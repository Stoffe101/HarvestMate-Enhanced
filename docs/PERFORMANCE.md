# Performance

Measured with `tools/bench.lua` (`python tools/run_tests.py bench -v`) on the full bundled data, Lua 5.1 via lupa on the development PC, outside the game. In the game every search and route build runs as a background job of at most 8 ms per frame (4 ms in low-performance mode), so the game never stalls; these are total CPU times.

| Workload | Time |
|---|---|
| Farm Finder, Mining, cold caches | ~105 ms |
| Farm Finder, Mining, warm | ~16 ms |
| Farm Finder, Herbalism profit | ~88 ms |
| Farm Finder, Skinning leveling (cold) | ~178 ms |
| Farm Finder, Skinning profit (cold) | ~314 ms |
| Farm Finder, Herbs + Ore combined | ~30 ms |
| Multi-material search (3 items) | ~18 ms |
| Switching professions x8 (warm) | ~115 ms (~397 ms before hunting areas were cached) |
| Spawn sites, densest mining zone | ~5 ms |
| Hunting areas, one zone | ~5 ms |
| Route build (all slices) | ~40 ms |
| Map overlay draw, one farm | ~1.4 ms |
| Map overlay draw, every pin in a dense zone (capped, grouped) | ~5 ms |
| Lua memory after all of the above | ~8.7 MB |

Caches: spawn sites per profession and map; hunting areas per map, goal, mode, skill and level; both invalidate when data changes. Pages build when first opened. Map pins are pooled, grouped when crowded, and capped (600 / 250).

Not measured: in-game frame time, garbage per frame, SavedVariables load time (see docs/MANUAL_TESTING.md).
