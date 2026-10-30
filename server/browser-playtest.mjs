import { randomBytes } from 'node:crypto';
import { throwIfAborted } from './iteration.mjs';

const id = () => randomBytes(12).toString('hex');
const identity = ['clientId', 'commandId', 'runtimeSession', 'buildId', 'sourceRevision', 'kind', 'runId'];
const errorRow = message => ({ file: 'browser', line: 0, message, kind: 'error' });
const errorsOf = rows => (Array.isArray(rows) ? rows : []).slice(0, 80).map(row => ({ file: String(row?.file || 'browser').slice(0, 200), line: Number(row?.line) || 0, message: String(row?.message || row || '').slice(0, 1000), kind: row?.kind === 'warning' ? 'warning' : 'error' }));
const checksOf = rows => (Array.isArray(rows) ? rows : []).slice(0, 1000).filter(row => row && typeof row.ok === 'boolean' && typeof row.what === 'string' && row.what.trim()).map(row => ({ ok: row.ok, what: row.what.slice(0, 1000) }));
const imageOf = value => typeof value === 'string' && value.length <= 2 * 1024 * 1024 && /^[A-Za-z0-9+/=]*$/.test(value) ? value : '';

/** One project, one bound browser execution. A failed browser command never falls back.
 * Only small metadata is emitted; screenshots are returned with results for evidence. */
