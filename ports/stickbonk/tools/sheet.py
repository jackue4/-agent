
import os,sys
from PIL import Image, ImageDraw
d=r"D:\ugc-ai\ports\stickbonk\tools\raw"
fs=sorted(f for f in os.listdir(d) if f.endswith('.png'))
W=200;cols=6;rows=(len(fs)+cols-1)//cols
sh=Image.new('RGB',(W*cols,(W+20)*rows),'gray')
dr=ImageDraw.Draw(sh)
for i,f in enumerate(fs):
    im=Image.open(os.path.join(d,f)).convert('RGB');im.thumbnail((W,W))
    x,y=(i%cols)*W,(i//cols)*(W+20)
    sh.paste(im,(x,y));dr.text((x+2,y+W+4),f[:-4],fill='white')
sh.save(r"D:\ugc-ai\ports\stickbonk\tools\sheet.jpg",quality=85)
