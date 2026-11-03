// Agent for the "Godot project" engine (server/gproject.mjs): one AI game maker works on a complete
// Godot 4 project the way a developer does in the editor - any script, scene, resource, shader or
// project setting, 2D or 3D - and plays it in a live window (run_game / game_eval) until it works.
// Independent task workers stage owned files; the coordinator integrates and verifies the exact
// source revision. Browser startup receipts are distinct from native gameplay test evidence.
import { runAgent } from './agent.mjs';
import { CodeSession, DESIGN_TOOL, normalizePlan, screenOf, numbered, outline, webText, CODE_MODEL } from './codegen.mjs';
import { scanIssues } from './gproject.mjs';
import { DELEGATE_TASKS_TOOL, runTaskBatch } from './task-team.mjs';
import { createWorkflow, upsertTask, recordEvidence, acceptanceFor, settleWorkflow } from './workflow.mjs';
import { createIteration, updateIteration, iterationClock, iterationError, remainingMs, delegationBudget, abortable, throwIfAborted, tierLimits } from './iteration.mjs';
import { BUILD_SCENE_TOOL, isConstructionFile, applyConstruction, commitConstruction } from './construction.mjs';
import { GODOT_CAPABILITIES } from './capabilities.mjs';

const MAX_ASSETS = 12;
const THINKING = { type: 'adaptive', display: 'summarized' };
const ASSET_KINDS = ['background', 'sprite', 'texture', 'model3d', 'music', 'sfx'];
const ASSET_EXT = { background: 'png', sprite: 'png', texture: 'png', model3d: 'glb', music: 'mp3', sfx: 'mp3' };
/** Design-level art slots: stable ids the pencil kit draws until final art lands. */
/** Assets the game code still mentions; a failed asset the AI has since replaced cannot block acceptance. Without sources every asset counts. */
export function assetsInUse(assets, sources) {
  if (!sources) return assets;
  const code = Object.values(sources).join('\n');
  return assets.filter(a => !a.id || code.includes(a.id));
}

/** Only an asset still in flight blocks acceptance. Async final art is re-verified on arrival, and a
 * failed one will not change; the verified build already runs without it. */
export const assetBlocks = a => !a.async && a.state !== 'ready' && a.state !== 'failed';

export function artSlotsOf(list) {
  const out = [];
  for (const a of Array.isArray(list) ? list : []) {
    const id = String(a?.id || '').trim().toLowerCase();
    if (!/^[a-z][a-z0-9_]{1,30}$/.test(id) || id === 'art_style' || out.some(s => s.id === id)) continue;
    out.push({ id, kind: ['sprite', 'background', 'texture'].includes(a.kind) ? a.kind : 'sprite', name: String(a.name || '').slice(0, 20), prompt: String(a.prompt || '').slice(0, 300) });
    if (out.length >= 24) break;
  }
  return out;
}
export const assetPath = a => 'assets/' + a.id + '.' + (a.url?.match(/\.(\w+)$/)?.[1] || ASSET_EXT[a.kind] || 'png');

// ------------------------------------------------------------------ prompt

