-- HarvestMate Enhanced: Engine/Geo.lua
-- Yards, zones and travel. Prefers what the client measures (C_Map) and falls
-- back to Data/Zones.lua. Travel time between zones comes from Forever-GPS when
-- it is installed and has been asked (Integrations/ForeverGPS.lua fills
-- Geo.external); otherwise HME's own estimate, labelled as such:
--   same zone       straight distance x 1.25 (paths are not straight)
--   other zone      shortest chain of neighbouring zones, crossing each at
--                   about two thirds of its diagonal, plus any boat or zeppelin
--   unknown         a Forever zone with no size or neighbours: no number at all
-- Copyright (C) 2026 HarvestMate Enhanced contributors. GPL-3.0-or-later.

local _, ns = ...
local HME = ns.HME
local U = HME.U
local Z = HME.ZoneData

local Geo = {}
HME.Geo = Geo

local yardCache = {}

-- Yards across and down a map, and whether that came from the client.
function Geo.MapYards(mapID)
    if not mapID then return nil end
    local c = yardCache[mapID]
    if c then return c[1], c[2], c[3] end
    local w, h, exact
    if C_Map and C_Map.GetMapWorldSize then
        local ok, a, b = pcall(C_Map.GetMapWorldSize, mapID)
        if ok and HME.Num(a) and HME.Num(b) and a > 0 and b > 0 then w, h, exact = a, b, true end
    end
    if not w and C_Map and C_Map.GetWorldPosFromMapPos and CreateVector2D then
        local ok, _, p1 = pcall(C_Map.GetWorldPosFromMapPos, mapID, CreateVector2D(0, 0))
        local ok2, _, p2 = pcall(C_Map.GetWorldPosFromMapPos, mapID, CreateVector2D(1, 1))
        if ok and ok2 and p1 and p2 and p1.GetXY then
            local ax, ay = p1:GetXY()
            local bx, by = p2:GetXY()
            if HME.Num(ax) and HME.Num(bx) then
                w, h, exact = math.abs(ay - by), math.abs(ax - bx), true
                if w <= 0 or h <= 0 then w, h, exact = nil, nil, nil end
            end
        end
    end
    if not w then
        local z = Z.Get(mapID)
        if z and z.size then w, h, exact = z.size[1], z.size[2], false end
    end
    if not w then return nil end
    yardCache[mapID] = { w, h, exact }
    return w, h, exact
end

-- Map position (0-1) -> yards; unknown maps use 1500 x 1000 (flagged).
function Geo.ToYards(mapID, x, y)
    local w, h = Geo.MapYards(mapID)
    if not w then return x * 1500, y * 1000, false end
    return x * w, y * h, true
end

function Geo.Distance(mapID, ax, ay, bx, by)
    local w, h = Geo.MapYards(mapID)
    w, h = w or 1500, h or 1000
    return U.Dist(ax * w, ay * h, bx * w, by * h)
end

