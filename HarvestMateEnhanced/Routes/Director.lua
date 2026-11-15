-- HarvestMate Enhanced: Routes/Director.lua (0.6.0)
-- The Route Director: loops sized to the time you have, laps measured as you
-- ride them, and stops that keep coming up empty.
--
-- Timed loops ("a 15-minute loop"): from an existing route, the longest run
-- of consecutive stops (in the route's own order, which already follows the
-- terrain) whose ride there and straight back to its first stop fits the
-- time. A lap's time is
--     yards / speed x walk factor  +  stops x seconds a stop
-- walk factor: the route's walked/straight ratio when its legs were walked
-- on Forever-GPS's grid, else 1.15 and the estimate is called rough; a stop
-- is a gather (4.5 s) for herb and ore routes, nothing extra for others
-- (fighting is not timed). The result is a NEW route next to the old one
-- (named "... · 15 min", marked as a variant of it): yours is never changed.
-- The band shown is x0.85 to x1.25 (x0.8 to x1.4 when rough), never one
-- exact minute.
--
-- Laps: while you follow a route, each time the loop comes round to its start
-- the lap is written down: time, gathers or skins, skill-ups (the newest 30
-- per route). Every stop counts its visits and how often something was
-- gathered there. A stop visited 4 times or more that never gave anything is
-- "weak": the Director offers a variant without those stops (you press it).
-- Copyright (C) 2026 HarvestMate Enhanced contributors. GPL-3.0-or-later.

local _, ns = ...
local HME = ns.HME
local U = HME.U

local D = {}
HME.RouteDirector = D

D.WALK_DEFAULT = 1.15
D.WEAK_VISITS = 4
D.MAX_LAPS = 30
D.MINUTES = { 10, 15, 20, 30 }

local function GP() return HME.Routes end
local function Yards(mapID)
    local w, h = HME.Geo.MapYards(mapID)
    return w or 1500, h or 1000
end

local function Pts(route)
    local out = {}
    local p = route.points or {}
    for i = 1, #p - 1, 2 do out[#out + 1] = { p[i], p[i + 1] } end
    return out
end

local function Gathering(route)
    local kinds = route.kinds or {}
    local prof = route.planned and route.planned.prof
    if prof == "Herbalism" or prof == "Mining" or prof == "Combined" then return true end
    return next(kinds) ~= nil and not prof
end

-- Lap model for a route: { speed, walk, perStop, rough }.
function D.Model(route)
    local speed = GP() and GP():Speed() or 7
    local walk, rough = D.WALK_DEFAULT, true
    if route.walkLength and route.length and route.length > 0 then
        walk, rough = math.max(1, route.walkLength / route.length), false
    end
    return { speed = speed, walk = walk, perStop = Gathering(route) and HME.Gathering.GATHER_SECONDS or 0, rough = rough }
end

local function Leg(a, b, w, h)
    local dx, dy = (a[1] - b[1]) * w, (a[2] - b[2]) * h
    return math.sqrt(dx * dx + dy * dy)
end

-- Seconds for a loop through these stops in order (closing back to the first).
function D.LapSecs(stops, mapID, model)
    if #stops < 2 then return 0, 0 end
    local w, h = Yards(mapID)
    local yards = 0
    for i = 1, #stops do yards = yards + Leg(stops[i], stops[i % #stops + 1], w, h) end
    return yards / model.speed * model.walk + #stops * model.perStop, yards
end

