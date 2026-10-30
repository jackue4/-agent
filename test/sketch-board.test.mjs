import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';

const source = await readFile(new URL('../web/sketch-board.js', import.meta.url), 'utf8');
const { itemStrokes, hatch, rng, pathLength, codeCard, SketchBoardView } = await import('data:text/javascript;base64,' + Buffer.from(source).toString('base64'));

test('pencil strokes are deterministic so redraws never change the drawing', () => {
  const rect = { id: 'hero', t: 'rect', x: 100, y: 80, w: 120, h: 60, fill: 'hatch' };
  assert.deepEqual(itemStrokes(rect), itemStrokes({ ...rect }));
  assert.notDeepEqual(itemStrokes(rect)[0].pts, itemStrokes({ ...rect, id: 'enemy' })[0].pts);
});

test('a hand-drawn rectangle has four loose sides, stays near its box and adds shading inside', () => {
  const strokes = itemStrokes({ id: 'box', t: 'rect', x: 100, y: 100, w: 200, h: 100, fill: 'hatch' });
  const sides = strokes.filter(s => !s.hatch), shade = strokes.filter(s => s.hatch);
  assert.equal(sides.length, 4); assert.ok(shade.length >= 10);
  for (const s of strokes) for (let i = 0; i < s.pts.length; i += 2) {
    assert.ok(s.pts[i] > 85 && s.pts[i] < 315 && s.pts[i + 1] > 85 && s.pts[i + 1] < 215, 'point near the box');
  }
  assert.ok(sides.every(s => s.len > 0 && Math.abs(s.len - pathLength(s.pts)) < 1e-6));
});

test('ellipse outlines overlap their start like a real pencil loop; arrows get a head', () => {
  const [loop] = itemStrokes({ id: 'sun', t: 'ellipse', x: 0, y: 0, w: 100, h: 100 });
  assert.ok(loop.len > Math.PI * 100, 'loop goes past a full circle');
  assert.equal(itemStrokes({ id: 'go', t: 'arrow', pts: [0, 0, 100, 0] }).length, 3);
  const [label] = itemStrokes({ id: 'hint', t: 'text', x: 10, y: 10, text: '点击跳跃', size: 18 });
  assert.equal(label.len, 4); assert.equal(label.text, '点击跳跃');
});

test('a pseudo-code note is a paper card with a title, its lines in order, and a box that fits the longest line', () => {
  const note = { id: 'jump', t: 'code', x: 600, y: 40, title: 'player.gd', lines: ['func jump():', '', '  vy = -420'] };
  const strokes = itemStrokes(note);
  assert.ok(strokes[0].card, 'the paper goes down first');
  const text = strokes.filter(s => s.text);
  assert.deepEqual(text.map(s => s.text), ['player.gd', 'func jump():', '  vy = -420'], 'blank lines take space but no strokes');
  assert.ok(text.slice(1).every(s => s.code && s.font));
  assert.ok(text[2].y > text[1].y + strokes[0].card.lh, 'the blank line keeps its gap');
  const card = codeCard(note);
  assert.ok(card.w >= 160 && card.x + card.w <= 1000 && card.h > 3 * card.lh);
  assert.ok(codeCard({ ...note, lines: ['x'.repeat(44)] }).w > card.w);
});

test('a card is an opaque sheet with a pencil border and a title, drawn before its contents', () => {
  const strokes = itemStrokes({ id: 'map2', t: 'card', x: 600, y: 300, w: 320, h: 200, title: '关卡 2' });
  assert.deepEqual(strokes[0].card, { x: 600, y: 300, w: 320, h: 200, plain: true, size: 15, pad: 12 });
  assert.equal(strokes.filter(s => s.pts).length, 4);
  assert.equal(strokes.at(-1).text, '关卡 2');
});

