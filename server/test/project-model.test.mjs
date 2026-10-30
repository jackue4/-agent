import test, { after } from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { Readable, Writable } from 'node:stream';
import { emptyGame } from '../engine.mjs';
import { MODEL_OPTIONS, MODEL_SETTINGS } from '../model-config.mjs';
import { runProjectBuilder } from '../gpagent.mjs';
import { runBuilder } from '../codegen.mjs';
import { defaultRunWorker } from '../task-team.mjs';

// Exercise the actual HTTP handler/storage and orchestration, but never a network model call.
const data = fs.mkdtempSync(path.join(os.tmpdir(), 'ugc-project-model-'));
process.env.UGC_DATA_DIR = data;
process.env.UGC_ENGINE = 'classic';
const originalFetch = globalThis.fetch;
globalThis.fetch = async () => assert.fail('project-model tests must never call a real network service');
const api = await import('../server.mjs');
after(() => { globalThis.fetch = originalFetch; assert.equal(api.server.listening, false); fs.rmSync(data, { recursive: true, force: true }); });
const choices = MODEL_OPTIONS.map(row => row.id);

class Response extends Writable {
  constructor() { super(); this.parts = []; this.done = new Promise(resolve => this.on('finish', resolve)); }
  _write(chunk, _encoding, callback) { this.parts.push(Buffer.from(chunk)); callback(); }
  writeHead(status, headers) { this.statusCode = status; this.headers = headers; }
  json() { return JSON.parse(Buffer.concat(this.parts).toString()); }
}
async function request(url, body, method = body === undefined ? 'GET' : 'POST') {
  const req = Readable.from(body === undefined ? [] : [Buffer.from(JSON.stringify(body))]);
  Object.assign(req, { url, method, headers: {} });
  const res = new Response(); await api.requestHandler(req, res); await res.done; return res;
}
function project(model, engine = 'godot') {
  const p = new api.Project({ ...(model === undefined ? {} : { model }) });
  p.game.meta.engine = engine; api.projects.set(p.id, p); return p;
}
function reload(p) { return new api.Project(JSON.parse(fs.readFileSync(p.file(), 'utf8'))); }

test('model catalogue and old-project defaults remain compatible without migrating game data', async () => {
  const response = await request('/api/models');
  assert.equal(response.statusCode, 200);
  assert.deepEqual(response.json(), { models: MODEL_OPTIONS, defaultModel: MODEL_SETTINGS.codeModel });
  assert.equal(new Set(choices).size, choices.length);
  for (const engine of ['godot', 'code', 'legacy']) {
    const p = project(undefined, engine), before = structuredClone(p.game);
    assert.equal(api.projectView(p).model, engine === 'legacy' ? MODEL_SETTINGS.model : MODEL_SETTINGS.codeModel);
    assert.equal(Object.hasOwn(p, 'model'), false);
    assert.deepEqual(p.game, before);
  }
});

test('create and select persist exact choices across reload while unknown input leaves state unchanged', async () => {
  const created = await request('/api/projects', { model: choices[0] });
  assert.equal(created.statusCode, 200);
  const p = api.projects.get(created.json().id);
  assert.equal(created.json().model, choices[0]);
  assert.equal(reload(p).model, choices[0]);
  const selected = await request('/api/projects/' + p.id + '/model', { model: choices[1] });
  assert.equal(selected.statusCode, 200);
  assert.deepEqual(selected.json(), { ok: true, model: choices[1] });
  assert.equal(api.projectView(reload(p)).model, choices[1]);
  for (const value of ['', null, 123, 'not-in-catalogue', choices[0] + ' ']) {
    const before = fs.readFileSync(p.file(), 'utf8'), size = api.projects.size;
    assert.equal((await request('/api/projects/' + p.id + '/model', { model: value })).statusCode, 400);
    assert.equal((await request('/api/projects', { model: value })).statusCode, 400);
    assert.equal((await request('/api/projects/' + p.id + '/chat', { text: 'must not start', model: value })).statusCode, 400);
    assert.equal(p.running, false); assert.equal(p.chat.length, 0); assert.equal(api.projects.size, size);
    assert.equal(fs.readFileSync(p.file(), 'utf8'), before);
  }
});

test('production and scene mutations reject switching without changing the stored selection', async () => {
  const p = project(choices[0]); p.save();
  for (const flag of ['running', 'mutating']) {
    p[flag] = true;
    for (const route of ['model', 'chat']) assert.equal((await request('/api/projects/' + p.id + '/' + route, { model: choices[1], text: 'test' })).statusCode, 409);
    assert.throws(() => api.selectProjectModel(p, choices[1]), error => error.statusCode === 409);
    assert.equal(p.model, choices[0]); assert.equal(reload(p).model, choices[0]);
    p[flag] = false;
  }
});

