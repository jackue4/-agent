import test, { after } from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { Readable, Writable } from 'node:stream';

const data = fs.mkdtempSync(path.join(os.tmpdir(), 'ugc-sketch-'));
process.env.UGC_DATA_DIR = data;
process.env.AIGATE_API_KEY = 'test-key';
fs.mkdirSync(path.join(data, 'projects'));
fs.mkdirSync(path.join(data, 'covers'));
const { SketchBoard, SketchArtist, normalizeItem, progressOf, boardSize, freeAreas } = await import('../sketch.mjs');
const api = await import('../server.mjs');
after(() => fs.rmSync(data, { recursive: true, force: true }));

const sleep = ms => new Promise(resolve => setTimeout(resolve, ms));
const size = boardSize('landscape');
const item = (id, extra = {}) => ({ id, t: 'rect', group: id, x: 100, y: 100, w: 80, h: 60, ...extra });

/** A model stand-in that streams one tool call in small JSON chunks, as the gateway does. */
function fakeStream(rounds, calls = []) {
  return async (messages, cb, signal, options) => {
    const input = rounds[calls.length] ?? rounds.at(-1);
    const board = options.board;
    calls.push({ messages, options, addsBefore: board?.state.items.length });
    if (input instanceof Error) throw input;
    if (input === 'hang') return new Promise((_, reject) => signal.addEventListener('abort', () => reject(signal.reason), { once: true }));
    const json = JSON.stringify(input);
    const seen = [];
    for (let at = 20; at < json.length + 20; at += 20) {
      if (signal.aborted) throw signal.reason;
      cb.onToolDelta?.('call', json.slice(0, at));
      seen.push(board?.state.items.length);
      await sleep(1);
    }
    calls.at(-1).seen = seen;
    return { content: [{ type: 'tool_use', id: 'call', name: 'sketch', input }], stop: 'tool_use' };
  };
}
function artist(rounds, extra = {}) {
  const board = new SketchBoard(null), calls = [], ops = [];
  const stream = fakeStream(rounds, calls);
  board.broadcast = op => ops.push(op);
  let clock = 0;
  const a = new SketchArtist({ board, prompt: '做一个跑酷游戏', model: 'm', orientation: 'landscape', stream: (m, cb, s, o) => stream(m, cb, s, { ...o, board }),
    now: () => (clock += 50), tickMs: 5, idleGapMs: 1e9, ...extra });
  return { a, board, calls, ops };
}

test('item normalization clamps to the paper and rejects unusable elements', () => {
  assert.deepEqual(normalizeItem({ id: 'Hero Box', t: 'rect', x: 990, y: -5, w: 300, h: 40, fill: 'hatch', color: '#FF0000', extra: 1 }, size),
    { id: 'hero_box', t: 'rect', color: '#ff0000', x: 990, y: 0, w: 10, h: 40, fill: 'hatch' });
  assert.deepEqual(normalizeItem({ id: 'g', t: 'line', pts: [[0, 10], [2000, 20]] }, size).pts, [0, 10, 1000, 20]);
  assert.equal(normalizeItem({ id: 's', t: 'shape', pts: [0, 0, 10, 10] }, size), null, 'a shape needs three points');
  assert.equal(normalizeItem({ id: 't', t: 'text', x: 1, y: 1, text: '  ' }, size), null);
  assert.equal(normalizeItem({ id: 'x', t: 'circle', x: 1, y: 1 }, size), null);
  assert.equal(normalizeItem({ t: 'text', x: 1, y: 1, text: '分数 0', size: 999 }, size, 'r1_0').size, 64);
  const note = normalizeItem({ id: 'jump_note', t: 'code', x: 900, y: 40, title: 'player.gd · 跳跃', lines: ['func jump():', '\tif on_floor:', '\t\tvy = -420', '', ''] }, size);
  assert.deepEqual(note.lines, ['func jump():', '  if on_floor:', '    vy = -420'], 'tabs become spaces and trailing blanks go');
  assert.equal(note.title, 'player.gd · 跳跃'); assert.equal(note.size, 14);
  assert.equal(normalizeItem({ id: 'empty', t: 'code', x: 1, y: 1, lines: ['  ', ''] }, size), null);
  assert.equal(normalizeItem({ id: 'long', t: 'code', x: 1, y: 1, lines: Array(30).fill('x'.repeat(90)) }, size).lines.length, 10);
  assert.deepEqual(normalizeItem({ id: 'map2', t: 'card', x: 600, y: 300, w: 320, h: 200, title: '关卡 2：蘑菇坡', fill: 'hatch' }, size), { id: 'map2', t: 'card', x: 600, y: 300, w: 320, h: 200, title: '关卡 2：蘑菇坡' });
  assert.equal(normalizeItem({ id: 'tiny', t: 'card', x: 1, y: 1, w: 30, h: 20 }, size), null, 'a card must hold a drawing');
});

