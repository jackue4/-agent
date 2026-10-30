import {
  BASE,
  ENEMIES,
  WEAPONS,
  derive,
  offerAngel,
  offerDevil,
  offerSkills,
  roomScale,
  slotDefs,
} from './content.js'
import { buildRoom } from './rooms.js'
import { mulberry32 } from './rng.js'

function hypot(x, z) {
  return Math.hypot(x, z)
}

function clamp(v, a, b) {
  return Math.max(a, Math.min(b, v))
}

function rot(dir, angle) {
  const c = Math.cos(angle)
  const s = Math.sin(angle)
  return { x: dir.x * c - dir.z * s, z: dir.x * s + dir.z * c }
}

function inCircle(x, z, zone) {
  return hypot(x - zone.x, z - zone.z) < zone.r
}

export const ROBES = [
  { name: '青衫', color: 0x3d6f8c },
  { name: '赤衫', color: 0xe25b4a },
  { name: '翠衫', color: 0x3e9a8c },
  { name: '金衫', color: 0xe2b15a },
]

const round = (n) => Math.round(n * 100) / 100

export class RunSim {
  constructor(seed) {
    this.seed = seed >>> 0
    this.rng = mulberry32(this.seed)
    this.events = []
  }

  setWeapon(id) {
    this.weapon = WEAPONS[id]
    this.counts = {}
    this.level = 1
    this.xp = 0
    this.kills = 0
    this.time = 0
    this.player = {
      x: 0,
      z: 0,
      hp: BASE.hp,
      hpMax: BASE.hp,
      r: BASE.radius,
      iframe: 0,
      spikeCd: 0,
      facingX: 0,
      facingZ: -1,
      hitFlash: 0,
    }
    this.bolts = []
    this.guards = []
    this.wing = null
    this.enemies = []
    this.shots = []
    this.orbs = []
    this.hazards = []
    this.queue = []
    this.gcd = new Map()
    this.spin = 0
    this.cd = 0.25
    this.focus = 0
    this.focused = false
    this.moving = false
    this.starClock = 2
    this.pulse = 0
    this.usedLife = false
    this.tookDamage = false
    this.pendingLevel = false
    this.cleared = false
    this.door = false
    this.over = false
    this.won = false
    this.room = null
    this.scale = { hp: 1, dmg: 1 }
    this.eid = 1
    this.target = null
    this.localId = 'local'
    this.offers = {}
    this.recompute()
    this.fighters = []
    this._pushFighter('local', ROBES[0])
    this.active = this.fighters[0]
  }

  makeFighterFields(weaponId) {
    this.weapon = WEAPONS[weaponId] || WEAPONS.qingfeng
    this.counts = {}
    this.player = {
      x: 0,
      z: 0,
      hp: BASE.hp,
      hpMax: BASE.hp,
      r: BASE.radius,
      iframe: 0,
      spikeCd: 0,
      facingX: 0,
      facingZ: -1,
      hitFlash: 0,
    }
    this.bolts = []
    this.guards = []
    this.wing = null
    this.queue = []
    this.gcd = new Map()
    this.spin = 0
    this.cd = 0.25
    this.focus = 0
    this.focused = false
    this.moving = false
    this.starClock = 2
    this.pulse = 0
    this.usedLife = false
    this.recompute()
  }

  setupParty(members, localId) {
    this.localId = localId
    this.fighters = []
    members.slice(0, 4).forEach((member, index) => {
      this.makeFighterFields(member.weapon || 'qingfeng')
      this._pushFighter(member.id, {
        name: member.name || ROBES[index % ROBES.length].name,
        color: member.color || ROBES[index % ROBES.length].color,
      })
    })
    this.bind(this.localFighter())
  }

  _pushFighter(id, look) {
    const fighter = {
      id,
      name: look.name,
      color: look.color,
      weapon: this.weapon,
      counts: this.counts,
      stats: this.stats,
      player: this.player,
      bolts: this.bolts,
      guards: this.guards,
      wing: this.wing,
      queue: this.queue,
      gcd: this.gcd,
      spin: this.spin,
      cd: this.cd,
      focus: this.focus,
      focused: this.focused,
      moving: this.moving,
      starClock: this.starClock,
      pulse: this.pulse,
      usedLife: this.usedLife,
      picked: false,
      chosen: false,
    }
    this.fighters.push(fighter)
    this.active = fighter
    return fighter
  }

  localFighter() {
    return this.fighters.find((fighter) => fighter.id === this.localId) || this.fighters[0]
  }

  fighterById(id) {
    return this.fighters.find((fighter) => fighter.id === id) || this.localFighter()
  }

  bind(fighter) {
    this.active = fighter
    this.weapon = fighter.weapon
    this.counts = fighter.counts
    this.stats = fighter.stats
    this.player = fighter.player
    this.bolts = fighter.bolts
    this.guards = fighter.guards
    this.wing = fighter.wing
    this.queue = fighter.queue
    this.gcd = fighter.gcd
    this.spin = fighter.spin
    this.cd = fighter.cd
    this.focus = fighter.focus
    this.focused = fighter.focused
    this.moving = fighter.moving
    this.starClock = fighter.starClock
    this.pulse = fighter.pulse
    this.usedLife = fighter.usedLife
  }

  save(fighter) {
    fighter.weapon = this.weapon
    fighter.counts = this.counts
    fighter.stats = this.stats
    fighter.player = this.player
    fighter.bolts = this.bolts
    fighter.guards = this.guards
    fighter.wing = this.wing
    fighter.queue = this.queue
    fighter.gcd = this.gcd
    fighter.spin = this.spin
    fighter.cd = this.cd
    fighter.focus = this.focus
    fighter.focused = this.focused
    fighter.moving = this.moving
    fighter.starClock = this.starClock
    fighter.pulse = this.pulse
    fighter.usedLife = this.usedLife
  }

  living() {
    return this.fighters.filter((fighter) => fighter.player.hp > 0)
  }

  nearestFighter(x, z) {
    let best = null
    let bestD = Infinity
    for (const fighter of this.living()) {
      const d = hypot(fighter.player.x - x, fighter.player.z - z)
      if (d < bestD) {
        bestD = d
        best = fighter
      }
    }
    return best
  }

  hurtFighter(fighter, amount, srcX, srcZ) {
    this.bind(fighter)
    this.hurtPlayer(amount, srcX, srcZ)
    this.save(fighter)
  }

  recompute() {
    const prev = this.player.hpMax
    this.stats = derive(this.weapon, this.counts)
    this.player.hpMax = this.stats.hpMax
    if (this.stats.hpMax > prev) this.player.hp += this.stats.hpMax - prev
    if (this.player.hp > this.player.hpMax) this.player.hp = this.player.hpMax
    this.player.r = this.stats.radius
    if (this.active) this.active.stats = this.stats
  }

