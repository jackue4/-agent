// Live Godot session for the code agent: the AI's game keeps running in a real window, and the
// agent executes GDScript snippets against it (game_eval) and looks at screenshots at any moment -
// the same loop a developer uses in the editor. The runtime side is main.gd `_live_loop`: the
// server drops numbered cmd_<n>.json files into a temp dir and waits for res_<n>.json.
import { spawn } from 'node:child_process';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { ROOT, godotBin } from './godot.mjs';
import { stderrErrors, throwIfAborted } from './gproject.mjs';
import { startWatchFrames } from './watch-frames.mjs';

const RUNTIME = path.join(ROOT, 'runtime');
const READY_TIMEOUT_MS = 25000;
const POLL_MS = 60;

const sleep = ms => new Promise(r => setTimeout(r, ms));
const readJson = f => { try { return JSON.parse(fs.readFileSync(f, 'utf8')); } catch { return null; } };
const readShot = f => { try { return f && fs.existsSync(f) ? fs.readFileSync(f).toString('base64') : ''; } catch { return ''; } };

export class LiveGame {
  constructor({ spawnProcess = spawn, cleanupDelayMs = 1500 } = {}) {
    this.ch = null; this.dir = null; this.n = 0; this.log = ''; this.exited = false;
    this._spawn = spawnProcess; this._cleanupDelayMs = cleanupDelayMs;
    this._generation = 0; this._abortCleanup = null; this._watchReader = null;
  }

  get running() { return !!this.ch && !this.exited; }

