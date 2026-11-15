local _, HG = ...

-- Статические данные: профессии, заклинания, ресурсы, добыча, ранги,
-- переплавка и взлом замков.

-- line   — id линии навыка (GetProfessionInfo)
-- track  — заклинание поиска на миникарте
-- gather — заклинания, которыми собирают ресурс
HG.PROF = {
	herb = { line = 182, track = 2383, gather = { 2366, 2368, 3570, 11993 }, label = "HERBALISM", find = "FIND_HERBS" },
	mine = { line = 186, track = 2580, gather = { 2575, 2576, 3564, 10248 }, label = "MINING", find = "FIND_MINERALS" },
	skin = { line = 393, gather = { 8613, 8617, 8618, 10768 }, label = "SKINNING" },
	-- Взлом замков: не профессия, навык разбойника (не выше уровень × 5).
	lock = { gather = { 1804 }, label = "LOCKPICKING" },
}

HG.TREASURE_SPELL = 2481   -- Поиск сокровищ (дворфы)
HG.CULTIVATION_SPELL = 20552 -- Культивация (таурены)

-- Предел навыка, выше которого нет следующего ранга у наставника.
HG.SKILL_CAP = 300

-- Ранги: текущий предел -> следующий ранг, нужный навык и уровень персонажа.
HG.RANKS = {
	[75] = { name = "RANK_JOURNEYMAN", skill = 50, level = 10 },
	[150] = { name = "RANK_EXPERT", skill = 125, level = 20 },
	[225] = { name = "RANK_ARTISAN", skill = 200, level = 35 },
}

HG.HEX = {
	red = "ff3030",
	orange = "ff8a3d",
	yellow = "ffe14d",
	green = "48c75a",
	grey = "9a9a9a",
}

------------------------------------------------------------------------
-- Ресурсы: { навык, имя1, имя2, ... } — английские имена объектов в мире.
------------------------------------------------------------------------

local HERBS = {
	{ 1, "Peacebloom", "Wilted Peacebloom", "Silverleaf", "Stunted Silverleaf" },
	{ 15, "Earthroot" },
	{ 50, "Mageroyal" },
	{ 70, "Briarthorn" },
	{ 85, "Stranglekelp" },
	{ 100, "Bruiseweed" },
	{ 115, "Wild Steelbloom" },
	{ 120, "Grave Moss" },
	{ 125, "Kingsblood", "Nightmare Moss" },
	{ 150, "Liferoot" },
	{ 160, "Fadeleaf" },
	{ 170, "Goldthorn" },
	{ 185, "Khadgar's Whisker" },
	{ 195, "Wintersbite" },
	{ 205, "Firebloom", "Dreamroot" },
	{ 210, "Purple Lotus" },
	{ 220, "Arthas' Tears" },
	{ 230, "Sungrass" },
	{ 235, "Blindweed" },
	{ 245, "Ghost Mushroom" },
	{ 250, "Gromsblood", "Moonroot", "Star Lotus" },
	{ 260, "Golden Sansam" },
	{ 270, "Dreamfoil" },
	{ 280, "Mountain Silversage" },
	{ 285, "Plaguebloom" },
	{ 290, "Icecap" },
	{ 300, "Black Lotus" },
}

local ORES = {
	{ 1, "Copper Vein", "Poor Copper Vein", "Weak Copper Vein", "Minor Copper Vein", "Lesser Copper Vein", "Small Copper Vein" },
	{ 65, "Tin Vein", "Incendicite Mineral Vein" },
	{ 75, "Silver Vein", "Ooze Covered Silver Vein", "Lesser Bloodstone Deposit" },
	{ 125, "Iron Deposit", "Cold Iron Deposit", "Ooze Covered Iron Deposit" },
	{ 150, "Indurium Mineral Vein" },
	{ 155, "Gold Vein", "Ooze Covered Gold Vein" },
	{ 175, "Mithril Deposit", "Fool's Gold Vein", "Ooze Covered Mithril Deposit" },
	{ 230, "Truesilver Deposit", "Dark Iron Deposit", "Ooze Covered Truesilver Deposit" },
	{ 245, "Small Thorium Vein", "Starsilver Vein", "Greater Moonstone Formation", "Ooze Covered Thorium Vein" },
	{ 275, "Rich Thorium Vein", "Hakkari Thorium Vein", "Ooze Covered Rich Thorium Vein" },
	{ 300, "Heavy Thorium Vein" },
	{ 305, "Small Obsidian Chunk", "Large Obsidian Chunk" },
}

-- Запертые объекты в мире. Одинаковые сундуки бывают разной сложности
-- в разных зонах: для них хранится минимум и пометка varies.
local LOCKS = {
	{ 1, "Practice Lockbox", "Ambermill Strongbox", "Buccaneer's Strongbox", "Venture Co. Strongbox" },
	{ 25, "Lucius's Lockbox", "The Jewel of the Southsea", "Large Iron Bound Chest" },
	{ 70, "Duskwood Chest", "Gallywix's Lockbox" },
	{ 100, "Benedict's Chest" },
	{ 160, "Cozzle's Footlocker" },
	{ 250, "Scarlet Footlocker" },
}
local LOCKS_VARY = {
	{ 1, "Alliance Strongbox" },
	{ 70, "Battered Footlocker", "Waterlogged Footlocker" },
	{ 175, "Dented Footlocker", "Mossy Footlocker", "Large Mithril Bound Chest" },
}

