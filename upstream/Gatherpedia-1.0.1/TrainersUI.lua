-- Gatherpedia: TrainersUI.lua
-- The Trainers page in the main window. Top to bottom:
--   a segmented profession filter and an Alliance / Horde toggle,
--   a Nearest card (the closest trainer for the filter, with Show on map),
--   one list: Rank-up (books and quests), Trainers nearest first, Supplies.
-- Click a row to open that zone on the world map and drop Gatherpedia's
-- own pin when coordinates are known.

local ADDON_NAME, ns = ...

local TrainersUI = {}
ns.TrainersUI = TrainersUI

local TH = ns.Theme
local TC = TH.C
local GOLD = TC.gold
local ROW_H = 44
local HEAD_H = 26
local SEG_H = 32
local CARD_H = 62
local GAP = 10
local PROF_CHIPS = { "All", "Herbalism", "Mining", "Fishing", "Skinning" }

local function Text(parent, font, justify)
    local fs = parent:CreateFontString(nil, "OVERLAY", font or "GatherpediaFontHighlight")
    fs:SetJustifyH(justify or "LEFT")
    return fs
end

local function Defaults()
    local db = ns.db
    db.trainers = db.trainers or {}
    if not db.trainers.prof then db.trainers.prof = "All" end
    return db.trainers
end

function TrainersUI:Opts() return Defaults() end

function TrainersUI:SelectedFaction()
    local f = self:Opts().faction
    if f == "Alliance" or f == "Horde" then return f end
    return ns.Trainers:PlayerFaction()
end

function TrainersUI:SetFaction(faction)
    self:Opts().faction = faction
    self:Refresh()
end

-- Kept for callers of the old dropdown: flips between the two factions.
function TrainersUI:ToggleFactionMenu()
    self:SetFaction(self:SelectedFaction() == "Horde" and "Alliance" or "Horde")
end

-- A segmented control: a recessed well holding buttons side by side.
local function Segmented(parent, keys, widths, onPick)
    local well = CreateFrame("Frame", nil, parent)
    well:SetHeight(SEG_H)
    TH:Panel(well, TC.well, TC.line, 8)
    well.buttons = {}
    local x = 3
    for i, key in ipairs(keys) do
        local b = CreateFrame("Button", nil, well)
        b:SetSize(widths[i] or 80, SEG_H - 6)
        b:SetPoint("LEFT", well, "LEFT", x, 0)
        b.key = key
        b.label = Text(b, "GatherpediaFontHighlightSmall", "CENTER")
        local pal = TH.PROF[key]
        if pal then
            b.dot = TH:Dot(b, 7, pal.accent)
            b.dot:SetPoint("LEFT", 10, 0)
            b.label:SetPoint("LEFT", b.dot, "RIGHT", 6, 0)
            b.label:SetPoint("RIGHT", -8, 0)
        else
            b.label:SetPoint("CENTER")
        end
        b.label:SetText(key)
        TH:SkinButton(b, "segment")
        b:SetScript("OnClick", function(btn) onPick(btn.key) end)
        well.buttons[i] = b
        x = x + (widths[i] or 80) + 2
    end
    well:SetWidth(x + 1)
    return well
end

