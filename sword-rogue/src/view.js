import * as THREE from 'three'

const _v = new THREE.Vector3()
const outlineMat = new THREE.MeshBasicMaterial({ color: 0x2a211c, side: THREE.BackSide })

function toonRamp() {
  const canvas = document.createElement('canvas')
  canvas.width = 4
  canvas.height = 1
  const ctx = canvas.getContext('2d')
  ;['#6a5860', '#b5a296', '#f4e6d4', '#fff9f2'].forEach((color, i) => {
    ctx.fillStyle = color
    ctx.fillRect(i, 0, 1, 1)
  })
  const tex = new THREE.CanvasTexture(canvas)
  tex.magFilter = THREE.NearestFilter
  tex.minFilter = THREE.NearestFilter
  return tex
}

const ramp = toonRamp()

function toon(color, emissive = 0x000000, intensity = 0) {
  return new THREE.MeshToonMaterial({ color, gradientMap: ramp, emissive, emissiveIntensity: intensity })
}

function shell(mesh, amount = 1.12) {
  const ghost = new THREE.Mesh(mesh.geometry, outlineMat)
  ghost.position.copy(mesh.position)
  ghost.rotation.copy(mesh.rotation)
  ghost.scale.copy(mesh.scale).multiplyScalar(amount)
  ghost.castShadow = false
  ghost.receiveShadow = false
  return ghost
}

function paperFloor() {
  const canvas = document.createElement('canvas')
  canvas.width = 1024
  canvas.height = 1024
  const ctx = canvas.getContext('2d')
  ctx.fillStyle = '#efe2cc'
  ctx.fillRect(0, 0, 1024, 1024)
  for (let i = 0; i < 80; i++) {
    ctx.fillStyle = `rgba(120, 80, 50, ${0.015 + Math.random() * 0.03})`
    ctx.beginPath()
    ctx.ellipse(Math.random() * 1024, Math.random() * 1024, 40 + Math.random() * 120, 18 + Math.random() * 40, Math.random() * 3, 0, Math.PI * 2)
    ctx.fill()
  }
  ctx.strokeStyle = 'rgba(90, 62, 42, 0.18)'
  ctx.lineWidth = 2
  for (let i = 0; i <= 8; i++) {
    const p = (i / 8) * 1024
    ctx.beginPath()
    ctx.moveTo(p, 40)
    ctx.lineTo(p, 984)
    ctx.stroke()
    ctx.beginPath()
    ctx.moveTo(40, p)
    ctx.lineTo(984, p)
    ctx.stroke()
  }
  ctx.strokeStyle = 'rgba(122, 72, 48, 0.55)'
  ctx.lineWidth = 6
  ctx.beginPath()
  ctx.arc(512, 512, 150, 0, Math.PI * 2)
  ctx.stroke()
  ctx.lineWidth = 2
  ctx.beginPath()
  ctx.arc(512, 512, 118, 0, Math.PI * 2)
  ctx.stroke()
  ctx.fillStyle = 'rgba(122, 62, 42, 0.78)'
  ctx.font = '92px SimSun, serif'
  ctx.textAlign = 'center'
  ctx.textBaseline = 'middle'
  ctx.fillText('剑', 512, 524)
  const tex = new THREE.CanvasTexture(canvas)
  tex.colorSpace = THREE.SRGBColorSpace
  tex.anisotropy = 4
  return tex
}

function makeTrail() {
  const geometry = new THREE.BufferGeometry()
  const positions = new Float32Array(16 * 3)
  geometry.setAttribute('position', new THREE.BufferAttribute(positions, 3))
  const indices = []
  for (let i = 0; i < 7; i++) {
    const a = i * 2
    indices.push(a, a + 1, a + 2, a + 1, a + 3, a + 2)
  }
  geometry.setIndex(indices)
  const material = new THREE.MeshBasicMaterial({
    color: 0xb7e6ff,
    transparent: true,
    opacity: 0.7,
    side: THREE.DoubleSide,
    depthWrite: false,
    blending: THREE.AdditiveBlending,
  })
  const mesh = new THREE.Mesh(geometry, material)
  mesh.frustumCulled = false
  mesh.userData.hist = []
  return mesh
}

