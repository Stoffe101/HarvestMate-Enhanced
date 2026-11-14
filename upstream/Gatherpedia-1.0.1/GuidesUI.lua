-- Gatherpedia: GuidesUI.lua
-- Standalone Guides tool page. Profession chips, Alliance/Horde chips
-- on the same row, then a bracket chip row (your range is marked), then
-- one scroll that reads top to bottom in the order you need it:
--   Where to go     farm spots, your zone first, with Start route / Show on map
--   What you'll find what the range gathers
--   Next rank       the nearest trainer (others on request) or the rank quest
--   Tips            gear and tips
-- The page opens on the range that matches your current skill.

local ADDON, ns = ...
local Guides = ns.Guides
local GuidesUI = {}
ns.GuidesUI = GuidesUI

local TH = ns.Theme
local TC = TH.C
local GOLD   = TC.gold
local WHITE  = "Interface\\Buttons\\WHITE8X8"
local TIP_BORDER = "Interface\\Tooltips\\UI-Tooltip-Border"

local PROF_ORDER = { "Herbalism", "Mining", "Fishing", "Skinning" }
local PROF_CHIP_W = 92
local BRACKET_CHIP_H = 32   -- segmented controls on the top row
local TRACK_H = 62           -- skill track card
local HINT_H = 16
local SECTION_GAP = 10
local HEAD_GAP = 4
local TITLE_GAP = 4
local BLURB_GAP = 10
local STEP_ROW_H = 38
local MAP_BTN_W = 24
local SPOT_ROW_H = 44
local COL_GAP = 12

local function Accent(prof)
    local c = TH:Prof(prof).accent
    return c[1], c[2], c[3]
end

local function Text(parent, template, justify)
    local fs = parent:CreateFontString(nil, "OVERLAY", template or "GatherpediaFontHighlight")
    fs:SetJustifyH(justify or "LEFT")
    return fs
end

-- Same chip language as the profession book and the Trainers page.
local function Chip(parent, w, h)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(w or 80, h or 26)
    b.label = Text(b, "GatherpediaFontHighlightSmall", "CENTER")
    b.label:SetPoint("CENTER")
    TH:SkinButton(b, "quiet")
    return b
end

local function PaintChip(b, on, r, g, bb)
    if not b then return end
    TH:PaintButton(b, on and "selected" or "quiet")
end

local function Measure(fs)
    if not fs then return 0 end
    if fs.GetStringHeight then
        local h = fs:GetStringHeight()
        if h and h > 0 then return h end
    end
    return 14
end

-- Segmented control: buttons side by side in a recessed well.
local function Segmented(parent, keys, widths, onPick, withDots)
    local well = CreateFrame("Frame", nil, parent)
    well:SetHeight(BRACKET_CHIP_H)
    TH:Panel(well, TC.well, TC.line, 8)
    well.buttons = {}
    local x = 3
    for i, key in ipairs(keys) do
        local b = CreateFrame("Button", nil, well)
        b:SetSize(widths[i] or 80, BRACKET_CHIP_H - 6)
        b:SetPoint("LEFT", well, "LEFT", x, 0)
        b.key = key
        b.label = Text(b, "GatherpediaFontHighlightSmall", "CENTER")
        local pal = withDots and TH.PROF[key]
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

function GuidesUI:Create(parent)
    local page = CreateFrame("Frame", "GatherpediaGuidesPage", parent)
    page:Hide()
    self.page = page

    self.profSeg = Segmented(page, PROF_ORDER, { 92, 76, 76, 86 }, function(key)
        self:Show(key)
    end, true)
    self.profSeg:SetPoint("TOPLEFT", page, "TOPLEFT", 0, 0)
    self.profChips = self.profSeg.buttons

    self.factionSeg = Segmented(page, { "Alliance", "Horde" }, { 70, 62 }, function(name)
        self.faction = name
        self:Paint()
    end)
    self.factionSeg:SetPoint("TOPRIGHT", page, "TOPRIGHT", 0, 0)
    self.factionChips = self.factionSeg.buttons

    -- Skill track: one button per range, your position and the rank-ups marked.
    self.bracketRow = CreateFrame("Frame", nil, page)
    self.bracketRow:SetPoint("TOPLEFT", page, "TOPLEFT", 0, -(BRACKET_CHIP_H + 10))
    self.bracketRow:SetPoint("TOPRIGHT", page, "TOPRIGHT", 0, -(BRACKET_CHIP_H + 10))
    self.bracketRow:SetHeight(TRACK_H)
    TH:Panel(self.bracketRow, TC.card, TC.line, 8)
    self.chips = {}
    self.marks = {}
    self.youMark = self.bracketRow:CreateTexture(nil, "OVERLAY")
    self.youMark:SetSize(2, 34)
    self.youMark:SetColorTexture(TC.goldHi[1], TC.goldHi[2], TC.goldHi[3], 1)
    self.youMark:Hide()
    self.youText = Text(self.bracketRow, "GatherpediaFontDisableSmall")
    self.youText:SetTextColor(TC.goldHi[1], TC.goldHi[2], TC.goldHi[3])
    self.youText:Hide()

    self.hint = Text(page, "GatherpediaFontDisableSmall")
    self.hint:SetPoint("TOPLEFT", self.bracketRow, "BOTTOMLEFT", 2, -6)
    self.hint:SetPoint("TOPRIGHT", self.bracketRow, "BOTTOMRIGHT", -8, -6)
    self.hint:SetHeight(HINT_H)
    if self.hint.SetWordWrap then self.hint:SetWordWrap(false) end
    self.hint:SetText("")

    local topInset = (BRACKET_CHIP_H + 10) + TRACK_H + 6 + HINT_H + 4
    self.topInset = topInset
    local Chrome = ns.Chrome
    local scroll, content = Chrome:CreateScroll(page, "GatherpediaGuidesScroll")
    self.scroll, self.content = scroll, content
    Chrome:PlaceScroll(scroll, topInset, 4)

    self.sections = {}
    self.blocks = {}
    return page
