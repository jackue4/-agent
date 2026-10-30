import { weighted } from './rng.js'

export const BASE = {
  hp: 100,
  atk: 14,
  speed: 7.6,
  radius: 0.34,
  crit: 0.05,
  critDmg: 1.5,
}

export const WEAPONS = {
  qingfeng: {
    id: 'qingfeng',
    name: '青锋',
    blurb: '去而复返。站定后剑飞向最近的敌人，再沿路飞回，回程仍能伤人。',
    speed: 18,
    dmg: 1,
    returnDmg: 0.55,
    interval: 0.48,
    windup: 0.12,
    range: 15,
    knock: 0.6,
    arc: 0,
    pierce: false,
    color: 0x8fd6ff,
  },
  xunying: {
    id: 'xunying',
    name: '迅影',
    blurb: '出剑极快，飞不远。要走进敌人再凝神，靠攻速和连御叠伤害。',
    speed: 26,
    dmg: 0.55,
    returnDmg: 0.4,
    interval: 0.28,
    windup: 0.06,
    range: 9.2,
    knock: 0.2,
    arc: 0,
    pierce: false,
    color: 0xc9d4ff,
  },
  zhongyue: {
    id: 'zhongyue',
    name: '重岳',
    blurb: '慢，重，击退强。凝神前摇更长，贪刀时最容易被砸中。',
    speed: 12,
    dmg: 1.85,
    returnDmg: 0.45,
    interval: 0.86,
    windup: 0.26,
    range: 14,
    knock: 2.6,
    arc: 0,
    pierce: false,
    color: 0xffb15a,
  },
  huihuan: {
    id: 'huihuan',
    name: '回环',
    blurb: '走弧线并穿透。它已经会穿人，再拿穿透或折壁没有好处。',
    speed: 14,
    dmg: 0.88,
    returnDmg: 0.85,
    interval: 0.62,
    windup: 0.12,
    range: 12,
    knock: 0.3,
    arc: 2.3,
    pierce: true,
    color: 0xd59bff,
  },
}

