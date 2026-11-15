local _, HG = ...

-- Клавиша сбора. Нажать на объект в мире за игрока аддон не может, но
-- может временно назначить клавишу на действие игры «Взаимодействовать
-- с целью». Пока мягкая цель стоит на известном ресурсе, выбранная клавиша
-- собирает его; как только цель ушла — клавиша снова делает своё.
-- В бою назначения менять нельзя: снимаем их до начала боя.

local ACTION = "INTERACTTARGET"
local owner = CreateFrame("Frame")
local bound -- клавиша, которую мы сейчас переназначили

-- Клавиша сбора сейчас действует (рядом ресурс, который можно собрать).
function HG.GatherKeyBound()
	return bound ~= nil
end

function HG.KeyLabel(key)
	local text = GetBindingText and GetBindingText(key)
	return HG.Str(text) or key
end

local function Locked()
	return InCombatLockdown and InCombatLockdown()
end

-- Настройки игры, которые включаются только на то время, пока клавиша
-- сбора активна, а потом возвращаются к прежнему значению.
local TEMPORARY = {
	{ cvar = "autoInteract", option = "gatherMove" },    -- перемещение по щелчку
	{ cvar = "autoLootDefault", option = "gatherLoot" }, -- автоматический сбор добычи
}

local function MoveOn()
	local db = HG.db
	if type(db.cvarBefore) ~= "table" then
		db.cvarBefore = {}
	end
	for _, item in ipairs(TEMPORARY) do
		if db.opt[item.option] and db.cvarBefore[item.cvar] == nil then
			local value = HG.GetCVar(item.cvar)
			if value ~= nil and value ~= "1" and HG.SetCVar(item.cvar, "1") then
				db.cvarBefore[item.cvar] = value
			end
		end
	end
end

local function MoveOff()
	local db = HG.db
	if not db then
		return
	end
	-- Значение, сохранённое версией 1.7.
	if db.ctmBefore ~= nil and HG.SetCVar("autoInteract", db.ctmBefore) then
		db.ctmBefore = nil
	end
	if type(db.cvarBefore) == "table" then
		for cvar, before in pairs(db.cvarBefore) do
			if HG.SetCVar(cvar, before) then
				db.cvarBefore[cvar] = nil
			end
		end
	end
end

local function Release()
	MoveOff()
	if bound and not Locked() then
		ClearOverrideBindings(owner)
		bound = nil
	end
end

-- Клавиша уже и так «взаимодействие» — переназначать не нужно.
local function AlreadyInteract(key)
	if not GetBindingAction then
		return false
	end
	local action = GetBindingAction(key)
	return not HG.Hidden(action) and action == ACTION
end

-- active = true, пока рядом известный ресурс.
function HG.SetGatherKeyActive(active)
	local opt = HG.db and HG.db.opt
	if not active or not opt or not opt.enabled or not opt.gatherKey then
		Release()
		return
	end
	if Locked() or not SetOverrideBinding then
		return
	end
	MoveOn()
	local key = opt.gatherKeyBind
	if bound == key then
		return
	end
	-- Смена клавиши: снимаем только старое назначение, настройку не трогаем.
	if bound then
		ClearOverrideBindings(owner)
		bound = nil
	end
	if AlreadyInteract(key) then
		return
	end
	SetOverrideBinding(owner, true, key, ACTION)
	bound = key
end

-- Строка-подсказка для плашки: "[F] Собрать", или nil.
function HG.GatherKeyHint(label)
	local opt = HG.db and HG.db.opt
	if not opt or not opt.gatherKey or Locked() then
		return nil
	end
	return "|cffffd100[" .. HG.KeyLabel(opt.gatherKeyBind) .. "]|r " .. (label or HG.L.GATHER_KEY)
end

-- Событие приходит до начала боевой блокировки — успеваем снять клавишу.
HG.On("PLAYER_REGEN_DISABLED", function()
	MoveOff()
	if bound then
		ClearOverrideBindings(owner)
		bound = nil
	end
end)