function writeRibbon(mesh, color) {
  const hist = mesh.userData.hist
  if (hist.length < 2) {
    mesh.visible = false
    return
  }
  mesh.visible = true
  mesh.material.color.setHex(color)
  const pos = mesh.geometry.attributes.position.array
  for (let i = 0; i < 8; i++) {
    const p = hist[Math.min(i, hist.length - 1)]
    const q = hist[Math.min(i + 1, hist.length - 1)]
    let dx = q.x - p.x
    let dz = q.z - p.z
    const len = Math.hypot(dx, dz) || 1
    dx /= len
    dz /= len
    const width = 0.03 + (i / 7) * 0.14
    const ox = -dz * width
    const oz = dx * width
    const o = i * 6
    pos[o] = p.x + ox
    pos[o + 1] = 0.85
    pos[o + 2] = p.z + oz
    pos[o + 3] = p.x - ox
    pos[o + 4] = 0.85
    pos[o + 5] = p.z - oz
  }
  mesh.geometry.attributes.position.needsUpdate = true
}

function makeSword() {
  const group = new THREE.Group()
  const mat = new THREE.MeshBasicMaterial({ color: 0xd7f4ff })
  const blade = new THREE.Mesh(new THREE.BoxGeometry(0.08, 0.035, 1.15), mat)
  blade.position.z = -0.48
  const guard = new THREE.Mesh(new THREE.BoxGeometry(0.28, 0.04, 0.08), mat)
  const tassel = new THREE.Mesh(new THREE.BoxGeometry(0.04, 0.22, 0.04), new THREE.MeshBasicMaterial({ color: 0xe25b4a }))
  tassel.position.set(0.12, -0.12, 0.08)
  group.add(blade, guard, tassel)
  group.userData.mat = mat
  return group
}

function eyes(group, y, z, spread, size = 0.045) {
  const mat = new THREE.MeshBasicMaterial({ color: 0x241810 })
  const left = new THREE.Mesh(new THREE.SphereGeometry(size, 8, 8), mat)
  const right = left.clone()
  left.position.set(-spread, y, z)
  right.position.set(spread, y, z)
  group.add(left, right)
}

function makeHero(color) {
  const group = new THREE.Group()
  const robe = new THREE.Mesh(new THREE.ConeGeometry(0.46, 1.02, 9), toon(color))
  robe.position.y = 0.55
  robe.castShadow = true
  const head = new THREE.Mesh(new THREE.SphereGeometry(0.28, 18, 14), toon(0xffe3c8))
  head.position.y = 1.22
  head.castShadow = true
  const hair = new THREE.Mesh(new THREE.SphereGeometry(0.24, 14, 12), toon(0x2a1c18))
  hair.position.y = 1.36
  hair.scale.set(1, 0.66, 1)
  const bun = new THREE.Mesh(new THREE.SphereGeometry(0.11, 10, 8), toon(0x2a1c18))
  bun.position.y = 1.56
  const ribbon = new THREE.Mesh(new THREE.ConeGeometry(0.07, 0.32, 5), toon(0xd24a45, 0x601818, 0.25))
  ribbon.position.set(0.18, 1.38, -0.06)
  ribbon.rotation.z = 0.7
  const sash = new THREE.Mesh(new THREE.TorusGeometry(0.28, 0.045, 6, 12), toon(0xf0d48a, 0x6a4010, 0.2))
  sash.rotation.x = Math.PI / 2
  sash.position.y = 0.82
  const shadow = new THREE.Mesh(
    new THREE.CircleGeometry(0.48, 18),
    new THREE.MeshBasicMaterial({ color: 0x1c1410, transparent: true, opacity: 0.28 }),
  )
  shadow.rotation.x = -Math.PI / 2
  shadow.position.y = 0.02
  const ring = new THREE.Mesh(
    new THREE.RingGeometry(0.36, 0.45, 28),
    new THREE.MeshBasicMaterial({ color: 0xf6e2b0, transparent: true, opacity: 0.95, side: THREE.DoubleSide }),
  )
  ring.rotation.x = -Math.PI / 2
  ring.position.y = 0.035
  group.add(shadow, ring, robe, head, hair, bun, ribbon, sash, shell(robe, 1.1), shell(head, 1.14))
  eyes(group, 1.22, 0.22, 0.09, 0.04)
  group.userData.ring = ring
  group.userData.robe = robe
  group.scale.setScalar(1.7)
  ring.scale.setScalar(1 / 1.7)
  return group
}

