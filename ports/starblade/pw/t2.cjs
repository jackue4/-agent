const { chromium } = require('playwright-core');
const PCK = '/api/projects/starblade_port/game.pck?build=9e47cc61cef4f63a8e302c1692e48f88';
(async () => {
  const b = await chromium.launch({ executablePath: 'C:/Program Files/Google/Chrome/Application/chrome.exe', headless: true, args: ['--use-angle=d3d11','--enable-gpu','--ignore-gpu-blocklist'] });
  const ctx = await b.newContext({ viewport: { width: 844, height: 390 }, deviceScaleFactor: 2, isMobile: true, hasTouch: true, userAgent: 'Mozilla/5.0 (Linux; Android 14; Pixel 8) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130 Mobile Safari/537.36' });
  const p = await ctx.newPage();
  const logs = []; p.on('console', m => logs.push(m.type() + ': ' + m.text())); p.on('pageerror', e => logs.push('pageerror: ' + e.message));
  const t0 = Date.now();
  await p.goto('http://localhost:5301/gp.html?pck=' + encodeURIComponent(PCK), { waitUntil: 'load', timeout: 60000 });
  await p.waitForFunction(() => document.getElementById('status')?.style.display === 'none' || !document.getElementById('status')?.offsetParent, null, { timeout: 60000 }).catch(() => {});
  console.log('loaded in', Date.now() - t0, 'ms');
  await p.waitForTimeout(4000);
  const fps = async () => p.evaluate(() => new Promise(r => { const ts = []; const f = t => { ts.push(t); if (ts.length < 181) requestAnimationFrame(f); else { const d = ts.slice(1).map((x, i) => x - ts[i]).sort((a, b) => a - b); r({ avg: (1000 * 180 / (ts[180] - ts[0])).toFixed(1), p95ms: d[Math.floor(d.length * .95)].toFixed(1) }); } }; requestAnimationFrame(f); }));
  console.log('hub fps', JSON.stringify(await fps()));
  const cdp = await ctx.newCDPSession(p);
  const touch = async (type, pts) => cdp.send('Input.dispatchTouchEvent', { type, touchPoints: pts });
  // first touch activates the touch layer
  await touch('touchStart', [{ x: 700, y: 60, id: 9 }]); await touch('touchEnd', []);
  await p.waitForTimeout(500);
  await p.screenshot({ path: '../shot_hub.png' });
  // joystick drag on the left half
  await touch('touchStart', [{ x: 120, y: 280, id: 1 }]);
  for (let i = 1; i <= 8; i++) { await touch('touchMove', [{ x: 120 + i * 6, y: 280 - i * 4, id: 1 }]); await p.waitForTimeout(40); }
  await p.waitForTimeout(800);
  await p.screenshot({ path: '../shot_move.png' });
  await touch('touchEnd', []);
  console.log(logs.filter(l => !/^(debug|verbose)/.test(l) && !/Cross-Origin/.test(l)).slice(-25).join('\n'));
  await b.close();
})();
