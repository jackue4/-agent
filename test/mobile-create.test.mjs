import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
const source=await readFile(new URL('../web/create-flow.js',import.meta.url),'utf8');
const {createGame}=await import('data:text/javascript;base64,'+Buffer.from(source.replace(/^import .*;\r?\n/gm,'')).toString('base64'));
test('Remix copies the chosen published source and carries the modification prompt and tier into Chat',async()=>{
 const calls=[];
 const prompt='主角改成小猫 & 添加月球关卡';
 const result=await createGame(prompt,{remix:{id:'original'},dim:'2d',ori:'landscape',tier:'quality',model:'chosen'},async(path,options)=>{calls.push({path,...options});return{id:'copy'};});
 assert.deepEqual(calls,[{path:'/projects',body:{remix:'original',model:'chosen'}}]);
 const url=new URL(result.href,'http://local');
 assert.equal(url.searchParams.get('id'),'copy');assert.equal(url.searchParams.get('go'),prompt);assert.equal(url.searchParams.get('remix'),'1');assert.equal(url.searchParams.get('tier'),'quality');assert.equal(url.searchParams.get('ori'),'landscape');
});
test('empty prompts and unconfirmed project creation never navigate to an editor',async()=>{
 let called=false;
 await assert.rejects(createGame('  ',{},async()=>{called=true;}),/描述/);assert.equal(called,false);
 await assert.rejects(createGame('小猫游戏',{dim:'2d',ori:'portrait'},async()=>({})),/确认/);
});