function TrainersUI:Create(parent)
    if self.frame then return self.frame end
    local f = CreateFrame("Frame", "GatherpediaTrainersPage", parent)
    self.frame = f
    f:Hide()

    self.profSeg = Segmented(f, PROF_CHIPS, { 42, 92, 76, 76, 86 }, function(key)
        TrainersUI:Opts().prof = key
        TrainersUI:Refresh()
    end)
    self.profSeg:SetPoint("TOPLEFT", f, "TOPLEFT", 0, 0)
    self.chips = self.profSeg.buttons

    self.factionSeg = Segmented(f, { "Alliance", "Horde" }, { 70, 62 }, function(key)
        TrainersUI:SetFaction(key)
    end)
    self.factionSeg:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, 0)
    -- Older code looks for factionDrop; point it at the toggle.
    self.factionDrop = self.factionSeg

    -- Nearest card.
    local card = CreateFrame("Button", nil, f)
    card:SetHeight(CARD_H)
    card:SetPoint("TOPLEFT", f, "TOPLEFT", 0, -(SEG_H + GAP))
    card:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, -(SEG_H + GAP))
    TH:Panel(card, TC.raised, TC.goldLine, 8)
    card.icon = TH:RoundIcon(card, 34)
    card.icon:SetPoint("LEFT", 14, 0)
    TH:SetRoundIcon(card.icon, "Interface\\Icons\\INV_Misc_Map_01", TC.goldDeep)
    card.kicker = Text(card, "GatherpediaFontLabel")
    card.kicker:SetPoint("TOPLEFT", card.icon, "TOPRIGHT", 12, 4)
    card.kicker:SetText("NEAREST TO YOU")
    card.kicker:SetTextColor(GOLD[1], GOLD[2], GOLD[3])
    card.name = Text(card, "GatherpediaFontHighlightLarge")
    card.name:SetPoint("TOPLEFT", card.kicker, "BOTTOMLEFT", 0, -2)
    if card.name.SetWordWrap then card.name:SetWordWrap(false) end
    card.where = Text(card, "GatherpediaFontHighlightSmall")
    card.where:SetPoint("TOPLEFT", card.name, "BOTTOMLEFT", 0, -2)
    card.where:SetTextColor(TC.text2[1], TC.text2[2], TC.text2[3])
    if card.where.SetWordWrap then card.where:SetWordWrap(false) end
    card.mapBtn = CreateFrame("Button", nil, card)
    card.mapBtn:SetSize(108, 28)
    card.mapBtn:SetPoint("RIGHT", -14, 0)
    card.mapBtn.label = Text(card.mapBtn, "GatherpediaFontNormalSmall", "CENTER")
    card.mapBtn.label:SetPoint("CENTER")
    card.mapBtn.label:SetText("Show on map")
    TH:SkinButton(card.mapBtn, "primary")
    card.name:SetPoint("RIGHT", card.mapBtn, "LEFT", -12, 0)
    card.where:SetPoint("RIGHT", card.mapBtn, "LEFT", -12, 0)
    local function openNearest()
        local e = card.entry
        if e and ns.MapLink then
            ns.MapLink:OpenAt(e.zone, e.x, e.y, e.name, { prof = e.prof, kind = "trainer" })
        end
    end
    card.mapBtn:SetScript("OnClick", openNearest)
    card:SetScript("OnClick", openNearest)
    card.flash = card:CreateTexture(nil, "OVERLAY")
    card.flash:SetPoint("TOPLEFT", 1, -1)
    card.flash:SetPoint("BOTTOMRIGHT", -1, 1)
    card.flash:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], 0)
    card.flash:Hide()
    self.nearestCard = card
    self.result = card

    -- The list sits in one card; the scroll lives inside it.
    local topInset = SEG_H + GAP + CARD_H + GAP
    self.topInset = topInset
    local listBg = CreateFrame("Frame", nil, f)
    listBg:SetPoint("TOPLEFT", f, "TOPLEFT", 0, -topInset)
    listBg:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 0, 4)
    TH:Panel(listBg, TC.card, TC.line, 8)
    self.listBg = listBg
    local Chrome = ns.Chrome
    local scroll, content = Chrome:CreateScroll(f, "GatherpediaTrainersScroll")
    self.scroll, self.content = scroll, content
    Chrome:PlaceScroll(scroll, topInset + 4, 8)

    self.empty = Text(f, "GatherpediaFontDisable", "CENTER")
    self.empty:SetPoint("TOP", listBg, "TOP", 0, -40)
    self.empty:SetText("No trainers match these filters.")
    self.empty:Hide()

    self.rows, self.headers = {}, {}
    -- Kept for older callers that set hint text.
    self.hint = Text(f, "GatherpediaFontDisableSmall")
    self.hint:Hide()
    return f
end

function TrainersUI:Header(i)
    local h = self.headers[i]
    if h then return h end
    h = CreateFrame("Frame", nil, self.content)
    h:SetHeight(HEAD_H)
    h.dot = TH:Dot(h, 7, GOLD)
    h.dot:SetPoint("LEFT", 14, -2)
    h.label = Text(h, "GatherpediaFontLabel")
    h.label:SetPoint("LEFT", 14, -2)
    h.line = h:CreateTexture(nil, "ARTWORK")
    h.line:SetHeight(1)
    h.line:SetPoint("LEFT", h.label, "RIGHT", 10, 0)
    h.line:SetPoint("RIGHT", h, "RIGHT", -14, 0)
    h.line:SetColorTexture(TC.line[1], TC.line[2], TC.line[3], 1)
    self.headers[i] = h
    return h
end

