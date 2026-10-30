import { derive, offerSkills, WEAPONS } from '../src/content.js'
import { RunSim } from '../src/sim.js'

const front = derive(WEAPONS.qingfeng, { front: 1 })
if (Math.abs(front.dmgMul - 0.75) > 0.001) throw new Error('齐射应让伤害变为 75%')

const loopOffers = new Set()
for (let i = 0; i < 40; i++) {
  const sim = new RunSim(i + 3)
  for (const skill of offerSkills(sim.rng, {}, WEAPONS.huihuan, 3)) loopOffers.add(skill.id)
}
if (loopOffers.has('pierce') || loopOffers.has('bouncy')) {
  throw new Error('回环不应再抽到穿透或折壁')
}

const sim = new RunSim(7)
sim.setWeapon('qingfeng')
sim.grant('multi')
sim.enter(1)
const before = sim.enemies.reduce((sum, e) => sum + e.hp, 0)
if (!sim.enemies.length) throw new Error('第一房没有敌人')
for (let i = 0; i < 240; i++) sim.update(1 / 60, { x: 0, z: 0, moving: false })
const after = sim.enemies.reduce((sum, e) => sum + e.hp, 0)
if (!(after < before || sim.kills > 0)) {
  throw new Error(`站住没有打出伤害 before=${before} after=${after} bolts=${sim.bolts.length}`)
}
sim.update(1 / 60, { x: 1, z: 0, moving: true })
if (sim.focus !== 0) throw new Error('移动后凝神没有断开')
if (!sim.guards.length) throw new Error('移动时没有绕身剑')

const devil = new RunSim(2)
devil.setWeapon('qingfeng')
devil.enter(1)
const offer = devil.offerDevilSkill()
if (!offer || offer.id !== 'extralife') throw new Error('第一份魔契应是残剑')
const maxBefore = devil.player.hpMax
devil.acceptDevil(offer.id)
if (!(devil.player.hpMax < maxBefore - 1)) throw new Error('魔契没有降低气血上限')

console.log('selfcheck ok', { before, after, kills: sim.kills, guards: sim.guards.length })
