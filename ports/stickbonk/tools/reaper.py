
import os, json
import numpy as np
from PIL import Image, ImageFilter
from collections import deque
here = r"D:\ugc-ai\ports\stickbonk\tools"
OUT = r"D:\ugc-ai\ports\stickbonk\src\art"
img = Image.open(os.path.join(here, "raw", "enemy_reaper.png")).convert("RGB")
a = np.asarray(img).astype(np.int32)
h, w, _ = a.shape
edge = np.concatenate([a[0], a[-1], a[:, 0], a[:, -1]])
bg = np.median(edge, axis=0)
dist = np.sqrt(((a - bg) ** 2).sum(-1))
cand = dist < 38
mask = np.zeros((h, w), bool)
q = deque()
for x in range(w):
    for y in (0, h - 1):
        if cand[y, x] and not mask[y, x]: mask[y, x] = True; q.append((y, x))
for y in range(h):
    for x in (0, w - 1):
        if cand[y, x] and not mask[y, x]: mask[y, x] = True; q.append((y, x))
while q:
    y, x = q.popleft()
    for dy, dx in ((1,0),(-1,0),(0,1),(0,-1)):
        ny, nx = y+dy, x+dx
        if 0 <= ny < h and 0 <= nx < w and cand[ny, nx] and not mask[ny, nx]:
            mask[ny, nx] = True; q.append((ny, nx))
# enclosed background pockets (between scythe and cloak) too
pocket = cand & ~mask & (dist < 22)
bgm = mask | pocket
alpha = np.where(bgm, 0, 255).astype(np.uint8)
al = Image.fromarray(alpha).filter(ImageFilter.MinFilter(3)).filter(ImageFilter.GaussianBlur(0.8))
rgba = img.convert("RGBA"); rgba.putalpha(al)
bb = rgba.getbbox(); rgba = rgba.crop(bb)
s = 420 / max(rgba.size)
rgba = rgba.resize((int(rgba.width * s), int(rgba.height * s)), Image.LANCZOS)
rgba.save(os.path.join(OUT, "enemy_reaper.png"))
A = np.asarray(rgba)[..., 3]
print("size", rgba.size, "opaque", round(float((A > 128).mean()), 3))
fl = Image.new("RGBA", rgba.size, (255, 255, 255, 255)); fl.putalpha(rgba.split()[3]); fl.save(os.path.join(OUT, "enemy_reaper_flash.png"))
src = open(r"D:\GodotProjects\StickBonk\tools\process_assets.py", encoding="utf8").read()
ns = {"np": np}; exec(src[src.index("def hull_pts"):src.index("hulls = {}")], ns)
hp = os.path.join(OUT, "hulls.json"); H = json.load(open(hp))
H["enemy_reaper"] = [list(map(float, p)) for p in ns["hull_pts"](A)]
json.dump(H, open(hp, "w")); print("hull", len(H["enemy_reaper"]))