test('free areas name the blank parts of the paper and ignore page frames', () => {
  const frame = item('frame', { x: 0, y: 0, w: 1000, h: 562 });
  const ground = item('ground', { t: 'line', pts: [0, 400, 1000, 400] });
  const hero = item('hero', { x: 40, y: 220, w: 160, h: 140 });
  const free = freeAreas([frame, ground, hero], size);
  assert.ok(!free.some(a => a.startsWith('中左')), 'the hero cell is used');
  assert.ok(free.some(a => a.startsWith('上右')), 'the empty top right is offered');
  assert.equal(free.length, 11, 'a thin ground line and the page frame use no cells');
  const full = Array.from({ length: 12 }, (_, i) => item('b' + i, { x: (i % 4) * 250 + 10, y: Math.floor(i / 4) * 187 + 10, w: 200, h: 150 }));
  assert.deepEqual(freeAreas(full, size), []);
});

test('a restored board is never shown as still drawing', () => {
  const board = new SketchBoard({ phase: 'drawing', items: [item('a'), { id: 'bad', t: 'nope' }], w: 562, h: 1000 });
  assert.equal(board.state.phase, 'stopped'); assert.equal(board.state.items.length, 1); assert.equal(board.state.w, 562);
});

test('strokes reach the board while the tool call is still streaming, in drawing order', async () => {
  const items = Array.from({ length: 6 }, (_, i) => item('part' + i, { x: 50 + i * 100 }));
  const { a, board, calls, ops } = artist([{ note: '先勾出赛道和主角', items }], { maxRounds: 1 });
  a.start();
  await sleep(5);
  a.observe({ type: 'turn_end', status: 'completed' });
  assert.equal(await a.done, 'done');
  assert.deepEqual(ops.slice(0, 3).map(op => op.op), ['begin', 'round', 'note']);
  assert.deepEqual(ops.filter(op => op.op === 'add').slice(0, 6).map(op => op.item.id), items.map(i => i.id));
  const seen = calls[0].seen;
  assert.ok(seen.some(n => n > 0 && n < items.length), 'some items were drawn before the model finished: ' + seen.join(','));
  assert.equal(board.state.items.length, 6);
  assert.equal(board.state.phase, 'done');
  assert.match(calls[0].messages[0].content[0].text, /做一个跑酷游戏/);
  assert.equal(calls[0].options.req.tool_choice.type, 'any', 'a named tool is incompatible with thinking models');
  assert.deepEqual(calls[0].options.req.thinking, { type: 'disabled' });
});

test('a model that rejects the thinking switch is retried once without it', async () => {
  const refusal = Object.assign(new Error('AI 服务返回 400：thinking not supported'), { status: 400 });
  const { a, calls, board } = artist([refusal, { note: '画', items: [item('a')] }], { maxRounds: 1 });
  a.start();
  while (calls.length < 2 || board.state.phase === 'drawing') await sleep(2);
  assert.deepEqual(calls[0].options.req.thinking, { type: 'disabled' });
  assert.equal('thinking' in calls[1].options.req, false);
  assert.equal(board.state.items.length, 1);
  a.stop();
});

