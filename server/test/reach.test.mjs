import test from 'node:test';
import assert from 'node:assert/strict';
import { check, plat2, onTop2, island3, hasIssue, issueTexts } from './helpers.mjs';
import { footprintGap, extension, moverOffsets, boxOf } from '../reach.mjs';
import { jumpModel, maxGap, maxRise } from '../physics.mjs';

const M2 = jumpModel('2d', {});
const M3 = jumpModel('3d', {});
const LIMIT = maxGap(M2, 0);           // widest flat gap
const player2 = { position: [100, 40] }; // stands on a platform whose top is y=0

/** Two flat platforms (top y=0) separated by gap, goal on the second one. */
function gapLevel(gap, extra = {}) {
  return check({
    player: player2,
    entities: [plat2('a', 0, 400, 0), plat2('b', 400 + gap, 400, extra.top ?? 0), onTop2('goal', 'goal', 400 + gap + 200, extra.top ?? 0), onTop2('c1', 'collectible', 200, 0)],
    ...extra.opts,
  });
}

test('geometry helpers: footprint gap and extension', () => {
  assert.equal(footprintGap({ l: 0, r: 10 }, { l: 15, r: 20 }), 5);
  assert.equal(footprintGap({ l: 0, r: 10 }, { l: 5, r: 20 }), 0);
  assert.equal(footprintGap({ l: 0, r: 1, n: 0, f: 1 }, { l: 4, r: 5, n: 5, f: 6 }), 5, '3D gap is xz euclidean');
  assert.equal(extension({ l: -5, r: 5 }, { l: 0, r: 100 }), 5);
  assert.ok(extension({ l: 10, r: 20 }, { l: 0, r: 100 }) < 0);
});

test('moverOffsets mirrors runtime behaviours', () => {
  const xs = moverOffsets({ behavior: { type: 'patrol', axis: 'x', range: 100 } }, '2d').map(o => o[0]);
  assert.deepEqual([Math.min(...xs), Math.max(...xs)], [-100, 100]);
  const ys = moverOffsets({ behavior: { type: 'move', axis: 'y', range: 60 } }, '2d').map(o => o[1]);
  assert.deepEqual([Math.min(...ys), Math.max(...ys)], [-60, 60]);
  const zs = moverOffsets({ behavior: { type: 'patrol', axis: 'z', range: 3 } }, '3d').map(o => o[2]);
  assert.deepEqual([Math.min(...zs), Math.max(...zs)], [-3, 3]);
  assert.equal(Math.max(...moverOffsets({ behavior: { type: 'float', range: 4 } }, '3d').map(o => o[1])), 0.6, '3D float bobs range*0.15');
  assert.deepEqual(moverOffsets({ behavior: { type: 'spin' } }, '2d'), [[0, 0, 0]]);
  assert.deepEqual(moverOffsets({ behavior: 'patrol' }, '2d').length, 5, 'string behaviours use runtime defaults');
  assert.deepEqual(moverOffsets({}, '2d'), [[0, 0, 0]]);
});

test('2D: comfortable gap is reachable with a critical path and margin', () => {
  const r = gapLevel(150);
  assert.equal(r.ok, true, issueTexts(r).join('\n'));
  assert.deepEqual(r.path.criticalPath, ['a', 'b']);
  assert.equal(r.path.spawn, 'a');
  assert.equal(r.path.target, 'goal');
  assert.equal(r.path.hardestJump.from, 'a');
  assert.equal(r.path.hardestJump.to, 'b');
  assert.equal(r.path.hardestJump.gap, 150);
  assert.ok(r.path.hardestJump.margin > 0.4);
  assert.equal(r.path.hardestJump.tooHard, false);
  assert.ok(!r.issues.some(i => /太难|不可达|孤岛/.test(i.text)));
});

test('2D: gap just under the limit is reachable but flagged too hard', () => {
  const r = gapLevel(Math.floor(LIMIT * 0.95));
  assert.equal(r.ok, true);
  assert.equal(r.path.hardestJump.tooHard, true);
  assert.ok(hasIssue(r, 'warn', /太难/));
});

