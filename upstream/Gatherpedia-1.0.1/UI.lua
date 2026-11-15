-- Gatherpedia: UI.lua
-- The main window: a dark-and-gold field guide with a profession sidebar,
-- search and filters, an icon grid with collection progress, a detail page,
-- "best spots for my level" suggestions, a Trainers page, and live session stats.
-- Built in Lua only, with Blizzard's own UI textures (no external art).

local ADDON_NAME, ns = ...

local UI = {}
ns.UI = UI

---------------------------------------------------------------------------
-- Layout constants
---------------------------------------------------------------------------

local WIDTH, HEIGHT = 800, 540
local SIDEBAR_W = 184
local MAIN_X = SIDEBAR_W + 16            -- left edge of the main area
local SIDEBAR_LIST_Y = -90              -- PROFESSIONS section header (below the dropdown)
local SIDEBAR_SEC_H = 16                -- section header height
-- Sidebar fit at HEIGHT 540: list starts at SIDEBAR_LIST_Y, session
-- sits at the bottom. With 4 profession rows, a 2 px gap, and 3 tool
-- rows (Trainers, Guides, Glimmer): 16 + 4*38 + 2 + 16 + 3*38 = 300,
-- and 540 - 12 - 136 - 90 = 302, so 2 px remain above This Session.
local SIDEBAR_ROW_H = 38                -- profession / tool row height
local SIDEBAR_TAB_Y = SIDEBAR_LIST_Y + SIDEBAR_SEC_H
local SIDEBAR_TAB_H = SIDEBAR_ROW_H
local SIDEBAR_SESS_H = 136              -- This Session dashboard
local SIDEBAR_SESS_PAD = 12
local ICON_RIM = "Interface\\AddOns\\Gatherpedia\\Media\\IconRim"
local SIDE_GRAIN = "Interface\\AddOns\\Gatherpedia\\Media\\SidebarGrain"
local BAR_GREEN = { 0.31, 0.67, 0.24 }
local BAR_ORANGE = { 0.82, 0.55, 0.16 }
-- Concept 2 parchment / leather-brown palette. Layout stays Concept 3.
local TH = ns.Theme
local TC = TH.C
local PARCHMENT = TC.side
local WELL = { TC.side[1], TC.side[2], TC.side[3], 0 }
local WELL_SELECTED = TC.goldFill
local DROP_BG = TC.button
local MUTED = TC.text2
local DIMMED = TC.text3
local MAIN_W = WIDTH - MAIN_X - 16
local COLS, ROWS = 4, 3
local PER_PAGE = COLS * ROWS
local CELL_W, CELL_H = 138, 98

local WHITE = "Interface\\Buttons\\WHITE8X8"
local GOLD = TC.gold
local GOLD_HEX = TH:Hex(TC.gold)
local MUTED_HEX = TH:Hex(TC.text3)

local FILTERS = {
    { key = "all",      label = "All" },
    { key = "can",      label = "Can gather" },
    { key = "skillups", label = "Skill-ups" },
    { key = "zone",     label = "This zone" },
}

UI.state = { prof = nil, page = {}, filter = "all", search = "", detail = nil, view = "book" }

---------------------------------------------------------------------------
-- Small widget helpers
---------------------------------------------------------------------------

local function Panel(parent, r, g, b, a, border)
    local f = CreateFrame("Frame", nil, parent)
    TH:Panel(f, TC.card, border and TC.line or nil, 8)
    return f
end

local function Text(parent, font, justify)
    local fs = parent:CreateFontString(nil, "OVERLAY", font or "GatherpediaFontHighlight")
    fs:SetJustifyH(justify or "LEFT")
    return fs
end


-- Gold-rimmed 32 px icon slot, matching the Concept 3 stone-frame sidebar.
local function IconSlot(parent)
    local slot = TH:RoundIcon(parent, 30)
    slot.fill = slot.bg
    slot.rim = slot.ring
    return slot
end

-- One sidebar row: recessed well, optional gold selection glow, 32 px
-- framed icon, title, optional rank/bar or subtitle.
function UI:CreateSidebarRow(parent, height)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(SIDEBAR_W - 16, height or SIDEBAR_ROW_H)
    TH:Panel(b, TC.side, nil, 6)
    -- Kept for older callers; selection is painted on the panel now.
    b.well = b:CreateTexture(nil, "BACKGROUND")
    b.well:SetAllPoints()
    b.well:SetColorTexture(0, 0, 0, 0)
    b.glow = CreateFrame("Frame", nil, b)
    b.glow:Hide()
    b.glowInner = CreateFrame("Frame", nil, b)
    b.glowInner:Hide()
    local slot = IconSlot(b)
    slot:SetPoint("LEFT", 5, 0)
    b.slot, b.icon, b.rim = slot, slot.icon, slot.rim
    b.label = Text(b, "GatherpediaFontHighlight")
    b.label:SetPoint("TOPLEFT", slot, "TOPRIGHT", 9, -2)
    b.label:SetPoint("RIGHT", b, "RIGHT", -52, 0)
    b.label:SetJustifyH("LEFT")
    if b.label.SetWordWrap then b.label:SetWordWrap(false) end
    -- Thin 4 px skill bar under the name, in the profession color.
    local track = CreateFrame("Frame", nil, b)
    track:SetHeight(4)
    track:SetPoint("BOTTOMLEFT", slot, "BOTTOMRIGHT", 9, 3)
    track:SetPoint("BOTTOMRIGHT", -6, 6)
    local bar = CreateFrame("StatusBar", nil, track)
    bar:SetAllPoints()
    bar:SetStatusBarTexture(TH.WHITE)
    bar:SetMinMaxValues(0, 1)
    bar:SetValue(0)
    -- Rank sits on the name line, right-aligned.
    b.rank = Text(b, "GatherpediaFontDisableSmall", "RIGHT")
    b.rank:SetPoint("TOPRIGHT", b, "TOPRIGHT", -6, -7)
    b.rank:SetTextColor(TC.text2[1], TC.text2[2], TC.text2[3])
    b.rankHold = b
    b.skillTrack, b.skillBar = track, bar
    if ns.Chrome and ns.Chrome.StyleSkillBar then
        ns.Chrome:StyleSkillBar(bar, { track = track })
    end
    b.sub = Text(b, "GatherpediaFontDisableSmall")
    b.sub:SetPoint("BOTTOMLEFT", slot, "BOTTOMRIGHT", 9, 3)
    TH:HoverPaint(b,
        function(btn) if not btn._gpSelected then TH:PanelColors(btn, TC.raised) end end,
        function(btn) if not btn._gpSelected then TH:PanelColors(btn, TC.side) end end)
    return b
end

function UI:PaintSidebarRow(b, selected, dim)
    if not b then return end
    b._gpSelected = selected and true or nil
    if selected then
        TH:PanelColors(b, TC.goldFill, TC.goldLine)
    else
        TH:PanelColors(b, TC.side)
    end
    if b.glow then b.glow:Hide() end
    if b.glowInner then b.glowInner:Hide() end
    if b.label then
        if selected then
            b.label:SetTextColor(TC.goldHi[1], TC.goldHi[2], TC.goldHi[3])
        elseif dim then
            b.label:SetTextColor(TC.text3[1], TC.text3[2], TC.text3[3])
        else
            b.label:SetTextColor(TC.text[1], TC.text[2], TC.text[3])
        end
    end
    if b.slot then
        local ring = b._ringColor or TC.goldLine
        TH:SetRoundIcon(b.slot, nil, ring, dim)
    end
end

local function SectionHeader(parent, caption)
    local h = TH:SectionLabel(parent, caption, true)
    h:SetSize(SIDEBAR_W - 16, SIDEBAR_SEC_H)
    h.label:ClearAllPoints()
    h.label:SetPoint("LEFT", 4, 0)
    return h
end


local function Bar(parent, width, height)
    local well = CreateFrame("Frame", nil, parent)
    well:SetSize(width, height)
    TH:Panel(well, TC.well, TC.line, math.min(6, math.floor(height / 2)))
    local bar = CreateFrame("StatusBar", nil, well)
    bar:SetPoint("TOPLEFT", 2, -2)
    bar:SetPoint("BOTTOMRIGHT", -2, 2)
    bar:SetStatusBarTexture(TH.WHITE)
    bar:SetMinMaxValues(0, 1)
    local hold = CreateFrame("Frame", nil, bar)
    hold:SetAllPoints(well)
    hold:SetFrameLevel((bar:GetFrameLevel() or 1) + 3)
    bar.text = Text(hold, "GatherpediaFontHighlightSmall", "CENTER")
    bar.text:SetPoint("CENTER", 0, 0)
    bar.well = well
    -- Callers place, show and hide the bar; do that to the well.
    bar.SetPoint = function(_, ...) well:SetPoint(...) end
    bar.ClearAllPoints = function() well:ClearAllPoints() end
    bar.Show = function() well:Show() end
    bar.Hide = function() well:Hide() end
    return bar
end

local function FadeIn(frame, duration)
    if not frame.fadeIn then
        local ag = frame:CreateAnimationGroup()
        local a = ag:CreateAnimation("Alpha")
        a:SetFromAlpha(0)
        a:SetToAlpha(1)
        a:SetDuration(duration or 0.15)
        a:SetSmoothing("OUT")
        ag:SetToFinalAlpha(true)
        frame.fadeIn = ag
    end
    frame.fadeIn:Stop()
    frame:SetAlpha(0)
    frame.fadeIn:Play()
end

-- Slide a panel in from the right while fading it in.
local function SlideIn(frame, anchor)
    if not frame.slideIn then
        local ag = frame:CreateAnimationGroup()
        local move = ag:CreateAnimation("Translation")
        move:SetOffset(-24, 0)
        move:SetDuration(0.18)
        move:SetSmoothing("OUT")
        local a = ag:CreateAnimation("Alpha")
        a:SetFromAlpha(0)
        a:SetToAlpha(1)
        a:SetDuration(0.18)
        ag:SetToFinalAlpha(true)
        ag:SetScript("OnFinished", function()
            frame:ClearAllPoints()
            frame:SetPoint(unpack(anchor))
        end)
        frame.slideIn = ag
    end
    frame.slideIn:Stop()
    frame:ClearAllPoints()
    local p, rel, rp, x, y = unpack(anchor)
    frame:SetPoint(p, rel, rp, x + 24, y)
    frame:Show()
    frame.slideIn:Play()
end

UI.widgets = { Panel = Panel, Text = Text, Bar = Bar, FadeIn = FadeIn }

local function IsToolView(view)
    return view == "trainers" or view == "glimmer" or view == "guides"
end

local function Accent(prof)
    local c = TH:Prof(prof).accent
    return c[1], c[2], c[3]
end

local function FormatDate(t)
    return t and date("%b %d, %Y", t) or "Not yet"
end

local function FormatDuration(seconds)
    seconds = math.floor(seconds)
    local h = math.floor(seconds / 3600)
    local m = math.floor((seconds % 3600) / 60)
    if h > 0 then return ("%dh %02dm"):format(h, m) end
    return ("%dm"):format(m)
end

---------------------------------------------------------------------------
-- Frame construction
---------------------------------------------------------------------------