function makeEnemy(type) {
  const group = new THREE.Group()
  const palette = {
    chaser: 0xe25b4a,
    archer: 0xf0a04a,
    jumper: 0x8a6ad4,
    summoner: 0x3f9a6a,
    boss: 0xe7d3ae,
  }
  const color = palette[type] || 0xffffff
  const mat = toon(color, color, type === 'boss' ? 0.18 : 0.08)
  const add = (mesh, y) => {
    mesh.position.y = y
    mesh.castShadow = true
    group.add(mesh, shell(mesh, 1.08))
  }
  if (type === 'boss') {
    const body = new THREE.Mesh(new THREE.SphereGeometry(1.05, 18, 14), mat)
    body.scale.y = 0.82
    add(body, 1.15)
    const head = new THREE.Mesh(new THREE.SphereGeometry(0.48, 14, 12), mat)
    add(head, 2.05)
    const belly = new THREE.Mesh(
      new THREE.SphereGeometry(0.42, 12, 10),
      new THREE.MeshBasicMaterial({ color: 0xffe3a0 }),
    )
    belly.position.set(0, 1.05, 0.72)
    group.add(belly)
    eyes(group, 2.08, 0.36, 0.16, 0.07)
  } else if (type === 'archer') {
    add(new THREE.Mesh(new THREE.CapsuleGeometry(0.22, 0.7, 4, 8), mat), 0.75)
    const bow = new THREE.Mesh(new THREE.TorusGeometry(0.28, 0.035, 6, 16, Math.PI), toon(0xf2d7a2))
    bow.position.set(0.28, 0.9, 0)
    bow.rotation.y = Math.PI / 2
    group.add(bow)
    eyes(group, 1.15, 0.18, 0.07)
  } else if (type === 'jumper') {
    const body = new THREE.Mesh(new THREE.SphereGeometry(0.48, 16, 12), mat)
    body.scale.set(1.15, 0.8, 1)
    add(body, 0.5)
    eyes(group, 0.62, 0.38, 0.12, 0.05)
  } else if (type === 'summoner') {
    add(new THREE.Mesh(new THREE.ConeGeometry(0.46, 1.25, 8), mat), 0.72)
    add(new THREE.Mesh(new THREE.ConeGeometry(0.32, 0.42, 8), toon(0xf2d7a2)), 1.5)
    eyes(group, 1.15, 0.28, 0.1)
  } else {
    const body = new THREE.Mesh(new THREE.SphereGeometry(0.42, 16, 12), mat)
    body.scale.set(1.15, 0.86, 1)
    add(body, 0.48)
    const horn = new THREE.Mesh(new THREE.ConeGeometry(0.08, 0.24, 6), toon(0xf2d7a2))
    horn.position.y = 0.95
    group.add(horn)
    eyes(group, 0.58, 0.32, 0.1, 0.045)
  }
  group.userData.mat = mat
  return group
}

