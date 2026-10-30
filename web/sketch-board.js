// Pencil sketch board: the sketch artist's strokes, drawn as they stream in from the server.
// Geometry is deterministic per element, so a redraw (resize, erase, reconnect) looks identical.
const INK = '#2a2a30';
const FONT = '"STXingkai","华文行楷","Xingkai SC","KaiTi","STKaiti","楷体",cursive';
const CODE_FONT = '"Segoe Print","Comic Sans MS","KaiTi","楷体",cursive';
const PX_PER_MS = 1.3, HATCH_PX_PER_MS = 3.2, MS_PER_CHAR = 60, MS_PER_CODE_CHAR = 26;
const TASK_LABEL = { first: '画初稿', revise: '按进展修改', level: '搭关卡', code: '写代码便签', notes: '补标注', final: '收尾' };
const charWidth = (ch, size) => /[\u2e80-\uffff]/.test(ch) ? size : ch === ' ' ? size * 0.42 : size * 0.6;
const textWidthEstimate = (text, size) => Array.from(text).reduce((n, ch) => n + charWidth(ch, size), 0);

/** Paper size of a pseudo-code sticky note, estimated so server, redraw and erase all agree. */
export function codeCard(item, board = { w: 1000, h: 1000 }) {
  const size = item.size || 14, lh = size * 1.45, pad = 12, titleH = item.title ? size * 1.6 : 0;
  const widest = Math.max(item.title ? textWidthEstimate(item.title, size * 1.05) : 0, ...item.lines.map(line => textWidthEstimate(line, size)));
  const w = Math.min(Math.max(160, widest + pad * 2), Math.max(60, board.w - item.x)), h = pad + titleH + item.lines.length * lh + pad * 0.6;
  return { x: item.x, y: item.y, w, h, size, lh, pad, titleH };
}

