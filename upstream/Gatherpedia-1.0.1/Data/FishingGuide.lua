-- Gatherpedia: Data/FishingGuide.lua
-- The 1-300 Fishing guide. Spots list only waters; trainers, the
-- Expert book and the Artisan quest are drawn under Next rank.

local _, ns = ...

ns.FishingGuide = {
    intro = "Fishing needs only a pole and lures. Skill comes from every catch; a fish that gets away gives nothing, so add a lure when that starts to happen.",
    brackets = {
        {
            key = "1-75", min = 1, max = 75,
            title = "Any starting zone",
            short = "Fish any starting-zone water to 75. Journeyman at 50.",
            train = "Learn Apprentice Fishing from any fishing trainer. Forever has no level requirement for it.",
            gear = "Buy a Fishing Pole and Shiny Baubles (+25) from the fishing supplier beside your trainer.",
            catches = "Any lake, river or coast in the seven starting zones. Capital cities are not starting zones for this range.",
            tips = "Fish the water nearest your trainer. Move up a range once fish start getting away.",
            spots = {
                { faction = "Alliance", zone = "Dun Morogh", mapID = 1426, label = "Dun Morogh waters" },
                { faction = "Horde", zone = "Durotar", mapID = 1411, label = "Durotar coast" },
                { faction = "Alliance", zone = "Elwynn Forest", mapID = 1429, label = "Elwynn lakes and rivers" },
                { faction = "Horde", zone = "Mulgore", mapID = 1412, label = "Mulgore waters" },
                { faction = "Alliance", zone = "Teldrassil", mapID = 1438, label = "Teldrassil waters" },
                { faction = "Horde", zone = "Tirisfal Glades", mapID = 1420, label = "Tirisfal waters" },
                { faction = "Both", zone = "Zephras Isle", mapID = 2521, label = "Skyborne starting isle" },
            },
        },
        {
            key = "75-150", min = 75, max = 150,
            title = "Capitals and second zones",
            short = "A capital city, or the Barrens, Darkshore, Loch Modan, Silverpine or Westfall. Expert at 125.",
            train = "The Expert book is also sold on the Auction House. Buy Bright Baubles from Old Man Heming while you are in Booty Bay.",
            gear = "Nightcrawlers (+50, need skill 50) from a fishing supplier when fish start getting away.",
            catches = "Capital city water, or the open water of the second-tier zones listed.",
            tips = "Fish wherever you already are. A capital is as good as the open zones and keeps the trainer and vendors close.",
            spots = {
                { faction = "Alliance", zone = "Darnassus", mapID = 1457, label = "Darnassus" },
                { faction = "Alliance", zone = "Stormwind City", mapID = 1453, label = "Stormwind City" },
                { faction = "Horde", zone = "Orgrimmar", mapID = 1454, label = "Orgrimmar" },
                { faction = "Horde", zone = "Undercity", mapID = 1458, label = "Undercity" },
                { faction = "Horde", zone = "Thunder Bluff", mapID = 1456, label = "Thunder Bluff" },
                { faction = "Alliance", zone = "Ironforge", mapID = 1455, label = "Ironforge" },
                { faction = "Horde", zone = "The Barrens", mapID = 1413, x = 56, y = 41, label = "Lushwater Oasis" },
                { faction = "Horde", zone = "The Barrens", mapID = 1413, x = 63, y = 38, label = "Ratchet coast" },
                { faction = "Alliance", zone = "Darkshore", mapID = 1439, label = "Darkshore coast" },
                { faction = "Alliance", zone = "Loch Modan", mapID = 1432, label = "Loch Modan" },
                { faction = "Horde", zone = "Silverpine Forest", mapID = 1421, label = "Silverpine shores" },
                { faction = "Alliance", zone = "Westfall", mapID = 1436, label = "Westfall coast" },
            },
        },
        {
            key = "150-225", min = 150, max = 225,
            title = "Dustwallow Marsh",
            short = "Dustwallow Marsh with Bright Baubles. Six other zones work as backups.",
            train = "Stay Expert through this range. Artisan opens at 225 as a quest from Nat Pagle; it is on the 225-300 page.",
            gear = "Keep Bright Baubles (+75) on the pole.",
            catches = "Dustwallow Marsh is the best water. Alterac Mountains, Arathi Highlands, Desolace, Stranglethorn Vale, Swamp of Sorrows and Thousand Needles also level you.",
            tips = "Fish in Dustwallow near Nat Pagle so you can take his quest the moment you reach 225.",
            spots = {
                { faction = "Both", zone = "Dustwallow Marsh", mapID = 1445, x = 58.6, y = 60, label = "Nat Pagle's island" },
                { faction = "Both", zone = "Dustwallow Marsh", mapID = 1445, x = 66, y = 50, label = "Theramore coast" },
                { faction = "Both", zone = "Alterac Mountains", mapID = 1416, label = "Alterac Mountains" },
                { faction = "Both", zone = "Arathi Highlands", mapID = 1417, label = "Arathi Highlands" },
                { faction = "Both", zone = "Desolace", mapID = 1443, x = 25, y = 77, label = "Sar'theris Strand (Striker)" },
                { faction = "Both", zone = "Stranglethorn Vale", mapID = 1434, x = 33, y = 32, label = "Savage Coast (Blue Sailfin)" },
                { faction = "Both", zone = "Swamp of Sorrows", mapID = 1435, x = 93, y = 40, label = "Misty Reed Strand" },
                { faction = "Both", zone = "Thousand Needles", mapID = 1441, label = "Thousand Needles" },
            },
        },
        {
            key = "225-300", min = 225, max = 300,
            title = "Late zones to 300",
            short = "Felwood, Feralas, the Hinterlands, Tanaris, Un'Goro or Western Plaguelands. Artisan quest first.",
            train = "Fishing stops at 225 until you finish the quest. There is no rank above Artisan.",
            gear = "Bright Baubles (+75) in every zone here, or fish will get away.",
            catches = "Any of the six late zones. Pick the one closest to where you play.",
            tips = "Take the quest before you travel; the quest fish only bite while you have it. Use Bright Baubles for the Feralas Ahi.",
            spots = {
                { faction = "Both", zone = "Felwood", mapID = 1448, label = "Felwood waters" },
                { faction = "Both", zone = "Feralas", mapID = 1444, x = 62, y = 52, label = "Verdantis River (Feralas Ahi)" },
                { faction = "Both", zone = "The Hinterlands", mapID = 1425, label = "Hinterlands waters" },
                { faction = "Both", zone = "Tanaris", mapID = 1446, label = "Tanaris coast" },
                { faction = "Both", zone = "Un'Goro Crater", mapID = 1449, x = 51, y = 50, label = "Un'Goro lake" },
                { faction = "Both", zone = "Western Plaguelands", mapID = 1422, label = "Western Plaguelands" },
            },
        },
    },
}
