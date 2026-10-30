import test, { after } from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { Readable, Writable } from 'node:stream';
import { PlaytestWatch } from '../playtest-watch.mjs';
const data = fs.mkdtempSync(path.join(os.tmpdir(), 'ugc-watch-http-'));
process.env.UGC_DATA_DIR = data;
const { Project, projects, requestHandler } = await import('../server.mjs');
after(() => fs.rmSync(data, { force: true, recursive: true }));
async function request(url) {
  const req = Readable.from([]); Object.assign(req, { url, method: 'GET', headers: {} });
  const out = { headers: {}, chunks: [] }, res = new Writable({ write(chunk, enc, cb) { out.chunks.push(Buffer.from(chunk)); cb(); } });
  res.writeHead = (status, headers) => { out.status = status; out.headers = headers; };
  const done = new Promise(resolve => res.on('finish', resolve)); await requestHandler(req, res); await done;
  out.body = Buffer.concat(out.chunks); return out;
}
test('watch HTTP returns real JPEG bytes, never persists frame blobs, and rejects a prior session', async () => {
  const p = new Project({ id: 'watchdemo' }); projects.set(p.id, p);
  assert.equal((await request('/api/projects/watchdemo/watch')).body.toString(), 'null');
  p.watch = new PlaytestWatch(p.id, { emit: e => p.emit(e) });
  const session = p.watch.start({ runId: 'round', kind: 'test', sourceRevision: 'revision', step: '移动' });
  const bytes = Buffer.from([255,216,1,4,8,255,217]);
  p.watch.frame(session, { seq: 1, image: bytes, capturedAt: Date.now() });
  const meta = await request('/api/projects/watchdemo/watch'), watch = JSON.parse(meta.body);
  assert.equal(watch.status, 'live'); assert.equal(meta.headers['cache-control'], 'no-store');
  const img = await request(watch.frameUrl); assert.equal(img.status, 200); assert.deepEqual(img.body, bytes); assert.equal(img.headers['Cache-Control'], 'no-store');
  p.save(); const saved = JSON.parse(fs.readFileSync(p.file())); assert.equal(saved.watch, undefined); assert.equal(JSON.stringify(saved).includes('Buffer'), false);
  p.watch.start({ runId: 'next', kind: 'test' }); assert.equal((await request(watch.frameUrl)).status, 410);
  assert.equal((await request('/api/projects/missing/watch')).status, 404);
});
