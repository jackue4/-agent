import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { runInNewContext } from 'node:vm';
import { webcrypto } from 'node:crypto';

const helpers = await readFile(new URL('../web/workflow-view.js', import.meta.url), 'utf8');
const view = await import('data:text/javascript;base64,' + Buffer.from(helpers).toString('base64'));
const inworldSource = await readFile(new URL('../web/inworld-workflow.js', import.meta.url), 'utf8');
const inworld = await import('data:text/javascript;base64,' + Buffer.from(inworldSource).toString('base64'));
const constructionSource = await readFile(new URL('../web/construction-view.js', import.meta.url), 'utf8');
const construction = await import('data:text/javascript;base64,' + Buffer.from(constructionSource).toString('base64'));
const playtestSource = await readFile(new URL('../web/playtest-view.js', import.meta.url), 'utf8');
const playtest = await import('data:text/javascript;base64,' + Buffer.from(playtestSource).toString('base64'));
const browserSource = await readFile(new URL('../web/browser-playtest.js', import.meta.url), 'utf8');
const browserPlaytest = await import('data:text/javascript;base64,' + Buffer.from(browserSource).toString('base64'));
const participationSource = await readFile(new URL('../web/participation-view.js', import.meta.url), 'utf8');
const participationView = await import('data:text/javascript;base64,' + Buffer.from(participationSource).toString('base64'));
const modelSource = await readFile(new URL('../web/model-selection.js', import.meta.url), 'utf8');
const modelView = await import('data:text/javascript;base64,' + Buffer.from(modelSource).toString('base64'));
const editor = (await readFile(new URL('../web/editor.js', import.meta.url), 'utf8')).replace(/^import .*;\r?\n/gm, '')
  + '\n globalThis.editorTest = { getSketch: () => sketch, handle, onRuntime, setMode, layout, setChat, renderClock, renderWorkflow, pollWatch, renderPlaytest, saveSceneMove, send, browserTests, getProject: () => proj, getWatch: () => playtestState.watch, getExpected: () => previewExpected, getMode: () => mode, getWorkflow: () => workflow };';

// A DOM/transport harness executes the real entry point without a browser, model call,
// or platform mutation. Layout and visual appearance still require browser acceptance.
async function boot({ chat = [], go = '', remix = false, status = 'running', tier = 'demo', pck = '/packs/old.pck', iteration = null, engine = 'godot', dimension = '2d', snapshot = null, watch = null, sceneDirty = false, sceneSourceRevision = '', sceneEditResult = null, sceneBuildResult = null, design = {}, participation = [], participationDelivery = 'live', participationResponse = null, model = 'choice-b', modelResponse = null } = {}) {
  const nodes = new Map(), listeners = new Map(), requests = [], reloads = [], intervals = [], focuses = [], sent = [], timers = new Map(), images = [];
  let timerId = 0;
  const makeNode = id => {
    const classes = new Set();
    return { id, contentWindow: {}, dataset: {}, hidden: false, open: false, value: '', innerHTML: '', textContent: '', children: [], scrollTop: 0, scrollHeight: 36, clientWidth: 900, clientHeight: 560, offsetHeight: 32,
      style: { setProperty() {} }, classList: { add(...items) { items.forEach(x => classes.add(x)); }, remove(x) { classes.delete(x); }, contains(x) { return classes.has(x); }, toggle(x, force) { const on = force ?? !classes.has(x); if (on) classes.add(x); else classes.delete(x); return on; } },
      setAttribute(k, v) { this[k] = String(v); }, removeAttribute(k) { delete this[k]; }, replaceWith(n) { nodes.set(this.id.startsWith('#') ? this.id : '#' + this.id, n); }, addEventListener() {}, appendChild(n) { this.children.push(n); n.parentElement = this; }, replaceChildren(...items) { this.children = items; }, remove() {}, focus() { focuses.push(id); },
      get childElementCount() { return this.children.length; }, querySelector() { return makeNode('child'); }, closest() { return null; } };
  };
  const $ = (selector, parent) => { if (parent) return parent.querySelector(selector); if (!nodes.has(selector)) nodes.set(selector, makeNode(selector)); return nodes.get(selector); };
  $('#iterationTier').value = 'demo'; $('#feed').hidden = true; $('#improvementOptions').hidden = true;
  $('#rt').src = $('#testRt').src = 'about:blank';
  const modes = ['edit', 'play'].map(m => { const n = makeNode(m); n.dataset.m = m; return n; });
  const project = { id: 'fixture', model, seq: 7, running: status === 'running', pck, sceneDirty, sceneSourceRevision, participation, participationDelivery, build: { buildId: 'old', sourceRevision: 'r1', version: 1 },
    game: { meta: { title: '测试', engine, dimension }, entities: {}, assets: {}, design, ...(snapshot ? { construction: snapshot } : {}) }, chat, versions: [],
    workflow: { id: 'run-1', status, goal: '先做一个可玩的房间', startedAt: 1000, updatedAt: 2000, tasks: [], evidence: [], issues: [], activity: [], ...(iteration ? { iteration } : {}) } };
  const context = { ...view, ...inworld, ...construction, ...playtest, ...browserPlaytest, ...participationView, ...modelView, $, $$: selector => selector === '#modeSeg button' ? modes : [], api: async (path, opts = {}) => {
    requests.push({ path, ...opts });
    if (path === '/models') return { models: [{ id: 'choice-a', label: 'A' }, { id: 'choice-b', label: 'B' }, { id: 'choice-c', label: 'C' }, { id: 'choice-d', label: 'D' }], defaultModel: 'choice-a' };
    if (path === '/projects/fixture/model') { const result = modelResponse ? await modelResponse(opts.body) : { ok: true, model: opts.body.model }; if (result?.ok) project.model = result.model; return result; }
    if (path.endsWith('/watch')) return typeof watch === 'function' ? await watch() : structuredClone(watch);
    if (path.endsWith('/scene-build')) return sceneBuildResult || { ok: false, error: '构建失败' };
    return path.endsWith('/events?since=7') ? { events: [], seq: 7 } : path === '/projects/fixture' ? structuredClone(project) : { ok: true };
  }, fetch: (url, options) => {
    requests.push({ path: url.replace(/^\/api/, ''), ...options });
    if (url.includes('/runtime-')) return Promise.resolve({ ok: true, json: async () => null });
    if (url.endsWith('/participation')) return Promise.resolve().then(async () => { const result = typeof participationResponse === 'function' ? await participationResponse(JSON.parse(options.body)) : participationResponse; return { ok: result?.ok === true, json: async () => result || { ok: false, error: '未收到建议' } }; });
    if (url.endsWith('/scene-edit')) return Promise.resolve({ ok: sceneEditResult?.ok === true, json: async () => sceneEditResult || { ok: false, error: '冲突', snapshot } });
    if (url.endsWith('/scene-build')) return Promise.resolve({ ok: sceneBuildResult?.ok === true, json: async () => sceneBuildResult || { ok: false, error: '构建失败' } });
    if (url === '/api/projects/fixture') return Promise.resolve({ ok: true, json: async () => structuredClone(project) });
    return new Promise((resolve, reject) => {
      const abort = () => reject(new Error('aborted'));
      options.signal.addEventListener('abort', abort, { once: true });
      Promise.resolve(typeof watch === 'function' ? watch(options.signal) : structuredClone(watch)).then(value => {
        options.signal.removeEventListener('abort', abort);
        if (!options.signal.aborted) resolve({ ok: true, json: async () => value });
      }, reject);
    });
  }, AbortController, esc: value => String(value ?? '').replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('"', '&quot;'), toast() {}, ago() { return '刚刚'; }, uuid: () => webcrypto.randomUUID(),
  Runtime: class { constructor() { this.ready = false; } send(message) { sent.push(message); } reload(src) { reloads.push(src); } focus() { focuses.push('runtime'); } snapshot() { return Promise.resolve(null); } },
  SketchBoardView: class { constructor(_root, hooks) { this.hooks = hooks; this.view = 'hidden'; this.live = false; this.content = false; this.views = []; this.connected = []; } connect(id) { this.connected.push(id); } close() {} hasContent() { return this.content; } setView(view, options) { this.view = view; this.views.push({ view, ...options }); } setMaker(text) { this.maker = text; } },
  location: { search: '?id=fixture&tier=' + tier + (go ? '&go=' + encodeURIComponent(go) : '') + (remix ? '&remix=1' : ''), origin: 'http://local' }, document: { title: '', visibilityState: 'visible', body: makeNode('body'), documentElement: makeNode('html'), createElement(type) { const node = makeNode('created'); if (type === 'img') images.push(node); return node; }, addEventListener(name, fn) { listeners.set('document:' + name, fn); } },
  history: { replaceState() {} }, URLSearchParams, crypto: webcrypto, console, innerHeight: 720, screen: {},
  addEventListener(name, fn) { listeners.set(name, fn); }, setInterval(fn) { intervals.push(fn); return intervals.length; }, clearInterval() {}, setTimeout(fn, delay) { timers.set(++timerId, { fn, delay }); return timerId; }, clearTimeout(id) { timers.delete(id); }, queueMicrotask, requestAnimationFrame(fn) { fn(); },
  ResizeObserver: class { observe() {} }, EventSource: class { close() {} } };
  context.window = context;
  runInNewContext(editor, context, { filename: 'editor.js' });
  await new Promise(resolve => setImmediate(resolve));
  await new Promise(resolve => setImmediate(resolve));
  return { context, nodes, $, requests, reloads, focuses, intervals, sent, timers, images, listeners };
}