  grant(id) {
    if (id) this.counts[id] = (this.counts[id] || 0) + 1
    this.recompute()
  }

  xpNeed() {
    return 8 + (this.level - 1) * 5
  }

  pickSkill(id, fighterId = this.localId) {
    const fighter = this.fighterById(fighterId)
    this.bind(fighter)
    if (id) this.grant(id)
    else this.healFrac(0.15)
    fighter.picked = true
    this.save(fighter)
    const waiting = this.living().filter((item) => !item.picked)
    if (waiting.length) {
      this.pendingLevel = true
      this.bind(this.localFighter())
      return
    }
    const need = this.xpNeed()
    this.xp = Math.max(0, this.xp - need)
    this.level += 1
    for (const item of this.fighters) item.picked = false
    this.pendingLevel = this.xp >= this.xpNeed()
    if (this.pendingLevel) this.rollOffers('level')
    this.bind(this.localFighter())
  }

  chooseAngel(choiceId, fighterId = this.localId) {
    const fighter = this.fighterById(fighterId)
    this.bind(fighter)
    if (choiceId === 'heal') this.healFrac(0.4)
    else if (choiceId) this.grant(choiceId)
    fighter.chosen = true
    this.save(fighter)
    if (this.living().every((item) => item.chosen)) {
      this.door = true
      for (const item of this.fighters) item.chosen = false
    }
    this.bind(this.localFighter())
  }

  chooseDevil(choiceId, fighterId = this.localId) {
    const fighter = this.fighterById(fighterId)
    this.bind(fighter)
    if (choiceId && choiceId !== 'no') this.acceptDevil(choiceId)
    fighter.chosen = true
    this.save(fighter)
    const done = this.living().every((item) => item.chosen)
    if (done) for (const item of this.fighters) item.chosen = false
    this.bind(this.localFighter())
    return done
  }

  rollOffers(kind) {
    this.offers = {}
    for (const fighter of this.living()) {
      this.bind(fighter)
      fighter.picked = false
      fighter.chosen = false
      if (kind === 'angel') {
        const skill = this.offerAngelSkill()
        const cards = [{ id: 'heal', name: '回春', desc: '立即回复 40% 气血。', kind: 'heal' }]
        if (skill) cards.push(skill)
        this.offers[fighter.id] = cards
      } else if (kind === 'devil') {
        const skill = this.offerDevilSkill()
        this.offers[fighter.id] = skill
          ? [skill, { id: 'no', name: '拒绝', desc: '不签契约。气血上限保持原样。', kind: 'no' }]
          : [{ id: 'no', name: '拒绝', desc: '没有可换的剑招。', kind: 'no' }]
      } else {
        this.offers[fighter.id] = this.offer(3)
      }
    }
    this.bind(this.localFighter())
  }

  acceptDevil(id) {
    this.counts.pacts = (this.counts.pacts || 0) + 1
    this.grant(id)
  }

  healFrac(frac) {
    this.player.hp = Math.min(this.player.hpMax, this.player.hp + this.player.hpMax * frac)
  }

  offer(n = 3) {
    return offerSkills(this.rng, this.counts, this.weapon, n)
  }

  offerDevilSkill() {
    return offerDevil(this.rng, this.counts)
  }

  offerAngelSkill() {
    return offerAngel(this.rng, this.counts, this.weapon)
  }

  stance() {
    if (this.moving) return '游身'
    if (this.focused) return '凝神'
    return '聚剑'
  }

  guardActive() {
    return this.stats.star && this.starClock % 10 < 2
  }

  enter(index) {
    this.room = buildRoom(this.rng, index)
    this.scale = roomScale(index)
    if (this.room.kind === 'chest') this.scale = { hp: this.scale.hp * 0.7, dmg: this.scale.dmg }
    this.tookDamage = false
    this.cleared = false
    this.door = false
    this.shots = []
    this.orbs = []
    this.hazards = []
    this.enemies = []
    const party = 1 + 0.7 * Math.max(0, this.fighters.length - 1)
    this.scale = { hp: this.scale.hp * party, dmg: this.scale.dmg }
    this.fighters.forEach((fighter, index) => {
      this.bind(fighter)
      const span = Math.max(0, this.fighters.length - 1)
      this.player.x = (index - span / 2) * 1.7
      this.player.z = this.room.halfH - 2.4
      this.player.iframe = 0.85
      this.player.facingX = 0
      this.player.facingZ = -1
      this.bolts = []
      this.queue = []
      this.focus = 0
      this.cd = 0.2
      this.guards = []
      this.wing = null
      this.save(fighter)
    })
    if (this.room.kind !== 'angel') {
      for (const spawn of this.room.spawns) this.spawnEnemy(spawn.type, spawn.x, spawn.z, false)
    } else {
      this.rollOffers('angel')
    }
    this.bind(this.localFighter())
    this.events.push({ t: 'enter', room: this.room, offers: this.offers })
  }

  spawnEnemy(type, x, z, summoned) {
    const spec = ENEMIES[type]
    const hp = spec.hp * this.scale.hp * (summoned ? 0.62 : 1)
    this.enemies.push({
      id: this.eid++,
      type,
      name: spec.name,
      x,
      z,
      r: spec.r * (summoned ? 0.85 : 1),
      hp,
      hpMax: hp,
      speed: spec.speed,
      touchDmg: spec.touch,
      shot: spec.shot || 8,
      shotSpeed: spec.shotSpeed || 6,
      xp: summoned ? 1 : spec.xp,
      summoned: !!summoned,
      state: 'move',
      action: '',
      timer: 0,
      gap: 0.6 + this.rng() * 0.5,
      touch: 0.3,
      vx: 0,
      vz: 0,
      frozen: 0,
      burn: 0,
      burnDmg: 0,
      burnTick: 0,
      poison: false,
      poisonDmg: 0,
      poisonTick: 0,
      hitFlash: 0,
      lockX: x,
      lockZ: z,
      tellR: 0.8,
      step: type === 'summoner' ? 3.4 : 0,
      rot: this.rng() * Math.PI,
      strafe: this.rng() < 0.5 ? -1 : 1,
      leapT: 0,
      lx0: x,
      lz0: z,
      dashX: 0,
      dashZ: 0,
      dead: false,
    })
  }

  normalizeInputs(input) {
    if (!input) return {}
    if (typeof input.x === 'number') return { [this.localFighter().id]: input }
    return input
  }

