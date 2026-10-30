// Game spec state machine: applies agent tool calls to a game project, emits build ops for the
// runtime to animate, and runs automatic playability checks.
import crypto from 'node:crypto';
import { analyzeReach, boxOf } from './reach.mjs';
import { jumpModel, jumpMetrics } from './physics.mjs';
import { parseLooseJson } from './json.mjs';

const KINDS_2D = {
  platform: [200, 40], collectible: [44, 44], enemy: [60, 60], hazard: [96, 36], goal: [72, 120], powerup: [52, 52],
  bouncer: [72, 32], sign: [160, 80], text: [300, 60], decor: [110, 110], checkpoint: [56, 110], player: [64, 64],
};
const KINDS_3D = {
  platform: [4, 0.6, 4], collectible: [0.8, 0.8, 0.8], enemy: [1.1, 1.1, 1.1], hazard: [2.5, 0.4, 2.5], goal: [1.4, 3.2, 1.4],
  powerup: [0.9, 0.9, 0.9], bouncer: [1.8, 0.4, 1.8], sign: [2.4, 1.4, 0.2], text: [3, 1, 0.1], decor: [2, 2.5, 2],
  checkpoint: [1, 2.2, 1], player: [0.9, 1.7, 0.9],
};
export const ENTITY_KINDS = Object.keys(KINDS_2D).filter(k => k !== 'player');
export const KIND_CN = { platform: '平台', collectible: '收集物', enemy: '敌人', hazard: '陷阱', goal: '终点', powerup: '道具', bouncer: '弹簧', sign: '告示牌', text: '文字', decor: '装饰', checkpoint: '检查点' };
const DEFAULT_COLOR = { platform: '#7cc44f', collectible: '#ffd23f', enemy: '#ef476f', hazard: '#b8c0cc', goal: '#ff6b6b', powerup: '#9b5de5', bouncer: '#ff4d6d', sign: '#c08552', text: '#ffffff', decor: '#57cc99', checkpoint: '#4cc9f0', player: '#4cc9f0' };
export const AMBIENTS = ['leaves', 'snow', 'dust', 'stars', 'bubbles', 'petals', 'none'];
export const PLATFORM_STYLES = ['grass', 'snow', 'stone', 'wood', 'candy', 'sand', 'ice', 'lava', 'cloud', 'metal'];
/** Pictographic emoji (runtime fonts cannot render them; the runtime strips them). */
export const EMOJI = /[\p{Extended_Pictographic}\u{1F1E6}-\u{1F1FF}\u{FE0F}]/u;
const TOPDOWN = ['topdown', 'top-down', 'shooter', 'maze', 'rpg'];
const MAX_ASSETS_PER_CALL = 8;
const MAX_ISSUES = 20;
const LONG_LEVEL = { '2d': 3000, '3d': 60 };

export function emptyGame() {
  return {
    meta: { title: '未命名游戏', dimension: '2d', genre: 'platformer', style: 'pixel', filter: 'pixel' },
    world: {},
    rules: { win: 'goal', lives: 3, instructions: '' },
    settings: { gravity: 1900 },
    player: { position: [0, 120], color: DEFAULT_COLOR.player },
    entities: {},
    sounds: {},
    assets: {},
  };
}

const num = (v, d) => (typeof v === 'number' && isFinite(v) ? v : d);
const isTopdown = game => game.meta.dimension !== '3d' && TOPDOWN.includes(game.meta.genre);

/** Tool arguments sometimes arrive as JSON strings; accept both. */
function asObject(v) {
  if (typeof v === 'string') v = parseLooseJson(v);
  return v && typeof v === 'object' && !Array.isArray(v) ? v : {};
}
function asArray(v) {
  if (typeof v === 'string') v = parseLooseJson(v);
  return Array.isArray(v) ? v : [];
}
const toNumbers = v => (Array.isArray(v) ? v.map(Number) : null);

