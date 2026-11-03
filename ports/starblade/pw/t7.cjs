const { chromium } = require('playwright-core');
const PCK = '/api/projects/starblade_port/game.pck?build=' + process.argv[2];
(async () => {
  const b = await chromium.launch({ executablePath: 'C:/Program Files/Google/Chrome/Application/chrome.exe', headless: true, args: ['--use-angle=d3d11','--enable-gpu','--ignore-gpu-blocklist'] });
  const ctx = await b.newContext({ viewport: { width: 844, height: 390 }, deviceScaleFactor: 2, isMobile: true, hasTouch: true });
  await ctx.addInitScript(() => { window.__emits = []; window.addEventListener('message', e => { if (e.data && e.data.__ugc) window.__emits.push(e.data.payload); });
    window.__long = []; let last = 0; const f = t => { if (last && t - last > 100) window.__long.push([Math.round(last), Math.round(t - last)]); last = t; requestAnimationFrame(f); }; requestAnimationFrame(f); });
  const p = await ctx.newPage();
  const logs = []; p.on('console', m => logs.push([Date.now(), m.type() + ': ' + m.text()])); const marks=[]; let t0;
  await p.goto('http://localhost:5301/gp.html?pck=' + encodeURIComponent(PCK), { waitUntil: 'load', timeout: 60000 });
  await p.waitForFunction(() => window.__emits.some(x => x.type === 'ready'), null, { timeout: 90000 }).catch(() => {});
  await p.waitForTimeout(2000);
  const now = () => p.evaluate(() => performance.now());
  const mark = async n => { marks.push([Date.now(), n]); };
  const evalGd = async code => p.evaluate(c => window.ugcReceive(JSON.stringify({ type: 'eval', code: c })), code);
  const step = async (n, code, wait) => { await mark(n); await evalGd(code); await p.waitForTimeout(wait); };
  t0 = await p.evaluate(()=>performance.now()); console.log('T0',Math.round(t0)); await step('start', 'game.start_raid()', 2500);
  await step('choose', 'game.choose_skill(str(game.choices[0].id))', 1500);
  await step('choose2', 'if game.mode == "skills": game.choose_skill(str(game.choices[0].id))', 1500);
  await step('melee1', 'UGC.press("melee", .1)', 2500);
  await step('melee2', 'UGC.press("melee", .1)', 1500);
  await step('special', 'UGC.press("special", .1)', 2500);
  await step('dash', 'UGC.press("dash", .1)', 1500);
  await step('hero1', 'UGC.press("hero_primary", .1)', 2500);
  await step('hero2', 'UGC.press("hero_secondary", .1)', 2500);
  await step('walk', 'UGC.hold("up", true)', 3000);
  await step('stop', 'UGC.hold("up", false)', 500);
  await mark('end');
  console.log('LONG', JSON.stringify(await p.evaluate(() => window.__long)));
  console.log('MARKS',JSON.stringify(marks.map(m=>[m[1],m[0]-marks[0][0]])),'NOW0'); const all=[]&&[...marks.map(m=>[m[0],'>> '+m[1]]),...logs.filter(l=>/WebGL/.test(l[1])).map(l=>[l[0],l[1].slice(0,90)])].sort((a,b)=>a[0]-b[0]); let prev=''; all.length=0; for(const a of all){ if(a[1]!==prev) console.log(a[0]%100000, a[1]); prev=a[1]; }
  console.log(logs.filter(l => /SCRIPT|ERROR|USER/.test(l[1])).slice(0, 10).map(l => l[1]).join('\n'));
  await p.screenshot({ path: '../shot_t5.png' });
  await b.close();
})();



