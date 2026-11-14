local _, ns = ... local HG = ns.HG -- HME patch P1

-- Подсказки: объекты в мире, значки на миникарте и существа (снятие шкур).

local HOVER_TTL = 12 -- сколько секунд помним объект под курсором

------------------------------------------------------------------------
-- Что было под курсором: нужно, чтобы связать следующий сбор с ресурсом.
------------------------------------------------------------------------

local hover = { at = 0 }

local function Remember(name, entry)
	hover.name, hover.entry, hover.at = name, entry, GetTime()
end

local function Forget()
	hover.name, hover.entry, hover.at = nil, nil, 0
end

-- name, entry (entry = nil для неизвестного объекта) или ничего.
-- maxAge — необязательный более строгий срок в секундах.
function HG.RecentHover(maxAge)
	if hover.name and GetTime() - hover.at <= (maxAge or HOVER_TTL) then
		return hover.name, hover.entry
	end
	return nil
end

HG.ForgetHover = Forget
HG.RememberHover = Remember

------------------------------------------------------------------------
-- Доступ к строкам подсказки
------------------------------------------------------------------------

local function LeftLine(tooltip, index)
	local own = tooltip["TextLeft" .. index]
	if own then
		return own
	end
	local frameName = HG.Str(tooltip:GetName())
	return frameName and _G[frameName .. "TextLeft" .. index]
end

local function RightLine(tooltip, index)
	local own = tooltip["TextRight" .. index]
	if own then
		return own
	end
	local frameName = HG.Str(tooltip:GetName())
	return frameName and _G[frameName .. "TextRight" .. index]
end

local function LineCount(tooltip)
	return HG.Num(tooltip:NumLines()) or 0
end

------------------------------------------------------------------------
-- Травы и руда
------------------------------------------------------------------------

local reported = {}

local function ReportUnknown(name)
	if HG.db.opt.debug and not reported[name] and #name < 70 then
		reported[name] = true
		HG.Debug(HG.L.UNKNOWN:format(name))
	end
end

-- Обрабатывает одну строку (на миникарте строк может быть несколько).
-- Возвращает новую строку или nil, и ресурс (если узнали).
local function RewriteSegment(segment)
	local icon = segment:match("^(|T.-|t%s*)") or segment:match("^(|A.-|a%s*)") or ""
	local name = HG.CleanName(segment)
	if not name then
		return nil, nil, nil
	end
	local entry = HG.Find(name)
	if not entry then
		ReportUnknown(name)
		return nil, nil, name
	end
	local described = HG.Describe(name, entry)
	if not described then
		return nil, entry, name
	end
	return icon .. described, entry, name
end

-- id объекта из GUID вида GameObject-0-xxxx-xxxx-xxxx-<id>-xxxx.
function HG.ObjectId(guid)
	guid = HG.Str(guid)
	if not guid then
		return nil
	end
	local id = guid:match("^GameObject%-%d+%-%d+%-%d+%-%d+%-(%d+)%-%x+$")
	return id and tonumber(id)
end

local function AddLines(tooltip, lines)
	for _, line in ipairs(lines) do
		tooltip:AddLine(line, 1, 1, 1)
	end
end

-- Текст первой строки: из самой строки подсказки, а если её прочитать
-- нельзя, из данных подсказки. Вторым значением — строка, которую можно
-- переписать (nil, если текст взят из данных).
local function FirstLine(tooltip, data)
	local first = LeftLine(tooltip, 1)
	local raw = first and HG.Str(first:GetText())
	if raw then
		return raw, first
	end
	local info = HG.Tbl(data)
	local lines = info and HG.Tbl(info.lines)
	local line = lines and HG.Tbl(lines[1])
	return line and HG.Str(line.leftText), nil
end

-- Последняя подсказка ресурса: для /hm tip.
local lastTip
-- Текст, который мы сами поставили в подсказку: если тот же текст пришёл
-- ещё раз, строки повторно не добавляем.
local processed = setmetatable({}, { __mode = "k" })