/** Fill defaults and coerce position/size to the dimension's vector shape. */
export function normalizeEntity(id, raw, dim) {
  raw = asObject(raw);
  const table = dim === '3d' ? KINDS_3D : KINDS_2D;
  const kind = table[raw.kind] ? String(raw.kind) : 'decor';
  const def = table[kind];
  const e = { ...raw, kind };
  if (id !== 'player') e.id = id;
  const pos = toNumbers(raw.position) || (dim === '3d' ? [0, 1, 0] : [0, 0]);
  let size = toNumbers(raw.size) || def;
  if (dim === '3d') {
    if (pos.length === 2) pos.splice(1, 0, 1);
    if (size.length === 2) size = [size[0], size[1], size[0]];
    e.position = [num(pos[0], 0), num(pos[1], 1), num(pos[2], 0)];
    e.size = [0, 1, 2].map(i => Math.max(0.05, num(size[i], def[i])));
  } else {
    e.position = [num(pos[0], 0), num(pos[1], 0)];
    e.size = [0, 1].map(i => Math.max(4, num(size[i], def[i])));
  }
  if (!e.color) e.color = DEFAULT_COLOR[kind];
  return e;
}

const HEX = /^#(?:[0-9a-f]{3}|[0-9a-f]{6})$/i;

/** Validate optional meta fields chosen in plan_game. */
export function normalizeMeta(meta) {
  const out = { ...meta };
  const palette = asArray(meta.palette).map(String).filter(c => HEX.test(c)).slice(0, 5);
  if (palette.length >= 3) out.palette = palette; else delete out.palette;
  const bible = String(meta.art_bible || '').replace(/\s+/g, ' ').trim().slice(0, 300);
  if (bible) out.art_bible = bible; else delete out.art_bible;
  return out;
}

export function normalizeWorld(world) {
  const out = { ...world };
  if (out.ambient !== undefined && !AMBIENTS.includes(out.ambient)) delete out.ambient;
  if (out.platform_style !== undefined && !PLATFORM_STYLES.includes(out.platform_style)) delete out.platform_style;
  return out;
}

export function normalizeRules(rules) {
  const out = { ...rules };
  if (out.par_time !== undefined) {
    const t = Number(out.par_time);
    if (isFinite(t) && t > 0) out.par_time = Math.round(t); else delete out.par_time;
  }
  return out;
}

// ---------------------------------------------------------------- check_game

const nameOf = e => '「' + (e.name || e.id) + '」';
const fmt = (dim, v) => (dim === '3d' ? Number(v).toFixed(1) : String(Math.round(v)));

function ruleIssues(game, byKind) {
  const issues = [];
  const win = (game.rules && game.rules.win) || 'goal';
  if (win === 'goal' && !byKind('goal').length) issues.push({ level: 'error', text: '胜利条件是到达终点，但没有放置终点', hint: 'add_entities 添加一个 goal' });
  if (win === 'collect_all' && !byKind('collectible').length) issues.push({ level: 'error', text: '胜利条件是收集全部，但没有收集物', hint: '添加 collectible' });
  if (win === 'defeat_all' && !byKind('enemy').length) issues.push({ level: 'error', text: '胜利条件是击败全部敌人，但没有敌人', hint: '添加 enemy' });
  if (win === 'score' && num(game.rules.target_score, 0) <= 0) issues.push({ level: 'error', text: '分数目标未设置', hint: 'set_rules 设置 target_score' });
  if (!byKind('collectible').length) issues.push({ level: 'warn', text: '没有收集物，缺少目标感', hint: '加一些金币' });
  if (!String((game.rules && game.rules.instructions) || '').trim()) issues.push({ level: 'warn', text: '缺少操作/目标提示文字', hint: 'set_rules 写一句 instructions' });
  issues.push(...emojiIssues(game));
  return issues;
}

/** Player-visible strings that contain emoji (the runtime strips them, leaving gaps in the text). */
export function emojiIssues(game) {
  const where = [];
  const rules = game.rules || {};
  for (const k of ['instructions', 'win_text', 'lose_text']) if (EMOJI.test(String(rules[k] || ''))) where.push('rules.' + k);
  if (EMOJI.test(String((game.meta && game.meta.title) || ''))) where.push('meta.title');
  for (const e of Object.values(game.entities || {})) {
    if (EMOJI.test(String(e.text || '')) || EMOJI.test(String(e.name || ''))) where.push(e.id);
  }
  if (!where.length) return [];
  return [{ level: 'warn', text: '文字里有 emoji（运行时字体不支持，会被删掉）：' + where.slice(0, 6).join('、'), hint: 'update_entities / set_rules 改成纯文字' }];
}

