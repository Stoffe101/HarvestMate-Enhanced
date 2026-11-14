-- HME's guidance against Forever-GPS's ACTUAL API code (Core/API.lua from a
-- Forever-GPS checkout with the feature/public-api branch). Only the parts of
-- Forever-GPS underneath the API (its route engine) are stood in for here;
-- that engine is covered by Forever-GPS's own tests/test_api.lua on its real
-- route engine. Skipped (and says so) when no Forever-GPS checkout is found:
-- set HME_FGPS_DIR, or keep it next to this repository as ../Forever-GPS.

local dir = os.getenv("HME_FGPS_DIR") or "../Forever-GPS"
local apiPath = dir .. "/addons/ForeverGPS/Core/API.lua"
local f = io.open(apiPath, "r")
if not f then
    REAL_PRINT("  SKIPPED: no Forever-GPS checkout with Core/API.lua at " .. dir)
    return
end
f:close()

-- What API.lua uses from Forever-GPS, behaving like the real thing: a route
-- starts when the planner's plan is started; arrival, a later clear, and a
-- clear when stopped.
local topics = {}
local route, plan = nil, nil
local FG = { VERSION = "2.8.0", char = {} }
ForeverGPS = FG
function FG.On(t, fn) topics[t] = topics[t] or {} table.insert(topics[t], fn) end
function FG.Emit(t, ...) for _, fn in ipairs(topics[t] or {}) do fn(...) end end
function FG.Try(fn, ...) return pcall(fn, ...) end
local stopped = 0
FG.Bridge = {
    Ready = function() return true end,
    CanNavigate = function(data) return data and data.mapID ~= nil end,
    ActiveRoute = function() return route and not route.arrived and route or nil end,
    Stop = function() stopped = stopped + 1 route = nil FG.Emit("route:cleared") end,
    WorldPos = function() return nil end,          -- falls back to same-map matching
    DestinationOf = function(d) return d end,
}
FG.Planner = {
    Inspect = function(target)
        plan = { status = "ready", dest = target.data }
        C_Timer.After(0, function() FG.Emit("plan:done") end)
    end,
    Current = function() return plan end,
    Start = function()
        route = { dest = plan.dest }
        FG.Emit("route:started", plan.dest)
        return true
    end,
}
-- Forever-GPS's arrow modes, as Journey.ApplyArrow sets them: "held" while
-- another addon holds the arrow (API v2).
FG.arrowMode = "hud"
FG.Journey = { ApplyArrow = function() FG.arrowMode = (FG.API.ArrowHeld and FG.API.ArrowHeld()) and "held" or "hud" end }
local chunk = assert(loadfile(apiPath))
chunk("ForeverGPS", {})
check(FG.API and FG.API.VERSION >= 1, "Forever-GPS's real API loaded")
local V2 = FG.API.VERSION >= 2

local ns, HME = LoadHME()
PLAYER.map, PLAYER.x, PLAYER.y = 1429, 0.42, 0.65
MAPS[1429].w, MAPS[1429].h = nil, nil
HME.Player.Refresh()
local G = HME.Guidance
eq(HME.FGPS.Mode(), "api", "HME picks the API")

local far
for _, r in ipairs(HME.Recommend.Find({ prof = "Mining", goal = "level" }, nil, HME.Player.Profile())) do
    if r.mapID ~= 1429 and r.mapID ~= 1436 then far = r break end
end
local function StartFar()
    G.StartResult(far, "level")
    for _ = 1, 4000 do
        Tick(0.016)
        RunTimers(0.016)
        if G.Active() and HME.FGPS.State() == "active" then break end
    end
end

STEP("scenario 6 with the real API: request, start, arrival, hand-over")
StartFar()
eq(G.Active().owner, "fgps", "Forever-GPS owns the trip")
eq(HME.FGPS.State(), "active", "the API started HME's journey (start = true)")
eq(FG.API.Current().token, HME.char.fgpsRequest.apiToken, "Forever-GPS names the same token")
check(not HME.Arrow.Shown(), "one arrow")
route.arrived = true
FG.Emit("route:arrived", route.dest)
eq(G.Active().phase, "farm", "HME takes over on arrival")
FG.Emit("route:cleared")
eq(G.Active().phase, "farm", "the clear after arrival changes nothing")
G.Stop()

STEP("scenario 7 with the real API: another destination is the player's")
StartFar()
local before = stopped
FG.Planner.Inspect({ data = { mapID = 1453, x = 0.6, y = 0.6, name = "Stormwind" } })
RunTimers(0.1)
FG.Planner.Start()
eq(HME.FGPS.State(), "superseded", "HME sees its journey was replaced")
eq(G.Active().owner, nil, "HME stepped back")
G.Stop()
eq(stopped, before, "and never stopped the player's journey")
check(route ~= nil, "which still runs")
route = nil

