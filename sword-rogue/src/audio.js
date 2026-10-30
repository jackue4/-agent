export class AudioBus {
  constructor() {
    this.ctx = null
    this.muted = localStorage.getItem('sword-rogue-mute') === '1'
  }

  ensure() {
    if (!this.ctx) {
      const AC = window.AudioContext || window.webkitAudioContext
      if (!AC) return
      this.ctx = new AC()
    }
    if (this.ctx.state === 'suspended') this.ctx.resume()
  }

  toggle() {
    this.muted = !this.muted
    localStorage.setItem('sword-rogue-mute', this.muted ? '1' : '0')
    return this.muted
  }

  tone(freq, dur, type, gain, slide = 0) {
    if (this.muted || !this.ctx) return
    const t = this.ctx.currentTime
    const o = this.ctx.createOscillator()
    const g = this.ctx.createGain()
    o.type = type
    o.frequency.setValueAtTime(freq, t)
    if (slide) o.frequency.exponentialRampToValueAtTime(Math.max(48, freq + slide), t + dur)
    g.gain.setValueAtTime(gain, t)
    g.gain.exponentialRampToValueAtTime(0.001, t + dur)
    o.connect(g)
    g.connect(this.ctx.destination)
    o.start(t)
    o.stop(t + dur + 0.02)
  }

  fire() { this.tone(540, 0.07, 'triangle', 0.045, 220) }
  hit() { this.tone(210, 0.04, 'square', 0.025, -90) }
  hurt() { this.tone(96, 0.16, 'sawtooth', 0.05, -50) }
  block() { this.tone(880, 0.04, 'square', 0.02, 80) }
  pick() { this.tone(640, 0.09, 'sine', 0.04, 180) }
  die() { this.tone(140, 0.28, 'sawtooth', 0.05, -90) }
  win() {
    this.tone(523, 0.16, 'sine', 0.045)
    setTimeout(() => this.tone(659, 0.16, 'sine', 0.045), 110)
    setTimeout(() => this.tone(784, 0.28, 'sine', 0.05), 220)
  }
}
