// "Code" engine: for any game that is not a platformer, an AI designer plans the game and an AI
// programmer writes real GDScript modules on top of the runtime's G SDK (runtime/kit.gd).
// Every module write is test-loaded in the real Godot runtime and, when it loads, hot-swapped into
// the user's preview where the builder drone reveals the new nodes - so the build stays visible.
import { runAgent } from './agent.mjs';
import { parsePartialJson } from './json.mjs';
import { runCodeTest, staticCheck } from './runner.mjs';

export const CODE_MODEL = process.env.UGC_CODE_MODEL || 'claude-opus-5-5';
const MAX_FILES = 12;
const MAX_TEST_RUNS = 8;
/** Opus streams a readable summary of its reasoning, so the user sees what each agent is thinking. */
const THINKING = { type: 'adaptive', display: 'summarized' };

/** The AI crew shown to the user: A designs, B writes gameplay logic, C builds the scene. */
export const CREW = {
  A: { name: '策划师', role: 'design', color: '#f472b6' },
  B: { name: '玩法程序员', role: 'gameplay', color: '#a78bfa' },
  C: { name: '场景搭建师', role: 'scene', color: '#34d399' },
};

/** Platformer-style requests keep the fast spec/template agent; everything else is written as code. */
export function wantsCodeEngine(text, dimension) {
  if (dimension === '3d') return false;
  const t = String(text || '');
  if (/(跑酷|平台跳跃|横版|闯关跳跃|马里奥|超级玛丽|platformer|jump\s*and\s*run|冒险跳跃|跳跳)/i.test(t)) return false;
  return true;
}

// ------------------------------------------------------------------ planner

const PLAN_SYSTEM = [
  '你是「造梦」平台的首席游戏设计师。用户是不会编程的普通人，用一句话描述想玩的游戏；你要把它想成一个完整、好玩、能分阶段做出来的 2D 网页小游戏，交给 AI 程序员用 Godot 4 GDScript 实现。',
  '',
  '# 原则',
  '- 忠于用户原话：用户说的游戏类型、题材、核心玩法必须保留，不要偷换成别的类型（比如用户说卡牌就绝不能做成跳跃闯关）。',
  '- 先找"最接近的已知游戏"，再写清楚这次和它有什么不同（题材、规则变化、独特机制），避免和平台上其它游戏雷同；同类游戏之间也要有自己的个性。',
  '- 规则要具体到可以直接编码：数值、回合流程、胜负条件、计分公式。',
  '- 一局 3-8 分钟能玩完；鼠标/触屏为主（点击、拖动），键盘只做可选。',
  '- 屏幕方向由用户选择（见消息开头【屏幕】），横屏按 1280x720、竖屏按 720x1280（手机竖握）设计。UI 布局用区域描述（顶部信息栏、中央牌桌、底部手牌区……），竖屏时内容自上而下排列、按钮放在拇指能够到的下半屏。',
  '- 游戏内文字用简体中文，不用 emoji（字体不支持），花色等符号用矢量图形绘制。',
  '- 模块化：3-7 个 .gd 文件（main.gd 是入口，其余如 deck.gd、rules.gd、card_view.gd、hud.gd），每个写清职责与对外接口（函数签名），让程序员一次写对。',
  '- 两位程序员会并行开工：owner="scene" 的模块（main.gd、视图/HUD/特效/布局）由场景搭建师写，owner="gameplay" 的模块（规则、数据、牌堆、AI 对手等纯逻辑，不建界面节点）由玩法程序员写。所以逻辑与视图要分开，接口（数据字典字段、函数签名）必须写清楚，双方才能对上。',
  '- 里程碑：M1 可玩核心循环（最重要，几分钟内要能玩）→ M2 手感与反馈（动画、音效、数值打磨）→ M3 内容扩展（更多卡牌/关卡/机制）→ M4 打磨（开始/结算表现、平衡、新手引导）。每个都要有可验证的验收标准。',
  '- M1 的 build_steps：4-7 个用户能看懂的搭建步骤（"铺好牌桌和计分栏""洗牌发出 8 张手牌"），每步对应在画面上能看到的变化。',
  '- 字段按顺序输出：先 title、pitch、palette、art_bible、assets，再其余（用户会实时看到方案一段段写出来）。',
  '- 美术：palette 3-5 个 hex（主/辅/强调/暗/亮），art_bible 一句英文画风描述。assets 可选 0-3 个 AI 生图素材（背景 background 或物件 sprite），程序员会在素材到达前用矢量图形占位。',
].join('\n');