const overlaps = (a, b) => a.l < b.r && b.l < a.r && a.bottom < b.top && b.bottom < a.top;
const TOPDOWN_MIN_MAP = 300;
const TOPDOWN_ACTORS = ['collectible', 'enemy', 'hazard', 'goal', 'powerup', 'checkpoint', 'bouncer'];

/** Top-down maps: no jumping, but things must not sit inside walls, on each other, or outside the map. */
function topdownIssues(game) {
  const issues = [];
  const ents = Object.values(game.entities || {});
  const walls = ents.filter(e => e.kind === 'platform' || ((e.kind === 'decor' || e.kind === 'sign') && e.solid === true));
  const actors = ents.filter(e => TOPDOWN_ACTORS.includes(e.kind));
  const player = { ...game.player, id: 'player', name: '主角' };
  const box = e => boxOf(e, '2d');
  for (const a of [player, ...actors]) {
    const wall = walls.find(w => overlaps(box(a), box(w)));
    if (wall) issues.push({ level: a === player ? 'error' : 'warn', text: nameOf(a) + '和墙体' + nameOf(wall) + '重叠，会卡住或拿不到', hint: '把它移到空地上' });
  }
  for (let i = 0; i < actors.length; i++) {
    for (let j = i + 1; j < actors.length; j++) {
      if (overlaps(box(actors[i]), box(actors[j]))) issues.push({ level: 'warn', text: nameOf(actors[i]) + '和' + nameOf(actors[j]) + '叠在一起', hint: '错开摆放' });
    }
    if (['enemy', 'hazard'].includes(actors[i].kind) && overlaps(box(player), box(actors[i]))) {
      issues.push({ level: 'error', text: '主角出生点和' + nameOf(actors[i]) + '重叠，一开局就受伤', hint: '把敌人/陷阱挪远一些' });
    }
  }
  const b = walls.length ? walls.map(box).reduce((u, w) => ({ l: Math.min(u.l, w.l), r: Math.max(u.r, w.r), bottom: Math.min(u.bottom, w.bottom), top: Math.max(u.top, w.top) })) : null;
  // Only meaningful when the walls enclose an area (a lone wall strip has no "inside").
  if (b && b.r - b.l > TOPDOWN_MIN_MAP && b.top - b.bottom > TOPDOWN_MIN_MAP) {
    for (const a of [player, ...actors]) {
      const p = a.position;
      if (p[0] < b.l || p[0] > b.r || p[1] < b.bottom || p[1] > b.top) issues.push({ level: a === player ? 'error' : 'warn', text: nameOf(a) + '在地图边界（墙体范围）之外', hint: '移回地图里面' });
    }
  }
  return issues;
}

function spawnInsideSolid(game, dim) {
  const p = game.player.position;
  for (const e of Object.values(game.entities || {})) {
    if (e.kind !== 'platform' && !(e.solid === true && e.kind === 'decor')) continue;
    const b = boxOf(e, dim);
    const inside = p[0] > b.l && p[0] < b.r && p[1] > b.bottom && p[1] < b.top && (dim !== '3d' || (p[2] > b.n && p[2] < b.f));
    if (inside) return e;
  }
  return null;
}

function approachHint(dim, a, metrics) {
  if (!a) return '最大跳高约 ' + fmt(dim, metrics.jumpHeight) + '，平地最远跳距约 ' + fmt(dim, metrics.jumpDistance);
  return '最近的起跳点' + '「' + a.fromName + '」：间隙 ' + fmt(dim, a.gap) + '、高差 ' + fmt(dim, a.rise) + '（此高度最远约 ' + fmt(dim, a.limitGap) + '，最高约 ' + fmt(dim, a.limitRise) + '）；缩小间距、降低高度或加台阶/弹簧';
}