  update(dt, input) {
    this.events.length = 0
    if (!this.room || this.over || this.won || !this.fighters?.length) return
    this.time += dt
    const inputs = this.normalizeInputs(input)
    for (const fighter of this.fighters) {
      this.bind(fighter)
      this.starClock += dt
      this.pulse = Math.max(0, this.pulse - dt * 3)
      if (this.player.hp > 0) this.stepFighter(dt, inputs[fighter.id] || { x: 0, z: 0, moving: false })
      this.bolts = this.bolts.filter((bolt) => !bolt.dead)
      this.save(fighter)
    }
    this.updateEnemies(dt)
    this.updateShots(dt)
    this.updateHazards(dt)
    this.updateDots(dt)
    this.separate()
    this.separateFighters()
    this.updateOrbs(dt)
    this.enemies = this.enemies.filter((e) => !e.dead)
    this.shots = this.shots.filter((s) => !s.dead)
    this.hazards = this.hazards.filter((h) => h.t < h.delay + 0.35)
    this.bind(this.localFighter())
    this.checkClear()
    this.checkLevel()
    if (!this.pendingLevel) this.checkDoor()
  }

  stepFighter(dt, move) {
    this.player.iframe = Math.max(0, this.player.iframe - dt)
    this.player.spikeCd = Math.max(0, this.player.spikeCd - dt)
    this.player.hitFlash = Math.max(0, this.player.hitFlash - dt)
    this.moving = !!move.moving
    if (this.moving) {
      const water = this.room.waters.some((w) => inCircle(this.player.x, this.player.z, w))
      const sp = this.stats.speed * (water ? 0.55 : 1)
      this.player.facingX = move.x
      this.player.facingZ = move.z
      this.player.x += move.x * sp * dt
      this.resolve(this.player)
      this.player.z += move.z * sp * dt
      this.resolve(this.player)
      this.focus = 0
      this.queue.length = 0
    } else {
      this.focus += dt
    }
    this.focused = !this.moving && this.focus >= this.weapon.windup
    if (this.player.spikeCd <= 0) {
      for (const spike of this.room.spikes) {
        if (inCircle(this.player.x, this.player.z, spike)) {
          this.player.spikeCd = 0.48
          this.hurtPlayer(7 * this.scale.dmg, spike.x, spike.z)
          break
        }
      }
    }
    this.updateOrbit(dt)
    this.updateFire(dt)
    this.updateBolts(dt)
  }

  updateFire(dt) {
    this.cd -= dt
    if (this.focused && this.cd <= 0 && !this.won) {
      this.launchVolley()
      this.cd = this.stats.interval
      this.pulse = 1
      this.events.push({ t: 'fire' })
      for (let i = 1; i <= this.stats.multi; i++) this.queue.push(0.11 * i)
      if (this.stats.chase) this.launchChase()
      if (this.stats.rain && this.rng() < 0.22) this.launchRain()
    }
    if (!this.moving) {
      for (let i = this.queue.length - 1; i >= 0; i--) {
        this.queue[i] -= dt
        if (this.queue[i] <= 0) {
          this.queue.splice(i, 1)
          this.launchVolley()
          this.events.push({ t: 'fire' })
        }
      }
    }
  }

  aimDir() {
    let best = null
    let bestD = Infinity
    for (const e of this.enemies) {
      if (e.dead) continue
      const d = hypot(e.x - this.player.x, e.z - this.player.z)
      if (d < bestD) {
        bestD = d
        best = e
      }
    }
    this.target = best
    if (this.active) this.active.target = best
    if (!best) return { x: this.player.facingX, z: this.player.facingZ || -1 }
    const dx = best.x - this.player.x
    const dz = best.z - this.player.z
    const l = hypot(dx, dz) || 1
    this.player.facingX = dx / l
    this.player.facingZ = dz / l
    return { x: dx / l, z: dz / l }
  }

  launchVolley() {
    const defs = slotDefs(this.counts)
    const aim = this.aimDir()
    const speed = this.weapon.speed
    defs.forEach((def, i) => {
      if (this.bolts.length > 42) return
      const dir = rot(aim, def.angle)
      const g = this.guards[i]
      const sideX = -dir.z
      const sideZ = dir.x
      this.bolts.push({
        x: (g ? g.x : this.player.x) + sideX * def.lateral,
        z: (g ? g.z : this.player.z) + sideZ * def.lateral,
        vx: dir.x * speed,
        vz: dir.z * speed,
        phase: 'out',
        dmgScale: 1,
        traveled: 0,
        ricUsed: 0,
        pierced: 0,
        wallBounces: 0,
        seen: new Set(),
        noHit: 0,
        arc: this.weapon.arc || 0,
        homing: false,
        kind: 'bolt',
        r: 0.46,
        dead: false,
        color: this.weapon.color,
        id: `b${this.bid = (this.bid || 0) + 1}`,
      })
    })
  }

  launchChase() {
    const aim = this.aimDir()
    const speed = this.weapon.speed * 0.95
    this.bolts.push({
      x: this.player.x + aim.x * 0.4,
      z: this.player.z + aim.z * 0.4,
      vx: aim.x * speed,
      vz: aim.z * speed,
      phase: 'out',
      dmgScale: 1.55,
      traveled: 0,
      ricUsed: 0,
      pierced: 0,
      wallBounces: 0,
      seen: new Set(),
      noHit: 0,
      arc: 0,
      homing: true,
      color: 0xfff1c2,
      id: `c${this.bid = (this.bid || 0) + 1}`,
      kind: 'chase',
      r: 0.42,
      dead: false,
      life: 2.3,
    })
  }

  launchRain() {
    const living = this.enemies.filter((e) => !e.dead)
    if (!living.length) return
    const e = living[Math.floor(this.rng() * living.length)]
    this.hazards.push({
      kind: 'rain',
      x: e.x,
      z: e.z,
      t: 0,
      delay: 0.38,
      r: 1.55,
      hit: false,
    })
  }

