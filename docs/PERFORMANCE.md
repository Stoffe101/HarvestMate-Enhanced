# Performance

Measured with `tools/bench.lua` (`python tools/run_tests.py bench -v`) on the full bundled data, Lua 5.1 via lupa on the development PC, outside the game. In the game every search and route build runs as a background job of at most 8 ms per frame (4 ms in low-performance mode), and Forever-GPS's walking-grid batches run at its own planning share (4-12 ms per frame); these are total CPU times.

## 0.3.0, 0.4.0 and 0.5.0 compared

`python tools/perf_compare.py` runs the same script (`tools/perf.lua`) against each version's addon folder, taken from git, in today's test client: three fresh runs each, the middle value kept. Headless CPU time and Lua memory on the development PC (an i7-class desktop), **not game frame times**: the game also draws, measures text and runs other addons.

| What | 0.3.0 | 0.4.0 | 0.5.0 |
|---|---|---|---|
| Load the addon (every file, data indexes) | 65 ms | 67 ms | 68 ms |
| Memory after load | 3.31 MB | 3.37 MB | 3.41 MB |
| Farm Finder, Skinning leveling (cold) | 43 ms | 44 ms | 41 ms |
| Farm Finder, Skinning leveling (warm) | 3.3 ms | 3.7 ms | 3.3 ms |
| Farm Finder, Medium Leather | 25 ms | 24 ms | 24 ms |
| Open the window and build every page | 17 ms | 17 ms | 17 ms |
| Dashboard refresh | 0.1 ms | 0.1 ms | 0.1 ms |
| 200 skin events (cast, loot, close) | 243 ms | 239 ms | 244 ms |
| HUD update, detailed | 0.1 ms, 5.6 KB garbage | 0.1 ms, 7.2 KB | 0.1 ms, 7.2 KB |
| Skinning levels update | 0.1 ms | 0.1 ms | 0.1 ms |
| Memory at the end of the run | 8.71 MB | 8.90 MB | 8.94 MB |

No path got slower. The redesign costs about 100 KB after load (art and font objects). The detailed HUD makes about 7 KB of garbage per update (once a second while shown), about 26 MB an hour, collected in small steps by the game; compact makes 2 KB. A skin event (with its session, goal, HUD and recorder updates) takes about 1.2 ms of CPU here; skins come every 20 seconds or more. Search and route work still runs as background jobs in the game (8 ms a frame), so these totals are spread over frames.

## Compared with 0.2.0

| Workload | 0.2.0 | 0.3.0 |
|---|---|---|
| Farm Finder, Mining, cold caches | ~105 ms | ~100 ms |
| Farm Finder, Mining, warm | ~16 ms | ~18 ms |
| Farm Finder, Herbalism profit | ~88 ms | ~91 ms |
| Farm Finder, Skinning leveling (cold) | ~178 ms | ~165 ms |
| Farm Finder, Skinning profit (cold) | ~314 ms | ~299 ms |
| Farm Finder, Herbs + Ore combined | ~30 ms | ~39 ms (combined-vs-separate check for the top 3) |
| Multi-material search (3 items) | ~18 ms | ~19 ms |
| Switching professions x8 (warm) | ~115 ms | ~122 ms |
| Spawn sites, densest mining zone | ~5 ms | ~6 ms |
| Hunting areas, one zone | ~5 ms | ~6 ms |
| Route build (all slices) | ~40 ms | ~35 ms |
| Map overlay draw, one farm | ~1.4 ms | ~0.6 ms |
| Map overlay draw, every pin in a dense zone | ~5 ms | ~4 ms |
| Lua memory at the same point | ~8.7 MB | ~9.3 MB (+0.6 MB: the new modules) |

No regression beyond noise except the combined search (+9 ms, the new check) and memory (+7%).

## New in 0.3.0

| Workload | Time |
|---|---|
| Map overlay draw, heatmap (dense zone) | ~9 ms |
| Terrain: assemble a walked 99-leg loop from the cache | ~0.3 ms |
| Route lines on the map, walked 99-leg loop | ~0.6 ms |
| Forever-GPS walking grid, real 99- and 100-leg loops (desktop Lua 5.4, its test stack) | ~3.8 s and ~6.2 s in all, slowest leg ~0.1 s; in the game spread over frames by `LocalPaths` |
| Recorder: one sample | < 0.1 ms (2000 samples kept 341 points) |
| Recorder: stop (simplify and save) | ~2 ms |
| Session live feedback (200 events) | < 0.1 ms |
| Expedition: 3 materials over 3 professions | ~273 ms (three Finder searches, run as background jobs) |
| Diagnostics report | ~0.2 ms |
| Lua memory after the whole benchmark (includes the fixture, its results and the 10 recordings of the terrain review) | ~22 MB |

Caches: spawn sites per profession and map; hunting areas per map, goal, mode, skill and level (and corrections); walked legs per account (1200). Pages build when first opened. Map pins are pooled, grouped when crowded, and capped (600 / 250).

## Terrain pass review (after the first 0.3.0 push)

A 99-stop loop (the real Redridge fixture) with 10 recordings of 300 points on the same map, the worst case for the corridor search (`python tools/run_tests.py bench -v`):

| Step | Before | After |
|---|---|---|
| Building the route (`Terrain.Refine` call, in one frame) | ~308 ms, a freeze | < 1 ms |
| The pass before walking (corridors, caves, cache) | in that one frame | ~92 ms of work in all, a background job a slice a frame |
| Again, legs cached (with the walking grid) | ~17 ms in one frame | ~6 ms, in the background |
| Forever-GPS's share of a frame while walking | 4-12 ms (its planner's) | 3 ms; no new batch in combat |
| Legs per batch | 64 | 16 (less lost to a cancel or a change) |

The corridor search now prepares each recording once per pass (points in yards and a box round them) and compares squared distances; a test checks it gives exactly what the point-by-point search in yards gave. The reorder pass now works on a copy and can be cancelled (it used to change the route's stops over several frames and could not be stopped).

Not measured: in-game frame time while legs are walked (manual test 54), garbage per frame, SavedVariables load time.
