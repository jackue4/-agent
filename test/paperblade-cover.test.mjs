import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import os from 'node:os';
import {ensureCover} from '../ports/paperblade/cover.mjs';
test('first PaperBlade import supplies the bundled real-game cover',()=>{
 const data=fs.mkdtempSync(path.join(os.tmpdir(),'paperblade-cover-'));
 try{const cover=ensureCover({data,id:'paperblade_port'});assert.equal(cover,'/covers/paperblade_port_cover.jpg');const bytes=fs.readFileSync(path.join(data,cover));assert.equal(bytes[0],0xff);assert.equal(bytes[1],0xd8);assert.ok(bytes.length>10000);}finally{const target=path.resolve(data);assert.ok(target.startsWith(path.resolve(os.tmpdir())+path.sep)&&path.basename(target).startsWith('paperblade-cover-'));fs.rmSync(target,{recursive:true,force:true});}
});
test('explicit and existing covers are never replaced by the default',()=>{
 assert.equal(ensureCover({requested:'/chosen.jpg',existing:'/old.jpg'}),'/chosen.jpg');
 assert.equal(ensureCover({existing:'/old.jpg',draft:'/draft.jpg'}),'/old.jpg');
 assert.equal(ensureCover({draft:'/draft.jpg'}),'/draft.jpg');
});
test('missing default fails explicitly and IDs cannot escape the cover directory',()=>{
 assert.throws(()=>ensureCover({id:'paperblade_port',bundled:path.join(os.tmpdir(),'missing-paperblade-cover.jpg')}),/missing/);
 assert.throws(()=>ensureCover({id:'../outside'}),/Invalid/);
});