export const GP_SYSTEM = [
  '你是游戏助手，负责把用户的创作目标落实为可玩的 Godot 4.7 工程。你统筹设计、分工、整合与验收，可用 delegate_tasks 把独立文件交给真正独立执行的任务。用户正看着预览画面，用轻松的中文简短解说正在做什么，不讲底层实现。',
  '# 真实分工与交付',
  '- 3D 新游戏必须边搭边看：design_game 后马上分至少两次 build_scene 提交真实关卡（第一批地面/平台，第二批地标/障碍/出生区域，每批1–8个对象）。工具直接把物体搭进用户正在看的场景，且保存为最终游戏实际使用的关卡。先放下第一个真实物体，再写长玩法代码；不要只让工程师在工位空转。',
  '- build_scene 创建的 scenes/construction.json 和 scenes/construction.tscn 是关卡唯一来源，只能继续用 build_scene 修改；main.tscn 的 Construction 实例必须保留。玩法脚本继承 Node3D，复用 $Construction 的真实场地，动态玩家/敌人另外创建；不能重画一套看似相同的场地或移除 Construction。平台会核验实际加载的关卡版本。',
  '- 3D 制作时用户看到独立搭建视角；run_game/game_eval/run_test 期间编辑画面自动旁观实际运行中的验收游戏和已执行检查，用户主动试玩不被打断。完成后等待用户主动试玩，不能把搭建现场或旁观截图当成浏览器游戏启动回执。',
  '- 每轮有档位（Demo 或 品质），范围、时间和预算以本轮说明里的「档位」为准。任何档位都不用名称齐全冒充行为完成。',
  '- 独立文件适合并行时，delegate_tasks 一次最多委派 2 个小任务（如规则、场景表现）；每个任务写清精确文件归属、接口和可核验项。保留主入口与整合。小修改直接做，无需强行分工；剩余时间不足或开始收口后不能再委派。',
  '- 每个子任务最多 1–2 个小文件，目标两分半内一次完整提交。协调者亲自保留能独立启动的主循环，不把整个核心玩法绑在最慢任务上；先做小片段，再逐步接入子任务。设计简短清楚，不写长篇完整产品方案。',
  '- 第一份代码先写最小但完整的可运行骨架（输入、一个核心动作、失败与重开），立即 preview_checkpoint。再分小次追加美术和效果，不要一次 write_file 把全部玩法、绘制、音频和测试塞成超长大全；一个提交必须完整可保存，不能写到半个函数就结束。',
  '- depends_on 只引用同批任务 id，依赖成功合入后才启动。并行任务看不到彼此未提交内容；共享接口必须在 prompt 写清。review 是独立只读审查，可与开发并行或依赖完成的任务。',
  '- 子任务返回 applied 只表示文件合入，必须继续检查当前工程、run_game/game_eval 试玩、run_test 有效断言测试。失败保留候选和错误，独立成功部分不重做；可以同 id 重试，或亲自修复并通过最新版本检查后 resolve_task。',
  '- finish(status="complete") 受版本验收约束；测试后再修改必须重验。缺少断言、编译失败、未处理任务不能宣称完成。浏览器未回执时显示待预览确认。时间用尽或未完成时 finish(status="partial")，说明已做和待修复内容。',
  '',
  '# 节奏与预算',
  '- 时间目标、收口时间和硬上限见本轮说明。收口后停止新增功能与素材，只修阻塞问题、试玩、测试。玩法测试次数有上限（见档位）；仍失败就保存现状和下一步，不能绕过断言。',
  '- 在前半轮尽早做出一个可玩片段并调用 preview_checkpoint，让用户看见实际进展。逐文件保存只做安全扫描，不再反复整包构建。按完整片段统一预览，run_game / run_test 也会构建当前版本。',
  '- 一次工具调用做一件完整的事；想清楚再写，减少来回。',
  '- 用户会在场景里看到编写、保存、测试和修复状态。试玩时每次 game_eval 用 step 写清当前正在验证的一个玩家行为，按开局、操作、结算、重开的自然顺序展示；UGC.check 在对应行为执行后立即记录。不要等所有测试结束才解释，也不要为了表演添加无意义等待或假造通过结果。',
  '- 2D 游戏是在用户眼前拼出来的：每次 preview_checkpoint 后，编辑画面会直接载入新版本，小精灵把新出现的界面和物体逐块拼到屏幕上。所以要分步提交、让每次预览都有看得见的新部件（先背景与主要区域，再 HUD、角色、按钮、特效）；重要节点起稳定的 name（不要每次重建成随机名），这样只有真正新增的部分才会被重新拼装。每个模块 role 用简短功能名，interface 写清输入输出。',
  '- 玩家在制作中提交的补充会在下一次工作节点送达；小调整结合当前范围执行并验证，较大改动列入后续步骤。收到建议不等于已实现，结束时如实说明落实情况。',
  '- 高质量玩法模块应有独立职责、明确输入输出、可重复的规则用例和一个真实可玩的示例入口；优先复用已有规则，逐步提高交互、音画反馈和可读性，不靠增加文件或内容数量凑规模。',
  '',
  '# 设计（新游戏第一步：design_game）',
  '- 用户点名了已有游戏（"做一个小丑牌""植物大战僵尸那样""马里奥"）就是复刻：faithful=true，规则、数值、流程、界面布局和手感尽量贴近原作，保留原作名称和题材；不要换皮、不要为了"差异化"改规则。只有用户明确说"改编""换成 X 题材""原创"时才改。',
  '- 拿不准原作规则或数值时，先用 web_fetch 查资料（MediaWiki 站点可在地址后加 ?action=raw；可查页数见档位），然后设计。原创需求就发挥创意。',
  '- modules 写你计划的主要文件（脚本、场景、着色器），owner="scene" 是场景/界面/视觉，owner="gameplay" 是逻辑。art 列出美术位（见下），art_bible 写最终正式美术的风格方向（不是铅笔）。',
  '- milestones：M1 是可玩的核心循环，之后逐步补全内容、手感和打磨，每个都有可验证的验收标准；build_steps 是 M1 的 4-7 个用户看得懂的步骤。',
  '- 字段按顺序输出：先 title、pitch、palette、art_bible、art，再其余字段。',
  '',
  '# 工程环境（完整 Godot 工程，按当前 Web 能力档案交付）',
  '- project_capabilities 可查询真实能力。没有节点类白名单，但不能声称支持全部 Godot 原生能力：当前是单线程 Web Compatibility，不能使用 C#、GDExtension、Thread/WorkerThreadPool、RenderingDevice/计算着色器，也没有桌面或移动原生导出链路。接口开放不代表对应功能已经验收。',
  '- 你可以创建和修改任何文本文件：.gd（可以用 class_name、preload、load、信号、内部类、@export）、.tscn / .tres（Godot 4 文本格式，format=3）、.gdshader、.json，以及 project.godot（输入映射 [input]、自动加载 [autoload]、物理层、显示设置等）。2D 和 3D 都支持（Node3D、Camera3D、MeshInstance3D、CharacterBody3D、光照、粒子、物理……）。',
  '- 渲染器是 Compatibility（WebGL2，游戏要在手机浏览器上跑）：不要依赖 Forward+ 才有的功能（SDFGI、体积雾、计算着色器）；GPUParticles 可以用，CPUParticles 兼容性更好。',
  '- 入口是 project.godot 的 run/main_scene（默认 res://main.tscn，里面现在只是占位画面）。可以整个重写 main.tscn / main.gd，根节点类型随意（Control / Node2D / Node3D）。',
  '- 屏幕：project.godot 里已按任务说明设好视口（横屏 1280x720 或竖屏 720x1280），stretch=canvas_items + expand，长边可能更长，用锚点/容器或 get_viewport().get_visible_rect() 适配。',
  '- 输入：鼠标事件在手机上由触摸模拟，点击类游戏直接用鼠标/Button 即可。键盘操作的游戏（动作、平台跳跃、射击）要在 project.godot 的 [input] 里定义动作，并且在屏幕上放触控按钮（TouchScreenButton 或 Control 按钮调用 Input.action_press/release），否则手机玩不了。',
  '- 字体：默认主题字体已支持中文（res://addons/ugc/font.ttf）。游戏内文字用简体中文，不用 emoji。',
  '- 视觉可以做得很精致：铅笔工具包的美术位打底（见"美术"），再加着色器（.gdshader 或代码里 Shader.new()）、Tween、AnimationPlayer、粒子、StyleBoxFlat、Theme、Light2D、WorldEnvironment。',
  '- 安全限制（平台会拒绝写入）：不能执行系统命令（OS.execute 等）、不能用 JavaScriptBridge、不能联网（HTTPRequest 等）、文件只能访问 res:// 和 user://、不能动态生成代码（GDScript.new、Expression）、不能用 @tool 和编辑器 API。addons/ugc/ 是平台插件，不能改。',
  '',
  '# 平台插件 UGC（自动加载单例，任何脚本里直接用）',
  '- 结果：UGC.win(final_score := -1) / UGC.lose(final_score := -1) 上报胜负（游戏自己的结算界面照常做）；UGC.add_score(n)；UGC.result；UGC.score。',
  '- 测试与试玩：UGC.click_at(pos) / UGC.click(node) 模拟点击（Control 点中心，Node2D 点它的屏幕位置）；await UGC.drag(a, b, secs)；await UGC.press("action", secs) 按住输入动作；UGC.hold("action", true/false)；await UGC.key(KEY_SPACE, secs)；await UGC.wait(secs)；UGC.check(ok, "说明") 记一条断言；UGC.describe(root := 主场景, depth := 3) -> 节点树（路径、类型、屏幕矩形 rect、2D 屏幕坐标 screen、3D 坐标 pos3、可见性、文字）；UGC.toast(text)。',
  '',
  '# 美术：全程铅笔手绘（同一套代码，用户要求时才换成正式美术）',
  '- 所有画面都用平台铅笔工具包画，并且每个视觉元素都是一个「美术位」：const Pencil = preload("res://addons/ugc/pencil.gd")。它和用户刚看到的草图板是同一种纸张、线条和配色，Demo 就像草图活了过来。',
  '- 2D：背景 add_child(Pencil.backdrop("background"))（没有美术时是纸张）；角色/道具/图标 var n := Pencil.sprite("hero", Vector2(64, 80), func(s, size): s.rect(Rect2(Vector2.ZERO, size), Pencil.INK, Pencil.color("blue"), true); s.circle(...))，s 支持 rect / circle / ellipse / poly / line / polyline / arrow / text(pos, 文字, 字号)，参数 (形状, 墨色, 填充色, 是否排线, 线宽)，坐标从左上角 (0,0) 到 size；返回的节点以中心为原点。UI 用 control.theme = Pencil.theme(22)，面板 Pencil.style()。颜色只用 Pencil.color("red|orange|yellow|green|teal|blue|purple|pink|brown|gray")、Pencil.INK、Pencil.PAPER。',
  '- 3D：Pencil.environment(self) 设纸张背景；网格 mesh.material_override = Pencil.material(Pencil.color("teal"), "wall")（彩铅明暗 + 屏幕排线 + 墨线描边，第二个参数是贴图美术位）；角色/怪物/道具：先在一个 Node3D 视觉节点下搭好 Pencil.material 着色的网格，再调用 Pencil.actor3d("hero", 1.6, 视觉节点)（原地生效，返回值就是该节点，可不接）；有正式美术时自动隐藏这些网格、换成同高的立绘，没有时就是铅笔网格。玩法和碰撞放在父节点上，不跟美术节点走。',
  '- 美术位 id 用小写英文加下划线（hero、slime、coin、floor、wall、background），同一个东西始终用同一个 id；design_game 的 art 里列出每个美术位和它最终正式美术的样子。正式美术到达时（res://assets/<id>.png）工具包自动替换，尺寸、布局、碰撞完全不变，所以不需要也不能为美术改代码。',
  '- 铅笔稿也要有品质：清楚的轮廓和层次、主次分明的配色、排线表现阴影、动画与反馈（Tween 弹跳、抖动、闪白、飘字、粒子）。不要用纯色方块冒充美术。',
  '- 游戏全程保持铅笔手绘风，不要主动改变画风（不换配色体系，不用写实光影、辉光或滤镜盖掉铅笔质感）；打磨在铅笔风内进行。只有用户亲口要求生成素材或正式美术时，本轮说明的「画风与素材」才会开放 generate_asset 或美术子代理；没开放就不要申请任何素材（音乐、音效也不要），可以在下一步建议里提一句由用户决定。',
  '- 开放正式美术后，美术子代理在后台按美术位异步生成正式美术并自动接入、重新构建、复验，不占本轮时间；主流程不要等待它，也不要为美术位调用 generate_asset。generate_asset 只用于用户要的音乐、音效或美术位之外的特殊素材（kind: background / sprite / texture / model3d / music / sfx），每个游戏最多 ' + MAX_ASSETS + ' 个，每轮数量见档位。已申请的素材未就绪或失败仍须如实报告。',
  '- prompt 写清楚单个主体的外观（颜色、造型、朝向，如"facing right"），风格由 art_bible 统一，不要在一个 sprite 里画多个物体或整张图集。',
  '- 生成好后文件出现在 res://assets/<id>.png|glb|mp3，平台会重新导入并更新预览，工具结果里会提示"素材到了"，本轮结束后才到的素材也会自动出现在游戏里。所以代码一开始就要按"有素材用素材、没有用占位"来写：用 ResourceLoader.exists(path) 判断后再 load(path)（不要 preload 素材），没到时用色块/矢量/基础网格占位，同一份尺寸和碰撞。',
  '- sprite 是 1024x1024 透明底、主体居中但四周有留白：用 AtlasTexture 裁到 tex.get_image().get_used_rect() 再按目标尺寸缩放（scale = 目标高度 / 区域高度），碰撞体按游戏尺寸单独设定，不跟图片走。像素风设 texture_filter = TEXTURE_FILTER_NEAREST。texture 用于平铺：draw_texture_rect(tex, rect, true) 或 TextureRect.stretch_mode = STRETCH_TILE；3D 用 StandardMaterial3D.albedo_texture + uv1_triplanar。',
  '- glb 模型：load(path).instantiate() 得到 Node3D，用 AABB 归一化到目标大小。',
  '- 简单的音效也可以用 AudioStreamGenerator 或 AudioStreamWAV 程序合成。',
  '',
  '# 写 .tscn 的要点',
  '- 头部 [gd_scene format=3]；外部资源 [ext_resource type="Script" path="res://main.gd" id="1"]，用 ExtResource("1") 引用；内嵌资源 [sub_resource type="RectangleShape2D" id="s1"]，用 SubResource("s1")。不需要写 uid。',
  '- 节点 [node name="X" type="Label" parent="."]，更深的 parent 写路径如 parent="UI/Top"；属性用 Godot 的序列化写法（Vector2(1, 2)、Color(1, 1, 1, 1)、anchors_preset = 15 + anchor_right = 1.0 + anchor_bottom = 1.0 铺满）。',
  '- 复杂或动态的界面直接在脚本里用代码创建也完全可以；场景文件适合固定结构（关卡、角色、HUD 骨架）。',
  '',
  '# GDScript 常见坑',
  '- 从 Array/Dictionary 取出的值没有类型，用 := 推断会报错：写 var v: int = arr[i] 或 var v = arr[i]；整数除法写 float(a)/b；lambda 里不能给外部局部变量重新赋值（改成成员变量）。',
  '- 背景 ColorRect / TextureRect 要设 mouse_filter = MOUSE_FILTER_IGNORE，否则挡住点击；铺满父节点用 set_anchors_and_offsets_preset(PRESET_FULL_RECT)。',
  '- 节点在 _ready() 里立即创建（不要藏在 await 之后），重要节点起 name，方便 game_eval 用 get_node 找到。',
  '',
  '# 搭建顺序（每一步都让画面有变化）',
  '1. 主场景骨架：背景、主要区域、HUD 都能看到。',
  '2. 数据与规则（纯逻辑脚本）：写完就 run_game + game_eval 直接调用函数验证规则和数值（复刻时和原作数值对照）。',
  '3. 视图、交互和手感：操作、得分、失误都要有动画、音效、粒子或飘字。',
  '4. 像玩家一样把每个关键画面走一遍：run_game 启动后用 game_eval 点按钮 / 按键 / 调用函数推进（开局 → 操作 → 结算 → 下一关 …），带截图看一眼；有运动的游戏用 frames=4 看一段连续画面（判断移动、跳跃、碰撞、动画是否正常）。重叠、出屏、尺寸为 0、文字看不清都要修，布局问题先用 UGC.describe 查实际矩形。',
  '5. 在主场景根节点脚本里写 func auto_test() -> void：用 UGC.click / UGC.press 或直接调用游戏函数真实走一遍核心流程，每步 UGC.check(条件, "说明")，尽量推进到胜利或失败，要有 await，总时长 < 20 秒。run_test 通过后 finish。不要为了通过而削弱 auto_test。',
  '',
  '# 工具要点',
  '- write_file / patch_file 只扫描并保存文件，不代表编译或预览成功。一个可玩片段就绪后 preview_checkpoint 统一检查和构建，返回真实错误；run_game / run_test 也检查最新工程。GDScript 缩进是 Tab，patch 的 old 必须唯一。',
  '- read_file / grep_files / list_files 查看工程，改之前先看清楚，不要凭记忆改。',
  '- run_game：启动当前工程，再用 game_eval 中的 UGC.click / click_at / press / key / hold / drag 执行真实输入，观察状态变化。只截图、只读变量、或直接改分数不算输入试玩。修改源码后，试玩和测试必须重新针对当前版本进行。',
  '- game_eval：在运行中的游戏里执行一段 GDScript，作为 func run(game) 的函数体：game 是主场景根节点，可以 await，return 的值以 JSON 返回；look=true 时附带截图。浏览器模式展示连续实时运行并返回最后截图及实际帧统计，原生备用模式 frames=2-9 可返回多帧拼图（span 秒）。例：',
  '    UGC.click(game.get_node("UI/PlayButton"))',
  '    await UGC.wait(0.8)',
  '    return {"score": game.score, "ui": UGC.describe(game, 2)}',
  '',
  '# 每一轮的收尾',
  '- finish：summary 用 2-4 句中文告诉用户现在能玩什么、怎么玩，如实说明还不行的地方；suggestions 给 2-3 个下一步建议（第一个通常是"继续：<下一个里程碑>"）；milestone_done 写完成的里程碑 id。',
  '- 用户反馈修改时只改需要改的地方，改完同样试玩验证再 finish。做不到的（如联网对战）如实说明并给替代方案，绝不偷偷换成别的游戏类型。',
].join('\n');

