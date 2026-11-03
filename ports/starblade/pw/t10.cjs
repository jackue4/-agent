const { chromium } = require('playwright-core');
const PCK = '/api/projects/starblade_port/game.pck?build=' + process.argv[2];
(async () => {
  const b = await chromium.launch({ executablePath: 'C:/Program Files/Google/Chrome/Application/chrome.exe', headless: true, args: ['--use-angle=d3d11','--enable-gpu','--ignore-gpu-blocklist'] });
  const ctx = await b.newContext({ viewport: { width: 844, height: 390 }, deviceScaleFactor: 2, isMobile: true, hasTouch: true });
  await ctx.addInitScript(() => { window.__bad=0; const P=WebGL2RenderingContext.prototype, ob=P.bindBuffer; const tgt=new WeakMap(); P.bindBuffer=function(t,b){ if(b){ const k=(t===this.ELEMENT_ARRAY_BUFFER)?1:2; const o=tgt.get(b); if(o&&o!==k) window.__bad++; else if(!o && (t===this.ELEMENT_ARRAY_BUFFER||t===this.ARRAY_BUFFER)) tgt.set(b,k);} return ob.call(this,t,b); }; window.__emits = []; window.addEventListener('message', e => { if (e.data && e.data.__ugc) window.__emits.push(e.data.payload); });
    window.__long = []; let last = 0; const f = t => { if (last && t - last > 100) window.__long.push([Math.round(last), Math.round(t - last)]); last = t; requestAnimationFrame(f); }; requestAnimationFrame(f); });
  const p = await ctx.newPage();
  const logs = []; p.on('console', m => logs.push([Date.now(), m.type() + ': ' + m.text()])); const marks=[];
  await p.goto('http://localhost:5301/gp.html?pck=' + encodeURIComponent(PCK), { waitUntil: 'load', timeout: 60000 });
  await p.waitForFunction(() => window.__emits.some(x => x.type === 'ready'), null, { timeout: 90000 }).catch(() => {});
  await p.waitForTimeout(2000);
  const now = () => p.evaluate(() => performance.now());
  const mark = async n => { marks.push([Date.now(), n]); };
  const evalGd = async code => p.evaluate(c => window.ugcReceive(JSON.stringify({ type: 'eval', code: c })), code);
  const step = async (n, code, wait) => { await mark(n); await evalGd(code); await p.waitForTimeout(wait); };
  console.log('preStart', logs.filter(l=>/WebGL/.test(l[1])).length, logs.filter(l=>/too many/i.test(l[1])).map(l=>l[1]).join('|'));
  const cnt = () => p.evaluate(()=>window.__bad);
  console.log('hub bad', await cnt()); let h=await cnt(); await p.waitForTimeout(1000); console.log('hub/s',(await cnt())-h);
  await step('start', 'game.start_raid()', 1500);
  await step('choose', 'game.choose_skill(str(game.choices[0].id))', 800);
  await step('choose2', 'if game.mode == "skills": game.choose_skill(str(game.choices[0].id))', 1500);
  let a = await cnt(); await p.waitForTimeout(1000); console.log('base/s', (await cnt())-a);
  for (const [n,c,w] of [['melee','UGC.press("melee", .1)',1500],['special','UGC.press("special", .1)',1500],['dash','UGC.press("dash", .1)',800],['hero1','UGC.press("hero_primary", .1)',1500],['hero2','UGC.press("hero_secondary", .1)',1500],['walk','UGC.hold("up", true)',2000],['stop','UGC.hold("up", false)',300]]) { await step(n,c,w); }
  a = await cnt(); await p.waitForTimeout(1000); console.log('combat/s', (await cnt())-a);
  console.log('LONG', JSON.stringify(await p.evaluate(() => window.__long)), 'T0', JSON.stringify(marks.map(m=>[m[1],m[0]-marks[0][0]])));
  console.log('webgl console', logs.filter(l=>/WebGL/.test(l[1])).length);
  await p.screenshot({ path: '../shot_final.png' });  console.log(logs.filter(l=>/HIDE|SCRIPT ERROR/.test(l[1])).map(l=>l[1].slice(0,120)).join('\n'));  console.log('total', logs.filter(l=>/WebGL/.test(l[1])).length, logs.filter(l=>/too many/i.test(l[1])).map(l=>l[1]).join('|'));
  await b.close(); })();