const PLAN_TOOL = {
  name: 'design_game',
  description: '输出完整的游戏设计方案（会展示给用户确认，并交给 AI 程序员实现）。',
  input_schema: {
    type: 'object',
    required: ['title', 'pitch', 'palette', 'closest_game', 'differences', 'core_loop', 'rules', 'layout', 'controls', 'goal_text', 'modules', 'milestones', 'build_steps', 'art_bible'],
    properties: {
      title: { type: 'string', description: '游戏名（中文，≤12 字）' },
      pitch: { type: 'string', description: '一句话卖点' },
      palette: { type: 'array', items: { type: 'string' } },
      art_bible: { type: 'string' },
      assets: { type: 'array', items: { type: 'object', required: ['id', 'kind', 'name', 'prompt'], properties: { id: { type: 'string' }, kind: { type: 'string', enum: ['background', 'sprite'] }, name: { type: 'string' }, prompt: { type: 'string' } } } },
      genre: { type: 'string', description: '类型，如 deckbuilder / card / puzzle / idle / strategy / arcade' },
      closest_game: { type: 'string', description: '最接近的已知游戏' },
      differences: { type: 'array', items: { type: 'string' }, description: '和最接近游戏的 2-4 个关键不同' },
      core_loop: { type: 'string', description: '核心循环，一两句' },
      rules: { type: 'array', items: { type: 'string' }, description: '具体规则与数值，6-14 条' },
      layout: { type: 'string', description: '屏幕布局（区域 + 内容）' },
      controls: { type: 'array', items: { type: 'array', items: { type: 'string' } }, description: '[["鼠标点击","选牌"], ...] 2-4 条' },
      goal_text: { type: 'string', description: '开始卡片上的一句话目标' },
      modules: { type: 'array', items: { type: 'object', required: ['file', 'role', 'owner'], properties: { file: { type: 'string' }, owner: { type: 'string', enum: ['scene', 'gameplay'] }, role: { type: 'string' }, interface: { type: 'string', description: '对外函数/信号签名、数据字典字段' } } } },
      milestones: { type: 'array', items: { type: 'object', required: ['id', 'name', 'goal', 'acceptance'], properties: { id: { type: 'string' }, name: { type: 'string' }, goal: { type: 'string' }, acceptance: { type: 'array', items: { type: 'string' } } } } },
      build_steps: { type: 'array', items: { type: 'string' } },
    },
  },
};

export const screenOf = o => o === 'portrait' ? { o: 'portrait', w: 720, h: 1280, cn: '竖屏 720x1280（手机竖握）' } : { o: 'landscape', w: 1280, h: 720, cn: '横屏 1280x720' };

export async function planGame(userText, { cb = {}, signal, previous, orientation } = {}) {
  const content = '【屏幕】' + screenOf(orientation).cn + '\n' + (previous ? '【已有设计（请在此基础上按用户新要求修订，保留已完成部分）】\n' + JSON.stringify(previous) + '\n\n【用户新要求】' : '【用户想做的游戏】') + userText;
  const messages = [{ role: 'user', content: content + '\n\n（请全程用中文思考和解说。）' }];
  let plan = null;
  await runAgent({
    messages, signal, maxTurns: 3, finishTools: ['design_game'],
    req: { model: CODE_MODEL, system: ['用中文思考和解说。', '', PLAN_SYSTEM, '', '直接调用 design_game 工具输出方案，不要先输出文字。'].join(String.fromCharCode(10)), tools: [PLAN_TOOL], max_tokens: 16000, thinking: THINKING },
    cb: { onToolStart: cb.onToolStart, onToolDelta: cb.onToolDelta, onText: cb.onText, onThinking: cb.onThinking },
    exec: async (name, input) => { plan = normalizePlan(input); return { ok: true }; },
  });
  if (!plan) throw new Error('设计师没有给出方案');
  return plan;
}

const str = (v, n = 400) => String(v ?? '').slice(0, n);
const strs = (v, n = 20, len = 300) => (Array.isArray(v) ? v : []).map(x => str(x, len)).filter(Boolean).slice(0, n);
/** scene: main.gd and anything that builds nodes; gameplay: pure logic. Planner's tag wins. */
export function moduleOwner(m) {
  const f = String(m?.file || '');
  if (f === 'main.gd') return 'scene';
  if (m?.owner === 'scene' || m?.owner === 'gameplay') return m.owner;
  return /(view|hud|ui|board|table|scene|fx|render|layout|anim|panel|screen|draw|visual)/i.test(f) ? 'scene' : 'gameplay';
}

