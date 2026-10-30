import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { defaultRunWorker, runTaskBatch } from '../task-team.mjs';

const request = (extra = {}) => ({ id: 'rules', title: 'rules', role: 'gameplay', files: ['rules.gd'], depends_on: [], prompt: 'Implement gameplay', acceptance: ['implemented'], ...extra });
function fixture(t, files = {}) {
  const artifactDir = fs.mkdtempSync(path.join(os.tmpdir(), 'ugc-team-diagnostics-'));
  let queue = Promise.resolve();
  const project = {
    files: { ...files }, state: { version: 0 },
    sources() { return { ...this.files }; }, list() { return Object.keys(this.files).map(path => ({ path })); },
    withLock(fn) { const result = queue.then(fn, fn); queue = result.catch(() => {}); return result; },
    write(file, content) { this.files[file] = content; return []; }, remove(file) { delete this.files[file]; return true; },
  };
  t.after(() => {
    assert.ok(path.resolve(artifactDir).startsWith(path.resolve(os.tmpdir()) + path.sep));
    assert.match(path.basename(artifactDir), /^ugc-team-diagnostics-/);
    fs.rmSync(artifactDir, { recursive: true, force: true });
  });
  return { project, artifactDir, tasks: [request()] };
}
const write = ctx => ctx.exec('write_file', { path: 'rules.gd', content: 'extends RefCounted\n' });
const submit = ctx => ctx.exec('submit_task', { summary: 'implementation ready, not run', acceptance: [{ criterion: 'implemented', passed: true, evidence: 'rules.gd implements the requested behavior' }] });
const saved = (env, out) => JSON.parse(fs.readFileSync(path.join(env.artifactDir, out.tasks[0].artifact), 'utf8'));

test('interrupted worker preserves sanitized cause and private candidate, never merges', async t => {
  const env = fixture(t);
  const out = await runTaskBatch({ ...env, runWorker: async ctx => {
    await write(ctx);
    return { done: false, interrupted: true, error: new Error('stream disconnected; Authorization: Bearer synthetic-secret-value') };
  } });
  assert.equal(out.ok, false);
  assert.equal(out.tasks[0].status, 'failed');
  assert.equal(out.tasks[0].worker_end.reason, 'interrupted');
  assert.match(out.tasks[0].error, /stream disconnected/);
  assert.doesNotMatch(out.tasks[0].error, /synthetic-secret-value/);
  assert.deepEqual(env.project.files, {});
  const artifact = saved(env, out);
  assert.equal(artifact.submission, null);
  assert.equal(artifact.candidate['rules.gd'], 'extends RefCounted\n');
  assert.equal(artifact.diagnostics.toolCalls, 1);
  assert.equal(artifact.diagnostics.tools[0].staged, true);
  assert.equal(artifact.diagnostics.workerRuns[0].reason, 'interrupted');
});

test('turn limit, early stop and a normal answer without submission stay distinguishable', async t => {
  for (const [result, reason] of [[{ done: false }, 'turn_limit'], [{ done: false, stopped: true }, 'stopped'], [{ done: true }, 'no_submit'], [{ ok: true, summary: 'done' }, 'no_submit']]) {
    await t.test(reason, async sub => {
      const env = fixture(sub);
      const out = await runTaskBatch({ ...env, runWorker: async ctx => { await write(ctx); return result; } });
      assert.equal(out.tasks[0].worker_end.reason, reason);
      assert.equal(out.tasks[0].status, 'failed');
      assert.deepEqual(env.project.files, {});
      assert.equal(saved(env, out).submission, null);
    });
  }
});

test('an explicit failed execution cannot apply even a previously valid submission', async t => {
  for (const result of [{ done: false, interrupted: true, error: 'interrupted after submit' }, { done: false }, { ok: false, error: 'worker validation failed' }]) {
    await t.test(JSON.stringify(result), async sub => {
      const env = fixture(sub);
      const out = await runTaskBatch({ ...env, runWorker: async ctx => {
        await write(ctx); assert.equal((await submit(ctx)).ok, true); return result;
      } });
      assert.equal(out.ok, false); assert.equal(out.tasks[0].status, 'failed');
      assert.deepEqual(out.changed, []); assert.deepEqual(env.project.files, {});
      assert.ok(saved(env, out).submission);
      assert.equal(out.tasks[0].verified, false);
    });
  }
});