test('builder progress triggers a revision that sees the design and the current drawing', async () => {
  const { a, board, calls } = artist([
    { note: '第一稿', items: [item('hero'), item('ground', { t: 'line', pts: [0, 500, 1000, 500] })] },
    { note: '按方案修改', erase: ['ground', 'unknown'], items: [item('hud', { t: 'text', text: '分数 0', x: 20, y: 20 })] },
    { note: '最后一稿', items: [item('done', { t: 'text', text: '✓ 已做好', x: 300, y: 20 })] },
  ]);
  a.start();
  a.observe({ type: 'design', design: { title: '霓虹跑者', genre: '跑酷', core_loop: '跳跃躲避', layout: '底部赛道，顶部分数', palette: ['#112233'] } });
  a.observe({ type: 'code_write', file: 'main.gd', step: '核心骨架' });
  a.observe({ type: 'code_write', file: 'main.gd', step: '又一次' });
  while (calls.length < 2) await sleep(2);
  a.observe({ type: 'turn_end', status: 'ready', summary: '可以跳跃了' });
  assert.equal(await a.done, 'done');
  const second = calls[1].messages[0].content[0].text;
  assert.match(second, /霓虹跑者/); assert.match(second, /hero \| rect/); assert.match(second, /保存了 main\.gd/);
  assert.equal(second.match(/保存了 main\.gd/g).length, 1, 'repeated saves of one file are reported once');
  assert.match(calls.at(-1).messages[0].content[0].text, /主 AI 已结束本轮/);
  assert.deepEqual(board.state.items.map(i => i.id).sort(), ['done', 'hero', 'hud']);
  assert.equal(board.state.round, 3);
});

test('the first real screenshot is sent as an image, and an image refusal falls back to text', async () => {
  const shots = [];
  const { a, calls } = artist([new Error('image not supported'), { note: '对照截图', items: [item('a')] }], {
    readImage: url => { shots.push(url); return 'BASE64'; }, maxRounds: 1,
  });
  a.observe({ type: 'eval', ok: true, step: '跳上平台', shot: '/covers/p_t1.jpg' });
  a.start();
  await sleep(5);
  a.observe({ type: 'turn_end', status: 'completed' });
  await a.done;
  assert.deepEqual(shots, ['/covers/p_t1.jpg']);
  assert.equal(calls[0].messages[0].content.at(-1).type, 'image');
  assert.equal(calls[1].messages[0].content.length, 1, 'retry is text only');
  assert.equal(progressOf({ type: 'eval', shot: 'http://elsewhere/x.jpg' }, { shots: 0 }).shot, '', 'only local covers are read');
});

test('model failures stay on the board and never escape into the build', async () => {
  const { a, board, calls } = artist([new Error('gateway 500')]);
  a.start();
  while (board.state.phase !== 'failed') await sleep(2);
  assert.match(board.state.message, /不影响游戏制作/);
  assert.equal(a.stopped, false, 'one failed sketch round waits for the next progress');
  a.observe({ type: 'turn_end', status: 'completed' });
  assert.equal(await a.done, 'failed');
  assert.equal(calls.length, 2); assert.equal(board.state.phase, 'failed');
});

test('without new progress the artist keeps drawing the agenda until the builder ends', async () => {
  const { a, ops, calls } = artist([{ note: '画', items: [item('a')] }], { idleGapMs: 0, maxRounds: 4 });
  a.start();
  while (calls.length < 4) await sleep(2);
  await sleep(10);
  assert.equal(calls.length, 4, 'the round budget caps the idle rounds');
  assert.equal(a.stopped, false, 'it waits for turn_end instead of finishing early');
  assert.deepEqual(ops.filter(op => op.op === 'round').map(op => op.task), ['first', 'level', 'notes', 'level'], 'code notes wait until the builder writes a file');
  assert.match(calls[1].messages[0].content[0].text, /本稿任务【关卡】/);
  a.observe({ type: 'turn_end', status: 'completed' });
  assert.equal(await a.done, 'done');
  assert.equal(calls.length, 5); assert.match(calls[4].messages[0].content[0].text, /最后一稿/);
});

