local _, ns = ... local HG = ns.HG -- HME patch P1

-- Подсветка ресурса рядом. Использует «мягкую цель взаимодействия»
-- (soft interact): когда вы подходите к траве, жиле или сундуку,
-- над объектом (или в выбранном месте экрана) появляется плашка с навыком,
-- ростом навыка, Культивацией и добычей. Издалека аддоны объекты
-- не видят — только то, на что игра навела мягкую цель.
--
-- Как узнаём объект (по порядку):
--   1) имя мягкой цели (UnitName),
--   2) первая строка подсказки мягкой цели (C_TooltipInfo),
--   3) изученная связь «id объекта -> ресурс»: из подсказки при наведении
--      мышью и из добычи (GetLootSourceInfo) после первого сбора.

local UNIT = "softinteract"
local POLL = 0.25 -- запасной опрос, если событие не приходит

local frame
local currentGuid
local eventGuid
local diag = { events = 0 }

------------------------------------------------------------------------
-- Плашка
------------------------------------------------------------------------

local function SavePosition(self)
	local cx, cy = self:GetCenter()
	local ux, uy = UIParent:GetCenter()
	if cx and ux then
		HG.db.banner.near = { x = math.floor(cx - ux + 0.5), y = math.floor(cy - uy + 0.5) }
	end
end

local function Build()
	frame = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
	frame:SetFrameStrata("MEDIUM")
	frame:SetClampedToScreen(true)
	frame:SetMovable(true)
	frame:EnableMouse(false)
	if frame.SetBackdrop then
		frame:SetBackdrop({
			bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
			edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
			edgeSize = 12,
			insets = { left = 3, right = 3, top = 3, bottom = 3 },
		})
		frame:SetBackdropColor(0, 0, 0, 0.75)
	end
	frame.rows = {}
	frame:Hide()
	-- Перетаскивание с Shift, когда плашка не привязана к объекту.
	frame:RegisterForDrag("LeftButton")
	frame:SetScript("OnDragStart", function(self)
		if IsShiftKeyDown() then
			self:StartMoving()
		end
	end)
	frame:SetScript("OnDragStop", function(self)
		self:StopMovingOrSizing()
		SavePosition(self)
	end)
end

local function Row(index)
	local row = frame.rows[index]
	if not row then
		row = frame:CreateFontString(nil, "OVERLAY", index == 1 and "GameFontNormal" or "GameFontHighlightSmall")
		row:SetJustifyH("LEFT")
		if index == 1 then
			row:SetPoint("TOPLEFT", frame, "TOPLEFT", 8, -7)
		else
			row:SetPoint("TOPLEFT", frame.rows[index - 1], "BOTTOMLEFT", 0, -2)
		end
		frame.rows[index] = row
	end
	return row
end

-- Табличка имени над объектом, если игра её показывает.
local function VisiblePlate()
	if not (C_NamePlate and C_NamePlate.GetNamePlateForUnit) then
		return nil
	end
	local ok, plate = pcall(C_NamePlate.GetNamePlateForUnit, UNIT)
	plate = ok and HG.Tbl(plate) or nil
	if plate and plate.IsVisible and plate:IsVisible() then
		return plate
	end
	return nil
end

------------------------------------------------------------------------
-- Символ над объектом: иконка ресурса с кольцом цвета сложности,
-- плавно покачивается. Ставится на табличку имени мягкой цели —
-- это единственный способ привязаться к месту объекта в мире.
------------------------------------------------------------------------

local MARKER_SIZE = 30
local LOCK_ICON = "Interface\\Icons\\INV_Misc_Key_03"
local DEFAULT_ICON = {
	herb = "Interface\\Icons\\INV_Misc_Flower_02",
	mine = "Interface\\Icons\\INV_Ore_Copper_01",
	lock = LOCK_ICON,
	skin = "Interface\\Icons\\INV_Misc_Pelt_Wolf_01",
}
local marker

