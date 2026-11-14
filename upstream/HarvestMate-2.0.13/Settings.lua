local _, HG = ...

-- Панель в «Настройки → Модификации». Разделы идут от главного к
-- второстепенному: сбор у ресурса, что показывать, напоминания, чат.
-- Зависимые настройки вложены в свою главную и гаснут вместе с ней.
-- Если API настроек недоступен, остаются слэш-команды.

local category

local function Changed()
	HG.Signal("OPTIONS")
end

local function Header(layout, text)
	if layout and CreateSettingsListSectionHeaderInitializer then
		layout:AddInitializer(CreateSettingsListSectionHeaderInitializer(text))
	end
end

-- Вкладывает настройку в главную: отступ и неактивность, пока главная выключена.
local function Nest(initializer, parent)
	if parent and parent.init and initializer and initializer.SetParentInitializer then
		initializer:SetParentInitializer(parent.init, function()
			return HG.db.opt[parent.key] == true
		end)
	end
end

local function Checkbox(key, label, tip, parent)
	local setting = Settings.RegisterAddOnSetting(category, "HARVESTMATE_" .. key, key,
		HG.db.opt, Settings.VarType.Boolean, label, HG.DEFAULTS[key])
	setting:SetValueChangedCallback(Changed)
	local initializer = Settings.CreateCheckbox(category, setting, tip)
	Nest(initializer, parent)
	return { init = initializer, key = key }
end

local function Slider(key, label, tip, low, high, step)
	if not (Settings.CreateSliderOptions and Settings.CreateSlider) then
		return
	end
	local setting = Settings.RegisterAddOnSetting(category, "HARVESTMATE_" .. key, key,
		HG.db.opt, Settings.VarType.Number, label, HG.DEFAULTS[key])
	setting:SetValueChangedCallback(Changed)
	local options = Settings.CreateSliderOptions(low, high, step)
	if MinimalSliderWithSteppersMixin and options.SetLabelFormatter then
		options:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right)
	end
	Settings.CreateSlider(category, setting, options, tip)
end

local function Button(layout, label, buttonText, tip, onClick, parent)
	if not (layout and CreateSettingsButtonInitializer) then
		return
	end
	local initializer = CreateSettingsButtonInitializer(label, buttonText, onClick, tip, true)
	layout:AddInitializer(initializer)
	Nest(initializer, parent)
end

-- Настройки для одной расы или класса не показываем остальным.
-- Если игра ещё не знает расу или класс — показываем.
local function IsRace(token)
	local _, race = UnitRace("player")
	race = HG.Str(race)
	return race == nil or race == token
end

local function IsClass(token)
	if not UnitClass then
		return true
	end
	local _, class = UnitClass("player")
	class = HG.Str(class)
	return class == nil or class == token
end

local RESET_POPUP = "HARVESTMATE_RESET"

local function AskReset()
	local L = HG.L
	local function Reset()
		HG.ResetOptions()
		HG.Say(L.RESET_DONE)
	end
	if not (StaticPopupDialogs and StaticPopup_Show) then
		Reset()
		return
	end
	StaticPopupDialogs[RESET_POPUP] = StaticPopupDialogs[RESET_POPUP] or {
		text = HG.title .. "|n|n" .. L.RESET_ASK,
		button1 = _G.YES or "Yes",
		button2 = _G.NO or "No",
		OnAccept = Reset,
		timeout = 0,
		whileDead = true,
		hideOnEscape = true,
		preferredIndex = 3,
	}
	StaticPopup_Show(RESET_POPUP)
end

