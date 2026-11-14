local _, HG = ...

-- Счётчик сбора за сессию: сколько собрано, на какую сумму и сколько
-- выходит в час. Время идёт с первого сбора, есть пауза и сброс.
-- Кнопка «Что собрали» открывает окно с добычей (значки, как в сумках,
-- самое дорогое первым) и итогами по каждой профессии.
-- Данные живут до выхода из игры или перезагрузки интерфейса.

local PROFS = { "herb", "mine", "skin" }
local COLUMNS, CELL, GAP, LABEL = 6, 36, 8, 14

local session = { running = true, elapsed = 0, since = nil, gathers = 0, items = {}, profs = {} }
HG.session = session

local frame, details

local function Price(id)
	return HG.BestPrice(id) or 0
end

local Elapsed
function HG.SessionElapsed()
	return Elapsed()
end

Elapsed = function()
	local total = session.elapsed
	if session.running and session.since then
		total = total + (GetTime() - session.since)
	end
	return total
end

-- Стоимость собранного: аукцион после комиссии или торговец, что больше.
function HG.SessionValue()
	local value = 0
	for id, count in pairs(session.items) do
		value = value + Price(id) * count
	end
	return value
end

-- Собранные предметы, самое дорогое первым: { id, count, value }.
function HG.SessionRows()
	local rows = {}
	for id, count in pairs(session.items) do
		rows[#rows + 1] = { id = id, count = count, value = Price(id) * count }
	end
	table.sort(rows, function(a, b)
		if a.value ~= b.value then
			return a.value > b.value
		end
		return a.id < b.id
	end)
	return rows
end

-- Итог по профессии: сборов, выручка (или nil, если не собирали).
function HG.SessionProfession(prof)
	local stats = session.profs[prof]
	if not stats or stats.gathers == 0 then
		return nil
	end
	local value = 0
	for id, count in pairs(stats.items) do
		value = value + Price(id) * count
	end
	return stats.gathers, value
end

local function Clock(seconds)
	seconds = math.floor(seconds)
	local hours = math.floor(seconds / 3600)
	local minutes = math.floor(seconds / 60) % 60
	if hours > 0 then
		return ("%d:%02d:%02d"):format(hours, minutes, seconds % 60)
	end
	return ("%d:%02d"):format(minutes, seconds % 60)
end

-- Короткая сумма под значком: «1.2з», «35с», «80м».
local function ShortMoney(copper)
	local L = HG.L
	if copper >= 10000 then
		return ("|cffffd100%.1f%s|r"):format(copper / 10000, L.COIN_GOLD)
	elseif copper >= 100 then
		return ("|cffc7c7cf%d%s|r"):format(math.floor(copper / 100), L.COIN_SILVER)
	end
	return ("|cffeda55f%d%s|r"):format(math.floor(copper + 0.5), L.COIN_COPPER)
end

------------------------------------------------------------------------
-- Окно «Что собрали»
------------------------------------------------------------------------

local function ItemIcon(id)
	local getIcon = (C_Item and C_Item.GetItemIconByID) or _G.GetItemIcon
	local icon = getIcon and getIcon(id)
	if icon and not HG.Hidden(icon) then
		return icon
	end
	return "Interface\\Icons\\INV_Misc_QuestionMark"
end

local function StatRow(index)
	local row = details.stats[index]
	if not row then
		row = details:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		row:SetJustifyH("LEFT")
		details.stats[index] = row
	end
	return row
end

local function Cell(index)
	local cell = details.cells[index]
	if cell then
		return cell
	end
	cell = CreateFrame("Button", nil, details)
	cell:SetSize(CELL, CELL)
	cell.icon = cell:CreateTexture(nil, "ARTWORK")
	cell.icon:SetAllPoints()
	cell.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	cell.count = cell:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
	cell.count:SetPoint("BOTTOMRIGHT", cell, "BOTTOMRIGHT", -2, 2)
	cell.price = cell:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	cell.price:SetPoint("TOP", cell, "BOTTOM", 0, -1)
	cell:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
	cell:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		if GameTooltip.SetItemByID and self.id then
			GameTooltip:SetItemByID(self.id)
		end
		GameTooltip:AddLine(HG.L.SESSION_ITEM_TOTAL:format(self.amount or 0, HG.Money(self.worth or 0)), 1, 0.82, 0)
		GameTooltip:Show()
	end)
	cell:SetScript("OnLeave", function()
		GameTooltip:Hide()
	end)
	details.cells[index] = cell
	return cell
end

