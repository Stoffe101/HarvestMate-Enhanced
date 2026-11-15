"""Draws HarvestMate Enhanced's interface as HTML pages and screenshots, to look at without the game.

    python tools/ui_preview.py                 # every screen and state, HTML into build/preview/
    python tools/ui_preview.py finder          # only states whose name contains "finder"
    python tools/ui_preview.py --shots         # also PNG screenshots, checks and the review gallery
    python tools/ui_preview.py --approve       # make the current screenshots the baseline
    python tools/ui_preview.py --shots --strict    # exit 1 when a check fails (overlap, cut, cramped)

Runs the real addon code in the test client (tests/support), with tools/preview/render.lua
recording what drawing needs and tools/preview/scenes.lua choosing the screens and states (a
level-41 Skinning character, realistic prices, sessions, goals and routes; several screen sizes and
UI scales). Screenshots are taken by Chrome or Edge in headless mode: no window opens and focus
never moves. Each state is checked for overlapping text, text cut short, text tight enough to be cut
in the game, cramped buttons, tiny or dim text, missing addon art and frames off the screen.
Differences against the approved baseline (build/preview/baseline/) are measured per pixel.

These are renders of the layout in a stand-in client, not screenshots of the game. Needs lupa (as
the tests) and Pillow (art and diffs). build/ is git-ignored: screenshots are never committed.
"""
import concurrent.futures
import glob
import html
import json
import os
import shutil
import subprocess
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import run_tests  # noqa: E402

ROOT = run_tests.ROOT
OUT = os.path.join(ROOT, "build", "preview")
SHOTS = os.path.join(OUT, "shots")
BASE = os.path.join(OUT, "baseline")
BROWSERS = [
    r"C:\Program Files\Google\Chrome\Application\chrome.exe",
    r"C:\Program Files (x86)\Google\Chrome\Application\chrome.exe",
    r"C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe",
    "/usr/bin/google-chrome", "/usr/bin/chromium", "/usr/bin/chromium-browser",
    "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome",
]


def fonts():
    """The bundled Inter, for the browser."""
    src = os.path.join(ROOT, "HarvestMateEnhanced", "Media", "Fonts")
    dst = os.path.join(OUT, "media", "fonts")
    os.makedirs(dst, exist_ok=True)
    for name in os.listdir(src):
        if name.endswith(".ttf"):
            shutil.copy(os.path.join(src, name), os.path.join(dst, name))


def media(rt):
    """Addon .tga art as PNG, where Pillow is available."""
    try:
        from PIL import Image
    except ImportError:
        return
    table = rt.eval("RENDER.MEDIA")
    for sub in ("", "UI"):
        src = os.path.join(ROOT, "HarvestMateEnhanced", "Media", sub)
        dst = os.path.join(OUT, "media", sub)
        os.makedirs(dst, exist_ok=True)
        for name in os.listdir(src):
            if name.lower().endswith(".tga"):
                png = os.path.splitext(name)[0] + ".png"
                try:
                    Image.open(os.path.join(src, name)).save(os.path.join(dst, png))
                except OSError:
                    continue
                rel = (sub + "/" if sub else "") + os.path.splitext(name)[0]
                table[("interface/addons/harvestmateenhanced/media/" + rel).lower()] = "media/" + rel + ".png"


def render(only):
    import lupa.lua51 as L  # noqa: N811
    os.chdir(ROOT)
    os.makedirs(OUT, exist_ok=True)
    for old in glob.glob(os.path.join(OUT, "*.html")):
        os.remove(old)
    rt = L.LuaRuntime(unpack_returned_tuples=True)
    lines = []
    rt.globals().print = lambda *a: lines.append(" ".join(str(x) for x in a))
    rt.execute(run_tests.PRELUDE.replace("REAL_PRINT = realPrint", ""))
    rt.execute('dofile("tools/preview/render.lua")')
    media(rt)
    fonts()
    rt.globals().PREVIEW_OUT = OUT.replace(os.sep, "/")
    if only:
        rt.globals().PREVIEW_ONLY = only
    rt.execute('dofile("tools/preview/scenes.lua")')
    for line in lines:
        if not line.startswith("STEP"):
            print(line)
    errors = rt.eval("ERRORS")
    if errors:
        for i in range(1, len(errors) + 1):
            print("error handler:", errors[i])
    with open(os.path.join(OUT, "manifest.json"), encoding="utf-8") as f:
        return json.load(f)


