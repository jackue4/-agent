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
  await evalGd('var n := 0\nfor x in game.get_tree().root.find_children("*","CPUParticles3D",true,false):\n\tx.visible = false; n += 1\nprint("HIDEPART ", n)');
  await p.waitForTimeout(300); a = await cnt(); await p.waitForTimeout(1000); console.log('noParticles/s', (await cnt())-a);
  await evalGd('var n := 0\nfor x in game.get_tree().root.find_children("*","MultiMeshInstance3D",true,false):\n\tx.visible = false; n += 1\nprint("HIDEMM ", n)');
  await p.waitForTimeout(300); a = await cnt(); await p.waitForTimeout(1000); console.log('noMM/s', (await cnt())-a);
  await evalGd('var n := 0\nfor x in game.get_tree().root.find_children("*","Label3D",true,false):\n\tx.visible = false; n += 1\nprint("HIDEL3 ", n)');
  await p.waitForTimeout(300); a = await cnt(); await p.waitForTimeout(1000); console.log('noLabel3D/s', (await cnt())-a);
  await evalGd('game.ui.visible = false\nfor c in game.ui.get_children(): if c is CanvasItem: c.visible = false\nprint("HIDEUI")');
  await p.waitForTimeout(300); a = await cnt(); await p.waitForTimeout(1000); console.log('noUI/s', (await cnt())-a);
  console.log(logs.filter(l=>/HIDE|SCRIPT ERROR/.test(l[1])).map(l=>l[1].slice(0,120)).join('\n'));  console.log('total', logs.filter(l=>/WebGL/.test(l[1])).length, logs.filter(l=>/too many/i.test(l[1])).map(l=>l[1]).join('|'));
  await b.close(); })();