const watchSnapshot = (sessionId = 'watch-a', frameSeq = 1, extra = {}) => ({ sessionId, runId: 'run-1', sourceRevision: 'r1', kind: 'eval', step: '向右移动', status: frameSeq ? 'live' : 'starting', frameSeq, frameUrl: frameSeq ? '/api/projects/fixture/watch/frame?session=' + sessionId + '&seq=' + frameSeq : '', capturedAt: frameSeq ? Date.now() : 0, updatedAt: Date.now(), checks: [], errors: [], ...extra });
const moduleDesign = { modules: [{ file: 'cards.gd', role: '手牌与牌面' }, { file: 'score.gd', role: '计分过程' }] };
const moduleClick = (h, file = 'score.gd', extra = {}) => h.listeners.get('message')({ origin: 'http://local', source: h.$('#rt').contentWindow,
  data: { __ugc: true, payload: { type: 'module_focus', file, label: 'untrusted label', previewSession: h.context.editorTest.getExpected().session } }, ...extra });

test('initial document is blank and project discovery starts exactly the correct single runtime', async () => {
  const html = await readFile(new URL('../web/editor.html', import.meta.url), 'utf8');
  assert.match(html, /<iframe id="rt"[^>]*src="about:blank"/);
  const godot = await boot({ design: moduleDesign, pck: '' });
  assert.equal(godot.reloads.length, 1); assert.match(godot.reloads[0], /workshop\.pck/);
  assert.equal(godot.reloads.includes('/game/index.html'), false);
  const legacy = await boot({ engine: 'code' });
  assert.deepEqual(legacy.reloads, ['/game/index.html']);
  legacy.context.editorTest.onRuntime({ type: 'ready' });
  assert.equal(legacy.reloads.length, 1);
  assert.ok(legacy.sent.some(message => message.type === 'load' && message.spec.meta.engine === 'code'));
});

test('Remix handoff puts the modification prompt into Chat despite the copied assistant welcome', async () => {
  const h = await boot({ status: 'completed', go: '主角改成小猫', remix: true, chat: [{ role: 'assistant', text: '已复制游戏，请告诉我如何改编' }] });
  assert.equal(h.$('#input').value, '主角改成小猫');
  assert.equal(h.$('#feed').hidden, false);
  const existing = await boot({ status: 'completed', go: '不要重复发送', remix: true, chat: [{ role: 'user', text: '这轮已经开始' }] });
  assert.equal(existing.$('#input').value, '');
});

test('landscape Preview swaps only the game dimensions, fills the surface, and restores portrait Chat without reloading', async () => {
  const h = await boot({ status: 'completed' });
  const values = new Map();
  h.$('#frameWrap').style.setProperty = (key, value) => values.set(key, value);
  h.$('#sceneSpace').clientWidth = 416;
  h.$('#sceneSpace').clientHeight = 700;
  h.$('#constructionStatus').hidden = h.$('#sceneEditBar').hidden = true;
  h.context.editorTest.getProject().game.meta.orientation = 'landscape';
  const before = h.reloads.length;
  h.context.editorTest.setChat(false, false);
  assert.equal(h.context.document.body.classList.contains('preview-rotated'), true);
  assert.equal(values.get('--frameW'), '700px', 'Preview hides the status toolbar, so the game takes the full height');
  assert.equal(values.get('--frameH'), '416px');
  assert.ok(Number(values.get('--runtimeScaleY')) > 1);
  h.context.editorTest.setChat(true, false);
  assert.equal(h.context.document.body.classList.contains('preview-rotated'), false);
  assert.equal(h.$('#feed').hidden, false);
  assert.equal(h.reloads.length, before);
  h.context.editorTest.getProject().game.meta.orientation = 'portrait';
  h.context.editorTest.setChat(false, false);
  assert.equal(h.context.document.body.classList.contains('preview-rotated'), false);
  assert.equal(h.context.document.body.classList.contains('landscape-preview'), false);
});

test('hidden primary workshop pauses idempotently and restores current state before rendering on return', async () => {
  const h = await boot({ design: moduleDesign, pck: '' }), api = h.context.editorTest;
  api.onRuntime({ type: 'workshop_ready', previewSession: api.getExpected().session, loaded: true });
  assert.equal(h.sent.findLast(row => row.type === 'presentation').active, true);
  const iframeSrc = h.$('#testRt').src, reloadCount = h.reloads.length;
  h.context.document.visibilityState = 'hidden'; h.listeners.get('document:visibilitychange')();
  assert.equal(h.sent.findLast(row => row.type === 'presentation').active, false);
  const hiddenCount = h.sent.filter(row => row.type === 'presentation').length;
  api.renderClock(); h.listeners.get('document:visibilitychange')();
  assert.equal(h.sent.filter(row => row.type === 'presentation').length, hiddenCount);
  api.handle({ type: 'code_write', file: 'score.gd', sourceRevision: 'r2' });
  const before = h.sent.length;
  h.context.document.visibilityState = 'visible'; h.listeners.get('document:visibilitychange')();
  const resumed = h.sent.slice(before), snapshot = resumed.findIndex(row => row.type === 'workshop'), presentation = resumed.findIndex(row => row.type === 'presentation' && row.active);
  assert.ok(snapshot >= 0 && presentation > snapshot);
  assert.equal(resumed[snapshot].restore, true); assert.equal(resumed[snapshot].modules.find(row => row.file === 'score.gd').state, 'saved');
  assert.equal(h.reloads.length, reloadCount); assert.equal(h.$('#testRt').src, iframeSrc);
});

test('a workshop that first becomes ready in a hidden page starts paused', async () => {
  const h = await boot({ design: moduleDesign, pck: '' }), api = h.context.editorTest;
  h.context.document.visibilityState = 'hidden';
  api.onRuntime({ type: 'workshop_ready', previewSession: api.getExpected().session, loaded: true });
  assert.equal(h.sent.findLast(row => row.type === 'presentation').active, false);
});

