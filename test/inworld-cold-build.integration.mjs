// Explicit native integration acceptance. Not included in the fast *.test.mjs suite.
// Run: node --test test/inworld-cold-build.integration.mjs
import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import { fileURLToPath } from 'node:url';
import { GodotProject, runGodot, tagged } from '../server/gproject.mjs';
import { readPck } from '../server/pck.mjs';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const sha = bytes => crypto.createHash('sha256').update(bytes).digest('hex');
const source = `extends Control

func auto_test() -> void:
	var portrait = load("res://addons/ugc/pixel-engineer.png")
	var font = load("res://addons/ugc/font.ttf")
	UGC.check(portrait is Texture2D and portrait.get_width() > 100, "pack portrait texture loads with real pixels")
	UGC.check(font is FontFile, "pack custom font loads as FontFile")
	UGC.show_crew = true
	UGC.crew({"agent": "M", "name": "Cold fixture", "state": "building", "file": "main.gd"})
	await get_tree().process_frame
	var actors = get_tree().get_nodes_in_group("ugc_crew_actor")
	UGC.check(actors.size() == 1, "platform plugin creates actual build fairy node")
	if actors.size() == 1:
		var actor = actors[0]
		UGC.check(actor.has_method("assist"), "packaged fairy script is the crew actor")
		UGC.check(actor.get("_font") == font, "actor uses packaged custom font rather than fallback")
		UGC.check(not actor.is_processing_input() and not actor.is_processing_unhandled_input(), "creative actor has no input handlers")
		actor.set_work({"state": "paused"})
		UGC.check(not actor.walking and actor.particles.is_empty(), "pause stops work and particles")
	UGC.show_crew = false
	await get_tree().process_frame
	UGC.check(get_tree().get_nodes_in_group("ugc_crew_actor").is_empty(), "leaving creation mode removes actors")
	var manifest = JSON.parse_string(FileAccess.get_file_as_string("res://addons/ugc/build.json"))
	UGC.check(manifest is Dictionary and str(manifest.get("buildId", "")).length() == 32, "actual pack contains immutable build manifest")
	UGC.check(manifest is Dictionary and str(manifest.get("sourceRevision", "")).length() == 64, "actual pack contains source revision")
`;

