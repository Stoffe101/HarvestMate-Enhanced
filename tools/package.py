"""Builds the installable ZIP: one folder, HarvestMateEnhanced/, ready to unzip
into World of Warcraft/_forever_/Interface/AddOns/.

    python tools/package.py            # dist/HarvestMateEnhanced-<version>.zip
    python tools/package.py --check    # build, then verify the archive

The archive holds exactly the addon folder plus README, THIRD_PARTY and the
licenses inside it. Development files (tests, tools, upstream sources, docs)
are never included. Every file named in the .toc must be present.
"""
import os
import re
import sys
import zipfile

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ADDON = "HarvestMateEnhanced"
EXTRA = ["README.md", "THIRD_PARTY.md", "LICENSE", "CHANGELOG.md"]


def version():
    toc = open(os.path.join(ROOT, ADDON, ADDON + ".toc"), encoding="utf-8").read()
    m = re.search(r"^## Version:\s*(\S+)", toc, re.M)
    return m.group(1) if m else "dev"


def toc_files():
    toc = open(os.path.join(ROOT, ADDON, ADDON + ".toc"), encoding="utf-8").read()
    out = []
    for line in toc.splitlines():
        line = line.strip()
        if line and not line.startswith("#"):
            out.append(line.replace("\\", "/"))
    return out


def build():
    os.makedirs(os.path.join(ROOT, "dist"), exist_ok=True)
    path = os.path.join(ROOT, "dist", "%s-%s.zip" % (ADDON, version()))
    missing = [f for f in toc_files() if not os.path.isfile(os.path.join(ROOT, ADDON, f))]
    if missing:
        sys.exit("files named in the .toc are missing: " + ", ".join(missing))
    with zipfile.ZipFile(path, "w", zipfile.ZIP_DEFLATED) as z:
        for base, _, files in os.walk(os.path.join(ROOT, ADDON)):
            for name in sorted(files):
                full = os.path.join(base, name)
                rel = os.path.relpath(full, ROOT).replace(os.sep, "/")
                z.write(full, rel)
        for extra in EXTRA:
            full = os.path.join(ROOT, extra)
            if os.path.isfile(full):
                z.write(full, ADDON + "/" + extra)
    return path


def check(path):
    with zipfile.ZipFile(path) as z:
        names = z.namelist()
    tops = {n.split("/")[0] for n in names}
    assert tops == {ADDON}, "one top folder only, got %s" % tops
    for f in toc_files():
        assert ADDON + "/" + f in names, "missing in zip: " + f
    for bad in ("tests/", "tools/", "upstream/", ".github/"):
        assert not any(("/" + bad) in n for n in names), "development files in the zip: " + bad
    assert ADDON + "/" + ADDON + ".toc" in names
    assert ADDON + "/LICENSE" in names and ADDON + "/THIRD_PARTY.md" in names
    size = os.path.getsize(path)
    print("ok: %d files, %.1f MB" % (len(names), size / 1e6))


if __name__ == "__main__":
    p = build()
    print("built", os.path.relpath(p, ROOT))
    if "--check" in sys.argv:
        check(p)
