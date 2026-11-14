"""Draws HarvestMate Enhanced's interface as HTML pages, to look at without the game.

    python tools/ui_preview.py            # every screen, into build/preview/
    python tools/ui_preview.py finder     # only screens whose name contains "finder"

Runs the real addon code in the test client (tests/support), with
tools/preview/render.lua recording what drawing needs, and tools/preview/scenes.lua
choosing the screens. Open build/preview/index.html in a browser. These are renders of
the layout in a stand-in client, not screenshots of the game. Needs lupa (as the tests);
Pillow, if installed, turns the addon's .tga art into images the browser can show.
Nothing is opened on screen.
"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import run_tests  # noqa: E402

ROOT = run_tests.ROOT
OUT = os.path.join(ROOT, "build", "preview")


def fonts():
    """The bundled Inter, for the browser."""
    import shutil
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
    src = os.path.join(ROOT, "HarvestMateEnhanced", "Media")
    dst = os.path.join(OUT, "media")
    os.makedirs(dst, exist_ok=True)
    table = rt.eval("RENDER.MEDIA")
    for name in os.listdir(src):
        if name.lower().endswith(".tga"):
            png = os.path.splitext(name)[0] + ".png"
            try:
                Image.open(os.path.join(src, name)).save(os.path.join(dst, png))
            except OSError:
                continue
            key = ("interface/addons/harvestmateenhanced/media/" + os.path.splitext(name)[0]).lower()
            table[key] = "media/" + png


def main():
    import lupa.lua51 as L  # noqa: N811
    os.chdir(ROOT)
    os.makedirs(OUT, exist_ok=True)
    rt = L.LuaRuntime(unpack_returned_tuples=True)
    lines = []
    rt.globals().print = lambda *a: lines.append(" ".join(str(x) for x in a))
    rt.execute(run_tests.PRELUDE.replace("REAL_PRINT = realPrint", ""))
    rt.execute('dofile("tools/preview/render.lua")')
    media(rt)
    fonts()
    rt.globals().PREVIEW_OUT = OUT.replace(os.sep, "/")
    if len(sys.argv) > 1:
        rt.globals().PREVIEW_ONLY = sys.argv[1]
    rt.execute('dofile("tools/preview/scenes.lua")')
    for line in lines:
        if not line.startswith("STEP"):
            print(line)
    errors = rt.eval("ERRORS")
    if errors:
        for i in range(1, len(errors) + 1):
            print("error handler:", errors[i])
    print("open", os.path.join(OUT, "index.html"))


if __name__ == "__main__":
    main()
