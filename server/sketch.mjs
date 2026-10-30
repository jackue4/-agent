// Sketch artist: a second model that runs beside the builder. While the game is being made it draws a
// pencil prototype on a shared board, one stroke at a time as its tool call streams in, and keeps working
// until the builder finishes: revising after real progress (design, builds, screenshots), otherwise
// extending the level, pinning pseudo-code notes about the file being written, or annotating the rules.
// The board is illustrative only: it never feeds acceptance, and its failures never touch the build.
import { streamTurn } from './agent.mjs';
import { parsePartialJson } from './json.mjs';

export const SKETCH_KINDS = ['line', 'shape', 'rect', 'ellipse', 'arrow', 'text', 'code', 'card'];
export const MAX_ITEMS = 320;
const MAX_PTS = 32;
const COLOR = /^#[0-9a-f]{6}$/i;
const PHASES = ['idle', 'drawing', 'waiting', 'done', 'stopped', 'failed'];

export const boardSize = orientation => orientation === 'portrait' ? { w: 562, h: 1000 } : { w: 1000, h: 562 };

const clamp = (v, lo, hi) => {
  const n = Number(v);
  return Number.isFinite(n) ? Math.round(Math.min(Math.max(lo, hi), Math.max(lo, n)) * 10) / 10 : null;
};
const cleanId = v => String(v ?? '').trim().toLowerCase().replace(/[^\w-]/g, '_').slice(0, 32);
const oneLine = (v, n) => String(v ?? '').replace(/\s+/g, ' ').trim().slice(0, n);

/** A model-written element made safe for the board, or null. Coordinates are clamped to the paper. */
export function normalizeItem(raw, { w, h }, fallbackId = 'item') {
  if (!raw || typeof raw !== 'object' || !SKETCH_KINDS.includes(raw.t)) return null;
  const item = { id: cleanId(raw.id) || cleanId(fallbackId), t: raw.t };
  const group = oneLine(raw.group, 16);
  if (group) item.group = group;
  if (raw.weight === 'light' || raw.weight === 'bold') item.weight = raw.weight;
  if (typeof raw.color === 'string' && COLOR.test(raw.color)) item.color = raw.color.toLowerCase();
  if (raw.t === 'line' || raw.t === 'shape' || raw.t === 'arrow') {
    const flat = Array.isArray(raw.pts) ? raw.pts.flat(2) : [];
    const pts = [];
    for (let i = 0; i + 1 < flat.length && pts.length < MAX_PTS * 2; i += 2) {
      const x = clamp(flat[i], 0, w), y = clamp(flat[i + 1], 0, h);
      if (x !== null && y !== null) pts.push(x, y);
    }
    if (pts.length < (raw.t === 'shape' ? 6 : 4)) return null;
    item.pts = pts;
  } else {
    const x = clamp(raw.x, 0, w), y = clamp(raw.y, 0, h);
    if (x === null || y === null) return null;
    item.x = x; item.y = y;
    if (raw.t === 'text') {
      item.text = oneLine(raw.text, 40);
      if (!item.text) return null;
      item.size = clamp(raw.size ?? 20, 10, 64);
    } else if (raw.t === 'code') {
      item.lines = (Array.isArray(raw.lines) ? raw.lines : String(raw.text ?? '').split('\n')).map(line => String(line ?? '').replace(/\t/g, '  ').replace(/[\r\n]/g, '').slice(0, 44)).slice(0, 10);
      while (item.lines.length && !item.lines.at(-1).trim()) item.lines.pop();
      if (!item.lines.length) return null;
      const title = oneLine(raw.title, 28);
      if (title) item.title = title;
      item.size = clamp(raw.size ?? 14, 10, 22);
    } else {
      item.w = clamp(raw.w, 2, w - x); item.h = clamp(raw.h, 2, h - y);
      if (item.w === null || item.h === null) return null;
      if (raw.t === 'card') {
        if (item.w < 60 || item.h < 40) return null;
        const title = oneLine(raw.title, 28);
        if (title) item.title = title;
      }
    }
  }
  if (raw.fill === 'hatch' && ['rect', 'ellipse', 'shape'].includes(item.t)) item.fill = 'hatch';
  return item;
}

function normalizeState(state) {
  const s = state && typeof state === 'object' ? state : {};
  const size = Number(s.w) > 0 && Number(s.h) > 0 ? { w: Number(s.w), h: Number(s.h) } : boardSize('landscape');
  const items = (Array.isArray(s.items) ? s.items : []).map((item, i) => normalizeItem(item, size, 'item' + i)).filter(Boolean).slice(-MAX_ITEMS);
  // A restored board cannot still be drawing: the artist that owned it is gone.
  const phase = ['drawing', 'waiting'].includes(s.phase) ? 'stopped' : PHASES.includes(s.phase) ? s.phase : 'idle';
  return { runId: String(s.runId || ''), ...size, round: Math.max(0, Number(s.round) || 0), task: oneLine(s.task, 12), phase, note: oneLine(s.note, 40), message: oneLine(s.message, 160), prompt: oneLine(s.prompt, 120), activity: phase === 'stopped' ? '' : oneLine(s.activity, 80), items, updatedAt: Number(s.updatedAt) || 0 };
}

