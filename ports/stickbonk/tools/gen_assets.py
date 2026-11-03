
import json, sys, time, os, re, urllib.request, concurrent.futures as cf
sys.path.insert(0, os.path.dirname(__file__))
from aigc import MCP

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
RAW = os.path.join(os.path.dirname(os.path.abspath(__file__)), "raw")
os.makedirs(RAW, exist_ok=True)

STYLE = ("American comic book hand-drawn ink illustration, bold thick black brush outlines with varying line weight, "
         "flat vivid cel colors, halftone dot shading and ink hatching in the shadows, punchy 1990s cartoon energy")
SPRITE = ("single character only, full body fully visible and not cropped, centered, generous margin, "
          "pure flat white background, no ground, no cast shadow, no text, no border, no speech bubble")

def load_manifest():
    with open(os.path.join(os.path.dirname(os.path.abspath(__file__)), "manifest2.json"), encoding="utf-8") as f:
        return json.load(f)

def submit(m, a):
    prompt = a["prompt"]
    if a.get("sprite", True):
        prompt = prompt + ". " + SPRITE
    prompt = prompt + ". Style: " + STYLE + "."
    args = {"prompt": prompt, "provider": "gpt-image-2", "width": a.get("w", 1024), "height": a.get("h", 1024),
            "negative_prompt": "text, letters, watermark, signature, photo, 3d render, blurry, multiple characters, frame"}
    r = m.call("generate_image_async", args)
    tid = re.search(r"任务ID:\s*(\S+)", r if isinstance(r, str) else json.dumps(r, ensure_ascii=False))
    return tid.group(1) if tid else None

def poll(m, tid):
    r = m.call("get_task_status", {"task_id": tid})
    s = r if isinstance(r, str) else json.dumps(r, ensure_ascii=False)
    st = re.search(r"状态:\s*(\S+)", s)
    url = re.search(r"(https://\S+?\.(?:png|jpg|jpeg|webp))", s)
    return (st.group(1) if st else "?"), (url.group(1) if url else None), s

def main():
    only = set(sys.argv[1:])
    man = load_manifest()
    m = MCP()
    jobs = {}
    for a in man:
        if only and a["id"] not in only:
            continue
        out = os.path.join(RAW, a["id"] + ".png")
        if os.path.exists(out) and not only:
            continue
        for attempt in range(3):
            try:
                tid = submit(m, a)
                if tid:
                    jobs[a["id"]] = tid
                    print("submitted", a["id"], tid, flush=True)
                    break
            except Exception as e:
                print("submit err", a["id"], e, flush=True)
                time.sleep(3)
    t0 = time.time()
    pending = dict(jobs)
    while pending and time.time() - t0 < 1500:
        time.sleep(10)
        for aid, tid in list(pending.items()):
            try:
                st, url, s = poll(m, tid)
            except Exception as e:
                print("poll err", aid, e, flush=True)
                continue
            if st == "completed" and url:
                urllib.request.urlretrieve(url, os.path.join(RAW, aid + ".png"))
                print("done", aid, flush=True)
                del pending[aid]
            elif st in ("failed", "error"):
                print("FAILED", aid, s[:300], flush=True)
                del pending[aid]
    print("remaining", list(pending.keys()))

main()