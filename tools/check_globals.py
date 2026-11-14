"""Lists the client functions HarvestMate Enhanced calls that the headless
fake client (tests/support) does not define yet. Run from the repo root:

    python tools/check_globals.py
"""
import glob
import os
import re

import lupa.lua51 as L

names = {}
for f in glob.glob("HarvestMateEnhanced/**/*.lua", recursive=True):
    f = f.replace(os.sep, "/")
    if "/Data/" in f:
        continue
    src = open(f, encoding="utf-8").read()
    local = set(re.findall(r"local\s+function\s+(\w+)", src)) | set(re.findall(r"local\s+(\w+)\s*=", src))
    for m in re.finditer(r"(?<![\w.:])([A-Z][A-Za-z0-9_]+)\s*\(", src):
        n = m.group(1)
        if n not in local:
            names.setdefault(n, set()).add(os.path.basename(f))
rt = L.LuaRuntime()
rt.execute('print=function() end; dofile("tests/support/wow.lua"); dofile("tests/support/wow_extra.lua")')
for n in sorted(names):
    if rt.eval('_G["%s"]' % n) is None:
        print(n, ",".join(sorted(names[n])))