function UI:Create()
    if self.frame then return self.frame end

    local f = CreateFrame("Frame", "GatherpediaFrame", UIParent, "BackdropTemplate")
    self.frame = f
    f:SetSize(WIDTH, HEIGHT)
    f:SetFrameStrata("HIGH")
    f:SetToplevel(true)
    f:SetClampedToScreen(true)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    -- Locked by default, like the world map. Options can unlock it.
    f:SetScript("OnDragStart", function(frame)
        if UI:IsLocked() then return end
        frame._gpDragging = true
        frame:StartMoving()
    end)
    f:SetScript("OnDragStop", function(frame)
        if not frame._gpDragging then return end
        frame._gpDragging = nil
        frame:StopMovingOrSizing()
        UI:SavePosition()
        -- A drag is a chosen position; do not snap back when the map closes.
        UI._mapDocked = false
    end)
    if ns.Chrome and ns.Chrome.ApplyWindow then
        ns.Chrome:ApplyWindow(f)
    else
        f:SetBackdrop({
            bgFile = WHITE,
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            edgeSize = 16,
            insets = { left = 4, right = 4, top = 4, bottom = 4 },
        })
        f:SetBackdropColor(0.055, 0.05, 0.06, 0.97)
        f:SetBackdropBorderColor(GOLD[1], GOLD[2], GOLD[3], 1)
    end
    f:Hide()
    tinsert(UISpecialFrames, "GatherpediaFrame") -- Escape closes it

    f:SetScript("OnShow", function()
        FadeIn(f, 0.15)
        UI:StartTicker()
        UI:Refresh()
    end)
    f:SetScript("OnHide", function() UI:StopTicker() end)

    -- Sidebar background and the accent line along the header.
    local side = f:CreateTexture(nil, "BACKGROUND", nil, 1)
    local inset = 1
    side:SetPoint("TOPLEFT", inset, -inset)
    side:SetPoint("BOTTOMLEFT", inset, inset)
    side:SetWidth(SIDEBAR_W)
    side:SetColorTexture(TC.side[1], TC.side[2], TC.side[3], 1)
    -- The main page sits on its own, slightly lighter ground.
    local mainBg = f:CreateTexture(nil, "BACKGROUND", nil, 1)
    mainBg:SetPoint("TOPLEFT", side, "TOPRIGHT", 1, 0)
    mainBg:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -inset, inset)
    mainBg:SetColorTexture(TC.main[1], TC.main[2], TC.main[3], 1)
    self.mainBg = mainBg
    local sideEdge = f:CreateTexture(nil, "BORDER")
    sideEdge:SetPoint("TOPLEFT", side, "TOPRIGHT", 0, 0)
    sideEdge:SetPoint("BOTTOMLEFT", side, "BOTTOMRIGHT", 0, 0)
    sideEdge:SetWidth(1)
    sideEdge:SetColorTexture(TC.line[1], TC.line[2], TC.line[3], 1)

    self.accentLine = f:CreateTexture(nil, "ARTWORK")
    self.accentLine:SetPoint("TOPLEFT", f, "TOPLEFT", MAIN_X, -66)
    self.accentLine:SetSize(MAIN_W, 1)

    -- Sidebar brand: the square gold G (36 px) beside Gatherpedia and
    -- the Field guide line, inside the frame. No hanging portrait ring.
    -- The metal strip still carries the centered Gatherpedia title.
    if ns.Chrome then
        self.banner = ns.Chrome:AddTitleBanner(f, "Gatherpedia")
        self.closeButton = ns.Chrome:MakeCloseButton(f, function() UI:Hide() end)
        self.settingsButton = self:MakeSettingsButton(self.banner, self.closeButton)
    else
        local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
        close:SetPoint("TOPRIGHT", f, "TOPRIGHT", -2, -2)
        close:SetScript("OnClick", function() UI:Hide() end)
        self.closeButton = close
    end
    local emblem = f:CreateTexture(nil, "ARTWORK")
    emblem:SetSize(36, 36)
    emblem:SetPoint("TOPLEFT", f, "TOPLEFT", 16, -14)
    emblem:SetTexture(ns.ICON_HEADER)
    self.portrait = emblem
    local brand = Text(f, "GatherpediaFontNormal")
    brand:SetPoint("TOPLEFT", emblem, "TOPRIGHT", 8, 1)
    brand:SetText("Gatherpedia")
    TH:Font(brand, "display", 16, "text")
    if brand.SetWordWrap then brand:SetWordWrap(false) end
    self.brandTitle = brand
    local subtitle = Text(f, "GatherpediaFontDisableSmall")
    subtitle:SetPoint("TOPLEFT", brand, "BOTTOMLEFT", 0, -1)
    subtitle:SetText("Field guide \194\183 v" .. ns.VERSION)
    self.subtitle = subtitle

    self:CreateSidebar(f)
    self:CreateHeader(f)
    self:CreateListPage(f)
    self:CreateDetailPage(f)
    self:CreateEmptyState(f)
    self:CreateTrainersPage(f)
    self:CreateGuidesPage(f)
    self:CreateGlimmerPage(f)
    self:RestorePosition()
    self:WatchMapFrame()
    self:ApplyLock()
    return f
end

-- Gear on the title strip, left of the close button. Opens the options.
function UI:MakeSettingsButton(strip, closeButton)
    if not strip then return end
    local b = CreateFrame("Button", nil, strip)
    b:SetSize(20, 20)
    if closeButton then
        b:SetPoint("RIGHT", closeButton, "LEFT", -4, 0)
    else
        b:SetPoint("RIGHT", strip, "RIGHT", -28, 0)
    end
    b:SetFrameLevel((strip:GetFrameLevel() or 1) + 6)
    TH:SkinButton(b, "quiet")
    local icon = b:CreateTexture(nil, "ARTWORK")
    icon:SetSize(12, 12)
    icon:SetPoint("CENTER")
    icon:SetTexture("Interface\\AddOns\\Gatherpedia\\Media\\Gear")
    icon:SetVertexColor(TC.text2[1], TC.text2[2], TC.text2[3], 1)
    b.icon = icon
    TH:HoverPaint(b,
        function(btn)
            btn._gpHover = true; TH:PaintButton(btn)
            btn.icon:SetVertexColor(TC.goldHi[1], TC.goldHi[2], TC.goldHi[3], 1)
        end,
        function(btn)
            btn._gpHover = nil; TH:PaintButton(btn)
            btn.icon:SetVertexColor(TC.text2[1], TC.text2[2], TC.text2[3], 1)
        end)
    b:SetScript("OnClick", function()
        if ns.Options and ns.Options.Toggle then ns.Options:Toggle() end
    end)
    b:SetScript("OnEnter", function(btn)
        if not GameTooltip then return end
        GameTooltip:SetOwner(btn, "ANCHOR_BOTTOM")
        GameTooltip:AddLine("Settings")
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function()
        if GameTooltip and GameTooltip.Hide then GameTooltip:Hide() end
    end)
    return b
end

function UI:IsLocked()
    local o = ns.db and ns.db.options
    return not (o and o.windowUnlocked)
end

function UI:ApplyLock()
    if self.frame and self.frame.SetMovable then
        self.frame:SetMovable(not self:IsLocked())
    end
end

function UI:SetLocked(locked)
    if ns.db and ns.db.options then ns.db.options.windowUnlocked = not locked end
    self:ApplyLock()
    if locked then self:SnapHome() end
end

---------------------------------------------------------------------------
-- Sidebar: profession tabs and session stats
---------------------------------------------------------------------------

function UI:CreateSidebar(f)
    -- Profession scope dropdown: left column only, under the title block.
    local dd = CreateFrame("Button", "GatherpediaProfDrop", f, "BackdropTemplate")
    dd:SetSize(SIDEBAR_W - 16, 24)
    dd:SetPoint("TOPLEFT", f, "TOPLEFT", 13, -62)
    TH:SkinButton(dd, "quiet")
    dd.label = Text(dd, "GatherpediaFontHighlightSmall")
    dd.label:SetPoint("LEFT", 8, 0)
    dd.label:SetPoint("RIGHT", dd, "RIGHT", -22, 0)
    dd.label:SetJustifyH("LEFT")
    dd.arrow = dd:CreateTexture(nil, "ARTWORK")
    dd.arrow:SetSize(12, 12)
    dd.arrow:SetPoint("RIGHT", -6, 0)
    dd.arrow:SetTexture("Interface\\AddOns\\Gatherpedia\\Media\\DropdownArrow")
    dd:SetScript("OnClick", function() UI:ToggleProfMenu() end)
    self.profDrop = dd
    self:RefreshProfDrop()

    self.profHeader = SectionHeader(f, "PROFESSIONS")
    self.toolsHeader = SectionHeader(f, "TOOLS")

    self.tabs = {}
    for i = 1, #ns.PROFESSIONS do
        local b = self:CreateSidebarRow(f, SIDEBAR_ROW_H)
        b:SetScript("OnClick", function(btn) UI:SelectProfession(btn.prof) end)
        self.tabs[i] = b
    end

    local t = self:CreateSidebarRow(f, SIDEBAR_ROW_H)
    t.icon:SetTexture("Interface\\Icons\\INV_Misc_Book_09")
    t.label:SetText("Trainers")
    t.rank:Hide()
    t.skillTrack:Hide()
    t.sub:Hide()
    -- Center the title vertically when there is no subtitle or bar.
    t.label:ClearAllPoints()
    t.label:SetPoint("LEFT", t.slot, "RIGHT", 8, 0)
    t.label:SetPoint("RIGHT", t, "RIGHT", -8, 0)
    t:SetScript("OnClick", function() UI:ShowTrainers() end)
    self.trainersTab = t

    local g = self:CreateSidebarRow(f, SIDEBAR_ROW_H)
    g.icon:SetTexture("Interface\\Icons\\INV_Misc_Book_11")
    g.label:SetText("Guides")
    g.rank:Hide()
    g.skillTrack:Hide()
    g.sub:SetText("Leveling notes")
    g.sub:Show()
    g.label:ClearAllPoints()
    g.label:SetPoint("TOPLEFT", g.slot, "TOPRIGHT", 8, -1)
    g.label:SetPoint("RIGHT", g, "RIGHT", -8, 0)
    g:SetScript("OnClick", function() UI:ShowGuides() end)
    self.guidesTab = g

    if ns.SparklesUI then
        self.sparklesTab = ns.SparklesUI:Attach(f)
    end

    -- Session dashboard at the bottom of the sidebar (hover or right-click for options).
    local box = ns.SessionUI:CreateBox(f, SIDEBAR_W - 16, SIDEBAR_SESS_H, false)
    box:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 13, SIDEBAR_SESS_PAD)
    self.sessionBox = box
end

