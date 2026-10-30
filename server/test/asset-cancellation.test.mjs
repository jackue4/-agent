import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { AssetFactory, callTool, sleep } from '../aigc.mjs';

function fixture(t) {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'ugc-asset-cancel-'));
  const factory = new AssetFactory(dir);
  t.after(() => { if (path.dirname(dir) === os.tmpdir() && path.basename(dir).startsWith('ugc-asset-cancel-')) fs.rmSync(dir, { recursive: true, force: true }); });
  return { factory, dir };
}
test('pre-aborted asset requests never submit, download or generate a fallback', async t => {
  const { factory, dir } = fixture(t), ac = new AbortController(); ac.abort(new Error('round ended'));
  let calls = 0; const previous = globalThis.fetch;
  globalThis.fetch = async () => { calls++; throw new Error('must not call'); }; t.after(() => { globalThis.fetch = previous; });
  await assert.rejects(callTool('generate_image_async', {}, { signal: ac.signal }), /round ended/);
  await assert.rejects(factory.download('https://example.test/image.png', '.png', ac.signal), /round ended/);
  await assert.rejects(factory.generate({ kind: 'sprite' }, {}, () => {}, { signal: ac.signal }), /round ended/);
  assert.equal(calls, 0); assert.deepEqual(fs.readdirSync(path.join(dir, 'assets')), []);
});
test('cancel during sprite cutout does not silently download an uncut fallback', async t => {
  const { factory } = fixture(t), ac = new AbortController(); let downloads = 0;
  factory.image = async () => 'https://example.test/concept.png';
  factory.cutout = async () => { ac.abort(new Error('timebox ended')); throw ac.signal.reason; };
  factory.download = async () => { downloads++; return '/assets/fake.png'; };
  await assert.rejects(factory.generate({ kind: 'sprite' }, {}, () => {}, { signal: ac.signal }), /timebox ended/);
  assert.equal(downloads, 0);
});
test('cancel after remote bytes arrive refuses writing the asset to disk', async t => {
  const { factory, dir } = fixture(t), ac = new AbortController(); const previous = globalThis.fetch;
  globalThis.fetch = async () => ({ ok: true, arrayBuffer: async () => { ac.abort(new Error('late bytes')); return new ArrayBuffer(12); } });
  t.after(() => { globalThis.fetch = previous; });
  await assert.rejects(factory.download('https://example.test/late.png', '.png', ac.signal), /late bytes/);
  assert.deepEqual(fs.readdirSync(path.join(dir, 'assets')), []);
});
test('cancellation interrupts polling backoff rather than delaying the deadline', async () => {
  const ac = new AbortController(), started = Date.now();
  const pending = sleep(3000, ac.signal); ac.abort(new Error('stop polling'));
  await assert.rejects(pending, /stop polling/); assert.ok(Date.now() - started < 500);
});