local function BuildMarker()
	marker = CreateFrame("Frame", nil, UIParent)
	marker:SetSize(MARKER_SIZE, MARKER_SIZE)
	marker:SetFrameStrata("MEDIUM")
	marker:EnableMouse(false)

	marker.icon = marker:CreateTexture(nil, "ARTWORK")
	marker.icon:SetAllPoints()
	marker.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

	-- Кольцо: рамка кнопки действия, подкрашенная цветом сложности.
	marker.ring = marker:CreateTexture(nil, "OVERLAY")
	marker.ring:SetTexture("Interface\\Buttons\\UI-ActionButton-Border")
	marker.ring:SetBlendMode("ADD")
	marker.ring:SetPoint("CENTER")
	marker.ring:SetSize(MARKER_SIZE * 1.9, MARKER_SIZE * 1.9)

	-- Покачивание вверх-вниз, как поплавок.
	marker.bob = false
	local group = marker.CreateAnimationGroup and marker:CreateAnimationGroup()
	local move = group and group:CreateAnimation("Translation")
	if move then
		move:SetOffset(0, 5)
		move:SetDuration(0.7)
		if move.SetSmoothing then
			move:SetSmoothing("IN_OUT")
		end
		group:SetLooping("BOUNCE")
		marker.bob = group
	end
	marker:Hide()
end

local function MarkerIcon(entry)
	if entry.prof == "lock" then
		return LOCK_ICON
	end
	local seed = HG.SEED_DROPS[entry.key]
	local id = seed and seed[1] and seed[1].id
	local getIcon = C_Item and C_Item.GetItemIconByID or _G.GetItemIcon
	local icon = id and getIcon and getIcon(id)
	if icon and not HG.Hidden(icon) then
		return icon
	end
	return DEFAULT_ICON[entry.prof] or DEFAULT_ICON.herb
end

local function HexToRGB(hex)
	return tonumber(hex:sub(1, 2), 16) / 255, tonumber(hex:sub(3, 4), 16) / 255, tonumber(hex:sub(5, 6), 16) / 255
end

-- Показывает символ над табличкой; возвращает true, если показан.
local function ShowMarker(plate, entry)
	if not plate or not HG.db.opt.marker then
		if marker then
			marker:Hide()
		end
		return false
	end
	if not marker then
		BuildMarker()
	end
	marker.icon:SetTexture(MarkerIcon(entry))
	local skill = HG.Skill(entry.prof)
	local req = HG.Requirement(entry)
	local difficulty = (skill and req) and HG.ColorFor(entry.prof, skill, req) or "grey"
	marker.ring:SetVertexColor(HexToRGB(HG.HEX[difficulty] or HG.HEX.grey))
	marker:ClearAllPoints()
	marker:SetPoint("BOTTOM", plate, "TOP", 0, 4)
	marker:Show()
	if marker.bob and not marker.bob:IsPlaying() then
		marker.bob:Play()
	end
	return true
end

local function HideMarker()
	if marker then
		marker:Hide()
	end
end

local currentEntry

local function Anchor()
	frame:ClearAllPoints()
	local plate = VisiblePlate()
	diag.plate = plate ~= nil
	if plate then
		local withMarker = ShowMarker(plate, currentEntry)
		if withMarker then
			frame:SetPoint("BOTTOM", marker, "TOP", 0, 8)
		else
			frame:SetPoint("BOTTOM", plate, "TOP", 0, 6)
		end
		frame:EnableMouse(false)
		return
	end
	HideMarker()
	local pos = HG.db.banner.near
	if type(pos) == "table" and type(pos.x) == "number" then
		frame:SetPoint("CENTER", UIParent, "CENTER", pos.x, pos.y)
	else
		frame:SetPoint("CENTER", UIParent, "CENTER", 0, -140)
	end
	frame:EnableMouse(true)
end

local function Render(lines)
	if not frame then
		Build()
	end
	local width, height = 0, 10
	for i, text in ipairs(lines) do
		local row = Row(i)
		row:SetText(text)
		row:Show()
		width = math.max(width, row:GetStringWidth())
		height = height + row:GetStringHeight() + 2
	end
	for i = #lines + 1, #frame.rows do
		frame.rows[i]:Hide()
	end
	frame:SetSize(width + 16, height + 4)
	Anchor()
	frame:Show()
end

local function HidePlate()
	if frame then
		frame:Hide()
	end
	HideMarker()
	HG.SetGatherKeyActive(false)
	HG.Signal("NEAR_NONE")
end