function UI:UpdateSidebar()
    local visible = ns:GetVisibleProfessions()
    local f = self.frame
    local y = SIDEBAR_LIST_Y
    if self.profHeader then
        self.profHeader:ClearAllPoints()
        self.profHeader:SetPoint("TOPLEFT", f, "TOPLEFT", 13, y)
        self.profHeader:Show()
        y = y - SIDEBAR_SEC_H
    end
    for i, b in ipairs(self.tabs) do
        local key = visible[i]
        b.prof = key
        if key then
            local def = ns.professions[key]
            b:ClearAllPoints()
            b:SetPoint("TOPLEFT", f, "TOPLEFT", 13, y)
            b.icon:SetTexture(def.icon)
            b._ringColor = TH:Prof(key).line
            b.label:SetText(def.label)
            local learned = ns.learned[key]
            local selected = (key == self.state.prof) and not IsToolView(self.state.view)
            if ns.Chrome and ns.Chrome.SetSkillBarProfession then
                ns.Chrome:SetSkillBarProfession(b.skillBar, key)
            end
            -- The 10 px sidebar bar is too short for "Herbalism 125/150";
            -- the name already sits above, so the bar shows the rank only.
            if learned and learned.max and learned.max > 0 then
                b.rank:SetText(("%d / %d"):format(learned.rank, learned.max))
                b.rank:SetTextColor(TC.text2[1], TC.text2[2], TC.text2[3])
                b.rank:Show()
                b.skillTrack:Show()
                b.skillBar:SetMinMaxValues(0, learned.max)
                b.skillBar:SetValue(learned.rank)
                b.sub:Hide()
                if b.icon.SetDesaturated then b.icon:SetDesaturated(false) end
                self:PaintSidebarRow(b, selected, false)
            else
                b.rank:SetText("Not learned")
                b.rank:SetTextColor(TC.text3[1], TC.text3[2], TC.text3[3])
                b.rank:Show()
                b.skillTrack:Hide()
                b.skillBar:SetMinMaxValues(0, 1)
                b.skillBar:SetValue(0)
                b.sub:Hide()
                if b.icon.SetDesaturated then b.icon:SetDesaturated(true) end
                self:PaintSidebarRow(b, selected, true)
            end
            b:Show()
            y = y - SIDEBAR_ROW_H
        else
            b:Hide()
        end
    end
    y = y - 2
    if self.toolsHeader then
        self.toolsHeader:ClearAllPoints()
        self.toolsHeader:SetPoint("TOPLEFT", f, "TOPLEFT", 13, y)
        self.toolsHeader:Show()
        y = y - SIDEBAR_SEC_H
    end
    if self.trainersTab then
        self.trainersTab:ClearAllPoints()
        self.trainersTab:SetPoint("TOPLEFT", f, "TOPLEFT", 13, y)
        local on = self.state.view == "trainers"
        self:PaintSidebarRow(self.trainersTab, on, false)
        self.trainersTab:Show()
        y = y - SIDEBAR_ROW_H
    end
    if self.guidesTab then
        self.guidesTab:ClearAllPoints()
        self.guidesTab:SetPoint("TOPLEFT", f, "TOPLEFT", 13, y)
        self:PaintSidebarRow(self.guidesTab, self.state.view == "guides", false)
        self.guidesTab:Show()
        y = y - SIDEBAR_ROW_H
    end
    if self.sparklesTab then
        self.sparklesTab:ClearAllPoints()
        self.sparklesTab:SetPoint("TOPLEFT", f, "TOPLEFT", 13, y)
        self.sparklesTab:Show()
        if ns.SparklesUI then ns.SparklesUI:RefreshTab() end
    end
    self:UpdateSession()
end

function UI:UpdateSession()
    if ns.SessionUI then ns.SessionUI:UpdateAll() end
end

function UI:StartTicker()
    if self.ticker or not C_Timer.NewTicker then return end
    self.ticker = C_Timer.NewTicker(5, function() UI:UpdateSession() end)
end

function UI:StopTicker()
    if self.ticker then
        self.ticker:Cancel()
        self.ticker = nil
    end
end

---------------------------------------------------------------------------
-- Header: profession title, skill bar, collection bar
---------------------------------------------------------------------------

function UI:CreateHeader(f)
    local h = CreateFrame("Frame", nil, f)
    h:SetPoint("TOPLEFT", f, "TOPLEFT", MAIN_X, -14)
    h:SetSize(MAIN_W - 30, 48)
    self.header = h

    self.profTitle = Text(h, "GatherpediaFontTitle")
    self.profTitle:SetPoint("TOPLEFT", 0, -2)

    if ns.Chrome and ns.Chrome.MakeSkillBar then
        self.skillBar = ns.Chrome:MakeSkillBar(h, 240, 18)
    else
        self.skillBar = Bar(h, 240, 18)
    end
    self.skillBar:SetPoint("TOPLEFT", self.profTitle, "BOTTOMLEFT", 2, -4)

    -- One-click Start/Stop route chip, always visible in the header.
    -- The label names the suggested route so the player can see what
    -- will start. A small arrow beside it opens a zone/nearby picker.
    -- Same chip language as Closest and the profession filters; no new box.

    local routeDrop = CreateFrame("Button", nil, h, "BackdropTemplate")
    routeDrop:SetSize(24, 26)
    routeDrop:SetPoint("TOPRIGHT", h, "TOPRIGHT", 0, -2)
    TH:SkinButton(routeDrop, "quiet")
    routeDrop.arrow = routeDrop:CreateTexture(nil, "ARTWORK")
    routeDrop.arrow:SetSize(10, 10)
    routeDrop.arrow:SetPoint("CENTER")
    routeDrop.arrow:SetTexture("Interface\\AddOns\\Gatherpedia\\Media\\DropdownArrow")
    routeDrop:SetScript("OnClick", function()
        UI:ToggleRoutePicker()
    end)
    routeDrop:SetScript("OnEnter", function(b)
        if not GameTooltip then return end
        GameTooltip:SetOwner(b, "ANCHOR_BOTTOM")
        GameTooltip:AddLine("Choose a route in this zone, or a nearby one.")
        GameTooltip:Show()
    end)
    routeDrop:SetScript("OnLeave", function()
        if GameTooltip and GameTooltip.Hide then GameTooltip:Hide() end
    end)
    self.routeDrop = routeDrop

    local routeBtn = CreateFrame("Button", nil, h, "BackdropTemplate")
    routeBtn:SetSize(200, 26)
    routeBtn:SetPoint("TOPRIGHT", routeDrop, "TOPLEFT", -4, 0)
    TH:SkinButton(routeBtn, "quiet")
    routeBtn.label = Text(routeBtn, "GatherpediaFontHighlightSmall", "CENTER")
    routeBtn.label:SetPoint("LEFT", 6, 0)
    routeBtn.label:SetPoint("RIGHT", -6, 0)
    if routeBtn.label.SetWordWrap then routeBtn.label:SetWordWrap(false) end
    routeBtn.label:SetText("Start route")
    routeBtn:SetScript("OnClick", function()
        if ns.ToggleZoneRoute then ns.ToggleZoneRoute() end
    end)
    routeBtn:SetScript("OnEnter", function(b)
        if not GameTooltip then return end
        GameTooltip:SetOwner(b, "ANCHOR_BOTTOM")
        GameTooltip:AddLine(b.label and b.label:GetText() or "Start route")
        GameTooltip:Show()
    end)
    routeBtn:SetScript("OnLeave", function()
        if GameTooltip and GameTooltip.Hide then GameTooltip:Hide() end
    end)
    self.routeChip = routeBtn

    self.collectBar = Bar(h, 190, 14)
    self.collectBar:SetPoint("TOPRIGHT", routeDrop, "BOTTOMRIGHT", 0, -4)
    self.collectBar:SetStatusBarColor(TC.gold[1], TC.gold[2], TC.gold[3])
    local label = Text(h, "GatherpediaFontLabel", "RIGHT")
    label:SetPoint("RIGHT", self.collectBar.well, "LEFT", -8, 0)
    label:SetText("COLLECTION")
    self.collectLabel = label

    -- Closest lives in the title band, to the left of Start/Stop route,
    -- so it never overlaps the list or the scrollbar.
    local closest = CreateFrame("Button", nil, h, "BackdropTemplate")
    closest:SetSize(80, 22)
    closest:SetPoint("TOPRIGHT", routeBtn, "TOPLEFT", -6, 0)

    TH:SkinButton(closest, "quiet")

    closest.label = Text(closest, "GatherpediaFontHighlightSmall", "CENTER")
    closest.label:SetPoint("CENTER")
    closest.label:SetText("Closest")
    closest:SetScript("OnClick", function()
        if ns.TrainersUI then ns.TrainersUI:FindClosest() end
    end)
    closest:SetScript("OnEnter", function(b)
        if GameTooltip then
            GameTooltip:SetOwner(b, "ANCHOR_BOTTOM")
            GameTooltip:AddLine("Find the nearest trainer.")
            GameTooltip:Show()
        end
    end)
    closest:SetScript("OnLeave", function()
        if GameTooltip and GameTooltip.Hide then GameTooltip:Hide() end
    end)
    closest:Hide()
    self.closestChip = closest
end

function UI:UpdateRouteToggle()
    local b = self.routeChip
    if not b then return end
    local running = ns.Arrow and ns.Arrow.IsActive and ns.Arrow:IsActive()
    local zone = ns.PlayerZoneName and ns.PlayerZoneName()
    local text
    if running then
        local name
        if ns.Arrow.active and ns.Arrow.active.label then
            name = ns.Arrow.active.label
        elseif ns.Guides and ns.Guides.RouteName and ns.Arrow.active then
            name = ns.Guides:RouteName(ns.Arrow.active.spot)
        end
        text = "Stop: " .. (name or "route")
    else
        local suggest = ns.RouteSuggestText and ns.RouteSuggestText(zone)
        if suggest then
            text = "Start: " .. suggest
        elseif zone then
            text = "No route for " .. zone .. " yet"
        else
            text = "No route yet"
        end
    end
    if b.label then
        b.label:SetText(text)
        local tw = (b.label.GetStringWidth and b.label:GetStringWidth()) or 120
        b:SetWidth(math.max(130, math.min(300, tw + 20)))
    end
    -- Running: gold outline. Idle: quiet.
    TH:PaintButton(b, running and "selected" or "quiet")
    TH:PaintButton(self.routeDrop, running and "selected" or "quiet")
end

function UI:ToggleRoutePicker()
    local owner = self.routeDrop or self.routeChip
    if not owner or not ns.Menu then return end
    if ns.Menu:IsOpen() and ns.Menu.owner == owner then
        ns.Menu:Close()
        return
    end
    self:OpenRoutePicker()
end

-- /gp route and the header arrow open this picker so the player can see
-- the routes in the current zone, then nearby ones, before starting one.
function UI:OpenRoutePicker()
    self:Create()
    if not self.frame or not self.frame:IsShown() then
        self:Show()
    end
    local owner = self.routeDrop or self.routeChip
    if not owner or not ns.Menu then return end
    if ns.Menu.Init then ns.Menu:Init() end
    local zone = ns.PlayerZoneName and ns.PlayerZoneName()
    local items = (ns.Guides and ns.Guides.RoutePickerItems and ns.Guides:RoutePickerItems(zone)) or {}
    if #items == 0 then
        items = { { kind = "info", text = zone and ("No route for " .. zone .. " yet") or "No route for this zone yet" } }
    end
    ns.Menu:Open(owner, items, { below = true })
end

