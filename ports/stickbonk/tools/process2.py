
"""Process expansion art (tools/raw) into src/art."""
import os, sys, json
import numpy as np
from PIL import Image, ImageDraw
sys.path.insert(0, r"D:\GodotProjects\StickBonk\tools")
import importlib.util
spec = importlib.util.spec_from_file_location("pa_src", r"D:\GodotProjects\StickBonk\tools\process_assets.py")
# only import helper funcs (module runs main code at import) -> exec selected source
src = open(r"D:\GodotProjects\StickBonk\tools\process_assets.py", encoding="utf8").read()
helpers = src.split("os.makedirs(os.path.join(OUT")[0]
ns = {"__file__": r"D:\GodotProjects\StickBonk\tools\process_assets.py"}
exec(helpers, ns)
knockout, trim, fit, remove_small = ns["knockout"], ns["trim"], ns["fit"], ns["remove_small"]
hull_src = src[src.index("def hull_pts"):src.index("hulls = {}")]
exec(hull_src, ns)
hull_pts = ns["hull_pts"]

HERE = os.path.dirname(os.path.abspath(__file__))
RAW = os.path.join(HERE, "raw")
OUT = os.path.join(os.path.dirname(HERE), "src", "art")
SPEC = {"enemy_slimeking": 400, "enemy_batqueen": 380, "prop_bamboo": 130, "prop_obsidian": 104, "prop_icecrystal": 110,
        "hero_red": 300, "hero_sumo": 300, "hero_ninja": 300, "hero_drunk": 300,
        "weapon_gloves": 150, "weapon_nunchaku": 150, "weapon_hammer": 150, "weapon_staff": 150}
PAPER = np.array([242, 220, 168], np.float32)

def sprite(i):
    img = Image.open(os.path.join(RAW, i + ".png")).convert("RGB")
    rgba = trim(remove_small(knockout(img)))
    rgba = fit(rgba, SPEC[i], SPEC[i] * 1.8)
    rgba.save(os.path.join(OUT, i + ".png"))

def icon(i):
    img = Image.open(os.path.join(RAW, i + ".png")).convert("RGB")
    rgba = trim(knockout(img))
    s = max(rgba.size)
    sq = Image.new("RGBA", (s, s), (0, 0, 0, 0))
    sq.paste(rgba, ((s - rgba.width) // 2, (s - rgba.height) // 2))
    sq = sq.resize((160, 160), Image.LANCZOS)
    m = Image.new("L", (640, 640), 0)
    ImageDraw.Draw(m).ellipse((6, 6, 634, 634), fill=255)
    m = m.resize((160, 160), Image.LANCZOS)
    a = np.minimum(np.asarray(sq.split()[3]), np.asarray(m))
    sq.putalpha(Image.fromarray(a.astype(np.uint8)))
    sq.save(os.path.join(OUT, "icons", i[5:] + ".png"))

def ground(i, mix):
    img = Image.open(os.path.join(RAW, i + ".png")).convert("RGB")
    w, h = img.size
    a = np.asarray(img).astype(np.float32)
    off = np.roll(np.roll(a, h // 2, 0), w // 2, 1)
    yy, xx = np.mgrid[0:h, 0:w]
    dx = np.abs(xx - w / 2) / (w / 2); dy = np.abs(yy - h / 2) / (h / 2)
    m = np.clip(np.maximum(dx, dy) * 1.6 - 0.6, 0, 1)[..., None]
    out = a * (1 - m) + off * m
    # soften toward a light tone so fighters & ink stay readable
    tone = out.mean(axis=2, keepdims=True)
    out = out * 0.75 + tone * 0.25
    out = out * (1 - mix) + PAPER * mix if i != "ground_ice" else out * (1 - mix) + np.array([235, 244, 250], np.float32) * mix
    Image.fromarray(np.clip(out, 0, 255).astype(np.uint8)).resize((512, 512), Image.LANCZOS).save(os.path.join(OUT, i + ".png"))

for i in SPEC: sprite(i)
for f in os.listdir(RAW):
    if f.startswith("icon_"): icon(f[:-4])
ground("ground_bamboo", 0.45); ground("ground_volcano", 0.30); ground("ground_ice", 0.35)
bg = Image.open(os.path.join(RAW, "dojo_bg.png")).convert("RGB")
fit(bg, 900, 1600).save(os.path.join(OUT, "dojo_bg.jpg"), quality=88)
hp = os.path.join(OUT, "hulls.json")
hulls = json.load(open(hp))
for i in SPEC:
    if i.startswith("hero_") or i.startswith("weapon_"): continue
    im = Image.open(os.path.join(OUT, i + ".png")).convert("RGBA")
    a = np.asarray(im)[..., 3]
    fl = np.zeros((*a.shape, 4), np.uint8); fl[..., :3] = 255; fl[..., 3] = a
    Image.fromarray(fl, "RGBA").save(os.path.join(OUT, i + "_flash.png"))
    hulls[i] = hull_pts(a)
json.dump(hulls, open(hp, "w"))
print("ok")
