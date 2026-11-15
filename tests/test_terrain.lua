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
eq(batches, math.ceil(nStops / T.CHUNK), "in batches of T.CHUNK legs (" .. batches .. ")")
check(T.CHUNK <= 64, "within Forever-GPS's limit of 64")
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
HME.FinishJobs()          -- the prepare job is done: the first batch is out
check(T.Busy(elwynn), "walking")
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

STEP("caves: Gatherpedia's outlines are known; a cave you mark routes through its entrance")
local Cv = HME.Caves
local c1 = Cv.At(1438, 0.433, 0.58)
check(c1 and c1.recorded, "inside one of Gatherpedia's Teldrassil cave outlines")
eq(Cv.At(1438, 0.10, 0.10), nil, "not everywhere")
-- A cave of your own in Redridge: node at (0.30, 0.30), mouth at (0.31, 0.32).
local cave = Cv.Mark(1433, 0.30, 0.30, 0.31, 0.32, "Test cave")
check(cave, "marked")
local leg = Cv.Leg(1433, 0.30, 0.30, 0.36, 0.36)
eq(leg.status, "cave")
eq(#leg.points, 6, "in through the entrance")
eq(leg.points[3], 0.31)
check(leg.yards >= leg.straight, "never shorter than the line")
HME.db.terrain = nil
local cr = Route({ mapID = 1433, name = "cave route", points = { 0.30, 0.30, 0.36, 0.36, 0.34, 0.30 } })
T.Refine(cr)
check(Wait(cr))
check(T.Summary(cr).caves >= 1, "legs through the entrance")
check(T.Text(cr):find("cave entrance", 1, true), T.Text(cr))
local via = T.Via(cr, 1, 2)
eq(via[1][1], 0.31, "the arrow goes to the entrance first")
-- A farm whose nodes sit in a cave nobody can enter ranks lower and says so.
local fake = { mapID = 1438, area = { sites = { { site = { x = 0.433, y = 0.58 } }, { site = { x = 0.10, y = 0.10 } } } } }
local share, blind = Cv.Share(fake)
eq(share, 0.5, "half in a cave")
eq(blind, 0, "Gatherpedia recorded that cave: it can be followed")
Cv.Remove(1433, cave.id)
eq(Cv.At(1433, 0.30, 0.30), nil, "removed")


STEP("recorded corridors: the prepared search gives what a point-by-point search in yards gives")
-- 0.3.0's search, kept here as the reference: every recorded point, in yards.
local function RefAlong(r, mapID, ax, ay, bx, by, line)
    local function Y(a, b, c, d) return HME.Geo.Distance(mapID, a, b, c, d) or 0 end
    local p = GP:DrawPoints(r)
    local n = math.floor(#p / 2)
    local ia, da, ib, db = nil, T.CORRIDOR_REACH, nil, T.CORRIDOR_REACH
    for i = 1, n do
        local d1 = Y(ax, ay, p[2 * i - 1], p[2 * i])
        if d1 <= da then ia, da = i, d1 end
        local d2 = Y(bx, by, p[2 * i - 1], p[2 * i])
        if d2 <= db then ib, db = i, d2 end
    end
    if not (ia and ib) or ia == ib then return nil end
    local closed = not (r.open or (r.loop == false and not r.backforth))
    local best
    for _, step in ipairs({ 1, -1 }) do
        local yards, i, ok = da + db, ia, true
        while i ~= ib do
            local j = i + step
            if j > n then j = closed and 1 or nil elseif j < 1 then j = closed and n or nil end
            if not j then ok = false break end
            yards = yards + Y(p[2 * i - 1], p[2 * i], p[2 * j - 1], p[2 * j])
            i = j
        end
        if ok and (not best or yards < best) then best = yards end
    end
    if not best or best > line * T.CORRIDOR_MAX + 20 then return nil end
    return best
end
local recs = {}
for k = 1, 6 do
    local pts = {}
    for i = 0, 119 do
        local f = i / 119
        pts[#pts + 1] = 0.30 + 0.2 * f + 0.004 * math.sin(i * 0.7 + k)
        pts[#pts + 1] = 0.30 + 0.2 * f + 0.004 * math.cos(i * 0.5 * k) + 0.003 * k
    end
    recs[k] = Route({ mapID = 1437, name = "recording " .. k, points = pts }, { recorded = true, recordedBy = "you", open = (k % 2 == 0) or nil })
end
local index = T.CorridorIndex(1437)
eq(#index, 6, "every recording on the map, prepared once")
local same, found = 0, 0
for i = 1, 60 do
    local r = recs[(i % 6) + 1]
    local a, b = (i * 7) % 119 + 1, (i * 13 + 30) % 119 + 1
    local ax, ay = r.points[2 * a - 1] + 0.0003, r.points[2 * a] - 0.0002
    local bx, by = r.points[2 * b - 1] - 0.0002, r.points[2 * b] + 0.0003
    if i % 5 == 0 then bx, by = 0.9, 0.1 end      -- and some legs nowhere near a recording
    local line = HME.Geo.Distance(1437, ax, ay, bx, by)
    local want
    for _, rr in ipairs(recs) do
        local y = RefAlong(rr, 1437, ax, ay, bx, by, line)
        if y and (not want or y < want) then want = y end
    end
    local got = T.Corridor(1437, ax, ay, bx, by, nil, index)
    if want then found = found + 1 end
    if (want == nil and got == nil) or (want and got and math.abs(got.yards - want) < 1e-6) then same = same + 1 end
end
check(found >= 20, "most of those legs follow a recording (" .. found .. ")")
eq(same, 60, "the same corridor and length for every leg")

STEP("many recordings on the map: the work happens in the background job, not when the route is built")
HME.db.terrain = nil
local along = Route({ mapID = 1437, name = "along the recordings", points = {} })
for i = 1, 100 do
    local r = recs[(i % 6) + 1]
    local k = (i * 11) % 119 + 1
    along.points[#along.points + 1] = r.points[2 * k - 1]
    along.points[#along.points + 1] = r.points[2 * k]
end
T.Refine(along)
check(T.Busy(along), "building the route returns at once")
local settled = 0
for _, leg in ipairs(T.Legs(along)) do if T.Lookup(1437, leg.ax, leg.ay, leg.bx, leg.by) then settled = settled + 1 end end
eq(settled, 0, "no leg was settled while the route was built")
check(Wait(along), "then finished in the background")
local s100 = T.Summary(along)
eq(s100.legs, 100, "a 100-stop loop")
check(s100.corridors > 0, "with legs along the recordings (" .. s100.corridors .. ")")
local stats = HME.Perf.stats["job:terrain:prepare"]
check(stats == nil or stats.n >= 1, "the prepare pass ran as a job")

STEP("cancelling: a rebuild during the reorder pass is never overwritten")
Ground()
HME.db.terrain = nil
local function Cross(name)
    local r = Route({ mapID = 1437, name = name, points = {
        0.10, 0.10,  0.20, 0.10,  0.10, 0.20,  0.20, 0.20,  0.25, 0.15,  0.15, 0.05 } })
    T.Refine(r)
    check(Wait(r), "walked")
    return r
end
local c2 = Cross("ridge rebuilt")
result = nil
T.Improve(c2, function(_, ok, info) result = { ok = ok, info = info } end)
check(T.Busy(c2), "reordering in the background")
-- The route is rebuilt meanwhile (new stops), without going through Cancel.
local rebuilt = { 0.11, 0.11, 0.21, 0.11, 0.11, 0.21, 0.21, 0.21, 0.26, 0.16, 0.16, 0.06 }
for i, v in ipairs(rebuilt) do c2.points[i] = v end
for _ = 1, 400 do HME.FinishJobs() RunTimers(0.05) Tick(0.05) if result then break end end
check(result and not result.ok and tostring(result.info):find("changed meanwhile", 1, true), "refused: " .. tostring(result and result.info))
for i, v in ipairs(rebuilt) do eq(c2.points[i], v, "the rebuilt stops are left as they are") end
check(not T.Busy(c2), "nothing left running")

local c3 = Cross("ridge cancelled")
local keep3 = {}
for i, v in ipairs(c3.points) do keep3[i] = v end
result = nil
T.Improve(c3, function(_, ok, info) result = { ok = ok, info = info } end)
T.Cancel(c3)
check(not T.Busy(c3), "cancelled")
for _ = 1, 100 do HME.FinishJobs() RunTimers(0.05) Tick(0.05) end
eq(result, nil, "a cancelled pass reports nothing")
for i, v in ipairs(keep3) do eq(c3.points[i], v, "and changes nothing") end

-- Cancelled while its new legs are being walked (the second half).
local c4 = Cross("ridge cancelled while walking")
HME.db.terrain.legs, HME.db.terrain.order = {}, {}
T.Refine(c4)
check(Wait(c4))
result = nil
local b4 = batches
T.Improve(c4, function(_, ok, info) result = { ok = ok, info = info } end)
for _ = 1, 3 do HME.FinishJobs() end     -- the moves are found; the new legs go out to the grid
check(batches > b4, "the new legs were sent to the grid")
T.Cancel(c4)
for _ = 1, 100 do HME.FinishJobs() RunTimers(0.05) Tick(0.05) end
eq(result, nil, "nothing reported")
check(not T.Busy(c4), "nothing running")

STEP("deleting a route stops its walks")
HME.db.terrain = nil
local gone = Route(F.routes[2])
T.Refine(gone)
HME.FinishJobs()
check(T.Busy(gone), "walking")
local cg = cancelled
GP:DeleteRoute(gone)
check(not T.Busy(gone), "stopped")
eq(cancelled, cg + 1, "its batch was cancelled")

STEP("no new batch starts in combat")
HME.db.terrain = nil
local fight = Route(F.routes[2])
IN_COMBAT = true
local bf = batches
T.Refine(fight)
for _ = 1, 20 do HME.FinishJobs() RunTimers(0.5) Tick(0.5) end
eq(batches, bf, "nothing sent to the grid while fighting")
check(T.Busy(fight), "waiting")
IN_COMBAT = false
check(Wait(fight), "after the fight it carries on")
eq(T.Summary(fight).state, "full", "every leg walked")
check(batches > bf, "in batches")
GP:DeleteRoute(fight)

STEP("the arrow keeps its stop when the reorder pass changes the order")
Ground()
local c5 = Cross("ridge followed")
c5.planned = { key = "test:ridge" }
G.Start(c5)
local st5 = G.Active()
st5.stop = 4
local wantX, wantY = c5.points[7], c5.points[8]
st5.visited = { [4] = true }
result = nil
T.Improve(c5, function(_, ok, info) result = { ok = ok, info = info } end)
for _ = 1, 400 do HME.FinishJobs() RunTimers(0.05) Tick(0.05) if result then break end end
check(result and result.ok, "reordered: " .. tostring(result and result.info))
eq(c5.points[2 * st5.stop - 1], wantX, "still the same stop (x)")
eq(c5.points[2 * st5.stop], wantY, "still the same stop (y)")
check(st5.visited[st5.stop], "and it is still marked visited")
G.Stop()
check(#(ERRORS or {}) == 0, "no errors: " .. tostring(ERRORS and ERRORS[1]))
