// Isolated browser regression: real platform files, fixture games, no live project writes.
import assert from 'node:assert/strict';
import http from 'node:http';
import fs from 'node:fs/promises';
import path from 'node:path';
import os from 'node:os';
import {spawn} from 'node:child_process';
import {findBrowser} from '../server/shot.mjs';
const root=path.resolve('web'),out=path.resolve('artifacts/play-orientation');await fs.mkdir(out,{recursive:true});
const games=[{id:'wide',title:'横屏回归',orientation:'landscape'},{id:'tall',title:'竖屏回归',orientation:'portrait'},{id:'stale',title:'旧列表方向回归',orientation:'portrait'}].map(g=>({...g,dimension:'2d',plays:0,likes:0,pitch:'屏幕方向测试',author:'测试'}));
const runtime=`<!doctype html><style>html,body{margin:0;width:100%;height:100%;overflow:hidden;background:#1a3750;color:white;font:24px sans-serif}body{display:grid;place-content:center}i{position:absolute;width:40px;height:40px;background:#adf36c}i:nth-child(1){left:0;top:0}i:nth-child(2){right:0;top:0}i:nth-child(3){right:0;bottom:0}i:nth-child(4){left:0;bottom:0}</style><i></i><i></i><i></i><i></i><div id="size"></div><script>window.ugcReceive=()=>clearInterval(readyTimer);function size(){document.querySelector('#size').textContent=innerWidth+' × '+innerHeight}onresize=size;size();onclick=()=>document.body.dataset.clicked='yes';const readyTimer=setInterval(()=>parent.postMessage({__ugc:true,payload:{type:'ready'}},location.origin),100);</script>`;
const server=http.createServer(async(req,res)=>{
 try{
 const url=new URL(req.url,'http://fixture');let data,type='application/json';
 if(url.pathname==='/api/feed')data=JSON.stringify(games);
 else if(url.pathname==='/api/me')data='[]';
 else if(/^\/api\/games\/[^/]+$/.test(url.pathname)){const g=games.find(g=>g.id===url.pathname.split('/').pop());data=JSON.stringify({...g,spec:{meta:{orientation:g.id==='stale'?'landscape':g.orientation}}});}
 else if(url.pathname.startsWith('/api/'))data='{}';
 else if(url.pathname==='/game/index.html'){data=runtime;type='text/html';}
 else {const file=path.resolve(root,'.'+(url.pathname==='/'?'/index.html':url.pathname));if(!file.startsWith(root+path.sep))throw Error('outside root');data=await fs.readFile(file);type=({'.html':'text/html','.css':'text/css','.js':'text/javascript','.png':'image/png','.webp':'image/webp','.svg':'image/svg+xml'})[path.extname(file)]||'application/octet-stream';}
 res.writeHead(200,{'Content-Type':type});res.end(data);
 }catch{res.writeHead(404);res.end();}
});
await new Promise(r=>server.listen(0,'127.0.0.1',r));const base='http://127.0.0.1:'+server.address().port;
const profile=await fs.mkdtemp(path.join(os.tmpdir(),'dream-viewport-'));
const browser=spawn(findBrowser(),['--headless=new','--remote-debugging-port=0','--user-data-dir='+profile,'--no-first-run','--no-default-browser-check','--hide-scrollbars','--use-angle=swiftshader','--enable-unsafe-swiftshader','about:blank'],{stdio:'ignore'});
let ws;const errors=[],results=[];const sleep=ms=>new Promise(r=>setTimeout(r,ms));
try{
 let port;for(let n=0;n<100;n++){try{port=Number((await fs.readFile(path.join(profile,'DevToolsActivePort'),'utf8')).split('\n')[0]);break;}catch{await sleep(100);}}
 assert.ok(port,'browser debugger started');const tabs=await(await fetch('http://127.0.0.1:'+port+'/json/list')).json();ws=new WebSocket(tabs.find(t=>t.type==='page').webSocketDebuggerUrl);await new Promise(r=>ws.addEventListener('open',r));
 let sequence=0;const pending=new Map();ws.addEventListener('message',e=>{const m=JSON.parse(e.data);if(m.id){const p=pending.get(m.id);pending.delete(m.id);m.error?p?.reject(Error(JSON.stringify(m.error))):p?.resolve(m.result);}if(m.method==='Runtime.exceptionThrown')errors.push(m.params.exceptionDetails.exception?.description||m.params.exceptionDetails.text);});
 const cmd=(method,params={})=>new Promise((resolve,reject)=>{const id=++sequence;pending.set(id,{resolve,reject});ws.send(JSON.stringify({id,method,params}));});
 const evaluate=async expression=>{const r=await cmd('Runtime.evaluate',{expression,awaitPromise:true,returnByValue:true});if(r.exceptionDetails)throw Error(r.exceptionDetails.exception?.description||r.exceptionDetails.text);return r.result.value;};
 const wait=async (expression,attempts=100)=>{for(let n=0;n<attempts;n++){if(await evaluate(expression))return;await sleep(50);}throw Error('timeout: '+expression);};
 const resize=async(w,h,mobile=true)=>{await cmd('Emulation.setDeviceMetricsOverride',{width:w,height:h,deviceScaleFactor:1,mobile});await cmd('Emulation.setTouchEmulationEnabled',{enabled:mobile,maxTouchPoints:5});await sleep(150);};
 const navigate=async url=>{await cmd('Page.navigate',{url:base+url});await wait('document.readyState === "complete"');};
 const shot=async name=>{const r=await cmd('Page.captureScreenshot',{format:'png'});await fs.writeFile(path.join(out,name+'.png'),Buffer.from(r.data,'base64'));};
 await cmd('Page.enable');await cmd('Runtime.enable');
 await cmd('Page.addScriptToEvaluateOnNewDocument',{source:`Element.prototype.requestFullscreen=function(){return Promise.reject(new Error('fixture: native fullscreen unavailable'))}`});
 const check=async(name,selector,w,h,rotation,embedded=false)=>{
  await wait(`document.querySelector(${JSON.stringify(selector)})?.dataset.rotation === '${rotation}'`);
  const value=await evaluate(`(()=>{const el=document.querySelector(${JSON.stringify(selector)}),frame=el.querySelector('iframe'),r=el.getBoundingClientRect();return {width:el.clientWidth,height:el.clientHeight,left:r.left,top:r.top,right:r.right,bottom:r.bottom,rotation:Number(el.dataset.rotation),iframeWidth:frame.contentWindow.innerWidth,iframeHeight:frame.contentWindow.innerHeight,viewport:[innerWidth,innerHeight],scroll:[document.documentElement.scrollWidth,document.documentElement.scrollHeight]}})()`);
  assert.ok(Math.abs(value.width-w)<=1,name+' width '+JSON.stringify(value));assert.ok(Math.abs(value.height-h)<=1,name+' height '+JSON.stringify(value));assert.equal(value.rotation,rotation,name+' rotation');assert.ok(value.left>=-1&&value.top>=-1&&value.right<=value.viewport[0]+1&&value.bottom<=value.viewport[1]+1,name+' bounds');
  assert.ok(Math.abs(value.iframeWidth-w)<=1&&Math.abs(value.iframeHeight-h)<=1,name+' logical iframe dimensions');
  if(embedded)assert.equal(await evaluate(`document.querySelector(${JSON.stringify(selector)}).querySelector('iframe').contentDocument.querySelector('.pl').dataset.rotation`),'0','no double rotation');
  await wait(embedded ? `document.querySelector(${JSON.stringify(selector)}).querySelector('iframe').contentDocument.querySelector('#ld').hidden` : `document.querySelector('#ld').hidden`);
  const controls=await evaluate(embedded
   ? `(()=>{const doc=document.querySelector('.is-playing iframe').contentDocument;return {visible:[...doc.querySelectorAll('button,a')].filter(el=>el.getClientRects().length).length,removed:doc.querySelectorAll('#fs,#controls,#restart,#like,#remix,.pbar').length,exit:document.querySelectorAll('.is-playing .preview-exit').length}})()`
   : `({visible:[...document.querySelectorAll('button,a')].filter(el=>el.getClientRects().length).length,removed:document.querySelectorAll('#fs,#controls,#restart,#like,#remix,.pbar').length,exit:document.querySelectorAll('a.back[href="/"]').length})`);
  assert.equal(controls.removed,0,name+' old platform controls removed');
  assert.equal(controls.visible,embedded?0:1,name+' only one visible platform exit');
  assert.equal(controls.exit,1,name+' exit available');
  results.push({name,...value,controls});
 };
 await resize(390,844);await navigate('/play.html?id=wide');await wait('document.title === "横屏回归 · 造梦"');
 await check('direct-wide-upright','.pl',844,390,90);await shot('direct-wide-upright');
 await cmd('Input.dispatchMouseEvent',{type:'mousePressed',x:195,y:422,button:'left',clickCount:1});await cmd('Input.dispatchMouseEvent',{type:'mouseReleased',x:195,y:422,button:'left',clickCount:1});
 assert.equal(await evaluate('document.querySelector("#rt").contentDocument.body.dataset.clicked'),'yes','rotated iframe receives pointer input');
 await resize(844,390);await check('direct-wide-rotated','.pl',844,390,0);
 await resize(390,844);await navigate('/play.html?id=tall');await wait('document.title === "竖屏回归 · 造梦"');await check('direct-tall-upright','.pl',390,844,0);await shot('direct-tall-upright');
 await resize(844,390);await check('direct-tall-rotated','.pl',390,844,-90);
 await resize(1440,900,false);await check('direct-tall-desktop','.pl',506,900,0);
 await navigate('/play.html?id=wide');await wait('document.title === "横屏回归 · 造梦"');await check('direct-wide-desktop','.pl',1440,900,0);await shot('direct-wide-desktop');
 await evaluate(`document.querySelector('a.back').click()`);await wait(`location.pathname === '/' && !document.querySelector('#rt')`);
 await resize(390,844);await navigate('/#discover');await wait('document.querySelectorAll("[data-preview]").length === 3');
 for(const [i,orientation] of [[0,'landscape'],[1,'portrait'],[2,'landscape']]){
  await evaluate(`document.querySelector('[data-preview="${i}"]').click()`);
  await wait(`document.querySelector('.is-playing iframe')?.contentDocument?.title === ${JSON.stringify(games[i].title+' · 造梦')}`);
  await check('discover-'+games[i].id,'.is-playing .discovery-art',orientation==='landscape'?844:390,orientation==='landscape'?390:844,orientation==='landscape'?90:0,true);
  await shot('discover-'+games[i].id);
  // Reject forged metadata from the parent or unrelated frame.
  await evaluate(`window.postMessage({type:'dream-play-orientation',orientation:'portrait'},location.origin)`);await sleep(50);
  assert.equal(await evaluate(`document.querySelector('.is-playing .discovery-art').dataset.orientation`),orientation);
  await evaluate(`document.querySelector('.is-playing .preview-exit').click()`);
  assert.equal(await evaluate(`document.body.classList.contains('discover-playing')||!!document.querySelector('.discover-card iframe')||document.querySelector('.tabbar').hasAttribute('inert')`),false,'exit restores feed');
 }
 await resize(844,390);await evaluate(`document.querySelector('[data-preview="1"]').click()`);await wait(`document.querySelector('.is-playing iframe')?.contentDocument?.title === '竖屏回归 · 造梦'`);await check('discover-tall-rotated','.is-playing .discovery-art',390,844,-90,true);
 if(process.env.PLAY_LIVE_ORIGIN){
  const origin=new URL(process.env.PLAY_LIVE_ORIGIN).origin;
  const feed=await(await fetch(origin+'/api/feed?sort=hot')).json();
  for(const orientation of ['landscape','portrait']){
   const game=feed.find(g=>g.orientation===orientation);assert.ok(game,'live '+orientation+' game exists');
   await resize(390,844);await cmd('Page.navigate',{url:origin+'/play.html?id='+encodeURIComponent(game.id)});
   await wait('document.querySelector("#ld")?.hidden === true',1200);
   await check('live-'+orientation,'.pl',orientation==='landscape'?844:390,orientation==='landscape'?390:844,orientation==='landscape'?90:0);
   await sleep(1500);await shot('live-'+orientation);
  }
 }
 assert.deepEqual(errors,[],'no uncaught browser errors');await fs.writeFile(path.join(out,'browser-results.json'),JSON.stringify({results,errors,scope:process.env.PLAY_LIVE_ORIGIN?'Fixture layout/input plus two live game load/layout smoke checks; no physical-device acceptance.':'Fixture runtime; browser layout and input, not physical-device or game-engine acceptance.'},null,2));console.log(JSON.stringify({passed:results.length,errors,artifacts:out},null,2));
}finally{ws?.close();browser.kill();server.close();await sleep(400);const resolved=path.resolve(profile);if(resolved.startsWith(path.resolve(os.tmpdir())+path.sep)&&path.basename(resolved).startsWith('dream-viewport-'))await fs.rm(resolved,{recursive:true,force:true,maxRetries:5,retryDelay:200}).catch(()=>{});}
