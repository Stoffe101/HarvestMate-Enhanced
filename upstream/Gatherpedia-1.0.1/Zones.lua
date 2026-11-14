-- Gatherpedia: Zones.lua
-- "Known zones" for an item page: the item's zone list (classic 1.12 data,
-- already ordered by commonness or level) merged with the zones you have
-- gathered it in, plus faction tags.
-- Pure logic, no frames.

local ADDON_NAME, ns = ...

local Zones = {}
ns.Zones = Zones

-- Home territory. Everything else is contested (or a neutral town).
Zones.FACTION = {
    ["Elwynn Forest"] = "Alliance", ["Dun Morogh"] = "Alliance", ["Teldrassil"] = "Alliance",
    ["Westfall"] = "Alliance", ["Loch Modan"] = "Alliance", ["Darkshore"] = "Alliance",
    ["Redridge Mountains"] = "Alliance", ["Duskwood"] = "Alliance", ["Wetlands"] = "Alliance",
    ["Stormwind City"] = "Alliance", ["Ironforge"] = "Alliance", ["Darnassus"] = "Alliance",
    ["Durotar"] = "Horde", ["Mulgore"] = "Horde", ["Tirisfal Glades"] = "Horde",
    ["The Barrens"] = "Horde", ["Silverpine Forest"] = "Horde", ["Orgrimmar"] = "Horde",
    ["Thunder Bluff"] = "Horde", ["Undercity"] = "Horde",
}

-- Contested zones that lean to one side (that side's towns, few or no
-- friendly flight points for the other). Not "best" for the other faction.
Zones.LEANS = {
    Horde = { ["Stonetalon Mountains"] = true, ["Thousand Needles"] = true, ["Swamp of Sorrows"] = true },
    Alliance = {},
}

-- Zones Forever has reworked; classic node and mob placement may not match.
Zones.FOREVER_REWORKED = {
    ["Elwynn Forest"] = true, ["Dun Morogh"] = true, ["Teldrassil"] = true, ["Durotar"] = true,
    ["Mulgore"] = true, ["Tirisfal Glades"] = true, ["Wetlands"] = true, ["Desolace"] = true,
}

-- uiMapID per zone name, from the 1.60.1 client's UiMap table (zone names
-- and IDs only). Forever-new zones use their Forever IDs. Names missing here
-- fall back to the map ID Gatherpedia saw when you gathered there.
Zones.MAP_IDS = {
    ["Durotar"] = 1411, ["Mulgore"] = 1412, ["The Barrens"] = 1413, ["Alterac Mountains"] = 1416,
    ["Arathi Highlands"] = 1417, ["Badlands"] = 1418, ["Blasted Lands"] = 1419, ["Tirisfal Glades"] = 1420,
    ["Silverpine Forest"] = 1421, ["Western Plaguelands"] = 1422, ["Eastern Plaguelands"] = 1423,
    ["Hillsbrad Foothills"] = 1424, ["The Hinterlands"] = 1425, ["Dun Morogh"] = 1426, ["Searing Gorge"] = 1427,
    ["Burning Steppes"] = 1428, ["Elwynn Forest"] = 1429, ["Deadwind Pass"] = 1430, ["Duskwood"] = 1431,
    ["Loch Modan"] = 1432, ["Redridge Mountains"] = 1433, ["Stranglethorn Vale"] = 1434, ["Swamp of Sorrows"] = 1435,
    ["Westfall"] = 1436, ["Wetlands"] = 1437, ["Teldrassil"] = 1438, ["Darkshore"] = 1439, ["Ashenvale"] = 1440,
    ["Thousand Needles"] = 1441, ["Stonetalon Mountains"] = 1442, ["Desolace"] = 1443, ["Feralas"] = 1444,
    ["Dustwallow Marsh"] = 1445, ["Tanaris"] = 1446, ["Azshara"] = 1447, ["Felwood"] = 1448,
    ["Un'Goro Crater"] = 1449, ["Moonglade"] = 1450, ["Silithus"] = 1451, ["Winterspring"] = 1452,
    ["Stormwind City"] = 1453, ["Orgrimmar"] = 1454, ["Ironforge"] = 1455, ["Thunder Bluff"] = 1456,
    ["Darnassus"] = 1457, ["Undercity"] = 1458,
    -- New on Forever
    ["Mount Hyjal"] = 2482, ["Zephras Isle"] = 2521, ["Riverglades"] = 2548, ["Shen'dralas"] = 2652,
}

function Zones:MapID(zone)
    if not zone then return nil end
    return self.MAP_IDS[zone] or (ns.db and ns.db.zoneMaps and ns.db.zoneMaps[zone]) or nil
end

local function Enemy(f) return f == "Alliance" and "Horde" or "Alliance" end

-- Is this zone a good pick for the given faction? Own territory, or a
-- contested zone that doesn't lean to the other side. Never the other
-- side's home zones.
function Zones:IsBest(zone, faction)
    local home = self.FACTION[zone]
    if home then return home == faction end
    return not (self.LEANS[Enemy(faction)] or {})[zone]
end

