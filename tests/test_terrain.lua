-- Terrain-aware routes (scenario A). Forever-GPS's API v2 is stood in for by
-- a replay of what its REAL walking grid answered for every leg of two real
-- HME loops (tests/fixtures/fgps_terrain.lua, made by tools/terrain_fixture.lua
-- on the Forever-GPS checkout). Batches answer a frame later and can be
-- cancelled, as the real LocalPaths does. Legs the fixture does not hold get
-- "nodata": nothing is invented.

local F = dofile("tests/fixtures/fgps_terrain.lua")
local asked, batches, cancelled = 0, 0, 0
local function Key(m, ax, ay, bx, by) return ("%d:%.4f:%.4f:%.4f:%.4f"):format(m, ax, ay, bx, by) end
local terrainMaps = { [1429] = true, [1433] = true, [1437] = true }
-- Made-up ground for the reordering test only (map 1437), said so where used.
SYNTHETIC = {}
local api = { VERSION = 2 }
function api.NavigateTo() return nil, "not in this test" end
function api.HasTerrain(m) return terrainMaps[m] == true end
function api.LocalBound() return nil end
function api.LocalPaths(spec, done)
    batches = batches + 1
    local h = { state = "queued" }
    function h:Cancel() if self.state == "queued" then self.state = "cancelled" cancelled = cancelled + 1 return true end return false end
    function h:Status() return self.state end
    C_Timer.After(0.05, function()
        if h.state == "cancelled" then return end
        local out = {}
        for i, leg in ipairs(spec.legs) do
            asked = asked + 1
            local r = F.results[Key(spec.mapID, leg[1], leg[2], leg[3], leg[4])]
            if not r and SYNTHETIC[spec.mapID] then r = SYNTHETIC[spec.mapID](leg[1], leg[2], leg[3], leg[4]) end
            out[i] = r or { status = "nodata" }
        end
        h.state = "done"
        done(out, h)
    end)
    return h
end
ForeverGPS = { VERSION = "2.8.0", API = api, On = function() end }

local ns, HME = LoadHME()
local T, GP, G = HME.Terrain, HME.Routes, HME.Guidance
eq(HME.FGPS.Mode(), "api")
check(T.Available(1433), "terrain on Redridge")

local function Route(fix, extra)
    local r = { id = GP.db.nextID, mapID = fix.mapID, name = fix.name, kinds = {}, sight = 0, shown = true,
                color = { 1, 1, 1 }, points = {} }
    for i, v in ipairs(fix.points) do r.points[i] = v end
    for k, v in pairs(extra or {}) do r[k] = v end
    GP.db.nextID = GP.db.nextID + 1
    table.insert(GP.db.routes, r)
    r.length = GP:RouteLength(r)
    return r
end
local function Wait(route)
    for _ = 1, 400 do
        RunTimers(0.05)
        Tick(0.05)
        if not T.Busy(route) then return true end
    end
    return false
end

STEP("scenario A: a real Redridge ore loop is walked on the real grid, leg by leg")
local redridge = Route(F.routes[1])
local nStops = #redridge.points / 2
T.Refine(redridge)
eq(T.Summary(redridge).state, "pending", "walking in the background")
check(Wait(redridge), "finished")
local s = T.Summary(redridge)
eq(s.legs, nStops, "every leg of the loop")
eq(s.state, "partial", "two legs had no walk within reach: partly terrain-aware")
eq(s.approx, 2, "those two are approximate")
check(s.walked >= nStops - 2, "the rest follow the walking grid")
check(s.walk > s.straight * 1.1, ("the walked loop is longer than the straight lines (%.0f vs %.0f)"):format(s.walk, s.straight))
check(s.detours > 5, "several legs go round something (" .. s.detours .. ")")
check(batches == 2, "in Forever-GPS's batches of at most 64 (" .. batches .. ")")
eq(asked, nStops, "each leg asked once")

