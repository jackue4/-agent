// Plays a 2D platformer project to the goal with the runtime autoplay bot (runtime/bot2d.gd),
// following the critical path from the server's reachability check. Exit 0 = the bot won.
// Usage: node test/bot_play.mjs <projectId> [--window]
import { spawnSync } from 'node:child_process';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { godotBin } from '../server/godot.mjs';

const BASE = process.env.UGC_BASE || 'http://10.0.4.94:5300';
const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const godot = godotBin();
const id = process.argv[2];
if (!id) { console.error('usage: node test/bot_play.mjs <projectId>'); process.exit(64); }

const get = async p => { const r = await fetch(BASE + '/api' + p); if (!r.ok) throw new Error(p + ' ' + r.status); return r.json(); };
const proj = await get('/projects/' + id);
const chk = await get('/projects/' + id + '/check');
if (proj.game.meta.dimension !== '2d') { console.log('skip: bot drives 2D platformers only'); process.exit(0); }
if (!chk.path || !chk.path.criticalPath || !chk.path.criticalPath.length) { console.log('skip: no critical path (topdown or no goal)'); process.exit(0); }
const ids = [...chk.path.criticalPath, chk.path.target].filter(Boolean);

const assets = {};
for (const [k, a] of Object.entries(proj.game.assets || {})) assets[k] = { kind: a.kind, state: a.state, url: a.url && a.url.startsWith('/') ? BASE + a.url : a.url };
const specFile = path.join(os.tmpdir(), 'ugc_bot_' + id + '.json');
fs.writeFileSync(specFile, JSON.stringify({ spec: proj.game, assets }));

const args = ['--path', path.join(root, 'runtime'), '--resolution', '1280x720'];
if (!process.argv.includes('--window')) args.unshift('--headless');
args.push('--', '--spec=' + specFile, '--play', '--bot=' + ids.join(','));
const r = spawnSync(godot, args, { encoding: 'utf8', timeout: 180000 });
const out = (r.stdout || '') + (r.stderr || '');
const line = out.split(/\r?\n/).find(l => l.startsWith('[bot]'));
const errs = out.split(/\r?\n/).filter(l => /SCRIPT ERROR/.test(l));
console.log(proj.game.meta.title, '| path', ids.join(' > '));
console.log(line || '[bot] no result (exit ' + r.status + ')');
errs.slice(0, 5).forEach(e => console.log('  ' + e));
process.exit(line && line.includes('result=win') && !errs.length ? 0 : 1);
