export class PartyClient {
  constructor(game) {
    this.game = game
    this.ws = null
    this.id = null
    this.hostId = null
    this.room = null
    this.members = []
  }

  get isHost() {
    return this.id && this.id === this.hostId
  }

  connect(room) {
    if (this.ws) {
      this.ws.onclose = null
      this.ws.onmessage = null
      this.ws.close()
    }
    this.room = room
    const proto = location.protocol === 'https:' ? 'wss' : 'ws'
    this.ws = new WebSocket(`${proto}://${location.host}/party`)
    this.ws.onopen = () => this.send({ t: 'join', room, weapon: this.game.ui.weaponId })
    this.ws.onmessage = (event) => {
      const msg = JSON.parse(event.data)
      this.game.onNet(msg)
    }
    this.ws.onerror = () => this.game.ui.toast('连不上联机服务，确认和房主在同一个 Wi-Fi')
    this.ws.onclose = () => {
      if (this.ws && this.ws.readyState === WebSocket.CLOSED) {
        this.game.onNet({ t: 'bye', text: '连接断开了' })
      }
    }
  }

  send(msg) {
    if (this.ws?.readyState === 1) this.ws.send(JSON.stringify(msg))
  }
}
