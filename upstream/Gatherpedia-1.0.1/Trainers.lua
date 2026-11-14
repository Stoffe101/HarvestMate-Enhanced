-- Gatherpedia: Trainers.lua
-- Where to train Herbalism, Mining, Fishing and Skinning, and where
-- to buy fishing supplies. Names, zones, coordinates and ranks are
-- public Classic and Forever locations. Stormwind uses the Forever
-- city positions (not the Classic 1.12 layout). Pure logic, no frames, so it can run outside
-- the game.

local ADDON_NAME, ns = ...

local Trainers = {}
ns.Trainers = Trainers

local function E(name, prof, faction, zone, subzone, x, y, rank, kind, note)
    return {
        name = name, prof = prof, faction = faction, zone = zone,
        subzone = subzone, x = x, y = y, rank = rank,
        kind = kind or "trainer", note = note,
    }
end

Trainers.List = {
    -- Herbalism, Alliance
    E("Tannysa", "Herbalism", "Alliance", "Stormwind City", "Mage Quarter", 54.5, 83.9, "Artisan", nil, nil),
    E("Shylamiir", "Herbalism", "Alliance", "Stormwind City", "The Park", 31.5, 63.0, "Artisan", nil, nil),
    E("Reyna Stonebranch", "Herbalism", "Alliance", "Ironforge", "The Great Forge", 55.6, 58, "Artisan", nil, nil),
    E("Firodren Mooncaller", "Herbalism", "Alliance", "Darnassus", "Temple Gardens", 47.9, 68.6, "Artisan", nil, nil),
    E("Herbalist Pomeroy", "Herbalism", "Alliance", "Elwynn Forest", "East of the Stormwind gates", 39.9, 48.4, "Artisan", nil, nil),
    E("Malorne Bladeleaf", "Herbalism", "Alliance", "Teldrassil", "Dolanaar", 57.7, 60.6, "Artisan", nil, nil),
    E("Kali Healtouch", "Herbalism", "Alliance", "Loch Modan", "Thelsamar", 36.5, 48.5, "Artisan", nil, nil),
    E("Alma Jainrose", "Herbalism", "Alliance", "Redridge Mountains", "Lakeshire", 16.8, 46.8, "Artisan", nil, nil),
    E("Cylania Rootstalker", "Herbalism", "Alliance", "Ashenvale", "Silverwind Refuge", 50.6, 67.1, "Artisan", nil, nil),
    E("Telurinon Moonshadow", "Herbalism", "Alliance", "Wetlands", "Menethil Harbor", 8, 55.8, "Artisan", nil, nil),
    E("Brant Jasperbloom", "Herbalism", "Alliance", "Dustwallow Marsh", "Theramore Isle", 64, 47.5, "Artisan", nil, nil),
    E("Nancy Songflower", "Herbalism", "Alliance", "Elwynn Forest", "Northshire", 52.4, 43.8, "Apprentice", nil, "Only teaches Apprentice, in the starting area."),
    E("Emrys Flintbeard", "Herbalism", "Alliance", "Dun Morogh", "Coldridge Valley", 28.8, 66.6, "Apprentice", nil, "Only teaches Apprentice, in the starting area."),
    E("Eleyna Duskbreeze", "Herbalism", "Alliance", "Teldrassil", "Shadowglen", 59.8, 41.4, "Apprentice", nil, "Only teaches Apprentice, in the starting area."),
    -- Herbalism, Horde
    E("Jandi", "Herbalism", "Horde", "Orgrimmar", "The Drag", 55.6, 39.5, "Artisan", nil, nil),
    E("Martha Alliestar", "Herbalism", "Horde", "Undercity", "The Apothecarium", 54.8, 50, "Artisan", nil, nil),
    E("Komin Winterhoof", "Herbalism", "Horde", "Thunder Bluff", "Middle Rise", 49.8, 39.8, "Artisan", nil, nil),
    E("Mishiki", "Herbalism", "Horde", "Durotar", "Sen'jin Village", 55.4, 75.1, "Artisan", nil, nil),
    E("Faruza", "Herbalism", "Horde", "Tirisfal Glades", "Brill", 59.8, 52.1, "Artisan", nil, nil),
    E("Aranae Venomblood", "Herbalism", "Horde", "Hillsbrad Foothills", "Tarren Mill", 61.7, 19.6, "Artisan", nil, nil),
    E("Angrun", "Herbalism", "Horde", "Stranglethorn Vale", "Grom'gol Base Camp", 32.2, 27.4, "Artisan", nil, nil),
    E("Ruw", "Herbalism", "Horde", "Feralas", "Camp Mojache", 76, 43.4, "Artisan", nil, nil),
    E("Zor'la", "Herbalism", "Horde", "Durotar", "Valley of Trials", 42.6, 67.4, "Apprentice", nil, "Only teaches Apprentice, in the starting area."),
    E("Garan Sunstrider", "Herbalism", "Horde", "Mulgore", "Red Cloud Mesa", 44.2, 77.8, "Apprentice", nil, "Only teaches Apprentice, in the starting area."),
    E("Florence Nightshade", "Herbalism", "Horde", "Tirisfal Glades", "Deathknell", 32.4, 65.2, "Apprentice", nil, "Only teaches Apprentice, in the starting area."),
    -- Herbalism, Neutral
    E("Flora Silverwind", "Herbalism", "Neutral", "Stranglethorn Vale", "Booty Bay", 27.7, 77.9, "Artisan", nil, nil),
    E("Malvor", "Herbalism", "Neutral", "Moonglade", "Nighthaven", 45.5, 46.8, "Artisan", nil, nil),
    E("Halassa Fernbreeze", "Herbalism", "Neutral", "Zephras Isle", "Shen'dar Village", 43.1, 43.5, "Artisan", nil, nil),
    E("Syriel Nightrain", "Herbalism", "Neutral", "Zephras Isle", "Valanaar", 57.9, 75.5, "Artisan", nil, nil),
    E("Edward Egan", "Herbalism", "Neutral", "Alterac Mountains", "Dalaran", 18.4, 63.2, "Artisan", nil, nil),
    -- Mining, Alliance
    E("Gelman Stonehand", "Mining", "Alliance", "Stormwind City", "Dwarven District", 59.1, 37.7, "Artisan", nil, nil),
    E("Geofram Bouldertoe", "Mining", "Alliance", "Ironforge", "The Great Forge", 50, 26.3, "Artisan", nil, nil),
    E("Yarr Hammerstone", "Mining", "Alliance", "Dun Morogh", "Steelgrill's Depot", 50, 50.3, "Artisan", nil, nil),
    E("Dank Drizzlecut", "Mining", "Alliance", "Dun Morogh", "Gol'Bolar Quarry", 69.3, 55.5, "Artisan", nil, nil),
    E("Brock Stoneseeker", "Mining", "Alliance", "Loch Modan", "Thelsamar", 37.2, 46.9, "Artisan", nil, nil),
    E("Matt Johnson", "Mining", "Alliance", "Duskwood", "Darkshire", 74, 49.6, "Artisan", nil, nil),
    E("Kurdram Stonehammer", "Mining", "Alliance", "Darkshore", "Auberdine", 38.2, 41, "Artisan", nil, nil),
    E("Kelsey Fargo", "Mining", "Alliance", "Elwynn Forest", "Northshire", 47.2, 32.6, "Apprentice", nil, "Only teaches Apprentice, in the starting area."),
    E("Sally Swiftwrench", "Mining", "Alliance", "Dun Morogh", "Coldridge Valley", 28.8, 67.8, "Apprentice", nil, "Only teaches Apprentice, in the starting area."),
    E("Fanorran Stilloak", "Mining", "Alliance", "Teldrassil", "Shadowglen", 58.2, 41.4, "Apprentice", nil, "Only teaches Apprentice, in the starting area."),
    -- Mining, Horde
    E("Makaru", "Mining", "Horde", "Orgrimmar", "Valley of Honor", 73.0, 27.0, "Artisan", nil, nil),
    E("Brom Killian", "Mining", "Horde", "Undercity", "The War Quarter", 55.9, 36.0, "Artisan", nil, nil),
    E("Brek Stonehoof", "Mining", "Horde", "Thunder Bluff", "Lower Rise", 34.4, 57.6, "Artisan", nil, nil),
    E("Krunn", "Mining", "Horde", "Durotar", "Razor Hill", 51.8, 40.9, "Artisan", nil, nil),
    E("Johan Focht", "Mining", "Horde", "Silverpine Forest", "The Sepulcher", 43.4, 40.5, "Artisan", nil, nil),
    E("Norzsh", "Mining", "Horde", "Durotar", "Valley of Trials", 40.6, 68, "Apprentice", nil, "Only teaches Apprentice, in the starting area."),
    E("Vartha Rockmane", "Mining", "Horde", "Mulgore", "Red Cloud Mesa", 44.2, 78.2, "Apprentice", nil, "Only teaches Apprentice, in the starting area."),
    E("Walter Mason", "Mining", "Horde", "Tirisfal Glades", "Deathknell", 32.2, 65.8, "Apprentice", nil, "Only teaches Apprentice, in the starting area."),
    -- Mining, Neutral
    E("Pikkle", "Mining", "Neutral", "Tanaris", "Gadgetzan", 51, 28, "Artisan", nil, nil),
    E("Messana Crestwind", "Mining", "Neutral", "Zephras Isle", "Shen'dar Village", 44.7, 44.5, "Artisan", nil, nil),
    E("Halavuul Cragwind", "Mining", "Neutral", "Zephras Isle", "Valanaar", 65.4, 80.4, "Artisan", nil, nil),
    E("Grungle", "Mining", "Neutral", "Riverglades", "Powderfuse Port", 77.7, 51.9, "Artisan", nil, nil),
    -- Skinning, Alliance
    E("Maris Granger", "Skinning", "Alliance", "Stormwind City", "Old Town", 72.3, 62.3, "Artisan", nil, nil),
    E("Balthus Stoneflayer", "Skinning", "Alliance", "Ironforge", "The Great Forge", 39.8, 32.6, "Artisan", nil, nil),
    E("Eladriel", "Skinning", "Alliance", "Darnassus", "Craftsmen's Terrace", 64.4, 21.6, "Artisan", nil, nil),
    E("Helene Peltskinner", "Skinning", "Alliance", "Elwynn Forest", "Goldshire", 46.3, 62.2, "Artisan", nil, nil),
    E("Radnaal Maneweaver", "Skinning", "Alliance", "Teldrassil", "Road east of Darnassus", 42.1, 50, "Artisan", nil, nil),
    E("Jayla", "Skinning", "Alliance", "Ashenvale", "Silverwind Refuge", 50, 67.2, "Artisan", nil, nil),
    E("Wilma Ranthal", "Skinning", "Alliance", "Redridge Mountains", "Shalewind Canyon", 83.6, 71.1, "Artisan", nil, nil),
    E("Riley Peltskinner", "Skinning", "Alliance", "Elwynn Forest", "Northshire", 47, 39.8, "Apprentice", nil, "Only teaches Apprentice, in the starting area."),
    E("Brighid Stormflayer", "Skinning", "Alliance", "Dun Morogh", "Coldridge Valley", 29.2, 67.7, "Apprentice", nil, "Only teaches Apprentice, in the starting area."),
    E("Terunne Bearshaper", "Skinning", "Alliance", "Teldrassil", "Shadowglen", 59.4, 38.7, "Apprentice", nil, "Only teaches Apprentice, in the starting area."),
    -- Skinning, Horde
    E("Thuwd", "Skinning", "Horde", "Orgrimmar", "The Drag", 63.3, 45.3, "Artisan", nil, nil),
    E("Killian Hagey", "Skinning", "Horde", "Undercity", "Rogues' Quarter", 70.8, 59.5, "Artisan", nil, nil),
    E("Mooranta", "Skinning", "Horde", "Thunder Bluff", "Middle Rise", 44.6, 43.2, "Artisan", nil, nil),
    E("Yonn Deepcut", "Skinning", "Horde", "Mulgore", "Bloodhoof Village", 45.0, 61.4, "Artisan", nil, nil),
    E("Rand Rhobart", "Skinning", "Horde", "Tirisfal Glades", "Southeast of Brill", 65.6, 60, "Artisan", nil, nil),
    E("Dranh", "Skinning", "Horde", "The Barrens", "Camp Taurajo", 45.1, 59.1, "Artisan", nil, nil),
    E("Kulleg Stonehorn", "Skinning", "Horde", "Feralas", "Camp Mojache", 74.5, 43, "Artisan", nil, nil),
    E("Malux", "Skinning", "Horde", "Desolace", "Shadowprey Village", 23.2, 69.8, "Artisan", nil, nil),
    E("Kagil", "Skinning", "Horde", "Durotar", "Valley of Trials", 40.8, 68, "Apprentice", nil, "Only teaches Apprentice, in the starting area."),
    E("Nawka Wildsong", "Skinning", "Horde", "Mulgore", "Red Cloud Mesa", 44.8, 76.8, "Apprentice", nil, "Only teaches Apprentice, in the starting area."),
    E("Margaret Weaver", "Skinning", "Horde", "Tirisfal Glades", "Deathknell", 32.6, 65.7, "Apprentice", nil, "Only teaches Apprentice, in the starting area."),
    -- Skinning, Neutral
    E("Ishlee Breezewhisper", "Skinning", "Neutral", "Zephras Isle", "Valanaar", 59.6, 75.9, "Artisan", nil, nil),
    E("Mendalass Tattermend", "Skinning", "Neutral", "Zephras Isle", "Shen'dar Village", 43.2, 43.4, "Artisan", nil, nil),
    -- Fishing, Alliance
    E("Arnold Leland", "Fishing", "Alliance", "Stormwind City", "The Canals, west of the Trade District", 55.1, 69.6, "Journeyman", nil, nil),
    E("Grimnur Stonebrand", "Fishing", "Alliance", "Ironforge", "The Forlorn Cavern", 48.5, 6.4, "Journeyman", nil, nil),
    E("Astaia", "Fishing", "Alliance", "Darnassus", "Temple Gardens", 47.6, 56.8, "Journeyman", nil, nil),
    E("Lee Brown", "Fishing", "Alliance", "Elwynn Forest", "Crystal Lake", 47.6, 62.3, "Journeyman", nil, nil),
    E("Paxton Ganter", "Fishing", "Alliance", "Dun Morogh", "Iceflow Lake", 35.6, 40.4, "Journeyman", nil, nil),
    E("Androl Oakhand", "Fishing", "Alliance", "Teldrassil", "Rut'theran Village", 55.8, 93.5, "Journeyman", nil, nil),
    E("Warg Deepwater", "Fishing", "Alliance", "Loch Modan", "The Loch", 40.4, 39.6, "Journeyman", nil, nil),
    E("Matthew Hooper", "Fishing", "Alliance", "Redridge Mountains", "Lakeshire docks", 21.5, 51.0, "Journeyman", nil, nil),
    E("Harold Riggs", "Fishing", "Alliance", "Wetlands", "Menethil Harbor", 8.2, 58.6, "Journeyman", nil, nil),
    E("Donald Rabonne", "Fishing", "Alliance", "Hillsbrad Foothills", "Southshore", 50.8, 61, "Journeyman", nil, nil),
    E("Brannock", "Fishing", "Alliance", "Feralas", "Feathermoon Stronghold", 32.2, 41.6, "Journeyman", nil, nil),
    E("Hunter Moore", "Fishing", "Alliance", "Hillsbrad Foothills", "Island off the coast", 54, 80.6, "Journeyman", nil, nil),
    -- Fishing, Horde
    E("Lumak", "Fishing", "Horde", "Orgrimmar", "Valley of Honor", 69.6, 29.6, "Journeyman", nil, nil),
    E("Kah Mistrunner", "Fishing", "Horde", "Thunder Bluff", "High Rise", 56, 46.8, "Journeyman", nil, nil),
    E("Armand Cromwell", "Fishing", "Horde", "Undercity", "Magic Quarter", 81, 30.8, "Journeyman", nil, nil),
    E("Lau'Tiki", "Fishing", "Horde", "Durotar", "Darkspear Strand", 53.2, 81.6, "Journeyman", nil, nil),
    E("Clyde Kellen", "Fishing", "Horde", "Tirisfal Glades", "Brightwater Lake", 67.2, 51, "Journeyman", nil, nil),
    E("Uthan Stillwater", "Fishing", "Horde", "Mulgore", "Stonebull Lake", 44.2, 63.9, "Journeyman", nil, nil),
    E("Kil'Hiwana", "Fishing", "Horde", "Ashenvale", "Zoram'gar Outpost", 10.8, 33.6, "Journeyman", nil, nil),
    E("Lui'Mala", "Fishing", "Horde", "Desolace", "Shadowprey Village", 22.6, 72.6, "Journeyman", nil, nil),
    E("Katoom the Angler", "Fishing", "Horde", "The Hinterlands", "Revantusk Village", 80.6, 81.6, "Journeyman", nil, nil),
    -- Fishing, Neutral
    E("Myizz Luckycatch", "Fishing", "Neutral", "Stranglethorn Vale", "Booty Bay", 27.6, 77, "Journeyman", nil, nil),
    E("Old Man Heming", "Fishing", "Neutral", "Stranglethorn Vale", "Booty Bay, The Happy Bobber", 27.4, 77, "Expert", "vendor", "Sells Expert Fishing — The Bass and You."),
    E("Nat Pagle", "Fishing", "Neutral", "Dustwallow Marsh", "Island west of Theramore", 58.6, 60, "Artisan", "quest", "Artisan Fishing quest: Nat Pagle, Angler Extreme."),
    E("Baelann Swiftcurrent", "Fishing", "Neutral", "Zephras Isle", "Valanaar", 63.2, 75.7, "Journeyman", nil, nil),
    E("Fenn Fairweather", "Fishing", "Neutral", "Zephras Isle", "Shen'dar Village", 45, 48.4, "Journeyman", nil, nil),
    E("Krix", "Fishing", "Neutral", "Riverglades", "Powderfuse Port", 79.3, 54.7, "Journeyman", nil, nil),
    -- Fishing, Alliance
    E("Catherine Leland", "Fishing", "Alliance", "Stormwind City", "The Canals, beside Arnold Leland", 55.1, 69.5, nil, "vendor", "Fishing supplies."),
    E("Tansy Puddlefizz", "Fishing", "Alliance", "Ironforge", "The Forlorn Cavern", 48.2, 6.6, nil, "vendor", "Fishing supplies."),
    E("Voloren", "Fishing", "Alliance", "Darnassus", "Temple Gardens", 47.3, 56.6, nil, "vendor", "Fishing supplies."),
    E("Nessa Shadowsong", "Fishing", "Alliance", "Teldrassil", "Rut'theran Village", 56.3, 92.4, nil, "vendor", "Fishing supplies."),
    -- Fishing, Horde
    E("Shankys", "Fishing", "Horde", "Orgrimmar", "Valley of Honor", 69.8, 29.8, nil, "vendor", "Fishing supplies."),
    E("Sewa Mistrunner", "Fishing", "Horde", "Thunder Bluff", "High Rise", 55.8, 47, nil, "vendor", "Fishing supplies."),
    E("Lizbeth Cromwell", "Fishing", "Horde", "Undercity", "Magic Quarter", 81, 31, nil, "vendor", "Fishing supplies."),
}