test('code notes follow the file the builder is writing, and the activity line updates without the model', async () => {
  const { a, ops, calls, board } = artist([{ note: '画', items: [item('a')] }], { idleGapMs: 0, maxRounds: 3, activityMs: 30, now: Date.now });
  a.observe({ type: 'tool_start', name: 'write_file' });
  assert.equal(board.state.activity, '正在写代码');
  a.observe({ type: 'tool_progress', name: 'write_file', file: 'player.gd', step: '跳跃', total: 12 });
  assert.equal(board.state.activity, '正在写 player.gd · 跳跃 · 已写 12 行', 'a new file shows at once');
  a.observe({ type: 'tool_progress', name: 'write_file', file: 'player.gd', step: '跳跃', total: 20 });
  assert.equal(board.state.activity, '正在写 player.gd · 跳跃 · 已写 12 行', 'line counts are throttled');
  await sleep(50);
  assert.equal(board.state.activity, '正在写 player.gd · 跳跃 · 已写 20 行', 'the latest count lands after the throttle');
  a.start();
  while (calls.length < 3) await sleep(2);
  const tasks = ops.filter(op => op.op === 'round').map(op => op.task);
  assert.deepEqual(tasks, ['first', 'level', 'code']);
  assert.match(calls[2].messages[0].content[0].text, /主 AI 正在写：player\.gd（跳跃）/);
  assert.match(calls[2].messages[0].content[0].text, /正在写代码/, 'recent actions are part of the brief');
  a.observe({ type: 'turn_end', status: 'completed' });
  assert.equal(await a.done, 'done');
  assert.equal(board.state.activity, '', 'the activity line clears when the builder ends');
});

test('a model that goes quiet is replaced by the next round, and the work log keeps the paper moving meanwhile', async () => {
  const { a, board, calls } = artist(['hang', { note: '画', items: [item('a')] }], { idleGapMs: 0, firstStrokeMs: 1500, logAfterMs: 0, maxRounds: 2 });
  a.observe({ type: 'tool_start', name: 'write_file' });
  a.observe({ type: 'tool_start', name: 'run_game' });
  a.start();
  while (!board.state.items.some(i => i.id === 'worklog')) await sleep(2);
  assert.deepEqual(board.state.items.find(i => i.id === 'worklog').lines, ['✓ 写代码', '▶ 启动游戏实测']);
  while (calls.length < 2 || !board.state.items.some(i => i.id === 'a')) await sleep(2);
  assert.equal(a.failures, 0, 'a stall is not a failure');
  assert.notEqual(board.state.phase, 'failed');
  a.observe({ type: 'turn_end', status: 'completed' });
  assert.equal(await a.done, 'done');
});

test('a model that never reaches its first stroke in time is swapped for the fallback after two rounds', async () => {
  const { a, board, calls } = artist(['hang', 'hang', { note: '画', items: [item('a')] }], { idleGapMs: 0, firstStrokeMs: 300, logAfterMs: 0, maxRounds: 3, model: 'slow-model', fallbackModel: 'fast-model' });
  a.start();
  while (!board.state.items.some(i => i.id === 'a')) await sleep(2);
  assert.deepEqual(calls.map(c => c.options.req.model), ['slow-model', 'slow-model', 'fast-model']);
  assert.equal(a.failures, 0);
  a.observe({ type: 'turn_end', status: 'completed' });
  assert.equal(await a.done, 'done');
});

test('a crowded board is thinned out a little per round, never wiped at once', async () => {
  const old = Array.from({ length: 80 }, (_, i) => item('old' + i));
  const { a, board } = artist([{ note: '整理', erase: old.map(i => i.id), items: [item('fresh')] }], { maxRounds: 1, keep: true });
  for (const it of old) board.apply({ op: 'add', item: normalizeItem(it, size) });
  a.start();
  while (!board.state.items.some(i => i.id === 'fresh')) await sleep(2);
  assert.equal(board.state.items.filter(i => i.id.startsWith('old')).length, 50);
  a.stop();
});

