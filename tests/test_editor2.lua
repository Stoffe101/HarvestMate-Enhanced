-- The route editor in 0.7.0: redo, moving a waypoint (shift-click, then
-- click), snapping to known nodes, versions kept by edits and rebuilds and
-- put back from the Inspector, and sharing one route without anything
-- personal in it.

local ns, HME = LoadHME()
PLAYER.map, PLAYER.x, PLAYER.y = 1429, 0.42, 0.65
CHAR.level = 36
PROFS = { { line = 393, rank = 175, max = 225 }, { line = 186, rank = 150, max = 225 } }
HME.Player.Refresh()
WorldMapFrame:Show()
local E, GP = HME.RouteEditor, HME.Routes

local mining = HME.Recommend.Find({ prof = "Mining", goal = "level" }, nil, HME.Player.Profile())
local route = HME.Planner.Create(mining[1], "level")
for _ = 1, 20000 do if not route.working then break end Tick(0.016) end
check(route.points and #route.points >= 6, "a planned mining route")
local function Copy(p) local c = {} for i, v in ipairs(p) do c[i] = v end return c end
local original = Copy(route.points)
local n0 = #route.points / 2

STEP("undo and redo")
check(E.Start(route), "editor open")
E.ToggleSnap()   -- off: the click lands where it is
check(E.State().snap == false, "snap off")
ClickMap("LeftButton", 0.5, 0.5)
eq(#route.points / 2, n0 + 1, "added")
E.Undo()
eq(#route.points / 2, n0, "undone")
E.Redo()
eq(#route.points / 2, n0 + 1, "redone")
E.Redo()
eq(#route.points / 2, n0 + 1, "nothing more to redo")
E.Undo()
ClickMap("LeftButton", 0.51, 0.52)
E.Redo()
eq(#route.points / 2, n0 + 1, "a new change clears what could be redone")

STEP("moving a waypoint: shift-click picks it up, the next click puts it down")
local x1, y1 = route.points[1], route.points[2]
check(E.Click(WorldMapFrame, "LeftButton", x1, y1, true), "picked up")
eq(E.State().moving, 1, "waypoint 1 is moving")
check(E.BarText():find("Click where waypoint 1 goes"), "the bar says what to do: " .. E.BarText())
local count = #route.points
E.Click(WorldMapFrame, "LeftButton", 0.3, 0.3, false)
eq(#route.points, count, "moved, not added")
eq(route.points[1], 0.3, "x moved")
eq(route.points[2], 0.3, "y moved")
check(E.State().moving == nil, "put down")
E.Undo()
eq(route.points[1], x1, "a move undoes too")
E.Click(WorldMapFrame, "LeftButton", x1, y1, true)
E.Click(WorldMapFrame, "RightButton", 0.3, 0.3, false)
eq(route.points[1], x1, "right-click while moving keeps the waypoint where it was")

STEP("snapping lands on a known node of the route's kinds")
E.ToggleSnap()
check(E.State().snap ~= false, "snap on")
-- A spot 8 yards from one of the route's own nodes.
local nx, ny, nname
for kind, names in pairs(route.kinds) do
    GP:EachNode(route.mapID, kind, function(x, y, name) if not nx and names[name] then nx, ny, nname = x, y, name end end)
end
check(nx, "a known node of the route's kinds")
local w = HME.Geo.MapYards(route.mapID)
local sx, sy, sname = E.Snap(route, nx + 8 / w, ny)
eq(sname, nname, "snapped to " .. tostring(nname))
check(math.abs(sx - nx) < 0.0001 and math.abs(sy - ny) < 0.0001, "onto the node")
local fx, fy, fname = E.Snap(route, nx + 300 / w, ny)
check(fname == nil or HME.Geo.Distance(route.mapID, fx, fy, nx + 300 / w, ny) <= E.SNAP_YARDS, "only within 20 yards")
local skinRoute = { mapID = route.mapID, points = Copy(original), kinds = {} }
local kx, ky, kname = E.Snap(skinRoute, nx + 8 / w, ny)
check(kname == nil and kx == nx + 8 / w, "a route without node kinds (a skinning loop) never snaps")
ClickMap("LeftButton", nx + 8 / w, ny)
check(E.BarText():find("Snapped to"), "the bar says it snapped")

STEP("Done keeps the waypoints it replaced as a version")
E.Finish()
check(route.edited, "edited")
eq(#(route.revisions or {}), 1, "one version kept")
eq(route.revisions[1].why, "before your edit")
eq(#route.revisions[1].points, #original, "the waypoints from before")
local vs = E.Versions(route)
eq(#vs, 1)
check(vs[1].text:find("before your edit"), vs[1].text)

STEP("an unchanged Done keeps no version and stays unedited")
local plain = { id = GP.db.nextID, mapID = 1429, name = "Plain", kinds = {}, sight = 0, color = { 1, 1, 1 }, shown = true,
    points = Copy(original) }
GP.db.nextID = GP.db.nextID + 1
table.insert(GP.db.routes, plain)
E.Start(plain)
ClickMap("LeftButton", 0.5, 0.5)
E.Undo()
E.Finish()
check(not plain.edited, "back where it started: not edited")
check(plain.revisions == nil, "no version")

STEP("restoring puts the old waypoints back and keeps the current ones")
local edited = Copy(route.points)
check(E.Restore(route, 1), "restored")
eq(#route.points, #original, "the old waypoints")
for i = 1, #original do if route.points[i] ~= original[i] then check(false, "point " .. i) break end end
eq(#route.revisions, 1, "the restored version leaves the list, the replaced one joins it")
eq(route.revisions[1].why, "before restoring an older version")
eq(#route.revisions[1].points, #edited)
check(route.edited, "a restored route is yours")
E.Restore(route, 1)
eq(#route.points, #edited, "and back again: nothing lost")

STEP("Rebuild keeps a version too (forced on an edited route)")
local before = #route.revisions
GP:RebuildRoute(route, true)
for _ = 1, 20000 do if not route.working then break end Tick(0.016) end
eq(#route.revisions, before + 1, "a version before the rebuild")
eq(route.revisions[#route.revisions].why, "before Rebuild")

STEP("at most 6 versions; the same waypoints are not kept twice")
for i = 1, 9 do E.Revise(route, "test " .. i, { 0.1 * (i % 9) + 0.01, 0.2, 0.3, 0.3, 0.5, 0.5 }) end
eq(#route.revisions, E.REVISIONS, "6 kept")
check(not E.Revise(route, "again", route.revisions[#route.revisions].points), "a copy of the newest is not kept")

STEP("sharing one route leaves out everything personal")
route.laps = 7
route.lapLog = { { secs = 300, gathers = 12 } }
route.stopStats = { { visits = 5, yields = 0 } }
route.recordedAt, route.recordSecs = 1700000000, 900
route.obs = { { k = "Mining", n = "Copper Vein", x = 0.4, y = 0.4 } }
local text = HME.DBM.ShareRoute(route)
check(type(text) == "string" and text:sub(1, 5) == "HME1:", "a share string")
local data = HME.DBM.ReadImport(text)
check(data and #data.routes == 1, "readable, one route")
local shared = data.routes[1]
for _, k in ipairs({ "laps", "lapLog", "stopStats", "revisions", "recordedAt", "recordSecs", "obs", "editedAt",
    "edited", "verified", "path", "terrain", "id" }) do
    check(shared[k] == nil, "no " .. k)
end
check(shared.planned == nil or (shared.planned.predicted == nil and shared.planned.key == nil and shared.planned.t == nil),
    "the plan without its prediction, key or time")
eq(#shared.points, #route.points, "the waypoints")
eq(shared.mapID, route.mapID)
check(shared.kinds and next(shared.kinds), "what it is for")

STEP("the full export leaves them out too, and an old export's are dropped on import")
local all = HME.DBM.ReadImport(HME.DBM.Export({ routes = true, taboos = true }))
for _, r in ipairs(all.routes) do
    check(r.lapLog == nil and r.stopStats == nil and r.revisions == nil and r.laps == nil, "nothing personal in " .. tostring(r.name))
end
local old = { v = 1, routes = { { name = "Old export", mapID = 1429, points = Copy(original), kinds = {}, laps = 3,
    lapLog = { { secs = 1 } }, stopStats = { {} }, revisions = { {} }, recordedAt = 1, planned = { predicted = { gph = 1 } } } } }
local added = HME.DBM.ApplyImport(old)
eq(added.routes, 1)
local got = GP.db.routes[#GP.db.routes]
eq(got.name, "Old export")
check(got.imported and got.lapLog == nil and got.stopStats == nil and got.revisions == nil and got.laps == nil
    and got.recordedAt == nil and got.planned.predicted == nil, "an older export's personal fields are not kept")

STEP("the share box says what is left out")
HME.OpenWindow("routes")
local box = GP:ShowShare(route)
check(box == text or (box and box:sub(1, 5) == "HME1:"), "shown")
local f = _G.HarvestMateEnhancedShare
check(f and f:IsShown(), "the share box is open")
check(f.note:GetText():find("Leaves out"), "it says what it leaves out")
f:Hide()

STEP("the Inspector lists versions")
local info = GP:InspectRoute(route)
check(info, "inspected")
local insp = _G.HarvestMateEnhancedRouteInspector
check(insp.text:GetText():find("Versions"), "a Versions line")
check(insp.versions:IsShown(), "the versions menu")
check(insp.share:IsShown(), "the share button")
insp:Hide()