-- The plan for a loop of about `minutes` from `route`:
-- { stops, secs, low, high, yards, kept, total, whole, rough, startIndex }.
function D.Timed(route, minutes)
    local stops = Pts(route)
    local n = #stops
    if n < 3 then return nil, "the route has fewer than three stops" end
    local model = D.Model(route)
    local target = minutes * 60
    local whole = D.LapSecs(stops, route.mapID, model)
    local function Band(secs, rough)
        local lo, hi = rough and 0.8 or 0.85, rough and 1.4 or 1.25
        return secs * lo, secs * hi
    end
    if whole <= target then
        local lo, hi = Band(whole, model.rough)
        return { stops = stops, secs = whole, low = lo, high = hi, kept = n, total = n, whole = true, rough = model.rough,
            startIndex = 1 }
    end
    -- Every window of consecutive stops (wrapping), longest that fits; among
    -- equally long ones the quickest, and the one with the most gathered.
    local w, h = Yards(route.mapID)
    local stats = route.stopStats or {}
    local best
    for s = 1, n do
        local along = 0
        for len = 2, n - 1 do
            local i = (s + len - 2) % n + 1
            local j = (s + len - 1) % n + 1
            along = along + Leg(stops[i], stops[j], w, h)
            local close = Leg(stops[j], stops[s], w, h)
            local secs = (along + close) / model.speed * model.walk + len * model.perStop
            if secs > target then break end
            local got = 0
            for k = 0, len - 1 do
                local st = stats[(s + k - 1) % n + 1]
                got = got + (st and st.yields or 0)
            end
            if not best or len > best.len or (len == best.len and (got > best.got or (got == best.got and secs < best.secs))) then
                best = { start = s, len = len, secs = secs, got = got, yards = along + close }
            end
        end
    end
    if not best then return nil, "even two neighbouring stops take longer than that" end
    local out = {}
    for k = 0, best.len - 1 do out[#out + 1] = stops[(best.start + k - 1) % n + 1] end
    local lo, hi = Band(best.secs, model.rough)
    return { stops = out, secs = best.secs, low = lo, high = hi, yards = best.yards, kept = best.len, total = n,
        whole = false, rough = model.rough, startIndex = best.start }
end

-- "About 14 min (12 to 17), 9 of 22 stops" for a plan.
function D.PlanText(plan, minutes)
    local band = ("about %s (%s to %s%s)"):format(U.Duration(plan.secs), U.Duration(plan.low), U.Duration(plan.high),
        plan.rough and ", rough: terrain not walked" or "")
    if plan.whole then
        return ("The whole loop already fits %d minutes: %s a lap, all %d stops."):format(minutes, band, plan.total)
    end
    return ("%d of %d stops, %s a lap."):format(plan.kept, plan.total, band)
end

-- A copy of the route as a variant: never changes the original. Returns the new route.
function D.MakeVariant(route, stops, label, extra)
    local G = GP()
    if not (G and G.db) then return nil, "routes are not ready" end
    local base = ("%s · %s"):format(route.name, label)
    local name, k = base, 1
    while G:RouteNamed(route.mapID, name) do
        k = k + 1
        name = ("%s (%d)"):format(base, k)
    end
    local flat = {}
    for _, p in ipairs(stops) do
        flat[#flat + 1] = p[1]
        flat[#flat + 1] = p[2]
    end
    local v = {
        id = G.db.nextID, mapID = route.mapID, name = name, kinds = U.Copy(route.kinds or {}), sight = route.sight or 0,
        color = { unpack(G.COLORS[(G.db.nextColor - 1) % #G.COLORS + 1]) }, shown = true, points = flat,
        planned = route.planned and U.Copy(route.planned) or nil, source = "Route Director", edited = true,
        variantOf = route.id, variant = extra or { label = label }, nodes = #stops,
    }
    G.db.nextID = G.db.nextID + 1
    G.db.nextColor = G.db.nextColor % #G.COLORS + 1
    v.length = G:RouteLength(v)
    table.insert(G.db.routes, v)
    if HME.Terrain then HME.After(0, function() HME.Terrain.Auto(v) end) end
    G:Changed()
    return v
end

function D.MakeTimed(route, minutes)
    local plan, why = D.Timed(route, minutes)
    if not plan then return nil, why end
    if plan.whole then return route, "the whole loop fits" end
    local v = D.MakeVariant(route, plan.stops, ("%d min"):format(minutes), { kind = "timed", minutes = minutes,
        estimate = math.floor(plan.secs + 0.5), rough = plan.rough })
    return v, D.PlanText(plan, minutes)
end

-- Variants of a route (and the route it came from).
function D.Variants(route)
    local out = {}
    for _, r in ipairs((GP() and GP().db and GP().db.routes) or {}) do
        if r.variantOf == route.id then out[#out + 1] = r end
    end
    local parent
    if route.variantOf then
        for _, r in ipairs((GP() and GP().db and GP().db.routes) or {}) do
            if r.id == route.variantOf then parent = r end
        end
    end
    return out, parent
end

---------------------------------------------------------------------------
-- Laps and stops, while you follow a route
---------------------------------------------------------------------------
local function Active()
    local s = HME.Guidance and HME.Guidance.Active()
    if not (s and s.phase == "farm" and s.routeID) then return nil end
    local route = HME.Guidance.Route(s.routeID)
    if not route then return nil end
    return s, route
end

local function StopStats(route, i)
    route.stopStats = type(route.stopStats) == "table" and route.stopStats or {}
    local st = route.stopStats[i]
    if not st then
        st = { visits = 0, yields = 0 }
        route.stopStats[i] = st
    end
    return st
end

local function Counts()
    local r = HME.Session.Rates()
    if not r then return { gathers = 0, skins = 0, skillups = 0 } end
    return { gathers = (r.nodes or 0) + (r.catches or 0), skins = r.skins or 0, skillups = r.skillups or 0 }
end

-- A lap begins when farming begins, and again each time the loop comes round.
local function BeginLap(s)
    s.lapStart = HME.Now()
    s.lapCounts = Counts()
end

local function EndLap(s, route)
    if not s.lapStart then return BeginLap(s) end
    local secs = HME.Now() - s.lapStart
    local now, was = Counts(), s.lapCounts or Counts()
    if secs >= 30 then
        route.lapLog = type(route.lapLog) == "table" and route.lapLog or {}
        U.Push(route.lapLog, { t = (time and time()) or 0, secs = math.floor(secs + 0.5), gathers = now.gathers - was.gathers,
            skins = now.skins - was.skins, skillups = now.skillups - was.skillups, stops = s.stops }, D.MAX_LAPS)
        route.laps = (route.laps or 0) + 1
        HME.Signal("ROUTE_LAP", route)
    end
    BeginLap(s)
end

-- Which stop index (1-based, of the route's own points) the guidance is at.
local function Index(s, n) return ((s.stop or 1) - 1) % math.max(1, n) + 1 end

function D.OnAdvance(s, route, beforeStop, beforeLaps)
    if not (s and route) then return end
    local n = #Pts(route)
    if n == 0 then return end
    if not s.lapStart then BeginLap(s) end
    local i = ((beforeStop or 1) - 1) % n + 1
    local st = StopStats(route, i)
    st.visits = st.visits + 1
    -- Guided: the loop came round when the stop number wraps back (Guidance
    -- keeps it within 1..n) or passes a multiple of n. Adaptive: Guidance
    -- counts its own laps.
    local now, was = s.stop or 1, beforeStop or 1
    local wrapped = now < was or math.floor((now - 1) / n) > math.floor((was - 1) / n)
    if wrapped or (s.laps or 0) > (beforeLaps or 0) then EndLap(s, route) end
end

-- Hooks Guidance.Advance (loaded before this file) without changing it.
do
    local G = HME.Guidance
    local orig = G and G.Advance
    if orig then
        G.Advance = function(...)
            local s = G.Active()
            local before, laps = s and s.stop, s and s.laps
            local a, b = orig(...)
            local s2, route = Active()
            if s2 and s2 == s then HME.Try(D.OnAdvance, s2, route, before, laps) end
            return a, b
        end
    end
end
HME.Listen("GUIDANCE_CHANGED", function()
    local s = Active()
    if s and not s.lapStart then BeginLap(s) end
end)

-- A gather near a stop counts for that stop.
HME.Listen("GATHER_LOOT", function()
    local s, route = Active()
    if not s then return end
    local mapID, x, y = HME.Player.Position()
    local zm, zx, zy = HME.Geo.ZoneOf(mapID, x, y)
    if zm ~= route.mapID or not zx then return end
    local best, bd
    for i, p in ipairs(Pts(route)) do
        local d = HME.Geo.Distance(route.mapID, zx, zy, p[1], p[2])
        if d and (not bd or d < bd) then best, bd = i, d end
    end
    if best and bd <= (HME.Guidance.DEPLETED_YARDS or 35) * 1.5 then
        local st = StopStats(route, best)
        st.yields = st.yields + 1
    end
end)

-- { laps, median, best, worst, perLap = { gathers, skins, skillups } (medians),
--   weak = { stop indexes }, stops = n, expected (gathers a lap from the
--   prediction, when known) } or nil without laps.
function D.Laps(route)
    local log = type(route.lapLog) == "table" and route.lapLog or {}
    local out = { laps = #log, weak = {}, stops = #Pts(route) }
    for i = 1, out.stops do
        local st = route.stopStats and route.stopStats[i]
        if st and st.visits >= D.WEAK_VISITS and st.yields == 0 and Gathering(route) then out.weak[#out.weak + 1] = i end
    end
    if #log == 0 then return out end
    local function Median(field)
        local v = {}
        for _, l in ipairs(log) do v[#v + 1] = l[field] or 0 end
        table.sort(v)
        return v[math.floor((#v + 1) / 2)], v[1], v[#v]
    end
    out.median, out.best, out.worst = Median("secs")
    out.perLap = { gathers = (Median("gathers")), skins = (Median("skins")), skillups = (Median("skillups")) }
    local pred = route.planned and route.planned.predicted
    if pred and out.median then
        local perHour = pred.nodes or pred.skins or pred.catches
        if perHour then out.expected = perHour * out.median / 3600 end
    end
    return out
end

-- Lines for the Route Inspector.
function D.LapLines(route)
    local l = D.Laps(route)
    local lines = {}
    if l.laps == 0 then
        lines[1] = "|cff999b8fLaps|r  none recorded yet: follow the route and each lap is written down."
    else
        local what = l.perLap.gathers > 0 and ("%d gathers"):format(l.perLap.gathers) or ("%d skins"):format(l.perLap.skins)
        lines[1] = ("|cff999b8fLaps|r  %d: typically %s (best %s, slowest %s), %s a lap%s."):format(l.laps, U.Duration(l.median),
            U.Duration(l.best), U.Duration(l.worst), what,
            l.expected and ("; predicted about %.0f"):format(l.expected) or "")
    end
    if #l.weak > 0 then
        local names = {}
        for i, idx in ipairs(l.weak) do if i <= 6 then names[#names + 1] = tostring(idx) end end
        lines[#lines + 1] = ("|cfff5a345Weak stops|r  %s: visited %d+ times, never gave anything. Without them is a variant "
            .. "away (the button below)."):format(table.concat(names, ", ") .. (#l.weak > 6 and "..." or ""), D.WEAK_VISITS)
    end
    local vars, parent = D.Variants(route)
    if parent then lines[#lines + 1] = ("|cff999b8fVariant of|r  %s"):format(parent.name) end
    if #vars > 0 then
        local names = {}
        for _, v in ipairs(vars) do names[#names + 1] = v.variant and v.variant.label or v.name end
        lines[#lines + 1] = "|cff999b8fVariants|r  " .. table.concat(names, ", ")
    end
    return lines, l
end

-- A variant without the weak stops (only when there is something to drop).
function D.WithoutWeak(route)
    local l = D.Laps(route)
    if #l.weak == 0 then return nil, "no weak stops" end
    local drop = {}
    for _, i in ipairs(l.weak) do drop[i] = true end
    local keep = {}
    for i, p in ipairs(Pts(route)) do if not drop[i] then keep[#keep + 1] = p end end
    if #keep < 3 then return nil, "too few stops would be left" end
    return D.MakeVariant(route, keep, "without empty stops", { kind = "trimmed", dropped = #l.weak })
end