-- Build the rows for an item page.
--   entry    item data (zones, zoneNotes)
--   counts   { [zone] = n } the player's own counts for this item (may be nil)
--   here     the player's current zone name (may be nil)
--   faction  "Alliance" or "Horde" (defaults to Alliance)
--   onlyGathered  hide zones with a count of 0
-- Returns rows { zone, n, yours, here, reworked, faction, best, note } and a
-- one-line faction hint.
function Zones:Build(entry, counts, here, faction, onlyGathered)
    counts = counts or {}
    faction = (faction == "Horde") and "Horde" or "Alliance"
    local notes = entry.zoneNotes or {}
    local rows, seen = {}, {}
    local function add(z, yours)
        if seen[z] then return end
        seen[z] = true
        local n = counts[z] or 0
        if onlyGathered and n == 0 then return end
        rows[#rows + 1] = {
            zone = z, n = n, yours = yours or nil, here = (here ~= nil and z == here) or nil,
            reworked = self.FOREVER_REWORKED[z] or nil, faction = self.FACTION[z],
            best = self:IsBest(z, faction) or nil, note = notes[z], mapID = self:MapID(z),
        }
    end
    for _, z in ipairs(entry.zones or {}) do add(z) end
    -- Zones only you have found it in, most gathered first.
    local extra = {}
    for z, n in pairs(counts) do if not seen[z] and n > 0 then extra[#extra + 1] = z end end
    table.sort(extra, function(a, b) if counts[a] == counts[b] then return a < b end return counts[a] > counts[b] end)
    for _, z in ipairs(extra) do add(z, true) end

    -- Fishing pages: lowest zone skill first, and tag each row with it.
    if (entry.prof == "Fishing" or entry.water) and #rows > 0 then
        table.sort(rows, function(a, b)
            local ca, na = Zones:FishSkill(a.zone)
            local cb, nb = Zones:FishSkill(b.zone)
            ca, cb = ca or 9999, cb or 9999
            na, nb = na or 9999, nb or 9999
            if ca ~= cb then return ca < cb end
            if na ~= nb then return na < nb end
            return a.zone < b.zone
        end)
        for _, r in ipairs(rows) do
            local c = Zones:FishSkill(r.zone)
            r.fishCast = c
            if c then
                local tag = "skill " .. c
                r.note = r.note and (r.note .. "  \194\183  " .. tag) or tag
            end
        end
    end

    -- Hint: own home zones first, then contested ones, in list order.
    local best = {}
    for pass = 1, 2 do
        for _, r in ipairs(rows) do
            if r.best and not r.yours and ((pass == 1) == (r.faction == faction)) then best[#best + 1] = r.zone end
        end
    end
    local hint
    if #rows == 0 then
        hint = nil
    elseif #best > 0 then
        local shown = {}
        for i = 1, math.min(3, #best) do shown[i] = best[i] end
        hint = faction .. ": best in " .. table.concat(shown, ", ") .. (#best > 3 and (" (+" .. (#best - 3) .. ")") or "")
    else
        hint = faction .. ": all listed zones are " .. (self:AllEnemy(rows, faction) and (Enemy(faction) .. " territory") or "contested")
    end
    return rows, hint
end

function Zones:AllEnemy(rows, faction)
    for _, r in ipairs(rows) do if r.faction ~= Enemy(faction) then return false end end
    return true
end

-- Open-water fishing skill by zone. `noGetaway` is the Classic / El's
-- Extreme Anglin' and Wowhead Classic "skill required to stop get-aways"
-- (https://www.wowhead.com/classic/skill=356/fishing,
-- https://www.elsanglin.com/the_role_of_skill.html). The skill to have a
-- chance of landing a catch is max(1, noGetaway - 95), which is also the
-- "minimum skill" listed for capital cities and starting zones in
-- WoW Forever leveling guides (wowforever.be, 60.tools, elitistgaming):
-- Stormwind canals are skill 1.
--
-- Subzone exceptions (Jaguero Isle 300, Bay of Storms / Jademir Lake 425)
-- are noted but not stored as zone-wide values. Zones not in this table
-- are unconfirmed; we do not invent a number.
Zones.FISH_NO_GETAWAY = {
    -- 25: starting zones (cast min 1)
    ["Dun Morogh"] = 25, ["Durotar"] = 25, ["Elwynn Forest"] = 25,
    ["Mulgore"] = 25, ["Teldrassil"] = 25, ["Tirisfal Glades"] = 25,
    -- 75: 10-20 zones and capital cities (cast min 1)
    ["The Barrens"] = 75, ["Darkshore"] = 75, ["Darnassus"] = 75,
    ["Ironforge"] = 75, ["Loch Modan"] = 75, ["Orgrimmar"] = 75,
    ["Silverpine Forest"] = 75, ["Stormwind City"] = 75, ["Thunder Bluff"] = 75,
    ["Undercity"] = 75, ["Westfall"] = 75,
    -- 150: 20-30 zones (cast min 55)
    ["Ashenvale"] = 150, ["Duskwood"] = 150, ["Hillsbrad Foothills"] = 150,
    ["Redridge Mountains"] = 150, ["Stonetalon Mountains"] = 150, ["Wetlands"] = 150,
    -- 225: 30-40 zones (cast min 130)
    ["Alterac Mountains"] = 225, ["Arathi Highlands"] = 225, ["Desolace"] = 225,
    ["Dustwallow Marsh"] = 225, ["Stranglethorn Vale"] = 225,
    ["Swamp of Sorrows"] = 225, ["Thousand Needles"] = 225,
    -- 300: 40-50/55 zones (cast min 205)
    ["Azshara"] = 300, ["Felwood"] = 300, ["Feralas"] = 300,
    ["The Hinterlands"] = 300, ["Moonglade"] = 300, ["Tanaris"] = 300,
    ["Un'Goro Crater"] = 300, ["Western Plaguelands"] = 300,
    -- 425: high-end Azeroth (cast min 330). 300 skill still gets getaways.
    ["Burning Steppes"] = 425, ["Deadwind Pass"] = 425,
    ["Eastern Plaguelands"] = 425, ["Silithus"] = 425, ["Winterspring"] = 425,
}

function Zones:FishSkill(zone)
    if not zone then return nil end
    local noGet = self.FISH_NO_GETAWAY[zone]
    if not noGet then return nil end
    local castMin = noGet - 95
    if castMin < 1 then castMin = 1 end
    return castMin, noGet
end