export class View {
  constructor(scene) {
    this.scene = scene
    scene.background = new THREE.Color(0x1c2438)
    scene.fog = new THREE.Fog(0x1c2438, 28, 62)
    scene.add(new THREE.HemisphereLight(0xf2e2c4, 0x2a3348, 1.25))
    this.key = new THREE.DirectionalLight(0xfff0d2, 2.2)
    this.key.position.set(8, 18, 6)
    this.key.castShadow = true
    this.key.shadow.mapSize.set(1024, 1024)
    const shadow = this.key.shadow.camera
    shadow.near = 2
    shadow.far = 42
    shadow.left = -18
    shadow.right = 18
    shadow.top = 18
    shadow.bottom = -18
    scene.add(this.key)
    scene.add(new THREE.DirectionalLight(0x8eb4ff, 0.55).translateX(-10).translateY(8).translateZ(-6))
    this.focusLight = new THREE.PointLight(0xffe0a0, 0, 7, 2)
    scene.add(this.focusLight)

    const moon = new THREE.Mesh(
      new THREE.SphereGeometry(2.2, 24, 16),
      new THREE.MeshBasicMaterial({ color: 0xfff3d2 }),
    )
    moon.position.set(-7, 16, -18)
    scene.add(moon)
    this.dressWorld(scene)

    this.roomRoot = new THREE.Group()
    scene.add(this.roomRoot)
    this.actorRoot = new THREE.Group()
    scene.add(this.actorRoot)
    this.floorMat = new THREE.MeshToonMaterial({ map: paperFloor(), gradientMap: ramp })
    this.wallMat = toon(0x6d5344)
    this.roofMat = toon(0x3e4d68)
    this.pillarMat = toon(0x8a6a48)
    this.waterMat = new THREE.MeshToonMaterial({
      color: 0x4f8fba, gradientMap: ramp, transparent: true, opacity: 0.78,
    })
    this.spikeMat = toon(0xa84848, 0x401010, 0.3)
    this.doorMat = new THREE.MeshBasicMaterial({ color: 0xf0d48a })

    this.heroes = new Map()
    this.swords = new Map()
    this.enemies = new Map()
    this.shots = []
    this.orbs = []
    this.rings = []
    this.sparks = []
    for (let i = 0; i < 48; i++) {
      const spark = new THREE.Mesh(
        new THREE.SphereGeometry(0.05, 6, 6),
        new THREE.MeshBasicMaterial({ color: 0xffe1a8, transparent: true }),
      )
      spark.visible = false
      this.actorRoot.add(spark)
      this.sparks.push(spark)
    }
    this.sparkCursor = 0
    this.petals = []
    const petalMat = new THREE.MeshBasicMaterial({ color: 0xf2b7c4, side: THREE.DoubleSide, transparent: true, opacity: 0.85 })
    for (let i = 0; i < 22; i++) {
      const petal = new THREE.Mesh(new THREE.CircleGeometry(0.08, 5), petalMat)
      petal.position.set((Math.random() - 0.5) * 16, 1 + Math.random() * 6, (Math.random() - 0.5) * 20)
      petal.userData.speed = 0.25 + Math.random() * 0.35
      this.actorRoot.add(petal)
      this.petals.push(petal)
    }
    this.room = null
    this.t = 0
  }

  dressWorld(scene) {
    const hillMat = toon(0x243044)
    for (const hill of [[-16, -8, 6], [14, -14, 8], [0, -20, 10]]) {
      const mesh = new THREE.Mesh(new THREE.SphereGeometry(hill[2], 12, 8), hillMat)
      mesh.position.set(hill[0], hill[2] * 0.2, hill[1])
      mesh.scale.y = 0.45
      scene.add(mesh)
    }
  }

  setWeapon() {}

  setRoom(room) {
    this.room = room
    for (const child of [...this.roomRoot.children]) {
      this.roomRoot.remove(child)
      child.traverse((obj) => {
        if (obj.geometry && obj.geometry !== this.floorMat) obj.geometry.dispose?.()
      })
    }
    const floor = new THREE.Mesh(new THREE.PlaneGeometry(room.halfW * 2, room.halfH * 2), this.floorMat)
    floor.rotation.x = -Math.PI / 2
    floor.receiveShadow = true
    this.roomRoot.add(floor)
    this.buildWalls(room)
    this.door = new THREE.Mesh(new THREE.BoxGeometry(2.2, 0.08, 0.35), this.doorMat)
    this.door.position.set(0, 0.08, -room.halfH + 0.2)
    this.roomRoot.add(this.door)
    for (const obstacle of room.obstacles) {
      const mesh = new THREE.Mesh(new THREE.CylinderGeometry(obstacle.r * 0.85, obstacle.r, 1.7, 8), this.pillarMat)
      mesh.position.set(obstacle.x, 0.85, obstacle.z)
      mesh.castShadow = true
      mesh.receiveShadow = true
      this.roomRoot.add(mesh, shell(mesh, 1.06))
    }
    for (const water of room.waters) {
      const mesh = new THREE.Mesh(new THREE.CircleGeometry(water.r, 22), this.waterMat)
      mesh.rotation.x = -Math.PI / 2
      mesh.position.set(water.x, 0.04, water.z)
      this.roomRoot.add(mesh)
    }
    for (const spike of room.spikes) {
      const mesh = new THREE.Mesh(new THREE.ConeGeometry(spike.r * 0.4, 0.6, 5), this.spikeMat)
      mesh.position.set(spike.x, 0.3, spike.z)
      this.roomRoot.add(mesh)
    }
    if (room.kind === 'angel') {
      const statue = new THREE.Mesh(new THREE.CapsuleGeometry(0.32, 1.3, 4, 8), toon(0xf7efe2, 0x6a5830, 0.2))
      statue.position.set(0, 1.15, -2.2)
      statue.castShadow = true
      this.roomRoot.add(statue)
    }
    this.addLanterns(room)
    this.addBamboo(room)
  }

