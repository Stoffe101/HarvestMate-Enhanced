# Testing

## How to run

```bash
pip install lupa
```

```bash
python tools/run_tests.py
```

Each `tests/test_*.lua` runs in a fresh **real Lua 5.1** interpreter (the one bundled with `lupa`), against a fake client in `tests/support/` (frames, events, maps, professions, items, loot, CVars, bindings that raise if changed in combat, timers, popups). Nothing opens a window or touches the desktop or the game. CI runs the same on every push (`.github/workflows/test.yml`) and builds the ZIP.

## What runs (all passing at the time of writing, 19 files)

| File | Covers |
|---|---|
| `test_gatherpath_routes.lua` | GatherPath's own regression suite, ported: solver (optimal on small sets, untangled, deterministic, bounded work), avoid areas in the solver, making/editing/renaming/hiding/deleting routes, nodes found and deleted later, skip list, world map and minimap lines (positions, rotation, clipping), arrows, line to route, lap time, range circle, restore defaults, saved data, no GatherMate2 |
| `test_scenarios.lua` | Brief scenarios A (level-36 Alliance hunter, 175 Skinning, fastest leveling), B (best profit, three estimates ordered, respawn cap), C (Goldthorn), D (mining leveling: only minable ore), E (lower PvP risk), F (no optional addons) on the real bundled data |
| `test_engines.lua` | Skill colors/chances, skinning rule, eligibility (level, elite, unskinnable), kill-time learning, yield blending, rare-drop damping, profit scope without double counting, measured-rate blending and verdict, risk (territory, guards, deaths, never "safe"), travel (unknown when there is no basis), planning a herb loop, avoid areas, hunting circuit, guide (cap, level, grey), sessions (auto start, idle pause, history, area stats), performance on the full data |
| `test_data.lua` | Packed points, migration from HarvestMateDB/GatherpediaDB/GatherPathForeverDB (old tables untouched, not doubled, unsafe options not carried over), shared sites, confirmation by your gathers, limits, export/import round trip, tampered and foreign text refused and never run, schema upgrade/newer save, resets |
| `test_safety.lua` | Nothing changes on first login; gather key needs a yes (and not in combat); bound only at a node; released on combat, binding change, turning off and logout; capture closes in combat; Soft Target Interact only with a yes and put back; no CVar in combat; old addons running: HME pauses without saving that; no protected calls |
| `test_integrations.lua` | Forever-GPS 2.x journey panel and published API, scenario G hand-off, no second arrow, stopping in Forever-GPS, too-old Forever-GPS, TomTom, Auctionator/TSM/vendor prices, nothing installed |
| `test_ui.lua` | Window and every page build lazily and refresh without errors; no widget outside the page; Farm Finder results, selection, empty states, the Best beasts panel (one and two materials, a click opens the area, the wrong goal); compact layout, scaling; tab memory; tab cycling; capture closes with the window; settings persist; HUD; minimap button; slash commands |
| `test_navigation.lua` | Request tokens, duplicate events, scenario 6 hand-off, scenario 7 changed destination, cancel without takeover, walking in with HME's or another journey, **one arrow on Guide me here with Forever-GPS 2.7 (map guidance)**, journeys started and ended during the farm, free mode, reload staleness, scenario 10 travel vs farming time |
| `test_fgps_api_live.lua` | HME's guidance against Forever-GPS's real `Core/API.lua` (skipped, with a note, when no Forever-GPS checkout is present): **scenario G with the real API v2 arrow hold**, the nearest vendor through `NavigateToService` |
| `test_skinning2.lua` | Four character fixtures, partial level ranges, eligibility vs efficiency, scenario 3 Heavy Leather, multi-mob and no-loot fights excluded, fading kill samples, loot counted once with sample sizes, evidence levels and ranges |
| `test_goals.lua` | Scenario 5 goal, bank, invalid goals, shopping lists, scenario 11 staged plan, comparison, scenario 4 combined loop, scenario 9 exclusion, suggestions, sell/keep, profiles |
| `test_maps.lua` | Overlay pins, crowd grouping, simple/heatmap, right-click corrections, hunting outlines, route editor, protection of edited routes, route quality, pin limits |
| `test_zz_bench.lua` | Benchmarks (tools/bench.lua) with generous bounds |
| `test_static.lua` | Every .toc file exists and compiles; vendored files equal upstream except declared patches; no unexpected globals; no saved-variable or command clashes |
| `test_terrain.lua` | Scenario A on a replay of Forever-GPS's REAL walking-grid answers for two real HME loops (`tests/fixtures/fgps_terrain.lua`): batches, detours, approximate legs, drawing, the arrow through the turns, quality labels, the leg cache, cancellation, no terrain, recorded routes, the hybrid reorder (made-up ground, said so), caves; the prepared corridor search against the point-by-point one (60 legs, 6 recordings), a 100-stop loop settled in the background, a rebuild or cancel during the reorder pass, deleting a route while walking, no batch in combat, the arrow keeping its stop after a reorder |
| `test_recorder.lua` | Scenario B: recording, standing still, turns, pause/resume, leaving the zone, reload, loops and there-and-back, gathers on the way, editing, trimming, limits, export/import, damaged state, recorded corridors |
| `test_intel.lua` | Scenario I calibration per character, reputation, skin attribution, confidence dimensions, profit per effort, corrections in the Finder, goal reasons, scenario D best beasts, live feedback and its suggestion, adaptive loops and circuit, scenario E priorities, records and now-vs-before |
| `test_expedition.lua` | Scenario F expeditions: stages, reasons for what cannot be planned, one-zone lists, progress, skip, reorder, replan, go; travel estimates; one-line shopping lists and the Goals page |
| `test_economy.lua` | Price sanity (impossible, missing, outlier prices) and the optional recipe link (format copied from Forever-GPS's data) |

Last run: 19 of 19 files passed (Lua 5.1 via lupa), ~17 s. The runner also fails a file when any Lua error reaches the error handler. The test client is like WoW Forever's in having `C_Item.GetItemInfo` and no global `GetItemInfo`.

Forever-GPS (branch feature/public-api) with API v2, every check its CI runs, on this PC: vendored pins, repository checks, Lua 5.1 syntax, Luacheck (0 warnings in 64 files), all four test suites through `tools/run_tests.py` (EasyFind 1312, GPS 432, Questie 6, Forever-GPS 630 passed, 0 failed) and the package build, at Forever-GPS commit 3afbfa6. Benchmarks: [docs/PERFORMANCE.md](docs/PERFORMANCE.md).

Interface previews: `python tools/ui_preview.py --shots` draws 40 states (every page and its important states, the HUD, the Skinning levels box, and the whole screen at seven sizes and UI scales) from the real layout code in the test client, screenshots them with headless Chrome or Edge (no window, no focus change), and checks each for overlapping text, text cut short or within 8% of its box, cramped buttons, text under 10.5 px, dim text, missing addon art and frames off the screen. `build/preview/review.html` is the gallery; `--approve` makes the current shots the baseline and later runs show what changed; `--strict` fails on overlap, cut or cramped. At 0.4.0: 0 overlap, 0 cut, 0 cramped, 0 tiny, 0 dim in every state ("tight" remains where text is fitted by measuring, by design). They are layout renders with estimated text sizes and stand-in fonts and textures, not game screenshots.

Real-grid fixture: `tools/terrain_fixture.lua` (run from the Forever-GPS checkout) records what the real walking grid answers for every leg of real HME loops into `tests/fixtures/fgps_terrain.lua`; HME's terrain tests replay those answers.

## Verified where

| Level | Status |
|---|---|
| Headless tests on real Lua 5.1 with a simulated client | **Done** (above) |
| Real WoW Forever client | **Loading only** (2026-11-14, client 1.60.1.70938): HME 0.3.0 and Forever-GPS 2.7.0 (API v2) loaded; `/hme diag` found API v2, the walking grid and the arrow hold, with no errors; `/fgps diag` found all 28 game functions it checks, including `CreateVector2D`. That report also showed two HME bugs, fixed since (position and class, see CHANGELOG). Nothing else has been tried in the game; the checklist is [docs/MANUAL_TESTING.md](docs/MANUAL_TESTING.md). |

The fake client accepts any method on a frame, so it cannot catch a wrong widget method name, layout that looks bad, textures that fail to load, or behaviour of the real map canvas, nameplates, soft targeting, secret values or protected functions. Those need the in-game checklist.
