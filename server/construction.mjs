// Canonical level data: the creation view and exported game load the same committed scene.
import path from 'node:path';
export const CONSTRUCTION_JSON = 'scenes/construction.json';
export const CONSTRUCTION_SCENE = 'scenes/construction.tscn';
export const CONSTRUCTION_FILES = new Set([CONSTRUCTION_JSON, CONSTRUCTION_SCENE]);
export const isConstructionFile = value => CONSTRUCTION_FILES.has(path.posix.normalize(String(value || '').replace(/\\/g, '/').replace(/^res:\/\//i, '')).toLowerCase());
const KINDS = new Set(['box', 'sphere', 'cylinder', 'cone']);
const ID = /^[A-Za-z][A-Za-z0-9_]{0,47}$/;
const color = (v, fallback) => {
  if (v === undefined) return fallback;
  if (typeof v !== 'string' || !/^#[0-9a-f]{6}$/i.test(v)) throw new Error('颜色必须是 #RRGGBB');
  return v.toLowerCase();
};
const vector = (v, fallback, min, max) => {
  if (v === undefined) return [...fallback];
  if (!Array.isArray(v) || v.length !== 3 || v.some(x => typeof x !== 'number' || !Number.isFinite(x) || x < min || x > max)) throw new Error('坐标/尺寸必须是范围内的三个有限数字');
  return v.map(x => Math.round(x * 10000) / 10000);
};
/** Optional pencil-kit texture slot: final art for res://assets/<art>.png replaces the pencil tint. */
const artSlot = (v, fallback) => {
  if (v === undefined || v === '') return fallback ? { art: fallback } : {};
  if (typeof v !== 'string' || !/^[a-z][a-z0-9_]{1,30}$/.test(v)) throw new Error('art 美术位 id 需为小写英文加下划线');
  return { art: v };
};
const label = (s, fallback = '') => typeof s === 'string' ? s.replace(/[\u0000-\u001f]/g, '').slice(0, 60) : fallback;

export function applyConstruction(previous, input, { runId = '' } = {}) {
  if (!input || !Array.isArray(input.ops) || input.ops.length < 1 || input.ops.length > 8) throw new Error('每批必须提交 1–8 个真实关卡操作');
  if (input.baseRevision !== undefined && input.baseRevision !== (previous?.revision || 0)) throw new Error('场景版本已改变，请读取最新 construction 后重试');
  const objects = new Map((previous?.objects || []).map(o => [o.id, structuredClone(o)]));
  const seen = new Set();
  for (const op of input.ops) {
    if (!op || typeof op.id !== 'string' || !ID.test(op.id) || seen.has(op.id)) throw new Error('对象 ID 需为唯一英文标识，同一批不能重复');
    seen.add(op.id);
    if (op.op === 'remove') {
      if (!objects.delete(op.id)) throw new Error('要移除的对象不存在：' + op.id);
      continue;
    }
    if (op.op !== 'upsert') throw new Error('操作只能是 upsert 或 remove');
    const old = objects.get(op.id) || {};
    const kind = op.kind ?? old.kind;
    if (!KINDS.has(kind)) throw new Error('kind 只能是 box/sphere/cylinder/cone');
    if (op.solid !== undefined && typeof op.solid !== 'boolean') throw new Error('solid 必须是布尔值');
    objects.set(op.id, { id: op.id, label: label(op.label, old.label || op.id), kind,
      position: vector(op.position, old.position || [0, 0, 0], -200, 200),
      size: vector(op.size, old.size || [1, 1, 1], 0.05, 100),
      rotation: vector(op.rotation, old.rotation || [0, 0, 0], -360, 360),
      color: color(op.color, old.color || '#7995aa'), solid: op.solid ?? old.solid ?? false, ...artSlot(op.art, old.art) });
  }
  if (objects.size > 96) throw new Error('本轮关卡最多 96 个对象，请保留一个小场景');
  const camera = { position: vector(input.camera?.position, previous?.camera?.position || [20, 18, 24], -200, 200), lookAt: vector(input.camera?.lookAt, previous?.camera?.lookAt || [0, 0, 0], -200, 200) };
  const offset = camera.position.map((x, i) => x - camera.lookAt[i]);
  if (Math.hypot(...offset) < 1 || Math.hypot(offset[0], offset[2]) < 0.05) throw new Error('镜头需要与目标分离且避免竖直退化');
  const environment = { background: color(input.environment?.background, previous?.environment?.background || '#f8f4ea'), ambient: color(input.environment?.ambient, previous?.environment?.ambient || '#ffffff') };
  if (previous && JSON.stringify([...objects.values()]) === JSON.stringify(previous.objects) && JSON.stringify(camera) === JSON.stringify(previous.camera) && JSON.stringify(environment) === JSON.stringify(previous.environment)) throw new Error('本批没有实际场景变化');
  const style = previous ? previous.style : 'pencil';
  return { schema: 1, dimension: '3d', revision: (previous?.revision || 0) + 1, runId: label(runId), step: label(input.step, '搭建关卡'), objects: [...objects.values()], camera, environment, ...(style ? { style } : {}) };
}

export const constructionSceneText = () => '[gd_scene load_steps=2 format=3]\n\n[ext_resource type="Script" path="res://addons/ugc/construction_scene.gd" id="1"]\n\n[node name="Construction" type="Node3D"]\nscript = ExtResource("1")\nsource_path = "res://scenes/construction.json"\n';

export function constructionScaffold(snapshot) {
  const v = x => 'Vector3(' + x.join(', ') + ')';
  return {
    'main.tscn': '[gd_scene load_steps=3 format=3]\n[ext_resource type="Script" path="res://main.gd" id="1"]\n[ext_resource type="PackedScene" path="res://scenes/construction.tscn" id="2"]\n[node name="Main" type="Node3D"]\nscript = ExtResource("1")\n[node name="Construction" parent="." instance=ExtResource("2")]\n',
    'main.gd': 'extends Node3D\n\nfunc _ready() -> void:\n\tvar camera := Camera3D.new()\n\tadd_child(camera)\n\tcamera.position = ' + v(snapshot.camera.position) + '\n\tcamera.look_at(' + v(snapshot.camera.lookAt) + ', Vector3.UP)\n\tcamera.current = true\n\tvar sun := DirectionalLight3D.new()\n\tadd_child(sun)\n\tsun.rotation_degrees = Vector3(-50, -25, 0)\n\tsun.light_energy = 1.4\n',
  };
}

/** The project lock is owned by the caller. Roll back the whole owned file bundle on any failure. */
export function commitConstruction(project, snapshot, { scaffold = false } = {}) {
  const files = { [CONSTRUCTION_JSON]: JSON.stringify(snapshot, null, 2) + '\n', [CONSTRUCTION_SCENE]: constructionSceneText(), ...(scaffold ? constructionScaffold(snapshot) : {}) };
  const before = Object.fromEntries(Object.keys(files).map(p => [p, project.read(p)]));
  const beforeState = project.state ? structuredClone(project.state) : null;
  try {
    for (const [p, content] of Object.entries(files)) {
      const issues = project.write(p, content);
      if (issues.length) throw new Error(issues.join('\n'));
    }
  } catch (error) {
    for (const [p, content] of Object.entries(before)) {
      if (content == null) project.remove(p); else project.write(p, content);
    }
    if (beforeState) project.state = beforeState;
    throw error;
  }
  return Object.keys(files);
}

const vecSchema = { type: 'array', minItems: 3, maxItems: 3, items: { type: 'number' } };
export const BUILD_SCENE_TOOL = { name: 'build_scene', description: '直接搭建用户正在看的真实 3D 关卡。每次提交一小批物体立即在现场施工，并保存到最终游戏实际实例化的 scenes/construction.tscn。先地面，再地标/障碍，最后写玩法；不是等待动画。', input_schema: { type: 'object', required: ['step', 'ops'], properties: {
  step: { type: 'string', description: '这一批实际搭建什么，简短中文' }, baseRevision: { type: 'integer', description: '上一批返回的 revision；第一批为 0' },
  ops: { type: 'array', minItems: 1, maxItems: 8, items: { type: 'object', required: ['op', 'id'], properties: {
    op: { type: 'string', enum: ['upsert', 'remove'] }, id: { type: 'string', description: '稳定英文ID，首字母为字母' }, label: { type: 'string' }, kind: { type: 'string', enum: ['box', 'sphere', 'cylinder', 'cone'] },
    position: vecSchema, size: { ...vecSchema, description: 'XYZ完整尺寸，最小0.05，最大100' }, rotation: { ...vecSchema, description: 'XYZ欧拉角，单位度' }, color: { type: 'string', description: '#RRGGBB，铅笔着色的底色' }, solid: { type: 'boolean', description: '是否创建StaticBody3D碰撞体' },
    art: { type: 'string', description: '可选：表面贴图美术位 id（如 floor、wall），与 design_game 的 art 一致，正式美术到达后自动贴上' },
  } } }, camera: { type: 'object', properties: { position: vecSchema, lookAt: vecSchema } }, environment: { type: 'object', properties: { background: { type: 'string' }, ambient: { type: 'string' } } },
} } };