HG.Listen("OPTIONS", Release)
-- Если игру закрыли, стоя у ресурса, вернём настройку при следующем входе.
HG.On("PLAYER_LOGIN", MoveOff)

local function ApplyKey(key)
	HG.db.opt.gatherKeyBind = key
	HG.Say(HG.L.KEY_SET:format(HG.KeyLabel(key)))
	HG.Signal("OPTIONS")
end

------------------------------------------------------------------------
-- Выбор клавиши нажатием: окно ждёт клавишу или кнопку мыши.
------------------------------------------------------------------------

-- Одиночные модификаторы не назначаем — ждём основную клавишу.
local MODIFIER = {
	LSHIFT = true, RSHIFT = true, LCTRL = true, RCTRL = true,
	LALT = true, RALT = true, LMETA = true, RMETA = true,
}
-- Кнопки мыши в имена назначений. Левая и правая — нельзя.
local MOUSE = { MiddleButton = "BUTTON3", Button4 = "BUTTON4", Button5 = "BUTTON5" }

local capture

local function WithModifiers(key)
	local prefix = ""
	if IsAltKeyDown and IsAltKeyDown() then
		prefix = prefix .. "ALT-"
	end
	if IsControlKeyDown and IsControlKeyDown() then
		prefix = prefix .. "CTRL-"
	end
	if IsShiftKeyDown and IsShiftKeyDown() then
		prefix = prefix .. "SHIFT-"
	end
	return prefix .. key
end

local function BuildCapture()
	capture = CreateFrame("Frame", "HarvestMateKeyCapture", UIParent, "BackdropTemplate")
	capture:SetSize(380, 130)
	capture:SetPoint("CENTER", UIParent, "CENTER", 0, 120)
	capture:SetFrameStrata("FULLSCREEN_DIALOG")
	capture:EnableKeyboard(true)
	capture:EnableMouse(true)
	if capture.SetBackdrop then
		capture:SetBackdrop({
			bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
			edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
			edgeSize = 24,
			insets = { left = 6, right = 6, top = 6, bottom = 6 },
		})
	end
	capture.text = capture:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	capture.text:SetPoint("TOPLEFT", 18, -18)
	capture.text:SetPoint("BOTTOMRIGHT", -18, 18)
	capture.text:SetJustifyH("CENTER")

	capture:SetScript("OnKeyDown", function(self, key)
		if key == "ESCAPE" then
			self:Hide()
			return
		end
		if MODIFIER[key] then
			return
		end
		ApplyKey(WithModifiers(key))
		self:Hide()
	end)
	capture:SetScript("OnMouseDown", function(self, button)
		local key = MOUSE[button]
		if not key then
			HG.Say(HG.L.KEY_MOUSE_LR)
			return
		end
		ApplyKey(WithModifiers(key))
		self:Hide()
	end)
	-- Пока окно открыто, нажатия не уходят в игру.
	capture:SetScript("OnShow", function(self)
		if self.SetPropagateKeyboardInput then
			self:SetPropagateKeyboardInput(false)
		end
	end)
	capture:Hide()
end

function HG.CaptureGatherKey()
	if Locked() then
		HG.Say(HG.L.SOFT_COMBAT)
		return
	end
	if not capture then
		BuildCapture()
	end
	capture.text:SetText("|cff6fcf97" .. HG.title .. "|r|n|n" .. HG.L.KEY_PROMPT:format(HG.KeyLabel(HG.db.opt.gatherKeyBind)))
	capture:Show()
end

-- /hm key — открыть выбор клавиши; /hm key F — задать сразу.
HG.commands.key = function(arg)
	local key = arg and arg:upper()
	if not key or key == "" then
		HG.CaptureGatherKey()
		return
	end
	if not key:match("^[%w%-]+$") then
		HG.Say(HG.L.KEY_USAGE)
		return
	end
	ApplyKey(key)
end
