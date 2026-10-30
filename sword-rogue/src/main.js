import * as THREE from 'three'
import { EffectComposer } from 'three/addons/postprocessing/EffectComposer.js'
import { RenderPass } from 'three/addons/postprocessing/RenderPass.js'
import { UnrealBloomPass } from 'three/addons/postprocessing/UnrealBloomPass.js'
import { AudioBus } from './audio.js'
import { Game } from './game.js'
import { Input } from './input.js'
import { UI } from './ui.js'
import { View } from './view.js'

const canvas = document.querySelector('#c')
const renderer = new THREE.WebGLRenderer({ canvas, antialias: true })
renderer.setPixelRatio(Math.min(window.devicePixelRatio, 2))
renderer.setSize(window.innerWidth, window.innerHeight, false)
renderer.outputColorSpace = THREE.SRGBColorSpace
renderer.toneMapping = THREE.ACESFilmicToneMapping
renderer.toneMappingExposure = 0.95
renderer.shadowMap.enabled = true
renderer.shadowMap.type = THREE.PCFShadowMap

const scene = new THREE.Scene()
const camera = new THREE.PerspectiveCamera(42, window.innerWidth / window.innerHeight, 0.1, 90)
camera.position.set(0, 22, 14)

const composer = new EffectComposer(renderer)
composer.addPass(new RenderPass(scene, camera))
const bloom = new UnrealBloomPass(new THREE.Vector2(window.innerWidth, window.innerHeight), 0.16, 0.35, 0.97)
composer.addPass(bloom)

const view = new View(scene)
const ui = new UI()
const input = new Input(canvas)
const audio = new AudioBus()
const game = new Game({ renderer, camera, view, ui, input, audio })

if (import.meta.env.DEV) window.__game = game

function onResize() {
  const w = window.innerWidth
  const h = window.innerHeight
  camera.aspect = w / h
  camera.updateProjectionMatrix()
  renderer.setSize(w, h, false)
  composer.setSize(w, h)
  bloom.setSize(w, h)
}
window.addEventListener('resize', onResize)

const timer = new THREE.Timer()
timer.connect(document)
renderer.setAnimationLoop((time) => {
  timer.update(time)
  const dt = Math.min(timer.getDelta(), 0.05)
  game.frame(dt)
  composer.render()
})