local busy = false -- наши собственные AddLine/SetText не должны вызывать обработку снова

local function HandleResource(tooltip, data, where)
	if not HG.Active() then
		return
	end
	local raw, first = FirstLine(tooltip, data)
	if not raw then
		if where == "minimap" then
			-- Подсказка пришла, но игра не даёт аддонам прочитать её текст.
			lastTip = { where = where, hidden = true }
		end
		return
	end
	if processed[tooltip] == raw then
		return
	end
	-- Несколько значков на миникарте игра может разделять и через |n.
	raw = raw:gsub("|n", "\n")
	lastTip = { where = where or "world", raw = raw }

	local out, changed = {}, false
	local named, lastName, lastEntry = 0, nil, nil
	for segment in (raw .. "\n"):gmatch("(.-)\n") do
		local rewritten, entry, name = RewriteSegment(segment)
		if name then
			named = named + 1
			lastName, lastEntry = name, entry
		end
		if rewritten then
			out[#out + 1] = rewritten
			changed = true
		else
			out[#out + 1] = segment
		end
	end

	-- Запоминаем только однозначный случай: под курсором один объект.
	if named == 1 then
		Remember(lastName, lastEntry)
		-- id объекта -> имя: нужно подсветке ресурса рядом.
		local info = HG.Tbl(data)
		local objectId = info and HG.ObjectId(info.guid)
		if objectId then
			HG.db.learned.objects[objectId] = lastName
		end
	else
		Forget()
	end

	if changed and first then
		first:SetText(table.concat(out, "\n"))
		processed[tooltip] = HG.Str(first:GetText())
		if not HG.db.opt.colorize then
			first:SetTextColor(1, 1, 1)
		end
	elseif changed then
		-- Переписать строку нельзя: добавляем навык отдельной строкой.
		for i, line in ipairs(out) do
			if line ~= "" then
				tooltip:AddLine(line, 1, 1, 1)
			end
		end
	end
	if named == 1 and lastEntry then
		AddLines(tooltip, HG.ExtraLines(lastEntry))
	end
	if not changed then
		processed[tooltip] = raw
	end
end

local function OnResourceTooltip(tooltip, data, where)
	if busy then
		return
	end
	busy = true
	local ok, err = pcall(HandleResource, tooltip, data, where)
	busy = false
	if not ok then
		error(err, 0)
	end
end

------------------------------------------------------------------------
-- Снятие шкур
------------------------------------------------------------------------

local SKIN_TYPE_ID = { [1] = true, [2] = true } -- животные и драконы

-- Семейства животных, с которых шкуру не снять, хотя тип у них «Животное».
-- Пауки и крабы: в Classic с них падает только обычная добыча.
local NO_SKIN_FAMILY_ID = { [3] = true, [8] = true }
local NO_SKIN_FAMILY_NAME = {
	-- пауки
	["Spider"] = true, ["Паук"] = true, ["Spinne"] = true, ["Araignée"] = true,
	["Araña"] = true, ["Ragno"] = true, ["Aranha"] = true, ["거미"] = true,
	["蜘蛛"] = true,
	-- крабы
	["Crab"] = true, ["Краб"] = true, ["Krebs"] = true, ["Krabbe"] = true,
	["Crabe"] = true, ["Cangrejo"] = true, ["Granchio"] = true,
	["Caranguejo"] = true, ["게"] = true, ["螃蟹"] = true,
}
-- Сколько разных существ одного семейства без шкуры нужно увидеть,
-- чтобы аддон перестал предлагать снять шкуру со всего семейства.
local FAMILY_PROOF = 2

local lastSkinLevel

local lastSkinName

function HG.LastSkinLevel()
	return lastSkinLevel
end

function HG.LastSkinName()
	return lastSkinName
end

local function TooltipUnit(tooltip, data)
	local _, unit = tooltip:GetUnit()
	unit = HG.Str(unit)
	if unit then
		return unit
	end
	data = HG.Tbl(data)
	local guid = data and HG.Str(data.guid)
	if guid and UnitTokenFromGUID then
		return HG.Str(UnitTokenFromGUID(guid))
	end
	return nil
end

-- id существа из GUID вида Creature-0-xxxx-xxxx-xxxx-<id>-xxxx.
function HG.NpcId(guid)
	guid = HG.Str(guid)
	if not guid then
		return nil
	end
	local kind, id = guid:match("^(%a+)%-%d+%-%d+%-%d+%-%d+%-(%d+)%-%x+$")
	if kind == "Creature" then
		return tonumber(id)
	end
	return nil
end

local function SkinnableKind(unit)
	local kindName, kindId = UnitCreatureType(unit)
	kindId = HG.Num(kindId)
	if kindId then
		return SKIN_TYPE_ID[kindId] == true
	end
	kindName = HG.Str(kindName)
	if not kindName then
		return false
	end
	local L = HG.L
	return kindName == L.BEAST or kindName == L.DRAGONKIN
		or kindName == "Beast" or kindName == "Dragonkin"
end

-- Ключ семейства: номер, если игра его даёт, иначе название.
local function FamilyKey(unit)
	if not UnitCreatureFamily then
		return nil
	end
	local ok, name, id = pcall(UnitCreatureFamily, unit)
	if not ok then
		return nil
	end
	id = HG.Num(id)
	if id then
		return id
	end
	return HG.Str(name)
end

local function FamilyRecord(key, create)
	local families = HG.db.learned.skinFamily
	local record = families[key]
	if type(record) ~= "table" and create then
		record = { yes = false, no = {} }
		families[key] = record
	end
	return type(record) == "table" and record or nil
end

-- false, если семейство заведомо без шкуры (встроенный список или опыт).
local function FamilySkinnable(unit)
	local key = FamilyKey(unit)
	if key == nil then
		return true
	end
	local record = FamilyRecord(key)
	if record and record.yes then
		return true
	end
	if NO_SKIN_FAMILY_ID[key] or NO_SKIN_FAMILY_NAME[key] then
		return false
	end
	if record then
		local count = 0
		for _ in pairs(record.no) do
			count = count + 1
		end
		if count >= FAMILY_PROOF then
			return false
		end
	end
	return true
end

local function NoteFamily(unit, npc, skinnable)
	local key = FamilyKey(unit)
	if key == nil then
		return
	end
	local record = FamilyRecord(key, true)
	if skinnable then
		record.yes = true
	else
		record.no[npc] = true
	end
end

local function Flag(value)
	if HG.Hidden(value) then
		return nil
	end
	return value and true or false
end

-- Есть ли в подсказке строка "Можно снять шкуру".
local function HasSkinnableLine(tooltip)
	local marker = HG.Str(_G.UNIT_SKINNABLE_LEATHER) or HG.L.SKINNABLE
	for i = 2, LineCount(tooltip) do
		for _, fs in ipairs({ LeftLine(tooltip, i), RightLine(tooltip, i) }) do
			local text = HG.Str(fs:GetText())
			if text and text:find(marker, 1, true) then
				return true
			end
		end
	end
	return false
end

-- Труп уже обыскан (добычи не осталось) и он наш.
local function LootedCorpse(unit)
	if not CanLootUnit then
		return false
	end
	local guid = HG.Str(UnitGUID(unit))
	if not guid then
		return false
	end
	local ok, hasLoot = pcall(CanLootUnit, guid)
	if not ok or HG.Hidden(hasLoot) then
		return false
	end
	local denied = Flag(UnitIsTapDenied(unit))
	return hasLoot == false and denied == false
end

local function LearnFromCorpse(tooltip, unit, npc)
	local known = HG.db.learned.skinnable
	local name = HG.Str(UnitName(unit)) or tostring(npc)
	if HasSkinnableLine(tooltip) then
		NoteFamily(unit, npc, true)
		if known[npc] ~= true then
			known[npc] = true
			HG.Learned(HG.L.LEARN_SKIN_YES:format(name))
		end
	elseif known[npc] ~= true and SkinnableKind(unit) and LootedCorpse(unit) then
		-- Труп обыскан, а строки «Можно снять шкуру» нет: шкуры нет.
		NoteFamily(unit, npc, false)
		if known[npc] == nil then
			known[npc] = false
			HG.Learned(HG.L.LEARN_SKIN_NO:format(name))
		end
	end
end

local function CanBeSkinned(unit, dead, npc)
	if Flag(UnitIsPlayer(unit)) ~= false or Flag(UnitPlayerControlled(unit)) ~= false then
		return false
	end
	local known = npc and HG.db.learned.skinnable[npc]
	if known == false then
		return false
	end
	if known ~= true and not (SkinnableKind(unit) and FamilySkinnable(unit)) then
		return false
	end
	if not dead and Flag(UnitCanAttack("player", unit)) ~= true then
		return false
	end
	return true
end

-- Труп, с которого можно снять шкуру: уровень и имя, иначе nil.
function HG.SkinnableCorpse(unit)
	if not Flag(UnitIsDead(unit)) then
		return nil
	end
	local npc = HG.NpcId(UnitGUID(unit))
	if not CanBeSkinned(unit, true, npc) then
		return nil
	end
	local level = HG.Num(UnitLevel(unit))
	if not level or level < 1 then
		return nil
	end
	return math.floor(level), HG.Str(UnitName(unit))
end

local function OnUnitTooltip(tooltip, data)
	if not HG.Active() then
		return
	end
	local unit = TooltipUnit(tooltip, data)
	if not unit then
		return
	end
	local dead = Flag(UnitIsDead(unit))
	if dead == nil then
		return
	end
	local npc = HG.NpcId(UnitGUID(unit))
	if dead and npc then
		LearnFromCorpse(tooltip, unit, npc)
	end

	if not HG.db.opt.skin then
		return
	end
	local skill = HG.Skill("skin")
	local level = HG.Num(UnitLevel(unit))
	if not skill or not level or level < 1 then
		return
	end
	if not CanBeSkinned(unit, dead, npc) then
		return
	end

	level = math.floor(level)
	lastSkinLevel = level
	lastSkinName = HG.Str(UnitName(unit))
	local entry = { prof = "skin", req = HG.SkinRequirement(level), key = "skin:" .. level }
	local req = HG.Requirement(entry)
	local numbers = HG.Numbers(skill, req)
	if not numbers and not HG.db.opt.colorize then
		return
	end
	local label = HG.ProfName("skin")
	local line = numbers and HG.L.SKIN_LINE:format(label, numbers) or label
	if HG.db.opt.colorize then
		line = HG.Paint(line, HG.Difficulty(skill, req))
		tooltip:AddLine(line)
	else
		tooltip:AddLine(line, 1, 1, 1)
	end
	if HG.db.opt.showBands then
		tooltip:AddLine(HG.BandsLine(req), 1, 1, 1)
	end
	local cap = HG.CapLine("skin")
	if cap then
		tooltip:AddLine(cap, 1, 1, 1)
	end
	AddLines(tooltip, HG.LootLines(entry.key))
end

------------------------------------------------------------------------
-- Предметы: трава и руда в сумках, на аукционе и т.д., сундучки
------------------------------------------------------------------------

local function SkillLine(template, prof, req, label)
	local text = template:format(label, req)
	local info = HG.SkillInfo(prof)
	if not info then
		return HG.Paint(text, "grey")
	end
	local mark = info.estimate and ("~" .. info.cur) or tostring(info.cur)
	return HG.Paint(text .. " " .. HG.L.ITEM_YOURS:format(mark), HG.ColorFor(prof, info.cur, req))
end

local function ItemSkillLines(tooltip, data)
	if not HG.db.opt.itemTips then
		return
	end
	data = HG.Tbl(data)
	local id = data and HG.Num(data.id)
	local info = id and HG.ITEM_INFO[id]
	if not info then
		return
	end
	local L = HG.L
	if info.gather then
		local prof = info.gather.prof
		tooltip:AddLine(SkillLine(L.ITEM_GATHER, prof, info.gather.req, HG.ProfName(prof)))
	end
	if info.smelt then
		tooltip:AddLine(SkillLine(L.ITEM_SMELT, "mine", info.smelt, L.SMELTING))
	end
	if info.lock then
		tooltip:AddLine(SkillLine(L.ITEM_GATHER, "lock", info.lock, L.LOCKPICKING))
	end
end

local function OnItemTooltip(tooltip, data)
	if not HG.Active() then
		return
	end
	ItemSkillLines(tooltip, data)
	if HG.db.opt.profit then
		local info = HG.Tbl(data)
		local id = info and HG.Num(info.id)
		if id then
			HG.ProfitLines(tooltip, id)
		end
	end
end

------------------------------------------------------------------------
-- Регистрация
------------------------------------------------------------------------

local kinds = Enum and Enum.TooltipDataType
if TooltipDataProcessor and kinds then
	if kinds.Object then
		TooltipDataProcessor.AddTooltipPostCall(kinds.Object, function(tooltip, data)
			OnResourceTooltip(tooltip, data, "world")
		end)
	end
	if kinds.MinimapMouseover then
		TooltipDataProcessor.AddTooltipPostCall(kinds.MinimapMouseover, function(tooltip, data)
			OnResourceTooltip(tooltip, data, "minimap")
		end)
	end
	if kinds.Unit then
		TooltipDataProcessor.AddTooltipPostCall(kinds.Unit, OnUnitTooltip)
	end
	if kinds.Corpse then
		TooltipDataProcessor.AddTooltipPostCall(kinds.Corpse, OnUnitTooltip)
	end
	if kinds.Item then
		TooltipDataProcessor.AddTooltipPostCall(kinds.Item, OnItemTooltip)
	end
end

------------------------------------------------------------------------
-- /hm tip: что аддон увидел в последней подсказке ресурса и почему
-- показал (или не показал) навык.
------------------------------------------------------------------------

local function Visible(text)
	return (text:gsub("|", "||"))
end

function HG.TipReport()
	local L = HG.L
	if not lastTip then
		HG.Say(L.TIP_NONE)
		return
	end
	if lastTip.hidden then
		HG.Say(L.TIP_HIDDEN)
		return
	end
	local where = lastTip.where == "minimap" and L.TIP_MINIMAP or L.TIP_WORLD
	HG.Say(L.TIP_RAW:format(where, Visible(lastTip.raw)))
	for segment in (lastTip.raw .. "\n"):gmatch("(.-)\n") do
		local name = HG.CleanName(segment)
		if name then
			local entry = HG.Find(name)
			local status
			if not entry then
				status = L.TIP_UNKNOWN
			elseif not HG.db.opt[entry.prof] then
				status = L.TIP_OFF:format(HG.ProfName(entry.prof))
			else
				local info = HG.SkillInfo(entry.prof)
				local req = HG.Requirement(entry)
				if not info then
					status = L.TIP_NO_PROF:format(HG.ProfName(entry.prof))
				else
					status = L.TIP_OK:format(HG.ProfName(entry.prof), info.cur, req or 0)
				end
			end
			print("  " .. name .. " — " .. status)
		end
	end
end

HG.commands.tip = HG.TipReport

------------------------------------------------------------------------
-- С билда 70938 (12 ноября 2026) игра скрывает от аддонов текст подсказки
-- миникарты. Окно подсказки не перехватываем: это ничего не даёт, а лишние
-- хуки на GameTooltip могут мешать самой игре. Подсказки миникарты по-прежнему
-- приходят через TooltipDataProcessor; если Blizzard снова откроет текст,
-- навык на миникарте вернётся сам.
------------------------------------------------------------------------

-- Тестам нужны внутренние обработчики.
HG._OnResourceTooltip = OnResourceTooltip
HG._OnUnitTooltip = OnUnitTooltip
HG._OnItemTooltip = OnItemTooltip
