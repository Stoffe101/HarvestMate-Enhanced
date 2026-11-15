local _, HG = ...

-- Предупреждения о выключенном поиске.
--
-- Поиск трав / минералов: в WoW Forever одновременно работает только один,
-- поэтому достаточно любого из двух.
-- Поиск сокровищ (дворфы): работает вместе с любым другим поиском, поэтому
-- проверяется отдельно. Как и остальной поиск, выключается после смерти.

local TREASURE = HG.TREASURE_SPELL

-- Читает одну запись трекинга. Поддерживает и таблицу, и старый формат
-- с несколькими возвращаемыми значениями.
local function ReadEntry(index)
	local a, _, c, _, _, f = C_Minimap.GetTrackingInfo(index)
	if type(a) == "table" then
		local info = HG.Tbl(a)
		if not info then
			return nil, nil, true
		end
		return HG.Num(info.spellID), info.active, false
	end
	return HG.Num(f), c, false
end

-- state[key] = { index, on } для "herb", "mine", "treasure";
-- второй результат — "что-то прочитать не удалось".
local function Scan()
	local state, unsure = {}, false
	if not (C_Minimap and C_Minimap.GetNumTrackingTypes) then
		return state, true
	end
	local count = HG.Num(C_Minimap.GetNumTrackingTypes())
	if not count then
		return state, true
	end
	for i = 1, count do
		local spellID, active, hidden = ReadEntry(i)
		if hidden then
			unsure = true
		elseif spellID then
			local key
			if spellID == TREASURE then
				key = "treasure"
			else
				for prof, info in pairs(HG.PROF) do
					if info.track == spellID then
						key = prof
					end
				end
			end
			if key then
				if HG.Hidden(active) then
					unsure = true
				else
					state[key] = { index = i, on = active and true or false }
				end
			end
		end
	end
	return state, unsure
end

local function SpellLabel(spellID, fallback)
	local name = C_Spell and C_Spell.GetSpellName and HG.Str(C_Spell.GetSpellName(spellID))
	return name or fallback
end

------------------------------------------------------------------------
-- Поиск сокровищ
------------------------------------------------------------------------

-- Выключен ли поиск сокровищ смертью и ещё не включён заново.
-- Нужен, если клиент не показывает его ни в списке трекинга, ни аурой.
local treasureLost = false

function HG.KnowsTreasure()
	if IsPlayerSpell then
		local known = IsPlayerSpell(TREASURE)
		if not HG.Hidden(known) and known then
			return true
		end
	end
	local _, race = UnitRace("player")
	return HG.Str(race) == "Dwarf" and IsPlayerSpell == nil
end

-- true / false, или nil — состояние неизвестно (тогда молчим).
local function TreasureOn(state)
	local entry = state.treasure
	if entry then
		return entry.on
	end
	if C_UnitAuras and C_UnitAuras.GetPlayerAuraBySpellID then
		local ok, aura = pcall(C_UnitAuras.GetPlayerAuraBySpellID, TREASURE)
		if ok and aura ~= nil and not HG.Hidden(aura) then
			return true
		end
	end
	if treasureLost then
		return false
	end
	return nil
end

------------------------------------------------------------------------
-- Кнопки и проверка
------------------------------------------------------------------------

-- Действие кнопки: через миникарту, если запись есть, иначе — защищённое
-- произнесение заклинания по щелчку (CastSpellByID аддонам недоступен).
local function Action(label, entry, spellID)
	local text = HG.L.TURN_ON:format(label)
	if entry and C_Minimap.SetTracking then
		return {
			text,
			function()
				C_Minimap.SetTracking(entry.index, true)
				HG.HideBanner("track")
				HG.Soon("track", 0.5, HG.CheckTracking)
			end,
		}
	end
	return { text, nil, spellID }
end

local inCombat = false

-- Собирает строки и кнопки для поиска трав/минералов.
local function GatherPart(state, unsure, lines, actions)
	local opt = HG.db.opt
	local candidates = {}
	for _, prof in ipairs({ "herb", "mine" }) do
		local entry = state[prof]
		if entry and entry.on then
			return
		end
		local known = entry ~= nil
		if not known and IsPlayerSpell then
			local learned = IsPlayerSpell(HG.PROF[prof].track)
			known = not HG.Hidden(learned) and learned == true
		end
		if known and opt[prof] and HG.Skill(prof) then
			candidates[#candidates + 1] = prof
		end
	end
	-- Не уверены в состоянии (секреты) или искать нечем — молчим.
	if unsure or #candidates == 0 then
		return
	end
	lines[#lines + 1] = HG.L.TRACK_OFF
	for _, prof in ipairs(candidates) do
		local info = HG.PROF[prof]
		actions[#actions + 1] = Action(SpellLabel(info.track, HG.L[info.find]), state[prof], info.track)
	end
end

local function TreasurePart(state, lines, actions)
	if not HG.db.opt.treasureWarn or not HG.KnowsTreasure() then
		return
	end
	if TreasureOn(state) ~= false then
		return
	end
	lines[#lines + 1] = HG.L.TREASURE_OFF
	actions[#actions + 1] = Action(SpellLabel(TREASURE, HG.L.FIND_TREASURE), state.treasure, TREASURE)
end

function HG.CheckTracking()
	local opt = HG.db and HG.db.opt
	if not opt or not opt.enabled or inCombat then
		HG.HideBanner("track")
		return
	end
	local dead = UnitIsDeadOrGhost("player")
	if HG.Hidden(dead) or dead then
		HG.HideBanner("track")
		return
	end

	local state, unsure = Scan()
	local lines, actions = {}, {}
	if opt.trackWarn then
		GatherPart(state, unsure, lines, actions)
	end
	TreasurePart(state, lines, actions)

	if #lines == 0 then
		HG.HideBanner("track")
		return
	end
	HG.ShowBanner("track", table.concat(lines, "\n"), actions)
end

local function Queue()
	HG.Soon("track", 0.3, HG.CheckTracking)
end

HG.On("PLAYER_ENTERING_WORLD", Queue)
HG.On("MINIMAP_UPDATE_TRACKING", Queue)
HG.On("PLAYER_ALIVE", Queue)
HG.On("PLAYER_UNGHOST", Queue)
HG.On("PLAYER_DEAD", function()
	treasureLost = true
	Queue()
end)
HG.On("UNIT_SPELLCAST_SUCCEEDED", function(_, _, spellID)
	if HG.Num(spellID) == TREASURE then
		treasureLost = false
		HG.HideBanner("track")
		Queue()
	end
end, "player")
HG.On("PLAYER_REGEN_DISABLED", function()
	inCombat = true
	HG.HideBanner("track")
end)
HG.On("PLAYER_REGEN_ENABLED", function()
	inCombat = false
	Queue()
end)
HG.Listen("SKILLS", Queue)
HG.Listen("OPTIONS", Queue)
