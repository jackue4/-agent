// Where is the Godot binary?
// The project is self-contained: tools/godot/ ships next to the code. Older checkouts kept the
// binary in the parent directory, and CI may point GODOT_BIN anywhere, so try all three and fail
// with a message that says exactly what to do.
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

export const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const NAMES = ['Godot_v4.7.2-stable_win64_console.exe', 'Godot_v4.7.2-stable_win64.exe', 'godot'];

/** First existing candidate, or null. */
export function findGodot() {
  const env = process.env.GODOT_BIN;
  if (env && fs.existsSync(env)) return env;
  const dirs = [path.join(ROOT, 'tools', 'godot'), path.join(ROOT, '..')];
  for (const d of dirs) for (const n of NAMES) { const p = path.join(d, n); if (fs.existsSync(p)) return p; }
  return null;
}

/** The Godot binary, or throw an actionable error. */
export function godotBin() {
  const p = findGodot();
  if (!p) throw new Error('找不到 Godot 可执行文件：把 Godot_v4.7.2-stable_win64_console.exe 放进 tools/godot/，或设置环境变量 GODOT_BIN');
  return p;
}
