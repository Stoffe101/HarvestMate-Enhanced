local ADDON, HG = ...

-- Ядро: защищённые значения (secrets), шина событий, сохранённые данные,
-- вывод в чат и слэш-команды.

HG.addon = ADDON
HG.title = "HarvestMate"

------------------------------------------------------------------------
-- Защищённые значения
-- В Forever (как и в Midnight) часть значений в бою становится "секретной":
-- их нельзя сравнивать, использовать как ключ таблицы и т.п.
------------------------------------------------------------------------

local isSecret = _G.issecretvalue
local canAccess = _G.canaccessvalue
local isSecretTable = _G.issecrettable
local canAccessTable = _G.canaccesstable

-- true, если значение нельзя читать.
function HG.Hidden(v)
	if isSecret and isSecret(v) then
		return not (canAccess and canAccess(v))
	end
	return false
end

-- Непустая читаемая строка либо nil.
function HG.Str(v)
	if type(v) == "string" and not HG.Hidden(v) and v ~= "" then
		return v
	end
	return nil
end

-- Читаемое число либо nil.
function HG.Num(v)
	if type(v) == "number" and not HG.Hidden(v) then
		return v
	end
	return nil
end

-- Таблица, которую можно индексировать, либо nil.
function HG.Tbl(v)
	if type(v) ~= "table" or HG.Hidden(v) then
		return nil
	end
	if isSecretTable and isSecretTable(v) and not (canAccessTable and canAccessTable(v)) then
		return nil
	end
	return v
end

------------------------------------------------------------------------
-- Шина событий: на одно событие можно подписать несколько модулей.
------------------------------------------------------------------------

local bus = CreateFrame("Frame")
local subscribers = {}

