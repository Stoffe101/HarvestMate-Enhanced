local _, ns = ... local HG = ns.HG -- HME patch P1

-- Обучение по факту сбора, учёт добычи и напоминания о рангах.
--
-- Успешный сбор с навыком X значит, что ресурс требует не больше X.
-- Так аддон уточняет требования и узнаёт ресурсы, которых нет в таблице
-- (например, новые травы и жилы WoW Forever). Добыча, выпавшая после
-- сбора, записывается к ресурсу — отсюда шансы в подсказке.

local START_WINDOW = 5      -- объект под курсором не раньше чем за 5 с до начала сбора
local LOOT_WINDOW = 12      -- добыча ждётся до 12 с после начала сбора
local CAPPED_COOLDOWN = 90  -- "навык не растёт" не чаще раза в 90 с
local READY_REPEAT = 1200   -- "доступен ранг" повторяется не чаще раза в 20 мин

-- Имена базовых заклинаний сбора: запасной способ узнать профессию,
-- если у ранга заклинания другой id.
local function ProfessionBySpell(spellID)
	spellID = HG.Num(spellID)
	if not spellID then
		return nil
	end
	local prof = HG.GATHER_SPELL[spellID]
	if prof then
		return prof
	end
	if not (C_Spell and C_Spell.GetSpellName) then
		return nil
	end
	local name = HG.Str(C_Spell.GetSpellName(spellID))
	if not name then
		return nil
	end
	for key, info in pairs(HG.PROF) do
		if HG.Str(C_Spell.GetSpellName(info.gather[1])) == name then
			return key
		end
	end
	return nil
end

------------------------------------------------------------------------
-- Добыча
------------------------------------------------------------------------

local pendingLoot -- { key, at }

local function LootKey(info)
	if info.prof == "skin" then
		return info.level and ("skin:" .. info.level) or nil
	end
	if info.prof == "lock" then
		return nil
	end
	if info.entry then
		return info.entry.key
	end
	return info.name
end

local function ItemIdFromLink(link)
	link = HG.Str(link)
	local id = link and link:match("item:(%d+)")
	return id and tonumber(id)
end

-- Записывает один сбор: какие предметы выпали (каждый считается один раз).
function HG.NoteLoot(key, itemIds, counts)
	if not key or #itemIds == 0 then
		return
	end
	local drops = HG.db.learned.drops
	local record = drops[key]
	if type(record) ~= "table" or type(record.items) ~= "table" then
		record = { n = 0, items = {} }
		drops[key] = record
	end
	record.n = (HG.Num(record.n) or 0) + 1
	local counted = {}
	for _, id in ipairs(itemIds) do
		if not counted[id] then
			counted[id] = true
			record.items[id] = (record.items[id] or 0) + 1
			-- Сколько штук выпало всего: отсюда среднее количество за раз.
			if type(record.qty) ~= "table" then
				record.qty = {}
			end
			record.qty[id] = (record.qty[id] or 0) + (counts and counts[id] or 1)
		end
	end
end

-- id объекта в мире, из которого идёт добыча (трава, жила, сундук).
local function LootObjectId()
	if not GetLootSourceInfo then
		return nil
	end
	local ok, guid = pcall(GetLootSourceInfo, 1)
	return ok and HG.ObjectId(guid) or nil
end