  updateOrbit(dt) {
    const gather = this.moving ? 0 : clamp(this.focus / this.weapon.windup, 0, 1)
    const rad = 1.38 - gather * 0.5 + this.pulse * 0.25
    const defs = slotDefs(this.counts)
    const total = Math.max(1, defs.length + this.stats.orbitN)
    this.spin += dt * (1.4 + gather * 4.5)
    this.guards = []
    for (let i = 0; i < defs.length; i++) {
      const ang = this.spin + (i / total) * Math.PI * 2
      this.guards.push({
        x: this.player.x + Math.cos(ang) * rad,
        z: this.player.z + Math.sin(ang) * rad,
        ang,
        r: 0.42,
        kind: 'form',
        i,
      })
    }
    for (let i = 0; i < this.stats.orbitN; i++) {
      const ang = -this.spin * 1.25 + (i / total) * Math.PI * 2 + 0.5
      this.guards.push({
        x: this.player.x + Math.cos(ang) * (rad + 0.2),
        z: this.player.z + Math.sin(ang) * (rad + 0.2),
        ang,
        r: 0.5,
        kind: 'orbit',
        i,
      })
    }
    if (this.stats.wing) {
      const ang = this.time * 2.2
      this.wing = {
        x: this.player.x + Math.cos(ang) * 2.2,
        z: this.player.z + Math.sin(ang) * 2.2,
        r: 0.72,
      }
    } else this.wing = null

    for (const [key, left] of this.gcd) {
      if (left - dt <= 0) this.gcd.delete(key)
      else this.gcd.set(key, left - dt)
    }
    for (const g of this.guards) {
      const allow = g.kind === 'orbit' || this.moving
      if (!allow) continue
      for (const e of this.enemies) {
        if (e.dead) continue
        if (hypot(e.x - g.x, e.z - g.z) > e.r + g.r) continue
        const key = `${g.kind}:${g.i}:${e.id}`
        if (this.gcd.has(key)) continue
        this.gcd.set(key, g.kind === 'orbit' ? 0.32 : 0.48)
        const dx = e.x - g.x
        const dz = e.z - g.z
        const l = hypot(dx, dz) || 1
        this.hurtEnemy(e, g.kind === 'orbit' ? 0.7 : 0.22, {
          dirX: dx / l,
          dirZ: dz / l,
          knock: 0.4,
          head: true,
          proc: true,
          crit: true,
        })
      }
    }
  }

  updateBolts(dt) {
    const speed = this.weapon.speed
    for (const bolt of this.bolts) {
      if (bolt.dead) continue
      bolt.noHit = Math.max(0, (bolt.noHit || 0) - dt)
      if (bolt.homing) {
        bolt.life -= dt
        const target = this.nearestEnemy(bolt.x, bolt.z, Infinity)
        if (target) {
          const dx = target.x - bolt.x
          const dz = target.z - bolt.z
          const l = hypot(dx, dz) || 1
          const tx = (dx / l) * speed
          const tz = (dz / l) * speed
          const k = 1 - Math.exp(-7 * dt)
          bolt.vx += (tx - bolt.vx) * k
          bolt.vz += (tz - bolt.vz) * k
        }
        if (bolt.life <= 0) {
          bolt.dead = true
          continue
        }
      } else if (bolt.arc && bolt.phase === 'out') {
        const ang = bolt.arc * dt
        const c = Math.cos(ang)
        const s = Math.sin(ang)
        const vx = bolt.vx * c - bolt.vz * s
        const vz = bolt.vx * s + bolt.vz * c
        bolt.vx = vx
        bolt.vz = vz
      }

      if (bolt.phase === 'back') {
        const dx = this.player.x - bolt.x
        const dz = this.player.z - bolt.z
        const d = hypot(dx, dz)
        const sp = speed * 1.22
        if (d < 0.5) {
          bolt.dead = true
          continue
        }
        const tx = (dx / d) * sp
        const tz = (dz / d) * sp
        const k = 1 - Math.exp(-8 * dt)
        bolt.vx += (tx - bolt.vx) * k
        bolt.vz += (tz - bolt.vz) * k
      }

      bolt.x += bolt.vx * dt
      bolt.z += bolt.vz * dt
      const step = hypot(bolt.vx, bolt.vz) * dt
      bolt.traveled += step
      if (!bolt.homing && bolt.phase === 'out' && bolt.traveled >= this.weapon.range) bolt.phase = 'back'
      this.boltWalls(bolt)

      if (bolt.noHit <= 0) {
        const spLen = hypot(bolt.vx, bolt.vz) || 1
        const hx = bolt.x + (bolt.vx / spLen) * 0.32
        const hz = bolt.z + (bolt.vz / spLen) * 0.32
        for (const e of this.enemies) {
          if (e.dead) continue
          if (hypot(e.x - hx, e.z - hz) > e.r + bolt.r) continue
          const key = `${bolt.phase}:${e.id}`
          if (bolt.seen.has(key)) continue
          bolt.seen.add(key)
          this.onSwordHit(bolt, e)
          break
        }
      }
    }
  }

  boltWalls(bolt) {
    const hw = this.room.halfW - 0.15
    const hh = this.room.halfH - 0.15
    const bounce = (axis) => {
      if (this.stats.bouncy && bolt.wallBounces < 2 && bolt.phase === 'out' && !bolt.homing) {
        if (axis === 'x') bolt.vx *= -1
        else bolt.vz *= -1
        bolt.wallBounces++
        bolt.x = clamp(bolt.x, -hw, hw)
        bolt.z = clamp(bolt.z, -hh, hh)
        return
      }
      if (bolt.homing) bolt.dead = true
      else if (bolt.phase === 'out') bolt.phase = 'back'
      bolt.x = clamp(bolt.x, -hw, hw)
      bolt.z = clamp(bolt.z, -hh, hh)
    }
    if (bolt.x > hw || bolt.x < -hw) bounce('x')
    if (bolt.dead) return
    if (bolt.z > hh || bolt.z < -hh) bounce('z')
    if (bolt.dead) return
    for (const o of this.room.obstacles) {
      const dx = bolt.x - o.x
      const dz = bolt.z - o.z
      const d = hypot(dx, dz)
      const min = o.r + 0.18
      if (d >= min) continue
      if (this.stats.bouncy && bolt.wallBounces < 2 && bolt.phase === 'out' && !bolt.homing) {
        const nx = dx / (d || 1)
        const nz = dz / (d || 1)
        const dot = bolt.vx * nx + bolt.vz * nz
        bolt.vx -= 2 * dot * nx
        bolt.vz -= 2 * dot * nz
        bolt.x = o.x + nx * (min + 0.05)
        bolt.z = o.z + nz * (min + 0.05)
        bolt.wallBounces++
      } else if (bolt.homing) bolt.dead = true
      else if (bolt.phase === 'out') bolt.phase = 'back'
    }
  }

  onSwordHit(bolt, enemy) {
    const ricUsed = bolt.ricUsed || 0
    const pierced = bolt.pierced || 0
    let scale = bolt.dmgScale * 0.7 ** ricUsed * 0.67 ** pierced * 0.5 ** (bolt.wallBounces || 0)
    if (bolt.phase === 'back') scale *= this.weapon.returnDmg
    const sp = hypot(bolt.vx, bolt.vz) || 1
    this.hurtEnemy(enemy, scale, {
      dirX: bolt.vx / sp,
      dirZ: bolt.vz / sp,
      knock: this.stats.knock,
      head: true,
      proc: true,
      crit: true,
      trauma: this.weapon.knock > 2 ? 0.12 : 0,
    })
    bolt.noHit = 0.05
    if (bolt.homing) {
      bolt.dead = true
      return
    }
    if (bolt.phase === 'out' && this.stats.ricochet && ricUsed < this.stats.ricochet) {
      const next = this.nearestEnemy(enemy.x, enemy.z, 7, enemy.id)
      if (next) {
        const dx = next.x - bolt.x
        const dz = next.z - bolt.z
        const l = hypot(dx, dz) || 1
        const spd = hypot(bolt.vx, bolt.vz) || this.weapon.speed
        bolt.vx = (dx / l) * spd
        bolt.vz = (dz / l) * spd
        bolt.ricUsed = ricUsed + 1
        bolt.x += bolt.vx * 0.02
        bolt.z += bolt.vz * 0.02
        return
      }
    }
    if (bolt.phase === 'out' && this.stats.pierce) {
      bolt.pierced = pierced + 1
      return
    }
    if (bolt.phase === 'out') bolt.phase = 'back'
  }