/** Board state plus its live viewers. Every applied op is pushed to open sketch streams. */
export class SketchBoard {
  constructor(state, { now = Date.now } = {}) {
    this.state = normalizeState(state);
    this.clients = new Set();
    this.n = 0;
    this.now = now;
  }
  snapshot() { return structuredClone(this.state); }
  apply(op) {
    const s = this.state;
    if (op.op === 'begin') {
      if (!op.keep) { s.items = []; s.round = 0; }
      Object.assign(s, { runId: String(op.runId || ''), w: op.w || s.w, h: op.h || s.h, phase: 'drawing', note: '', message: '', prompt: oneLine(op.prompt, 120) });
      op = { ...op, w: s.w, h: s.h, round: s.round, items: op.keep ? s.items : [] };
    } else if (op.op === 'round') { s.round = op.round; s.task = op.task || ''; s.phase = 'drawing'; s.note = ''; s.message = ''; }
    else if (op.op === 'note') s.note = op.note = oneLine(op.note, 40);
    else if (op.op === 'add') {
      s.items = s.items.filter(item => item.id !== op.item.id);
      s.items.push(op.item);
      if (s.items.length > MAX_ITEMS) s.items.splice(0, s.items.length - MAX_ITEMS);
    } else if (op.op === 'erase') {
      const ids = new Set(op.ids);
      s.items = s.items.filter(item => !ids.has(item.id));
    } else if (op.op === 'phase') { s.phase = PHASES.includes(op.phase) ? op.phase : s.phase; s.message = op.message = oneLine(op.message, 160); }
    else if (op.op === 'activity') s.activity = op.text = oneLine(op.text, 80);
    else return;
    s.updatedAt = this.now();
    this.broadcast({ ...op, n: ++this.n });
  }
  broadcast(message) {
    const line = 'data: ' + JSON.stringify(message) + '\n\n';
    for (const c of this.clients) { try { c.write(line); } catch { this.clients.delete(c); } }
  }
  attach(res) {
    res.write('data: ' + JSON.stringify({ op: 'snapshot', n: this.n, state: this.state }) + '\n\n');
    this.clients.add(res);
    return () => this.clients.delete(res);
  }
}

export const SKETCH_TOOL = {
  name: 'sketch',
  description: '在画纸上增删铅笔草图元素。字段顺序必须是 note → erase → items。',
  input_schema: {
    type: 'object', required: ['note', 'items'],
    properties: {
      note: { type: 'string', description: '给用户看的一句话（≤18 字），说明这一稿在画什么' },
      erase: { type: 'array', items: { type: 'string' }, description: '要擦掉的已有元素 id' },
      items: {
        type: 'array', description: '按落笔顺序排列的新元素；id 与已有元素相同则覆盖重画',
        items: {
          type: 'object', required: ['id', 't'],
          properties: {
            id: { type: 'string', description: '稳定的英文小写 id，如 hero / ground / hud_score' },
            t: { type: 'string', enum: SKETCH_KINDS },
            group: { type: 'string', description: '中文名，如 主角 / 地面 / 分数' },
            pts: { type: 'array', items: { type: 'number' }, description: 'line/shape/arrow 的点：[x1,y1,x2,y2,...]，最多 24 个点' },
            x: { type: 'number' }, y: { type: 'number' },
            w: { type: 'number', description: 'rect/ellipse/card 外框宽' }, h: { type: 'number', description: 'rect/ellipse/card 外框高' },
            text: { type: 'string', description: 'text 的文字（≤10 字），x,y 是文字左上角' },
            size: { type: 'number', description: 'text 字号 14–40；code 字号 12–16' },
            title: { type: 'string', description: 'code 便签或 card 卡片的标题，如 "main.gd · 跳跃" / "关卡 2：蘑菇坡"' },
            lines: { type: 'array', items: { type: 'string' }, description: 'code 便签的伪代码行，4–8 行，每行 ≤40 字符' },
            fill: { type: 'string', enum: ['none', 'hatch'], description: 'rect/ellipse/shape 用铅笔排线涂暗' },
            weight: { type: 'string', enum: ['light', 'normal', 'bold'] },
            color: { type: 'string', description: '可选彩铅颜色 #rrggbb，只给少数关键元素用' },
          },
        },
      },
    },
  },
};

