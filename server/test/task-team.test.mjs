import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { runTaskBatch, DELEGATE_TASKS_TOOL } from '../task-team.mjs';
import { GodotProject } from '../gproject.mjs';

class MemoryProject {
  constructor(files = {}) { this.files = { ...files }; this.state = { revision: 0 }; this.busy = Promise.resolve(); this.failPath = ''; this.writeHook = null; }
  sources() { return { ...this.files }; }
  list() { return Object.keys(this.files).map(path => ({ path })); }
  revision() { return JSON.stringify(this.files); }
  withLock(fn) { const run = this.busy.then(fn, fn); this.busy = run.catch(() => {}); return run; }
  write(p, content) {
    if (p === this.failPath) return ['injected write failure'];
    this.files[p] = content; this.state.revision++; this.writeHook?.(p);
    return [];
  }
  remove(p) { delete this.files[p]; this.state.revision++; return true; }
}
const task = (id, extra = {}) => ({ id, title: id, role: 'gameplay', files: [id + '.gd'], depends_on: [], prompt: 'Implement ' + id, acceptance: ['implemented'], ...extra });
const gate = () => { let resolve; const promise = new Promise(r => { resolve = r; }); return { promise, resolve }; };
async function submit(ctx, passed = true) {
  return ctx.exec('submit_task', { summary: 'Ready for coordinator validation', acceptance: ctx.task.acceptance.map(criterion => ({ criterion, evidence: ctx.task.files.join(', ') || 'Reviewed project snapshot', passed })) });
}
async function writeAndSubmit(ctx) {
  const r = await ctx.exec('write_file', { path: ctx.task.files[0], content: 'extends RefCounted\n' });
  assert.equal(r.ok, true, r.error);
  assert.equal((await submit(ctx)).ok, true);
}
function setup(t, files = {}) {
  const artifactDir = fs.mkdtempSync(path.join(os.tmpdir(), 'ugc-team-test-'));
  t.after(() => fs.rmSync(artifactDir, { recursive: true, force: true }));
  return { project: new MemoryProject(files), artifactDir };
}

test('delegate schema exposes bounded tasks and exact ownership', () => {
  assert.equal(DELEGATE_TASKS_TOOL.name, 'delegate_tasks');
  assert.equal(DELEGATE_TASKS_TOOL.input_schema.properties.tasks.maxItems, 2);
});

test('independent workers really overlap and candidates stay private until submission', async t => {
  const env = setup(t), both = gate();
  let active = 0, peak = 0, starts = 0;
  const events = [];
  const out = await runTaskBatch({ ...env, tasks: [task('a'), task('b')], onTask: e => events.push(e), runWorker: async ctx => {
    active++; peak = Math.max(peak, active);
    await ctx.exec('write_file', { path: ctx.task.files[0], content: 'extends Node\n' });
    assert.deepEqual(env.project.files, {});
    if (++starts === 2) both.resolve();
    await both.promise;
    await submit(ctx); active--;
  } });
  assert.equal(out.ok, true); assert.equal(peak, 2);
  assert.deepEqual(out.changed.sort(), ['a.gd', 'b.gd']);
  assert.ok(out.tasks.every(r => r.status === 'applied' && r.verified === false));
  assert.ok(events.some(e => e.status === 'queued')); assert.ok(events.some(e => e.status === 'running'));
  assert.ok(events.every(e => !('prompt' in e) && !('candidate' in e)));
  assert.ok(out.tasks.every(r => fs.existsSync(path.join(env.artifactDir, r.artifact))));
});

test('dependencies wait for applied predecessors and receive their snapshot and delivery', async t => {
  const env = setup(t), order = [];
  const out = await runTaskBatch({ ...env, tasks: [task('b', { depends_on: ['a'] }), task('a')], runWorker: async ctx => {
    order.push(ctx.task.id);
    if (ctx.task.id === 'b') {
      assert.equal(ctx.projectSnapshot['a.gd'], 'extends RefCounted\n');
      assert.equal(ctx.dependencies[0].id, 'a');
      assert.equal(ctx.dependencies[0].status, 'applied');
      assert.ok(ctx.dependencies[0].submission.summary);
    }
    await writeAndSubmit(ctx);
  } });
  assert.equal(out.ok, true); assert.deepEqual(order, ['a', 'b']);
});