test('legacy to Godot creation immediately updates real feedback delivery semantics', async () => {
  const entry = { id: 'advice', text: '让目标更清楚', status: 'queued', t: 1 };
  const h = await boot({ engine: 'code', participationDelivery: 'next_round', participation: [entry] }), api = h.context.editorTest;
  assert.match(h.$('#participationNote').textContent, /下轮开始时送达/);
  api.handle({ type: 'turn_start', engine: 'godot' });
  assert.equal(api.getProject().participationDelivery, 'live'); assert.match(h.$('#participationNote').textContent, /等待下个工作节点/);
  assert.match(h.$('#input').placeholder, /下个工作节点/);
  api.handle({ type: 'ops', ops: [{ op: 'set_meta', meta: { title: '旧运行器', engine: 'code' } }] });
  assert.equal(api.getProject().participationDelivery, 'next_round'); assert.match(h.$('#participationNote').textContent, /下轮开始时送达/);
});

test('2D builds show the real game: each checkpoint reloads with an assembly pass; the stage only precedes the first pack', async () => {
  const h = await boot({ design: moduleDesign }), api = h.context.editorTest;
  assert.match(h.reloads[0], /old\.pck&edit=1&assemble=1/); assert.doesNotMatch(h.reloads[0], /workshop=1/);
  assert.match(h.$('#constructionStatus').textContent, /小精灵正在现场拼装/);
  api.handle({ type: 'ops', ops: [{ op: 'pck', url: '/packs/new.pck', buildId: 'new', sourceRevision: 'r2' }] });
  assert.match(h.reloads.at(-1), /new\.pck&edit=1&assemble=1/); assert.equal(api.getExpected().workshop, false); assert.equal(api.getExpected().buildId, 'new');
  api.setMode('play'); assert.match(h.reloads.at(-1), /new.pck/); assert.doesNotMatch(h.reloads.at(-1), /edit=1|assemble=1/);
  const stage = await boot({ pck: '' }); stage.context.editorTest.handle({ type: 'design', design: moduleDesign });
  assert.match(stage.reloads.at(-1), /workshop=1/, 'before the first pack a plain stage stands in');
  assert.match(stage.$('#constructionStatus').textContent, /第一版画面/);
  stage.context.editorTest.handle({ type: 'ops', ops: [{ op: 'pck', url: '/packs/first.pck', buildId: 'first', sourceRevision: 'r2' }] });
  assert.match(stage.reloads.at(-1), /first\.pck&edit=1&assemble=1/, 'the first pack replaces the stage');
  const idle = await boot({ status: 'completed' }), count = idle.reloads.length;
  idle.context.editorTest.handle({ type: 'ops', ops: [{ op: 'pck', url: '/packs/scene.pck', buildId: 'scene', sourceRevision: 'r3' }] });
  assert.equal(idle.reloads.length, count, 'outside a running build the open game is not interrupted');
  assert.doesNotMatch(idle.reloads[0], /assemble=1/);
});

test('scene module clicks are source, origin, navigation and planned-file checked; suggestions only fill the draft', async () => {
  const h = await boot({ design: moduleDesign }), api = h.context.editorTest;
  for (const extra of [{ origin: 'https://other.invalid' }, { source: h.$('#testRt').contentWindow }, { data: { __ugc: true, payload: { type: 'module_focus', file: 'score.gd', previewSession: 'old-navigation' } } }]) moduleClick(h, 'score.gd', extra);
  moduleClick(h, 'unknown.gd'); assert.equal(h.$('#moduleFocus').hidden, true);
  moduleClick(h); assert.equal(h.$('#moduleFocus').hidden, false); assert.equal(h.$('#moduleFocusName').textContent, '正在讨论：计分过程');
  assert.match(h.$('#input').placeholder, /计分过程/); assert.doesNotMatch(h.$('#moduleFocusName').textContent, /untrusted/);
  const requests = h.requests.length;
  h.$('#moduleSuggestions').onclick({ target: { closest: () => ({ dataset: { moduleSuggestion: '0' } }) } });
  assert.equal(h.$('#input').value, '解释分数是怎么算的'); assert.equal(h.requests.length, requests);
  h.$('#moduleFocusClear').onclick(); api.setMode('play'); moduleClick(h); assert.equal(h.$('#moduleFocus').hidden, true);
});

test('running feedback enters the queue without stopping or starting work and SSE delivery is not implementation', async () => {
  const entry = { id: 'advice-1', text: '请把计分说清楚', moduleFile: 'score.gd', status: 'queued', t: 1 };
  const h = await boot({ design: moduleDesign, participationResponse: { ok: true, participation: [entry] } }), api = h.context.editorTest;
  moduleClick(h); h.$('#input').value = entry.text;
  assert.equal(h.$('#sendBtn').hidden, false); assert.equal(h.$('#sendLabel').textContent, '提交建议');
  const count = h.requests.length; await api.send();
  const requests = h.requests.slice(count), body = JSON.parse(requests.find(row => row.path.endsWith('/participation')).body);
  assert.equal(body.text, entry.text); assert.equal(body.moduleFile, 'score.gd'); assert.match(body.requestId, /^[\w-]{8,80}$/);
  assert.equal(requests.some(row => /\/(chat|stop)$/.test(row.path)), false); assert.equal(api.getWorkflow().status, 'running');
  assert.equal(h.$('#input').value, ''); assert.match(h.$('#participationNote').textContent, /等待下个工作节点/);
  api.handle({ type: 'participation', participation: [{ ...entry, status: 'applied', appliedAt: 2 }] });
  assert.match(h.$('#participationList').innerHTML, /已送达本轮/); assert.match(h.$('#participationNote').textContent, /尚不代表已经实现/);
});

test('queue failure preserves drafts and idempotent retry, even if the current run finishes meanwhile', async () => {
  let attempts = 0;
  const entry = { id: 'retry-1', text: '让牌面更清晰', status: 'queued', t: 1 };
  const h = await boot({ participationResponse: () => ++attempts === 1 ? { ok: false, error: '连接中断' } : { ok: true, participation: [entry] } }), api = h.context.editorTest;
  h.$('#input').value = entry.text; await api.send();
  assert.equal(h.$('#input').value, entry.text); assert.match(h.$('#participationNote').textContent, /草稿已保留/);
  api.handle({ type: 'turn_end', runId: 'run-1', status: 'partial' });
  await api.send();
  const requests = h.requests.filter(row => row.path.endsWith('/participation')).map(row => JSON.parse(row.body));
  assert.equal(requests.length, 2); assert.equal(requests[0].requestId, requests[1].requestId);
  assert.equal(h.requests.some(row => row.path.endsWith('/chat')), false); assert.match(h.$('#participationNote').textContent, /下轮开始时送达/);
});

test('a retry preserves the exact submitted payload when the module plan changes while its receipt is uncertain', async () => {
  let attempts = 0;
  const h = await boot({ design: moduleDesign, participationResponse: () => ++attempts === 1 ? { ok: false, error: '回执中断' } : { ok: true, participation: [] } }), api = h.context.editorTest;
  api.handle({ type: 'code_write', file: 'score.gd', sourceRevision: 'r2' }); moduleClick(h);
  h.$('#input').value = '让计分更清楚'; await api.send();
  api.handle({ type: 'design', design: { modules: [{ file: 'cards.gd', role: '手牌' }] } });
  await api.send();
  const submitted = h.requests.filter(row => row.path.endsWith('/participation')).map(row => JSON.parse(row.body));
  assert.equal(submitted.length, 2); assert.deepEqual(submitted[1], submitted[0]); assert.equal(submitted[1].moduleFile, 'score.gd');
});

test('pending feedback cannot double-submit or erase a newer draft; queue receipts restore without launching work', async () => {
  let finish;
  const entry = { id: 'pending-1', text: '旧建议', status: 'queued', t: 1 };
  const h = await boot({ participationResponse: () => new Promise(resolve => { finish = resolve; }) }), api = h.context.editorTest;
  h.$('#input').value = '旧建议'; const pending = api.send(); await Promise.resolve();
  await api.send(); h.$('#input').value = '新草稿';
  finish({ ok: true, participation: [entry] }); await pending;
  assert.equal(h.requests.filter(row => row.path.endsWith('/participation')).length, 1); assert.equal(h.$('#input').value, '新草稿');
  const restored = await boot({ status: 'completed', participation: [entry], participationDelivery: 'next_round' });
  assert.match(restored.$('#participationNote').textContent, /下轮开始时送达/);
  assert.equal(restored.requests.some(row => /\/(chat|participation)$/.test(row.path)), false);
});