def browser():
    for b in BROWSERS:
        if os.path.exists(b):
            return b
    return shutil.which("chrome") or shutil.which("chromium") or shutil.which("msedge")


def shoot(exe, state):
    """One state: a PNG (headless, no window) and the checks' results from the page."""
    page = "file:///" + os.path.join(OUT, state["name"] + ".html").replace(os.sep, "/")
    png = os.path.join(SHOTS, state["name"] + ".png")
    w, h = int(state["w"] + 0.5), int(state["h"] + 0.5)
    base = [exe, "--headless=new", "--disable-gpu", "--hide-scrollbars", "--mute-audio", "--no-first-run",
            "--no-default-browser-check", "--allow-file-access-from-files", "--virtual-time-budget=4000",
            "--user-data-dir=" + os.path.join(OUT, ".chrome", state["name"])]   # one profile each: they run side by side
    kw = dict(capture_output=True, timeout=90, creationflags=getattr(subprocess, "CREATE_NO_WINDOW", 0))
    # Headless Chrome keeps part of the window for itself: shoot taller, then crop to the state.
    subprocess.run(base + ["--window-size=%d,%d" % (w, h + 160), "--screenshot=" + png, page.replace(".html", ".html?clean")], **kw)
    try:
        from PIL import Image
        im = Image.open(png)
        im.crop((0, 0, min(w, im.size[0]), min(h, im.size[1]))).save(png)
    except (ImportError, OSError):
        pass
    dom = subprocess.run(base + ["--dump-dom", page], **kw).stdout.decode("utf-8", "replace")
    result = {}
    start = dom.find('<pre id="result"')
    if start >= 0:
        body = dom[dom.find(">", start) + 1:dom.find("</pre>", start)]
        try:
            result = json.loads(html.unescape(body))
        except ValueError:
            result = {"error": "unreadable result"}
    else:
        result = {"error": "the page did not finish its checks"}
    return state["name"], result