test('2D: gap beyond the limit makes the goal unreachable (error) with an actionable hint', () => {
  const r = gapLevel(Math.ceil(LIMIT + 10));
  assert.equal(r.ok, false);
  assert.ok(hasIssue(r, 'error', /终点.*跳不到/));
  assert.ok(hasIssue(r, 'warn', /平台「b」是孤岛/));
  assert.deepEqual(r.path.criticalPath, []);
  assert.ok(r.path.unreachable.includes('goal'));
  assert.deepEqual(r.path.isolated, ['b']);
  const hint = r.issues.find(i => i.level === 'error').hint;
  assert.match(hint, /最近的起跳点「a」/);
  assert.match(hint, /间隙 \d+/);
});

test('2D: a step higher than max jump height is unreachable even with no gap', () => {
  const tooHigh = Math.ceil(maxRise(M2) + 20);
  const r = gapLevel(0, { top: tooHigh });
  assert.ok(hasIssue(r, 'error', /终点/), issueTexts(r).join('\n'));
  const ok = gapLevel(0, { top: 100 });
  assert.equal(ok.ok, true, issueTexts(ok).join('\n'));
});

test('2D: dropping down allows wider gaps than flat jumps', () => {
  const gap = Math.ceil(LIMIT + 20);
  assert.ok(gap < maxGap(M2, -150));
  const r = gapLevel(gap, { top: -150 });
  assert.equal(r.ok, true, issueTexts(r).join('\n'));
});

test('2D: one-way platform directly overhead can be jumped through; a solid one cannot', () => {
  const base = plat2('ground', -200, 1000, 0);
  const oneWay = { id: 'ledge', kind: 'platform', position: [300, 120 - 15], size: [300, 30] }; // thin, not solid
  const solid = { id: 'ledge', kind: 'platform', position: [300, 120 - 15], size: [1200, 30], solid: true }; // covers the whole ground
  const goal = onTop2('goal', 'goal', 300, 120);
  const r1 = check({ player: { position: [300, 40] }, entities: [base, oneWay, goal] });
  assert.equal(r1.ok, true, issueTexts(r1).join('\n'));
  const r2 = check({ player: { position: [300, 40] }, entities: [base, solid, goal] });
  assert.ok(hasIssue(r2, 'error', /终点/), issueTexts(r2).join('\n'));
});

test('2D: solid ledge overhead is reachable by jumping around its lip', () => {
  const r = check({
    player: { position: [0, 40] },
    entities: [plat2('ground', -400, 1200, 0), plat2('box', 200, 200, 100), onTop2('goal', 'goal', 300, 100)],
  });
  assert.equal(r.ok, true, issueTexts(r).join('\n'));
  // the goal may be grabbed mid-arc over the lip, so assert the ledge itself is reachable
  assert.deepEqual(r.path.isolated, []);
  assert.deepEqual(r.path.unreachable, []);
});

test('2D: an item resting on a solid platform cannot be grabbed through it from below', () => {
  // goal sits on a floating solid slab directly above the spawn, slab too wide to jump around
  const r = check({
    player: { position: [300, 40] },
    entities: [plat2('ground', 0, 600, 0), plat2('slab', -100, 800, 180), onTop2('goal', 'goal', 300, 180)],
  });
  assert.ok(hasIssue(r, 'error', /终点/), issueTexts(r).join('\n'));
  // the same goal on a one-way slab is fine: the player jumps up through it
  const r2 = check({
    player: { position: [300, 40] },
    entities: [plat2('ground', 0, 600, 0), { id: 'slab', kind: 'platform', position: [300, 135], size: [800, 30] }, onTop2('goal', 'goal', 300, 150)],
  });
  assert.equal(r2.ok, true, issueTexts(r2).join('\n'));
});

test('2D: no ground under spawn is an error', () => {
  const r = check({ player: { position: [2000, 40] }, entities: [plat2('a', 0, 400, 0), onTop2('goal', 'goal', 200, 0)] });
  assert.equal(r.ok, false);
  assert.ok(hasIssue(r, 'error', /出生点下方没有平台/));
  assert.equal(r.path.spawn, null);
});

test('2D: spawn below the platform top does not count as standing on it', () => {
  const r = check({ player: { position: [200, -200] }, entities: [plat2('a', 0, 400, 0), onTop2('goal', 'goal', 200, 0)] });
  assert.ok(hasIssue(r, 'error', /出生点下方没有平台/));
});

