import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import crypto from 'node:crypto';
import { GodotProject, safePath } from '../gproject.mjs';
import { readPck, writePck } from '../pck.mjs';

const hash = value => crypto.createHash('sha256').update(value).digest('hex');
const success = (stdout = '') => ({ code: 0, stdout, stderr: '', timedOut: false });
const deferred = () => { let resolve; const promise = new Promise(r => { resolve = r; }); return { promise, resolve }; };
const report = (tag, value) => success('[' + tag + '] ' + JSON.stringify(value));
const checkReport = () => ({ loaded: true, errors: [] });
const testReport = () => ({ loaded: true, errors: [], checks: [{ what: 'player can move', ok: true }], has_test: true });
const fontImportErrors = "ERROR: No loader found for resource: res://addons/ugc/font.ttf (expected type: unknown)\r\n   at: _load (core/io/resource_loader.cpp:332)\r\nERROR: Error loading custom project font 'res://addons/ugc/font.ttf'\r\n   at: initialize_theme (scene/theme/theme_db.cpp:84)\r\n";

function fontImportCache(project, contents = 'font-cache') {
  const resource = '.godot/imported/font.ttf-' + 'a'.repeat(32) + '.fontdata';
  fs.mkdirSync(path.dirname(path.join(project.dir, resource)), { recursive: true });
  fs.writeFileSync(path.join(project.dir, resource), contents);
  fs.writeFileSync(path.join(project.dir, 'addons/ugc/font.ttf.import'), '[remap]\r\npath="res://' + resource + '"\r\n[deps]\r\nsource_file="res://addons/ugc/font.ttf"\r\n');
}

function fixture(t) {
  const temporary = fs.mkdtempSync(path.join(os.tmpdir(), 'ugc-workflow-'));
  const root = path.join(temporary, 'projects'), template = path.join(temporary, 'template');
  const write = (rel, value) => {
    const file = path.join(template, rel);
    fs.mkdirSync(path.dirname(file), { recursive: true });
    fs.writeFileSync(file, value);
  };
  write('project.godot', 'config_version=5\n[application]\nconfig/name="Fixture"\nrun/main_scene="res://main.tscn"\n[display]\nwindow/size/viewport_width=1280\nwindow/size/viewport_height=720\n');
  write('main.gd', 'extends Node\n');
  write('main.tscn', '[gd_scene format=3]\n[node name="Main" type="Node"]\n');
  write('addons/ugc/ugc.gd', 'extends Node\n');
  write('addons/ugc/font.ttf', Buffer.from('fixture-font'));
  write('export_presets.cfg', '[preset.0]\nname="Web"\n');
  const calls = [];
  let intercept = null;
  const runner = async (args, opts) => {
    calls.push(args);
    const override = await intercept?.(args, opts);
    if (override !== undefined) return override;
    if (args.includes('--import')) fs.mkdirSync(path.join(opts.cwd, '.godot', 'imported'), { recursive: true });
    if (args.includes('--export-pack')) {
      const files = new Map();
      const collect = (dir, prefix = '') => {
        for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
          const rel = prefix + entry.name;
          if (/^(?:build|\.godot|generated)(?:\/|$)/.test(rel)) continue;
          if (entry.isDirectory()) collect(path.join(dir, entry.name), rel + '/');
          else files.set(rel, fs.readFileSync(path.join(dir, entry.name)));
        }
      };
      collect(opts.cwd);
      fs.writeFileSync(path.join(opts.cwd, args.at(-1)), writePck({ version: { format: 3, major: 4, minor: 7, patch: 2 }, files }));
    }
    if (args.includes('--ugc-check')) return report('ugc-check', checkReport());
    if (args.includes('--ugc-test')) return report('ugc-test', testReport());
    return success();
  };
  const project = new GodotProject('fixture', { root, template, runGodot: runner }).create();
  const another = () => new GodotProject('fixture', { root, template, runGodot: runner });
  t.after(() => {
    // Only this test's own resolved mkdtemp directory is eligible for recursive cleanup.
    assert.ok(path.resolve(temporary).startsWith(path.resolve(os.tmpdir()) + path.sep));
    assert.match(path.basename(temporary), /^ugc-workflow-/);
    fs.rmSync(temporary, { recursive: true, force: true });
  });
  return { project, another, temporary, template, calls, writeTemplate: write, intercept: fn => { intercept = fn; } };
}

