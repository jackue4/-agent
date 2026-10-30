// Browser E2E: open the public play page for a published game, check the start card appears,
// press Enter to start, play a moment, and capture screenshots + console errors.
// Usage: node test/e2e_play.mjs <gameId> [outPrefix]
import { capture } from '../server/shot.mjs';
const id = process.argv[2] || 'd7b950c42f';
const pre = process.argv[3] || 'test/shots/web_' + id;
const r = await capture('http://10.0.4.94:5300/play.html?id=' + id, pre + '_start.png', {
  wait: 14000, port: 9460,
  actions: [
    { type: 'shot', path: pre + '_card.png' },
    { type: 'click', x: 500, y: 400 },
    { type: 'key', key: 'Enter', code: 'Enter', vk: 13, text: '\r' },
    { type: 'wait', ms: 2500 },
  ],
});
const errs = r.logs.filter(l => /exception|error|SCRIPT ERROR/i.test(l) && !/favicon|Reading less data|status of 404/.test(l));
console.log(r.logs.filter(l => /ugc|game_over|error/i.test(l)).slice(-15).join('\n'));
console.log(errs.length ? 'ERRORS:\n' + errs.join('\n') : 'no console errors');
process.exit(errs.length ? 1 : 0);
