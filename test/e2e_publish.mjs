// Opens the editor for a project, presses Publish, and captures the publish dialog (cover preview).
// Does not confirm the dialog. Usage: node test/e2e_publish.mjs <projectId>
import { capture } from '../server/shot.mjs';
const id = process.argv[2] || 'bd3b527c55';
const r = await capture('http://10.0.4.94:5300/editor.html?id=' + id, 'test/shots/web_publish.png', {
  wait: 25000, port: 9480,
  actions: [{ type: 'eval', js: "document.getElementById('pubBtn').click(),'ok'" }, { type: 'wait', ms: 6000 }],
});
const bad = r.logs.filter(l => /exception|Uncaught/i.test(l));
console.log(bad.length ? bad.join('\n') : 'clean');
process.exit(bad.length ? 1 : 0);
