"""Reviews a new upstream release against what HME vendored, without
changing anything. For each file of the new release it says whether it
changed since the snapshot in upstream/, and how HME uses that file:

  vendored   copied unchanged or with declared patches: update by copying
             the new file, re-running tools/vendor_patch.py and the tests
  adapted    HME changed it heavily: port the upstream fix by hand
  replaced   HME has its own implementation: check whether the fix applies
  unused     not shipped in HME

    python tools/upstream_check.py harvestmate path/to/HarvestMate-x.y.z.zip
    python tools/upstream_check.py gatherpedia path/to/Gatherpedia-vX.zip
    python tools/upstream_check.py gatherpath  path/to/gatherpath-checkout

Prints a unified diff summary per changed file (first 40 lines with -v).
"""
import difflib
import hashlib
import os
import sys
import tempfile
import zipfile

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

SNAP = {
    "harvestmate": "upstream/HarvestMate-2.0.13",
    "gatherpedia": "upstream/Gatherpedia-1.0.1",
    "gatherpath": "upstream/GatherPath-1.12.1",
}
USE = {
    "harvestmate": {
        **{f: ("vendored", "Gather/" + f) for f in ["Data.lua", "Skill.lua", "Resolve.lua", "Prices.lua", "Profit.lua",
            "Extras.lua", "Tooltip.lua", "Learn.lua", "Announce.lua", "Stats.lua", "Toast.lua", "Gear.lua", "Tracking.lua",
            "Banner.lua", "Bind.lua", "Nearby.lua"]},
        "Core.lua": ("adapted", "Gather/HGCore.lua"),
        "Session.lua": ("replaced", "Engine/Session.lua"),
        "Hub.lua": ("replaced", "UI/Window.lua"), "Settings.lua": ("replaced", "UI/PageSettings.lua"),
        "Minimap.lua": ("replaced", "UI/Minimap.lua"),
    },
    "gatherpedia": {
        **{"Data/" + f: ("vendored", "Data/Gatherpedia/" + f) for f in ["Herbalism.lua", "Mining.lua", "Fishing.lua",
            "Skinning.lua", "HerbalismGuide.lua", "MiningGuide.lua", "FishingGuide.lua", "SkinningGuide.lua",
            "SkinningMobs.lua", "NodeSpawns.lua"]},
        "Zones.lua": ("vendored", "Data/Gatherpedia/Zones.lua"), "Trainers.lua": ("vendored", "Data/Gatherpedia/Trainers.lua"),
        "Guides.lua": ("vendored", "Data/Gatherpedia/Guides.lua"), "Sparkles.lua": ("vendored", "Glimmer/Sparkles.lua"),
        "SparklesUI.lua": ("adapted", "Glimmer/SparklesCloud.lua"), "Core.lua": ("adapted", "Core/GPCompat.lua"),
        "Arrow.lua": ("replaced", "Map/Arrow.lua"), "SpawnPins.lua": ("replaced", "Map/Overlay.lua"),
        "Session.lua": ("replaced", "Engine/Session.lua"), "Tracker.lua": ("replaced", "Engine/Learning.lua"),
        "RouteOverlay.lua": ("replaced", "Routes/Routes.lua"),
    },
    "gatherpath": {
        "Optimize.lua": ("vendored", "Engine/Optimize.lua"), "Core.lua": ("adapted", "Routes/Routes.lua"),
        "Options.lua": ("adapted", "Routes/RoutesUI.lua"), "Theme.lua": ("adapted", "UI/Theme.lua"),
        "Pin.xml": ("adapted", "Routes/Pin.xml"),
    },
}


def files_of(path):
    out = {}
    if os.path.isdir(path):
        for base, _, names in os.walk(path):
            if ".git" in base:
                continue
            for n in names:
                full = os.path.join(base, n)
                out[os.path.relpath(full, path).replace(os.sep, "/")] = open(full, "rb").read()
        return out
    with zipfile.ZipFile(path) as z:
        names = [n for n in z.namelist() if not n.endswith("/")]
        top = os.path.commonprefix([n.split("/")[0] + "/" for n in names])
        for n in names:
            rel = n[len(top):] if top and n.startswith(top) else n
            out[rel] = z.read(n)
    return out


def main():
    if len(sys.argv) < 3 or sys.argv[1] not in SNAP:
        print(__doc__)
        return 2
    which, src = sys.argv[1], sys.argv[2]
    new = files_of(src)
    snap_dir = os.path.join(ROOT, SNAP[which])
    changed = 0
    for rel in sorted(new):
        if not rel.endswith((".lua", ".xml", ".toc")):
            continue
        old_path = os.path.join(snap_dir, rel)
        old = open(old_path, "rb").read() if os.path.exists(old_path) else None
        if old is not None and hashlib.sha256(old).digest() == hashlib.sha256(new[rel]).digest():
            continue
        changed += 1
        how, where = USE[which].get(rel, ("unused", "-"))
        state = "new file" if old is None else "changed"
        print(f"{state:9} {rel:32} {how:9} -> {where}")
        if "-v" in sys.argv and old is not None:
            diff = difflib.unified_diff(old.decode("utf-8", "replace").splitlines(), new[rel].decode("utf-8", "replace").splitlines(),
                                        lineterm="", n=1)
            for i, line in enumerate(diff):
                if i >= 40:
                    print("    ...")
                    break
                print("    " + line)
    print(f"\n{changed} file(s) differ from the snapshot in {SNAP[which]}. Nothing was changed.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
