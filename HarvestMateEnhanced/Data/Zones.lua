-- HarvestMate Enhanced: Data/Zones.lua
-- What HME needs to know about each zone to plan around it. Every number here
-- is a fallback: in game, sizes come from C_Map (exact), and level ranges are
-- also worked out from the beasts in Data/Gatherpedia/SkinningMobs.lua.
--
--   size     yards across and down (classic 1.12 maps; approximate)
--   levels   typical creature levels (classic zone ranges; approximate)
--   cont     "K" Kalimdor, "E" Eastern Kingdoms, "F" a Forever island/zone
--   near     zones you can walk or ride straight into
--   towns    guarded settlements: { faction, x, y, radius yards, name }. Their
--            guards attack the other faction. Positions are approximate,
--            from public classic maps, and only used to mark risk.
--
-- Forever's own zones (Zephras Isle, Riverglades, Mount Hyjal, Shen'dralas)
-- have no bundled size or neighbours: HME asks the client and, failing that,
-- marks distances there as unknown rather than guessing.
--
-- Copyright (C) 2026 HarvestMate Enhanced contributors. GPL-3.0-or-later.

local _, ns = ...
local HME = ns.HME

local Z = {}
HME.ZoneData = Z

Z.CONTINENT_MAP = { K = 1414, E = 1415 }