---------------------------------------------------------------------------
-- Zone level ranges: the 10th-90th percentile of the (non-elite) beasts in
-- the bundled spawn data, else Data/Zones.lua, else nil.
---------------------------------------------------------------------------
local levelCache = {}
function Geo.ZoneLevels(mapID)
    if levelCache[mapID] ~= nil then return levelCache[mapID] or nil end
    local mobs = ns.SkinningMobs and ns.SkinningMobs[mapID]
    local result
    if mobs and #mobs >= 4 then
        local levels = {}
        for _, m in ipairs(mobs) do
            if m[5] == 0 then
                local n = U.PackedCount(m[6])
                local mid = (m[3] + m[4]) / 2
                for _ = 1, math.min(n, 50) do levels[#levels + 1] = mid end
            end
        end
        if #levels >= 4 then
            result = { math.floor(U.Quantile(levels, 0.1)), math.ceil(U.Quantile(levels, 0.9)), source = "spawns" }
        end
    end
    if not result then
        local z = Z.Get(mapID)
        if z and z.levels then result = { z.levels[1], z.levels[2], source = "table" } end
    end
    levelCache[mapID] = result or false
    return result
end

---------------------------------------------------------------------------
-- Travel
---------------------------------------------------------------------------
local DETOUR = 1.25

-- Zones reachable from `from`, with the crossing time added for boats.
local function Neighbours(mapID, faction)
    local list = {}
    local z = Z.Get(mapID)
    for _, n in ipairs(z and z.near or {}) do list[#list + 1] = { n, 0 } end
    for _, c in ipairs(Z.CROSSINGS) do
        if c[3] == "Both" or c[3] == faction then
            if c[1] == mapID then list[#list + 1] = { c[2], c[4] * 60 } end
            if c[2] == mapID then list[#list + 1] = { c[1], c[4] * 60 } end
        end
    end
    return list
end

local function CrossSeconds(mapID, speed)
    local w, h = Geo.MapYards(mapID)
    if not w then return 240 end
    return math.sqrt(w * w + h * h) * 0.66 / speed
end

-- Seconds to get from (fromMap, fx, fy) to (toMap, tx, ty), and how sure:
-- returns seconds, quality ("measured", "estimate", "rough") or nil, "unknown".
function Geo.TravelTime(fromMap, fx, fy, toMap, tx, ty, opts)
    opts = opts or {}
    local speed = opts.speed or (HME.Player and HME.Player.Speed()) or 7
    local faction = opts.faction or (HME.Player and HME.Player.Faction()) or "Neutral"
    if not fromMap or not toMap then return nil, "unknown" end
    -- Forever-GPS estimates from where the player stands: only for trips that
    -- start there (opts.fromPlayer), never for a leg between two other places.
    if Geo.external and opts.fromPlayer then
        local secs, quality = Geo.external(fromMap, fx, fy, toMap, tx, ty)
        if secs then return secs, quality or "measured" end
    end
    if fromMap == toMap then
        if not (fx and tx) then return 0, "estimate" end
        local d = Geo.Distance(fromMap, fx, fy, tx, ty)
        local _, _, exact = Geo.MapYards(fromMap)
        return d * DETOUR / speed, exact and "estimate" or "rough"
    end
    -- Breadth-first over neighbouring zones (Dijkstra on crossing time).
    local dist, done = { [fromMap] = 0 }, {}
    local first = fx and 0.5 * CrossSeconds(fromMap, speed) or CrossSeconds(fromMap, speed) * 0.5
    dist[fromMap] = first
    for _ = 1, 80 do
        local best, bestD
        for id, d in pairs(dist) do
            if not done[id] and (not bestD or d < bestD) then best, bestD = id, d end
        end
        if not best then break end
        if best == toMap then
            return bestD - CrossSeconds(toMap, speed) * 0.5, "rough"
        end
        done[best] = true
        for _, nb in ipairs(Neighbours(best, faction)) do
            local id, extra = nb[1], nb[2]
            local d = bestD + extra + CrossSeconds(id, speed)
            if not dist[id] or d < dist[id] then dist[id] = d end
        end
    end
    return nil, "unknown"
end

-- Where a micro map (cave, building) sits: its zone's id and position.
function Geo.ZoneOf(mapID, x, y)
    if not (C_Map and C_Map.GetMapInfo) or not mapID then return mapID, x, y end
    local zoneType = (Enum and Enum.UIMapType and Enum.UIMapType.Zone) or 3
    local info = C_Map.GetMapInfo(mapID)
    local guard = 0
    while info and info.mapType and info.mapType > zoneType and info.parentMapID and info.parentMapID ~= 0 and guard < 5 do
        local parentID = info.parentMapID
        if x and C_Map.GetMapRectOnMap then
            local ok, l, r, t, b = pcall(C_Map.GetMapRectOnMap, info.mapID, parentID)
            if ok and HME.Num(l) and HME.Num(r) then
                x, y = l + (r - l) * x, t + (b - t) * y
            else
                x, y = nil, nil
            end
        end
        mapID = parentID
        info = C_Map.GetMapInfo(parentID)
        guard = guard + 1
    end
    return mapID, x, y
end

-- "north-west", "centre", ... for a map position; used to name farming areas.
function Geo.Compass(x, y)
    local ns_, ew = "", ""
    if y < 0.36 then ns_ = "north" elseif y > 0.64 then ns_ = "south" end
    if x < 0.36 then ew = "west" elseif x > 0.64 then ew = "east" end
    if ns_ == "" and ew == "" then return "central" end
    if ns_ ~= "" and ew ~= "" then return ns_ .. "-" .. ew end
    return ns_ .. ew
end
