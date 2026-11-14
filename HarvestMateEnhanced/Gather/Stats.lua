local _, ns = ... local HG = ns.HG -- HME patch P1

-- Статистика за всё время, рекорды и достижения.
--
-- Достижения идут сериями: одна серия — одна цель с несколькими ступенями
-- (I–V). Есть и разовые достижения. Всё считается по сохранённой
-- статистике (db.stats), полученные ступени лежат в db.ach.

local ROMAN = { "I", "II", "III", "IV", "V" }
local TIER_POINTS = { 5, 10, 15, 20, 30 }
local GOLD = 10000
local RATE_MIN_TIME = 600        -- доход в час считается рекордом после 10 минут
local STREAK_COUNT, STREAK_WINDOW = 10, 300
local RECORD_MIN_GATHERS = 20    -- до этого рекорды бьются слишком легко, молчим

-- Сумма текстом без цветов и значков: годится для чата.
function HG.PlainMoney(copper)
	local L = HG.L
	copper = math.floor(copper + 0.5)
	local parts = {}
	local gold, silver, rest = math.floor(copper / GOLD), math.floor(copper / 100) % 100, copper % 100
	if gold > 0 then
		parts[#parts + 1] = gold .. L.COIN_GOLD
	end
	if silver > 0 then
		parts[#parts + 1] = silver .. L.COIN_SILVER
	end
	if rest > 0 or #parts == 0 then
		parts[#parts + 1] = rest .. L.COIN_COPPER
	end
	return table.concat(parts, " ")
end

------------------------------------------------------------------------
-- Хранилище
------------------------------------------------------------------------

local function Sub(parent, key)
	if type(parent[key]) ~= "table" then
		parent[key] = {}
	end
	return parent[key]
end

local function Stats()
	local db = HG.db
	local stats = Sub(db, "stats")
	Sub(stats, "gathers")
	local kinds = Sub(stats, "kinds")
	Sub(kinds, "herb")
	Sub(kinds, "mine")
	Sub(stats, "best")
	Sub(stats, "flags")
	for _, key in ipairs({ "items", "value", "skinLevel", "locks", "keyGathers" }) do
		if type(stats[key]) ~= "number" then
			stats[key] = 0
		end
	end
	Sub(db, "ach")
	return stats
end
HG.Stats = Stats

local function Count(list)
	local total = 0
	for _ in pairs(list) do
		total = total + 1
	end
	return total
end

------------------------------------------------------------------------
-- Список достижений
------------------------------------------------------------------------

local ICON = {
	herb = "Interface\\Icons\\INV_Misc_Flower_02",
	mine = "Interface\\Icons\\Trade_Mining",
	skin = "Interface\\Icons\\INV_Misc_Pelt_Wolf_01",
	lock = "Interface\\Icons\\INV_Misc_Key_03",
	key = "Interface\\Icons\\INV_Misc_Gear_01",
	money = "Interface\\Icons\\INV_Misc_Coin_01",
	other = "Interface\\Icons\\INV_Misc_Book_09",
}

local CATEGORY_LABEL = {
	herb = "HERBALISM", mine = "MINING", skin = "SKINNING", lock = "LOCKPICKING",
	key = "CAT_KEY", money = "CAT_MONEY", other = "CAT_OTHER",
}

local function Gathers(prof)
	return function(stats)
		return stats.gathers[prof] or 0
	end
end

local function BaseSkill(prof)
	return function()
		local info = HG.SkillInfo(prof)
		return info and info.base or 0
	end
end

local function Best(key)
	return function(stats)
		return stats.best[key] or 0
	end
end

local function Flag(key)
	return function(stats)
		return stats.flags[key] and 1 or 0
	end
end

local COUNT_TIERS = { 10, 100, 500, 2000, 10000 }
local SKILL_TIERS = { 75, 150, 225, 300 }

-- money = пороги в меди; skill = навык профессии; single = разовое, без ступеней.
local SERIES = {
	-- Травничество
	{ id = "herb_gathers", cat = "herb", name = "ACH_HERB_GATHERS", tiers = COUNT_TIERS, value = Gathers("herb") },
	{ id = "herb_kinds", cat = "herb", name = "ACH_HERB_KINDS", tiers = { 3, 8, 15, 22, 28 },
		value = function(stats) return Count(stats.kinds.herb) end },
	{ id = "skill_herb", cat = "herb", name = "ACH_SKILL_HERB", desc = "ACH_SKILL_D", skill = "herb", tiers = SKILL_TIERS, value = BaseSkill("herb") },
	{ id = "lotus", cat = "herb", name = "ACH_LOTUS", single = true, value = Flag("lotus") },
	-- Горное дело
	{ id = "mine_gathers", cat = "mine", name = "ACH_MINE_GATHERS", tiers = COUNT_TIERS, value = Gathers("mine") },
	{ id = "mine_kinds", cat = "mine", name = "ACH_MINE_KINDS", tiers = { 2, 4, 6, 8, 10 },
		value = function(stats) return Count(stats.kinds.mine) end },
	{ id = "skill_mine", cat = "mine", name = "ACH_SKILL_MINE", desc = "ACH_SKILL_D", skill = "mine", tiers = SKILL_TIERS, value = BaseSkill("mine") },
	{ id = "thorium", cat = "mine", name = "ACH_THORIUM", single = true, value = Flag("thorium") },
	-- Снятие шкур
	{ id = "skin_gathers", cat = "skin", name = "ACH_SKIN_GATHERS", tiers = COUNT_TIERS, value = Gathers("skin") },
	{ id = "skin_level", cat = "skin", name = "ACH_SKIN_LEVEL", tiers = { 15, 30, 45, 55, 60 },
		value = function(stats) return stats.skinLevel end },
	{ id = "skill_skin", cat = "skin", name = "ACH_SKILL_SKIN", desc = "ACH_SKILL_D", skill = "skin", tiers = SKILL_TIERS, value = BaseSkill("skin") },
	-- Взлом замков
	{ id = "lock", cat = "lock", name = "ACH_LOCK", tiers = { 5, 25, 100, 250, 1000 },
		value = function(stats) return stats.locks end },
	-- Сбор одной клавишей
	{ id = "key", cat = "key", name = "ACH_KEY", tiers = COUNT_TIERS,
		value = function(stats) return stats.keyGathers end },
	{ id = "streak", cat = "key", name = "ACH_STREAK", single = true, value = Flag("streak") },
	{ id = "geared", cat = "key", name = "ACH_GEARED", single = true, value = Flag("geared") },
	-- Заработок
	{ id = "value", cat = "money", name = "ACH_VALUE", money = true,
		tiers = { 10 * GOLD, 100 * GOLD, 500 * GOLD, 2000 * GOLD, 10000 * GOLD },
		value = function(stats) return stats.value end },
	{ id = "rate", cat = "money", name = "ACH_RATE", money = true,
		tiers = { 5 * GOLD, 20 * GOLD, 50 * GOLD, 100 * GOLD, 250 * GOLD }, value = Best("rate") },
	{ id = "single", cat = "money", name = "ACH_SINGLE", money = true,
		tiers = { 1000, GOLD, 5 * GOLD, 20 * GOLD, 100 * GOLD }, value = Best("single") },
	{ id = "accountant", cat = "money", name = "ACH_ACCOUNTANT", single = true, value = Flag("accountant") },
	-- Разное
	{ id = "first", cat = "other", name = "ACH_FIRST", single = true, value = Flag("first") },
	{ id = "session", cat = "other", name = "ACH_SESSION", tiers = { 25, 50, 100, 250, 500 }, value = Best("sessionGathers") },
	{ id = "items", cat = "other", name = "ACH_ITEMS", tiers = { 100, 1000, 5000, 20000, 100000 },
		value = function(stats) return stats.items end },
	{ id = "triathlon", cat = "other", name = "ACH_TRIATHLON", single = true, value = Flag("triathlon") },
	{ id = "learned", cat = "other", name = "ACH_LEARNED", tiers = { 1, 3, 5, 10, 20 },
		value = function() return Count(HG.db.learned.custom) end },
	{ id = "showoff", cat = "other", name = "ACH_SHOWOFF", single = true, value = Flag("showoff") },
}

for _, series in ipairs(SERIES) do
	if series.single then
		series.tiers = { 1 }
	end
	series.icon = ICON[series.cat]
end

function HG.AchName(series, tier)
	local name = HG.L[series.name]
	if series.single then
		return name
	end
	return name .. " " .. (ROMAN[tier] or tier)
end

-- Число ступени так, как его показывать: сумма или просто число.
function HG.AchAmount(series, amount)
	if series.money then
		return HG.PlainMoney(amount)
	end
	return tostring(math.floor(amount))
end

function HG.AchDesc(series, tier)
	local L = HG.L
	local template = L[series.desc or (series.name .. "_D")]
	if series.single then
		return template
	end
	local threshold = series.tiers[tier]
	if series.skill then
		return template:format(HG.ProfName(series.skill), threshold)
	end
	if series.money then
		return template:format(HG.PlainMoney(threshold))
	end
	return template:format(threshold)
end

function HG.AchPoints(series, tier)
	return series.single and 10 or (TIER_POINTS[tier] or 10)
end

local function Earned(series, tier)
	return HG.db.ach[series.id .. ":" .. tier] ~= nil
end

-- Сколько ступеней серии получено подряд с первой.
local function EarnedTiers(series)
	local earned = 0
	for tier = 1, #series.tiers do
		if Earned(series, tier) then
			earned = tier
		end
	end
	return earned
end

local function Visible(series, stats)
	-- Взлом замков показываем только тем, кому он доступен.
	if series.cat == "lock" then
		return HG.KnowsLockpicking() or stats.locks > 0
	end
	return true
end

-- Строки для окна достижений: по одной на серию.
function HG.AchRows()
	local stats = Stats()
	local rows = {}
	for _, series in ipairs(SERIES) do
		if Visible(series, stats) then
			local earned = EarnedTiers(series)
			local target = math.min(earned + 1, #series.tiers)
			rows[#rows + 1] = {
				series = series,
				earned = earned,
				total = #series.tiers,
				value = series.value(stats),
				target = target,
				threshold = series.tiers[target],
				category = HG.L[CATEGORY_LABEL[series.cat]],
			}
		end
	end
	return rows
end

-- Получено, всего, очков.
function HG.AchTotals()
	local stats = Stats()
	local earned, total, points = 0, 0, 0
	for _, series in ipairs(SERIES) do
		if Visible(series, stats) then
			for tier = 1, #series.tiers do
				total = total + 1
				if Earned(series, tier) then
					earned = earned + 1
					points = points + HG.AchPoints(series, tier)
				end
			end
		end
	end
	return earned, total, points
end

------------------------------------------------------------------------
-- Чат: поделиться с гильдией или группой
------------------------------------------------------------------------

local function GroupChannel()
	if not IsInGroup then
		return nil
	end
	local instance = LE_PARTY_CATEGORY_INSTANCE
	if instance and IsInGroup(instance) then
		return "INSTANCE_CHAT"
	end
	if IsInRaid and IsInRaid() then
		return "RAID"
	end
	return IsInGroup() and "PARTY" or nil
end

-- where: "GUILD" или "PARTY". quiet — автоматическая отправка, без отчёта игроку.
function HG.Share(text, where, quiet)
	local L = HG.L
	local channel
	if where == "GUILD" then
		if not (IsInGuild and IsInGuild()) then
			if not quiet then
				HG.Say(L.NOT_IN_GUILD)
			end
			return false
		end
		channel = "GUILD"
	else
		channel = GroupChannel()
		if not channel then
			if not quiet then
				HG.Say(L.NOT_IN_GROUP)
			end
			return false
		end
	end
	local send = (C_ChatInfo and C_ChatInfo.SendChatMessage) or _G.SendChatMessage
	if send then
		pcall(send, "[" .. HG.title .. "] " .. text, channel)
	end
	if not quiet then
		Stats().flags.showoff = true
		HG.CheckAchievements()
	end
	return true
end

function HG.ShareAchievement(series, tier, where, quiet)
	return HG.Share(HG.L.ACH_SHARE_MSG:format(HG.AchName(series, tier), HG.AchDesc(series, tier)), where, quiet)
end

------------------------------------------------------------------------
-- Выдача достижений
------------------------------------------------------------------------

local function Earn(series, tier, silent)
	local id = series.id .. ":" .. tier
	if HG.db.ach[id] ~= nil then
		return
	end
	HG.db.ach[id] = (_G.time and _G.time()) or 0
	if silent then
		return
	end
	local L = HG.L
	local name, desc = HG.AchName(series, tier), HG.AchDesc(series, tier)
	HG.Say("|cffffd100" .. L.ACH_EARNED .. "|r " .. name .. " |cffaaaaaa(" .. desc .. ")|r")
	local opt = HG.db.opt
	if opt.achToast then
		HG.Toast({
			header = L.TOAST_ACH,
			name = name,
			desc = desc,
			icon = series.icon,
			points = HG.AchPoints(series, tier),
			page = "ach",
			share = function(where)
				HG.ShareAchievement(series, tier, where)
			end,
		})
	end
	if opt.achGuild then
		HG.ShareAchievement(series, tier, "GUILD", true)
	end
	HG.Signal("ACHIEVEMENT")
end

-- silent — молча отметить уже выполненное (первый запуск).
function HG.CheckAchievements(silent)
	if not HG.db then
		return
	end
	local stats = Stats()
	for _, series in ipairs(SERIES) do
		local value = series.value(stats)
		for tier, threshold in ipairs(series.tiers) do
			if value >= threshold then
				Earn(series, tier, silent)
			end
		end
	end
end

------------------------------------------------------------------------
-- Рекорды
------------------------------------------------------------------------

local RECORDS = {
	{ key = "rate", label = "REC_RATE", money = true },
	{ key = "sessionValue", label = "REC_SESSION_VALUE", money = true },
	{ key = "sessionGathers", label = "REC_SESSION_GATHERS" },
	{ key = "single", label = "REC_SINGLE", money = true },
}

local announced = {} -- рекорд объявляем один раз за сессию

local function TotalGathers(stats)
	local total = 0
	for _, count in pairs(stats.gathers) do
		total = total + count
	end
	return total
end

local function Record(record, value)
	local stats = Stats()
	local best = stats.best[record.key] or 0
	if value <= best then
		return
	end
	stats.best[record.key] = value
	if best <= 0 or announced[record.key] or TotalGathers(stats) < RECORD_MIN_GATHERS then
		return
	end
	announced[record.key] = true
	local L = HG.L
	local label = L[record.label]
	local plain = record.money and HG.PlainMoney(value) or tostring(math.floor(value))
	HG.Say("|cffffd100" .. L.REC_TOAST .. "|r " .. label .. ": " .. plain)
	if HG.db.opt.achToast then
		HG.Toast({
			header = L.TOAST_REC,
			name = label,
			desc = record.money and HG.Money(value) or plain,
			icon = ICON.money,
			page = "records",
			share = function(where)
				HG.Share(L.REC_TOAST .. " " .. label .. ": " .. plain, where)
			end,
		})
	end
end

-- Строки для окна рекордов: { label, value }.
function HG.RecordLines()
	local L = HG.L
	local stats = Stats()
	local lines = {}
	for _, record in ipairs(RECORDS) do
		local value = stats.best[record.key] or 0
		lines[#lines + 1] = { L[record.label], value > 0 and (record.money and HG.Money(value) or tostring(math.floor(value))) or "-" }
	end
	lines[#lines + 1] = { L.REC_TOTAL_GATHERS, tostring(TotalGathers(stats)) }
	for _, prof in ipairs({ "herb", "mine", "skin" }) do
		local count = stats.gathers[prof] or 0
		if count > 0 then
			lines[#lines + 1] = { "  " .. HG.ProfName(prof), tostring(count) }
		end
	end
	lines[#lines + 1] = { L.REC_TOTAL_ITEMS, tostring(stats.items) }
	lines[#lines + 1] = { L.REC_TOTAL_VALUE, HG.Money(stats.value) }
	return lines
end

------------------------------------------------------------------------
-- Сбор статистики
------------------------------------------------------------------------

local recent = {} -- время последних сборов, для «Конвейера»

HG.Listen("GATHER_LOOT", function(prof, key, counts, extra)
	local stats = Stats()
	stats.gathers[prof] = (stats.gathers[prof] or 0) + 1

	local value, items = 0, 0
	for id, count in pairs(counts) do
		items = items + count
		value = value + (HG.BestPrice(id) or 0) * count
	end
	stats.items = stats.items + items
	stats.value = stats.value + value

	local flags = stats.flags
	flags.first = true
	local entry = key and HG.Find(key)
	local resource = entry and entry.key or key
	if resource and stats.kinds[prof] then
		stats.kinds[prof][resource] = true
	end
	if resource == "Black Lotus" then
		flags.lotus = true
	elseif resource == "Rich Thorium Vein" then
		flags.thorium = true
	end
	if prof == "skin" and key then
		local level = tonumber(key:match("^skin:(%d+)$"))
		if level and level > stats.skinLevel then
			stats.skinLevel = level
		end
	end
	if extra and extra.viaKey then
		stats.keyGathers = stats.keyGathers + 1
	end
	if extra and extra.geared then
		flags.geared = true
	end

	-- 10 сборов за 5 минут
	local now = GetTime()
	recent[#recent + 1] = now
	while recent[1] and now - recent[1] > STREAK_WINDOW do
		table.remove(recent, 1)
	end
	if #recent >= STREAK_COUNT then
		flags.streak = true
	end

	-- Трава, руда и шкура за одну сессию
	if HG.SessionProfession("herb") and HG.SessionProfession("mine") and HG.SessionProfession("skin") then
		flags.triathlon = true
	end

	Record(RECORDS[4], value)
	Record(RECORDS[3], HG.session.gathers)
	local sessionValue = HG.SessionValue()
	Record(RECORDS[2], sessionValue)
	local elapsed = HG.SessionElapsed()
	if elapsed >= RATE_MIN_TIME then
		Record(RECORDS[1], sessionValue / elapsed * 3600)
	end

	HG.CheckAchievements()
end)

HG.Listen("LOCKPICKED", function()
	local stats = Stats()
	stats.locks = stats.locks + 1
	HG.CheckAchievements()
end)

HG.Listen("USED_BAGS", function()
	Stats().flags.accountant = true
	HG.CheckAchievements()
end)

-- Навыки читаются при входе в мир. В первый раз уже выполненное
-- отмечаем молча, чтобы не засыпать игрока окнами.
HG.Listen("SKILLS", function()
	if not HG.db then
		return
	end
	if not HG.db.achBaseline then
		HG.db.achBaseline = true
		HG.CheckAchievements(true)
	else
		HG.CheckAchievements()
	end
end)

HG.commands.ach = function()
	HG.OpenHub("ach")
end

-- Пробное окно достижения: показывает случайное достижение так, как оно
-- выглядит при получении. Ничего не выдаёт и не сохраняет, а кнопки
-- «В гильдию» и «В группу» только печатают текст сообщения вам в чат.
function HG.TestAchievement()
	if not HG.db then
		return
	end
	local L = HG.L
	local series = SERIES[math.random(#SERIES)]
	local tier = math.random(#series.tiers)
	local name, desc = HG.AchName(series, tier), HG.AchDesc(series, tier)
	HG.Say("|cffffd100" .. L.ACH_EARNED .. "|r " .. name .. " |cffaaaaaa(" .. desc .. ")|r")
	HG.Toast({
		header = L.TOAST_ACH,
		name = name,
		desc = desc,
		icon = series.icon,
		points = HG.AchPoints(series, tier),
		page = "ach",
		share = function(where)
			local label = where == "GUILD" and L.SHARE_GUILD or L.SHARE_PARTY
			HG.Say("|cffaaaaaa" .. label .. ":|r [" .. HG.title .. "] " .. L.ACH_SHARE_MSG:format(name, desc))
		end,
	})
end

HG.commands.test = HG.TestAchievement
