// Headless Chrome/Edge screenshot + console capture via raw CDP (no deps).
import { spawn } from 'node:child_process';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';

const CANDIDATES = [
  'C:/Program Files (x86)/Microsoft/Edge/Application/msedge.exe',
  'C:/Program Files/Google/Chrome/Application/chrome.exe',
  'C:/Program Files (x86)/Google/Chrome/Application/chrome.exe',
];
export function findBrowser() { return CANDIDATES.find(p => fs.existsSync(p)); }

const sleep = ms => new Promise(r => setTimeout(r, ms));

export async function capture(url, out, { width = 1440, height = 860, wait = 6000, actions = [], port = 9411, mobile = false } = {}) {
  const exe = findBrowser();
  if (!exe) throw new Error('no browser');
  const prof = path.join(os.tmpdir(), 'ugcshot' + port);
  fs.rmSync(prof, { recursive: true, force: true });
  const proc = spawn(exe, ['--headless=new', '--remote-debugging-port=' + port, '--user-data-dir=' + prof,
    '--window-size=' + width + ',' + height, '--use-angle=swiftshader', '--enable-unsafe-swiftshader',
    '--autoplay-policy=no-user-gesture-required', '--disable-gpu-sandbox', '--no-first-run', '--no-default-browser-check',
    '--hide-scrollbars', 'about:blank'], { stdio: 'ignore' });
  try {
    let targets = null;
    for (let i = 0; i < 40; i++) {
      await sleep(250);
      try { targets = await (await fetch('http://127.0.0.1:' + port + '/json/list')).json(); } catch { continue; }
      if (targets && targets.length) break;
    }
    const page = targets.find(t => t.type === 'page');
    const ws = new WebSocket(page.webSocketDebuggerUrl);
    const logs = [];
    let id = 0;
    const pending = new Map();
    await new Promise(r => ws.addEventListener('open', r));
    ws.addEventListener('message', e => {
      const m = JSON.parse(e.data);
      if (m.id && pending.has(m.id)) { pending.get(m.id)(m); pending.delete(m.id); }
      if (m.method === 'Runtime.consoleAPICalled') logs.push('[' + m.params.type + '] ' + m.params.args.map(a => a.value ?? a.description ?? '').join(' '));
      if (m.method === 'Runtime.exceptionThrown') logs.push('[exception] ' + (m.params.exceptionDetails.exception?.description || m.params.exceptionDetails.text));
      if (m.method === 'Log.entryAdded') logs.push('[' + m.params.entry.level + '] ' + m.params.entry.text);
    });
    const cmd = (method, params = {}) => new Promise(res => { const i = ++id; pending.set(i, res); ws.send(JSON.stringify({ id: i, method, params })); });
    await cmd('Runtime.enable'); await cmd('Log.enable'); await cmd('Page.enable');
    await cmd('Emulation.setDeviceMetricsOverride', { width, height, deviceScaleFactor: 1, mobile });
  // phones: coarse pointer + touch events, so touch-specific UI paths are exercised
  if (mobile) await cmd('Emulation.setTouchEmulationEnabled', { enabled: true, maxTouchPoints: 5 });
    await cmd('Page.navigate', { url });
    await sleep(wait);
    for (const a of actions) {
      if (a.type === 'eval') { const r = await cmd('Runtime.evaluate', { expression: a.js, awaitPromise: true, returnByValue: true }); logs.push('[eval] ' + JSON.stringify(r.result?.result?.value)); }
      else if (a.type === 'click') await cmd('Input.dispatchMouseEvent', { type: 'mousePressed', x: a.x, y: a.y, button: 'left', clickCount: 1 }), await cmd('Input.dispatchMouseEvent', { type: 'mouseReleased', x: a.x, y: a.y, button: 'left', clickCount: 1 });
      else if (a.type === 'key') { await cmd('Input.dispatchKeyEvent', { type: 'keyDown', key: a.key, code: a.code, windowsVirtualKeyCode: a.vk, text: a.text }); await cmd('Input.dispatchKeyEvent', { type: 'keyUp', key: a.key, code: a.code, windowsVirtualKeyCode: a.vk }); }
      else if (a.type === 'wait') await sleep(a.ms);
      else if (a.type === 'shot') { const s = await cmd('Page.captureScreenshot', { format: 'png' }); fs.writeFileSync(a.path, Buffer.from(s.result.data, 'base64')); }
    }
    const s = await cmd('Page.captureScreenshot', { format: 'png' });
    fs.writeFileSync(out, Buffer.from(s.result.data, 'base64'));
    ws.close();
    return { out, logs: logs.slice(-80) };
  } finally { proc.kill(); }
}

if (process.argv[1] && process.argv[1].endsWith('shot.mjs')) {
  const [url, out, waitArg] = process.argv.slice(2);
  const r = await capture(url, out, { wait: +(waitArg || 6000) });
  console.log(r.logs.join('\n'));
}
