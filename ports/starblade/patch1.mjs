import fs from 'fs';
const d='src/scripts/';
function patch(f, pairs){ let s=fs.readFileSync(d+f,'utf8'); for(const [a,b] of pairs){ if(!s.includes(a)) throw new Error(f+' missing: '+a.slice(0,80)); s=s.split(a).join(b);} fs.writeFileSync(d+f,s); }
const Q='preload("res://scripts/quality.gd")';
// main.gd

patch('main.gd',[
 ['const FlyingBlades = preload("res://scripts/flying_blades.gd")','const FlyingBlades = preload("res://scripts/flying_blades.gd")\nconst Quality = preload("res://scripts/quality.gd")\nconst TouchControls = preload("res://scripts/touch_controls.gd")\nvar touch_controls'],
 ['	env.glow_enabled = true\n','	env.glow_enabled = not Quality.low()\n'],
 ['	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY\n','	env.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED if Quality.low() else Environment.REFLECTION_SOURCE_SKY\n	if Quality.low(): env.sky = null; env.tonemap_mode = Environment.TONE_MAPPER_LINEAR\n'],
 ['	key.shadow_enabled = true\n','	key.shadow_enabled = not Quality.low()\n'],
 ['	var scenery_focus := preload("res://scripts/scenery_focus.gd").new()\n	camera.add_child(scenery_focus)\n	scenery_focus.configure(world)\n','	if not Quality.low():\n		var scenery_focus := preload("res://scripts/scenery_focus.gd").new()\n		camera.add_child(scenery_focus)\n		scenery_focus.configure(world)\n'],
 ['	art_direction.configure(camera,env_node)\n','	art_direction.configure(camera,env_node)\n	if Quality.low():\n		art_direction.set_enabled(false)\n		art_direction.set_process(false)\n		vfx.max_effects = 14\n	touch_controls = TouchControls.new()\n	add_child(touch_controls)\n	touch_controls.bind(self)\n'],
 ['	var glow := OmniLight3D.new()\n	glow.name = "HeroLight"','	var glow := OmniLight3D.new()\n	glow.visible = not Quality.low()\n	glow.name = "HeroLight"'],
 ['		env.fog_enabled = density > 0.0\n','		env.fog_enabled = density > 0.0 and not Quality.low()\n'],
 ['(("stage_%d" if "--legacy-arena" in OS.get_cmdline_user_args() else "dungeon_%d") % stage)','("dungeon_%d" % stage)'],
 ['		"quit": get_tree().quit()','		"quit":\n			if not OS.has_feature("web"): get_tree().quit()'],
 ['	if effects.size() > 180: return','	if effects.size() > (40 if Quality.low() else 180): return'],
 ['	particles.amount = mini(64,count)','	particles.amount = mini(16 if Quality.low() else 64,count)'],
]);
patch('ui.gd',[[`	var f := SystemFont.new()\n	f.font_names = PackedStringArray(["Microsoft YaHei", "Noto Sans CJK SC", "Arial"])\n	ui_font = f`,`	ui_font = ${Q}.font()`],
 ['	if DisplayServer.get_name() != "headless":\n		var screen: Image','	if DisplayServer.get_name() != "headless" and not '+Q+'.low():\n		var screen: Image']]);
patch('damage_numbers.gd',[['var _font: SystemFont','var _font: Font'],[`	_font = SystemFont.new()\n	_font.font_names = PackedStringArray(["Bahnschrift","Microsoft YaHei","Arial"])\n	_font.font_weight = 800`,`	_font = ${Q}.font()`],
 ['	while _live.size() >= MAX_ITEMS: _remove(0)','	while _live.size() >= (24 if '+Q+'.low() else MAX_ITEMS): _remove(0)']]);
patch('boon_runtime.gd',[['label.font = SystemFont.new(); label.font.font_names = PackedStringArray(["Microsoft YaHei"])','label.font = '+Q+'.font()']]);
patch('world.gd',[[`	var font := SystemFont.new()\n	font.font_names = PackedStringArray(["Microsoft YaHei UI","Microsoft YaHei","Noto Sans CJK SC"])\n	label.font = font`,`	label.font = ${Q}.font()`]]);
patch('combat_vfx.gd',[['	emitter.amount = clampi(count,3,40)','	emitter.amount = clampi(count,3,18 if '+Q+'.low() else 40)']]);
patch('room_reward.gd',[['	p.amount = count','	p.amount = mini(count,14) if '+Q+'.low() else count']]);
// point lights: skip on low
for (const f of ['world.gd','desert_world.gd']){ let s=fs.readFileSync(d+f,'utf8'); let n=0; s=s.replace(/(var (\w+) ?:?= ?OmniLight3D\.new\(\))/g,(x,all,v)=>{n++;return all+'; '+v+'.visible = not '+Q+'.low()';}); console.log(f,n); fs.writeFileSync(d+f,s);}
console.log('done');