test('shutdown resource leak lines do not fail a run that loaded cleanly, real errors still do', async t => {
  const { project, intercept } = fixture(t);
  const leak = '\nWARNING: 2 ObjectDB instances were leaked at exit (run with `--verbose` for details).\r\n   at: cleanup (core/object/object.cpp:2536)\r\nERROR: 1 resources still in use at exit (run with --verbose for details).\r\n   at: clear (core/io/resource.cpp:822)\r\n';
  let extra = leak;
  intercept(args => {
    if (args.includes('--ugc-check')) return success('[ugc-check] ' + JSON.stringify(checkReport()) + extra);
    if (args.includes('--ugc-test')) return success('[ugc-test] ' + JSON.stringify(testReport()) + extra);
  });
  const check = await project.check(), selfTest = await project.selfTest({ shot: false });
  assert.equal(check.ok, true, JSON.stringify(check.errors)); assert.equal(selfTest.ok, true, JSON.stringify(selfTest.errors));
  extra = leak + 'ERROR: Something else broke during the run.\r\n   at: run (core/os/main_loop.cpp:1)\r\n';
  assert.equal((await project.check()).ok, false);
});

test('locks serialize different instances, allow nested work and recover after rejection', async t => {
  const { project, another } = fixture(t);
  const entered = deferred(), release = deferred(), order = [];
  const first = project.withLock(async () => {
    order.push('first'); entered.resolve();
    await another().withLock(async () => { order.push('nested'); });
    await release.promise;
    order.push('released');
  });
  await entered.promise;
  const second = another().withLock(() => order.push('second'));
  await new Promise(resolve => setImmediate(resolve));
  assert.deepEqual(order, ['first', 'nested']);
  release.resolve();
  await Promise.all([first, second]);
  assert.deepEqual(order, ['first', 'nested', 'released', 'second']);
  await assert.rejects(project.withLock(() => { throw new Error('intentional'); }), /intentional/);
  assert.equal(await another().withLock(() => 7), 7);
});

test('async descendants from an expired lock cannot bypass the next owner', async t => {
  const { project, another } = fixture(t);
  const enterDetached = deferred(), ownerEntered = deferred(), releaseOwner = deferred();
  let detached;
  const order = [];
  await project.withLock(() => {
    detached = enterDetached.promise.then(() => another().withLock(() => order.push('detached')));
  });
  const owner = another().withLock(async () => { ownerEntered.resolve(); await releaseOwner.promise; order.push('owner'); });
  await ownerEntered.promise;
  enterDetached.resolve();
  await new Promise(resolve => setImmediate(resolve));
  assert.deepEqual(order, []);
  releaseOwner.resolve();
  await Promise.all([owner, detached]);
  assert.deepEqual(order, ['owner', 'detached']);
});

test('concurrent edit-check-build transactions produce separate exact revision artifacts', async t => {
  const { project, another } = fixture(t);
  const transact = (p, score) => p.withLock(async () => {
    p.write('main.gd', 'extends Node\nvar score = ' + score + '\n');
    const checked = await p.check();
    assert.equal(checked.ok, true);
    const built = await p.build({ sourceRevision: checked.sourceRevision });
    assert.equal(built.ok, true, built.error);
    return built;
  });
  const [first, second] = await Promise.all([transact(project, 1), transact(another(), 2)]);
  assert.equal(second.version, first.version + 1);
  assert.notEqual(first.sourceRevision, second.sourceRevision);
  for (const [index, artifact] of [first, second].entries()) {
    const packed = readPck(fs.readFileSync(artifact.path));
    assert.match(packed.files.get('main.gd').toString(), new RegExp('score = ' + (index + 1)));
    assert.equal(JSON.parse(packed.files.get('addons/ugc/build.json')).sourceRevision, artifact.sourceRevision);
  }
});

