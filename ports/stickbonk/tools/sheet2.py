
import os
from PIL import Image, ImageDraw
d=r"D:\ugc-ai\ports\stickbonk\src\art"
fs=[f for f in ["enemy_slimeking.png","enemy_batqueen.png","prop_bamboo.png","prop_obsidian.png","prop_icecrystal.png","hero_red.png","hero_sumo.png","hero_ninja.png","hero_drunk.png","weapon_gloves.png","weapon_nunchaku.png","weapon_hammer.png","weapon_staff.png","ground_bamboo.png","ground_volcano.png","ground_ice.png","icons/frost.png","icons/combo_quake.png"]]
W=200;cols=6;rows=3
sh=Image.new('RGB',(W*cols,(W+20)*rows),(242,220,168))
dr=ImageDraw.Draw(sh)
for i,f in enumerate(fs):
    im=Image.open(os.path.join(d,f)).convert('RGBA');im.thumbnail((W,W))
    x,y=(i%cols)*W,(i//cols)*(W+20)
    sh.paste(im,(x,y),im);dr.text((x+2,y+W+4),f,fill='black')
sh.save(r"D:\ugc-ai\ports\stickbonk\tools\sheet2.jpg",quality=85)
