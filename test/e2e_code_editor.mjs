// Open a finished code-engine project in the editor (web runtime) and capture the chat + preview.
import { capture } from '../server/shot.mjs';
const id = process.argv[2];
const r = await capture('http://10.0.4.94:5300/editor.html?id=' + id, 'test/shots/code_editor_' + id + '.png', { wait: 16000, port: 9483 });
console.log(r.logs.filter(l => /error|exception|code_status/i.test(l) && !/favicon|404/.test(l)).slice(-10).join('\n') || 'no errors');