  buildWalls(room) {
    const t = 0.55
    const gap = 1.35
    const side = room.halfW - gap
    const h = 1.15
    const place = (x, z, width, depth) => {
      const mesh = new THREE.Mesh(new THREE.BoxGeometry(width, h, depth), this.wallMat)
      mesh.position.set(x, h / 2, z)
      mesh.castShadow = true
      mesh.receiveShadow = true
      const roof = new THREE.Mesh(new THREE.BoxGeometry(width + 0.25, 0.18, depth + 0.3), this.roofMat)
      roof.position.set(x, h + 0.08, z)
      this.roomRoot.add(mesh, roof)
    }
    place(0, room.halfH + t / 2, room.halfW * 2 + t * 2, t)
    place(-gap - side / 2, -room.halfH - t / 2, side, t)
    place(gap + side / 2, -room.halfH - t / 2, side, t)
    place(-room.halfW - t / 2, 0, t, room.halfH * 2)
    place(room.halfW + t / 2, 0, t, room.halfH * 2)
  }

  addLanterns(room) {
    const spots = [
      [-room.halfW + 0.8, -room.halfH + 1.2],
      [room.halfW - 0.8, -room.halfH + 1.2],
      [-room.halfW + 0.8, room.halfH - 1.2],
      [room.halfW - 0.8, room.halfH - 1.2],
    ]
    for (const [x, z] of spots) {
      const pole = new THREE.Mesh(new THREE.CylinderGeometry(0.05, 0.06, 1.5, 6), toon(0x5a4034))
      pole.position.set(x, 0.75, z)
      const lamp = new THREE.Mesh(
        new THREE.SphereGeometry(0.22, 10, 8),
        new THREE.MeshBasicMaterial({ color: 0xffc56a }),
      )
      lamp.position.set(x, 1.55, z)
      lamp.scale.y = 1.25
      const light = new THREE.PointLight(0xffb45a, 0.55, 3.2, 2)
      light.position.set(x, 1.55, z)
      this.roomRoot.add(pole, lamp, light)
    }
  }

  addBamboo(room) {
    for (let i = 0; i < 6; i++) {
      const side = i < 3 ? -1 : 1
      const z = -room.halfH + 3 + (i % 3) * 4.2
      const x = side * (room.halfW + 1.1)
      const culm = new THREE.Mesh(new THREE.CylinderGeometry(0.06, 0.08, 3.2, 6), toon(0x6f8f62))
      culm.position.set(x, 1.6, z)
      const leaf = new THREE.Mesh(new THREE.ConeGeometry(0.28, 0.7, 5), toon(0x87a86a))
      leaf.position.set(x + side * 0.15, 2.8, z)
      leaf.rotation.z = side * 0.6
      this.roomRoot.add(culm, leaf)
    }
  }

  heroFor(player) {
    let hero = this.heroes.get(player.id)
    if (!hero) {
      hero = makeHero(player.color || 0xf4f0e6)
      this.actorRoot.add(hero)
      this.heroes.set(player.id, hero)
    }
    return hero
  }

  swordFor(id) {
    let sword = this.swords.get(id)
    if (!sword) {
      sword = { mesh: makeSword(), trail: makeTrail() }
      this.actorRoot.add(sword.mesh, sword.trail)
      this.swords.set(id, sword)
    }
    return sword
  }

