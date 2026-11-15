-- Record My Route (scenario B) and recorded routes as corridors for planned
-- routes. The player's position is moved by hand; the recorder only reads it.

local ns, HME = LoadHME()
local R, GP, G, E, T = HME.Recorder, HME.Routes, HME.Guidance, HME.RouteEditor, HME.Terrain
local E_MAP = 1429

local function At(x, y, map)
    PLAYER.map, PLAYER.x, PLAYER.y = map or E_MAP, x, y
end
local function Second(n) for _ = 1, (n or 1) do RunTimers(1.0) Tick(1.0) end end
-- Rides from (x1, y1) to (x2, y2) in steps of about `yards`.
local function Ride(x1, y1, x2, y2, steps)
    for k = 1, steps do
        At(x1 + (x2 - x1) * k / steps, y1 + (y2 - y1) * k / steps)
        Second()
    end
end

STEP("start, stand still, ride: only movement is written down")
At(0.40, 0.60)
check(R.Start("Copper round"), "started")
check(R.Active())
local s = R.State()
eq(#s.points, 2, "the start")
Second(20)
eq(#s.points, 2, "standing still writes nothing")
Ride(0.40, 0.60, 0.40, 0.66, 12)   -- south, about 70 yards
local south = #s.points / 2
check(south >= 2 and south <= 4, "a straight run keeps few points (" .. south .. ")")
Ride(0.40, 0.66, 0.46, 0.66, 12)   -- a right-angle turn, then east
check(#s.points / 2 > south, "the turn is kept")
check(s.yards > 100, "distance counted: " .. s.yards)
check(s.secs >= 40, "time counted: " .. s.secs)

STEP("what you gather on the way is kept with the route")
HME.Signal("GATHER_LOOT", "mine", "Copper Vein", { [2770] = 2 })
HME.Signal("GATHER_LOOT", "mine", "Copper Vein", { [2770] = 1 })
HME.Signal("GATHER_LOOT", "herb", "Peacebloom", { [2447] = 1 })
eq(#s.obs, 3)
eq(s.obs[1].n, "Copper Vein")

STEP("pause and resume; leaving the zone pauses until you come back")
check(R.Pause())
local before = #s.points
Ride(0.46, 0.66, 0.50, 0.70, 6)
eq(#s.points, before, "nothing while paused")
check(R.Resume())
At(0.5, 0.5, 1436)      -- Westfall
Second()
eq(s.state, "paused", "left the zone: paused")
At(0.50, 0.70)
Second()
eq(s.state, "recording", "back: recording again")

STEP("a reload keeps the recording")
local saved = HarvestMateEnhancedCharDB
HME.char = HME.DBM.PrepareChar(saved)
check(R.Active(), "still recording after the saved data was read again")

STEP("riding back to the start closes a loop; stop saves a recorded route")
Ride(0.50, 0.70, 0.46, 0.60, 15)
Ride(0.46, 0.60, 0.401, 0.601, 10)
local route = R.Stop()
check(route, "saved")
check(not R.Active())
eq(route.recorded, true)
eq(route.recordedBy, "you")
eq(route.name, "Copper round")
check(route.loop, "a loop")
check(#route.points / 2 >= 4 and #route.points / 2 <= R.MAX_SAVED, "simplified: " .. #route.points / 2 .. " points")
eq(#route.obs, 3, "the gathers came along")
local seen = R.Seen(route)
eq(seen[1].name, "Copper Vein")
eq(seen[1].count, 2)
local q = E.Quality(route)
eq(q.label, "Recorded")
eq(T.Summary(route).state, "recorded", "never walked on the grid: it is the way you rode")
check(GP:RebuildRoute(route) == false, "Rebuild leaves a recording alone")

STEP("follow it later; ridden laps make it observed")
G.Start(route)
check(G.Active(), "following")
G.Stop()
route.laps = 1
eq(E.Quality(route).label, "Recorded and observed")

STEP("edit: add a waypoint, reverse, trim")
local n0 = #route.points / 2
E.Start(route)
E.AddPoint(route, 0.43, 0.63)
eq(#route.points / 2, n0 + 1, "a waypoint added")
local lastX = route.points[#route.points - 1]
E.Reverse()
E.Finish()
eq(route.points[1], lastX, "reversed")
eq(route.edited, true, "edited by you")
eq(E.Quality(route).trust, "recorded", "still a recording")
check(R.Trim(route, 2, #route.points / 2 - 1), "trimmed")
eq(#route.points / 2, n0 - 1, "one stop off each end")
check(not R.Trim(route, 3, 3), "a route needs two stops")

STEP("there and back: followed out and back, drawn along the way out")
At(0.30, 0.30)
R.Start("Out and back")
Ride(0.30, 0.30, 0.30, 0.40, 10)
Ride(0.30, 0.40, 0.36, 0.40, 10)
local ob = R.Stop()
check(ob and not ob.loop and ob.backforth, "not a loop")
local np = #ob.points / 2
eq(#G.Stops(ob), 2 * np - 2, "out and back as one loop")
local drawn = GP:DrawPoints(ob)
eq(#drawn / 2, 2 * np - 2, "the way back is drawn along the way out")

STEP("too short is not saved; cancel throws away")
At(0.2, 0.2)
R.Start()
Second(3)
eq(R.Stop(), nil, "too short")
R.Start()
Ride(0.2, 0.2, 0.2, 0.3, 10)
check(R.Cancel())
check(not R.Active())

STEP("very long rides stop at the limit and are simplified to the saved size")
local saveMax = R.MAX_RAW
R.MAX_RAW = 200
At(0.1, 0.1)
R.Start("long")
local x, y = 0.1, 0.1
for k = 1, 400 do
    if not R.Active() then break end
    x = 0.1 + (k % 40) * 0.01
    y = 0.1 + math.floor(k / 40) * 0.02 + ((k % 2) * 0.005)
    At(x, y)
    Second()
end
check(not R.Active(), "stopped at the limit")
R.MAX_RAW = saveMax
local long = GP:RouteNamed(E_MAP, "long")
check(long and #long.points / 2 <= R.MAX_SAVED, "saved within the bound")

STEP("export and import: points travel (gathers only when asked), the recording is marked imported")
local plainExport = assert(HME.DBM.ReadImport(HME.DBM.Export({ routes = true })))
for _, r in ipairs(plainExport.routes) do check(r.obs == nil, "gathers seen while recording stay home unless asked for") end
local text = HME.DBM.Export({ routes = true, gathers = true })
local data = assert(HME.DBM.ReadImport(text))
local count = #GP.db.routes
HME.DBM.ApplyImport(data)
local imported
for i = count + 1, #GP.db.routes do if GP.db.routes[i].name:find("Copper round", 1, true) then imported = GP.db.routes[i] end end
check(imported, "imported")
eq(imported.recordedBy, "import", "someone's recording, not yours")
eq(#imported.obs, 3)
eq(imported.path, nil, "no drawn polylines travel")
-- A damaged recording in the import is dropped, not trusted.
data.routes[1].points = { 0.1, 2.0, 0.2 }
data.routes[1].obs = { { x = 5, y = 0.1 }, "junk" }
local n2 = #GP.db.routes
HME.DBM.ApplyImport({ v = 1, routes = { data.routes[1] } })
eq(#GP.db.routes, n2, "bad points: not imported")

STEP("damaged recording state is dropped on load")
local bad = HME.DBM.PrepareChar({ recording = { state = "recording", points = "x" } })
eq(bad.recording, nil)

STEP("a recorded route is the preferred corridor for a planned route's legs")
-- A recording along x = 0.6, from y = 0.3 to y = 0.5, with a bend.
At(0.60, 0.30)
R.Start("Corridor")
Ride(0.60, 0.30, 0.64, 0.40, 12)
Ride(0.64, 0.40, 0.60, 0.50, 12)
local corridor = R.Stop()
check(corridor, "recorded")
local planned = { id = GP.db.nextID, mapID = E_MAP, name = "planned near the corridor", kinds = {}, sight = 0,
                  shown = true, color = { 1, 1, 1 }, points = { 0.601, 0.301, 0.601, 0.499, 0.55, 0.40 } }
GP.db.nextID = GP.db.nextID + 1
table.insert(GP.db.routes, planned)
T.Refine(planned)      -- no Forever-GPS here: the corridor alone
HME.FinishJobs()
local sum = T.Summary(planned)
check(sum and sum.corridors >= 1, "a leg follows the recording")
check(T.Text(planned):find("recorded in game", 1, true), T.Text(planned))
local via = T.Via(planned, 1, 2)
check(#via >= 1, "the leg bends with the recording")
check(math.abs(via[math.floor(#via / 2) + 1][1] - 0.6) > 0.01, "east of the straight line, as ridden")
-- Delete the recording: the corridor goes with it.
GP:DeleteRoute(corridor)
T.Assemble(planned)
eq(T.Summary(planned).corridors, 0, "no recording, no corridor")
