import fs from 'fs';
const d='src/scripts/';
function patch(f, pairs){ let s=fs.readFileSync(d+f,'utf8'); for(const [a,b] of pairs){ if(!s.includes(a)) throw new Error(f+' missing: '+a.slice(0,80)); s=s.split(a).join(b);} fs.writeFileSync(d+f,s); }
const Q='preload("res://scripts/quality.gd")';
// main.gd

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