local function CollectLoot()
	local count = HG.Num(GetNumLootItems()) or 0
	if count == 0 then
		return
	end
	local ids, counts = {}, {}
	for slot = 1, count do
		local id = ItemIdFromLink(GetLootSlotLink(slot))
		if id then
			ids[#ids + 1] = id
			local quantity = GetLootSlotInfo and HG.Num((select(3, GetLootSlotInfo(slot))))
			counts[id] = (counts[id] or 0) + (quantity and quantity > 0 and quantity or 1)
		end
	end
	local pending = pendingLoot
	if pending and GetTime() - pending.at > LOOT_WINDOW then
		pending, pendingLoot = nil, nil
	end

	-- Связь «id объекта -> ресурс»: по ней подсветка рядом узнаёт такие же
	-- узлы, даже если игра не отдаёт имя объекта.
	-- Однозначный предмет надёжнее ожидания: если он указывает на другой
	-- ресурс, ожидание устарело (сбор не дал добычи) и не используется.
	local byItem
	for _, id in ipairs(ids) do
		byItem = byItem or HG.ITEM_TO_RESOURCE[id]
	end
	if pending and byItem then
		local expected = pending.key and HG.Find(pending.key)
		local itemEntry = HG.Find(byItem)
		if (expected and expected.key ~= byItem) or (itemEntry and itemEntry.prof ~= pending.prof) then
			pending, pendingLoot = nil, nil
		end
	end

	-- Сбор «на пробу» считается, только если добыча пришла с объекта в мире
	-- и в ней есть предмет именно этого ресурса.
	if pending and pending.trial and not (byItem and LootObjectId()) then
		pending, pendingLoot = nil, nil
	end

	-- Только после настоящего сбора: сундук с травой внутри не должен
	-- стать «травой» для подсветки.
	local objectId = pending and LootObjectId()
	if objectId and HG.db then
		local key = byItem or pending.key
		local entry = key and HG.Find(key)
		if entry and entry.prof == pending.prof then
			HG.db.learned.objects[objectId] = key
			-- Добыча подтвердила: это заклинание и есть сбор.
			if pending.trial then
				HG.db.learned.spells[pending.trial] = pending.prof
			end
		end
	end

	if pending then
		pendingLoot = nil
		if pending.key then
			HG.NoteLoot(pending.key, ids, counts)
		end
		HG.Signal("GATHER_LOOT", pending.prof, pending.key, counts, pending)
	end
end

HG.On("LOOT_READY", CollectLoot)
HG.On("LOOT_OPENED", CollectLoot)
HG.On("LOOT_CLOSED", function()
	pendingLoot = nil
end)

------------------------------------------------------------------------
-- Наблюдение за сбором
------------------------------------------------------------------------

-- Мёртвое существо, с которого сейчас снимают шкуру: мягкая цель, цель
-- или под курсором. Возвращает уровень и имя (или nil).
local function SkinTarget()
	for _, unit in ipairs({ "softinteract", "target", "mouseover" }) do
		local dead = UnitIsDead(unit)
		if not HG.Hidden(dead) and dead then
			local guid = UnitGUID(unit)
			local isCreature = HG.Hidden(guid) or HG.NpcId(guid) ~= nil
			local level = HG.Num(UnitLevel(unit))
			if isCreature and level and level > 0 then
				return math.floor(level), HG.Str(UnitName(unit))
			end
		end
	end
	return nil
end

-- Начатый сбор: профессия, имя и ресурс, навык в момент начала.
local cast

-- Профессия по заклинанию: известные id и те, что аддон выучил сам.
local function SpellProfession(spellID)
	local prof = ProfessionBySpell(spellID)
	if prof then
		return prof
	end
	local id = HG.Num(spellID)
	local learned = HG.db and id and HG.db.learned.spells[id]
	return HG.PROF[learned] and learned or nil
end

HG.On("UNIT_SPELLCAST_START", function(_, _, spellID)
	cast = nil
	local prof = SpellProfession(spellID)
	-- Незнакомое заклинание у известной травы или жилы: возможно, в этой
	-- версии игры у сбора другой id. Считаем сбором «на пробу»; если следом
	-- придёт добыча именно с этого ресурса, заклинание запоминается.
	local trial
	if not prof and HG.db then
		local _, hovered = HG.RecentHover(START_WINDOW)
		if hovered and (hovered.prof == "herb" or hovered.prof == "mine") and HG.Skill(hovered.prof) then
			prof, trial = hovered.prof, HG.Num(spellID)
		end
	end
	if not prof then
		return
	end
	local name, entry, skinLevel
	if prof == "skin" then
		skinLevel, name = SkinTarget()
		skinLevel = skinLevel or HG.LastSkinLevel()
		name = name or HG.LastSkinName()
	else
		name, entry = HG.RecentHover(START_WINDOW)
	end
	-- Оценочный навык (взлом без данных клиента) для обучения не годится.
	local skillInfo = HG.SkillInfo(prof)
	cast = {
		prof = prof,
		name = name,
		entry = entry,
		skill = skillInfo and not skillInfo.estimate and skillInfo.cur or nil,
		level = skinLevel,
		spell = HG.Num(spellID),
		trial = trial,
	}
	-- Ожидание добычи заводим и без имени: по добыче узнаем сам узел.
	local key = LootKey(cast)
	if key or prof == "herb" or prof == "mine" then
		pendingLoot = {
			key = key, prof = prof, at = GetTime(), trial = trial,
			viaKey = HG.GatherKeyBound(),
			geared = skillInfo ~= nil and not skillInfo.estimate and skillInfo.cur > skillInfo.base,
		}
	else
		pendingLoot = nil
	end
	if prof ~= "lock" and not trial then
		HG.Signal("GATHER_START", prof, name)
	end
end, "player")

local function Lower(key, skill, label)
	local lowest = HG.db.learned.lowest
	if type(lowest[key]) == "number" and lowest[key] <= skill then
		return
	end
	lowest[key] = skill
	HG.Learned(HG.L.LEARN_LOWER:format(label, skill))
end

-- Применяет успешный сбор к изученным данным.
function HG.NoteGather(info)
	local skill = info.skill
	if type(skill) ~= "number" then
		return
	end
	if info.prof == "skin" then
		local level = info.level
		if type(level) == "number" and skill < HG.SkinRequirement(level) then
			Lower("skin:" .. level, skill, HG.L.SKINNING .. " " .. level)
		end
		return
	end
	local name, entry = info.name, info.entry
	if not name then
		return
	end
	if entry then
		if entry.prof == info.prof then
			local req = HG.Requirement(entry)
			if not req or skill < req then
				Lower(entry.key, skill, name)
			end
		end
		return
	end
	-- Неизвестный объект: запоминаем как новый ресурс этой профессии.
	HG.db.learned.custom[name] = { prof = info.prof, key = name }
	HG.db.learned.lowest[name] = skill
	HG.Learned(HG.L.LEARN_NEW:format(name, skill))
end

HG.On("UNIT_SPELLCAST_SUCCEEDED", function(_, _, spellID)
	local info = cast
	cast = nil
	if not info or info.spell ~= HG.Num(spellID) or not HG.Active() then
		return
	end
	if info.prof == "lock" then
		HG.Signal("LOCKPICKED")
	end
	-- Сбор «на пробу» ничему не учит, пока его не подтвердит добыча.
	if not info.trial then
		HG.NoteGather(info)
	end
	HG.ForgetHover()
	-- Добыча могла прийти раньше этого события — проверяем ещё раз.
	CollectLoot()
	-- Навык после сбора обновится не сразу: проверяем ранг чуть позже.
	HG.Soon("train:" .. info.prof, 1, function()
		HG.ReadSkills()
		HG.CheckTrainer(info.prof)
	end)
end, "player")

local function Cancel()
	cast = nil
	pendingLoot = nil
end
HG.On("UNIT_SPELLCAST_INTERRUPTED", Cancel, "player")
HG.On("UNIT_SPELLCAST_FAILED", Cancel, "player")

------------------------------------------------------------------------
-- Напоминания о рангах
--
-- 1) Навык дорос до порога следующего ранга (50 / 125 / 200) — можно
--    учиться. Если уровень персонажа мал — пишем, с какого уровня.
-- 2) Навык упёрся в предел ранга (75 / 150 / 225) — расти не будет.
-- На 300 ничего не показываем.
------------------------------------------------------------------------

