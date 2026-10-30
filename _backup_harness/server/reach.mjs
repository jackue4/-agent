// Physics-accurate reachability for side-view (2D platformer) and 3D levels.
// Builds standing surfaces (platforms, solid decor, 3D ground) and launch pads (bouncers), connects them
// with jump edges whose difficulty comes from physics.mjs, then runs a bottleneck search from the spawn
// surface: every node gets the easiest possible "hardest jump" needed to get there. Difficulty <= 1 means
// reachable; > HARD_RATIO means a required jump is nearly at the physical limit.
// Known simplifications: intermediate geometry does not block arcs, moving platforms are assumed to be at
// their most favourable offset, and coyote time / riding momentum are ignored (conservative).
import { jumpModel, jumpDifficulty, maxGap, maxRise, HARD_RATIO } from './physics.mjs';

const ONE_WAY_MAX_HEIGHT = 48;
const SPAWN_EPS = { '2d': 6, '3d': 0.25 };
const MOVER_SAMPLES = [-1, -0.5, 0, 0.5, 1];
const DECOR_SOLID_3D = ['rock', 'box', 'crate', 'house', 'building', 'pillar', 'tower', 'cylinder', ''];
const ITEM_KINDS = ['collectible', 'powerup', 'goal', 'checkpoint'];

const num = (v, d) => (typeof v === 'number' && isFinite(v) ? v : d);

/** Axis-aligned box of an entity at an offset; z fields only in 3D. */
export function boxOf(e, dim, off = [0, 0, 0], scale = [1, 1, 1]) {
  const [x, y, z = 0] = e.position;
  const w = e.size[0] * scale[0], h = e.size[1] * scale[1], d = (e.size[2] || 0) * scale[2];
  const b = { l: x + off[0] - w / 2, r: x + off[0] + w / 2, bottom: y + off[1] - h / 2, top: y + off[1] + h / 2 };
  if (dim === '3d') { b.n = z + off[2] - d / 2; b.f = z + off[2] + d / 2; }
  return b;
}

/** Edge-to-edge distance between two footprints (2D: x only; 3D: euclidean xz). 0 when overlapping. */
export function footprintGap(a, b) {
  const dx = Math.max(0, b.l - a.r, a.l - b.r);
  const dz = a.n === undefined ? 0 : Math.max(0, b.n - a.f, a.n - b.f);
  return Math.hypot(dx, dz);
}

/** How far footprint a sticks out beyond footprint b on its best side (negative: a lies inside b). */
export function extension(a, b) {
  const ext = [b.l - a.l, a.r - b.r];
  if (a.n !== undefined) ext.push(b.n - a.n, a.f - b.f);
  return Math.max(...ext);
}

function behaviorOf(e) {
  const b = e.behavior;
  if (typeof b === 'string') return { type: b };
  return b && typeof b === 'object' ? b : null;
}

/** Axis index a patrol/move behaviour slides along (ent2d: anything but "x" is vertical). */
function patrolAxis(axis, dim) {
  if (axis === 'x') return 0;
  if (dim === '2d') return 1;
  return axis === 'y' ? 1 : axis === 'z' ? 2 : 0;
}

/** Offsets a moving platform can occupy (amplitudes copied from runtime ent2d/ent3d), sampled. */
export function moverOffsets(e, dim) {
  const b = behaviorOf(e);
  const type = b ? String(b.type || '') : '';
  const range = Math.abs(num(b && b.range, dim === '3d' ? 4 : 200));
  const axis = patrolAxis(String((b && b.axis) || 'x'), dim);
  const along = (i, v) => { const o = [0, 0, 0]; o[i] = v; return o; };
  switch (type) {
    case 'patrol': case 'move':
      return MOVER_SAMPLES.map(s => along(axis, s * range));
    case 'float':
      return MOVER_SAMPLES.map(s => along(1, s * range * (dim === '3d' ? 0.15 : 1)));
    case 'fly': {
      const bob = range * (dim === '3d' ? 0.3 : 0.5);
      return MOVER_SAMPLES.flatMap(sx => [-1, 0, 1].map(sy => [sx * range, sy * bob, 0]));
    }
    default:
      return [[0, 0, 0]];
  }
}