  sync(world, dt) {
    this.t += dt
    for (const petal of this.petals) {
      petal.position.y -= petal.userData.speed * dt
      petal.rotation.z += dt
      petal.position.x += Math.sin(this.t + petal.position.z) * dt * 0.15
      if (petal.position.y < 0.2) petal.position.y = 5.5
    }
    for (const spark of this.sparks) {
      if (!spark.visible) continue
      spark.userData.life -= dt
      spark.position.x += spark.userData.vx * dt
      spark.position.z += spark.userData.vz * dt
      spark.position.y += dt * 1.2
      spark.material.opacity = Math.max(0, spark.userData.life / 0.35)
      if (spark.userData.life <= 0) spark.visible = false
    }
    if (!world) return
    const seenHero = new Set()
    for (const player of world.players || []) {
      seenHero.add(player.id)
      const hero = this.heroFor(player)
      hero.visible = player.alive !== false
      const bob = Math.sin(this.t * 3 + player.x) * 0.03
      hero.position.set(player.x, bob, player.z)
      hero.rotation.y = Math.atan2(player.fx || 0, player.fz || -1)
      hero.userData.ring.material.color.setHex(player.guard ? 0xffe08a : player.focused ? 0xfff0b0 : 0xf6e2b0)
      hero.userData.robe.material.emissive.setHex(player.flash > 0 ? 0xff5530 : 0x000000)
      hero.userData.robe.material.emissiveIntensity = player.flash > 0 ? 0.7 : 0
      if (player.focused) {
        this.focusLight.position.set(player.x, 1.6, player.z)
        this.focusLight.intensity = 0.65
      }
    }
    for (const [id, hero] of this.heroes) {
      if (!seenHero.has(id)) hero.visible = false
    }
    if (!(world.players || []).some((player) => player.focused)) this.focusLight.intensity = 0

    const seenSword = new Set()
    for (const player of world.players || []) {
      for (const guard of player.guards || []) {
        const id = `${player.id}:g:${guard.kind}:${guard.i}`
        seenSword.add(id)
        const sword = this.swordFor(id)
        const color = guard.kind === 'orbit' ? 0xf0c14a : player.weaponColor
        this.placeSword(sword, guard.x, guard.z, 1.05, -Math.sin(guard.ang || 0), Math.cos(guard.ang || 0), color, false)
      }
      if (player.wing) {
        const id = `${player.id}:wing`
        seenSword.add(id)
        const sword = this.swordFor(id)
        this.placeSword(sword, player.wing.x, player.wing.z, 1.25, -Math.sin(this.t * 2), Math.cos(this.t * 2), 0x9ee0b8, false)
      }
    }
    for (const bolt of world.bolts || []) {
      const id = bolt.id || `${bolt.x}:${bolt.z}`
      seenSword.add(id)
      const sword = this.swordFor(id)
      const speed = Math.hypot(bolt.vx, bolt.vz) || 1
      this.placeSword(sword, bolt.x, bolt.z, bolt.phase === 'back' ? 0.8 : 1.05, bolt.vx / speed, bolt.vz / speed, bolt.color || 0xd7f4ff, true)
    }
    for (const [id, sword] of this.swords) {
      if (!seenSword.has(id)) {
        sword.mesh.visible = false
        sword.trail.visible = false
        sword.trail.userData.hist = []
      }
    }
    if (this.door) {
      const open = !!world.door
      this.door.material.color.setHex(open ? 0xffe7a8 : 0x5c5146)
    }
    this.syncEnemies(world)
    this.syncShots(world)
    this.syncOrbs(world)
    this.syncRings(world)
  }

  placeSword(sword, x, z, y, dx, dz, color, trail) {
    sword.mesh.visible = true
    sword.mesh.position.set(x, y, z)
    _v.set(x + dx, y, z + dz)
    sword.mesh.lookAt(_v)
    sword.mesh.userData.mat.color.setHex(color)
    const hist = sword.trail.userData.hist
    if (trail) {
      hist.push({ x, z })
      if (hist.length > 8) hist.shift()
      writeRibbon(sword.trail, color)
    } else {
      hist.length = 0
      sword.trail.visible = false
    }
  }

  syncEnemies(world) {
    const alive = new Set()
    for (const enemy of world.enemies || []) {
      alive.add(enemy.id)
      let mesh = this.enemies.get(enemy.id)
      if (!mesh) {
        mesh = makeEnemy(enemy.type)
        this.actorRoot.add(mesh)
        this.enemies.set(enemy.id, mesh)
      }
      mesh.visible = true
      mesh.position.set(enemy.x, 0, enemy.z)
      const squash = enemy.state === 'windup' ? 1.08 : 1
      mesh.scale.setScalar(squash)
      if (mesh.userData.mat) {
        mesh.userData.mat.emissive.setHex(enemy.hitFlash > 0 ? 0xfff2ea : enemy.frozen > 0 ? 0xb7e4ff : mesh.userData.mat.color.getHex())
        mesh.userData.mat.emissiveIntensity = enemy.hitFlash > 0 ? 0.8 : 0.12
      }
    }
    for (const [id, mesh] of this.enemies) {
      if (!alive.has(id)) {
        mesh.visible = false
        this.actorRoot.remove(mesh)
        this.enemies.delete(id)
      }
    }
  }

