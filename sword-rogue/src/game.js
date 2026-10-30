import * as THREE from 'three'
import { SKILLS } from './content.js'
import { RunSim } from './sim.js'
import { PartyClient } from './net.js'

export class Game {
  constructor({ renderer, camera, view, ui, input, audio }) {
    this.renderer = renderer
    this.camera = camera
    this.view = view
    this.ui = ui
    this.input = input
    this.audio = audio
    this.mode = 'title'
    this.sim = null
    this.weaponId = 'qingfeng'
    this.look = new THREE.Vector3()
    this.trauma = 0
    this.hitstop = 0
    this.shakeT = 0
    this.after = null
    this.cards = []
    this.modalKind = ''
    this.role = 'solo'
    this.inputs = {}
    this.world = null
    this.snapAcc = 0
    this.net = new PartyClient(this)
    this.ui.onStart = (id) => this.start(id)
    this.ui.onPick = (id) => this.pick(id)
    this.ui.onResume = () => {
      this.mode = 'play'
      this.ui.showPause(false)
    }
    this.ui.onRetry = () => this.start(this.weaponId)
    this.ui.onTitle = () => this.toTitle()
    this.ui.onMute = () => {
      this.audio.ensure()
      this.ui.setMuteLabel(this.audio.toggle())
    }
    this.ui.onHost = () => this.hostRoom()
    this.ui.onWeapon = (id) => {
      this.weaponId = id
      if (this.net.ws) this.net.send({ t: 'weapon', weapon: id })
    }
    this.ui.onLaunch = () => this.net.send({ t: 'go' })
    this.ui.onJoin = (code) => this.joinRoom(code)
    this.ui.setMuteLabel(this.audio.muted)
    this.view.setRoom(emptyRoom())
    this.ui.showTitle(true)
    const room = new URLSearchParams(location.search).get('room')
    if (room) this.joinRoom(room.toUpperCase())
  }

  toTitle() {
    this.mode = 'title'
    this.sim = null
    this.after = null
    this.view.setRoom(emptyRoom())
    this.ui.showTitle(true)
  }

  start(weaponId) {
    this.audio.ensure()
    this.weaponId = weaponId
    const seed = (Math.random() * 1e9) >>> 0
    this.sim = new RunSim(seed)
    this.sim.setWeapon(weaponId)
    this.view.setWeapon(this.sim.weapon)
    this.view.setRoom(emptyRoom())
    const cards = this.sim.offer(3)
    this.modalKind = 'open'
    this.cards = cards
    this.mode = 'modal'
    this.ui.showHud(false)
    this.ui.showTitle(false)
    this.ui.showModal({
      kicker: '起手',
      title: '选一式剑招',
      sub: '站住才全力出剑。移动时剑绕身，能刮到身边的敌人，也能挡住弹幕。',
      cards,
    })
  }

  beginRoom(index) {
    this.sim.enter(index)
    this.sim.events.length = 0
    this.view.setRoom(this.sim.room)
    this.ui.hideModal()
    this.ui.showPause(false)
    this.ui.showHud(true)
    this.mode = 'play'
    const room = this.sim.room
    this.ui.toast(`第 ${room.index} 房 · ${room.name}`)
    if (index === 1) this.ui.toast('松开移动键，飞剑会自己出去')
    if (room.kind === 'angel') this.openAngel()
  }

  frame(dt) {
    this.shakeT += dt
    const presses = this.input.consume()
    this.handleKeys(presses)
    let simDt = dt
    if (this.hitstop > 0) {
      this.hitstop = Math.max(0, this.hitstop - dt)
      simDt = 0
    }
    if (this.mode === 'play' && this.sim && this.role !== 'guest') {
      const input = this.role === 'host'
        ? { ...this.inputs, [this.net.id]: this.input.snapshot() }
        : this.input.snapshot()
      this.sim.update(simDt, input)
      this.consume(this.sim.events)
      if (this.role === 'host') this.flushSnap(dt)
    } else if (this.role === 'guest' && this.mode === 'play') {
      const move = this.input.snapshot()
      this.net.send({ t: 'input', ...move })
    }
    this.trauma = Math.max(0, this.trauma - dt * 1.7)
    this.updateCamera(dt)
    if (this.role === 'guest' && this.world) this.view.sync(this.world, dt)
    else if (this.sim?.room) this.view.sync(this.sim.present(), dt)
    else this.view.sync(null, dt)
    if (this.role === 'guest' && this.world?.hud && this.mode !== 'title') this.ui.syncHud(this.world)
    else if (this.sim && this.mode !== 'title') this.ui.syncHud(this.sim)
    this.ui.setStick(this.mode === 'play' ? this.input.pointer : null)
  }

