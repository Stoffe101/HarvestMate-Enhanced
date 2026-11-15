local _, HG = ...

-- Навыки профессий сбора. Кэш обновляется по событиям и лениво перед
-- первым показом подсказки.

local cache = {}   -- prof -> { cur, base, max, name }
local byLine = {}  -- id линии навыка -> { cur, name } для любой основной профессии
local fresh = false
local readAt = 0

local LINE_TO_PROF = {}
for prof, info in pairs(HG.PROF) do
	if info.line then
		LINE_TO_PROF[info.line] = prof
	end
end

local function Absorb(index)
	if not HG.Num(index) then
		return
	end
	local name, _, level, maxLevel, _, _, line, bonus = GetProfessionInfo(index)
	line, level, maxLevel = HG.Num(line), HG.Num(level), HG.Num(maxLevel)
	if not line or not level or not maxLevel then
		return
	end
	byLine[line] = { cur = level + (HG.Num(bonus) or 0), name = HG.Str(name) }
	local prof = LINE_TO_PROF[line]
	if not prof then
		return
	end
	cache[prof] = {
		cur = level + (HG.Num(bonus) or 0),
		base = level,
		max = maxLevel,
		name = HG.Str(name),
	}
end

-- Навык основной профессии по id линии (186 — горное дело, 165 — кожевничество).
function HG.LineSkill(line)
	if not fresh then
		HG.ReadSkills()
	end
	return byLine[line] and byLine[line].cur
end

function HG.LineName(line)
	return byLine[line] and byLine[line].name
end

function HG.ReadSkills()
	for key in pairs(cache) do
		cache[key] = nil
	end
	for key in pairs(byLine) do
		byLine[key] = nil
	end
	fresh = true
	readAt = GetTime and GetTime() or 0
	local first, second = GetProfessions()
	Absorb(first)
	Absorb(second)
end

------------------------------------------------------------------------
-- Взлом замков (разбойники)
------------------------------------------------------------------------

function HG.KnowsLockpicking()
	if not IsPlayerSpell then
		return false
	end
	local known = IsPlayerSpell(HG.PROF.lock.gather[1])
	return not HG.Hidden(known) and known == true
end

-- Навык взлома. Если клиент не отдаёт строку навыка, берём предел
-- (уровень × 5) и помечаем как оценку: { cur, base, max, estimate }.
local function LockInfo()
	if not HG.KnowsLockpicking() then
		return nil
	end
	local level = HG.Num(UnitLevel("player")) or 1
	local cap = math.min(HG.SKILL_CAP, level * 5)
	if GetNumSkillLines and GetSkillLineInfo then
		local wanted = HG.L.LOCKPICKING
		for i = 1, HG.Num(GetNumSkillLines()) or 0 do
			local name, header, _, rank, _, _, maxRank = GetSkillLineInfo(i)
			name = HG.Str(name)
			if not header and (name == wanted or name == "Lockpicking") and HG.Num(rank) then
				return { cur = rank, base = rank, max = HG.Num(maxRank) or cap }
			end
		end
	end
	return { cur = cap, base = cap, max = cap, estimate = true }
end

-- { cur, base, max, name[, estimate] } или nil, если профессии нет.
function HG.SkillInfo(prof)
	if prof == "lock" then
		return LockInfo()
	end
	if not fresh then
		HG.ReadSkills()
	elseif not cache[prof] and GetTime and GetTime() - readAt > 3 then
		-- При входе в игру список профессий бывает ещё пуст, а события
		-- об изменении навыков может не прийти: перечитываем сами.
		HG.ReadSkills()
	end
	return cache[prof]
end

function HG.Skill(prof)
	local info = HG.SkillInfo(prof)
	return info and info.cur
end

-- Имя профессии: от клиента, иначе из локали.
function HG.ProfName(prof)
	local info = cache[prof]
	if info and info.name then
		return info.name
	end
	return HG.L[HG.PROF[prof].label]
end

local function Refresh()
	HG.ReadSkills()
	HG.Signal("SKILLS")
end

HG.On("PLAYER_ENTERING_WORLD", Refresh)
HG.On("SKILL_LINES_CHANGED", Refresh)
HG.On("CHAT_MSG_SKILL", Refresh)