test('2D: spawn inside a solid platform is an error', () => {
  const r = check({ player: { position: [200, -20] }, entities: [plat2('a', 0, 400, 0), onTop2('goal', 'goal', 200, 0)] });
  assert.ok(hasIssue(r, 'error', /卡在/));
});

test('2D: empty level reports missing ground', () => {
  const r = check({ player: player2, entities: [onTop2('goal', 'goal', 200, 0)] });
  assert.ok(hasIssue(r, 'error', /没有任何平台/));
});

test('2D: an unreachable collectible / powerup is a warning, the goal still ok', () => {
  const r = check({
    player: player2,
    entities: [plat2('a', 0, 600, 0), onTop2('goal', 'goal', 500, 0), { id: 'coin_sky', kind: 'collectible', position: [300, 600] }, { id: 'pu', kind: 'powerup', position: [300, 900] }],
  });
  assert.equal(r.ok, true);
  assert.ok(hasIssue(r, 'warn', /收集物「coin_sky」不可达/));
  assert.ok(hasIssue(r, 'warn', /道具「pu」不可达/));
  assert.deepEqual(r.path.unreachable.sort(), ['coin_sky', 'pu']);
});

test('2D: collectibles reachable by jumping up into them in mid air', () => {
  const r = check({
    player: player2,
    entities: [plat2('a', 0, 600, 0), onTop2('goal', 'goal', 500, 0), { id: 'coin', kind: 'collectible', position: [300, 180] }],
  });
  assert.ok(!hasIssue(r, 'warn', /不可达/), issueTexts(r).join('\n'));
});

test('2D: collect_all makes an unreachable collectible an error', () => {
  const r = check({
    rules: { win: 'collect_all' },
    player: player2,
    entities: [plat2('a', 0, 600, 0), { id: 'c1', kind: 'collectible', position: [300, 40] }, { id: 'c2', kind: 'collectible', position: [300, 800] }],
  });
  assert.equal(r.ok, false);
  assert.ok(hasIssue(r, 'error', /「c2」不可达/));
});

test('2D: bouncer launches the player to a ledge a jump cannot reach', () => {
  const high = 300; // > 160 max jump, < 360 bounce height
  const entities = [plat2('ground', 0, 800, 0), plat2('high', 300, 300, high), onTop2('goal', 'goal', 450, high)];
  const without = check({ player: player2, entities });
  assert.ok(hasIssue(without, 'error', /终点/));
  const withSpring = check({ player: player2, entities: [...entities, { id: 'spring', kind: 'bouncer', position: [200, 16] }] });
  assert.equal(withSpring.ok, true, issueTexts(withSpring).join('\n'));
  assert.deepEqual(withSpring.path.criticalPath, ['ground', 'spring', 'high']);
  const weak = check({ player: player2, entities: [...entities, { id: 'spring', kind: 'bouncer', position: [200, 16], strength: 1.1 }] });
  assert.ok(hasIssue(weak, 'error', /终点/), 'strength scales the launch');
});

test('2D: double jump (air_jumps) widens reach', () => {
  const gap = Math.ceil(LIMIT + 100);
  const entities = [plat2('a', 0, 400, 0), plat2('b', 400 + gap, 400, 0), onTop2('goal', 'goal', 400 + gap + 200, 0)];
  assert.ok(hasIssue(check({ player: player2, entities }), 'error', /终点/));
  const r = check({ player: { ...player2, air_jumps: 1 }, entities });
  assert.equal(r.ok, true, issueTexts(r).join('\n'));
});

test('2D: higher jump / speed stats change reachability', () => {
  const gap = Math.ceil(LIMIT + 60);
  const entities = [plat2('a', 0, 400, 0), plat2('b', 400 + gap, 400, 0), onTop2('goal', 'goal', 400 + gap + 200, 0)];
  assert.ok(hasIssue(check({ player: player2, entities }), 'error', /终点/));
  assert.equal(check({ player: { ...player2, speed: 480 }, entities }).ok, true);
});