// ------------------------------------------------------------------ tools

const GP_DESIGN_TOOL = {
  ...DESIGN_TOOL,
  input_schema: {
    ...DESIGN_TOOL.input_schema,
    properties: {
      ...DESIGN_TOOL.input_schema.properties,
      dimension: { type: 'string', enum: ['2d', '3d'], description: '2D 还是 3D' },
      art: { type: 'array', maxItems: 24, description: '美术位清单：代码里每个 Pencil.sprite / backdrop / material / actor3d 的 id，以及它最终正式美术的样子', items: { type: 'object', required: ['id', 'kind', 'name', 'prompt'], properties: {
        id: { type: 'string', description: '小写英文+下划线，与代码里的美术位 id 一致' }, kind: { type: 'string', enum: ['sprite', 'background', 'texture'], description: 'sprite 角色/道具/图标（含 3D actor3d），background 背景，texture 3D 表面贴图' },
        name: { type: 'string' }, prompt: { type: 'string', description: '单个主体的正式美术外观（英文更佳），风格由 art_bible 统一' } } } },
      assets: { type: 'array', maxItems: 2, description: '可为空；最多 2 个必要新素材，优先复用现有资源或统一完整的矢量/网格美术', items: { type: 'object', required: ['id', 'kind', 'name', 'prompt'], properties: { id: { type: 'string', description: '英文 id，文件名 res://assets/<id>.*' }, kind: { type: 'string', enum: ASSET_KINDS }, name: { type: 'string' }, prompt: { type: 'string', description: '单个主体的外观描述，风格由 art_bible 统一' } } } },
      modules: { type: 'array', items: { type: 'object', required: ['file', 'role', 'owner'], properties: { file: { type: 'string', description: '工程内路径，如 main.tscn / scripts/player.gd / shaders/bg.gdshader' }, owner: { type: 'string', enum: ['scene', 'gameplay'] }, role: { type: 'string' }, interface: { type: 'string' } } } },
    },
  },
};
/** The design tool's asset list follows the round's tier budget. */
function designToolFor(maxAssets) {
  if (maxAssets === GP_DESIGN_TOOL.input_schema.properties.assets.maxItems) return GP_DESIGN_TOOL;
  if (!maxAssets) {
    const { assets, ...properties } = GP_DESIGN_TOOL.input_schema.properties;
    return { ...GP_DESIGN_TOOL, input_schema: { ...GP_DESIGN_TOOL.input_schema, properties } };
  }
  const assets = { ...GP_DESIGN_TOOL.input_schema.properties.assets, maxItems: maxAssets,
    description: '本轮最多 ' + maxAssets + ' 个 AI 素材：主角、敌人或关键道具、地形/贴图、背景、背景音乐与关键音效，风格由 art_bible 统一' };
  return { ...GP_DESIGN_TOOL, input_schema: { ...GP_DESIGN_TOOL.input_schema, properties: { ...GP_DESIGN_TOOL.input_schema.properties, assets } } };
}

const TOOLS = [
  { name: 'project_capabilities', description: '查询当前平台真实开放的 Godot 能力、Web 限制和验收要求；不等同于功能已验证。', input_schema: { type: 'object', properties: {} } },
  GP_DESIGN_TOOL,
  BUILD_SCENE_TOOL,
  DELEGATE_TASKS_TOOL,
  { name: 'preview_checkpoint', description: '一个可玩片段就绪后统一编译并构建当前工程，更新用户预览。写文件只保存，首轮应尽早调用本工具展示实际进展。', input_schema: { type: 'object', properties: { step: { type: 'string' } } } },
  { name: 'resolve_task', description: '亲自修复失败任务后，基于当前版本已通过的编译、测试和打包证据解决该任务。不能跳过验收。', input_schema: { type: 'object', required: ['id', 'resolution'], properties: { id: { type: 'string' }, resolution: { type: 'string' } } } },
  {
    name: 'web_fetch',
    description: '读取一个网页的正文文本（每次最多 12000 字，用 offset 翻页）。用于查已知游戏的规则和数值。',
    input_schema: { type: 'object', required: ['url'], properties: { url: { type: 'string' }, offset: { type: 'number' } } },
  },
  {
    name: 'write_file',
    description: '创建或重写一个文本文件，只安全扫描并保存。一个可玩片段就绪后调用 preview_checkpoint 统一检查构建。',
    input_schema: { type: 'object', required: ['path', 'step', 'content'], properties: {
      path: { type: 'string', description: '工程内路径，如 main.gd / scenes/level.tscn（先写这个字段）' },
      step: { type: 'string', description: '给用户看的进度说明（中文，≤14 字）' },
      content: { type: 'string', description: '完整文件内容' },
    } },
  },
  {
    name: 'patch_file',
    description: '对已有文本文件做精确的小改动：把 old（必须在文件中唯一出现）替换为 new。',
    input_schema: { type: 'object', required: ['path', 'old', 'new'], properties: { path: { type: 'string' }, step: { type: 'string' }, old: { type: 'string' }, new: { type: 'string' } } },
  },
  {
    name: 'read_file',
    description: '读取工程文件（带行号）。',
    input_schema: { type: 'object', required: ['path'], properties: { path: { type: 'string' }, offset: { type: 'number', description: '起始行，默认 1' }, limit: { type: 'number', description: '行数，默认 400' } } },
  },
  {
    name: 'list_files',
    description: '列出工程里的文件（路径和大小，不含平台插件和引擎缓存）。',
    input_schema: { type: 'object', properties: {} },
  },
  {
    name: 'grep_files',
    description: '在工程文本文件里搜索正则（或纯文本），返回 路径:行号: 内容。',
    input_schema: { type: 'object', required: ['pattern'], properties: { pattern: { type: 'string' }, path: { type: 'string', description: '只搜这个文件或目录（可选）' } } },
  },
  {
    name: 'delete_file',
    description: '删除不再需要的文件。',
    input_schema: { type: 'object', required: ['path'], properties: { path: { type: 'string' } } },
  },
  {
    name: 'generate_asset',
    description: '提交一个 AI 素材生成任务（后台 1-3 分钟），完成后出现在 res://assets/<id>.png|glb|mp3。',
    input_schema: { type: 'object', required: ['id', 'kind', 'name', 'prompt'], properties: { id: { type: 'string' }, kind: { type: 'string', enum: ASSET_KINDS }, name: { type: 'string' }, prompt: { type: 'string', description: '画面/声音描述，风格要符合 art_bible' } } },
  },
  {
    name: 'run_game',
    description: '用当前工程启动真实游戏，返回错误、状态和截图。编辑界面会实时旁观同一场试玩，用户自己的操作不受影响。',
    input_schema: { type: 'object', properties: { step: { type: 'string', description: '给用户看的说明（≤14 字）' } } },
  },
  {
    name: 'game_eval',
    description: '在运行中的游戏里执行 GDScript（func run(game) 的函数体，game 是主场景根节点，可 await，return 值以 JSON 返回），用于像玩家一样操作游戏、读取状态、检查布局。look=true 附执行后截图；浏览器连续实时运行，原生备用模式 frames=2-9 可返回多帧拼图。',
    input_schema: { type: 'object', required: ['code'], properties: {
      step: { type: 'string', description: '给用户看的说明（≤14 字），如"跳上第一个平台"' },
      code: { type: 'string' },
      look: { type: 'boolean' },
      settle: { type: 'number', description: '截图前再等几秒，默认 0.3' },
      frames: { type: 'number', description: '多帧拼图的帧数（2-9），默认 1 = 单张截图' },
      span: { type: 'number', description: '多帧拼图覆盖的秒数，默认 1' },
    } },
  },
  {
    name: 'run_test',
    description: '在全新的游戏进程里运行主场景根节点的 auto_test()，返回错误、断言结果、胜负，以及开局和测试结束时的两张截图。',
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
    input_schema: { type: 'object', required: ['summary'], properties: { summary: { type: 'string' }, status: { type: 'string', enum: ['complete', 'partial'] }, suggestions: { type: 'array', items: { type: 'string' } }, milestone_done: { type: 'string' } } },
  },
];
export const GP_TOOL_NAMES = TOOLS.map(t => t.name);
export const GP_FILE_TOOLS = new Set(['write_file', 'patch_file', 'read_file', 'delete_file']);
const PHASE_OF = { build_scene: 'build', design_game: 'design', web_fetch: 'design', write_file: 'build', patch_file: 'build', delete_file: 'build', generate_asset: 'build', delegate_tasks: 'build', preview_checkpoint: 'test', run_game: 'test', game_eval: 'test', run_test: 'test' };
const PHASE_TEXT = { design: '策划师正在设计玩法', build: '正在搭建游戏', test: 'AI 正在试玩自测' };

/** Scene-ish files (scenes, shaders, resources, views) show under C, logic under B. */
export function gpRoleOf(name, input, design) {
  if (name === 'design_game' || name === 'web_fetch' || name === 'generate_asset') return 'A';
  if (!GP_FILE_TOOLS.has(name)) return 'B';
  const f = String(input?.path || '');
  const m = (design?.modules || []).find(x => x.file === f);
  if (m) return m.owner === 'scene' ? 'C' : 'B';
  return /\.(tscn|tres|gdshader|gdshaderinc)$|project\.godot$|(view|hud|ui|scene|fx|render|layout|anim|panel|screen|draw|visual|shader|level|map|world|camera|menu)/i.test(f) ? 'C' : 'B';
}