end

function GuidesUI:PaintProfChips()
    for _, b in ipairs(self.profChips or {}) do
        local pal = TH:Prof(b.key)
        TH:PaintButton(b, b.key == self.prof and "segmentOn" or "segment",
            { fill = pal.fill, line = pal.line, text = TC.text })
    end
end

function GuidesUI:LayoutTop()
    local topInset = (BRACKET_CHIP_H + 10) + TRACK_H + 6 + HINT_H + 4
    self.topInset = topInset
    if self.scroll and ns.Chrome and ns.Chrome.PlaceScroll then
        ns.Chrome:PlaceScroll(self.scroll, topInset, 4)
    end
end

function GuidesUI:PaintBracketChips()
    local row = self.bracketRow
    local brackets = Guides:Brackets(self.prof)
    local pal = TH:Prof(self.prof)
    local width = (row.GetWidth and row:GetWidth()) or 560
    if width < 200 then width = 560 end
    local n = 0
    for _, br in ipairs(brackets) do
        if br.key ~= "event" then n = n + 1 end
    end
    if n == 0 then n = 1 end
    local pad, gap = 10, 3
    local cw = math.floor((width - pad * 2 - gap * (n - 1)) / n)
    local playerKey = self:PlayerKey()
    local skill = ns.GetPlayerSkill and ns.GetPlayerSkill(self.prof)
    self.youMark:Hide()
    self.youText:Hide()
    local i = 0
    for _, br in ipairs(brackets) do
        if br.key ~= "event" then
            i = i + 1
            local chip = self.chips[i]
            if not chip then
                chip = Chip(row, cw, 28)
                self.chips[i] = chip
            end
            chip:SetSize(cw, 28)
            chip.key = br.key
            chip.label:SetText(((br.label or br.key):gsub("%-", "\226\128\147")))
            chip:ClearAllPoints()
            local x = pad + (i - 1) * (cw + gap)
            chip:SetPoint("TOPLEFT", row, "TOPLEFT", x, -9)
            chip:SetScript("OnClick", function()
                self.key = br.key
                self:Paint()
            end)
            TH:PaintButton(chip, br.key == self.key and "segmentOn" or "quiet",
                { fill = pal.fill, line = pal.line, text = TC.text })
            chip:Show()
            -- Milestone under the range: the rank-up it holds, else its cap.
            local mark = self.marks[i]
            if not mark then
                mark = Text(row, "GatherpediaFontDisableSmall", "RIGHT")
                self.marks[i] = mark
            end
            mark:ClearAllPoints()
            mark:SetPoint("TOPRIGHT", chip, "BOTTOMRIGHT", 0, -4)
            local rank, at = Guides:RankMilestone(self.prof, br.key)
            if rank then
                mark:SetText(rank .. " " .. at)
            elseif i == n then
                mark:SetText("Cap " .. (br.max or ""))
            else
                mark:SetText("")
            end
            mark:Show()
            -- Your position: a gold line on your range, and "You · N" under it.
            if br.key == playerKey and skill and br.min and br.max and br.max > br.min then
                local t = (skill - br.min) / (br.max - br.min)
                if t < 0 then t = 0 elseif t > 1 then t = 1 end
                self.youMark:ClearAllPoints()
                self.youMark:SetPoint("TOP", chip, "TOPLEFT", math.max(2, math.floor(cw * t)), 3)
                self.youMark:Show()
                -- Your exact skill is on the line under the track.
            end
        end
    end
    for j = i + 1, #(self.chips or {}) do
        self.chips[j]:Hide()
        if self.marks[j] then self.marks[j]:Hide() end
    end
    self:LayoutTop()
end

function GuidesUI:Block(i)
    local b = self.blocks[i]
    if b then return b end
    b = {}
    b.head = Text(self.content, "GatherpediaFontLabel")
    b.body = Text(self.content, "GatherpediaFontHighlightSmall")
    b.body:SetTextColor(TC.text2[1], TC.text2[2], TC.text2[3])
    if b.body.SetWordWrap then b.body:SetWordWrap(true) end
    if b.body.SetJustifyV then b.body:SetJustifyV("TOP") end
    if b.body.SetSpacing then b.body:SetSpacing(3) end
    self.blocks[i] = b
    return b
end

function GuidesUI:PaintFactionChips()
    if not self.faction then
        self.faction = Guides:PlayerFaction()
    end
    for _, b in ipairs(self.factionChips or {}) do
        TH:PaintButton(b, b.key == self.faction and "segmentOn" or "segment", TH.FACTION[b.key])
    end
end

-- The bracket key that matches this character's skill, or nil if the
-- profession is not learned.
function GuidesUI:PlayerKey()
    local skill = ns.GetPlayerSkill and ns.GetPlayerSkill(self.prof)
    if not skill or skill < 1 then return nil end
    return Guides:DefaultKey(self.prof, skill)
end

-- One-line status under the chips: your skill and where it sits.
function GuidesUI:StatusText(br)
    local skill = ns.GetPlayerSkill and ns.GetPlayerSkill(self.prof)
    if not skill or skill < 1 then
        return ("You have not learned %s on this character."):format(self.prof or "this profession")
    end
    local where = ""
    if br and br.min and br.max then
        if skill < br.min then
            where = ", below this range"
        elseif skill > br.max then
            where = ", above this range"
        else
            where = ", in this range"
        end
    end
    return ("Your %s skill: %d%s."):format(self.prof, skill, where)
end