function isSolidDecor(e, dim) {
  if (!['decor', 'sign', 'text'].includes(e.kind)) return false;
  if (dim === '2d' || e.kind !== 'decor') return e.solid === true;
  return e.solid !== undefined ? e.solid === true : DECOR_SOLID_3D.includes(String(e.shape || ''));
}

function decorScale(e, dim) {
  if (dim === '2d') return [0.8, 0.8, 1];
  const shape = String(e.shape || '');
  return ['', 'pine', 'tree'].includes(shape) ? [0.2, 1, 0.2] : [0.9, 0.9, 0.9];
}

/** Standing surfaces + bouncer launch pads. */
export function buildNodes(game, dim, m) {
  const nodes = [];
  const gs = num(game.world && game.world.ground_size, 0);
  if (dim === '3d' && gs > 0) {
    nodes.push({ id: '__ground', name: '地面', kind: 'ground', samples: [{ l: -gs / 2, r: gs / 2, n: -gs / 2, f: gs / 2, top: 0, bottom: -1 }], oneWay: false, v0: m.jump });
  }
  for (const e of Object.values(game.entities || {})) {
    if (e.kind === 'platform') {
      const oneWay = dim === '2d' && e.size[1] <= ONE_WAY_MAX_HEIGHT && e.solid !== true;
      nodes.push({ id: e.id, name: e.name || e.id, kind: 'platform', samples: moverOffsets(e, dim).map(o => boxOf(e, dim, o)), oneWay, v0: m.jump });
    } else if (isSolidDecor(e, dim)) {
      nodes.push({ id: e.id, name: e.name || e.id, kind: 'decor', samples: [boxOf(e, dim, [0, 0, 0], decorScale(e, dim))], oneWay: false, v0: m.jump });
    } else if (e.kind === 'bouncer') {
      const strength = num(e.strength, m.bounce);
      nodes.push({ id: e.id, name: e.name || e.id, kind: 'bouncer', samples: [boxOf(e, dim)], oneWay: true, v0: m.jump * Math.max(0.1, strength) });
    }
  }
  return nodes;
}

/** Cost of jumping from surface sample a (launch speed v0) onto surface sample b. */
export function surfaceCost(m, a, v0, b, bOneWay) {
  // Overlapping footprints need care: one-way platforms are jumped through from below, solid ones are not.
  const dh = b.top - a.top;
  let gap = footprintGap(a, b);
  if (gap === 0) {
    const eps = m.dim === '3d' ? 0.05 : 2;
    if (dh > eps) {
      // Solid surface overhead: only reachable by standing where a sticks out past b and jumping around the lip.
      if (!bOneWay && extension(a, b) < m.radius) return { d: Infinity, gap: 0, dh };
    } else if (dh < -eps) {
      // Lower surface underneath: land on the part of b beyond a's edge, or steer back under a if there is headroom.
      const ext = extension(b, a);
      if (ext < m.radius && a.bottom - b.top < m.bodyHeight) return { d: Infinity, gap: 0, dh };
      gap = Math.max(0, m.radius - ext);
    }
  }
  return { d: jumpDifficulty(m, gap, dh, v0), gap, dh };
}

/** Cost of touching an item box from surface sample a (launch speed v0). */
export function touchCost(m, a, v0, item) {
  const s = item.support;
  if (s && s !== a && a.top < s.top - (m.dim === '3d' ? 0.05 : 2) && footprintGap(a, s) === 0 && extension(a, s) < m.radius) {
    return { d: Infinity, gap: 0, dh: s.top - a.top }; // blocked by the solid support overhead
  }
  const lo = item.bottom - m.bodyHeight - a.top; // feet height where the head grazes the item
  const hi = item.top - a.top;                    // feet height where the feet graze the item
  const dh = lo > 0 ? lo : hi < 0 ? hi : 0;
  let gap = footprintGap(a, item);
  if (gap === 0 && hi < 0) {
    // item hangs below this surface: walk off an edge and steer back under it
    if (a.bottom - item.top < m.bodyHeight * 0.5 && extension(item, a) < 0) return { d: Infinity, gap: 0, dh };
    gap = Math.max(0, -extension(item, a));
  }
  return { d: jumpDifficulty(m, gap, dh, v0), gap, dh };
}