  nearestEnemy(x, z, maxDist, ignoreId = -1) {
    let best = null
    let bestD = maxDist
    for (const e of this.enemies) {
      if (e.dead || e.id === ignoreId) continue
      const d = hypot(e.x - x, e.z - z)
      if (d < bestD) {
        bestD = d
        best = e
      }
    }
    return best
  }

  hurtEnemy(enemy, scale, opts = {}) {
    if (!enemy || enemy.dead || this.over || this.won) return
    let amount = this.stats.hitAtk * scale
    if (this.stats.rage) amount *= 1 + (1 - this.player.hp / this.player.hpMax)
    let crit = false
    if (opts.crit && this.rng() < this.stats.crit) {
      crit = true
      amount *= this.stats.critDmg
    }
    if (opts.head && this.stats.headshot && enemy.type !== 'boss' && this.rng() < this.stats.headshot) {
      this.events.push({ t: 'num', x: enemy.x, z: enemy.z, text: '斩', crit: true })
      enemy.hp = 0
    } else {
      amount = Math.max(1, Math.round(amount))
      enemy.hp -= amount
      if (opts.num !== false) {
        this.events.push({ t: 'num', x: enemy.x, z: enemy.z, text: String(amount), crit })
      }
    }
    enemy.hitFlash = 0.1
    if (opts.knock) {
      const kl = hypot(opts.dirX || 0, opts.dirZ || 0) || 1
      enemy.vx += ((opts.dirX || 0) / kl) * opts.knock
      enemy.vz += ((opts.dirZ || 0) / kl) * opts.knock
    }
    const wasFrozen = enemy.frozen > 0
    if (wasFrozen) enemy.frozen = 0
    else if (opts.proc) this.applyElement(enemy)
    if (opts.trauma) this.events.push({ t: 'impact', power: opts.trauma })
    if (enemy.hp <= 0) this.kill(enemy)
  }

  applyElement(enemy) {
    const elite = enemy.type === 'boss' ? 0.55 : 1
    const base = this.stats.hitAtk * elite
    if (this.stats.blaze) {
      enemy.burn = 2
      enemy.burnDmg = base * 0.18
      enemy.burnTick = 0.25
    }
    if (this.stats.poison && !enemy.poison) {
      enemy.poison = true
      enemy.poisonDmg = base * 0.35
      enemy.poisonTick = 1
    }
    if (this.stats.freeze && enemy.type !== 'boss') enemy.frozen = Math.max(enemy.frozen, 1.5)
    if (this.stats.boltEl) {
      for (const other of this.enemies) {
        if (other === enemy || other.dead) continue
        if (hypot(other.x - enemy.x, other.z - enemy.z) > 2.5) continue
        this.hurtEnemy(other, 0.25 * elite, { proc: false, head: false, crit: false, knock: 0.2, dirX: other.x - enemy.x, dirZ: other.z - enemy.z })
      }
    }
  }

  kill(enemy) {
    if (enemy.dead) return
    enemy.dead = true
    this.kills += 1
    if (this.stats.blood) {
      this.player.hp = Math.min(this.player.hpMax, this.player.hp + this.stats.blood * BASE.hp)
    }
    this.orbs.push({ x: enemy.x, z: enemy.z, v: enemy.xp, age: 0 })
    this.events.push({ t: 'kill', x: enemy.x, z: enemy.z, boss: enemy.type === 'boss' })
  }

  updateDots(dt) {
    for (const e of this.enemies) {
      if (e.dead) continue
      if (e.burn > 0) {
        e.burn -= dt
        e.burnTick -= dt
        if (e.burnTick <= 0) {
          e.burnTick += 0.25
          this.hurtEnemy(e, e.burnDmg / this.stats.hitAtk, { proc: false, head: false, crit: false, num: false })
        }
      }
      if (e.poison) {
        e.poisonTick -= dt
        if (e.poisonTick <= 0) {
          e.poisonTick += 1
          this.hurtEnemy(e, e.poisonDmg / this.stats.hitAtk, { proc: false, head: false, crit: false, num: false })
        }
      }
    }
  }

  updateEnemies(dt) {
    for (const e of this.enemies) {
      if (e.dead) continue
      e.hitFlash = Math.max(0, e.hitFlash - dt)
      e.touch = Math.max(0, e.touch - dt)
      e.vx *= Math.exp(-6 * dt)
      e.vz *= Math.exp(-6 * dt)
      this.tryMove(e, e.vx * dt, e.vz * dt)
      if (e.frozen > 0) {
        e.frozen -= dt
        continue
      }
      const aim = this.nearestFighter(e.x, e.z)
      if (aim) this.player = aim.player
      if (e.type === 'boss') this.updateBoss(e, dt)
      else if (e.type === 'archer') this.updateArcher(e, dt)
      else if (e.type === 'jumper') this.updateJumper(e, dt)
      else if (e.type === 'summoner') this.updateSummoner(e, dt)
      else this.updateChaser(e, dt)
      if (e.touch <= 0) {
        for (const fighter of this.living()) {
          if (hypot(e.x - fighter.player.x, e.z - fighter.player.z) < e.r + fighter.player.r) {
            e.touch = 0.7
            this.hurtFighter(fighter, e.touchDmg * this.scale.dmg, e.x, e.z)
            break
          }
        }
      }
    }
  }

  updateChaser(e, dt) {
    if (e.state === 'windup') {
      e.timer -= dt
      if (e.timer <= 0) {
        const dx = e.lockX - e.x
        const dz = e.lockZ - e.z
        const l = hypot(dx, dz) || 1
        e.dashX = (dx / l) * 10
        e.dashZ = (dz / l) * 10
        e.state = 'dash'
        e.timer = 0.26
      }
      return
    }
    if (e.state === 'dash') {
      e.timer -= dt
      this.tryMove(e, e.dashX * dt, e.dashZ * dt)
      if (e.timer <= 0) {
        e.state = 'move'
        e.gap = 1.25
      }
      return
    }
    this.steer(e, this.player.x, this.player.z, e.speed, dt)
    e.gap -= dt
    if (e.gap <= 0 && hypot(this.player.x - e.x, this.player.z - e.z) < 6.4) {
      e.state = 'windup'
      e.action = 'dash'
      e.timer = 0.4
      e.lockX = this.player.x
      e.lockZ = this.player.z
      e.tellR = 0.55
    }
  }

