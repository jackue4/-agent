import fs from 'fs';
const Q='preload("res://scripts/quality.gd").touch_active';
const ed=(f,pairs)=>{let s=fs.readFileSync(f,'utf8');for(const[a,b]of pairs){if(!s.includes(a))throw f+': '+a;s=s.replace(a,b);}fs.writeFileSync(f,s);};
ed('main.gd',[['prompt = "WASD 移动 · 走近设施按 E 使用 · Space 闪避" if selected.is_empty()','prompt = ("摇杆移动 · 走近设施点「交互」 · 「冲刺」闪避" if '+Q+' else "WASD 移动 · 走近设施按 E 使用 · Space 闪避") if selected.is_empty()'],
 ['else "[E] " + str(selected.name)','else ("「交互」 " if '+Q+' else "[E] ") + str(selected.name)']]);
ed('ui.gd',[['refs["hub_prompt"].text = prompt if not prompt.is_empty() else "靠近设施  ·  按 E 交互"','refs["hub_prompt"].text = prompt if not prompt.is_empty() else ("靠近设施  ·  点「交互」" if '+Q+' else "靠近设施  ·  按 E 交互")'],
 ['refs["blade_hint"] = _label(scene_ui,"J 射剑 · 打空后 J 召回"','refs["blade_hint"] = _label(scene_ui,"「攻击」射剑 · 打空后召回" if '+Q+' else "J 射剑 · 打空后 J 召回"'],
 ['{"empty":"剑阵已空 · 按 J 召回","recall":"召回中……"}.get(bs,"J 射剑  %d / %d" % [pips.loaded,pips.total])','{"empty":"剑阵已空 · 点攻击召回" if '+Q+' else "剑阵已空 · 按 J 召回","recall":"召回中……"}.get(bs,("射剑  %d / %d" if '+Q+' else "J 射剑  %d / %d") % [pips.loaded,pips.total])'],
 ['	var controls := "WASD','	var controls := "左侧拖动  移动\\n攻击  连刺/射剑（自动瞄准）；按住蓄力\\n投掷  长矛投掷与召回\\n冲刺  闪避\\n技能 / 绝技  英雄技能\\n交互  设施与宝箱   /   背包  构筑与收获" if '+Q+' else "WASD']]);