local function CurrentZone()
    local z = GetRealZoneText and GetRealZoneText()
    if type(z) == "string" and z ~= "" then return z end
end

-- Farm spots in the order a player wants them: the zone you are in,
-- then the guide's best pick, then spots with a recorded route, then
-- your faction's home zones, then the rest in guide order.
function GuidesUI:SortedSpots(br)
    local faction = self.faction or Guides:PlayerFaction()
    local here = CurrentZone()
    local list = {}
    for i, s in ipairs(Guides:Spots(br, faction) or {}) do
        if not Guides:IsTrainSpot(s) then
            local home = ns.Zones and ns.Zones.FACTION and ns.Zones.FACTION[s.zone]
            list[#list + 1] = {
                spot = s,
                k1 = (here and s.zone == here) and 0 or 1,
                k2 = (s.best and 0 or 1) * 2 + (Guides:HasRoute(s) and 0 or 1),
                k3 = (home == faction) and 0 or ((home == nil) and 1 or 2),
                k4 = i,
            }
        end
    end
    table.sort(list, function(a, b)
        if a.k1 ~= b.k1 then return a.k1 < b.k1 end
        if a.k2 ~= b.k2 then return a.k2 < b.k2 end
        if a.k3 ~= b.k3 then return a.k3 < b.k3 end
        return a.k4 < b.k4
    end)
    return list, here
end