const SKILL_LIST = [
  { id: 'front', name: '齐射', kind: 'sword', max: 2, weight: 14, desc: '正前方多一把剑。每层让全部飞剑伤害变为 75%。' },
  { id: 'multi', name: '连御', kind: 'sword', max: 2, weight: 14, desc: '同一轮额外追发一波。每层伤害 ×0.9，出剑间隔 ×1.15。' },
  { id: 'diagonal', name: '雁行', kind: 'sword', max: 2, weight: 12, desc: '每一层在斜前方两侧各加一把剑。配合折壁会扫到墙边。' },
  { id: 'side', name: '左右游', kind: 'sword', max: 1, weight: 8, desc: '身体左右各飞出一把剑。' },
  { id: 'rear', name: '回身', kind: 'sword', max: 1, weight: 7, desc: '背后也飞出一把剑。有折壁时，它能弹回身前。' },
  { id: 'ricochet', name: '跳斩', kind: 'sword', max: 1, weight: 13, desc: '命中后折向附近敌人，最多 3 次。每次折转伤害 ×0.7。' },
  { id: 'pierce', name: '穿心', kind: 'sword', max: 1, weight: 9, banOnLoop: true, desc: '穿透敌人继续飞。每穿过一个，后续伤害 ×0.67。' },
  { id: 'bouncy', name: '折壁', kind: 'sword', max: 1, weight: 9, banOnLoop: true, desc: '碰到墙或石柱会折返，每次折返后伤害 ×0.5。' },
  { id: 'orbit', name: '剑丸', kind: 'sword', max: 2, weight: 12, desc: '增加两把只绕身、不飞出的剑。贴着走就能刮伤敌人，也能挡弹。' },
  { id: 'chase', name: '追魂', kind: 'sword', max: 1, weight: 11, desc: '每轮御剑额外追出一把会转弯的剑，伤害更高。' },
  { id: 'rain', name: '剑雨', kind: 'sword', max: 1, weight: 8, desc: '御剑时有几率从空中砸下一剑，伤到一片敌人。' },
  { id: 'wing', name: '剑灵', kind: 'defense', max: 1, weight: 11, desc: '一柄灵剑在身外周旋，替你挡下飞来的弹幕。' },
  { id: 'rage', name: '血怒', kind: 'sword', max: 1, weight: 12, desc: '失去的气血越多，飞剑越重。剩一半血时，伤害约变为 1.5 倍。' },
  { id: 'slow', name: '凝滞', kind: 'defense', max: 1, weight: 12, desc: '敌人的弹幕变慢，走位更从容。' },
  { id: 'dwarf', name: '缩地', kind: 'defense', max: 1, weight: 8, desc: '受击范围变小，移动稍快。' },
  { id: 'star', name: '星护', kind: 'defense', max: 1, weight: 10, desc: '每 10 秒有 2 秒剑气护体，期间不受伤害。' },
  { id: 'blaze', name: '炎意', kind: 'element', max: 1, weight: 9, desc: '命中后短时间持续灼烧。' },
  { id: 'poison', name: '毒意', kind: 'element', max: 1, weight: 7, desc: '命中后中毒，直到目标倒下。伤害不叠加。' },
  { id: 'freeze', name: '霜意', kind: 'element', max: 1, weight: 8, desc: '命中后短暂停住敌人。首领不受冻结。' },
  { id: 'bolt', name: '雷意', kind: 'element', max: 1, weight: 9, desc: '命中时电光溅到附近的其他敌人。' },
  { id: 'atk', name: '攻势', kind: 'stat', max: 3, weight: 6, desc: '飞剑伤害 +30%，可叠加。' },
  { id: 'aspd', name: '迅捷', kind: 'stat', max: 3, weight: 6, desc: '出剑更快，可叠加。' },
  { id: 'crit', name: '暴击', kind: 'stat', max: 2, weight: 6, desc: '暴击率和暴击伤害都提高。' },
  { id: 'hp', name: '气血', kind: 'stat', max: 3, weight: 6, desc: '气血上限提高，并立刻回复新增的部分。' },
  { id: 'blood', name: '饮血', kind: 'defense', max: 2, weight: 5, desc: '击败敌人时回复少量气血。' },
  { id: 'head', name: '斩首', kind: 'sword', max: 1, weight: 7, desc: '飞剑有小几率直接斩杀非首领敌人。' },
  { id: 'extralife', name: '残剑', kind: 'devil', max: 1, weight: 0, devil: true, desc: '致死时改为满血站起一次。只有魔契会给。' },
]

export const MINORS = [
  { id: 'minorAtk', name: '凝气', kind: 'minor', max: 4, weight: 1, desc: '飞剑伤害小幅提升。' },
  { id: 'minorAspd', name: '轻身', kind: 'minor', max: 4, weight: 1, desc: '出剑间隔小幅缩短。' },
  { id: 'minorHp', name: '固本', kind: 'minor', max: 4, weight: 1, desc: '气血上限小幅提升，并回复等量气血。' },
]

export const SKILLS = Object.fromEntries(SKILL_LIST.map((s) => [s.id, s]))
for (const m of MINORS) SKILLS[m.id] = m

export const ENEMIES = {
  chaser: { name: '扑剑傀', hp: 36, speed: 3.05, r: 0.48, touch: 10, xp: 3, color: 0xc4473a },
  archer: { name: '射矢俑', hp: 28, speed: 2.35, r: 0.4, touch: 8, xp: 3, color: 0xe08a3c, shot: 9, shotSpeed: 7.2 },
  jumper: { name: '跃雷', hp: 42, speed: 2.5, r: 0.46, touch: 11, xp: 4, color: 0x8d6bdb, shot: 8, shotSpeed: 5.4 },
  summoner: { name: '唤剑师', hp: 78, speed: 1.85, r: 0.5, touch: 8, xp: 6, color: 0x3fa36a, shot: 8, shotSpeed: 4.4 },
  boss: { name: '守冢傀', hp: 620, speed: 2.15, r: 1.15, touch: 14, xp: 20, color: 0xd7c4a3, shot: 12, shotSpeed: 6.2 },
}

