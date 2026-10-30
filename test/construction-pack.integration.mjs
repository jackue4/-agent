// Real export acceptance, intentionally separate from the fast *.test.mjs suite.
import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { GodotProject, runGodot, tagged } from '../server/gproject.mjs';
import { applyConstruction, commitConstruction } from '../server/construction.mjs';
import { readPck } from '../server/pck.mjs';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const runtimeTests = `
func auto_test() -> void:
	var data = JSON.parse_string(FileAccess.get_file_as_string("res://scenes/construction.json"))
	var roots = get_tree().get_nodes_in_group("ugc_construction_scene")
	UGC.check(roots.size() == 1, "exactly one canonical construction scene is instantiated")
	if roots.size() != 1:
		return
	var world = roots[0]
	UGC.check(world == get_node("Construction"), "game entry actually owns the committed scene")
	UGC.check(world.source_path == "res://scenes/construction.json", "runtime reads final canonical JSON")
	UGC.check(world.get_meta("construction_revision") == data.revision, "runtime scene revision matches final JSON")
	UGC.check(world.objects.size() == data.objects.size(), "actual object dictionary matches final snapshot count")
	UGC.check(world.get_meta("objects_count") == data.objects.size(), "reported object count matches actual objects")
	UGC.check(not world.objects.has("discarded"), "removed draft geometry did not reappear in exported game")
	for row in data.objects:
		var object = world.objects.get(row.id)
		UGC.check(object != null and object.name == row.id, "stable object id " + row.id)
		if object == null:
			continue
		var position_expected = Vector3(row.position[0], row.position[1], row.position[2])
		var size_expected = Vector3(row.size[0], row.size[1], row.size[2])
		UGC.check(object.position.is_equal_approx(position_expected), "actual position " + row.id)
		UGC.check(object.get_meta("construction_data") == row, "full committed metadata " + row.id)
		var visual = object.get_node("Visual")
		UGC.check(visual is MeshInstance3D and visual.scale.is_equal_approx(size_expected), "actual mesh dimensions " + row.id)
		var mat = visual.material_override
		var tint = mat.get_shader_parameter("tint") if mat is ShaderMaterial else mat.albedo_color
		UGC.check(tint.is_equal_approx(Color(row.color)), "actual material color " + row.id)
		UGC.check(object.has_node("Solid") == bool(row.solid), "actual collision policy " + row.id)
		if row.solid:
			var collision = object.get_node("Solid").get_child(0)
			UGC.check(collision is CollisionShape3D and collision.shape != null, "real collision shape " + row.id)
	UGC.check(UGC.construction_report()[0].revision == data.revision, "platform report reads actual scene revision")
`;