function bestOver(samplesA, samplesB, fn) {
  let best = null;
  for (const a of samplesA) for (const b of samplesB) {
    const c = fn(a, b);
    if (!best || c.d < best.d) best = c;
  }
  return best;
}

/** Cost from node A to node B. Bouncers are entered by touch, not by landing. */
function nodeCost(m, A, B) {
  if (B.kind === 'bouncer') return bestOver(A.samples, B.samples, (a, b) => touchCost(m, a, A.v0, b));
  return bestOver(A.samples, B.samples, (a, b) => surfaceCost(m, a, A.v0, b, B.oneWay));
}

/** The highest surface directly under the spawn point, or null. */
export function spawnSurface(nodes, game, dim, m) {
  const p = game.player.position;
  const feet = p[1] - m.bodyHeight / 2;
  const at = { l: p[0], r: p[0], n: dim === '3d' ? p[2] : undefined, f: dim === '3d' ? p[2] : undefined };
  let best = null;
  for (const n of nodes) {
    if (n.kind === 'bouncer') continue;
    const s = n.samples[Math.floor(n.samples.length / 2)];
    if (footprintGap(at, s) > m.radius) continue;
    if (s.top > feet + SPAWN_EPS[dim]) continue;
    if (!best || s.top > best.top) best = { node: n, top: s.top };
  }
  return best && best.node;
}

/**
 * Minimax ("easiest hardest jump") search from the spawn node. Returns per-node best difficulty and the
 * predecessor edge used, so paths can be reconstructed.
 */
function bottleneckSearch(nodes, costs, start) {
  const best = nodes.map(() => Infinity);
  const prev = nodes.map(() => -1);
  const hops = nodes.map(() => Infinity);
  const done = nodes.map(() => false);
  best[start] = 0; hops[start] = 0;
  for (;;) {
    let u = -1;
    for (let i = 0; i < nodes.length; i++) {
      if (!done[i] && best[i] <= 1 && (u < 0 || best[i] < best[u] || (best[i] === best[u] && hops[i] < hops[u]))) u = i;
    }
    if (u < 0) break;
    done[u] = true;
    for (let v = 0; v < nodes.length; v++) {
      if (v === u || done[v]) continue;
      const d = Math.max(best[u], costs[u][v].d);
      if (d > 1) continue;
      if (d < best[v] - 1e-9 || (Math.abs(d - best[v]) <= 1e-9 && hops[u] + 1 < hops[v])) { best[v] = d; prev[v] = u; hops[v] = hops[u] + 1; }
    }
  }
  return { best, prev };
}

function pathTo(prev, i) {
  const out = [];
  for (let k = i; k >= 0; k = prev[k]) out.unshift(k);
  return out;
}

const round = (dim, v) => +Number(v).toFixed(dim === '3d' ? 2 : 0);

/** Describe the most promising (reachable) launch point towards an unreachable target. */
function nearestApproach(m, nodes, reach, costTo) {
  let best = null;
  nodes.forEach((n, i) => {
    if (reach.best[i] > 1) return;
    const c = costTo(n);
    if (!best || c.d < best.c.d) best = { n, c };
  });
  if (!best) return null;
  const limit = maxGap(m, best.c.dh, best.n.v0);
  return { from: best.n.id, fromName: best.n.name, gap: round(m.dim, best.c.gap), rise: round(m.dim, best.c.dh), limitGap: limit === null ? 0 : round(m.dim, limit), limitRise: round(m.dim, maxRise(m, best.n.v0)) };
}

