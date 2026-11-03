import fs from 'fs';
let s=fs.readFileSync('touch_controls.gd','utf8');
const rep=(a,b)=>{ if(!s.includes(a)) throw new Error('miss '+a.slice(0,60)); s=s.replace(a,b); };
rep(`		{"action":"dash","pos":base+Vector2(-150,22)*u,"r":44*u,"label":"冲刺","color":Color("62e5eb"),"hold":false},
		{"action":"special","pos":base+Vector2(-62,-118)*u,"r":40*u,"label":"投掷","color":Color("b8afff"),"hold":true},
		{"action":"interact","pos":base+Vector2(-200,-80)*u,"r":36*u,"label":"交互","color":Color("ff9e50"),"hold":false},`,
`		{"action":"dash","pos":base+Vector2(-155,25)*u,"r":44*u,"label":"冲刺","color":Color("62e5eb"),"hold":false,"tile":"dash"},
		{"action":"special","pos":base+Vector2(-120,-110)*u,"r":40*u,"label":"投掷","color":Color("b8afff"),"hold":true,"tile":"special"},
		{"action":"hero_primary","pos":base+Vector2(-10,-172)*u,"r":40*u,"label":"技能","color":Color("ffd36b"),"hold":false,"tile":"primary"},
		{"action":"hero_secondary","pos":base+Vector2(96,-126)*u,"r":36*u,"label":"绝技","color":Color("ff7a9c"),"hold":false,"tile":"secondary"},
		{"action":"interact","pos":base+Vector2(-262,-40)*u,"r":36*u,"label":"交互","color":Color("ff9e50"),"hold":false},`);
rep(`		for id in ["melee","special","dash"]:`,`		for id in ["melee","special","dash","primary","secondary"]:`);
rep(`		var cd := 0.0
		if b.action == "dash": cd = float(g.dash_cd)`,`		var cd := 0.0
		var cd_max := 1.0
		if b.has("tile") and g.ui != null:
			var t = g.ui.refs.get("tile_"+str(b.tile))
			if t != null and is_instance_valid(t): cd = float(t.cooldown); cd_max = maxf(.01,float(t.duration))`);
rep(`clampf(cd/1.0,0,1)`,`clampf(cd/cd_max,0,1)`);
rep(`			var hint := Vector2(150*u, _last_layout.y-150*u)`,`			var hint := Vector2(160*u, _last_layout.y-200*u)`);
fs.writeFileSync('touch_controls.gd',s);
let ui=fs.readFileSync('ui.gd','utf8');
const a='		_label(scene_ui,"WASD  移动     SPACE  冲刺     E  交互"';
if(!ui.includes(a)) throw 'ui';
ui=ui.replace(a,'		_label(scene_ui,"左侧拖动 移动     冲刺     交互" if preload("res://scripts/quality.gd").touch_active else "WASD  移动     SPACE  冲刺     E  交互"');
ui=ui.replace('"靠近设施  ·  按 E 交互"','"靠近设施  ·  点「交互」" if preload("res://scripts/quality.gd").touch_active else "靠近设施  ·  按 E 交互"');
fs.writeFileSync('ui.gd',ui);