function TrainersUI:Row(i)
    local row = self.rows[i]
    if row then return row end
    row = CreateFrame("Button", nil, self.content)
    row:SetHeight(ROW_H)
    row:EnableMouse(true)
    row.bg = row:CreateTexture(nil, "BACKGROUND")
    row.bg:SetAllPoints()
    row.bg:SetColorTexture(TC.raised[1], TC.raised[2], TC.raised[3], 0)
    row.sep = row:CreateTexture(nil, "BORDER")
    row.sep:SetHeight(1)
    row.sep:SetPoint("TOPLEFT", 0, 0)
    row.sep:SetPoint("TOPRIGHT", 0, 0)
    row.sep:SetColorTexture(TC.rowLine[1], TC.rowLine[2], TC.rowLine[3], 1)

    row.mapBtn = TH:MapButton(row, 24)
    row.mapBtn:SetPoint("RIGHT", -12, 0)
    row.mapBtn:SetScript("OnClick", function()
        local e = row.entry
        if e and row.mapID and ns.MapLink then
            ns.MapLink:OpenAt(e.zone, e.x, e.y, e.name, { prof = e.prof, kind = "trainer" })
        end
    end)
    row.coords = Text(row, "GatherpediaFontDisableSmall", "RIGHT")
    row.coords:SetWidth(70)
    row.coords:SetPoint("RIGHT", row.mapBtn, "LEFT", -10, 0)
    row.coords:SetTextColor(TC.text2[1], TC.text2[2], TC.text2[3])
    row.badge = TH:Badge(row)
    row.badge:SetPoint("RIGHT", row.coords, "LEFT", -10, 0)

    row.guideBtn = CreateFrame("Button", nil, row)
    row.guideBtn:SetSize(56, 18)
    row.guideBtn:SetPoint("RIGHT", row.badge, "LEFT", -8, 0)
    row.guideBtn.label = Text(row.guideBtn, "GatherpediaFontNormalSmall", "RIGHT")
    row.guideBtn.label:SetPoint("RIGHT")
    row.guideBtn.label:SetText("In guide")
    row.guideBtn:Hide()
    row.guideBtn:SetScript("OnClick", function()
        local e = row.entry
        if not e or not ns.Guides or not ns.Guides.FindTrainerGuide then return end
        local fac = TrainersUI:SelectedFaction()
        local prof, key = ns.Guides:FindTrainerGuide(e.name, fac)
        if not prof then return end
        if ns.UI and ns.UI.ShowGuides then ns.UI:ShowGuides() end
        if ns.GuidesUI then
            if fac == "Alliance" or fac == "Horde" then ns.GuidesUI.faction = fac end
            ns.GuidesUI:Show(prof, key)
            if ns.GuidesUI.ScrollToTrainer then ns.GuidesUI:ScrollToTrainer(e.name) end
        end
    end)
    -- The guide link only shows while the row is hovered.
    row.guideBtn:SetScript("OnEnter", function(b) b.label:SetTextColor(TC.goldHi[1], TC.goldHi[2], TC.goldHi[3]) end)
    row.guideBtn:SetScript("OnLeave", function(b)
        b.label:SetTextColor(GOLD[1], GOLD[2], GOLD[3])
        if not row:IsMouseOver() then b:Hide() end
    end)

    row.name = Text(row, "GatherpediaFontHighlight")
    row.name:SetPoint("TOPLEFT", 14, -7)
    row.name:SetPoint("RIGHT", row.guideBtn, "LEFT", -8, 0)
    if row.name.SetWordWrap then row.name:SetWordWrap(false) end
    row.where = Text(row, "GatherpediaFontDisableSmall")
    row.where:SetPoint("TOPLEFT", row.name, "BOTTOMLEFT", 0, -2)
    row.where:SetPoint("RIGHT", row.guideBtn, "LEFT", -8, 0)
    if row.where.SetWordWrap then row.where:SetWordWrap(false) end
    -- Older code paths read these.
    row.meta = row.badge.label
    row.pin = row.mapBtn

    row.flash = row:CreateTexture(nil, "OVERLAY")
    row.flash:SetAllPoints()
    row.flash:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], 0)
    row.flash:Hide()

    row:SetScript("OnEnter", function(r)
        r.bg:SetColorTexture(TC.raised[1], TC.raised[2], TC.raised[3], 1)
        r.name:SetTextColor(TC.goldHi[1], TC.goldHi[2], TC.goldHi[3])
        if r.hasGuide then r.guideBtn:Show() end
        if not r.entry then return end
        local e = r.entry
        GameTooltip:SetOwner(r, "ANCHOR_RIGHT")
        GameTooltip:AddLine(e.name)
        GameTooltip:AddLine(ns.Trainers:WhereText(e), 1, 1, 1)
        if e.rank then GameTooltip:AddLine("Teaches up to " .. e.rank, 0.8, 0.8, 0.8) end
        if e.note then GameTooltip:AddLine(e.note, 1, 1, 1, true) end
        if r.mapID then
            local xy = ns.Trainers:CoordsText(e)
            GameTooltip:AddLine(xy and "Click: open map and mark the spot" or "Click: open map", 0.6, 0.6, 0.6)
        end
        GameTooltip:Show()
    end)
    row:SetScript("OnLeave", function(r)
        r.bg:SetColorTexture(TC.raised[1], TC.raised[2], TC.raised[3], 0)
        r.name:SetTextColor(TC.text[1], TC.text[2], TC.text[3])
        if not r.guideBtn:IsMouseOver() then r.guideBtn:Hide() end
        GameTooltip:Hide()
    end)
    row:SetScript("OnClick", function(r)
        if not r.entry or not r.mapID then return end
        local e = r.entry
        ns.MapLink:OpenAt(e.zone, e.x, e.y, e.name, { prof = e.prof, kind = "trainer" })
    end)
    self.rows[i] = row
    return row