  syncShots(world) {
    const shots = world.shots || []
    while (this.shots.length < shots.length) {
      const mesh = new THREE.Mesh(
        new THREE.SphereGeometry(1, 10, 8),
        new THREE.MeshBasicMaterial({ color: 0xff6a3c }),
      )
      this.actorRoot.add(mesh)
      this.shots.push(mesh)
    }
    this.shots.forEach((mesh, i) => {
      const shot = shots[i]
      mesh.visible = !!shot
      if (!shot) return
      mesh.position.set(shot.x, 0.55, shot.z)
      mesh.scale.setScalar(Math.max(0.34, shot.r * 1.9))
    })
  }

  syncOrbs(world) {
    const orbs = world.orbs || []
    while (this.orbs.length < orbs.length) {
      const mesh = new THREE.Mesh(
        new THREE.OctahedronGeometry(0.14, 0),
        new THREE.MeshBasicMaterial({ color: 0xffe08a }),
      )
      this.actorRoot.add(mesh)
      this.orbs.push(mesh)
    }
    this.orbs.forEach((mesh, i) => {
      const orb = orbs[i]
      mesh.visible = !!orb
      if (!orb) return
      mesh.position.set(orb.x, 0.55 + Math.sin(this.t * 6 + i) * 0.08, orb.z)
      mesh.rotation.y += 0.08
    })
  }

  syncRings(world) {
    const marks = []
    for (const enemy of world.enemies || []) {
      if (enemy.state === 'windup') {
        marks.push({ x: enemy.lockX, z: enemy.lockZ, r: enemy.tellR || 0.8, color: 0xff5a4a, opacity: 0.7 })
      }
    }
    for (const hazard of world.hazards || []) {
      const u = Math.min(1, hazard.t / hazard.delay)
      marks.push({
        x: hazard.x,
        z: hazard.z,
        r: hazard.r * (0.35 + u * 0.75),
        color: hazard.kind === 'rain' ? 0xf0c14a : 0xff3b3b,
        opacity: hazard.hit ? 0.25 : 0.75,
      })
    }
    if (world.target) marks.push({ x: world.target.x, z: world.target.z, r: world.target.r + 0.25, color: 0xfff0b0, opacity: 0.45 })
    while (this.rings.length < marks.length) {
      const mesh = new THREE.Mesh(
        new THREE.RingGeometry(0.82, 1, 28),
        new THREE.MeshBasicMaterial({ color: 0xff5a4a, transparent: true, opacity: 0.75, side: THREE.DoubleSide }),
      )
      mesh.rotation.x = -Math.PI / 2
      this.actorRoot.add(mesh)
      this.rings.push(mesh)
    }
    this.rings.forEach((mesh, i) => {
      const mark = marks[i]
      mesh.visible = !!mark
      if (!mark) return
      mesh.position.set(mark.x, 0.05, mark.z)
      mesh.scale.setScalar(mark.r)
      mesh.material.color.setHex(mark.color)
      mesh.material.opacity = mark.opacity
    })
  }

  burst(x, z, color, n = 8) {
    for (let i = 0; i < n; i++) {
      const spark = this.sparks[this.sparkCursor++ % this.sparks.length]
      spark.visible = true
      spark.position.set(x, 0.8, z)
      spark.material.color.setHex(color)
      spark.userData.vx = (Math.random() - 0.5) * 5
      spark.userData.vz = (Math.random() - 0.5) * 5
      spark.userData.life = 0.35
    }
  }

  project(camera, x, y, z, width, height) {
    _v.set(x, y, z).project(camera)
    return {
      x: (_v.x * 0.5 + 0.5) * width,
      y: (-_v.y * 0.5 + 0.5) * height,
      behind: _v.z > 1,
    }
  }
}