function UI:UpdateHeader(entries)
    self:UpdateRouteToggle()
    if self.closestChip then
        local onTrainers = self.state.view == "trainers"
        -- The Trainers page shows its own Nearest card now.
        self.closestChip:Hide()
    end
    if IsToolView(self.state.view) then
        local title = (self.state.view == "glimmer" and "Glimmer")
            or (self.state.view == "guides" and "Guides")
            or "Trainers"
        self.profTitle:SetText(title)
        self.profTitle:SetTextColor(TC.text[1], TC.text[2], TC.text[3])
        self.accentLine:SetColorTexture(TC.line[1], TC.line[2], TC.line[3], 1)
        self.skillBar:Hide()
        self.collectBar:Hide()
        if self.collectLabel then self.collectLabel:Hide() end
        return
    end
    self.skillBar:Show()
    self.collectBar:Show()
    if self.collectLabel then self.collectLabel:Show() end
    local prof = self.state.prof
    local def = ns.professions[prof]
    local r, g, b = Accent(prof)
    self.profTitle:SetText(def.label)
    self.profTitle:SetTextColor(TC.text[1], TC.text[2], TC.text[3])
    self.accentLine:SetColorTexture(r, g, b, 0.55)

    local learned = ns.learned[prof]
    if ns.Chrome and ns.Chrome.SetSkillBarProfession then
        ns.Chrome:SetSkillBarProfession(self.skillBar, prof)
    end
    if learned and learned.max > 0 then
        self.skillBar:SetMinMaxValues(0, learned.max)
        self.skillBar:SetValue(learned.rank)
        if ns.Chrome and ns.Chrome.SetSkillBarLabel then
            ns.Chrome:SetSkillBarLabel(self.skillBar, ("%s %d/%d"):format(def.label, learned.rank, learned.max), false)
        else
            self.skillBar.text:SetText(("%s %d/%d"):format(def.label, learned.rank, learned.max))
            self.skillBar.text:SetTextColor(1, 1, 1)
        end
    else
        self.skillBar:SetMinMaxValues(0, 1)
        self.skillBar:SetValue(0)
        if ns.Chrome and ns.Chrome.SetSkillBarLabel then
            ns.Chrome:SetSkillBarLabel(self.skillBar, "Not learned", true)
        else
            self.skillBar.text:SetText("Not learned")
            self.skillBar.text:SetTextColor(0.70, 0.66, 0.56)
        end
    end

    local have, total = 0, 0
    for _, e in ipairs(entries) do
        if ns:IsNodeEntry(e) then
            total = total + 1
            if e.id and ns:GetTotalCount(e.id) > 0 then have = have + 1 end
        end
    end
    self.collectBar:SetMinMaxValues(0, math.max(total, 1))
    self.collectBar:SetValue(have)
    self.collectBar.text:SetText(("%d of %d gathered"):format(have, total))
end

---------------------------------------------------------------------------
-- List page: search, filters, grid, paging, best spots
---------------------------------------------------------------------------

