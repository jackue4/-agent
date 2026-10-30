// Godot resource packs (.pck, format 2-4 as written by Godot 4.x exports): read the file table of an
// exported pack and write a new pack, so a script/scene edit can be shipped to the web preview in
// milliseconds by swapping raw text files into the last full export instead of re-exporting.
import crypto from 'node:crypto';

const MAGIC = 0x43504447; // "GDPC"
const FLAG_REL_FILEBASE = 2;
const ALIGN = 16;

const pad = (n, a) => (a - (n % a)) % a;

/** { version: {format, major, minor, patch}, files: Map<path, Buffer> } */
export function readPck(buf) {
  if (buf.readUInt32LE(0) !== MAGIC) throw new Error('not a Godot pack');
  let o = 4;
  const u32 = () => { const v = buf.readUInt32LE(o); o += 4; return v; };
  const u64 = () => { const v = Number(buf.readBigUInt64LE(o)); o += 8; return v; };
  const format = u32(), major = u32(), minor = u32(), patch = u32();
  const flags = format >= 2 ? u32() : 0;
  const base = format >= 2 ? u64() : 0;
  if (flags & 1) throw new Error('encrypted packs are not supported');
  let dir;
  if (format >= 3) dir = u64();
  else { o += 64; dir = o; }
  o = dir;
  const n = u32();
  const files = new Map();
  for (let i = 0; i < n; i++) {
    const len = u32();
    const p = buf.toString('utf8', o, o + len).replace(/\0+$/, '');
    o += len;
    const off = u64(), size = u64();
    o += 16; // md5
    if (format >= 2) u32(); // per-file flags
    const at = (flags & FLAG_REL_FILEBASE ? base : 0) + off;
    files.set(p, buf.subarray(at, at + size));
  }
  return { version: { format, major, minor, patch }, files };
}

/** Pack in the same format the engine exported (format 3+ layout: header, data, directory). */
export function writePck({ version, files }) {
  const { format = 3, major = 4, minor = 0, patch = 0 } = version || {};
  if (format < 3) throw new Error('pack format ' + format + ' is too old to rewrite');
  const headerLen = 4 * 6 + 8 + 8 + 16 * 4;
  const base = headerLen + pad(headerLen, ALIGN);
  const chunks = [];
  const table = [];
  let off = 0;
  for (const [p, data] of files) {
    table.push({ p, off, size: data.length, md5: crypto.createHash('md5').update(data).digest() });
    chunks.push(data);
    const z = pad(data.length, ALIGN);
    if (z) chunks.push(Buffer.alloc(z));
    off += data.length + z;
  }
  const dirParts = [u32b(table.length)];
  for (const t of table) {
    const name = Buffer.from(t.p, 'utf8');
    const len = name.length + pad(name.length, 4);
    dirParts.push(u32b(len), Buffer.concat([name, Buffer.alloc(len - name.length)]), u64b(t.off), u64b(t.size), t.md5, u32b(0));
  }
  const header = Buffer.alloc(base);
  let o = 0;
  for (const v of [MAGIC, format, major, minor, patch, FLAG_REL_FILEBASE]) { header.writeUInt32LE(v, o); o += 4; }
  header.writeBigUInt64LE(BigInt(base), o); o += 8;
  header.writeBigUInt64LE(BigInt(base + off), o);
  return Buffer.concat([header, ...chunks, ...dirParts]);
}

const u32b = v => { const b = Buffer.alloc(4); b.writeUInt32LE(v); return b; };
const u64b = v => { const b = Buffer.alloc(8); b.writeBigUInt64LE(BigInt(v)); return b; };

/**
 * New pack = exported pack with the given project files replaced by their raw source (Godot loads
 * .gd/.tscn/.tres/.gdshader text at runtime). Exported remaps and the tokenized/binary copies of a
 * replaced file are dropped; `deleted` paths are removed. `extra` entries (e.g. the class cache)
 * overwrite whatever the export had.
 */
export function patchPck(buf, { files = {}, deleted = [], extra = {} }) {
  const pck = readPck(buf);
  const drop = p => {
    pck.files.delete(p);
    pck.files.delete(p + '.remap');
    if (p.endsWith('.gd')) pck.files.delete(p.slice(0, -3) + '.gdc');
  };
  for (const p of deleted) drop(p);
  for (const [p, src] of Object.entries(files)) {
    drop(p);
    if (p === 'project.godot') pck.files.delete('project.binary');
    pck.files.set(p, Buffer.isBuffer(src) ? src : Buffer.from(String(src), 'utf8'));
  }
  for (const [p, data] of Object.entries(extra)) pck.files.set(p, Buffer.isBuffer(data) ? data : Buffer.from(String(data), 'utf8'));
  return writePck(pck);
}
