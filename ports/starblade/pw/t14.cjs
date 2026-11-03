const { chromium } = require('playwright-core');
(async () => {
  const b = await chromium.launch({ executablePath: 'C:/Program Files/Google/Chrome/Application/chrome.exe', headless: true, args: ['--use-angle=d3d11','--enable-gpu','--ignore-gpu-blocklist'] });
  const ctx = await b.newContext({ viewport: { width: 844, height: 390 }, isMobile: true, hasTouch: true });
  const q = await ctx.newPage(); const t0=Date.now();
  q.on('response', r => { if (r.status()>=400 || /pck|wasm|gp\.html/.test(r.url())) console.log(((Date.now()-t0)/1000).toFixed(1), r.status(), r.url().slice(0,150)); });
  q.on('console', m => { if (/error|ready|ugc/i.test(m.text())) console.log('C', m.text().slice(0,140)); });
  q.on('requestfinished', r => { if (/pck|wasm/.test(r.url())) console.log(((Date.now()-t0)/1000).toFixed(1),'done',r.url().slice(-60)); });
  await q.goto(process.argv[2] + '/play.html?id=' + (process.argv[3]||'starblade_port'), { waitUntil: 'load', timeout: 60000 });
  await q.waitForTimeout(+process.argv[4]||90000);
  await q.screenshot({ path: '../shot_play.png' });
  console.log('frames', q.frames().map(f=>f.url().slice(0,100)).join(' | '));
  await b.close(); })();
