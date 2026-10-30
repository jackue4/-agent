// Jump physics shared by the reachability checker (reach.mjs) and the system prompt (prompt.mjs).
// Mirrors runtime/player2d.gd + player3d.gd: instant take-off velocity, gravity while rising, heavier
// gravity while falling (2D), capped fall speed (2D), full run speed kept in the air, mid-air jumps at
// 90% power and bouncers that launch at jump * strength. Reachability assumes jump held for the full
// arc (the variable-jump cut only ever lowers a jump). Heights are measured between standing surfaces,
// gaps between surface edges (2D: along x; 3D: euclidean gap of the xz footprints).

export const PHYS = {
  '2d': { gravity: 1900, fallMult: 1.3, maxFall: 1500, speed: 360, jump: 760, releaseCut: 0.45, bounce: 1.5, radiusRatio: 0.36, heightRatio: 0.95, player: [64, 64] },
  '3d': { gravity: 24, fallMult: 1.35, maxFall: 30, speed: 7, jump: 9, releaseCut: 0.45, bounce: 1.6, radiusRatio: 0.45, heightRatio: 1, player: [0.9, 1.7, 0.9] },
};
export const AIR_JUMP_POWER = 0.9;
/** Jumps above this fraction of the physical limit are reported as "too hard". */
export const HARD_RATIO = 0.9;
/** Jumps at or below this fraction feel comfortable for casual players. */
export const COMFORT_RATIO = 0.65;
const MAX_AIR_JUMPS = 2; // analysis cap; more air jumps barely change level topology but cost a lot
const AIR_JUMP_SAMPLES = 24;

const positive = (v, d) => (typeof v === 'number' && isFinite(v) && v > 0 ? v : d);

/** Effective movement parameters of the game's player (falls back to runtime defaults). */
export function jumpModel(dim, game = {}) {
  const key = dim === '3d' ? '3d' : '2d';
  const d = PHYS[key];
  const pl = game.player || {};
  const size = Array.isArray(pl.size) && pl.size.length >= 2 ? pl.size : d.player;
  const pw = positive(Number(size[0]), d.player[0]);
  const ph = positive(Number(size[1]), d.player[1]);
  const radius = pw * d.radiusRatio;
  return {
    dim: key,
    g: positive(game.settings && game.settings.gravity, d.gravity),
    fallMult: d.fallMult,
    maxFall: d.maxFall,
    speed: positive(pl.speed, d.speed),
    jump: positive(pl.jump, d.jump),
    airJumps: Math.max(0, Math.min(MAX_AIR_JUMPS, Math.floor(Number(pl.air_jumps) || 0))),
    releaseCut: d.releaseCut,
    bounce: d.bounce,
    radius,
    bodyHeight: Math.max(ph * d.heightRatio, radius * 2),
    // Edge tolerance: the capsule still counts as on the floor (floor_max_angle 50°) with its centre
    // ~0.75 radius past an edge, both at take-off and at landing. Coyote time is ignored (conservative).
    foot: radius * 1.5,
    cache: new Map(),
  };
}

/** Distance fallen from rest after t seconds (fall gravity, capped fall speed). */
export function fallDistance(m, t) {
  const gf = m.g * m.fallMult;
  const tCap = m.maxFall / gf;
  return t <= tCap ? gf * t * t / 2 : m.maxFall * m.maxFall / (2 * gf) + m.maxFall * (t - tCap);
}

/** Time to fall distance d from rest. */
export function fallTime(m, d) {
  if (d <= 0) return 0;
  const gf = m.g * m.fallMult;
  const dCap = m.maxFall * m.maxFall / (2 * gf);
  return d <= dCap ? Math.sqrt(2 * d / gf) : m.maxFall / gf + (d - dCap) / m.maxFall;
}

/** Height relative to take-off t seconds after launching upward with speed v. */
export function heightAt(m, v, t) {
  const tUp = v / m.g;
  if (t <= tUp) return v * t - m.g * t * t / 2;
  return v * v / (2 * m.g) - fallDistance(m, t - tUp);
}

/** Latest time a launch with speed v passes height dh on the way down (null: never reaches dh). */
function descendTime(m, v, dh) {
  const apex = v * v / (2 * m.g);
  if (apex < dh - 1e-9) return null;
  return v / m.g + fallTime(m, apex - dh);
}

/**
 * Latest time at which the body can still be at relative height dh, launching with v0 and spending up
 * to airJumps mid-air jumps (timing sampled). null when dh is out of reach. Memoised per model.
 */
export function airTime(m, v0, dh, airJumps = m.airJumps) {
  const key = v0 + '|' + dh.toFixed(m.dim === '3d' ? 2 : 0) + '|' + airJumps;
  if (m.cache.has(key)) return m.cache.get(key);
  let best = descendTime(m, v0, dh);
  if (airJumps > 0) {
    const horizon = v0 / m.g + fallTime(m, v0 * v0 / (2 * m.g) + Math.max(0, -dh));
    for (let i = 0; i <= AIR_JUMP_SAMPLES; i++) {
      const t = horizon * i / AIR_JUMP_SAMPLES;
      const rest = airTime(m, m.jump * AIR_JUMP_POWER, dh - heightAt(m, v0, t), airJumps - 1);
      if (rest !== null && (best === null || t + rest > best)) best = t + rest;
    }
  }
  m.cache.set(key, best);
  return best;
}

/** Highest reachable rise of the feet above the take-off surface. */
export function maxRise(m, v0 = m.jump) {
  const air = m.jump * AIR_JUMP_POWER;
  return (v0 * v0 + m.airJumps * air * air) / (2 * m.g);
}

/** Lowest controllable hop: jump tapped and released at once (variable jump height). */
export function minHop(m) {
  const v = m.jump * m.releaseCut;
  return v * v / (2 * m.g);
}

/** Widest edge-to-edge gap that can be cleared when landing dh above (negative: below) the take-off. */
export function maxGap(m, dh, v0 = m.jump) {
  const t = airTime(m, v0, dh);
  return t === null ? null : m.speed * t + m.foot;
}

/**
 * Difficulty of a jump as a fraction of the physical limit: <= COMFORT_RATIO easy, > HARD_RATIO risky,
 * > 1 impossible. Combines horizontal reach at that height with the pure vertical demand.
 */
export function jumpDifficulty(m, gap, dh, v0 = m.jump) {
  const reach = maxGap(m, dh, v0);
  if (reach === null) return Infinity;
  return Math.max(Math.max(0, gap) / reach, dh > 0 ? dh / maxRise(m, v0) : 0);
}

/** Headline metrics for prompts and check_game results. */
export function jumpMetrics(m) {
  const round = v => +v.toFixed(m.dim === '3d' ? 2 : 0);
  const rise = maxRise(m);
  const comfortRise = rise * COMFORT_RATIO;
  return {
    jumpHeight: round(rise),
    jumpDistance: round(maxGap(m, 0)),
    comfortRise: round(comfortRise),
    comfortGap: round(maxGap(m, 0) * COMFORT_RATIO),
    gapAtComfortRise: round(maxGap(m, comfortRise)),
    comfortGapAtComfortRise: round(maxGap(m, comfortRise) * COMFORT_RATIO),
    gapAtDrop: round(maxGap(m, -rise)),
    minHop: round(minHop(m)),
    bounceHeight: round(maxRise(m, m.jump * m.bounce)),
  };
}
