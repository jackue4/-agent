import { SKILLS, WEAPONS } from './content.js'

export class UI {
  constructor() {
    this.title = document.querySelector('#title')
    this.modal = document.querySelector('#modal')
    this.pause = document.querySelector('#pause')
    this.result = document.querySelector('#result')
    this.hud = document.querySelector('#hud')
    this.floats = document.querySelector('#floats')
    this.toasts = document.querySelector('#toasts')
    this.stick = document.querySelector('#stick')
    this.weaponId = 'qingfeng'
    this.onStart = null
    this.onPick = null
    this.onResume = null
    this.onRetry = null
    this.onTitle = null
    this.onMute = null
    this.buildTitle()
    document.querySelector('#resume').addEventListener('click', () => this.onResume?.())
    document.querySelector('#retry').addEventListener('click', () => this.onRetry?.())
    document.querySelector('#back-title').addEventListener('click', () => this.onTitle?.())
    document.querySelector('#pause-title').addEventListener('click', () => this.onTitle?.())
    document.querySelector('#mute').addEventListener('click', () => this.onMute?.())
  }

  buildTitle() {
    const host = document.querySelector('#weapons')
    host.innerHTML = ''
    for (const weapon of Object.values(WEAPONS)) {
      const btn = document.createElement('button')
      btn.type = 'button'
      btn.className = 'weapon'
      btn.dataset.id = weapon.id
      btn.innerHTML = `<strong>${weapon.name}</strong><span>${weapon.blurb}</span>`
      btn.addEventListener('click', () => {
        this.weaponId = weapon.id
        this.markWeapon()
        this.onWeapon?.(weapon.id)
      })
      host.append(btn)
    }
    this.markWeapon()
    document.querySelector('#start').addEventListener('click', () => this.onStart?.(this.weaponId))
    document.querySelector('#host-room')?.addEventListener('click', () => this.onHost?.())
    document.querySelector('#launch')?.addEventListener('click', () => this.onLaunch?.())
    document.querySelector('#join-room')?.addEventListener('click', () => this.joinByCode())
    document.querySelector('#join-code')?.addEventListener('keydown', (event) => {
      if (event.key === 'Enter') this.joinByCode()
    })
    document.querySelector('#copy-link')?.addEventListener('click', () => this.copyLink())
  }

  joinByCode() {
    const code = (document.querySelector('#join-code').value || '').trim().toUpperCase()
    if (code.length < 4) {
      this.toast('房间号是 4 位')
      return
    }
    this.onJoin?.(code)
  }

  async copyLink() {
    const input = document.querySelector('#room-link')
    const text = input.value || input.textContent || ''
    const state = document.querySelector('#copy-state')
    input.focus()
    input.select()
    let ok = false
    try {
      if (navigator.clipboard && window.isSecureContext) {
        await navigator.clipboard.writeText(text)
        ok = true
      }
    } catch {
      ok = false
    }
    if (!ok) {
      const area = document.createElement('textarea')
      area.value = text
      area.setAttribute('readonly', '')
      area.style.position = 'fixed'
      area.style.left = '-9999px'
      document.body.append(area)
      area.select()
      try { ok = document.execCommand('copy') } catch { ok = false }
      area.remove()
    }
    if (state) state.textContent = ok ? '已复制。发给同一 Wi-Fi 里的朋友。' : '这个网页不能自动复制，请选中上面的链接手动复制。'
    this.toast(ok ? '链接已复制' : '请手动选中链接复制')
  }

  markWeapon() {
    for (const btn of document.querySelectorAll('.weapon')) {
      btn.classList.toggle('on', btn.dataset.id === this.weaponId)
    }
  }

  showTitle(show) {
    this.title.hidden = !show
    if (show) {
      this.modal.hidden = true
      this.pause.hidden = true
      this.result.hidden = true
      this.hud.hidden = true
      document.querySelector('#lobby').hidden = true
    }
  }

  showHud(show) {
    this.hud.hidden = !show
  }

  showModal({ kicker, title, sub, cards }) {
    this.modal.hidden = false
    this.pause.hidden = true
    this.result.hidden = true
    this.title.hidden = true
    this.modal.querySelector('.kicker').textContent = kicker
    this.modal.querySelector('h2').textContent = title
    this.modal.querySelector('.sub').textContent = sub
    const host = this.modal.querySelector('.cards')
    host.innerHTML = ''
    cards.forEach((card, i) => {
      const btn = document.createElement('button')
      btn.type = 'button'
      btn.className = 'card'
      const kind = card.kind || 'sword'
      btn.innerHTML = `<em>${i + 1}</em><strong>${card.name}</strong><span>${card.desc}</span><small>${kindLabel(kind)}</small>`
      btn.addEventListener('click', () => this.onPick?.(card.id))
      host.append(btn)
    })
  }

  hideModal() {
    this.modal.hidden = true
  }

  showPause(show) {
    this.pause.hidden = !show
  }

  showResult({ win, title, lines }) {
    this.result.hidden = false
    this.modal.hidden = true
    this.pause.hidden = true
    this.result.querySelector('.kicker').textContent = win ? '破冢' : '剑折'
    this.result.querySelector('h2').textContent = title
    this.result.querySelector('.sub').textContent = lines.join('\n')
  }

