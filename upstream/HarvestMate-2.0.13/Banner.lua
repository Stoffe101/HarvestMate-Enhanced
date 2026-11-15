local _, HG = ...

-- Сообщения в центре экрана. Каждое сообщение — отдельная рамка со своим
-- местом (db.banner[id]). Shift + перетаскивание двигает рамку.

local unpack = unpack or table.unpack
local banners = {}

local DEFAULT_Y = { track = 160, train = 120 }

local function SavePosition(frame)
	local cx, cy = frame:GetCenter()
	local ux, uy = UIParent:GetCenter()
	if not cx or not ux then
		return
	end
	local scale = frame:GetEffectiveScale() / UIParent:GetEffectiveScale()
	HG.db.banner[frame.id] = {
		x = math.floor(cx * scale - ux + 0.5),
		y = math.floor(cy * scale - uy + 0.5),
	}
end

local function Place(frame)
	local pos = HG.db.banner[frame.id]
	frame:ClearAllPoints()
	if type(pos) == "table" and type(pos.x) == "number" and type(pos.y) == "number" then
		frame:SetPoint("CENTER", UIParent, "CENTER", pos.x, pos.y)
	else
		frame:SetPoint("CENTER", UIParent, "CENTER", 0, DEFAULT_Y[frame.id] or 140)
	end
end

local function StyleText(fontString, size)
	local file = GameFontNormalLarge:GetFont()
	if file then
		-- Пустая строка флагов в Lua — «истина», поэтому контур задаём явно.
		fontString:SetFont(file, size, "OUTLINE")
	end
end

local function Build(id)
	local frame = CreateFrame("Frame", nil, UIParent)
	frame.id = id
	frame:SetSize(400, 40)
	frame:SetFrameStrata("HIGH")
	frame:SetClampedToScreen(true)
	frame:SetMovable(true)
	frame:EnableMouse(true)
	frame:RegisterForDrag("LeftButton")
	frame:SetScript("OnDragStart", function(self)
		if IsShiftKeyDown() then
			self:StartMoving()
		end
	end)
	frame:SetScript("OnDragStop", function(self)
		self:StopMovingOrSizing()
		SavePosition(self)
		Place(self)
	end)

	frame.text = frame:CreateFontString(nil, "OVERLAY")
	frame.text:SetPoint("TOP", frame, "TOP", 0, 0)
	frame.text:SetTextColor(1, 0.35, 0.25)
	-- Тень под текстом: читается на любом фоне.
	frame.text:SetShadowColor(0, 0, 0, 1)
	frame.text:SetShadowOffset(1, -1)

	frame.buttons = {}
	frame:Hide()
	Place(frame)
	return frame
end

local function Get(id)
	local frame = banners[id]
	if not frame then
		frame = Build(id)
		banners[id] = frame
	end
	return frame
end

local function Button(frame, index)
	local button = frame.buttons[index]
	if button then
		return button
	end
	-- Защищённая кнопка: может произнести заклинание по щелчку игрока.
	-- Обычные действия выполняются в PostClick.
	button = CreateFrame("Button", nil, frame, "SecureActionButtonTemplate")
	button:RegisterForClicks("AnyUp", "AnyDown")
	button.label = button:CreateFontString(nil, "OVERLAY")
	button.label:SetPoint("CENTER")
	button.label:SetTextColor(1, 0.85, 0.1)
	button:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD")
	button:SetScript("PostClick", function(self, _, down)
		if self.action and not down then
			self.action()
		end
	end)
	frame.secure = true
	frame.buttons[index] = button
	return button
end

-- Рамку с защищёнными кнопками нельзя показывать и скрывать в бою.
local function Locked(frame)
	return frame.secure and InCombatLockdown and InCombatLockdown()
end

-- Цвета сообщений: предупреждение — красноватый, остальные — яркие.
HG.BANNER_COLOR = {
	warn = { 1, 0.35, 0.25 },
	ready = { 1, 0.82, 0 },   -- золотой: можно учить ранг
	capped = { 1, 0.55, 0.1 }, -- оранжевый: навык упёрся в предел
}

-- Показывает сообщение. actions — список { text, fn, spellID } для кнопок
-- под текстом: fn — обычное действие, spellID — заклинание по щелчку.
-- color — ключ из HG.BANNER_COLOR (по умолчанию warn).
function HG.ShowBanner(id, message, actions, color)
	local frame = Get(id)
	if Locked(frame) then
		return
	end
	local size = HG.db.opt.fontSize
	StyleText(frame.text, size)
	frame.text:SetTextColor(unpack(HG.BANNER_COLOR[color or "warn"] or HG.BANNER_COLOR.warn))
	frame.text:SetText(message)

	local height = frame.text:GetStringHeight()
	local width = frame.text:GetStringWidth()
	local offset = height + 6
	for i, button in ipairs(frame.buttons) do
		button:Hide()
		button.action = nil
	end
	for i, action in ipairs(actions or {}) do
		local button = Button(frame, i)
		StyleText(button.label, math.max(10, size - 4))
		button.label:SetText(action[1])
		button.action = action[2]
		if action[3] then
			button:SetAttribute("type", "spell")
			button:SetAttribute("spell", action[3])
		else
			button:SetAttribute("type", nil)
			button:SetAttribute("spell", nil)
		end
		button:SetSize(button.label:GetStringWidth() + 16, button.label:GetStringHeight() + 6)
		-- Защищённую кнопку можно крепить только к рамкам, не к тексту:
		-- ставим её от верха рамки со сдвигом на высоту текста и кнопок выше.
		button:ClearAllPoints()
		button:SetPoint("TOP", frame, "TOP", 0, -offset)
		button:Show()
		offset = offset + button:GetHeight() + 2
		height = height + button:GetHeight() + 4
		width = math.max(width, button:GetWidth())
	end
	frame:SetSize(math.max(width, 100) + 20, height + 8)
	Place(frame)
	frame:Show()
end

function HG.HideBanner(id)
	local frame = banners[id]
	if frame and frame:IsShown() and not Locked(frame) then
		frame:Hide()
	end
end

-- Сообщение, которое само исчезает через seconds секунд.
local hideAt = {}
function HG.FlashBanner(id, message, seconds, color)
	HG.ShowBanner(id, message, nil, color)
	local stamp = GetTime() + seconds
	hideAt[id] = stamp
	C_Timer.After(seconds, function()
		if hideAt[id] == stamp then
			HG.HideBanner(id)
		end
	end)
end

HG.Listen("OPTIONS", function()
	for id, frame in pairs(banners) do
		if not Locked(frame) then
			Place(frame)
		end
		if not HG.Active() then
			HG.HideBanner(id)
		end
	end
end)
