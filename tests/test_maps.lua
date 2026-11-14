-- The map: what the overlay draws (grouped where crowded, heatmap, simple),
-- corrections from the map (scenario 9), hunting areas as outlines, the
-- route editor and route quality labels, and edited routes surviving the
-- Farm Finder and Rebuild.

local ns, HME = LoadHME()
PLAYER.map, PLAYER.x, PLAYER.y = 1429, 0.42, 0.65
MAPS[1429].w, MAPS[1429].h = nil, nil
CHAR.level = 36
PROFS = { { line = 393, rank = 175, max = 225 }, { line = 186, rank = 150, max = 225 } }
HME.Player.Refresh()
local O = HME.MapOverlay
WorldMapFrame:Show()

STEP("previewing a mining farm draws its spawn points, grouped where they crowd")
local mining = HME.Recommend.Find({ prof = "Mining", goal = "level" }, nil, HME.Player.Profile())
O.Preview(mining[1])
local data = O.Collect(mining[1].mapID)
check(#data.pins > 10, "pins for the farm's sites (" .. #data.pins .. ")")
local confirmed = 0
for _, p in ipairs(data.pins) do if p[5] then confirmed = confirmed + 1 end end
eq(confirmed, 0, "all predicted until you gather there")
O.Draw()
check(O.lastCount > 0 and O.lastCount <= #data.pins, "drawn")
O.CROWD_PX = 400   -- zoomed far out: everything crowds
O.Draw()
check(O.lastGroups < #data.pins, "crowded pins become groups with a count")
O.CROWD_PX = 22

STEP("map detail: areas only, and heatmap")
HME.settings.mapDetail = "simple"
check(#O.Collect(mining[1].mapID).pins == 0, "areas only: no pins")
HME.settings.mapDetail = "heatmap"
O.Draw()
check(O.lastCount == 0, "heatmap: shading instead of pins")
HME.settings.mapDetail = "detailed"

STEP("scenario 9 from the map: right-click a wrong spawn point")
local before = #HME.Spawns.Sites("Mining", mining[1].mapID)
data = O.Collect(mining[1].mapID)
data.pins[1][8].run()
eq(#HME.Spawns.Sites("Mining", mining[1].mapID), before - 1, "that site is left out from now on")
local again = HME.Recommend.Find({ prof = "Mining", goal = "level" }, nil, HME.Player.Profile())
check(#again > 0, "rankings still work without it")

STEP("hunting areas: outlines and light fills, beasts as small dots")
local skin = HME.Recommend.Find({ prof = "Skinning", goal = "level" }, nil, HME.Player.Profile())
O.Preview(skin[1])
data = O.Collect(skin[1].mapID)
check(#data.outlines >= 1, "area boundaries")
for _, d in ipairs(data.discs) do check(d[5] <= 0.4, "fills stay light") end
check(#data.labels >= 1, "areas are labelled")
local small = true
for _, p in ipairs(data.pins) do small = small and p[7] end
check(small, "beast spawns are small dots")
local nBefore = #HME.Corrections.List()
data.pins[1][8].run()
local marks = HME.Corrections.List()
eq(#marks, nBefore + 1, "a beast can be marked from the map")
eq(marks[#marks].kind, "notHere", "for that spot only")
eq(marks[#marks].scope, "spot")
HME.Corrections.Remove(marks[#marks].id)
O.ClearPreview()

STEP("the route editor: add, remove, undo, reverse, cancel, done")
local route = HME.Planner.Create(mining[1], "level")
for _ = 1, 20000 do if not route.working then break end Tick(0.016) end
local n0 = #route.points / 2
local E = HME.RouteEditor
check(E.Start(route), "editor open")
check(E.Active(), "active")
ClickMap("LeftButton", route.points[1] + 0.01, route.points[2] + 0.01)
eq(#route.points / 2, n0 + 1, "left-click adds a waypoint")
ClickMap("RightButton", route.points[3], route.points[4])
eq(#route.points / 2, n0, "right-click removes the nearest")
E.Undo()
eq(#route.points / 2, n0 + 1, "undo brings it back")
local firstX = route.points[1]
E.Reverse()
eq(route.points[#route.points - 1], firstX, "reversed")
E.Cancel()
eq(#route.points / 2, n0, "cancel puts everything back")
check(not route.edited, "not marked edited")
E.Start(route)
ClickMap("LeftButton", 0.5, 0.5)
E.Finish()
check(route.edited, "done: edited by you")
eq(E.Quality(route).trust, "verified", "an edited route counts as verified by you")
IN_COMBAT = true
check(not E.Start(route), "no editing in combat")
IN_COMBAT = false

STEP("edited routes are protected")
ClearLog()
check(HME.Routes:RebuildRoute(route) == false, "Rebuild without confirming does nothing")
local fresh = HME.Planner.Create(mining[1], "level")
check(fresh ~= route, "the Farm Finder makes a new route instead of replanning yours")
for _ = 1, 20000 do if not fresh.working then break end Tick(0.016) end

STEP("route quality says where a route came from")
local q = E.Quality(fresh)
eq(q.trust, "approximate", "a planned route is approximate")
check(q.text:find("terrain unknown", 1, true), "and says why: " .. q.text)
fresh.laps = 2
eq(E.Quality(fresh).trust, "verified", "two laps ridden verify it")
local rec = { mapID = 1429, points = { 0.1, 0.1, 0.2, 0.1, 0.2, 0.2 }, recorded = true }
eq(E.Quality(rec).trust, "recorded", "a Gatherpedia recording is recorded")

STEP("the overlay keeps to its pin limit")
HME.settings.performance = "low"
HME.settings.nodePinsAlways = true
O.ClearPreview()
WorldMapFrame:SetMapID(1434)
O.Draw()
check(O.lastCount <= 250, "low performance: at most 250 pins (" .. tostring(O.lastCount) .. ")")
HME.settings.performance = "normal"
HME.settings.nodePinsAlways = false