local function Build()
	if not (Settings and Settings.RegisterVerticalLayoutCategory and Settings.RegisterAddOnSetting) then
		return
	end
	local L = HG.L
	local layout
	category, layout = Settings.RegisterVerticalLayoutCategory(HG.title)

	Checkbox("enabled", L.OPT_ENABLED, L.OPT_ENABLED_TIP)

	-- 1. Ресурс рядом: подсказка, значок, сбор одной клавишей
	Header(layout, L.SEC_NEARBY)
	local nearby = Checkbox("nearby", L.OPT_NEARBY, L.OPT_NEARBY_TIP)
	Checkbox("marker", L.OPT_MARKER, L.OPT_MARKER_TIP, nearby)
	Checkbox("nearbySound", L.OPT_SOUND, L.OPT_SOUND_TIP, nearby)
	local gatherKey = Checkbox("gatherKey", L.OPT_GKEY, L.OPT_GKEY_TIP, nearby)
	Button(layout, L.OPT_GKEY_BIND, L.KEY_BUTTON, L.OPT_GKEY_BIND_TIP, function()
		HG.CaptureGatherKey()
	end, gatherKey)
	Checkbox("gatherMove", L.OPT_GMOVE, L.OPT_GMOVE_TIP, gatherKey)
	Checkbox("gatherLoot", L.OPT_AUTOLOOT, L.OPT_AUTOLOOT_TIP, gatherKey)
	local gear = Checkbox("gearWarn", L.OPT_GEAR, L.OPT_GEAR_TIP, nearby)
	Checkbox("gearSwap", L.OPT_GEARSWAP, L.OPT_GEARSWAP_TIP, gear)
	Button(layout, L.OPT_SOFT, L.SOFT_YES, L.OPT_SOFT_TIP, function()
		HG.commands.soft("")
	end, nearby)

	-- 2. Для каких профессий работать
	Header(layout, L.SEC_PROFESSIONS)
	Checkbox("herb", HG.ProfName("herb"), L.OPT_HERB_TIP)
	Checkbox("mine", HG.ProfName("mine"), L.OPT_MINE_TIP)
	Checkbox("skin", HG.ProfName("skin"), L.OPT_SKIN_TIP)
	if IsClass("ROGUE") then
		Checkbox("lock", L.LOCKPICKING, L.OPT_LOCK_TIP)
	end

	-- 3. Что показывать в подсказке ресурса
	Header(layout, L.SEC_TOOLTIP)
	Checkbox("showOwn", L.OPT_OWN, L.OPT_OWN_TIP)
	Checkbox("showReq", L.OPT_REQ, L.OPT_REQ_TIP)
	Checkbox("colorize", L.OPT_COLOR, L.OPT_COLOR_TIP)
	Checkbox("showBands", L.OPT_BANDS, L.OPT_BANDS_TIP)
	local loot = Checkbox("showLoot", L.OPT_LOOT, L.OPT_LOOT_TIP)
	Checkbox("showPrices", L.OPT_PRICES, L.OPT_PRICES_TIP, loot)
	if IsRace("Tauren") then
		Checkbox("cultivation", L.OPT_CULT, L.OPT_CULT_TIP)
	end

	-- 4. Что показывать в подсказке предмета
	Header(layout, L.SEC_ITEMS)
	Checkbox("itemTips", L.OPT_ITEMS, L.OPT_ITEMS_TIP)
	Checkbox("profit", L.OPT_PROFIT, L.OPT_PROFIT_TIP)

	-- 5. Напоминания на экране
	Header(layout, L.SEC_REMINDERS)
	Checkbox("trackWarn", L.OPT_TRACK, L.OPT_TRACK_TIP)
	if IsRace("Dwarf") then
		Checkbox("treasureWarn", L.OPT_TREASURE, L.OPT_TREASURE_TIP)
	end
	Checkbox("trainWarn", L.OPT_TRAIN, L.OPT_TRAIN_TIP)
	Slider("fontSize", L.OPT_FONT, L.OPT_FONT_TIP, 10, 32, 1)

	-- 6. Что аддон пишет в чат
	Header(layout, L.SEC_ANNOUNCE)
	Checkbox("announceParty", L.OPT_PARTY, L.OPT_PARTY_TIP)
	Checkbox("announceEmote", L.OPT_EMOTE, L.OPT_EMOTE_TIP)
	Checkbox("chatLearn", L.OPT_CHAT, L.OPT_CHAT_TIP)

	-- 7. Достижения и рекорды
	Header(layout, L.NAV_ACH)
	local achToast = Checkbox("achToast", L.OPT_ACH_TOAST, L.OPT_ACH_TOAST_TIP)
	Checkbox("achSound", L.OPT_ACH_SOUND, L.OPT_ACH_SOUND_TIP, achToast)
	Checkbox("achGuild", L.OPT_ACH_GUILD, L.OPT_ACH_GUILD_TIP)

	-- 8. Прочее
	Header(layout, L.SEC_OTHER)
	Checkbox("minimap", L.OPT_MINIMAP, L.OPT_MINIMAP_TIP)
	Button(layout, L.OPT_RESET, L.RESET_BUTTON, L.RESET_ASK, AskReset)

	Settings.RegisterAddOnCategory(category)
end

function HG.OpenSettings()
	if category and Settings.OpenToCategory then
		Settings.OpenToCategory(category:GetID())
	else
		HG.commands.help()
	end
end

HG.Listen("READY", function()
	local ok, err = pcall(Build)
	if not ok then
		category = nil
		HG.Debug("settings:", err)
	end
end)
