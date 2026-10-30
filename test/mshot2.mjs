
import fs from 'node:fs';
import { capture } from '../server/shot.mjs';
const [url, out, actFile, w, h] = process.argv.slice(2);
const acts = actFile ? JSON.parse(fs.readFileSync(actFile, 'utf8')) : [];
const r = await capture(url, out, { width: +(w || 390), height: +(h || 844), wait: 5000, mobile: true, port: 9486, actions: acts });
console.log(JSON.stringify((r && r.logs || []).filter(l => /error|exception|eval/i.test(l)).slice(0, 8)));