function GuidesUI:Paint()
    self._stepsPainted = nil
    self:PaintProfChips()
    self:PaintFactionChips()
    self:PaintBracketChips()

    local guide = Guides:Get(self.prof, self.key)
    local chrome = ns.Chrome
    local br = Guides:Bracket(self.prof, self.key)
    self.hint:SetText(self:StatusText(br))
    if not guide then
        if self.title then self.title:SetText("No guide for this range yet.") end
        if self.blurb then self.blurb:SetText("") end
        for _, b in ipairs(self.blocks) do
            b.head:Hide(); b.body:Hide()
        end
        for _, row in ipairs(self.rows or {}) do row:Hide(); row.spot = nil end
        for _, row in ipairs(self.trainerRows or {}) do row:Hide(); row.step = nil end
        if self.spotCard then self.spotCard:Hide() end
        if self.tipsCard then self.tipsCard:Hide() end
        self:HideSteps()
        self.content:SetHeight(20)
        chrome:UpdateScrollBar(self.scroll)
        return
    end

    if not self.title then
        self.title = Text(self.content, "GatherpediaFontHeading")
        self.title:SetPoint("TOPLEFT", self.content, "TOPLEFT", 2, -2)
        self.title:SetPoint("TOPRIGHT", self.content, "TOPRIGHT", -2, -2)
    end
    self.title:SetText(guide.title or "")
    if self.title.SetWordWrap then self.title:SetWordWrap(false) end

    if not self.blurb then
        self.blurb = Text(self.content, "GatherpediaFontHighlightSmall")
        self.blurb:SetTextColor(TC.text2[1], TC.text2[2], TC.text2[3])
        if self.blurb.SetWordWrap then self.blurb:SetWordWrap(true) end
        if self.blurb.SetJustifyV then self.blurb:SetJustifyV("TOP") end
    end
    self.blurb:ClearAllPoints()
    local titleH = Measure(self.title)
    self.blurb:SetPoint("TOPLEFT", self.content, "TOPLEFT", 2, -(2 + titleH + TITLE_GAP))
    self.blurb:SetText(guide.blurb or "")
    self.blurb:Show()

    local width = math.max(300, (self.scroll:GetWidth() or 560) - 4)
    self.blurb:SetWidth(width - 4)
    local blurbH = Measure(self.blurb)
    local top = 2 + titleH + TITLE_GAP + blurbH + 12

    -- Two columns: where to go on the left, rank and tips on the right.
    local leftW = math.floor((width - COL_GAP) * 0.58)
    local rightX = leftW + COL_GAP
    local rightW = width - rightX
    local n = 0

    -- Label (small caps) at x, y; optional body text under it. Returns new y.
    local function Label(text, x, y, w)
        n = n + 1
        local b = self:Block(n)
        b.head:ClearAllPoints()
        b.head:SetPoint("TOPLEFT", self.content, "TOPLEFT", x + 2, -y)
        b.head:SetWidth(w)
        b.head:SetText(text:upper())
        b.head:Show()
        b.body:SetText("")
        b.body:Hide()
        return y + Measure(b.head) + 6, b
    end
    local function Body(b, text, x, y, w)
        b.body:ClearAllPoints()
        b.body:SetPoint("TOPLEFT", self.content, "TOPLEFT", x, -y)
        b.body:SetWidth(w)
        b.body:SetText(text)
        b.body:Show()
        return y + Measure(b.body)
    end

    ----------------------------------------------------------------------
    -- Left: Where to go, then What you'll find.
    ----------------------------------------------------------------------
    local ly = top
    local spots, here = self:SortedSpots(br)
    self.rows = self.rows or {}
    local si = 0
    if not self.spotCard then
        self.spotCard = CreateFrame("Frame", nil, self.content)
        TH:Panel(self.spotCard, TC.card, TC.line, 8)
        -- Keep the card under the rows that sit on it.
        self.spotCard:SetFrameLevel(self.content:GetFrameLevel())
    end
    if #spots > 0 then
        ly = Label("Where to go", 0, ly, leftW)
        self.spotCard:ClearAllPoints()
        self.spotCard:SetPoint("TOPLEFT", self.content, "TOPLEFT", 0, -ly)
        self.spotCard:SetSize(leftW, #spots * SPOT_ROW_H + 2)
        self.spotCard:Show()
        local ry = ly + 1
        for _, rec in ipairs(spots) do
            local s = rec.spot
            si = si + 1
            local row = self:SpotRow(si)
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", self.content, "TOPLEFT", 1, -ry)
            row:SetSize(leftW - 2, SPOT_ROW_H)
            row.spot = s
            row.bracket = br
            local isHere = here and s.zone == here
            local name = s.label or s.zone or ""
            if s.best then name = name .. "  |cff" .. TH:Hex(TC.gold) .. "best pick|r" end
            row.left:SetText(name)
            local where = s.zone or ""
            if type(s.x) == "number" and type(s.y) == "number" then
                where = string.format("%s  \194\183  %.0f, %.0f", where, s.x, s.y)
            end
            if isHere then
                row.right:SetText("You are here  \194\183  " .. where)
                row.right:SetTextColor(TC.green[1], TC.green[2], TC.green[3])
                row.bg:SetColorTexture(TC.here[1], TC.here[2], TC.here[3], 1)
            else
                row.right:SetText(where)
                row.right:SetTextColor(TC.text3[1], TC.text3[2], TC.text3[3])
                row.bg:SetColorTexture(0, 0, 0, 0)
            end
            row.sep:SetShown(si > 1)
            local hasRoute = Guides:HasRoute(s)
            local spotMap = s.mapID or (ns.Zones and ns.Zones:MapID(s.zone))
            local beasts = self.prof == "Skinning" and ns.SpawnPins
                and ns.SpawnPins:Has(spotMap, "Skinning")
            row.startBtn.beasts = beasts or nil
            -- Herbalism, Mining, Fishing: a small Nodes / Pools button
            -- beside the route button.
            local nodes = self.prof ~= "Skinning" and ns.SpawnPins and ns.SpawnPins:Has(spotMap, self.prof)
            if nodes then
                local onN = ns.SpawnPins:IsShowing(s.zone, self.prof)
                row.nodesBtn.label:SetText(self.prof == "Fishing" and "Pools" or "Nodes")
                TH:PaintButton(row.nodesBtn, onN and "selected" or "quiet")
                row.nodesBtn:Show()
            else
                row.nodesBtn:Hide()
            end
            if beasts then
                local on = ns.SpawnPins:IsShowing(s.zone, "Skinning")
                row.startBtn.mapOnly = nil
                row.startBtn.label:SetText(on and "Hide beasts" or "Show beasts")
                row.startBtn:SetWidth(92)
                TH:PaintButton(row.startBtn, on and "selected" or (isHere and "primary" or "quiet"))
                row.startBtn:Show()
            elseif hasRoute and self.prof ~= "Fishing" then
                local running = ns.Arrow and ns.Arrow:IsFor(s)
                row.startBtn.mapOnly = nil
                local isCave = Guides:RouteType(s) == "cave"
                row.startBtn.label:SetText(running and "Stop" or (isCave and "Go to cave" or "Start route"))
                row.startBtn:SetWidth(88)
                TH:PaintButton(row.startBtn, running and "selected" or (isHere and "primary" or "quiet"))
                row.startBtn:Show()
            elseif s.zone then
                row.startBtn.mapOnly = true
                row.startBtn.label:SetText("Show on map")
                row.startBtn:SetWidth(92)
                TH:PaintButton(row.startBtn, isHere and "primary" or "quiet")
                row.startBtn:Show()
            else
                row.startBtn:Hide()
            end
            -- Text stops at the leftmost visible button.
            local edge = row.nodesBtn:IsShown() and row.nodesBtn or row.startBtn
            row.left:SetPoint("RIGHT", edge, "LEFT", -10, 0)
            row.right:SetPoint("RIGHT", edge, "LEFT", -10, 0)
            row:Show()
            ry = ry + SPOT_ROW_H
        end
        ly = ry + 1 + SECTION_GAP + 4
    else
        self.spotCard:Hide()
    end
    for i = si + 1, #self.rows do
        self.rows[i]:Hide()
        self.rows[i].spot = nil
    end
    if guide.catches and guide.catches ~= "" then
        local b
        ly, b = Label("What you'll find", 0, ly, leftW)
        ly = Body(b, guide.catches, 2, ly, leftW - 4) + SECTION_GAP
    end

    ----------------------------------------------------------------------
    -- Right: Next rank, then Tips (gear first).
    ----------------------------------------------------------------------
    local ry = top
    local groups = Guides:RankSteps(self.prof, self.key, self.faction or Guides:PlayerFaction())
    local hasSteps = groups and #groups > 0
    if (guide.train and guide.train ~= "") or hasSteps then
        local b
        ry, b = Label("Next rank", rightX, ry, rightW)
        if guide.train and guide.train ~= "" then
            ry = Body(b, guide.train, rightX + 2, ry, rightW - 4) + 8
        end
        ry = self:PaintSteps(ry, rightW - 8, groups, rightX)
    else
        self:HideSteps()
    end

    local tips = guide.gear or ""
    if guide.tips and guide.tips ~= "" then
        tips = (tips ~= "" and (tips .. "\n\n") or "") .. guide.tips
    end
    if not self.tipsCard then
        self.tipsCard = CreateFrame("Frame", nil, self.content)
        TH:Panel(self.tipsCard, TC.card, TC.line, 8)
    end
    if tips ~= "" then
        ry = Label("Tips", rightX, ry, rightW)
        -- The text belongs to the card so it draws on top of it.
        local card = self.tipsCard
        if not card.text then
            card.text = Text(card, "GatherpediaFontHighlightSmall")
            card.text:SetTextColor(TC.text2[1], TC.text2[2], TC.text2[3])
            if card.text.SetWordWrap then card.text:SetWordWrap(true) end
            if card.text.SetJustifyV then card.text:SetJustifyV("TOP") end
            if card.text.SetSpacing then card.text:SetSpacing(3) end
            card.text:SetPoint("TOPLEFT", 12, -10)
        end
        card.text:SetWidth(rightW - 24)
        card.text:SetText(tips)
        local textH = Measure(card.text)
        card:ClearAllPoints()
        card:SetPoint("TOPLEFT", self.content, "TOPLEFT", rightX, -ry)
        card:SetSize(rightW, textH + 20)
        card:Show()
        ry = ry + textH + 20 + SECTION_GAP
    else
        self.tipsCard:Hide()
    end

    -- Trainers are listed under Next rank.
    for _, row in ipairs(self.trainerRows or {}) do
        row:Hide()
        row.step = nil
    end
    for i = n + 1, #(self.blocks or {}) do
        self.blocks[i].head:Hide()
        self.blocks[i].body:Hide()
    end

    local y = math.max(ly, ry)
    self.content:SetHeight(y + 8)
    self.content:SetWidth(width)
    chrome:UpdateScrollBar(self.scroll)
end

function GuidesUI:TrainerRow(i)
    self.trainerRows = self.trainerRows or {}
    local row = self.trainerRows[i]
    if row then return row end
    row = CreateFrame("Button", nil, self.content)
    row:SetHeight(26)
    row:EnableMouse(true)
    row.left = Text(row, "GatherpediaFontHighlight")
    row.left:SetPoint("LEFT", 8, 0)
    row.left:SetTextColor(1, 1, 1)
    if row.left.SetWordWrap then row.left:SetWordWrap(false) end
    row.right = Text(row, "GatherpediaFontDisableSmall", "RIGHT")
    row.right:SetTextColor(0.70, 0.64, 0.50)
    if row.right.SetWordWrap then row.right:SetWordWrap(false) end
    row.pin = row:CreateTexture(nil, "ARTWORK")
    row.pin:SetSize(10, 10)
    row.pin:SetPoint("RIGHT", -4, 0)
    row.pin:SetTexture("Interface\\Icons\\INV_Misc_Map_01")
    row.pin:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    row.hl = row:CreateTexture(nil, "HIGHLIGHT")
    row.hl:SetAllPoints()
    row.hl:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], 0.12)
    row:SetScript("OnClick", function(r)
        local s = r.step
        if not s or not s.zone or not ns.MapLink then return end
        ns.MapLink:OpenAt(s.zone, s.x, s.y, s.label or s.who or s.zone, {
            prof = GuidesUI.prof, kind = "trainer",
        })
    end)
    self.trainerRows[i] = row
    return row