-- Английское имя -> { prof, req, key[, varies] }. key — ключ изученных данных.
HG.RESOURCES = {}

local function Fill(prof, groups, varies)
	for _, group in ipairs(groups) do
		for i = 2, #group do
			local name = group[i]
			HG.RESOURCES[name] = { prof = prof, req = group[1], key = name, varies = varies or nil }
		end
	end
end

Fill("herb", HERBS)
Fill("mine", ORES)
Fill("lock", LOCKS)
Fill("lock", LOCKS_VARY, true)

------------------------------------------------------------------------
-- Добыча со сбора. Здесь только то, что падает всегда: сама трава,
-- руда и камень. Самоцветы и прочее аддон узнаёт из реальной добычи.
------------------------------------------------------------------------

local HERB_ITEM = {
	["Peacebloom"] = 2447, ["Wilted Peacebloom"] = 2447,
	["Silverleaf"] = 765, ["Stunted Silverleaf"] = 765,
	["Earthroot"] = 2449, ["Mageroyal"] = 785, ["Briarthorn"] = 2450,
	["Stranglekelp"] = 3820, ["Bruiseweed"] = 2453, ["Wild Steelbloom"] = 3355,
	["Grave Moss"] = 3369, ["Kingsblood"] = 3356, ["Liferoot"] = 3357,
	["Fadeleaf"] = 3818, ["Goldthorn"] = 3821, ["Khadgar's Whisker"] = 3358,
	["Wintersbite"] = 3819, ["Firebloom"] = 4625, ["Purple Lotus"] = 8831,
	["Arthas' Tears"] = 8836, ["Sungrass"] = 8838, ["Blindweed"] = 8839,
	["Ghost Mushroom"] = 8845, ["Gromsblood"] = 8846, ["Golden Sansam"] = 13464,
	["Dreamfoil"] = 13463, ["Mountain Silversage"] = 13465, ["Plaguebloom"] = 13466,
	["Icecap"] = 13467, ["Black Lotus"] = 13468,
}

-- Попутная трава (падает не всегда).
local HERB_BONUS = {
	["Mageroyal"] = 2452, ["Briarthorn"] = 2452, -- Скорополох
	["Purple Lotus"] = 8153,                     -- Дикая лоза
}

local ORE_ITEMS = {
	["Copper Vein"] = { 2770, 2835 }, ["Poor Copper Vein"] = { 2770, 2835 },
	["Weak Copper Vein"] = { 2770, 2835 }, ["Minor Copper Vein"] = { 2770, 2835 },
	["Lesser Copper Vein"] = { 2770, 2835 }, ["Small Copper Vein"] = { 2770, 2835 },
	["Tin Vein"] = { 2771, 2836 },
	["Silver Vein"] = { 2775 }, ["Ooze Covered Silver Vein"] = { 2775 },
	["Iron Deposit"] = { 2772, 2838 }, ["Cold Iron Deposit"] = { 2772, 2838 },
	["Ooze Covered Iron Deposit"] = { 2772, 2838 },
	["Gold Vein"] = { 2776 }, ["Ooze Covered Gold Vein"] = { 2776 },
	["Mithril Deposit"] = { 3858, 7912 }, ["Ooze Covered Mithril Deposit"] = { 3858, 7912 },
	["Truesilver Deposit"] = { 7911 }, ["Ooze Covered Truesilver Deposit"] = { 7911 },
	["Dark Iron Deposit"] = { 11370 },
	["Small Thorium Vein"] = { 10620, 12365 }, ["Ooze Covered Thorium Vein"] = { 10620, 12365 },
	["Rich Thorium Vein"] = { 10620, 12365 }, ["Ooze Covered Rich Thorium Vein"] = { 10620, 12365 },
	["Hakkari Thorium Vein"] = { 10620 },
	["Incendicite Mineral Vein"] = { 3340 },
	["Lesser Bloodstone Deposit"] = { 4278 },
	["Indurium Mineral Vein"] = { 5833 },
	["Small Obsidian Chunk"] = { 22202 }, ["Large Obsidian Chunk"] = { 22203 },
}

-- Ключ ресурса -> список { id, sure } (sure = падает всегда).
HG.SEED_DROPS = {}
for name, id in pairs(HERB_ITEM) do
	HG.SEED_DROPS[name] = { { id = id, sure = true } }
	if HERB_BONUS[name] then
		table.insert(HG.SEED_DROPS[name], { id = HERB_BONUS[name] })
	end