  /** (Re)starts the game with these files in play mode. Returns { loaded, errors, image, state }. */
  async start(files, meta = {}, { signal } = {}) {
    throwIfAborted(signal);
    this.stop();
    const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'ugc-live-'));
    const spec = path.join(dir, 'spec.json');
    fs.writeFileSync(spec, JSON.stringify({ spec: { meta: { ...meta, engine: 'code', dimension: '2d' }, code: { files } }, assets: {} }));
    const res = meta.orientation === 'portrait' ? '540x960' : '1280x720';
    const godotDir = dir.replace(/\\/g, '/');
    const args = ['--path', RUNTIME, '--audio-driver', 'Dummy', '--resolution', res, '--position', '40,40', '--', '--spec=' + spec, '--play', '--live=' + godotDir];
    return this._launch(dir, args, RUNTIME, signal);
  }

  /** (Re)starts a full Godot project (server/gproject.mjs) whose UGC plugin serves the same channel. */
  async startProject(project, orientation, { signal, onFrame } = {}) {
    throwIfAborted(signal);
    this.stop();
    const generation = this._generation;
    await project.ready({ signal });
    throwIfAborted(signal);
    if (generation !== this._generation) throw new Error('试玩启动已停止或被替换');
    const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'ugc-live-'));
    const args = project.liveArgs(dir.replace(/\\/g, '/'), orientation);
    if (typeof onFrame === 'function') args.push('--ugc-watch=' + dir.replace(/\\/g, '/'));
    return this._launch(dir, args, project.dir, signal, onFrame);
  }

  async _launch(dir, args, cwd, signal, onFrame) {
    throwIfAborted(signal);
    this.dir = dir; this.n = 0; this.log = ''; this.exited = false;
    let ch;
    try { ch = this._spawn(process.env.GODOT_BIN || godotBin(), args, { cwd, windowsHide: true }); }
    catch (error) { this.stop(); throw error; }
    this.ch = ch;
    const reader = startWatchFrames(dir, { onFrame, signal, isCurrent: () => this.ch === ch && !this.exited });
    this._watchReader = reader;
    const keep = d => { if (this.ch !== ch) return; this.log += d; if (this.log.length > 200000) this.log = this.log.slice(-100000); };
    ch.stdout.on('data', keep);
    ch.stderr.on('data', keep);
    const abort = () => { if (this.ch === ch) this.stop(); };
    const detach = () => signal?.removeEventListener('abort', abort);
    this._abortCleanup = detach;
    ch.on('close', () => { detach(); reader.stop(); this._cleanDir(dir); if (this.ch === ch) this.exited = true; });
    ch.on('error', e => { detach(); reader.stop(); this._cleanDir(dir); if (this.ch === ch) { this.exited = true; this.log += '\n' + e.message; } });
    signal?.addEventListener('abort', abort, { once: true });
    let r;
    try { r = await this.waitFile(path.join(dir, 'ready.json'), READY_TIMEOUT_MS, { signal, child: ch }); throwIfAborted(signal); }
    catch (error) { if (this.ch === ch) this.stop(); throw error; }
    if (!r) {
      const fromLog = stderrErrors(this.log).slice(0, 10);
      const why = { file: 'main', line: 0, message: this.exited ? '游戏进程启动后退出了' : '游戏启动超时', kind: 'error' };
      if (this.ch === ch) this.stop();
      return { loaded: false, errors: fromLog.length ? fromLog : [why], image: '', state: {} };
    }
    await reader.flush();
    throwIfAborted(signal);
    if (this.ch !== ch) throw new Error('试玩启动已停止或被替换');
    return { loaded: !!r.loaded, errors: r.errors || [], image: readShot(r.shot), state: r.state || {} };
  }

  /** Runs one snippet (body of `func run(game, G)` / `func run(game)`). Returns { ok, value, errors, image, state }.
   *  frames > 1: the screenshot is a strip of that many frames spread over `span` seconds. */
  async eval(code, { shot = true, settle = 0.3, timeoutMs = 15000, frames = 1, span = 1, signal } = {}) {
    return this.cmd({ type: 'eval', code: String(code || ''), shot, settle, timeout_ms: timeoutMs, frames, span }, timeoutMs + 8000 + span * 1000, { signal });
  }

  async shot({ signal } = {}) { return this.cmd({ type: 'shot', shot: true, settle: 0.05 }, 8000, { signal }); }

  async cmd(obj, waitMs, { signal } = {}) {
    throwIfAborted(signal);
    if (!this.running) return { ok: false, errors: [{ file: 'main.gd', line: 0, message: '游戏没有在运行（先调用 run_game；游戏也可能已经崩溃退出）', kind: 'error' }], image: '', state: {} };
    const child = this.ch;
    const reader = this._watchReader;
    const id = ++this.n;
    const f = path.join(this.dir, 'cmd_' + id + '.json');
    fs.writeFileSync(f + '.tmp', JSON.stringify(obj));
    fs.renameSync(f + '.tmp', f);
    const abort = () => { if (this.ch === child) this.stop(); };
    signal?.addEventListener('abort', abort, { once: true });
    let r;
    try { r = await this.waitFile(path.join(this.dir, 'res_' + id + '.json'), waitMs, { signal, child }); throwIfAborted(signal); }
    catch (error) { if (this.ch === child) this.stop(); throw error; }
    finally { signal?.removeEventListener('abort', abort); }
    if (!r) {
      const crashed = this.exited;
      if (this.ch === child) this.stop();
      return { ok: false, errors: [{ file: 'eval', line: 0, message: crashed ? '游戏进程崩溃退出了，请 run_game 重新启动' : '游戏没有响应（可能卡死），已关闭，请 run_game 重新启动', kind: 'error' }], image: '', state: {} };
    }
    await reader?.flush();
    throwIfAborted(signal);
    if (this.ch !== child) throw new Error('试玩执行已停止或被替换');
    return { ok: r.ok !== false, value: r.value, errors: r.errors || [], image: readShot(r.shot), state: r.state || {} };
  }

  async waitFile(file, ms, { signal, child = this.ch } = {}) {
    const t0 = Date.now();
    while (Date.now() - t0 < ms) {
      throwIfAborted(signal);
      if (child !== this.ch) return null;
      if (fs.existsSync(file)) { const j = readJson(file); if (j) return j; }
      if (this.exited) return fs.existsSync(file) ? readJson(file) : null;
      await sleep(POLL_MS);
    }
    return null;
  }

  stop() {
    this._generation++;
    this._watchReader?.stop(); this._watchReader = null;
    this._abortCleanup?.(); this._abortCleanup = null;
    if (this.ch && !this.exited) { try { this.ch.kill(); } catch { /* already gone */ } }
    this.ch = null; this.exited = true;
    this._cleanDir(this.dir);
    this.dir = null;
  }

  _cleanDir(dir) {
    if (dir) {
      const d = path.resolve(dir);
      if (path.dirname(d) === path.resolve(os.tmpdir()) && path.basename(d).startsWith('ugc-live-')) {
        setTimeout(() => { try { fs.rmSync(d, { recursive: true, force: true }); } catch { /* process may still be closing */ } }, this._cleanupDelayMs).unref();
      }
    }
  }
}
