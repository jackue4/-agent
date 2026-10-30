import test from 'node:test';
import assert from 'node:assert/strict';
import {
  PHYS, jumpModel, airTime, maxRise, minHop, maxGap, jumpDifficulty, jumpMetrics,
  fallDistance, fallTime, heightAt, HARD_RATIO, COMFORT_RATIO,
} from '../physics.mjs';

const near = (a, b, eps = 1e-6) => assert.ok(Math.abs(a - b) <= eps, a + ' !~ ' + b);

test('jumpModel uses runtime defaults when the game is empty', () => {
  const m2 = jumpModel('2d', {});
  assert.equal(m2.g, 1900);
  assert.equal(m2.speed, 360);
  assert.equal(m2.jump, 760);
  assert.equal(m2.airJumps, 0);
  assert.equal(m2.foot, 64 * PHYS['2d'].radiusRatio * 1.5);
  const m3 = jumpModel('3d', {});
  assert.equal(m3.g, 24);
  assert.equal(m3.speed, 7);
  assert.equal(m3.bodyHeight, 1.7);
});

test('jumpModel reads player overrides and clamps air jumps', () => {
  const m = jumpModel('2d', { player: { speed: 500, jump: 900, air_jumps: 9, size: [40, 90] } });
  assert.equal(m.speed, 500);
  assert.equal(m.jump, 900);
  assert.equal(m.airJumps, 2, 'air jumps capped at 2 for analysis');
  assert.equal(m.bodyHeight, 90 * PHYS['2d'].heightRatio);
  assert.equal(jumpModel('2d', { player: { speed: 0, jump: -5 } }).speed, 360, 'non-positive values fall back to defaults');
});

test('gravity setting overrides the dimension default', () => {
  assert.equal(jumpModel('2d', { settings: { gravity: 3000 } }).g, 3000);
  assert.equal(jumpModel('2d', { settings: { gravity: 0 } }).g, 1900);
});

test('fall physics: heavy fall gravity and capped fall speed', () => {
  const m = jumpModel('2d', { settings: { gravity: 1900 } });
  const gf = 1900 * 1.3;
  near(fallDistance(m, 0.1), gf * 0.01 / 2);
  near(fallDistance(m, 0), 0);
  near(fallTime(m, fallDistance(m, 0.4)), 0.4, 1e-9);
  // 1500 px/s cap is reached after 1500/2470 s; beyond that distance grows linearly
  const tCap = 1500 / gf;
  const dCap = fallDistance(m, tCap);
  near(fallDistance(m, tCap + 1), dCap + 1500);
});

test('heightAt follows rise then fall legs', () => {
  const m = jumpModel('2d', {});
  near(heightAt(m, m.jump, 0), 0);
  near(heightAt(m, m.jump, m.jump / m.g), maxRise(m));
  assert.ok(heightAt(m, m.jump, 1) < 0, 'one second in, the body is already falling below take-off');
});

test('airTime finds the descending crossing and rejects unreachable heights', () => {
  const m = jumpModel('2d', {});
  const t0 = airTime(m, m.jump, 0);
  // rise 760/1900 s, then fall the apex height under 1.3x gravity
  near(t0, 760 / 1900 + Math.sqrt(2 * maxRise(m) / (1900 * 1.3)), 1e-9);
  assert.equal(airTime(m, m.jump, maxRise(m) + 5), null);
  const tUp = airTime(m, m.jump, 100);
  assert.ok(tUp < t0, 'landing higher means less air time');
});

test('air jumps extend both height and air time', () => {
  const m = jumpModel('2d', { player: { air_jumps: 1 } });
  const single = jumpModel('2d', {});
  assert.ok(maxRise(m) > maxRise(single));
  assert.ok(airTime(m, m.jump, 0) > airTime(single, m.jump, 0));
});

test('minHop matches the variable jump cut', () => {
  const m = jumpModel('2d', {});
  const v = m.jump * PHYS['2d'].releaseCut;
  near(minHop(m), v * v / (2 * m.g), 1e-9);
});

test('maxGap shrinks as the target gets higher and grows when dropping', () => {
  const m = jumpModel('2d', {});
  const flat = maxGap(m, 0);
  assert.ok(maxGap(m, 100) < flat);
  assert.ok(maxGap(m, -100) > flat);
  assert.equal(maxGap(m, maxRise(m) + 1), null);
  near(flat, m.speed * airTime(m, m.jump, 0) + m.foot);
});

test('jumpDifficulty is a fraction of the limit and ranks vertical demand too', () => {
  const m = jumpModel('2d', {});
  assert.equal(jumpDifficulty(m, 0, 0), 0);
  near(jumpDifficulty(m, maxGap(m, 0), 0), 1, 1e-9);
  approx(jumpDifficulty(m, 0, maxRise(m)), 1);
  assert.ok(jumpDifficulty(m, 0, maxRise(m) + 1) === Infinity);
  assert.ok(jumpDifficulty(m, maxGap(m, 0) * 1.2, 0) > 1);
  function approx(a, b) { assert.ok(Math.abs(a - b) < 1e-3, a + ' !~ ' + b); }
});

test('jumpMetrics headline numbers for both dimensions', () => {
  const m2 = jumpMetrics(jumpModel('2d', {}));
  assert.equal(m2.jumpHeight, 152); // 760^2 / (2*1900)
  assert.ok(m2.jumpDistance > 290 && m2.jumpDistance < 320);
  assert.ok(m2.comfortGap < m2.jumpDistance);
  approx(m2.comfortGap, m2.jumpDistance * COMFORT_RATIO, 1);
  assert.equal(m2.minHop, 31);
  assert.ok(m2.bounceHeight > m2.jumpHeight, 'bouncer launches higher than a jump');
  assert.equal(m2.bounceHeight, 342); // (760*1.5)^2 / (2*1900)
  const m3 = jumpMetrics(jumpModel('3d', {}));
  assert.equal(m3.jumpHeight, 1.69);
  assert.ok(m3.jumpDistance > 5 && m3.jumpDistance < 6);
  approx(m3.bounceHeight, 4.32, 0.01);
  function approx(a, b, eps) { assert.ok(Math.abs(a - b) <= eps, a + ' !~ ' + b); }
});

test('HARD_RATIO and COMFORT_RATIO leave a comfortable band', () => {
  assert.ok(COMFORT_RATIO < HARD_RATIO && HARD_RATIO < 1);
});

test('airTime is memoised per model, not shared across models', () => {
  const a = jumpModel('2d', {});
  const b = jumpModel('2d', { settings: { gravity: 950 } });
  const ta = airTime(a, a.jump, 0);
  const tb = airTime(b, b.jump, 0);
  assert.notEqual(ta, tb);
  assert.equal(airTime(a, a.jump, 0), ta);
});
