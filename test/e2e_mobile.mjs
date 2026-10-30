// Mobile-layout E2E: renders the feed and play page at a phone viewport.
import { capture } from '../server/shot.mjs';
const id = process.argv[2] || 'd7b950c42f';
for (const [name, url] of [['feed', '/'], ['play', '/play.html?id=' + id]]) {
  const r = await capture('http://10.0.4.94:5300' + url, 'test/shots/mobile_' + name + '.png', { width: 390, height: 844, mobile: true, wait: name === 'play' ? 12000 : 3000, port: name === 'play' ? 9472 : 9470 });
  const errs = r.logs.filter(l => /exception/i.test(l));
  console.log(name, errs.length ? errs.join('\n') : 'ok');
}
