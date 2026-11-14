# Performance

Measured with `tools/bench.lua` (`python tools/run_tests.py bench -v`) on the full bundled data, Lua 5.1 via lupa on the development PC, outside the game. In the game every search and route build runs as a background job of at most 8 ms per frame (4 ms in low-performance mode), and Forever-GPS's walking-grid batches run at its own planning share (4-12 ms per frame); these are total CPU times.

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