test('watch metadata timeout aborts the actual request, retries and ignores its late response', async () => {
  let calls = 0, resolveOld;
  const signals = [];
  const h = await boot({ watch: signal => {
    signals.push(signal); calls++;
    return calls === 1 ? new Promise(resolve => { resolveOld = resolve; }) : watchSnapshot('retry-session');
  } }), api = h.context.editorTest;
  assert.equal(calls, 1);
  const timeout = [...h.timers.values()].find(timer => timer.delay === 4000);
  assert.ok(timeout);
  timeout.fn();
  await new Promise(resolve => setImmediate(resolve));
  assert.equal(signals[0].aborted, true);
  assert.equal([...h.timers.values()].some(timer => timer.fn.name === 'pollWatch'), true);
  await api.pollWatch();
  assert.equal(calls, 2);
  assert.equal(api.getWatch().sessionId, 'retry-session');
  resolveOld(watchSnapshot('timed-out-old-session', 9, { updatedAt: Date.now() + 1000 }));
  await new Promise(resolve => setImmediate(resolve));
  assert.equal(api.getWatch().sessionId, 'retry-session');
});

test('changing visibility or entering play aborts an in-flight metadata request', async () => {
  const signals = [];
  const h = await boot({ watch: signal => { signals.push(signal); return new Promise(() => {}); } }), api = h.context.editorTest;
  h.context.document.visibilityState = 'hidden';
  h.listeners.get('document:visibilitychange')();
  assert.equal(signals[0].aborted, true);
  h.context.document.visibilityState = 'visible';
  h.listeners.get('document:visibilitychange')();
  assert.equal(signals.length, 2);
  api.setMode('play');
  assert.equal(signals[1].aborted, true);
  await new Promise(resolve => setImmediate(resolve));
  assert.equal([...h.timers.values()].some(timer => timer.fn.name === 'pollWatch'), false);
});
test('actual watch frames replace the scene only in edit and a new session never displays the old frame', async () => {
  const h = await boot(), api = h.context.editorTest;
  api.handle({ type: 'playtest_watch', watch: watchSnapshot() });
  assert.equal(h.$('#playtestSurface').hidden, false);
  assert.equal(h.$('#watchFrame').hidden, true);
  h.images.at(-1).onload();
  assert.match(h.$('#watchFrame').src, /session=watch-a&seq=1/);
  api.handle({ type: 'playtest_watch', watch: watchSnapshot('watch-a', 2) });
  const lateLoad = h.images.at(-1).onload;
  api.handle({ type: 'playtest_watch', watch: watchSnapshot('watch-b', 0) });
  assert.equal(h.$('#watchFrame').hidden, true);
  lateLoad();
  assert.equal(h.$('#watchFrame').hidden, true);
  assert.match(h.$('#watchWaiting').textContent, /等待首帧/);
  api.handle({ type: 'playtest_watch', watch: watchSnapshot('watch-a', 99, { updatedAt: Date.now() + 1000 }) });
  assert.equal(api.getWatch().sessionId, 'watch-b');
  assert.equal(h.requests.some(r => r.path.endsWith('/preview_receipt')), false);
  assert.equal(h.sent.some(m => m.type === 'eval'), false);
});

test('watch follows real repair and next-test boundaries while preserving manual view choice', async () => {
  const h = await boot(), api = h.context.editorTest;
  api.handle({ type: 'playtest_watch', watch: watchSnapshot() });
  h.$('#watchMaking').onclick();
  api.handle({ type: 'playtest_watch', watch: watchSnapshot('watch-a', 2) });
  assert.equal(h.$('#playtestSurface').hidden, true);
  api.handle({ type: 'playtest_watch', watch: watchSnapshot('watch-b', 0) });
  assert.equal(h.$('#playtestSurface').hidden, false);
  api.handle({ type: 'tool_start', name: 'patch_file' });
  assert.equal(h.$('#playtestSurface').hidden, true);
  api.handle({ type: 'playtest_watch', watch: watchSnapshot('watch-c', 1, { status: 'failed', errors: ['碰撞失败'] }) });
  h.$('#watchTesting').onclick();
  assert.match(h.$('#watchErrors').textContent, /碰撞失败/);
  assert.match(h.$('#watchStatus').textContent, /未通过/);
});

test('manual play and hidden pages neither fetch nor display automated watch input', async () => {
  let snapshot = null;
  const h = await boot({ watch: () => snapshot }), api = h.context.editorTest;
  api.setMode('play');
  const requestCount = h.requests.length, reloadCount = h.reloads.length, sentCount = h.sent.length;
  snapshot = watchSnapshot();
  api.handle({ type: 'playtest_watch', watch: snapshot });
  api.handle({ type: 'ops', ops: [{ op: 'eval', code: 'MOVE' }, { op: 'ai_play' }] });
  await api.pollWatch();
  assert.equal(h.requests.length, requestCount);
  assert.equal(h.reloads.length, reloadCount);
  assert.equal(h.$('#playtestSurface').hidden, true);
  assert.equal(h.sent.slice(sentCount).some(m => ['eval', 'ai_play'].includes(m.type)), false);
  h.context.document.visibilityState = 'hidden';
  api.setMode('edit');
  await api.pollWatch();
  assert.equal(h.requests.length, requestCount);
  h.context.document.visibilityState = 'visible';
  h.listeners.get('document:visibilitychange')();
  await new Promise(resolve => setImmediate(resolve));
  assert.ok(h.requests.length > requestCount);
});

test('refresh restores a real last test frame and a prior-run pending poll cannot replace a new run', async () => {
  const ended = await boot({ status: 'completed', iteration: { phase: 'review' }, watch: watchSnapshot('last', 3, { kind: 'test', status: 'passed' }) });
  assert.equal(ended.$('#playtestSurface').hidden, false);
  assert.match(ended.$('#watchStatus').textContent, /本次断言检查通过/);
  assert.match(ended.$('#watchNote').textContent, /最后一帧/);
  let resolveOld;
  const h = await boot({ watch: () => new Promise(resolve => { resolveOld = resolve; }) }), api = h.context.editorTest;
  api.handle({ type: 'workflow', workflow: { id: 'run-2', status: 'running', tasks: [], evidence: [], issues: [] } });
  api.handle({ type: 'playtest_watch', watch: watchSnapshot('new-run', 0, { runId: 'run-2' }) });
  resolveOld(watchSnapshot('old-run'));
  await new Promise(resolve => setImmediate(resolve));
  assert.equal(api.getWatch().sessionId, 'new-run');
});