export class BrowserPlaytest {
  constructor(projectId, { emit = () => {}, clock = Date.now, leaseMs = 10000, timeoutMs = 45000, pollMs = 250 } = {}) {
    this.projectId = projectId; this.emit = emit; this.clock = clock;
    this.leaseMs = leaseMs; this.timeoutMs = timeoutMs; this.pollMs = pollMs;
    this.clients = new Map(); this.controls = new Map(); this.completed = new Map(); this.session = null; this.pending = null; this.generation = 0;
  }
  _client(clientId) { const c = this.clients.get(clientId); return c?.visible && c.supported && this.clock() - c.seenAt < this.leaseMs ? c : null; }
  get available() { return [...this.clients.keys()].some(clientId => this._client(clientId)); }
  get running() { return !!this.session?.running; }
  heartbeat(info = {}) {
    if (typeof info.clientId !== 'string' || !/^[A-Za-z0-9_-]{8,100}$/.test(info.clientId)) return { ok: false, error: '无效客户端标识' };
    for (const [key, c] of this.clients) if (this.clock() - c.seenAt > this.leaseMs * 3 && key !== this.session?.clientId) { this.clients.delete(key); this.controls.delete(key); }
    this.clients.set(info.clientId, { clientId: info.clientId, visible: info.visible === true, supported: info.supported === true, seenAt: this.clock() });
    if (this.session?.clientId === info.clientId && !this._client(info.clientId)) this._fail('验收浏览器已隐藏、退出或不再可用');
    return { ok: true, available: this.available };
  }
  next(clientId) {
    this._checkLease();
    if (this.pending?.command.clientId === clientId) return structuredClone(this.pending.command);
    return this.controls.has(clientId) ? structuredClone(this.controls.get(clientId)) : null;
  }
  _checkLease() {
    if (this.session?.running && !this._client(this.session.clientId)) this._fail('验收浏览器连接已断开');
  }
  _stopCommand(session) {
    if (!session) return;
    const command = { ...session, commandId: id(), kind: 'stop', payload: {}, createdAt: this.clock(), expiresAt: this.clock() + 30000 };
    delete command.running; delete command.project;
    this.controls.set(command.clientId, command); this.emit({ type: 'runtime_test', mode: 'browser', command });
  }
  _fail(message) {
    this.generation++;
    const pending = this.pending, session = this.session;
    this.session = null; this._stopCommand(session);
    if (pending) pending.finish(new Error(message));
  }
  stop() { this._fail('浏览器验收已停止或被替换'); }
  async _prepare(project, orientation, { signal, sourceRevision, runId = '' } = {}) {
    throwIfAborted(signal);
    this.stop();
    const generation = this.generation;
    const client = [...this.clients.values()].filter(c => this._client(c.clientId)).sort((a, b) => b.seenAt - a.seenAt)[0];
    if (!client) throw new Error('没有可用的可见浏览器验收客户端');
    const revision = project.revision();
    if (sourceRevision && sourceRevision !== revision) throw new Error('浏览器验收请求的源码版本已过期');
    let built = project.latestBuild;
    if (!built || built.sourceRevision !== revision) built = await project.build({ signal, sourceRevision: revision });
    throwIfAborted(signal);
    if (generation !== this.generation) throw new Error('浏览器验收准备已停止或被替换');
    if (!built || built.ok === false || !built.buildId || built.sourceRevision !== revision || project.revision() !== revision) throw new Error(built?.error || '当前源码没有匹配的不可变构建');
    if (!this._client(client.clientId)) throw new Error('浏览器在准备验收时断开');
    this.controls.delete(client.clientId);
    this.session = { clientId: client.clientId, runtimeSession: id(), buildId: built.buildId, sourceRevision: revision, runId: String(runId),
      orientation: orientation === 'portrait' ? 'portrait' : 'landscape', pckUrl: `/api/projects/${encodeURIComponent(this.projectId)}/game.pck?build=${encodeURIComponent(built.buildId)}`,
      running: true, project };
  }
  _command(kind, payload, { signal, timeoutMs = this.timeoutMs, step = '' } = {}) {
    throwIfAborted(signal); this._checkLease();
    if (!this.running) return Promise.reject(new Error('浏览器游戏未运行，请先 run_game'));
    if (this.pending) return Promise.reject(new Error('浏览器已有验收命令正在执行'));
    if (this.session.project.revision() !== this.session.sourceRevision) { this.stop(); return Promise.reject(new Error('源码已经改变，不能继续操作旧构建')); }
    const command = { ...this.session, commandId: id(), kind, step: String(step).slice(0, 180), payload, createdAt: this.clock(), expiresAt: this.clock() + timeoutMs };
    delete command.running; delete command.project;
    return new Promise((resolve, reject) => {
      const abort = () => this._fail('浏览器验收已取消');
      const timer = setInterval(() => {
        if (this.clock() >= command.expiresAt) this._fail('浏览器验收超时，未取得有效结果');
        else this._checkLease();
      }, this.pollMs);
      const finish = (error, result) => {
        if (this.pending?.command.commandId !== command.commandId) return;
        clearInterval(timer); signal?.removeEventListener('abort', abort); this.pending = null;
        if (error) reject(error); else resolve(result);
      };
      this.pending = { command, finish, startedAt: this.clock() };
      signal?.addEventListener('abort', abort, { once: true });
      this.emit({ type: 'runtime_test', mode: 'browser', command: structuredClone(command) });
    });
  }
  async startProject(project, orientation, opts = {}) {
    await this._prepare(project, orientation, opts);
    return this._command('run', { shot: true }, { ...opts, timeoutMs: opts.timeoutMs || 60000 });
  }
  eval(code, { shot = true, settle = .3, frames = 1, span = 1, signal, timeoutMs = 15000, step } = {}) {
    return this._command('eval', { code: String(code || ''), shot, settle, frames, span, timeoutMs }, { signal, timeoutMs: timeoutMs + 10000, step });
  }
  async selfTest(project, { orientation, signal, shot = true, sourceRevision, runId } = {}) {
    await this._prepare(project, orientation, { signal, sourceRevision, runId });
    return this._command('test', { shot, timeoutMs: this.timeoutMs }, { signal, timeoutMs: this.timeoutMs + 15000, step: '逐项检查玩法、失败与重开' });
  }
  receive(body = {}) {
    this._checkLease();
    const completed = this.completed.get(body.commandId);
    if (body.phase === 'result' && completed && identity.every(key => body[key] === completed[key])) return { ok: true, accepted: true, duplicate: true };
    if (body.kind === 'stop' && identity.every(key => this.controls.get(body.clientId)?.[key] === body[key])) return { ok: true, ignored: true };
    const pending = this.pending, command = pending?.command;
    if (!command || !identity.every(key => body[key] === command[key])) return { ok: false, error: '回执不属于当前客户端、会话、构建或命令' };
    if (!['progress', 'result'].includes(body.phase) || !body.data || typeof body.data !== 'object') return { ok: false, error: '无效执行回执' };
    if (this.clock() >= command.expiresAt || this.session?.project.revision() !== command.sourceRevision) { this._fail('验收回执已过期或源码已经改变'); return { ok: false, error: '过期执行回执' }; }
    const data = body.data, checks = checksOf(data.checks), errors = errorsOf(data.errors);
    const metrics = data.metrics && typeof data.metrics === 'object' ? Object.fromEntries(Object.entries(data.metrics).filter(([, v]) => Number.isFinite(v)).slice(0, 20)) : {};
    if (body.phase === 'progress') {
      this.emit({ type: 'runtime_test', mode: 'browser', phase: 'progress', runId: command.runId, commandId: command.commandId, runtimeSession: command.runtimeSession, clientId: command.clientId, buildId: command.buildId, sourceRevision: command.sourceRevision, kind: command.kind, checks, metrics });
      return { ok: true };
    }
    if (data.loaded !== true) errors.push(errorRow('浏览器未确认当前构建已载入'));
    if (command.kind === 'test' && (!data.has_test || !checks.length || !Array.isArray(data.checks) || checks.length !== data.checks.length)) errors.push(errorRow('auto_test 必须执行至少一条有效断言'));
    const result = { ...data, mode: 'browser', sourceRevision: command.sourceRevision, buildId: command.buildId, runtimeSession: command.runtimeSession,
      loaded: data.loaded === true, errors, checks, metrics, image: imageOf(data.image), image_end: imageOf(data.image_end),
      ms: this.clock() - pending.startedAt, assertionCount: checks.length };
    // The bounded display list must not hide a later failed assertion.
    const failedCheck = Array.isArray(data.checks) && data.checks.some(c => c && c.ok === false && typeof c.what === 'string' && c.what.trim());
    result.ok = data.ok === true && result.loaded && !errors.some(e => e.kind !== 'warning') && !failedCheck;
    if (!result.ok || command.kind === 'test') this.session.running = false;
    this.completed.set(command.commandId, Object.fromEntries(identity.map(key => [key, command[key]])));
    while (this.completed.size > 20) this.completed.delete(this.completed.keys().next().value);
    this.emit({ type: 'runtime_test', mode: 'browser', phase: 'result', runId: command.runId, commandId: command.commandId, runtimeSession: command.runtimeSession, clientId: command.clientId, buildId: command.buildId, sourceRevision: command.sourceRevision, kind: command.kind, ok: result.ok, checks, errors, metrics });
    pending.finish(null, result);
    return { ok: true, accepted: true };
  }
}
