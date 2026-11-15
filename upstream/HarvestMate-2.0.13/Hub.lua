local _, HG = ...

-- Главное окно аддона. Слева разделы, справа содержимое:
-- сессия, достижения, рекорды, сумки, что качать. Кнопка «Настройки»
-- открывает панель настроек игры. В заголовке — название аддона и раздел.

local WIDTH, HEIGHT = 720, 452
local NAV_WIDTH = 150
local LEFT, TOP = NAV_WIDTH + 24, -48          -- начало области содержимого
local CONTENT_WIDTH = WIDTH - LEFT - 16
local MAX_LINES, LINE_HEIGHT = 20, 17
local ROWS_PER_PAGE, ROW_HEIGHT = 7, 46

local PAGES = {
	{ id = "session", label = "SESSION_TITLE" },
	{ id = "ach", label = "NAV_ACH" },
	{ id = "records", label = "NAV_RECORDS" },
	{ id = "bags", label = "NAV_BAGS" },
	{ id = "next", label = "NAV_NEXT" },
}

local hub
local current = "session"
local achPage = 1

local function Clock(seconds)
	seconds = math.floor(seconds)
	local hours, minutes = math.floor(seconds / 3600), math.floor(seconds / 60) % 60
	if hours > 0 then
		return ("%d:%02d:%02d"):format(hours, minutes, seconds % 60)
	end
	return ("%d:%02d"):format(minutes, seconds % 60)
end

------------------------------------------------------------------------
-- Кирпичики
------------------------------------------------------------------------

local function PanelButton(parent, width, text, onClick)
	local button = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
	button:SetSize(width, 22)
	button:SetText(text)
	button:SetScript("OnClick", onClick)
	return button
end

local function Line(index)
	local line = hub.lines[index]
	if not line then
		line = hub:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
		line:SetJustifyH("LEFT")
		line:SetWidth(CONTENT_WIDTH)
		line:SetPoint("TOPLEFT", hub, "TOPLEFT", LEFT, TOP - (index - 1) * LINE_HEIGHT)
		hub.lines[index] = line
	end
	return line
end

local function ShowLines(lines)
	for i = 1, MAX_LINES do
		local text = lines[i]
		if text then
			local line = Line(i)
			line:SetText(text)
			line:Show()
		elseif hub.lines[i] then
			hub.lines[i]:Hide()
		end
	end
end

-- Кнопки внизу области содержимого: список { текст, действие }.
local function ShowActions(actions)
	for i, action in ipairs(actions) do
		local button = hub.actions[i]
		if not button then
			button = PanelButton(hub, 104, "", nil)
			button:SetWidth(104)
			button:SetPoint("BOTTOMLEFT", hub, "BOTTOMLEFT", LEFT + (i - 1) * 108, 14)
			hub.actions[i] = button
		end
		button:SetText(action[1])
		button:SetScript("OnClick", action[2])
		button:Show()
	end
	for i = #actions + 1, #hub.actions do
		hub.actions[i]:Hide()
	end
end

------------------------------------------------------------------------
-- Строки достижений
------------------------------------------------------------------------

local function AchRow(index)
	local row = hub.rows[index]
	if row then
		return row
	end
	row = CreateFrame("Frame", nil, hub)
	row:SetSize(CONTENT_WIDTH, ROW_HEIGHT - 4)
	row:SetPoint("TOPLEFT", hub, "TOPLEFT", LEFT, TOP - 24 - (index - 1) * ROW_HEIGHT)

	row.icon = row:CreateTexture(nil, "ARTWORK")
	row.icon:SetSize(34, 34)
	row.icon:SetPoint("LEFT", row, "LEFT", 0, 0)
	row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

	row.name = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	row.name:SetPoint("TOPLEFT", row, "TOPLEFT", 42, -1)
	row.name:SetJustifyH("LEFT")

	row.desc = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	row.desc:SetPoint("TOPLEFT", row.name, "BOTTOMLEFT", 0, -2)
	row.desc:SetWidth(CONTENT_WIDTH - 42 - 150)
	row.desc:SetJustifyH("LEFT")

	row.progress = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	row.progress:SetPoint("TOPRIGHT", row, "TOPRIGHT", 0, -1)
	row.progress:SetJustifyH("RIGHT")

	row.bar = CreateFrame("StatusBar", nil, row)
	row.bar:SetSize(CONTENT_WIDTH - 42 - 150, 5)
	row.bar:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 42, 0)
	row.bar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
	row.bar:SetStatusBarColor(0.28, 0.78, 0.35)
	local back = row.bar:CreateTexture(nil, "BACKGROUND")
	back:SetAllPoints()
	back:SetColorTexture(0, 0, 0, 0.5)

	row.guild = PanelButton(row, 70, HG.L.SHARE_GUILD, function()
		HG.ShareAchievement(row.series, row.tier, "GUILD")
	end)
	row.guild:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", -74, -2)
	row.party = PanelButton(row, 70, HG.L.SHARE_PARTY, function()
		HG.ShareAchievement(row.series, row.tier, "PARTY")
	end)
	row.party:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", 0, -2)

	hub.rows[index] = row
	return row
