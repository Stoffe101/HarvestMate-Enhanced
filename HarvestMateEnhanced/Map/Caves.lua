-- HarvestMate Enhanced: Map/Caves.lua
-- Caves: where they are and how to get in. The client gives no height or
-- collision data, so HME never guesses a cave from coordinates. It knows a
-- cave from:
--   * Gatherpedia's recorded cave outlines (its leveling guides, "caves")
--   * caves you mark: stand at the mouth, right-click a node inside on the map
--     with Shift ("cave entrance: where I stand"); nodes within CAVE_YARDS of
--     that node are that cave, and its entrance is where you stood.
-- Uses:
--   * the Farm Finder: a farm whose nodes are largely in a cave with no
--     known entrance (and no recorded cave loop) ranks lower and says so
--   * terrain: a leg into or out of a cave with an entrance goes through the
--     entrance ("cave" legs, drawn via it), never straight through rock
--   * the map: entrances are marked
-- Copyright (C) 2026 HarvestMate Enhanced contributors. GPL-3.0-or-later.

local _, ns = ...
local HME = ns.HME

local Cv = {}
HME.Caves = Cv

Cv.CAVE_YARDS = 60
Cv.MAX = 200

local guideCaves      -- [mapID] = { { poly = { x1, y1, ... } (0-1), name, recorded = true } }
local function GuideCaves()
    if guideCaves then return guideCaves end
    guideCaves = {}
    local Gd = ns.Guides
    if not Gd then return guideCaves end
    for _, prof in ipairs({ "Mining", "Herbalism", "Skinning", "Fishing" }) do
        local ok, brackets = pcall(Gd.Brackets, Gd, prof)
        for _, b in ipairs(ok and brackets or {}) do
            for _, spot in ipairs(b.spots or {}) do
                local loops = spot.mapID and Gd:CaveLoops(spot)
                for _, loop in ipairs(loops or {}) do
                    local poly = {}
                    for _, p in ipairs(loop) do poly[#poly + 1], poly[#poly + 2] = p.x / 100, p.y / 100 end
                    guideCaves[spot.mapID] = guideCaves[spot.mapID] or {}
                    table.insert(guideCaves[spot.mapID], { poly = poly, name = spot.label, recorded = true })
                end
            end
        end
    end
    return guideCaves
end

local function Mine()
    if not HME.db then return {} end
    if type(HME.db.caves) ~= "table" then HME.db.caves = {} end
    return HME.db.caves
end

local function Inside(poly, x, y)
    local n = #poly / 2
    local inside = false
    local j = n
    for i = 1, n do
        local xi, yi, xj, yj = poly[2 * i - 1], poly[2 * i], poly[2 * j - 1], poly[2 * j]
        if ((yi > y) ~= (yj > y)) and (x < (xj - xi) * (y - yi) / ((yj - yi) ~= 0 and (yj - yi) or 1e-9) + xi) then inside = not inside end
        j = i
    end
    return inside
end

-- The cave a point is in, or nil: { name, entrance = {x, y} | nil, recorded, mine }.
function Cv.At(mapID, x, y)
    if not (mapID and x and y) then return nil end
    for _, c in ipairs(Mine()[mapID] or {}) do
        local d = HME.Geo.Distance(mapID, c.x, c.y, x, y)
        if d and d <= (c.r or Cv.CAVE_YARDS) then return { name = c.name, entrance = c.entrance, mine = true, id = c.id } end
    end
    for _, c in ipairs(GuideCaves()[mapID] or {}) do
        if Inside(c.poly, x, y) then return { name = c.name, recorded = true } end
    end
    return nil
end

-- Marks a cave: nodes within CAVE_YARDS of (x, y), entered at (ex, ey).
function Cv.Mark(mapID, x, y, ex, ey, name)
    if not (mapID and x and y and ex and ey) then return nil, "where?" end
    local list = Mine()
    list[mapID] = list[mapID] or {}
    local id = (time and time()) or 0
    local c = { id = id .. ":" .. #list[mapID], x = x, y = y, r = Cv.CAVE_YARDS, entrance = { ex, ey }, name = name or "Cave" }
    table.insert(list[mapID], c)
    local total = 0
    for _, l in pairs(list) do total = total + #l end
    if total > Cv.MAX then table.remove(list[mapID], 1) end
    HME.Signal("LEARNED")
    return c
end

function Cv.Remove(mapID, id)
    local l = Mine()[mapID] or {}
    for i = #l, 1, -1 do if l[i].id == id then table.remove(l, i) HME.Signal("LEARNED") return true end end
    return false
end

function Cv.Entrances(mapID)
    local out = {}
    for _, c in ipairs(Mine()[mapID] or {}) do
        if c.entrance then out[#out + 1] = { x = c.entrance[1], y = c.entrance[2], name = c.name } end
    end
    return out
end

-- For a Farm Finder result: the share of its sites in a cave, and the share
-- in a cave nobody can say how to enter (no entrance marked, no recorded loop).
function Cv.Share(r)
    local sites = r.area and r.area.sites
    if not sites or #sites == 0 then return 0, 0 end
    local inCave, blind = 0, 0
    for _, m in ipairs(sites) do
        local s = m.site or m
        local c = s.x and Cv.At(r.mapID, s.x, s.y)
        if c then
            inCave = inCave + 1
            if not (c.entrance or c.recorded) then blind = blind + 1 end
        end
    end
    return inCave / #sites, blind / #sites
end

-- For a route leg: { status = "cave", points = { a, entrance, b }, yards }
-- when one end is in a cave with a known entrance (the other outside), or both
-- in the same cave (straight inside); nil otherwise.
function Cv.Leg(mapID, ax, ay, bx, by)
    local ca, cb = Cv.At(mapID, ax, ay), Cv.At(mapID, bx, by)
    if not (ca or cb) then return nil end
    local line = HME.Geo.Distance(mapID, ax, ay, bx, by) or 0
    if ca and cb and ca.id and ca.id == cb.id then
        return { status = "cave", points = { ax, ay, bx, by }, yards = line, straight = line }
    end
    local c = ca or cb
    if ca and cb then c = ca.entrance and ca or cb end
    if not c.entrance then return nil end
    local ex, ey = c.entrance[1], c.entrance[2]
    local yards = (HME.Geo.Distance(mapID, ax, ay, ex, ey) or 0) + (HME.Geo.Distance(mapID, ex, ey, bx, by) or 0)
    return { status = "cave", points = { ax, ay, ex, ey, bx, by }, yards = yards, straight = line }
end