test('rejects same-file ownership across casing and slash spelling before starting', async t => {
  const env = setup(t); let called = false;
  const out = await runTaskBatch({ ...env, tasks: [task('a', { files: ['res://Scripts/Foo.gd'] }), task('b', { files: ['scripts\\foo.GD'] })], runWorker: async () => { called = true; } });
  assert.equal(out.ok, false); assert.match(out.errors[0].error, /归属冲突/); assert.equal(called, false);
});

test('normalizes existing case and patch candidates without duplicate disk files', async t => {
  const env = setup(t, { 'Scripts/Foo.gd': 'extends Node\nvar x = 1\n' });
  const out = await runTaskBatch({ ...env, tasks: [task('a', { files: ['scripts/foo.GD'] })], runWorker: async ctx => {
    assert.equal(ctx.task.files[0], 'Scripts/Foo.gd');
    assert.equal((await ctx.exec('patch_file', { path: 'SCRIPTS/FOO.gd', old: 'x = 1', new: 'x = 2' })).ok, true);
    await submit(ctx);
  } });
  assert.equal(out.ok, true); assert.deepEqual(Object.keys(env.project.files), ['Scripts/Foo.gd']);
  assert.match(env.project.files['Scripts/Foo.gd'], /x = 2/);
});

test('rejects stale candidate when target changed since task started', async t => {
  const env = setup(t, { 'a.gd': 'extends Node\n' });
  const out = await runTaskBatch({ ...env, tasks: [task('a')], runWorker: async ctx => {
    await ctx.exec('write_file', { path: 'a.gd', content: 'extends Node2D\n' });
    await env.project.withLock(() => env.project.write('a.gd', 'extends Control\n'));
    await submit(ctx);
  } });
  assert.equal(out.ok, false); assert.equal(out.tasks[0].status, 'failed');
  assert.match(out.errors[0].error, /基线冲突/); assert.equal(env.project.files['a.gd'], 'extends Control\n');
  const saved = JSON.parse(fs.readFileSync(path.join(env.artifactDir, out.tasks[0].artifact), 'utf8'));
  assert.equal(saved.candidate['a.gd'], 'extends Node2D\n');
  assert.equal(saved.baseline['a.gd'], 'extends Node\n');
});

test('one failure preserves independent successful work', async t => {
  const env = setup(t), started = [];
  const out = await runTaskBatch({ ...env, tasks: [task('bad'), task('good')], runWorker: async ctx => {
    started.push(ctx.task.id);
    if (ctx.task.id === 'bad') { await ctx.exec('write_file', { path: 'bad.gd', content: 'extends Node\n' }); throw new Error('worker failed'); }
    await writeAndSubmit(ctx);
  } });
  assert.equal(out.ok, false);
  assert.equal(out.tasks.find(t => t.id === 'bad').status, 'failed');
  assert.deepEqual(started.sort(), ['bad', 'good']);
  assert.deepEqual(Object.keys(env.project.files), ['good.gd']);
});

test('failure blocks a dependent without starting it', async t => {
  const env = setup(t), started = [];
  const out = await runTaskBatch({ ...env, tasks: [task('bad'), task('dependent', { depends_on: ['bad'] })], runWorker: async ctx => {
    started.push(ctx.task.id); throw new Error('worker failed');
  } });
  assert.deepEqual(started, ['bad']); assert.equal(out.tasks[1].status, 'blocked');
});

test('cancelled worker cannot merge or perform a late tool write even when it ignores signal', async t => {
  const env = setup(t), ac = new AbortController(), started = gate(), late = gate();
  let lateResult;
  const run = runTaskBatch({ ...env, tasks: [task('a'), task('b', { depends_on: ['a'] })], signal: ac.signal, runWorker: async ctx => {
    await ctx.exec('write_file', { path: 'a.gd', content: 'extends Node\n' }); started.resolve();
    await late.promise;
    lateResult = await ctx.exec('write_file', { path: 'a.gd', content: 'extends Node2D\n' });
  } });
  await started.promise; ac.abort(new Error('user cancelled'));
  const out = await run; late.resolve(); await new Promise(r => setImmediate(r));
  assert.ok(out.tasks.every(r => r.status === 'cancelled'));
  assert.deepEqual(env.project.files, {}); assert.ok(lateResult.error);
});