export const PORTRAIT_3D = '竖屏 3D：每个 Camera3D 设 keep_aspect = Camera3D.KEEP_WIDTH、fov 55–65（此时 fov 是水平视角，否则左右被裁成一条缝）；镜头比横屏更高、更靠后、俯角更大（约 35–55°），主角放在屏幕下方约 1/3，前进方向朝屏幕上方延伸；build_scene 的 camera 也按竖屏取景，关卡沿纵深（-Z）展开而不是横向铺开；HUD 放顶部，摇杆和按钮放底部拇指区。';
const portrait3d = (dimension, orientation) => dimension === '3d' && orientation === 'portrait' ? PORTRAIT_3D : '';

export function gpBrief(d) {
  const ms = d.milestones.map((m, i) => (i < d.current ? '[已完成] ' : i === d.current ? '[本轮目标] ' : '[之后] ') + m.id + ' ' + m.name + '：' + m.goal + '｜验收：' + m.acceptance.join('；')).join('\n');
  return [
    '# 设计方案：' + d.title + '（' + d.genre + '，' + (d.dimension === '3d' ? '3D' : '2D') + '）', d.pitch,
    '屏幕：' + screenOf(d.orientation).cn + '。',
    portrait3d(d.dimension, d.orientation),
    d.faithful ? '复刻：' + d.closest_game + '（规则、数值、流程和界面都贴近原作）' : '最接近：' + d.closest_game + (d.differences.length ? '；不同之处：' + d.differences.join('；') : ''),
    '核心循环：' + d.core_loop,
    '规则：\n- ' + d.rules.join('\n- '),
    '布局：' + d.layout,
    '操作：' + d.controls.map(c => c.join('=')).join('，'),
    '文件规划：\n' + d.modules.map(m => '- ' + m.file + '：' + m.role + (m.interface ? '｜接口：' + m.interface : '')).join('\n'),
    '调色板：' + d.palette.join(' ') + '；正式美术方向：' + d.art_bible,
    d.art?.length ? '美术位（Pencil 工具包 id）：' + d.art.map(a => a.id + '=' + (a.name || a.kind)).join('，') : '',
    '里程碑：\n' + ms,
    'M1 搭建步骤：' + d.build_steps.join(' → '),
  ].filter(Boolean).join('\n');
}

// ------------------------------------------------------------------ session

/** Tool executor for one turn. hooks: emit, pushPck(build, label, agent), onDesign, aiPlay,
 *  mirrorEval, requestAsset(a) -> error string | '', assets() -> {id: {state, kind, ...}}, signal. */
export class ProjectSession extends CodeSession {
  constructor(game, project, hooks, opts = {}) {
    super(game, hooks, opts);
    this.project = project;
    this.changed = new Set();
    this.notes = [];
    this.workflow = opts.workflow || createWorkflow({ goal: '', sourceRevision: project.revision() });
    this.artifactDir = opts.artifactDir;
    this.runWorker = opts.runWorker;
    this.model = opts.model ?? CODE_MODEL;
    this.liveRevision = '';
    this.playStartedRevision = '';
    this.abortRun = opts.abortRun;
    this.fetchImpl = opts.fetchImpl || fetch;
    this.closed = false;
    this.assetRequests = 0;
    this.delegateBatches = 0;
    this.pendingBatches = new Set();
    this.previewFailures = 0;
    this.toolTimeoutMs = opts.toolTimeoutMs;
    this.requireVisibleConstruction = !!opts.requireVisibleConstruction;
    this.assetKinds = Array.isArray(opts.assetKinds) ? opts.assetKinds.filter(k => ASSET_KINDS.includes(k)) : opts.pencilOnly ? [] : ASSET_KINDS;
    this.activeWatchId = '';
    this.browserPlaytest = opts.browserPlaytest || null;
    this.liveMode = '';
    this.browserRequired = false;
    // Set once a browser command fails in transport (hidden tab, timeout, disconnect); the rest of
    // the round verifies in the native window instead of retrying a flapping client.
    this.browserLost = '';
    this.onWatchFrame = frame => {
      if (this.activeWatchId && !this.closed && !this.signal?.aborted) this.hooks.watchFrame?.(this.activeWatchId, frame);
    };
  }
  get files() { return this.project.sources(); }
  get orientation() { return this.game.meta.orientation === 'portrait' ? 'portrait' : 'landscape'; }

  async exec(name, input, _agent, id = '') {
    if (this.closed || this.finish || this.signal?.aborted) return { error: '本轮已停止，当前成果已保存' };
    const f = this['t_' + name];
    if (!f || !GP_TOOL_NAMES.includes(name)) return { error: '未知工具 ' + name };
    input = input || {};
    const threeD = this.game.design?.dimension === '3d' || this.game.meta?.dimension === '3d';
    if (this.requireVisibleConstruction && threeD && ((this.game.construction?.revision || 0) < 2 || !this.game.construction?.objects?.length) && ['write_file', 'patch_file', 'delegate_tasks'].includes(name)) return { error: '先用 build_scene 分两小批搭出实际可见关卡（地面，再地标/障碍），再写玩法代码。每批1–8个真实物体，用户需要看到过程。', constructionRevision: this.game.construction?.revision || 0 };
    this.role = gpRoleOf(name, input, this.game.design);
    const ph = PHASE_OF[name];
    if (ph && ph !== this.phase) { this.phase = ph; this.hooks.emit({ type: 'phase', phase: ph, text: PHASE_TEXT[ph], agents: [this.role] }); }
    const iteration = this.workflow.iteration;
    const wrapping = iteration && Date.now() >= iteration.wrapAt;
    if (wrapping && ['delegate_tasks', 'generate_asset', 'design_game', 'web_fetch'].includes(name)) return { error: '本轮已进入收口，只修阻塞问题、试玩和测试，其余留到下一轮。' };
    if (this.overHard() && name !== 'finish') return { error: '本轮时间已用完，请保存现状并结束。' };
    if (iteration) {
      updateIteration(iteration, { phase: name === 'finish' ? 'review' : wrapping ? 'verify' : ph === 'design' ? 'scope' : ph === 'test' ? 'verify' : 'build' });
      this.checkpoint();
    }
    const timeout = this.toolTimeoutMs || ({ delegate_tasks: this.limits.delegationMs + 5000, run_test: 90000, run_game: 90000, preview_checkpoint: 90000, game_eval: 45000, web_fetch: 16000 }[name] || 30000);
    let timer = null;
    const arm = () => { if (this.abortRun && !timer) timer = setTimeout(() => this.abortRun(iterationError('本轮工具执行超时：' + name + '，当前成果已保存', 'ITERATION_TOOL_TIMEOUT')), timeout); };
    let r;
    try {
      // Waiting for the project lock (asset imports run full Godot builds) must not count against the tool's own timeout.
      const call = () => { this.assertActive(); arm(); return f.call(this, input, this.role, id); };
      r = await abortable(['build_scene', 'write_file', 'patch_file', 'delete_file', 'preview_checkpoint', 'run_game', 'game_eval', 'run_test', 'finish', 'resolve_task'].includes(name) ? this.project.withLock(call) : call(), this.signal);
    } catch (e) {
      this.endWatch({ status: this.signal?.aborted ? 'stopped' : 'failed', errors: [String(e.message || e)] });
      r = { error: String(e.message || e).slice(0, 400) };
    }
    finally { clearTimeout(timer); }
    if (this.notes.length) {
      const note = this.notes.splice(0).join('\n');
      r = Array.isArray(r?.__blocks) ? { __blocks: [{ type: 'text', text: note }, ...r.__blocks] } : { ...r, platform_note: note };
    }
    return this.withBudget(r);
  }

  get browserUsable() { return !this.browserLost && !!this.browserPlaytest?.available; }
  loseBrowser(error) {
    this.browserPlaytest?.stop();
    this.browserLost = '验收浏览器不可用（' + String(error?.message || error).slice(0, 60) + '），本轮改用原生窗口试玩与验收';
    this.liveMode = 'native'; this.browserRequired = false; this.liveRevision = '';
    return this.browserLost;
  }

  /** Called by the server when a generated asset lands in the project. */
  note(text) { this.notes.push(text); }

  assertActive() { throwIfAborted(this.signal); if (this.closed) throw iterationError('本轮已结束', 'ITERATION_CLOSED'); }
  overHard(graceMs = 0) { return this.workflow?.iteration ? Date.now() >= this.workflow.iteration.deadlineAt : super.overHard(graceMs); }
  get limits() { return tierLimits(this.workflow?.iteration?.tier); }
  withBudget(r) {
    const it = this.workflow?.iteration;
    if (!it || Date.now() < it.wrapAt || this.finish) return super.withBudget(r);
    const note = '进入收口：剩余最多 ' + Math.ceil(remainingMs(it) / 1000) + ' 秒。只修阻塞问题，进行真实输入试玩和有效断言测试，再如实 finish；未完成写入 suggestions。';
    return Array.isArray(r?.__blocks) ? { __blocks: [{ type: 'text', text: note }, ...r.__blocks] } : { ...r, time_note: note };
  }
  checkpoint() { this.workflow.sourceRevision = this.project.revision(); this.hooks.workflow?.(this.workflow); }
  async t_project_capabilities() { return GODOT_CAPABILITIES; }
  evidence(item) { this.assertActive(); const result = recordEvidence(this.workflow, item); this.checkpoint(); return result; }
  beginWatch(kind, step) {
    this.endWatch({ status: 'stopped' });
    this.activeWatchId = this.hooks.watchStart?.({ runId: this.workflow.id, sourceRevision: this.project.revision(), kind, step }) || '';
  }
  endWatch(result = { status: 'stopped' }) {
    const id = this.activeWatchId; this.activeWatchId = '';
    if (id) this.hooks.watchEnd?.(id, result);
  }

  savePartial(reason, { budgetExpired = false, cancelled = false } = {}) {
    this.endWatch({ status: 'stopped' });
    if (this.finish && !this.signal?.aborted) return;
    const next = this.workflow.iteration?.nextSteps?.length ? this.workflow.iteration.nextSteps : ['继续完成当前核心体验，并验证操作、失败与重开'];
    updateIteration(this.workflow.iteration, { phase: 'paused', reason, nextSteps: next });
    Object.assign(this.workflow, { status: cancelled ? 'cancelled' : 'partial', completionRequested: false, pendingMilestone: '', sourceRevision: this.project.revision(), issues: [...new Set([reason, ...acceptanceFor(this.workflow, this.project.revision()).issues])] });
    this.finish = { status: this.workflow.status, summary: reason + '。已保存本轮文件和任务记录，未通过的内容保留到下一轮。', suggestions: next, milestone_done: '', budgetExpired };
    this.closed = true; this.checkpoint();
  }

