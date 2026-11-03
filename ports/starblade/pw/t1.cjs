const { chromium } = require('playwright-core');
(async () => {
  const b = await chromium.launch({ executablePath: 'C:/Program Files/Google/Chrome/Application/chrome.exe', headless: true, args: ['--use-angle=d3d11','--enable-gpu','--ignore-gpu-blocklist'] });
  const ctx = await b.newContext({ viewport: { width: 844, height: 390 }, deviceScaleFactor: 2, isMobile: true, hasTouch: true, userAgent: 'Mozilla/5.0 (Linux; Android 14; Pixel 8) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130 Mobile Safari/537.36' });
  const p = await ctx.newPage();
  const logs = []; p.on('console', m => logs.push(m.type() + ': ' + m.text())); p.on('pageerror', e => logs.push('pageerror: ' + e.message));
  await p.goto('http://10.0.4.94:5301/play.html?id=starblade_port', { waitUntil: 'load', timeout: 60000 });
  await p.waitForTimeout(20000);
  await p.screenshot({ path: '../shot_hub.png' });
  // fps sample via rAF
  const fps = await p.evaluate(() => new Promise(r => { let n = 0; const t0 = performance.now(); const f = () => { n++; if (performance.now() - t0 < 3000) requestAnimationFrame(f); else r(n / 3); }; requestAnimationFrame(f); }));
  console.log('rAF fps', fps.toFixed(1));
  const frames = p.frames().map(f => f.url()); console.log(frames.join('\n'));
  console.log(logs.filter(l => !/^(debug|verbose)/.test(l)).slice(-25).join('\n'));
  await b.close();
})();
