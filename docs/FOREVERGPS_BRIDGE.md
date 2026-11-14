# Forever-GPS bridge

## Today (Forever-GPS 2.x, no changes to Forever-GPS)

HME uses only what Forever-GPS already exposes on its global `ForeverGPS` table, each piece feature-checked and wrapped in `pcall`:

| Need | Forever-GPS 2.7 | Notes |
|---|---|---|
| Is it there, and new enough | `ForeverGPS.VERSION` (≥ 2.0) | else HME's own arrow |
| Take a destination | `Search.CoordsFor("<zone> <x> <y>")`, `Search.Target`, `Planner.Inspect`, `Window.Show("search")`, `Window.ShowRoute()` | exactly what `/fgps way` does; the player presses **Go** in Forever-GPS — HME never starts a journey by itself |
| Arrival / stop | `ForeverGPS.On("route:arrived")`, `ForeverGPS.On("route:cleared")` | HME takes over on arrival; on a stop it waits for the player |
| Prices | `ForeverGPS.Market.Price(itemID)` → `{ buy, typical, units, age }` | read-only |

Internal functions such as these can change between Forever-GPS versions; that is why HME checks each one and falls back.

## ForeverGPS.API v1 and v2 (implemented on a Forever-GPS branch)

Implemented in the Forever-GPS repository on branch `feature/public-api` (draft PR https://github.com/Stoffe101/Forever-GPS/pull/3, not merged) as `addons/ForeverGPS/Core/API.lua`, documented in its `docs/API.md`, tested on its real route engine (`tests/test_api.lua`, 9 tests; whole suite 614 passing). HME prefers it when present and is tested against that real file in `tests/test_fgps_api_live.lua`. Request states on both sides: pending, active, arrived, cancelled, superseded, released, stale. HME passes `start = true` because the player just asked for directions.

### Version 2 (implemented on the same branch)

Added in 0.3.0, additive: `HoldArrow` / `ReleaseArrow` / `ArrowHeld` and the `hold` and `ended` events (one arrow: docs/NAVIGATION.md), `HasTerrain`, `LocalPath`, `LocalPaths`, `LocalBound` (walks on the walking grid: docs/TERRAIN.md), and `NavigateToService` (the nearest vendor, mailbox, trainer...). Documented in Forever-GPS's `docs/API.md`; tested on its real stack and walking grid in `tests/test_api_v2.lua`. HME checks each function before using it, so Forever-GPS 2.7 and API v1 keep working.

(0.2.0's text here carried an older API proposal; it was replaced by the implementation and is no longer documented here, to avoid confusion.)

## Ownership rule
Only one arrow at a time: while Forever-GPS travels, HME hides its arrow; after arrival HME's loop guidance takes over and Forever-GPS's route has ended. HME calls `API.Release` only for a journey it asked for and that still runs. Beside a journey that is not HME's, HME shows its arrow only while Forever-GPS holds its own (API v2); otherwise it guides on the map. Details: docs/NAVIGATION.md.