test('stopping the round aborts the artist mid-stroke', async () => {
  const parent = new AbortController();
  const many = Array.from({ length: 40 }, (_, i) => item('p' + i));
  const { a, board, calls } = artist([{ note: '慢慢画', items: many }], { signal: parent.signal });
  a.start();
  await sleep(4);
  parent.abort(new Error('user stop'));
  assert.equal(await a.done, 'stopped');
  const drawn = board.state.items.length;
  await sleep(20);
  assert.equal(board.state.items.length, drawn); assert.ok(drawn < many.length);
  assert.equal(calls.length, 1); assert.equal(board.state.phase, 'stopped');
});

class Response extends Writable {
  constructor() { super(); this.parts = []; this.done = new Promise(resolve => this.on('finish', resolve)); }
  _write(chunk, _encoding, cb) { this.parts.push(Buffer.from(chunk)); cb(); }
  writeHead(status, headers) { this.statusCode = status; this.headers = headers; }
  flushHeaders() {}
}

test('a real production round runs the artist in parallel and serves the sketch over HTTP', async () => {
  const p = new api.Project({}); p.game.meta.engine = 'godot';
  api.projects.set(p.id, p);
  const gp = api.gpOf(p);
  fs.mkdirSync(gp.dir, { recursive: true });
  gp.write('project.godot', 'config_version=5\n'); gp.write('main.gd', 'extends Node\n');
  const calls = [];
  let artistDuringBuild = null, boardDuringBuild = 0;
  const sketchStream = fakeStream([{ note: '第一稿', items: [item('hero')] }, { note: '按方案改', items: [item('hud', { t: 'text', text: '分数', x: 10, y: 10 })] }], calls);
  await api.runCodeChat(p, '做一个跳跃小游戏', {}, { live: { stop() {} }, sketchStream, runProjectBuilder: async args => {
    artistDuringBuild = p.sketchArtist;
    while (!calls.length) await sleep(2);
    args.hooks.onDesign({ title: '跳跳', genre: '平台', core_loop: '跳', layout: '底部地面', palette: [], assets: [] });
    while (calls.length < 2) await sleep(2);
    boardDuringBuild = api.sketchBoardOf(p).state.items.length;
    return { session: { changed: new Set(), finish: null }, out: { done: true } };
  } });
  assert.ok(artistDuringBuild, 'the artist started before the builder returned');
  assert.ok(boardDuringBuild >= 1, 'strokes were on the board while the builder was still working');
  await artistDuringBuild.done;
  assert.equal(p.sketchArtist, null);
  assert.match(calls[1].messages[0].content[0].text, /跳跳/);
  assert.equal(calls[0].options.req.model, 'gpt-5.4-mini', 'the sketch keeps its own model, independent of the builder model');
  const saved = JSON.parse(fs.readFileSync(p.file(), 'utf8')).sketch;
  assert.equal(saved.phase, 'done'); assert.ok(saved.items.some(i => i.id === 'hero'));
  assert.equal(p.log.some(e => e.type === 'sketch'), false, 'strokes stay out of the workflow event log');

  const snapshot = new Response();
  await api.requestHandler(Object.assign(Readable.from([]), { url: '/api/projects/' + p.id + '/sketch', method: 'GET', headers: {} }), snapshot);
  await snapshot.done;
  assert.equal(JSON.parse(Buffer.concat(snapshot.parts).toString()).items.length, saved.items.length);

  const req = Object.assign(Readable.from([]), { url: '/api/projects/' + p.id + '/sketch?stream=1', method: 'GET', headers: {} });
  const stream = new Response();
  await api.requestHandler(req, stream);
  const first = Buffer.concat(stream.parts).toString().split('\n\n').find(block => block.startsWith('data: '));
  assert.equal(JSON.parse(first.slice(6)).op, 'snapshot');
  api.sketchBoardOf(p).apply({ op: 'note', note: '实时' });
  assert.match(Buffer.concat(stream.parts).toString(), /"op":"note","note":"实时"/);
  req.emit('close');
  assert.equal(api.sketchBoardOf(p).clients.size, 0);
});