test('2D: moving platform is evaluated at its most favourable position', () => {
  // the patrol platform sits too far at home, but its +x patrol brings it close to b
  const gap = Math.ceil(LIMIT + 150);
  const entities = [
    plat2('a', 0, 400, 0),
    { ...plat2('mover', 400 + LIMIT + 50, 200, 0), behavior: { type: 'patrol', axis: 'x', range: 200, speed: 100 } },
    plat2('b', 400 + LIMIT + 50 + 200 + gap, 400, 0),
    onTop2('goal', 'goal', 400 + LIMIT + 50 + 200 + gap + 200, 0),
  ];
  const r = check({ player: player2, entities });
  assert.equal(r.ok, true, issueTexts(r).join('\n'));
  assert.deepEqual(r.path.criticalPath, ['a', 'mover', 'b']);
  const still = check({ player: player2, entities: entities.map(e => (e.id === 'mover' ? { ...e, behavior: undefined } : e)) });
  assert.ok(hasIssue(still, 'error', /终点/));
});

test('2D: vertical lift (move axis y) carries the player up', () => {
  const entities = [
    plat2('ground', 0, 400, 0),
    { ...plat2('lift', 450, 160, 0, { h: 30 }), behavior: { type: 'move', axis: 'y', range: 180, speed: 80 } },
    plat2('top', 640, 300, 300),
    onTop2('goal', 'goal', 790, 300),
  ];
  const r = check({ player: player2, entities });
  assert.equal(r.ok, true, issueTexts(r).join('\n'));
  assert.ok(r.path.criticalPath.includes('lift'));
});

test('2D: the critical path takes the easiest route, not the shortest', () => {
  // direct a->b is a 95% jump, a->step->b is easy
  const gap = Math.floor(LIMIT * 0.95);
  const entities = [
    plat2('a', 0, 400, 0), plat2('b', 400 + gap, 400, 0), onTop2('goal', 'goal', 400 + gap + 300, 0),
    { id: 'step', kind: 'platform', position: [400 + gap / 2, -40], size: [120, 30] },
  ];
  const r = check({ player: player2, entities });
  assert.deepEqual(r.path.criticalPath, ['a', 'step', 'b']);
  assert.equal(r.path.hardestJump.tooHard, false);
  assert.ok(!hasIssue(r, 'warn', /太难/));
});

test('2D: unreachable side platform is reported as isolated', () => {
  const r = check({ player: player2, entities: [plat2('a', 0, 800, 0), onTop2('goal', 'goal', 700, 0), plat2('cloud', 200, 200, 700)] });
  assert.equal(r.ok, true);
  assert.deepEqual(r.path.isolated, ['cloud']);
  assert.ok(hasIssue(r, 'warn', /平台「cloud」是孤岛/));
});

test('2D: solid decor can be used as a step', () => {
  const entities = [plat2('ground', 0, 800, 0), plat2('high', 300, 300, 260), onTop2('goal', 'goal', 450, 260)];
  assert.ok(hasIssue(check({ player: player2, entities }), 'error', /终点/));
  const crate = { id: 'crate', kind: 'decor', shape: 'crate', solid: true, position: [200, 75], size: [140, 140] };
  const r = check({ player: player2, entities: [...entities, crate] });
  assert.equal(r.ok, true, issueTexts(r).join('\n'));
});

test('2D: long levels without a checkpoint get a warning, with one they do not', () => {
  const plats = Array.from({ length: 16 }, (_, i) => plat2('p' + i, i * 250, 200, 0));
  const goal = onTop2('goal', 'goal', 15 * 250 + 100, 0);
  const r = check({ player: player2, entities: [...plats, goal, onTop2('c', 'collectible', 100, 0)] });
  assert.ok(hasIssue(r, 'warn', /检查点/));
  assert.equal(r.counts.checkpoints, 0);
  const r2 = check({ player: player2, entities: [...plats, goal, onTop2('c', 'collectible', 100, 0), onTop2('cp', 'checkpoint', 7 * 250 + 100, 0)] });
  assert.ok(!hasIssue(r2, 'warn', /检查点/));
  assert.equal(r2.counts.checkpoints, 1);
  assert.equal(r2.path.unreachable.length, 0, 'checkpoints are reachability-checked too');
});