const sceneSnapshot = revision => ({ schema: 1, dimension: '3d', revision, runId: 'run-1', step: '搭建地面', objects: [{ id: 'floor', label: '地面', kind: 'box', position: [0, 0, 0], size: [12, 1, 12], rotation: [0, 0, 0], color: '#456789', solid: true }] });
test('edited scenes do not restore old native acceptance after refresh or keep an old browser test on screen', async () => {
  const ended = watchSnapshot('old-test', 9, { status: 'passed', kind: 'test', sourceRevision: 'old-source' });
  const h = await boot({ status: 'partial', dimension: '3d', snapshot: sceneSnapshot(2), sceneDirty: true, sceneSourceRevision: 'edited-source', iteration: { phase: 'review' }, watch: ended }), api = h.context.editorTest;
  assert.equal(api.getWatch(), null); assert.equal(h.$('#playtestSurface').hidden, true);
  assert.equal(h.$('#workflowStatus').textContent, '场景已修改，等待验收');
  api.handle({ type: 'playtest_watch', watch: ended }); assert.equal(api.getWatch(), null);
  const instance = api.browserTests;
  instance.view = { commandId: 'test-done', runId: 'run-1', sourceRevision: 'edited-source', kind: 'test', status: 'passed', loaded: true, checks: [{ what: '9项检查', ok: true }], errors: [] };
  instance.onView(instance.view, true); assert.equal(h.$('#playtestSurface').hidden, false);
  api.handle({ type: 'scene_edit', sceneDirty: true, sceneSourceRevision: 'another-edit' });
  assert.equal(instance.view, null); assert.equal(h.$('#playtestSurface').hidden, true); assert.equal(h.$('#testRt').src, 'about:blank');
  api.handle({ type: 'ops', ops: [{ op: 'pck', url: '/packs/latest.pck', buildId: 'latest', sourceRevision: 'latest-ai-source' }] });
  api.handle({ type: 'scene_edit', sceneDirty: false, sceneSourceRevision: 'another-edit' });
  api.handle({ type: 'playtest_watch', watch: watchSnapshot('latest-test', 1, { sourceRevision: 'latest-ai-source' }) });
  assert.equal(api.getWatch().sessionId, 'latest-test', 'a newer build is authoritative after the edited scene has been built');
});
test('manual scene moves persist canonical positions and require a new pack before play', async () => {
  const changed = sceneSnapshot(2); changed.objects[0].position = [1, 0, 0];
  const h = await boot({ status: 'completed', dimension: '3d', snapshot: sceneSnapshot(1), sceneEditResult: { ok: true, snapshot: changed, sourceRevision: 'r2', dirty: true }, sceneBuildResult: { ok: true, pck: '/packs/edited.pck', build: { buildId: 'edited', sourceRevision: 'r2' }, sourceRevision: 'r2' } }), api = h.context.editorTest;
  api.onRuntime({ type: 'workshop_ready', previewSession: api.getExpected().session, loaded: true });
  api.onRuntime({ type: 'editor_selection', previewSession: api.getExpected().session, id: 'floor', label: '地面', position: [0, 0, 0], revision: 1, pending: false });
  assert.equal(h.$('#sceneEditBar').hidden, false); assert.match(h.$('#sceneEditPosition').textContent, /X 0.00/);
  await api.saveSceneMove({ id: 'floor', position: [1, 0, 0], baseRevision: 1, requestId: 'move-1' });
  assert.equal(api.getProject().sceneDirty, true); assert.equal(h.sent.findLast(row => row.type === 'construction').restore, true);
  assert.match(h.$('#sceneEditPosition').textContent, /X 1.00/);
  await api.setMode('play'); assert.equal(api.getMode(), 'play'); assert.match(h.reloads.at(-1), /edited.pck/);
  assert.ok(h.requests.some(row => row.path.endsWith('/scene-build'))); assert.equal(api.getProject().sceneDirty, false);
});
test('failed scene save restores the same authoritative revision and building failure never plays an old pack', async () => {
  const h = await boot({ status: 'completed', dimension: '3d', snapshot: sceneSnapshot(1), sceneDirty: true }), api = h.context.editorTest;
  api.onRuntime({ type: 'workshop_ready', previewSession: api.getExpected().session, loaded: true });
  await api.saveSceneMove({ id: 'floor', position: [1, 0, 0], baseRevision: 1, requestId: 'move-1' });
  const restore = h.sent.findLast(row => row.type === 'construction'); assert.equal(restore.restore, true); assert.equal(restore.snapshot.revision, 1);
  assert.match(h.$('#constructionStatus').textContent, /保存失败/);
  const before = h.reloads.length; await api.setMode('play'); assert.equal(api.getMode(), 'edit'); assert.equal(h.reloads.length, before);
  assert.match(h.$('#constructionStatus').textContent, /生成失败/);
});
test('AI production and stale scene revisions cannot move objects', async () => {
  const h = await boot({ dimension: '3d', snapshot: sceneSnapshot(3) }), api = h.context.editorTest;
  api.onRuntime({ type: 'workshop_ready', previewSession: api.getExpected().session, loaded: true });
  await api.saveSceneMove({ id: 'floor', position: [1, 0, 0], baseRevision: 3 });
  assert.equal(h.requests.some(row => row.path.endsWith('/scene-edit')), false);
  api.handle({ type: 'turn_end', engine: 'godot', runId: 'run-1', status: 'completed' });
  await api.saveSceneMove({ id: 'floor', position: [1, 0, 0], baseRevision: 2 });
  assert.equal(h.requests.some(row => row.path.endsWith('/scene-edit')), false);
});
test('browser command surface is independent and cannot receive player-iframe messages or input', async () => {
  const h = await boot(), api = h.context.editorTest, instance = api.browserTests, frames = [];
  h.$('#testRt').contentWindow = { ugcReceive: message => frames.push(JSON.parse(message)) };
  const command = { commandId: 'browser-command', clientId: instance.clientId, runId: 'run-1', runtimeSession: 'browser-session', buildId: 'next-build', sourceRevision: 'next-revision', kind: 'run', pckUrl: '/packs/next.pck', createdAt: Date.now(), expiresAt: Date.now() + 60000, payload: {} };
  api.handle({ type: 'runtime_test', command }); assert.match(h.$('#testRt').src, /runtimeTest=1/); assert.equal(h.$('#playtestSurface').hidden, false);
  assert.equal(h.reloads.length, 1); assert.equal(h.$('#watchFrame').hidden, true);
  api.onRuntime({ type: 'ready', previewSession: instance.session.previewSession, loaded: true, buildId: command.buildId, sourceRevision: command.sourceRevision }); assert.equal(frames.length, 0);
  instance.onMessage({ source: h.$('#testRt').contentWindow, origin: 'http://local', data: { __ugc: true, payload: { type: 'ready', previewSession: instance.session.previewSession, loaded: true, buildId: command.buildId, sourceRevision: command.sourceRevision, errors: [] } } });
  assert.equal(frames[0].type, 'runtime_test'); assert.equal(h.sent.some(row => row.type === 'runtime_test'), false);
  assert.equal(h.requests.some(row => row.path.endsWith('/preview_receipt')), false);
  api.setMode('play'); assert.equal(h.$('#playtestSurface').hidden, true); assert.equal(h.$('#testRt').src, 'about:blank');
});
test('watching pauses only the background scene and returning restores canonical state before rendering', async () => {
  const h = await boot({ status: 'completed', dimension: '3d', snapshot: sceneSnapshot(2) }), api = h.context.editorTest;
  api.onRuntime({ type: 'workshop_ready', previewSession: api.getExpected().session, loaded: true });
  api.handle({ type: 'playtest_watch', watch: watchSnapshot() });
  assert.equal(h.sent.findLast(row => row.type === 'presentation').active, false);
  h.$('#watchMaking').onclick();
  assert.equal(h.sent.at(-1).type, 'presentation'); assert.equal(h.sent.at(-1).active, true);
  assert.equal(h.sent.at(-2).type, 'construction'); assert.equal(h.sent.at(-2).restore, true);
});

