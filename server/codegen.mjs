// "Code" engine: for any game that is not a platformer, one AI game maker designs the game and
// writes real GDScript modules on top of the runtime's G SDK (runtime/kit.gd), then plays it in a
// live Godot window (run_game / game_eval + screenshots) until it works - the same loop a developer
// uses in the editor. Every module write is test-loaded and hot-swapped into the user's preview,
// and the agent's test drive is mirrored into the preview, so the whole build stays visible.
// The crew (A designs, B gameplay, C scene) is a presentation of what the one agent is doing.
import { runAgent } from './agent.mjs';
import { parsePartialJson } from './json.mjs';
import { runCodeTest, staticCheck, bannedIssues } from './runner.mjs';
import { LiveGame } from './live.mjs';
import { MODEL_SETTINGS } from './model-config.mjs';

export const CODE_MODEL = MODEL_SETTINGS.codeModel;
const MAX_FILES = 30;
const MAX_TEST_RUNS = 8;
const MAX_FETCHES = 6;
const FETCH_CHARS = 12000;
/** Opus streams a readable summary of its reasoning, so the user sees what the agent is thinking. */
const THINKING = { type: 'adaptive', display: 'summarized' };
const budgetMin = Number(process.env.UGC_BUDGET_MIN || 10);
/** Minutes per turn: past `soft` every tool result asks the agent to wrap up; past `hard` only finish works. */
export const BUDGET = {
  first: { soft: budgetMin, hard: budgetMin * 1.4 },
  follow: { soft: budgetMin * 0.6, hard: budgetMin },
};

/** Who the user sees working: A designs, B writes gameplay and playtests, C builds the scene. */
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

export const screenOf = o => o === 'portrait' ? { o: 'portrait', w: 720, h: 1280, cn: '竖屏 720x1280（手机竖握）' } : { o: 'landscape', w: 1280, h: 720, cn: '横屏 1280x720' };

// ------------------------------------------------------------------ design

export const DESIGN_TOOL = {
  name: 'design_game',
  description: '输出游戏设计方案（会实时展示给用户），之后照着它开工。新游戏的第一步。',
  input_schema: {
    type: 'object',
    required: ['title', 'pitch', 'palette', 'closest_game', 'core_loop', 'rules', 'layout', 'controls', 'goal_text', 'modules', 'milestones', 'build_steps', 'art_bible'],
    properties: {
      title: { type: 'string', description: '游戏名（中文，≤12 字）。复刻已知游戏时用原作名' },
      pitch: { type: 'string', description: '一句话卖点' },
      palette: { type: 'array', items: { type: 'string' } },
      art_bible: { type: 'string' },
      assets: { type: 'array', items: { type: 'object', required: ['id', 'kind', 'name', 'prompt'], properties: { id: { type: 'string' }, kind: { type: 'string', enum: ['background', 'sprite'] }, name: { type: 'string' }, prompt: { type: 'string' } } } },
      genre: { type: 'string', description: '类型，如 deckbuilder / card / puzzle / idle / strategy / arcade' },
      faithful: { type: 'boolean', description: 'true = 复刻用户点名的已知游戏' },
      closest_game: { type: 'string', description: '复刻的原作，或最接近的已知游戏' },
      differences: { type: 'array', items: { type: 'string' }, description: '只有原创/改编时才写：和最接近游戏的关键不同' },
      core_loop: { type: 'string', description: '核心循环，一两句' },
      rules: { type: 'array', items: { type: 'string' }, description: '具体规则与数值（复刻时用原作数值）' },
      layout: { type: 'string', description: '屏幕布局（区域 + 内容）' },
      controls: { type: 'array', items: { type: 'array', items: { type: 'string' } }, description: '[["鼠标点击","选牌"], ...] 2-4 条' },
      goal_text: { type: 'string', description: '开始卡片上的一句话目标' },
      modules: { type: 'array', items: { type: 'object', required: ['file', 'role', 'owner'], properties: { file: { type: 'string' }, owner: { type: 'string', enum: ['scene', 'gameplay'] }, role: { type: 'string' }, interface: { type: 'string', description: '对外函数/信号签名、数据字典字段' } } } },
      milestones: { type: 'array', items: { type: 'object', required: ['id', 'name', 'goal', 'acceptance'], properties: { id: { type: 'string' }, name: { type: 'string' }, goal: { type: 'string' }, acceptance: { type: 'array', items: { type: 'string' } } } } },
      build_steps: { type: 'array', items: { type: 'string' } },
    },
  },
};

const str = (v, n = 400) => String(v ?? '').slice(0, n);
const strs = (v, n = 20, len = 300) => (Array.isArray(v) ? v : []).map(x => str(x, len)).filter(Boolean).slice(0, n);
/** scene: main.gd and anything that builds nodes; gameplay: pure logic. Planner's tag wins. */
export function moduleOwner(m) {
  const f = String(m?.file || '');
  if (f === 'main.gd') return 'scene';
  if (m?.owner === 'scene' || m?.owner === 'gameplay') return m.owner;
  return /(view|hud|ui|board|table|scene|fx|render|layout|anim|panel|screen|draw|visual|shader)/i.test(f) ? 'scene' : 'gameplay';
}

