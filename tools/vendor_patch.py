"""Applies HarvestMate Enhanced's declared patches to freshly copied upstream
files. Every patch is listed in UPSTREAM.md. Idempotent. From the repo root:

    python tools/vendor_patch.py
"""
import glob
import re

A = "HarvestMateEnhanced"
BS = chr(92)  # one backslash; the Lua sources write it doubled inside strings
LUA_SEP = BS + BS


def patch(path, fn):
    with open(path, encoding="utf-8", newline="") as f:
        text = f.read()
    new = fn(text)
    if new != text:
        with open(path, "w", encoding="utf-8", newline="") as f:
            f.write(new)
        print("patched", path)


# P1 (HarvestMate modules and locales): share the addon's private table;
# HarvestMate's own namespace lives at ns.HG.
P1 = "local _, ns = ... local HG = ns.HG -- HME patch P1"
for path in glob.glob(A + "/Gather/*.lua") + glob.glob(A + "/Gather/Locale/*.lua"):
    patch(path, lambda t: re.sub(r"\Alocal _, HG = \.\.\.", P1, t))

# P2 (Gatherpedia Glimmer): texture paths point into this addon's Media folder,
# where the files carry a GP_ prefix.
OLD = "AddOns" + LUA_SEP + "Gatherpedia" + LUA_SEP + "Media" + LUA_SEP
NEW = "AddOns" + LUA_SEP + "HarvestMateEnhanced" + LUA_SEP + "Media" + LUA_SEP + "GP_"
for path in [A + "/Glimmer/Sparkles.lua", A + "/Glimmer/SparklesCloud.lua"]:
    patch(path, lambda t: t.replace(OLD, NEW))

# P3 (HarvestMate Bind.lua): the key-capture window gets HME's own global name,
# so it can never clash with HarvestMate's if both are installed.
patch(A + "/Gather/Bind.lua",
      lambda t: t.replace('CreateFrame("Frame", "HarvestMateKeyCapture"', 'CreateFrame("Frame", "HarvestMateEnhancedKeyCapture"'))
