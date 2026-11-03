# PaperBlade platform cover

- `cover.jpg` is a crop of the local game capture `shots/final_gpu_4later.png` (1280 × 720).
- Crop: x=0, y=80, width=1280, height=640; resized to 960 × 480 JPEG. This removes the platform exit button and the top HUD while keeping the real character, enemies, arena and attacks.
- No generated art is used. The imported game's original asset ownership is unchanged.
- Import cover priority: explicit `COVER`, existing published cover, draft cover, bundled `cover.jpg`.
- A successful first import copies the bundled image to `/covers/<project-id>_cover.jpg`; a missing bundled image fails explicitly instead of publishing an empty cover.