local lastCapped = {}
local lastReady = {}

function HG.CheckTrainer(prof)
	local opt = HG.db.opt
	if prof == "lock" or not HG.Active() or not opt.trainWarn or not opt[prof] then
		return
	end
	local info = HG.SkillInfo(prof)
	if not info or info.max <= 0 or info.max >= HG.SKILL_CAP then
		return
	end
	local L = HG.L
	local now = GetTime()
	local profName = HG.ProfName(prof)

	if info.base >= info.max then
		if lastCapped[prof] and now - lastCapped[prof] < CAPPED_COOLDOWN then
			return
		end
		lastCapped[prof] = now
		local text = L.TRAIN_CAPPED:format(profName, info.base, info.max)
		HG.FlashBanner("train", text, 7, "capped")
		HG.Say("|cffff8c1a" .. text .. "|r")
		return
	end

	local rank = HG.RANKS[info.max]
	if not rank or info.base < rank.skill then
		return
	end
	local key = prof .. ":" .. info.max
	if lastReady[key] and now - lastReady[key] < READY_REPEAT then
		return
	end
	lastReady[key] = now
	local rankName = L[rank.name]
	local level = HG.Num(UnitLevel("player")) or 0
	local text
	if level < rank.level then
		text = L.TRAIN_LEVEL:format(rankName, profName, rank.level)
	else
		text = L.TRAIN_READY:format(rankName, profName)
	end
	HG.FlashBanner("train", text, 7, "ready")
	HG.Say("|cffffd100" .. text .. "|r")
end
