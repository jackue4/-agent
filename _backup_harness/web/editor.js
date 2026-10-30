import { $, $$, api, esc, toast, ago, Runtime, STYLE_CN, GENRE_CN } from '/common.js';

const qs = new URLSearchParams(location.search);
const pid = qs.get('id');
let proj = null;
let mode = 'edit';
let running = false;
let selection = null;
let curText = null;      // streaming AI text bubble
let curAgent = '';       // crew member that owns curText
const cards = {};        // tool_use id -> card element
let planEl = null, planSteps = [], planIdx = -1;
let opsPending = 0, opsDone = 0;
const assetEls = {};

const TOOL_META = {
  plan_game: ['📋', '规划游戏'], set_world: ['🌄', '布置世界'], set_rules: ['📜', '制定规则'], set_player: ['🦸', '放置主角'],
  add_entities: ['🧱', '搭建'], update_entities: ['🔧', '调整'], remove_entities: ['🧹', '移除'], generate_assets: ['🎨', '生成 AI 素材'],
  check_game: ['🔍', '自检可玩性'], finish: ['✨', '完成'],
  design_game: ['🧠', '设计玩法'], write_module: ['⌨️', '写代码'], patch_module: ['🩹', '修改代码'], delete_module: ['🧹', '删除模块'],
  run_test: ['🧪', '试玩自测'], update_plan: ['🗺️', '调整路线'],
};
const CODE_TOOLS = ['write_module', 'patch_module', 'delete_module', 'run_test', 'update_plan'];
let designEl = null;       // design/roadmap card for code-engine games
const KIND_COLOR = { platform: '#7cc44f', collectible: '#ffd23f', enemy: '#ef476f', hazard: '#b8c0cc', goal: '#ff6b6b', powerup: '#9b5de5', bouncer: '#ff4d6d', sign: '#c08552', text: '#ffffff', decor: '#57cc99' };
const ASSET_ICON = { sprite: '🧸', background: '🏞️', texture: '🧵', model3d: '🗿', music: '🎵', sfx: '🔔' };
const STAGE_CN = { queued: '排队中', drawing: '绘制中', cutout: '抠图中', sculpting: '3D 塑形中', composing: '作曲中', recording: '录制中' };

// ---------------- AI crew: one lane per agent, live status, phase pipeline ----------------
let crewInfo = { A: { name: '策划师', color: '#f472b6' }, B: { name: '玩法程序员', color: '#a78bfa' }, C: { name: '场景搭建师', color: '#34d399' } };
const ICON = { A: '📝', B: '⚙️', C: '🎨' };
const PHASES = [['design', '设计'], ['build', '并行搭建'], ['integrate', '联调'], ['test', '自测'], ['done', '完成']];
const crew = {};           // agent -> { el, state, lines, files, t0 }
const thinkEls = {};       // agent -> live thinking bubble in the chat
let turnT0 = 0, phaseNow = '', timer = 0, lastBeat = 0;
function crewBar() { return $('#crew'); }
function crewShow(on) {
  crewBar().hidden = !on; requestAnimationFrame(() => layout());
  $('#frameWrap').classList.toggle('crewing', on);
  if (on && !timer) timer = setInterval(crewTick, 500);
  if (!on && timer) { clearInterval(timer); timer = 0; }
}
function crewReset(first) {
  for (const k of Object.keys(crew)) delete crew[k];
  $('#crewLanes').innerHTML = '';
  turnT0 = Date.now(); phaseNow = '';
  $('#crewPipe').innerHTML = (first ? PHASES : PHASES.slice(2)).map(([k, n]) => '<span data-k="' + k + '">' + n + '</span>').join('<i></i>');
  crewShow(true);
}
function crewLane(agent) {
  if (crew[agent]) return crew[agent];
  const who = crewInfo[agent] || { name: agent, color: '#a78bfa' };
  const el = document.createElement('div'); el.className = 'lane'; el.style.setProperty('--c', who.color);
  el.innerHTML = '<div class="la">' + (ICON[agent] || '🤖') + '</div><div class="lb"><div class="ln"><b>' + esc(who.name) + '</b><span class="lst">待命</span><span class="lt"></span></div><div class="lx">…</div><div class="lbar"><i></i></div></div>';
  $('#crewLanes').appendChild(el);
  crew[agent] = { el, state: 'idle', lines: 0, files: 0, t0: Date.now() };
  return crew[agent];
}
const STATE_CN = { thinking: '思考中', coding: '写代码', testing: '自测中', building: '搭建中', done: '已交付', idle: '待命', error: '出错' };
function crewSet(agent, { state, text, pct } = {}) {
  if (!agent) return;
  const c = crewLane(agent);
  if (state) { c.state = state; c.el.dataset.s = state; c.el.querySelector('.lst').textContent = STATE_CN[state] || state; if (state === 'done') c.tDone = Date.now(); }
  if (text !== undefined) c.el.querySelector('.lx').textContent = text;
  if (pct !== undefined) c.el.querySelector('.lbar i').style.width = Math.max(4, Math.min(100, pct)) + '%';
  c.beat = Date.now();
}
function crewPhase(k) {
  phaseNow = k;
  let past = true;
  [...document.querySelectorAll('#crewPipe span')].forEach(s => { const cur = s.dataset.k === k; if (cur) past = false; s.classList.toggle('cur', cur); s.classList.toggle('done', past && !cur); });
}
const fmt = ms => { const s = Math.floor(ms / 1000); return (s >= 60 ? Math.floor(s / 60) + ':' + String(s % 60).padStart(2, '0') : s + 's'); };
function crewTick() {
  if (!turnT0) return;
  $('#crewClock').textContent = fmt(Date.now() - turnT0);
  for (const c of Object.values(crew)) {
    c.el.querySelector('.lt').textContent = fmt((c.tDone || Date.now()) - c.t0);
    // heartbeat: a quiet agent is still alive - make that visible instead of a frozen screen
    c.el.classList.toggle('quiet', c.state !== 'done' && Date.now() - (c.beat || 0) > 6000);
  }
}
/** Live thinking line from an agent (Opus streams a summary of its reasoning). */
function crewThink(agent, text) {
  crewSet(agent, { state: crew[agent]?.state === 'coding' ? 'coding' : 'thinking', text: '💭 ' + text.slice(-90) });
  let el = thinkEls[agent];
  if (!el || !el.isConnected) {
    endStream();
    el = document.createElement('div'); el.className = 'think'; const who = crewInfo[agent];
    if (who) el.style.setProperty('--c', who.color);
    el.innerHTML = '<span class="tw">' + esc(who ? who.name : 'AI') + ' 在想</span><span class="tt"></span>';
    msgs.appendChild(el); thinkEls[agent] = el;
  }
  el.querySelector('.tt').textContent = text;
  scroll();
  rt.send({ type: 'crew', agent, state: 'thinking', text: text.slice(-26) });
}
function crewThinkEnd(agent) { const el = thinkEls[agent]; if (el) { el.classList.add('past'); delete thinkEls[agent]; } }

