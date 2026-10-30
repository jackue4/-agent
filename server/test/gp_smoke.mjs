// Native smoke test of the Godot-project engine: create -> write -> check -> build (full, then
// patch) -> live eval with a frame strip -> self-test. Usage: node test/gp_smoke.mjs [--keep]
import fs from 'node:fs';
import { GodotProject } from '../gproject.mjs';
import { LiveGame } from '../live.mjs';

const keep = process.argv.includes('--keep');
const p = new GodotProject('smoke_test');
fs.rmSync(p.dir, { recursive: true, force: true });
const t = () => ((Date.now() - t0) / 1000).toFixed(1) + 's';
const t0 = Date.now();
p.create({ title: '冒烟测试', orientation: 'landscape' });
const must = (ok, what) => { console.log(ok ? 'ok  ' : 'FAIL', what); if (!ok) process.exitCode = 1; };

must(p.write('scripts/mover.gd', 'class_name Mover\nextends Node2D\nvar speed := 300.0\nfunc _process(dt):\n\tposition.x = fmod(position.x + speed * dt, 1280.0)\nfunc _draw():\n\tdraw_circle(Vector2.ZERO, 40, Color.ORANGE)\n').length === 0, 'write class_name script');
must(p.write('main.tscn', '[gd_scene load_steps=2 format=3]\n\n[ext_resource type="Script" path="res://main.gd" id="1"]\n\n[node name="Main" type="Node2D"]\nscript = ExtResource("1")\n\n[node name="Score" type="Label" parent="."]\noffset_left = 20.0\noffset_top = 20.0\ntext = "分数 0"\n').length === 0, 'write scene');
must(p.write('main.gd', 'extends Node2D\nvar score := 0\nfunc _ready():\n\tvar m := Mover.new()\n\tm.name = "Ball"\n\tm.position = Vector2(100, 360)\n\tadd_child(m)\nfunc _unhandled_input(e):\n\tif e is InputEventMouseButton and e.pressed:\n\t\tscore += 1\n\t\t$Score.text = "分数 %d" % score\n\t\tif score >= 3: UGC.win(score)\nfunc auto_test():\n\tfor i in 3:\n\t\tUGC.click_at(Vector2(640, 360))\n\t\tawait UGC.wait(0.1)\n\tUGC.check(score == 3, "点三下得 3 分")\n\tUGC.check(UGC.result == "win", "三分获胜")\n').length === 0, 'write main');
must(p.write('evil.gd', 'extends Node\nfunc _ready():\n\tOS.execute("cmd", [])\n').length > 0, 'scan blocks OS.execute');
must(p.write('evil.tscn', '[sub_resource type="GDScript" id="x"]\nscript/source = "extends Node\\nfunc _ready(): JavaScriptBridge.eval(\\"1\\")"\n').length > 0, 'scan blocks scripts embedded in scenes');
let threw = false; try { p.write('addons/ugc/ugc.gd', 'x'); } catch { threw = true; }
must(threw, 'platform plugin is protected');

const c = await p.check();
must(c.loaded && !c.errors.length, 'check loads cleanly ' + t() + ' ' + JSON.stringify(c.errors));
const b1 = await p.build();
must(b1.ok && b1.full, 'full build ' + b1.ms + 'ms ' + (b1.error || ''));
p.write('main.gd', p.read('main.gd').replace('score := 0', 'score := 0\nvar patched := true'));
const b2 = await p.build();
must(b2.ok && !b2.full && b2.ms < 2000, 'patch build ' + b2.ms + 'ms');

p.write('broken.gd', 'extends Node\nfunc f():\n\tvar x: int = "s"\n');
const c2 = await p.check();
must(c2.errors.some(e => e.file === 'broken.gd' && e.line === 3), 'check reports broken.gd:3 ' + JSON.stringify(c2.errors).slice(0, 200));
p.remove('broken.gd');

const live = new LiveGame();
const s = await live.startProject(p, 'landscape');
must(s.loaded && s.image, 'live start ' + t() + ' ' + JSON.stringify(s.errors));
const e1 = await live.eval('UGC.click_at(Vector2(640, 360))\nawait UGC.wait(0.1)\nreturn {"score": game.score, "ball": game.get_node("Ball").position, "patched": game.patched}', { frames: 4, span: 0.6 });
must(e1.ok && e1.value?.score === 1 && e1.value?.patched === true && e1.image, 'live eval ' + JSON.stringify(e1.value) + ' ' + JSON.stringify(e1.errors));
const e2 = await live.eval('return game.nope()');
must(!e2.ok && e2.errors.some(e => e.file === 'eval' && e.line === 1), 'eval error line ' + JSON.stringify(e2.errors));
if (e1.image) fs.writeFileSync(p.buildDir + '/strip.jpg', Buffer.from(e1.image, 'base64'));
live.stop();

const r = await p.selfTest({});
must(r.ok && r.result === 'win' && r.image && r.image_end, 'self-test ' + JSON.stringify({ ok: r.ok, result: r.result, checks: r.checks, errors: r.errors, ms: r.ms }));
console.log('done', t(), keep ? p.dir : '');
if (!keep) setTimeout(() => fs.rmSync(p.dir, { recursive: true, force: true }), 2000);