test('2D: errors are sorted before warnings and the list is capped', () => {
  const coins = Array.from({ length: 30 }, (_, i) => ({ id: 'c' + i, kind: 'collectible', position: [i * 50, 2000] }));
  const r = check({ player: player2, entities: [plat2('a', 0, 400, 0), ...coins] });
  assert.ok(r.issues.length <= 20);
  assert.equal(r.issues[0].level, 'error');
  const firstWarn = r.issues.findIndex(i => i.level === 'warn');
  assert.ok(r.issues.slice(firstWarn).every(i => i.level === 'warn'));
});

test('3D: reachable islands give a path and xz gap is euclidean', () => {
  const r = check({
    dimension: '3d',
    world: { ground_size: 0 },
    player: { position: [0, 1, 0] },
    entities: [island3('a', 0, 0, 0), island3('b', 7, 0, 0.8), island3('c', 7, 7, 0.8), { id: 'goal', kind: 'goal', position: [7, 2.4, 7] }, { id: 'coin', kind: 'collectible', position: [0, 0.8, 0] }],
  });
  assert.equal(r.ok, true, issueTexts(r).join('\n'));
  assert.deepEqual(r.path.criticalPath, ['a', 'b', 'c']);
  assert.equal(r.path.hardestJump.gap, 3);
});

test('3D: a diagonal gap too wide in xz is unreachable', () => {
  // edges 4.5 apart in both x and z -> euclidean 6.36 > limit
  const r = check({
    dimension: '3d',
    world: { ground_size: 0 },
    player: { position: [0, 1, 0] },
    entities: [island3('a', 0, 0, 0), island3('b', 8.5, 8.5, 0), { id: 'goal', kind: 'goal', position: [8.5, 1.6, 8.5] }],
  });
  assert.ok(maxGap(M3, 0) < Math.hypot(4.5, 4.5));
  assert.ok(maxGap(M3, 0) > 4.5, 'each axis alone would be jumpable');
  assert.ok(hasIssue(r, 'error', /终点/), issueTexts(r).join('\n'));
});

test('3D: infinite ground counts as a standing surface', () => {
  const r = check({ dimension: '3d', world: { ground_size: 80 }, player: { position: [0, 1, 0] }, entities: [{ id: 'goal', kind: 'goal', position: [20, 1.6, 0] }] });
  assert.equal(r.path.spawn, '__ground');
  assert.equal(r.ok, true, issueTexts(r).join('\n'));
});

test('3D: no ground and spawn in the void is an error', () => {
  const r = check({ dimension: '3d', world: { ground_size: 0 }, player: { position: [30, 3, 0] }, entities: [island3('a', 0, 0, 0), { id: 'goal', kind: 'goal', position: [0, 1.6, 0] }] });
  assert.ok(hasIssue(r, 'error', /出生点下方没有平台/));
});

test('3D: bouncer reaches a high island', () => {
  const entities = [island3('a', 0, 0, 0, 8), island3('high', 6, 0, 3.5), { id: 'goal', kind: 'goal', position: [6, 5.1, 0] }];
  const base = { dimension: '3d', world: { ground_size: 0 }, player: { position: [-2, 1, 0] } };
  assert.ok(hasIssue(check({ ...base, entities }), 'error', /终点/));
  const r = check({ ...base, entities: [...entities, { id: 'pad', kind: 'bouncer', position: [2.5, 0.2, 0] }] });
  assert.equal(r.ok, true, issueTexts(r).join('\n'));
  assert.ok(r.path.criticalPath.includes('pad'));
});

test('3D: z-axis patrol platform bridges a gap', () => {
  const entities = [
    island3('a', 0, 0, 0),
    island3('mover', 0, 9, 0, 3, { behavior: { type: 'patrol', axis: 'z', range: 4 } }),
    island3('b', 0, 18, 0),
    { id: 'goal', kind: 'goal', position: [0, 1.6, 18] },
  ];
  const r = check({ dimension: '3d', world: { ground_size: 0 }, player: { position: [0, 1, 0] }, entities });
  assert.equal(r.ok, true, issueTexts(r).join('\n'));
  assert.deepEqual(r.path.criticalPath, ['a', 'mover', 'b']);
});

test('boxOf respects offsets and the 3D depth axis', () => {
  const b = boxOf({ position: [0, 0, 0], size: [2, 2, 4] }, '3d', [1, 0, 0]);
  assert.deepEqual([b.l, b.r, b.n, b.f, b.top], [0, 2, -2, 2, 1]);
});