  updateArcher(e, dt) {
    if (e.state === 'windup') {
      e.timer -= dt
      if (e.timer <= 0) {
        this.spawnShot(e.x, e.z, e.lockX - e.x, e.lockZ - e.z, e.shotSpeed, e.shot * this.scale.dmg)
        e.state = 'move'
        e.gap = 1.35
      }
      return
    }
    const dx = this.player.x - e.x
    const dz = this.player.z - e.z
    const d = hypot(dx, dz) || 1
    const prefer = 6.3
    let mx = 0
    let mz = 0
    if (d > prefer + 0.45) {
      mx = dx / d
      mz = dz / d
    } else if (d < prefer - 0.7) {
      mx = -dx / d
      mz = -dz / d
    } else {
      mx = (-dz / d) * e.strafe
      mz = (dx / d) * e.strafe
    }
    this.tryMove(e, mx * e.speed * dt, mz * e.speed * dt)
    e.gap -= dt
    if (e.gap <= 0 && d < 13) {
      e.state = 'windup'
      e.action = 'aim'
      e.timer = 0.42
      e.lockX = this.player.x
      e.lockZ = this.player.z
      e.tellR = 0.42
    }
  }

  updateJumper(e, dt) {
    if (e.state === 'windup') {
      e.timer -= dt
      if (e.timer <= 0) {
        e.state = 'leap'
        e.leapT = 0
        e.lx0 = e.x
        e.lz0 = e.z
      }
      return
    }
    if (e.state === 'leap') {
      e.leapT += dt
      const u = Math.min(1, e.leapT / 0.28)
      e.x = e.lx0 + (e.lockX - e.lx0) * u
      e.z = e.lz0 + (e.lockZ - e.lz0) * u
      this.resolve(e)
      if (u >= 1) {
        this.spawnPlus(e.x, e.z, e.shotSpeed, e.shot * this.scale.dmg)
        e.state = 'move'
        e.gap = 1.7
      }
      return
    }
    this.steer(e, this.player.x, this.player.z, e.speed, dt)
    e.gap -= dt
    if (e.gap <= 0) {
      e.state = 'windup'
      e.action = 'leap'
      e.timer = 0.48
      const ang = this.rng() * Math.PI * 2
      e.lockX = clamp(this.player.x + Math.cos(ang) * 0.4, -this.room.halfW + 1, this.room.halfW - 1)
      e.lockZ = clamp(this.player.z + Math.sin(ang) * 0.4, -this.room.halfH + 1, this.room.halfH - 1)
      e.tellR = 0.7
    }
  }

  updateSummoner(e, dt) {
    if (e.state === 'windup') {
      e.timer -= dt
      if (e.timer <= 0) {
        if (e.action === 'ring') this.spawnRing(e.x, e.z, 8, e.shotSpeed, e.shot * this.scale.dmg, e.rot)
        if (e.action === 'summon' && this.enemies.filter((x) => !x.dead).length < 9) {
          const ang = this.rng() * Math.PI * 2
          this.spawnEnemy('chaser', e.x + Math.cos(ang) * 1.4, e.z + Math.sin(ang) * 1.4, true)
        }
        e.state = 'move'
        e.gap = e.action === 'summon' ? 4.6 : 2.5
      }
      return
    }
    const dx = this.player.x - e.x
    const dz = this.player.z - e.z
    const d = hypot(dx, dz) || 1
    const dir = d < 6.5 ? -1 : 1
    this.tryMove(e, (dx / d) * dir * e.speed * dt, (dz / d) * dir * e.speed * dt)
    e.gap -= dt
    e.step -= dt
    if (e.step <= 0) {
      e.step = 5.2
      e.state = 'windup'
      e.action = 'summon'
      e.timer = 0.45
      e.lockX = e.x
      e.lockZ = e.z
      e.tellR = 1
      return
    }
    if (e.gap <= 0) {
      e.state = 'windup'
      e.action = 'ring'
      e.timer = 0.5
      e.rot += 0.4
      e.lockX = e.x
      e.lockZ = e.z
      e.tellR = 1.2
    }
  }

  updateBoss(e, dt) {
    const phase2 = e.hp < e.hpMax * 0.5
    if (e.state === 'windup') {
      e.timer -= dt
      if (e.timer <= 0) {
        this.execBoss(e, phase2)
        if (e.state === 'windup') e.state = 'move'
      }
      return
    }
    if (e.state === 'dash') {
      e.timer -= dt
      this.tryMove(e, e.dashX * dt, e.dashZ * dt)
      if (e.timer <= 0) {
        e.state = 'move'
        e.gap = phase2 ? 0.7 : 0.95
      }
      return
    }
    const dx = this.player.x - e.x
    const dz = this.player.z - e.z
    const d = hypot(dx, dz) || 1
    if (d > 2.4) this.tryMove(e, (dx / d) * e.speed * dt, (dz / d) * e.speed * dt)
    e.gap -= dt
    if (e.gap > 0) return
    const pattern = e.step % (phase2 ? 4 : 5)
    e.step += 1
    e.lockX = this.player.x
    e.lockZ = this.player.z
    if (pattern === 0) {
      e.state = 'windup'
      e.action = 'radial'
      e.timer = 0.62
      e.tellR = 1.3
      e.radialN = phase2 ? 14 : 9
    } else if (pattern === 1) {
      e.state = 'windup'
      e.action = 'fan'
      e.timer = 0.4
      e.tellR = 0.5
    } else if (pattern === 2) {
      e.state = 'windup'
      e.action = 'slam'
      e.timer = 0.68
      e.tellR = 1.8
    } else if (pattern === 3) {
      e.state = 'windup'
      e.action = 'dash'
      e.timer = 0.42
      e.tellR = 0.9
    } else {
      e.state = 'windup'
      e.action = 'radial'
      e.timer = 0.5
      e.tellR = 1.1
      e.radialN = phase2 ? 12 : 8
    }
  }

