const { chromium } = require('playwright-core');
(async () => {
  const b = await chromium.launch({ executablePath: 'C:/Program Files/Google/Chrome/Application/chrome.exe', headless: true, args: ['--use-angle=d3d11','--enable-gpu','--ignore-gpu-blocklist'] });
  const ctx = await b.newContext({ viewport: { width: 844, height: 390 }, deviceScaleFactor: 2, isMobile: true, hasTouch: true });
  const q = await ctx.newPage(); const seen = new Map();
  q.on('console', m => { const t = m.type()+': '+m.text().slice(0,260); seen.set(t, (seen.get(t)||0)+1); });
  await q.goto('http://10.0.4.94:5300/play.html?id=paperblade_port', { waitUntil: 'load', timeout: 60000 });
  await q.waitForTimeout(30000);
  await q.touchscreen.tap(422, 285); await q.waitForTimeout(1200);
  await q.touchscreen.tap(170, 195); await q.waitForTimeout(8000);
  for (const [k,v] of seen) if (!/Cross-Origin/.test(k)) console.log(v+'x '+k);
  await b.close(); })();
