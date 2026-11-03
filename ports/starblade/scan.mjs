import fs from 'node:fs'; import path from 'node:path';
import { scanIssues } from '../../server/gproject.mjs'; import { compatibilityIssues } from '../../server/capabilities.mjs';
const root = process.argv[2]; const out = [];
const walk = d => { for (const e of fs.readdirSync(d, { withFileTypes: true })) { const f = path.join(d, e.name); if (e.isDirectory()) walk(f); else if (/\.(gd|tscn|gdshader|godot|tres)$/.test(e.name)) { const rel = path.relative(root, f).replace(/\\/g, '/'); const s = fs.readFileSync(f, 'utf8'); out.push(...scanIssues(rel, s), ...compatibilityIssues(rel, s)); } } };
walk(root); console.log(out.join('\n') || 'clean');

