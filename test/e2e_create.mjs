// End-to-end creation run against the live server: create a project, send the prompt, follow the
// agent's SSE stream until the turn ends and every asset settles, then print a quality report.
// Usage: node test/e2e_create.mjs <2d|3d> "<prompt>" [--no-wait-assets]
const BASE = process.env.UGC_BASE || 'http://10.0.4.94:5300';
const [dim = '2d', prompt = '一只小狐狸在森林里收集蘑菇'] = process.argv.slice(2);
const waitAssets = !process.argv.includes('--no-wait-assets');
const api = async (p, body) => {
  const r = await fetch(BASE + '/api' + p, body ? { method: 'POST', headers: { 'content-type': 'application/json' }, body: JSON.stringify(body) } : {});
  const j = await r.json().catch(() => ({}));
  if (!r.ok) throw new Error(p + ' -> ' + r.status + ' ' + (j.error || ''));
  return j;
};
const t0 = Date.now();
const secs = () => ((Date.now() - t0) / 1000).toFixed(0) + 's';
const proj = await api('/projects', { prompt, dimension: dim });
const pid = proj.id;
console.log('project', pid, BASE + '/editor.html?id=' + pid);

// follow SSE
const ctrl = new AbortController();
const res = await fetch(BASE + '/api/projects/' + pid + '/events', { signal: ctrl.signal });
const reader = res.body.getReader();
const dec = new TextDecoder();
let buf = '', turnDone = false, tools = [], checks = [], errors = [];
const pump = (async () => {
  try {
    for (;;) {
      const { value, done } = await reader.read();
      if (done) break;
      buf += dec.decode(value, { stream: true });
      let i;
      while ((i = buf.indexOf('\n\n')) >= 0) {
        const chunk = buf.slice(0, i); buf = buf.slice(i + 2);
        const line = chunk.split('\n').find(l => l.startsWith('data:'));
        if (!line) continue;
        let ev; try { ev = JSON.parse(line.slice(5)); } catch { continue; }
        if (ev.type === 'tool_start') { tools.push(ev.name); console.log(secs(), 'tool', ev.name); }
        if (ev.type === 'check') { checks.push(ev); console.log(secs(), 'check', ev.ok ? 'OK' : 'issues', (ev.issues || []).map(x => x.message || x).join(' | ').slice(0, 300)); }
        if (ev.type === 'error') { errors.push(ev.message); console.log(secs(), 'ERROR', ev.message); }
        if (ev.type === 'asset' && (ev.state === 'ready' || ev.state === 'failed')) console.log(secs(), 'asset', ev.id, ev.state);
        if (ev.type === 'done' || ev.type === 'turn_end' || ev.type === 'idle') turnDone = true;
      }
    }
  } catch {}
})();
await api('/projects/' + pid + '/chat', { text: prompt, dimension: dim });
const deadline = Date.now() + 15 * 60 * 1000;
for (;;) {
  await new Promise(r => setTimeout(r, 4000));
  const p = await api('/projects/' + pid);
  const assets = Object.values(p.game.assets || {});
  const pending = assets.filter(a => a.state !== 'ready' && a.state !== 'failed').length;
  if ((turnDone || p.running === false) && (!waitAssets || pending === 0) && tools.length) break;
  if (Date.now() > deadline) { console.log('TIMEOUT'); break; }
}
ctrl.abort();
const p = await api('/projects/' + pid);
const chk = await api('/projects/' + pid + '/check').catch(e => ({ error: e.message }));
const g = p.game, ents = Object.values(g.entities || {});
const kinds = {};
for (const e of ents) kinds[e.kind] = (kinds[e.kind] || 0) + 1;
console.log(JSON.stringify({
  pid, secs: secs(), title: g.meta?.title, palette: g.meta?.palette, art_bible: g.meta?.art_bible,
  world: Object.fromEntries(Object.entries(g.world || {}).filter(([k]) => !/color/.test(k))),
  rules: g.rules, kinds, assets: Object.fromEntries(Object.entries(g.assets || {}).map(([k, a]) => [k, a.state])),
  check: chk.ok, issues: (chk.issues || []).map(i => i.level + ':' + (i.message || '')).slice(0, 8), path: chk.path && { critical: chk.path.criticalPath?.length, hardest: chk.path.hardestJump, unreachable: chk.path.unreachable?.length },
  errors,
}, null, 1));