/** Side-view / 3D: physics reachability from the spawn surface. */
function reachIssues(game, dim, metrics) {
  const issues = [];
  const ents = game.entities || {};
  const inside = spawnInsideSolid(game, dim);
  if (inside) issues.push({ level: 'error', text: '主角出生点卡在' + nameOf(inside) + '内部', hint: '把 player.position 抬到平台顶面上方' });
  const r = analyzeReach(game, dim);
  const path = { spawn: r.spawn, target: null, criticalPath: [], hardestJump: null, unreachable: [], isolated: r.isolated, tooHard: [] };
  if (!r.nodes.length) {
    issues.push({ level: 'error', text: '没有任何平台或地面，主角会直接掉下去', hint: 'add_entities 添加一块大地面 platform' });
    return { issues, path };
  }
  if (!r.spawn) {
    issues.push({ level: 'error', text: '主角出生点下方没有平台，开局就会掉下去', hint: '把主角放到某块平台正上方（脚底略高于平台顶面）' });
    return { issues, path };
  }
  const win = (game.rules && game.rules.win) || 'goal';
  const goals = Object.keys(r.items).filter(id => ents[id].kind === 'goal');
  const goal = goals.find(id => r.items[id].reachable) || goals[0];
  if (goal) {
    const info = r.items[goal];
    path.target = goal;
    if (info.reachable) {
      path.criticalPath = info.path;
      path.hardestJump = info.hardest;
      if (info.hardest.tooHard) {
        issues.push({ level: 'warn', text: '通往终点的必经一跳太难：' + nameOf(ents[info.hardest.from] || { id: info.hardest.from }) + '→' + nameOf(ents[info.hardest.to] || { id: info.hardest.to }) + '（间隙 ' + fmt(dim, info.hardest.gap) + '，高差 ' + fmt(dim, info.hardest.rise) + '，用掉 ' + Math.round(info.hardest.difficulty * 100) + '% 极限）', hint: '把间隙缩到 ' + fmt(dim, metrics.comfortGap) + ' 以内、高差 ' + fmt(dim, metrics.comfortRise) + ' 以内，或在中间加平台' });
      }
    } else if (win === 'goal') {
      issues.push({ level: 'error', text: '终点' + nameOf(ents[goal]) + '从出生点跳不到', hint: approachHint(dim, info.approach, metrics) });
    }
  }
  for (const [id, info] of Object.entries(r.items)) {
    const e = ents[id];
    if (info.reachable) {
      if (id !== goal && info.hardest.tooHard) path.tooHard.push(id);
      continue;
    }
    path.unreachable.push(id);
    if (id === goal && win === 'goal') continue;
    const level = win === 'collect_all' && e.kind === 'collectible' ? 'error' : 'warn';
    issues.push({ level, text: (KIND_CN[e.kind] || '物体') + nameOf(e) + '不可达，主角拿不到', hint: approachHint(dim, info.approach, metrics) });
  }
  for (const id of r.isolated) {
    issues.push({ level: 'warn', text: '平台' + nameOf(ents[id]) + '是孤岛，从出生点跳不上去', hint: approachHint(dim, r.approach[id], metrics) });
  }
  const span = levelSpan(game, dim);
  if (span > LONG_LEVEL[dim] && !Object.values(ents).some(e => e.kind === 'checkpoint')) {
    issues.push({ level: 'warn', text: '关卡较长（约 ' + fmt(dim, span) + '）却没有检查点，掉下去要从头再来', hint: '在中段平台上放 1-2 个 checkpoint' });
  }
  return { issues, path };
}

function levelSpan(game, dim) {
  const xs = Object.values(game.entities || {}).filter(e => e.kind === 'platform').flatMap(e => {
    const b = boxOf(e, dim);
    return dim === '3d' ? [[b.l, b.n], [b.r, b.f]] : [[b.l, 0], [b.r, 0]];
  });
  if (!xs.length) return 0;
  const span = i => Math.max(...xs.map(p => p[i])) - Math.min(...xs.map(p => p[i]));
  return Math.max(span(0), span(1));
}

const LEVEL_RANK = { error: 0, warn: 1 };

/** A normalized copy of a stored/hand-written game, so checks never see missing sizes or vectors. */
function normalizedForCheck(game) {
  const meta = { ...emptyGame().meta, ...asObject(game.meta) };
  const dim = meta.dimension === '3d' ? '3d' : '2d';
  const entities = {};
  for (const [id, e] of Object.entries(asObject(game.entities))) entities[id] = normalizeEntity(id, e, dim);
  return {
    ...game, meta, entities,
    world: asObject(game.world), rules: asObject(game.rules), settings: asObject(game.settings),
    player: normalizeEntity('player', { ...asObject(game.player), kind: 'player' }, dim),
  };
}