test('revision follows source and binary contents and platform template, ignoring generated output', t => {
  const { project, writeTemplate } = fixture(t);
  project.syncPlatform();
  const initial = project.revision();
  assert.match(initial, /^[a-f0-9]{64}$/);
  for (const rel of ['build/noise.json', '.godot/imported/random.bin', 'generated/tmp.gd', 'main.gd.uid']) {
    const file = path.join(project.dir, rel);
    fs.mkdirSync(path.dirname(file), { recursive: true }); fs.writeFileSync(file, 'generated');
  }
  assert.equal(project.revision(), initial);
  assert.deepEqual(project.write('main.gd', 'extends Node\nvar score = 1\n'), []);
  const source = project.revision();
  assert.notEqual(source, initial);
  project.writeAsset('assets/hero.png', Buffer.from([1, 2, 3]));
  const asset = project.revision();
  assert.notEqual(asset, source);
  fs.writeFileSync(path.join(project.dir, 'assets/hero.png'), Buffer.from([1, 2, 4]));
  assert.notEqual(project.revision(), asset, 'same-length asset edits must change identity');
  const beforePlugin = project.revision();
  writeTemplate('addons/ugc/ugc.gd', 'extends Node\nvar platform_version = 2\n');
  assert.notEqual(project.revision(), beforePlugin);
  const afterPlugin = project.revision();
  fs.writeFileSync(path.join(project.dir, 'addons/ugc/ugc.gd'), 'tampered local plugin');
  assert.equal(project.revision(), afterPlugin, 'template is the authoritative platform input');
  project.syncPlatform();
  assert.match(fs.readFileSync(path.join(project.dir, 'addons/ugc/ugc.gd'), 'utf8'), /platform_version = 2/);
});

test('builds preserve prior bytes and embed exact identity, including direct text edits and deletes', async t => {
  const { project, another, calls } = fixture(t);
  const first = await project.build();
  assert.equal(first.ok, true, first.error);
  assert.equal(first.full, true);
  assert.equal(first.sourceRevision, project.revision());
  const bytes = fs.readFileSync(first.path);
  const manifest = JSON.parse(readPck(bytes).files.get('addons/ugc/build.json'));
  assert.deepEqual(manifest, { buildId: first.buildId, sourceRevision: first.sourceRevision, version: first.version });
  assert.equal(first.contentHash, hash(bytes));
  fs.writeFileSync(path.join(project.dir, 'main.gd'), 'extends Node\nvar next = 2\n');
  const second = await another().build();
  assert.equal(second.ok, true, second.error);
  assert.equal(second.full, false);
  assert.equal(second.version, first.version + 1);
  assert.notEqual(second.buildId, first.buildId);
  assert.notEqual(second.sourceRevision, first.sourceRevision);
  assert.deepEqual(fs.readFileSync(first.path), bytes);
  assert.equal(readPck(fs.readFileSync(second.path)).files.get('main.gd').toString(), project.read('main.gd'));
  assert.equal(calls.filter(a => a.includes('--export-pack')).length, 1);
  assert.deepEqual(project.latestBuild, project.getBuild(second.buildId));
  assert.equal(project.state.lastBuild.buildId, second.buildId);
  assert.deepEqual(fs.readFileSync(project.pckPath), fs.readFileSync(second.path));
  fs.unlinkSync(path.join(project.dir, 'main.gd'));
  const third = await project.build();
  assert.equal(third.ok, true, third.error);
  assert.equal(readPck(fs.readFileSync(third.path)).files.has('main.gd'), false);
  for (const invalid of ['../game', '', first.buildId.toUpperCase(), first.buildId + '.pck', 'f'.repeat(32)]) assert.equal(project.getBuild(invalid), null);
  fs.appendFileSync(first.path, 'tamper');
  assert.equal(project.getBuild(first.buildId), null, 'metadata must not authenticate modified artifact bytes');
});

test('binary changes require a fresh import/export, including changes outside writeAsset', async t => {
  const { project, calls } = fixture(t);
  project.writeAsset('assets/sound.wav', Buffer.from('first'));
  const first = await project.build();
  assert.equal(first.ok, true);
  const importedBefore = calls.filter(a => a.includes('--import')).length;
  fs.writeFileSync(path.join(project.dir, 'assets/sound.wav'), 'other');
  const second = await project.build();
  assert.equal(second.ok, true, second.error);
  assert.equal(second.full, true);
  assert.equal(calls.filter(a => a.includes('--import')).length, importedBefore + 1);
  assert.equal(readPck(fs.readFileSync(second.path)).files.get('assets/sound.wav').toString(), 'other');
});

test('failed import does not clear dirty state, run check/test/export or publish a build', async t => {
  const { project, calls, intercept } = fixture(t);
  intercept(args => args.includes('--import') ? { code: 2, stdout: '', stderr: 'import failed', timedOut: false } : undefined);
  for (const run of [() => project.importIfNeeded(), () => project.check(), () => project.selfTest({ shot: false }), () => project.build()]) {
    const result = await run();
    assert.equal(result.ok, false);
    assert.equal(project.state.needsImport, true);
    assert.equal(project.state.version, 0);
    assert.equal(project.latestBuild, null);
  }
  assert.ok(calls.every(args => args.includes('--import')));
  await assert.rejects(project.ready(), /资源导入失败/);
});

