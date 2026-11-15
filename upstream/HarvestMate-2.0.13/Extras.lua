local _, HG = ...

-- Дополнительные строки подсказки ресурса: пороги цветов, предел навыка,
-- Культивация и добыча с ценами. Используются и в подсказке, и в
-- подсветке ресурса рядом.

local MAX_LOOT_LINES = 4 -- без Shift

------------------------------------------------------------------------
-- Пороги цветов: "1–24 · 25–49 · 50–99 · 100+"
------------------------------------------------------------------------

function HG.BandsLine(req)
	local yellow, green, grey = HG.Thresholds(req)
	local parts = {
		HG.Paint(req .. "–" .. (yellow - 1), "orange"),
		HG.Paint(yellow .. "–" .. (green - 1), "yellow"),
		HG.Paint(green .. "–" .. (grey - 1), "green"),
		HG.Paint(grey .. "+", "grey"),
	}
	return HG.L.BANDS .. " " .. table.concat(parts, "  ")
end

------------------------------------------------------------------------
-- Предел навыка
------------------------------------------------------------------------

-- Строка, если навык упёрся в предел текущего ранга (не 300).
function HG.CapLine(prof)
	if prof == "lock" then
		return nil
	end
	local info = HG.SkillInfo(prof)
	if not info or info.max <= 0 or info.max >= HG.SKILL_CAP or info.base < info.max then
		return nil
	end
	return HG.Paint(HG.L.CAP_LINE, "orange")
end

------------------------------------------------------------------------
-- Культивация (таурены)
------------------------------------------------------------------------

function HG.KnowsCultivation()
	if not IsPlayerSpell then
		return false
	end
	local known = IsPlayerSpell(HG.CULTIVATION_SPELL)
	return not HG.Hidden(known) and known == true
end

-- Сколько секунд до готовности: 0 — готова, nil — неизвестно.
function HG.CultivationRemaining()
	local id = HG.CULTIVATION_SPELL
	local start, duration
	if C_Spell and C_Spell.GetSpellCooldown then
		local info = HG.Tbl(C_Spell.GetSpellCooldown(id))
		if not info then
			return nil
		end
		start, duration = HG.Num(info.startTime), HG.Num(info.duration)
	elseif GetSpellCooldown then
		local s, d = GetSpellCooldown(id)
		start, duration = HG.Num(s), HG.Num(d)
	end
	if not start or not duration then
		return nil
	end
	-- Общий откат (до 1.5 с) — это не откат Культивации.
	if start == 0 or duration <= 1.5 then
		return 0
	end
	return math.max(0, start + duration - GetTime())
end

local function Clock(seconds)
	seconds = math.ceil(seconds)
	return ("%d:%02d"):format(math.floor(seconds / 60), seconds % 60)
end

function HG.CultivationLine(entry)
	if entry.prof ~= "herb" or not HG.db.opt.cultivation or not HG.KnowsCultivation() then
		return nil
	end
	local L = HG.L
	local req = entry.req or HG.Requirement(entry)
	if req then
		local need = HG.CultivationLevel(req)
		local level = HG.Num(UnitLevel("player")) or 0
		if level < need then
			return HG.Paint(L.CULT_LEVEL:format(need), "red")
		end
	end
	local left = HG.CultivationRemaining()
	if left == nil then
		return nil
	end
	if left <= 0 then
		return HG.Paint(L.CULT_READY, "green")
	end
	return HG.Paint(L.CULT_WAIT:format(Clock(left)), "grey")
end

------------------------------------------------------------------------
-- Добыча
------------------------------------------------------------------------