/** Readability: signs and text overlapping the spawn point are hidden behind the player. */
function readabilityIssues(game, dim) {
  const issues = [];
  if (!game.player || !Array.isArray(game.player.position)) return issues;
  const size = Array.isArray(game.player.size) ? game.player.size : (dim === '3d' ? [0.9, 1.7, 0.9] : [64, 64]);
  const pb = boxOf({ position: game.player.position, size }, dim);
  const pad = dim === '3d' ? 1.2 : 70;
  const grown = { ...pb, l: pb.l - pad, r: pb.r + pad, n: pb.n - pad, f: pb.f + pad };
  const hit = (a, b) => overlaps(a, b) && (dim !== '3d' || (a.n < b.f && b.n < a.f));
  for (const e of Object.values(game.entities)) {
    if ((e.kind !== 'sign' && e.kind !== 'text') || !Array.isArray(e.position) || !Array.isArray(e.size)) continue;
    if (hit(grown, boxOf(e, dim))) issues.push({ level: 'warn', text: '告示牌' + nameOf(e) + '和主角出生点重叠，开局文字会被主角挡住', hint: dim === '3d' ? '把告示牌挪到出生点侧后方 2 米以外' : '把告示牌挪到出生点右边 150px 以外' });
  }
  return issues;
}

export function checkGame(stored) {
  const game = normalizedForCheck(stored);
  const dim = game.meta.dimension === '3d' ? '3d' : '2d';
  const ents = Object.values(game.entities);
  const byKind = k => ents.filter(e => e.kind === k);
  const metrics = jumpMetrics(jumpModel(dim, game));
  const issues = ruleIssues(game, byKind);
  let path = null;
  if (isTopdown(game)) {
    issues.push(...topdownIssues(game));
  } else {
    const reach = reachIssues(game, dim, metrics);
    issues.push(...reach.issues);
    path = reach.path;
  }
  issues.push(...readabilityIssues(game, dim));
  issues.sort((a, b) => LEVEL_RANK[a.level] - LEVEL_RANK[b.level]);
  return {
    ok: !issues.some(i => i.level === 'error'),
    counts: { entities: ents.length, platforms: byKind('platform').length, collectibles: byKind('collectible').length, enemies: byKind('enemy').length, goals: byKind('goal').length, checkpoints: byKind('checkpoint').length },
    metrics,
    issues: issues.slice(0, MAX_ISSUES),
    path,
  };
}

// ---------------------------------------------------------------- tool application

const WORLD_TARGETS = { background: 'background_asset', ground: 'ground_asset', music: 'music_asset', platforms: 'platform_asset' };
const WORLD_TARGET_LABEL = { background: '换上背景', ground: '地面换上贴图', music: '配上音乐', platforms: '平台换上贴图' };
const cleanId = s => String(s).replace(/[^a-zA-Z0-9_]/g, '_');

export class GameEngine {
  constructor(project) { this.p = project; }
  get game() { return this.p.game; }
  get dim() { return this.game.meta.dimension === '3d' ? '3d' : '2d'; }

  apply(name, input) {
    input = asObject(input);
    const handler = this['tool_' + name];
    if (!handler) return { ops: [], result: { error: 'unknown tool ' + name } };
    const ops = [];
    const out = handler.call(this, input, ops);
    return out || { ops, result: { ok: true, entities: Object.keys(this.game.entities).length } };
  }

  tool_plan_game(input, ops) {
    const g = this.game;
    const style = input.style || g.meta.style;
    const nd = input.dimension === '3d' ? '3d' : '2d';
    g.meta = normalizeMeta({
      title: input.title || g.meta.title, dimension: nd, genre: input.genre || 'platformer', style,
      filter: style === 'pixel' ? 'pixel' : 'smooth', pitch: input.pitch || '',
      palette: input.palette || g.meta.palette, art_bible: input.art_bible || g.meta.art_bible,
    });
    g.settings = nd === '3d' ? { gravity: 24 } : { gravity: 1900 };
    for (const [id, e] of Object.entries(g.entities)) g.entities[id] = normalizeEntity(id, e, nd);
    const keepPos = Array.isArray(g.player.position) && g.player.position.length === (nd === '3d' ? 3 : 2);
    g.player = normalizeEntity('player', { ...g.player, kind: 'player', position: keepPos ? g.player.position : (nd === '3d' ? [0, 2, 0] : [0, 120]) }, nd);
    ops.push({ op: 'set_meta', meta: g.meta, label: '开始搭建：' + g.meta.title });
  }