STEP("the map draws the walked way, approximate legs in the warning colour")
local path, legOf = GP:DrawPoints(redridge)
check(path ~= redridge.points and #path > #redridge.points, "more turns than stops")
local approxSeen = 0
for i = 1, #path / 2 do
    if legOf[i] and s.approxLegs[legOf[i]] then approxSeen = approxSeen + 1 end
end
check(approxSeen >= 2, "approximate legs are known to the drawing")
for i = 1, #path do check(path[i] >= 0 and path[i] <= 1, "on the map") end
-- The first leg that detours: its turns lie between its two stops in the path.
local detourLeg
for i = 1, nStops do
    local j = i % nStops + 1
    local e = T.Lookup(1433, redridge.points[2 * i - 1], redridge.points[2 * i], redridge.points[2 * j - 1], redridge.points[2 * j])
    if e and e.s == "path" and e.y / e.l > 1.5 then detourLeg = i break end
end
check(detourLeg, "a leg that goes round an obstacle")
local via = T.Via(redridge, detourLeg, detourLeg % nStops + 1)
check(#via >= 1, "with turns to follow")
local back = T.Via(redridge, detourLeg % nStops + 1, detourLeg)
eq(back[1][1], via[#via][1], "walked back: the same turns reversed")

STEP("route quality: terrain-aware is not 'verified'")
local q = HME.RouteEditor.Quality(redridge)
eq(q.label, "Partly terrain-aware")
eq(q.trust, "partial")
check(q.text:find("approximate", 1, true), q.text)
check(q.text:find("longer than the straight lines", 1, true), q.text)
redridge.laps = 2
eq(HME.RouteEditor.Quality(redridge).trust, "verified", "ridden twice: observed")
check(HME.RouteEditor.Quality(redridge).text:find("observed", 1, true))
redridge.laps = nil
check(GP:LapTime(redridge), "a lap time from the walked length")
eq(redridge.walkLength, s.walk)

STEP("the arrow follows the turns of a walked leg, then the stop")
redridge.planned = { key = "test:redridge" }
G.Start(redridge)
local st = G.Active()
st.stop, st.via = detourLeg % nStops + 1, 1
G.Present()
eq(st.present, "hme")
local target = HME.Arrow.Target and HME.Arrow.Target()
local label = HME.Arrow.label or (target and target.label)
G.PointAtStop()
local turns = #G.ViaInto(redridge, st.stop, nStops)
check(turns == #via, "the leg into the stop has its turns")
for k = 1, turns do
    eq(st.via, k, "turn " .. k)
    G.Advance()
end
eq(st.stop, detourLeg % nStops + 1, "still the same stop after its turns")
G.Advance()
eq(st.stop, detourLeg % nStops + 2, "then on to the next stop")
G.Stop()

STEP("cached legs are not walked again; changed stops are")
local before = asked
T.Refine(redridge)
check(Wait(redridge))
eq(asked, before, "nothing walked again")
-- The player moves one stop in the editor: only its two legs are new.
redridge.points[1] = redridge.points[1] + 0.002
redridge.edited = true
T.Refine(redridge)
check(Wait(redridge))
eq(asked - before, 2, "only the two changed legs were asked for")
eq(T.Summary(redridge).legs, nStops)
check(HME.RouteEditor.Quality(redridge).label == "User-corrected", "edited: user-corrected")
redridge.points[1] = redridge.points[1] - 0.002

STEP("a change while walking cancels and starts afresh")
HME.db.terrain = nil
local elwynn = Route(F.routes[2])
T.Refine(elwynn)
local c0 = cancelled
T.Refine(elwynn)
eq(cancelled, c0 + 1, "the first batch was cancelled")
check(Wait(elwynn))
eq(T.Summary(elwynn).state, "full", "every Elwynn leg walked")
check(T.Text(elwynn):find("terrain-aware", 1, true), T.Text(elwynn))

STEP("no terrain: straight lines, marked approximate, nothing invented")
local nowhere = Route({ mapID = 1436, name = "Westfall test", points = { 0.4, 0.4, 0.45, 0.42, 0.43, 0.47 } })
T.Refine(nowhere)
eq(T.Summary(nowhere).state, "unavailable")
eq(GP:DrawPoints(nowhere), nowhere.points, "drawn straight")
eq(HME.RouteEditor.Quality(nowhere).label, "Approximate")

STEP("recorded routes are never refined")
local rec = Route({ mapID = 1433, name = "rec", points = { 0.3, 0.3, 0.31, 0.3, 0.31, 0.31 } }, { recorded = true })
local before2 = asked
T.Refine(rec)
eq(asked, before2, "nothing asked")
eq(T.Summary(rec).state, "recorded")

STEP("the cache is bounded and survives a logout without the drawn polylines")
local store = T.Store()
local n = 0
for _ in pairs(store.legs) do n = n + 1 end
check(n <= T.CACHE_MAX, "bounded")
local saveMax = T.CACHE_MAX
T.CACHE_MAX = 10
T._Remember(1433, 0.1, 0.1, 0.2, 0.2, { status = "straight", straight = 10, yards = 10 })
check(#store.order <= 10, "old legs go first")
T.CACHE_MAX = saveMax
FireEvent("PLAYER_LOGOUT")
eq(elwynn.path, nil, "the polyline is not saved")
check(elwynn.terrain, "the summary is")
FireEvent("PLAYER_LOGIN")
RunTimers(2)
check(elwynn.path, "rebuilt from the cache at login")

STEP("damaged cache entries are survived")
HME.db.terrain = { legs = "junk" }
local r2 = Route({ mapID = 1433, name = "junk test", points = { 0.3, 0.3, 0.31, 0.3 } })
T.Refine(r2)
check(Wait(r2))
check(T.Summary(r2), "summary despite the damaged cache")

STEP("the hybrid pass (made-up ground): a loop crossing a ridge is reordered when the walk is really shorter")
local function Ground(bad, badMult)
    SYNTHETIC[1437] = function(ax, ay, bx, by)
        local line = HME.Geo.Distance(1437, ax, ay, bx, by)
        -- The diagonal from (0.2, 0.1) to (0.1, 0.2) crosses a ridge: three times as far round it.
        local diag = math.abs(ax + ay - 0.3) < 0.001 and math.abs(bx + by - 0.3) < 0.001 and math.abs(ax - bx) > 0.05
        if diag then return { status = "path", yards = line * 3, straight = line, points = { ax, ay, 0.12, 0.12, bx, by } } end
        if bad and bad(ax, ay, bx, by) then return { status = "detour", straight = line } end
        return { status = "straight", yards = line * (badMult or 1), straight = line, points = { ax, ay, bx, by } }
    end
end
Ground()
HME.db.terrain = nil
local cross = Route({ mapID = 1437, name = "ridge test", points = {
    0.10, 0.10,  0.20, 0.10,  0.10, 0.20,  0.20, 0.20,  0.25, 0.15,  0.15, 0.05 } })
T.Refine(cross)
check(Wait(cross))
local before = T.Summary(cross).walk
eq(T.Summary(cross).detours, 1, "one leg goes round the ridge")
local result
T.Improve(cross, function(_, ok, info) result = { ok = ok, info = info } end)
for _ = 1, 400 do HME.FinishJobs() RunTimers(0.05) Tick(0.05) if result then break end end
check(result and result.ok, "reordered: " .. tostring(result and result.info))
check(T.Summary(cross).walk < before, ("shorter walked: %.0f -> %.0f"):format(before, T.Summary(cross).walk))
eq(T.Summary(cross).detours, 0, "the ridge is no longer crossed")
eq(#cross.points, 12, "the same stops")
check(T.Text(cross):find("reordered round the terrain", 1, true), T.Text(cross))

STEP("the hybrid pass keeps the old order when the new legs are not really shorter")
Ground(function(ax, ay, bx, by) return true end)   -- every new leg turns out unwalkable
HME.db.terrain = nil
local keep = Route({ mapID = 1437, name = "ridge test 2", points = {
    0.10, 0.10,  0.20, 0.10,  0.10, 0.20,  0.20, 0.20,  0.25, 0.15,  0.15, 0.05 } })
-- Its own legs were walked before the ground "changed".
Ground()
T.Refine(keep)
check(Wait(keep))
Ground(function(ax, ay, bx, by)
    return not T.Lookup(1437, ax, ay, bx, by)
end)
local saved = {}
for i, v in ipairs(keep.points) do saved[i] = v end
result = nil
T.Improve(keep, function(_, ok, info) result = { ok = ok, info = info } end)
for _ = 1, 400 do HME.FinishJobs() RunTimers(0.05) Tick(0.05) if result then break end end
check(result and not result.ok, "not taken: " .. tostring(result and (type(result.info) == "table" and "accepted" or result.info)))
for i, v in ipairs(saved) do eq(keep.points[i], v, "the old order is back") end

STEP("the hybrid pass never reorders a route you edited or recorded")
keep.edited = true
result = nil
T.Improve(keep, function(_, ok, info) result = { ok = ok, info = info } end)
check(result and not result.ok and tostring(result.info):find("yours", 1, true), "kept")