// ---------------- runtime ----------------
const rt = new Runtime($('#rt'), onRuntime);
function onRuntime(ev) {
  if (ev.type === 'ready') { $('#rtLoading').hidden = true; if (proj) loadRuntime(); }
  else if (ev.type === 'op_done') { opsDone++; updateHud(); }
  else if (ev.type === 'build_idle') { if (!running) hideHud(); maybeCover(); }
  else if (ev.type === 'select') setSelection(ev.id);
  else if (ev.type === 'moved') { api('/projects/' + pid + '/move', { body: { id: ev.id, position: ev.position } }); const e = ev.id === '__player' ? proj.game.player : proj.game.entities[ev.id]; if (e) e.position = ev.position; }
  else if (ev.type === 'js_error') console.warn('runtime', ev.message);
}
function loadRuntime(m = mode) { rt.send({ type: 'load', spec: proj.game, assets: assetStates(), mode: m }); }
function assetStates() { const o = {}; for (const [k, a] of Object.entries(proj.game.assets || {})) o[k] = { kind: a.kind, state: a.state, url: a.url || '' }; return o; }

// ---------------- chat rendering ----------------
const msgs = $('#msgs');
function scroll() { requestAnimationFrame(() => { msgs.scrollTop = msgs.scrollHeight; }); }
function addUser(t) { const d = document.createElement('div'); d.className = 'msg user'; d.innerHTML = '<div>' + esc(t) + '</div>'; msgs.appendChild(d); scroll(); }
function addAi(t, streaming, agent) {
  const d = document.createElement('div'); d.className = 'msg ai';
  const who = agent && crewInfo[agent];
  d.innerHTML = (who ? '<div class="av crew" style="--c:' + who.color + '">' + agent + '</div>' : '<div class="av">🛸</div>') + '<div class="tx' + (streaming ? ' cursor' : '') + '">' + '</div>';
  if (who) d.querySelector('.tx').dataset.who = who.name;
  d.querySelector('.tx').textContent = t || '';
  if (!streaming) md(d.querySelector('.tx'));
  msgs.appendChild(d); scroll(); return d.querySelector('.tx');
}
function addSugg(list) {
  if (!list || !list.length) return;
  setQuick(list);
  const d = document.createElement('div'); d.className = 'sugg';
  d.innerHTML = list.map(s => '<button>💡 ' + esc(s) + '</button>').join('');
  $$('button', d).forEach((b, i) => b.onclick = () => { $('#input').value = list[i]; send(); });
  msgs.appendChild(d); scroll();
}
function md(el) { el.innerHTML = esc(el.textContent).replace(/\*\*(.+?)\*\*/g, '<b>$1</b>').replace(/`([^`]+)`/g, '<code>$1</code>'); }
function endStream() { if (curText) { md(curText); curText.classList.remove('cursor'); if (!curText.textContent.trim()) curText.parentElement.remove(); curText = null; } }

function toolCard(id, name, agent) {
  endStream();
  const c = toolCard0(id, name);
  if (c && agent && crewInfo[agent]) { c.style.setProperty('--c', crewInfo[agent].color); c.classList.add('by'); c.dataset.who = crewInfo[agent].name; }
  return c;
}
function toolCard0(id, name) {
  if (name === 'plan_game' || name === 'finish' || name === 'update_plan') return null;
  if (name === 'design_game') return designPending(id);
  if (CODE_TOOLS.includes(name)) return codeCard(id, name);
  const [ic, label] = TOOL_META[name] || ['⚙️', name];
  const c = document.createElement('div'); c.className = 'tcard run';
  c.innerHTML = '<div class="th"><span class="ic">' + ic + '</span><span class="lb">' + label + '</span><span class="st">进行中…</span></div><div class="tb"></div>';
  msgs.appendChild(c); scroll();
  cards[id] = c; return c;
}
function pill(text, color, done) { return '<span class="pill' + (done ? ' done' : '') + '"><i style="background:' + (color || '#a78bfa') + '"></i>' + esc(text) + '</span>'; }

function renderPlan(p) {
  planEl = document.createElement('div'); planEl.className = 'plan';
  planSteps = p.steps || []; planIdx = 0;
  planEl.innerHTML = '<h4>🎮 ' + esc(p.title) + '</h4><div class="pt">' + esc(p.pitch || '') + '</div><div class="tags"><span class="badge">' + (p.dimension === '3d' ? '3D' : '2D') + '</span><span class="badge">' + esc(STYLE_CN[p.style] || p.style || '') + '风</span></div><ol>' + planSteps.map(s => '<li>' + esc(s) + '</li>').join('') + '</ol>';
  msgs.appendChild(planEl); scroll(); markPlan();
  $('#title').value = p.title; document.title = p.title + ' · 造梦';
  $('#dimBadge').textContent = p.dimension === '3d' ? '3D' : '2D';
}
function markPlan() { if (!planEl) return; $$('li', planEl).forEach((li, i) => { li.classList.toggle('done', i < planIdx); li.classList.toggle('cur', i === planIdx); }); }
function advancePlan(stepName) {
  if (!planEl || planIdx >= planSteps.length) return;
  // move forward when a build step starts (simple heuristic: each entity batch / world / asset call advances one)
  planIdx = Math.min(planIdx + 1, planSteps.length - 1);
  markPlan();
}

// ---------------- code engine: design card, code cards, tests ----------------
function designPending(id) {
  const c = document.createElement('div'); c.className = 'design pending';
  c.innerHTML = '<div class="dh">🧠 <b>设计师正在构思</b><span class="st">理解你的想法…</span></div><div class="dsk"><i></i><i></i><i></i></div>';
  msgs.appendChild(c); scroll(); cards[id] = c; return c;
}
const SECTION_CN = ['参考游戏', '核心循环', '规则', '布局', '模块', '里程碑', '搭建步骤', '配色'];
function renderDesign(d, el) {
  el = el || designEl || document.createElement('div');
  el.className = 'design';
  const sw = (d.palette || []).map(h => '<i style="background:' + esc(h) + '"></i>').join('');
  el.innerHTML = '<div class="dh">🎮 <b>' + esc(d.title) + '</b><span class="sw">' + sw + '</span></div>'
    + '<div class="pt">' + esc(d.pitch) + '</div>'
    + (d.closest_game ? '<div class="ref">参考 <b>' + esc(d.closest_game) + '</b>，但：' + d.differences.map(x => '<span>' + esc(x) + '</span>').join('') + '</div>' : '')
    + '<details><summary>玩法与规则</summary><p>' + esc(d.core_loop) + '</p><ul>' + d.rules.map(r => '<li>' + esc(r) + '</li>').join('') + '</ul>'
    + '<p class="dim">布局：' + esc(d.layout) + '</p><p class="dim">模块：' + d.modules.map(m => '<code>' + esc(m.file) + '</code> ' + esc(m.role)).join('；') + '</p></details>'
    + '<div class="road"></div>'
    + '<div class="fix">觉得哪里不对？直接告诉我，比如"规则改成……"，我会修改方案再继续。</div>';
  designEl = el; renderRoad(d);
  if (!el.parentElement) msgs.appendChild(el);
  scroll();
}
function renderRoad(d) {
  if (!designEl || !d) return;
  const r = designEl.querySelector('.road');
  r.innerHTML = d.milestones.map((m, i) => '<div class="ms ' + (i < d.current ? 'done' : i === d.current ? 'cur' : '') + '"><b>' + esc(m.id) + '</b><span>' + esc(m.name) + '</span><em title="' + esc(m.acceptance.join('\n')) + '">' + esc(m.goal) + '</em></div>').join('')
    + (d.build_steps?.length && d.current === 0 ? '<ol class="steps">' + d.build_steps.map(s => '<li>' + esc(s) + '</li>').join('') + '</ol>' : '');
  markSteps();
}
let stepsDone = 0;
function markSteps() { if (!designEl) return; $$('.steps li', designEl).forEach((li, i) => { li.classList.toggle('done', i < stepsDone); li.classList.toggle('cur', i === stepsDone); }); }
function codeCard(id, name) {
  const [ic, label] = TOOL_META[name];
  const c = document.createElement('div'); c.className = 'tcard code run';
  c.innerHTML = '<div class="th"><span class="ic">' + ic + '</span><span class="lb">' + label + '</span><span class="st">' + (name === 'run_test' ? '在真实引擎里试玩…' : '构思中…') + '</span></div>';
  msgs.appendChild(c); scroll(); cards[id] = c; return c;
}
/** Live code while the model is still typing it: an open block that follows the newest line. */
function liveCode(card, code) {
  let box = card.querySelector('details.src');
  if (!box) { box = document.createElement('details'); box.className = 'src'; box.open = true; box.innerHTML = '<summary>实时代码</summary><pre></pre>'; card.appendChild(box); }
  const pre = box.querySelector('pre');
  if (pre.textContent.length > code.length + 200) return;
  pre.textContent = code;
  pre.scrollTop = pre.scrollHeight;
}
/** Reveals code with a typewriter effect inside a collapsed block. */
function typeCode(card, code) {
  let box = card.querySelector('details.src');
  if (!box) { box = document.createElement('details'); box.className = 'src'; box.innerHTML = '<summary>查看代码</summary><pre></pre>'; card.appendChild(box); }
  const pre = box.querySelector('pre');
  if (box.open && pre.textContent) { pre.textContent = code; box.open = false; box.querySelector('summary').textContent = '查看代码'; return; }
  const lines = code.split('\n'); let i = 0;
  pre.textContent = '';
  const tick = () => { if (i >= lines.length) return; pre.textContent += lines.slice(i, i + 3).join('\n') + '\n'; i += 3; if (box.open) pre.scrollTop = pre.scrollHeight; setTimeout(tick, 16); };
  tick();
}
function testCard(ev) {
  const d = document.createElement('div'); d.className = 'check ' + (ev.ok ? 'ok' : 'bad');
  const errs = (ev.errors || []).map(e => '<li>❌ ' + esc(e.file + (e.line ? ':' + e.line : '') + ' ' + e.message) + '</li>');
  const chks = (ev.checks || []).map(c => '<li>' + (c.ok ? '✅ ' : '⚠️ ') + esc(c.what) + '</li>');
  const res = ev.result === 'win' ? '，自动试玩打赢了 🏆' : ev.result === 'lose' ? '，自动试玩输了一局' : '';
  d.innerHTML = '🧪 <b>第 ' + ev.run + ' 次试玩自测</b>：' + (ev.ok ? '全部通过 ✅' + res : !ev.loaded ? '代码还跑不起来，AI 正在修' : '有 ' + ((ev.errors || []).length + (ev.checks || []).filter(c => !c.ok).length) + ' 处问题，AI 正在修') + ' <span class="dim">' + Math.round((ev.ms || 0) / 100) / 10 + 's</span>'
    + '<ul>' + errs.concat(chks).slice(0, 10).join('') + '</ul>'
    + (ev.shot ? '<img class="shot" src="' + esc(ev.shot) + '" title="AI 自测时看到的画面">' : '');
  const im = d.querySelector('img.shot'); if (im) im.onclick = () => im.classList.toggle('big');
  msgs.appendChild(d); scroll();
}

// ---------------- build HUD ----------------
function showHud(title, sub) { $('#buildHud').hidden = false; $('#frameWrap').classList.add('building'); if (title) $('#bhTitle').textContent = title; if (sub !== undefined) $('#bhSub').textContent = sub; updateHud(); }
function hideHud() { $('#buildHud').hidden = true; $('#frameWrap').classList.remove('building'); }
function updateHud() { const pct = opsPending ? Math.min(100, opsDone / opsPending * 100) : 0; $('#bhBar').style.width = pct + '%'; }

// ---------------- assets shelf ----------------
function shelfItem(a) {
  if ($('#shelfWrap').hidden) { $('#shelfWrap').hidden = false; layout(); }
  let el = assetEls[a.id];
  if (!el) { el = document.createElement('div'); el.className = 'asset'; assetEls[a.id] = el; $('#shelf').prepend(el); }
  const st = a.state || 'pending';
  el.className = 'asset ' + st;
  const isImg = ['sprite', 'background', 'texture'].includes(a.kind);
  let im = ASSET_ICON[a.kind] || '📦';
  if (st === 'ready' && isImg && a.url) im = '<img src="' + esc(a.url) + '">';
  else if (a.preview) im = '<img class="prev" src="' + esc(a.preview) + '">';
  if (st === 'ready' && a.kind === 'music' && a.url) im = '<span style="cursor:pointer" data-play="' + esc(a.url) + '">▶️</span>';
  const stg = st === 'ready' ? '✅ 完成' + (a.ms ? ' ' + Math.round(a.ms / 1000) + 's' : '') : st === 'failed' ? '⚠️ 失败' : (STAGE_CN[a.stage] || '生成中');
  el.innerHTML = '<div class="im' + (a.kind === 'background' ? ' bg' : '') + '">' + im + '</div><span class="stg">' + stg + '</span><div class="nm" title="' + esc(a.prompt || '') + '">' + esc(a.name || a.id) + '</div>';
  el.title = st === 'failed' ? '点击重试生成' : (a.prompt || '');
  el.onclick = st === 'failed' ? () => api('/projects/' + pid + '/retry_assets', { body: {} }).then(() => toast('🔁 正在重新生成失败的素材')) : null;
  if (st === 'failed') el.style.cursor = 'pointer';
  const pl = el.querySelector('[data-play]');
  if (pl) pl.onclick = () => { const au = new Audio(pl.dataset.play); au.play(); setTimeout(() => au.pause(), 8000); };
  $('#shelfHint').textContent = Object.keys(assetEls).length + ' 个素材';
}

// ---------------- SSE ----------------
// Live build progress. SSE is the fast path, but mobile networks and tunnels buffer
// text/event-stream until a full frame accumulates, which makes the whole build look frozen.
// So: whenever the stream is quiet while a build runs, poll the same events by seq - whatever
// arrives first wins, and duplicates are dropped by seq.
let es = null, lastSeq = 0, lastEventAt = 0, gotData = false;
const seenSeq = new Set();
function route(ev) {
  if (typeof ev.seq === 'number') {
    if (seenSeq.has(ev.seq)) return;
    seenSeq.add(ev.seq);
    if (ev.seq > lastSeq) lastSeq = ev.seq;
    if (seenSeq.size > 4000) seenSeq.clear();
  }
  lastEventAt = Date.now(); gotData = true;
  handle(ev);
}
function connect() {
  es = new EventSource('/api/projects/' + pid + '/events');
  es.onmessage = e => route(JSON.parse(e.data));
  setInterval(pollEvents, 4000);
}
async function pollEvents() {
  if (gotData && Date.now() - lastEventAt < 12000) return;   // the stream is healthy
  try {
    const r = await api('/projects/' + pid + '/events?since=' + lastSeq);
    for (const ev of r.events || []) route(ev);
  } catch { /* offline; the next tick retries */ }
}
/** Sends a crew update to the preview (the drone needs its name/colour the first time it appears). */
function rtCrew(agent, extra) { const w = crewInfo[agent]; if (w) rt.send({ type: 'crew', agent, name: w.name, color: w.color, ...extra }); }

/** Design card that fills in field by field while the planner is still writing it. */
function renderDesignLive(p, el) {
  if (!el) return;
  const sw = (p.palette || []).filter(h => /^#[0-9a-f]{6}$/i.test(h)).map(h => '<i style="background:' + esc(h) + '"></i>').join('');
  const li = a => (a || []).filter(x => typeof x === 'string' && x).map(x => '<li>' + esc(x) + '</li>').join('');
  el.innerHTML = '<div class="dh">📝 <b>' + esc(p.title || '构思中…') + '</b><span class="sw">' + sw + '</span><span class="st">策划师正在写方案</span></div>'
    + (p.pitch ? '<div class="pt">' + esc(p.pitch) + '</div>' : '')
    + ((p.assets || []).length ? '<div class="ref">🎨 要画：' + p.assets.filter(a => a && a.name).map(a => '<span>' + esc(a.name) + '</span>').join('') + '</div>' : '')
    + (p.closest_game ? '<div class="ref">参考 <b>' + esc(p.closest_game) + '</b>' + ((p.differences || []).length ? '，但：' + p.differences.filter(Boolean).map(x => '<span>' + esc(x) + '</span>').join('') : '') + '</div>' : '')
    + (p.core_loop ? '<p class="live">🔁 ' + esc(p.core_loop) + '</p>' : '')
    + ((p.rules || []).length ? '<ul class="live">' + li(p.rules.slice(-5)) + '</ul>' : '')
    + ((p.modules || []).length ? '<div class="mods">' + p.modules.filter(m => m && m.file).map(m => '<span class="' + (m.owner === 'gameplay' ? 'gp' : 'sc') + '">' + esc(m.file) + '</span>').join('') + '</div>' : '')
    + ((p.milestones || []).length ? '<div class="road">' + p.milestones.filter(m => m && m.id).map(m => '<div class="ms"><b>' + esc(m.id) + '</b><span>' + esc(m.name || '') + '</span><em>' + esc(m.goal || '') + '</em></div>').join('') + '</div>' : '')
    + '<div class="dsk"><i></i><i></i><i></i></div>';
  el.classList.add('pending', 'streaming');
  scroll();
}

function crewEvent(ev) {
  const a = ev.agent;
  switch (ev.type) {
    case 'turn_start':
      if (ev.crew) crewInfo = ev.crew;
      if (ev.engine === 'code') { crewReset(ev.first); rt.send({ type: 'crew_clear' }); if (ev.first) rt.send({ type: 'blueprint', status: '策划师正在构思…' }); }
      break;
    case 'phase':
      crewPhase(ev.phase === 'code' ? 'integrate' : ev.phase);
      for (const x of ev.agents || []) { crewLane(x); rtCrew(x, { state: 'thinking' }); }
      break;
    case 'crew':
      crewSet(a, { state: ev.state, text: ev.text, pct: ev.state === 'done' ? 100 : undefined });
      rtCrew(a, { state: ev.state, text: ev.text || '' });
      if (ev.state === 'done') { crewThinkEnd(a); setTimeout(() => rtCrew(a, a === 'A' ? { state: 'gone' } : { text: '' }), 2500); }
      break;
    case 'thinking': if (a) crewThink(a, ev.text); break;
    case 'tool_start':
      if (!a) break;
      crewThinkEnd(a);
      if (ev.name === 'design_game') { crewSet(a, { state: 'coding', text: '✍️ 正在写方案…', pct: 5 }); rtCrew(a, { state: 'coding', text: '写方案中' }); }
      else if (ev.name === 'write_module' || ev.name === 'patch_module') { crewSet(a, { state: 'coding', text: '⌨️ 开始写…' }); rtCrew(a, { state: 'coding', text: '' }); }
      else if (ev.name === 'run_test') { crewPhase('test'); crewSet(a, { state: 'testing', text: '🧪 在真实引擎里试玩…' }); rtCrew(a, { state: 'testing', text: '试玩自测中', code: '' }); }
      break;
    case 'tool_progress':
      if (!a) break;
      if (ev.name === 'design_game' && ev.partial) {
        const p = ev.partial, n = ['title', 'pitch', 'palette', 'art_bible', 'assets', 'closest_game', 'core_loop', 'rules', 'layout', 'modules', 'milestones', 'build_steps'].filter(k => k in p).length;
        crewSet(a, { text: '✍️ ' + (p.title ? '「' + p.title + '」' : '') + ' 已写 ' + n + '/12 部分', pct: n / 12 * 100 });
        rt.send({ type: 'blueprint', ...p, status: '策划师正在写方案… ' + n + '/12' });
        renderDesignLive(p, cards[ev.id]);
      } else if ((ev.name === 'write_module' || ev.name === 'patch_module') && (ev.tail || ev.file)) {
        const c = crew[a];
        crewSet(a, { text: '⌨️ ' + (ev.file || '') + (ev.total ? ' · ' + ev.total + ' 行' : '') + (ev.step ? ' — ' + ev.step : '') });
        if (ev.code && cards[ev.id]) liveCode(cards[ev.id], ev.code);
        rtCrew(a, { state: 'coding', code: ev.tail || '', text: ev.step ? ev.step.slice(0, 14) : '' });
        if (ev.file && c && c.lastFile !== ev.file) { c.lastFile = ev.file; rt.send({ type: 'blueprint_mark', file: ev.file, text: '[' + (crewInfo[a]?.name || a) + ' 写入中]' }); }
      }
      break;
    case 'code_write':
      if (a && crew[a]) { crew[a].files++; crewSet(a, { text: '✅ ' + ev.file + ' ' + ev.lines + ' 行' + (ev.patch ? '（修改）' : ''), pct: Math.min(95, crew[a].files * 22) }); rtCrew(a, { code: '' }); rt.send({ type: 'blueprint_mark', file: ev.file, text: '[完成]' }); }
      break;
    case 'compile':
      if (a) crewSet(a, { text: ev.ok ? '🟢 ' + ev.files.join('、') + ' 编译通过' : '🔴 ' + ev.files.join('、') + ' 有 ' + ev.errors.length + ' 处错误，正在修' });
      if (a) rtCrew(a, { text: ev.ok ? '编译通过' : '有错，修一下' });
      break;
    case 'test':
      if (a) crewSet(a, { state: ev.ok ? 'done' : 'coding', text: ev.ok ? '🎉 自测通过' : '🔧 自测没过，正在修（第 ' + ev.run + ' 次）' });
      if (a) rtCrew(a, { state: ev.ok ? 'done' : 'coding', text: ev.ok ? '自测通过!' : '我来修' });
      break;
    case 'turn_end':
      crewPhase('done');
      for (const [k, c] of Object.entries(crew)) { if (c.state !== 'done') crewSet(k, { state: 'done', pct: 100 }); crewThinkEnd(k); }
      $('#crewClock').textContent = '用时 ' + fmt(ev.ms || (Date.now() - turnT0));
      turnT0 = 0;
      setTimeout(() => rt.send({ type: 'crew_clear' }), 3000);
      setTimeout(() => { if (!running) crewShow(false); }, 9000);
      break;
  }
}

function handle(ev) {
  if (ev.agent || ['turn_start', 'phase', 'turn_end'].includes(ev.type)) { try { crewEvent(ev); } catch (e) { console.error(e); } }
  switch (ev.type) {
    case 'turn_start': if (ev.model) $('#modelHint').textContent = '🧠 ' + ev.model; setRunning(true); opsPending = 0; opsDone = 0; showHud('AI 正在构思…', '理解你的想法'); break;
    case 'thinking': case 'crew': case 'compile': break;
    case 'text':
      if (curText && (ev.agent || '') !== curAgent) endStream();
      if (!curText) { curText = addAi('', true, ev.agent); curAgent = ev.agent || ''; }
      curText.textContent += ev.delta; scroll();
      $('#bhSub').textContent = curText.textContent.slice(-60);
      break;
    case 'tool_start': {
      toolCard(ev.id, ev.name, ev.agent);
      const [ic, label] = TOOL_META[ev.name] || ['⚙️', ev.name];
      showHud(ic + ' ' + label + '…', '');
      if (['add_entities', 'set_world', 'generate_assets', 'set_player', 'check_game'].includes(ev.name) && planIdx >= 0) {}
      break;
    }
    case 'tool_progress': {
      const c = cards[ev.id];
      if (ev.step) { if (c) c.querySelector('.lb').textContent = '搭建：' + ev.step; $('#bhTitle').textContent = '🧱 ' + ev.step; }
      if (ev.count !== undefined) { if (c) c.querySelector('.st').textContent = '设计中 · ' + ev.count + ' 个'; $('#bhSub').textContent = ev.last ? '正在设计：' + ev.last : ''; }
      if (ev.title && !planEl) { $('#bhTitle').textContent = '📋 规划：' + ev.title; }
      if (ev.name === 'design_game' && c) { c.querySelector('.st').textContent = ev.title ? '「' + ev.title + '」' + (ev.sections ? ' · ' + SECTION_CN[Math.min(ev.sections, 8) - 1] : '') : '构思中…'; $('#bhSub').textContent = ev.sections ? '正在想：' + SECTION_CN[Math.min(ev.sections, 8) - 1] : ''; }
      if ((ev.name === 'write_module' || ev.name === 'patch_module') && c) {
        if (ev.step) { c.querySelector('.lb').textContent = '正在做：' + ev.step; $('#bhTitle').textContent = '⌨️ 正在做：' + ev.step; }
        c.querySelector('.st').textContent = (ev.file ? ev.file + ' · ' : '') + (ev.lines ? ev.lines + ' 行' : '');
        $('#bhSub').textContent = ev.lines ? '已写 ' + ev.lines + ' 行代码' : '';
      }
      break;
    }
    case 'plan': renderPlan(ev); break;
    case 'phase': showHud(ev.phase === 'design' ? '🧠 设计玩法中' : '⌨️ 开始写代码', ev.text); break;
    case 'design': {
      const pend = Object.values(cards).find(c => c.classList.contains('design'));
      proj.game.design = ev.design; stepsDone = 0;
      renderDesign(ev.design, pend);
      $('#title').value = ev.design.title; document.title = ev.design.title + ' · 造梦';
      break;
    }
    case 'roadmap': if (proj.game.design) { proj.game.design.milestones = ev.milestones; proj.game.design.current = ev.current; renderRoad(proj.game.design); } break;
    case 'code_write': {
      const c = cards[ev.id] || Object.values(cards).filter(x => x.classList.contains('code') && x.classList.contains('run')).pop();
      if (c) { c.querySelector('.lb').textContent = (ev.patch ? '修改：' : '完成：') + (ev.step || ev.file); c.querySelector('.st').textContent = ev.file + ' · ' + ev.lines + ' 行'; typeCode(c, ev.preview || ''); }
      if (!ev.patch) { stepsDone++; markSteps(); }
      break;
    }
    case 'test_start': $('#bhTitle').textContent = '🧪 在真实引擎里试玩自测…'; $('#bhSub').textContent = 'AI 会自己点一遍，看能不能玩通'; break;
    case 'test': testCard(ev); break;
    case 'ops':
      opsPending += ev.ops.length; updateHud();
      for (const o of ev.ops) {
        if (o.op === 'asset') { proj.game.assets[o.id] = { ...(proj.game.assets[o.id] || {}), id: o.id, kind: o.kind, state: 'pending', url: '' }; }
        if (o.op === 'add' || o.op === 'update') proj.game.entities[o.id] = o.entity;
        if (o.op === 'remove') delete proj.game.entities[o.id];
        if (o.op === 'set_player') proj.game.player = o.player;
        if (o.op === 'set_world') proj.game.world = o.world;
        if (o.op === 'set_rules') proj.game.rules = o.rules;
        if (o.op === 'set_meta') proj.game.meta = o.meta;
        if (o.op === 'code') proj.game.code = { files: o.files };
      }
      if (mode !== 'edit') setMode('edit', true);
      rt.send({ type: 'ops', ops: ev.ops });
      break;
    case 'tool_done': {
      const c = cards[ev.id];
      if (ev.name === 'add_entities' || ev.name === 'set_world' || ev.name === 'generate_assets') advancePlan();
      if (!c) break;
      if (c.classList.contains('code')) { c.classList.remove('run'); if (c.querySelector('.st').textContent.includes('…')) c.querySelector('.st').textContent = '✓'; break; }
      c.classList.remove('run');
      c.querySelector('.st').textContent = '✓ 完成';
      const tb = c.querySelector('.tb');
      const inp = ev.input || {};
      if (ev.name === 'add_entities') { c.querySelector('.lb').textContent = '搭建：' + (inp.step || ''); tb.innerHTML = (inp.entities || []).map(e => pill(e.name || e.id, KIND_COLOR[e.kind], true)).join(''); }
      else if (ev.name === 'update_entities') { c.querySelector('.lb').textContent = '调整：' + (inp.step || ''); tb.innerHTML = (inp.changes || []).map(e => pill((proj.game.entities[e.id]?.name || e.id) + ' · ' + e.keys.join('/'), '#fbbf24', true)).join(''); }
      else if (ev.name === 'remove_entities') tb.innerHTML = (inp.ids || []).map(id => pill(id, '#f87171', true)).join('');
      else if (ev.name === 'generate_assets') tb.innerHTML = (inp.assets || []).map(a => pill((ASSET_ICON[a.kind] || '') + ' ' + a.name, '#c084fc', true)).join('');
      else if (ev.name === 'set_world') tb.innerHTML = Object.entries(inp.world || {}).filter(([k, v]) => /color/.test(k)).map(([k, v]) => pill(k.replace('_color', '').replace('background', '背景').replace('sky', '天空').replace('ground', '地面').replace('horizon', '地平线'), v, true)).join('');
      else if (ev.name === 'set_rules') { const r = inp.rules || {}; tb.innerHTML = pill({ goal: '到达终点', collect_all: '收集全部', defeat_all: '击败全部', score: '达到分数', survive: '坚持生存' }[r.win] || r.win || '', '#34d399', true) + (r.lives ? pill('♥ ' + r.lives + ' 条命', '#f87171', true) : '') + (r.time_limit ? pill('⏱ ' + r.time_limit + 's', '#22d3ee', true) : ''); }
      else if (ev.name === 'set_player') tb.innerHTML = pill(inp.player?.name || '主角', '#4cc9f0', true);
      else if (ev.name === 'check_game') { c.remove(); delete cards[ev.id]; }
      if (!tb.innerHTML) tb.remove();
      scroll();
      break;
    }
    case 'check': {
      const d = document.createElement('div'); d.className = 'check ' + (ev.ok && !ev.issues.length ? 'ok' : ev.ok ? 'ok' : 'bad');
      d.innerHTML = '🔍 <b>可玩性自检</b>：' + ev.counts.platforms + ' 平台 · ' + ev.counts.collectibles + ' 收集物 · ' + ev.counts.enemies + ' 敌人 — ' + (ev.issues.length ? '发现 ' + ev.issues.length + ' 处可以改进，AI 正在修复' : '全部通过 ✅') + (ev.issues.length ? '<ul>' + ev.issues.slice(0, 6).map(i => '<li>' + (i.level === 'error' ? '❌ ' : '⚠️ ') + esc(i.text) + '</li>').join('') + '</ul>' : '');
      msgs.appendChild(d); scroll();
      break;
    }
    case 'asset': case 'asset_stage': {
      const a = proj.game.assets[ev.id] = { ...(proj.game.assets[ev.id] || {}), ...ev, type: undefined };
      if (ev.type === 'asset') a.state = ev.state;
      shelfItem(a);
      if (ev.type === 'asset' && (ev.state === 'ready' || ev.state === 'failed')) {
        rt.send({ type: 'asset', id: ev.id, kind: ev.kind, state: ev.state, url: ev.url || '' });
        if (ev.state === 'ready') toast('🎨 「' + (ev.name || ev.id) + '」生成好了！');
      }
      break;
    }
    case 'error': endStream(); { const d = document.createElement('div'); d.className = 'err'; d.textContent = '⚠️ ' + ev.message; msgs.appendChild(d); scroll(); } break;
    case 'turn_end':
      endStream();
      for (const c of Object.values(cards)) if (c.classList.contains('run')) { c.classList.remove('run'); c.querySelector('.st').textContent = '—'; }
      if (planEl) { planIdx = planSteps.length; markPlan(); planEl = null; }
      if (ev.summary) addAi(ev.summary);
      addSugg(ev.suggestions);
      setRunning(false);
      $('#bhTitle').textContent = '✨ 搭建完成'; $('#bhSub').textContent = '点「▶ 试玩」玩一玩，或继续告诉我怎么改';
      opsDone = opsPending; updateHud();
      setTimeout(() => { if (!running) hideHud(); }, 4000);
      break;
  }
}

function setRunning(v) {
  running = v;
  $('#sendBtn').hidden = v; $('#stopBtn').hidden = !v;
  $('#input').placeholder = v ? 'AI 团队正在搭建，看上面的画面 ↑' : '告诉 AI 你想怎么改…';
  if (v) setQuick([]);
  layout();
}

// ---------------- mobile layout ----------------
/** Quick-reply chips above the composer (AI suggestions; tap = send). */
function setQuick(list) {
  const q = $('#quick'); q.innerHTML = '';
  for (const s of (list || []).slice(0, 4)) { const b = document.createElement('button'); b.textContent = '💡 ' + s; b.onclick = () => { $('#input').value = s; send(); }; q.appendChild(b); }
  layout();
}
const portrait = () => (proj?.game?.meta?.orientation || qs.get('ori')) === 'portrait';
/** Sizes the game frame to its aspect inside the stage, and the conversation to the space left. */
function layout() {
  const app = $('#app'), stage = $('#stage'), fw = $('#frameWrap');
  if (!app || !stage) return;
  const por = portrait();
  document.body.classList.toggle('por', por); document.body.classList.toggle('lan', !por);
  const ch = $('#composer').offsetHeight; app.style.setProperty('--composerH', ch + 'px');
  const sideways = matchMedia('(orientation:landscape) and (max-height:520px)').matches;
  const W = stage.clientWidth - 16, H = stage.clientHeight;
  let w, h;
  if (mode === 'play' || sideways) { const r = por ? 9 / 16 : 16 / 9; w = Math.min(W, H * r); h = w / r; }
  else if (por) { w = W; h = H; }                           // portrait games fill the screen, chat floats over the bottom
  else { w = W; h = w * 9 / 16; }                            // landscape: 16:9 strip at the top
  app.style.setProperty('--frameW', Math.floor(w) + 'px'); app.style.setProperty('--frameH', Math.floor(h) + 'px');
  const crewH = $('#crew').hidden ? 0 : $('#crew').offsetHeight + 12; app.style.setProperty('--crewH', crewH + 6 + 'px');
  if (!sideways) {
    // landscape: chat takes everything under the stage (+ crew strip); portrait: lower ~40% of the game
    const top = $('.etop').offsetHeight;
    const used = por ? 0 : h + (stage.querySelector('.crew:not([hidden])')?.offsetHeight || 0) + ($('#shelfWrap').hidden ? 0 : 58) + 12;
    const feedH = por ? Math.round((app.clientHeight - top - ch) * 0.42) : Math.max(120, app.clientHeight - top - ch - used);
    app.style.setProperty('--feedH', feedH + 'px');
  }
}
addEventListener('resize', layout);
visualViewport?.addEventListener('resize', () => { layout(); scroll(); });
new ResizeObserver(layout).observe(document.body);
// pull the grip (or tap it) to read the whole conversation; the game stays live behind it
(function feedDrag() {
  const feed = $('#feed'), grip = $('#grip');
  const set = o => { feed.dataset.open = o ? '1' : '0'; $('#gripTxt').textContent = o ? '收起' : '对话记录'; scroll(); };
  grip.onclick = () => set(feed.dataset.open !== '1');
  let y0 = null;
  grip.addEventListener('touchstart', e => { y0 = e.touches[0].clientY; }, { passive: true });
  grip.addEventListener('touchend', e => { if (y0 == null) return; const dy = e.changedTouches[0].clientY - y0; if (Math.abs(dy) > 24) set(dy < 0); y0 = null; });
  $('#msgs').addEventListener('click', e => { if (e.target.closest('button,a,details,summary,img')) return; });
})();
$('#moreBtn').onclick = e => { e.stopPropagation(); $('#moreMenu').hidden = !$('#moreMenu').hidden; };
document.addEventListener('click', e => { if (!e.target.closest('#moreMenu')) $('#moreMenu').hidden = true; });
// grow the composer with its text; Enter sends on desktop, the keyboard's send key on phones
$('#input').addEventListener('input', () => { const t = $('#input'); t.style.height = 'auto'; t.style.height = Math.min(110, t.scrollHeight) + 'px'; layout(); });
$('#input').addEventListener('focus', () => setTimeout(scroll, 300));

// ---------------- actions ----------------
async function send() {
  const t = $('#input').value.trim();
  if (!t || running) return;
  $('#input').value = '';
  addUser(t);
  setRunning(true);
  try {
    const sel = selection ? (selection === '__player' ? '主角' : (proj.game.entities[selection]?.name || selection) + '（id=' + selection + '）') : '';
    await api('/projects/' + pid + '/chat', { body: { text: t, dimension: qs.get('dim') || proj.game.meta.dimension, selection: sel } });
  } catch (e) { setRunning(false); toast('发送失败：' + e.message); }
}
$('#sendBtn').onclick = send;
$('#input').onkeydown = e => { if (e.key === 'Enter' && !e.shiftKey) { e.preventDefault(); send(); } };
$('#stopBtn').onclick = () => api('/projects/' + pid + '/stop', { body: {} });

function setSelection(id) {
  selection = id || null;
  const chip = $('#selChip');
  if (!selection) { chip.hidden = true; return; }
  const nm = selection === '__player' ? '主角' : (proj.game.entities[selection]?.name || selection);
  chip.hidden = false;
  chip.innerHTML = '🎯 已选中「' + esc(nm) + '」— 直接说要怎么改它，也可以在画面里拖动 <button>✕</button>';
  chip.querySelector('button').onclick = () => setSelection(null);
}

function setMode(m, silent) {
  mode = m;
  $$('#modeSeg button').forEach(b => b.classList.toggle('on', b.dataset.m === m));
  document.body.classList.toggle('playing', m === 'play'); layout();
  if (!silent) { loadRuntime(m); if (m === 'play') { setSelection(null); setTimeout(() => rt.focus(), 100); } }
}
$$('#modeSeg button').forEach(b => b.onclick = () => { if (running && b.dataset.m === 'play') { toast('AI 搭建完成后再试玩哦'); return; } setMode(b.dataset.m); });
$('#frameBtn').onclick = () => rt.send({ type: 'frame' });
let muted = false;
$('#muteBtn').onclick = () => { muted = !muted; rt.send({ type: 'mute', value: muted }); $('#muteBtn').textContent = muted ? '🔇 已静音' : '🔊 声音'; };
$('#fsBtn').onclick = async () => { try { await $('#frameWrap').requestFullscreen?.(); await screen.orientation?.lock?.(portrait() ? 'portrait' : 'landscape'); } catch {} };

let coverT = 0;
async function maybeCover() {
  if (Date.now() - coverT < 20000 || (!Object.keys(proj.game.entities).length && !proj.game.code)) return;
  coverT = Date.now();
  const data = await rt.snapshot();
  if (data) api('/projects/' + pid + '/cover', { body: { data } });
}

$('#verBtn').onclick = async () => {
  proj = await api('/projects/' + pid);
  const m = document.createElement('div'); m.className = 'modal-bg';
  m.innerHTML = '<div class="modal"><h3>🕘 版本历史</h3><p>每次 AI 搭建完成都会自动存一个版本，随时可以回退</p><div class="ver-list">' + (proj.versions.slice().reverse().map(v => '<button data-v="' + v.v + '"><b>v' + v.v + '</b><span style="flex:1">' + esc((v.prompt || '').slice(0, 40)) + '</span><span class="hint">' + ago(v.t) + '</span></button>').join('') || '<div class="hint">还没有版本</div>') + '</div><div style="text-align:right;margin-top:14px"><button class="btn" id="vClose">关闭</button></div></div>';
  document.body.appendChild(m);
  $('#vClose', m).onclick = () => m.remove();
  $$('.ver-list button', m).forEach(b => b.onclick = async () => {
    proj = await api('/projects/' + pid + '/restore', { body: { v: +b.dataset.v } });
    m.remove(); loadRuntime('edit'); setMode('edit', true); addAi('已回到 v' + b.dataset.v + ' 版本 ↩️');
  });
};

// 3D covers read far better from the player's chase camera than from the editor overview,
// so briefly enter play view for the shot and then restore the previous mode.
async function coverShot() {
  if (proj.game.meta.dimension !== '3d' || mode === 'play') return rt.snapshot();
  const prev = mode;
  toast('正在为封面取景…', 2600);
  setMode('play');
  await new Promise(r => setTimeout(r, 2600));
  const shot = await rt.snapshot();
  setMode(prev);
  return shot;
}

$('#pubBtn').onclick = async () => {
  if (running) { toast('等 AI 搭建完再发布吧'); return; }
  if (!Object.keys(proj.game.entities).length && !proj.game.code?.files?.['main.gd']) { toast('游戏还是空的，先让 AI 搭建一下'); return; }
  const chk = await api('/projects/' + pid + '/check');
  const shot = await coverShot();
  const m = document.createElement('div'); m.className = 'modal-bg';
  m.innerHTML = '<div class="modal"><h3>🚀 发布游戏</h3><p>发布后所有人都能在「发现」里玩到，还可以 Remix 你的游戏</p>' + (shot ? '<div class="pub-cover" style="background-image:url(data:image/jpeg;base64,' + shot + ')"></div>' : '') + '<div class="field"><label>游戏名称</label><input id="pTitle" maxlength="40"></div><div class="field"><label>一句话介绍</label><input id="pPitch" maxlength="120"></div>' + (chk.ok ? '' : '<div class="check bad" style="margin:0 0 14px">⚠️ 自检发现问题：' + esc(chk.issues.filter(i => i.level === 'error').map(i => i.text).join('；')) + '</div>') + '<div style="display:flex;gap:10px;justify-content:flex-end"><button class="btn" id="pCancel">取消</button><button class="btn pri" id="pGo">发布 🚀</button></div></div>';
  document.body.appendChild(m);
  $('#pTitle', m).value = $('#title').value; $('#pPitch', m).value = proj.game.meta.pitch || '';
  $('#pCancel', m).onclick = () => m.remove();
  $('#pGo', m).onclick = async () => {
    $('#pGo', m).disabled = true;
    const r = await api('/projects/' + pid + '/publish', { body: { title: $('#pTitle', m).value, pitch: $('#pPitch', m).value, cover: shot } });
    m.innerHTML = '<div class="modal" style="text-align:center"><div style="font-size:54px">🎉</div><h3>发布成功！</h3><p>你的游戏已经出现在「发现」里了</p><div style="display:flex;gap:10px;justify-content:center"><a class="btn" href="/">去发现页</a><a class="btn pri" href="' + r.url + '">▶ 打开游戏页</a></div></div>';
    m.onclick = e => { if (e.target === m) m.remove(); };
  };
};
$('#title').onchange = () => { proj.game.meta.title = $('#title').value; };

// ---------------- boot ----------------
(async () => {
  proj = await api('/projects/' + pid);
  $('#title').value = proj.game.meta.title; document.title = proj.game.meta.title + ' · 造梦';
  $('#dimBadge').textContent = proj.game.meta.dimension === '3d' ? '3D' : '2D';
  $('#oriBadge').textContent = portrait() ? '竖屏' : '横屏';
  layout();
  $('#modelHint').textContent = '🧠 ' + proj.model;
  for (const m of proj.chat) { if (m.role === 'user') addUser(m.text); else { addAi(m.text, false, m.agent); if (m.suggestions) addSugg(m.suggestions); } }
  if (proj.game.design) { stepsDone = 99; renderDesign(proj.game.design); msgs.prepend(designEl); }
  if (!proj.chat.length) addAi('嗨！我们是你的 AI 团队 🛸 描述一下你想做什么游戏，我们会在上面的画面里一块一块把它搭出来给你看。');
  for (const a of Object.values(proj.game.assets || {})) shelfItem(a);
  const lastS = [...proj.chat].reverse().find(m => m.role !== 'user');
  if (lastS?.suggestions && !proj.running) setQuick(lastS.suggestions);
  connect();
  if (proj.running) setRunning(true);
  if (rt.ready) loadRuntime();
  const go = qs.get('go');
  if (go && !proj.chat.length) {
    history.replaceState(null, '', '/editor.html?id=' + pid + '&dim=' + (qs.get('dim') || '2d'));
    $('#input').value = go;
    setTimeout(send, 300);
  }
})();