def diff(name):
    """Share of pixels that differ from the baseline, or None without one."""
    try:
        from PIL import Image, ImageChops
    except ImportError:
        return None
    a, b = os.path.join(SHOTS, name + ".png"), os.path.join(BASE, name + ".png")
    if not (os.path.exists(a) and os.path.exists(b)):
        return None
    ia, ib = Image.open(a).convert("RGB"), Image.open(b).convert("RGB")
    if ia.size != ib.size:
        return 1.0
    d = ImageChops.difference(ia, ib).convert("L").point(lambda v: 255 if v > 24 else 0)
    changed = sum(d.histogram()[255:])
    out = os.path.join(SHOTS, name + ".diff.png")
    if changed:
        mask = d.convert("1")
        red = Image.new("RGB", ia.size, (255, 40, 40))
        Image.composite(red, ia.point(lambda v: v // 3), mask).save(out)
    elif os.path.exists(out):
        os.remove(out)
    return changed / float(ia.size[0] * ia.size[1])


SEVERE = ("overlap", "cut", "narrow", "error")


def gallery(states, results):
    """build/preview/review.html: every state, its checks, its change against the baseline."""
    rows, groups = [], {}
    for s in states:
        groups.setdefault(s.get("group", "Other"), []).append(s)
    total = {k: 0 for k in ("overlap", "cut", "tight", "narrow", "tiny", "dim", "other")}
    for g, items in groups.items():
        rows.append("<h2>%s</h2><div class=grid>" % html.escape(g))
        for s in items:
            r = results.get(s["name"], {})
            badges = []
            for k in total:
                n = len(r.get(k, []))
                total[k] += n
                if n:
                    badges.append('<span class="b %s">%d %s</span>' % ("bad" if k in SEVERE else "warn", n, k))
            if r.get("error"):
                badges.append('<span class="b bad">%s</span>' % html.escape(r["error"]))
            d = r.get("diff")
            if d is not None:
                badges.append('<span class="b %s">%s vs baseline</span>' % ("warn" if d > 0.002 else "ok",
                                                                           "%.1f%% changed" % (d * 100) if d else "unchanged"))
            if not badges:
                badges.append('<span class="b ok">all checks pass</span>')
            details = "".join("<li><b>%s</b>: %s</li>" % (k, html.escape(" | ".join(
                " <> ".join(x) if isinstance(x, list) else x for x in r.get(k, [])))) for k in total if r.get(k))
            img = "shots/%s.png" % s["name"]
            dimg = "shots/%s.diff.png" % s["name"]
            difflink = ' · <a href="%s">diff</a>' % dimg if os.path.exists(os.path.join(OUT, dimg)) else ""
            rows.append('<figure><a href="%s"><img loading=lazy src="%s"></a><figcaption><b>%s</b><br><small>%s · %s</small>'
                        '<div>%s</div><small><a href="%s.html">checked page</a>%s</small>%s</figcaption></figure>' % (
                            img, img, html.escape(s["title"]), html.escape(s.get("screen", "")), html.escape(s["name"]),
                            " ".join(badges), s["name"], difflink, "<ul>%s</ul>" % details if details else ""))
        rows.append("</div>")
    summary = ", ".join("%d %s" % (v, k) for k, v in total.items())
    page = """<!doctype html><html><head><meta charset=utf-8><title>HME visual review</title><style>
body{background:#111310;color:#e6e4dc;font:14px/1.45 Segoe UI,Arial,sans-serif;margin:24px}
h1{font-weight:600}h2{margin:28px 0 10px;font-weight:600;color:#cca66b}
.grid{display:grid;grid-template-columns:repeat(auto-fill,minmax(420px,1fr));gap:18px}
figure{margin:0;background:#1c1f1a;border:1px solid #2c3029;border-radius:8px;overflow:hidden}
figure img{width:100%%;display:block;background:#0b0c0a}figcaption{padding:10px 12px}
small{color:#999b8f}a{color:#8fcc5c}.b{display:inline-block;border-radius:9px;padding:1px 8px;margin:4px 4px 0 0;font-size:12px}
.ok{background:#25331d;color:#a7d77a}.warn{background:#3a2f17;color:#f5c45f}.bad{background:#3d1b1a;color:#f28a84}
ul{margin:6px 0 0 18px;padding:0;font-size:12px;color:#c7c7ba}.note{max-width:900px;color:#c7c7ba}
</style></head><body><h1>HarvestMate Enhanced: visual review</h1>
<p class=note>Renders of the addon's real layout code in a stand-in client (fonts: the bundled Inter;
game textures: placeholders; spell icons from a public CDN). They are not game screenshots and do not
prove the look in WoW Forever: docs/MANUAL_TESTING.md lists what to check in the client.
Checks: overlapping text, text cut short, text within 8%% of its box (may be cut in the game), cramped
buttons, text under 10.5 px on screen, dim text, missing addon art, frames off the screen.</p>
<p><b>%d states.</b> %s.</p>%s</body></html>""" % (len(states), summary, "\n".join(rows))
    with open(os.path.join(OUT, "review.html"), "w", encoding="utf-8") as f:
        f.write(page)
    with open(os.path.join(OUT, "report.json"), "w", encoding="utf-8") as f:
        json.dump({"states": states, "results": results, "totals": total}, f, indent=1)
    return total


def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    flags = {a for a in sys.argv[1:] if a.startswith("--")}
    if "--approve" in flags:
        if os.path.exists(BASE):
            shutil.rmtree(BASE)
        os.makedirs(BASE)
        n = 0
        for png in glob.glob(os.path.join(SHOTS, "*.png")):
            if not png.endswith(".diff.png"):
                shutil.copy(png, BASE)
                n += 1
        print("approved %d screenshots as the baseline in %s" % (n, BASE))
        return 0
    states = render(args[0] if args else None)
    print("wrote %d states to %s" % (len(states), OUT))
    if "--shots" not in flags:
        print("open", os.path.join(OUT, "index.html"))
        return 0
    exe = browser()
    if not exe:
        print("no Chrome or Edge found: HTML only")
        return 0
    os.makedirs(SHOTS, exist_ok=True)
    results = {}
    with concurrent.futures.ThreadPoolExecutor(max_workers=4) as pool:
        for name, res in pool.map(lambda s: shoot(exe, s), states):
            res["diff"] = diff(name)
            results[name] = res
    total = gallery(states, results)
    print("checks:", ", ".join("%d %s" % (v, k) for k, v in total.items()))
    for s in states:
        r = results[s["name"]]
        bad = {k: r.get(k) for k in SEVERE if r.get(k)}
        if bad:
            print("  %s: %s" % (s["name"], json.dumps(bad)[:300]))
    print("review", os.path.join(OUT, "review.html"))
    if "--strict" in flags and any(total[k] for k in ("overlap", "cut", "narrow")):
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