test('default worker reminds a normal early answer once and still requires real submit', async t => {
  const env = fixture(t), budgets = [];
  let calls = 0;
  const out = await runTaskBatch({ ...env, runWorker: ctx => defaultRunWorker(ctx, async opts => {
    budgets.push(opts.maxTurns);
    if (++calls === 1) {
      await opts.exec('write_file', { path: 'rules.gd', content: 'extends RefCounted\n' });
      assert.deepEqual(env.project.files, {});
      return { done: true };
    }
    assert.equal(opts.messages.filter(m => /唯一一次续交提醒/.test(m.content)).length, 1);
    assert.equal((await submit({ exec: opts.exec })).ok, true);
    return { done: true };
  }) });
  assert.equal(out.ok, true); assert.equal(calls, 2);
  assert.deepEqual(budgets, [16, 4]);
  assert.equal(env.project.files['rules.gd'], 'extends RefCounted\n');
  const artifact = saved(env, out);
  assert.equal(artifact.diagnostics.reminders, 1);
  assert.deepEqual(artifact.diagnostics.workerRuns.map(r => r.reason), ['no_submit', 'submitted']);
  assert.equal(out.tasks[0].worker_end.reason, 'submitted');
  assert.equal(out.tasks[0].verified, false);
});

test('a second normal answer without submit fails instead of looping or applying', async t => {
  const env = fixture(t);
  let calls = 0;
  const out = await runTaskBatch({ ...env, runWorker: ctx => defaultRunWorker(ctx, async opts => {
    calls++; await opts.exec('write_file', { path: 'rules.gd', content: 'extends RefCounted\n' }); return { done: true };
  }) });
  assert.equal(calls, 2); assert.equal(out.ok, false);
  assert.equal(out.tasks[0].worker_end.reason, 'no_submit');
  assert.equal(saved(env, out).diagnostics.reminders, 1);
  assert.deepEqual(env.project.files, {});
});

test('default worker does not remind interrupted, exhausted, stopped or failed executions', async t => {
  for (const result of [{ done: false, interrupted: true, error: 'network interrupted' }, { done: false }, { done: false, stopped: true }, { done: true, error: 'execution failed' }]) {
    await t.test(JSON.stringify(result), async sub => {
      const env = fixture(sub);
      let calls = 0;
      const out = await runTaskBatch({ ...env, runWorker: ctx => defaultRunWorker(ctx, async () => { calls++; return result; }) });
      assert.equal(calls, 1); assert.equal(out.ok, false);
      assert.equal(saved(env, out).diagnostics.reminders, 0);
      assert.deepEqual(env.project.files, {});
    });
  }
});

test('default worker successful submission needs no reminder', async t => {
  const env = fixture(t);
  let calls = 0;
  const out = await runTaskBatch({ ...env, runWorker: ctx => defaultRunWorker(ctx, async opts => {
    calls++; await write({ exec: opts.exec }); await submit({ exec: opts.exec }); return { done: true };
  }) });
  assert.equal(out.ok, true); assert.equal(calls, 1);
  assert.equal(saved(env, out).diagnostics.reminders, 0);
});

