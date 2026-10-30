export class Input {
  constructor(el) {
    this.el = el
    this.keys = new Set()
    this.just = new Set()
    this.pointer = null
    const down = (e) => {
      const k = e.key.toLowerCase()
      if (!e.repeat) this.just.add(k)
      this.keys.add(k)
      if (['arrowup', 'arrowdown', 'arrowleft', 'arrowright', ' '].includes(k)) e.preventDefault()
    }
    const up = (e) => this.keys.delete(e.key.toLowerCase())
    window.addEventListener('keydown', down)
    window.addEventListener('keyup', up)
    window.addEventListener('blur', () => {
      this.keys.clear()
      this.pointer = null
    })
    el.addEventListener('contextmenu', (e) => e.preventDefault())
    el.addEventListener('pointerdown', (e) => {
      if (e.button !== 0) return
      this.pointer = { id: e.pointerId, x: e.clientX, y: e.clientY, cx: e.clientX, cy: e.clientY }
      el.setPointerCapture(e.pointerId)
    })
    el.addEventListener('pointermove', (e) => {
      if (!this.pointer || e.pointerId !== this.pointer.id) return
      this.pointer.x = e.clientX
      this.pointer.y = e.clientY
    })
    const end = (e) => {
      if (this.pointer && e.pointerId === this.pointer.id) this.pointer = null
    }
    el.addEventListener('pointerup', end)
    el.addEventListener('pointercancel', end)
  }

  consume() {
    const just = new Set(this.just)
    this.just.clear()
    return just
  }

  snapshot() {
    let x = 0
    let z = 0
    if (this.keys.has('a') || this.keys.has('arrowleft')) x -= 1
    if (this.keys.has('d') || this.keys.has('arrowright')) x += 1
    if (this.keys.has('w') || this.keys.has('arrowup')) z -= 1
    if (this.keys.has('s') || this.keys.has('arrowdown')) z += 1
    if (this.pointer) {
      const dx = this.pointer.x - this.pointer.cx
      const dy = this.pointer.y - this.pointer.cy
      const mag = Math.hypot(dx, dy)
      if (mag > 10) {
        const k = Math.min(1, (mag - 10) / 72)
        x += (dx / mag) * k
        z += (dy / mag) * k
      }
    }
    const l = Math.hypot(x, z)
    if (l > 1) {
      x /= l
      z /= l
    }
    return { x, z, moving: l > 0.2 }
  }
}