end

function GuidesUI:PaintTrainers(y, width, n)
    self._trainerY, self._trainerH, self._trainerBlock = nil, nil, nil
    self.trainerRows = self.trainerRows or {}
    local trainers = Guides:BracketTrainers(self.prof, self.key, self.faction or Guides:PlayerFaction())
    if not trainers or #trainers == 0 then
        for i = 1, #self.trainerRows do
            self.trainerRows[i]:Hide()
            self.trainerRows[i].step = nil
        end
        if self.trainerFlash then self.trainerFlash:Hide() end
        return y, n
    end
    n = (n or 0) + 1
    local b = self:Block(n)
    self._trainerBlock = n
    self._trainerY = y
    b.head:ClearAllPoints()
    b.head:SetPoint("TOPLEFT", self.content, "TOPLEFT", 8, -y)
    b.head:SetPoint("TOPRIGHT", self.content, "TOPRIGHT", -8, -y)
    b.head:SetText("TRAINER")
    b.head:Show()
    b.body:SetText("")
    b.body:Hide()
    y = y + Measure(b.head) + HEAD_GAP
    for i, s in ipairs(trainers) do
        local row = self:TrainerRow(i)
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", self.content, "TOPLEFT", 4, -y)
        row:SetPoint("TOPRIGHT", self.content, "TOPRIGHT", -4, -y)
        row:SetHeight(26)
        row.step = s
        row.left:SetText(s.who or s.label or "")
        row.right:SetText(s.where or s.zone or "")
        local hasPin = type(s.x) == "number" and type(s.y) == "number"
        row.pin:SetShown(hasPin and true or false)
        row.right:ClearAllPoints()
        row.right:SetPoint("RIGHT", hasPin and -18 or -6, 0)
        row.right:SetPoint("LEFT", row, "CENTER", 4, 0)
        row:Show()
        y = y + 26
    end
    for i = #trainers + 1, #self.trainerRows do
        self.trainerRows[i]:Hide()
        self.trainerRows[i].step = nil
    end
    self._trainerH = (y - (self._trainerY or y))
    return y + 4, n
end

function GuidesUI:FlashTrainer()
    if not self.content or not self._trainerY then return end
    local hl = self.trainerFlash
    if not hl then
        hl = CreateFrame("Frame", nil, self.content)
        local tex = hl:CreateTexture(nil, "ARTWORK")
        tex:SetAllPoints()
        tex:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], 0.22)
        hl.tex = tex
        self.trainerFlash = hl
    end
    hl:ClearAllPoints()
    hl:SetPoint("TOPLEFT", self.content, "TOPLEFT", 2, -(self._trainerY or 0))
    hl:SetPoint("TOPRIGHT", self.content, "TOPRIGHT", -2, -(self._trainerY or 0))
    hl:SetHeight(self._trainerH or 40)
    hl:SetFrameLevel((self.content.GetFrameLevel and self.content:GetFrameLevel() or 1) + 6)
    hl:SetAlpha(0.7)
    hl:Show()
    hl.t = 0
    hl:SetScript("OnUpdate", function(f, dt)
        f.t = (f.t or 0) + (dt or 0)
        if f.t >= 1.2 then
            f:Hide()
            f:SetScript("OnUpdate", nil)
            return
        end
        if f.t > 0.5 then
            f:SetAlpha(0.7 * (1 - (f.t - 0.5) / 0.7))
        end
    end)
