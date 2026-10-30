import fs from 'node:fs';
import path from 'node:path';
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const stage = path.join(root, 'artifacts', 'inworld', 'workshop-build');
fs.mkdirSync(stage, { recursive: true });
fs.cpSync(path.join(root, 'workshop'), stage, { recursive: true });
fs.cpSync(path.join(root, 'gp_template', 'addons'), path.join(stage, 'addons'), { recursive: true, filter: p => !p.includes('.godot') });
// This shared waiting scene never identifies itself as a generated game's build.
fs.rmSync(path.join(stage, 'addons', 'ugc', 'build.json'), { force: true });
fs.copyFileSync(path.join(root, 'gp_template', 'export_presets.cfg'), path.join(stage, 'export_presets.cfg'));
const godot = process.env.GODOT_BIN || path.join(root, 'tools', 'godot', 'Godot_v4.7.2-stable_win64_console.exe');
const output = path.join(root, 'web', 'workshop.pck');
const candidate = path.join(root, 'web', 'workshop.next.pck');
for (const args of [['--headless', '--path', stage, '--import'], ['--headless', '--path', stage, '--export-pack', 'Web', candidate]]) {
  const result = spawnSync(godot, args, { encoding: 'utf8', windowsHide: true, timeout: 180000 });
  process.stdout.write(result.stdout || '');
  process.stderr.write(result.stderr || '');
  if (result.error || result.status !== 0 || /SCRIPT ERROR:|Parse Error:/.test((result.stdout || '') + (result.stderr || ''))) throw result.error || new Error('workshop build failed');
}
fs.renameSync(candidate, output);
console.log('Built web/workshop.pck');
