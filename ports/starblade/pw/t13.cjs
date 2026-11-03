const { chromium } = require('playwright-core');
(async () => {
  const b = await chromium.launch({ executablePath: 'C:/Program Files/Google/Chrome/Application/chrome.exe', headless: true, args: ['--use-angle=d3d11','--enable-gpu','--ignore-gpu-blocklist'] });
  const ctx = await b.newContext({ viewport: { width: 390, height: 844 }, deviceScaleFactor: 2, isMobile: true, hasTouch: true });
  const p = await ctx.newPage();
  await p.goto('http://10.0.4.94:5300/', { waitUntil: 'networkidle', timeout: 60000 });
  await p.waitForTimeout(1500);
  const rows = await p.evaluate(() => [...document.querySelectorAll('#feed section')].map(s => [s.querySelector('h2')?.textContent, [...s.querySelectorAll('[data-id],[data-game]')].map(e=>e.dataset.id||e.dataset.game).slice(0,8)]));
  console.log(JSON.stringify(rows));
  const txt = await p.evaluate(() => document.querySelector('#feed')?.innerText.includes('星刃'));
  console.log('home has 星刃', txt);
  const el = await p.$('text=星刃：回收协议'); if (el) { await el.scrollIntoViewIfNeeded(); await p.waitForTimeout(800); }
  await p.screenshot({ path: '../shot_home.png' });
  const q = await ctx.newPage(); const errs=[]; q.on('console', m => { if (m.type()==='error') errs.push(m.text().slice(0,140)); });
  await q.setViewportSize({ width: 844, height: 390 });
  await q.goto('https://ideas-ebooks-ian-advise.trycloudflare.com/play.html?id=starblade_port', { waitUntil: 'load', timeout: 60000 });
  await q.waitForTimeout(60000);
  await q.screenshot({ path: '../shot_play.png' });
  console.log('play errors', errs.length, errs.slice(0,5).join(' | '));
  await b.close(); })();

