// Imports the StickBonk port into a 造梦 project and publishes it (featured) when the build passes.
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
const id = process.argv[2] || 'stickbonk_port';
const skipBuild = process.argv.includes('--no-build');
const file = path.join(data, 'projects', id + '.json');
const src = path.resolve('src');
const project = new GodotProject(id);
const fresh = !project.exists;
project.create({ title: '火柴人大乱斗 StickBonk', orientation: 'landscape' });
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
// Drop project assets that were removed/renamed in src (e.g. ground_*.png -> .jpg) so they don't bloat the pck.
for (const f of project.list()) {
  if (/^addons\//.test(f.path) || f.path === 'project.godot' || f.path === 'build.json') continue;
  if (/^art\//.test(f.path) && !fs.existsSync(path.join(src, f.path))) { project.remove(f.path); console.error('removed stale', f.path); }
}
// Big full-screen backdrops: lossy import keeps the web pck small (sprites stay lossless).
for (const big of ['art/title_splash.jpg', 'art/dojo_bg.jpg', 'art/ground_bamboo.jpg', 'art/ground_volcano.jpg', 'art/ground_ice.jpg']) {
  const imp = path.join(src, big + '.import');
  const cfg = '[remap]\n\nimporter="texture"\ntype="CompressedTexture2D"\n\n[params]\n\ncompress/mode=1\ncompress/lossy_quality=0.8\nmipmaps/generate=false\n';
  if (fs.existsSync(path.join(src, big)) && !fs.existsSync(path.join(project.dir, big + '.import'))) fs.writeFileSync(path.join(project.dir, big + '.import'), cfg);
  else if (fs.existsSync(path.join(project.dir, big + '.import'))) {
    let t = fs.readFileSync(path.join(project.dir, big + '.import'), 'utf8');
    if (!/compress\/mode=1/.test(t)) { t = t.replace(/compress\/mode=\d/, 'compress/mode=1').replace(/compress\/lossy_quality=[\d.]+/, 'compress/lossy_quality=0.8'); fs.writeFileSync(path.join(project.dir, big + '.import'), t); }
  }
}
project.syncPlatform();
console.error(`wrote ${n} files, ${(bytes / 1024).toFixed(0)} KB`);
const goal = '「Stick Bonk! 火柴人大乱斗」大版本：元素反应与 6 张合体金卡、卡牌刷新/封印/锁定与稀有度；道馆养成（碎片结晶、修炼、秘籍、门派、图鉴、成就，原子化存档）；4 名角色、4 把武器、招式进化、诅咒卡、武馆挑战/流浪商人/宝箱怪/混沌祭坛事件；竹林/火山/冰原三张地图与环境机制、史莱姆王/蝙蝠女王两只新 BOSS、破坏协议难度阶梯、每日挑战与 5 分钟速通。保持美漫手绘风与手机横屏触控。';
const game = emptyGame();
Object.assign(game.meta, { engine: 'godot', title: '火柴人大乱斗 StickBonk', pitch: '美漫火柴人肉鸽乱斗：元素反应 + 合体金卡，道馆养成四大门派，竹林/火山/冰原三图挑战破坏协议！', orientation: 'landscape', dimension: '2d' });
game.code = { files: {} };
game.design = normalizePlan({
  title: game.meta.title, pitch: game.meta.pitch, genre: '动作肉鸽 · 割草乱斗', dimension: '2d', orientation: 'landscape', faithful: true,
  closest_game: 'Poke Bonk / 吸血鬼幸存者式割草肉鸽，加上火柴人格斗连招', differences: ['触控操作替代键鼠，攻击自动瞄准最近怪物', '元素反应（灼烧/感电/冰冻 → 爆燃/雷暴/冰爆/空中追击）与合体金卡', '局外道馆养成 + 多角色/武器/地图/门派', '移动端低画质档'],
  core_loop: '道馆选择角色/武器/地图/门派/模式 → 出战割草 → 升级三选一（稀有度、刷新、封印、锁定、合体金卡、招式进化）→ 随机事件 → BOSS → 结算碎片结晶 → 道馆修炼解锁',
  rules: ['左半屏拖动摇杆移动，右侧攻击/重锤/冲刺', '火焰灼烧、雷电感电、寒冰冻结，组合触发元素反应', '两个技能都到 Lv3 时出现合体金卡（雷光闪、千手观音、天崩地裂、火流星、血影、引力拳）', '事件：武馆挑战、流浪商人、精英护送宝箱怪、混沌祭坛诅咒', '地图：街头道场、竹林（狂风）、火山（熔岩+落石）、冰原（打滑+暴风雪）', 'BOSS：巨拳魔王、史莱姆王、蝙蝠女王', '破坏协议 0-8 级难度阶梯、每日固定种子挑战、5 分钟速通', '结算获得碎片结晶，用于修炼、秘籍、门派、角色、武器与地图解锁'],
  palette: ['#120d17', '#f8eed4', '#ee2b33', '#ffd924', '#2e8cfa'], art_bible: '美漫手绘风：粗黑描边、网点半调、爆炸拟声字，程序绘制的火柴人与 AI 手绘怪物贴图',
  layout: '顶部经验条，左上血条，中上计时，右上击碎数与连击，左下摇杆，右下攻击/重锤/冲刺按钮', controls: [['左侧拖动', '移动'], ['攻击', '四段连击'], ['重锤', '跃起砸地'], ['冲刺', '突进 / 冲刺中攻击飞踢'], ['暂停', '暂停']],
  modules: [{ file: 'scripts/main.gd', role: '游戏主循环、刷怪与自测', owner: 'gameplay', interface: 'Node2D 主场景; auto_test()' }, { file: 'scripts/touch_controls.gd', role: '移动端触控层', owner: 'scene', interface: 'CanvasLayer; main 引用' }, { file: 'scripts/player.gd', role: '火柴人主角与招式', owner: 'gameplay', interface: 'Player' }, { file: 'scripts/g.gd', role: '全局状态、手感与画质档', owner: 'gameplay', interface: 'autoload G' }],
  milestones: [{ id: 'M1', name: '移动端可玩移植', goal: '原玩法完整，触控可玩，低画质档', acceptance: ['标题页进入道馆', '道馆购买与存档', '元素反应', '合体金卡', '卡牌刷新/封印/锁定', '事件与商店/祭坛', '新地图与新 BOSS', '结算结晶'] }],
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
const cover = process.env.COVER || old?.published?.cover || '';
const t = Date.now();
const published = buildMeta && result.ok ? { game: structuredClone(game), assets: {}, cover, t, pck: true, build: buildMeta, author: '造梦官方', plays: old?.published?.plays || 0, likes: old?.published?.likes || 0, featured: true } : old?.published || null;
fs.mkdirSync(path.dirname(file), { recursive: true });
fs.writeFileSync(file, JSON.stringify({ ...(old || {}), id, owner: 'me', created: old?.created || t, updated: t, game, messages: [], chat: [{ role: 'user', text: goal, t }, { role: 'assistant', text: '已完成移植：触控摇杆 + 攻击/重锤/冲刺按钮，触屏自动瞄准，手机低画质档，已发布并置顶首页。', t }], timeline: [], versions: [], running: false, prompt: goal, published, workflow, build: buildMeta, seq: 0, log: [] }));
console.log(JSON.stringify({ id, ok: result.ok, buildId: buildMeta?.buildId }));