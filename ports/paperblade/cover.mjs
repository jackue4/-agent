import fs from 'node:fs';
import path from 'node:path';
import {fileURLToPath} from 'node:url';

// Reuse a chosen cover; a first import gets the bundled real-game screenshot.
export function ensureCover({data,id,requested,existing,draft,bundled=fileURLToPath(new URL('./cover.jpg',import.meta.url))}) {
  const cover=requested||existing||draft;
  if(cover)return cover;
  if(!/^[\w-]{1,128}$/.test(id||''))throw new Error('Invalid cover project ID');
  if(!fs.existsSync(bundled))throw new Error('PaperBlade default cover is missing; provide COVER before publishing');
  const directory=path.join(data,'covers'),name=id+'_cover.jpg';
  fs.mkdirSync(directory,{recursive:true});
  fs.copyFileSync(bundled,path.join(directory,name));
  return '/covers/'+name;
}