  handleKeys(presses) {
    if (presses.has('escape')) {
      if (this.mode === 'play') {
        this.mode = 'pause'
        this.ui.showPause(true)
      } else if (this.mode === 'pause') {
        this.mode = 'play'
        this.ui.showPause(false)
      }
    }
    if (this.mode !== 'modal') return
    const order = ['1', '2', '3']
    for (let i = 0; i < order.length; i++) {
      if (presses.has(order[i]) && this.cards[i]) this.pick(this.cards[i].id)
    }
  }

  pick(id) {
    this.audio.pick()
    if (this.modalKind === 'open') {
      this.sim.grant(id)
      this.beginRoom(1)
      return
    }
    if (this.modalKind === 'level') {
      if (this.role === 'guest') {
        this.net.send({ t: 'pick', kind: 'level', skill: id })
        this.waitPeers()
        return
      }
      this.sim.pickSkill(id)
      if (this.sim.pendingLevel) this.waitPeers()
      else this.afterLevel()
      return
    }
    if (this.modalKind === 'angel') {
      if (this.role === 'guest') {
        this.net.send({ t: 'pick', kind: 'angel', skill: id })
        this.waitPeers()
        return
      }
      this.sim.chooseAngel(id)
      if (this.sim.door) {
        this.ui.hideModal()
        this.mode = 'play'
        this.ui.toast('走向北侧光门')
      } else this.waitPeers()
      return
    }
    if (this.modalKind === 'devil') {
      if (this.role === 'guest') {
        this.net.send({ t: 'pick', kind: 'devil', skill: id })
        this.waitPeers()
        return
      }
      const done = this.sim.chooseDevil(id)
      this.ui.hideModal()
      if (done) this.finishExit()
      else this.waitPeers()
    }
  }

  afterLevel() {
    if (this.sim.pendingLevel) {
      this.openLevel()
      return
    }
    if (this.after) {
      const next = this.after
      this.after = null
      next()
      return
    }
    this.ui.hideModal()
    this.mode = 'play'
  }

  openLevel() {
    if (!this.sim.offers?.[this.sim.localId]) this.sim.rollOffers('level')
    const cards = this.sim.offers[this.sim.localId] || []
    this.broadcastOffers('level')
    if (!cards.length) {
      this.sim.pickSkill(null)
      if (this.sim.pendingLevel) this.waitPeers()
      else this.afterLevel()
      return
    }
    this.cards = cards
    this.modalKind = 'level'
    this.mode = 'modal'
    this.ui.showModal({
      kicker: `剑意 ${this.sim.level}`,
      title: '三选一',
      sub: '这一局里的剑招会叠加。同伴各自选择，都选完才会继续。',
      cards,
    })
  }

  openAngel() {
    const cards = this.sim.offers?.[this.sim.localId]
    this.broadcastOffers('angel')
    if (!cards) return
    this.cards = cards
    this.modalKind = 'angel'
    this.mode = 'modal'
    this.ui.showModal({
      kicker: '仙缘',
      title: '仙人让你选',
      sub: '每个人各自选。血量健康时，永久的小增益通常比立刻回血更值。',
      cards,
    })
  }

  openDevil(skill) {
    this.cards = [skill, { id: 'no', name: '拒绝', desc: '不签契约。气血上限保持原样。', kind: 'no' }]
    this.modalKind = 'devil'
    this.mode = 'modal'
    this.ui.showModal({
      kicker: '魔契',
      title: '用两成气血上限换一式',
      sub: '残剑能在致死时满血站起一次。已经有残剑时，这里会换成别的强招。',
      cards: this.cards,
    })
  }

  onDoor(perfect) {
    this.sim.bankOrbs()
    const go = () => {
      if (this.sim.pendingLevel) {
        this.after = go
        this.openLevel()
        return
      }
      const offer = this.sim.living().length ? this.sim.rollOffers('devil') || this.sim.offers[this.sim.localId] : null
      const cards = this.sim.offers[this.sim.localId]
      const chance = perfect ? 0.55 : 0.08
      if (cards && this.sim.rng() < chance) {
        this.broadcastOffers('devil')
        this.cards = cards
        this.modalKind = 'devil'
        this.mode = 'modal'
        this.ui.showModal({
          kicker: '魔契',
          title: '用两成气血上限换一式',
          sub: '每个人自己决定签不签。残剑能在致死时满血站起一次。',
          cards,
        })
      } else this.finishExit()
      void offer
    }
    go()
  }