export function hashSeed(text) {
  let h = 2166136261;
  for (const ch of String(text)) { h ^= ch.codePointAt(0); h = Math.imul(h, 16777619); }
  return h >>> 0;
}
export function rng(seed) {
  let a = seed >>> 0;
  return () => {
    a = (a + 0x6D2B79F5) | 0;
    let t = Math.imul(a ^ (a >>> 15), 1 | a);
    t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}
export function pathLength(pts) {
  let n = 0;
  for (let i = 2; i < pts.length; i += 2) n += Math.hypot(pts[i] - pts[i - 2], pts[i + 1] - pts[i - 1]);
  return n;
}

/** A hand-drawn version of a polyline: subdivided, slightly bowed, with drifting wobble and loose ends. */
export function wobble(pts, closed, r, { amp = 0.9, bow = 0.02, overshoot = 3.5 } = {}) {
  const src = [];
  for (let i = 0; i + 1 < pts.length; i += 2) src.push([pts[i], pts[i + 1]]);
  if (closed) src.push(src[0], [src[0][0] + (src[1][0] - src[0][0]) * 0.12, src[0][1] + (src[1][1] - src[0][1]) * 0.12]);
  const out = [];
  let drift = 0;
  for (let s = 0; s < src.length - 1; s++) {
    const [x1, y1] = src[s], [x2, y2] = src[s + 1];
    const dx = x2 - x1, dy = y2 - y1, L = Math.hypot(dx, dy) || 1;
    const nx = -dy / L, ny = dx / L, n = Math.max(2, Math.ceil(L / 9));
    const b = (r() - 0.5) * 2 * Math.min(L * bow, 5);
    for (let k = s === 0 ? 0 : 1; k <= n; k++) {
      const t = k / n;
      drift = drift * 0.7 + (r() - 0.5) * amp;
      const off = Math.sin(Math.PI * t) * b + drift;
      out.push(x1 + dx * t + nx * off, y1 + dy * t + ny * off);
    }
  }
  if (!closed && overshoot && out.length >= 4) {
    const extend = (ax, ay, bx, by) => { const L = Math.hypot(ax - bx, ay - by) || 1, e = 1 + r() * overshoot; return [ax + (ax - bx) / L * e, ay + (ay - by) / L * e]; };
    const head = extend(out[0], out[1], out[2], out[3]), m = out.length;
    const tail = extend(out[m - 2], out[m - 1], out[m - 4], out[m - 3]);
    out.unshift(...head); out.push(...tail);
  }
  return out;
}

/** Diagonal pencil shading clipped to a polygon (flat [x,y,...]). */
export function hatch(poly, r, spacing = 7) {
  const xs = poly.filter((_, i) => i % 2 === 0), ys = poly.filter((_, i) => i % 2 === 1);
  const lo = Math.min(...xs) + Math.min(...ys), hi = Math.max(...xs) + Math.max(...ys), lines = [];
  for (let c = lo + spacing * (0.5 + r() * 0.5); c < hi; c += spacing * (0.8 + r() * 0.4)) {
    const hits = [];
    for (let i = 0; i < poly.length; i += 2) {
      const ax = poly[i], ay = poly[i + 1], bx = poly[(i + 2) % poly.length], by = poly[(i + 3) % poly.length];
      const fa = ax + ay - c, fb = bx + by - c;
      if ((fa < 0) !== (fb < 0)) { const t = fa / (fa - fb); hits.push([ax + (bx - ax) * t, ay + (by - ay) * t]); }
    }
    hits.sort((p, q) => p[0] - q[0]);
    for (let k = 0; k + 1 < hits.length; k += 2) {
      const [x1, y1] = hits[k], [x2, y2] = hits[k + 1], L = Math.hypot(x2 - x1, y2 - y1);
      if (L < 3) continue;
      const a = r() * 2 / L, b = 1 - r() * 2 / L;
      lines.push([x1 + (x2 - x1) * a, y1 + (y2 - y1) * a + (r() - 0.5), x1 + (x2 - x1) * b, y1 + (y2 - y1) * b + (r() - 0.5)]);
    }
  }
  return lines;
}

function ellipsePoly(cx, cy, rx, ry, n = 28) {
  const out = [];
  for (let i = 0; i < n; i++) { const a = i / n * Math.PI * 2; out.push(cx + Math.cos(a) * rx, cy + Math.sin(a) * ry); }
  return out;
}

/** The pencil strokes of one board element, in drawing order. */
export function itemStrokes(item) {
  const r = rng(hashSeed(item.id + ':' + item.t + ':' + (item.x ?? item.pts?.[0] ?? 0) + ':' + (item.y ?? item.pts?.[1] ?? 0)));
  const base = { w: item.weight === 'bold' ? 2.4 : item.weight === 'light' ? 1.1 : 1.7, a: item.weight === 'light' ? 0.55 : 0.85, color: item.color || INK };
  const line = (pts, extra = {}) => ({ ...base, ...extra, pts, len: pathLength(pts) });
  const shade = poly => hatch(poly, r).map(pts => line(pts, { w: 0.9, a: 0.42, hatch: true }));
  if (item.t === 'text') return [{ ...base, text: item.text, x: item.x, y: item.y, size: item.size || 20, len: Array.from(item.text).length, seed: hashSeed(item.id + item.text) }];
  if (item.t === 'card') {
    const size = 15, c = { x: item.x, y: item.y, w: item.w, h: item.h, plain: true, size, pad: 12 }, { x, y, w, h } = c;
    const edge = [x, y, x + w, y, x + w, y + h, x, y + h];
    const out = [{ card: c, len: 1 }, ...[0, 1, 2, 3].map(i => line(wobble([edge[i * 2], edge[i * 2 + 1], edge[(i * 2 + 2) % 8], edge[(i * 2 + 3) % 8]], false, r, { overshoot: 1.5 }), { w: 1.1, a: 0.5 }))];
    if (item.title) out.push({ ...base, text: item.title, x: x + c.pad, y: y + 8, size, len: Array.from(item.title).length, seed: hashSeed(item.id + item.title), color: '#6b5a3a' });
    return out;
  }
  if (item.t === 'code') {
    const c = codeCard(item), { x, y, w, h } = c, edge = [x, y, x + w, y, x + w, y + h, x, y + h];
    const side = i => line(wobble([edge[i * 2], edge[i * 2 + 1], edge[(i * 2 + 2) % 8], edge[(i * 2 + 3) % 8]], false, r, { overshoot: 1.5 }), { w: 1.1, a: 0.5 });
    const write = (text, tx, ty, size, extra) => ({ ...base, text, x: tx, y: ty, size, len: Array.from(text).length, seed: hashSeed(item.id + ty + text), ...extra });
    const out = [{ card: c, len: 1 }, ...[0, 1, 2, 3].map(side)];
    if (item.title) out.push(write(item.title, x + c.pad, y + c.pad * 0.7, c.size * 1.05, { color: '#7a5b22' }), line(wobble([x + c.pad, y + c.pad * 0.7 + c.size * 1.3, x + w - c.pad, y + c.pad * 0.7 + c.size * 1.3], false, r, { overshoot: 1 }), { w: 0.9, a: 0.45 }));
    item.lines.forEach((text, i) => { if (text.trim()) out.push(write(text, x + c.pad, y + c.pad + c.titleH + i * c.lh, c.size, { font: CODE_FONT, code: true, color: item.color || '#2d3a4a' })); });
    return out;
  }
  if (item.t === 'line') return [line(wobble(item.pts, false, r))];
  if (item.t === 'arrow') {
    const p = item.pts, m = p.length, ex = p[m - 2], ey = p[m - 1];
    const ang = Math.atan2(ey - p[m - 3], ex - p[m - 4]), head = 14;
    const wing = da => line(wobble([ex, ey, ex - Math.cos(ang + da) * head, ey - Math.sin(ang + da) * head], false, r, { overshoot: 1 }));
    return [line(wobble(p, false, r)), wing(0.45), wing(-0.45)];
  }
  if (item.t === 'shape') return [line(wobble(item.pts, true, r)), ...(item.fill === 'hatch' ? shade(item.pts) : [])];
  if (item.t === 'rect') {
    const { x, y, w, h } = item, c = [x, y, x + w, y, x + w, y + h, x, y + h];
    const side = i => line(wobble([c[i * 2], c[i * 2 + 1], c[(i * 2 + 2) % 8], c[(i * 2 + 3) % 8]], false, r));
    const sides = [0, 1, 2, 3].map(side);
    const again = item.weight === 'bold' ? [0, 1, 2, 3].map(i => ({ ...side(i), a: 0.4 })) : [];
    return [...sides, ...again, ...(item.fill === 'hatch' ? shade(c) : [])];
  }
  if (item.t === 'ellipse') {
    const cx = item.x + item.w / 2, cy = item.y + item.h / 2, rx = item.w / 2, ry = item.h / 2;
    const a0 = r() * Math.PI * 2, sweep = Math.PI * 2 + 0.25 + r() * 0.35, n = Math.max(18, Math.ceil((rx + ry) * Math.PI / 7)), pts = [];
    let drift = 0;
    for (let i = 0; i <= n; i++) {
      const a = a0 + sweep * i / n;
      drift = drift * 0.8 + (r() - 0.5) * 0.04;
      const k = 1 + drift + (i / n) * 0.03;
      pts.push(cx + Math.cos(a) * rx * k, cy + Math.sin(a) * ry * k);
    }
    return [line(pts), ...(item.fill === 'hatch' ? shade(ellipsePoly(cx, cy, rx * 0.92, ry * 0.92)) : [])];
  }
  return [];
}

function pointAt(pts, cum, d) {
  let i = 1;
  while (i < cum.length - 1 && cum[i] < d) i++;
  const span = cum[i] - cum[i - 1] || 1, t = Math.min(1, Math.max(0, (d - cum[i - 1]) / span));
  return [pts[(i - 1) * 2] + (pts[i * 2] - pts[(i - 1) * 2]) * t, pts[(i - 1) * 2 + 1] + (pts[i * 2 + 1] - pts[(i - 1) * 2 + 1]) * t, i];
}
function cumulative(pts) {
  const cum = [0];
  for (let i = 2; i < pts.length; i += 2) cum.push(cum.at(-1) + Math.hypot(pts[i] - pts[i - 2], pts[i + 1] - pts[i - 1]));
  return cum;
}
function itemBox(item) {
  if (item.pts) {
    const xs = item.pts.filter((_, i) => i % 2 === 0), ys = item.pts.filter((_, i) => i % 2 === 1);
    return { x: Math.min(...xs), y: Math.min(...ys), w: Math.max(...xs) - Math.min(...xs), h: Math.max(...ys) - Math.min(...ys) };
  }
  if (item.t === 'text') return { x: item.x, y: item.y, w: (item.size || 20) * Array.from(item.text).length, h: item.size || 20 };
  if (item.t === 'code') { const { x, y, w, h } = codeCard(item); return { x, y, w, h }; }
  return { x: item.x, y: item.y, w: item.w, h: item.h };
}
function unionBox(items) {
  const boxes = items.map(itemBox);
  if (!boxes.length) return null;
  const x = Math.min(...boxes.map(b => b.x)), y = Math.min(...boxes.map(b => b.y));
  return { x, y, w: Math.max(...boxes.map(b => b.x + b.w)) - x, h: Math.max(...boxes.map(b => b.y + b.h)) - y };
}

const PENCIL_SVG = '<svg viewBox="0 0 36 36" aria-hidden="true"><g transform="translate(2 34) rotate(-45)"><polygon points="0,0 5,-1.6 5,1.6" fill="#333"/><polygon points="5,-1.6 12,-3.6 12,3.6 5,1.6" fill="#e8c99a"/><rect x="12" y="-3.6" width="22" height="7.2" fill="#f2c230"/><rect x="12" y="-1" width="22" height="2" fill="#dba91c"/><rect x="34" y="-3.6" width="3" height="7.2" fill="#b9b9b9"/><rect x="37" y="-3.6" width="4.5" height="7.2" rx="1.6" fill="#e98b96"/></g></svg>';

/**
 * DOM view: a paper canvas, a moving pencil, a caption with the sketch round and what the builder is
 * doing. view is 'full' (covers the game area), 'pip' (a note in the corner) or 'hidden'.
 */
export class SketchBoardView {
  constructor(root, { onChange = () => {}, onChoice = () => {} } = {}) {
    this.root = root; this.onChange = onChange; this.onChoice = onChoice;
    root.innerHTML = '<div class="sketch-paper"><canvas></canvas><div class="sketch-pencil">' + PENCIL_SVG + '</div><div class="sketch-eraser"></div></div>'
      + '<div class="sketch-head"><span class="sketch-badge">✎ 铅笔草图</span><strong class="sketch-round"></strong><span class="sketch-note" role="status"></span></div>'
      + '<div class="sketch-foot"><span class="sketch-maker"></span><button type="button" class="sketch-collapse">看真实画面</button></div>'
      + '<button type="button" class="sketch-close" aria-label="收起草图">×</button>';
    this.paper = root.querySelector('.sketch-paper'); this.canvas = root.querySelector('canvas'); this.ctx = this.canvas.getContext('2d');
    this.pencil = root.querySelector('.sketch-pencil'); this.eraser = root.querySelector('.sketch-eraser');
    this.roundEl = root.querySelector('.sketch-round'); this.noteEl = root.querySelector('.sketch-note'); this.makerEl = root.querySelector('.sketch-maker');
    root.querySelector('.sketch-collapse').onclick = event => { event.stopPropagation(); this.onChoice('pip'); };
    root.querySelector('.sketch-close').onclick = event => { event.stopPropagation(); this.onChoice('hidden'); };
    root.addEventListener('click', () => { if (this.view === 'pip') this.onChoice('full'); });
    this.state = { w: 1000, h: 562, round: 0, phase: 'idle', note: '', message: '' };
    this.items = []; this.queue = []; this.task = null; this.tip = null;
    this.view = 'hidden'; this.live = false; this.maker = ''; this.activity = ''; this.canCollapse = false;
    this.scale = 1; this.raf = 0; this.last = 0;
    new ResizeObserver(() => this.resize()).observe(this.paper);
    document.addEventListener('visibilitychange', () => { if (document.visibilityState === 'visible') this.play(); });
  }
  connect(projectId) {
    this.es?.close();
    this.es = new EventSource('/api/projects/' + encodeURIComponent(projectId) + '/sketch?stream=1');
    this.es.onmessage = event => { try { this.receive(JSON.parse(event.data)); } catch (error) { console.warn('sketch event', error); } };
  }
  close() { this.es?.close(); this.es = null; cancelAnimationFrame(this.raf); this.raf = 0; }
  receive(msg) {
    if (msg.op === 'snapshot') return this.load(msg.state);
    if (msg.op === 'begin') {
      this.flush();
      Object.assign(this.state, { w: msg.w, h: msg.h, round: msg.round || 0, phase: 'drawing', note: '', message: '' });
      if (!msg.keep) this.items = [];
      this.live = true; this.resize(true); this.renderHead();
      this.onChange({ begin: true });
      return;
    }
    this.live = true;
    if (msg.op === 'activity') { this.activity = msg.text || ''; this.renderMaker(); return; }
    this.queue.push(msg);
    this.play();
    this.onChange({});
  }
  load(state) {
    if (!state) return;
    this.queue = []; this.task = null;
    this.state = { w: state.w || 1000, h: state.h || 562, round: state.round || 0, task: state.task || '', phase: state.phase || 'idle', note: state.note || '', message: state.message || '' };
    this.items = Array.isArray(state.items) ? state.items.map(item => ({ ...item, strokes: itemStrokes(item) })) : [];
    this.activity = state.activity || '';
    this.resize(true); this.renderHead(); this.renderMaker(); this.hideTools();
    this.onChange({});
  }
  hasContent() { return this.items.length > 0 || !!this.task || this.queue.length > 0 || this.state.phase === 'drawing'; }
  active() { return !!this.task || this.queue.length > 0 || ['drawing', 'waiting'].includes(this.state.phase); }
  setView(view, { canCollapse = false } = {}) {
    this.canCollapse = canCollapse;
    this.root.querySelector('.sketch-collapse').hidden = !canCollapse;
    this.root.querySelector('.sketch-close').hidden = view === 'full' && !canCollapse;
    if (view === this.view) return;
    this.view = view;
    this.root.hidden = view === 'hidden';
    this.root.dataset.view = view;
    if (view === 'hidden') this.flush(); else { this.resize(true); this.play(); }
  }
  /** Fallback status from the editor; the board's own live activity line takes precedence while it exists. */
  setMaker(text) {
    if (text === this.maker) return;
    this.maker = text;
    this.renderMaker();
  }
  renderMaker() {
    const text = this.maker ? this.activity || this.maker : '';
    const line = text ? '主制作 AI：' + text : '';
    if (this.makerEl.textContent !== line) this.makerEl.textContent = line;
  }
  visibleNow() { return this.view !== 'hidden' && document.visibilityState === 'visible'; }
  play() {
    if (this.raf || (!this.task && !this.queue.length)) return;
    if (!this.visibleNow()) { this.flush(); return; }
    this.last = performance.now();
    this.raf = requestAnimationFrame(t => this.frame(t));
  }
  frame(t) {
    this.raf = 0;
    if (!this.visibleNow()) { this.flush(); return; }
    const boost = 1 + this.queue.length * 0.5;
    let budget = Math.min(64, t - this.last) * boost;
    this.last = t;
    // Every step consumes at least 0.5 ms of budget; a float remainder must never stall the loop.
    while (budget > 0.01 && (this.task || this.queue.length)) {
      if (!this.task) { this.next(); continue; }
      budget = this.step(budget);
    }
    this.renderHead();
    if (this.task || this.queue.length) { this.renderTools(); this.raf = requestAnimationFrame(next => this.frame(next)); }
    else { this.hideTools(); this.onChange({}); }
  }
  /** Takes the next queued op; meta ops apply at once, drawing ops become the current task. */
  next() {
    const op = this.queue.shift();
    if (!op) return;
    if (op.op === 'round') Object.assign(this.state, { round: op.round, task: op.task || '', phase: 'drawing', note: '', message: '' });
    else if (op.op === 'note') this.state.note = op.note || '';
    else if (op.op === 'phase') Object.assign(this.state, { phase: op.phase, message: op.message || '' });
    else if (op.op === 'add') {
      const item = { ...op.item, strokes: itemStrokes(op.item) };
      const draw = { kind: 'add', item, si: 0, d: 0 };
      const old = this.items.filter(row => row.id === item.id);
      this.task = old.length ? { kind: 'erase', ids: [item.id], box: unionBox(old), t: 0, dur: 260, then: draw } : draw;
    } else if (op.op === 'erase') {
      const gone = this.items.filter(row => op.ids.includes(row.id));
      if (gone.length) this.task = { kind: 'erase', ids: op.ids, box: unionBox(gone), t: 0, dur: 480 };
    }
  }
  /** Advances the current task by budget (ms, already sped up); returns what is left over. */
  step(budget) {
    const task = this.task;
    if (task.kind === 'erase') {
      const use = Math.min(budget, task.dur - task.t);
      task.t += use;
      const p = task.t / task.dur, b = task.box, zig = Math.abs(((p * 4) % 2) - 1);
      this.tip = [b.x + b.w * zig, b.y + b.h * p];
      if (task.t >= task.dur - 0.01) this.finishErase(task);
      return budget - Math.max(use, 0.5);
    }
    const s = task.item.strokes[task.si];
    if (!s) { this.finishAdd(task); return budget; }
    if (s.card) { this.drawCard(s.card); task.si++; return budget - 1; }
    if (s.text) {
      const perChar = s.code ? MS_PER_CODE_CHAR : MS_PER_CHAR;
      const can = budget / perChar, to = Math.min(s.len, task.d + can);
      this.drawText(s, Math.floor(task.d), Math.floor(to));
      const used = (to - task.d) * perChar;
      task.d = to;
      this.tip = [s.x + this.textWidth(s, Math.floor(to)), s.y + s.size * 0.8];
      if (task.d >= s.len) { task.si++; task.d = 0; }
      return budget - Math.max(used, 0.5);
    }
    const rate = s.hatch ? HATCH_PX_PER_MS : PX_PER_MS;
    s.cum ||= cumulative(s.pts);
    const to = Math.min(s.len, task.d + budget * rate);
    this.drawSegment(s, task.d, to);
    const used = (to - task.d) / rate;
    task.d = to;
    const [x, y] = pointAt(s.pts, s.cum, to);
    this.tip = [x, y];
    if (task.d >= s.len) { task.si++; task.d = 0; }
    return budget - Math.max(used, 0.5);
  }
  finishAdd(task) { this.items = this.items.filter(row => row.id !== task.item.id); this.items.push(task.item); this.task = null; }
  finishErase(task) {
    this.items = this.items.filter(row => !task.ids.includes(row.id));
    this.task = task.then || null;
    this.redraw();
  }
  /** Completes everything queued without animation (hidden board, new run, reconnect). */
  flush() {
    cancelAnimationFrame(this.raf); this.raf = 0;
    let guard = 10000;
    while ((this.task || this.queue.length) && guard--) {
      if (!this.task) { this.next(); continue; }
      if (this.task.kind === 'erase') { this.items = this.items.filter(row => !this.task.ids.includes(row.id)); this.task = this.task.then || null; }
      else this.finishAdd(this.task);
    }
    this.redraw(); this.renderHead(); this.hideTools();
  }
  resize(force = false) {
    const width = this.paper.clientWidth, height = this.paper.clientHeight;
    if (!width || !height) return;
    const { w, h } = this.state;
    this.root.style.setProperty('--sketch-aspect', w + ' / ' + h);
    const cssW = Math.floor(Math.min(width, height * w / h)), cssH = Math.floor(cssW * h / w);
    const dpr = Math.min(2, window.devicePixelRatio || 1);
    if (!force && cssW === this.cssW && cssH === this.cssH && dpr === this.dpr) return;
    this.cssW = cssW; this.cssH = cssH; this.dpr = dpr;
    this.canvas.style.width = cssW + 'px'; this.canvas.style.height = cssH + 'px';
    this.canvas.width = Math.round(cssW * dpr); this.canvas.height = Math.round(cssH * dpr);
    this.scale = cssW / w;
    this.redraw();
  }
  paperTexture() {
    if (this.grain) return this.grain;
    const c = document.createElement('canvas'); c.width = c.height = 96;
    const g = c.getContext('2d'), r = rng(7);
    for (let i = 0; i < 900; i++) { g.fillStyle = 'rgba(90,80,60,' + (r() * 0.09).toFixed(3) + ')'; g.fillRect(r() * 96, r() * 96, 1, 1); }
    return (this.grain = this.ctx.createPattern(c, 'repeat'));
  }
  redraw() {
    const ctx = this.ctx, { w, h } = this.state, k = this.scale * (this.dpr || 1);
    if (!this.cssW) return;
    ctx.setTransform(k, 0, 0, k, 0, 0);
    ctx.globalAlpha = 1;
    ctx.fillStyle = '#f8f4ea'; ctx.fillRect(0, 0, w, h);
    ctx.fillStyle = this.paperTexture(); ctx.fillRect(0, 0, w, h);
    ctx.fillStyle = 'rgba(150,140,120,.28)';
    for (let x = 25; x < w; x += 25) for (let y = 25; y < h; y += 25) ctx.fillRect(x - 0.6, y - 0.6, 1.2, 1.2);
    for (const item of this.items) for (const s of item.strokes) this.drawFull(s);
    const task = this.task?.kind === 'add' ? this.task : null;
    if (task) {
      task.item.strokes.slice(0, task.si).forEach(s => this.drawFull(s));
      const s = task.item.strokes[task.si];
      if (s?.text) this.drawText(s, 0, Math.floor(task.d)); else if (s && task.d > 0) { s.cum ||= cumulative(s.pts); this.drawSegment(s, 0, task.d); }
    }
  }
  drawFull(s) { if (s.card) this.drawCard(s.card); else if (s.text) this.drawText(s, 0, s.len); else { s.cum ||= cumulative(s.pts); this.drawSegment(s, 0, s.len); } }
  drawCard(c) {
    const ctx = this.ctx;
    ctx.save();
    ctx.shadowColor = 'rgba(60,45,20,.22)'; ctx.shadowBlur = 6 / this.scale; ctx.shadowOffsetY = 2 / this.scale;
    ctx.fillStyle = c.plain ? '#fffdf7' : '#fff3b4'; ctx.globalAlpha = c.plain ? 1 : 0.96; ctx.fillRect(c.x, c.y, c.w, c.h);
    ctx.restore();
    ctx.save();
    ctx.globalAlpha = 0.5; ctx.strokeStyle = '#c9b56a'; ctx.lineWidth = 0.6;
    if (c.lh > 1) for (let ly = c.y + c.pad + c.titleH + c.lh - 2; ly < c.y + c.h - 4; ly += c.lh) { ctx.beginPath(); ctx.moveTo(c.x + 6, ly); ctx.lineTo(c.x + c.w - 6, ly); ctx.stroke(); }
    ctx.globalAlpha = 0.75; ctx.fillStyle = '#cfe0ea';
    const tape = (tx, angle) => { ctx.save(); ctx.translate(tx, c.y); ctx.rotate(angle); ctx.fillRect(-26, -7, 52, 14); ctx.restore(); };
    if (c.plain) { tape(c.x + 18, -0.5); tape(c.x + c.w - 18, 0.5); } else tape(c.x + c.w / 2, -0.06);
    ctx.restore();
    ctx.globalAlpha = 1;
  }
  drawSegment(s, d0, d1) {
    if (d1 <= d0) return;
    const ctx = this.ctx, [sx, sy, i0] = pointAt(s.pts, s.cum, d0), [ex, ey, i1] = pointAt(s.pts, s.cum, d1);
    const lw = Math.max(s.w, 0.8 / this.scale);
    const path = (dx, dy) => {
      ctx.beginPath(); ctx.moveTo(sx + dx, sy + dy);
      for (let i = i0; i < i1; i++) ctx.lineTo(s.pts[i * 2] + dx, s.pts[i * 2 + 1] + dy);
      ctx.lineTo(ex + dx, ey + dy); ctx.stroke();
    };
    ctx.lineCap = 'round'; ctx.lineJoin = 'round'; ctx.strokeStyle = s.color;
    ctx.globalAlpha = s.a * 0.85; ctx.lineWidth = lw; path(0, 0);
    ctx.globalAlpha = s.a * 0.3; ctx.lineWidth = lw * 0.55; path(0.45, 0.35);
    ctx.globalAlpha = 1;
  }
  textWidth(s, n) {
    this.ctx.font = s.size + 'px ' + (s.font || FONT);
    return this.ctx.measureText(Array.from(s.text).slice(0, n).join('')).width;
  }
  drawText(s, from, to) {
    if (to <= from) return;
    const ctx = this.ctx, chars = Array.from(s.text);
    ctx.font = s.size + 'px ' + (s.font || FONT); ctx.textBaseline = 'top'; ctx.fillStyle = s.color; ctx.globalAlpha = Math.min(1, s.a + 0.1);
    for (let i = from; i < to && i < chars.length; i++) {
      const r = rng(s.seed + i * 7919), x = s.x + ctx.measureText(chars.slice(0, i).join('')).width;
      ctx.save(); ctx.translate(x, s.y + (r() - 0.5) * 2); ctx.rotate((r() - 0.5) * 0.09); ctx.fillText(chars[i], 0, 0); ctx.restore();
    }
    ctx.globalAlpha = 1;
  }
  renderTools() {
    if (!this.tip || !this.cssW) return;
    const left = this.canvas.offsetLeft + this.tip[0] * this.scale, top = this.canvas.offsetTop + this.tip[1] * this.scale;
    const erasing = this.task?.kind === 'erase';
    this.pencil.classList.toggle('on', !erasing); this.eraser.classList.toggle('on', erasing);
    if (erasing) this.eraser.style.transform = 'translate(' + (left - 13) + 'px,' + (top - 7) + 'px) rotate(-18deg)';
    else { const size = this.pencil.offsetWidth || 36; this.pencil.style.transform = 'translate(' + (left - size * 2 / 36) + 'px,' + (top - size * 34 / 36) + 'px)'; }
  }
  hideTools() { this.pencil.classList.remove('on'); this.eraser.classList.remove('on'); }
  renderHead() {
    const s = this.state, drawing = !!this.task || this.queue.length > 0;
    const note = s.phase === 'failed' ? s.message
      : drawing || s.phase === 'drawing' ? (s.note || (this.items.length ? '正在按最新进展修改…' : '草图助手拿起铅笔，先把你的想法画出来…'))
      : s.phase === 'waiting' ? (s.note ? s.note + ' · ' : '') + '构思下一笔…'
      : s.phase === 'done' ? '本轮草图完成，共 ' + s.round + ' 稿'
      : s.phase === 'stopped' ? '草图已停止' : '';
    const task = TASK_LABEL[s.task];
    const round = s.round ? '第 ' + s.round + ' 稿' + (task ? ' · ' + task : '') : '';
    if (this.roundEl.textContent !== round) this.roundEl.textContent = round;
    if (this.noteEl.textContent !== note) this.noteEl.textContent = note;
    this.root.dataset.phase = drawing ? 'drawing' : s.phase;
  }
}