end
for name, ids in pairs(ORE_ITEMS) do
	local list = {}
	for _, id in ipairs(ids) do
		list[#list + 1] = { id = id, sure = true }
	end
	HG.SEED_DROPS[name] = list
end

------------------------------------------------------------------------
-- Подсказки предметов: id предмета -> что о нём сказать.
------------------------------------------------------------------------

-- Навык переплавки руды.
local SMELT = {
	[2770] = 1, [2771] = 65, [2775] = 75, [2772] = 125, [2776] = 155,
	[3858] = 175, [7911] = 230, [11370] = 230, [10620] = 250,
}

-- Сундучки в сумках (id предмета -> навык взлома).
local LOCKBOX = {
	[16882] = 1,   -- Battered Junkbox
	[4632] = 1,    -- Ornate Bronze Lockbox
	[6354] = 1,    -- Small Locked Chest
	[4633] = 25,   -- Heavy Bronze Lockbox
	[16883] = 70,  -- Worn Junkbox
	[4634] = 70,   -- Iron Lockbox
	[6355] = 70,   -- Sturdy Locked Chest
	[4636] = 125,  -- Strong Iron Lockbox
	[16884] = 175, -- Sturdy Junkbox
	[4637] = 175,  -- Steel Lockbox
	[13875] = 175, -- Ironbound Locked Chest
	[4638] = 225,  -- Reinforced Steel Lockbox
	[5758] = 225,  -- Mithril Lockbox
	[5759] = 225,  -- Thorium Lockbox
	[5760] = 225,  -- Eternium Lockbox
	[16885] = 250, -- Heavy Junkbox
	[13918] = 250, -- Reinforced Locked Chest
}

-- id предмета -> { gather = { prof, req }, smelt = req, lock = req }
HG.ITEM_INFO = {}

local function ItemInfo(id)
	local info = HG.ITEM_INFO[id]
	if not info then
		info = {}
		HG.ITEM_INFO[id] = info
	end
	return info
end

local function NoteGatherItem(id, prof, req)
	local info = ItemInfo(id)
	if not info.gather or req < info.gather.req then
		info.gather = { prof = prof, req = req }
	end
end

for name, id in pairs(HERB_ITEM) do
	NoteGatherItem(id, "herb", HG.RESOURCES[name].req)
end
for name, ids in pairs(ORE_ITEMS) do
	NoteGatherItem(ids[1], "mine", HG.RESOURCES[name].req)
end
for id, req in pairs(SMELT) do
	ItemInfo(id).smelt = req
end
for id, req in pairs(LOCKBOX) do
	ItemInfo(id).lock = req
end

-- Основной предмет -> ресурс, чтобы узнать узел по добыче.
-- Берём первое имя группы; если предмет дают ресурсы с разным
-- требованием (ториевая руда), связь неоднозначна и не используется.
HG.ITEM_TO_RESOURCE = {}
do
	local ambiguous = {}
	local function Link(id, name)
		local known = HG.ITEM_TO_RESOURCE[id]
		if known == nil and not ambiguous[id] then
			HG.ITEM_TO_RESOURCE[id] = name
		elseif known and HG.RESOURCES[known].req ~= HG.RESOURCES[name].req then
			HG.ITEM_TO_RESOURCE[id] = nil
			ambiguous[id] = true
		end
	end
	for _, group in ipairs(HERBS) do
		for i = 2, #group do
			if HERB_ITEM[group[i]] then
				Link(HERB_ITEM[group[i]], group[i])
			end
		end
	end
	for _, group in ipairs(ORES) do
		for i = 2, #group do
			local ids = ORE_ITEMS[group[i]]
			if ids then
				Link(ids[1], group[i])
			end
		end
	end
end

------------------------------------------------------------------------
-- Заклинания и формулы
------------------------------------------------------------------------

-- id заклинания сбора -> профессия.
HG.GATHER_SPELL = {}
for prof, info in pairs(HG.PROF) do
	for _, id in ipairs(info.gather) do
		HG.GATHER_SPELL[id] = prof
	end
end

-- Требуемый навык снятия шкур по уровню существа.
function HG.SkinRequirement(level)
	if level <= 10 then
		return 1
	end
	if level <= 20 then
		return (level - 10) * 10
	end
	return level * 5
end

-- Уровень таурена для Культивации травы: навык / 5 (не меньше 1, не больше 60).
function HG.CultivationLevel(req)
	return math.max(1, math.min(60, math.ceil(req / 5)))
end

-- Пороги цветов: с какого навыка ресурс жёлтый, зелёный и серый.
-- Для требования 1 пороги ровные: 25 / 50 / 100 (как в таблицах Wowhead).
function HG.Thresholds(req)
	local base = req <= 1 and 0 or req
	return base + 25, base + 50, base + 100
end

-- Цвет сложности: "red", "orange", "yellow", "green" или "grey".
function HG.Difficulty(skill, req)
	local yellow, green, grey = HG.Thresholds(req)
	if skill < req then
		return "red"
	elseif skill < yellow then
		return "orange"
	elseif skill < green then
		return "yellow"
	elseif skill < grey then
		return "green"
	end
	return "grey"
end

function HG.Paint(text, difficulty)
	local hex = HG.HEX[difficulty]
	if not hex then
		return text
	end
	return "|cff" .. hex .. text .. "|r"
end
