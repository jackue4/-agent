// Render a code-engine project's current game through the runner (windowed) and save the frame.
// Usage: node test/code_shot.mjs <pid> <out.jpg>
import fs from 'node:fs';
import { runCodeTest } from '../server/runner.mjs';
const [pid, out = 'test/shots/code.jpg'] = process.argv.slice(2);
const p = JSON.parse(fs.readFileSync(new URL('../data/projects/' + pid + '.json', import.meta.url), 'utf8'));
const r = await runCodeTest(p.game.code.files, { title: p.game.meta.title, palette: p.game.meta.palette }, { shot: true });
if (r.image) fs.writeFileSync(out, Buffer.from(r.image, 'base64'));
console.log(JSON.stringify({ ok: r.ok, result: r.result, errors: r.errors, failed: (r.checks || []).filter(c => !c.ok), n: (r.checks || []).length, ms: r.ms }));
