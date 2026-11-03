const { chromium } = require('playwright-core');
(async () => {
  const b = await chromium.launch({ executablePath: 'C:/Program Files/Google/Chrome/Application/chrome.exe', headless: false, args: ['--use-angle=d3d11','--enable-gpu','--ignore-gpu-blocklist'] });
  const ctx = await b.newContext({ viewport: { width: 844, height: 390 }, deviceScaleFactor: 2, isMobile: true, hasTouch: true });
  const q = await ctx.newPage(); q.on('console', m => { if (/OpenGL API/.test(m.text())) console.log(m.text().slice(0,200)); }); const errs=[];
  q.on('console', m => { if (m.type()==='error' && !/Cross-Origin|Secure Context|missing:|^Error$/.test(m.text())) errs.push(m.text().slice(0,200)); });
  await q.addInitScript(() => { try { localStorage.setItem('pbdbg', 'red'); } catch (e) {} });
  await q.goto('http://10.0.4.94:5300/play.html?id=paperblade_port', { waitUntil: 'load', timeout: 60000 });
  await q.waitForTimeout(30000);
  const D = 'D:/ugc-ai/ports/paperblade/';
  const W=844,H=390;
  const tap = async (x, y, w=1200) => { await q.touchscreen.tap(W*x, H*y); await q.waitForTimeout(w); };
  await q.screenshot({ path: D+'s1_title.png' });
  await tap(0.5, 0.73);
 await q.screenshot({ path: D+'s2_maps.png' }); await tap(0.2, 0.5, 4000);
  await q.screenshot({ path: D+'s3_play.png' });
  const cdp = await ctx.newCDPSession(q);
  const tp = (type, x, y) => cdp.send('Input.dispatchTouchEvent', { type, touchPoints: type==='touchEnd'?[]:[{ x, y, id: 1 }] });
  await tp('touchStart', 200, 280);
  for (let i=1;i<=10;i++){ await tp('touchMove', 200+i*7, 280-i*3); await q.waitForTimeout(40); }
  await q.waitForTimeout(2500);
  await q.screenshot({ path: D+'s4_joy.png' });
  await tp('touchEnd');
  await q.waitForTimeout(12000);
  await q.screenshot({ path: D+'s5_later.png' });
  await tap(0.33, 0.5, 1500); await q.screenshot({ path: D+'s6_red.png' });
  console.log('errors', errs.length, errs.slice(0,6).join(' | '));
  await b.close(); })();