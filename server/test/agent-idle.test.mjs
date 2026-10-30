import test from 'node:test';
import assert from 'node:assert/strict';

process.env.AIGATE_API_KEY = 'test-key';
process.env.AIGATE_PROTOCOL = 'messages';
const { streamTurn, runAgent } = await import('../agent.mjs');
const sleep = ms => new Promise(resolve => setTimeout(resolve, ms));
const packet = value => 'data: ' + JSON.stringify(value) + '\n\n';
const stop = packet({ type: 'message_delta', delta: { stop_reason: 'end_turn' } });
const textStart = packet({ type: 'content_block_start', index: 0, content_block: { type: 'text', text: '' } });
const textDelta = text => packet({ type: 'content_block_delta', index: 0, delta: { type: 'text_delta', text } });
function neverUntilAborted(signal) {
  if (signal.aborted) return Promise.reject(signal.reason);
  return new Promise((_, reject) => signal.addEventListener('abort', () => reject(signal.reason), { once: true }));
}

test('productive streams can run many inactivity periods without interruption', async () => {
  let actualSignal, calls = 0, text = '';
  const start = Date.now();
  const result = await streamTurn([], { onText: delta => { text += delta; } }, undefined, {
    idleTimeoutMs: 100,
    fetchImpl: async (_url, { signal }) => {
      actualSignal = signal; calls++;
      return { ok: true, body: (async function* () {
        yield textStart;
        for (let i = 0; i < 16; i++) { await sleep(20); assert.equal(signal.aborted, false); yield textDelta('x'); }
        yield stop;
      })() };
    },
  });
  assert.equal(result.stop, 'end_turn'); assert.equal(text, 'x'.repeat(16));
  assert.equal(calls, 1); assert.ok(Date.now() - start >= 300);
  await sleep(130); assert.equal(actualSignal.aborted, false, 'completed request must clear its idle timer');
});

test('partial SSE byte chunks reset inactivity even before an event is complete', async () => {
  let actualSignal;
  const wire = textStart + textDelta('complete') + stop;
  const result = await streamTurn([], {}, undefined, {
    idleTimeoutMs: 100,
    fetchImpl: async (_url, { signal }) => {
      actualSignal = signal;
      return { ok: true, body: (async function* () {
        for (let at = 0; at < wire.length; at += 10) { await sleep(10); yield new TextEncoder().encode(wire.slice(at, at + 10)); }
      })() };
    },
  });
  assert.equal(result.content[0].text, 'complete'); assert.equal(actualSignal.aborted, false);
});

test('no response headers abort the real request signal and retain the bounded retry policy', async () => {
  const signals = [];
  await assert.rejects(streamTurn([], {}, undefined, {
    idleTimeoutMs: 15, sleep: async () => {},
    fetchImpl: (_url, { signal }) => { signals.push(signal); return neverUntilAborted(signal); },
  }), error => error.code === 'STREAM_IDLE_TIMEOUT');
  assert.equal(signals.length, 3); assert.ok(signals.every(signal => signal.aborted));
});

test('a stalled tool stream is cancelled once and incomplete arguments never execute', async () => {
  let actualSignal, calls = 0, executed = 0;
  const out = await runAgent({ messages: [], cb: {}, exec: async () => { executed++; }, idleTimeoutMs: 20, deps: {
    fetchImpl: async (_url, { signal }) => {
      actualSignal = signal; calls++;
      return { ok: true, body: (async function* () {
        yield packet({ type: 'content_block_start', index: 0, content_block: { type: 'tool_use', id: 'one', name: 'write_file' } });
        yield packet({ type: 'content_block_delta', index: 0, delta: { type: 'input_json_delta', partial_json: '{"path":"main.gd","content":"' } });
        await neverUntilAborted(signal);
      })() };
    },
  } });
  assert.equal(out.interrupted, true); assert.equal(out.error.code, 'STREAM_IDLE_TIMEOUT');
  assert.equal(actualSignal.aborted, true); assert.equal(calls, 1); assert.equal(executed, 0);
});

test('parent cancellation interrupts healthy activity before idle and does not retry', async () => {
  const parent = new AbortController(); let calls = 0;
  const failure = new Error('whole round deadline');
  const run = streamTurn([], {}, parent.signal, { idleTimeoutMs: 1000, fetchImpl: async (_url, { signal }) => {
    calls++;
    return { ok: true, body: (async function* () { yield textStart; await neverUntilAborted(signal); })() };
  } });
  setTimeout(() => parent.abort(failure), 15);
  await assert.rejects(run, error => error === failure); assert.equal(calls, 1);
});

test('existing callers without idleTimeoutMs retain the original signal and behavior', async () => {
  const parent = new AbortController();
  const result = await streamTurn([], {}, parent.signal, { fetchImpl: async (_url, { signal }) => {
    assert.equal(signal, parent.signal);
    return { ok: true, body: (async function* () { await sleep(30); yield textStart + textDelta('legacy') + stop; })() };
  } });
  assert.equal(result.content[0].text, 'legacy');
});