test('timeout returns even if worker ignores cancellation', async t => {
  const env = setup(t);
  const out = await runTaskBatch({ ...env, tasks: [task('a')], timeoutMs: 15, runWorker: async () => new Promise(() => {}) });
  assert.equal(out.tasks[0].status, 'cancelled'); assert.match(out.tasks[0].error, /超时/);
});

test('cancel before start runs no worker and changes nothing', async t => {
  const env = setup(t), ac = new AbortController(); ac.abort();
  const out = await runTaskBatch({ ...env, tasks: [task('a')], signal: ac.signal, runWorker: async () => { assert.fail('must not start'); } });
  assert.equal(out.tasks[0].status, 'cancelled'); assert.deepEqual(env.project.files, {});
});

test('late cancellation while waiting for commit lock prevents merge', async t => {
  const env = setup(t), ac = new AbortController(), lockHeld = gate(), releaseLock = gate();
  let holding;
  const out = await runTaskBatch({ ...env, tasks: [task('a')], signal: ac.signal, runWorker: async ctx => {
    await writeAndSubmit(ctx);
    holding = env.project.withLock(async () => { lockHeld.resolve(); await releaseLock.promise; });
    await lockHeld.promise; setImmediate(() => ac.abort(new Error('cancel before merge')));
  } });
  assert.equal(out.tasks[0].status, 'cancelled'); releaseLock.resolve(); await holding; await env.project.busy;
  assert.deepEqual(env.project.files, {});
});

test('atomic rollback restores earlier writes and state after a later file fails', async t => {
  const env = setup(t, { 'a.gd': 'extends Node\n' }); env.project.failPath = 'b.gd';
  const out = await runTaskBatch({ ...env, tasks: [task('a', { files: ['a.gd', 'b.gd'] })], runWorker: async ctx => {
    await ctx.exec('write_file', { path: 'a.gd', content: 'extends Node2D\n' });
    await ctx.exec('write_file', { path: 'b.gd', content: 'extends Node\n' });
    await submit(ctx);
  } });
  assert.equal(out.tasks[0].status, 'failed'); assert.deepEqual(env.project.files, { 'a.gd': 'extends Node\n' });
  assert.deepEqual(env.project.state, { revision: 0 });
});

test('cancellation synchronously triggered during write rolls the transaction back', async t => {
  const env = setup(t), ac = new AbortController(); env.project.writeHook = () => ac.abort(new Error('cancel write'));
  const out = await runTaskBatch({ ...env, tasks: [task('a')], signal: ac.signal, runWorker: writeAndSubmit });
  assert.equal(out.tasks[0].status, 'cancelled'); assert.deepEqual(env.project.files, {});
});

test('review is read-only and failed findings are retained rather than applied', async t => {
  const env = setup(t, { 'a.gd': 'extends Node\n' });
  const out = await runTaskBatch({ ...env, tasks: [task('review', { role: 'review', files: [] })], runWorker: async ctx => {
    assert.equal(ctx.tools.some(t => t.name === 'write_file'), false);
    assert.ok((await ctx.exec('write_file', { path: 'a.gd', content: 'extends Node2D\n' })).error);
    assert.equal((await ctx.exec('read_file', { path: 'a.gd' })).total_lines, 2);
    await submit(ctx, false);
  } });
  assert.equal(out.tasks[0].status, 'failed'); assert.equal(out.tasks[0].acceptance[0].passed, false);
  assert.deepEqual(env.project.files, { 'a.gd': 'extends Node\n' });
});

test('passing review remains explicitly unverified and does not count as source changes', async t => {
  const env = setup(t);
  const out = await runTaskBatch({ ...env, tasks: [task('review', { role: 'review', files: [] })], runWorker: submit });
  assert.equal(out.ok, true); assert.equal(out.tasks[0].review_only, true); assert.equal(out.tasks[0].verified, false);
  assert.deepEqual(out.changed, []);
});

