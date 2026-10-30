// Re-publish a project with a fresh in-engine cover snapshot (editor overview, or play view with --play).
import { capture } from './shot.mjs';
const args = process.argv.slice(2);
const play = args.includes('--play');
const [id, author, prompt] = args.filter(a => a !== '--play');
const js = "new Promise(res => { const w = document.getElementById('rt').contentWindow; addEventListener('message', e => { const p = e.data && e.data.payload; if (p && p.type === 'snapshot') res(p.data); }); w.ugcReceive(JSON.stringify({ type: 'snapshot', req: 's' })); setTimeout(() => res(null), 5000); })"
  + ".then(async data => { const r = await fetch('/api/projects/" + id + "/publish', { method: 'POST', headers: { 'content-type': 'application/json' }, body: JSON.stringify({ cover: data, author: " + JSON.stringify(author) + ", prompt: " + JSON.stringify(prompt) + " }) }); return (data ? data.length : 0) + ' ' + r.status; })";
const actions = play
  ? [{ type: 'eval', js: "document.querySelector('#modeSeg [data-m=play]').click(),'ok'" }, { type: 'wait', ms: 4000 }, { type: 'eval', js }]
  : [{ type: 'eval', js }];
const r = await capture('http://10.0.4.94:5300/editor.html?id=' + id, process.env.TEMP + '\\seed.png', { wait: 30000, port: 9431, actions });
console.log(r.logs.filter(l => /eval|exception/.test(l)).join('\n'));
