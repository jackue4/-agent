// A native Godot viewport stream. Metadata is committed after its JPEG, and the
// two-slot protocol lets readers reject a frame replaced while they were reading.
import fs from 'node:fs/promises';
import path from 'node:path';

const MAX_META = 128 * 1024;
const MAX_IMAGE = 1024 * 1024;

async function boundedFile(file, maximum) {
  const stat = await fs.lstat(file);
  if (!stat.isFile() || stat.isSymbolicLink() || stat.size < 1 || stat.size > maximum) return null;
  const bytes = await fs.readFile(file);
  return bytes.length <= maximum ? bytes : null;
}

/** Optional observation only: callback failures never change game/test results.
 * stop() prevents any later delivery; flush() drains the newest committed frame.
 * Slow observers skip intermediate frames instead of building an unbounded queue. */
export function startWatchFrames(directory, { onFrame, signal, isCurrent = () => true, intervalMs = 60 } = {}) {
  let stopped = typeof onFrame !== 'function' || !!signal?.aborted;
  let lastSeq = 0, pending = null, timer = null;
  const current = () => !stopped && !signal?.aborted && isCurrent();
  const metaPath = path.join(directory, 'watch.json');
  const poll = async () => {
    if (!current()) return;
    try {
      const before = await boundedFile(metaPath, MAX_META);
      if (!before || !current()) return;
      const data = JSON.parse(before.toString('utf8'));
      if (!Number.isSafeInteger(data.seq) || data.seq <= lastSeq || !/^frame_[01]\.jpg$/.test(data.frame)
        || !Number.isFinite(data.capturedAt) || data.capturedAt <= 0 || !Array.isArray(data.checks)
        || !data.state || typeof data.state !== 'object' || Array.isArray(data.state)) return;
      const image = await boundedFile(path.join(directory, data.frame), MAX_IMAGE);
      if (!image || image.length < 4 || image[0] !== 0xff || image[1] !== 0xd8
        || image.at(-2) !== 0xff || image.at(-1) !== 0xd9) return;
      const after = await boundedFile(metaPath, MAX_META);
      if (!after || !before.equals(after) || !current()) return;
      lastSeq = data.seq;
      const checks = data.checks.slice(-200).filter(c => c && typeof c.ok === 'boolean' && typeof c.what === 'string')
        .map(c => ({ ok: c.ok, what: c.what.slice(0, 500) }));
      await onFrame({ seq: data.seq, image, checks, state: data.state, capturedAt: data.capturedAt });
    } catch { /* Missing/replaced files, process exits and observer errors are non-fatal. */ }
  };
  const schedule = () => {
    if (!pending && current()) pending = poll().finally(() => { pending = null; });
    return pending || Promise.resolve();
  };
  const stop = () => {
    stopped = true;
    if (timer) clearInterval(timer);
    timer = null;
    signal?.removeEventListener('abort', stop);
  };
  if (!stopped) {
    signal?.addEventListener('abort', stop, { once: true });
    timer = setInterval(schedule, Math.max(10, intervalMs)); timer.unref();
    schedule();
  }
  return {
    stop,
    async flush() { if (pending) await pending; if (current()) await schedule(); },
  };
}