end

-- Badge text and colors for an entry.
local function BadgeFor(e)
    if e.kind == "quest" then
        return (e.rank or "Rank") .. " quest", TH.RANK[e.rank] or TH.RANK.Artisan
    elseif e.kind == "vendor" and e.rank then
        return e.rank .. " book", TH.RANK[e.rank] or TH.RANK.Expert
    elseif e.kind == "vendor" then
        return "Supplies", TH.RANK.Supplies
    elseif e.rank then
        return e.rank, TH.RANK[e.rank] or TH.RANK.Journeyman
    end
    return nil
end

-- Which group an entry belongs to on a single-profession list.
local function GroupOf(e)
    if e.kind == "quest" or (e.kind == "vendor" and e.rank) then return 1 end
    if e.kind == "vendor" then return 3 end
    return 2
end
local GROUP_TITLE = { "Rank-up", "Trainers \194\183 nearest first", "Supplies" }

function TrainersUI:PaintChips(o, fac)
    for _, b in ipairs(self.chips or {}) do
        local on = (o.prof == b.key)
        local pal = TH.PROF[b.key]
        TH:PaintButton(b, on and "segmentOn" or "segment",
            pal and { fill = pal.fill, line = pal.line, text = TC.text } or { fill = TC.goldFill, line = TC.goldLine, text = TC.goldHi })
    end
    for _, b in ipairs(self.factionSeg.buttons) do
        local on = (b.key == fac)
        local pal = TH.FACTION[b.key]
        TH:PaintButton(b, on and "segmentOn" or "segment", pal)
    end
end