  tool_set_world(input, ops) {
    const g = this.game;
    g.world = normalizeWorld({ ...g.world, ...asObject(input.world) });
    ops.push({ op: 'set_world', world: g.world, label: input.label || '布置世界环境' });
  }

  tool_set_rules(input, ops) {
    const g = this.game;
    g.rules = normalizeRules({ ...g.rules, ...asObject(input.rules) });
    ops.push({ op: 'set_rules', rules: g.rules });
  }

  tool_set_player(input, ops) {
    const g = this.game;
    g.player = normalizeEntity('player', { ...g.player, ...asObject(input.player), kind: 'player' }, this.dim);
    ops.push({ op: 'set_player', player: g.player, label: '放置主角' });
  }

  tool_add_entities(input, ops) {
    const g = this.game;
    asArray(input.entities).forEach((raw, i) => {
      raw = asObject(raw);
      let id = cleanId(raw.id || ('e_' + Date.now().toString(36) + '_' + i));
      while (g.entities[id]) id += '_b';
      g.entities[id] = normalizeEntity(id, raw, this.dim);
      ops.push({ op: 'add', id, entity: g.entities[id], label: (KIND_CN[g.entities[id].kind] || '物体') + '：' + (g.entities[id].name || id) });
    });
  }

  tool_update_entities(input, ops) {
    const g = this.game;
    for (const ch of asArray(input.changes).map(asObject)) {
      const id = String(ch.id || '');
      if (!g.entities[id]) continue;
      g.entities[id] = normalizeEntity(id, { ...g.entities[id], ...ch, id }, this.dim);
      ops.push({ op: 'update', id, entity: g.entities[id], label: '调整：' + (g.entities[id].name || id) });
    }
  }

  tool_remove_entities(input, ops) {
    const g = this.game;
    for (const id of asArray(input.ids).map(String)) {
      if (!g.entities[id]) continue;
      const n = g.entities[id].name || id;
      delete g.entities[id];
      ops.push({ op: 'remove', id, label: '移除：' + n });
    }
  }

  tool_generate_assets(input, ops) {
    const g = this.game;
    const jobs = [];
    for (const a of asArray(input.assets).map(asObject).slice(0, MAX_ASSETS_PER_CALL)) {
      const id = cleanId(a.id || crypto.randomBytes(4).toString('hex'));
      const prev = g.assets[id];
      const same = prev && prev.prompt === a.prompt && prev.kind === a.kind && prev.state !== 'failed';
      if (!same) {
        g.assets[id] = { id, kind: a.kind, name: a.name || id, prompt: a.prompt, state: 'pending', url: '' };
        ops.push({ op: 'asset', id, kind: a.kind, state: 'pending', url: '' });
        jobs.push(id);
      }
      for (const t of asArray(a.apply_to).map(String)) this.bindAsset(id, a.name || id, t, ops);
    }
    return { ops, jobs, result: { started: jobs, note: '素材已在后台生成，生成期间物体显示占位动画，完成后会自动替换，无需等待。' } };
  }

  /** Bind asset id to one apply_to target. */
  bindAsset(id, name, target, ops) {
    const g = this.game;
    if (target === 'player') {
      g.player = { ...g.player, asset: id };
      ops.push({ op: 'set_player', player: g.player, label: '主角换装：' + name });
    } else if (WORLD_TARGETS[target]) {
      g.world = { ...g.world, [WORLD_TARGETS[target]]: id };
      ops.push({ op: 'set_world', world: g.world, label: WORLD_TARGET_LABEL[target] });
    } else if (target.startsWith('sfx:')) {
      g.sounds = { ...g.sounds, [target.slice(4)]: id };
    } else {
      const targets = target.startsWith('kind:')
        ? Object.keys(g.entities).filter(k => g.entities[k].kind === target.slice(5))
        : (g.entities[target] ? [target] : []);
      for (const eid of targets) {
        g.entities[eid] = { ...g.entities[eid], asset: id };
        ops.push({ op: 'update', id: eid, entity: g.entities[eid], label: '换装：' + (g.entities[eid].name || eid) });
      }
    }
  }

  tool_check_game(input, ops) {
    return { ops, result: checkGame(this.game) };
  }

  tool_finish(input, ops) {
    return { ops, result: { ok: true } };
  }
}
