-- Navigation ownership with Forever-GPS (scenarios 6, 7) and farming-time
-- measurement (scenario 10). A fake Forever-GPS 2.x that behaves like the real
-- one: a journey starts only when the player presses Go (route:started with
-- its destination), route:arrived(dest) on arrival, then route:cleared after
-- a linger; a new destination replaces the journey with another
-- route:started; StopNavigation clears it.

local topics = {}
local fg = { journey = nil, stopped = 0, panelTarget = nil }
local function Emit(topic, ...) for _, fn in ipairs(topics[topic] or {}) do fn(...) end end
local function Press(dest) fg.journey = { dest = dest } Emit("route:started", dest) end
local function Arrive() local d = fg.journey.dest fg.journey.arrived = true Emit("route:arrived", d) end
local function Clear() fg.journey = nil Emit("route:cleared") end
ForeverGPS = {
    VERSION = "2.7.0",
    On = function(topic, fn) topics[topic] = topics[topic] or {}; table.insert(topics[topic], fn) end,
    Search = {
        CoordsFor = function(text)
            local zone, x, y = text:match("^(.-) ([%d%.]+) ([%d%.]+)$")
            return { data = { zone = zone, x = tonumber(x) / 100, y = tonumber(y) / 100 }, name = text }
        end,
        Target = function(result) return { data = result.data, name = result.name } end,
    },
    Planner = { Inspect = function(target) fg.panelTarget = target end },
    Window = { Show = function() end, ShowRoute = function() end },
    Bridge = { ActiveRoute = function() return fg.journey and not fg.journey.arrived and fg.journey or nil end },
    StopNavigation = function() fg.stopped = fg.stopped + 1 Clear() end,
}

local ns, HME = LoadHME()
PLAYER.map, PLAYER.x, PLAYER.y = 1429, 0.42, 0.65
MAPS[1429].w, MAPS[1429].h = nil, nil
HME.Player.Refresh()
local G = HME.Guidance

local function FarmFar()
    local res = HME.Recommend.Find({ prof = "Mining", goal = "level" }, nil, HME.Player.Profile())
    for _, r in ipairs(res) do if r.mapID ~= 1429 and r.mapID ~= 1436 then return r end end
end
local function StartFar(r)
    G.StartResult(r, "level")
    for _ = 1, 4000 do
        Tick(0.016)
        if G.Active() then break end
    end
    return G.Active()
end
-- Where Forever-GPS's panel was sent (the destination HME asked for).
local function Requested()
    local d = fg.panelTarget.data
    return { mapID = HME.ZoneData.MapID(d.zone), x = d.x, y = d.y }
end
local far = FarmFar()
check(far, "a far farm")

STEP("1. HME's request: the journey becomes HME's only when that destination starts")
local g = StartFar(far)
eq(g.owner, "fgps", "Forever-GPS was asked")
check(not HME.Arrow.Shown(), "HME's arrow hidden")
eq(HME.FGPS.State(), "pending", "waiting for the player to press Go")
Press(Requested())
eq(HME.FGPS.State(), "active", "the started journey matches the request")
Emit("route:started", Requested())   -- the same event twice
eq(HME.FGPS.State(), "active", "duplicate delivery changes nothing")

STEP("2. no session clock while travelling")
check(not HME.Session.Current(), "travel is not farming")

STEP("6. arrival hands over cleanly; the linger clear is not a cancel")
Arrive()
eq(G.Active().phase, "farm", "farming")
eq(G.Active().owner, "hme", "HME owns the loop")
Clear()   -- Forever-GPS clears its arrived route a little later
eq(G.Active().phase, "farm", "the clear after arrival is not a cancellation")
check(HME.Arrow.Shown(), "HME's arrow round the loop")
G.Stop()

STEP("7. the player picks another destination in Forever-GPS: HME steps back for good")
g = StartFar(far)
Press(Requested())
local elsewhere = { mapID = 1453, x = 0.6, y = 0.6 }
Press(elsewhere)
eq(HME.FGPS.State(), "superseded", "the new journey is not HME's")
eq(G.Active().owner, nil, "nobody owned by HME")
check(not HME.Arrow.Shown(), "no HME arrow")
Arrive()   -- arriving at the OTHER place
eq(G.Active().phase, "travel", "arriving elsewhere is not arriving at the farm")
local before = fg.stopped
G.Stop()
eq(fg.stopped, before, "stopping HME's farm never stops the player's journey")
check(fg.journey ~= nil, "their journey is untouched")
Clear()