test('worker return value and unsubmitted writes cannot claim completion', async t => {
  const env = setup(t);
  const out = await runTaskBatch({ ...env, tasks: [task('a')], runWorker: async ctx => {
    await ctx.exec('write_file', { path: 'a.gd', content: 'extends Node\n' }); return { ok: true, summary: 'done' };
  } });
  assert.equal(out.tasks[0].status, 'failed'); assert.match(out.tasks[0].error, /submit_task/); assert.deepEqual(env.project.files, {});
});

test('worker whitelist, ownership, safety scan, limits and unique patch matching are enforced', async t => {
  const env = setup(t, { 'a.gd': 'extends Node\n# abc abc\n' });
  const out = await runTaskBatch({ ...env, tasks: [task('a')], runWorker: async ctx => {
    assert.ok((await ctx.exec('generate_asset', {})).error);
    assert.ok((await ctx.exec('write_file', { path: 'other.gd', content: 'extends Node\n' })).error);
    assert.ok((await ctx.exec('write_file', { path: 'a.gd', content: 'extends Node\nfunc x(): OS.execute("bad",[])' })).error);
    assert.ok((await ctx.exec('write_file', { path: 'a.gd', content: 'x'.repeat(200001) })).error);
    assert.ok((await ctx.exec('patch_file', { path: 'a.gd', old: 'abc', new: 'xyz' })).error);
    assert.ok((await ctx.exec('read_file', { path: '../private.txt' })).error);
    assert.equal((await ctx.exec('grep_files', { pattern: 'abc' })).matches.length, 1);
    await writeAndSubmit(ctx);
    assert.ok((await ctx.exec('write_file', { path: 'a.gd', content: 'late' })).error);
  } });
  assert.equal(out.ok, true);
});

test('invalid paths, duplicate IDs and cyclic/missing dependencies are rejected without workers', async t => {
  const env = setup(t);
  const bad = ['../a.gd', 'D:/a.gd', '/tmp/a.gd', 'ADDONS/UGC/ugc.gd', '.godot/x.gd', 'BUILD/x.gd', 'a/../b.gd', 'a/./b.gd', 'a//b.gd', 'a.gd.', 'con.gd', 'a/*.gd', 'private.env'];
  for (const p of bad) {
    const out = await runTaskBatch({ ...env, tasks: [task('a', { files: [p] })], runWorker: async () => assert.fail('invalid task ran') });
    assert.equal(out.ok, false, p);
  }
  for (const tasks of [[task('a'), task('a')], [task('a', { depends_on: ['b'] }), task('b', { depends_on: ['a'] })], [task('a', { depends_on: ['missing'] })]]) {
    const out = await runTaskBatch({ ...env, tasks, runWorker: async () => assert.fail('invalid graph ran') }); assert.equal(out.ok, false);
  }
});

test('real GodotProject instances share the commit lock and preserve source revision', async t => {
  const env = setup(t);
  const project = new GodotProject('actual', { root: env.artifactDir });
  const other = new GodotProject('actual', { root: env.artifactDir });
  fs.mkdirSync(project.dir, { recursive: true });
  fs.writeFileSync(path.join(project.dir, 'project.godot'), 'config_version=5\n');
  assert.deepEqual(project.write('a.gd', 'extends Node\n'), []);
  const before = project.revision();
  const out = await runTaskBatch({ project, artifactDir: path.join(env.artifactDir, 'evidence'), tasks: [task('a')], runWorker: async ctx => {
    await ctx.exec('write_file', { path: 'a.gd', content: 'extends Node2D\n' });
    await other.withLock(() => other.write('a.gd', 'extends Control\n'));
    await submit(ctx);
  } });
  assert.equal(out.ok, false); assert.match(out.errors[0].error, /基线冲突/);
  assert.equal(project.read('a.gd'), 'extends Control\n'); assert.notEqual(project.revision(), before);
});

test('candidate evidence must be writable before source commit', async t => {
  const env = setup(t), file = path.join(env.artifactDir, 'not-a-directory'); fs.writeFileSync(file, 'occupied');
  const out = await runTaskBatch({ ...env, artifactDir: file, tasks: [task('a')], runWorker: writeAndSubmit });
  assert.equal(out.ok, false); assert.match(out.tasks[0].error, /保存候选/); assert.deepEqual(env.project.files, {});
});