export function slotDefs(counts) {
  const slots = [{ angle: 0, lateral: 0 }]
  const front = counts.front || 0
  for (let i = 0; i < front; i++) {
    const sign = i % 2 === 0 ? 1 : -1
    const row = Math.floor(i / 2) + 1
    slots.push({ angle: 0, lateral: sign * 0.42 * row })
  }
  const diag = counts.diagonal || 0
  for (let i = 0; i < diag; i++) {
    const a = 0.42 + i * 0.18
    slots.push({ angle: a, lateral: 0 }, { angle: -a, lateral: 0 })
  }
  if (counts.side) {
    slots.push({ angle: Math.PI / 2, lateral: 0 }, { angle: -Math.PI / 2, lateral: 0 })
  }
  if (counts.rear) slots.push({ angle: Math.PI, lateral: 0 })
  return slots
}

export function derive(weapon, counts) {
  const front = counts.front || 0
  const multi = counts.multi || 0
  const atkAdd = 0.3 * (counts.atk || 0) + 0.12 * (counts.minorAtk || 0)
  const spdAdd = 0.25 * (counts.aspd || 0) + 0.12 * (counts.minorAspd || 0)
  const hpBonus = 0.2 * (counts.hp || 0) + 0.12 * (counts.minorHp || 0)
  const pacts = counts.pacts || 0
  const dmgMul = 0.75 ** front * 0.9 ** multi * (1 + atkAdd)
  return {
    dmgMul,
    interval: (weapon.interval * 1.15 ** multi) / (1 + spdAdd),
    hitAtk: BASE.atk * weapon.dmg * dmgMul,
    crit: BASE.crit + 0.1 * (counts.crit || 0),
    critDmg: BASE.critDmg + 0.4 * (counts.crit || 0),
    hpMax: BASE.hp * (1 + hpBonus) * 0.8 ** pacts,
    speed: BASE.speed * (counts.dwarf ? 1.08 : 1),
    radius: BASE.radius * (counts.dwarf ? 0.72 : 1),
    pierce: !!(counts.pierce || weapon.pierce),
    bouncy: !!counts.bouncy,
    ricochet: counts.ricochet ? 3 : 0,
    rage: !!counts.rage,
    slow: counts.slow ? 0.62 : 1,
    headshot: counts.head ? 0.125 : 0,
    blood: 0.015 * (counts.blood || 0),
    blaze: !!counts.blaze,
    poison: !!counts.poison,
    freeze: !!counts.freeze,
    boltEl: !!counts.bolt,
    orbitN: (counts.orbit || 0) * 2,
    chase: !!counts.chase,
    rain: !!counts.rain,
    wing: !!counts.wing,
    star: !!counts.star,
    multi,
    knock: weapon.knock,
  }
}

export function offerSkills(rng, counts, weapon, n = 3) {
  const avail = SKILL_LIST.filter((s) => {
    if (s.devil) return false
    if ((counts[s.id] || 0) >= s.max) return false
    if (weapon.pierce && s.banOnLoop) return false
    return true
  })
  const pool = [...avail]
  const picked = []
  while (picked.length < n && pool.length) {
    const choice = weighted(rng, pool)
    picked.push(choice)
    pool.splice(pool.indexOf(choice), 1)
  }
  if (picked.length === 3 && picked.every((s) => s.kind === 'stat')) {
    const alt = pool.find((s) => s.kind === 'sword' || s.kind === 'element')
    if (alt) picked[2] = alt
  }
  return picked
}

export function offerDevil(rng, counts) {
  if (!counts.extralife) return SKILLS.extralife
  const ids = ['multi', 'front', 'rage', 'aspd', 'slow', 'atk', 'chase', 'star']
  const avail = ids.map((id) => SKILLS[id]).filter((s) => s && (counts[s.id] || 0) < s.max)
  if (!avail.length) return null
  return weighted(rng, avail)
}

export function offerAngel(rng, counts, weapon) {
  const minors = MINORS.filter((m) => (counts[m.id] || 0) < m.max)
  if (minors.length) return minors[Math.floor(rng() * minors.length)]
  const one = offerSkills(rng, counts, weapon, 1)
  return one[0] || null
}

export function roomScale(index) {
  return {
    hp: 1 + (index - 1) * 0.15,
    dmg: 1 + (index - 1) * 0.08,
  }
}
