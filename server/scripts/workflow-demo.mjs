// Creates an isolated, deliberately failing sample for exercising resume -> independent tasks -> acceptance.
// Never touches an existing project. Run with UGC_DATA_DIR pointing at a test data directory.
import fs from 'node:fs';
import path from 'node:path';
import { GodotProject } from '../gproject.mjs';
import { emptyGame } from '../engine.mjs';
import { normalizePlan } from '../codegen.mjs';
import { createWorkflow, recordEvidence, upsertTask } from '../workflow.mjs';

const data = process.env.UGC_DATA_DIR;
if (!data) throw new Error('Set UGC_DATA_DIR to an isolated test directory');
const id = process.argv[2] || 'workflow_demo_v1';
const file = path.join(data, 'projects', id + '.json');
if (fs.existsSync(file)) throw new Error('Demo already exists; use a fresh id to preserve it');
const project = new GodotProject(id);
project.create({ title: '星光收集站 · 协作验收', orientation: 'landscape' });
const goal = '完善星光收集站。每点击一次收集增加 1 分，收集 5 次胜利，重新开始清零。规则程序和画面分别交给独立任务，同批并行：规则任务只改 scripts/rules.gd，场景任务只改 scripts/hud.gd。沿用主入口及 auto_test，不生成素材，画面用几何星光和按钮即可。修复已有测试失败并验收。';
const sources = {
  'scripts/rules.gd': `extends RefCounted\nvar score: int = 0\nvar goal: int = 5\nfunc collect() -> void:\n\tif not won():\n\t\tscore += 2\nfunc reset() -> void:\n\tscore = 0\nfunc won() -> bool:\n\treturn score >= goal\n`,
  'scripts/hud.gd': `extends Control\nsignal collected\nsignal restarted\nvar counter: Label\nfunc _ready() -> void:\n\tset_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)\n\tcounter = Label.new()\n\tcounter.position = Vector2(460, 180)\n\tcounter.add_theme_font_size_override("font_size", 28)\n\tadd_child(counter)\n\tvar button = Button.new()\n\tbutton.name = "Collect"\n\tbutton.text = "收集星光"\n\tbutton.position = Vector2(460, 290)\n\tbutton.size = Vector2(360, 100)\n\tbutton.pressed.connect(func(): collected.emit())\n\tadd_child(button)\n\tvar restart_button = Button.new()\n\trestart_button.name = "Restart"\n\trestart_button.text = "重新开始"\n\trestart_button.position = Vector2(540, 450)\n\trestart_button.size = Vector2(200, 60)\n\trestart_button.pressed.connect(func(): restarted.emit())\n\tadd_child(restart_button)\nfunc present(score: int, goal: int, won: bool) -> void:\n\tif counter:\n\t\tcounter.text = "星光 %d / %d%s" % [score, goal, " · 完成" if won else ""]\n`,
  'main.gd': `extends Control\nvar rules = preload("res://scripts/rules.gd").new()\nvar hud: Control\nfunc _ready() -> void:\n\thud = preload("res://scripts/hud.gd").new()\n\thud.name = "GameView"\n\tadd_child(hud)\n\thud.collected.connect(_collect)\n\thud.restarted.connect(_restart)\n\thud.present(rules.score, rules.goal, rules.won())\nfunc _collect() -> void:\n\trules.collect()\n\thud.present(rules.score, rules.goal, rules.won())\n\tif rules.won():\n\t\tUGC.win(rules.score)\nfunc _restart() -> void:\n\trules.reset()\n\tUGC.result = ""\n\thud.present(rules.score, rules.goal, rules.won())\nfunc auto_test() -> void:\n\t_restart()\n\tawait UGC.wait(0.1)\n\tUGC.check(rules.score == 0, "重新开始分数为零")\n\tUGC.click(hud.get_node("Collect"))\n\tawait UGC.wait(0.1)\n\tUGC.check(rules.score == 1, "真实点击收集一次恰好增加一分")\n\tfor i in range(4):\n\t\tUGC.click(hud.get_node("Collect"))\n\t\tawait UGC.wait(0.08)\n\tUGC.check(rules.score == 5 and rules.won(), "五次收集达到胜利")\n\tUGC.check(UGC.result == "win", "胜利已上报平台")\n\tUGC.click(hud.get_node("Collect"))\n\tawait UGC.wait(0.08)\n\tUGC.check(rules.score == 5, "胜利后额外点击不会继续加分")\n\tUGC.click(hud.get_node("Restart"))\n\tawait UGC.wait(0.08)\n\tUGC.check(rules.score == 0 and not rules.won(), "真实点击重新开始恢复游戏")\n`,
};
for (const [name, code] of Object.entries(sources)) {
  const issues = project.write(name, code); if (issues.length) throw new Error(issues.join('\n'));
}
const game = emptyGame();
Object.assign(game.meta, { engine: 'godot', title: '星光收集站 · 协作验收', pitch: '真实分工、失败修复和版本验收的可玩示例', orientation: 'landscape', dimension: '2d' });
game.code = { files: {} };
game.design = normalizePlan({
  title: game.meta.title, pitch: game.meta.pitch, genre: '点击收集', dimension: '2d', orientation: 'landscape', faithful: false,
  closest_game: '轻量点击收集', differences: [], core_loop: '收集五颗星光 → 胜利 → 重新开始',
  rules: ['每次点击增加一分', '五分胜利', '胜利后不再加分', '重新开始清零'],
  palette: ['#10182c', '#75e5df', '#f4ca78'], art_bible: '深蓝夜空、温暖金色星光和青色按钮，清晰简洁',
  layout: '顶部标题和进度，中央大收集按钮，下方重新开始', controls: [['点击收集', '获得一分'], ['重新开始', '清零']],
  modules: [{ file: 'scripts/rules.gd', role: '收集规则与胜利判定', owner: 'gameplay', interface: 'score:int goal:int; collect(), reset(), won()->bool' }, { file: 'scripts/hud.gd', role: '游戏画面与按钮', owner: 'scene', interface: 'extends Control; signals collected/restarted; present(score:int,goal:int,won:bool); direct children Collect and Restart Buttons' }],
  milestones: [{ id: 'M1', name: '可玩收集循环', goal: '规则正确、画面完整、点击可用', acceptance: ['收集一次加一分', '五次点击胜利', '胜利后分数不再增加', '重新开始清零'] }],
  build_steps: ['修复计分规则', '搭建星光画面', '运行真实点击测试', '确认浏览器预览'], assets: [],
});
const workflow = createWorkflow({ goal, sourceRevision: project.revision() });
upsertTask(workflow, { id: 'rules', title: '修复收集规则', role: 'gameplay', status: 'failed', files: ['scripts/rules.gd'], depends_on: [], error: '一次点击错误增加两分，玩法测试失败' });
upsertTask(workflow, { id: 'scene', title: '完善星光画面', role: 'scene', status: 'queued', files: ['scripts/hud.gd'], depends_on: [] });
const compile = await project.check();
recordEvidence(workflow, { kind: 'compile', sourceRevision: compile.sourceRevision, ok: !!compile.loaded && !compile.errors?.length, errors: compile.errors });
const result = await project.selfTest({ shot: false });
recordEvidence(workflow, { kind: 'test', sourceRevision: result.sourceRevision, ok: result.ok, checks: result.checks, errors: result.errors });
if (result.ok || !result.checks?.some(c => !c.ok)) throw new Error('Expected the sample to fail its real gameplay assertions');
const build = await project.build();
if (!build.ok) throw new Error(build.error);
recordEvidence(workflow, { kind: 'build', ...build });
game.meta.pck_version = build.version;
const { path: internalPath, ...buildMeta } = build;
fs.mkdirSync(path.dirname(file), { recursive: true });
const record = { id, owner: 'me', created: Date.now(), updated: Date.now(), game, messages: [], chat: [{ role: 'user', text: goal, t: Date.now() }], timeline: [], versions: [], running: true, prompt: goal, published: null, workflow, build: buildMeta, seq: 0, log: [] };
fs.writeFileSync(file, JSON.stringify(record));
fs.writeFileSync(path.join(data, 'baseline-verification.json'), JSON.stringify({ id, compile: { loaded: compile.loaded, errors: compile.errors, sourceRevision: compile.sourceRevision }, test: { ok: result.ok, checks: result.checks, errors: result.errors }, build: buildMeta }, null, 2));
console.log(JSON.stringify({ id, expectedFailure: true, checks: result.checks, buildId: build.buildId, file }));