-- Список { id, chance } для ключа ресурса: сначала то, что падает всегда,
-- затем изученное по убыванию частоты. chance = nil — «всегда».
function HG.LootFor(key)
	local result, seen = {}, {}
	local learned = HG.db.learned.drops[key]
	local total = learned and HG.Num(learned.n) or 0
	for _, seed in ipairs(HG.SEED_DROPS[key] or {}) do
		seen[seed.id] = true
		local chance
		if not seed.sure and total > 0 then
			chance = (learned.items[seed.id] or 0) / total
		end
		result[#result + 1] = { id = seed.id, chance = chance, sure = seed.sure }
	end
	if total > 0 then
		local extra = {}
		for id, count in pairs(learned.items) do
			if not seen[id] then
				extra[#extra + 1] = { id = id, chance = count / total }
			end
		end
		table.sort(extra, function(a, b)
			if a.chance ~= b.chance then
				return a.chance > b.chance
			end
			return a.id < b.id
		end)
		for _, item in ipairs(extra) do
			-- Падает почти каждый раз — показываем как «всегда».
			if total >= 5 and item.chance >= 0.98 then
				item.sure, item.chance = true, nil
			end
			result[#result + 1] = item
		end
	end
	return result, total
end

local function Percent(chance)
	local value = chance * 100
	if value >= 10 then
		return ("%d%%"):format(math.floor(value + 0.5))
	end
	return ("%.1f%%"):format(value)
end

-- Строки добычи: заголовок и по строке на предмет.
function HG.LootLines(key)
	if not HG.db.opt.showLoot then
		return {}
	end
	local items, total = HG.LootFor(key)
	if #items == 0 then
		return {}
	end
	local L = HG.L
	local lines = {}
	local limit = (IsShiftKeyDown and IsShiftKeyDown()) and #items or MAX_LOOT_LINES
	local hidden = 0
	for _, item in ipairs(items) do
		local label = HG.ItemLabel(item.id)
		if label and #lines < limit then
			local text = "  " .. label
			if item.chance then
				text = text .. " |cffaaaaaa(" .. Percent(item.chance) .. ")|r"
			end
			local price = HG.db.opt.showPrices and HG.PriceText(item.id)
			if price then
				text = text .. " — " .. price
			end
			lines[#lines + 1] = text
		elseif label then
			hidden = hidden + 1
		end
	end
	if #lines == 0 then
		return {}
	end
	local header = L.LOOT
	if total > 0 then
		header = header .. " |cffaaaaaa" .. L.LOOT_SEEN:format(total) .. "|r"
	end
	table.insert(lines, 1, header)
	if hidden > 0 then
		lines[#lines + 1] = "  |cffaaaaaa" .. L.LOOT_MORE:format(hidden) .. "|r"
	end
	local average = HG.db.opt.showPrices and HG.AverageValue(key)
	if average then
		lines[#lines + 1] = L.AVG_VALUE:format(HG.Money(average))
	end
	return lines
end

-- Сколько в среднем приносит один сбор: шанс × среднее количество × цена.
function HG.AverageValue(key)
	local items = HG.LootFor(key)
	local learned = HG.db.learned.drops[key]
	local sum = 0
	for _, item in ipairs(items) do
		local price = HG.BestPrice(item.id)
		if price then
			local quantity = 1
			local seen = learned and learned.items[item.id]
			if seen and seen > 0 and type(learned.qty) == "table" and learned.qty[item.id] then
				quantity = learned.qty[item.id] / seen
			end
			sum = sum + (item.chance or 1) * quantity * price
		end
	end
	return sum > 0 and sum or nil
end

-- «Ещё N до следующего цвета», в цвете, которым ресурс станет.
function HG.UntilNextLine(skill, req)
	local yellow, green, grey = HG.Thresholds(req)
	local steps = { { req, "orange" }, { yellow, "yellow" }, { green, "green" }, { grey, "grey" } }
	for _, step in ipairs(steps) do
		if skill < step[1] then
			return HG.Paint(HG.L.UNTIL_NEXT:format(step[1] - skill), step[2])
		end
	end
	return nil
end

-- «Навык: 42 + 5 от экипировки», если есть бонус.
function HG.BonusLine(prof)
	local info = HG.SkillInfo(prof)
	if info and not info.estimate and info.cur > info.base then
		return HG.L.BONUS_LINE:format(info.base, info.cur - info.base)
	end
	return nil
end

------------------------------------------------------------------------
-- Все дополнительные строки для ресурса
------------------------------------------------------------------------

function HG.ExtraLines(entry)
	local opt = HG.db.opt
	local lines = {}
	if not opt[entry.prof] or not HG.Skill(entry.prof) then
		-- Без профессии остаётся только Культивация (траву можно вырастить и без неё).
		local cult = HG.CultivationLine(entry)
		if cult then
			lines[1] = cult
		end
		return lines
	end
	local req = HG.Requirement(entry)
	if opt.showBands and req and entry.prof ~= "lock" then
		lines[#lines + 1] = HG.BandsLine(req)
		lines[#lines + 1] = HG.UntilNextLine(HG.Skill(entry.prof), req)
	end
	lines[#lines + 1] = HG.BonusLine(entry.prof)
	local cap = HG.CapLine(entry.prof)
	if cap then
		lines[#lines + 1] = cap
	end
	local cult = HG.CultivationLine(entry)
	if cult then
		lines[#lines + 1] = cult
	end
	if entry.prof ~= "lock" then
		for _, line in ipairs(HG.LootLines(entry.key)) do
			lines[#lines + 1] = line
		end
	end
	return lines
end

------------------------------------------------------------------------
-- /hm next — на чём сейчас растёт навык и что будет дальше
------------------------------------------------------------------------

-- Разновидности одного и того же ресурса в список не идут.
local VARIANTS = { "^Ooze Covered ", "^Wilted ", "^Stunted ", "^%a+ Copper Vein$" }

local function IsVariant(name)
	for _, pattern in ipairs(VARIANTS) do
		if name:find(pattern) then
			return true
		end
	end
	return false
end

-- Строки отчёта: на чём сейчас растёт навык и что будет дальше.
function HG.NextReport()
	local L = HG.L
	local lines = {}
	for _, prof in ipairs({ "herb", "mine" }) do
		local skill = HG.Skill(prof)
		if skill then
			local list = {}
			for name, entry in pairs(HG.RESOURCES) do
				if entry.prof == prof and not IsVariant(name) then
					list[#list + 1] = { name = name, req = HG.Requirement(entry) }
				end
			end
			table.sort(list, function(a, b)
				if a.req ~= b.req then
					return a.req < b.req
				end
				return a.name < b.name
			end)
			local current, upcoming, upcomingReq = {}, {}, nil
			for _, item in ipairs(list) do
				local difficulty = HG.Difficulty(skill, item.req)
				local shown = HG.DisplayName(item.name)
				if difficulty == "orange" or difficulty == "yellow" then
					current[#current + 1] = HG.Paint(shown, difficulty)
				elseif difficulty == "red" and (not upcomingReq or item.req == upcomingReq) then
					upcomingReq = item.req
					upcoming[#upcoming + 1] = shown
				end
			end
			local label = HG.ProfName(prof)
			if #current > 0 then
				lines[#lines + 1] = L.NEXT_NOW:format(label, skill, table.concat(current, ", "))
			else
				lines[#lines + 1] = L.NEXT_NONE:format(label, skill)
			end
			if #upcoming > 0 then
				lines[#lines + 1] = "  " .. L.NEXT_SOON:format(table.concat(upcoming, ", "), upcomingReq)
			end
		end
	end
	if #lines == 0 then
		lines[1] = HG.Paint(L.NEXT_NO_PROF, "grey")
	end
	return lines
end

HG.commands.next = function()
	for i, line in ipairs(HG.NextReport()) do
		if i == 1 then
			HG.Say(line)
		else
			print(line)
		end
	end
end