local function Chime()
	if not HG.db.opt.nearbySound or not PlaySound then
		return
	end
	local kit = SOUNDKIT and SOUNDKIT.MAP_PING or 3175
	PlaySound(kit, "SFX")
end

------------------------------------------------------------------------
-- Что под мягкой целью
------------------------------------------------------------------------

local function TooltipName()
	if not (C_TooltipInfo and C_TooltipInfo.GetUnit) then
		return nil
	end
	local ok, data = pcall(C_TooltipInfo.GetUnit, UNIT)
	data = ok and HG.Tbl(data) or nil
	local lines = data and HG.Tbl(data.lines)
	local first = lines and HG.Tbl(lines[1])
	return first and HG.CleanName(HG.Str(first.leftText))
end

-- Как выглядит значение для диагностики: обычное, скрытое (secret) или пустое.
local function Peek(value)
	if value == nil then
		return nil
	end
	if HG.Hidden(value) then
		return "(secret)"
	end
	return tostring(value)
end

-- key (для сравнения «тот же объект?»), objectId, имя, ресурс.
-- GUID может быть скрыт клиентом — тогда работаем только по имени.
local function Identify()
	local rawGuid = UnitGUID(UNIT)
	diag.rawGuid, diag.eventGuid = Peek(rawGuid), Peek(eventGuid)
	local guid = HG.Str(rawGuid) or eventGuid
	local kind = guid and guid:match("^(%a+)%-")
	local objectId = guid and HG.ObjectId(guid)
	diag.guid, diag.objectId = guid, objectId
	-- Существо (NPC, труп) — не наш случай.
	if kind and kind ~= "GameObject" then
		return nil
	end
	local rawName = UnitName(UNIT)
	diag.rawName = Peek(rawName)
	local unitName = HG.CleanName(HG.Str(rawName))
	local tipName = not unitName and TooltipName() or nil
	local learned = objectId and HG.db.learned.objects[objectId]
	diag.unitName, diag.tipName, diag.learned = unitName, tipName, learned
	if not objectId and not unitName and not tipName then
		return nil
	end

	local name = unitName or tipName
	local entry = name and HG.Find(name)
	if not entry and type(learned) == "string" then
		entry = HG.Find(learned)
		if entry then
			name = HG.DisplayName(learned)
		end
	end
	if name and entry and objectId then
		-- Запоминаем: в следующий раз узнаем и без имени.
		HG.db.learned.objects[objectId] = entry.key
	end
	return guid or ("name:" .. tostring(name)), objectId, name, entry
end

