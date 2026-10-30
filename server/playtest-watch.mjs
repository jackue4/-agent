import { randomBytes } from 'node:crypto';

const cleanChecks = rows => (Array.isArray(rows) ? rows : []).slice(-40).map(row => ({ what: String(row?.what || '').slice(0, 240), ok: row?.ok === true }));
const cleanErrors = rows => (Array.isArray(rows) ? rows : []).slice(0, 8).map(row => ({ message: String(row?.message || row || '').slice(0, 400) }));

/** Ephemeral, bounded transport of real viewport frames. It never creates acceptance evidence. */
export class PlaytestWatch {
  constructor(projectId, { emit = () => {}, clock = Date.now } = {}) {
    this.projectId = projectId; this.emit = emit; this.clock = clock;
    this.current = null; this.frames = new Map(); this.nativeSeq = 0;
  }
  snapshot() { return this.current ? structuredClone(this.current) : null; }
  publish() { this.emit({ type: 'playtest_watch', watch: this.snapshot() }); }
  start({ runId, sourceRevision, kind, step }) {
    const sessionId = randomBytes(10).toString('hex');
    this.frames.clear(); this.nativeSeq = 0;
    this.current = { sessionId, runId: String(runId || ''), sourceRevision: String(sourceRevision || ''), kind, step: String(step || '').slice(0, 140), status: 'starting', frameSeq: 0, frameUrl: '', capturedAt: 0, checks: [], errors: [], updatedAt: this.clock() };
    this.publish(); return sessionId;
  }
  frame(sessionId, frame) {
    const row = this.current;
    if (!row || row.sessionId !== sessionId || !['starting', 'live'].includes(row.status)) return false;
    if (!Buffer.isBuffer(frame?.image) || frame.image.length < 4 || frame.image.length > 1024 * 1024 || frame.image[0] !== 0xff || frame.image[1] !== 0xd8) return false;
    if (!Number.isSafeInteger(frame.seq) || frame.seq <= this.nativeSeq) return false;
    this.nativeSeq = frame.seq;
    const first = row.frameSeq === 0;
    row.frameSeq++; row.frameUrl = `/api/projects/${encodeURIComponent(this.projectId)}/watch/frame?session=${row.sessionId}&seq=${row.frameSeq}`;
    row.status = 'live'; row.capturedAt = Number.isFinite(frame.capturedAt) ? frame.capturedAt : this.clock();
    row.updatedAt = this.clock(); row.checks = cleanChecks(frame.checks);
    this.frames.set(row.frameSeq, Buffer.from(frame.image));
    while (this.frames.size > 8) this.frames.delete(this.frames.keys().next().value);
    if (first) this.publish();
    return true;
  }
  end(sessionId, { status = 'stopped', checks, errors } = {}) {
    const row = this.current;
    if (!row || row.sessionId !== sessionId || !['starting', 'live'].includes(row.status)) return false;
    row.status = ['passed', 'failed', 'stopped'].includes(status) ? status : 'stopped';
    if (checks) row.checks = cleanChecks(checks);
    row.errors = cleanErrors(errors); row.updatedAt = this.clock(); this.publish(); return true;
  }
  stop() { if (this.current) this.end(this.current.sessionId); }
  image(sessionId, seq) { return this.current?.sessionId === sessionId ? this.frames.get(Number(seq)) || null : null; }
}
