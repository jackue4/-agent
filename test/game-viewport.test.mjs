import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
const source=await readFile(new URL('../web/game-viewport.js',import.meta.url),'utf8');
const {gameOrientation,gameViewport,enterGameFullscreen}=await import('data:text/javascript;base64,'+Buffer.from(source).toString('base64'));
test('orientation comes from actual game metadata before stale feed metadata',()=>{
 assert.equal(gameOrientation({orientation:'portrait',spec:{meta:{orientation:'landscape'}}}),'landscape');
 assert.equal(gameOrientation({game:{meta:{orientation:'portrait'}}}),'portrait');
 assert.equal(gameOrientation({orientation:'portrait',title:'横版射击'}),'portrait');
 assert.equal(gameOrientation({orientation:'invalid'}),'landscape');
 assert.equal(gameOrientation(),'landscape');
});
for(const [name,orientation,w,h,options,expected] of [
 ['landscape on upright phone','landscape',390,844,{coarse:true},{width:844,height:390,rotation:90}],
 ['landscape on rotated phone','landscape',844,390,{coarse:true},{width:844,height:390,rotation:0}],
 ['portrait on upright phone','portrait',390,844,{coarse:true},{width:390,height:844,rotation:0}],
 ['portrait on rotated phone','portrait',844,390,{coarse:true},{width:390,height:844,rotation:-90}],
 ['desktop landscape not limited to 440px','landscape',1440,900,{}, {width:1440,height:900,rotation:0}],
 ['desktop portrait fills height, not stretched','portrait',1440,900,{}, {width:506.25,height:900,rotation:0}],
 ['narrow desktop landscape rotates','landscape',600,900,{}, {width:900,height:600,rotation:90}],
 ['embedded landscape is not rotated twice','landscape',844,390,{embedded:true}, {width:844,height:390,rotation:0}],
 ['embedded portrait is not fitted twice','portrait',390,844,{embedded:true}, {width:390,height:844,rotation:0}],
])test(name,()=>assert.deepEqual(gameViewport(orientation,w,h,options),expected));
test('fullscreen denial and missing APIs leave CSS fallback usable',async()=>{
 await enterGameFullscreen({},'landscape');
 await enterGameFullscreen({requestFullscreen(){throw Error('denied');}},'landscape');
 await enterGameFullscreen({requestFullscreen(){return Promise.reject(Error('denied'));}},'portrait');
});
test('native fullscreen locks requested orientation only while current',async()=>{
 const calls=[];globalThis.screen={orientation:{lock:async direction=>calls.push(direction)}};
 const element={async requestFullscreen(){calls.push('fullscreen');}};
 await enterGameFullscreen(element,'portrait');assert.deepEqual(calls,['fullscreen','portrait']);
 calls.length=0;let active=true;
 await enterGameFullscreen({async requestFullscreen(){active=false;}},'landscape',()=>active);
 assert.deepEqual(calls,[]);
 await enterGameFullscreen(element,'landscape',()=>false);assert.deepEqual(calls,[]);
 delete globalThis.screen;
});
test('exiting while native fullscreen is pending cleans up the retired card',async()=>{
 let active=true,exited=false;
 const element={async requestFullscreen(){active=false;globalThis.document.fullscreenElement=this;}};
 globalThis.document={fullscreenElement:null,async exitFullscreen(){exited=true;this.fullscreenElement=null;}};
 try{await enterGameFullscreen(element,'landscape',()=>active);assert.equal(exited,true);assert.equal(document.fullscreenElement,null);}finally{delete globalThis.document;}
});