local RANK_ORDER = { Artisan = 1, Expert = 2, Journeyman = 3, Apprentice = 4 }

function Trainers:All() return self.List end

function Trainers:Find(name)
    for _, e in ipairs(self.List) do
        if e.name == name then return e end
    end
end

function Trainers:PlayerFaction()
    local f = UnitFactionGroup and UnitFactionGroup("player")
    if f == "Alliance" or f == "Horde" then return f end
    return "Alliance"
end

-- opts.prof: profession or "All".
-- opts.faction: "Alliance" or "Horde" (defaults to the player's faction).
-- Only that faction is listed, plus Neutral (Booty Bay, Gadgetzan, Nat Pagle
-- and so on), which appears in both views. Notable hunting targets sit at
-- the top of their profession.
function Trainers:Filtered(opts)
    opts = opts or {}
    local prof = opts.prof
    local me = opts.faction or self:PlayerFaction()
    if me ~= "Alliance" and me ~= "Horde" then me = self:PlayerFaction() end
    local out = {}
    for _, e in ipairs(self.List) do
        if (not prof or prof == "All" or e.prof == prof) then
            if e.faction == me or e.faction == "Neutral" then out[#out + 1] = e end
        end
    end
    table.sort(out, function(a, b)
        if a.prof ~= b.prof then
            local order = { Herbalism = 1, Mining = 2, Fishing = 3, Skinning = 4 }
            return (order[a.prof] or 9) < (order[b.prof] or 9)
        end
        local function weight(e)
            local notable = (e.kind == "quest" or (e.kind == "vendor" and e.rank == "Expert")) and 0 or 1
            local fac = e.faction == me and 0 or (e.faction == "Neutral" and 1 or 2)
            local rank = RANK_ORDER[e.rank] or (e.kind == "vendor" and 5 or 3)
            return notable, fac, rank
        end
        local an, af, ar = weight(a)
        local bn, bf, br = weight(b)
        if an ~= bn then return an < bn end
        if af ~= bf then return af < bf end
        if ar ~= br then return ar < br end
        if a.zone ~= b.zone then return a.zone < b.zone end
        return a.name < b.name
    end)
    return out
end

function Trainers:Counts()
    local c = {}
    for _, e in ipairs(self.List) do
        c[e.prof] = c[e.prof] or { Alliance = 0, Horde = 0, Neutral = 0, total = 0 }
        c[e.prof][e.faction] = (c[e.prof][e.faction] or 0) + 1
        c[e.prof].total = c[e.prof].total + 1
    end
    return c
end

function Trainers:WhereText(e)
    if e.subzone and e.subzone ~= "" then return e.zone .. ", " .. e.subzone end
    return e.zone
end

function Trainers:CoordsText(e)
    if not e.x or not e.y then return nil end
    return ("%.1f, %.1f"):format(e.x, e.y)
end

function Trainers:Label(e)
    return e.name
end

-- Feature-detected player map position. x,y are 0-1. Returns nil when the
-- client cannot place the player (instances, loading, no map API).
local function MapXY(mapID)
    if C_Map and C_Map.GetPlayerMapPosition and mapID then
        local pos = C_Map.GetPlayerMapPosition(mapID, "player")
        if pos then
            if pos.GetXY then
                local ok, x, y = pcall(pos.GetXY, pos)
                if ok and x and y then return x, y end
            end
            if pos.x and pos.y then return pos.x, pos.y end
        end
    end
    if GetPlayerMapPosition then
        local x, y = GetPlayerMapPosition("player")
        if type(x) == "number" and type(y) == "number" then return x, y end
    end
end

local function WorldXY(mapID, x, y)
    if not (C_Map and C_Map.GetWorldPosFromMapPos and mapID and x and y) then return end
    local vec
    if CreateVector2D then
        vec = CreateVector2D(x, y)
    else
        vec = { x = x, y = y }
    end
    local ok, continent, world = pcall(C_Map.GetWorldPosFromMapPos, mapID, vec)
    if not ok or not world then return end
    local wx, wy
    if world.GetXY then
        local wok, a, b = pcall(world.GetXY, world)
        if wok then wx, wy = a, b end
    end
    if not wx and world.x then wx, wy = world.x, world.y end
    if wx and wy then return continent, wx, wy end
end

function Trainers:PlayerPosition()
    local zone, mapID
    if ns.GetCurrentZone then
        zone, mapID = ns.GetCurrentZone()
    end
    if (not zone or zone == "" or zone == UNKNOWN) and GetRealZoneText then
        zone = GetRealZoneText()
    end
    local x, y = MapXY(mapID)
    if not x or not y then
        x, y = MapXY(nil)
    end
    -- 0,0 is what the client returns when it has no fix (inside an instance).
    if not x or not y or (x == 0 and y == 0) then return nil end
    if not zone or zone == "" or zone == UNKNOWN then return nil end
    return { zone = zone, mapID = mapID, x = x, y = y }
end

local function SameZone(pos, e)
    if not pos or not e then return false end
    if e.zone and pos.zone and e.zone == pos.zone then return true end
    local mid = e.zone and ns.Zones and ns.Zones:MapID(e.zone)
    return mid and pos.mapID and mid == pos.mapID
end

-- Approximate yards, plus whether the two points share a continent.
-- Same-zone and same-continent distances use GetWorldPosFromMapPos when
-- it exists; otherwise yards is nil.
function Trainers:Distance(pos, e)
    if not pos or not e then return nil, false, false end
    local sameZone = SameZone(pos, e)
    local tMap = e.zone and ns.Zones and ns.Zones:MapID(e.zone)
    local tx, ty
    if e.x and e.y then tx, ty = e.x / 100, e.y / 100 end
    local c1, wx1, wy1 = WorldXY(pos.mapID, pos.x, pos.y)
    local c2, wx2, wy2 = WorldXY(tMap, tx, ty)
    local sameCont = (c1 ~= nil and c2 ~= nil and c1 == c2)
    local yards
    if sameCont and wx1 and wx2 then
        local dx, dy = wx1 - wx2, wy1 - wy2
        yards = math.sqrt(dx * dx + dy * dy)
    end
    return yards, sameZone, sameCont or sameZone
end

local function RoundYards(n)
    if not n then return nil end
    n = math.floor(n + 0.5)
    if n < 15 then return n < 1 and 1 or n end
    if n >= 1000 then
        return math.floor(n / 100 + 0.5) * 100
    end
    if n >= 100 then
        return math.floor(n / 10 + 0.5) * 10
    end
    return math.floor(n / 5 + 0.5) * 5
end

function Trainers:NearestLabel(result)
    if not result or not result.yards then return "Nearest" end
    return "Nearest  ·  about " .. RoundYards(result.yards) .. " yd"
end

function Trainers:ClosestText(result)
    if not result then return "" end
    if result.error then return result.error end
    local e = result.entry
    if not e then return "" end
    local yards = result.yards and (" (about " .. RoundYards(result.yards) .. " yd)") or ""
    if result.sameZone then
        return ("Closest: %s, %s%s"):format(e.name, e.zone, yards)
    end
    return ("Closest: %s, in %s%s"):format(e.name, e.zone, yards)
end

-- opts.prof: a profession or "All".
-- opts.faction: Alliance/Horde; defaults to UnitFactionGroup.
-- opts.learned: when prof is All, only these professions are searched;
--   if empty or nil, every gathering profession is used.
-- Returns a result table, or nil plus "no_position" / "none".
function Trainers:Closest(opts)
    opts = opts or {}
    local pos = self:PlayerPosition()
    if not pos then return nil, "no_position" end
    local prof = opts.prof
    local learned = opts.learned
    local want = nil
    if prof and prof ~= "All" then
        want = { [prof] = true }
    elseif learned and #learned > 0 then
        want = {}
        for _, p in ipairs(learned) do want[p] = true end
    end
    local filterOpts = { faction = opts.faction or self:PlayerFaction(), prof = "All" }
    if prof and prof ~= "All" then filterOpts.prof = prof end
    local list = self:Filtered(filterOpts)
    local best, bestTier, bestYards
    for _, e in ipairs(list) do
        if not want or want[e.prof] then
            local yards, sameZone, sameCont = self:Distance(pos, e)
            local tier
            if sameZone then
                tier = 0
            elseif sameCont then
                tier = 1
            else
                tier = 2
            end
            local key = yards or math.huge
            if not best or tier < bestTier or (tier == bestTier and key < bestYards) then
                best, bestTier, bestYards = e, tier, key
            end
        end
    end
    if not best then return nil, "none" end
    local yards, sameZone, sameCont = self:Distance(pos, best)
    local result = {
        entry = best, yards = yards, sameZone = sameZone, sameContinent = sameCont, pos = pos,
    }
    result.text = self:ClosestText(result)
    return result
end