test('playback always spends its frame budget, so a float remainder can never freeze the page', () => {
  const node = () => ({ style: { setProperty() {} }, classList: { toggle() {}, remove() {} }, dataset: {}, clientWidth: 1000, clientHeight: 562, addEventListener() {}, querySelector: () => node() });
  const ctx = new Proxy({}, { get: (t, k) => k === 'measureText' ? s => ({ width: String(s).length * 10 }) : k in t ? t[k] : () => ({}), set: (t, k, v) => { t[k] = v; return true; } });
  const saved = { ...globalThis };
  Object.assign(globalThis, { window: { devicePixelRatio: 1 }, ResizeObserver: class { observe() {} }, document: { visibilityState: 'hidden', addEventListener() {} } });
  try {
    const root = node(); root.querySelector = sel => Object.assign(node(), sel === 'canvas' ? { getContext: () => ctx } : {});
    const view = new SketchBoardView(root);
    view.queue.push({ op: 'add', item: { id: 'round_status', t: 'text', x: 620, y: 112, text: '本轮已保存', size: 22 } });
    view.next();
    view.task.d = 1.8368642305689236;
    const tiny = 8.881784197001252e-16;
    assert.ok(view.step(tiny) < tiny, 'handwriting consumes budget even when it cannot advance a character');
    view.task = { kind: 'erase', ids: [], box: { x: 0, y: 0, w: 1, h: 1 }, t: 479.999999, dur: 480 };
    assert.ok(view.step(tiny) < tiny); assert.equal(view.task, null, 'an erase within a hair of its end finishes');
  } finally { for (const k of ['window', 'ResizeObserver', 'document']) if (k in saved) globalThis[k] = saved[k]; else delete globalThis[k]; }
});

test('a drawing snapshot queues new strokes instead of painting them finished, and a repeat does not draw them twice', () => {
  const node = () => ({ style: { setProperty() {} }, classList: { toggle() {}, remove() {} }, dataset: {}, hidden: false, clientWidth: 1000, clientHeight: 562, addEventListener() {}, querySelector: () => node() });
  const ctx = new Proxy({}, { get: (t, k) => k === 'measureText' ? s => ({ width: String(s).length * 10 }) : k in t ? t[k] : () => ({}), set: (t, k, v) => { t[k] = v; return true; } });
  const saved = { ...globalThis };
  Object.assign(globalThis, { window: { devicePixelRatio: 1 }, ResizeObserver: class { observe() {} }, document: { visibilityState: 'visible', addEventListener() {}, createElement: () => ({ getContext: () => ctx }) }, requestAnimationFrame: () => 1, cancelAnimationFrame() {} });
  try {
    const root = node(); root.querySelector = sel => Object.assign(node(), sel === 'canvas' ? { getContext: () => ctx } : {});
    const view = new SketchBoardView(root, { onChange() { view.setView('full'); } });
    const hero = { id: 'hero', t: 'rect', x: 80, y: 80, w: 120, h: 60, fill: 'hatch' };
    view.receive({ op: 'snapshot', n: 2, state: { w: 1000, h: 562, phase: 'drawing', round: 1, items: [hero] } });
    assert.equal(view.live, true);
    assert.equal(view.view, 'full');
    assert.equal(view.items.length, 0, 'the pencil has not finished the stroke yet');
    assert.equal(view.queue.filter(op => op.op === 'add').length, 1);
    view.receive({ op: 'snapshot', n: 2, state: { w: 1000, h: 562, phase: 'drawing', round: 1, items: [hero] } });
    assert.equal(view.queue.filter(op => op.op === 'add').length, 1, 'the same snapshot must not queue the stroke again');
    view.receive({ op: 'add', n: 3, item: hero });
    assert.equal(view.queue.filter(op => op.op === 'add').length, 1, 'a live stroke already taken from the snapshot is skipped');
    view.receive({ op: 'snapshot', n: 1, state: { w: 1000, h: 562, phase: 'drawing', items: [] } });
    assert.equal(view.state.round, 1, 'an older snapshot cannot rewind the board');
  } finally { for (const k of ['window', 'ResizeObserver', 'document', 'requestAnimationFrame', 'cancelAnimationFrame']) if (k in saved) globalThis[k] = saved[k]; else delete globalThis[k]; }
});

test('hatching is clipped to the polygon', () => {
  const lines = hatch([0, 0, 50, 0, 50, 50, 0, 50], rng(1));
  assert.ok(lines.length > 5);
  for (const [x1, y1, x2, y2] of lines) for (const v of [x1, y1, x2, y2]) assert.ok(v >= -1 && v <= 51);
});
