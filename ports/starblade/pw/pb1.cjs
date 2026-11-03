const { chromium } = require('playwright-core');
const fs = require('fs');
(async () => {
  const b = await chromium.launch({ executablePath: 'C:/Program Files/Google/Chrome/Application/chrome.exe', headless: true, args: ['--use-angle=d3d11','--enable-gpu','--ignore-gpu-blocklist'] });
  const ctx = await b.newContext({ viewport: { width: 844, height: 390 }, deviceScaleFactor: 2, isMobile: true, hasTouch: true });
  const q = await ctx.newPage(); const errs=[]; const logs=[];
  q.on('console', m => { const t=m.text().slice(0,200); if (m.type()==='error') errs.push(t); else if (/fps|ERROR|SCRIPT/i.test(t)) logs.push(t); });
  await q.goto('http://10.0.4.94:5300/play.html?id=paperblade_port', { waitUntil: 'load', timeout: 60000 });
  await q.waitForTimeout(35000);
  const D = 'D:/ugc-ai/ports/paperblade/';
  await q.screenshot({ path: D+'shot_title.png' });
  // find canvas (may be inside iframe)
  let fr = q.mainFrame(); for (const f of q.frames()) { if (await f.$('canvas').catch(()=>null)) { fr = f; } }
  const c = await fr.$('canvas'); const box = await c.boundingBox(); console.log('canvas', JSON.stringify(box));
  const tap = async (x, y) => { await q.touchscreen.tap(box.x + box.width * x, box.y + box.height * y); await q.waitForTimeout(900); };
  // title "开始修行" button ~ center lower; then first map card
  await q.screenshot({ path: D+'shot_t0.png' });
  fs.writeFileSync(D+'box.json', JSON.stringify(box));
  console.log('errors', errs.length, errs.slice(0,6).join(' | ')); console.log('logs', logs.slice(0,6).join(' | '));
  await b.close(); })();