end

function GuidesUI:ScrollToTrainer(name)
    -- A trainer other than the nearest is hidden until the list expands.
    if name then self.showAllTrainers = true end
    if not self.page or not self.page:IsShown() then
        if ns.UI and ns.UI.ShowGuides then ns.UI:ShowGuides() end
        self:Show(self.prof, self.key)
    else
        self:Paint()
    end
    local scroll = self.scroll
    if scroll and self._trainerY and scroll.SetVerticalScroll then
        local range = (scroll.GetVerticalScrollRange and scroll:GetVerticalScrollRange()) or 0
        local dest = self._trainerY
        if dest < 0 then dest = 0 end
        if range and dest > range then dest = range end
        scroll:SetVerticalScroll(dest)
    end
    self:FlashTrainer()
end

function GuidesUI:HideSteps()
    self._stepsPainted = nil
    if self.stepHead then self.stepHead:Hide() end
    for _, box in ipairs(self.stepBoxes or {}) do
        box:Hide()
    end
    for _, row in ipairs(self.stepRows or {}) do
        row:Hide()
        row.step = nil
    end
end

function GuidesUI:StepBox(i)
    self.stepBoxes = self.stepBoxes or {}
    local box = self.stepBoxes[i]
    if box then return box end
    box = CreateFrame("Frame", nil, self.content)
    TH:Panel(box, TC.card, TC.line, 8)
    box.head = Text(box, "GatherpediaFontHeading")
    box.head:SetTextColor(TC.text[1], TC.text[2], TC.text[3])
    box.head:SetPoint("TOPLEFT", 12, -10)
    box.head:SetPoint("TOPRIGHT", -12, -10)
    box.sub = Text(box, "GatherpediaFontDisableSmall")
    box.sub:SetTextColor(TC.text2[1], TC.text2[2], TC.text2[3])
    if box.sub.SetWordWrap then box.sub:SetWordWrap(true) end
    if box.sub.SetJustifyV then box.sub:SetJustifyV("TOP") end
    self.stepBoxes[i] = box
    return box
end

function GuidesUI:StepRow(i)
    self.stepRows = self.stepRows or {}
    local row = self.stepRows[i]
    if row then return row end
    row = CreateFrame("Frame", nil, self.content)
    row:SetHeight(STEP_ROW_H)
    row.bg = row:CreateTexture(nil, "BACKGROUND")
    row.bg:SetAllPoints()
    row.bg:SetColorTexture(0, 0, 0, 0)
    row.num = Text(row, "GatherpediaFontNormalSmall")
    row.num:SetPoint("TOPLEFT", 0, -5)
    row.num:SetWidth(16)
    row.num:SetJustifyH("RIGHT")
    row.title = Text(row, "GatherpediaFontHighlightSmall")
    row.title:SetPoint("TOPLEFT", row.num, "TOPRIGHT", 6, 0)
    if row.title.SetWordWrap then row.title:SetWordWrap(true) end
    if row.title.SetJustifyV then row.title:SetJustifyV("TOP") end
    row.where = Text(row, "GatherpediaFontDisableSmall")
    if row.where.SetWordWrap then row.where:SetWordWrap(false) end
    row.needed = Text(row, "GatherpediaFontDisableSmall")
    row.needed:SetText("Pin needed")
    if row.needed.SetWordWrap then row.needed:SetWordWrap(false) end
    row.mapBtn = TH:MapButton(row, MAP_BTN_W)
    row.mapBtn:SetPoint("TOPRIGHT", 0, -4)
    row.mapBtn:SetScript("OnClick", function()
        local s = row.step
        if not s or not s.zone or not ns.MapLink then return end
        if type(s.x) ~= "number" or type(s.y) ~= "number" then return end
        local kind = s.who and "trainer" or "spot"
        ns.MapLink:OpenAt(s.zone, s.x, s.y, s.label or s.who or s.title or s.zone, {
            prof = GuidesUI.prof, kind = kind,
        })
    end)
    row:EnableMouse(true)
    row:SetScript("OnMouseUp", function()
        local s = row.step
        if s and s.who then
            GuidesUI:ScrollToTrainer(s.who)
        end
    end)
    self.stepRows[i] = row
    return row
end

