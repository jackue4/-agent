import { WebSocketServer } from 'ws'
import os from 'os'

const rooms = new Map()
const ROBES = [
  { name: '青衫', color: 0x3d6f8c },
  { name: '赤衫', color: 0xe25b4a },
  { name: '翠衫', color: 0x3e9a8c },
  { name: '金衫', color: 0xe2b15a },
]

export function lanHosts() {
  const hosts = []
  for (const list of Object.values(os.networkInterfaces())) {
    for (const net of list || []) {
      if (net.family === 'IPv4' && !net.internal) hosts.push(net.address)
    }
  }
  return hosts
}

function send(ws, msg) {
  if (ws.readyState === 1) ws.send(JSON.stringify(msg))
}

function membersOf(room) {
  return [...room.members.values()].map((member) => ({
    id: member.id,
    name: member.name,
    color: member.color,
    weapon: member.weapon,
    host: member.id === room.hostId,
  }))
}

function emitLobby(room) {
  const members = membersOf(room)
  for (const member of room.members.values()) {
    send(member.ws, { t: 'lobby', you: member.id, hostId: room.hostId, room: room.id, members })
  }
}

function handle(ws, msg) {
  if (msg.t === 'join') {
    const roomId = String(msg.room || '').toUpperCase().replace(/[^A-Z0-9]/g, '').slice(0, 4)
    if (roomId.length < 4) {
      send(ws, { t: 'error', text: '房间号无效' })
      return
    }
    let room = rooms.get(roomId)
    if (!room) room = rooms.set(roomId, { id: roomId, hostId: null, members: new Map(), started: false }).get(roomId)
    if (room.started) {
      send(ws, { t: 'error', text: '这局已经开始了' })
      return
    }
    if (room.members.size >= 4) {
      send(ws, { t: 'error', text: '这间房已经满了' })
      return
    }
    const look = ROBES[room.members.size % ROBES.length]
    const id = `p${room.members.size + 1}`
    const member = { id, ws, name: look.name, color: look.color, weapon: msg.weapon || 'qingfeng' }
    room.members.set(id, member)
    if (!room.hostId) room.hostId = id
    ws.room = room
    ws.memberId = id
    emitLobby(room)
    return
  }
  const room = ws.room
  if (!room) return
  const member = room.members.get(ws.memberId)
  if (!member) return
  if (msg.t === 'weapon' && !room.started) {
    member.weapon = msg.weapon || member.weapon
    emitLobby(room)
  } else if (msg.t === 'go' && ws.memberId === room.hostId && !room.started) {
    room.started = true
    room.seed = (Math.random() * 1e9) >>> 0
    const payload = { t: 'go', seed: room.seed, hostId: room.hostId, members: membersOf(room) }
    for (const item of room.members.values()) send(item.ws, payload)
  } else if (msg.t === 'input' && room.started) {
    const host = room.members.get(room.hostId)
    if (host) send(host.ws, { t: 'input', id: member.id, x: msg.x, z: msg.z, moving: !!msg.moving })
  } else if (msg.t === 'pick' && room.started) {
    const host = room.members.get(room.hostId)
    if (host) send(host.ws, { t: 'pick', id: member.id, kind: msg.kind, skill: msg.skill })
  } else if ((msg.t === 'snap' || msg.t === 'offers' || msg.t === 'toast') && ws.memberId === room.hostId) {
    for (const item of room.members.values()) {
      if (item.id !== room.hostId) send(item.ws, msg)
    }
  }
}

function leave(ws) {
  const room = ws.room
  if (!room) return
  room.members.delete(ws.memberId)
  if (room.members.size === 0) {
    rooms.delete(room.id)
    return
  }
  if (room.hostId === ws.memberId) {
    for (const item of room.members.values()) send(item.ws, { t: 'bye', text: '房主离开了，这局结束' })
    rooms.delete(room.id)
    return
  }
  if (!room.started) emitLobby(room)
  else {
    const host = room.members.get(room.hostId)
    if (host) send(host.ws, { t: 'leave', id: ws.memberId })
  }
}

export function attachParty(httpServer) {
  const wss = new WebSocketServer({ noServer: true })
  httpServer.on('upgrade', (request, socket, head) => {
    if (!(request.url || '').startsWith('/party')) return
    wss.handleUpgrade(request, socket, head, (ws) => {
      wss.emit('connection', ws, request)
    })
  })
  wss.on('connection', (ws) => {
    ws.on('message', (raw) => {
      try {
        handle(ws, JSON.parse(raw.toString()))
      } catch {
        send(ws, { t: 'error', text: '消息无法解析' })
      }
    })
    ws.on('close', () => leave(ws))
  })
}
