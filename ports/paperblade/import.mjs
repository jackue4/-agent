// Imports the PaperBlade Survivors (纸剑幸存者) port into a 造梦 project and publishes it (featured) when the build passes.
import fs from 'node:fs';
import path from 'node:path';
import { ensureCover } from './cover.mjs';
import { GodotProject } from '../../server/gproject.mjs';
import { emptyGame } from '../../server/engine.mjs';
import { normalizePlan } from '../../server/codegen.mjs';
import { createWorkflow, recordEvidence } from '../../server/workflow.mjs';

// Windows AV/indexer can briefly hold freshly written files; retry renames (local import tool only).
const _rename = fs.renameSync;
fs.renameSync = (a, b) => { for (let i = 0; ; i++) { try { return _rename(a, b); } catch (e) { if (e.code !== 'EPERM' || i > 40) throw e; Atomics.wait(new Int32Array(new SharedArrayBuffer(4)), 0, 0, 50); } } };

const data = process.env.UGC_DATA_DIR;
if (!data) throw new Error('Set UGC_DATA_DIR');
const id = process.argv[2] || 'paperblade_port';
const skipBuild = process.argv.includes('--no-build');
const file = path.join(data, 'projects', id + '.json');
const src = path.resolve('src');
const TITLE = '纸剑幸存者';
const project = new GodotProject(id);
const fresh = !project.exists;
project.create({ title: TITLE, orientation: 'landscape' });
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
const goal = '移植 Godot 项目「纸剑幸存者 PaperBlade Survivors」到造梦平台：面向手机横屏，增加全屏浮动虚拟摇杆与暂停按钮、触屏提示，网页字体与存档适配，移动端低画质档（关闭泛光、粒子减半、敌人上限降低）。';
const game = emptyGame();
Object.assign(game.meta, { engine: 'godot', title: TITLE, pitch: '剪纸国风仙侠割草：御剑、剑轮、掌心雷自动索敌，拾取灵晶突破境界，开宝箱转盘进化神通，在妖潮中存活 15 分钟！', orientation: 'landscape', dimension: '3d' });
game.code = { files: {} };
game.design = normalizePlan({
  title: TITLE, pitch: game.meta.pitch, genre: '动作肉鸽 · 幸存者割草', dimension: '3d', orientation: 'landscape', faithful: true,
  closest_game: '吸血鬼幸存者（Vampire Survivors）式自动攻击割草肉鸽，国风剪纸仙侠题材', differences: ['触控浮动摇杆替代键盘', '移动端低画质档：关闭泛光、碎片与天气粒子减半、敌人上限 260'],
  core_loop: '走位躲避 → 飞剑自动索敌击杀妖怪 → 拾取灵晶升级 → 三选一功法 → 武器满级+被动 → 击杀精英开宝箱进化 → 存活 15 分钟 → 金币永久修炼',
  rules: ['按住屏幕任意处拖动移动，武器自动攻击', '击杀掉落灵晶，升级时暂停并三选一功法', '武器满级且持有对应被动时，精英宝箱可进化', '每分钟一只精英，定时妖潮与首领', '金币在洞府修炼永久强化，三张地图逐步解锁'],
  palette: ['#0a0614', '#ffe08a', '#b48cff', '#5aa0ff', '#f25c5c'], art_bible: '国风剪纸仙侠：纸片角色立在 3D 斜俯视场地上，金色描边 UI，发光法术特效',
  layout: '顶部经验条，左上武器/被动图标，中上计时与暂停按钮，右上等级/击杀/金币，角色脚下血条', controls: [['拖动屏幕', '移动'], ['暂停按钮', '暂停'], ['点击卡片', '选择功法'], ['点击', '宝箱跳过/领取']],
  modules: [{ file: 'scripts/game.gd', role: '游戏主循环、升级、宝箱与自测', owner: 'gameplay', interface: 'Node 主场景; auto_test()' }, { file: 'scripts/touch_controls.gd', role: '移动端触控层', owner: 'scene', interface: 'CanvasLayer; game 引用' }, { file: 'scripts/hud.gd', role: '全部 2D 界面', owner: 'ui', interface: 'CanvasLayer' }, { file: 'scripts/g.gd', role: '全局状态、存档与画质档', owner: 'gameplay', interface: 'autoload G' }],
  milestones: [{ id: 'M1', name: '移动端可玩移植', goal: '原玩法完整，触控可玩，低画质档', acceptance: ['标题页点击开始', '选择地图', '摇杆移动', '升级选卡', '暂停与继续'] }],
  build_steps: ['导入源码与素材', '编译检查', '自动试玩', '构建网页包', '发布并置顶首页'], assets: [],
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
const old = fs.existsSync(file) ? JSON.parse(fs.readFileSync(file, 'utf8')) : null;
const cover = buildMeta && result.ok ? ensureCover({ data, id, requested: process.env.COVER, existing: old?.published?.cover, draft: old?.draftCover }) : (old?.published?.cover || '');
const t = Date.now();
const published = buildMeta && result.ok ? { game: structuredClone(game), assets: {}, cover, t, pck: true, build: buildMeta, author: '造梦官方', plays: old?.published?.plays || 0, likes: old?.published?.likes || 0, featured: true } : old?.published || null;
fs.mkdirSync(path.dirname(file), { recursive: true });
fs.writeFileSync(file, JSON.stringify({ ...(old || {}), id, owner: 'me', created: old?.created || t, updated: t, game, messages: [], chat: [{ role: 'user', text: goal, t }, { role: 'assistant', text: '已完成移植：全屏浮动虚拟摇杆 + 暂停按钮，触屏提示与字体适配，手机低画质档，已发布并置顶首页。', t }], timeline: [], versions: [], running: false, prompt: goal, published, workflow, build: buildMeta, seq: 0, log: [] }));
console.log(JSON.stringify({ id, ok: result.ok, buildId: buildMeta?.buildId }));