-- Numbered checklist after the Train paragraph. Returns the new y offset.
-- Safe to call more than once in a paint: later calls are no-ops.
function GuidesUI:PaintSteps(y, width, groups, x)
    if self._stepsPainted then return y end
    self._stepsPainted = true
    self._trainerY, self._trainerH = nil, nil
    groups = groups or Guides:RankSteps(self.prof, self.key, self.faction or Guides:PlayerFaction())
    if not groups or #groups == 0 then
        self:HideSteps()
        -- HideSteps clears the painted flag; keep it set so a second call
        -- from Paint does not run again in this pass.
        self._stepsPainted = true
        return y
    end
    -- The "Next rank" heading is drawn by Paint.
    if self.stepHead then self.stepHead:Hide() end
    self._trainerY = y

    local innerW = math.max(160, width - 8)
    local ri, bi = 0, 0
    for _, g in ipairs(groups) do
        bi = bi + 1
        local box = self:StepBox(bi)
        box:ClearAllPoints()
        box:SetPoint("TOPLEFT", self.content, "TOPLEFT", x or 4, -y)
        box:SetWidth(width + 8)
        box.head:SetText(g.heading or "")
        box.sub:ClearAllPoints()
        local headH = Measure(box.head)
        box.sub:SetPoint("TOPLEFT", box, "TOPLEFT", 12, -(10 + headH + 2))
        box.sub:SetPoint("TOPRIGHT", box, "TOPRIGHT", -12, -(10 + headH + 2))
        box.sub:SetWidth(innerW - 12)
        box.sub:SetText(g.sub or "")
        local subH = Measure(box.sub)
        local innerY = 10 + headH + 2 + subH + 8
        local gi = 0
        local allRows = g.rows or {}
        local shown = allRows
        local extra = 0
        if g.collapsible and not self.showAllTrainers and #allRows > 1 then
            shown = { allRows[1] }
            extra = #allRows - 1
        end
        for _, step in ipairs(shown) do
            gi = gi + 1
            ri = ri + 1
            local row = self:StepRow(ri)
            row:SetParent(box)
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", box, "TOPLEFT", 10, -innerY)
            row:SetPoint("TOPRIGHT", box, "TOPRIGHT", -10, -innerY)
            -- The nearest trainer sits on a raised strip.
            local lead = g.collapsible and gi == 1 and #allRows > 1
            row.bg:SetColorTexture(TC.raised[1], TC.raised[2], TC.raised[3], lead and 1 or 0)
            row.step = step
            row.num:SetText(g.collapsible and "" or (tostring(gi) .. "."))
            local hasPin = type(step.x) == "number" and type(step.y) == "number"
            local title = step.title or step.who or ""
            if g.collapsible and gi == 1 and g.located and #allRows > 1 then
                title = title .. "  |cff4de05cnearest|r"
            end
            row.title:ClearAllPoints()
            row.title:SetPoint("TOPLEFT", row.num, "TOPRIGHT", 6, 0)
            if hasPin then
                row.mapBtn:Show()
                row.needed:Hide()
                row.title:SetPoint("TOPRIGHT", row.mapBtn, "TOPLEFT", -8, 0)
                row.title:SetWidth(math.max(80, innerW - 18 - MAP_BTN_W - 8))
            else
                row.mapBtn:Hide()
                row.needed:Show()
                row.needed:ClearAllPoints()
                row.needed:SetPoint("TOPRIGHT", 0, -2)
                row.title:SetPoint("TOPRIGHT", row.needed, "TOPLEFT", -8, 0)
                local nw = (row.needed.GetStringWidth and row.needed:GetStringWidth()) or 70
                row.title:SetWidth(math.max(80, innerW - 18 - nw - 8))
            end
            row.title:SetText(title)
            local titleH = math.max(12, Measure(row.title))
            row.where:ClearAllPoints()
            row.where:SetPoint("TOPLEFT", row.title, "BOTTOMLEFT", 0, -1)
            if hasPin then
                row.where:SetPoint("RIGHT", row.mapBtn, "LEFT", -8, 0)
                row.where:SetText(step.where or "")
            else
                -- "Pin needed" sits on the right; the place name stays on the left.
                row.where:SetPoint("RIGHT", row.needed, "LEFT", -8, 0)
                local place = step.where or step.zone or ""
                row.where:SetText(place)
            end
            local whereH = ((row.where:GetText() or "") ~= "" and Measure(row.where)) or 0
            local h = math.max(STEP_ROW_H, 4 + titleH + 1 + whereH + 6)
            row:SetHeight(h)
            row:Show()
            innerY = innerY + h
        end
        if not box.more then
            box.more = CreateFrame("Button", nil, box)
            box.more:SetHeight(16)
            box.more.label = Text(box.more, "GatherpediaFontNormalSmall")
            box.more.label:SetPoint("LEFT")
            box.more.label:SetTextColor(GOLD[1], GOLD[2], GOLD[3])
            box.more:SetScript("OnEnter", function(b) b.label:SetTextColor(1, 1, 1) end)
            box.more:SetScript("OnLeave", function(b) b.label:SetTextColor(GOLD[1], GOLD[2], GOLD[3]) end)
            box.more:SetScript("OnClick", function()
                GuidesUI.showAllTrainers = not GuidesUI.showAllTrainers
                GuidesUI:Paint()
            end)
        end
        if g.collapsible and #allRows > 1 then
            box.more:ClearAllPoints()
            box.more:SetPoint("TOPLEFT", box, "TOPLEFT", 14, -innerY)
            box.more:SetPoint("RIGHT", box, "RIGHT", -10, 0)
            if extra > 0 then
                box.more.label:SetText(("Show %d more trainer%s"):format(extra, extra == 1 and "" or "s"))
            else
                box.more.label:SetText("Show only the nearest")
            end
            box.more:Show()
            innerY = innerY + 18
        else
            box.more:Hide()
        end
        box:SetHeight(innerY + 6)
        box:Show()
        y = y + innerY + 6 + SECTION_GAP
    end
    for i = bi + 1, #(self.stepBoxes or {}) do
        self.stepBoxes[i]:Hide()
    end
    for i = ri + 1, #(self.stepRows or {}) do
        self.stepRows[i]:Hide()
        self.stepRows[i].step = nil
    end
    return y
end