test('diagnostics are bounded, redact secrets and never persist prompts, messages or read contents', async t => {
  const env = fixture(t, { 'private.gd': 'extends Node\n# PRIVATE_READ_CONTENT_SENTINEL\n' });
  env.tasks = [request({ prompt: 'FULL_PROMPT_SENTINEL that must not be saved' })];
  const out = await runTaskBatch({ ...env, runWorker: async ctx => {
    ctx.messages.push({ role: 'assistant', content: [{ type: 'thinking', thinking: 'PRIVATE_REASONING_SENTINEL' }] });
    for (let i = 0; i < 60; i++) await ctx.exec('read_file', { path: 'private.gd' });
    await ctx.exec('read_file', { path: 'Bearer SECRET_PATH_SENTINEL' });
    return { done: false, error: 'api_key="SECRET_API_SENTINEL" password=SECRET_PASSWORD_SENTINEL https://name:pass@example.test/private/SECRET_URL_SENTINEL?token=secret sk-abcdefghijklmnop123456 ' + 'x'.repeat(2000) };
  } });
  const artifact = saved(env, out), serialized = JSON.stringify(artifact);
  assert.equal(artifact.version, 2);
  assert.equal(artifact.request.prompt, undefined);
  assert.equal(artifact.request.promptChars, env.tasks[0].prompt.length);
  assert.equal(artifact.diagnostics.tools.length, 40);
  assert.equal(artifact.diagnostics.toolCalls, 61);
  assert.equal(artifact.diagnostics.traceDropped, 21);
  assert.ok(artifact.task.worker_end.error.length <= 500);
  assert.doesNotMatch(serialized, /FULL_PROMPT_SENTINEL|PRIVATE_REASONING_SENTINEL|PRIVATE_READ_CONTENT_SENTINEL|SECRET_PATH_SENTINEL|SECRET_API_SENTINEL|SECRET_PASSWORD_SENTINEL|SECRET_URL_SENTINEL|sk-abcdefghijklmnop123456/);
  assert.match(serialized, /REDACTED/);
  assert.equal('messages' in artifact, false);
  assert.ok(artifact.diagnostics.tools.every(row => !('input' in row) && !('content' in row) && !('text' in row)));
});

test('a thrown worker error retains sanitized diagnostics and cannot apply candidates', async t => {
  const env = fixture(t);
  const out = await runTaskBatch({ ...env, runWorker: async ctx => {
    await write(ctx); throw new Error('failed with token=SECRET_THROW_SENTINEL');
  } });
  assert.equal(out.tasks[0].worker_end.reason, 'worker_error');
  assert.match(out.tasks[0].error, /failed with/);
  assert.doesNotMatch(JSON.stringify(saved(env, out)), /SECRET_THROW_SENTINEL/);
  assert.deepEqual(env.project.files, {});
});

test('worker response model metadata reaches task events and persisted artifacts only', async t => {
  const env = fixture(t), events = [];
  let late;
  const out = await runTaskBatch({ ...env, onTask: event => events.push(event), runWorker: ctx => defaultRunWorker(ctx, async opts => {
    late = opts.cb.onModel;
    opts.cb.onModel({ requestedModel: opts.req.model, responseModel: 'gateway-returned-model', thinking: 'PRIVATE_REASONING_SENTINEL' });
    await write({ exec: opts.exec }); await submit({ exec: opts.exec }); return { done: true };
  }) });
  assert.equal(out.ok, true);
  assert.equal(out.tasks[0].model.responseModel, 'gateway-returned-model');
  assert.equal(typeof out.tasks[0].model.requestedModel, 'string');
  assert.equal(out.tasks[0].model.requestedModel.length > 0, true);
  assert.deepEqual(saved(env, out).task.model, out.tasks[0].model);
  assert.ok(events.some(event => event.model?.responseModel === 'gateway-returned-model'));
  assert.doesNotMatch(JSON.stringify(saved(env, out)), /PRIVATE_REASONING_SENTINEL/);
  const count = events.length;
  late({ requestedModel: 'late', responseModel: 'late' });
  assert.equal(events.length, count);
  assert.equal(out.tasks[0].model.responseModel, 'gateway-returned-model');
});

test('worker response model omission stays empty and model metadata cannot turn failure into success', async t => {
  const env = fixture(t);
  const out = await runTaskBatch({ ...env, runWorker: ctx => defaultRunWorker(ctx, async opts => {
    opts.cb.onModel({ requestedModel: opts.req.model });
    return { done: false, interrupted: true, error: 'interrupted' };
  }) });
  assert.equal(out.ok, false);
  assert.equal(out.tasks[0].status, 'failed');
  assert.equal(out.tasks[0].model.responseModel, '');
  assert.equal(saved(env, out).task.model.responseModel, '');
  assert.deepEqual(env.project.files, {});
});