export function sketchSystem({ w, h }) {
  return [
    '你是「草图助手」，和负责真正制作游戏的主 AI 并行工作。主 AI 写代码、试玩要好几分钟，你让用户在等待时看到游戏正在成形：在一张 ' + w + '×' + h + ' 的画纸上（' + (w > h ? '横屏' : '竖屏') + '，原点在左上角，x 向右，y 向下）用铅笔手绘这款游戏的原型草图，像游戏设计师在速写本上画的一屏游戏画面线框。',
    '每次只调用一次 sketch 工具。字段顺序必须是 note → erase → items（先写 note），工具参数里不要写多余字段。',
    '# 画法',
    '- 画玩家实际看到的那一屏：场景与地面/棋盘/赛道等主要区域、主角、敌人或关键物体、HUD（分数、血量、计时、按钮）、操作提示。用简洁几何形概括，不画细节，不画写实风景。',
    '- 用 text 写简短中文标注（≤10 字），用 arrow 指出交互和运动方向（如"点击跳跃""拖动发射""敌人从右边来"）。',
    '- 落笔顺序像人画画：先画面外框内的大块区域，再主角与核心物体，再 HUD、标注和箭头，最后少量排线阴影（fill:"hatch"）。',
    '- 每个元素一个稳定 id 和中文 group。修改已有元素就用同一 id 重画，不需要的写进 erase。',
    '- 第一稿 18–32 个元素；之后每稿只改 4–16 个元素，保留其他内容，不要整张重画。',
    '- 坐标必须落在画纸内，元素不要挤在一起，留出边距；pts 最多 24 个点。大部分用灰黑铅笔，确定调色板后只给 2–4 个关键元素加 color。',
    '- code 是贴在画纸上的伪代码便签：x,y 为左上角，title 写文件名和功能，lines 写 4–8 行像 GDScript 的简短伪代码（可夹中文注释），约占 300×200。便签贴在画面边角，别盖住主角；同一时间最多 2 张，新便签用新 id 并擦掉旧的。',
    '- card 是贴在画纸上的不透明白卡片（x,y,w,h，可带 title），会盖住它下面的笔画。画纸画满后，新的关卡段、小地图、规则速写都先放一张 card，再把内容画在卡片范围内（卡片四边内缩 12 以上），整张卡片内容用同一个 group。卡片约 260×170–340×220，别盖住主角和 HUD；同一时间最多 2 张，换新卡片时把旧卡片和它 group 里的元素一起擦掉。',
    '# 持续工作',
    '- 主 AI 干完之前你一直在画，每稿都要有看得见的新内容。每稿会给你一个本稿任务，按它做：',
    '  · 修订：只依据给你的真实进展修改，不编造进展。方案确定后让布局、角色和 HUD 与方案一致，不一致的擦掉重画；收到真实截图时让位置和比例向截图靠拢，在已实现的部分旁写"✓ 已做好"。',
    '  · 关卡：把关卡往下画——补一段障碍/平台/敌人/收集物，或在空白处画一张关卡路线小地图，标出起点、难点、终点。',
    '  · 代码便签：照主 AI 此刻正在写的文件和步骤，写一张伪代码便签，说明这段逻辑大致怎么写。这是示意，不是真实源码。',
    '  · 标注：用箭头和短句解释一条玩法规则、操作或胜负条件，或补一处动作/特效的小速写。',
    '- 画纸元素超过 120 个时，先在 erase 里擦掉旧便签、旧标注和过时的细节。每稿最多擦 30 个，逐步整理，不要整张擦掉重画。',
    '- 右下角 id 为 worklog 的「主 AI 工作日志」便签由系统维护：不要擦它，也不要在它上面画。',
    '- 主 AI 结束本轮后做最后一稿：标出已完成的部分；没做完的标"下一轮"。',
    '- note 用一句口语告诉用户这一稿在画什么，如"先勾出赛道和主角""给跳跃逻辑写张便签"。',
  ].join('\n');
}

const TOOL_CN = { design_game: '构思玩法方案', project_capabilities: '查看引擎能力', list_files: '查看工程文件', read_file: '阅读工程代码', grep_files: '搜索工程代码', write_file: '写代码', patch_file: '修改代码', delete_file: '清理文件',
  preview_checkpoint: '编译出可试玩版本', run_game: '启动游戏实测', game_eval: '模拟玩家操作', run_test: '跑自动测试', delegate_tasks: '分派并行任务', resolve_task: '收尾分工任务', generate_asset: '生成美术素材',
  build_scene: '搭建 3D 关卡', web_fetch: '查阅资料', update_plan: '调整开发路线', finish: '整理本轮成果' };

