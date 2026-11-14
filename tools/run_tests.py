"""Runs HarvestMate Enhanced's headless tests, each file in a fresh Lua 5.1.

Uses the real Lua 5.1 interpreter bundled with the `lupa` package when it is
installed (pip install lupa), else a `lua5.1` executable on PATH. Nothing is
opened on screen: the game is simulated by tests/support/*.lua.

    python tools/run_tests.py            # every tests/test_*.lua
    python tools/run_tests.py skinning   # only files whose name contains "skinning"
"""
import glob
import os
import shutil
import subprocess
import sys
import time

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

PRELUDE = """
dofile("tests/support/wow.lua")
dofile("tests/support/wow_extra.lua")
dofile("tests/support/loader.lua")
dofile("tests/support/assert.lua")
"""

RUNNER = PRELUDE + """
local ok, err = xpcall(function() dofile(TEST_FILE) end, debug.traceback)
for _, line in ipairs(LOG) do
    if line:find("^STEP") then REAL_PRINT(line) end
end
if not ok then
    REAL_PRINT("FAILED: " .. tostring(err))
    REAL_PRINT("last chat lines:")
    for i = math.max(1, #LOG - 6), #LOG do REAL_PRINT("  " .. tostring(LOG[i])) end
    if ERRORS then for _, e in ipairs(ERRORS) do REAL_PRINT("  error handler: " .. e) end end
    return 1
end
if ERRORS and #ERRORS > 0 and not ALLOW_ERRORS then
    REAL_PRINT("FAILED: Lua errors reached the error handler during the test:")
    for _, e in ipairs(ERRORS) do REAL_PRINT("  error handler: " .. e) end
    return 1
end
REAL_PRINT(("PASSED %d checks"):format(Passed()))
return 0
"""


def run_lupa(path):
    import lupa.lua51 as L  # noqa: N811
    rt = L.LuaRuntime(unpack_returned_tuples=True)
    out = []
    rt.globals().print = lambda *a: out.append(" ".join(str(x) for x in a))
    rt.globals().TEST_FILE = path
    code = rt.execute(RUNNER.replace("REAL_PRINT = realPrint", ""))
    return code, out


def run_exe(exe, path):
    src = "TEST_FILE=" + repr(path).replace("'", '"') + "\n" + RUNNER.replace("return 1", "os.exit(1)").replace(
        "return 0", "os.exit(0)")
    proc = subprocess.run([exe, "-"], input=src, text=True, capture_output=True, cwd=ROOT)
    return proc.returncode, (proc.stdout + proc.stderr).splitlines()


def main():
    os.chdir(ROOT)
    pattern = sys.argv[1] if len(sys.argv) > 1 else ""
    files = sorted(f.replace(os.sep, "/") for f in glob.glob("tests/test_*.lua") if pattern in f)
    try:
        import lupa.lua51  # noqa: F401
        mode = "lupa"
    except ImportError:
        mode = shutil.which("lua5.1") or shutil.which("lua51")
        if not mode:
            print("Needs Lua 5.1: pip install lupa, or put lua5.1 on PATH.")
            return 2
    failed = []
    total_start = time.time()
    for f in files:
        start = time.time()
        try:
            if mode == "lupa":
                code, out = run_lupa(f)
            else:
                code, out = run_exe(mode, f)
        except Exception as e:  # a Lua error escaping the runner
            code, out = 1, ["FAILED: " + str(e)]
        took = time.time() - start
        status = "ok" if code == 0 else "FAIL"
        print(f"[{status}] {f} ({took:.1f}s)")
        if code != 0 or "-v" in sys.argv:
            for line in out:
                print("    " + line)
        if code != 0:
            failed.append(f)
    print(f"\n{len(files) - len(failed)} of {len(files)} test files passed in {time.time() - total_start:.1f}s"
          f" (Lua 5.1 via {'lupa' if mode == 'lupa' else mode})")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