  execBoss(e, phase2) {
    const dmg = e.shot * this.scale.dmg * (phase2 ? 1.08 : 1)
    if (e.action === 'radial') {
      e.rot += 0.35
      this.spawnRing(e.x, e.z, e.radialN || 9, e.shotSpeed, dmg, e.rot)
      e.state = 'move'
      e.gap = phase2 ? 0.85 : 1.15
    } else if (e.action === 'fan') {
      const dx = e.lockX - e.x
      const dz = e.lockZ - e.z
      const base = Math.atan2(dx, dz)
      for (let i = -2; i <= 2; i++) {
        const a = base + i * 0.18
        this.spawnShot(e.x, e.z, Math.sin(a), Math.cos(a), e.shotSpeed, dmg)
      }
      e.state = 'move'
      e.gap = phase2 ? 0.75 : 1
    } else if (e.action === 'slam') {
      this.hazards.push({
        kind: 'slam',
        x: e.lockX,
        z: e.lockZ,
        t: 0,
        delay: 0.02,
        r: 1.8,
        dmg,
        hit: false,
      })
      this.spawnRing(e.lockX, e.lockZ, 8, e.shotSpeed * 0.85, dmg * 0.7, e.rot)
      e.state = 'move'
      e.gap = phase2 ? 0.8 : 1.05
    } else if (e.action === 'dash') {
      const dx = e.lockX - e.x
      const dz = e.lockZ - e.z
      const l = hypot(dx, dz) || 1
      e.dashX = (dx / l) * (phase2 ? 9 : 7.5)
      e.dashZ = (dz / l) * (phase2 ? 9 : 7.5)
      e.state = 'dash'
      e.timer = 0.34
    }
  }

  steer(e, x, z, speed, dt) {
    const dx = x - e.x
    const dz = z - e.z
    const l = hypot(dx, dz) || 1
    this.tryMove(e, (dx / l) * speed * dt, (dz / l) * speed * dt)
  }

  tryMove(body, dx, dz) {
    body.x += dx
    this.resolve(body)
    body.z += dz
    this.resolve(body)
  }

  resolve(body) {
    const hw = this.room.halfW - body.r
    const hh = this.room.halfH - body.r
    body.x = clamp(body.x, -hw, hw)
    body.z = clamp(body.z, -hh, hh)
    for (const o of this.room.obstacles) {
      let dx = body.x - o.x
      let dz = body.z - o.z
      let d = hypot(dx, dz)
      const min = body.r + o.r
      if (d < min) {
        if (d < 1e-4) {
          dx = min
          dz = 0
          d = min
        }
        const p = (min - d) / d
        body.x += dx * p
        body.z += dz * p
      }
    }
  }

  separate() {
    const list = this.enemies
    for (let i = 0; i < list.length; i++) {
      for (let j = i + 1; j < list.length; j++) {
        const a = list[i]
        const b = list[j]
        if (a.dead || b.dead) continue
        const dx = b.x - a.x
        const dz = b.z - a.z
        const d = hypot(dx, dz)
        const min = a.r + b.r
        if (d < min && d > 0.001) {
          const p = ((min - d) / d) * 0.5
          a.x -= dx * p
          a.z -= dz * p
          b.x += dx * p
          b.z += dz * p
        }
      }
    }
    for (const e of list) if (!e.dead) this.resolve(e)
  }

  separateFighters() {
    const list = this.living()
    for (let i = 0; i < list.length; i++) {
      for (let j = i + 1; j < list.length; j++) {
        const a = list[i].player
        const b = list[j].player
        const dx = b.x - a.x
        const dz = b.z - a.z
        const d = hypot(dx, dz)
        const min = a.r + b.r + 0.2
        if (d < min && d > 0.001) {
          const p = ((min - d) / d) * 0.5
          a.x -= dx * p
          a.z -= dz * p
          b.x += dx * p
          b.z += dz * p
          this.resolve(a)
          this.resolve(b)
        }
      }
    }
  }

  spawnShot(x, z, dx, dz, speed, dmg) {
    const l = hypot(dx, dz) || 1
    this.shots.push({
      x,
      z,
      vx: (dx / l) * speed,
      vz: (dz / l) * speed,
      r: 0.22,
      dmg,
      life: 4,
      dead: false,
    })
  }

  spawnRing(x, z, n, speed, dmg, rot) {
    for (let i = 0; i < n; i++) {
      const a = rot + (i / n) * Math.PI * 2
      this.spawnShot(x, z, Math.cos(a), Math.sin(a), speed, dmg)
    }
  }

  spawnPlus(x, z, speed, dmg) {
    this.spawnShot(x, z, 1, 0, speed, dmg)
    this.spawnShot(x, z, -1, 0, speed, dmg)
    this.spawnShot(x, z, 0, 1, speed, dmg)
    this.spawnShot(x, z, 0, -1, speed, dmg)
  }

  partySlow() {
    let slow = 1
    for (const fighter of this.living()) slow = Math.min(slow, fighter.stats.slow)
    return slow
  }

  updateShots(dt) {
    const slow = this.partySlow()
    for (const s of this.shots) {
      if (s.dead) continue
      s.life -= dt
      s.x += s.vx * slow * dt
      s.z += s.vz * slow * dt
      if (s.life <= 0) {
        s.dead = true
        continue
      }
      const hw = this.room.halfW - 0.2
      const hh = this.room.halfH - 0.2
      if (Math.abs(s.x) > hw || Math.abs(s.z) > hh) {
        s.dead = true
        continue
      }
      for (const o of this.room.obstacles) {
        if (hypot(s.x - o.x, s.z - o.z) < o.r + s.r) {
          s.dead = true
          break
        }
      }
      if (s.dead) continue
      for (const fighter of this.living()) {
        for (const guard of fighter.guards) {
          if (hypot(s.x - guard.x, s.z - guard.z) < guard.r + s.r) {
            s.dead = true
            this.events.push({ t: 'block', x: s.x, z: s.z })
            break
          }
        }
        if (s.dead) break
        if (fighter.wing && hypot(s.x - fighter.wing.x, s.z - fighter.wing.z) < fighter.wing.r + s.r) {
          s.dead = true
          this.events.push({ t: 'block', x: s.x, z: s.z })
          break
        }
      }
      if (s.dead) continue
      for (const fighter of this.living()) {
        if (hypot(s.x - fighter.player.x, s.z - fighter.player.z) < s.r + fighter.player.r) {
          s.dead = true
          this.hurtFighter(fighter, s.dmg, s.x, s.z)
          break
        }
      }
    }
  }

  updateHazards(dt) {
    for (const h of this.hazards) {
      h.t += dt
      if (h.hit || h.t < h.delay) continue
      h.hit = true
      if (h.kind === 'rain') {
        for (const e of this.enemies) {
          if (e.dead) continue
          if (hypot(e.x - h.x, e.z - h.z) <= h.r + e.r) {
            this.hurtEnemy(e, 2, { proc: true, head: true, crit: true, knock: 0.8, dirX: e.x - h.x, dirZ: e.z - h.z })
          }
        }
        this.events.push({ t: 'impact', power: 0.18, x: h.x, z: h.z })
      } else if (h.kind === 'slam') {
        for (const fighter of this.living()) {
          if (hypot(fighter.player.x - h.x, fighter.player.z - h.z) < h.r + fighter.player.r) {
            this.hurtFighter(fighter, h.dmg, h.x, h.z)
          }
        }
        this.events.push({ t: 'impact', power: 0.28, x: h.x, z: h.z })
      }
    }
  }

