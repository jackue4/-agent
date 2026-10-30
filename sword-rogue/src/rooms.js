import { ENEMIES } from './content.js'

const COMP = {
  1: [['chaser', 4]],
  2: [['chaser', 3], ['archer', 2]],
  3: [['jumper', 1], ['archer', 2], ['chaser', 2]],
  4: [['chaser', 3], ['archer', 2]],
  6: [['jumper', 2], ['archer', 2], ['chaser', 2]],
  7: [['summoner', 1], ['chaser', 2], ['archer', 1]],
  8: [['archer', 3], ['jumper', 1], ['chaser', 2]],
  9: [['chaser', 3]],
}

const NAMES = {
  1: '初试剑',
  2: '双俑',
  3: '落点',
  4: '石柱',
  5: '仙缘',
  6: '夹击',
  7: '唤剑',
  8: '水刺',
  9: '遗箱',
  10: '守冢',
}

function farEnough(x, z, r, room, placed) {
  if (Math.abs(x) > room.halfW - r - 0.6) return false
  if (z > 2.2 || z < -room.halfH + 3.2) return false
  for (const o of room.obstacles) {
    if (Math.hypot(x - o.x, z - o.z) < r + o.r + 0.9) return false
  }
  for (const s of room.spikes) {
    if (Math.hypot(x - s.x, z - s.z) < r + s.r + 0.5) return false
  }
  for (const w of room.waters) {
    if (Math.hypot(x - w.x, z - w.z) < r + w.r * 0.45) return false
  }
  for (const p of placed) {
    if (Math.hypot(x - p.x, z - p.z) < r + p.r + 1.25) return false
  }
  return true
}

function place(rng, type, room, placed) {
  const spec = ENEMIES[type]
  for (let i = 0; i < 40; i++) {
    const x = (rng() * 2 - 1) * (room.halfW - 1.6)
    const z = -room.halfH + 3.4 + rng() * (room.halfH + 2.2 - 3.4)
    if (farEnough(x, z, spec.r, room, placed)) return { type, x, z }
  }
  return { type, x: (rng() * 2 - 1) * 3, z: -2 - rng() * 3 }
}

export function buildRoom(rng, index) {
  const halfW = 8
  const halfH = 11
  const kind = index === 5 ? 'angel' : index === 9 ? 'chest' : index === 10 ? 'boss' : 'combat'
  const obstacles = []
  const waters = []
  const spikes = []
  if (index === 2) obstacles.push({ x: 0, z: -1, r: 0.85 })
  if (index === 4) {
    obstacles.push({ x: -3.4, z: -1.2, r: 0.75 }, { x: 3.4, z: -1.2, r: 0.75 })
    spikes.push({ x: 0, z: 3.4, r: 0.7 })
  }
  if (index === 6) obstacles.push({ x: 0, z: -2, r: 0.95 })
  if (index === 8) {
    obstacles.push({ x: -4.1, z: 0.2, r: 0.7 }, { x: 4.1, z: -2.6, r: 0.7 })
    waters.push({ x: -2.2, z: 2.6, r: 1.65 }, { x: 2.5, z: -0.6, r: 1.45 })
    spikes.push({ x: 0, z: 4.4, r: 0.62 }, { x: -5.1, z: -4, r: 0.55 }, { x: 5.2, z: 1.6, r: 0.55 })
  }
  const room = { index, halfW, halfH, kind, name: NAMES[index] || '剑房', obstacles, waters, spikes, spawns: [] }
  if (index === 10) {
    room.spawns.push({ type: 'boss', x: 0, z: -3.2 })
  } else {
    for (const [type, n] of COMP[index] || []) {
      for (let i = 0; i < n; i++) room.spawns.push(place(rng, type, room, room.spawns))
    }
  }
  return room
}