test('missing imported cache re-dirties import state and an error line is a failure even with exit zero', async t => {
  const { project, intercept } = fixture(t);
  assert.equal((await project.importIfNeeded()).ok, true);
  fs.rmdirSync(path.join(project.dir, '.godot', 'imported'));
  intercept(args => args.includes('--import') ? { ...success(), stderr: 'ERROR: cannot import resource' } : undefined);
  assert.equal((await project.importIfNeeded()).ok, false);
  assert.equal(project.state.needsImport, true);
});

test('first-import platform font errors receive one clean confirmation retry after cache creation', async t => {
  const { project, intercept, calls } = fixture(t);
  let attempts = 0;
  intercept(args => {
    if (!args.includes('--import')) return;
    attempts++;
    if (attempts === 1) { fontImportCache(project); return { ...success(), stderr: fontImportErrors }; }
    return success();
  });
  const imported = await project.importIfNeeded();
  assert.equal(imported.ok, true);
  assert.equal(imported.retried, true);
  assert.equal(project.state.needsImport, false);
  assert.equal(attempts, 2);
  assert.equal((await project.importIfNeeded()).skipped, true);
  assert.equal(calls.length, 2);
});

test('font retry never masks extra errors, nonzero exit, timeout, absent or empty cache', async t => {
  for (const scenario of ['extra-error', 'nonzero', 'timeout', 'missing-cache', 'empty-cache', 'wrong-font']) {
    await t.test(scenario, async sub => {
      const { project, intercept, calls } = fixture(sub);
      intercept(args => {
        if (!args.includes('--import')) return;
        if (scenario !== 'missing-cache') fontImportCache(project, scenario === 'empty-cache' ? '' : 'font-cache');
        return { ...success(), code: scenario === 'nonzero' ? 1 : 0, timedOut: scenario === 'timeout',
          stderr: scenario === 'wrong-font' ? fontImportErrors.replaceAll('addons/ugc/font.ttf', 'assets/custom.ttf') : fontImportErrors + (scenario === 'extra-error' ? 'SCRIPT ERROR: Parse Error: invalid script\n' : '') };
      });
      const imported = await project.importIfNeeded();
      assert.equal(imported.ok, false);
      assert.equal(project.state.needsImport, true);
      assert.equal(calls.length, 1);
    });
  }
});

test('a repeated transient font error or nonzero confirmation still fails after exactly two imports', async t => {
  for (const repeated of [true, false]) {
    await t.test(repeated ? 'same error again' : 'confirmation process fails', async sub => {
      const { project, intercept, calls } = fixture(sub);
      intercept(args => {
        if (!args.includes('--import')) return;
        fontImportCache(project);
        return { ...success(), code: !repeated && calls.length === 2 ? 2 : 0, stderr: fontImportErrors };
      });
      assert.equal((await project.importIfNeeded()).ok, false);
      assert.equal(project.state.needsImport, true);
      assert.equal(calls.length, 2);
    });
  }
});

test('failed export cannot replace last successful artifact or increment version', async t => {
  const { project, intercept } = fixture(t);
  const first = await project.build();
  assert.equal(first.ok, true);
  const before = fs.readFileSync(project.pckPath);
  intercept(args => args.includes('--export-pack') ? { code: 3, stdout: '', stderr: 'export failed', timedOut: false } : undefined);
  project.writeAsset('assets/fail.png', Buffer.from('bad'));
  const failed = await project.build();
  assert.equal(failed.ok, false);
  assert.equal(project.state.needsExport, true);
  assert.equal(project.state.version, first.version);
  assert.equal(project.latestBuild.buildId, first.buildId);
  assert.deepEqual(fs.readFileSync(project.pckPath), before);
  assert.deepEqual(fs.readdirSync(path.dirname(first.path)).sort(), [first.buildId + '.json', first.buildId + '.pck'].sort());
});