Z.ZONES = {
    -- Eastern Kingdoms
    [1429] = { name = "Elwynn Forest", cont = "E", size = { 3470, 2315 }, levels = { 1, 10 }, near = { 1436, 1431, 1433, 1453 } },
    [1436] = { name = "Westfall", cont = "E", size = { 3500, 2333 }, levels = { 10, 20 }, near = { 1429, 1431 },
        towns = { { "Alliance", 56.3, 47.5, 140, "Sentinel Hill" } } },
    [1431] = { name = "Duskwood", cont = "E", size = { 2700, 1800 }, levels = { 18, 30 }, near = { 1429, 1436, 1433, 1434, 1430 },
        towns = { { "Alliance", 75.0, 46.0, 160, "Darkshire" } } },
    [1433] = { name = "Redridge Mountains", cont = "E", size = { 2171, 1448 }, levels = { 15, 25 }, near = { 1429, 1431, 1428 },
        towns = { { "Alliance", 29.0, 47.0, 160, "Lakeshire" } } },
    [1434] = { name = "Stranglethorn Vale", cont = "E", size = { 6381, 4254 }, levels = { 30, 45 }, near = { 1431 },
        towns = { { "Horde", 32.5, 28.5, 180, "Grom'gol Base Camp" }, { "Alliance", 38.0, 4.0, 140, "Rebel Camp" } } },
    [1430] = { name = "Deadwind Pass", cont = "E", size = { 2500, 1667 }, levels = { 55, 60 }, near = { 1431, 1435 } },
    [1435] = { name = "Swamp of Sorrows", cont = "E", size = { 2294, 1529 }, levels = { 35, 45 }, near = { 1430, 1419 },
        towns = { { "Horde", 46.0, 54.5, 180, "Stonard" } } },
    [1419] = { name = "Blasted Lands", cont = "E", size = { 3350, 2233 }, levels = { 45, 55 }, near = { 1435 },
        towns = { { "Alliance", 66.0, 19.0, 180, "Nethergarde Keep" } } },
    [1428] = { name = "Burning Steppes", cont = "E", size = { 2929, 1952 }, levels = { 50, 58 }, near = { 1433, 1427 },
        towns = { { "Alliance", 84.5, 68.5, 140, "Morgan's Vigil" }, { "Horde", 65.5, 24.0, 140, "Flame Crest" } } },
    [1427] = { name = "Searing Gorge", cont = "E", size = { 2231, 1488 }, levels = { 43, 50 }, near = { 1428 } },
    [1418] = { name = "Badlands", cont = "E", size = { 2488, 1658 }, levels = { 35, 45 }, near = { 1432 },
        towns = { { "Horde", 3.5, 47.5, 160, "Kargath" } } },
    [1432] = { name = "Loch Modan", cont = "E", size = { 2758, 1840 }, levels = { 10, 20 }, near = { 1426, 1437, 1418 },
        towns = { { "Alliance", 34.5, 47.5, 160, "Thelsamar" } } },
    [1426] = { name = "Dun Morogh", cont = "E", size = { 4925, 3283 }, levels = { 1, 12 }, near = { 1432, 1455 } },
    [1437] = { name = "Wetlands", cont = "E", size = { 4135, 2756 }, levels = { 20, 30 }, near = { 1432, 1417 },
        towns = { { "Alliance", 10.0, 59.0, 200, "Menethil Harbor" } } },
    [1417] = { name = "Arathi Highlands", cont = "E", size = { 3600, 2400 }, levels = { 30, 40 }, near = { 1437, 1424 },
        towns = { { "Alliance", 46.0, 47.0, 160, "Refuge Pointe" }, { "Horde", 73.5, 33.5, 160, "Hammerfall" } } },
    [1424] = { name = "Hillsbrad Foothills", cont = "E", size = { 4850, 3233 }, levels = { 20, 31 }, near = { 1417, 1416, 1421, 1425 },
        towns = { { "Alliance", 50.5, 58.0, 220, "Southshore" }, { "Horde", 62.0, 20.0, 200, "Tarren Mill" } } },
    [1416] = { name = "Alterac Mountains", cont = "E", size = { 2800, 1867 }, levels = { 30, 40 }, near = { 1424, 1421, 1422 } },
    [1421] = { name = "Silverpine Forest", cont = "E", size = { 4200, 2800 }, levels = { 10, 20 }, near = { 1420, 1424, 1416 },
        towns = { { "Horde", 43.0, 41.0, 160, "The Sepulcher" } } },
    [1420] = { name = "Tirisfal Glades", cont = "E", size = { 4519, 3013 }, levels = { 1, 12 }, near = { 1421, 1422, 1458 },
        towns = { { "Horde", 61.0, 52.0, 160, "Brill" } } },
    [1422] = { name = "Western Plaguelands", cont = "E", size = { 4300, 2867 }, levels = { 51, 58 }, near = { 1420, 1423, 1416 },
        towns = { { "Alliance", 43.0, 84.5, 140, "Chillwind Camp" } } },
    [1423] = { name = "Eastern Plaguelands", cont = "E", size = { 3871, 2581 }, levels = { 53, 60 }, near = { 1422 } },
    [1425] = { name = "The Hinterlands", cont = "E", size = { 3850, 2567 }, levels = { 40, 50 }, near = { 1424 },
        towns = { { "Alliance", 14.0, 45.0, 180, "Aerie Peak" }, { "Horde", 79.0, 79.0, 160, "Revantusk Village" } } },
    -- Kalimdor
    [1438] = { name = "Teldrassil", cont = "K", size = { 5092, 3394 }, levels = { 1, 11 }, near = { 1457 } },
    [1439] = { name = "Darkshore", cont = "K", size = { 6550, 4367 }, levels = { 10, 20 }, near = { 1440 },
        towns = { { "Alliance", 37.0, 44.0, 180, "Auberdine" } } },
    [1440] = { name = "Ashenvale", cont = "K", size = { 5767, 3844 }, levels = { 18, 30 }, near = { 1439, 1448, 1442, 1413, 1447 },
        towns = { { "Alliance", 36.5, 50.0, 180, "Astranaar" }, { "Horde", 73.0, 61.0, 160, "Splintertree Post" } } },
    [1448] = { name = "Felwood", cont = "K", size = { 5750, 3833 }, levels = { 48, 55 }, near = { 1440, 1452, 1450 },
        towns = { { "Alliance", 62.5, 25.0, 140, "Talonbranch Glade" }, { "Horde", 34.5, 53.0, 140, "Bloodvenom Post" } } },
    [1452] = { name = "Winterspring", cont = "K", size = { 7100, 4733 }, levels = { 55, 60 }, near = { 1448, 1450 } },
    [1450] = { name = "Moonglade", cont = "K", size = { 2308, 1540 }, levels = { 55, 60 }, near = { 1448, 1452 } },
    [1447] = { name = "Azshara", cont = "K", size = { 5071, 3381 }, levels = { 45, 55 }, near = { 1440 },
        towns = { { "Horde", 22.0, 51.5, 140, "Valormok" } } },
    [1442] = { name = "Stonetalon Mountains", cont = "K", size = { 4883, 3256 }, levels = { 15, 27 }, near = { 1440, 1413, 1443 },
        towns = { { "Horde", 47.0, 61.5, 160, "Sun Rock Retreat" }, { "Alliance", 36.0, 7.5, 140, "Stonetalon Peak" } } },
    [1443] = { name = "Desolace", cont = "K", size = { 4496, 2998 }, levels = { 30, 40 }, near = { 1442, 1444 },
        towns = { { "Alliance", 66.0, 9.0, 160, "Nijel's Point" }, { "Horde", 24.5, 70.5, 160, "Shadowprey Village" } } },
    [1444] = { name = "Feralas", cont = "K", size = { 6950, 4633 }, levels = { 40, 50 }, near = { 1443, 1441 },
        towns = { { "Horde", 75.0, 44.0, 180, "Camp Mojache" }, { "Alliance", 31.0, 44.0, 180, "Feathermoon Stronghold" } } },
    [1413] = { name = "The Barrens", cont = "K", size = { 10133, 6756 }, levels = { 10, 25 }, near = { 1411, 1440, 1442, 1412, 1445, 1441 },
        towns = { { "Horde", 52.0, 30.0, 220, "The Crossroads" }, { "Horde", 45.0, 59.0, 200, "Camp Taurajo" } } },
    [1411] = { name = "Durotar", cont = "K", size = { 5288, 3525 }, levels = { 1, 10 }, near = { 1413, 1454 } },
    [1412] = { name = "Mulgore", cont = "K", size = { 5138, 3425 }, levels = { 1, 10 }, near = { 1413, 1456 } },
    [1445] = { name = "Dustwallow Marsh", cont = "K", size = { 5250, 3500 }, levels = { 35, 45 }, near = { 1413 },
        towns = { { "Alliance", 66.5, 49.0, 260, "Theramore Isle" }, { "Horde", 36.0, 31.0, 160, "Brackenwall Village" } } },
    [1441] = { name = "Thousand Needles", cont = "K", size = { 4400, 2933 }, levels = { 25, 35 }, near = { 1413, 1444, 1446 },
        towns = { { "Horde", 46.0, 50.5, 160, "Freewind Post" } } },
    [1446] = { name = "Tanaris", cont = "K", size = { 6900, 4600 }, levels = { 40, 50 }, near = { 1441, 1449 } },
    [1449] = { name = "Un'Goro Crater", cont = "K", size = { 3700, 2467 }, levels = { 48, 55 }, near = { 1446, 1451 } },
    [1451] = { name = "Silithus", cont = "K", size = { 3483, 2323 }, levels = { 55, 60 }, near = { 1449 } },
    -- Cities (for trainers; never recommended as farms)
    [1453] = { name = "Stormwind City", cont = "E", city = "Alliance", near = { 1429 } },
    [1455] = { name = "Ironforge", cont = "E", city = "Alliance", near = { 1426 } },
    [1457] = { name = "Darnassus", cont = "K", city = "Alliance", near = { 1438 } },
    [1454] = { name = "Orgrimmar", cont = "K", city = "Horde", near = { 1411 } },
    [1456] = { name = "Thunder Bluff", cont = "K", city = "Horde", near = { 1412 } },
    [1458] = { name = "Undercity", cont = "E", city = "Horde", near = { 1420 } },
    -- WoW Forever's own zones: sizes and links come from the client in game.
    [2521] = { name = "Zephras Isle", cont = "F", forever = true },
    [2548] = { name = "Riverglades", cont = "F", forever = true },
    [2482] = { name = "Mount Hyjal", cont = "F", forever = true, upcoming = true },
    [2652] = { name = "Shen'dralas", cont = "F", forever = true },
}

-- Boats and zeppelins between the continents: { from, to, faction, minutes
-- including a typical wait }. Forever-GPS knows the real network; these only
-- keep HME's own estimate honest when it is not installed.
Z.CROSSINGS = {
    { 1437, 1445, "Alliance", 6, "Menethil Harbor to Theramore" },
    { 1439, 1438, "Alliance", 4, "Auberdine to Rut'theran" },
    { 1420, 1411, "Horde", 6, "Tirisfal to Durotar zeppelin" },
    { 1434, 1411, "Horde", 6, "Grom'gol to Durotar zeppelin" },
    { 1434, 1413, "Both", 7, "Booty Bay to Ratchet" },
}

Z.byName = {}
for id, z in pairs(Z.ZONES) do
    z.mapID = id
    Z.byName[z.name] = id
end

function Z.Get(mapID) return mapID and Z.ZONES[mapID] end
function Z.MapID(name) return name and Z.byName[name] end
function Z.Name(mapID)
    local z = Z.ZONES[mapID]
    if z then return z.name end
    if C_Map and C_Map.GetMapInfo and mapID then
        local info = C_Map.GetMapInfo(mapID)
        return info and info.name or ("Map " .. tostring(mapID))
    end
    return "Map " .. tostring(mapID)
end