function HG.On(event, handler, unit)
	local list = subscribers[event]
	if not list then
		list = {}
		subscribers[event] = list
		-- Неизвестное клиенту событие не должно ломать загрузку аддона.
		local ok
		if unit then
			ok = pcall(bus.RegisterUnitEvent, bus, event, unit)
		else
			ok = pcall(bus.RegisterEvent, bus, event)
		end
		if not ok then
			HG.missingEvents = HG.missingEvents or {}
			HG.missingEvents[#HG.missingEvents + 1] = event
		end
	end
	list[#list + 1] = handler
end

bus:SetScript("OnEvent", function(_, event, ...)
	local list = subscribers[event]
	if not list then
		return
	end
	for i = 1, #list do
		list[i](...)
	end
end)

-- Внутренние сигналы между модулями (не события игры).
local signals = {}

function HG.Listen(name, handler)
	signals[name] = signals[name] or {}
	table.insert(signals[name], handler)
end

function HG.Signal(name, ...)
	local list = signals[name]
	if not list then
		return
	end
	for i = 1, #list do
		list[i](...)
	end
end

-- Отложенный вызов с объединением повторов: несколько запросов подряд
-- дают один вызов.
local queued = {}
function HG.Soon(id, delay, fn)
	if queued[id] then
		return
	end
	queued[id] = true
	C_Timer.After(delay, function()
		queued[id] = nil
		fn()
	end)
end

------------------------------------------------------------------------
-- Сохранённые данные
------------------------------------------------------------------------

HG.DEFAULTS = {
	enabled = true,
	herb = true,
	mine = true,
	skin = true,
	showOwn = true,
	showReq = true,
	colorize = true,
	chatLearn = false,
	trackWarn = true,
	treasureWarn = true,
	trainWarn = true,
	lock = true,
	showBands = true,
	showLoot = true,
	showPrices = true,
	profit = true,
	cultivation = true,
	itemTips = true,
	nearby = true,
	nearbySound = true,
	marker = true,
	announceParty = true,
	announceEmote = true,
	gatherKey = true,
	gatherMove = true,
	gatherLoot = true,
	gearWarn = true,
	gearSwap = false,
	achToast = true,
	achSound = true,
	achGuild = false,
	gatherKeyBind = "F",
	minimap = true,
	fontSize = 18,
	debug = false,
}

local SCHEMA = 1

local function Section(root, key)
	if type(root[key]) ~= "table" then
		root[key] = {}
	end
	return root[key]
end

-- Приводит сохранённую таблицу к ожидаемому виду, ничего не теряя.
function HG.PrepareDB(saved)
	if type(saved) ~= "table" then
		saved = {}
	end
	local opt = Section(saved, "opt")
	for key, value in pairs(HG.DEFAULTS) do
		if type(opt[key]) ~= type(value) then
			opt[key] = value
		end
	end
	local learned = Section(saved, "learned")
	Section(learned, "lowest")    -- ключ ресурса -> минимальный навык успешного сбора
	Section(learned, "custom")    -- имя неизвестного ресурса -> { prof, key }
	Section(learned, "skinnable") -- id существа -> true / false
	Section(learned, "skinFamily") -- семейство -> { yes = шкура была, no = { [id существа] = true } }
	Section(learned, "drops")     -- ключ ресурса -> { n = сборов, items = { [id] = раз } }
	Section(learned, "objects")   -- id объекта в мире -> имя
	Section(learned, "spells")    -- id заклинания сбора, выученного по добыче -> профессия
	Section(saved, "banner")
	if type(saved.angle) ~= "number" then
		saved.angle = 215
	end
	saved.schema = SCHEMA
	return saved
end

function HG.ResetOptions()
	local opt = HG.db.opt
	for key, value in pairs(HG.DEFAULTS) do
		opt[key] = value
	end
	HG.db.banner = {}
	HG.db.angle = 215
	HG.Signal("OPTIONS")
end

function HG.ForgetLearned()
	HG.db.learned = nil
	HG.PrepareDB(HG.db)
	HG.Signal("LEARNED")
end

-- Аддон включён и готов.
function HG.Active()
	return HG.db ~= nil and HG.db.opt.enabled
end

------------------------------------------------------------------------
-- Чат
------------------------------------------------------------------------

local TAG = "|cff6fcf97HarvestMate|r: "

function HG.Say(text)
	print(TAG .. tostring(text))
end

function HG.Debug(...)
	if not (HG.db and HG.db.opt.debug) then
		return
	end
	local parts = {}
	for i = 1, select("#", ...) do
		parts[i] = tostring((select(i, ...)))
	end
	print(TAG .. "|cff999999" .. table.concat(parts, " ") .. "|r")
end

function HG.Learned(text)
	if HG.db and HG.db.opt.chatLearn then
		HG.Say(text)
	end
end

------------------------------------------------------------------------
-- Загрузка
------------------------------------------------------------------------

HG.On("ADDON_LOADED", function(name)
	if name ~= ADDON or HG.db then
		return
	end
	-- Перенос данных со времён, когда аддон назывался Harvest Gauge
	-- (если файл сохранения переименован в HarvestMate.lua).
	local migrated = false
	if type(_G.HarvestMateDB) ~= "table" and type(_G.HarvestGaugeDB) == "table" then
		_G.HarvestMateDB = _G.HarvestGaugeDB
		migrated = true
	end
	_G.HarvestGaugeDB = nil
	_G.HarvestMateDB = HG.PrepareDB(_G.HarvestMateDB)
	HG.db = _G.HarvestMateDB
	if migrated then
		HG.Say(HG.L.MIGRATED)
	end
	HG.Signal("READY")
end)

------------------------------------------------------------------------
-- Слэш-команды: /hm, /harvestmate и старая /hg
------------------------------------------------------------------------

local commands = {}
HG.commands = commands

function commands.debug()
	local opt = HG.db.opt
	opt.debug = not opt.debug
	HG.Say(HG.L.DEBUG_STATE:format(opt.debug and HG.L.ON or HG.L.OFF))
end

function commands.reset()
	HG.ResetOptions()
	HG.Say(HG.L.RESET_DONE)
end

function commands.forget()
	HG.ForgetLearned()
	HG.Say(HG.L.FORGET_DONE)
end

function commands.skills()
	HG.ReadSkills()
	for _, prof in ipairs({ "herb", "mine", "skin" }) do
		local s = HG.SkillInfo(prof)
		if s then
			HG.Say(("%s: %d (%d/%d)"):format(HG.ProfName(prof), s.cur, s.base, s.max))
		end
	end
end

------------------------------------------------------------------------
-- Настройки игры (CVar). В современном клиенте — C_CVar, старые
-- глобальные функции могут отсутствовать.
------------------------------------------------------------------------

function HG.GetCVar(name)
	local get = (C_CVar and C_CVar.GetCVar) or _G.GetCVar
	if not get then
		return nil
	end
	local ok, value = pcall(get, name)
	return ok and value or nil
end

function HG.SetCVar(name, value)
	local set = (C_CVar and C_CVar.SetCVar) or _G.SetCVar
	if not set then
		return false
	end
	local ok = pcall(set, name, value)
	return ok and HG.GetCVar(name) == tostring(value)
end

-- Мягкая цель: 0 — выкл., 1 — геймпад, 2 — клавиатура и мышь, 3 — всегда.
local SOFT = "SoftTargetInteract"

-- Включён ли интерфейс геймпада. В нём мягкой целью управляет сама игра
-- (значение 1 — «для геймпада»), и менять её аддону не нужно.
-- Сколько геймпадов подключено; nil, если игра этого не говорит.
function HG.GamepadDevices()
	if not (C_GamePad and C_GamePad.GetAllDeviceIDs) then
		return nil
	end
	local ok, ids = pcall(C_GamePad.GetAllDeviceIDs)
	if not ok or type(ids) ~= "table" or HG.Hidden(ids) then
		return nil
	end
	local count = 0
	for _ in pairs(ids) do
		count = count + 1
	end
	return count
end

-- Играют ли сейчас с геймпада. Включённого интерфейса геймпада мало:
-- если геймпад не подключён, игра управляется мышью, и значение мягкой
-- цели «только для геймпада» (1) для мыши не работает.
function HG.GamepadMode()
	local enabled = false
	if C_GamePad and C_GamePad.IsEnabled then
		local ok, value = pcall(C_GamePad.IsEnabled)
		enabled = ok and not HG.Hidden(value) and value == true
	end
	if not enabled then
		enabled = HG.GetCVar("GamePadEnable") == "1"
	end
	if not enabled then
		return false
	end
	local devices = HG.GamepadDevices()
	return devices == nil or devices > 0
end

function HG.SoftTargetOn()
	local value = HG.GetCVar(SOFT)
	if value == "2" or value == "3" then
		return true
	end
	return value == "1" and HG.GamepadMode()
end

-- Включает мягкую цель, запомнив прежнее значение. true — получилось.
-- Согласие игрока запоминается: настройки игры хранятся на каждом
-- компьютере отдельно, и на другом ПК мягкая цель может быть выключена.
function HG.EnableSoftTarget()
	if HG.SoftTargetOn() then
		HG.db.softWanted = true
		return true
	end
	local before = HG.GetCVar(SOFT)
	if HG.SetCVar(SOFT, "3") then
		if HG.db.softBefore == nil then
			HG.db.softBefore = before
		end
		HG.db.softWanted = true
		return true
	end
	return false
end

-- /hm soft — включить мягкую цель взаимодействия; /hm soft off — вернуть как было.
function commands.soft(arg)
	local L = HG.L
	if InCombatLockdown and InCombatLockdown() then
		HG.Say(L.SOFT_COMBAT)
		return
	end
	if arg == "off" then
		local previous = HG.db.softBefore or "0"
		HG.SetCVar(SOFT, previous)
		HG.db.softBefore = nil
		HG.db.softWanted = false
		HG.Say(L.SOFT_OFF)
		return
	end
	if HG.EnableSoftTarget() then
		HG.Say(L.SOFT_ON)
	else
		HG.Say(L.SOFT_FAILED)
	end
	HG.Signal("OPTIONS")
end

function commands.near()
	HG.NearbyReport()
end

function commands.config()
	HG.OpenSettings()
end

function commands.help()
	HG.Say(HG.L.HELP_HEAD)
	print("  /hm, /hm config, /hm session, /hm ach, /hm bags, /hm next, /hm key, /hm soft, /hm near")
	print("  /hm test, /hm tip, /hm skills, /hm debug, /hm reset, /hm forget")
end

_G.SLASH_HARVESTMATE1 = "/hm"
_G.SLASH_HARVESTMATE2 = "/harvestmate"
-- Старая команда со времён Harvest Gauge — по привычке.
_G.SLASH_HARVESTMATE3 = "/hg"
_G.SlashCmdList.HARVESTMATE = function(msg)
	if not HG.db then
		return
	end
	local word, arg = (msg or ""):match("^%s*(%S*)%s*(%S*)")
	word, arg = word:lower(), arg:lower()
	local fn = commands[word]
	if fn then
		fn(arg)
	elseif word == "" then
		HG.OpenHub()
	else
		commands.help()
	end
end