  updateOrbs(dt) {
    for (let i = this.orbs.length - 1; i >= 0; i--) {
      const o = this.orbs[i]
      o.age += dt
      const magnet = this.nearestFighter(o.x, o.z)?.player || this.player
      const dx = magnet.x - o.x
      const dz = magnet.z - o.z
      const d = hypot(dx, dz)
      if (o.age > 0.3) {
        const sp = 15
        o.x += (dx / (d || 1)) * sp * dt
        o.z += (dz / (d || 1)) * sp * dt
      }
      if (d < magnet.r + 0.45) {
        this.xp += o.v
        this.orbs.splice(i, 1)
        this.events.push({ t: 'orb' })
      }
    }
  }

  checkLevel() {
    if (!this.pendingLevel && this.xp >= this.xpNeed() && !this.over && !this.won) {
      this.pendingLevel = true
      this.rollOffers('level')
      this.events.push({ t: 'level', offers: this.offers })
    }
  }

  checkClear() {
    if (this.over || this.cleared || this.room.kind === 'angel') return
    if (this.enemies.some((e) => !e.dead)) return
    this.cleared = true
    if (this.room.index === 10) {
      this.won = true
      this.events.push({ t: 'win' })
      return
    }
    this.door = true
    if (this.room.kind === 'chest') {
      for (const fighter of this.living()) {
        fighter.player.hp = Math.min(fighter.player.hpMax, fighter.player.hp + fighter.player.hpMax * 0.3)
      }
      this.xp += 8
      this.events.push({ t: 'chest' })
    }
    this.events.push({ t: 'clear', perfect: !this.tookDamage })
  }

  checkDoor() {
    if (!this.door || this.won) return
    const reached = this.living().some((fighter) => fighter.player.z < -this.room.halfH + 1.65 && Math.abs(fighter.player.x) < 1.45)
    if (reached) {
      this.door = false
      this.events.push({ t: 'door', perfect: !this.tookDamage })
    }
  }

  bankOrbs() {
    for (const o of this.orbs) this.xp += o.v
    this.orbs = []
    if (!this.pendingLevel && this.xp >= this.xpNeed() && !this.over && !this.won) this.pendingLevel = true
  }

  hurtPlayer(amount, srcX, srcZ) {
    if (this.over || this.won) return
    if (this.player.iframe > 0) return
    if (this.guardActive()) {
      this.events.push({ t: 'guard', x: this.player.x, z: this.player.z })
      this.player.iframe = 0.12
      return
    }
    amount = Math.max(1, Math.round(amount))
    this.player.hp -= amount
    this.tookDamage = true
    this.player.iframe = 0.64
    this.player.hitFlash = 0.16
    const dx = this.player.x - srcX
    const dz = this.player.z - srcZ
    const l = hypot(dx, dz) || 1
    this.player.x += (dx / l) * 0.4
    this.player.z += (dz / l) * 0.4
    if (this.room) this.resolve(this.player)
    this.focus = 0
    this.queue.length = 0
    this.events.push({ t: 'hurt', amount, x: this.player.x, z: this.player.z })
    if (this.player.hp <= 0) {
      if (this.counts.extralife && !this.usedLife) {
        this.usedLife = true
        this.player.hp = this.player.hpMax
        this.player.iframe = 1.6
        this.events.push({ t: 'revive' })
      } else {
        this.player.hp = 0
        this.events.push({ t: 'down', id: this.active?.id })
        if (!this.living().length) {
          this.over = true
          this.events.push({ t: 'dead' })
        }
      }
    }
  }

  present() {
    const me = this.localFighter()
    const players = this.fighters.map((fighter) => ({
      id: fighter.id,
      name: fighter.name,
      color: fighter.color,
      x: round(fighter.player.x),
      z: round(fighter.player.z),
      r: fighter.player.r,
      fx: round(fighter.player.facingX || 0),
      fz: round(fighter.player.facingZ || -1),
      hp: fighter.player.hp,
      hpMax: fighter.player.hpMax,
      flash: fighter.player.hitFlash,
      focus: fighter.focus,
      windup: fighter.weapon.windup,
      moving: fighter.moving,
      focused: fighter.focused,
      alive: fighter.player.hp > 0,
      guards: fighter.guards,
      wing: fighter.wing,
      weaponColor: fighter.weapon.color,
      guard: !!(fighter.stats.star && fighter.starClock % 10 < 2),
    }))
    const bolts = []
    for (const fighter of this.fighters) {
      for (const bolt of fighter.bolts) {
        if (bolt.dead) continue
        bolts.push({
          x: round(bolt.x),
          z: round(bolt.z),
          vx: round(bolt.vx),
          vz: round(bolt.vz),
          phase: bolt.phase,
          homing: bolt.homing,
          color: bolt.color || fighter.weapon.color,
          id: bolt.id,
        })
      }
    }
    return {
      room: this.room,
      door: this.door,
      players,
      bolts,
      enemies: this.enemies.filter((e) => !e.dead).map((e) => ({
        id: e.id,
        type: e.type,
        x: round(e.x),
        z: round(e.z),
        r: e.r,
        hp: e.hp,
        hpMax: e.hpMax,
        state: e.state,
        lockX: e.lockX,
        lockZ: e.lockZ,
        tellR: e.tellR,
        hitFlash: e.hitFlash,
        frozen: e.frozen,
      })),
      shots: this.shots.filter((s) => !s.dead).map((s) => ({ x: round(s.x), z: round(s.z), r: s.r })),
      orbs: this.orbs.map((o) => ({ x: round(o.x), z: round(o.z) })),
      hazards: this.hazards.map((h) => ({
        kind: h.kind, x: h.x, z: h.z, t: h.t, delay: h.delay, r: h.r, hit: h.hit,
      })),
      target: me?.target && !me.target.dead
        ? { x: me.target.x, z: me.target.z, r: me.target.r }
        : null,
      hud: {
        level: this.level,
        xp: this.xp,
        need: this.xpNeed(),
        counts: me?.counts || {},
        weapon: me?.weapon?.name || '',
        stance: me?.moving ? '游身' : me?.focused ? '凝神' : '聚剑',
        moving: !!me?.moving,
        focused: !!me?.focused,
        guard: players.find((p) => p.id === this.localId)?.guard,
        hp: me?.player.hp ?? 0,
        hpMax: me?.player.hpMax ?? 1,
        room: this.room,
        party: players.map((p) => ({
          id: p.id, name: p.name, color: p.color, hp: p.hp, hpMax: p.hpMax, alive: p.alive,
        })),
      },
    }
  }
}