if V2 then
STEP("scenario G with the real API v2: Guide me here beside another journey, one arrow, journey untouched")
-- The player is on their way somewhere else in Forever-GPS.
FG.Planner.Inspect({ data = { mapID = 1453, x = 0.6, y = 0.6, name = "Stormwind" } })
RunTimers(0.1)
FG.Planner.Start()
local theirs = route
StartFar()
eq(G.Active().owner, "fgps", "HME asked Forever-GPS for its farm")
-- They carry on with their own journey: HME's request is superseded when it starts.
FG.Planner.Inspect({ data = { mapID = 1453, x = 0.61, y = 0.61, name = "Stormwind bank" } })
RunTimers(0.1)
FG.Planner.Start()
theirs = route
local rr = G.Route(G.Active().routeID)
PLAYER.map, PLAYER.x, PLAYER.y = rr.mapID, rr.points[1], rr.points[2]
before = stopped
Tick(1.1)
eq(G.Active().phase, "farm", "at the farm")
eq(G.Active().present, "external", "their journey leads")
check(not HME.Arrow.Shown(), "HME's arrow waits")
eq(FG.arrowMode, "hud", "Forever-GPS's arrow is up")
G.TakeOver()
eq(G.Active().present, "hme", "the player chose HME's loop")
check(HME.Arrow.Shown(), "HME's arrow")
eq(FG.arrowMode, "held", "Forever-GPS paused its arrow: one arrow")
check(FG.API.ArrowHeld(), "the hold stands in Forever-GPS")
eq(route, theirs, "their journey is untouched")
eq(stopped, before, "and was never stopped")
eq(G.ArrowOwner(), "HME")
G.GiveBack()
eq(FG.arrowMode, "hud", "handed back: Forever-GPS points again")
check(not HME.Arrow.Shown(), "and HME waits")
G.TakeOver()
eq(FG.arrowMode, "held")
-- The player starts yet another journey: their newest choice leads.
FG.Planner.Inspect({ data = { mapID = 1453, x = 0.4, y = 0.4, name = "Trade district" } })
RunTimers(0.1)
FG.Planner.Start()
eq(FG.arrowMode, "hud", "Forever-GPS let go of the hold for the new journey")
eq(G.Active().present, "external", "HME steps aside")
check(not HME.Arrow.Shown(), "one arrow")
G.TakeOver()
check(FG.API.ArrowHeld(), "held again")
G.Stop()
check(not FG.API.ArrowHeld(), "stopping HME's guidance gives the arrow back")
eq(FG.arrowMode, "hud")
eq(stopped, before, "their journey was never stopped")
route = nil
PLAYER.map, PLAYER.x, PLAYER.y = 1429, 0.42, 0.65

STEP("bags full: the nearest vendor through Forever-GPS's real API, opened for the player to start")
local searched
FG.Search = { Run = function(q)
    searched = q
    return { { name = "Hostile vendor", hostile = true }, { name = "Brog's General Goods", data = { mapID = 1453, x = 0.5, y = 0.5 } } }
end }
plan = nil
local okS, nameS = HME.FGPS.GoToService("vendor")
check(okS, "asked")
eq(searched, "nearest general goods", "Forever-GPS's own search, nearest first")
eq(nameS, "Brog's General Goods", "enemy ground passed over")
check(plan and plan.status == "ready", "the journey is planned...")
eq(route, nil, "...and not started: the player presses Go")
HME.Suggest.Add("bagsFull", "bags-live", "Bags nearly full.", { kind = "service", what = "mailbox" })
check(HME.Suggest.Run(HME.Suggest.Actionable()), "the suggestion's Do it does the same")
eq(searched, "nearest mailbox")
eq(select(2, HME.FGPS.GoToService("teleporter")), "unknown service", "unknown kinds refused")
plan = nil
end

STEP("walking in: HME releases only its own API journey")
StartFar()
local r = G.Route(G.Active().routeID)
PLAYER.map, PLAYER.x, PLAYER.y = r.mapID, r.points[1], r.points[2]
before = stopped
Tick(1.1)
eq(G.Active().phase, "farm", "farming")
eq(stopped, before + 1, "its own journey stopped through API.Release")
eq(FG.API.Status(HME.char.fgpsRequest.apiToken), "released", "Forever-GPS agrees: released")
G.Stop()