/** One line about what the builder is doing right now, from observable tool events only (never source text). */
export function activityOf(ev, memory) {
  if (ev?.type === 'tool_start') {
    memory.tool = ev.name;
    return TOOL_CN[ev.name] ? '正在' + TOOL_CN[ev.name] : null;
  }
  if (ev?.type === 'tool_progress' && /^(write|patch)_(file|module)$/.test(ev.name)) {
    const file = clip(ev.file, 40);
    if (!file) return null;
    const lines = Number(ev.total || ev.lines) || 0;
    return (ev.name.startsWith('patch') ? '正在修改 ' : '正在写 ') + file + (ev.step ? ' · ' + clip(ev.step, 20) : '') + (lines > 1 ? ' · 已写 ' + lines + ' 行' : '');
  }
  if (ev?.type === 'tool_progress' && ev.name === 'design_game') return '正在构思玩法方案' + (ev.title ? '：《' + clip(ev.title, 20) + '》' : '');
  if (ev?.type === 'eval' || ev?.type === 'test') return (ev.type === 'test' ? '自动测试' : '实测') + (ev.step ? '：' + clip(ev.step, 24) : '') + (ev.ok ? ' ✓' : ' ✗ 发现问题，准备修复');
  if (ev?.type === 'ops' && (ev.ops || []).some(op => op.op === 'pck')) return '新的可试玩版本已生成';
  if (ev?.type === 'asset' && ev.state === 'ready') return '素材「' + clip(ev.name || ev.id, 16) + '」已放进游戏';
  if (ev?.type === 'turn_end') return '';
  return null;
}

const STATUS_CN = { queued: '排队中', running: '进行中', applied: '已合入', verified: '已验收', failed: '失败', blocked: '受阻', interrupted: '中断', cancelled: '已取消' };
const clip = (v, n) => oneLine(v, n);
const coverShot = url => typeof url === 'string' && /^\/covers\/[\w.-]+\.jpg$/.test(url) ? url : '';

/** What a builder event means for the sketch: a progress line, whether it warrants a redraw now, and a screenshot. */
export function progressOf(ev, memory) {
  switch (ev?.type) {
    case 'design': {
      const d = ev.design || {};
      memory.design = d;
      return { urgent: true, text: '方案确定：《' + clip(d.title, 30) + '》' + clip(d.genre, 20) + (d.dimension === '3d' ? '（3D）' : '') + '\n  核心循环：' + clip(d.core_loop, 200) + '\n  布局：' + clip(d.layout, 240) + (d.controls ? '\n  操作：' + clip(d.controls, 120) : '') + (Array.isArray(d.palette) && d.palette.length ? '\n  调色板：' + d.palette.slice(0, 6).join(' ') : '') };
    }
    case 'task': {
      const t = ev.task || {};
      const key = t.id || t.title;
      if (!key || memory.tasks.get(key) === t.status) return null;
      memory.tasks.set(key, t.status);
      return { text: '分工任务「' + clip(t.title || t.id, 30) + '」' + (STATUS_CN[t.status] || clip(t.status, 12)) + (t.summary ? '：' + clip(t.summary, 80) : '') };
    }
    case 'code_write': {
      const file = clip(ev.file || ev.path, 60);
      if (!file || memory.files.has(file)) return null;
      memory.files.add(file);
      return { text: '保存了 ' + file + (ev.step ? '（' + clip(ev.step, 20) + '）' : '') };
    }
    case 'ops': {
      const pck = (ev.ops || []).find(op => op.op === 'pck');
      if (!pck) return null;
      memory.builds++;
      return { urgent: memory.builds === 1, text: memory.builds === 1 ? '第一版可试玩画面已经生成' : '可试玩画面更新到第 ' + memory.builds + ' 版' + (pck.label ? '：' + clip(pck.label, 30) : '') };
    }
    case 'construction': {
      const objects = ev.snapshot?.objects || [];
      if (!objects.length || objects.length === memory.objects) return null;
      const first = !memory.objects;
      memory.objects = objects.length;
      return { urgent: first, text: '3D 关卡已搭出 ' + objects.length + ' 个物体：' + objects.slice(0, 10).map(o => clip(o.label || o.name || o.id, 12)).join('、') };
    }
    case 'eval': case 'test': {
      const shot = coverShot(ev.shot);
      const checks = Array.isArray(ev.checks) ? ev.checks : [];
      const text = (ev.type === 'test' ? '自动测试' : '真实试玩') + (ev.step ? '「' + clip(ev.step, 20) + '」' : '') + (ev.ok ? '通过' : '发现问题') + (checks.length ? '（断言 ' + checks.filter(c => c?.ok).length + '/' + checks.length + '）' : '');
      const first = shot && !memory.shots++;
      return { urgent: !!first, text, shot };
    }
    case 'asset':
      if (ev.state !== 'ready' && ev.state !== 'failed') return null;
      return { text: '素材「' + clip(ev.name || ev.id, 20) + '」' + (ev.state === 'ready' ? '已生成并放进游戏' : '生成失败，先用占位') };
    case 'turn_end':
      return { urgent: true, final: true, text: '主 AI 已结束本轮（' + ({ completed: '已完成验收', ready: '等待浏览器确认', partial: '保存了部分成果', cancelled: '用户停止', interrupted: '中断', failed: '失败' }[ev.status] || clip(ev.status, 12)) + '）' + (ev.summary ? '：' + clip(ev.summary, 240) : '') };
    default: return null;
  }
}

