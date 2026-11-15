-- The Route Director: loops sized to a time (a new route, the original never
-- changed, the time as a range), laps recorded while following, stops that
-- keep coming up empty, and a variant without them.

local ns, HME = LoadHME()
PLAYER.map, PLAYER.x, PLAYER.y = 1429, 0.40, 0.50
HME.Player.Refresh()
local D, G, GP = HME.RouteDirector, HME.Guidance, HME.Routes

-- A herb loop of 24 stops round a circle in Elwynn.
local function Circle(n, r, name)
    local pts = {}
    for i = 1, n do
        local a = (i - 1) / n * 2 * math.pi
        pts[#pts + 1] = 0.40 + r * math.cos(a)
        pts[#pts + 1] = 0.50 + r * math.sin(a) * 1.5
    end
    local route = { id = GP.db.nextID, mapID = 1429, name = name or "Herb circle", kinds = { Herb = { Peacebloom = true } },
        sight = 75, color = { 1, 1, 1 }, shown = true, points = pts }
    GP.db.nextID = GP.db.nextID + 1
    route.length = GP:RouteLength(route)
    table.insert(GP.db.routes, route)
    return route
end

local route = Circle(24, 0.08)
local original = {}
for i, v in ipairs(route.points) do original[i] = v end
local whole = D.LapSecs((function() local t = {} for i = 1, #route.points, 2 do t[#t + 1] = { route.points[i], route.points[i + 1] } end return t end)(),
    1429, D.Model(route))

STEP("timed loop: the whole loop when it fits")
local plan = D.Timed(route, math.ceil(whole / 60) + 2)
check(plan.whole, "whole fits")
eq(plan.kept, 24)

STEP("timed loop: a shorter run of consecutive stops that fits")
local minutes = math.floor(whole / 60 / 2)
check(minutes >= 1, "a meaningful target: " .. minutes)
plan = D.Timed(route, minutes)
check(not plan.whole and plan.kept < 24 and plan.kept >= 2, "some stops: " .. plan.kept)
check(plan.secs <= minutes * 60, "fits the time: " .. plan.secs)
check(plan.low < plan.secs and plan.high > plan.secs, "a range, not one number")
check(plan.rough, "rough: the legs were not walked on the grid")
check(D.PlanText(plan, minutes):find("rough"), D.PlanText(plan, minutes))
-- Consecutive in the route's own order.
local idx = {}
for i = 1, #route.points, 2 do idx[route.points[i] .. ":" .. route.points[i + 1]] = (i + 1) / 2 end
local prev
for _, p in ipairs(plan.stops) do
    local i = idx[p[1] .. ":" .. p[2]]
    check(i, "a stop of the route")
    if prev then eq(i, prev % 24 + 1, "the next stop in order") end
    prev = i
end

STEP("timed loop: a new route; yours is untouched")
local count = #GP.db.routes
local v, text = D.MakeTimed(route, minutes)
check(v and v ~= route, "a variant")
eq(#GP.db.routes, count + 1)
eq(v.variantOf, route.id)
check(v.name:find("· " .. minutes .. " min"), v.name)
check(v.edited, "a rebuild never replaces its stops")
eq(#v.points, plan.kept * 2)
for i, x in ipairs(original) do eq(route.points[i], x, "original point " .. i) end
check(text and text:find("of 24 stops"), tostring(text))
local vars = D.Variants(route)
eq(#vars, 1)
local _, parent = D.Variants(v)
eq(parent, route, "the variant knows where it came from")

STEP("timed loop: walked legs make it less rough")
route.walkLength = route.length * 1.3
local walkedPlan = D.Timed(route, minutes)
check(not walkedPlan.rough, "walked")
check(walkedPlan.kept <= plan.kept + 1, "a longer walk keeps no more stops: " .. walkedPlan.kept .. " vs " .. plan.kept)
route.walkLength = nil

STEP("timed loop: refuses what cannot be")
local tiny = Circle(2, 0.05, "Two stops")
check(D.Timed(tiny, 10) == nil, "two stops: no loop")

STEP("laps: following the route writes each lap down")
G.Start(route)
local s = G.Active()
check(s, "following")
PLAYER.x, PLAYER.y = route.points[1], route.points[2]
G.BeginFarm(1)
HME.Signal("GUIDANCE_CHANGED")
s.lapStart = HME.Now()
-- Ride the loop: stand at the stop the arrow points to; guidance moves on by itself.
for _ = 1, 60 do
    local i = ((s.stop or 1) - 1) % 24 + 1
    PLAYER.x, PLAYER.y = route.points[2 * i - 1], route.points[2 * i]
    RunTimers(5)
    Tick(1.1)
    if D.Laps(route).laps >= 1 then break end
end
local laps = D.Laps(route)
eq(laps.laps, 1, "one lap")
check(laps.median >= 100, "its time: " .. tostring(laps.median))
eq(route.laps, 1)
for i = 1, 24 do eq(route.stopStats[i].visits, 1, "visited " .. i) end

STEP("laps: a gather near a stop counts for it")
PLAYER.x, PLAYER.y = route.points[5], route.points[6]
HME.Signal("GATHER_LOOT", "herb", "Peacebloom", { [2447] = 1 })
eq(route.stopStats[3].yields, 1, "stop 3 gave something")

STEP("weak stops: four visits, nothing gathered")
for i = 1, 24 do route.stopStats[i] = { visits = 5, yields = (i == 7 or i == 8) and 0 or 2 } end
laps = D.Laps(route)
eq(#laps.weak, 2)
eq(laps.weak[1], 7)
local lines = D.LapLines(route)
check(table.concat(lines, " "):find("Weak stops"), "said")
local trimmed = D.WithoutWeak(route)
check(trimmed and #trimmed.points == 22 * 2, "a variant without them")
for i, x in ipairs(original) do eq(route.points[i], x, "original kept") end
G.Stop()

STEP("hunting routes never call stops weak (no gathers there)")
local hunt = Circle(10, 0.05, "Hunt")
hunt.kinds = {}
hunt.planned = { prof = "Skinning", key = "Skinning@1429:8:10" }
for i = 1, 10 do hunt.stopStats = hunt.stopStats or {} hunt.stopStats[i] = { visits = 9, yields = 0 } end
eq(#D.Laps(hunt).weak, 0)

STEP("the Route Inspector shows laps and the timed buttons")
HME.OpenWindow("routes")
RunTimers(1)
local info = GP:InspectRoute(route)
check(info, "inspected")
local f = _G.HarvestMateEnhancedRouteInspector
check(f and f.timed and #f.timed == 4, "four timed buttons")
check(f.trim:IsShown(), "trim offered (weak stops)")

STEP("the Copilot offers the trimmed copy while you follow the route (you press it)")
G.Start(route)
G.BeginFarm(1)
HME.Copilot.Evaluate(true)
local card
for _, c in ipairs(HME.Copilot.cards) do if c.type == "route" then card = c end end
check(card and card.action.kind == "trim", "route card")
local before = #GP.db.routes
check(HME.Copilot.Run(card.action), "made")
eq(#GP.db.routes, before + 1)
G.Stop()