test('primary presentation changes never pause or reload an active independent acceptance command', async () => {
  const h = await boot({ design: moduleDesign, pck: '' }), api = h.context.editorTest, instance = api.browserTests, commands = [];
  api.onRuntime({ type: 'workshop_ready', previewSession: api.getExpected().session, loaded: true });
  h.$('#testRt').contentWindow = { ugcReceive(message) { commands.push(JSON.parse(message)); } };
  const command = { commandId: 'live-test', clientId: instance.clientId, runId: 'run-1', runtimeSession: 'live-session', buildId: 'old', sourceRevision: 'r1', kind: 'test', pckUrl: '/packs/old.pck', createdAt: Date.now(), expiresAt: Date.now() + 60000, payload: {} };
  api.handle({ type: 'runtime_test', command });
  const testSource = h.$('#testRt').src;
  const emit = payload => instance.onMessage({ source: h.$('#testRt').contentWindow, origin: 'http://local', data: { __ugc: true, payload: { previewSession: instance.session.previewSession, ...payload } } });
  emit({ type: 'ready', buildId: command.buildId, sourceRevision: command.sourceRevision, loaded: true, errors: [] });
  assert.equal(h.sent.findLast(row => row.type === 'presentation').active, false);
  h.$('#watchMaking').onclick(); assert.equal(h.sent.findLast(row => row.type === 'presentation').active, true);
  h.$('#watchTesting').onclick(); assert.equal(h.sent.findLast(row => row.type === 'presentation').active, false);
  assert.equal(instance.current.commandId, command.commandId); assert.equal(h.$('#testRt').src, testSource);
  assert.equal(commands.length, 1); assert.equal(commands[0].type, 'runtime_test');
  assert.equal(commands.some(row => row.type === 'presentation'), false);
  emit({ ...command, type: 'runtime_test_result', data: { loaded: true, ok: true, has_test: true, checks: [{ what: '实际规则断言', ok: true }], errors: [] } });
  assert.equal(instance.view.status, 'passed'); assert.equal(instance.completed.get(command.commandId).data.ok, true);
  assert.equal(h.sent.findLast(row => row.type === 'workshop').modules.some(row => row.state === 'verified'), false, 'one passed test is not whole-version acceptance');
});
test('finished browser acceptance followed by manual play returns to making instead of an unloaded canvas', async () => {
  const h = await boot({ status: 'completed' }), api = h.context.editorTest, instance = api.browserTests;
  h.$('#testRt').contentWindow = { ugcReceive() {} };
  const command = { commandId: 'finished-command', clientId: instance.clientId, runId: 'run-1', runtimeSession: 'finished-session', buildId: 'current-build', sourceRevision: 'r1', kind: 'test', pckUrl: '/packs/old.pck', createdAt: Date.now(), expiresAt: Date.now() + 60000, payload: {} };
  api.handle({ type: 'runtime_test', command });
  const emit = payload => instance.onMessage({ source: h.$('#testRt').contentWindow, origin: 'http://local', data: { __ugc: true, payload: { previewSession: instance.session.previewSession, ...payload } } });
  emit({ type: 'ready', loaded: true, buildId: command.buildId, sourceRevision: command.sourceRevision, errors: [] });
  emit({ ...command, type: 'runtime_test_result', data: { loaded: true, ok: true, has_test: true, checks: [{ what: '实际玩法检查', ok: true }], errors: [] } });
  assert.equal(h.$('#playtestSurface').hidden, false); assert.equal(instance.view.status, 'passed');
  api.setMode('play'); api.setMode('edit');
  assert.equal(api.getMode(), 'edit'); assert.equal(h.$('#testRt').src, 'about:blank');
  assert.equal(instance.view, null); assert.equal(h.$('#playtestSurface').hidden, true);
  assert.equal(h.$('#watchMaking')['aria-pressed'], 'true');
  assert.equal(instance.completed.get(command.commandId).data.ok, true, 'the real result remains cached for delivery');
});
test('committed 3D scenes remain in observation through final build and require explicit play', async () => {
  const h = await boot({ dimension: '3d', pck: null }), api = h.context.editorTest;
  assert.match(h.reloads[0], /workshop=1&dim=3d/);
  const ready = () => api.onRuntime({ type: 'workshop_ready', surface: 'workshop', previewSession: api.getExpected().session, loaded: true, errors: [] });
  ready();
  api.handle({ type: 'construction', runId: 'run-1', snapshot: sceneSnapshot(1) });
  assert.equal(h.sent.findLast(m => m.type === 'construction').restore, false);
  assert.match(h.$('#constructionStatus').textContent, /正在应用/);
  api.onRuntime({ type: 'construction_applied', surface: 'construction', previewSession: api.getExpected().session, revision: 0, runId: 'run-1', loaded: true, objectCount: 1, errors: [] });
  assert.match(h.$('#constructionStatus').textContent, /正在应用/);
  api.onRuntime({ type: 'construction_applied', surface: 'construction', previewSession: api.getExpected().session, revision: 1, runId: 'run-1', loaded: true, objectCount: 1, errors: [] });
  assert.match(h.$('#constructionStatus').textContent, /已落地 · 1 个对象/);
  api.handle({ type: 'ops', ops: [{ op: 'pck', url: '/packs/new.pck', buildId: 'new', sourceRevision: 'r2', version: 2 }, { op: 'ai_play' }, { op: 'eval', code: 'MOVE_PLAYER' }] });
  api.handle({ type: 'turn_end', engine: 'godot', runId: 'run-1', status: 'completed', pck: '/packs/new.pck' });
  assert.equal(h.reloads.length, 1);
  assert.equal(api.getMode(), 'edit');
  assert.equal(h.sent.some(m => ['eval', 'ai_play'].includes(m.type)), false);
  assert.equal(h.requests.some(r => r.path.endsWith('/preview_receipt')), false);
  h.$('#scenePlay').onclick();
  assert.equal(h.reloads.length, 2);
  assert.match(h.reloads[1], /new.pck/);
  assert.doesNotMatch(h.reloads[1], /edit=1|workshop=1/);
  const before = h.sent.length;
  api.handle({ type: 'construction', runId: 'run-1', snapshot: sceneSnapshot(2) });
  assert.equal(h.sent.slice(before).some(m => m.type === 'construction'), false);
  api.setMode('edit'); ready();
  assert.match(h.reloads[2], /workshop=1&dim=3d/);
  assert.equal(h.sent.findLast(m => m.type === 'construction').snapshot.revision, 2);
  assert.equal(h.sent.findLast(m => m.type === 'construction').restore, true);
});

test('recovered construction snapshots open observation and restore immediately without replay', async () => {
  const h = await boot({ dimension: '3d', snapshot: sceneSnapshot(4) }), api = h.context.editorTest;
  assert.match(h.reloads[0], /workshop=1&dim=3d/);
  api.onRuntime({ type: 'workshop_ready', surface: 'workshop', previewSession: api.getExpected().session, loaded: true });
  const message = h.sent.findLast(m => m.type === 'construction');
  assert.equal(message.restore, true);
  assert.equal(message.snapshot.revision, 4);
  const before = h.sent.length;
  api.handle({ type: 'construction', runId: 'other-run', snapshot: { ...sceneSnapshot(5), runId: 'other-run' } });
  api.handle({ type: 'construction', runId: 'run-1', snapshot: sceneSnapshot(3) });
  assert.equal(h.sent.slice(before).some(m => m.type === 'construction'), false);
  assert.equal(h.requests.some(r => r.path.endsWith('/preview_receipt')), false);
});

test('writing progress shows safe unsaved metadata at most once a second and clears on save or stop', async () => {
  const h = await boot(), api = h.context.editorTest;
  const progress = lines => api.handle({ type: 'tool_progress', name: 'write_file', id: 'write-1', agent: 'B', step: '核心玩法骨架', file: 'main.gd', lines, code: 'PRIVATE_SOURCE', tail: 'PRIVATE_SOURCE' });
  progress(100);
  assert.match(h.$('#workflowContent').innerHTML, /核心玩法骨架/);
  assert.match(h.$('#workflowContent').innerHTML, /main.gd · 已收到 100 行/);
  assert.match(h.$('#workflowContent').innerHTML, /编写中 · 尚未保存/);
  const first = h.$('#workflowContent').innerHTML;
  progress(150); progress(200); progress(250);
  assert.equal(h.$('#workflowContent').innerHTML, first);
  const timers = [...h.timers].filter(([, timer]) => timer.fn.name === 'publishWritingProgress');
  assert.equal(timers.length, 1);
  assert.ok(timers[0][1].delay > 0 && timers[0][1].delay <= 1000);
  h.timers.delete(timers[0][0]); timers[0][1].fn();
  assert.match(h.$('#workflowContent').innerHTML, /已收到 250 行/);
  assert.doesNotMatch(h.$('#workflowContent').innerHTML, /PRIVATE_SOURCE/);
  assert.equal(h.sent.some(message => JSON.stringify(message).includes('PRIVATE_SOURCE')), false);
  assert.doesNotMatch(h.$('#workflowContent').innerHTML, /<li data-status="running">/, 'stream chunks do not become activity records');
  progress(300);
  api.handle({ type: 'code_write', id: 'write-1', file: 'main.gd', lines: 300 });
  assert.doesNotMatch(h.$('#workflowContent').innerHTML, /尚未保存/);
  assert.match(h.$('#workflowContent').innerHTML, /已写入 main.gd/);
  assert.equal([...h.timers.values()].some(timer => timer.fn.name === 'publishWritingProgress'), false);
  progress(400);
  api.handle({ type: 'turn_end', runId: 'run-1', status: 'interrupted' });
  assert.doesNotMatch(h.$('#workflowContent').innerHTML, /尚未保存/);
});