function describeItem(item) {
  let box;
  if (item.pts) {
    const xs = item.pts.filter((_, i) => i % 2 === 0), ys = item.pts.filter((_, i) => i % 2 === 1);
    box = Math.round(Math.min(...xs)) + ',' + Math.round(Math.min(...ys)) + ' → ' + Math.round(Math.max(...xs)) + ',' + Math.round(Math.max(...ys));
  } else box = Math.round(item.x) + ',' + Math.round(item.y) + (item.w ? ' ' + Math.round(item.w) + '×' + Math.round(item.h) : '');
  return item.id + ' | ' + item.t + ' | ' + (item.group || '') + ' | ' + box + (item.text ? ' | "' + item.text + '"' : '') + (item.title ? (item.t === 'card' ? ' | 卡片「' : ' | 便签「') + item.title + '」' : '');
}

function boxOf(item) {
  if (item.pts) {
    const xs = item.pts.filter((_, i) => i % 2 === 0), ys = item.pts.filter((_, i) => i % 2 === 1);
    return [Math.min(...xs), Math.min(...ys), Math.max(...xs), Math.max(...ys)];
  }
  if (item.t === 'text') return [item.x, item.y, item.x + (item.size || 20) * Array.from(item.text).length * 0.9, item.y + (item.size || 20)];
  if (item.t === 'code') { const s = item.size || 14; return [item.x, item.y, item.x + Math.max(160, s * 0.62 * Math.max(...item.lines.map(l => l.length)) + 24), item.y + s * 1.45 * item.lines.length + s * 3]; }
  return [item.x, item.y, item.x + (item.w || 0), item.y + (item.h || 0)];
}
const COLS = ['左', '中左', '中右', '右'], ROWS = ['上', '中', '下'];
/** Blank cells of a 4×3 grid over the paper, so new sections land beside the drawing instead of on it. Page frames and backgrounds (over half the paper) do not count. */
export function freeAreas(items, { w, h }) {
  const cw = w / COLS.length, ch = h / ROWS.length, used = new Set();
  for (const item of items) {
    const [x0, y0, x1, y1] = boxOf(item);
    if ((x1 - x0) * (y1 - y0) > w * h * 0.5) continue;
    for (let r = 0; r < ROWS.length; r++) for (let c = 0; c < COLS.length; c++) {
      const ox = Math.min(x1, (c + 1) * cw) - Math.max(x0, c * cw), oy = Math.min(y1, (r + 1) * ch) - Math.max(y0, r * ch);
      // A thin frame line through a cell does not use it up; a block covering a twentieth of it does.
      if (ox > 0 && oy > 0 && ox * oy > cw * ch * 0.05) used.add(r * COLS.length + c);
    }
  }
  const free = [];
  for (let r = 0; r < ROWS.length; r++) for (let c = 0; c < COLS.length; c++) if (!used.has(r * COLS.length + c)) free.push(ROWS[r] + COLS[c] + ' (' + Math.round(c * cw) + ',' + Math.round(r * ch) + ')-(' + Math.round((c + 1) * cw) + ',' + Math.round((r + 1) * ch) + ')');
  return free;
}

const AGENDA = ['level', 'code', 'notes'];
const LOG_ID = 'worklog';
const MAX_ERASE = 30;
const TASK_TEXT = {
  first: '主 AI 刚开始工作，先根据需求画出第一版原型草图。',
  revise: '本稿任务【修订】：根据新进展修订草图——改不一致的，补新出现的，标出已做好的。',
  level: '本稿任务【关卡】：把关卡往下画——在空白处补一段障碍/平台/敌人/收集物；没有空白就贴一张 card，在卡片里画下一段关卡或关卡路线小地图。',
  code: '本稿任务【代码便签】：照主 AI 此刻正在写的内容，贴一张伪代码便签（t:"code"），并擦掉更早的便签。',
  notes: '本稿任务【标注】：用箭头和短句解释一条玩法规则、操作或胜负条件，或补一处动作/特效小速写；没有空白就画在一张 card 上。',
  final: '主 AI 已结束本轮：做最后一稿，标出已完成和"下一轮"的部分，不要大改。',
};