-- Труп зверя под мягкой целью: плашка снятия шкур и клавиша сбора.
-- Если на трупе ещё есть добыча, та же клавиша сначала обыщет его.
local function ShowCorpse(level, name)
	local skill = HG.Skill("skin")
	if not skill or not HG.db.opt.skin then
		currentGuid = nil
		HidePlate()
		return
	end
	local entry = { prof = "skin", req = HG.SkinRequirement(level), key = "skin:" .. level }
	local label = HG.ProfName("skin")
	local title = name or label
	local lines = { HG.Describe(title, entry) or title }
	local canSkin = skill >= HG.Requirement(entry)
	HG.SetGatherKeyActive(canSkin)
	local hint = canSkin and HG.GatherKeyHint(label)
	if hint then
		lines[#lines + 1] = hint
	end
	for _, line in ipairs(HG.ExtraLines(entry)) do
		lines[#lines + 1] = line
	end
	currentGuid = "corpse:" .. tostring(name) .. ":" .. level
	currentEntry = entry
	Render(lines)
	HG.Signal("NEAR_NODE", entry.prof)
end

-- refresh = true: тот же объект, только обновить текст (таймер Культивации).
function HG.UpdateNearby(refresh)
	local opt = HG.db and HG.db.opt
	if not opt or not opt.enabled or not opt.nearby then
		currentGuid = nil
		HidePlate()
		return
	end
	local corpseLevel, corpseName = HG.SkinnableCorpse(UNIT)
	if corpseLevel then
		ShowCorpse(corpseLevel, corpseName)
		return
	end
	local guid, objectId, name, entry = Identify()
	diag.entry = entry and entry.key or nil
	if not guid then
		currentGuid = nil
		HidePlate()
		return
	end

	local isNew = guid ~= currentGuid
	currentGuid = guid
	if isNew and name then
		-- Сбор клавишей взаимодействия тоже привязывается к этому объекту.
		HG.RememberHover(name, entry)
	end
	if not entry then
		HidePlate()
		return
	end

	-- Собрать можно, только если профессия есть, включена и навыка хватает.
	local mySkill = HG.Skill(entry.prof)
	local needed = HG.Requirement(entry)
	local hasProf = mySkill ~= nil and HG.db.opt[entry.prof]
	local extra = HG.ExtraLines(entry)
	-- Нет профессии и сказать нечего — не подсвечиваем чужой ресурс.
	if not hasProf and #extra == 0 then
		HidePlate()
		return
	end
	local canGather = hasProf and needed ~= nil and mySkill >= needed

	local lines = { HG.Describe(name, entry) or name }
	HG.SetGatherKeyActive(canGather)
	local hint = canGather and HG.GatherKeyHint()
	if hint then
		lines[#lines + 1] = hint
	end
	for _, line in ipairs(extra) do
		lines[#lines + 1] = line
	end
	currentEntry = entry
	Render(lines)
	HG.Signal("NEAR_NODE", entry.prof)

	if isNew and not refresh then
		local skill = HG.Skill(entry.prof)
		local req = HG.Requirement(entry)
		if skill and req and skill >= req then
			Chime()
		end
	end
end

------------------------------------------------------------------------
-- События и опрос
------------------------------------------------------------------------

HG.On("PLAYER_SOFT_INTERACT_CHANGED", function(_, newTarget)
	diag.events = diag.events + 1
	eventGuid = HG.Str(newTarget)
	HG.Debug("soft target:", Peek(newTarget) or "-", Peek(UnitName(UNIT)) or "-")
	HG.UpdateNearby(false)
end)

-- Опрос раз в 0.25 с: смена цели без события и таймер Культивации.
do
	local driver = CreateFrame("Frame")
	local elapsed, sinceRefresh, lastSeen = 0, 0, nil
	driver:SetScript("OnUpdate", function(_, delta)
		elapsed = elapsed + delta
		if elapsed < POLL then
			return
		end
		sinceRefresh = sinceRefresh + elapsed
		elapsed = 0
		if not (HG.db and HG.db.opt.enabled and HG.db.opt.nearby) then
			return
		end
		local guid = HG.Str(UnitGUID(UNIT)) or HG.Str(UnitName(UNIT))
		if guid ~= lastSeen then
			lastSeen = guid
			if not guid then
				eventGuid = nil
			end
			HG.UpdateNearby(false)
		elseif currentGuid and sinceRefresh >= 1 then
			sinceRefresh = 0
			HG.UpdateNearby(true)
		end
	end)
end

HG.Listen("OPTIONS", function()
	HG.UpdateNearby(true)
end)
HG.Listen("SKILLS", function()
	if currentGuid then
		HG.UpdateNearby(true)
	end
end)

------------------------------------------------------------------------
-- Мягкая цель в настройках игры и диагностика
------------------------------------------------------------------------

-- Символу нужна табличка имени над мягкой целью. Включаем её, пока
-- символ включён, и возвращаем как было, когда его выключают.
local PLATE_CVAR = "SoftTargetNameplateInteract"

local function ApplyPlateSetting()
	local db = HG.db
	if not db or (InCombatLockdown and InCombatLockdown()) then
		return
	end
	local want = db.opt.enabled and db.opt.nearby and db.opt.marker
	local value = HG.GetCVar(PLATE_CVAR)
	if want and value ~= nil and value ~= "1" then
		db.plateBefore = value
		HG.SetCVar(PLATE_CVAR, "1")
	elseif not want and db.plateBefore ~= nil then
		HG.SetCVar(PLATE_CVAR, db.plateBefore)
		db.plateBefore = nil
	end
end

HG.Listen("OPTIONS", ApplyPlateSetting)
HG.On("PLAYER_REGEN_ENABLED", ApplyPlateSetting)

-- При первом запуске — окно с объяснением и предложением включить мягкую
-- цель. Пока игрок не нажал «Включить», ничего не меняется. Окно
-- показывается один раз, какой бы ни был ответ.
local POPUP = "HARVESTMATE_SOFT_TARGET"

local function RegisterPopup()
	if not StaticPopupDialogs or StaticPopupDialogs[POPUP] then
		return StaticPopupDialogs ~= nil
	end
	local L = HG.L
	StaticPopupDialogs[POPUP] = {
		text = L.SOFT_ASK,
		button1 = L.SOFT_YES,
		button2 = L.SOFT_NO,
		OnAccept = function()
			if InCombatLockdown and InCombatLockdown() then
				HG.Say(L.SOFT_COMBAT)
			elseif HG.EnableSoftTarget() then
				HG.Say(L.SOFT_ON)
				HG.Signal("OPTIONS")
			else
				HG.Say(L.SOFT_FAILED)
			end
		end,
		OnCancel = function()
			HG.Say(L.SOFT_LATER)
		end,
		timeout = 0,
		whileDead = true,
		hideOnEscape = true,
		preferredIndex = 3,
	}
	return true
end

function HG.AskSoftTarget()
	if not RegisterPopup() or not StaticPopup_Show then
		HG.Say(HG.L.SOFT_HINT)
		return
	end
	HG.db.softAsked = true
	StaticPopup_Show(POPUP)
end

local function MaybeAsk()
	local db = HG.db
	local opt = db and db.opt
	if not opt or not opt.enabled or not opt.nearby or db.softAsked or HG.SoftTargetOn() then
		return
	end
	if InCombatLockdown and InCombatLockdown() then
		return
	end
	HG.AskSoftTarget()
end

-- Мягкая цель выключена, хотя игрок её уже включал (другой компьютер,
-- сброс настроек игры, выключенный геймпад): включаем снова и говорим об этом.
local function Restore()
	local db = HG.db
	local opt = db and db.opt
	if not opt or not opt.enabled or not opt.nearby or HG.SoftTargetOn() then
		return
	end
	if db.softWanted == nil and db.softBefore ~= nil then
		db.softWanted = true -- включал в прошлых версиях, когда согласие ещё не запоминалось
	end
	if not db.softWanted then
		if db.softAsked then
			HG.Say(HG.L.SOFT_HINT)
		end
		return
	end
	if InCombatLockdown and InCombatLockdown() then
		return
	end
	if HG.EnableSoftTarget() then
		HG.Say(HG.L.SOFT_RESTORED)
		HG.Signal("OPTIONS")
	else
		HG.Say(HG.L.SOFT_FAILED)
	end
end

HG.On("PLAYER_LOGIN", function()
	local db = HG.db
	local opt = db and db.opt
	if opt and opt.nearby and db.softAsked and HG.SoftTargetOn() and db.softWanted == nil then
		db.softWanted = true
	end
	C_Timer.After(2, Restore)
	-- Немного подождём, пока интерфейс догрузится.
	C_Timer.After(4, MaybeAsk)
	ApplyPlateSetting()
end)

HG.On("PLAYER_REGEN_ENABLED", MaybeAsk)

-- /hm near — что видит подсветка прямо сейчас.
function HG.NearbyReport()
	local function show(value)
		if value == nil then
			return "-"
		end
		return tostring(value)
	end
	HG.UpdateNearby(true)
	HG.Say(("SoftTargetInteract=%s gamepad=%s devices=%s GamePadEnable=%s SoftTargetNameplateInteract=%s events=%d plate=%s shown=%s marker=%s"):format(
		show(HG.GetCVar("SoftTargetInteract")), show(HG.GamepadMode()), show(HG.GamepadDevices()), show(HG.GetCVar("GamePadEnable")),
		show(HG.GetCVar(PLATE_CVAR)), diag.events,
		show(diag.plate), show(frame and frame:IsShown()), show(marker and marker:IsShown())))
	HG.Say(("guid=%s event=%s object=%s"):format(show(diag.rawGuid), show(diag.eventGuid), show(diag.objectId)))
	HG.Say(("name=%s tooltip=%s learned=%s match=%s"):format(
		show(diag.rawName), show(diag.tipName), show(diag.learned), show(diag.entry)))
	if HG.missingEvents then
		HG.Say("missing events: " .. table.concat(HG.missingEvents, ", "))
	end
end
