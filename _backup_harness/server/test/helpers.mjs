// Shared fixtures for the server unit tests.
import { GameEngine, emptyGame } from '../engine.mjs';

/** A fresh engine on an empty project, planned for the given dimension/genre. */
export function newEngine({ dimension = '2d', genre = 'platformer', meta = {} } = {}) {
  const project = { game: emptyGame() };
  const engine = new GameEngine(project);
  engine.apply('plan_game', { title: '测试', dimension, genre, style: 'cartoon', pitch: 'p', steps: [], ...meta });
  engine.apply('set_rules', { rules: { win: 'goal', instructions: '跑到终点' } });
  return engine;
}

/** Build a level and return the check_game result. */
export function check({ dimension = '2d', genre, entities = [], player, world, rules } = {}) {
  const engine = newEngine({ dimension, genre });
  if (world) engine.apply('set_world', { world });
  if (rules) engine.apply('set_rules', { rules });
  if (player) engine.apply('set_player', { player });
  engine.apply('add_entities', { step: 's', entities });
  return engine.apply('check_game', {}).result;
}

/** 2D platform whose top surface is at y=top, spanning [left, left+width]. */
export function plat2(id, left, width, top, extra = {}) {
  const h = extra.h || 60;
  return { id, kind: 'platform', position: [left + width / 2, top - h / 2], size: [width, h], solid: extra.oneWay ? undefined : true, ...extra, h: undefined, oneWay: undefined };
}

/** 2D item standing on a surface at y=top (default sizes from the engine). */
export function onTop2(id, kind, x, top, h) {
  const size = { goal: 120, collectible: 44, powerup: 52, checkpoint: 110, enemy: 60 }[kind] || 44;
  return { id, kind, position: [x, top + (h || size) / 2] };
}

/** 3D square island with top surface at y=top, centred at (x, z). */
export function island3(id, x, z, top, w = 4, extra = {}) {
  return { id, kind: 'platform', position: [x, top - 0.3, z], size: [w, 0.6, w], ...extra };
}

export const issueTexts = r => r.issues.map(i => i.level + ':' + i.text);
export const hasIssue = (r, level, re) => r.issues.some(i => i.level === level && re.test(i.text));
