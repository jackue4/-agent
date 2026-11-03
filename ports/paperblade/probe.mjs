// Capture the published paperblade game in headless Chrome: title -> start -> map -> play. Usage: node probe.mjs <prefix> [gpu]
import { spawn } from 'node:child_process';
import fs from 'node:fs'; import os from 'node:os'; import path from 'node:path';
const pre = process.argv[2] || 'probe'; const gpu = process.argv[3] === 'gpu';
const url = process.env.URL || 'http://10.0.4.94:5300/play.html?id=paperblade_port';
const exe = 'C:/Program Files/Google/Chrome/Application/chrome.exe';
const port = 9471 + (gpu ? 1 : 0); const prof = path.join(os.tmpdir(), 'pbprobe' + port);
fs.rmSync(prof, { recursive: true, force: true });
const W = 1280, H = 720;
const flags = ['--headless=new', '--remote-debugging-port=' + port, '--user-data-dir=' + prof, '--window-size=' + W + ',' + H,
  '--autoplay-policy=no-user-gesture-required', '--no-first-run', '--hide-scrollbars',
  ...(gpu ? ['--use-angle=d3d11', '--enable-gpu', '--ignore-gpu-blocklist'] : ['--use-angle=swiftshader', '--enable-unsafe-swiftshader']), 'about:blank'];
const proc = spawn(exe, flags, { stdio: 'ignore' });
const sleep = ms => new Promise(r => setTimeout(r, ms));
try {
  let targets; for (let i = 0; i < 40; i++) { await sleep(250); try { targets = await (await fetch('http://127.0.0.1:' + port + '/json/list')).json(); if (targets.length) break; } catch {} }
  const ws = new WebSocket(targets.find(t => t.type === 'page').webSocketDebuggerUrl);
  const logs = []; let id = 0; const pending = new Map();
  await new Promise(r => ws.addEventListener('open', r));
  ws.addEventListener('message', e => { const m = JSON.parse(e.data); if (m.id && pending.has(m.id)) { pending.get(m.id)(m); pending.delete(m.id); }
    if (m.method === 'Runtime.consoleAPICalled') logs.push('[' + m.params.type + '] ' + m.params.args.map(a => a.value ?? a.description ?? '').join(' '));
    if (m.method === 'Runtime.exceptionThrown') logs.push('[exception] ' + (m.params.exceptionDetails.exception?.description || m.params.exceptionDetails.text)); });
  const cmd = (method, params = {}) => new Promise(res => { const i = ++id; pending.set(i, res); ws.send(JSON.stringify({ id: i, method, params })); });
  await cmd('Runtime.enable'); await cmd('Page.enable');
  await cmd('Emulation.setDeviceMetricsOverride', { width: W, height: H, deviceScaleFactor: 1, mobile: false });
  await cmd('Page.navigate', { url });
  const shot = async n => { const s = await cmd('Page.captureScreenshot', { format: 'png' }); fs.writeFileSync(pre + '_' + n + '.png', Buffer.from(s.result.data, 'base64')); };
  const click = async (x, y) => { await cmd('Input.dispatchMouseEvent', { type: 'mousePressed', x, y, button: 'left', clickCount: 1 }); await sleep(60); await cmd('Input.dispatchMouseEvent', { type: 'mouseReleased', x, y, button: 'left', clickCount: 1 }); };
  const key = async (k, code, vk, ms = 80) => { await cmd('Input.dispatchKeyEvent', { type: 'keyDown', key: k, code, windowsVirtualKeyCode: vk }); await sleep(ms); await cmd('Input.dispatchKeyEvent', { type: 'keyUp', key: k, code, windowsVirtualKeyCode: vk }); };
  await sleep(+(process.env.WAIT || 16000));
  await shot('1title');
  const gl = await cmd('Runtime.evaluate', { expression: "(()=>{const f=document.querySelector('iframe');const d=f?f.contentDocument:document;const c=d.querySelector('canvas');const g=c&&(c.getContext('webgl2'));const e=g&&g.getExtension('WEBGL_debug_renderer_info');return e?g.getParameter(e.UNMASKED_RENDERER_WEBGL):'n/a'})()", returnByValue: true });
  logs.push('[renderer] ' + JSON.stringify(gl.result?.result?.value));
  const clicks = JSON.parse(process.env.CLICKS || '[[640,500],[640,400]]');
  for (const [x, y] of clicks) { await click(x, y); await sleep(1500); }
  await shot('2after_clicks');
  await key('Enter', 'Enter', 13); await sleep(3000); await shot('3play');
  await key('d', 'KeyD', 68, 1500); await sleep(4000); await shot('4later');
  ws.close();
  console.log(logs.filter(l => !/favicon/.test(l)).slice(-40).join('\n'));
} finally { proc.kill(); }
