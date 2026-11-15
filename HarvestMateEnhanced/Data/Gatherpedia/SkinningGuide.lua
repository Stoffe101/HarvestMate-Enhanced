-- Gatherpedia: Data/SkinningGuide.lua
-- The 1-300 Skinning guide. Farm spots list zones; "Show beasts" puts
-- the beasts on the map. Trainers are drawn under Next rank.

local _, ns = ...

ns.SkinningGuide = {
    intro = "Skinning follows beast level more than a zone list. From mob level 20 on, you need a skill of five times the mob's level or the hide will not come off.",
    brackets = {
        {
            key = "1-75", min = 1, max = 75,
            title = "Starting beasts",
            short = "Starting zones. Train Journeyman at 50.",
            train = "Learn Skinning from a trainer in a starting area or a capital. On Zephras Isle, it is granted by the Thendal Village quest reward instead. Train Journeyman at 50.",
            gear = "Carry a Skinning Knife.",
            catches = "The beasts in your starting zone are enough to open the skill.",
            tips = "Alliance can begin with the beasts around Northshire. Horde can begin in the Valley of Trials. Once mobs reach level 20, your skill must be five times their level.",
            spots = {
                { faction = "Alliance", zone = "Elwynn Forest", mapID = 1429, label = "Northshire and Elwynn" },
                { faction = "Alliance", zone = "Dun Morogh", mapID = 1426, label = "Dun Morogh" },
                { faction = "Alliance", zone = "Teldrassil", mapID = 1438, label = "Teldrassil" },
                { faction = "Horde", zone = "Durotar", mapID = 1411, label = "Valley of Trials and Durotar" },
                { faction = "Horde", zone = "Mulgore", mapID = 1412, label = "Mulgore" },
                { faction = "Horde", zone = "Tirisfal Glades", mapID = 1420, label = "Tirisfal Glades" },
                { faction = "Both", zone = "Zephras Isle", mapID = 2521, label = "Skyborne starting isle" },
            },
        },
        {
            key = "75-150", min = 75, max = 150,
            title = "The Barrens, Loch Modan and Wetlands",
            short = "Horde: the Barrens. Alliance: Loch Modan, then the Wetlands from 125. Train Expert at 125.",
            train = "Train Expert at 125 so hides in the next zones still come off.",
            gear = "Keep a Skinning Knife on you.",
            catches = "Beasts in the Barrens for Horde. Alliance can stay in Loch Modan into the mid-120s, then move to the Wetlands.",
            tips = "Watch the five-times-level rule as the mobs climb.",
            spots = {
                { faction = "Horde", zone = "The Barrens", mapID = 1413, label = "The Barrens" },
                { faction = "Alliance", zone = "Loch Modan", mapID = 1432, label = "Loch Modan, into the mid-120s" },
                { faction = "Alliance", zone = "Wetlands", mapID = 1437, label = "Wetlands, from about 125" },
            },
        },
        {
            key = "150-225", min = 150, max = 225,
            title = "Hillsbrad yetis and Duskwood",
            short = "Hillsbrad Foothills (yeti cave) and Duskwood. Train Artisan at 200.",
            train = "Train Artisan at 200 (character level 35) before this range runs out.",
            gear = "Keep a Skinning Knife on you.",
            catches = "Yetis in the Hillsbrad cave for both factions, and the beasts of Duskwood.",
            tips = "The yeti cave in Hillsbrad Foothills is a reliable loop. Duskwood is a good second stop.",
            spots = {
                { faction = "Both", zone = "Hillsbrad Foothills", mapID = 1424, label = "Hillsbrad yeti cave" },
                { faction = "Alliance", zone = "Duskwood", mapID = 1431, label = "Duskwood" },
            },
        },
        {
            key = "225-280", min = 225, max = 280,
            title = "Feralas yetis",
            short = "Feral Scar Vale in Feralas.",
            train = "You should already be Artisan. There is no higher rank in this era.",
            gear = "Keep a Skinning Knife on you.",
            catches = "Yetis in Feral Scar Vale.",
            tips = "Feral Scar Vale will carry you most of the way to the last bracket.",
            spots = {
                { faction = "Both", zone = "Feralas", mapID = 1444, label = "Feral Scar Vale yetis" },
            },
        },
        {
            key = "280-300", min = 280, max = 300,
            title = "Un'Goro Crater",
            short = "Un'Goro Crater to the cap.",
            train = "You should already be Artisan. There is no higher rank in this era.",
            gear = "Keep a Skinning Knife on you.",
            catches = "Un'Goro beasts to 300.",
            tips = "Finish the last twenty skill in Un'Goro Crater.",
            spots = {
                { faction = "Both", zone = "Un'Goro Crater", mapID = 1449, label = "Un'Goro Crater" },
            },
        },
    },
}
