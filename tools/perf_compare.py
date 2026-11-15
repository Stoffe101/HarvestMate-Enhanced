"""Compares HarvestMate Enhanced's performance across versions, headless.

    python tools/perf_compare.py                    # 0.3.0, 0.4.0 and the working tree
    python tools/perf_compare.py 390c523 HEAD .     # any git refs, "." for the working tree

Each version's HarvestMateEnhanced/ folder is taken from git into build/perf/<ref>/ and
loaded by today's test client (tests/support), which runs tools/perf.lua: load time and
memory, Farm Finder searches, building every page, Dashboard refresh, 200 skin events, HUD
and Skinning-levels updates, with the garbage each makes. Each version runs three times
and the middle value is kept. CPU time outside the game, not game frame times. Needs lupa.
"""
import io
import os
import statistics
import subprocess
import sys
import tarfile

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import run_tests  # noqa: E402

ROOT = run_tests.ROOT
OUT = os.path.join(ROOT, "build", "perf")
DEFAULT = [("0.3.0", "390c523"), ("0.4.0", "2d15762"), ("now", ".")]


def extract(ref):
    if ref == ".":
        return "HarvestMateEnhanced"
    dst = os.path.join(OUT, ref)
    if not os.path.exists(os.path.join(dst, "HarvestMateEnhanced")):
        os.makedirs(dst, exist_ok=True)
        data = subprocess.run(["git", "archive", "--format=tar", ref, "HarvestMateEnhanced"], cwd=ROOT,
                              capture_output=True, check=True).stdout
        tarfile.open(fileobj=io.BytesIO(data)).extractall(dst, filter="data")
    return os.path.relpath(os.path.join(dst, "HarvestMateEnhanced"), ROOT).replace(os.sep, "/")


def run(addon_dir):
    import lupa.lua51 as L  # noqa: N811
    os.chdir(ROOT)
    rt = L.LuaRuntime(unpack_returned_tuples=True)
    lines = []
    rt.globals().print = lambda *a: None
    rt.execute(run_tests.PRELUDE.replace("REAL_PRINT = realPrint", ""))
    rt.globals().REAL_PRINT = lambda *a: lines.append(" ".join(str(x) for x in a))
    rt.globals().ADDON_DIR = addon_dir
    rt.execute('dofile("tools/perf.lua")')
    res = {}
    for line in lines:
        if line.startswith("PERF\t"):
            _, label, value, unit = line.split("\t")
            res[label] = (float(value), unit)
    return res


def main():
    args = sys.argv[1:]
    versions = [(a, a) for a in args] if args else DEFAULT
    table, order = {}, []
    for name, ref in versions:
        d = extract(ref)
        runs = []
        for _ in range(3):
            # A fresh process each time: one version's state never leaks into the next.
            out = subprocess.run([sys.executable, "-c", "import sys; sys.path.insert(0, 'tools'); import perf_compare as p, json; "
                                  "print(json.dumps(p.run(%r)))" % d], cwd=ROOT, capture_output=True, text=True)
            import json
            try:
                runs.append(json.loads(out.stdout.strip().splitlines()[-1]))
            except (ValueError, IndexError):
                print(name, "failed:", out.stderr[-400:])
                runs = []
                break
        if not runs:
            continue
        med = {}
        for label in runs[0]:
            vals = [r[label][0] for r in runs if label in r]
            med[label] = (statistics.median(vals), runs[0][label][1])
            if label not in order:
                order.append(label)
        table[name] = med
    names = [n for n, _ in versions if n in table]
    lines = ["| What | " + " | ".join(names) + " |", "|---|" + "---|" * len(names)]
    for label in order:
        cells = []
        for n in names:
            v = table[n].get(label)
            cells.append("%.1f %s" % (v[0], v[1]) if v else "–")
        lines.append("| %s | %s |" % (label, " | ".join(cells)))
    text = "\n".join(lines)
    print(text)
    os.makedirs(OUT, exist_ok=True)
    with open(os.path.join(OUT, "compare.md"), "w", encoding="utf-8") as f:
        f.write(text + "\n")
    return 0


if __name__ == "__main__":
    sys.exit(main())