test('source changes while export runs invalidate the artifact', async t => {
  const { project, intercept } = fixture(t);
  intercept(args => {
    if (args.includes('--export-pack')) fs.writeFileSync(path.join(project.dir, 'main.gd'), 'extends Node\nvar changed_during_export = true\n');
  });
  const result = await project.build();
  assert.equal(result.ok, false);
  assert.match(result.error, /构建期间/);
  assert.equal(project.state.version, 0);
  assert.equal(project.latestBuild, null);
});

test('check, self-test and build reject stale requested revisions and report actual identity', async t => {
  const { project, calls } = fixture(t);
  await project.importIfNeeded();
  const old = project.revision();
  project.write('main.gd', 'extends Node\nvar updated = true\n');
  const current = project.revision();
  const before = calls.length;
  for (const result of [await project.check({ sourceRevision: old }), await project.selfTest({ shot: false, sourceRevision: old }), await project.build({ sourceRevision: old })]) {
    assert.equal(result.ok, false);
    assert.equal(result.sourceRevision, current);
  }
  assert.equal(calls.length, before, 'mismatch must not run Godot against a different revision');
  assert.equal((await project.check({ sourceRevision: current })).ok, true);
  const tested = await project.selfTest({ shot: false, sourceRevision: current });
  assert.equal(tested.ok, true);
  assert.equal(tested.assertionCount, 1);
  assert.equal(tested.sourceRevision, current);
});

test('self-test requires at least one well formed passing assertion', async t => {
  const { project, intercept } = fixture(t);
  for (const checks of [[], [{ ok: true }], [{ what: 'empty state' }], [{ what: ' ', ok: true }], [{ what: 'loss condition', ok: false }], [{ what: 'valid', ok: true }, { what: 'invalid', ok: 'yes' }]]) {
    intercept(args => args.includes('--ugc-test') ? report('ugc-test', { ...testReport(), checks }) : undefined);
    const result = await project.selfTest({ shot: false });
    assert.equal(result.ok, false, JSON.stringify(checks));
  }
  intercept(args => args.includes('--ugc-test') ? report('ugc-test', testReport()) : undefined);
  assert.equal((await project.selfTest({ shot: false })).ok, true);
});

test('successful-looking reports cannot override nonzero exits, timeouts or changed source', async t => {
  const { project, intercept } = fixture(t);
  for (const tag of ['ugc-check', 'ugc-test']) {
    const run = () => tag === 'ugc-check' ? project.check() : project.selfTest({ shot: false });
    for (const failure of [{ code: 1 }, { timedOut: true }, { stderr: 'ERROR: platform failure' }]) {
      intercept(args => args.includes('--' + tag) ? { ...report(tag, { ...(tag === 'ugc-check' ? checkReport() : testReport()), errors: [{ kind: 'warning', file: 'main.gd', line: 1, message: 'warning only' }] }), ...failure } : undefined);
      assert.equal((await run()).ok, false, JSON.stringify(failure));
    }
    intercept(args => {
      if (!args.includes('--' + tag)) return;
      fs.appendFileSync(path.join(project.dir, 'main.gd'), '\n# external write');
      return report(tag, tag === 'ugc-check' ? checkReport() : testReport());
    });
    const changed = await run();
    assert.equal(changed.ok, false);
    assert.ok(changed.errors.some(e => /发生变化/.test(e.message)));
  }
});

test('Windows case and trailing-dot aliases cannot modify managed paths', t => {
  const { project } = fixture(t);
  for (const rel of ['ADDONS/UGC/x.gd', 'Addons/Ugc', 'BUILD/state.json', '.GODOT/x.gd', 'Generated/x.gd', 'build./x.gd', 'a/../main.gd', 'a/./main.gd']) assert.throws(() => safePath(rel), undefined, rel);
  assert.equal(project.remove('PROJECT.GODOT'), false);
  assert.throws(() => project.remove('ADDONS'), /平台插件/);
  assert.throws(() => project.write('ADDONS/UGC/ugc.gd', 'extends Node'));
});

test('directory deletion rejects an actual path outside the project, preserving its target', t => {
  const { project, temporary } = fixture(t);
  const outside = path.join(temporary, 'outside');
  fs.mkdirSync(outside); fs.writeFileSync(path.join(outside, 'keep.txt'), 'keep');
  const link = path.join(project.dir, 'linked');
  fs.symlinkSync(outside, link, process.platform === 'win32' ? 'junction' : 'dir');
  assert.throws(() => project.remove('linked'), /实际路径超出/);
  assert.throws(() => project.write('linked/overwrite.txt', 'no'), /实际路径超出/);
  assert.equal(fs.readFileSync(path.join(outside, 'keep.txt'), 'utf8'), 'keep');
  assert.equal(fs.existsSync(path.join(outside, 'overwrite.txt')), false);
  fs.unlinkSync(link);
});