function GuidesUI:SpotRow(i)
    local row = self.rows and self.rows[i]
    if row then return row end
    self.rows = self.rows or {}
    row = CreateFrame("Button", nil, self.content)
    row:SetHeight(SPOT_ROW_H)
    row:EnableMouse(true)
    row.bg = row:CreateTexture(nil, "BACKGROUND")
    row.bg:SetAllPoints()
    row.bg:SetColorTexture(0, 0, 0, 0)
    row.sep = row:CreateTexture(nil, "BORDER")
    row.sep:SetHeight(1)
    row.sep:SetPoint("TOPLEFT", 0, 0)
    row.sep:SetPoint("TOPRIGHT", 0, 0)
    row.sep:SetColorTexture(TC.rowLine[1], TC.rowLine[2], TC.rowLine[3], 1)
    row.startBtn = Chip(row, 88, 24)
    row.startBtn.label:SetText("Start route")
    row.startBtn:SetPoint("RIGHT", -10, 0)
    row.startBtn:Hide()
    row.nodesBtn = Chip(row, 58, 24)
    row.nodesBtn.label:SetText("Nodes")
    row.nodesBtn:SetPoint("RIGHT", row.startBtn, "LEFT", -6, 0)
    row.nodesBtn:Hide()
    row.nodesBtn:SetScript("OnClick", function()
        if row.spot then GuidesUI:ToggleNodes(row.spot, row.bracket) end
    end)
    row.nodesBtn:SetScript("OnEnter", function(b)
        if not GameTooltip then return end
        GameTooltip:SetOwner(b, "ANCHOR_TOP")
        GameTooltip:AddLine(GuidesUI.prof == "Fishing" and "Show fishing pools on the map"
            or "Show every node for this range on the map", 1, 1, 1)
        GameTooltip:Show()
    end)
    row.nodesBtn:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
    row.startBtn:SetScript("OnClick", function(b)
        local s = row.spot
        if not s then return end
        if b.beasts then
            GuidesUI:ToggleBeasts(s, row.bracket)
            return
        end
        if b.mapOnly or GuidesUI.prof == "Fishing" then
            if not s.zone or not ns.MapLink then return end
            local x, y
            if Guides.PinCoords then x, y = Guides:PinCoords(s) end
            ns.MapLink:OpenAt(s.zone, x, y, s.label or s.zone, { prof = GuidesUI.prof, kind = "spot" })
            return
        end
        if not ns.Arrow then return end
        if ns.Arrow:IsFor(s) then
            ns.Arrow:Stop()
        else
            if ns.Arrow:Start(s) and ns.RouteOverlay and ns.RouteOverlay.FocusRouteMap then
                -- Open the map on the route; the window docks to its right.
                ns.RouteOverlay:FocusRouteMap(true)
            end
        end
        if GuidesUI.page and GuidesUI.page:IsShown() then
            GuidesUI:Paint()
        end
    end)
    row.left = Text(row, "GatherpediaFontHighlight")
    row.left:SetPoint("TOPLEFT", 12, -7)
    row.left:SetPoint("RIGHT", row.startBtn, "LEFT", -10, 0)
    if row.left.SetWordWrap then row.left:SetWordWrap(false) end
    row.right = Text(row, "GatherpediaFontDisableSmall")
    row.right:SetPoint("TOPLEFT", row.left, "BOTTOMLEFT", 0, -2)
    row.right:SetPoint("RIGHT", row.startBtn, "LEFT", -10, 0)
    if row.right.SetWordWrap then row.right:SetWordWrap(false) end
    -- Older code reads these; they are not drawn any more.
    row.status = Text(row, "GatherpediaFontDisableSmall")
    row.status:Hide()
    row.pin = row:CreateTexture(nil, "ARTWORK")
    row.pin:Hide()
    row:SetScript("OnEnter", function(r)
        r.left:SetTextColor(TC.goldHi[1], TC.goldHi[2], TC.goldHi[3])
    end)
    row:SetScript("OnLeave", function(r)
        r.left:SetTextColor(TC.text[1], TC.text[2], TC.text[3])
    end)
    row:SetScript("OnClick", function(r)
        if not r.spot or not r.spot.zone or not ns.MapLink then return end
        local s = r.spot
        if r.startBtn and r.startBtn.beasts then
            GuidesUI:ToggleBeasts(s, r.bracket, true)
            return
        end
        local x, y = Guides:PinCoords(s)
        ns.MapLink:OpenAt(s.zone, x, y, s.label or s.zone, { prof = GuidesUI.prof, kind = "spot" })
    end)
    self.rows[i] = row
    return row
end

-- Skinning: open the map on the spot's zone with a pin on every beast
-- spawn that suits this range. Clicking again hides them; a row click
-- always shows.
function GuidesUI:ToggleBeasts(s, br, showOnly)
    if not (s and ns.SpawnPins) then return end
    local SP = ns.SpawnPins
    if not showOnly and SP:IsShowing(s.zone, "Skinning") then
        SP:Clear()
    else
        SP:Show({
            prof = "Skinning", zone = s.zone, mapID = s.mapID,
            smin = br and br.min, smax = br and br.max,
        })
    end
    if self.page and self.page:IsShown() then self:Paint() end
end

-- Herbalism, Mining, Fishing: every node (or pool) on the spot's map that
-- suits this range. Works alongside a running route.
function GuidesUI:ToggleNodes(s, br)
    if not (s and ns.SpawnPins) then return end
    local SP, prof = ns.SpawnPins, self.prof
    if SP:IsShowing(s.zone, prof) then
        SP:Clear()
    else
        SP:Show({
            prof = prof, zone = s.zone, mapID = s.mapID,
            smin = br and br.min, smax = br and br.max,
        })
    end
    if self.page and self.page:IsShown() then self:Paint() end
end

-- Opens on the range for this character's current skill. Pass `key`
-- to land on a specific range instead (the Trainers page does this).
function GuidesUI:Show(prof, key)
    if not self.page then return end
    local newProf = prof or self.prof or Guides:DefaultProfession()
    if newProf ~= self.prof then self.showAllTrainers = nil end
    self.prof = newProf
    if not self.faction then
        self.faction = Guides:PlayerFaction()
    end
    if key and Guides:Bracket(self.prof, key) then
        self.key = key
    else
        local skill = ns.GetPlayerSkill and ns.GetPlayerSkill(self.prof)
        self.key = Guides:DefaultKey(self.prof, skill)
    end
    self.page:Show()
    self:Paint()
end

function GuidesUI:Refresh()
    self:Paint()
end

function GuidesUI:Hide()
    if self.page then self.page:Hide() end
end