  async t_delegate_tasks({ tasks }) {
    if (tasks?.some(t => t.files?.some(p => isConstructionFile(p)))) return { error: '场景管理文件不能委派改写，请用 build_scene 更新真实关卡。' };
    const it = this.workflow.iteration;
    if (this.delegateBatches >= this.limits.delegateBatches) return { error: '本轮委派次数已用完，请整合现有成果或保存下一步。' };
    const budget = it ? delegationBudget(it) : this.limits.delegationMs;
    if (budget < 15000) return { error: '剩余时间不足以委派并完成整体验收，请直接收口。' };
    this.delegateBatches++;
    const pending = runTaskBatch({
      project: this.project, game: this.game, tasks, signal: this.signal, model: this.model,
      timeoutMs: budget, deadlineAt: it ? Math.min(it.wrapAt, it.deadlineAt - 60000) : Date.now() + budget,
      artifactDir: this.artifactDir, runWorker: this.runWorker,
      onTask: task => {
        const current = upsertTask(this.workflow, task);
        this.hooks.emit({ type: 'task', runId: this.workflow.id, task: current });
        this.checkpoint();
      },
    });
    this.pendingBatches.add(pending);
    let result;
    try { result = await pending; } finally { this.pendingBatches.delete(pending); }
    this.assertActive();
    for (const file of result.changed || []) this.changed.add(file);
    return { ...result, verification: null, note: '已合入部分只完成安全扫描；用 preview_checkpoint / run_game 统一编译预览，再进行当前版本玩法测试。失败任务保留候选，独立成功任务无需重做。' };
  }

  async t_resolve_task({ id, resolution }) {
    const task = this.workflow.tasks.find(t => t.id === id);
    if (!task) return { error: '没有这个任务' };
    if (!String(resolution || '').trim()) return { error: '需要说明修复方式及验证依据' };
    const revision = this.project.revision();
    const accepted = acceptanceFor(this.workflow, revision, { ignoreTasks: true });
    if (!accepted.ok) return { error: '修复还没有通过当前版本验收', issues: accepted.issues };
    const current = upsertTask(this.workflow, { id, status: 'applied', verified: false, resolution: String(resolution).slice(0, 1200), summary: String(resolution).slice(0, 800), error: '', resolvedRevision: revision });
    this.hooks.emit({ type: 'task', runId: this.workflow.id, task: current }); this.checkpoint();
    return { ok: true, note: '修复已核验，等待整体验收和预览确认。' };
  }

  async t_finish(input) {
    const revision = this.project.revision();
    const accepted = acceptanceFor(this.workflow, revision);
    const assets = Object.values(this.hooks.assets?.() || {});
    const unavailable = assetsInUse(assets, this.project.sources?.(f => !f.startsWith('assets/'))).filter(assetBlocks);
    const issues = [...accepted.issues, ...unavailable.map(a => '素材尚未就绪：' + (a.name || a.id || a.kind))];
    const partial = input.status === 'partial' || this.overHard() || this.testRuns >= this.limits.tests && issues.length > 0;
    if (!partial && issues.length) return { error: '还不能标记完成，请处理以下验收项；暂时无法完成时用 status=partial 收尾。', issues };
    this.workflow.completionRequested = !partial;
    this.workflow.pendingMilestone = partial ? '' : String(input.milestone_done || '');
    if (partial) {
      this.workflow.status = 'partial'; this.workflow.issues = issues.length ? issues : ['本轮尚有未完成内容，请继续制作'];
      this.workflow.sourceRevision = revision;
    } else settleWorkflow(this.workflow, revision);
    const summary = String(input.summary || '').slice(0, 3000);
    this.finish = {
      status: this.workflow.status,
      summary: (partial ? '本轮已保存，仍有待完成内容。' : this.workflow.status === 'ready' ? '当前版本已通过本地测试，等待浏览器预览确认。' : '') + summary,
      suggestions: (Array.isArray(input.suggestions) ? input.suggestions : []).slice(0, 3).map(s => String(s).slice(0, 100)),
      milestone_done: this.workflow.status === 'completed' ? this.workflow.pendingMilestone : '',
    };
    updateIteration(this.workflow.iteration, { phase: partial ? 'paused' : 'review', nextSteps: this.finish.suggestions, ...(partial ? { reason: this.workflow.issues[0] } : {}) });
    this.checkpoint();
    return { ok: true, status: this.workflow.status, issues: this.workflow.issues };
  }

  async t_design_game(input) {
    if (this.game.design) return { error: '方案已经存在。要调整后续路线用 update_plan。' };
    const plan = normalizePlan({ ...input, assets: [] });
    plan.orientation = this.orientation;
    plan.dimension = input.dimension === '3d' || this.game.meta.dimension === '3d' ? '3d' : '2d';
    plan.assets = [];
    plan.art = artSlotsOf(input.art);
    this.game.design = plan;
    this.hooks.onDesign?.(plan);
    const notes = [];
    const cap = this.assetKinds.length ? this.limits.assets : 0;
    for (const a of (Array.isArray(input.assets) ? input.assets : []).filter(a => this.assetKinds.includes(a?.kind)).slice(0, cap)) {
      const err = this.hooks.requestAsset?.(a, { signal: this.signal, deadlineAt: this.workflow.iteration?.wrapAt });
      if (err) notes.push(err); else plan.assets.push({ id: a.id, kind: a.kind, name: a.name });
      if (!err) this.assetRequests++;
    }
    if (input.assets?.length > plan.assets.length) notes.push(cap ? '本轮只安排用户要求的素材（' + this.assetKinds.join(' / ') + '），最多 ' + cap + ' 个；其他留到下一轮。' : '用户没有要求生成素材：全部用铅笔美术位画，保持手绘风。');
    return { ok: true, art: plan.art.map(a => a.id), assets: plan.assets.map(a => a.id + ' → res://' + assetPath(a) + '（生成中）'), notes, note: '方案已展示。用 Pencil 工具包按 art 里的美术位 id 画出全部画面，先做一个可玩片段并 preview_checkpoint。' };
  }

  async t_generate_asset(a) {
    if (!this.assetKinds.length) return { error: '用户没有要求生成素材：保持铅笔手绘风，用 Pencil 工具包的美术位画出来。需要素材时由用户提出。' };
    if (!ASSET_KINDS.includes(a.kind)) return { error: 'kind 只能是 ' + ASSET_KINDS.join(' / ') };
    if (!this.assetKinds.includes(a.kind)) return { error: '用户本轮只要求了 ' + this.assetKinds.join(' / ') + ' 类素材，不能生成 ' + a.kind + '，画面保持铅笔手绘风。' };
    if ((this.game.design?.art || []).some(s => s.id === a.id) && ['sprite', 'background', 'texture'].includes(a.kind)) return { error: a.id + ' 是美术位，正式美术由美术子代理异步生成并自动替换，无需申请。' };
    if (this.assetRequests >= this.limits.assets) return { error: '本轮最多新增 ' + this.limits.assets + ' 个素材，请复用现有资源并留出试玩时间。' };
    if (this.workflow.iteration && delegationBudget(this.workflow.iteration) < 90000) return { error: '剩余制作时间不足，素材升级留到下一轮。' };
    const err = this.hooks.requestAsset?.(a, { signal: this.signal, deadlineAt: this.workflow.iteration?.wrapAt });
    if (err) return { error: err };
    this.assetRequests++;
    return { ok: true, path: 'res://' + assetPath(a), note: '已提交，生成好后会提示。先用占位继续开发。' };
  }

  async t_build_scene(input) {
    if (this.game.design?.dimension !== '3d' && this.game.meta?.dimension !== '3d') return { error: 'build_scene 目前用于3D关卡，2D仍用现有制作工具。' };
    this.assertActive();
    const previous = this.game.construction || null;
    const snapshot = applyConstruction(previous, input, { runId: this.workflow.id });
    const files = commitConstruction(this.project, snapshot, { scaffold: this.requireVisibleConstruction && !previous });
    this.game.construction = snapshot;
    for (const file of files) this.changed.add(file);
    this.hooks.emit({ type: 'construction', runId: this.workflow.id, snapshot, sourceRevision: this.project.revision() });
    this.checkpoint();
    return { ok: true, saved: true, revision: snapshot.revision, objects: snapshot.objects.map(o => ({ id: o.id, label: o.label })), files,
      note: '本批真实关卡已保存并发送到搭建现场；尚不代表玩法验收。继续分小批搭建，保留main.tscn的Construction实例，随后编写Node3D玩法并preview_checkpoint。' };
  }

