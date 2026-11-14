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

## ForeverGPS.API v1 (implemented on a Forever-GPS branch)

Implemented in the Forever-GPS repository on branch `feature/public-api` (draft PR https://github.com/Stoffe101/Forever-GPS/pull/3, not merged) as `addons/ForeverGPS/Core/API.lua`, documented in its `docs/API.md`, tested on its real route engine (`tests/test_api.lua`, 9 tests; whole suite 614 passing). HME prefers it when present and is tested against that real file in `tests/test_fgps_api_live.lua`. Request states on both sides: pending, active, arrived, cancelled, superseded, released, stale. HME passes `start = true` because the player just asked for directions.

### The original proposal (superseded by the implementation above)

Not committed to the Forever-GPS repository: it needs review there first. Suggested `Core/API.lua`, loaded after `Core/Bridge.lua`:

```lua
-- ForeverGPS.API: a stable surface for other addons. Versioned; additive only.
local FG = ForeverGPS
local API = { VERSION = 1 }
FG.API = API
local listeners = { arrived = {}, cleared = {} }

-- Plans a journey to a map point and opens it for the player to start.
-- opts.source names the caller; opts.autoStart is ignored unless the player allowed it in settings.
function API.NavigateTo(mapID, x, y, label, opts)
    local result = FG.Search.CoordsFor(("%s %.1f %.1f"):format(FG.Bridge.MapName(mapID) or "", x * 100, y * 100))
    if not result then return false, "unknown place" end
    local target = FG.Search.Target(result)
    target.name = label or target.name
    target.source = opts and opts.source
    FG.Window.Show("search")
    FG.Planner.Inspect(target)
    FG.Window.ShowRoute()
    return true
end

function API.Stop() FG.Bridge.Stop() end
function API.IsNavigating() return FG.Bridge.ActiveRoute() ~= nil end
function API.EstimateSeconds(mapID, x, y) --[[ from FG.Bridge.EstimateRoute when cheap ]] end
function API.On(event, fn) if listeners[event] then table.insert(listeners[event], fn) end end

FG.On("route:arrived", function(...) for _, fn in ipairs(listeners.arrived) do FG.Try(fn, ...) end end)
FG.On("route:cleared", function(...) for _, fn in ipairs(listeners.cleared) do FG.Try(fn, ...) end end)
```

HME already prefers `ForeverGPS.API` (VERSION ≥ 1) when present (`Integrations/ForeverGPS.lua`, tested in `tests/test_integrations.lua` with a fake). Tests on the Forever-GPS side would cover: missing destination, combat, a caller stopping only its own journey, and listeners that error.

## Ownership rule
Only one arrow at a time: while Forever-GPS travels, HME hides its arrow; after arrival HME's loop guidance takes over and Forever-GPS's route has ended. HME calls `API.Stop` only for a journey it asked for.
