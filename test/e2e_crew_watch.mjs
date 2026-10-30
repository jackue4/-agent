// Watch a crew build live in the editor: creates a project with ?go=<prompt> so the editor itself sends
// it, then screenshots the editor every N seconds (chat lanes + preview drones).
// Usage: node test/e2e_crew_watch.mjs "<prompt>" [interval_s=25] [count=10]
import { capture } from '../server/shot.mjs';
const [prompt = '做一个小丑牌', every = '25', count = '10'] = process.argv.slice(2);
const r = await fetch('http://10.0.4.94:5300/api/projects', { method: 'POST', headers: { 'content-type': 'application/json' }, body: JSON.stringify({ prompt, dimension: '2d' }) });
const { id } = await r.json();
console.log('project', id);
const actions = [];
for (let i = 0; i < Number(count); i++) actions.push({ type: 'wait', ms: Number(every) * 1000 }, { type: 'shot', path: 'test/shots/crew_' + String(i).padStart(2, '0') + '.png' });
const res = await capture('http://10.0.4.94:5300/editor.html?id=' + id + '&go=' + encodeURIComponent(prompt), 'test/shots/crew_end.png', { wait: 3000, port: 9484, actions });
console.log(res.logs.filter(l => /error|exception/i.test(l) && !/favicon|404/.test(l)).slice(-12).join('\n') || 'no errors');
