const { chromium } = require('playwright-core');
const PCK = '/api/projects/starblade_port/game.pck?build=fce3a7ffb18f72abf6d680110b6de04a';
(async () => {
  const b = await chromium.launch({ executablePath: 'C:/Program Files/Google/Chrome/Application/chrome.exe', headless: true, args: ['--use-angle=d3d11','--enable-gpu','--ignore-gpu-blocklist'] });
  const ctx = await b.newContext({ viewport: { width: 844, height: 390 }, deviceScaleFactor: 2, isMobile: true, hasTouch: true, userAgent: 'Mozilla/5.0 (Linux; Android 14; Pixel 8) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130 Mobile Safari/537.36' });
  await ctx.addInitScript(() => { window.__emits = []; window.addEventListener('message', e => { if (e.data && e.data.__ugc) window.__emits.push(e.data.payload); }); });
  // gp.html posts to parent; when top-level, parent===window so we capture it.
  const p = await ctx.newPage();
  const logs = []; p.on('console', m => logs.push(m.type() + ': ' + m.text())); p.on('pageerror', e => logs.push('pageerror: ' + e.message));
  await p.goto('http://localhost:5301/gp.html?pck=' + encodeURIComponent(PCK), { waitUntil: 'load', timeout: 60000 });
  await p.waitForFunction(() => window.__emits.some(x => x.type === 'ready'), null, { timeout: 90000 }).catch(() => console.log('no ready emit'));
  await p.waitForTimeout(3000);
  const evalGd = async code => { await p.evaluate(c => window.ugcReceive && window.ugcReceive(JSON.stringify({ type: 'eval', code: c })), code); await p.waitForTimeout(400); };
  const fps = async (secs = 3) => p.evaluate(s => new Promise(r => { const ts = []; const end = performance.now() + s * 1000; const f = t => { ts.push(t); if (t < end) requestAnimationFrame(f); else { const d = ts.slice(1).map((x, i) => x - ts[i]).sort((a, b) => a - b); r({ avg: +(1000 * (ts.length - 1) / (ts[ts.length - 1] - ts[0])).toFixed(1), p95ms: +d[Math.floor(d.length * .95)].toFixed(1), worst: +d[d.length - 1].toFixed(1) }); } }; requestAnimationFrame(f); }), secs);
  const cdp = await ctx.newCDPSession(p);
  const touch = (type, pts) => cdp.send('Input.dispatchTouchEvent', { type, touchPoints: pts });
  const tap = async (x, y, ms = 80) => { await touch('touchStart', [{ x, y, id: 5 }]); await p.waitForTimeout(ms); await touch('touchEnd', []); };
  const out = {};
  await tap(700, 60);
  out.hub = await fps();
  await evalGd('game.start_raid()');
  await p.waitForTimeout(2500);
  await p.screenshot({ path: '../shot_cards.png' });
  out.cards = await fps(2);
  await evalGd('var g = 0\nwhile game.mode == "skills" and g < 4:\n\tgame.choose_skill(str(game.choices[0].id)); g += 1\n\tawait game.get_tree().create_timer(.3).timeout');
  await p.waitForTimeout(2000);
  await p.screenshot({ path: '../shot_raid.png' });
  out.raid_idle = await fps();
  // combat: hold joystick up while tapping attack, then dash
  await touch('touchStart', [{ x: 130, y: 280, id: 1 }]);
  await touch('touchMove', [{ x: 150, y: 235, id: 1 }]);
  const combat = fps(6);
  for (let i = 0; i < 18; i++) {
    await touch('touchMove', [{ x: 150, y: 235, id: 1 }, { x: 769, y: 325, id: 2 }]);
    await touch('touchStart', [{ x: 150, y: 235, id: 1 }, { x: 769, y: 325, id: 2 }]);
    await p.waitForTimeout(120);
    await touch('touchEnd', [{ x: 150, y: 235, id: 1 }]);
    await p.waitForTimeout(150);
    if (i % 6 === 5) { await touch('touchStart', [{ x: 150, y: 235, id: 1 }, { x: 691, y: 337, id: 3 }]); await p.waitForTimeout(60); await touch('touchEnd', [{ x: 150, y: 235, id: 1 }]); }
  }
  out.combat = await combat;
  await p.screenshot({ path: '../shot_combat.png' });
  await touch('touchEnd', []);
  await cdp.send('Emulation.setCPUThrottlingRate', { rate: 4 });
  out.combat_cpu4x = await fps(4);
  await cdp.send('Emulation.setCPUThrottlingRate', { rate: 1 });
  const errs = window => 0;
  out.emits = await p.evaluate(() => window.__emits.filter(x => /error/.test(x.type)).slice(0, 8));
  console.log(JSON.stringify(out, null, 1));
  console.log(logs.filter(l => /error|ERROR|SCRIPT/.test(l) && !/Cross-Origin|favicon|404/.test(l)).slice(-15).join('\n'));
  await b.close();
})();