  syncHud(sim) {
    const hud = sim.hud
    const room = hud?.room || sim.room
    document.querySelector('#room-label').textContent = room
      ? `第 ${room.index} / 10 房 · ${room.name}`
      : '飞剑传说'
    const hp = hud ? hud.hp : sim.player.hp
    const hpMax = hud ? hud.hpMax : sim.player.hpMax
    document.querySelector('#hp-fill').style.width = `${Math.max(0, hp / hpMax) * 100}%`
    document.querySelector('#hp-text').textContent = `${Math.ceil(hp)} / ${Math.ceil(hpMax)}`
    const need = hud ? hud.need : sim.xpNeed()
    const xp = hud ? hud.xp : sim.xp
    document.querySelector('#xp-fill').style.width = `${Math.max(0, Math.min(1, xp / need)) * 100}%`
    const stance = document.querySelector('#stance')
    const label = hud ? hud.stance : sim.stance()
    const guard = hud ? hud.guard : sim.guardActive()
    const weapon = hud ? hud.weapon : sim.weapon.name
    stance.textContent = guard ? `${label} · 护体` : `${label} · ${weapon}`
    const moving = hud ? hud.moving : sim.moving
    const focused = hud ? hud.focused : sim.focused
    stance.dataset.mode = moving ? 'move' : focused ? 'focus' : 'charge'
    const counts = hud ? hud.counts : sim.counts
    const pills = document.querySelector('#skills')
    const parts = []
    for (const [id, n] of Object.entries(counts || {})) {
      if (!n || id === 'pacts') continue
      const skill = SKILLS[id]
      if (!skill) continue
      parts.push(`<i>${skill.name}${n > 1 ? ` ${n}` : ''}</i>`)
    }
    pills.innerHTML = parts.join('')
    const party = hud?.party || (sim.fighters || []).map((fighter) => ({
      id: fighter.id,
      name: fighter.name,
      color: fighter.color,
      hp: fighter.player.hp,
      hpMax: fighter.player.hpMax,
      alive: fighter.player.hp > 0,
    }))
    this.renderParty(party)
  }

  renderParty(party) {
    const host = document.querySelector('#party')
    if (!host) return
    if (!party || party.length < 2) {
      host.innerHTML = ''
      return
    }
    host.innerHTML = party.map((player) => {
      const pct = Math.max(0, Math.min(1, player.hp / player.hpMax))
      return `<div class="mate${player.alive ? '' : ' down'}"><b style="color:#${player.color.toString(16).padStart(6, '0')}">${player.name}</b><i style="width:${pct * 100}%"></i></div>`
    }).join('')
  }

  showLobby(link) {
    const lobby = document.querySelector('#lobby')
    if (!link) {
      lobby.hidden = true
      return
    }
    lobby.hidden = false
    const field = document.querySelector('#room-link')
    field.value = link
    const code = (String(link).match(/room=([A-Z0-9]+)/i) || [])[1] || ''
    document.querySelector('#room-code').textContent = code
    document.querySelector('#copy-state').textContent = ''
    this.title.hidden = true
    const box = document.querySelector('#lobby-weapons')
    if (box && !box.childElementCount) {
      for (const weapon of Object.values(WEAPONS)) {
        const btn = document.createElement('button')
        btn.type = 'button'
        btn.className = 'weapon'
        btn.dataset.id = weapon.id
        btn.innerHTML = `<strong>${weapon.name}</strong>`
        btn.addEventListener('click', () => {
          this.weaponId = weapon.id
          this.markWeapon()
          this.onWeapon?.(weapon.id)
        })
        box.append(btn)
      }
    }
    this.markWeapon()
  }

  renderLobby(members, hosting) {
    const list = document.querySelector('#lobby-members')
    list.innerHTML = members.map((member) => `<li>${member.host ? '房主 · ' : ''}${member.name}</li>`).join('')
    document.querySelector('#launch').hidden = !hosting
    const note = document.querySelector('#lobby-note')
    note.textContent = hosting ? '朋友打开下面的链接就能进来。人都到齐后一起出发。' : '等房主出发。先选好自己的剑。'
  }

  toast(text) {
    const el = document.createElement('div')
    el.className = 'toast'
    el.textContent = text
    this.toasts.append(el)
    setTimeout(() => el.remove(), 2200)
  }

  float(px, py, text, crit) {
    const el = document.createElement('span')
    el.className = crit ? 'float crit' : 'float'
    el.textContent = text
    el.style.left = `${px}px`
    el.style.top = `${py}px`
    this.floats.append(el)
    setTimeout(() => el.remove(), 700)
  }

  setStick(pointer) {
    if (!pointer) {
      this.stick.hidden = true
      return
    }
    this.stick.hidden = false
    this.stick.style.left = `${pointer.cx}px`
    this.stick.style.top = `${pointer.cy}px`
    const knob = this.stick.querySelector('i')
    const dx = Math.max(-36, Math.min(36, pointer.x - pointer.cx))
    const dy = Math.max(-36, Math.min(36, pointer.y - pointer.cy))
    knob.style.transform = `translate(${dx}px, ${dy}px)`
  }

  setMuteLabel(muted) {
    document.querySelector('#mute').textContent = muted ? '声音关' : '声音开'
  }
}

function kindLabel(kind) {
  return {
    sword: '剑阵',
    element: '剑意',
    defense: '护体',
    stat: '根基',
    devil: '魔契',
    minor: '仙缘',
    heal: '回复',
    no: '离开',
  }[kind] || '剑招'
}