test('unchanged next-step choices retain their DOM nodes on clock and workflow refresh', async () => {
  const h = await boot({ status: 'ready' }), node = h.$('#improvementOptions');
  let html = node.innerHTML, writes = 0;
  Object.defineProperty(node, 'innerHTML', { get() { return html; }, set(value) { html = value; writes++; } });
  h.context.editorTest.renderClock();
  h.context.editorTest.renderWorkflow();
  h.context.editorTest.handle({ type: 'workflow', workflow: h.context.editorTest.getWorkflow() });
  assert.equal(writes, 0);
  h.context.editorTest.handle({ type: 'workflow', workflow: { ...h.context.editorTest.getWorkflow(), iteration: { nextSteps: ['只调整难度'] } } });
  assert.equal(writes, 1);
});

test('test input requires edit mode and a matching actual ready manifest', async () => {
  const h = await boot(), api = h.context.editorTest;
  const evaluate = () => api.handle({ type: 'ops', ops: [{ op: 'eval', code: 'test input' }] });
  evaluate();
  assert.equal(h.sent.filter(x => x.type === 'eval').length, 0);
  api.onRuntime({ type: 'ready', previewSession: api.getExpected().session, buildId: 'old', sourceRevision: 'r1', loaded: true, errors: [] });
  evaluate();
  assert.equal(h.sent.filter(x => x.type === 'eval').length, 1);
  api.handle({ type: 'ops', ops: [{ op: 'pck', url: '/packs/new.pck', buildId: 'new', sourceRevision: 'r2' }] });
  evaluate();
  assert.equal(h.sent.filter(x => x.type === 'eval').length, 1, 'old open build must not receive a new build test');
  api.setMode('play');
  const before = h.reloads.length, sentBeforePlay = h.sent.length;
  api.handle({ type: 'ops', ops: [{ op: 'ai_play' }, { op: 'eval', code: 'test input' }] });
  api.handle({ type: 'tool_start', name: 'write_file', agent: 'B' });
  assert.equal(h.sent.filter(x => x.type === 'eval').length, 1);
  assert.equal(h.reloads.length, before);
  assert.equal(api.getMode(), 'play');
  assert.equal(h.sent.slice(sentBeforePlay).some(message => ['crew', 'crew_clear', 'workshop'].includes(message.type)), false);
});

test('legacy runtime play is isolated from test input and scene edits', async () => {
  const h = await boot({ engine: 'code' }), api = h.context.editorTest;
  api.setMode('play');
  const before = h.sent.length, reloads = h.reloads.length;
  api.handle({ type: 'ops', ops: [{ op: 'ai_play' }, { op: 'eval', code: 'test input' }, { op: 'entity_add', id: 'new', entity: {} }] });
  api.handle({ type: 'turn_end', engine: 'code', status: 'ready' });
  assert.equal(api.getMode(), 'play');
  assert.equal(h.sent.slice(before).some(x => x.type === 'eval' || x.type === 'ops'), false);
  assert.equal(h.reloads.length, reloads);
});

test('initial snapshot keeps records collapsed and opens the existing checkpoint just once', async () => {
  const h = await boot();
  assert.equal(h.$('#workflowPanel').hidden, true);
  assert.match(h.$('#workflowContent').innerHTML, /制作阶段/);
  assert.doesNotMatch(h.$('#workflowContent').innerHTML, /尚未分配任务/);
  assert.equal(h.reloads.length, 1);
  assert.equal(h.$('#studioPlay').hidden, false);
  const before = h.$('#workflowContent').innerHTML;
  h.context.editorTest.renderClock();
  assert.equal(h.$('#workflowContent').innerHTML, before);
  assert.equal(h.reloads.length, 1);
  assert.deepEqual(h.focuses, []);
});
test('workshop is a real iframe without a game receipt; first game pack replaces it once', async () => {
  const h = await boot({ pck: null });
  assert.match(h.reloads[0], /pck=%2Fworkshop.pck&edit=1&workshop=1/);
  const session = h.context.editorTest.getExpected().session;
  h.context.editorTest.onRuntime({ type: 'workshop_ready', surface: 'workshop', previewSession: session, loaded: true, errors: [] });
  h.context.editorTest.onRuntime({ type: 'ready', previewSession: session, buildId: 'old', sourceRevision: 'r1', loaded: true, errors: [] });
  assert.equal(h.requests.some(request => request.path.endsWith('/preview_receipt')), false);
  assert.equal(h.sent.some(message => message.type === 'crew' && message.agent === 'M'), true);
  h.context.editorTest.handle({ type: 'design', design: { title: '霓虹守夜', core_loop: '躲避无人机，撑过30秒', palette: ['#00e5ff'], milestones: [{ name: '一个可玩房间' }] } });
  const plan = h.sent.findLast(message => message.type === 'workshop').plan;
  assert.equal(plan.title, '霓虹守夜');
  assert.equal(plan.milestone, '一个可玩房间');
  assert.equal(h.reloads.length, 1);
  h.context.editorTest.handle({ type: 'tool_start', seq: 8, name: 'write_file', activity: { id: 'current', at: 3000, kind: 'tool', title: '正在制作游戏内容', status: 'running' } });
  assert.match(h.$('#workflowContent').innerHTML, /主制作/);
  assert.equal((h.$('#workflowContent').innerHTML.match(/class="worker-card"/g) || []).length, 1);
  assert.ok(h.$('#workflowContent').innerHTML.indexOf('最近发生') < h.$('#workflowContent').innerHTML.indexOf('worker-card'));
  h.context.editorTest.handle({ type: 'ops', seq: 9, ops: [{ op: 'pck', url: '/packs/first.pck', buildId: 'first', sourceRevision: 'r1', version: 1 }] });
  assert.equal(h.reloads.length, 2);
  assert.match(h.reloads[1], /first.pck/);
  const gameSession = h.context.editorTest.getExpected().session;
  h.context.editorTest.onRuntime({ type: 'workshop_ready', surface: 'workshop', previewSession: gameSession, loaded: true });
  assert.equal(h.requests.some(request => request.path.endsWith('/preview_receipt')), false);
  h.context.editorTest.onRuntime({ type: 'ready', previewSession: gameSession, buildId: 'first', sourceRevision: 'r1', loaded: true, errors: [] });
  assert.equal(h.requests.filter(request => request.path.endsWith('/preview_receipt')).length, 1);
});
test('a running 2D checkpoint is shown live; test-play and completion events do not reload again or steal focus', async () => {
  const h = await boot();
  h.context.editorTest.handle({ type: 'ops', seq: 8, ops: [{ op: 'pck', url: '/packs/new.pck', buildId: 'new', sourceRevision: 'r2', version: 2 }] });
  assert.equal(h.reloads.length, 2); assert.match(h.reloads[1], /new\.pck&edit=1&assemble=1/);
  h.context.editorTest.handle({ type: 'ops', seq: 9, ops: [{ op: 'ai_play' }] });
  h.context.editorTest.handle({ type: 'turn_end', seq: 10, engine: 'godot', runId: 'run-1', status: 'ready', pck: '/packs/new.pck' });
  assert.equal(h.reloads.length, 2);
  assert.equal(h.context.editorTest.getMode(), 'edit');
  assert.equal(h.$('#studioNext').hidden, false);
  assert.deepEqual(h.focuses, []);
  h.$('#studioPlay').onclick();
  assert.equal(h.reloads.length, 3);
  assert.match(h.reloads[2], /new.pck/);
  assert.equal(h.context.editorTest.getMode(), 'play');
});
test('a real screenshot activity on a tool event updates the workshop without opening chat', async () => {
  const h = await boot();
  // The phone workspace starts in Chat; choose Preview before checking that
  // incoming progress does not change the user's selected page.
  assert.equal(h.$('#feed').hidden, false);
  h.$('#chatClose').onclick();
  h.focuses.length = 0;
  h.context.editorTest.handle({ type: 'tool_result', seq: 8, activity: { id: 'shot1', title: '实机输入试玩通过', at: 1500, status: 'verified', image: '/covers/real.png' } });
  assert.match(h.$('#workflowContent').innerHTML, /实机输入试玩通过/);
  assert.match(h.$('#workflowContent').innerHTML, /\/covers\/real.png/);
  assert.equal(h.$('#feed').hidden, true);
  assert.deepEqual(h.focuses, []);
});
test('composer sends selected tier and does not launch a next iteration by merely showing choices', async () => {
  const h = await boot({ status: 'completed', tier: 'quality' });
  assert.equal(h.$('#iterationTier').value, 'quality');
  h.$('#improveBtn').onclick();
  assert.equal(h.requests.filter(r => r.path.endsWith('/chat')).length, 0);
  h.$('#input').value = '只改善移动手感';
  await h.context.editorTest.send();
  const request = h.requests.find(r => r.path.endsWith('/chat'));
  assert.equal(request.body.iteration.tier, 'quality');
  assert.equal(request.body.text, '只改善移动手感');
});
test('persisted iteration tier overrides the link tier on recovery; old records keep no invented target', async () => {
  const h = await boot({ tier: 'demo', iteration: { kind: 'iteration', tier: 'quality', targetMs: 1500000, startedAt: 1000, phase: 'build' } });
  assert.equal(h.$('#iterationTier').value, 'quality');
  assert.equal(h.$('#iterationTarget').textContent, '目标 25 分钟');
  const legacy = await boot({ tier: 'quality' });
  assert.equal(legacy.$('#iterationTarget').textContent, '未设置目标时间');
});
test('recovered interrupted demo visibly shows 2:50 and does not keep ticking', async () => {
  const h = await boot({ status: 'interrupted', iteration: { phase: 'paused', targetMs: 480000, startedAt: 1793089413346, endedAt: 1793089583650 } });
  assert.equal(h.$('#iterationElapsed').textContent, '2:50');
  h.context.editorTest.renderClock();
  assert.equal(h.$('#iterationElapsed').textContent, '2:50');
});