export function normalizePlan(p) {
  p = p && typeof p === 'object' ? p : {};
  const ms = (Array.isArray(p.milestones) ? p.milestones : []).slice(0, 6).map((m, i) => ({ id: str(m?.id || 'M' + (i + 1), 8), name: str(m?.name, 40), goal: str(m?.goal, 300), acceptance: strs(m?.acceptance, 8) }));
  if (!ms.length) ms.push({ id: 'M1', name: '可玩核心', goal: '核心循环可以完整玩一局', acceptance: ['能开始、操作、分出胜负'] });
  return {
    title: str(p.title || '新游戏', 24), pitch: str(p.pitch, 120), genre: str(p.genre || 'code', 30), faithful: p.faithful === true,
    closest_game: str(p.closest_game, 60), differences: strs(p.differences, 5), core_loop: str(p.core_loop, 300),
    rules: strs(p.rules, 30, 400), layout: str(p.layout, 800),
    controls: (Array.isArray(p.controls) ? p.controls : []).filter(c => Array.isArray(c) && c.length >= 2).slice(0, 4).map(c => [str(c[0], 12), str(c[1], 20)]),
    goal_text: str(p.goal_text, 60),
    modules: (Array.isArray(p.modules) ? p.modules : []).slice(0, MAX_FILES).map(m => ({ file: str(m?.file, 40), owner: moduleOwner(m), role: str(m?.role, 200), interface: str(m?.interface, 600) })),
    milestones: ms, build_steps: strs(p.build_steps, 8, 40),
    palette: strs(p.palette, 5, 9).filter(h => /^#[0-9a-f]{6}$/i.test(h)),
    art_bible: str(p.art_bible, 300),
    orientation: p.orientation === 'portrait' ? 'portrait' : 'landscape',
    assets: (Array.isArray(p.assets) ? p.assets : []).slice(0, 6).filter(a => a && a.prompt).map(a => ({ id: str(a.id, 30).replace(/[^\w-]/g, '_') || 'art', kind: a.kind === 'sprite' ? 'sprite' : 'background', name: str(a.name, 20), prompt: str(a.prompt, 400) })),
    current: 0,
  };
}

// ------------------------------------------------------------------ system prompt

export const SDK_DOC = [
  '# G：平台 SDK（全局单例，任何脚本里直接用 G.xxx）',
  '流程：G.win(final_score:=-1, stars:=3) 胜利并弹出平台结算卡；G.lose(final_score:=-1)；G.add_score(n)；G.score；G.elapsed()；await G.wait(secs)（暂停时停表）；G.screen() -> Vector2 屏幕尺寸。',
  '声音（程序合成，直接可用）：G.sfx(name, vol_db:=0.0, pitch:=1.0)，name ∈ pop sparkle jump coin hurt win lose whoosh step land stomp checkpoint tick star；G.sfx_combo("coin") 连击音高递增。',
  '手感：G.toast(text, color, secs)；G.float_text(screen_pos, text, color, font_size:=36) 飘字；G.burst(screen_pos, color, amount:=24) 粒子爆开；G.pop(node) 弹一下；G.shake(node, amount:=10) 抖动单个节点；G.shake_screen(amount)；G.flash(node)；G.move_to(node, pos, secs, trans) -> Tween；G.fade_in(node)/G.fade_out(node, secs, free_after)；G.count_up(label, from, to, secs, prefix, suffix) 数字滚动；G.hover_lift(control) 悬停上浮；G.make_draggable(control, on_drop: Callable(control, global_pos) -> bool) 拖拽（返回 false 自动弹回）。',
  'UI 部件：G.color(i) 取设计调色板颜色；G.style(bg, radius, border, border_w, shadow) -> StyleBoxFlat；G.label(text, size:=24, color, align) -> Label；G.panel(bg, radius, border, border_w, shadow) -> PanelContainer；G.button(text, bg:=G.color(0), size:=24) -> Button（自带点击音与弹跳）；G.draw_shape(canvas_item, shape, center, radius, color) 在 _draw() 里画 heart diamond club spade star circle square triangle。',
  '素材：G.tex(asset_id) -> Texture2D 或 null（AI 生图还没好时为 null，要先用矢量/色块占位）；信号 G.asset_ready(id) 到达后可替换。',
  '数据：G.shuffle(array) 原地洗牌并返回；G.pick(array)；G.rng（RandomNumberGenerator）。',
  '测试与调试：G.check(ok: bool, what: String)；G.click(control) 模拟点击控件中心；G.click_at(pos)；G.describe(node:=游戏根节点, depth:=2) -> 节点树（路径、类型、全局矩形 [x,y,w,h]、是否可见、文字）。',
].join('\n');

export const CODE_SYSTEM = [
  '你是「造梦」平台的 AI 游戏制作人（用户看到的是一支三人小队：策划师、玩法程序员、场景搭建师，其实都是你），独自负责策划、写 Godot 4.7 GDScript、试玩和修 bug 的全过程。用户不懂编程，正看着预览画面：每写完一个模块画面就热更新；你每次 run_game / game_eval 试玩，用户的预览也会同步演示你的操作。用轻松的中文简短解说你在做什么（一两句），不要讲代码细节。',
  '',
  '# 节奏与预算',
  '- 每轮有时间预算（见任务说明，工具结果里会提示已用时间）。预算内优先保证：核心循环完整可玩、画面整洁、试玩验证过。没做完的内容放进后续里程碑，不要交付跑不起来的东西。',
  '- 一次工具调用做一件完整的事；能并行想清楚的就一次写对，减少来回。',
  '',
  '# 设计（新游戏的第一步：design_game）',
  '- 用户点名了已有游戏（"做一个小丑牌""植物大战僵尸那样""UNO"）就是复刻：faithful=true，规则、数值、流程、界面布局和手感尽量贴近原作，保留原作名称和题材。不要换皮、不要改规则、不要为了"差异化"自创机制；只有用户明确说"改编""换成 X 题材""原创"时才改。',
  '- 拿不准原作的具体规则或数值时，可以先用 web_fetch 查 1-3 个页面（例如 wiki；MediaWiki 站点可在页面地址后加 ?action=raw 取源码），然后马上设计，不要长时间调研。',
  '- 原创需求：发挥创意，做一个有个性、好玩的版本。',
  '- 屏幕方向见任务说明：横屏按 1280x720、竖屏按 720x1280（手机竖握）设计；竖屏内容自上而下排列，按钮放在拇指能够到的下半屏。',
  '- 游戏内文字用简体中文，不用 emoji（字体不支持），花色等符号用矢量图形绘制。',
  '- modules：按职责拆分（数据表、规则引擎、视图、HUD、main.gd 入口），owner="gameplay" 是纯逻辑，owner="scene" 是建界面的模块。内容多的游戏可以有 10 个以上模块。',
  '- milestones：M1 是可玩的核心循环（复刻时就是原作的核心循环），之后逐步补全内容、手感和打磨。每个都写可验证的验收标准。build_steps：M1 的 4-7 个用户看得懂的搭建步骤。',
  '- 字段按顺序输出：先 title、pitch、palette、art_bible、assets（0-6 个 AI 生图：background 或 sprite，后台生成，到达前用矢量占位），再其余字段。',
  '',
  '# 运行环境',
  '- 游戏是若干 .gd 模块，入口 main.gd（extends Control，全屏，在 _ready() 里用代码创建所有节点；也可 extends Node2D）。模块之间用 const Deck = preload("deck.gd") 引用（只写文件名）。不能用 class_name、load()、文件/网络/OS 访问、@tool。没有 .tscn，所有节点用代码 new。',
  '- 用 G.screen() 或锚点适配屏幕（长边可能更长），不要写死整屏坐标。平台在开始前显示开始卡、结束后显示结算卡（由 G.win/G.lose 触发），你不需要做开始菜单和结算页，但游戏内要有自己的 HUD。',
  '- 视觉可以做得很精致：Shader 用代码创建（var sh := Shader.new(); sh.code = "shader_type canvas_item; ..."; var m := ShaderMaterial.new(); m.shader = sh），可以做背景流动、卡牌光泽、CRT 等效果；_draw() 自绘；Tween 做动效。',
  '- Godot 4 写法：@onready、signal x(a)、x.emit()、btn.pressed.connect(func(): ...)、await G.wait(0.2)、create_tween()。常见编译错误：从 Array/Dictionary 取出的值没有类型，用 := 推断会报错，要写 var v: int = arr[i] 或 var v = arr[i]；整数除法写 float(a)/b；内部类用 class Foo: 定义；lambda 里不能给外部局部变量重新赋值（改成成员变量）。',
  '- 鼠标输入：Control 的 gui_input 或 Button.pressed；背景 ColorRect 要设 mouse_filter = MOUSE_FILTER_IGNORE，否则会挡住点击。铺满父节点用 set_anchors_and_offsets_preset(PRESET_FULL_RECT)（只用 set_anchors_preset 不改 offsets，尺寸可能是 0）。',
  '- 文件规模：最多 ' + MAX_FILES + ' 个模块，单个文件建议 ≤ 900 行，过长就按职责拆开。',
  '',
  SDK_DOC,
  '',
  '# 搭建顺序（每一步都让画面有变化）',
  '1. 先写 main.gd 骨架：背景、主要区域、HUD 标签都能看到。节点在 _ready() 里立即创建（不要藏在 await 之后），重要节点起 name。',
  '2. 数据与规则模块（纯逻辑，extends RefCounted）：写完就用 run_game + game_eval 直接调用函数验证规则和数值（例如构造一手牌算分，和原作数值对照）。',
  '3. 视图与交互模块，接进 main.gd。用 G 的手感函数：操作、得分、失误都要有动画、音效、飘字或粒子。颜色用 G.color(i)。',
  '4. 像玩家一样把每个关键画面走一遍：run_game 启动后，用 game_eval 点按钮/调用函数推进（开局 → 操作 → 结算 → 下一关/商店 …），每个画面带截图看一眼：重叠、溢出、出屏、尺寸为 0、文字看不清都要修。布局问题先用 G.describe 查实际矩形再改。',
  '5. main.gd 写 func auto_test() -> void：用 G.click 或直接调用游戏函数真实走一遍核心流程，每步 G.check(条件, "说明")，尽量推进到胜利或失败；要有 await，总时长 < 20 秒。run_test 通过后 finish。不要为了通过而削弱 auto_test。',
  '',
  '# 工具要点',
  '- write_module 写整个文件，patch_module 精确替换一处（old 必须唯一，缩进是 Tab）。写完平台会自动试加载，成功就热更新到用户预览。',
  '- read_module / grep_code 查看已有代码（行号从 1 开始），改之前先看清楚，不要凭记忆改。',
  '- run_game：用当前代码（重新）启动游戏窗口（游玩模式），返回加载错误和截图。改了代码后要再 run_game 才生效。',
  '- game_eval：在运行中的游戏里执行一段 GDScript，作为 func run(game, G) 的函数体：game 是 main.gd 的实例，可以 await，return 的值以 JSON 返回，look=true 时附带截图。模块里的类通过 game 上的常量访问（如 game.Rules），eval 里不能 preload。例：',
  '    G.click(game.get_node("PlayButton"))',
  '    await G.wait(0.8)',
  '    return {"score": game.score, "hand": game.hand.size(), "ui": G.describe(game, 1)}',
  '',
  '# 每一轮的收尾',
  '- finish：summary 用 2-4 句中文告诉用户现在能玩什么、怎么玩，如实说明还不行的地方；suggestions 给 2-3 个下一步建议（第一个通常是"继续：<下一个里程碑>"）；milestone_done 写完成的里程碑 id。',
  '- 用户反馈修改时只改需要改的地方，改完同样试玩验证再 finish。用户要的东西本平台做不到（如 3D、联网对战）就如实说明并给替代方案，绝不偷偷换成别的游戏类型。',
].join('\n');

// ------------------------------------------------------------------ tools

const TOOLS = [
  DESIGN_TOOL,
  {
    name: 'web_fetch',
    description: '读取一个网页的正文文本（每次最多 ' + FETCH_CHARS + ' 字，用 offset 翻页）。用于查已知游戏的规则和数值。',
    input_schema: { type: 'object', required: ['url'], properties: { url: { type: 'string' }, offset: { type: 'number' } } },
  },
  {
    name: 'write_module',
    description: '创建或整体重写一个 GDScript 模块文件。写完平台会自动试加载，成功则热更新到用户预览。',
    input_schema: { type: 'object', required: ['file', 'step', 'code'], properties: {
      file: { type: 'string', description: '文件名，如 main.gd / deck.gd（先写这个字段）' },
      step: { type: 'string', description: '给用户看的进度说明（中文，≤14 字）' },
      code: { type: 'string', description: '完整 GDScript 源码' },
    } },
  },
  {
    name: 'patch_module',
    description: '对已有模块做精确的小改动：把 old 文本（必须在文件中唯一出现）替换为 new。',
    input_schema: { type: 'object', required: ['file', 'old', 'new'], properties: {
      file: { type: 'string' }, step: { type: 'string' }, old: { type: 'string' }, new: { type: 'string' },
    } },
  },
  {
    name: 'read_module',
    description: '读取模块源码（带行号）。',
    input_schema: { type: 'object', required: ['file'], properties: { file: { type: 'string' }, offset: { type: 'number', description: '起始行，默认 1' }, limit: { type: 'number', description: '行数，默认 400' } } },
  },
  {
    name: 'grep_code',
    description: '在所有模块里搜索正则（或纯文本），返回 文件:行号: 内容。',
    input_schema: { type: 'object', required: ['pattern'], properties: { pattern: { type: 'string' }, file: { type: 'string', description: '只搜这个文件（可选）' } } },
  },
  {
    name: 'delete_module',
    description: '删除不再需要的模块。',
    input_schema: { type: 'object', required: ['file'], properties: { file: { type: 'string' } } },
  },
  {
    name: 'run_game',
    description: '用当前代码在真实 Godot 窗口里（重新）启动游戏（游玩模式），返回加载错误、状态和截图。用户预览会同步进入试玩。',
    input_schema: { type: 'object', properties: { step: { type: 'string', description: '给用户看的说明（≤14 字）' } } },
  },
  {
    name: 'game_eval',
    description: '在运行中的游戏里执行 GDScript（func run(game, G) 的函数体，可 await，return 值以 JSON 返回），用于像玩家一样操作游戏、读取状态、检查布局。look=true（默认）附带执行后的截图。',
    input_schema: { type: 'object', required: ['code'], properties: {
      step: { type: 'string', description: '给用户看的说明（≤14 字），如"打出一对 K"' },
      code: { type: 'string' },
      look: { type: 'boolean' },
      settle: { type: 'number', description: '截图前再等几秒让动画播完，默认 0.3' },
    } },
  },
  {
    name: 'run_test',
    description: '在全新的游戏进程里运行 main.gd 的 auto_test()，返回错误、断言结果、胜负，以及开局和测试结束时的两张截图。',
    input_schema: { type: 'object', properties: { look: { type: 'boolean', description: '是否附带截图（默认 true）' } } },
  },
  {
    name: 'update_plan',
    description: '根据用户反馈修订后续里程碑（已完成的不要改）。',
    input_schema: { type: 'object', required: ['milestones'], properties: { milestones: DESIGN_TOOL.input_schema.properties.milestones, note: { type: 'string' } } },
  },
  {
    name: 'finish',
    description: '本轮结束。',
    input_schema: { type: 'object', required: ['summary'], properties: {
      summary: { type: 'string' }, suggestions: { type: 'array', items: { type: 'string' } }, milestone_done: { type: 'string' },
    } },
  },
];
export const TOOL_NAMES = TOOLS.map(t => t.name);
/** Tools whose role (B or C) depends on the file argument. */
export const FILE_TOOLS = new Set(['write_module', 'patch_module', 'read_module', 'delete_module']);

/** Crew member shown for a tool call: design work is A, scene files are C, the rest is B. */
export function roleOf(name, input, design) {
  if (name === 'design_game' || name === 'web_fetch') return 'A';
  if (FILE_TOOLS.has(name)) {
    const f = String(input?.file || '');
    const m = (design?.modules || []).find(x => x.file === f);
    return moduleOwner(m || { file: f }) === 'scene' ? 'C' : 'B';
  }
  return 'B';
}
const PHASE_OF = { design_game: 'design', web_fetch: 'design', write_module: 'build', patch_module: 'build', delete_module: 'build', run_game: 'test', game_eval: 'test', run_test: 'test' };
const PHASE_TEXT = { design: '策划师正在设计玩法', build: '正在搭建游戏', test: 'AI 正在试玩自测' };

/** Last few lines of a module that is still streaming in (shown on the agent's drone and code card). */
export function codeTail(json, n = 7) {
  const part = parsePartialJson(json);
  const code = ['code', 'content', 'new'].map(k => part?.[k]).find(v => typeof v === 'string') || '';
  if (!code) return null;
  const lines = code.split('\n');
  return { tail: lines.slice(-n).map(l => l.replace(/\t/g, '  ').slice(0, 56)).join('\n'), code: code.length > 9000 ? code.slice(-9000) : code, total: lines.length };
}

const DESIGN_ORDER = ['title', 'pitch', 'palette', 'art_bible', 'assets', 'genre', 'faithful', 'closest_game', 'differences', 'core_loop', 'rules', 'layout', 'controls', 'goal_text', 'modules', 'milestones', 'build_steps'];
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
    d.faithful ? '复刻：' + d.closest_game + '（规则、数值、流程和界面都贴近原作）' : '最接近：' + d.closest_game + (d.differences.length ? '；不同之处：' + d.differences.join('；') : ''),
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

export function numbered(src, from = 1) { return src.split('\n').map((l, i) => String(i + from).padStart(4) + '| ' + l).join('\n'); }

/** Top-level declarations of a module, for prompts where the full source would be too long. */
export function outline(src) {
  return src.split('\n').map((l, i) => [i + 1, l]).filter(([, l]) => /^(extends|const|signal|var|func|static func|class|enum)\b/.test(l)).map(([n, l]) => String(n).padStart(4) + '| ' + l.slice(0, 140)).join('\n');
}

// ------------------------------------------------------------------ web_fetch

const PRIVATE_HOST = /^(localhost|127\.|10\.|192\.168\.|172\.(1[6-9]|2\d|3[01])\.|169\.254\.|0\.|\[?::1\]?$)/i;
/** Readable text of an HTML (or plain/wikitext) page. */
export function webText(body) {
  const s = String(body || '');
  if (!/<(html|body|div|p|table)\b/i.test(s)) return s.replace(/\r/g, '').replace(/\n{3,}/g, '\n\n').trim();
  return s.replace(/<(script|style|noscript|svg|head)\b[\s\S]*?<\/\1>/gi, ' ')
    .replace(/<br\s*\/?>|<\/(p|div|li|tr|h\d|table|section)>/gi, '\n').replace(/<\/t[dh]>/gi, ' | ')
    .replace(/<[^>]+>/g, ' ')
    .replace(/&nbsp;/g, ' ').replace(/&amp;/g, '&').replace(/&lt;/g, '<').replace(/&gt;/g, '>').replace(/&quot;/g, '"').replace(/&#39;/g, "'").replace(/&#(\d+);/g, (_, n) => String.fromCharCode(Number(n)))
    .replace(/[ \t]+/g, ' ').replace(/ *\n */g, '\n').replace(/\n{3,}/g, '\n\n').trim();
}

// ------------------------------------------------------------------ session

/** Tool executor for one turn of the game maker. hooks: emit(ev), pushCode(files, label, agent),
 *  onDesign(design), aiPlay(), mirrorEval(code), signal. */
export class CodeSession {
  constructor(game, hooks, { budget = null, live = null } = {}) {
    this.game = game;
    this.hooks = hooks;
    this.signal = hooks.signal;
    this.budget = budget;
    this.live = live;
    this.t0 = Date.now();
    this.testRuns = 0;
    this.fetches = 0;
    this.lastTest = null;
    this.finish = null;
    this.role = game.design ? 'B' : 'A';
    this.phase = '';
  }
  get files() { return (this.game.code ||= { files: {} }).files; }
  get meta() { return { title: this.game.meta.title, palette: this.game.meta.palette || [], orientation: this.game.meta.orientation || 'landscape' }; }
  minutes() { return (Date.now() - this.t0) / 60000; }
  overHard(graceMs = 0) { return !!this.budget && Date.now() - this.t0 > this.budget.hard * 60000 + graceMs; }

  async exec(name, input, _agent, id = '') {
    const f = this['t_' + name];
    if (!f) return { error: '未知工具 ' + name };
    input = input || {};
    this.role = roleOf(name, input, this.game.design);
    const ph = PHASE_OF[name];
    if (ph && ph !== this.phase) { this.phase = ph; this.hooks.emit({ type: 'phase', phase: ph, text: PHASE_TEXT[ph], agents: [this.role] }); }
    if (this.overHard() && name !== 'finish') return { error: '本轮时间已用完（' + this.minutes().toFixed(1) + ' 分钟），请立刻调用 finish，如实说明现状，把没做完的写进 suggestions。' };
    const r = await f.call(this, input, this.role, id);
    return this.withBudget(r);
  }

  /** Past the soft budget every result carries a wrap-up reminder. */
  withBudget(r) {
    if (!this.budget || this.minutes() < this.budget.soft || this.finish) return r;
    const note = '【已用 ' + this.minutes().toFixed(1) + ' 分钟，预算 ' + this.budget.soft + ' 分钟】请收尾：只修致命问题，run_test 后 finish。';
    if (r && Array.isArray(r.__blocks)) return { __blocks: [{ type: 'text', text: note }, ...r.__blocks] };
    return { ...r, time_note: note };
  }

  async t_design_game(input) {
    if (this.game.design) return { error: '方案已经存在。要调整后续路线用 update_plan。' };
    const plan = normalizePlan(input);
    plan.orientation = this.game.meta.orientation === 'portrait' ? 'portrait' : 'landscape';
    this.game.design = plan;
    this.hooks.onDesign?.(plan);
    return { ok: true, note: '方案已展示给用户。现在开工：先写 main.gd 骨架。' };
  }

  async t_web_fetch({ url, offset = 0 }) {
    if (this.fetches >= MAX_FETCHES) return { error: '本轮查资料次数已用完，请根据已有信息继续。' };
    let u;
    try { u = new URL(String(url || '')); } catch { return { error: '不是有效的网址：' + url }; }
    if (!/^https?:$/.test(u.protocol) || PRIVATE_HOST.test(u.hostname)) return { error: '只能访问公网 http(s) 网页' };
    this.fetches++;
    try {
      const res = await fetch(u, { signal: AbortSignal.timeout(15000), headers: { 'user-agent': 'Mozilla/5.0 (zaomeng game research)', accept: 'text/html,text/plain,*/*' } });
      if (!res.ok) return { error: '网页返回 HTTP ' + res.status };
      const text = webText((await res.text()).slice(0, 3e6));
      const at = Math.max(0, Number(offset) || 0);
      return { url: u.href, total: text.length, offset: at, text: text.slice(at, at + FETCH_CHARS), more: at + FETCH_CHARS < text.length };
    } catch (e) {
      return { error: '读取失败：' + String(e.message || e).slice(0, 160) };
    }
  }

  async t_write_module({ file, step, code }, agent = 'B', id = '') {
    file = String(file || '').trim();
    code = String(code || '').replace(/\r\n/g, '\n');
    const issues = staticCheck(file, code);
    if (!this.files[file] && Object.keys(this.files).length >= MAX_FILES) issues.push('模块数量已达上限 ' + MAX_FILES);
    if (issues.length) return { error: '代码没有写入：\n' + issues.join('\n') };
    const prev = this.files[file];
    this.files[file] = code;
    this.hooks.emit({ type: 'code_write', id, agent, file, step: String(step || ''), lines: code.split('\n').length, code, created: !prev });
    return this.tryLoad(step || file, agent);
  }

  async t_patch_module({ file, old, new: nw, step }, agent = 'B', id = '') {
    const src = this.files[file];
    if (src == null) return { error: '没有这个文件：' + file + '。已有：' + Object.keys(this.files).join(', ') };
    old = String(old ?? '').replace(/\r\n/g, '\n');
    const n = old ? src.split(old).length - 1 : 0;
    if (n !== 1) return { error: n === 0 ? 'old 文本在 ' + file + ' 中找不到（注意缩进是 Tab），先用 read_module 看准再改' : 'old 文本出现了 ' + n + ' 次，请包含更多上下文让它唯一' };
    const code = src.replace(old, () => String(nw ?? '').replace(/\r\n/g, '\n'));
    const issues = staticCheck(file, code);
    if (issues.length) return { error: '修改没有应用：\n' + issues.join('\n') };
    this.files[file] = code;
    this.hooks.emit({ type: 'code_write', id, agent, file, step: String(step || '修正 ' + file), lines: code.split('\n').length, code, patch: true });
    return this.tryLoad(step || '修正 ' + file, agent);
  }

  async t_read_module({ file, offset = 1, limit = 400 }) {
    const src = this.files[file];
    if (src == null) return { error: '没有这个文件：' + file + '。已有：' + Object.keys(this.files).join(', ') };
    const lines = src.split('\n');
    const from = Math.max(1, Math.floor(Number(offset) || 1));
    const n = Math.min(800, Math.max(1, Math.floor(Number(limit) || 400)));
    return { file, total_lines: lines.length, from, text: numbered(lines.slice(from - 1, from - 1 + n).join('\n'), from) };
  }

  async t_grep_code({ pattern, file }) {
    let re;
    try { re = new RegExp(String(pattern || ''), 'i'); } catch { re = new RegExp(String(pattern || '').replace(/[.*+?^${}()|[\]\\]/g, '\\$&'), 'i'); }
    const out = [];
    for (const [f, src] of Object.entries(this.files)) {
      if (file && f !== file) continue;
      src.split('\n').forEach((l, i) => { if (out.length < 80 && re.test(l)) out.push(f + ':' + (i + 1) + ': ' + l.trim().slice(0, 160)); });
    }
    return { matches: out.length, results: out.join('\n') || '（没有匹配）' };
  }

  async t_delete_module({ file }) {
    if (file === 'main.gd') return { error: 'main.gd 是入口，不能删除' };
    delete this.files[file];
    return { ok: true, files: Object.keys(this.files) };
  }

  /** Quick headless load after each write; hot-swaps into the preview when the game starts cleanly. */
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

  liveGame() { return (this.live ||= new LiveGame()); }

  /** Tool result with an optional screenshot the model can look at. */
  withShot(summary, image, caption) {
    if (!image) return summary;
    return { __blocks: [{ type: 'text', text: JSON.stringify(summary) + '\n' + caption }, { type: 'image', source: { type: 'base64', media_type: 'image/jpeg', data: image } }] };
  }

  async t_run_game({ step }, agent = 'B', id = '') {
    if (!this.files['main.gd']) return { error: '还没有 main.gd' };
    const r = await this.liveGame().start({ ...this.files }, this.meta, { signal: this.signal });
    const errors = r.errors.filter(e => e.kind !== 'warning');
    if (r.loaded) this.hooks.aiPlay?.();
    this.hooks.emit({ type: 'eval', id, agent, kind: 'run', step: String(step || '启动游戏'), ok: r.loaded && !errors.length, errors: errors.slice(0, 6), shot: r.image || '' });
    const summary = { loaded: r.loaded, errors: errors.slice(0, 15), state: r.state, hint: r.loaded ? '游戏在运行，用 game_eval 操作和检查。' : '游戏没能启动，修复错误后再 run_game。' };
    return this.withShot(summary, r.image, '开局截图：');
  }

  async t_game_eval({ code, look = true, settle = 0.3, step }, agent = 'B', id = '') {
    code = String(code || '').replace(/\r\n/g, '\n');
    const issues = bannedIssues('eval', code);
    if (/\bpreload\s*\(/.test(code)) issues.push('eval 里不能 preload，用 game 上的常量访问模块（如 game.Rules）');
    if (issues.length) return { error: issues.join('\n') };
    const live = this.liveGame();
    if (!live.running) {
      if (!this.files['main.gd']) return { error: '还没有 main.gd' };
      const s = await live.start({ ...this.files }, this.meta, { signal: this.signal });
      if (!s.loaded) return { error: '游戏启动失败，先修复：', errors: s.errors.slice(0, 12) };
      this.hooks.aiPlay?.();
    }
    const r = await live.eval(code, { shot: look !== false, settle: Math.min(5, Math.max(0, Number(settle) || 0.3)) });
    const errors = (r.errors || []).filter(e => e.kind !== 'warning');
    if (!errors.length) this.hooks.mirrorEval?.(code);
    this.hooks.emit({ type: 'eval', id, agent, kind: 'eval', step: String(step || ''), ok: r.ok && !errors.length, errors: errors.slice(0, 6), value: JSON.stringify(r.value ?? null).slice(0, 300), shot: r.image || '' });
    let value = JSON.stringify(r.value ?? null);
    if (value.length > 6000) value = value.slice(0, 6000) + ' …（已截断）';
    const summary = { ok: r.ok && !errors.length, value, errors: errors.slice(0, 12), state: r.state };
    return this.withShot(summary, r.image, '执行后的画面：');
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
    this.hooks.emit({ type: 'test', id, agent, shot: r.image_end || r.image || '', run: this.testRuns, ok: r.ok, loaded: r.loaded, has_test: r.has_test, result: r.result, errors: errors.slice(0, 8), checks: checks.slice(0, 20), ms: r.ms });
    if (r.loaded && !errors.length) this.hooks.pushCode({ ...this.files }, r.ok ? '自测通过' : '', agent);
    const summary = {
      ok: r.ok, loaded: r.loaded, has_auto_test: r.has_test, result: r.result || '未分胜负', score: r.score,
      errors: errors.slice(0, 15),
      checks: checks.map(c => (c.ok ? '✓ ' : '✗ ') + c.what),
      hint: r.ok ? '全部通过。' : !r.has_test && r.loaded ? 'main.gd 缺少 auto_test()。' : '请修复后再 run_test。错误行号对应文件行号。',
    };
    if (!r.image && !r.image_end) return summary;
    const blocks = [{ type: 'text', text: JSON.stringify(summary) + '\n截图：开局' + (r.image_end ? ' / auto_test 结束时' : '') + '。检查布局是否美观、文字是否被遮挡/溢出：' }];
    for (const img of [r.image, r.image_end]) if (img) blocks.push({ type: 'image', source: { type: 'base64', media_type: 'image/jpeg', data: img } });
    return { __blocks: blocks };
  }

  async t_update_plan({ milestones, note }) {
    const d = this.game.design;
    if (!d) return { error: '还没有设计方案，先 design_game' };
    const fresh = normalizePlan({ milestones }).milestones;
    d.milestones = [...d.milestones.slice(0, d.current), ...fresh.filter(m => !d.milestones.slice(0, d.current).some(x => x.id === m.id))];
    this.hooks.emit({ type: 'roadmap', milestones: d.milestones, current: d.current, note: String(note || '') });
    return { ok: true };
  }

  async t_finish(input) {
    this.finish = { summary: String(input.summary || ''), suggestions: strs(input.suggestions, 3, 40), milestone_done: String(input.milestone_done || '') };
    return { ok: true };
  }
}

// ------------------------------------------------------------------ turn

const FULL_CODE_CHARS = 60000;

/** First user message of a turn. recap: short log of earlier turns. */
export function codeTurnPrompt(game, userText, isFirst, recap = '') {
  const d = game.design;
  const files = game.code?.files || {};
  const scr = screenOf(game.meta?.orientation);
  const budget = isFirst ? BUDGET.first : BUDGET.follow;
  const parts = [];
  if (!d) {
    parts.push('【屏幕】' + scr.cn + (game.meta?.genre_hint ? '\n【类型】' + game.meta.genre_hint : '') + '\n【用户想做的游戏】' + userText);
    parts.push('# 本轮任务\n先 design_game（复刻已知游戏时，拿不准的规则可以先 web_fetch 查一下），然后按搭建顺序开工，完成 M1 并试玩验证。时间预算约 ' + budget.soft + ' 分钟。');
    return parts.join('\n\n');
  }
  parts.push(designBrief(d));
  if (recap) parts.push('# 之前几轮\n' + recap);
  const total = Object.values(files).reduce((n, s) => n + s.length, 0);
  if (Object.keys(files).length) {
    parts.push(total <= FULL_CODE_CHARS
      ? '# 当前代码\n' + Object.entries(files).map(([f, s]) => '## ' + f + '\n' + numbered(s)).join('\n\n')
      : '# 当前代码（太长，只列出顶层声明，需要时用 read_module / grep_code 查看）\n' + Object.entries(files).map(([f, s]) => '## ' + f + '（' + s.split('\n').length + ' 行）\n' + outline(s)).join('\n\n'));
  }
  const cur = d.milestones[d.current];
  if (isFirst) parts.push('# 本轮任务\n实现 ' + (cur ? cur.id + ' ' + cur.name : 'M1') + '。用户原话：「' + userText + '」');
  else parts.push('# 用户这次说\n「' + userText + '」\n' + (/^(继续|下一步|接着|继续做|go on|continue)/i.test(userText.trim()) && cur ? '→ 推进里程碑 ' + cur.id + ' ' + cur.name + '。' : '→ 按用户要求修改（必要时用 update_plan 调整后续里程碑）。'));
  parts.push('时间预算约 ' + budget.soft + ' 分钟。');
  return parts.join('\n\n');
}

/**
 * One turn of the game maker. makeCb(session) returns the streaming callbacks (the server tags
 * everything with session.role so the UI shows the right crew member).
 */
export async function runBuilder({ game, userText, isFirst, hooks, makeCb, signal, recap = '', live = null, model = CODE_MODEL, agentRunner = runAgent }) {
  const budget = isFirst ? BUDGET.first : BUDGET.follow;
  const session = new CodeSession(game, { ...hooks, signal }, { budget, live });
  const messages = [{ role: 'user', content: codeTurnPrompt(game, userText, isFirst, recap) + '\n\n（请全程用中文思考和解说。）' }];
  const tools = game.design ? TOOLS.filter(t => t.name !== 'design_game') : TOOLS;
  const out = await agentRunner({
    messages, signal, cb: makeCb(session), maxTurns: 80, finishTools: ['finish'],
    until: () => session.overHard(120000),
    req: { model, system: '用中文思考和解说。\n\n' + CODE_SYSTEM, tools, max_tokens: 32000, thinking: THINKING },
    exec: (name, input, id) => session.exec(name, input, null, id),
  });
  return { session, messages, out };
}
