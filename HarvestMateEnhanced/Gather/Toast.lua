local _, ns = ... local HG = ns.HG -- HME patch P1

-- Всплывающее окно достижения и рекорда, в духе окна достижений из
-- Wrath of the Lich King: появляется снизу по центру, вспыхивает, по нему
-- пробегает блик, через несколько секунд гаснет. Под окном — кнопки
-- «В гильдию» и «В группу». Щелчок по окну открывает нужный раздел.
-- Несколько окон подряд показываются по очереди.

local HOLD = 6       -- секунд на экране
local FADE_IN, FADE_OUT = 0.25, 1.2
-- Звук достижения: сначала файл «фанфар» из окна достижений, затем запасные
-- варианты. Канал Master — слышно, даже если звуковые эффекты приглушены.
local SOUND_FILE = 569143  -- sound/interface/achievmentsound1.ogg
local SOUND_KITS = { 12891, 8960 }

local function PlayFanfare()
	if PlaySoundFile then
		local ok, played = pcall(PlaySoundFile, SOUND_FILE, "Master")
		if ok and played then
			return
		end
	end
	if PlaySound then
		for _, kit in ipairs(SOUND_KITS) do
			local ok, played = pcall(PlaySound, kit, "Master")
			if ok and played then
				return
			end
		end
	end
end

local WIDTH = 340
local TEXT_LEFT = 70
local TEXT_WIDTH = WIDTH - TEXT_LEFT - 66 -- до щита с очками
local TEXT_CENTER = TEXT_LEFT + TEXT_WIDTH / 2

local toast
local queue = {}
local showing

local function Next()
	showing = nil
	if toast then
		toast:Hide()
	end
	local info = table.remove(queue, 1)
	if info then
		HG.Toast(info, true)
	end
end

local function Animation(group, kind, order)
	local animation = group:CreateAnimation(kind)
	animation:SetOrder(order)
	return animation
end