STEP("cancelling HME's journey does not bring back HME's arrow")
g = StartFar(far)
Press(Requested())
Clear()   -- the player cancels before arriving
eq(HME.FGPS.State(), "cancelled", "cancelled")
eq(G.Active().owner, nil, "nobody navigates")
check(not HME.Arrow.Shown(), "no arrow by itself")
G.Stop()

STEP("walking in while HME's own journey runs: HME releases only its journey")
g = StartFar(far)
Press(Requested())
local route = G.Route(G.Active().routeID)
PLAYER.map, PLAYER.x, PLAYER.y = route.mapID, route.points[1], route.points[2]
before = fg.stopped
Tick(1.1)
eq(G.Active().phase, "farm", "near the loop: farming")
eq(fg.stopped, before + 1, "HME's own journey stopped, so its arrow goes")
eq(HME.FGPS.State(), "released", "released")
G.Stop()

STEP("walking in while ANOTHER journey runs: guidance offered, nothing hijacked")
PLAYER.map, PLAYER.x, PLAYER.y = 1429, 0.42, 0.65
g = StartFar(far)
Press(elsewhere)          -- the player went somewhere else instead
PLAYER.map, PLAYER.x, PLAYER.y = route.mapID, route.points[1], route.points[2]
before = fg.stopped
Tick(1.1)
eq(G.Active().phase, "farm", "at the farm")
eq(fg.stopped, before, "the other journey keeps running")
check(G.Active().arrowHeld, "HME's arrow waits")
check(not HME.Arrow.Shown(), "never two arrows")
G.TakeOver()
check(HME.Arrow.Shown(), "the player can ask HME to guide here")
eq(fg.stopped, before, "still without stopping their journey")
Clear()
G.Stop()

STEP("reload: stale ownership is detected")
PLAYER.map, PLAYER.x, PLAYER.y = 1429, 0.42, 0.65
g = StartFar(far)
Press(Requested())
fg.journey = nil              -- the journey ended while the UI was reloading
HME.FGPS.Reconcile()
eq(HME.FGPS.State(), "stale", "the saved request no longer matches anything")
eq(G.Active().owner, nil, "and HME does not claim to navigate")
G.Stop()
g = StartFar(far)
Press(Requested())
HME.FGPS.Reconcile()
eq(HME.FGPS.State(), "active", "a matching journey after reload stays HME's")
G.Stop()
check(fg.journey == nil, "and stopping the farm releases that HME journey")

STEP("10. travel 10 minutes, farm 20: farming rate uses the 20")
PLAYER.map, PLAYER.x, PLAYER.y = 1429, 0.42, 0.65
g = StartFar(far)
Press(Requested())
FAKE_TIME = FAKE_TIME + 600
Tick(1.1)
Arrive()
route = G.Route(G.Active().routeID)
PLAYER.map, PLAYER.x, PLAYER.y = route.mapID, route.points[1], route.points[2]
ITEMS[2772] = { name = "Iron Ore", sell = 100 }
HME.Prices.fixed = { [2772] = { low = 1000, typical = 1000 } }
HME.Prices.Invalidate()
for _ = 1, 20 do
    HME.Signal("GATHER_LOOT", "mine", "Iron Deposit", { [2772] = 1 }, {})
    FAKE_TIME = FAKE_TIME + 60
    Tick(1.1)
end
local r = HME.Session.Rates()
near(r.farmSecs, 1200, 70, "about 20 minutes farmed")
near(r.travelSecs, 600, 30, "about 10 minutes travelled")
check(r.gph > r.tripGph * 1.3, "farming gold/h higher than trip gold/h")
local summary = HME.Session.Stop("manual")
near(summary.travelSecs, 600, 30, "travel kept in the summary")
local st = HME.db.stats[G.Active() and G.Active().key or summary.areas[1].key]
check(st and st.hours < 0.4, "the area's measured hours are farming hours only (" .. tostring(st and st.hours) .. ")")
check(st.travelHours and st.travelHours > 0.15, "travel recorded separately")