local function RefreshDetails()
	if not details or not details:IsShown() then
		return
	end
	local L = HG.L
	local y = -32

	-- Итоги по профессиям
	local used = 0
	for _, prof in ipairs(PROFS) do
		local gathers, value = HG.SessionProfession(prof)
		if gathers then
			used = used + 1
			local row = StatRow(used)
			row:SetText(L.SESSION_PROF_LINE:format(HG.ProfName(prof), gathers, HG.Money(value), HG.Money(value / gathers)))
			row:ClearAllPoints()
			row:SetPoint("TOPLEFT", details, "TOPLEFT", 12, y)
			row:Show()
			y = y - 16
		end
	end
	for i = used + 1, #details.stats do
		details.stats[i]:Hide()
	end

	-- Добыча значками, самое дорогое первым
	local rows = HG.SessionRows()
	if #rows == 0 then
		details.empty:Show()
		y = y - 18
	else
		details.empty:Hide()
		y = y - 6
	end
	local step = CELL + LABEL + GAP
	for i, item in ipairs(rows) do
		local cell = Cell(i)
		local column = (i - 1) % COLUMNS
		local line = math.floor((i - 1) / COLUMNS)
		cell:ClearAllPoints()
		cell:SetPoint("TOPLEFT", details, "TOPLEFT", 12 + column * (CELL + GAP), y - line * step)
		cell.icon:SetTexture(ItemIcon(item.id))
		cell.count:SetText(item.count)
		cell.price:SetText(ShortMoney(item.value))
		cell.id, cell.amount, cell.worth = item.id, item.count, item.value
		cell:Show()
	end
	for i = #rows + 1, #details.cells do
		details.cells[i]:Hide()
	end
	details:SetHeight(-y + math.ceil(#rows / COLUMNS) * step + 10)
end

local function Backdrop(target)
	if target.SetBackdrop then
		target:SetBackdrop({
			bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
			edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
			edgeSize = 12,
			insets = { left = 3, right = 3, top = 3, bottom = 3 },
		})
		target:SetBackdropColor(0, 0, 0, 0.8)
	end
end

local function BuildDetails()
	details = CreateFrame("Frame", "HarvestMateSessionLoot", frame, "BackdropTemplate")
	details:SetSize(24 + COLUMNS * CELL + (COLUMNS - 1) * GAP, 80)
	details:SetPoint("TOPLEFT", frame, "BOTTOMLEFT", 0, -2)
	details:EnableMouse(true)
	Backdrop(details)
	details.stats, details.cells = {}, {}
	details.title = details:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	details.title:SetPoint("TOPLEFT", details, "TOPLEFT", 12, -10)
	details.title:SetText("|cff6fcf97" .. HG.title .. "|r: " .. HG.L.SESSION_DETAILS)
	details.empty = details:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	details.empty:SetPoint("TOPLEFT", details, "TOPLEFT", 12, -32)
	details.empty:SetText(HG.L.SESSION_EMPTY)
	details:Hide()
end

local function ToggleDetails()
	if not details then
		BuildDetails()
	end
	if details:IsShown() then
		details:Hide()
	else
		details:Show()
		RefreshDetails()
	end
end

------------------------------------------------------------------------
-- Основное окно
------------------------------------------------------------------------

local function Refresh()
	if not frame or not frame:IsShown() then
		return
	end
	local L = HG.L
	local elapsed = Elapsed()
	local value = HG.SessionValue()
	frame.title:SetText("|cff6fcf97" .. HG.title .. "|r: " .. L.SESSION_TITLE .. "  |cffffffff" .. Clock(elapsed) .. "|r")
	frame.gathers:SetText(L.SESSION_GATHERS:format(session.gathers))
	frame.value:SetText(L.SESSION_VALUE:format(HG.Money(value)))
	-- Темп считаем после первой минуты, иначе цифра скачет.
	local rate = elapsed >= 60 and HG.Money(value / elapsed * 3600) or "-"
	frame.rate:SetText(L.SESSION_RATE:format(rate))
	frame.pause:SetText(session.running and L.SESSION_PAUSE or L.SESSION_RESUME)
end

-- Итог сессии одной строкой, без цветов: для чата.
function HG.SessionSummary()
	local L = HG.L
	local elapsed = Elapsed()
	local value = HG.SessionValue()
	local rate = elapsed >= 60 and HG.PlainMoney(value / elapsed * 3600) or "-"
	return L.SHARE_SESSION_MSG:format(Clock(elapsed), session.gathers, HG.PlainMoney(value), rate)
end

-- where: "GUILD" или "PARTY".
function HG.ShareSession(where)
	return HG.Share(HG.SessionSummary(), where)
end

local function Pause()
	if session.running then
		session.elapsed = Elapsed()
		session.since = nil
		session.running = false
	else
		session.running = true
		if session.gathers > 0 then
			session.since = GetTime()
		end
	end
	Refresh()
end

HG.SessionPause = Pause

function HG.SessionReset()
	session.running, session.elapsed, session.since = true, 0, nil
	session.gathers, session.items, session.profs = 0, {}, {}
	Refresh()
	RefreshDetails()
end

local function Line(anchor, font)
	local text = frame:CreateFontString(nil, "OVERLAY", font or "GameFontHighlightSmall")
	text:SetJustifyH("LEFT")
	if anchor then
		text:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -4)
	else
		text:SetPoint("TOPLEFT", frame, "TOPLEFT", 12, -10)
	end
	return text
end

local function PanelButton(width, onClick)
	local button = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
	button:SetSize(width, 20)
	button:SetScript("OnClick", onClick)
	return button
end

local function Build()
	frame = CreateFrame("Frame", "HarvestMateSession", UIParent, "BackdropTemplate")
	frame:SetSize(24 + COLUMNS * CELL + (COLUMNS - 1) * GAP, 156)
	frame:SetFrameStrata("MEDIUM")
	frame:SetClampedToScreen(true)
	frame:SetMovable(true)
	frame:EnableMouse(true)
	frame:RegisterForDrag("LeftButton")
	Backdrop(frame)
	local pos = HG.db.banner.session
	if type(pos) == "table" and type(pos.x) == "number" then
		frame:SetPoint("CENTER", UIParent, "CENTER", pos.x, pos.y)
	else
		frame:SetPoint("CENTER", UIParent, "CENTER", 320, 60)
	end
	frame:SetScript("OnDragStart", frame.StartMoving)
	frame:SetScript("OnDragStop", function(self)
		self:StopMovingOrSizing()
		local cx, cy = self:GetCenter()
		local ux, uy = UIParent:GetCenter()
		if cx and ux then
			HG.db.banner.session = { x = math.floor(cx - ux + 0.5), y = math.floor(cy - uy + 0.5) }
		end
	end)

	frame.title = Line(nil, "GameFontNormal")
	frame.gathers = Line(frame.title)
	frame.value = Line(frame.gathers)
	frame.rate = Line(frame.value)

	local half = (frame:GetWidth() - 20) / 2
	frame.more = PanelButton(frame:GetWidth() - 16, ToggleDetails)
	frame.more:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 8, 56)
	frame.more:SetText(HG.L.SESSION_DETAILS)

	-- Поделиться итогом сессии
	frame.guild = PanelButton(half, function()
		HG.ShareSession("GUILD")
	end)
	frame.guild:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 8, 32)
	frame.guild:SetText(HG.L.SHARE_GUILD)
	frame.party = PanelButton(half, function()
		HG.ShareSession("PARTY")
	end)
	frame.party:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -8, 32)
	frame.party:SetText(HG.L.SHARE_PARTY)

	frame.pause = PanelButton(half, Pause)
	frame.pause:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 8, 8)

	frame.reset = PanelButton(half, HG.SessionReset)
	frame.reset:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -8, 8)
	frame.reset:SetText(HG.L.RESET_BUTTON)

	local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
	close:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 2, 2)
	close:SetScript("OnClick", function()
		frame:Hide()
	end)

	local sinceUpdate = 0
	frame:SetScript("OnUpdate", function(_, delta)
		sinceUpdate = sinceUpdate + delta
		if sinceUpdate >= 1 then
			sinceUpdate = 0
			Refresh()
		end
	end)
	frame:Hide()
end

function HG.ToggleSession()
	if not HG.db then
		return
	end
	if not frame then
		Build()
	end
	if frame:IsShown() then
		frame:Hide()
	else
		frame:Show()
		Refresh()
		RefreshDetails()
	end
end

HG.commands.session = HG.ToggleSession

-- Каждый сбор с добычей: prof, ключ ресурса, { id -> штук }.
HG.Listen("GATHER_LOOT", function(prof, _, counts)
	if not session.running then
		return
	end
	if not session.since then
		session.since = GetTime()
	end
	session.gathers = session.gathers + 1
	local stats = session.profs[prof]
	if not stats then
		stats = { gathers = 0, items = {} }
		session.profs[prof] = stats
	end
	stats.gathers = stats.gathers + 1
	for id, count in pairs(counts) do
		session.items[id] = (session.items[id] or 0) + count
		stats.items[id] = (stats.items[id] or 0) + count
	end
	Refresh()
	RefreshDetails()
end)
