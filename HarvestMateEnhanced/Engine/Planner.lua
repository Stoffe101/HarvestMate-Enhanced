-- HarvestMate Enhanced: Engine/Planner.lua
-- Turns a Farm Finder result into a saved route (Routes/Routes.lua) and
-- rebuilds it from current data when asked.
--
--   Herbalism / Mining  the area's sites for the goal; the loop passes within
--                       DETECT yards of each (you see the node and turn to it)
--   Skinning            the hunting areas' centres in circuit order, with a
--                       zig-zag through any area wider than 120 yards; the
--                       areas themselves are kept for the map's shading
--   Fishing             the zone's pools near the spot
-- The solver itself is GatherPath's (Engine/Optimize.lua), with your avoid
-- areas as walls. A planned route remembers how it was made (route.planned)
-- so Rebuild re-plans it for your skill and data at that time.
-- Copyright (C) 2026 HarvestMate Enhanced contributors. GPL-3.0-or-later.

local _, ns = ...
local HME = ns.HME
local U = HME.U
local Geo = HME.Geo

local P = {}
HME.Planner = P

P.DETECT = 75            -- planned gathering loops pass within this of each node
P.ZIGZAG = 120           -- hunting areas wider than this get a pattern inside
P.KIND = { Herbalism = "Herb Gathering", Mining = "Mining", Fishing = "Fishing" }

