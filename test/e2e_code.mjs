// End-to-end run of the code engine against the live server: create a project, send the prompt
// (and optional follow-ups), print the visible build timeline, then dump the design + test results.
// Usage: node test/e2e_code.mjs "<prompt>" ["<follow-up>" ...]   or   --pid=<id> "<follow-up>"
const BASE = process.env.UGC_BASE || 'http://10.0.4.94:5300';
const args = process.argv.slice(2);
const pidArg = (args.find(a => a.startsWith('--pid=')) || '').slice(6);
const prompts = args.filter(a => !a.startsWith('--'));
const api = async (p, body) => {
  const r = await fetch(BASE + '/api' + p, body ? { method: 'POST', headers: { 'content-type': 'application/json' }, body: JSON.stringify(body) } : {});
  const j = await r.json().catch(() => ({}));
  if (!r.ok) throw new Error(p + ' -> ' + r.status + ' ' + (j.error || ''));
  return j;
};
const t0 = Date.now();
const secs = () => ((Date.now() - t0) / 1000).toFixed(0).padStart(4) + 's';
const pid = pidArg || (await api('/projects', { prompt: prompts[0], dimension: '2d' })).id;
console.log('project', pid, BASE + '/editor.html?id=' + pid);
const ctrl = new AbortController();
const res = await fetch(BASE + '/api/projects/' + pid + '/events', { signal: ctrl.signal });
const reader = res.body.getReader();
const dec = new TextDecoder();
let buf = '', ended = 0;
const stats = { writes: 0, patches: 0, tests: [], pushes: 0, errors: [] };
(async () => {
  try {
    for (;;) {
      const { value, done } = await reader.read();
      if (done) break;
      buf += dec.decode(value, { stream: true });
      let i;
      while ((i = buf.indexOf('\n\n')) >= 0) {
        const line = buf.slice(0, i).split('\n').find(l => l.startsWith('data:')); buf = buf.slice(i + 2);
        if (!line) continue;
        let ev; try { ev = JSON.parse(line.slice(5)); } catch { continue; }
        if (ev.type === 'phase') console.log(secs(), '==', ev.text);
        if (ev.type === 'crew') console.log(secs(), '[' + ev.agent + ']', ev.state, ev.text || '');
        if (ev.type === 'thinking' && !(stats.th ||= {})[ev.agent]) { stats.th[ev.agent] = 1; console.log(secs(), '[' + ev.agent + '] first thinking:', ev.text.slice(0, 80)); }
        if (ev.type === 'compile') console.log(secs(), '[' + ev.agent + '] compile', ev.ok ? 'OK' : 'ERR', ev.files.join(','), (ev.errors || []).map(e => e.file + ':' + e.line + ' ' + e.message).join(' | ').slice(0, 300));
        if (ev.type === 'asset') console.log(secs(), 'ASSET', ev.id, ev.state);
        if (ev.type === 'design') console.log(secs(), 'DESIGN', ev.design.title, '| 参考', ev.design.closest_game, ev.design.faithful ? '(复刻)' : '', '|', (ev.design.differences || []).join(' / '), '| modules', (ev.design.modules || []).map(m => m.file).join(','), '| M:', (ev.design.milestones || []).map(m => m.id + m.name).join(' '));
        if (ev.type === 'eval') { (stats.evals ||= []).push(ev.ok); console.log(secs(), 'EVAL', ev.ok ? 'ok' : 'ERR', (ev.step || '').slice(0, 60), ev.shot ? 'shot=' + ev.shot : '', (ev.errors || []).map(e => e.line + ' ' + e.message).join(' | ').slice(0, 200)); }
        if (ev.type === 'ops') for (const o of ev.ops) if (o.op === 'ai_play' || o.op === 'eval') (stats.mirror ||= {})[o.op] = (stats.mirror[o.op] || 0) + 1;
        if (ev.type === 'ops') for (const o of ev.ops) if (o.op === 'pck') { stats.pushes++; console.log(secs(), '>> preview pack v' + o.version, o.label || ''); }
        if (ev.type === 'tool_start' && /generate_asset|web_fetch|list_files|read_file|grep_files/.test(ev.name)) console.log(secs(), '[' + ev.agent + ']', ev.name);
        if (ev.type === 'code_write') { ev.patch ? stats.patches++ : stats.writes++; console.log(secs(), '[' + ev.agent + ']', ev.patch ? 'patch' : 'write', ev.file, ev.lines + 'L', ev.step); }
        if (ev.type === 'ops') for (const o of ev.ops) if (o.op === 'code') { stats.pushes++; console.log(secs(), '>> hot-load to preview', Object.keys(o.files).join(','), o.label); }
        if (ev.type === 'test') { stats.tests.push(ev.ok); console.log(secs(), 'TEST#' + ev.run, ev.ok ? 'PASS' : 'FAIL', ev.result || '', (ev.errors || []).map(e => e.file + ':' + e.line + ' ' + e.message).join(' | ').slice(0, 400), (ev.checks || []).filter(c => !c.ok).map(c => '✗' + c.what).join(' ')); }
        if (ev.type === 'error') { stats.errors.push(ev.message); console.log(secs(), 'ERROR', ev.message); }
        if (ev.type === 'turn_end') { ended++; console.log(secs(), 'TURN END', ev.summary.slice(0, 300), '|', (ev.suggestions || []).join(' / ')); }
      }
    }
  } catch {}
})();
for (const [k, text] of prompts.entries()) {
  if (pidArg || k > 0 || true) await api('/projects/' + pid + '/chat', { text, dimension: '2d' });
  const want = ended + 1;
  const deadline = Date.now() + 25 * 60 * 1000;
  while (ended < want && Date.now() < deadline) await new Promise(r => setTimeout(r, 2000));
}
ctrl.abort();
const p = await api('/projects/' + pid);
const files = p.game.code?.files || {};
console.log(JSON.stringify({ pid, secs: secs().trim(), engine: p.game.meta.engine, title: p.game.meta.title, current: p.game.design?.current, pck: p.pck, files: Object.fromEntries(Object.entries(files).map(([f, s]) => [f, s.split('\n').length])), ...stats }, null, 1));