test('pre-aborted project operations neither start a process nor change import/build state', async t => {
  const { project, calls } = fixture(t);
  const controller = new AbortController(); controller.abort(new Error('deadline'));
  const before = project.state;
  for (const method of ['importIfNeeded', 'build', 'check', 'selfTest', 'ready']) {
    await assert.rejects(project[method]({ signal: controller.signal }), { name: 'AbortError' });
  }
  assert.equal(calls.length, 0);
  assert.deepEqual(project.state, before);
  assert.equal(project.latestBuild, null);
});

test('operations cancelled while queued recheck the signal after acquiring the shared lock', async t => {
  const { project, another, calls } = fixture(t);
  const entered = deferred(), release = deferred();
  const owner = project.withLock(async () => { entered.resolve(); await release.promise; });
  await entered.promise;
  const controller = new AbortController(), before = project.state;
  const results = ['importIfNeeded', 'build', 'check', 'selfTest', 'ready'].map(method =>
    assert.rejects(another()[method]({ signal: controller.signal }), { name: 'AbortError' }));
  controller.abort(new Error('deadline in queue')); release.resolve();
  await Promise.all([owner, ...results]);
  assert.equal(calls.length, 0);
  assert.deepEqual(project.state, before);
  assert.equal(project.latestBuild, null);
});

test('an importer returning success after cancellation cannot clear needsImport', async t => {
  const { project, intercept } = fixture(t);
  const controller = new AbortController();
  intercept(args => { if (args.includes('--import')) controller.abort(); });
  await assert.rejects(project.importIfNeeded({ signal: controller.signal }), { name: 'AbortError' });
  assert.equal(project.state.needsImport, true);
});

test('cancelled export cannot publish an artifact or replace the last accepted build', async t => {
  const { project, intercept } = fixture(t);
  const original = await project.build(); assert.equal(original.ok, true);
  const before = project.state, bytes = fs.readFileSync(project.pckPath);
  const artifacts = fs.readdirSync(path.join(project.buildDir, 'builds')).sort();
  const controller = new AbortController();
  intercept(args => { if (args.includes('--export-pack')) controller.abort(new Error('late export')); });
  const result = await project.build({ full: true, signal: controller.signal });
  assert.equal(result.ok, false); assert.equal(result.aborted, true);
  assert.deepEqual(project.state, before);
  assert.equal(project.latestBuild.buildId, original.buildId);
  assert.deepEqual(fs.readFileSync(project.pckPath), bytes);
  assert.deepEqual(fs.readdirSync(path.join(project.buildDir, 'builds')).sort(), artifacts);
});

test('cancellation immediately before a fast patch commit preserves the previous artifact', async t => {
  const { project, calls } = fixture(t);
  const original = await project.build(); assert.equal(original.ok, true);
  project.write('main.gd', 'extends Node\nfunc changed(): return 2\n');
  const before = project.state, bytes = fs.readFileSync(project.pckPath), callCount = calls.length;
  const controller = new AbortController(), originalCache = project.writeClassCache.bind(project);
  project.writeClassCache = () => { const result = originalCache(); controller.abort(); return result; };
  const result = await project.build({ signal: controller.signal });
  assert.equal(result.ok, false); assert.equal(result.aborted, true);
  assert.equal(calls.length, callCount, 'this is the no-process incremental pack path');
  assert.deepEqual(project.state, before);
  assert.equal(project.latestBuild.buildId, original.buildId);
  assert.deepEqual(fs.readFileSync(project.pckPath), bytes);
  assert.equal(fs.readdirSync(path.join(project.buildDir, 'builds')).length, 2);
});

test('late successful check and self-test results cannot pass after cancellation', async t => {
  for (const [method, flag] of [['check', '--ugc-check'], ['selfTest', '--ugc-test']]) {
    await t.test(method, async t => {
      const { project, intercept } = fixture(t);
      await project.ready();
      const controller = new AbortController();
      intercept(args => { if (args.includes(flag)) controller.abort(); });
      await assert.rejects(project[method]({ signal: controller.signal, shot: false }), { name: 'AbortError' });
      assert.equal(project.latestBuild, null);
    });
  }
});