test('construction data survives a real GodotProject export and missing runtime scene is rejected', { timeout: 180000 }, async t => {
  const artifactRoot = path.join(root, 'artifacts', 'inworld');
  const isolated = fs.mkdtempSync(path.join(artifactRoot, 'construction-pack-'));
  const template = path.join(isolated, 'template');
  fs.cpSync(path.join(root, 'gp_template'), template, { recursive: true,
    filter: p => !/(?:^|[\\/])(?:\.godot|build|generated)(?:[\\/]|$)|\.(?:import|uid)$/.test(p) });
  const report = { isolated, startedAt: new Date().toISOString(), calls: [] };
  const runner = async (args, opts) => {
    const result = await runGodot(args, opts), index = report.calls.length + 1;
    fs.writeFileSync(path.join(isolated, `process-${index}.log`), result.stdout + '\n' + result.stderr);
    report.calls.push({ args, code: result.code, timedOut: !!result.timedOut, errors: (result.stdout + '\n' + result.stderr).split(/\r?\n/).filter(line => /^(?:SCRIPT |USER )?ERROR:/.test(line)) });
    return result;
  };
  const project = new GodotProject('canonical-scene', { root: path.join(isolated, 'projects'), template, runGodot: runner }).create({ title: path.basename(isolated) });
  const first = applyConstruction(null, { step: '地面', baseRevision: 0, ops: [
    { op: 'upsert', id: 'floor', kind: 'box', position: [0, -.5, 0], size: [24, 1, 24], color: '#456789', solid: true },
    { op: 'upsert', id: 'discarded', kind: 'box' },
  ] }, { runId: 'isolated-real-run' });
  commitConstruction(project, first, { scaffold: true });
  const final = applyConstruction(first, { step: '地标与障碍', baseRevision: 1, ops: [
    { op: 'remove', id: 'discarded' },
    { op: 'upsert', id: 'tower', kind: 'cone', position: [4, 2, 0], size: [2, 4, 2], rotation: [0, 30, 0], color: '#71c6a8', solid: true },
    { op: 'upsert', id: 'orb', kind: 'sphere', position: [-3, 1.5, 0], size: [2, 3, 2], color: '#edbc57', solid: false },
    { op: 'upsert', id: 'pillar', kind: 'cylinder', position: [0, 2, -5], size: [2, 4, 2], color: '#ad78cf', solid: true },
  ] }, { runId: 'isolated-real-run' });
  commitConstruction(project, final);
  const main = project.read('main.gd') + runtimeTests;
  assert.deepEqual(project.write('main.gd', main), []);
  let built;
  try {
    await t.test('native check confirms the managed scene actually loaded, not only a textual reference', async () => {
      const checked = await project.check(); report.check = checked;
      assert.equal(checked.ok, true, JSON.stringify(checked));
      assert.ok(checked.construction.some(row => row.revision === 2 && row.objectCount === 4 && row.source_path === 'res://scenes/construction.json'));
      built = await project.build({ sourceRevision: checked.sourceRevision }); report.build = built;
      assert.equal(built.ok, true, JSON.stringify(built));
    });
    await t.test('the immutable pack includes the exact final scene JSON and native instancing script', () => {
      assert.ok(built?.ok);
      const { files } = readPck(fs.readFileSync(built.path));
      assert.deepEqual(JSON.parse(files.get('scenes/construction.json')), final);
      assert.ok(files.has('scenes/construction.tscn') || files.has('scenes/construction.tscn.remap'));
      assert.ok(files.has('addons/ugc/construction_scene.gd') || files.has('addons/ugc/construction_scene.gdc') || files.has('addons/ugc/construction_scene.gd.remap'));
      assert.equal(JSON.parse(files.get('addons/ugc/build.json')).sourceRevision, built.sourceRevision);
    });
    await t.test('pack-only native runtime instantiates all four actual meshes, colors and collisions', async () => {
      assert.ok(built?.ok);
      const empty = path.join(isolated, 'pack-only'); fs.mkdirSync(empty);
      const result = await runner(['--headless', '--path', empty, '--main-pack', built.path, '--audio-driver', 'Dummy', '--', '--ugc-test'], { cwd: empty, timeoutMs: 30000 });
      const native = tagged(result.stdout, 'ugc-test'); report.native = native;
      assert.equal(result.code, 0, result.stdout + result.stderr);
      assert.equal(result.timedOut, false);
      assert.ok(native?.loaded && native?.has_test, result.stdout + result.stderr);
      assert.deepEqual(native.errors, []);
      assert.equal(native.checks.length, 35);
      assert.equal(native.checks.every(check => check.ok), true, JSON.stringify(native.checks));
      assert.equal(fs.existsSync(path.join(empty, 'scenes')), false, 'no loose scene can supply the game geometry');
    });
    await t.test('removing the managed instance at runtime fails the platform check despite a valid tscn reference', async () => {
      assert.deepEqual(project.write('main.gd', 'extends Node3D\nfunc _ready() -> void:\n\tget_node("Construction").queue_free()\n'), []);
      const missing = await project.check(); report.missingScene = missing;
      assert.equal(missing.loaded, true);
      assert.equal(missing.ok, false);
      assert.match(missing.errors.map(e => e.message).join('\n'), /没有加载当前搭建的关卡/);
      assert.deepEqual(missing.construction, []);
      assert.equal(project.latestBuild.buildId, built.buildId, 'bad draft must not replace the last valid pack');
      project.write('main.gd', main);
    });
  } finally {
    report.finishedAt = new Date().toISOString();
    fs.writeFileSync(path.join(isolated, 'report.json'), JSON.stringify(report, null, 2));
    fs.writeFileSync(path.join(artifactRoot, 'construction-pack-latest.json'), JSON.stringify({ report: path.join(isolated, 'report.json') }, null, 2));
    console.log('Construction pack evidence: ' + path.join(isolated, 'report.json'));
  }
});
