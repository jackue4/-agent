// Web runtime check for AI-written games: load test/code_sample.json into the exported runtime
// (game/index.html), wait for code_status, click two cards and confirm scoring works in WASM.
import fs from 'node:fs';
import { capture } from '../server/shot.mjs';
const sample = JSON.parse(fs.readFileSync(new URL('./code_sample.json', import.meta.url), 'utf8'));
const msg = JSON.stringify({ type: 'load', spec: sample.spec, assets: {}, mode: 'play' });
const js = "new Promise(res => { const out = []; window.ugcEmit = j => { out.push(j); }; const send = () => window.ugcReceive(" + JSON.stringify(msg) + "); const t = setInterval(() => { if (window.ugcReceive) { clearInterval(t); send(); setTimeout(() => res(out.join('\\n')), 3500); } }, 200); })";
const r = await capture('http://10.0.4.94:5300/game/index.html', 'test/shots/code_web_loaded.png', {
  width: 1280, height: 720, wait: 9000, port: 9482,
  actions: [
    { type: 'eval', js },
    { type: 'key', key: 'Enter', code: 'Enter', vk: 13, text: '\r' },
    { type: 'wait', ms: 800 },
    { type: 'click', x: 248, y: 488 }, { type: 'wait', ms: 300 },
    { type: 'click', x: 362, y: 488 }, { type: 'wait', ms: 900 },
    { type: 'shot', path: 'test/shots/code_web_scored.png' },
  ],
});
console.log(r.logs.filter(l => /eval|code_status|error|SCRIPT/i.test(l)).slice(-12).join('\n'));