-- The planned description stored on a route (small and saveable).
local function Describe(r, goal)
    local d = { prof = r.prof, goal = goal, key = r.key, mapID = r.mapID, cx = U.Round(r.cx, 4), cy = U.Round(r.cy, 4),
        radius = math.floor((r.radius or 300) + 0.5), t = (time and time()) or 0 }
    if r.prof == "Skinning" and r.circuit then
        d.areas = {}
        for _, a in ipairs(r.circuit) do
            local hull = {}
            for i = 1, math.min(#(a.hull or {}), 48) do hull[i] = U.Round(a.hull[i], 4) end
            -- Up to 40 of its spawn points, evenly picked, for sweeps and density.
            local pts, step = {}, math.max(1, math.floor(#(a.points or {}) / 40))
            for i = 1, #(a.points or {}), step do
                pts[#pts + 1] = U.Round(a.points[i][1], 4)
                pts[#pts + 1] = U.Round(a.points[i][2], 4)
            end
            d.areas[#d.areas + 1] = { x = U.Round(a.cx, 4), y = U.Round(a.cy, 4), r = math.floor(a.radius + 0.5),
                spawns = a.spawns, hull = hull, pts = pts }
        end
        d.beasts = {}
        for _, t in ipairs(r.targets or {}) do d.beasts[#d.beasts + 1] = t.npcID end
    elseif r.targets then
        d.types = {}
        for _, t in ipairs(r.targets) do if t.name then d.types[t.name] = true end end
    end
    -- What was predicted, to compare with the session later.
    local m = r.metrics or {}
    d.predicted = { skill = m.skillPerHour, gph = m.gph and m.gph.typical, nodes = m.nodesPerHour,
        beasts = m.beastsPerHour, catches = m.catchesPerHour }
    return d
end
P.Describe = Describe

-- Stops for a planned route, as { {x, y}, ... } map positions (0-1).
function P.Points(route)
    local d = route.planned
    if not d then return {} end
    if d.prof == "Skinning" then return P.HuntPoints(route) end
    if d.prof == "Fishing" then return P.PoolPoints(route) end
    local profile = HME.Player.Profile()
    local w, h = Geo.MapYards(d.mapID)
    w, h = w or 1500, h or 1000
    local targets = d.goal == "material" and d.types or nil
    local weighed = HME.Gathering.Weigh(d.prof, d.mapID, profile, d.goal == "material" and "material" or d.goal, targets,
        HME.settings.priceMode or "typical")
    local reach = (d.radius or 300) * 1.25 + 60
    local pts = {}
    for _, e in ipairs(weighed) do
        if e.w > 0 and U.Dist(e[1], e[2], d.cx * w, d.cy * h) <= reach then
            pts[#pts + 1] = { e[1] / w, e[2] / h, w = e.w }
        end
    end
    -- Keep the most useful when there are too many for a sensible loop.
    if #pts > HME.Gathering.MAX_SITES then
        table.sort(pts, function(a, b) return a.w > b.w end)
        for i = #pts, HME.Gathering.MAX_SITES + 1, -1 do pts[i] = nil end
    end
    table.sort(pts, function(a, b) if a[1] ~= b[1] then return a[1] < b[1] end return a[2] < b[2] end)
    -- The kinds keep new nodes of these types joining the route as you find them.
    route.kinds = {}
    for name in pairs(d.types or {}) do
        local p = d.prof
        if p == "Combined" then p = HME.Spawns.NodeType("Herbalism", name) and "Herbalism" or "Mining" end
        local kind = P.KIND[p]
        route.kinds[kind] = route.kinds[kind] or {}
        route.kinds[kind][name] = true
    end
    return pts
end

-- Hunting circuit: one waypoint per area, and for a wide area a few
-- waypoints on its densest parts (k-means pieces of its spawn points, about
-- 90 yards apart), visited in an order that sweeps through it instead of
-- zig-zagging. Waypoints sit on spawn concentrations, not on hull corners.
function P.HuntPoints(route)
    local d = route.planned
    local w, h = Geo.MapYards(d.mapID)
    w, h = w or 1500, h or 1000
    local out = {}
    for _, a in ipairs(d.areas or {}) do
        if (a.r or 0) > P.ZIGZAG and a.pts and #a.pts >= 8 then
            local pts, members = {}, {}
            for i = 1, #a.pts - 1, 2 do
                pts[#pts + 1] = { a.pts[i] * w, a.pts[i + 1] * h }
                members[#members + 1] = #pts
            end
            local pieces = HME.Cluster.Split(pts, members, 90)
            -- Sweep order: by angle round the area's centre.
            table.sort(pieces, function(p1, p2)
                return math.atan2(p1.cy - a.y * h, p1.cx - a.x * w) < math.atan2(p2.cy - a.y * h, p2.cx - a.x * w)
            end)
            for i = 1, math.min(#pieces, 5) do out[#out + 1] = { pieces[i].cx / w, pieces[i].cy / h } end
        else
            out[#out + 1] = { a.x, a.y }
        end
    end
    -- One area alone: still a loop, round it.
    if #out == 1 then
        local a = d.areas[1]
        local r = math.max(30, (a.r or 40) * 0.6)
        out = {}
        for i = 0, 3 do
            local ang = i * math.pi / 2
            out[#out + 1] = { a.x + math.cos(ang) * r / w, a.y + math.sin(ang) * r / h }
        end
    end
    return out
end

function P.PoolPoints(route)
    local d = route.planned
    local out = {}
    for _, e in ipairs(HME.Spawns.DbNodes("Fishing", d.mapID)) do
        U.EachPacked(e[4], function(x, y)
            if Geo.Distance(d.mapID, x, y, d.cx, d.cy) <= (d.radius or 600) + 300 then out[#out + 1] = { x, y } end
        end)
    end
    return out
end

-- A route already made for this result (same farm key), if any.
function P.Existing(key)
    for _, r in ipairs((HME.Routes and HME.Routes.db and HME.Routes.db.routes) or {}) do
        if r.planned and r.planned.key == key then return r end
    end
end

local GOAL_NAMES = { level = "leveling", profit = "gold", balanced = "balanced", material = "material",
    safest = "lower risk", here = "here", near = "nearby" }

-- Makes (or rebuilds) the route for a result. done(route) when it is ready.
function P.Create(result, goal, done)
    local GP = HME.Routes
    if not (GP and GP.db) then return nil end
    local existing = P.Existing(result.key)
    if existing then
        existing.planned = Describe(result, goal)
        if existing.working then return existing end
        GP:RebuildRoute(existing)
        P.WhenBuilt(existing, done)
        return existing
    end
    local name = ("%s - %s %s"):format(result.zone or HME.ZoneData.Name(result.mapID), result.prof, GOAL_NAMES[goal] or goal)
    local route = GP:NewRoute({
        mapID = result.mapID, kinds = {}, name = name,
        sight = result.prof == "Skinning" and 0 or P.DETECT,
        planned = Describe(result, goal),
    })
    if route then P.WhenBuilt(route, done) end
    return route
end

-- Calls done(route) once the route's background build has finished.
function P.WhenBuilt(route, done)
    if not done then return end
    local f = CreateFrame("Frame")
    local waited = 0
    f:SetScript("OnUpdate", function(self, dt)
        waited = waited + dt
        if not route.working or waited > 30 then
            self:SetScript("OnUpdate", nil)
            if not route.working then done(route) end
        end
    end)
end
