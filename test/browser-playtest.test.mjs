import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { runInNewContext } from 'node:vm';
const source = await readFile(new URL('../web/browser-playtest.js', import.meta.url), 'utf8');
const { BrowserPlaytestController, runtimePresentation } = await import('data:text/javascript;base64,' + Buffer.from(source).toString('base64'));
const flush = () => new Promise(resolve => setImmediate(resolve));
test('browser timers keep the Window receiver for defaults and explicit timer injection', () => {
  const host = { location: { origin: 'http://local' }, addEventListener() {} }, calls = [];
  function nativeSet(callback, delay) { if (this !== host) throw new TypeError('Illegal invocation'); calls.push(['set', delay]); return 17; }
  function nativeClear(timer) { if (this !== host) throw new TypeError('Illegal invocation'); calls.push(['clear', timer]); }
  const sandbox = { window: host, setTimeout: nativeSet, clearTimeout: nativeClear };
  runInNewContext(source.replace(/^export /gm, '') + '\nglobalThis.Controller = BrowserPlaytestController;', sandbox);
  const args = { projectId: 'p1', iframe: {}, context: () => ({}), uuid: () => 'client-1' };
  const defaults = new sandbox.Controller(args);
  defaults.clearTimer(defaults.setTimer(() => {}, 2000));
  const injected = new sandbox.Controller({ ...args, setTimer: nativeSet, clearTimer: nativeClear });
  injected.clearTimer(injected.setTimer(() => {}, 4000));
  assert.deepEqual(calls, [['set', 2000], ['clear', 17], ['set', 4000], ['clear', 17]]);
});
function setup() {
  const messages = [], requests = [], views = [], timers = new Map(), listeners = new Map(); let number = 0, now = 1000;
  const context = { enabled: true, visible: true, mode: 'edit', runId: 'run-1' };
  const iframe = { src: 'about:blank', contentWindow: { ugcReceive: value => messages.push(JSON.parse(value)) } };
  const host = { location: { origin: 'http://local' }, addEventListener: (type, fn) => listeners.set(type, fn), removeEventListener: type => listeners.delete(type) };
  const client = new BrowserPlaytestController({ projectId: 'p1', iframe, host, context: () => context, clock: () => now,
    uuid: () => 'uuid-' + ++number, setTimer: (fn, delay) => { const id = ++number; timers.set(id, { fn, delay }); return id; }, clearTimer: id => timers.delete(id),
    onView: (view, fresh) => views.push({ view, fresh }), fetcher: async (url, options) => { requests.push({ url, options, body: options.body && JSON.parse(options.body) }); return { ok: true, json: async () => null }; } });
  client.active = true;
  const command = (kind = 'run', extra = {}) => ({ commandId: 'command-' + ++number, clientId: client.clientId, runtimeSession: 'session-1', runId: 'run-1',
    buildId: 'build-1', sourceRevision: 'revision-1', pckUrl: '/packs/new.pck?build=build-1', kind, createdAt: now, expiresAt: now + 60000, payload: {}, ...extra });
  const emit = payload => client.onMessage({ source: iframe.contentWindow, origin: host.location.origin, data: { __ugc: true, payload: { previewSession: client.session?.previewSession, ...payload } } });
  const ready = () => emit({ type: 'ready', loaded: true, buildId: 'build-1', sourceRevision: 'revision-1', errors: [] });
  const result = (command, data = { ok: true, loaded: true, checks: [{ what: '实际移动', ok: true }], errors: [] }) => emit({ ...command, type: 'runtime_test_result', data });
  return { client, context, iframe, command, emit, ready, result, messages, requests, views, timers, advance: value => { now += value; } };
}
test('real run waits for matching first frame and validates all result identities and message source', async () => {
  const h = setup(), c = h.command(); h.client.accept(c);
  assert.match(h.iframe.src, /runtimeTest=1/); assert.match(h.iframe.src, /runtimeSession=session-1/); assert.equal(h.messages.length, 0);
  h.client.onMessage({ source: {}, origin: 'http://local', data: { __ugc: true, payload: { type: 'ready' } } });
  h.emit({ type: 'ready', previewSession: 'old', loaded: true, buildId: 'build-1', sourceRevision: 'revision-1' });
  assert.equal(h.messages.length, 0);
  h.ready(); assert.equal(h.messages[0].type, 'runtime_test'); assert.equal(h.messages[0].command.commandId, c.commandId);
  h.emit({ ...c, commandId: 'old', type: 'runtime_test_result', data: { ok: true } }); assert.equal(h.client.current.commandId, c.commandId);
  h.emit({ ...c, type: 'runtime_test_progress', data: { checks: [{ what: '中间碰撞检查', ok: true }] } });
  assert.match(runtimePresentation(h.client.view).checks, /中间碰撞检查/);
  h.result(c); await flush(); assert.equal(h.client.view.status, 'passed');
  assert.equal(h.requests.filter(row => row.body?.phase === 'result').length, 1);
  h.client.accept(c); await flush(); assert.equal(h.messages.length, 1, 'duplicate command only retries its saved receipt');
  assert.equal(h.requests.some(row => row.url.includes('preview_receipt')), false);
});
test('eval reuses exactly its ready runtime and a fresh test opens another isolated instance', () => {
  const h = setup(), c = h.command(); h.client.accept(c); h.ready(); h.result(c); const src = h.iframe.src;
  const evalCommand = h.command('eval'); h.client.accept(evalCommand); assert.equal(h.iframe.src, src); assert.equal(h.messages.length, 2);
  h.result(evalCommand); const testCommand = h.command('test', { runtimeSession: 'session-2' }); h.client.accept(testCommand);
  assert.notEqual(h.iframe.src, src); assert.equal(h.messages.length, 2); h.ready(); assert.equal(h.messages.length, 3);
});
test('wrong build, expired or foreign commands cannot masquerade as successful tests', () => {
  const h = setup(); assert.equal(h.client.accept(h.command('run', { clientId: 'other' })), false);
  assert.equal(h.client.accept(h.command('run', { runId: 'old' })), false);
  assert.equal(h.client.accept(h.command('run', { expiresAt: 999 })), false);
  h.client.accept(h.command()); h.emit({ type: 'ready', loaded: true, buildId: 'old', sourceRevision: 'revision-1' });
  assert.equal(h.client.view.status, 'failed'); assert.equal(h.iframe.src, 'about:blank'); assert.equal(h.messages.length, 0);
});
test('stop after a passed step preserves the real canvas and scoped result', () => {
  const h = setup(), c = h.command('test'); h.client.accept(c); h.ready(); h.result(c); const src = h.iframe.src;
  h.client.accept(h.command('stop'));
  assert.equal(h.iframe.src, src); assert.equal(h.client.view.status, 'passed'); assert.equal(h.messages.at(-1).command.kind, 'stop');
  assert.equal(runtimePresentation(h.client.view).status, '本次断言检查通过');
});
test('a false eval check fails immediately even when the runtime reports overall ok', () => {
  const h = setup(), run = h.command(); h.client.accept(run); h.ready(); h.result(run);
  const command = h.command('eval'); h.client.accept(command);
  const checks = [{ what: '玩家已经移动', ok: true }, { what: '玩家停在墙前', ok: false }];
  h.result(command, { ok: true, loaded: true, checks, errors: ['碰撞位置不符'] });
  assert.equal(h.client.view.status, 'failed');
  assert.equal(runtimePresentation(h.client.view).status, '本步检查未通过');
  assert.deepEqual(h.client.view.checks, checks); assert.deepEqual(h.client.view.errors, ['碰撞位置不符']);
  const withoutError = h.command('eval'); h.client.accept(withoutError);
  h.result(withoutError, { ok: true, loaded: true, checks, errors: [] });
  assert.equal(h.client.view.status, 'failed', 'a false check alone is sufficient');
  assert.deepEqual(h.client.view.checks, checks);
});
test('manual play, invisible pages and timeouts cancel active input with a truthful failure', async () => {
  for (const switchMode of ['play', 'hidden']) {
    const h = setup(), c = h.command(); h.client.accept(c); h.ready();
    if (switchMode === 'play') h.context.mode = 'play'; else h.context.visible = false;
    h.client.sync(); await flush(); assert.equal(h.client.current, null); assert.equal(h.iframe.src, 'about:blank');
    assert.equal(h.requests.some(row => row.body?.visible === false), true);
    assert.equal(h.requests.some(row => row.body?.commandId === c.commandId && row.body.phase === 'result' && row.body.data.ok === false), true, 'cancelling keeps the active command failure receipt');
    assert.equal(h.client.accept(h.command()), false);
  }
  const h = setup(); h.client.accept(h.command()); [...h.timers.values()].find(row => row.delay === 60000).fn();
  assert.equal(h.client.view.status, 'failed'); assert.match(h.client.view.errors[0], /超时/);
});
test('a pending metadata request is aborted on timeout and can be retried', async () => {
  const h = setup(); let signal;
  h.client.fetcher = (url, options) => new Promise((resolve, reject) => { signal = options.signal; signal.addEventListener('abort', () => reject(new Error('aborted')), { once: true }); });
  const pending = h.client.tick(); [...h.timers.values()].find(row => row.delay === 4000).fn(); await pending;
  assert.equal(signal.aborted, true); assert.equal(h.client.polling, false); assert.ok([...h.timers.values()].some(row => row.delay === 2000));
});
test('server result copies update the same view without echoing or accepting older sessions', () => {
  const h = setup(), c = h.command(); h.client.accept(c); h.ready(); h.result(c); const count = h.requests.length;
  h.client.receive({ ...c, command: undefined, phase: 'result', ok: false, checks: [], errors: ['服务端拒绝过期版本'] });
  assert.equal(h.client.view.status, 'failed'); assert.equal(h.requests.length, count);
  h.client.receive({ ...c, runtimeSession: 'old', phase: 'result', ok: true }); assert.equal(h.client.view.status, 'failed');
  assert.equal(h.client.accept(h.command('run', { createdAt: 999 })), false);
});
test('large screenshot results avoid keepalive limits and failed receipts retry without repeating input', async () => {
  const h = setup(); let attempts = 0; const received = [];
  h.client.fetcher = async (url, options) => {
    const body = options.body && JSON.parse(options.body);
    if (body?.phase === 'result') { received.push(options); if (++attempts === 1) throw new Error('response lost'); }
    return { ok: true, json: async () => ({ ok: true, accepted: true }) };
  };
  const c = h.command(); h.client.accept(c); h.ready(); h.result(c, { ok: true, loaded: true, image: 'A'.repeat(80000), checks: [], errors: [] }); await flush();
  assert.equal(received[0].keepalive, false); assert.equal(h.client.outbox.size, 1);
  await h.client.tick(); await flush(); assert.equal(attempts, 2); assert.equal(h.client.outbox.size, 0); assert.equal(h.messages.length, 1);
});