test('model selector restores project choice, uses API options and never reloads the game', async () => {
  const h = await boot({ status: 'completed', model: 'choice-d' }), reloads = h.reloads.length;
  assert.equal(h.$('#modelSelect').value, 'choice-d'); assert.equal(h.$('#modelSelect').disabled, false);
  assert.match(h.$('#modelSelect').innerHTML, /choice-a/); assert.match(h.$('#modelSelect').innerHTML, /choice-d/);
  h.$('#modelSelect').value = 'choice-c'; await h.$('#modelSelect').onchange();
  assert.equal(h.context.editorTest.getProject().model, 'choice-c'); assert.equal(h.reloads.length, reloads);
  assert.deepEqual(JSON.parse(JSON.stringify(h.requests.find(row => row.path.endsWith('/model')).body)), { model: 'choice-c' });
  h.context.editorTest.handle({ type: 'turn_start', model: 'choice-c' });
  assert.equal(h.$('#modelSelect').disabled, true); assert.match(h.$('#modelNote').textContent, /本轮完成后/);
  h.$('#modelSelect').value = 'choice-a'; await h.$('#modelSelect').onchange();
  assert.equal(h.$('#modelSelect').value, 'choice-c'); assert.equal(h.requests.filter(row => row.path.endsWith('/model')).length, 1);
});

test('model persistence failure restores the actual project choice with a visible error', async () => {
  const h = await boot({ status: 'completed', modelResponse: async () => { throw new Error('正在制作，请稍后'); } });
  h.$('#modelSelect').value = 'choice-a'; await h.$('#modelSelect').onchange();
  assert.equal(h.$('#modelSelect').value, 'choice-b'); assert.equal(h.context.editorTest.getProject().model, 'choice-b');
  assert.match(h.$('#modelNote').textContent, /切换未确认/); assert.equal(h.$('#modelNote').hidden, false);
});

test('a model save in progress preserves draft and blocks starting a round with stale selection', async () => {
  let finish; const h = await boot({ status: 'completed', modelResponse: () => new Promise(resolve => { finish = resolve; }) });
  h.$('#modelSelect').value = 'choice-a'; const saving = h.$('#modelSelect').onchange();
  h.$('#input').value = '改善操作'; await h.context.editorTest.send();
  assert.equal(h.$('#input').value, '改善操作'); assert.equal(h.$('#sendBtn').disabled, true);
  assert.equal(h.requests.some(row => row.path.endsWith('/chat')), false);
  finish({ ok: true, model: 'choice-a' }); await saving;
  assert.equal(h.$('#sendBtn').disabled, false);
});

test('the pencil sketch fills the stage while the builder works, moves to the corner when the round ends, and hides in play', async () => {
  const h = await boot({ pck: '' }), api = h.context.editorTest, sketch = api.getSketch();
  assert.deepEqual(sketch.connected, ['fixture']);
  assert.equal(sketch.view, 'hidden'); assert.equal(h.$('#sketchBtn').hidden, true, 'nothing drawn yet');
  sketch.content = true; sketch.live = true; sketch.hooks.onChange({ begin: true });
  assert.equal(sketch.view, 'full'); assert.equal(sketch.views.at(-1).canCollapse, false);
  assert.equal(h.$('#sketchBtn').hidden, false);
  assert.match(sketch.maker, /\S/, 'the caption shows what the builder is doing in parallel');
  api.handle({ type: 'ops', ops: [{ op: 'pck', url: '/packs/first.pck', buildId: 'first', sourceRevision: 'r2' }] });
  assert.equal(sketch.view, 'full', 'an early build does not end the show while the builder is still working');
  assert.equal(sketch.views.at(-1).canCollapse, true, 'but the user can switch to the real picture');
  sketch.hooks.onChoice('pip'); assert.equal(sketch.view, 'pip');
  h.$('#sketchBtn').onclick(); assert.equal(sketch.view, 'hidden');
  h.$('#sketchBtn').onclick(); assert.equal(sketch.view, 'pip');
  sketch.hooks.onChange({ begin: true }); assert.equal(sketch.view, 'full', 'a new round returns to the automatic placement');
  h.$('#frameWrap').classList.add('watching'); sketch.hooks.onChange({});
  assert.equal(sketch.view, 'pip', 'a live playtest on screen takes the stage and the sketch steps into the corner');
  h.$('#frameWrap').classList.remove('watching'); sketch.hooks.onChange({});
  assert.equal(sketch.view, 'full');
  api.handle({ type: 'turn_end', status: 'completed' });
  assert.equal(sketch.view, 'pip', 'once the builder is done the real game takes the stage');
  assert.equal(sketch.maker, '');
  api.setMode('play'); assert.equal(sketch.view, 'hidden');
  api.setMode('edit'); assert.equal(sketch.view, 'pip');
  const old = await boot({ status: 'completed' }), board = old.context.editorTest.getSketch();
  board.content = true; board.hooks.onChange({});
  assert.equal(board.view, 'hidden', 'an old sketch does not cover a finished game on reopening');
  assert.equal(old.$('#sketchBtn').hidden, false);
});