function UI:CreateListPage(f)
    local list = CreateFrame("Frame", nil, f)
    list:SetPoint("TOPLEFT", f, "TOPLEFT", MAIN_X, -76)
    list:SetSize(MAIN_W, HEIGHT - 76 - 12)
    self.list = list

    -- Search box (Blizzard's SearchBoxTemplate if available).
    local ok, search = pcall(CreateFrame, "EditBox", "GatherpediaSearchBox", list, "SearchBoxTemplate")
    if not ok or not search then
        search = CreateFrame("EditBox", "GatherpediaSearchBox", list, "InputBoxTemplate")
    end
    search:SetSize(170, 30)
    search:SetPoint("TOPLEFT", 4, -1)
    search:SetAutoFocus(false)
    -- Hide the template's own art and sit the box in a themed well.
    do
        local name = search.GetName and search:GetName()
        for _, key in ipairs({ "Left", "Middle", "Right", "Mid" }) do
            local t = search[key] or (name and _G[name .. key])
            if t and t.Hide then t:Hide(); if t.SetAlpha then t:SetAlpha(0) end end
        end
        local well = CreateFrame("Frame", nil, search)
        well:SetPoint("TOPLEFT", -4, 0)
        well:SetPoint("BOTTOMRIGHT", 0, 0)
        well:SetFrameLevel(math.max(0, (search:GetFrameLevel() or 1) - 1))
        TH:Panel(well, TC.well, TC.line, 8)
        search._gpWell = well
        if search.SetTextInsets then search:SetTextInsets(search.searchIcon and 18 or 6, 18, 0, 0) end
        if search.SetFontObject then search:SetFontObject("GatherpediaFontHighlightSmall") end
        search:HookScript("OnEditFocusGained", function() TH:PanelColors(well, TC.well, TC.goldLine) end)
        search:HookScript("OnEditFocusLost", function() TH:PanelColors(well, TC.well, TC.line) end)
    end
    search:SetMaxLetters(40)
    if not search.Instructions then
        local hint = Text(search, "GatherpediaFontDisableSmall")
        hint:SetPoint("LEFT", 4, 0)
        hint:SetText("Search herbs, ores, fish...")
        search.hint = hint
    else
        search.Instructions:SetText("Search herbs, ores, fish...")
    end
    search:HookScript("OnTextChanged", function(box)
        local text = box:GetText() or ""
        if box.hint then box.hint:SetShown(text == "") end
        UI.state.search = strtrim(text):lower()
        UI.state.page[UI.state.prof or ""] = 1
        UI:RefreshList()
    end)
    search:SetScript("OnEscapePressed", function(box) box:ClearFocus() end)
    search:SetScript("OnEnterPressed", function(box) box:ClearFocus() end)
    self.search = search

    -- Filters: one segmented control beside the search box.
    self.chips = {}
    local seg = CreateFrame("Frame", nil, list)
    seg:SetHeight(32)
    seg:SetPoint("LEFT", search, "RIGHT", 10, 0)
    TH:Panel(seg, TC.well, TC.line, 8)
    self.filterSeg = seg
    local prev
    local segX = 3
    for i, info in ipairs(FILTERS) do
        local chip = CreateFrame("Button", nil, seg)
        local w = (info.key == "all") and 52 or 90
        chip:SetSize(w, 26)
        chip:SetPoint("LEFT", seg, "LEFT", segX, 0)
        segX = segX + w + 2
        chip.label = Text(chip, "GatherpediaFontHighlightSmall", "CENTER")
        TH:SkinButton(chip, "segment")
        chip.label:SetPoint("CENTER")
        chip.label:SetText(info.label)
        chip.key = info.key
        chip:SetScript("OnClick", function(btn)
            UI.state.filter = btn.key
            UI.state.page[UI.state.prof or ""] = 1
            UI:RefreshList()
        end)
        self.chips[i] = chip
        prev = chip
    end
    seg:SetWidth(segX + 1)

    -- Grid cells.
    self.cells = {}
    for i = 1, PER_PAGE do
        local col = (i - 1) % COLS
        local row = math.floor((i - 1) / COLS)
        local c = CreateFrame("Button", nil, list, "BackdropTemplate")
        c:SetSize(CELL_W, CELL_H)
        c:SetPoint("TOPLEFT", list, "TOPLEFT", 4 + col * (CELL_W + 8), -40 - row * (CELL_H + 8))
        if TH then
            TH:Panel(c, TC.card, TC.line, 8)
            TH:HoverPaint(c,
                function(cell) TH:PanelColors(cell, TC.raised, TC.goldLine) end,
                function(cell) TH:PanelColors(cell, TC.card, TC.line) end)
        else
            c:SetBackdrop({ bgFile = WHITE, edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 10,
                insets = { left = 2, right = 2, top = 2, bottom = 2 } })
            c:SetBackdropColor(1, 1, 1, 0.035)
            c:SetBackdropBorderColor(GOLD[1], GOLD[2], GOLD[3], 0.18)
        end
        c:RegisterForClicks("LeftButtonUp")

        -- Rounded icon frame. Its border shows the skill-up color; the old
        -- SetColorTexture calls are routed to it so paint code stays simple.
        local frameIcon = CreateFrame("Frame", nil, c)
        -- Three bands so nothing overlaps: labels on top, icon, then name.
        frameIcon:SetSize(40, 40)
        frameIcon:SetPoint("TOP", 0, -22)
        TH:Panel(frameIcon, TC.well, TC.line2, 7)
        frameIcon.SetColorTexture = function(self, r, g, b, a)
            TH:PanelColors(self, TC.well, { r, g, b }, 1, a or 1)
        end
        c.iconBorder = frameIcon
        c.icon = frameIcon:CreateTexture(nil, "ARTWORK")
        c.icon:SetPoint("TOPLEFT", 3, -3)
        c.icon:SetPoint("BOTTOMRIGHT", -3, 3)
        c.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
        c.mystery = Text(frameIcon, "GatherpediaFontTitle", "CENTER")
        c.mystery:SetPoint("CENTER", c.icon)
        c.mystery:SetText("?")
        c.count = Text(frameIcon, "NumberFontNormal", "RIGHT")
        c.count:SetPoint("BOTTOMRIGHT", c.icon, "BOTTOMRIGHT", 1, 1)
        c.skill = Text(c, "GatherpediaFontLabel")
        c.skill:SetPoint("TOPLEFT", 8, -7)
        c.skill:SetPoint("RIGHT", c, "CENTER", 14, 0)
        if c.skill.SetWordWrap then c.skill:SetWordWrap(false) end
        c.tag = Text(c, "GatherpediaFontLabel", "RIGHT")
        c.tag:SetPoint("TOPRIGHT", -8, -7)
        c.tag:SetPoint("LEFT", c, "CENTER", 16, 0)
        if c.tag.SetWordWrap then c.tag:SetWordWrap(false) end
        c.name = Text(c, "GatherpediaFontHighlightSmall", "CENTER")
        c.name:SetPoint("TOP", c.iconBorder, "BOTTOM", 0, -4)
        c.name:SetWidth(CELL_W - 10)
        c.name:SetHeight(26)
        c.name:SetJustifyV("TOP")

        local hl = c:CreateTexture(nil, "HIGHLIGHT")
        hl:SetPoint("TOPLEFT", 3, -3)
        hl:SetPoint("BOTTOMRIGHT", -3, 3)
        hl:SetColorTexture(1, 0.85, 0.4, 0)

        c:SetScript("OnClick", function(cell)
            if not cell.entry then return end
            if IsModifiedClick and IsModifiedClick("CHATLINK") then
                local link = ns.GetItemLink(cell.entry)
                if link and ChatEdit_InsertLink then ChatEdit_InsertLink(link) end
                return
            end
            UI:ShowDetail(cell.entry)
        end)
        c:SetScript("OnEnter", function(cell)
            if not cell.entry then return end
            GameTooltip:SetOwner(cell, "ANCHOR_RIGHT")
            if cell.entry.id and GameTooltip.SetItemByID then
                GameTooltip:SetItemByID(cell.entry.id)
            else
                GameTooltip:SetText(cell.entry.name or "?")
                local zl = cell.entry.zones
                if zl and #zl > 0 then
                    GameTooltip:AddLine(("Known zones: %d (%s%s)"):format(#zl, zl[1], #zl > 1 and ", ..." or ""), 0.8, 0.8, 0.8, true)
                end
            end
            if cell.entry.found and cell.entry.found ~= "" then
                if ns:IsBonusDrop(cell.entry) then
                    GameTooltip:AddLine(cell.entry.found, 1, 0.82, 0.2, true)
                else
                    GameTooltip:AddLine(cell.entry.found, 0.85, 0.8, 0.7, true)
                end
            end
            GameTooltip:AddLine("Click for details. Shift-click to link.", 0.6, 0.6, 0.6)
            GameTooltip:Show()
        end)
        c:SetScript("OnLeave", function() GameTooltip:Hide() end)
        self.cells[i] = c
    end

    -- Paging.
    local function PageButton(dir)
        local b = CreateFrame("Button", nil, list)
        b:SetSize(26, 26)
        b.label = Text(b, "GatherpediaFontHighlight", "CENTER")
        b.label:SetPoint("CENTER", 0, 1)
        b.label:SetText(dir < 0 and "<" or ">")
        TH:SkinButton(b, "quiet")
        -- Dim when there is no page that way.
        local origEnable = b.SetEnabled
        b.SetEnabled = function(self, on)
            origEnable(self, on)
            self:SetAlpha(on and 1 or 0.35)
        end
        b:SetScript("OnClick", function() UI:ChangePage(dir) end)
        return b
    end
    local gridBottom = -40 - ROWS * (CELL_H + 8)
    self.pageText = Text(list, "GatherpediaFontDisableSmall", "CENTER")
    self.pageText:SetPoint("TOP", list, "TOPLEFT", 4 + (COLS * (CELL_W + 8) - 8) / 2, gridBottom - 8)
    self.prevPage = PageButton(-1)
    self.prevPage:SetPoint("RIGHT", self.pageText, "LEFT", -10, 0)
    self.nextPage = PageButton(1)
    self.nextPage:SetPoint("LEFT", self.pageText, "RIGHT", 10, 0)
    self.noResults = Text(list, "GatherpediaFontDisable", "CENTER")
    self.noResults:SetPoint("TOP", list, "TOP", 0, -140)
    self.noResults:SetText("Nothing matches this search or filter.")

    -- Best spots for my level.
    local spots = Panel(list, 0, 0, 0, 0.35, true)
    spots:SetPoint("BOTTOMLEFT", list, "BOTTOMLEFT", 4, 0)
    spots:SetSize(COLS * (CELL_W + 8) - 8, 56)
    spots.iconRing = TH:RoundIcon(spots, 32)
    spots.iconRing:SetPoint("LEFT", 12, 0)
    TH:SetRoundIcon(spots.iconRing, "Interface\\Icons\\INV_Misc_Map_01", TC.goldDeep)
    spots.icon = spots.iconRing.icon
    spots.title = Text(spots, "GatherpediaFontLabel")
    spots.title:SetTextColor(TC.gold[1], TC.gold[2], TC.gold[3])
    spots.title:SetPoint("TOPLEFT", spots.iconRing, "TOPRIGHT", 12, 0)
    spots.body = Text(spots, "GatherpediaFontHighlight")
    spots.body:SetPoint("BOTTOMLEFT", spots.iconRing, "BOTTOMRIGHT", 12, 1)
    spots.body:SetWidth(spots:GetWidth() - 70)
    spots.body:SetWordWrap(false)
    self.spots = spots
end

-- Does an entry pass the active search text and filter chip?
local function PassesFilter(entry, prof, filter, search, zone)
    if search ~= "" then
        local name = (ns.GetItemName(entry) or ""):lower()
        if not name:find(search, 1, true) then return false end
    end
    if filter == "all" then return true end
    if entry.placeholder then return false end
    local diff = ns.GetDifficulty(entry, ns.GetPlayerSkill(prof))
    if filter == "can" then
        return diff ~= "red" and diff ~= "unknown"
    elseif filter == "skillups" then
        return diff == "orange" or diff == "yellow" or diff == "green" or diff == "partial"
    elseif filter == "zone" then
        if entry.id and ns.db.counts[entry.id] and ns.db.counts[entry.id][zone] then return true end
        for _, z in ipairs(entry.zones or {}) do
            if z == zone then return true end
        end
        return false
    end
    return true
end

function UI:GetFiltered(entries)
    local prof, s = self.state.prof, self.state
    local zone = ns.GetCurrentZone()
    local out = {}
    for _, e in ipairs(entries) do
        if PassesFilter(e, prof, s.filter, s.search, zone) then out[#out + 1] = e end
    end
    return out
end

function UI:UpdateCell(c, entry, prof, rank)
    c.entry = entry
    if not entry then c:Hide() return end
    c:Show()

    local count = entry.id and ns:GetTotalCount(entry.id) or 0
    local diff = ns.GetDifficulty(entry, rank)
    local hex = ns.DIFFICULTY[diff].hex
    local r, g, b = Accent(prof)

    c.icon:SetTexture(ns.GetItemIcon(entry))
    c.mystery:SetShown(entry.placeholder and true or false)
    if entry.placeholder then
        -- Silhouette: unknown item, not gathered yet.
        c.icon:SetDesaturated(true)
        c.icon:SetVertexColor(0.08, 0.08, 0.08)
        c.iconBorder:SetColorTexture(0.25, 0.22, 0.18, 1)
        c.name:SetText(ns.Colorize(MUTED_HEX, "Undiscovered") .. "\n" .. ns.Colorize("6e6655", entry.name))
        c.skill:SetText("")
        c.tag:SetText(ns.Colorize(MUTED_HEX, "NEW?"))
        c.count:SetText("")
        return
    end

    if entry.upcoming and count == 0 then
        -- Announced but not out yet: silhouette with the release note.
        c.icon:SetDesaturated(true)
        c.icon:SetVertexColor(0.1, 0.1, 0.1)
        c.iconBorder:SetColorTexture(0.25, 0.22, 0.18, 1)
        c.mystery:Show()
        c.count:SetText("")
        c.skill:SetText("")
        c.tag:SetText(ns.Colorize(GOLD_HEX, "HYJAL"))
        c.name:SetText(ns.Colorize("bdb39a", ns.GetItemName(entry)) .. "\n" .. ns.Colorize(MUTED_HEX, "Coming soon"))
        return
    end

    -- The icon frame takes the skill-up color (orange, yellow, green,
    -- gray); bright once gathered, faint until then.
    local dr, dg, db = tonumber(hex:sub(1, 2), 16) / 255, tonumber(hex:sub(3, 4), 16) / 255, tonumber(hex:sub(5, 6), 16) / 255
    if count > 0 then
        c.icon:SetDesaturated(false)
        c.icon:SetVertexColor(1, 1, 1)
        c.iconBorder:SetColorTexture(dr, dg, db, 0.95)
        c.count:SetText(count)
    else
        -- Not collected yet: dimmed until the first gather.
        c.icon:SetDesaturated(true)
        c.icon:SetVertexColor(0.45, 0.45, 0.45)
        c.iconBorder:SetColorTexture(dr, dg, db, 0.40)
        c.count:SetText("")
    end
    c.name:SetText(ns.Colorize(hex, ns.GetItemName(entry)))
    local shown = entry.skill or entry.skillMin
    if entry.prof == "Fishing" then
        local _, castMin = ns.FishingEval(entry)
        shown = castMin or shown
    end
    if ns:IsBonusDrop(entry) then
        -- Not a node: gold border and a "Bonus drop" mark so it is
        -- not mistaken for something you walk up to on its own.
        c.iconBorder:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], count > 0 and 0.9 or 0.45)
        c.skill:SetText(ns.Colorize(GOLD_HEX, "Bonus drop"))
        c.tag:SetText(ns.Colorize(GOLD_HEX, entry.category or "Bonus"))
    else
        c.skill:SetText(shown and ns.Colorize(hex, shown) or "")
        if entry.discovered then
            c.tag:SetText(ns.Colorize(GOLD_HEX, "FOUND"))
        else
            c.tag:SetText(ns.Colorize(MUTED_HEX, entry.category or ""))
        end
    end
end

-- Zones that suit the player's current skill: every orange/yellow entry
-- votes for its zones, and zones where the player already gathered it get a
-- bonus. Returns up to three zone names.
function UI:BestSpots(entries, prof, rank)
    local def = ns.professions[prof]
    if def.skillMode ~= "tiers" then
        -- Fishing and Skinning have no zone data: use your own log instead.
        local zones = {}
        for z, n in pairs(ns.db.gathers[prof] or {}) do zones[#zones + 1] = { z = z, s = n } end
        table.sort(zones, function(a, b) if a.s == b.s then return a.z < b.z end return a.s > b.s end)
        local out = {}
        for i = 1, math.min(3, #zones) do out[i] = zones[i].z .. " (" .. zones[i].s .. ")" end
        return out, true
    end
    local scores = {}
    for _, e in ipairs(entries) do
        if ns:IsBonusDrop(e) then
            -- Bonus drops are not nodes and do not vote for zones.
        else
        local diff = ns.GetDifficulty(e, rank)
        local weight = (diff == "orange" and 2) or (diff == "yellow" and 1.5)
            or (diff == "ok" and rank and e.skill and rank - e.skill < 75 and 1) or 0
        if weight > 0 then
            for _, z in ipairs(e.zones or {}) do scores[z] = (scores[z] or 0) + weight end
            local mine = e.id and ns.db.counts[e.id]
            if mine then
                for z, n in pairs(mine) do scores[z] = (scores[z] or 0) + weight * 0.5 + math.min(n, 20) * 0.05 end
            end
        end
        end
    end
    local zones = {}
    for z, sc in pairs(scores) do zones[#zones + 1] = { z = z, s = sc } end
    table.sort(zones, function(a, b) if a.s == b.s then return a.z < b.z end return a.s > b.s end)
    local out = {}
    for i = 1, math.min(3, #zones) do out[i] = zones[i].z end
    return out
end

function UI:RefreshList()
    if not self.frame or not self.frame:IsShown() or not self.state.prof then return end
    local prof = self.state.prof
    local all = ns:GetEntries(prof)
    local entries = self:GetFiltered(all)
    local rank = ns.GetPlayerSkill(prof)

    self:UpdateHeader(all)

    for _, chip in ipairs(self.chips) do
        local on = chip.key == self.state.filter
        local pal = TH:Prof(prof)
        TH:PaintButton(chip, on and "segmentOn" or "segment", { fill = pal.fill, line = pal.line, text = TC.text })
    end
    if self.search then self.search:Show() end
    if self.pageText then self.pageText:Show() end
    if self.prevPage then self.prevPage:Show() end
    if self.nextPage then self.nextPage:Show() end
    if self.spots then self.spots:Show() end


    local pages = math.max(1, math.ceil(#entries / PER_PAGE))
    local page = math.min(self.state.page[prof] or 1, pages)
    self.state.page[prof] = page
    for i, c in ipairs(self.cells) do
        self:UpdateCell(c, entries[(page - 1) * PER_PAGE + i], prof, rank)
    end
    self.pageText:SetText(("Page %d of %d"):format(page, pages))
    self.prevPage:SetEnabled(page > 1)
    self.nextPage:SetEnabled(page < pages)
    self.noResults:SetShown(#entries == 0)

    local spots, fromLog = self:BestSpots(all, prof, rank)
    if fromLog then
        self.spots.title:SetText("YOUR BEST SPOTS")
        self.spots.body:SetText(#spots > 0 and table.concat(spots, ns.Colorize(GOLD_HEX, "  \194\183  "))
            or ns.Colorize(MUTED_HEX, "Gather a few times and your busiest zones will show up here."))
    elseif not rank then
        self.spots.title:SetText("BEST SPOTS FOR MY LEVEL")
        self.spots.body:SetText(ns.Colorize(MUTED_HEX, "Learn " .. ns.professions[prof].label .. " to get zone suggestions for your skill."))
    elseif #spots == 0 then
        self.spots.title:SetText(("BEST SPOTS FOR SKILL %d"):format(rank))
        self.spots.body:SetText(ns.Colorize(MUTED_HEX, "Everything here is gray for you. Time to train the next rank!"))
    else
        self.spots.title:SetText(("BEST SPOTS FOR SKILL %d"):format(rank))
        self.spots.body:SetText(table.concat(spots, ns.Colorize(GOLD_HEX, "  \194\183  ")))
    end
end

function UI:ChangePage(dir)
    local prof = self.state.prof
    self.state.page[prof] = (self.state.page[prof] or 1) + dir
    self:RefreshList()
end

---------------------------------------------------------------------------
-- Detail page
---------------------------------------------------------------------------

function UI:CreateDetailPage(f)
    local d = CreateFrame("Frame", nil, f)
    d:SetSize(MAIN_W, HEIGHT - 76 - 12)
    self.detailAnchor = { "TOPLEFT", f, "TOPLEFT", MAIN_X, -76 }
    d:SetPoint(unpack(self.detailAnchor))
    d:Hide()
    self.detail = d

    local back = CreateFrame("Button", nil, d)
    back:SetSize(78, 26)
    back:SetPoint("TOPLEFT", 4, -2)
    back.label = Text(back, "GatherpediaFontHighlightSmall", "CENTER")
    back.label:SetPoint("CENTER")
    back.label:SetText("< Back")
    TH:SkinButton(back, "quiet")
    back:SetScript("OnClick", function() UI:ShowList() end)

    local iconFrame = Panel(d, 0, 0, 0, 0.6, true)
    iconFrame:SetSize(76, 76)
    iconFrame:SetPoint("TOPLEFT", 4, -38)
    d.icon = iconFrame:CreateTexture(nil, "ARTWORK")
    d.icon:SetPoint("TOPLEFT", 6, -6)
    d.icon:SetPoint("BOTTOMRIGHT", -6, 6)
    d.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    d.iconFrame = iconFrame

    d.name = Text(d, "GatherpediaFontTitle")
    d.name:SetPoint("TOPLEFT", iconFrame, "TOPRIGHT", 14, -4)
    d.name:SetTextColor(TC.text[1], TC.text[2], TC.text[3])
    d.sub = Text(d, "GatherpediaFontHighlightSmall")
    d.sub:SetPoint("TOPLEFT", d.name, "BOTTOMLEFT", 0, -4)
    d.tiers = Text(d, "GatherpediaFontHighlight")
    d.tiers:SetPoint("TOPLEFT", d.sub, "BOTTOMLEFT", 0, -8)
    -- Hover area over the skill line; shows the profession's formula, if any.
    d.tiersHit = CreateFrame("Frame", nil, d)
    d.tiersHit:SetAllPoints(d.tiers)
    d.tiersHit:EnableMouse(true)
    d.tiersHit:SetScript("OnEnter", function(hit)
        if not hit.note then return end
        GameTooltip:SetOwner(hit, "ANCHOR_BOTTOMLEFT")
        GameTooltip:AddLine("Skill needed")
        GameTooltip:AddLine(hit.note, 1, 1, 1, true)
        GameTooltip:Show()
    end)
    d.tiersHit:SetScript("OnLeave", function() GameTooltip:Hide() end)

    -- Segmented skill bar: orange, yellow, green, gray, with a marker for you.
    local seg = CreateFrame("Frame", nil, d)
    seg:SetSize(MAIN_W - 120, 10)
    seg:SetPoint("TOPLEFT", iconFrame, "BOTTOMLEFT", 0, -14)
    seg.parts = {}
    for i = 1, 4 do
        seg.parts[i] = seg:CreateTexture(nil, "ARTWORK")
        seg.parts[i]:SetHeight(10)
    end
    seg.marker = seg:CreateTexture(nil, "OVERLAY")
    seg.marker:SetSize(3, 18)
    seg.marker:SetColorTexture(1, 1, 1, 1)
    seg.markerText = Text(seg, "GatherpediaFontHighlightSmall", "CENTER")
    seg.markerText:SetPoint("TOP", seg.marker, "BOTTOM", 0, -2)
    d.seg = seg
    d.diffText = Text(d, "GatherpediaFontHighlight", "RIGHT")
    d.diffText:SetPoint("BOTTOMRIGHT", seg, "TOPRIGHT", 0, 6)

    -- How the item is found: habitat for a node, or "bonus from …,
    -- not its own node" for scarce drops, gems, stones and seeds.
    d.found = Text(d, "GatherpediaFontHighlight")
    d.found:SetPoint("TOPLEFT", seg, "BOTTOMLEFT", 0, -12)
    d.found:SetWidth(MAIN_W - 8)
    d.found:SetJustifyH("LEFT")
    if d.found.SetWordWrap then d.found:SetWordWrap(true) end

    -- Stat tiles.
    d.stats = {}
    local labels = { "TOTAL GATHERED", "FIRST GATHERED", "ZONES" }
    for i = 1, 3 do
        local tile = Panel(d, 0, 0, 0, 0.35, true)
        tile:SetSize(170, 46)
        tile:SetPoint("TOPLEFT", d.found, "BOTTOMLEFT", (i - 1) * 182, -12)
        local l = Text(tile, "GatherpediaFontLabel")
        l:SetPoint("TOPLEFT", 12, -9)
        l:SetText(labels[i])
        tile.value = Text(tile, "GatherpediaFontHighlightLarge")
        tile.value:SetPoint("BOTTOMLEFT", 12, 8)
        d.stats[i] = tile
    end

    -- Known zones: every zone for the item, scrollable.
    local zonesLabel = Text(d, "GatherpediaFontLabel")
    zonesLabel:SetPoint("TOPLEFT", d.stats[1], "BOTTOMLEFT", 2, -14)
    zonesLabel:SetText("KNOWN ZONES")
    d.zonesHint = Text(d, "GatherpediaFontDisableSmall")
    d.zonesHint:SetPoint("LEFT", zonesLabel, "RIGHT", 8, 0)
    d.zonesHint:SetWidth(MAIN_W - 120)
    d.zonesHint:SetWordWrap(false)
    d.factionHint = Text(d, "GatherpediaFontHighlightSmall")
    d.factionHint:SetPoint("TOPLEFT", zonesLabel, "BOTTOMLEFT", 0, -3)
    d.factionHint:SetWidth(MAIN_W - 20)
    d.factionHint:SetWordWrap(false)

    local box = Panel(d, 0, 0, 0, 0.25, true)
    box:SetPoint("TOPLEFT", d.factionHint, "BOTTOMLEFT", -4, -6)
    box:SetPoint("BOTTOMRIGHT", d, "BOTTOMRIGHT", -4, 4)
    -- The same slim scrollbar as the Guides and Trainers pages.
    local scroll, content = ns.Chrome:CreateScroll(box, nil)
    ns.Chrome:PlaceScroll(scroll, 4, 4)
    content:SetSize(MAIN_W - 40, 10)
    d.zoneBox = box
    d.zoneScroll, d.zoneContent, d.rows = scroll, content, {}
end

local ZONE_ROW_H = 22
local CHECK = "|TInterface\\RaidFrame\\ReadyCheck-Ready:12:12|t"
local FACTION_HEX = { Alliance = "4a9eff", Horde = "ff4a4a" }

function UI:ZoneRow(i)
    local d = self.detail
    local row = d.rows[i]
    if row then return row end
    row = CreateFrame("Frame", nil, d.zoneContent)
    row:SetSize(MAIN_W - 40, ZONE_ROW_H)
    row:SetPoint("TOPLEFT", 0, -(i - 1) * ZONE_ROW_H)
    row.bg = row:CreateTexture(nil, "BACKGROUND")
    row.bg:SetAllPoints()
    row.left = Text(row, "GatherpediaFontHighlightSmall")
    row.left:SetPoint("LEFT", 8, 0)
    row.left:SetWordWrap(false)
    row.pin = row:CreateTexture(nil, "ARTWORK")
    row.pin:SetSize(12, 12)
    row.pin:SetPoint("RIGHT", -4, 0)
    row.pin:SetTexture("Interface\\Icons\\INV_Misc_Map_01")
    row.pin:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    row.right = Text(row, "GatherpediaFontHighlightSmall", "RIGHT")
    row.right:SetPoint("RIGHT", -20, 0)
    row.hl = row:CreateTexture(nil, "HIGHLIGHT")
    row.hl:SetAllPoints()
    row.hl:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], 0.08)
    -- Click a zone: open the world map on it (only opens the map).
    row:SetScript("OnEnter", function(r)
        if not r.mapID then return end
        GameTooltip:SetOwner(r, "ANCHOR_RIGHT")
        GameTooltip:AddLine(r.zone)
        GameTooltip:AddLine(r.beasts and (r.beasts.prof == "Skinning" and "Click: show the beasts on the map"
            or "Click: show its nodes on the map") or "Click: open map", 1, 1, 1)
        GameTooltip:Show()
    end)
    row:SetScript("OnLeave", function() GameTooltip:Hide() end)
    row:SetScript("OnMouseUp", function(r, button)
        if button == "LeftButton" and r.beasts and ns.SpawnPins then
            ns.SpawnPins:Show(r.beasts)
        elseif button == "LeftButton" and r.mapID then
            ns.MapLink:ClearPin()
            if ns.SpawnPins then ns.SpawnPins:Clear() end
            ns.MapLink:Open(r.zone, r.mapID)
        end
    end)
    row.note = Text(row, "GatherpediaFontDisableSmall")
    row.note:SetPoint("LEFT", row.left, "RIGHT", 8, 0)
    row.note:SetPoint("RIGHT", row.right, "LEFT", -6, 0)
    row.note:SetWordWrap(false)
    d.rows[i] = row
    return row
end

function UI:FillDetail(entry)
    local d = self.detail
    local prof = entry.prof or self.state.prof
    local def = ns.professions[prof]
    local rank = ns.GetPlayerSkill(prof)
    local r, g, b = Accent(prof)
    local count = entry.id and ns:GetTotalCount(entry.id) or 0

    d.icon:SetTexture(ns.GetItemIcon(entry))
    d.icon:SetDesaturated(entry.placeholder and true or false)
    d.icon:SetVertexColor(entry.placeholder and 0.1 or 1, entry.placeholder and 0.1 or 1, entry.placeholder and 0.1 or 1)
    d.iconFrame:SetBackdropBorderColor(r, g, b, 1)
    d.name:SetText(entry.placeholder and ("Undiscovered: " .. entry.name) or ns.GetItemName(entry))
    -- Category and profession only. Data-source tags (Based on Classic,
    -- Confirmed for Forever, etc.) stay in entry.status and are not shown.
    local sub = (entry.category or "") .. "  \194\183  " .. def.label
    if entry.discovered then
        sub = sub .. "  \194\183  Learned from your gathering"
    end
    d.sub:SetText(ns.Colorize(TH:Hex(TC.text2), sub))

    -- Skill tiers and the segmented bar.
    local seg = d.seg
    d.tiersHit.note = def.skillNote
    local width = seg:GetWidth()
    if entry.tiers then
        d.tiers:SetText("Skill   " .. ns.FormatTiers(entry.tiers))
        local lo, hi = entry.tiers[1], entry.tiers[4] + 25
        local span = hi - lo
        local x = 0
        local bounds = { entry.tiers[1], entry.tiers[2], entry.tiers[3], entry.tiers[4], hi }
        for i = 1, 4 do
            local w = (bounds[i + 1] - bounds[i]) / span * width
            local hex = ns.DIFFICULTY[ns.TIER_KEYS[i]].hex
            seg.parts[i]:ClearAllPoints()
            seg.parts[i]:SetPoint("LEFT", seg, "LEFT", x, 0)
            seg.parts[i]:SetWidth(math.max(w, 1))
            seg.parts[i]:SetColorTexture(tonumber(hex:sub(1, 2), 16) / 255, tonumber(hex:sub(3, 4), 16) / 255,
                tonumber(hex:sub(5, 6), 16) / 255, 0.85)
            seg.parts[i]:Show()
            x = x + w
        end
        if rank then
            local pos = math.max(0, math.min(1, (rank - lo) / span)) * width
            seg.marker:ClearAllPoints()
            seg.marker:SetPoint("CENTER", seg, "LEFT", pos, 0)
            seg.marker:Show()
            seg.markerText:SetText("You: " .. rank)
        else
            seg.marker:Hide()
            seg.markerText:SetText("")
        end
        seg:Show()
    elseif entry.skill then
        d.tiers:SetText("Skill needed   " .. ns.Colorize("ffffff", entry.skill))
        seg:Hide()
    elseif (entry.prof == "Fishing" and ns.SkillRangeText(entry)) or entry.skillMin then
        d.tiers:SetText(ns.Colorize("ffffff", ns.SkillRangeText(entry)))
        seg:Hide()
    elseif def.skillShort then
        d.tiers:SetText(ns.Colorize("d9d1b3", def.skillShort))
        seg:Hide()
    else
        d.tiers:SetText("")   -- skill unknown: leave the line out rather than say so
        seg:Hide()
    end
    local diff = ns.GetDifficulty(entry, rank)
    if entry.upcoming and count == 0 then
        d.diffText:SetText(ns.Colorize(GOLD_HEX, entry.upcoming))
    elseif diff == "nodata" then
        d.diffText:SetText("")
    elseif entry.placeholder or diff == "unknown" then
        d.diffText:SetText(entry.placeholder and "" or ns.Colorize(MUTED_HEX, "You haven't learned " .. def.label))
    else
        d.diffText:SetText(ns.Colorize(ns.DIFFICULTY[diff].hex, ns.DifficultyLabel(entry, diff)))
    end

    -- How it's found. Bonus drops get the gold "not its own node" line.
    if d.found then
        d.found:ClearAllPoints()
        if entry.tiers and seg:IsShown() then
            d.found:SetPoint("TOPLEFT", seg, "BOTTOMLEFT", 0, -12)
        else
            d.found:SetPoint("TOPLEFT", d.iconFrame, "BOTTOMLEFT", 0, -16)
        end
        local found = entry.found
        if type(found) == "string" and found ~= "" then
            if ns:IsBonusDrop(entry) then
                d.found:SetText(ns.Colorize(GOLD_HEX, found))
            else
                d.found:SetText(ns.Colorize("d9d1b3", found))
            end
            d.found:Show()
        else
            d.found:SetText(" ")
            d.found:Show()
        end
    end

    -- Stats.
    local mine = (entry.id and ns.db.counts[entry.id]) or {}
    local zoneCount = 0
    for _ in pairs(mine) do zoneCount = zoneCount + 1 end
    d.stats[1].value:SetText(count)
    d.stats[2].value:SetText(FormatDate(entry.id and ns.db.firsts[entry.id]))
    d.stats[3].value:SetText(zoneCount)

    -- Known zones. Bonus drops list the union of their parent-node zones.
    local here = GetRealZoneText and GetRealZoneText() or nil
    local faction = UnitFactionGroup and UnitFactionGroup("player") or "Alliance"
    local zoneView = ns:EntryWithSourceZones(entry)
    local rows, hint = ns.Zones:Build(zoneView, mine, here, faction, ns.db.options.onlyGatheredZones)
    local srcZones = zoneView.zones or {}
    local sub
    if ns:IsBonusDrop(entry) and #srcZones > 0 then
        sub = (prof == "Skinning") and "Where its source beasts are found"
            or (prof == "Mining") and "Where its source nodes are mined"
            or "Where its source nodes grow"
    elseif #srcZones > 0 then
        local order = (prof == "Skinning") and "by beast level, low to high"
            or (prof == "Fishing") and "by zone fishing level" or "most common first"
        sub = order .. (entry.water and ("  \194\183  water: " .. entry.water) or "")
    else
        sub = entry.upcoming and "Zones will be added once it's out" or "learned from your own gathering"
    end
    d.zonesHint:SetText(sub)
    d.factionHint:SetText(hint and ns.Colorize("8fc8ff", hint) or "")

    for i, info in ipairs(rows) do
        local row = self:ZoneRow(i)
        local name = info.zone
        if info.here then
            name = ns.Colorize("ffd200", name) .. ns.Colorize(GOLD_HEX, "  (you are here)")
        elseif info.n > 0 then
            name = ns.Colorize("ffffff", name)
        else
            name = ns.Colorize(info.best and "d9d1b3" or MUTED_HEX, name)
        end
        local tags = {}
        if info.faction then tags[#tags + 1] = ns.Colorize(FACTION_HEX[info.faction], info.faction) end
        if info.yours then tags[#tags + 1] = ns.Colorize("40bf40", "yours") end
        if #tags > 0 then name = name .. "  " .. table.concat(tags, " ") end
        row.left:SetText(name)
        -- Reworked-zone flags stay on info.reworked; we do not show a
        -- "may differ on Forever" source tag to the player.
        row.note:SetText(info.note or "")
        row.right:SetText(info.n > 0 and (CHECK .. " " .. ns.Colorize(GOLD_HEX, info.n)) or ns.Colorize("5c5547", "0"))
        row.zone, row.mapID = info.zone, info.mapID
        row.beasts = nil
        if prof == "Skinning" and ns.SpawnPins and ns.SpawnPins:Has(info.mapID) then
            -- Level window for this zone from the note ("lvl 16-22 · ..."),
            -- else the item's own range.
            local lo, hi = tostring(entry.zoneNotes and entry.zoneNotes[info.zone] or ""):match("lvl (%d+)%-(%d+)")
            row.beasts = {
                prof = "Skinning", zone = info.zone, mapID = info.mapID,
                mobMin = tonumber(lo) or entry.mobMin, mobMax = tonumber(hi) or entry.mobMax,
            }
        elseif (prof == "Herbalism" or prof == "Mining") and entry.id and ns.SpawnPins
            and #ns.SpawnPins:Entries(prof, info.mapID, { itemID = ns.canonical and ns.canonical[entry.id] or entry.id }) > 0 then
            -- This herb's or ore's own nodes in the zone.
            row.beasts = {
                prof = prof, zone = info.zone, mapID = info.mapID,
                itemID = ns.canonical and ns.canonical[entry.id] or entry.id,
            }
        end
        row:EnableMouse(info.mapID ~= nil)          -- zones without a map ID stay plain text
        row.pin:SetShown(info.mapID ~= nil)
        row.hl:SetShown(info.mapID ~= nil)
        if info.here then
            row.bg:SetColorTexture(TC.goldFill[1], TC.goldFill[2], TC.goldFill[3], 1)
        elseif info.best then
            row.bg:SetColorTexture(0.29, 0.62, 1, 0.07)   -- good pick for your faction
        else
            row.bg:SetColorTexture(TC.raised[1], TC.raised[2], TC.raised[3], (i % 2 == 0) and 0.6 or 0)
        end
        row:Show()
    end
    local n = #rows
    if n == 0 then
        local row = self:ZoneRow(1)
        row.left:SetText(ns.Colorize(MUTED_HEX, entry.upcoming and "Zones will be added once it's out."
            or (ns.db.options.onlyGatheredZones and #srcZones > 0)
                and "You haven't gathered this yet. Turn off \"Only list zones I've gathered in\" to see every zone."
            or "No zones yet. Gather one and Gatherpedia will remember where."))
        row.note:SetText(""); row.right:SetText(""); row.bg:SetColorTexture(0, 0, 0, 0)
        row.zone, row.mapID, row.beasts = nil, nil, nil
        row:EnableMouse(false); row.pin:Hide(); row.hl:Hide()
        row:Show()
        n = 1
    end
    for i = n + 1, #d.rows do d.rows[i]:Hide() end
    d.zoneContent:SetHeight(math.max(n * ZONE_ROW_H, 10))
    d.zoneScroll:SetVerticalScroll(0)
    if ns.Chrome and ns.Chrome.UpdateScrollBar then ns.Chrome:UpdateScrollBar(d.zoneScroll) end
    d.zoneRows = rows
end

function UI:ShowDetail(entry)
    self.state.detail = entry
    self.state.view = "book"
    if self.trainersPage then self.trainersPage:Hide() end
    if self.guidesPage then self.guidesPage:Hide() end
    self:FillDetail(entry)
    self.list:Hide()
    SlideIn(self.detail, self.detailAnchor)
end

function UI:ShowList()
    self.state.detail = nil
    self.state.view = "book"
    if self.trainersPage then self.trainersPage:Hide() end
    if self.glimmerPage then self.glimmerPage:Hide() end
    if self.guidesPage then self.guidesPage:Hide() end
    if ns.GuidesUI then ns.GuidesUI:Hide() end
    self.detail:Hide()
    self.list:Show()
    FadeIn(self.list, 0.12)
    self:RefreshList()
end

function UI:CreateGuidesPage(f)
    if not ns.GuidesUI then return end
    local page = ns.GuidesUI:Create(f)
    page:SetPoint("TOPLEFT", f, "TOPLEFT", MAIN_X, -72)
    page:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -16, 16)
    page:SetSize(MAIN_W, HEIGHT - 88)
    self.guidesPage = page
end

function UI:ShowGuides()
    self:Create()
    self.state.view = "guides"
    self.state.detail = nil
    if self.frame:IsShown() then self:Refresh() else self.frame:Show() end
end

---------------------------------------------------------------------------
-- Empty state (no gathering professions on this character)
---------------------------------------------------------------------------

function UI:CreateEmptyState(f)
    local e = CreateFrame("Frame", nil, f)
    e:SetPoint("TOPLEFT", f, "TOPLEFT", MAIN_X, -20)
    e:SetSize(MAIN_W, HEIGHT - 40)
    e:Hide()
    self.empty = e

    local head = Text(e, "GatherpediaFontTitle", "CENTER")
    head:SetPoint("TOP", 0, -60)
    head:SetText("No gathering professions yet")
    local body = Text(e, "GatherpediaFontHighlight", "CENTER")
    body:SetPoint("TOP", head, "BOTTOM", 0, -12)
    body:SetWidth(MAIN_W - 80)
    body:SetText("Gatherpedia fills in as this character gathers. Visit a profession trainer in any major city to learn one of these:")

    local order = { "Herbalism", "Mining", "Skinning", "Fishing" }
    local blurbs = {
        Herbalism = "Pick herbs for potions",
        Mining = "Mine ore, stone and gems",
        Skinning = "Skin beasts for leather",
        Fishing = "Secondary: fish any water",
    }
    for i, key in ipairs(order) do
        local card = Panel(e, 0, 0, 0, 0.35, true)
        card:SetSize(130, 120)
        card:SetPoint("TOP", e, "TOP", (i - 2.5) * 140, -170)
        local icon = card:CreateTexture(nil, "ARTWORK")
        icon:SetSize(44, 44)
        icon:SetPoint("TOP", 0, -14)
        card.icon = icon
        card.key = key
        local name = Text(card, "GatherpediaFontNormal", "CENTER")
        name:SetPoint("TOP", icon, "BOTTOM", 0, -8)
        name:SetText(key)
        local blurb = Text(card, "GatherpediaFontHighlightSmall", "CENTER")
        blurb:SetPoint("TOP", name, "BOTTOM", 0, -4)
        blurb:SetWidth(118)
        blurb:SetText(blurbs[key])
        e[key] = card
    end

    local browse = CreateFrame("Button", nil, e, "UIPanelButtonTemplate")
    browse:SetSize(200, 26)
    browse:SetPoint("TOP", e, "TOP", 0, -320)
    browse:SetText("Browse all professions")
    browse:SetScript("OnClick", function()
        UI:SetShowAllProfessions(true)
    end)
end

---------------------------------------------------------------------------
-- Public API
---------------------------------------------------------------------------


function UI:CreateTrainersPage(f)
    if not ns.TrainersUI then return end
    local page = ns.TrainersUI:Create(f)
    page:SetPoint("TOPLEFT", f, "TOPLEFT", MAIN_X, -72)
    page:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -16, 16)
    self.trainersPage = page
end

function UI:ShowTrainers()
    self:Create()
    self.state.view = "trainers"
    self.state.detail = nil
    if self.frame:IsShown() then self:Refresh() else self.frame:Show() end
end

function UI:CreateGlimmerPage(f)
    if not ns.SparklesUI then return end
    local page = ns.SparklesUI:Create(f)
    page:SetPoint("TOPLEFT", f, "TOPLEFT", MAIN_X, -72)
    page:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -16, 16)
    self.glimmerPage = page
end

function UI:ShowGlimmer()
    self:Create()
    self.state.view = "glimmer"
    self.state.detail = nil
    if ns.Options and ns.Options.Hide then ns.Options:Hide() end
    if self.frame:IsShown() then self:Refresh() else self.frame:Show() end
end

function UI:SelectProfession(prof)
    if not prof then return end
    self.state.prof = prof
    self.state.view = "book"
    if self.search then self.search:SetText("") end
    self.state.search = ""
    self.state.detail = nil
    -- Always go through Refresh so the item list is shown again after
    -- Trainers (or a detail page) hid it. RefreshList alone would update
    -- the header while leaving the grid hidden.
    if self.frame and self.frame:IsShown() then
        self:Refresh()
    else
        self:UpdateSidebar()
    end
end

function UI:Refresh()
    if not self.frame or not self.frame:IsShown() then return end
    local visible = ns:GetVisibleProfessions()
    local isEmpty = #visible == 0 and not IsToolView(self.state.view)

    -- Keep the selected tab valid for this character.
    local valid = false
    for _, key in ipairs(visible) do if key == self.state.prof then valid = true end end
    if not valid and not IsToolView(self.state.view) then self.state.prof = visible[1] end

    self.empty:SetShown(isEmpty)
    if isEmpty then
        self.header:SetShown(false)
        self.accentLine:SetShown(false)
        for _, key in ipairs(ns.PROFESSIONS) do
            self.empty[key].icon:SetTexture(ns.professions[key].icon)
        end
        self.list:Hide()
        self.detail:Hide()
        if self.trainersPage then self.trainersPage:Hide() end
        if self.glimmerPage then self.glimmerPage:Hide() end
        if self.guidesPage then self.guidesPage:Hide() end
        self:UpdateSidebar()
        return
    end

    self.header:SetShown(true)
    self.accentLine:SetShown(true)
    self:UpdateSidebar()
    if self.state.view == "trainers" then
        self.list:Hide()
        self.detail:Hide()
        self.empty:Hide()
        if self.glimmerPage then self.glimmerPage:Hide() end
        if self.guidesPage then self.guidesPage:Hide() end
        self:UpdateHeader()
        if self.trainersPage then
            self.trainersPage:Show()
            if ns.TrainersUI then ns.TrainersUI:Refresh() end
        end
        return
    end
    if self.state.view == "guides" then
        self.list:Hide()
        self.detail:Hide()
        self.empty:Hide()
        if self.trainersPage then self.trainersPage:Hide() end
        if self.glimmerPage then self.glimmerPage:Hide() end
        self:UpdateHeader()
        if self.guidesPage then
            self.guidesPage:Show()
            if ns.GuidesUI then ns.GuidesUI:Show() end
        end
        return
    end
    if self.state.view == "glimmer" then
        self.list:Hide()
        self.detail:Hide()
        self.empty:Hide()
        if self.trainersPage then self.trainersPage:Hide() end
        if self.guidesPage then self.guidesPage:Hide() end
        self:UpdateHeader()
        if self.glimmerPage then
            self.glimmerPage:Show()
            if ns.SparklesUI then ns.SparklesUI:Refresh() end
        end
        return
    end
    if self.trainersPage then self.trainersPage:Hide() end
    if self.glimmerPage then self.glimmerPage:Hide() end
    if self.guidesPage then self.guidesPage:Hide() end
    if self.state.detail then
        self.list:Hide()
        self.detail:Show()
        self:FillDetail(self.state.detail)
        self:UpdateHeader(ns:GetEntries(self.state.prof))
    else
        self.detail:Hide()
        self.list:Show()
        self:RefreshList()
    end
end

-- Throttled refresh, used after loot and when item names finish loading.
function UI:RequestRefresh()
    if self.refreshQueued or not self.frame or not self.frame:IsShown() then return end
    self.refreshQueued = true
    C_Timer.After(0.15, function()
        UI.refreshQueued = false
        UI:Refresh()
    end)
end

function UI:ShowAllProfessions()
    return ns.charDB and ns.charDB.showAllProfessions and true or false
end

function UI:RefreshProfDrop()
    local dd = self.profDrop
    if not dd then return end
    local all = self:ShowAllProfessions()
    dd.label:SetText(all and "All professions" or "My professions")
    TH:PaintButton(dd)
    if dd.arrow then
        dd.arrow:SetVertexColor(TC.text2[1], TC.text2[2], TC.text2[3], 1)
        dd.arrow:Show()
    end
end

function UI:SetShowAllProfessions(on)
    if not ns.charDB then return end
    ns.charDB.showAllProfessions = on and true or false
    self:RefreshProfDrop()
    if ns.Options then ns.Options:Refresh() end
    if self.frame and self.frame:IsShown() then
        self:Refresh()
    else
        self:UpdateSidebar()
    end
end

function UI:ToggleProfMenu()
    local dd = self.profDrop
    if not dd or not ns.Menu then return end
    if ns.Menu:IsOpen() and ns.Menu.owner == dd then
        ns.Menu:Close()
        return
    end
    local function item(label, all)
        return { text = label, kind = "radio",
            checked = function() return UI:ShowAllProfessions() == all end,
            func = function() UI:SetShowAllProfessions(all) end,
            close = true }
    end
    ns.Menu:Open(dd, { item("All professions", true), item("My professions", false) }, { below = true })
end

function UI:OnProfessionsChanged()
    self:RefreshProfDrop()
    self:Refresh()
end

function UI:Show(prof)
    self:Create()
    if prof then
        if ns.learned[prof] or (ns.charDB and ns.charDB.showAllProfessions) then
            self.state.prof = prof
            self.state.detail = nil
            self.state.view = "book"
        else
            ns:Print(("This character hasn't learned %s. Turn on \"Show all professions\" in /gp options to browse it."):format(prof))
        end
    end
    if self.frame:IsShown() then self:Refresh() else self.frame:Show() end
end

function UI:Hide()
    if self.frame then self.frame:Hide() end
end

function UI:Toggle()
    if self.frame and self.frame:IsShown() then self:Hide() else self:Show() end
end

function UI:SavePosition()
    local point, _, relPoint, x, y = self.frame:GetPoint(1)
    local w = ns.db.window
    w.point, w.relPoint, w.x, w.y = point, relPoint, x, y
end

-- Where the window sits on its own. Locked (the default): the left side
-- of the screen, where the game puts the world map and other panels.
-- Unlocked: wherever it was last dragged.
local LEFT_X, LEFT_Y = 16, -116
function UI:RestorePosition()
    local w = ns.db.window
    self.frame:ClearAllPoints()
    if w.point and not self:IsLocked() then
        self.frame:SetPoint(w.point, UIParent, w.relPoint or w.point, w.x or 0, w.y or 0)
    else
        self.frame:SetPoint("TOPLEFT", UIParent, "TOPLEFT", LEFT_X, LEFT_Y)
    end
end

-- When the player opens the world map from Gatherpedia, slide the main
-- window to the right of WorldMapFrame (LEFT -> RIGHT, small gap),
-- clamped to the screen. The saved position is not overwritten. Closing
-- the map puts the window back; a drag while docked becomes the new save
-- and cancels the snap-back.
function UI:WatchMapFrame()
    if self._mapWatch then return end
    local map = WorldMapFrame
    if not map then return end
    self._mapWatch = true
    local function undock()
        if ns.UI then ns.UI:UndockFromMap() end
    end
    -- The map opened by the player (M key) moves the window too. The game
    -- may close this window as the map opens, so a window that closed a
    -- moment ago comes back.
    local function onMapShow()
        local ui = ns.UI
        local f = ui and ui.frame
        if not f then return end
        local recent = ui._hiddenAt and GetTime and (GetTime() - ui._hiddenAt) < 0.3
        if f:IsShown() or recent then ui:DockAfterMapOpen(true) end
    end
    if self.frame and self.frame.HookScript then
        self.frame:HookScript("OnHide", function()
            if GetTime then UI._hiddenAt = GetTime() end
        end)
        -- Every way of opening the window lands here: left side on its
        -- own, right of the map when the map is up.
        self.frame:HookScript("OnShow", function()
            if map:IsShown() then
                UI:DockBesideMap()
            elseif not UI._mapDocked then
                UI:RestorePosition()
            end
        end)
    end
    if map.HookScript then
        pcall(map.HookScript, map, "OnHide", undock)
        pcall(map.HookScript, map, "OnShow", onMapShow)
    else
        local prev = map.GetScript and map:GetScript("OnHide")
        if map.SetScript then
            map:SetScript("OnHide", function(...)
                if prev then prev(...) end
                undock()
            end)
        end
    end
end

function UI:DockBesideMap()
    self:WatchMapFrame()
    local f = self.frame
    local map = WorldMapFrame
    if not f or not f.IsShown or not f:IsShown() then return end
    if not map or not map.IsShown or not map:IsShown() then return end
    self._mapDocked = true
    local GAP = 8
    local parent = UIParent or f:GetParent() or map
    local function num(frame, method)
        if not frame or not frame[method] then return nil end
        local ok, v = pcall(frame[method], frame)
        if ok and type(v) == "number" then return v end
        return nil
    end
    local function scale(frame)
        return num(frame, "GetEffectiveScale") or 1
    end
    local mr, mt = num(map, "GetRight"), num(map, "GetTop")
    local pr, pt = num(parent, "GetRight"), num(parent, "GetTop")
    local pl, pb = num(parent, "GetLeft") or 0, num(parent, "GetBottom") or 0
    if mr and pr then
        local ps = scale(parent)
        if ps == 0 then ps = 1 end
        local fw = (num(f, "GetWidth") or 800) * scale(f) / ps
        local fh = (num(f, "GetHeight") or 540) * scale(f) / ps
        local left = mr * scale(map) / ps + GAP
        if left + fw > pr then
            left = pr - fw -- as far right as there is room
        end
        if left < pl then left = pl end
        local top = mt and (mt * scale(map) / ps) or (pt or 0)
        if pt and top > pt then top = pt end
        if top - fh < pb then top = pb + fh end
        f:ClearAllPoints()
        f:SetPoint("TOPLEFT", parent, "BOTTOMLEFT", left, top)
    else
        f:ClearAllPoints()
        f:SetPoint("LEFT", map, "RIGHT", GAP, 0)
    end
end

-- Opening the world map closes windows that Escape would close, and this
-- window is one of them. After the map opens, bring the window back if it
-- was open and dock it to the right of the map. Retried once the map has
-- finished laying itself out.
function UI:DockAfterMapOpen(wasShown)
    local function go()
        local f = self.frame
        if not f then return end
        if wasShown and not f:IsShown() then f:Show() end
        self:DockBesideMap()
        if f.Raise then f:Raise() end
    end
    go()
    if C_Timer and C_Timer.After then
        C_Timer.After(0, go)
        C_Timer.After(0.15, go)
    end
end

function UI:UndockFromMap()
    if not self._mapDocked then return end
    self._mapDocked = false
    if self.frame then self:RestorePosition() end
end

-- Lock state changed in options: a locked window goes back to the left.
function UI:SnapHome()
    if self.frame and not self._mapDocked then self:RestorePosition() end
end

function UI:ResetPosition()
    wipe(ns.db.window)
    self._mapDocked = false
    if self.frame then self:RestorePosition() end
    ns:Print("Window position reset.")
end