  finishExit() {
    if (!this.sim.room) return
    this.beginRoom(this.sim.room.index + 1)
  }

  consume(events) {
    let end = null
    for (const ev of events) {
      if (ev.t === 'fire') this.audio.fire()
      else if (ev.t === 'hurt') {
        this.audio.hurt()
        this.trauma = Math.min(1, this.trauma + 0.55)
        this.hitstop = 0.045
        this.view.burst(ev.x, ev.z, 0xff5530, 10)
      } else if (ev.t === 'kill') {
        this.view.burst(ev.x, ev.z, ev.boss ? 0xffe1a8 : 0xf2d48a, ev.boss ? 16 : 7)
        if (ev.boss) {
          this.trauma = Math.min(1, this.trauma + 0.45)
          this.hitstop = 0.04
        }
      } else if (ev.t === 'block') {
        this.audio.block()
        this.view.burst(ev.x, ev.z, 0x9fd8ff, 4)
      } else if (ev.t === 'impact') {
        this.trauma = Math.min(1, this.trauma + (ev.power || 0.1))
        if (ev.x != null) this.view.burst(ev.x, ev.z, 0xffe1a8, 8)
      } else if (ev.t === 'num') {
        const size = this.renderer.domElement
        const p = this.view.project(this.camera, ev.x, 1.5, ev.z, size.clientWidth, size.clientHeight)
        if (!p.behind) this.ui.float(p.x, p.y, ev.text, ev.crit)
      } else if (ev.t === 'level' && !this.sim.over && !this.sim.won) {
        this.openLevel()
      } else if (ev.t === 'clear') {
        this.ui.toast(ev.perfect ? '无伤过房' : '此房已清，走向光门')
      } else if (ev.t === 'chest') {
        this.ui.toast('遗箱：回复气血，并得到一截剑意')
      } else if (ev.t === 'revive') {
        this.ui.toast('残剑续命')
        this.audio.pick()
      } else if (ev.t === 'door') {
        this.onDoor(ev.perfect)
      } else if (ev.t === 'dead') end = 'dead'
      else if (ev.t === 'win') end = 'win'
    }
    if (end === 'win') this.showResult(true)
    else if (end === 'dead') this.showResult(false)
  }

  showResult(win) {
    this.mode = 'result'
    this.ui.hideModal()
    this.ui.showPause(false)
    if (win) this.audio.win()
    else this.audio.die()
    const sim = this.sim
    const names = Object.entries(sim.counts)
      .filter(([id, n]) => n && id !== 'pacts' && SKILLS[id])
      .map(([id, n]) => `${SKILLS[id].name}${n > 1 ? n : ''}`)
      .join('、') || '无'
    const sec = Math.round(sim.time)
    this.ui.showResult({
      win,
      title: win ? '守冢傀已倒' : `倒在第 ${sim.room?.index || 1} 房`,
      lines: [
        `${sim.weapon.name} · 击败 ${sim.kills} · ${sec} 秒`,
        `剑招：${names}`,
        `种子 ${sim.seed}。再走一章会换新的房间。`,
      ],
    })
  }

  hostRoom() {
    const alphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789'
    let code = ''
    for (let i = 0; i < 4; i++) code += alphabet[Math.floor(Math.random() * alphabet.length)]
    this.ui.showLobby('正在建立房间…')
    fetch('/api/link').then((res) => res.json()).then((info) => {
      const host = info.hosts?.[0] || location.hostname
      const link = `${location.protocol}//${host}:${location.port || info.port}/?room=${code}`
      this.ui.showLobby(link)
      this.net.connect(code)
    }).catch(() => {
      const link = `${location.origin}/?room=${code}`
      this.ui.showLobby(link)
      this.net.connect(code)
    })
  }

  joinRoom(code) {
    this.ui.showLobby(`${location.origin}/?room=${code}`)
    this.net.connect(code)
  }

  beginParty(msg) {
    this.role = 'host'
    this.audio.ensure()
    this.inputs = {}
    this.sim = new RunSim(msg.seed)
    this.sim.setWeapon(msg.members[0]?.weapon || 'qingfeng')
    this.sim.setupParty(msg.members, this.net.id)
    this.ui.showTitle(false)
    this.ui.showLobby('')
    this.weaponId = this.sim.weapon.id
    this.beginRoom(1)
  }