test('remix inherits the source selection and an explicit choice overrides only the new work', async () => {
  const src = project(choices[0], 'legacy'); src.published = { game: structuredClone(src.game) }; src.save();
  const copied = await request('/api/projects', { remix: src.id });
  assert.equal(copied.statusCode, 200); assert.equal(copied.json().model, choices[0]);
  const overridden = await request('/api/projects', { remix: src.id, model: choices[2] });
  assert.equal(overridden.statusCode, 200); assert.equal(overridden.json().model, choices[2]);
  assert.equal(reload(api.projects.get(copied.json().id)).model, choices[0]);
  assert.equal(src.model, choices[0]);
});

test('concurrent Godot rounds keep request selection through the real independent worker adapter', async () => {
  const selected = [choices[0], choices[2]], runs = selected.map(model => project(model));
  let started = 0, release;
  const together = new Promise(resolve => { release = resolve; });
  const seen = [];
  await Promise.all(runs.map((p, i) => api.runCodeChat(p, 'review one small module', {}, {
    live: { stop() {} },
    runProjectBuilder: args => runProjectBuilder({ ...args,
      agentRunner: async options => {
        seen.push({ project: p.id, role: 'main', model: options.req.model });
        assert.equal(options.req.model, selected[i]);
        if (++started === 2) release();
        await together;
        assert.throws(() => api.selectProjectModel(p, choices[3]), error => error.statusCode === 409);
        options.cb.onModel({ requestedModel: options.req.model, responseModel: options.req.model });
        const batch = await options.exec('delegate_tasks', { tasks: [{ id: 'review', title: 'Review', role: 'review', files: [], depends_on: [], prompt: 'Review the existing snapshot', acceptance: ['snapshot inspected'] }] });
        assert.equal(batch.ok, true, JSON.stringify(batch));
        return { done: true };
      },
      runWorker: ctx => defaultRunWorker(ctx, async options => {
        seen.push({ project: p.id, role: 'worker', model: options.req.model });
        assert.equal(ctx.model, selected[i]); assert.equal(options.req.model, selected[i]);
        options.cb.onModel({ requestedModel: options.req.model, responseModel: options.req.model });
        const result = await options.exec('submit_task', { summary: 'Reviewed actual snapshot; no runtime claim', acceptance: [{ criterion: 'snapshot inspected', passed: true, evidence: 'Read project snapshot' }] });
        assert.equal(result.ok, true); return { done: true };
      }),
    }),
  })));
  assert.equal(seen.length, 4); assert.equal(started, 2);
  for (let i = 0; i < runs.length; i++) {
    const p = runs[i];
    assert.deepEqual(seen.filter(row => row.project === p.id).map(row => row.model), [selected[i], selected[i]]);
    assert.equal(p.log.find(row => row.type === 'turn_start').model, selected[i]);
    assert.equal(p.log.find(row => row.type === 'model_response').requestedModel, selected[i]);
    assert.equal(p.workflow.tasks[0].model.requestedModel, selected[i]);
    assert.equal(p.workflow.tasks[0].model.responseModel, selected[i]);
    assert.equal(p.model, selected[i]); assert.equal(reload(p).model, selected[i]);
  }
});

test('chat override is persisted before JS production and reaches its actual request object', async () => {
  const p = project(choices[0], 'code'); let calls = 0;
  await api.runCodeChat(p, 'one improvement', { model: choices[2] }, {
    live: { stop() {} },
    runBuilder: args => runBuilder({ ...args, agentRunner: async options => {
      calls++; assert.equal(args.model, choices[2]); assert.equal(options.req.model, choices[2]);
      assert.equal(reload(p).model, choices[2]);
      options.cb.onModel({ requestedModel: options.req.model, responseModel: options.req.model });
      return { done: true };
    } }),
  });
  assert.equal(calls, 1);
  assert.equal(p.log.find(row => row.type === 'turn_start').model, choices[2]);
  assert.equal(p.log.find(row => row.type === 'model_response').responseModel, choices[2]);
  await assert.rejects(api.runCodeChat(p, 'never request', { model: 'unknown' }), error => error.statusCode === 400);
  assert.equal(p.model, choices[2]);
});

test('legacy scene builder receives the project choice and records the actual response identifier', async () => {
  const p = project(choices[3], 'legacy'); let calls = 0;
  // Existing entities keep this fixture on the legacy branch regardless of prompt routing.
  p.game.entities.floor = { id: 'floor', kind: 'platform', position: [0, 0], size: [10, 1] };
  await api.runChat(p, '调整平台颜色', { model: choices[2] }, { runBuilder: () => assert.fail('wrong builder route'), runProjectBuilder: () => assert.fail('wrong project route'), runAgent: async options => {
    calls++; assert.equal(options.req.model, choices[2]); assert.equal(reload(p).model, choices[2]);
    options.cb.onModel({ requestedModel: options.req.model, responseModel: choices[2] + '-reported' });
    return { done: true };
  } });
  assert.equal(calls, 1);
  assert.equal(p.log.find(row => row.type === 'turn_start').model, choices[2]);
  assert.equal(p.log.find(row => row.type === 'model_response').responseModel, choices[2] + '-reported');
});