end

local function HideAchRows()
	for _, row in ipairs(hub.rows) do
		row:Hide()
	end
	hub.pager:Hide()
end

------------------------------------------------------------------------
-- Разделы
------------------------------------------------------------------------

local render = {}

function render.session()
	local L = HG.L
	local session = HG.session
	local elapsed = HG.SessionElapsed()
	local value = HG.SessionValue()
	local lines = {
		"|cffffd100" .. Clock(elapsed) .. "|r",
		L.SESSION_GATHERS:format(session.gathers),
		L.SESSION_VALUE:format(HG.Money(value)),
		L.SESSION_RATE:format(elapsed >= 60 and HG.Money(value / elapsed * 3600) or "-"),
		" ",
	}
	for _, prof in ipairs({ "herb", "mine", "skin" }) do
		local gathers, worth = HG.SessionProfession(prof)
		if gathers then
			lines[#lines + 1] = L.SESSION_PROF_LINE:format(HG.ProfName(prof), gathers, HG.Money(worth), HG.Money(worth / gathers))
		end
	end
	local rows = HG.SessionRows()
	if #rows == 0 then
		lines[#lines + 1] = "|cff9a9a9a" .. L.SESSION_EMPTY .. "|r"
	else
		lines[#lines + 1] = " "
		for i = 1, math.min(#rows, 10) do
			local item = rows[i]
			lines[#lines + 1] = ("%s x%d  %s"):format(HG.ItemLabel(item.id) or ("#" .. item.id), item.count, HG.Money(item.value))
		end
	end
	ShowLines(lines)
	ShowActions({
		{ session.running and L.SESSION_PAUSE or L.SESSION_RESUME, function()
			HG.SessionPause()
			HG.RefreshHub()
		end },
		{ L.RESET_BUTTON, function()
			HG.SessionReset()
			HG.RefreshHub()
		end },
		{ L.SHARE_GUILD, function()
			HG.ShareSession("GUILD")
		end },
		{ L.SHARE_PARTY, function()
			HG.ShareSession("PARTY")
		end },
		{ L.SESSION_MINI, HG.ToggleSession },
	})
end

function render.ach()
	local L = HG.L
	local earned, total, points = HG.AchTotals()
	ShowLines({ L.ACH_COUNT:format(earned, total) .. "    |cffffd100" .. L.ACH_POINTS:format(points) .. "|r" })
	ShowActions({ { L.ACH_TEST, HG.TestAchievement } })

	local rows = HG.AchRows()
	local pages = math.max(1, math.ceil(#rows / ROWS_PER_PAGE))
	achPage = math.max(1, math.min(achPage, pages))
	local first = (achPage - 1) * ROWS_PER_PAGE
	for i = 1, ROWS_PER_PAGE do
		local data = rows[first + i]
		local row = AchRow(i)
		if data then
			local series = data.series
			row.series, row.tier = series, data.earned
			row.icon:SetTexture(series.icon)
			if data.earned > 0 then
				row.name:SetText(HG.AchName(series, data.earned))
				row.name:SetTextColor(1, 0.82, 0)
				row.icon:SetDesaturated(false)
			else
				row.name:SetText(HG.AchName(series, 1))
				row.name:SetTextColor(0.6, 0.6, 0.6)
				row.icon:SetDesaturated(true)
			end
			row.desc:SetText("|cff9a9a9a" .. data.category .. ":|r " .. HG.AchDesc(series, data.target))
			if data.earned >= data.total then
				row.progress:SetText("|cff48c75a" .. data.earned .. " / " .. data.total .. "|r")
				row.bar:SetMinMaxValues(0, 1)
				row.bar:SetValue(1)
			else
				local shown = math.min(data.value, data.threshold)
				row.progress:SetText(HG.AchAmount(series, shown) .. " / " .. HG.AchAmount(series, data.threshold))
				row.bar:SetMinMaxValues(0, data.threshold)
				row.bar:SetValue(shown)
			end
			if data.earned > 0 then
				row.guild:Show()
				row.party:Show()
			else
				row.guild:Hide()
				row.party:Hide()
			end
			row:Show()
		else
			row:Hide()
		end
	end
	hub.pager.text:SetText(achPage .. " / " .. pages)
	hub.pager.pages = pages
	hub.pager:Show()
end

function render.records()
	local lines = {}
	for _, pair in ipairs(HG.RecordLines()) do
		lines[#lines + 1] = pair[1] .. ":  |cffffd100" .. pair[2] .. "|r"
	end
	ShowLines(lines)
	ShowActions({})
end

function render.bags()
	ShowLines(HG.BagReport())
	-- Сумки пересчитываются при открытии раздела; кнопка — после того,
	-- как что-то продали, купили или обновили цены аукциона.
	ShowActions({ { HG.L.REFRESH, HG.RefreshHub } })
end

function render.next()
	ShowLines(HG.NextReport())
	ShowActions({})
end

------------------------------------------------------------------------
-- Окно
------------------------------------------------------------------------

local function Label(id)
	for _, page in ipairs(PAGES) do
		if page.id == id then
			return HG.L[page.label]
		end
	end
	return ""
end

function HG.RefreshHub()
	if not hub or not hub:IsShown() then
		return
	end
	hub.title:SetText("|cff6fcf97" .. HG.title .. "|r: " .. Label(current))
	HideAchRows()
	render[current]()
	for _, page in ipairs(PAGES) do
		local button = hub.nav[page.id]
		if page.id == current then
			button:LockHighlight()
		else
			button:UnlockHighlight()
		end
	end
end

local function Build()
	hub = CreateFrame("Frame", "HarvestMateHub", UIParent, "BackdropTemplate")
	hub:SetSize(WIDTH, HEIGHT)
	hub:SetPoint("CENTER")
	hub:SetFrameStrata("HIGH")
	hub:SetClampedToScreen(true)
	hub:SetMovable(true)
	hub:EnableMouse(true)
	hub:RegisterForDrag("LeftButton")
	hub:SetScript("OnDragStart", hub.StartMoving)
	hub:SetScript("OnDragStop", hub.StopMovingOrSizing)
	if hub.SetBackdrop then
		hub:SetBackdrop({
			bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark",
			edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
			edgeSize = 24,
			insets = { left = 6, right = 6, top = 6, bottom = 6 },
		})
	end
	-- Закрытие по Esc
	if UISpecialFrames then
		table.insert(UISpecialFrames, "HarvestMateHub")
	end

	hub.title = hub:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
	hub.title:SetPoint("TOPLEFT", hub, "TOPLEFT", LEFT, -20)

	local close = CreateFrame("Button", nil, hub, "UIPanelCloseButton")
	close:SetPoint("TOPRIGHT", hub, "TOPRIGHT", -4, -4)
	close:SetScript("OnClick", function()
		hub:Hide()
	end)

	-- Разделы слева
	hub.nav = {}
	for i, page in ipairs(PAGES) do
		local button = PanelButton(hub, NAV_WIDTH, HG.L[page.label], function()
			HG.OpenHub(page.id)
		end)
		button:SetPoint("TOPLEFT", hub, "TOPLEFT", 14, -20 - (i - 1) * 28)
		hub.nav[page.id] = button
	end
	local settings = PanelButton(hub, NAV_WIDTH, HG.L.NAV_SETTINGS, function()
		HG.OpenSettings()
	end)
	settings:SetPoint("BOTTOMLEFT", hub, "BOTTOMLEFT", 14, 14)
	hub.settings = settings

	local divider = hub:CreateTexture(nil, "ARTWORK")
	divider:SetColorTexture(1, 1, 1, 0.12)
	divider:SetSize(1, HEIGHT - 32)
	divider:SetPoint("TOPLEFT", hub, "TOPLEFT", NAV_WIDTH + 18, -16)

	hub.lines, hub.actions, hub.rows = {}, {}, {}

	-- Листание достижений
	hub.pager = CreateFrame("Frame", nil, hub)
	hub.pager:SetSize(140, 22)
	hub.pager:SetPoint("BOTTOMRIGHT", hub, "BOTTOMRIGHT", -16, 14)
	hub.pager.text = hub.pager:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	hub.pager.text:SetPoint("CENTER")
	hub.pager.prev = PanelButton(hub.pager, 30, "<", function()
		achPage = achPage > 1 and achPage - 1 or (hub.pager.pages or 1)
		HG.RefreshHub()
	end)
	hub.pager.prev:SetPoint("LEFT")
	hub.pager.next = PanelButton(hub.pager, 30, ">", function()
		achPage = achPage < (hub.pager.pages or 1) and achPage + 1 or 1
		HG.RefreshHub()
	end)
	hub.pager.next:SetPoint("RIGHT")

	-- Раздел сессии тикает раз в секунду
	local since = 0
	hub:SetScript("OnUpdate", function(_, delta)
		since = since + delta
		if since >= 1 then
			since = 0
			if current == "session" then
				HG.RefreshHub()
			end
		end
	end)
	hub:Hide()
end

-- Открыть окно на разделе (или на последнем открытом).
function HG.OpenHub(page)
	if not HG.db then
		return
	end
	if not hub then
		Build()
	end
	if page and render[page] then
		current = page
	end
	hub:Show()
	HG.RefreshHub()
end

function HG.ToggleHub()
	if hub and hub:IsShown() then
		hub:Hide()
	else
		HG.OpenHub()
	end
end

function HG.HubPage()
	return hub and hub:IsShown() and current or nil
end

HG.Listen("GATHER_LOOT", function()
	HG.RefreshHub()
end)
HG.Listen("ACHIEVEMENT", function()
	HG.RefreshHub()
end)