  beginGuest() {
    this.role = 'guest'
    this.sim = null
    this.ui.showTitle(false)
    this.ui.showLobby('')
    this.ui.showHud(true)
    this.mode = 'play'
    this.ui.toast('已连上，跟着房主入房')
  }

  waitPeers() {
    this.ui.hideModal()
    if (this.role === 'host') {
      this.mode = 'wait'
      this.ui.toast('等同伴选完')
    } else {
      this.mode = 'play'
      this.ui.toast('已选好，等同伴')
    }
  }

  broadcastOffers(kind) {
    if (this.role === 'host') this.net.send({ t: 'offers', kind, offers: this.sim.offers })
  }

  flushSnap(dt) {
    this.snapAcc += dt
    if (this.snapAcc < 0.05) return
    this.snapAcc = 0
    this.net.send({ t: 'snap', state: this.sim.present() })
  }

  onNet(msg) {
    if (msg.t === 'lobby') {
      this.net.id = msg.you
      this.net.hostId = msg.hostId
      this.net.members = msg.members
      this.ui.renderLobby(msg.members, msg.you === msg.hostId)
      return
    }
    if (msg.t === 'go') {
      if (msg.hostId === this.net.id) this.beginParty(msg)
      else this.beginGuest(msg)
      return
    }
    if (msg.t === 'input' && this.role === 'host') {
      this.inputs[msg.id] = { x: msg.x, z: msg.z, moving: msg.moving }
      return
    }
    if (msg.t === 'pick' && this.role === 'host') {
      this.onRemotePick(msg)
      return
    }
    if (msg.t === 'snap' && this.role === 'guest') {
      if (!this.world || this.world.room?.index !== msg.state.room?.index) this.view.setRoom(msg.state.room)
      this.world = msg.state
      return
    }
    if (msg.t === 'offers' && this.role === 'guest') {
      const cards = msg.offers?.[this.net.id] || []
      if (!cards.length) return
      this.cards = cards
      this.modalKind = msg.kind
      this.mode = 'modal'
      const titles = { level: '三选一', angel: '仙人让你选', devil: '魔契' }
      this.ui.showModal({
        kicker: msg.kind === 'devil' ? '魔契' : '剑招',
        title: titles[msg.kind] || '选择',
        sub: '选完后等其他同伴。',
        cards,
      })
      return
    }
    if (msg.t === 'leave' && this.role === 'host' && this.sim) {
      const fighter = this.sim.fighterById(msg.id)
      fighter.player.hp = 0
      fighter.picked = true
      fighter.chosen = true
      this.ui.toast(`${fighter.name} 离开了`)
      return
    }
    if (msg.t === 'error' || msg.t === 'bye') {
      this.ui.toast(msg.text || '连接断开了')
      if (msg.t === 'bye') this.toTitle()
    }
  }

  onRemotePick(msg) {
    if (msg.kind === 'level') this.sim.pickSkill(msg.skill, msg.id)
    if (msg.kind === 'angel') this.sim.chooseAngel(msg.skill, msg.id)
    if (msg.kind === 'devil') {
      const done = this.sim.chooseDevil(msg.skill, msg.id)
      if (done) {
        this.mode = 'play'
        this.finishExit()
        return
      }
    }
    if (msg.kind === 'angel' && this.sim.door && this.mode === 'wait') {
      this.mode = 'play'
      this.ui.toast('走向北侧光门')
    }
    if (msg.kind === 'level' && !this.sim.pendingLevel && this.mode === 'wait') {
      this.mode = 'play'
      this.afterLevel()
    }
  }

  updateCamera(dt) {
    const aspect = this.camera.aspect || 1
    let fov = 43
    let y = 34
    let z = 7.2
    let lookZ = 0.4
    if (aspect < 0.9) {
      fov = 62
      y = 34
      z = 9
      lookZ = 0
    } else if (aspect < 1.25) {
      fov = 46
      y = 32
      z = 8.4
      lookZ = 0.2
    }
    if (this.camera.fov !== fov) {
      this.camera.fov = fov
      this.camera.updateProjectionMatrix()
    }
    const shake = this.trauma * this.trauma
    const ox = Math.sin(this.shakeT * 73) * 0.28 * shake
    const oz = Math.cos(this.shakeT * 61) * 0.2 * shake
    this.camera.position.set(ox, y, z + oz)
    this.camera.lookAt(ox * 0.4, 0, lookZ)
  }
}

function emptyRoom() {
  return {
    index: 0,
    halfW: 8,
    halfH: 11,
    kind: 'combat',
    name: '',
    obstacles: [],
    waters: [],
    spikes: [],
    spawns: [],
  }
}
