const { chromium } = require('playwright-core');
(async () => {
  const b = await chromium.launch({ executablePath: 'C:/Program Files/Google/Chrome/Application/chrome.exe', headless: true, args: ['--use-angle=d3d11','--enable-gpu','--ignore-gpu-blocklist'] });
  const ctx = await b.newContext({ viewport: { width: 1280, height: 720 } });
  const p = await ctx.newPage(); const logs=[];
  p.on('console', m => { if (/error|receipt/i.test(m.text())) logs.push(m.text().slice(0,160)); });
  p.on('response', r => { if (/preview_receipt/.test(r.url())) logs.push('RECEIPT '+r.status()); });
  await p.goto('http://10.0.4.94:5300/editor.html?id=starblade_port', { waitUntil: 'load', timeout: 60000 });
  for (let i=0;i<60;i++){ await p.waitForTimeout(2000); if (logs.some(l=>l.startsWith('RECEIPT'))) break; }
  await p.waitForTimeout(1500);
  console.log(logs.slice(-15).join('\n')); await b.close(); })();
