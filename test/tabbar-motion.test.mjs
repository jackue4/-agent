import test from 'node:test';
import assert from 'node:assert/strict';
import vm from 'node:vm';
import {readFile} from 'node:fs/promises';
const js=await readFile(new URL('../web/home.js',import.meta.url),'utf8');
const css=await readFile(new URL('../web/home.css',import.meta.url),'utf8');
const source=js.slice(js.indexOf('function moveTabBubble('),js.indexOf('function navigate(t)'));
function setup(){
 let left=120,top=610,reduced=false,reads=0;const writes=[];
 const style=new Proxy({}, {set(target,key,value){writes.push([key,value]);target[key]=value;return true;}});
 const bubble={dataset:{},style,getBoundingClientRect(){reads++;return{};}};
 const icon={getBoundingClientRect:()=>({left,top,width:46,height:28})};
 const button={querySelector:()=>icon};const bar={querySelector:()=>button,getBoundingClientRect:()=>({left:100,top:600})};
 const context={$:s=>s==='.tabbar'?bar:bubble,matchMedia:()=>({matches:reduced})};vm.createContext(context);vm.runInContext(source,context);
 return {move:context.moveTabBubble,bubble,writes,reads:()=>reads,target:(x,y=610)=>{left=x;top=y;},reduce:()=>{reduced=true;}};
}
test('initial mount positions the pill immediately without sliding in from a corner',()=>{const f=setup();f.move();assert.equal(f.bubble.style.transform,'translate3d(43px,24px,0) translate(-50%,-50%)');assert.equal(f.bubble.dataset.ready,'true');assert.equal(f.bubble.style.opacity,'1');assert.equal(f.reads(),1);assert.deepEqual(f.writes.filter(([k])=>k==='transition'),[['transition','none'],['transition','']]);});
test('rapid retargeting changes only the destination, with no cancel, shrink, or animation queue',()=>{const f=setup();f.move();f.writes.length=0;for(const x of [205,460,375,120]){f.target(x);f.move();}assert.ok(f.writes.every(([k])=>k!=='transition'));assert.equal(f.reads(),1);assert.equal(f.bubble.style.transform,'translate3d(43px,24px,0) translate(-50%,-50%)');assert.doesNotMatch(source,/\.animate\(|\.cancel\(|scale\(/);});
test('resizing snaps to the recomputed geometry and accounts for vertical changes',()=>{const f=setup();f.move();f.target(230,640);f.move({animate:false});assert.equal(f.bubble.style.transform,'translate3d(153px,54px,0) translate(-50%,-50%)');assert.equal(f.reads(),2);assert.match(js,/layoutDiscoverPlay\(\);moveTabBubble\(\{animate:false\}\)/);});
test('reduced-motion preference skips movement animation',()=>{const f=setup();f.move();f.reduce();f.writes.length=0;f.target(350);f.move();assert.deepEqual(f.writes.filter(([k])=>k==='transition'),[['transition','none'],['transition','']]);assert.match(css,/@media\(prefers-reduced-motion:reduce\)/);});
test('selected icons are lime and bubble transitions remain transform-only',()=>{assert.match(css,/\.tabbar>button\.on\{color:var\(--lime\)\}/);assert.match(css,/\.tabbar>button\.on>span:first-child svg\{color:var\(--lime\)/);const bubble=css.match(/\.tab-bubble\{([^}]+)\}/)[1];assert.match(bubble,/width:48px;height:30px/);assert.match(bubble,/transform 300ms cubic-bezier/);assert.doesNotMatch(bubble,/#2d2346|transition:all|width .*ms|height .*ms/);});