/**
 * Drives the board for one production round. start() draws a first sketch from the request alone; observe(ev)
 * receives every builder event. Until the builder's turn_end the artist keeps drawing — a revision when real
 * progress arrives, otherwise the next agenda task — then makes a final pass and stops.
 */
export class SketchArtist {
  constructor({ board, prompt, model, fallbackModel = '', orientation, dimension, design = null, keep = false, runId = '', signal, readImage = () => null, stream = streamTurn,
    maxRounds = 40, idleGapMs = 2500, tickMs = 1000, roundTimeoutMs = 120000, firstStrokeMs = 25000, logAfterMs = 12000, activityMs = 700, now = Date.now, onSave = () => {}, onStop = () => {} }) {
    Object.assign(this, { board, prompt: String(prompt || ''), model, fallbackModel, dimension, keep, runId, readImage, stream, maxRounds, idleGapMs, roundTimeoutMs, firstStrokeMs, logAfterMs, activityMs, now, onSave, onStop });
    this.stalls = 0;
    this.size = boardSize(orientation);
    this.memory = { design, tasks: new Map(), files: new Set(), builds: 0, objects: 0, shots: 0 };
    this.updates = []; this.urgent = false; this.ending = false; this.shot = '';
    this.recent = []; this.writing = null; this.agenda = 0;
    this.activity = { text: '', key: '', at: 0, pending: null };
    this.rounds = 0; this.failures = 0; this.lastRoundAt = 0; this.lastStrokeAt = 0; this.logged = '';
    this.busy = null; this.stopped = false;
    this.abort = new AbortController();
    this.signal = signal ? AbortSignal.any([signal, this.abort.signal]) : this.abort.signal;
    this.signal.addEventListener('abort', () => this.stop('stopped'), { once: true });
    this.timer = setInterval(() => { this.writeLog(); this.kick(); }, tickMs);
    this.timer.unref?.();
    this.done = new Promise(resolve => { this.resolveDone = resolve; });
  }
  start() {
    this.board.apply({ op: 'begin', runId: this.runId, keep: this.keep, prompt: this.prompt, ...this.size });
    this.started = true;
    this.urgent = true;
    this.kick();
    return this;
  }
  observe(ev) {
    if (this.stopped) return;
    this.track(ev);
    const p = progressOf(ev, this.memory);
    if (!p) return;
    this.updates.push(p.text);
    if (this.updates.length > 24) this.updates.splice(0, this.updates.length - 24);
    if (p.shot) this.shot = p.shot;
    if (p.urgent) this.urgent = true;
    if (p.final) this.ending = true;
    this.kick();
  }
  /** The live "what the builder is doing" line, pushed straight to the board without waiting for the model. */
  track(ev) {
    if (ev?.type === 'tool_progress' && /^(write|patch)_(file|module)$/.test(ev.name) && ev.file) this.writing = { file: clip(ev.file, 40), step: clip(ev.step, 30), at: this.now() };
    const text = activityOf(ev, this.memory);
    if (text === null || text === undefined) return;
    if (text && text !== this.recent.at(-1) && !/ · 已写 \d+ 行$/.test(text)) { this.recent.push(text); if (this.recent.length > 6) this.recent.shift(); }
    const a = this.activity, key = text.replace(/ · 已写 \d+ 行$/, '');
    clearTimeout(a.pending);
    const publish = () => { a.pending = null; a.text = text; a.key = key; a.at = this.now(); if (!this.stopped) this.board.apply({ op: 'activity', text }); };
    if (key !== a.key || this.now() - a.at >= this.activityMs) publish();
    else { a.pending = setTimeout(publish, this.activityMs); a.pending.unref?.(); }
  }
  /** While the model is slow to answer, the paper still moves: a sticky note of the builder's real recent actions. */
  writeLog() {
    if (!this.started || this.stopped || !this.busy || this.now() - this.lastStrokeAt < this.logAfterMs) return;
    const lines = this.recent.slice(-5).map((text, i, all) => (i === all.length - 1 ? '▶ ' : '✓ ') + text.replace(/^正在/, '').slice(0, 40));
    const key = lines.join('\n');
    if (!lines.length || key === this.logged) return;
    this.logged = key;
    const { w, h } = this.size, height = 44 + lines.length * 21;
    const item = normalizeItem({ id: LOG_ID, t: 'code', title: '主 AI 工作日志', lines, size: 13, x: w - 300, y: h - height - 10 }, this.size);
    this.lastStrokeAt = this.now();
    this.board.apply({ op: 'add', item });
  }
  kick() {
    if (!this.started || this.stopped || this.busy) return;
    const budget = this.rounds < this.maxRounds || (this.ending && this.rounds < this.maxRounds + 1);
    if (!budget) { if (this.ending) this.stop('done'); return; }
    const gap = this.idleGapMs * (1 + this.failures * 3);
    const due = this.urgent || this.now() - this.lastRoundAt >= gap;
    if (!due) return;
    this.busy = this.round().finally(() => { this.busy = null; if (!this.stopped) queueMicrotask(() => this.kick()); });
  }
  /** What this round should draw: the first sketch, a revision after real progress, or the next agenda item. */
  taskFor(final) {
    if (final) return 'final';
    if (!this.board.state.items.length) return 'first';
    if (this.updates.length) return 'revise';
    const writingNow = this.writing && this.now() - this.writing.at < 30000;
    let task = AGENDA[this.agenda++ % AGENDA.length];
    if (task === 'code' && !writingNow && !this.memory.files.size) task = AGENDA[this.agenda++ % AGENDA.length];
    return task;
  }
  compose(final, task = this.taskFor(final)) {
    const s = this.board.state, d = this.memory.design;
    const lines = ['用户的需求：「' + clip(this.prompt, 600) + '」', '画纸：' + s.w + '×' + s.h + '（' + (s.w > s.h ? '横屏' : '竖屏') + '），' + (this.dimension === '3d' ? '3D 游戏，画第三人称/俯视角的一屏' : '2D 游戏')];
    if (d) lines.push('主 AI 的方案：《' + clip(d.title, 30) + '》' + clip(d.pitch, 120) + '\n核心循环：' + clip(d.core_loop, 240) + '\n布局：' + clip(d.layout, 300) + (d.controls ? '\n操作：' + clip(d.controls, 160) : '') + (Array.isArray(d.palette) ? '\n调色板：' + d.palette.slice(0, 6).join(' ') : ''));
    lines.push(s.items.length ? '画纸上已有的元素（id | 类型 | 组 | 位置 | 文字）：\n' + s.items.slice(-120).map(describeItem).join('\n') : '画纸现在是空的。');
    if (this.updates.length) lines.push('自上一稿以来主 AI 的真实进展：\n' + this.updates.map(u => '- ' + u).join('\n'));
    if (this.recent.length) lines.push('主 AI 最近的动作（最新在后）：\n' + this.recent.map(u => '- ' + u).join('\n'));
    if (task === 'code') lines.push(this.writing ? '主 AI 正在写：' + this.writing.file + (this.writing.step ? '（' + this.writing.step + '）' : '') : '主 AI 已经写过的文件：' + [...this.memory.files].slice(-4).join('、'));
    if (s.items.length && ['level', 'code', 'notes'].includes(task)) {
      const free = freeAreas(s.items, s);
      lines.push(free.length ? '画纸上的空白区域（新内容画在这里，不要压在已有画面上）：' + free.join('；') : '画纸已经没有空白：把新内容画在一张 card 上，不要直接压在已有笔画上。');
    }
    if (s.items.length > 120) lines.push('画纸已有 ' + s.items.length + ' 个元素，先擦掉一些旧便签、旧标注或过时细节。');
    lines.push('这是第 ' + (s.round + 1) + ' 稿。' + TASK_TEXT[task]);
    return lines.join('\n\n');
  }
  async round() {
    const final = this.ending;
    const round = this.board.state.round + 1;
    const task = this.taskFor(final);
    const text = this.compose(final, task);
    const shotUrl = this.shot, briefed = this.updates;
    this.updates = []; this.urgent = false; this.shot = '';
    this.rounds++;
    this.lastStrokeAt = this.now();
    this.board.apply({ op: 'round', round, task });
    try {
      const image = shotUrl ? await this.readImage(shotUrl) : null;
      const content = [{ type: 'text', text }];
      if (image) content.push({ type: 'text', text: '下面是主 AI 最近一次真实运行的游戏截图：' }, { type: 'image', source: { type: 'base64', media_type: 'image/jpeg', data: image } });
      try { await this.draw(content, round); }
      catch (error) {
        // Some models refuse images; a text-only retry keeps the sketch moving.
        if (!image || error?.stall || this.signal.aborted || this.drawn) throw error;
        await this.draw([{ type: 'text', text }], round);
      }
      this.failures = 0; this.stalls = 0;
      if (!this.stopped) this.board.apply({ op: 'phase', phase: final ? 'done' : 'waiting' });
    } catch (error) {
      if (this.stopped) return;
      if (error?.stall && !final) {
        this.updates = [...briefed, ...this.updates].slice(-24);
        this.shot ||= shotUrl;
        // A model that keeps thinking past the first-stroke window would leave the paper blank all build.
        const swap = !this.drawn && ++this.stalls >= 2 && this.fallbackModel && this.fallbackModel !== this.model;
        if (swap) { this.model = this.fallbackModel; this.stalls = 0; }
        this.board.apply({ op: 'phase', phase: 'waiting', ...(swap ? { message: '草图助手换用更快的模型继续画' } : {}) });
        return;
      }
      this.failures++;
      this.board.apply({ op: 'phase', phase: 'failed', message: '草图助手这一稿没画完：' + String(error?.message || error).slice(0, 100) + '（不影响游戏制作）' });
      if (this.failures >= 3) this.stop('failed');
    } finally {
      this.lastRoundAt = this.now();
      this.onSave();
      if (final && !this.stopped) this.stop(this.failures ? 'failed' : 'done');
    }
  }
  /** Thinking delays the first stroke by a minute on the default model, and it rules out forcing a named tool. */
  async draw(content, round) {
    const req = { model: this.model, system: sketchSystem(this.size), tools: [SKETCH_TOOL], tool_choice: { type: 'any' }, max_tokens: 8000 };
    try { return await this.drawWith(content, round, { ...req, thinking: { type: 'disabled' } }); }
    catch (error) {
      if (this.drawn || this.signal.aborted || error?.status !== 400) throw error;
      return this.drawWith(content, round, req);
    }
  }
  /** A round that shows nothing on paper for firstStrokeMs is abandoned, so a slow gateway never freezes the board. */
  async drawWith(content, round, req) {
    const stall = new AbortController();
    let watchdog;
    const arm = () => { clearTimeout(watchdog); watchdog = setTimeout(() => stall.abort(Object.assign(new Error('草图助手这一稿卡住了'), { stall: true })), this.firstStrokeMs); watchdog.unref?.(); };
    const signal = AbortSignal.any([this.signal, stall.signal, AbortSignal.timeout(this.roundTimeoutMs)]);
    const progress = { sent: 0, note: false, erase: false, added: new Set(), round, last: 0, shown: 0 };
    this.drawn = false;
    arm();
    try {
      const result = await this.stream([{ role: 'user', content }], {
        onToolDelta: (_id, json) => {
          const t = this.now();
          if (t - progress.last < 40) return;
          progress.last = t;
          const before = progress.shown;
          this.consume(parsePartialJson(json), progress, false);
          if (progress.shown !== before) arm();
        },
      }, signal, { req, idleTimeoutMs: 45000 });
      if (stall.signal.aborted && !this.signal.aborted) throw stall.signal.reason;
      const use = (result?.content || []).find(block => block.type === 'tool_use' && block.name === 'sketch');
      if (use && !use.input?.__bad_json) this.consume(use.input, progress, true);
      if (!this.drawn && !progress.erase && !result?.interrupted) throw new Error('没有收到草图笔画');
    } catch (error) {
      if (stall.signal.aborted && !this.signal.aborted) throw stall.signal.reason;
      throw error;
    } finally { clearTimeout(watchdog); }
  }
  /** Applies whatever of a (possibly partial) tool input is complete. The last streamed item waits until the next one starts. */
  consume(part, progress, final) {
    if (!part || typeof part !== 'object' || this.stopped) return;
    const show = op => { progress.shown++; this.lastStrokeAt = this.now(); this.board.apply(op); };
    if (!progress.note && typeof part.note === 'string' && (final || 'erase' in part || 'items' in part)) {
      progress.note = true;
      show({ op: 'note', note: part.note });
    }
    if (!progress.erase && Array.isArray(part.erase) && (final || 'items' in part)) {
      progress.erase = true;
      const known = new Set(this.board.state.items.map(item => item.id));
      const ids = part.erase.map(cleanId).filter(id => known.has(id) && !progress.added.has(id) && id !== LOG_ID).slice(0, MAX_ERASE);
      if (ids.length) show({ op: 'erase', ids });
    }
    const items = Array.isArray(part.items) ? part.items : [];
    const ready = final ? items.length : items.length - 1;
    for (; progress.sent < ready; progress.sent++) {
      const item = normalizeItem(items[progress.sent], this.size, 'r' + progress.round + '_' + progress.sent);
      if (!item || item.id === LOG_ID) continue;
      progress.added.add(item.id);
      this.drawn = true;
      show({ op: 'add', item });
    }
  }
  stop(phase = 'stopped') {
    if (this.stopped) return;
    this.stopped = true;
    clearInterval(this.timer);
    clearTimeout(this.activity.pending);
    if (this.board.state.activity) this.board.apply({ op: 'activity', text: '' });
    if (!this.abort.signal.aborted) this.abort.abort(new Error('草图助手已停止'));
    if (this.board.state.phase !== 'done' || phase !== 'stopped') this.board.apply({ op: 'phase', phase, message: phase === 'failed' ? this.board.state.message : '' });
    this.onSave();
    this.onStop();
    this.resolveDone(phase);
  }
}