/**
 * Full reachability analysis. Returns null for top-down games.
 * { spawn, nodes, reachable:Set(ids), items: {id: {d, from}}, goalPath, isolated, unreachableItems }
 */
export function analyzeReach(game, dim) {
  const m = jumpModel(dim, game);
  const nodes = buildNodes(game, dim, m);
  const spawn = spawnSurface(nodes, game, dim, m);
  const result = { model: m, nodes, spawn: spawn ? spawn.id : null, items: {}, isolated: [], approach: {} };
  if (!spawn) return result;
  const costs = nodes.map(A => nodes.map(B => (A === B ? { d: 0, gap: 0, dh: 0 } : nodeCost(m, A, B))));
  const reach = bottleneckSearch(nodes, costs, nodes.indexOf(spawn));
  result.difficulty = Object.fromEntries(nodes.map((n, i) => [n.id, reach.best[i]]));
  result.isolated = nodes.filter((n, i) => n.kind === 'platform' && reach.best[i] > 1).map(n => n.id);
  for (const id of result.isolated) {
    const B = nodes.find(n => n.id === id);
    result.approach[id] = nearestApproach(m, nodes, reach, A => nodeCost(m, A, B));
  }
  for (const e of Object.values(game.entities || {})) {
    if (!ITEM_KINDS.includes(e.kind)) continue;
    const box = touchBox(boxOf(e, dim), nodes, m);
    let best = { d: Infinity, via: -1, jump: null };
    nodes.forEach((n, i) => {
      if (reach.best[i] > 1) return;
      const c = bestOver(n.samples, [box], (a, b) => touchCost(m, a, n.v0, b));
      const d = Math.max(reach.best[i], c.d);
      if (d < best.d) best = { d, via: i, jump: c };
    });
    const info = { d: best.d, reachable: best.d <= 1 };
    if (info.reachable) info.path = pathTo(reach.prev, best.via).map(i => nodes[i].id);
    else info.approach = nearestApproach(m, nodes, reach, n => bestOver(n.samples, [box], (a, b) => touchCost(m, a, n.v0, b)));
    if (info.reachable) info.hardest = hardestJump(m, nodes, costs, pathTo(reach.prev, best.via), best.jump, e.id);
    result.items[e.id] = info;
  }
  return result;
}

/**
 * Attach the solid surface an item rests on (if any). Such an item can only be touched with the feet at
 * or above that surface (no grabbing it through the block's side or underside). One-way and moving
 * supports are ignored: the player passes through those.
 */
export function touchBox(item, nodes, m) {
  const eps = m.dim === '3d' ? 0.15 : 8;
  const cx = (item.l + item.r) / 2;
  const cz = item.n === undefined ? undefined : (item.n + item.f) / 2;
  let support = null;
  for (const n of nodes) {
    if (n.oneWay || n.samples.length > 1) continue;
    const s = n.samples[0];
    const under = cx >= s.l && cx <= s.r && (cz === undefined || (cz >= s.n && cz <= s.f));
    if (under && Math.abs(s.top - item.bottom) <= eps && (!support || s.top > support.top)) support = s;
  }
  return support ? { ...item, bottom: Math.max(item.bottom, support.top + m.bodyHeight), support } : item;
}

/** Hardest single jump along a node path (plus the final touch of the target). */
function hardestJump(m, nodes, costs, path, finalTouch, targetId) {
  let worst = { from: nodes[path[path.length - 1]].id, to: targetId, ...finalTouch };
  for (let k = 1; k < path.length; k++) {
    const c = costs[path[k - 1]][path[k]];
    if (c.d > worst.d) worst = { from: nodes[path[k - 1]].id, to: nodes[path[k]].id, ...c };
  }
  return {
    from: worst.from, to: worst.to, gap: round(m.dim, worst.gap), rise: round(m.dim, worst.dh),
    difficulty: +worst.d.toFixed(2), margin: +(1 - worst.d).toFixed(2), tooHard: worst.d > HARD_RATIO,
  };
}