test('fresh GodotProject imports, exports and executes its packaged crew resources with correct platform versioning', { timeout: 240000 }, async t => {
  const artifactRoot = path.join(root, 'artifacts', 'inworld');
  fs.mkdirSync(artifactRoot, { recursive: true });
  const isolated = fs.mkdtempSync(path.join(artifactRoot, 'cold-build-'));
  const template = path.join(isolated, 'template');
  // Freeze the real platform template. This test never changes gp_template or user games.
  fs.cpSync(path.join(root, 'gp_template'), template, { recursive: true,
    filter: p => !/(?:^|[\\/])(?:\.godot|build|generated)(?:[\\/]|$)|\.(?:import|uid)$/.test(p) });
  const calls = [], report = { isolated, calls, startedAt: new Date().toISOString() };
  const runner = async (args, opts) => {
    const result = await runGodot(args, opts);
    const number = calls.length + 1;
    fs.writeFileSync(path.join(isolated, `process-${number}.log`), result.stdout + '\n' + result.stderr);
    calls.push({ args, code: result.code, timedOut: !!result.timedOut, aborted: !!result.aborted,
      errors: (result.stdout + '\n' + result.stderr).split(/\r?\n/).filter(line => /^(?:SCRIPT |USER )?ERROR:/.test(line)) });
    return result;
  };
  const project = new GodotProject('cold-crew', { root: path.join(isolated, 'projects'), template, runGodot: runner }).create({ title: 'ColdCrew_' + path.basename(isolated) });
  const runDir = path.join(isolated, 'pack-only');
  fs.mkdirSync(runDir);
  assert.deepEqual(project.write('main.gd', source), []);
  assert.equal(fs.existsSync(path.join(project.dir, '.godot')), false, 'test starts without an imported cache');
  let first, second;
  try {
    await t.test('a direct first build succeeds, including the narrowly confirmed font-first-import retry', async () => {
      first = await project.build();
      report.first = first;
      assert.equal(first.ok, true, JSON.stringify(first));
      assert.equal(first.full, true);
      assert.equal(first.sourceRevision, project.revision());
      assert.ok(calls.some(call => call.args.includes('--import')));
      assert.ok(calls.some(call => call.args.includes('--export-pack')));
      assert.equal(calls.some(call => call.code !== 0 || call.timedOut || call.aborted), false);
      assert.equal(calls.some(call => call.errors.some(line => /SCRIPT ERROR:|Parse Error:|pixel-engineer/.test(line))), false);
    });
    await t.test('exported pack contains texture and font remaps plus their imported bytes', () => {
      assert.ok(first?.ok, 'first build required');
      const { files } = readPck(fs.readFileSync(first.path));
      for (const resource of ['pixel-engineer.png', 'font.ttf']) {
        const remap = files.get(`addons/ugc/${resource}.import`)?.toString();
        assert.ok(remap, `${resource} import metadata is inside immutable pack`);
        const targets = [...remap.matchAll(/(?:path|path\.[^=]+)="res:\/\/([^"\r\n]+)"/g)].map(match => match[1]);
        assert.ok(targets.length, `${resource} has imported data paths`);
        for (const target of targets) assert.ok(files.get(target)?.length > 100, `${target} imported bytes exist`);
      }
      const manifest = JSON.parse(files.get('addons/ugc/build.json'));
      assert.deepEqual(manifest, { buildId: first.buildId, sourceRevision: first.sourceRevision, version: first.version });
      assert.equal(sha(fs.readFileSync(first.path)), first.contentHash);
      report.packEntries = [...files.keys()].filter(name => /addons\/ugc|font\.ttf|pixel-engineer/.test(name));
    });
    await t.test('native engine executes the immutable pack from an empty folder, not the source tree', async () => {
      assert.ok(first?.ok, 'first build required');
      const result = await runner(['--headless', '--path', runDir, '--main-pack', first.path, '--audio-driver', 'Dummy', '--', '--ugc-test'], { cwd: runDir, timeoutMs: 30000 });
      const native = tagged(result.stdout, 'ugc-test');
      report.native = native;
      assert.equal(result.code, 0, result.stdout + result.stderr);
      assert.equal(result.timedOut, false);
      assert.ok(native?.loaded && native?.has_test, result.stdout + result.stderr);
      assert.deepEqual(native.errors, []);
      assert.equal(native.checks.length, 10);
      assert.equal(native.checks.every(check => check.ok), true, JSON.stringify(native.checks));
      assert.equal(fs.existsSync(path.join(runDir, 'addons')), false, 'empty run directory cannot supply resources outside the pack');
    });
    await t.test('platform-only source and asset changes invalidate revision and force a fresh full export', async () => {
      assert.ok(first?.ok, 'first build required');
      const actorPath = path.join(template, 'addons/ugc/crew_actor.gd');
      fs.appendFileSync(actorPath, '\n# Isolated platform revision probe.\n');
      const sourceChanged = project.revision();
      assert.notEqual(sourceChanged, first.sourceRevision);
      fs.copyFileSync(path.join(template, 'addons/ugc/pixel-engineer.png'), path.join(template, 'addons/ugc/cold-extra.png'));
      const assetChanged = project.revision();
      assert.notEqual(assetChanged, sourceChanged);
      second = await project.build({ sourceRevision: assetChanged });
      report.second = second;
      assert.equal(second.ok, true, JSON.stringify(second));
      assert.equal(second.full, true);
      assert.equal(second.sourceRevision, assetChanged);
      assert.notEqual(second.buildId, first.buildId);
      assert.equal(second.version, first.version + 1);
      const { files } = readPck(fs.readFileSync(second.path));
      assert.ok(files.has('addons/ugc/cold-extra.png.import'), 'new platform image was imported and exported');
      assert.equal(JSON.parse(files.get('addons/ugc/build.json')).sourceRevision, assetChanged);
      assert.equal(sha(fs.readFileSync(first.path)), first.contentHash, 'the original artifact remains immutable');
      assert.equal(project.latestBuild.buildId, second.buildId);
      assert.equal(project.getBuild(first.buildId).contentHash, first.contentHash);
    });
  } finally {
    report.finishedAt = new Date().toISOString();
    fs.writeFileSync(path.join(isolated, 'report.json'), JSON.stringify(report, null, 2));
    fs.writeFileSync(path.join(artifactRoot, 'cold-build-latest.json'), JSON.stringify({ report: path.join(isolated, 'report.json'), first: first?.buildId, second: second?.buildId }, null, 2));
    console.log('Cold build evidence: ' + path.join(isolated, 'report.json'));
  }
});
