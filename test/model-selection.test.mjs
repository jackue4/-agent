import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';

const source = await readFile(new URL('../web/model-selection.js', import.meta.url), 'utf8');
const { ModelSelection, modelSelectionView, paintModelSelection } = await import('data:text/javascript;base64,' + Buffer.from(source).toString('base64'));
const catalogue = { models: [{ id: 'server-a', label: '第一项' }, { id: 'server-b', label: '第二项' }, { id: 'server-c', label: '第三项' }, { id: 'server-d', label: '第四项' }], defaultModel: 'server-b' };

test('all options and creation default come from the server; project refresh retains its persisted choice', async () => {
  const home = new ModelSelection({ request: async () => catalogue }); await home.load();
  assert.equal(home.value, 'server-b'); assert.deepEqual(home.models, catalogue.models);
  const project = new ModelSelection({ request: async () => catalogue, projectId: 'game' }); project.sync('server-d'); await project.load();
  assert.equal(modelSelectionView(project).value, 'server-d'); assert.equal(modelSelectionView(project).disabled, false);
});

test('busy state blocks a programmatic switch as well as the native select', async () => {
  const calls = [], picker = new ModelSelection({ request: async path => { calls.push(path); return catalogue; }, projectId: 'game' });
  picker.sync('server-b', true); await picker.load();
  assert.equal(await picker.choose('server-a'), false); assert.deepEqual(calls, ['/models']);
  assert.equal(modelSelectionView(picker).value, 'server-b'); assert.match(modelSelectionView(picker).note, /本轮完成后/);
});

test('save has a single in-flight request and only confirmed server values become persisted state', async () => {
  let finish; const saved = [], calls = [];
  const picker = new ModelSelection({ projectId: 'game', request: async (path, opts) => { calls.push({ path, opts }); return path === '/models' ? catalogue : new Promise(resolve => { finish = resolve; }); }, onSaved: value => saved.push(value) });
  picker.sync('server-b'); await picker.load(); const saving = picker.choose('server-a');
  assert.equal(picker.value, 'server-b'); assert.equal(modelSelectionView(picker).disabled, true); assert.match(modelSelectionView(picker).note, /正在保存/);
  assert.equal(await picker.choose('server-c'), false); assert.equal(calls.length, 2);
  finish({ ok: true, model: 'server-a' }); assert.equal(await saving, true); assert.deepEqual(saved, ['server-a']); assert.equal(picker.pending, '');
});

test('failed saves read the real value back, including a commit whose response was lost', async () => {
  for (const actual of ['server-b', 'server-a']) {
    const picker = new ModelSelection({ projectId: 'game', request: async path => { if (path === '/models') return catalogue; if (path.endsWith('/model')) throw new Error('连接中断'); return { model: actual, running: true }; } });
    picker.sync('server-b'); await picker.load(); assert.equal(await picker.choose('server-a'), false);
    assert.equal(picker.value, actual); assert.equal(picker.pending, ''); assert.equal(modelSelectionView(picker).disabled, true); assert.match(modelSelectionView(picker).note, /切换未确认/);
  }
});

test('offline and unknown current selections are retained without silently choosing the default', async () => {
  let offline = true;
  const picker = new ModelSelection({ projectId: 'game', request: async () => { if (offline) throw new Error('离线'); return catalogue; } });
  picker.sync('older-server-choice'); await picker.load();
  assert.equal(picker.value, 'older-server-choice'); assert.equal(modelSelectionView(picker).retry, true);
  offline = false; await picker.load(); assert.equal(picker.value, 'older-server-choice'); assert.equal(modelSelectionView(picker).options[0].disabled, true);
});

test('unconfirmed success and failed readback preserve the last known value', async () => {
  const picker = new ModelSelection({ projectId: 'game', request: async path => { if (path === '/models') return catalogue; if (path.endsWith('/model')) return { ok: true }; throw new Error('离线'); } });
  picker.sync('server-b'); await picker.load(); assert.equal(await picker.choose('server-c'), false); assert.equal(picker.value, 'server-b');
});

test('routine status updates do not recreate focused native select options', async () => {
  const picker = new ModelSelection({ request: async () => catalogue }); await picker.load();
  let writes = 0, html = ''; const select = { get innerHTML() { return html; }, set innerHTML(value) { writes++; html = value; } }, note = { dataset: {} }, retry = {};
  paintModelSelection(picker, select, note, retry, String); picker.busy = true; paintModelSelection(picker, select, note, retry, String);
  assert.equal(writes, 1); assert.equal(select.disabled, true);
});

test('the actual homepage creation function sends the selected API ID and keeps the creation tier', async () => {
  const flowSource = await readFile(new URL('../web/create-flow.js', import.meta.url), 'utf8');
  // Browser helpers are not needed by the exported request/handoff function.
  const { createGame } = await import('data:text/javascript;base64,' + Buffer.from(flowSource.replace(/^import .*;\r?\n/gm, '')).toString('base64'));
  const calls = [], request = async (path, opts) => { calls.push({ path, ...opts }); return { id: 'new-game' }; };
  const picker = new ModelSelection({ request: async () => catalogue }); await picker.load(); await picker.choose('server-c');
  const quality = await createGame('做一个纸牌游戏', { dim: '2d', ori: 'portrait', type: { k: '卡牌' }, tier: 'quality', model: picker.value }, request);
  assert.equal(calls[0].path, '/projects'); assert.equal(calls[0].body.model, 'server-c'); assert.match(quality.href, /tier=quality$/);
  assert.deepEqual(calls[0].body, { prompt: '做一个纸牌游戏', dimension: '2d', orientation: 'portrait', genre_hint: '卡牌', model: 'server-c' });
  const free = await createGame('探索一个小岛', { dim: '3d', ori: 'landscape', type: { k: '自由创意' }, tier: 'bogus', model: picker.value }, request);
  assert.match(free.href, /dim=3d&ori=landscape&tier=demo$/); assert.equal(calls[1].body.genre_hint, '');
  assert.equal(new URL(free.href, 'https://example.invalid').searchParams.get('go'), '探索一个小岛');
  await assert.rejects(() => createGame('  ', { model: picker.value }, request), /请先描述/);
  assert.equal(calls.length, 2, 'blank prompts must not create an empty project');
  await assert.rejects(() => createGame('做一个纸牌游戏', { model: picker.value }, async () => ({})), /创建确认/);
  assert.match(flowSource, /cModel.*aria-describedby="cModelNote"/);
});