export function normalizePlan(p) {
  p = p && typeof p === 'object' ? p : {};
  const ms = (Array.isArray(p.milestones) ? p.milestones : []).slice(0, 6).map((m, i) => ({ id: str(m?.id || 'M' + (i + 1), 8), name: str(m?.name, 40), goal: str(m?.goal, 300), acceptance: strs(m?.acceptance, 8) }));
  if (!ms.length) ms.push({ id: 'M1', name: '可玩核心', goal: '核心循环可以完整玩一局', acceptance: ['能开始、操作、分出胜负'] });
  return {
    title: str(p.title || '新游戏', 24), pitch: str(p.pitch, 120), genre: str(p.genre || 'code', 30),
    closest_game: str(p.closest_game, 60), differences: strs(p.differences, 5), core_loop: str(p.core_loop, 300),
    rules: strs(p.rules, 16), layout: str(p.layout, 600),
    controls: (Array.isArray(p.controls) ? p.controls : []).filter(c => Array.isArray(c) && c.length >= 2).slice(0, 4).map(c => [str(c[0], 12), str(c[1], 20)]),
    goal_text: str(p.goal_text, 60),
    modules: (Array.isArray(p.modules) ? p.modules : []).slice(0, MAX_FILES).map(m => ({ file: str(m?.file, 40), owner: moduleOwner(m), role: str(m?.role, 200), interface: str(m?.interface, 600) })),
    milestones: ms, build_steps: strs(p.build_steps, 8, 40),
    palette: strs(p.palette, 5, 9).filter(h => /^#[0-9a-f]{6}$/i.test(h)),
    art_bible: str(p.art_bible, 300),
    orientation: p.orientation === 'portrait' ? 'portrait' : 'landscape',
    assets: (Array.isArray(p.assets) ? p.assets : []).slice(0, 3).filter(a => a && a.prompt).map(a => ({ id: str(a.id, 30).replace(/[^\w-]/g, '_') || 'art', kind: a.kind === 'sprite' ? 'sprite' : 'background', name: str(a.name, 20), prompt: str(a.prompt, 400) })),
    current: 0,
  };
}

// ------------------------------------------------------------------ programmer

export const SDK_DOC = [
  '# G：平台 SDK（全局单例，任何脚本里直接用 G.xxx）',
  '流程：G.win(final_score:=-1, stars:=3) 胜利并弹出平台结算卡；G.lose(final_score:=-1)；G.add_score(n)；G.score；G.elapsed()；await G.wait(secs)（暂停时停表）；G.screen() -> Vector2 屏幕尺寸。',
  '声音（程序合成，直接可用）：G.sfx(name, vol_db:=0.0, pitch:=1.0)，name ∈ pop sparkle jump coin hurt win lose whoosh step land stomp checkpoint tick star；G.sfx_combo("coin") 连击音高递增。',
  '手感：G.toast(text, color, secs)；G.float_text(screen_pos, text, color, font_size:=36) 飘字；G.burst(screen_pos, color, amount:=24) 粒子爆开；G.pop(node) 弹一下；G.shake(node, amount:=10) 抖动单个节点；G.shake_screen(amount)；G.flash(node)；G.move_to(node, pos, secs, trans) -> Tween；G.fade_in(node)/G.fade_out(node, secs, free_after)；G.count_up(label, from, to, secs, prefix, suffix) 数字滚动；G.hover_lift(control) 悬停上浮；G.make_draggable(control, on_drop: Callable(control, global_pos) -> bool) 拖拽（返回 false 自动弹回）。',
  'UI 部件：G.color(i) 取设计调色板颜色；G.style(bg, radius, border, border_w, shadow) -> StyleBoxFlat；G.label(text, size:=24, color, align) -> Label；G.panel(bg, radius, border, border_w, shadow) -> PanelContainer；G.button(text, bg:=G.color(0), size:=24) -> Button（自带点击音与弹跳）；G.draw_shape(canvas_item, shape, center, radius, color) 在 _draw() 里画 heart diamond club spade star circle square triangle。',
  '素材：G.tex(asset_id) -> Texture2D 或 null（AI 生图还没好时为 null，要先用矢量/色块占位）；信号 G.asset_ready(id) 到达后可替换。',
  '数据：G.shuffle(array) 原地洗牌并返回；G.pick(array)；G.rng（RandomNumberGenerator）。',
  '自测：G.check(ok: bool, what: String)；G.click(control) 模拟点击控件中心；G.click_at(pos)。',
].join('\n');

const CODE_SYSTEM = [
  '你是「造梦」平台的 AI 游戏程序员（形象是一架紫色小无人机），在用户眼前用 Godot 4.7 GDScript 把设计师的方案写成真正能玩的游戏。用户不懂编程，你用轻松的中文解说你在做什么（"先把牌桌铺好……"），不要给用户讲代码细节。',
  '',
  '# 运行环境',
  '- 游戏是若干 .gd 模块，入口 main.gd（extends Control，全屏，在 _ready() 里用代码创建所有节点；也可 extends Node2D）。模块之间用 const Deck = preload("deck.gd") 引用（只写文件名）。不能用 class_name、load()、文件/网络/OS 访问、@tool。没有 .tscn，所有节点用代码 new。',
  '- 屏幕方向见设计方案的「屏幕」一行：横屏 1280x720 或竖屏 720x1280，长边可能更长，用 G.screen() 或锚点适配，不要写死坐标。竖屏是手机竖握：按钮要大（至少 88 像素高）、放下半屏。平台在开始前显示开始卡、结束后显示结算卡（由 G.win/G.lose 触发），你不需要做开始菜单和结算页，但游戏内要有自己的 HUD（分数、回合、目标等）。',
  '- 字体已支持中文；不要用 emoji 和 ♠♥ 这类符号字符，花色/图标用 G.draw_shape 或 _draw() 画。',
  '- Godot 4 写法：@onready、signal x(a)、x.emit()、btn.pressed.connect(func(): ...)、await G.wait(0.2)、create_tween()。常见编译错误要避免：从 Array/Dictionary 取出的值没有类型，用 := 推断会报错，要写 var v: int = arr[i] 或 var v = arr[i]；不要用 Python 语法；整数除法写 float(a)/b；内部类用 class Foo: 定义；lambda 里不能给外部局部变量重新赋值（改成成员变量）。',
  '- 鼠标输入：Control 的 gui_input 或 Button.pressed；背景 ColorRect 要设 mouse_filter = MOUSE_FILTER_IGNORE，否则会挡住点击。',
  '',
  SDK_DOC,
  '',
  '# 让搭建过程好看（非常重要）',
  '- 平台会在每个模块写完后自动试运行，加载成功就热更新到用户的预览里，无人机会把"新出现的节点"一个个飞过去点亮。所以：先写 main.gd 的骨架（背景、区域、HUD 都能看到），再逐个补模块，每写一个模块画面就多一些东西。节点要在 _ready() 里立即创建（不要藏在 await 之后），并给重要节点起 name。',
  '- 每次 write_module 的 step 写成用户看得懂的进度（"洗牌和发牌""计分规则"）。',
  '- 用 G 的手感函数：出牌/得分/失误都要有动画、音效、飘字或粒子。颜色用 G.color(i)。',
  '',
  '# 自测（必须）',
  '- main.gd 必须有 func auto_test() -> void：用 G.click(...) 或直接调用游戏函数，真实地走一遍核心流程（例如选牌→出牌→计分→过关），每一步用 G.check(条件, "说明") 断言，最后尽量推进到胜利或失败。函数里要有 await（如 await G.wait(0.2)），总时长 < 20 秒，不能死循环。',
  '- run_test 会在真实 Godot 里运行并返回：编译/运行错误（文件:行号）、每条 G.check 结果、胜负、以及一张截图。根据结果修代码（patch_module 改小处，write_module 重写整文件），直到全部通过。',
  '- 不要为了通过测试而削弱 auto_test；它是证明"能玩"的证据。',
  '',
  '# 工作流程（每一轮）',
  '1. 一句话说明本轮目标（当前里程碑）。',
  '2. 按模块依赖顺序 write_module：先 main.gd 骨架 → 数据/规则模块 → 视图模块 → 回到 main.gd 串起来。一个文件 ≤ 350 行，过长就拆。',
  '3. run_test，修到通过（最多几次；实在修不好就如实告诉用户哪里还不行）。',
  '4. finish：summary 用 2-4 句中文告诉用户现在能玩什么、怎么玩；suggestions 给 2-3 个下一步建议（第一个通常是"继续：<下一个里程碑>"）；milestone_done 写完成的里程碑 id。',
  '- 用户反馈修改时：只改需要改的模块，改完同样 run_test 再 finish。若用户要求的东西本平台做不到（如 3D、联网对战），如实说明并给替代方案，绝不偷偷换成别的游戏类型。',
].join('\n');

const CODE_TOOLS = [
  {
    name: 'write_module',
    description: '创建或整体重写一个 GDScript 模块文件。写完平台会自动试加载，成功则热更新到用户预览。',
    input_schema: { type: 'object', required: ['file', 'step', 'code'], properties: {
      step: { type: 'string', description: '给用户看的进度说明（中文，≤14 字），先写这个字段' },
      file: { type: 'string', description: '文件名，如 main.gd / deck.gd' },
      code: { type: 'string', description: '完整 GDScript 源码' },
    } },
  },
  {
    name: 'patch_module',
    description: '对已有模块做精确的小改动：把 old 文本（必须在文件中唯一出现）替换为 new。适合修 bug。',
    input_schema: { type: 'object', required: ['file', 'old', 'new'], properties: {
      step: { type: 'string' }, file: { type: 'string' }, old: { type: 'string' }, new: { type: 'string' },
    } },
  },
  {
    name: 'delete_module',
    description: '删除不再需要的模块。',
    input_schema: { type: 'object', required: ['file'], properties: { file: { type: 'string' } } },
  },
  {
    name: 'run_test',
    description: '在真实 Godot 运行时里运行游戏并执行 main.gd 的 auto_test()，返回错误、断言结果、胜负和截图。',
    input_schema: { type: 'object', properties: { look: { type: 'boolean', description: '是否附带截图（默认 true）' } } },
  },
  {
    name: 'update_plan',
    description: '根据用户反馈修订后续里程碑（已完成的不要改）。',
    input_schema: { type: 'object', required: ['milestones'], properties: { milestones: PLAN_TOOL.input_schema.properties.milestones, note: { type: 'string' } } },
  },
  {
    name: 'finish',
    description: '本轮结束。',
    input_schema: { type: 'object', required: ['summary'], properties: {
      summary: { type: 'string' }, suggestions: { type: 'array', items: { type: 'string' } }, milestone_done: { type: 'string' },
    } },
  },
];

/** Last few lines of a module that is still streaming in (shown on the agent's drone and code card). */
export function codeTail(json, n = 7) {
  const part = parsePartialJson(json);
  const code = typeof part?.code === 'string' ? part.code : typeof part?.new === 'string' ? part.new : '';
  if (!code) return null;
  const lines = code.split('\n');
  return { tail: lines.slice(-n).map(l => l.replace(/\t/g, '  ').slice(0, 56)).join('\n'), code: code.length > 9000 ? code.slice(-9000) : code, total: lines.length };
}

const DESIGN_ORDER = ['title', 'pitch', 'palette', 'art_bible', 'assets', 'genre', 'closest_game', 'differences', 'core_loop', 'rules', 'layout', 'controls', 'goal_text', 'modules', 'milestones', 'build_steps'];
/** Assets in a streaming design whose prompt is complete (a later item or a later field has started). */
export function readyAssets(part) {
  const list = Array.isArray(part?.assets) ? part.assets : [];
  const after = DESIGN_ORDER.slice(DESIGN_ORDER.indexOf('assets') + 1).some(k => part && k in part);
  return (after ? list : list.slice(0, -1)).filter(a => a && a.id && a.prompt && a.name);
}

export function designBrief(d) {
  const ms = d.milestones.map((m, i) => (i < d.current ? '[已完成] ' : i === d.current ? '[本轮目标] ' : '[之后] ') + m.id + ' ' + m.name + '：' + m.goal + '｜验收：' + m.acceptance.join('；')).join('\n');
  return [
    '# 设计方案：' + d.title + '（' + d.genre + '）', d.pitch,
    '屏幕：' + screenOf(d.orientation).cn + '。设计尺寸以此为准，G.screen() 取实际大小（长边可能更长），布局用比例/锚点适配。',
    '最接近：' + d.closest_game + '；不同之处：' + d.differences.join('；'),
    '核心循环：' + d.core_loop,
    '规则：\n- ' + d.rules.join('\n- '),
    '布局：' + d.layout,
    '操作：' + d.controls.map(c => c.join('=')).join('，'),
    '模块：\n' + d.modules.map(m => '- ' + m.file + '：' + m.role + (m.interface ? '｜接口：' + m.interface : '')).join('\n'),
    '调色板（G.color(0..)）：' + d.palette.join(' '),
    d.assets.length ? 'AI 素材（G.tex(id)，到达前要占位）：' + d.assets.map(a => a.id + '=' + a.kind + ' ' + a.name).join('，') : '',
    '里程碑：\n' + ms,
    'M1 搭建步骤：' + d.build_steps.join(' → '),
  ].filter(Boolean).join('\n');
}

function numbered(src) { return src.split('\n').map((l, i) => String(i + 1).padStart(3) + '| ' + l).join('\n'); }

/** Tool executor for one programmer turn. hooks: emit(ev), pushCode(files, label), save(). */
export class CodeSession {
  constructor(game, hooks) {
    this.game = game;
    this.hooks = hooks;
    this.testRuns = 0;
    this.lastTest = null;
    this.finish = null;
    this.signal = hooks.signal;
  }
  get files() { return (this.game.code ||= { files: {} }).files; }
  get meta() { return { title: this.game.meta.title, palette: this.game.meta.palette || [], orientation: this.game.meta.orientation || 'landscape' }; }

  async exec(name, input, agent = 'B', id = '') {
    const f = this['t_' + name];
    if (!f) return { error: '未知工具 ' + name };
    return f.call(this, input || {}, agent, id);
  }

  /** During the parallel build each file belongs to whoever wrote it first, so the crew never clobber each other. */
  claim(file, agent) {
    if (!this.claims) return null;
    const owner = this.claims[file];
    if (owner && owner !== agent) return { error: file + ' 由' + CREW[owner].name + '负责，你不能改它。需要的话在 finish 里说明。' };
    this.claims[file] = agent;
    return null;
  }

  async t_write_module({ file, step, code }, agent = 'B', id = '') {
    file = String(file || '').trim();
    const denied = this.claim(file, agent);
    if (denied) return denied;
    if (this.lockMain && agent === this.lockMain && file === 'main.gd') return { error: 'main.gd 由场景搭建师负责，你只写玩法逻辑模块' };
    code = String(code || '').replace(/\r\n/g, '\n');
    const issues = staticCheck(file, code);
    if (!this.files[file] && Object.keys(this.files).length >= MAX_FILES) issues.push('模块数量已达上限 ' + MAX_FILES);
    if (issues.length) return { error: '代码没有写入：\n' + issues.join('\n') };
    const prev = this.files[file];
    this.files[file] = code;
    this.hooks.emit({ type: 'code_write', id, agent, file, step: String(step || ''), lines: code.split('\n').length, code, created: !prev });
    if (this.lockMain && agent === this.lockMain) return this.checkModules([file]);
    return this.tryLoad(step || file, agent);
  }

  async t_patch_module({ file, old, new: nw, step }, agent = 'B', id = '') {
    const denied = this.claim(String(file || ''), agent);
    if (denied) return denied;
    const src = this.files[file];
    if (src == null) return { error: '没有这个文件：' + file + '。已有：' + Object.keys(this.files).join(', ') };
    old = String(old ?? '').replace(/\r\n/g, '\n');
    const n = old ? src.split(old).length - 1 : 0;
    if (n !== 1) return { error: n === 0 ? 'old 文本在 ' + file + ' 中找不到（注意缩进是 Tab）。当前文件：\n' + numbered(src).slice(0, 7000) : 'old 文本出现了 ' + n + ' 次，请包含更多上下文让它唯一' };
    const code = src.replace(old, String(nw ?? '').replace(/\r\n/g, '\n'));
    const issues = staticCheck(file, code);
    if (issues.length) return { error: '修改没有应用：\n' + issues.join('\n') };
    this.files[file] = code;
    this.hooks.emit({ type: 'code_write', id, agent, file, step: String(step || '修正 ' + file), lines: code.split('\n').length, code, patch: true });
    if (this.lockMain && agent === this.lockMain) return this.checkModules([file]);
    return this.tryLoad(step || '修正 ' + file, agent);
  }

  async t_delete_module({ file }) {
    if (file === 'main.gd') return { error: 'main.gd 是入口，不能删除' };
    delete this.files[file];
    return { ok: true, files: Object.keys(this.files) };
  }

  /** Quick headless load after each write; hot-swaps into the preview when the game starts cleanly. */
  /** Compile check for logic modules written while main.gd belongs to someone else: a synthetic
   *  entry preloads just these files, so parse/type errors come back with file:line. */
  async checkModules(list) {
    const files = {};
    for (const f of list) if (this.files[f] != null) files[f] = this.files[f];
    for (const [f, s] of Object.entries(this.files)) if (f !== 'main.gd' && new RegExp('preload\\("' + f.replace('.', '\\.') + '"\\)').test(Object.values(files).join('\n'))) files[f] = s;
    const NL = String.fromCharCode(10), TAB = String.fromCharCode(9);
    files['main.gd'] = ['extends Control', ...Object.keys(files).map((f, i) => 'const _M' + i + ' = preload("' + f + '")'), 'func auto_test() -> void:', TAB + 'await G.wait(0.05)', ''].join(NL);
    const r = await runCodeTest(files, this.meta, { signal: this.signal });
    const errors = r.errors.filter(e => e.kind !== 'warning' && e.file !== 'main.gd');
    const ok = r.loaded && !errors.length;
    this.hooks.emit({ type: 'compile', agent: this.lockMain, files: list, ok, errors: errors.slice(0, 6) });
    return ok ? { ok: true, compiled: true, note: '编译通过。' } : { ok: true, compiled: false, note: '文件已保存，但编译有错误，请用 patch_module 修正：', errors: errors.slice(0, 12) };
  }

  async tryLoad(label, agent = 'B') {
    if (!this.files['main.gd']) return { ok: true, note: '已保存。main.gd 还没写，暂不能试运行。', files: Object.keys(this.files) };
    const r = await runCodeTest(this.files, this.meta, { signal: this.signal });
    const errors = r.errors.filter(e => e.kind !== 'warning');
    if (r.loaded && !errors.length) {
      this.hooks.pushCode({ ...this.files }, label, agent);
      return { ok: true, loaded: true, note: '已加载并热更新到用户预览。', files: Object.keys(this.files) };
    }
    return { ok: true, loaded: r.loaded, note: '文件已保存，但游戏暂时无法干净运行（若是因为依赖的模块还没写，可以先继续写）：', errors: errors.slice(0, 12), files: Object.keys(this.files) };
  }

  async t_run_test({ look = true }, agent = 'B', id = '') {
    if (!this.files['main.gd']) return { error: '还没有 main.gd' };
    if (this.testRuns >= MAX_TEST_RUNS) return { error: '本轮测试次数已用完，请如实总结现状并 finish' };
    this.testRuns++;
    this.hooks.emit({ type: 'test_start', agent, run: this.testRuns });
    const r = await runCodeTest(this.files, this.meta, { shot: look, signal: this.signal });
    this.lastTest = r;
    const errors = r.errors.filter(e => e.kind !== 'warning');
    const checks = r.checks || [];
    this.hooks.emit({ type: 'test', id, agent, shot: r.image || '', run: this.testRuns, ok: r.ok, loaded: r.loaded, has_test: r.has_test, result: r.result, errors: errors.slice(0, 8), checks: checks.slice(0, 20), ms: r.ms });
    if (r.loaded && !errors.length) this.hooks.pushCode({ ...this.files }, r.ok ? '自测通过' : '', agent);
    const summary = {
      ok: r.ok, loaded: r.loaded, has_auto_test: r.has_test, result: r.result || '未分胜负', score: r.score,
      errors: errors.slice(0, 15),
      checks: checks.map(c => (c.ok ? '✓ ' : '✗ ') + c.what),
      hint: r.ok ? '全部通过。' : !r.has_test && r.loaded ? 'main.gd 缺少 auto_test()。' : '请修复后再 run_test。错误行号对应文件行号。',
    };
    if (r.image) return { __blocks: [{ type: 'text', text: JSON.stringify(summary) + '\n截图如下，检查布局是否美观、文字是否被遮挡/溢出：' }, { type: 'image', source: { type: 'base64', media_type: 'image/jpeg', data: r.image } }] };
    return summary;
  }

  async t_update_plan({ milestones, note }) {
    const d = this.game.design;
    const fresh = normalizePlan({ milestones }).milestones;
    d.milestones = [...d.milestones.slice(0, d.current), ...fresh.filter(m => !d.milestones.slice(0, d.current).some(x => x.id === m.id))];
    this.hooks.emit({ type: 'roadmap', milestones: d.milestones, current: d.current, note: String(note || '') });
    return { ok: true };
  }

  async t_finish(input, agent = 'B') {
    if (this.finishes) this.finishes[agent] = String(input.summary || '');
    this.finish = { summary: String(input.summary || ''), suggestions: strs(input.suggestions, 3, 40), milestone_done: String(input.milestone_done || '') };
    return { ok: true };
  }
}

/** First user message for a programmer turn. */
export function codeTurnPrompt(game, userText, isFirst) {
  const d = game.design;
  const files = game.code?.files || {};
  const cur = d.milestones[d.current];
  const parts = [designBrief(d)];
  if (Object.keys(files).length) parts.push('# 当前代码\n' + Object.entries(files).map(([f, s]) => '## ' + f + '\n' + numbered(s)).join('\n\n'));
  if (isFirst) parts.push('# 本轮任务\n实现 ' + (cur ? cur.id + ' ' + cur.name : 'M1') + '。用户原话：「' + userText + '」');
  else parts.push('# 用户这次说\n「' + userText + '」\n' + (/^(继续|下一步|接着|继续做|go on|continue)/i.test(userText.trim()) && cur ? '→ 推进里程碑 ' + cur.id + ' ' + cur.name + '。' : '→ 按用户要求修改（必要时用 update_plan 调整后续里程碑）。'));
  return parts.join('\n\n');
}

/** One agent loop over a shared CodeSession; the agent id travels with every tool call. */
function runRole({ session, agent, prompt, names, cb, signal, maxTurns, history = [] }) {
  const messages = [...history, { role: 'user', content: prompt + '\n\n（请全程用中文思考和解说。）' }];
  return runAgent({
    messages, signal, cb, maxTurns, finishTools: ['finish'],
    req: { model: CODE_MODEL, system: '用中文思考和解说。\n\n' + CODE_SYSTEM, tools: names ? CODE_TOOLS.filter(t => names.includes(t.name)) : CODE_TOOLS, max_tokens: 32000, thinking: THINKING },
    exec: (name, input, id) => session.exec(name, input, agent, id),
  }).then(out => ({ out, messages }));
}

/** Single-programmer turn (follow-ups and "继续"): B does everything. */
export async function runProgrammer({ game, userText, isFirst, hooks, cb, cbFor, signal, history = [] }) {
  const session = new CodeSession(game, { ...hooks, signal });
  const { out, messages } = await runRole({ session, agent: 'B', prompt: codeTurnPrompt(game, userText, isFirst), cb: cb || cbFor('B'), signal, maxTurns: 40, history });
  return { session, messages, out };
}

/** Files each crew member owns in the parallel phase. */
export function crewSplit(design) {
  const gameplay = design.modules.filter(m => m.owner === 'gameplay' && m.file !== 'main.gd');
  const scene = design.modules.filter(m => m.owner !== 'gameplay' || m.file === 'main.gd');
  if (!scene.some(m => m.file === 'main.gd')) scene.unshift({ file: 'main.gd', owner: 'scene', role: '入口：搭界面、串流程', interface: '' });
  return { gameplay, scene };
}

const fileList = ms => ms.map(m => '- ' + m.file + '：' + m.role + (m.interface ? '｜接口：' + m.interface : '')).join('\n');

export function crewPrompts(design, userText) {
  const { gameplay, scene } = crewSplit(design);
  const brief = designBrief(design);
  const B = gameplay.length ? [brief,
    '# 你的身份：玩法程序员（B）',
    '你和场景搭建师（C）正在并行开工。你只负责下面这些纯逻辑模块（规则、数据、状态机、计分、AI 对手），不创建任何界面节点，不写 main.gd：\n' + fileList(gameplay),
    '- 逻辑模块用 extends RefCounted（需要信号时 extends Node 也行），对外接口严格按设计里的签名；数据用 Dictionary/Array 并在文件顶部注释写清字段，C 之后会照着接。',
    '- 按依赖顺序逐个 write_module，平台会立刻编译检查并把错误（文件:行号）返回给你，有错就 patch_module 修。',
    '- 全部写完、编译通过后调用 finish：summary 用一两句说明各模块的用法（给联调看）。不要 run_test（你还没有入口）。用户原话：「' + userText + '」',
  ].join('\n\n') : null;
  const C = [brief,
    '# 你的身份：场景搭建师（C）',
    '你和玩法程序员（B）正在并行开工。你负责入口 main.gd 和这些界面/表现模块：\n' + fileList(scene),
    gameplay.length ? 'B 正在写这些逻辑模块：' + gameplay.map(m => m.file).join('、') + '。它们还没写完，这一阶段你绝对不要 preload 它们；先用 main.gd 里的本地示例数据（几张示例牌、示例分数、示例棋盘……）把画面摆出来，之后的联调阶段会把真逻辑接上。' : '',
    '- 目标：让用户尽快看到游戏的样子。第一步立刻写出 main.gd 骨架（≤120 行：背景、各区域面板、HUD 标签、示例内容），每写一个文件平台都会热更新到用户预览，无人机会把新节点一个个点亮。然后再逐步丰富：视图模块（如卡牌/棋子绘制）、动画、配色细节。',
    '- 重要节点都要起 name，在 _ready() 里立即创建；视图模块对外接口写清楚，方便联调。',
    '- main.gd 先写一个简单的 auto_test()（检查关键节点存在即可）。完成画面后调用 finish，summary 一两句说明界面结构和接口。不要 run_test。用户原话：「' + userText + '」',
  ].filter(Boolean).join('\n\n');
  return { B, C, gameplay, scene };
}

/**
 * First build of a code game with a visible crew: B (gameplay) and C (scene) work in parallel, each
 * with its own avatar in the preview, then B integrates the two halves and runs the playtest loop.
 */
export async function runCrewBuild({ game, userText, hooks, cbFor, signal }) {
  const session = new CodeSession(game, { ...hooks, signal });
  const pr = crewPrompts(game.design, userText);
  session.lockMain = 'B';
  session.claims = {};
  for (const m of pr.gameplay) session.claims[m.file] = 'B';
  for (const m of pr.scene) session.claims[m.file] = 'C';
  hooks.emit({ type: 'phase', phase: 'build', text: pr.B ? '玩法程序员和场景搭建师同时开工' : '场景搭建师开工', agents: pr.B ? ['B', 'C'] : ['C'] });
  const notes = {};
  const one = async (agent, prompt) => {
    hooks.emit({ type: 'crew', agent, state: 'thinking', text: agent === 'B' ? '读方案，规划逻辑模块…' : '读方案，构思画面布局…' });
    try {
      await runRole({ session, agent, prompt, names: ['write_module', 'patch_module', 'finish'], cb: cbFor(agent), signal, maxTurns: 16 });
      notes[agent] = session.finishes?.[agent] || '';
    } catch (e) {
      if (signal?.aborted) throw e;
      notes[agent] = '（中途出错：' + String(e.message || e).slice(0, 120) + '）';
    }
    hooks.emit({ type: 'crew', agent, state: 'done', text: '这部分交付了' });
  };
  session.finishes = {};
  await Promise.all([pr.B && one('B', pr.B), one('C', pr.C)].filter(Boolean));
  session.lockMain = null;
  session.claims = null;
  session.finish = null;
  hooks.emit({ type: 'phase', phase: 'integrate', text: '联调：把玩法接到画面上，再自己试玩' , agents: ['B'] });
  hooks.emit({ type: 'crew', agent: 'B', state: 'thinking', text: '把逻辑接进 main.gd…' });
  const prompt = codeTurnPrompt(game, userText, true) + '\n\n# 现在是联调阶段（你是玩法程序员 B，负责收尾）\n上面的代码是你（逻辑模块）和场景搭建师 C（main.gd 与界面模块）并行写的。'
    + (notes.B ? '\nB 的交付说明：' + notes.B : '') + (notes.C ? '\nC 的交付说明：' + notes.C : '')
    + '\n请：1) 把 main.gd 里的示例数据换成真正的逻辑模块（preload 并调用），保留 C 的画面风格；2) 完成本里程碑的核心循环和 auto_test；3) run_test 修到通过；4) finish。能用 patch_module 小改就别整文件重写。';
  const { out, messages } = await runRole({ session, agent: 'B', prompt, cb: cbFor('B'), signal, maxTurns: 30 });
  return { session, messages, out };
}