local function Build()
	toast = CreateFrame("Button", "HarvestMateToast", UIParent, "BackdropTemplate")
	toast:SetSize(WIDTH, 88)
	toast:SetPoint("BOTTOM", UIParent, "BOTTOM", 0, 190)
	toast:SetFrameStrata("DIALOG")
	toast:Hide()

	local background = toast:CreateTexture(nil, "BACKGROUND")
	background:SetTexture("Interface\\AchievementFrame\\UI-Achievement-Alert-Background")
	background:SetTexCoord(0, 0.605, 0, 0.703)
	background:SetAllPoints()

	toast.glow = toast:CreateTexture(nil, "OVERLAY")
	toast.glow:SetTexture("Interface\\AchievementFrame\\UI-Achievement-Alert-Glow")
	toast.glow:SetTexCoord(0, 0.78125, 0, 0.66796875)
	toast.glow:SetBlendMode("ADD")
	toast.glow:SetSize(400, 171)
	toast.glow:SetPoint("CENTER")
	toast.glow:SetAlpha(0)
	toast.glow:Hide()

	toast.shine = toast:CreateTexture(nil, "OVERLAY")
	toast.shine:SetTexture("Interface\\AchievementFrame\\UI-Achievement-Alert-Glow")
	toast.shine:SetTexCoord(0.78125, 0.912109375, 0, 0.28125)
	toast.shine:SetBlendMode("ADD")
	toast.shine:SetSize(67, 72)
	toast.shine:SetPoint("BOTTOMLEFT", toast, "BOTTOMLEFT", 0, 8)
	toast.shine:SetAlpha(0)
	toast.shine:Hide()

	-- Раскладка повторяет окно достижений игры: значок слева в рамке,
	-- текст в «окошке» между рамками, щит с очками справа.
	toast.icon = toast:CreateTexture(nil, "ARTWORK")
	toast.icon:SetSize(48, 48)
	toast.icon:SetPoint("CENTER", toast, "TOPLEFT", 36, -44)
	toast.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

	local ring = toast:CreateTexture(nil, "OVERLAY")
	ring:SetTexture("Interface\\AchievementFrame\\UI-Achievement-IconFrame")
	ring:SetTexCoord(0, 0.5625, 0, 0.5625)
	ring:SetSize(72, 72)
	ring:SetPoint("CENTER", toast.icon, "CENTER", -1, -1)

	-- Внутри окна две строки по центру: «Достижение HarvestMate» и название.
	-- Обе в одну линию; если текст не помещается, шрифт уменьшается.
	-- Описание показывается в подсказке при наведении.
	local function TextLine(font, y)
		local text = toast:CreateFontString(nil, "OVERLAY", font)
		text:SetWidth(TEXT_WIDTH)
		text:SetJustifyH("CENTER")
		if text.SetWordWrap then
			text:SetWordWrap(false)
		end
		text:SetPoint("CENTER", toast, "TOPLEFT", TEXT_CENTER, y)
		return text
	end
	toast.header = TextLine("GameFontNormalSmall", -40)
	toast.name = TextLine("GameFontHighlight", -56)

	toast.shield = toast:CreateTexture(nil, "ARTWORK")
	toast.shield:SetTexture("Interface\\AchievementFrame\\UI-Achievement-Shields")
	toast.shield:SetTexCoord(0, 0.5, 0, 0.45)
	toast.shield:SetSize(52, 48)
	toast.shield:SetPoint("CENTER", toast, "TOPRIGHT", -36, -44)

	toast.points = toast:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	toast.points:SetPoint("CENTER", toast.shield, "CENTER", 0, 2)

	-- Кнопки под окном: «В гильдию» и «В группу».
	local function ShareButton(key, where, anchor, x)
		local button = CreateFrame("Button", nil, toast, "UIPanelButtonTemplate")
		button:SetSize(110, 20)
		button:SetPoint(anchor, toast, "BOTTOM", x, 12)
		button:SetText(HG.L[key])
		button:SetScript("OnClick", function()
			if showing and showing.share then
				showing.share(where)
			end
		end)
		return button
	end
	toast.guild = ShareButton("SHARE_GUILD", "GUILD", "TOPRIGHT", -3)
	toast.party = ShareButton("SHARE_PARTY", "PARTY", "TOPLEFT", 3)

	toast:SetScript("OnClick", function()
		local page = showing and showing.page
		Next()
		if page then
			HG.OpenHub(page)
		end
	end)

	-- Анимация. Если клиент её не умеет, окно просто исчезнет по таймеру.
	toast.life, toast.flash, toast.sweep = false, false, false
	local group = toast.CreateAnimationGroup and toast:CreateAnimationGroup()
	if group and group.CreateAnimation then
		local appear = Animation(group, "Alpha", 1)
		appear:SetFromAlpha(0)
		appear:SetToAlpha(1)
		appear:SetDuration(FADE_IN)
		local vanish = Animation(group, "Alpha", 2)
		vanish:SetFromAlpha(1)
		vanish:SetToAlpha(0)
		vanish:SetStartDelay(HOLD)
		vanish:SetDuration(FADE_OUT)
		group:SetScript("OnFinished", Next)
		toast.life = group

		-- Вспышка и блик проигрываются один раз. Когда анимация кончается,
		-- смещение сбрасывается и блик вернулся бы в начало, поэтому
		-- текстуру прячем целиком, а не полагаемся на прозрачность.
		local function Settle(animation, texture)
			if animation.SetLooping then
				animation:SetLooping("NONE")
			end
			if animation.SetToFinalAlpha then
				animation:SetToFinalAlpha(true)
			end
			local function Done()
				texture:SetAlpha(0)
				texture:Hide()
			end
			animation:SetScript("OnFinished", Done)
			animation:SetScript("OnStop", Done)
		end

		local flash = toast.glow:CreateAnimationGroup()
		local flashIn = Animation(flash, "Alpha", 1)
		flashIn:SetFromAlpha(0)
		flashIn:SetToAlpha(1)
		flashIn:SetDuration(0.2)
		local flashOut = Animation(flash, "Alpha", 2)
		flashOut:SetFromAlpha(1)
		flashOut:SetToAlpha(0)
		flashOut:SetDuration(0.5)
		Settle(flash, toast.glow)
		toast.flash = flash

		local sweep = toast.shine:CreateAnimationGroup()
		local sweepIn = Animation(sweep, "Alpha", 1)
		sweepIn:SetFromAlpha(0)
		sweepIn:SetToAlpha(1)
		sweepIn:SetDuration(0.2)
		local sweepMove = Animation(sweep, "Translation", 2)
		sweepMove:SetOffset(WIDTH - 70, 0)
		sweepMove:SetDuration(0.85)
		local sweepOut = Animation(sweep, "Alpha", 2)
		sweepOut:SetFromAlpha(1)
		sweepOut:SetToAlpha(0)
		sweepOut:SetStartDelay(0.35)
		sweepOut:SetDuration(0.5)
		Settle(sweep, toast.shine)
		toast.sweep = sweep

	end

	-- При наведении: описание в подсказке, и окно не гаснет.
	toast:SetScript("OnEnter", function(self)
		if toast.life then
			toast.life:Stop()
			self:SetAlpha(1)
		end
		if showing and GameTooltip and GameTooltip.SetOwner then
			GameTooltip:SetOwner(self, "ANCHOR_TOP")
			GameTooltip:AddLine(showing.name, 1, 0.82, 0)
			if showing.desc and showing.desc ~= "" then
				GameTooltip:AddLine(showing.desc, 1, 1, 1, true)
			end
			GameTooltip:Show()
		end
	end)
	toast:SetScript("OnLeave", function()
		if GameTooltip and GameTooltip.Hide then
			GameTooltip:Hide()
		end
		if showing and toast.life then
			toast.life:Play()
		end
	end)
end

-- Ставит текст и уменьшает шрифт, пока строка не поместится по ширине.
local function Fit(text, value, size, smallest)
	local file, _, flags = text:GetFont()
	text:SetText(value)
	if not file then
		return
	end
	local measure = text.GetUnboundedStringWidth or text.GetStringWidth
	for current = size, smallest, -1 do
		text:SetFont(file, current, flags)
		local width = measure(text)
		if type(width) ~= "number" or width <= TEXT_WIDTH then
			break
		end
	end
end

-- info: header, name, desc, icon, points, page, share(where).
function HG.Toast(info, fromQueue)
	if showing and not fromQueue then
		queue[#queue + 1] = info
		return
	end
	if not toast then
		Build()
	end
	showing = info
	Fit(toast.header, info.header, 10, 8)
	Fit(toast.name, info.name, 12, 9)
	toast.icon:SetTexture(info.icon)
	if info.points then
		toast.points:SetText(info.points)
		toast.points:Show()
		toast.shield:Show()
	else
		toast.points:Hide()
		toast.shield:Hide()
	end
	toast:SetAlpha(1)
	toast:Show()
	if HG.db.opt.achSound then
		PlayFanfare()
	end
	if toast.life then
		toast.life:Stop()
		toast.life:Play()
		toast.flash:Stop()
		toast.sweep:Stop()
		toast.glow:Show()
		toast.shine:Show()
		toast.flash:Play()
		toast.sweep:Play()
	else
		C_Timer.After(HOLD, function()
			if showing == info then
				Next()
			end
		end)
	end
end

-- Для тестов и раздела «Достижения»: что сейчас на экране.
function HG.ToastShowing()
	return showing
end
