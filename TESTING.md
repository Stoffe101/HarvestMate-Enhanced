# Testing

## How to run

```bash
pip install lupa
```

```bash
python tools/run_tests.py
```

Each `tests/test_*.lua` runs in a fresh **real Lua 5.1** interpreter (the one bundled with `lupa`), against a fake client in `tests/support/` (frames, events, maps, professions, items, loot, CVars, bindings that raise if changed in combat, timers, popups). Nothing opens a window or touches the desktop or the game. CI runs the same on every push (`.github/workflows/test.yml`) and builds the ZIP.

## What runs (all passing at the time of writing, 8 files)

| File | Covers |
|---|---|
| `test_gatherpath_routes.lua` | GatherPath's own regression suite, ported: solver (optimal on small sets, untangled, deterministic, bounded work), avoid areas in the solver, making/editing/renaming/hiding/deleting routes, nodes found and deleted later, skip list, world map and minimap lines (positions, rotation, clipping), arrows, line to route, lap time, range circle, restore defaults, saved data, no GatherMate2 |
| `test_scenarios.lua` | Brief scenarios A (level-36 Alliance hunter, 175 Skinning, fastest leveling), B (best profit, three estimates ordered, respawn cap), C (Goldthorn), D (mining leveling: only minable ore), E (lower PvP risk), F (no optional addons) on the real bundled data |
| `test_engines.lua` | Skill colors/chances, skinning rule, eligibility (level, elite, unskinnable), kill-time learning, yield blending, rare-drop damping, profit scope without double counting, measured-rate blending and verdict, risk (territory, guards, deaths, never "safe"), travel (unknown when there is no basis), planning a herb loop, avoid areas, hunting circuit, guide (cap, level, grey), sessions (auto start, idle pause, history, area stats), performance on the full data |
| `test_data.lua` | Packed points, migration from HarvestMateDB/GatherpediaDB/GatherPathForeverDB (old tables untouched, not doubled, unsafe options not carried over), shared sites, confirmation by your gathers, limits, export/import round trip, tampered and foreign text refused and never run, schema upgrade/newer save, resets |
| `test_safety.lua` | Nothing changes on first login; gather key needs a yes (and not in combat); bound only at a node; released on combat, binding change, turning off and logout; capture closes in combat; Soft Target Interact only with a yes and put back; no CVar in combat; old addons running: HME pauses without saving that; no protected calls |
| `test_integrations.lua` | Forever-GPS 2.x journey panel and published API, scenario G hand-off, no second arrow, stopping in Forever-GPS, too-old Forever-GPS, TomTom, Auctionator/TSM/vendor prices, nothing installed |
| `test_ui.lua` | Window and every page build lazily and refresh without errors; no widget outside the page; Farm Finder results, selection, empty states; compact layout, scaling; tab memory; tab cycling; capture closes with the window; settings persist; HUD; minimap button; slash commands |
| `test_static.lua` | Every .toc file exists and compiles; vendored files equal upstream except declared patches; no unexpected globals; no saved-variable or command clashes |

Last run: 8 of 8 files passed, about 1,400 checks plus GatherPath's suite, ~9 s. Three full Farm Finder searches over all bundled data took 0.31 s of CPU (outside the game).

## Verified where

| Level | Status |
|---|---|
| Headless tests on real Lua 5.1 with a simulated client | **Done** (above) |
| Real WoW Forever client | **Not yet.** Nothing in HME has been run in the game. The checklist is [docs/MANUAL_TESTING.md](docs/MANUAL_TESTING.md). |

The fake client accepts any method on a frame, so it cannot catch a wrong widget method name, layout that looks bad, textures that fail to load, or behaviour of the real map canvas, nameplates, soft targeting, secret values or protected functions. Those need the in-game checklist.