function TrainersUI:PaintNearest(o, fac)
    local card = self.nearestCard
    local result, err = ns.Trainers:Closest({
        prof = o.prof, faction = fac, learned = ns.learnedList,
    })
    card.entry = nil
    if err == "no_position" then
        card.name:SetText("Can't tell where you are right now.")
        card.where:SetText("Try again once you are outdoors.")
        card.mapBtn:Hide()
    elseif not result or not result.entry then
        card.name:SetText("No trainer to show.")
        card.where:SetText("")
        card.mapBtn:Hide()
    else
        local e = result.entry
        card.entry = e
        card.name:SetText(e.name)
        local parts = { ns.Trainers:WhereText(e) }
        local badge = BadgeFor(e)
        if badge then parts[#parts + 1] = badge end
        local xy = ns.Trainers:CoordsText(e)
        if xy then parts[#parts + 1] = xy end
        card.where:SetText(table.concat(parts, "  \194\183  "))
        card.mapBtn:SetShown(ns.Zones:MapID(e.zone) and true or false)
    end
    return result and result.entry
end

function TrainersUI:Refresh()
    if not self.frame then return end
    local o = self:Opts()
    local fac = self:SelectedFaction()
    self:PaintChips(o, fac)
    local nearest = self:PaintNearest(o, fac)

    local list = ns.Trainers:Filtered({ prof = o.prof, faction = fac })
    local pos = ns.Trainers:PlayerPosition()
    local width = (self.scroll:GetWidth() or 560)
    if width < 200 then width = 560 end

    -- Sort: group, then distance when we know where the player is.
    local single = (o.prof ~= "All")
    local key = {}
    local profOrder = { Herbalism = 1, Mining = 2, Fishing = 3, Skinning = 4 }
    for i, e in ipairs(list) do
        local yards = math.huge
        if pos then
            local y = ns.Trainers:Distance(pos, e)
            yards = y or math.huge
        end
        key[e] = {
            single and 0 or (profOrder[e.prof] or 9),
            GroupOf(e), yards, i,
        }
    end
    table.sort(list, function(a, b)
        local ka, kb = key[a], key[b]
        for j = 1, 4 do
            if ka[j] ~= kb[j] then return ka[j] < kb[j] end
        end
        return false
    end)

    local y, ri, hi = 0, 0, 0
    local lastHead
    local function head(text, dotColor)
        hi = hi + 1
        local h = self:Header(hi)
        h:ClearAllPoints()
        h:SetPoint("TOPLEFT", self.content, "TOPLEFT", 0, -y)
        h:SetSize(width, HEAD_H)
        h.label:SetText(text:upper())
        h.label:ClearAllPoints()
        if dotColor then
            h.dot:SetVertexColor(dotColor[1], dotColor[2], dotColor[3], 1)
            h.dot:Show()
            h.label:SetPoint("LEFT", h.dot, "RIGHT", 7, 0)
        else
            h.dot:Hide()
            h.label:SetPoint("LEFT", 14, -2)
        end
        h:Show()
        y = y + HEAD_H
    end

    local fguide = ns.Guides and ns.Guides.FindTrainerGuide
    for _, e in ipairs(list) do
        local headKey = single and GroupOf(e) or e.prof
        if headKey ~= lastHead then
            lastHead = headKey
            if single then
                head(GROUP_TITLE[headKey])
            else
                head(e.prof, TH:Prof(e.prof).accent)
            end
        end
        ri = ri + 1
        local row = self:Row(ri)
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", self.content, "TOPLEFT", 0, -y)
        row:SetSize(width, ROW_H)
        row.entry = e
        row.mapID = ns.Zones:MapID(e.zone)
        local isNearest = nearest and e.name == nearest.name and e.zone == nearest.zone
        row.name:SetText(e.name)
        row.name:SetTextColor(TC.text[1], TC.text[2], TC.text[3])
        local where = ns.Trainers:WhereText(e)
        if isNearest then where = where .. "  |cff" .. TH:Hex(TC.green) .. "nearest|r" end
        row.where:SetText(where)
        local text, pal = BadgeFor(e)
        TH:SetBadge(row.badge, text, pal)
        local xy = ns.Trainers:CoordsText(e)
        row.coords:SetText(xy or "")
        row.mapBtn:SetShown(row.mapID and true or false)
        row.hasGuide = fguide and (ns.Guides:FindTrainerGuide(e.name, fac) ~= nil) or false
        row.guideBtn:Hide()
        row.bg:SetColorTexture(TC.raised[1], TC.raised[2], TC.raised[3], 0)
        row:Show()
        y = y + ROW_H
    end
    for i = ri + 1, #self.rows do self.rows[i]:Hide(); self.rows[i].entry = nil end
    for i = hi + 1, #self.headers do self.headers[i]:Hide() end
    self.content:SetSize(width, math.max(y + 6, 1))
    self.empty:SetShown(#list == 0)
    if ns.Chrome then ns.Chrome:UpdateScrollBar(self.scroll) end
end

local function Flash(tex, host, alpha)
    if not tex then return end
    tex:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], alpha)
    tex:Show()
    host._flash = 0.55
    host:SetScript("OnUpdate", function(r, elapsed)
        r._flash = (r._flash or 0) - (elapsed or 0.05)
        if r._flash <= 0 then
            tex:Hide()
            r:SetScript("OnUpdate", nil)
        else
            tex:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], alpha * (r._flash / 0.55))
        end
    end)
end

function TrainersUI:Flash(row)
    if not row or not row.flash then return end
    Flash(row.flash, row, 0.30)
end

function TrainersUI:FindClosest()
    self:ShowClosest()
end

-- Refresh, scroll to the top and flash the Nearest card.
function TrainersUI:ShowClosest(quiet)
    if not self.frame then return end
    self.wantClosest = true
    self:Refresh()
    if ns.Chrome and ns.Chrome.ScrollToTop then ns.Chrome:ScrollToTop(self.scroll) end
    if not quiet then self:Flash(self.nearestCard) end
end

function TrainersUI:Show()
    if not self.frame then return end
    self.frame:Show()
    self:Refresh()
end

function TrainersUI:Hide()
    if self.frame then self.frame:Hide() end
end
