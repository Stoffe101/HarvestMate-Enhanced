-- HarvestMate Enhanced: Routes/Terrain.lua
-- Terrain-aware routes: each leg of a loop (stop to stop) walked on Forever-GPS's
-- walking grid (ForeverGPS.API v2, LocalPaths), so a route goes round a hill,
-- a lake or a cliff instead of straight through it. HME never searches terrain
-- itself and invents none: where the grid has no answer a leg stays a straight
-- line and is marked approximate.
--
--   T.Refine(route[, done])  walks every leg in the background (a few ms a
--                            frame, Forever-GPS's own budget); cached per leg
--   T.Path(route)            the drawn polyline (stops and the turns between),
--                            or nil while it is not walked / out of date
--   T.Via(route, from, to)   the turns between two stops, in walking order
--   T.Summary(route)         { state, legs, walked, approx, detours, walk,
--                              straight, ratio } state: "full" | "partial" |
--                              "none" | "pending" | "unavailable" | "recorded"
--   T.Improve(route[, done]) the hybrid pass: reorders round the legs that
--                            detour most when the walked loop gets shorter,
--                            and keeps the old order otherwise
--
-- Where several sources know a leg, the most trusted leads: your own edited
-- waypoints are never touched; then a route recorded in game that passes both
-- ends (yours first, then Gatherpedia's), as "corridor"; then Forever-GPS's
-- walking grid; then the straight line, marked approximate.
--
-- Legs are cached account-wide (HarvestMateEnhancedDB.terrain, bounded) by
-- their ends; a route whose points change is walked again only where its legs
-- changed. Recorded routes are already the way someone walked: never refined.
-- Copyright (C) 2026 HarvestMate Enhanced contributors. GPL-3.0-or-later.

local _, ns = ...
local HME = ns.HME

local T = {}
HME.Terrain = T

T.CACHE_MAX = 1200         -- legs kept
T.CHUNK = 16               -- legs per Forever-GPS batch (its limit is 64): a cancel or a stop change loses little
T.DETOUR = 1.5             -- a walk this much longer than the line is a detour worth showing
T.MAX_LEG = 1500           -- Forever-GPS walks no longer leg

local jobs = {}            -- [route] = { handle, sig }

local function API()
    local api = HME.FGPS and HME.FGPS.APIv2 and HME.FGPS.APIv2()
    if api and type(api.LocalPaths) == "function" then return api end
    return nil
end

function T.Available(mapID)
    local api = API()
    if not api then return false, "needs Forever-GPS 2.7 or later" end
    local ok, has = pcall(api.HasTerrain, mapID)
    if not (ok and has) then return false, "Forever-GPS has no walking grid for this map" end
    return true
end

---------------------------------------------------------------------------
-- The cache
---------------------------------------------------------------------------
local function Store()
    local db = HME.db
    if not db then return { legs = {}, order = {} } end
    local c = db.terrain
    if type(c) ~= "table" or type(c.legs) ~= "table" or type(c.order) ~= "table" then
        c = { legs = {}, order = {}, ver = 1 }
        db.terrain = c
    end
    return c
end
T.Store = Store

local function R4(v) return math.floor(v * 10000 + 0.5) / 10000 end
local function Key(mapID, ax, ay, bx, by) return ("%d:%.4f:%.4f:%.4f:%.4f"):format(mapID, ax, ay, bx, by) end
T.Key = Key

-- A leg either way round (a walk back is the same way, reversed).
local function RouteByID(id)
    for _, r in ipairs((HME.Routes and HME.Routes.db and HME.Routes.db.routes) or {}) do
        if r.id == id then return r end
    end
end

-- A corridor whose recording was deleted is no corridor any more.
local function Live(e)
    if e and e.s == "corridor" and not RouteByID(e.src) then return nil end
    return e
end

local function Lookup(mapID, ax, ay, bx, by)
    local c = Store()
    local e = Live(c.legs[Key(mapID, ax, ay, bx, by)])
    if e then return e, false end
    e = Live(c.legs[Key(mapID, bx, by, ax, ay)])
    if e then return e, true end
    return nil
end
T.Lookup = Lookup

local function Remember(mapID, ax, ay, bx, by, res)
    local c = Store()
    local key = Key(mapID, ax, ay, bx, by)
    if not c.legs[key] then
        c.order[#c.order + 1] = key
        while #c.order > T.CACHE_MAX do c.legs[table.remove(c.order, 1)] = nil end
    end
    local e = { s = res.status, y = HME.Num(res.yards), l = HME.Num(res.straight), t = HME.Now(), src = res.src }
    -- Only the turns between the ends are kept, rounded to the map's 0.0001.
    if (res.status == "path" or res.status == "corridor" or res.status == "cave") and type(res.points) == "table" and #res.points > 4 then
        local inner = {}
        for i = 3, #res.points - 2 do inner[#inner + 1] = R4(res.points[i]) end
        e.p = inner
    end
    c.legs[key] = e
    return e
end
T._Remember = Remember

function T.ClearCache()
    if HME.db then HME.db.terrain = nil end
    for _, route in ipairs((HME.Routes and HME.Routes.db and HME.Routes.db.routes) or {}) do route.path, route.terrain = nil, nil end
end

---------------------------------------------------------------------------
-- Legs of a route
---------------------------------------------------------------------------
-- A cheap fingerprint of the stops: a walked path belongs to these stops only.
local function Sig(points)
    local n, sum = #(points or {}), 0
    for i = 1, n do sum = sum + points[i] * ((i % 7) + 1) end
    return ("%d:%.4f"):format(n, sum)
end
T.Sig = Sig

local function Legs(route)
    local p = route.points or {}
    local n = math.floor(#p / 2)
    local out = {}
    if n < 2 then return out end
    local last = n == 2 and 1 or n
    for i = 1, last do
        local j = i % n + 1
        out[#out + 1] = { i = i, j = j, ax = p[2 * i - 1], ay = p[2 * i], bx = p[2 * j - 1], by = p[2 * j] }
    end
    return out
end
T.Legs = Legs

local function Yards(mapID, ax, ay, bx, by) return HME.Geo.Distance(mapID, ax, ay, bx, by) or 0 end

local GOOD = { straight = true, path = true, corridor = true, cave = true }
T.GOOD = GOOD

---------------------------------------------------------------------------
-- Recorded corridors: a leg along a route someone actually rode
---------------------------------------------------------------------------
T.CORRIDOR_REACH = 25     -- both ends this near the recorded path
T.CORRIDOR_MAX = 2.5      -- and the way along it at most this times the line

-- A recorded route made ready to search once per pass: its drawn points in
-- yards and a box round them, so a leg far from it is passed over at once
-- (a pass checks every leg against every recording on the map).
local function Prepared(r, mapID)
    local p = HME.Routes:DrawPoints(r)
    local n = math.floor(#p / 2)
    if n < 2 then return nil end
    local w, h = HME.Geo.MapYards(mapID)
    w, h = w or 1500, h or 1000
    local X, Y = {}, {}
    local x0, x1, y0, y1 = math.huge, -math.huge, math.huge, -math.huge
    for i = 1, n do
        local x, y = p[2 * i - 1] * w, p[2 * i] * h
        X[i], Y[i] = x, y
        if x < x0 then x0 = x end
        if x > x1 then x1 = x end
        if y < y0 then y0 = y end
        if y > y1 then y1 = y end
    end
    local reach = T.CORRIDOR_REACH
    return { r = r, p = p, n = n, X = X, Y = Y, w = w, h = h,
             x0 = x0 - reach, x1 = x1 + reach, y0 = y0 - reach, y1 = y1 + reach,
             closed = not (r.open or (r.loop == false and not r.backforth)) }
end

-- The recordings on a map other than `except`, ready for T.Corridor.
function T.CorridorIndex(mapID, except)
    local out = {}
    for _, r in ipairs((HME.Routes and HME.Routes.db and HME.Routes.db.routes) or {}) do
        if r ~= except and r.recorded and r.mapID == mapID and r.points and #r.points >= 4 then
            local c = Prepared(r, mapID)
            if c then out[#out + 1] = c end
        end
    end
    return out
end

-- The way along recording c from A to B, or nil.
local function Along(c, ax, ay, bx, by, line)
    local AX, AY, BX, BY = ax * c.w, ay * c.h, bx * c.w, by * c.h
    if AX < c.x0 or AX > c.x1 or AY < c.y0 or AY > c.y1 or BX < c.x0 or BX > c.x1 or BY < c.y0 or BY > c.y1 then
        return nil
    end
    local X, Y, n, p = c.X, c.Y, c.n, c.p
    local reach2 = T.CORRIDOR_REACH * T.CORRIDOR_REACH
    local ia, da, ib, db = nil, reach2, nil, reach2
    for i = 1, n do
        local dx, dy = X[i] - AX, Y[i] - AY
        local d = dx * dx + dy * dy
        if d <= da then ia, da = i, d end
        dx, dy = X[i] - BX, Y[i] - BY
        d = dx * dx + dy * dy
        if d <= db then ib, db = i, d end
    end
    if not (ia and ib) or ia == ib then return nil end
    da, db = math.sqrt(da), math.sqrt(db)
    local closed = c.closed
    local function Walk(step)
        local pts, yards, i = {}, da + db, ia
        while i ~= ib do
            local j = i + step
            if j > n then j = closed and 1 or nil elseif j < 1 then j = closed and n or nil end
            if not j then return nil end
            local dx, dy = X[j] - X[i], Y[j] - Y[i]
            yards = yards + math.sqrt(dx * dx + dy * dy)
            i = j
            if i ~= ib then pts[#pts + 1], pts[#pts + 2] = p[2 * i - 1], p[2 * i] end
        end
        return pts, yards
    end
    local best, bestY
    for _, step in ipairs({ 1, -1 }) do
        local pts, yards = Walk(step)
        if pts and (not bestY or yards < bestY) then best, bestY = pts, yards end
    end
    if not best or bestY > line * T.CORRIDOR_MAX + 20 then return nil end
    -- The recorded points nearest the ends join the leg's own ends.
    table.insert(best, 1, p[2 * ia])
    table.insert(best, 1, p[2 * ia - 1])
    best[#best + 1], best[#best + 2] = p[2 * ib - 1], p[2 * ib]
    return best, bestY
end

-- A leg along a recorded route: { status = "corridor", yards, straight,
-- points (ends included), src = route id } or nil. Yours before Gatherpedia's.
-- index: T.CorridorIndex(mapID, except), made once for many legs.
function T.Corridor(mapID, ax, ay, bx, by, except, index)
    local line = Yards(mapID, ax, ay, bx, by)
    if line < 3 then return nil end
    local best, bestRank
    for _, c in ipairs(index or T.CorridorIndex(mapID, except)) do
        local pts, yards = Along(c, ax, ay, bx, by, line)
        if pts then
            local rank = yards * (c.r.recordedBy == "you" and 1 or 1.3)
            if not bestRank or rank < bestRank then
                bestRank = rank
                local all = { ax, ay }
                for i = 1, #pts do all[#all + 1] = pts[i] end
                all[#all + 1], all[#all + 2] = bx, by
                best = { status = "corridor", yards = yards, straight = line, points = all, src = c.r.id }
            end
        end
    end
    return best
end

-- Builds route.path and route.terrain from the cache (no searching).
function T.Assemble(route)
    if route.recorded then
        route.path = nil
        route.terrain = { state = "recorded", sig = Sig(route.points) }
        return route.terrain
    end
    local legs = Legs(route)
    local path, approxLegs, legOf = {}, {}, {}
    local walked, approx, detours, missing, corridors, caves = 0, 0, 0, 0, 0, 0
    local walk, straight = 0, 0
    for k, leg in ipairs(legs) do
        local line = Yards(route.mapID, leg.ax, leg.ay, leg.bx, leg.by)
        straight = straight + line
        local e, reversed = Lookup(route.mapID, leg.ax, leg.ay, leg.bx, leg.by)
        path[#path + 1], path[#path + 2] = leg.ax, leg.ay
        legOf[#path / 2] = k
        if e and GOOD[e.s] then
            walked = walked + 1
            if e.s == "corridor" then corridors = corridors + 1 end
            if e.s == "cave" then caves = caves + 1 end
            local y = e.y or line
            walk = walk + y
            if line > 0 and y / line >= T.DETOUR then detours = detours + 1 end
            local inner = e.p
            if inner then
                if reversed then
                    for i = #inner - 1, 1, -2 do
                        path[#path + 1], path[#path + 2] = inner[i], inner[i + 1]
                        legOf[#path / 2] = k
                    end
                else
                    for i = 1, #inner - 1, 2 do
                        path[#path + 1], path[#path + 2] = inner[i], inner[i + 1]
                        legOf[#path / 2] = k
                    end
                end
            end
        else
            walk = walk + line
            if e then approx = approx + 1 approxLegs[k] = e.s else missing = missing + 1 end
        end
    end
    -- Two stops: one leg out, no closing leg; the far stop ends the line.
    if #legs == 1 then
        path[#path + 1], path[#path + 2] = legs[1].bx, legs[1].by
        legOf[#path / 2] = 1
    end
    local state
    if #legs == 0 then
        state = "none"
    elseif walked == #legs then
        state = "full"
    elseif walked > 0 then
        state = missing > 0 and "pending" or "partial"
    else
        state = missing > 0 and "pending" or "none"
    end
    local edited = route.edited and true or nil
    route.terrain = { state = state, legs = #legs, walked = walked, approx = approx, detours = detours, missing = missing,
                      walk = walk, straight = straight, ratio = straight > 0 and walk / straight or 1, corridors = corridors, caves = caves,
                      sig = Sig(route.points), approxLegs = approxLegs, edited = edited,
                      improved = route.terrain and route.terrain.improved or nil }
    route.path = walked > 0 and path or nil
    route.pathLeg = walked > 0 and legOf or nil
    if walked > 0 then route.walkLength = walk end
    return route.terrain
end

function T.Summary(route)
    local t = route and route.terrain
    if not t or t.sig ~= Sig(route.points) then return nil end
    return t
end

-- The polyline to draw: stops with the turns between, if walked for these stops.
function T.Path(route)
    local t = T.Summary(route)
    if t and route.path then return route.path end
    return nil
end

-- The turns walking from stop `from` to stop `to` (neighbours in either
-- direction), as { {x, y}, ... } without the two stops.
function T.Via(route, from, to)
    local p = route.points or {}
    if not (p[2 * from] and p[2 * to]) or not T.Summary(route) then return {} end
    local e, reversed = Lookup(route.mapID, p[2 * from - 1], p[2 * from], p[2 * to - 1], p[2 * to])
    local out = {}
    if not (e and e.p) then return out end
    local inner = e.p
    if reversed then
        for i = #inner - 1, 1, -2 do out[#out + 1] = { inner[i], inner[i + 1] } end
    else
        for i = 1, #inner - 1, 2 do out[#out + 1] = { inner[i], inner[i + 1] } end
    end
    return out
end

-- A line the editor or the map can say about a route's ground.
function T.Text(route)
    local t = T.Summary(route)
    if not t then return nil end
    if t.state == "recorded" then return "recorded in game: the way it was walked" end
    if t.state == "unavailable" then return "straight lines: " .. (t.why or "no walking grid") end
    if t.state == "pending" then return ("walking the legs on Forever-GPS's grid: %d of %d"):format(t.walked + t.approx, t.legs) end
    local parts = {}
    if t.state == "full" then parts[#parts + 1] = "terrain-aware: every leg follows the walking grid"
    elseif t.state == "partial" then parts[#parts + 1] = ("partly terrain-aware: %d of %d legs walked, %d approximate"):format(t.walked, t.legs, t.approx)
    else parts[#parts + 1] = "approximate: no leg could be walked on the grid" end
    if (t.caves or 0) > 0 then parts[#parts + 1] = ("%d leg%s through a cave entrance you marked"):format(t.caves, t.caves == 1 and "" or "s") end
    if (t.corridors or 0) > 0 then parts[#parts + 1] = ("%d leg%s along a route recorded in game"):format(t.corridors, t.corridors == 1 and "" or "s") end
    if t.detours > 0 then parts[#parts + 1] = ("%d leg%s go%s round an obstacle"):format(t.detours, t.detours == 1 and "" or "s", t.detours == 1 and "es" or "") end
    if t.ratio > 1.01 then parts[#parts + 1] = ("walk %d%% longer than the straight lines"):format((t.ratio - 1) * 100 + 0.5) end
    if t.improved then parts[#parts + 1] = ("reordered round the terrain: %s shorter"):format(HME.U.Yards(t.improved.saved)) end
    return table.concat(parts, " · ")
end

---------------------------------------------------------------------------
-- Walking the legs (Forever-GPS's batches)
---------------------------------------------------------------------------
-- Everything below runs in the background and can be stopped at any point:
--   1. a prepare job (HME's job queue, a slice per frame) settles each leg
--      from your cave entrances, recorded corridors and the cache;
--   2. the legs left are walked by Forever-GPS in batches of T.CHUNK, each
--      with a small share of the frame (T.BUDGET_MS); no new batch starts in
--      combat;
--   3. the reorder pass works on a copy of the stops and changes the route
--      in one step at the end, only if its stops did not change meanwhile.
-- T.Cancel stops all three; deleting or rebuilding a route calls it.
T.BUDGET_MS = 3           -- per frame for HME's walks (Forever-GPS's own plans take 4-12)
T.COMBAT_WAIT = 2         -- seconds between looks while in combat

local improving = {}      -- [route] = { cancelled, shadow }

function T.Cancel(route)
    local j = jobs[route]
    if j and j.handle then pcall(j.handle.Cancel, j.handle) end
    if j then j.cancelled = true end
    jobs[route] = nil
    local imp = improving[route]
    if imp then
        imp.cancelled = true
        improving[route] = nil
        if imp.shadow then T.Cancel(imp.shadow) end
    end
end

function T.Busy(route) return jobs[route] ~= nil or improving[route] ~= nil end

-- One leg before walking: a cave you marked, a recorded corridor or the
-- cache. True when the grid still has to walk it.
local function Settle(route, leg, index, grid)
    local mapID = route.mapID
    local cached = Lookup(mapID, leg.ax, leg.ay, leg.bx, leg.by)
    if not grid then
        -- Without the grid, recorded corridors still count.
        local c = T.Corridor(mapID, leg.ax, leg.ay, leg.bx, leg.by, route, index)
        if c then
            Remember(mapID, leg.ax, leg.ay, leg.bx, leg.by, c)
        elseif not cached then
            -- Straight and approximate for now; asked again once the grid is there.
            Remember(mapID, leg.ax, leg.ay, leg.bx, leg.by, { status = "nodata", straight = Yards(mapID, leg.ax, leg.ay, leg.bx, leg.by) })
        end
        return false
    end
    -- Into or out of a cave you marked: through its entrance (the grid
    -- cannot tell a cave floor from the hill above it).
    local cave = HME.Caves and HME.Caves.Leg(mapID, leg.ax, leg.ay, leg.bx, leg.by)
    if cave then
        Remember(mapID, leg.ax, leg.ay, leg.bx, leg.by, cave)
        cached = cave
    end
    -- A recorded corridor outranks the grid, also over a leg walked before.
    if not cave and not (cached and cached.s == "corridor") then
        local corridor = T.Corridor(mapID, leg.ax, leg.ay, leg.bx, leg.by, route, index)
        if corridor then
            Remember(mapID, leg.ax, leg.ay, leg.bx, leg.by, corridor)
            cached = corridor
        end
    end
    if not cached or cached.s == "nodata" then
        local line = Yards(mapID, leg.ax, leg.ay, leg.bx, leg.by)
        if line > T.MAX_LEG then
            Remember(mapID, leg.ax, leg.ay, leg.bx, leg.by, { status = "far", straight = line })
        elseif line < 3 then
            Remember(mapID, leg.ax, leg.ay, leg.bx, leg.by, { status = "straight", straight = line, yards = line })
        else
            return true
        end
    end
    return false
end

-- Step 2: Forever-GPS walks `want` in batches. job is jobs[route].
local function Walk(route, job, want, done)
    local api = API()
    local at = 1
    local started = HME.Now()
    local function Next()
        if jobs[route] ~= job then return end
        if Sig(route.points) ~= job.sig then     -- the stops changed meanwhile: walk them afresh
            jobs[route] = nil
            return T.Refine(route, done)
        end
        if at > #want then
            jobs[route] = nil
            T.Assemble(route)
            route.terrain.secs = HME.Now() - started
            HME.Perf.Add("terrain:walk", (HME.Now() - started) * 1000)
            HME.Signal("TERRAIN_CHANGED", route)
            if HME.Routes and HME.Routes.Changed then HME.Routes:Changed() end
            if done then done(route, route.terrain) end
            return
        end
        if HME.InCombat() then
            job.handle = nil
            HME.After(T.COMBAT_WAIT, Next)
            return
        end
        local chunk, legsSpec = {}, {}
        for k = at, math.min(#want, at + T.CHUNK - 1) do
            chunk[#chunk + 1] = want[k]
            legsSpec[#legsSpec + 1] = { want[k].ax, want[k].ay, want[k].bx, want[k].by }
        end
        at = at + #chunk
        local okCall, handle = pcall(api.LocalPaths, { mapID = route.mapID, legs = legsSpec, budgetMs = T.BUDGET_MS }, function(results)
            if jobs[route] ~= job then return end
            job.handle = nil
            for k, leg in ipairs(chunk) do
                local res = type(results) == "table" and results[k]
                if type(res) == "table" and type(res.status) == "string" then
                    Remember(route.mapID, leg.ax, leg.ay, leg.bx, leg.by, res)
                end
            end
            T.Assemble(route)
            HME.Signal("TERRAIN_CHANGED", route)
            Next()
        end)
        if not (okCall and handle) then
            jobs[route] = nil
            T.Assemble(route)
            if done then done(route, route.terrain) end
            return
        end
        job.handle = handle
    end
    Next()
end

-- Walks the legs not cached yet. done(route, summary) when finished (also
-- when nothing needed walking or terrain is unavailable). Returns false, why
-- without the grid (recorded corridors are still used).
function T.Refine(route, done)
    if not route or not route.points then return false end
    T.Cancel(route)
    if route.recorded then
        local s = T.Assemble(route)
        if done then done(route, s) end
        return true
    end
    local grid, why = T.Available(route.mapID)
    -- What the cache knows already, at once; the rest follows.
    T.Assemble(route)
    if not grid and route.terrain.walked == 0 then route.terrain.state, route.terrain.why = "unavailable", why end
    local job = { sig = Sig(route.points) }
    jobs[route] = job
    local legs, want = Legs(route), {}
    HME.RunJob("terrain:prepare", function()
        local index = T.CorridorIndex(route.mapID, route)
        for _, leg in ipairs(legs) do
            if jobs[route] ~= job then return end
            if Settle(route, leg, index, grid) then want[#want + 1] = leg end
            HME.Yield()
        end
    end, function()
        if jobs[route] ~= job then return end
        if Sig(route.points) ~= job.sig then
            jobs[route] = nil
            return T.Refine(route, done)
        end
        T.Assemble(route)
        if not grid or #want == 0 then
            jobs[route] = nil
            if not grid and route.terrain.walked == 0 then route.terrain.state, route.terrain.why = "unavailable", why end
            HME.Signal("TERRAIN_CHANGED", route)
            if done then done(route, route.terrain) end
            return
        end
        Walk(route, job, want, done)
    end, { fail = function() if jobs[route] == job then jobs[route] = nil end end })
    if not grid then return false, why end
    return true
end

---------------------------------------------------------------------------
-- The hybrid pass: GatherPath's loop, then the terrain's say
---------------------------------------------------------------------------
-- What a leg between stops a and b of `pts` costs to walk: the cached walk,
-- else the grid's lower bound or the straight line, whichever is more.
local function Cost(mapID, pts, a, b, api)
    local ax, ay, bx, by = pts[2 * a - 1], pts[2 * a], pts[2 * b - 1], pts[2 * b]
    local line = Yards(mapID, ax, ay, bx, by)
    local e = Lookup(mapID, ax, ay, bx, by)
    if e and GOOD[e.s] then return e.y or line, true end
    if e then return line * 3, true end          -- no walk within reach: dear
    local bound = api and api.LocalBound and select(2, pcall(api.LocalBound, mapID, ax, ay, bx, by))
    bound = HME.Num(bound)
    return math.max(line, bound or line) * 1.05, false
end

local function Reverse(points, i, j)   -- stops i..j (1-based) reversed in place
    while i < j do
        points[2 * i - 1], points[2 * j - 1] = points[2 * j - 1], points[2 * i - 1]
        points[2 * i], points[2 * j] = points[2 * j], points[2 * i]
        i, j = i + 1, j - 1
    end
end

-- 2-opt moves that take out a leg which detours (or could not be walked),
-- judged by walked legs and the grid's bounds; then the new legs are walked
-- and the new order is kept only if the walked loop really is shorter. The
-- moves are tried on a copy: the route itself changes once, at the end.
function T.Improve(route, done)
    if not route or route.recorded or route.edited or route.userOrder then
        if done then done(route, false, "this route's order is yours or recorded: kept") end
        return false
    end
    local t = T.Summary(route)
    if not (t and (t.state == "full" or t.state == "partial")) then
        if done then done(route, false, "walk the legs first") end
        return false
    end
    local api = API()
    local n = math.floor(#route.points / 2)
    if n < 5 then
        if done then done(route, false, "too few stops") end
        return false
    end
    if improving[route] then
        improving[route].cancelled = true
        if improving[route].shadow then T.Cancel(improving[route].shadow) end
    end
    local token = {}
    improving[route] = token
    local before, approxBefore = t.walk, t.approx or 0
    local startSig = Sig(route.points)
    local mapID = route.mapID
    local work = {}
    for i = 1, #route.points do work[i] = route.points[i] end
    local moves = 0
    local function Finish(ok, info)
        if improving[route] == token then improving[route] = nil end
        if done then done(route, ok, info) end
    end
    HME.RunJob("terrain:improve", function()
        for _ = 1, 2 do
            local improved = false
            for a = 1, n do
                local a2 = a % n + 1
                local cost, known = Cost(mapID, work, a, a2, api)
                local line = Yards(mapID, work[2 * a - 1], work[2 * a], work[2 * a2 - 1], work[2 * a2])
                if known and line > 0 and cost / line >= T.DETOUR then
                    local best, bestB = 0, nil
                    for b = 1, n do
                        local b2 = b % n + 1
                        if b ~= a and b ~= a2 and b2 ~= a then
                            local old = cost + Cost(mapID, work, b, b2, api)
                            local new = Cost(mapID, work, a, b, api) + Cost(mapID, work, a2, b2, api)
                            if old - new > best then best, bestB = old - new, b end
                        end
                        HME.Yield()
                        if token.cancelled then return end
                    end
                    if bestB and best > 0.02 * before then
                        local i, j = a2, bestB
                        if i > j then i, j = j + 1, a end
                        if i < j then
                            Reverse(work, i, j)
                            moves = moves + 1
                            improved = true
                        end
                    end
                end
            end
            if not improved then break end
        end
    end, function()
        if token.cancelled then return end
        if moves == 0 then return Finish(false, "no better order found") end
        -- The new legs are walked on a stand-in; the cache is shared.
        local shadow = { id = route.id, mapID = mapID, name = route.name, points = work }
        token.shadow = shadow
        T.Refine(shadow, function(_, s)
            if token.cancelled then return end
            if Sig(route.points) ~= startSig or route.edited or route.userOrder or route.recorded then
                return Finish(false, "the route changed meanwhile: kept as it is")
            end
            local after = s and s.walk
            -- A leg the grid cannot walk counts as its straight line in the
            -- walk, so a new order is taken only with no more of those.
            if after and (s.state == "full" or s.state == "partial") and after < before * 0.99
                and (s.approx or 0) <= approxBefore and (s.missing or 0) == 0 then
                local old = {}
                for i = 1, #route.points do old[i] = route.points[i] end
                for i = 1, #work do route.points[i] = work[i] end
                T.Assemble(route)
                route.length = HME.Routes and HME.Routes:RouteLength(route) or route.length
                route.terrain.improved = { before = before, after = route.terrain.walk, saved = before - route.terrain.walk, moves = moves }
                if HME.Guidance and HME.Guidance.Reindex then HME.Try(HME.Guidance.Reindex, route, old) end
                HME.Signal("TERRAIN_CHANGED", route)
                if HME.Routes and HME.Routes.Changed then HME.Routes:Changed() end
                return Finish(true, route.terrain.improved)
            end
            Finish(false, "the walked loop was not shorter: kept the old order")
        end)
    end, { fail = function() if improving[route] == token then improving[route] = nil end end })
    return true
end

-- Walks a route as soon as it is made or rebuilt (out of combat; the work is
-- spread over frames by Forever-GPS anyway).
function T.Auto(route)
    if not (route and HME.settings and HME.settings.terrain ~= false) then return end
    if HME.InCombat() then
        HME.After(5, function() T.Auto(route) end)
        return
    end
    T.Refine(route, function(r, s)
        if s and (s.state == "full" or s.state == "partial") and s.detours > 0 and not r.edited then T.Improve(r) end
    end)
end

-- The walked polylines are rebuilt from the cache at login, never saved twice.
HME.On("PLAYER_LOGOUT", function()
    for _, route in ipairs((HME.Routes and HME.Routes.db and HME.Routes.db.routes) or {}) do
        route.path, route.pathLeg = nil, nil
    end
end)
HME.On("PLAYER_LOGIN", function()
    HME.After(1, function()
        for _, route in ipairs((HME.Routes and HME.Routes.db and HME.Routes.db.routes) or {}) do
            if route.terrain and route.points then HME.Try(T.Assemble, route) end
        end
    end)
end)
