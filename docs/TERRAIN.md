# Terrain-aware routes, caves and recorded routes

## The problem

GatherPath's solver finds a short loop through the stops, but the legs between stops are straight lines. A straight line can run through a mountain, across a lake or off a cliff. Measured on two real HME loops (99 and 100 legs, Redridge ore and Elwynn copper) against Forever-GPS's walking grid: only about a third of the legs were walkable as a straight line; about one leg in three was more than 20% longer on foot, and about one in ten more than twice as long. Short legs were no exception.

## How HME solves it

HME does not search terrain itself and invents no terrain data. It asks Forever-GPS, which bundles EasyFind GPS's walking grid for WoW Forever (4-yard cells with their floors and links, built from the game's own data).

1. **The Farm Finder picks** the area and the nodes worth visiting (unchanged).
2. **GatherPath's solver orders** them into a short loop (unchanged).
3. **Each leg is walked** on the grid through `ForeverGPS.API.LocalPaths` (API v2): in batches of up to 64 legs, a few milliseconds a frame, inside a coroutine that yields within searches. It waits while Forever-GPS plans a route of its own, never changes the grid's settings and never touches the journey being followed. A leg is searched only up to 4x its straight length.
4. **The loop is drawn** along the walked turns on the world map and minimap; legs the grid could not walk are drawn in the warning colour (orange) and marked approximate.
5. **The hybrid pass**: where a leg detours badly (1.5x or more), HME tries 2-opt changes of order that take that leg out, judged by walked legs and the grid's landmark bounds, walks the new legs, and keeps the new order only if the walked loop really is at least 1% shorter with no more approximate legs. Your own edited or recorded routes are never reordered.
6. **The arrow** follows the walked turns of the current leg, then the stop.
7. **Lap time** uses the walked length.

Each leg's result is cached per account (`HarvestMateEnhancedDB.terrain`, newest 1200 legs) by its two ends, either way round, so a route is walked again only where its stops changed. The drawn polylines are rebuilt from the cache at login and never saved twice.

## What has priority

When several sources know a leg, the most trusted leads:

1. your own edited waypoints (never moved);
2. a cave you marked: in or out through its entrance;
3. a route recorded in game that passes both ends of the leg ("corridor"): yours first, then Gatherpedia's recorded guide routes;
4. Forever-GPS's walking grid;
5. the straight line, marked approximate.

## Route quality labels

| Label | Meaning |
|---|---|
| Recorded and observed | recorded in game, and ridden with HME since |
| Recorded | recorded in game (by you, Gatherpedia's guides, or imported) |
| User-corrected | waypoints edited by you |
| Terrain-aware | every leg follows the walking grid (or a corridor or cave entrance) |
| Partly terrain-aware | some legs walked, the rest straight lines |
| Approximate | straight lines, terrain unknown |

A route ridden two laps or more is also "observed". A route is never called verified just because an algorithm returned waypoints.

## Caves

The client gives no height or collision data, so HME never guesses a cave from coordinates. It knows a cave from Gatherpedia's recorded cave outlines (its leveling guides) or because you marked it: stand at the cave's mouth, open the map and **Shift+right-click** a node inside. Nodes within 60 yards of that node are that cave; its entrance is where you stood. Legs into or out of it go through the entrance. In the Farm Finder, a farm with many nodes in a cave nobody can say how to enter ranks lower and says how to fix it.

## Limits

- Needs Forever-GPS with API v2 (branch `feature/public-api`). Without it, routes stay straight lines labelled approximate, and recorded corridors and caves still apply.
- The grid's walks follow its settings at that moment (roads, danger, drop limit); `result.settings` records them.
- One leg can take about a tenth of a second of searching on a desktop PC (Lua 5.4); in the game the batches spread this over frames, so a 100-leg loop is walked in the background over several seconds of play.
- Swimming, drops and cave floors are as the grid knows them; nothing about live obstacles.