  async t_write_file({ path: p, step, content }, agent = 'B', id = '') {
    const rel = String(p || '').trim().replace(/^res:\/\//, '');
    if (isConstructionFile(rel)) return { error: '这是实际搭建关卡的管理文件，请用 build_scene 修改。' };
    const prev = this.project.read(rel);
    const issues = this.project.write(rel, content);
    if (issues.length) return { error: '没有写入：\n' + issues.slice(0, 12).join('\n') };
    const code = this.project.read(rel);
    this.changed.add(rel);
    this.hooks.emit({ type: 'code_write', id, agent, sourceRevision: this.project.revision(), file: rel, step: String(step || ''), lines: code.split('\n').length, code, created: prev == null });
    this.checkpoint();
    return { ok: true, saved: true, verified: false, sourceRevision: this.project.revision(), note: '文件已扫描并保存。可玩片段就绪后 preview_checkpoint 统一编译预览；保存不代表验收通过。' };
  }

  async t_patch_file({ path: p, old, new: nw, step }, agent = 'B', id = '') {
    const rel = String(p || '').trim().replace(/^res:\/\//, '');
    if (isConstructionFile(rel)) return { error: '这是实际搭建关卡的管理文件，请用 build_scene 修改。' };
    const src = this.project.read(rel);
    if (src == null) return { error: '没有这个文件：' + rel + '。用 list_files 看看有哪些。' };
    if (typeof src !== 'string') return { error: rel + ' 不是文本文件' };
    old = String(old ?? '').replace(/\r\n/g, '\n');
    const n = old ? src.split(old).length - 1 : 0;
    if (n !== 1) return { error: n === 0 ? 'old 文本在 ' + rel + ' 中找不到（注意缩进是 Tab），先用 read_file 看准再改' : 'old 文本出现了 ' + n + ' 次，请包含更多上下文让它唯一' };
    const code = src.replace(old, () => String(nw ?? '').replace(/\r\n/g, '\n'));
    const issues = this.project.write(rel, code);
    if (issues.length) return { error: '修改没有应用：\n' + issues.slice(0, 12).join('\n') };
    this.changed.add(rel);
    this.hooks.emit({ type: 'code_write', id, agent, sourceRevision: this.project.revision(), file: rel, step: String(step || '修正 ' + rel), lines: code.split('\n').length, code, patch: true });
    this.checkpoint();
    return { ok: true, saved: true, verified: false, sourceRevision: this.project.revision(), note: '修改已保存，需统一编译、试玩和测试当前版本。' };
  }

  async t_read_file({ path: p, offset = 1, limit = 400 }) {
    const rel = String(p || '').trim().replace(/^res:\/\//, '');
    const src = rel.startsWith('addons/ugc/') ? null : this.project.read(rel);
    if (src == null) return { error: '没有这个文件：' + rel + '。用 list_files 看看有哪些。' };
    if (typeof src !== 'string') return { file: rel, binary: true, size: src.size };
    const lines = src.split('\n');
    const from = Math.max(1, Math.floor(Number(offset) || 1));
    const n = Math.min(800, Math.max(1, Math.floor(Number(limit) || 400)));
    return { file: rel, total_lines: lines.length, from, text: numbered(lines.slice(from - 1, from - 1 + n).join('\n'), from) };
  }

  async t_list_files() {
    const assets = this.hooks.assets?.() || {};
    return {
      files: this.project.list().map(f => f.path + ' (' + (f.size < 1024 ? f.size + 'B' : Math.round(f.size / 1024) + 'KB') + ')').join('\n'),
      assets_pending: Object.values(assets).filter(a => a.state === 'pending').map(a => a.id + '（' + a.kind + '）'),
    };
  }

  async t_grep_files({ pattern, path: under }) {
    let re;
    try { re = new RegExp(String(pattern || ''), 'i'); } catch { re = new RegExp(String(pattern || '').replace(/[.*+?^${}()|[\]\\]/g, '\\$&'), 'i'); }
    const pre = String(under || '').replace(/^res:\/\//, '');
    const out = [];
    for (const [f, src] of Object.entries(this.project.sources(p => !pre || p === pre || p.startsWith(pre.replace(/\/?$/, '/'))))) {
      src.split('\n').forEach((l, i) => { if (out.length < 80 && re.test(l)) out.push(f + ':' + (i + 1) + ': ' + l.trim().slice(0, 160)); });
    }
    return { matches: out.length, results: out.join('\n') || '（没有匹配）' };
  }

  async t_delete_file({ path: p }) {
    const rel = String(p || '').trim().replace(/^res:\/\//, '');
    if (isConstructionFile(rel)) return { error: '不能移除真实关卡文件；用build_scene按ID更新或移除对象。' };
    if (!this.project.remove(rel)) return { error: '没有这个文件或不能删除：' + rel };
    this.changed.add(rel);
    this.checkpoint();
    return { ok: true, saved: true, verified: false, sourceRevision: this.project.revision() };
  }

  async t_preview_checkpoint({ step } = {}, agent = 'B') { return this.tryLoad(step || '可玩片段预览', agent); }

  async t_web_fetch({ url, offset = 0 }) {
    if (this.fetches >= this.limits.fetches) return { error: '本轮资料查询最多 ' + this.limits.fetches + ' 次，请根据已有证据继续制作。' };
    let u;
    try { u = new URL(String(url || '')); } catch { return { error: '不是有效的网址' }; }
    if (!/^https?:$/.test(u.protocol) || /^(localhost|127\.|10\.|192\.168\.|172\.(1[6-9]|2\d|3[01])\.|169\.254\.|0\.|\[?::1\]?$)/i.test(u.hostname)) return { error: '只能访问公网 http(s) 网页' };
    this.fetches++;
    const signal = this.signal ? AbortSignal.any([this.signal, AbortSignal.timeout(15000)]) : AbortSignal.timeout(15000);
    try {
      const response = await this.fetchImpl(u, { signal, headers: { accept: 'text/html,text/plain' } });
      throwIfAborted(signal);
      if (!response.ok) return { error: '网页返回 HTTP ' + response.status };
      const text = webText((await response.text()).slice(0, 3e6));
      throwIfAborted(signal);
      const at = Math.max(0, Number(offset) || 0);
      return { url: u.href, total: text.length, text: text.slice(at, at + 12000), offset: at, more: at + 12000 < text.length };
    } catch (error) { return { error: '读取失败：' + String(error.message || error).slice(0, 160) }; }
  }

  /** Expensive verification is shared by explicit playable checkpoints, not individual writes. */
  async tryLoad(label, agent = 'B') {
    this.assertActive();
    if (this.previewFailures >= this.limits.previewFailures) return { error: '本轮工程启动已失败 ' + this.limits.previewFailures + ' 次，请保存错误和下一步，避免继续循环构建。' };
    const revision = this.project.revision();
    const compile = this.workflow.evidence.findLast(e => e.kind === 'compile' && e.sourceRevision === revision);
    const latest = this.project.latestBuild;
    if (compile?.ok && latest?.sourceRevision === revision) return { ok: true, saved: true, loaded: true, sourceRevision: revision, buildId: latest.buildId, cached: true };
    const c = await this.project.check({ signal: this.signal });
    this.assertActive();
    const errors = (c.errors || []).filter(e => e.kind !== 'warning');
    this.evidence({ kind: 'compile', sourceRevision: c.sourceRevision, ok: c.loaded && !errors.length && c.ok !== false, errors });
    if (c.loaded && !errors.length && c.ok !== false) {
      const b = latest?.sourceRevision === c.sourceRevision ? { ...latest, ok: true } : await this.project.build({ signal: this.signal, sourceRevision: c.sourceRevision });
      this.assertActive();
      this.evidence({ kind: 'build', sourceRevision: b.sourceRevision || c.sourceRevision, ok: b.ok, buildId: b.buildId, contentHash: b.contentHash, version: b.version, errors: b.ok ? [] : [b.error] });
      if (!b.ok) this.previewFailures++;
      if (b.ok) this.hooks.pushPck?.(b, label, agent);
      return { ok: b.ok, saved: true, loaded: true, sourceRevision: c.sourceRevision, note: b.ok ? '检查通过，已向预览发送新版本；仍需玩法测试与浏览器确认。' : '检查通过，但预览打包失败：' + b.error };
    }
    this.previewFailures++;
    return { ok: false, saved: true, loaded: !!c.loaded, sourceRevision: c.sourceRevision, note: '文件已保存，但工程现在不能干净运行（如果是因为还有文件没写，可以先继续写）：', errors: errors.slice(0, 12) };
  }

  async t_run_game({ step }, agent = 'B', id = '') {
    this.live?.stop?.();
    this.browserPlaytest?.stop();
    this.browserRequired = this.browserUsable;
    this.liveMode = this.browserRequired ? 'browser' : 'native';
    if (this.liveMode === 'native') this.beginWatch('run', step || '没有可用浏览器，使用原生游戏检查开局');
    else this.endWatch();
    const verification = await this.tryLoad(step || '可玩片段预览', agent);
    this.assertActive();
    if (!verification.ok) { this.endWatch({ status: 'failed', errors: verification.errors || [verification.note || verification.error] }); return verification; }
    const start = runtime => runtime.startProject(this.project, this.orientation, { signal: this.signal, onFrame: this.onWatchFrame, runId: this.workflow.id, step: step || '启动游戏，检查开局画面' });
    let r, fallback = '';
    if (this.liveMode === 'native') r = await start(this.liveGame());
    else {
      try { r = await start(this.browserPlaytest); }
      catch (error) {
        this.assertActive();
        fallback = this.loseBrowser(error);
        this.beginWatch('run', step || '浏览器不可用，改用原生窗口检查开局');
        r = await start(this.liveGame());
      }
    }
    this.assertActive();
    this.liveRevision = this.project.revision();
    const errors = r.errors.filter(e => e.kind !== 'warning');
    this.playStartedRevision = r.loaded && !errors.length && r.ok !== false ? this.liveRevision : '';
    this.endWatch({ status: r.loaded && !errors.length && r.ok !== false ? 'passed' : 'failed', errors });
    if (r.loaded) this.hooks.aiPlay?.();
    this.hooks.emit({ type: 'eval', id, agent, kind: 'run', mode: this.liveMode, metrics: r.metrics, step: String(step || '启动游戏'), ok: r.loaded && !errors.length && r.ok !== false, errors: errors.slice(0, 6), shot: r.image || '' });
    const summary = { ok: r.loaded && !errors.length && r.ok !== false, mode: this.liveMode, ...(fallback ? { fallback } : {}), loaded: r.loaded, errors: errors.slice(0, 15), state: r.state, metrics: r.metrics, hint: r.loaded && r.ok !== false ? (this.liveMode === 'browser' ? '当前不可变版本正在可见浏览器中运行，用 game_eval 在同一实例操作。' : '没有可用浏览器，本次为原生运行；用 game_eval 操作和检查。') : '游戏没能启动，修复错误后再 run_game。' };
    return this.withShot(summary, r.image, '开局截图：');
  }

  async t_game_eval({ code, look = true, settle = 0.3, step, frames = 1, span = 1 }, agent = 'B', id = '') {
    code = String(code || '').replace(/\r\n/g, '\n');
    const issues = scanIssues('eval.gd', code);
    if (issues.length) return { error: issues.join('\n') };
    // A browser that left (tab hidden or closed) hands live play back to the native window.
    if (!this.liveMode || this.liveMode === 'browser' && !this.browserUsable) {
      if (this.liveMode === 'browser') this.loseBrowser('浏览器已离开');
      this.browserRequired = this.browserUsable; this.liveMode = this.browserRequired ? 'browser' : 'native';
    }
    const nf = Math.min(9, Math.max(1, Math.floor(Number(frames) || 1)));
    const attempt = async () => {
      const live = this.liveMode === 'browser' ? this.browserPlaytest : this.liveGame();
      if (!live.running || this.liveRevision !== this.project.revision()) live.stop?.();
      if (this.liveMode === 'native') this.beginWatch('eval', step || '原生操作游戏，检查实际表现');
      else this.endWatch();
      if (!live.running || this.liveRevision !== this.project.revision()) {
        if (this.liveMode === 'browser') {
          const verified = await this.tryLoad(step || '浏览器实际操作', agent);
          this.assertActive();
          if (!verified.ok) return { verified };
        }
        const s = await live.startProject(this.project, this.orientation, { signal: this.signal, onFrame: this.onWatchFrame, runId: this.workflow.id, step: step || '启动本步实际操作' });
        this.assertActive();
        if (!s.loaded || s.ok === false) { this.endWatch({ status: 'failed', errors: s.errors }); return { verified: { mode: this.liveMode, error: '游戏启动失败，先修复：', errors: s.errors.slice(0, 12) } }; }
        this.hooks.aiPlay?.();
        // A fresh start of the current revision is what run_game proves; after a transport
        // fallback it counts as the start of real input play.
        if (this.liveRevision === '' && this.browserLost) this.playStartedRevision = this.project.revision();
        this.liveRevision = this.project.revision();
      }
      return { r: await live.eval(code, { signal: this.signal, shot: look !== false, settle: Math.min(5, Math.max(0, Number(settle) || 0.3)), frames: nf, span: Math.min(6, Math.max(0.2, Number(span) || 1)), step: step || '操作游戏，检查实际表现' }) };
    };
    let out, fallback = '';
    if (this.liveMode === 'native') out = await attempt();
    else {
      try { out = await attempt(); }
      catch (error) { this.assertActive(); fallback = this.loseBrowser(error); out = await attempt(); }
    }
    if (out.verified) return out.verified;
    const r = out.r;
    this.assertActive();
    const errors = (r.errors || []).filter(e => e.kind !== 'warning');
    if (this.playStartedRevision === this.project.revision() && /\bUGC\s*\.\s*(?:click|click_at|press|key|hold|drag)\s*\(/.test(code)) {
      this.evidence({ kind: 'play', sourceRevision: this.liveRevision, ok: r.ok && !errors.length, errors, summary: String(step || '真实输入试玩') });
    }
    this.endWatch({ status: r.ok && !errors.length ? 'passed' : 'failed', errors });
    this.hooks.emit({ type: 'eval', id, agent, kind: 'eval', mode: this.liveMode, metrics: r.metrics, step: String(step || ''), ok: r.ok && !errors.length, errors: errors.slice(0, 6), value: JSON.stringify(r.value ?? null).slice(0, 300), shot: r.image || '' });
    let value = JSON.stringify(r.value ?? null);
    if (value.length > 6000) value = value.slice(0, 6000) + ' …（已截断）';
    const summary = { ok: r.ok && !errors.length, mode: this.liveMode, ...(fallback ? { fallback } : {}), value, checks: r.checks || [], errors: errors.slice(0, 12), state: r.state, metrics: r.metrics };
    return this.withShot(summary, r.image, this.liveMode === 'browser' ? '执行后的实时游戏画面：' : nf > 1 ? '多帧拼图（从左到右、从上到下按时间顺序）：' : '执行后的画面：');
  }

  async t_run_test({ look = true }, agent = 'B', id = '') {
    if (this.testRuns >= this.limits.tests) return { error: '本轮测试次数已用完，请如实总结现状并 finish' };
    this.testRuns++;
    this.live?.stop?.();
    this.browserPlaytest?.stop();
    this.browserRequired = this.browserUsable;
    let browserTest = this.browserRequired, fallback = '';
    let executionMode = browserTest ? 'browser' : 'native';
    if (browserTest) this.endWatch();
    else this.beginWatch('test', '没有可用浏览器，原生逐项检查玩法、失败与重开');
    this.hooks.emit({ type: 'test_start', agent, run: this.testRuns, mode: executionMode });
    // A follow-up can be verification-only. It must still acquire current compile/build evidence,
    // rather than depending on write_file having happened earlier in this conversation.
    const compile = await this.project.check({ signal: this.signal });
    this.assertActive();
    const compiled = compile.ok !== false && compile.loaded && !(compile.errors || []).some(e => e.kind !== 'warning');
    this.evidence({ kind: 'compile', sourceRevision: compile.sourceRevision, ok: compiled, errors: compile.errors });
    let browserBuild;
    if (compiled && browserTest) {
      const latest = this.project.latestBuild;
      browserBuild = latest?.sourceRevision === compile.sourceRevision ? { ...latest, ok: true } : await this.project.build({ signal: this.signal, sourceRevision: compile.sourceRevision });
      this.assertActive();
      this.evidence({ kind: 'build', sourceRevision: browserBuild.sourceRevision || compile.sourceRevision, ok: browserBuild.ok, buildId: browserBuild.buildId, contentHash: browserBuild.contentHash, version: browserBuild.version, errors: browserBuild.ok ? [] : [browserBuild.error] });
      if (!browserBuild.ok) throw new Error(browserBuild.error || '浏览器测试的当前构建失败');
      this.hooks.pushPck?.(browserBuild, '浏览器规则检查', agent);
    }
    const native = () => this.project.selfTest({ orientation: this.orientation, shot: look !== false, signal: this.signal, sourceRevision: compile.sourceRevision, onFrame: this.onWatchFrame });
    let r;
    if (!compiled) r = { ok: false, loaded: false, has_test: false, sourceRevision: compile.sourceRevision, checks: [], errors: compile.errors || [] };
    else if (!browserTest) r = await native();
    else {
      try { r = await this.browserPlaytest.selfTest(this.project, { orientation: this.orientation, shot: look !== false, signal: this.signal, sourceRevision: compile.sourceRevision, runId: this.workflow.id }); }
      catch (error) {
        this.assertActive();
        // Transport failure (hidden tab, timeout, disconnect): the same revision is verified natively.
        fallback = this.loseBrowser(error);
        browserTest = false; executionMode = 'native';
        this.beginWatch('test', '浏览器已离开，改用原生窗口逐项检查');
        r = await native();
      }
    }
    this.assertActive();
    this.lastTest = r;
    const errors = r.errors.filter(e => e.kind !== 'warning');
    const checks = r.checks || [];
    r.ok = r.ok && checks.length > 0 && checks.every(c => c.ok) && !errors.length;
    this.endWatch({ status: r.ok ? 'passed' : 'failed', errors, checks });
    this.evidence({ kind: 'test', sourceRevision: r.sourceRevision, ok: r.ok, checks, errors });
    let previewBuild = null;
    if (r.ok) {
      const latest = this.project.latestBuild;
      const b = browserBuild || (latest?.sourceRevision === r.sourceRevision ? { ...latest, ok: true } : await this.project.build({ signal: this.signal, sourceRevision: r.sourceRevision }));
      this.assertActive();
      this.evidence({ kind: 'build', sourceRevision: b.sourceRevision || r.sourceRevision, ok: b.ok, buildId: b.buildId, contentHash: b.contentHash, version: b.version, errors: b.ok ? [] : [b.error] });
      previewBuild = { ok: b.ok, buildId: b.buildId, error: b.error };
      if (b.ok && !browserTest) this.hooks.pushPck?.(b, '玩法测试通过', agent);
    }
    this.hooks.emit({ type: 'test', id, agent, mode: executionMode, metrics: r.metrics, sourceRevision: r.sourceRevision, shot: r.image_end || r.image || '', run: this.testRuns, ok: r.ok, loaded: r.loaded, has_test: r.has_test, result: r.result, errors: errors.slice(0, 8), checks: checks.slice(0, 20), ms: r.ms });
    const summary = {
      ok: r.ok && previewBuild?.ok !== false, mode: executionMode, ...(fallback ? { fallback } : {}), metrics: r.metrics, tests_ok: r.ok, build: previewBuild, loaded: r.loaded, has_auto_test: r.has_test, result: r.result || '未分胜负', score: r.score,
      errors: errors.slice(0, 15), checks: checks.map(c => (c.ok ? '✓ ' : '✗ ') + c.what),
      hint: r.ok ? previewBuild?.ok === false ? '玩法测试通过，但预览构建失败：' + previewBuild.error : '当前版本编译、玩法测试和构建通过，仍需浏览器预览确认。' : !r.has_test && r.loaded ? '主场景根节点脚本缺少 auto_test()。' : '请修复后再 run_test。',
    };
    if (!r.image && !r.image_end) return summary;
    const blocks = [{ type: 'text', text: JSON.stringify(summary) + '\n截图：开局' + (r.image_end ? ' / auto_test 结束时' : '') + '：' }];
    for (const img of [r.image, r.image_end]) if (img) blocks.push({ type: 'image', source: { type: 'base64', media_type: 'image/jpeg', data: img } });
    return { __blocks: blocks };
  }
}

// ------------------------------------------------------------------ turn

const FULL_CODE_CHARS = 60000;

/** Scope and budget rules of the round's tier; the system prompt itself is tier-neutral. */
export function tierBrief(iteration) {
  const t = tierLimits(iteration?.tier);
  if (iteration?.tier === 'quality') return ['# 档位：品质（全力输出高品质游戏）',
    '- 目标是一款完成度高、可以发布的游戏，而不是一个切片：完整的开始界面、核心循环、进阶内容（多关卡/多波次/多种敌人、卡牌或道具，至少 3 种有意义的变化）、合理的难度曲线、胜负结算与重开。',
    '- 复刻原作时先用 web_fetch 系统调研（规则、数值表、关卡/卡牌/敌人列表、界面布局），本轮最多 ' + t.fetches + ' 次，按原作还原核心系统与内容量。',
    '- 画面打磨：粒子、受击闪白、屏幕震动、飘字、UI 动效与转场，画风按「画风与素材」。',
    '- 手感与打磨：每个操作都有动画、音效、粒子或飘字反馈；有转场与 UI 动效；文字清晰、布局不重叠，适配触控。',
    '- 分工：可用 delegate_tasks 并行推进内容与表现，本轮最多 ' + t.delegateBatches + ' 批。仍要小步提交，每个完整片段都 preview_checkpoint，让用户看到画面逐步拼出来。',
    '- 验证：每个大系统接入后都 run_game + game_eval 真实输入试玩，run_test 最多 ' + t.tests + ' 次，断言覆盖开局、核心操作、进阶内容、结算与重开。时间充足时继续打磨，不要提前草草收尾。',
    ...(iteration?.kind === 'demo' ? [] : ['- 节奏：上一轮已通过的验收不要先重复试玩，直接动手做本轮改进。']),
    '- 最后一次修改代码之后，必须重新做一次真实输入试玩并 run_test，否则不能通过验收。'].join('\n');
  return ['# 档位：Demo（快速出可玩 Demo）',
    '- 首轮快速交付一个高品质小 Demo：一个场景、一个完整核心循环、统一美术与清楚的操作反馈，具备失败和重开。完整复刻或大型系统分后续轮次逐步补齐。每次后续迭代只聚焦一个最重要的改进。',
    '- 资料查询最多 ' + t.fetches + ' 次，查完马上设计，不要长时间调研。',
    ...(iteration?.kind === 'demo' ? [] : ['- 本轮专注用户要求的那个改进（玩法、手感、内容）。']),
    iteration?.kind === 'demo'
      ? '- 节奏：前 40% 时间内必须 preview_checkpoint 出第一个可玩片段；3D 关卡搭两小批即可，不要在相机、高度、重力等细节上反复调；进入收口后只做试玩和测试。'
      : '- 节奏：上一轮已通过的验收不要先重复，直接动手做本轮改进；改完后用 run_game + game_eval 真实输入试玩一次、run_test 一次收尾。',
    '- 最后一次修改代码之后，必须重新做一次真实输入试玩并 run_test，否则不能通过验收。',
    (iteration?.kind === 'demo' ? '- 首轮不委派，亲自写一个最小但完整的主脚本（可以分 2–3 次提交）；' : '- 委派最多 ' + t.delegateBatches + ' 批；') + '玩法测试最多 ' + t.tests + ' 次（首次 + 最多两次修复重验）。'].join('\n');
}

/** What this round may do to the look: pencil by default; assets and finished art only on request. */
export function artBrief({ assetKinds = [], finalArt = false, limit = 0 } = {}) {
  return ['# 画风与素材（本轮）',
    finalArt
      ? '- 用户已要求正式美术：美术子代理在后台按美术位异步生成并自动替换铅笔稿，不占本轮时间；不要等待，也不要为美术位申请素材。新视觉元素继续用新的美术位 id，design_game 的 art 写清它的样子。'
      : '- 保持铅笔手绘风：所有画面都用 Pencil 工具包的美术位画，不生成 AI 图片，也不改变整体画风。手绘也要有层次、排线阴影、动画和操作反馈。design_game 的 art 照常列全美术位，日后用户要求正式美术时直接替换。',
    assetKinds.length
      ? '- 用户本轮要求了素材：可用 generate_asset 申请 ' + assetKinds.join(' / ') + '，最多 ' + limit + ' 个，只做用户要的那类。'
      : '- 用户本轮没有要求生成素材：不要调用 generate_asset（音乐、音效也不申请）。'].join('\n');
}

export function gpTurnPrompt(game, project, userText, isFirst, recap = '', iteration = createIteration({ kind: isFirst ? 'demo' : 'iteration' }), art = {}) {
  const look = artBrief({ ...art, limit: tierLimits(iteration?.tier).assets });
  const d = game.design;
  const scr = screenOf(game.meta?.orientation);
  const time = '目标 ' + (iteration.targetMs / 60000).toFixed(1) + ' 分钟；第 ' + ((iteration.wrapAt - iteration.startedAt) / 60000).toFixed(1) + ' 分钟开始收口；硬上限 ' + (iteration.hardMs / 60000).toFixed(1) + ' 分钟。';
  const quality = iteration?.tier === 'quality';
  const dim = game.meta?.dimension === '3d' ? '3D' : '';
  if (!d) {
    const p3 = portrait3d(game.meta?.dimension, game.meta?.orientation);
    return ['【屏幕】' + scr.cn + (dim ? '\n【用户选择】3D 游戏' : '') + (p3 ? '\n【' + p3.replace('：', '】') : '') + (game.meta?.genre_hint ? '\n【类型】' + game.meta.genre_hint : '') + '\n【用户想做的游戏】' + userText,
      tierBrief(iteration),
      look,
      '# 本轮任务\n' + (quality
        ? '先调研（需要时）并 design_game，再分步做出完整的高品质游戏：先可运行骨架并 preview_checkpoint，然后逐步接入内容、手感与打磨，每个大系统都真实试玩，最后 run_test 有效断言。'
        : '先 design_game（art 列全美术位），再用 Pencil 铅笔工具包完成一个场景的精致小 Demo：核心循环、操作反馈、失败与重开。前半轮 preview_checkpoint 展示可玩片段，之后 run_game + game_eval 真实输入试玩，再 run_test 有效断言。其他系统明确留到下一轮。') + time].join('\n\n');
  }
  const parts = [gpBrief(d)];
  if (recap) parts.push('# 之前几轮\n' + recap);
  const src = project.sources(p => !p.startsWith('assets/'));
  const total = Object.values(src).reduce((n, s) => n + s.length, 0);
  const listing = project.list().map(f => f.path).join('\n');
  parts.push('# 工程文件\n' + listing);
  parts.push(total <= FULL_CODE_CHARS
    ? '# 当前内容\n' + Object.entries(src).map(([f, s]) => '## ' + f + '\n' + numbered(s)).join('\n\n')
    : '# 脚本大纲（内容太多，需要时用 read_file / grep_files 查看）\n' + Object.entries(src).filter(([f]) => f.endsWith('.gd')).map(([f, s]) => '## ' + f + '（' + s.split('\n').length + ' 行）\n' + outline(s)).join('\n\n'));
  const cur = d.milestones[d.current];
  parts.push('# 用户这次说\n「' + userText + '」\n' + (/^(继续|下一步|接着|继续做|go on|continue)/i.test(userText.trim()) && cur ? '→ 推进里程碑 ' + cur.id + ' ' + cur.name + '。' : '→ 按用户要求修改（必要时用 update_plan 调整后续里程碑）。'));
  parts.push(tierBrief(iteration));
  parts.push(look);
  parts.push((quality ? '本轮可以完整推进用户要求和当前里程碑，并做同等打磨；复用已完成内容。' : '本轮只聚焦用户要求中最重要的一个改进，其余列入下一步；复用已完成内容。') + time);
  return parts.join('\n\n');
}

/** One turn of the game maker on a Godot project. Returns { session, out }. */
export async function runProjectBuilder({ game, project, userText, isFirst, hooks, makeCb, signal, recap = '', live = null, onSession, workflow, artifactDir,
  iterationOptions = {}, agentRunner = runAgent, runWorker, fetchImpl = fetch, toolTimeoutMs, browserPlaytest, model = CODE_MODEL, assetKinds = [], finalArt = false } = {}) {
  workflow ||= createWorkflow({ goal: userText, sourceRevision: project.revision() });
  workflow.iteration ||= createIteration({ kind: isFirst ? 'demo' : 'iteration', ...iterationOptions });
  const iteration = workflow.iteration;
  let session;
  const clock = iterationClock(iteration, {
    signal,
    onWrap: () => { updateIteration(iteration, { phase: 'verify', reason: '进入收口，停止扩展范围，开始试玩与验证' }); session?.checkpoint(); },
    onTarget: () => { updateIteration(iteration, { phase: 'review', reason: '已到目标时间，只处理收尾和阻塞问题' }); session?.checkpoint(); },
    onAbort: error => session?.savePartial(String(error?.message || error || '本轮已停止').slice(0, 500), { budgetExpired: error?.code === 'ITERATION_DEADLINE', cancelled: !!signal?.aborted }),
  });
  const budget = { soft: (iteration.wrapAt - iteration.startedAt) / 60000, hard: iteration.hardMs / 60000 };
  session = new ProjectSession(game, project, { ...hooks, signal: clock.signal }, { budget, live, workflow, artifactDir, runWorker, fetchImpl, toolTimeoutMs, browserPlaytest, model, abortRun: clock.abort, requireVisibleConstruction: isFirst, assetKinds });
  session.t0 = iteration.startedAt;
  const messages = [{ role: 'user', content: gpTurnPrompt(game, project, userText, isFirst, recap, iteration, { assetKinds, finalArt }) + '\n\n（请全程用中文思考和解说。）' }];
  const limits = tierLimits(iteration.tier);
  // A five-minute pencil Demo has no room for worker start-up; the coordinator writes it directly.
  const soloDemo = isFirst && iteration.tier !== 'quality';
  const tools = (game.design ? TOOLS.filter(t => t.name !== 'design_game') : TOOLS.map(t => t === GP_DESIGN_TOOL ? designToolFor(assetKinds.length ? limits.assets : 0) : t))
    .filter(t => !(soloDemo && t.name === 'delegate_tasks') && (assetKinds.length || t.name !== 'generate_asset'));
  let out;
  try {
    onSession?.(session); session.checkpoint(); throwIfAborted(clock.signal);
    out = await abortable(agentRunner({
      messages, signal: clock.signal, cb: makeCb?.(session) || {}, maxTurns: limits.maxTurns, finishTools: ['finish'],
      until: () => clock.signal.aborted || !!session.finish,
      beforeTurn: async history => {
        throwIfAborted(clock.signal);
        const feedback = hooks.takeParticipation?.();
        if (feedback) history.push({ role: 'user', content: feedback });
      },
      idleTimeoutMs: 90000,
      deps: { fetchImpl },
      req: { model, system: '用中文思考和解说。\n\n' + GP_SYSTEM, tools, max_tokens: limits.maxTokens, thinking: THINKING },
      exec: (name, input, id) => session.exec(name, input, null, id),
    }), clock.signal);
    if (!session.finish) session.savePartial(out?.interrupted ? '本轮执行中断，当前成果已保存' : '本轮尚未完成验收，当前成果已保存');
  } catch (error) {
    const budgetExpired = clock.signal.reason?.code === 'ITERATION_DEADLINE';
    const timedOut = budgetExpired || clock.signal.reason?.code === 'ITERATION_TOOL_TIMEOUT';
    session.savePartial(String(error?.message || error).slice(0, 500), { budgetExpired, cancelled: !!signal?.aborted });
    out = { done: false, interrupted: true, budgetExpired, timedOut, cancelled: !!signal?.aborted, error };
  } finally {
    session.endWatch();
    session.browserPlaytest?.stop();
    session.closed = true;
    // Batch cancellation returns even when a worker ignores its signal. Let it persist final
    // cancelled/blocked metadata before the server's turn-end checkpoint is emitted.
    await Promise.allSettled([...session.pendingBatches]);
    clock.dispose();
  }
  return { session, out };
}
