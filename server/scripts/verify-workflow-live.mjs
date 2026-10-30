// Read-only evidence checks plus a local staging-only publication check for the synthetic sample.
import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import assert from 'node:assert/strict';
const base = process.argv[2] || 'http://10.0.4.94:5301';
if (base !== 'http://10.0.4.94:5301') throw new Error('This verifier only writes to the isolated staging service on 5301');
const id = 'workflow_demo_v1', api = base + '/api/projects/' + id;
const call = async (route, body) => {
  const response = await fetch(route, body ? { method: 'POST', headers: { 'content-type': 'application/json' }, body: JSON.stringify(body) } : {});
  return { status: response.status, data: await response.json() };
};
const { data: view } = await call(api);
assert.equal(view.running, false); assert.equal(view.workflow.status, 'completed');
assert.ok(view.workflow.tasks.length >= 2 && view.workflow.tasks.every(t => t.status === 'verified'));
const { data: replay } = await call(api + '/events?since=0');
const rows = replay.events.filter(e => e.type === 'task' && e.runId === view.workflow.id).map(e => e.task);
const firstRules = rows.find(t => t.id === 'rules_progress' && t.status === 'running');
const firstScene = rows.find(t => t.id === 'scene_help' && t.status === 'running');
const rulesDone = rows.find(t => t.id === 'rules_progress' && t.status === 'applied');
const sceneFailed = rows.find(t => t.id === 'scene_help' && t.status === 'failed');
assert.ok(firstRules && firstScene && rulesDone && sceneFailed, 'Expected real task overlap and retry evidence');
const overlapMs = Math.min(rulesDone.finishedAt, sceneFailed.finishedAt) - Math.max(firstRules.startedAt, firstScene.startedAt);
assert.ok(overlapMs > 0, 'Workers must actually overlap');
assert.equal(view.workflow.tasks.find(t => t.id === 'rules_progress').attempt, 1);
assert.equal(view.workflow.tasks.find(t => t.id === 'scene_help').attempt, 2);
const check = await call(api + '/check');
assert.equal(check.data.ok, true); assert.equal(check.data.sourceRevision, view.build.sourceRevision);
const test = view.workflow.evidence.findLast(e => e.kind === 'test' && e.sourceRevision === view.build.sourceRevision);
assert.ok(test.ok && test.checks.length >= 8 && test.checks.every(c => c.ok));
const wrongReceipt = await call(api + '/preview_receipt', { kind: 'runtime_ready', buildId: '0'.repeat(32), sourceRevision: view.build.sourceRevision, loaded: true, errors: [] });
assert.equal(wrongReceipt.status, 409);
const pub = await call(api + '/publish', { title: view.game.meta.title });
assert.equal(pub.status, 200);
const published = await call(base + '/api/games/' + id);
assert.equal(published.data.build.buildId, view.build.buildId);
const bytes = Buffer.from(await (await fetch(base + published.data.pck)).arrayBuffer());
const contentHash = crypto.createHash('sha256').update(bytes).digest('hex');
assert.equal(contentHash, view.build.contentHash);
const file = path.resolve('artifacts/workflow-v1/live-verification.json');
const report = { at: new Date().toISOString(), projectId: id, runId: view.workflow.id, status: view.workflow.status,
  overlapMs, tasks: view.workflow.tasks, firstAttemptFailure: sceneFailed.error, check: { ok: check.data.ok, sourceRevision: check.data.sourceRevision },
  test, wrongBuildReceiptStatus: wrongReceipt.status, publishedBuild: { buildId: view.build.buildId, contentHash },
  preview: view.workflow.evidence.findLast(e => e.kind === 'preview' && e.buildId === view.build.buildId),
};
fs.writeFileSync(file, JSON.stringify(report, null, 2));
console.log(JSON.stringify({ ok: true, overlapMs, taskAttempts: report.tasks.map(t => ({ id: t.id, attempt: t.attempt, status: t.status })), assertions: test.checks.length, publicationMatchesVerifiedBuild: true, file }));
