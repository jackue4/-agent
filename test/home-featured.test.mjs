import test from 'node:test';
import assert from 'node:assert/strict';
import vm from 'node:vm';
import {readFile} from 'node:fs/promises';
const source=await readFile(new URL('../web/home.js',import.meta.url),'utf8');
const rendering=source.slice(source.indexOf('function renderFeatured(){'),source.indexOf('const spotlight='));
const matching=source.slice(source.indexOf('function matches(g){'),source.indexOf('function bindGames(root){'));
function fixture(){
 const featured={hidden:false,innerHTML:'retained-carousel',track:{scrollLeft:407,selectedDot:1}},feed={innerHTML:''},search={value:''},bound=[];
 const game=(id,genre,dimension='2d')=>({id,title:id,genre,dimension});
 const state={featuredAutoplay:null,mountFeaturedAutoplay:()=>null,category:'all',feedList:[game('adventure-game','shooter'),game('puzzle-game','puzzle'),game('card-game','card'),game('world-game','world','3d')],
  $:selector=>({'#featured':featured,'#feed':feed,'#gameSearch':search}[selector]||null),bindGames:root=>bound.push(root),card:g=>g.id,row:(_title,games)=>games.map(g=>g.id).join(','),heroSlides:()=>[],openCreate(){}};
 vm.createContext(state);vm.runInContext(matching+'\n'+rendering,state);
 return {state,featured,feed,search,bound};
}
for(const category of ['all','adventure','puzzle','card','3d'])test(category+' filters only the lower feed and retains carousel state',()=>{
 const {state,featured,feed,bound}=fixture();const track=featured.track;
 Object.defineProperty(featured,'innerHTML',{get:()=> 'retained-carousel',set:()=>assert.fail('category must never rebuild featured DOM')});
 state.category=category;state.renderFeed();assert.equal(featured.hidden,false);assert.equal(featured.track,track);assert.equal(track.scrollLeft,407);assert.equal(track.selectedDot,1);assert.deepEqual(bound,[feed]);
 if(category==='all')assert.ok(feed.innerHTML.includes('adventure-game')&&feed.innerHTML.includes('card-game'));
 else{const expected=category==='3d'?'world-game':category+'-game';assert.ok(feed.innerHTML.includes(expected));for(const g of state.feedList.filter(g=>g.id!==expected))assert.ok(!feed.innerHTML.includes(g.id));}
});
test('empty category leaves featured visible',()=>{const {state,featured,feed}=fixture();state.feedList=[];state.category='puzzle';state.renderFeed();assert.equal(featured.hidden,false);assert.match(feed.innerHTML,/没有找到/);assert.equal(featured.innerHTML,'retained-carousel');});
test('search behavior is preserved and clearing search restores featured without rebuilding',()=>{const {state,featured,search,feed}=fixture();search.value='card-game';state.renderFeed();assert.equal(featured.hidden,true);assert.match(feed.innerHTML,/搜索结果/);search.value='';state.category='card';state.renderFeed();assert.equal(featured.hidden,false);assert.equal(featured.innerHTML,'retained-carousel');});
test('featured renderer still initializes the empty-feed creation entry independently',()=>{const {state,featured,bound}=fixture();state.renderFeatured();assert.match(featured.innerHTML,/开始创造/);assert.deepEqual(bound,[featured]);});
test('initial data load and confirmed deletion refresh featured as well as lower content',()=>{assert.match(source,/feedList=await fillSpotlight\(orderHot\(list\)\);renderFeatured\(\);renderFeed\(\);renderDiscover\(\)/);assert.match(source,/renderMine\(\);renderFeatured\(\);renderFeed\(\);renderDiscover\(\)/);});
