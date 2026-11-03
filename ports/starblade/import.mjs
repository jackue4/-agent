// Imports the Starblade port into a 造梦 project. Never overwrites an existing project record.
import fs from 'node:fs';
import path from 'node:path';
import { GodotProject } from '../../server/gproject.mjs';
import { emptyGame } from '../../server/engine.mjs';
import { normalizePlan } from '../../server/codegen.mjs';
import { createWorkflow, recordEvidence } from '../../server/workflow.mjs';

// Windows AV/indexer can briefly hold freshly written files; retry renames (local import tool only).
const _rename = fs.renameSync;
fs.renameSync = (a, b) => { for (let i = 0; ; i++) { try { return _rename(a, b); } catch (e) { if (e.code !== 'EPERM' || i > 40) throw e; Atomics.wait(new Int32Array(new SharedArrayBuffer(4)), 0, 0, 50); } } };

const data = process.env.UGC_DATA_DIR;
if (!data) throw new Error('Set UGC_DATA_DIR');
const id = process.argv[2] || 'starblade_port';
const skipBuild = process.argv.includes('--no-build');
const file = path.join(data, 'projects', id + '.json');
const src = path.resolve('src');
const project = new GodotProject(id);
const fresh = !project.exists;
project.create({ title: '星刃：回收协议', orientation: 'landscape' });
if (fresh) project.remove('main.gd');
const walk = d => fs.readdirSync(d, { withFileTypes: true }).flatMap(e => e.isDirectory() ? walk(path.join(d, e.name)) : [path.join(d, e.name)]);
const TEXT = /\.(gd|tscn|tres|gdshader|gdshaderinc|godot|cfg|json|txt|md|csv)$/i;
let n = 0, bytes = 0;
for (const f of walk(src)) {
  const rel = path.relative(src, f).split(path.sep).join('/');
  if (/^(README\.md|\.gitignore)$/.test(rel) || /\.import$|\.uid$/.test(rel)) continue;
  const buf = fs.readFileSync(f); bytes += buf.length; n++;
  if (TEXT.test(rel)) { const issues = project.write(rel, buf.toString('utf8')); if (issues.length) throw new Error(rel + ': ' + issues.join('; ')); }
  else project.writeAsset(rel, buf);
}
project.syncPlatform();
console.error(`wrote ${n} files, ${(bytes / 1024).toFixed(0)} KB`);
const goal = '移植 Godot 项目「星刃：回收协议」到造梦平台：面向移动端，增加虚拟摇杆与触控按钮，移动/网页默认低画质档以控制性能开销。';
const game = emptyGame();
Object.assign(game.meta, { engine: 'godot', title: '星刃：回收协议', pitch: '霓虹地下城动作肉鸽：选英雄与神祇祝福，九房间闯关，击败首领后撤离。', orientation: 'landscape', dimension: '3d' });
game.code = { files: {} };
game.design = normalizePlan({
  title: game.meta.title, pitch: game.meta.pitch, genre: '动作肉鸽 · 地下城撤离', dimension: '3d', orientation: 'landscape', faithful: true,
  closest_game: 'Hades 式俯视角动作肉鸽', differences: ['触控操作替代键鼠', '移动端低画质档：关闭后处理、阴影、辉光与点光源，粒子减量'],
  core_loop: '基地选英雄/武器 → 出击 → 清理房间获得祝福 → 击败首领 → 撤离结算 → 基地成长',
  rules: ['左侧摇杆移动，右侧攻击（长按蓄力）、冲刺、投掷、英雄技能', '房间清空后掉落祝福三选一', '首领击败后开启升降梯进入下一层', '死亡失去背包物资，撤离保留'],
  palette: ['#080e1c', '#62e5eb', '#ff9e50', '#ff5c52'], art_bible: '低多边形霓虹科幻地下城，冷蓝金属与橙色强调光',
  layout: '左下血条与摇杆，右下技能按钮，右上背包与暂停', controls: [['左侧拖动', '移动'], ['攻击', '连刺 / 长按横扫'], ['冲刺', '闪避'], ['技能 / 绝技', '英雄技能'], ['交互', '设施与宝箱']],
  modules: [{ file: 'scripts/main.gd', role: '游戏主循环', owner: 'gameplay', interface: 'Node3D 主场景' }, { file: 'scripts/touch_controls.gd', role: '移动端触控层', owner: 'scene', interface: 'CanvasLayer; bind(main)' }, { file: 'scripts/quality.gd', role: '画质分档', owner: 'gameplay', interface: 'static low()/font()' }],
  milestones: [{ id: 'M1', name: '移动端可玩移植', goal: '原玩法完整，触控可玩，低画质档', acceptance: ['基地可移动', '出击并选择祝福', '地下城可移动与攻击', '触控层可用'] }],
  build_steps: ['导入源码与素材', '编译检查', '自动试玩', '构建网页包'], assets: [],
});
const workflow = createWorkflow({ goal, sourceRevision: project.revision() });
const compile = await project.check();
console.error('check', JSON.stringify({ loaded: compile.loaded, errors: compile.errors?.slice(0, 20) }));
recordEvidence(workflow, { kind: 'compile', sourceRevision: compile.sourceRevision, ok: !!compile.loaded && !compile.errors?.length, errors: compile.errors });
const result = await project.selfTest({ shot: false });
console.error('test', JSON.stringify({ ok: result.ok, checks: result.checks, errors: result.errors?.slice(0, 20) }));
recordEvidence(workflow, { kind: 'test', sourceRevision: result.sourceRevision, ok: result.ok, checks: result.checks, errors: result.errors });
let buildMeta = null;
if (!skipBuild) {
  const build = await project.build();
  console.error('build', JSON.stringify({ ok: build.ok, error: build.error, buildId: build.buildId, version: build.version }));
  if (build.ok) { recordEvidence(workflow, { kind: 'build', ...build }); game.meta.pck_version = build.version; const { path: _p, ...m } = build; buildMeta = m; }
}
workflow.completionRequested = !!buildMeta && result.ok;
if (workflow.completionRequested) workflow.status = 'ready';
if (!fs.existsSync(file)) {
  fs.mkdirSync(path.dirname(file), { recursive: true });
  fs.writeFileSync(file, JSON.stringify({ id, owner: 'me', created: Date.now(), updated: Date.now(), game, messages: [], chat: [{ role: 'user', text: goal, t: Date.now() }], timeline: [], versions: [], running: false, prompt: goal, published: null, workflow, build: buildMeta, seq: 0, log: [] }));
}
console.log(JSON.stringify({ id, ok: result.ok, buildId: buildMeta?.buildId }));
