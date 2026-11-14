-- Gatherpedia: SessionUI.lua
-- Draws "This Session" in the sidebar box and in the optional floating box,
-- and builds their settings menu. The menu opens on hover (short delay) or
-- on right-click. Numbers come from Session.lua.

local ADDON_NAME, ns = ...

local SessionUI = {}
ns.SessionUI = SessionUI

local GOLD = { 0.90, 0.75, 0.38 }
local MUTED_HEX = "9a8f78"
local MAX_LINES = 7
local MAX_ZONE_ROWS = 6
SessionUI.boxes = {}

local function Opts() return ns.Session:Opts() end

---------------------------------------------------------------------------
-- Box (used twice: sidebar and floating)
---------------------------------------------------------------------------

function SessionUI:CreateBox(parent, width, height, floating)
    local box = CreateFrame("Frame", floating and "GatherpediaSessionFrame" or nil, parent, "BackdropTemplate")
    box:SetSize(width, height)
    box:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1, insets = { left = 1, right = 1, top = 1, bottom = 1 } })
    box:SetBackdropColor(0, 0, 0, floating and 0.75 or 0.35)
    box:SetBackdropBorderColor(GOLD[1], GOLD[2], GOLD[3], floating and 0.8 or 0.35)
    box.floating = floating
    box.width = width
    if floating and ns.Theme then
        ns.Theme:Panel(box, ns.Theme.C.window, ns.Theme.C.frame, 8)
    elseif not floating then
        -- Recessed card at the foot of the sidebar.
        if ns.Chrome and ns.Chrome.ApplyCard then
            ns.Chrome:ApplyCard(box, "session")
        else
            box:SetBackdropColor(0.204, 0.153, 0.094, 1)
            box:SetBackdropBorderColor(0.43, 0.35, 0.16, 1)
        end
    end
    box.head = box:CreateFontString(nil, "OVERLAY", "GatherpediaFontNormalSmall")
    box.head:SetPoint("TOPLEFT", 10, -9)
    box.lines = {}
    for i = 1, MAX_LINES do
        local l = {}
        l.icon = box:CreateTexture(nil, "ARTWORK")
        l.icon:SetSize(13, 13)
        l.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
        l.label = box:CreateFontString(nil, "OVERLAY", "GatherpediaFontHighlightSmall")
        l.label:SetJustifyH("LEFT")
        l.value = box:CreateFontString(nil, "OVERLAY", "GatherpediaFontHighlightSmall")
        l.value:SetJustifyH("RIGHT")
        l.value:SetPoint("RIGHT", box, "RIGHT", -10, 0)
        box.lines[i] = l
    end
    box.lastIcon = box:CreateTexture(nil, "ARTWORK")
    box.lastIcon:SetSize(22, 22)
    box.lastIcon:SetPoint("BOTTOMLEFT", 10, 10)
    box.last = box:CreateFontString(nil, "OVERLAY", "GatherpediaFontHighlightSmall")
    box.last:SetPoint("LEFT", box.lastIcon, "RIGHT", 6, 0)
    box.last:SetWidth(width - 52)
    box.last:SetWordWrap(false)
    box.last:SetJustifyH("LEFT")

    -- Stone-frame 2x2 dashboard (sidebar only). Hidden on the floating box.
    box.idle = box:CreateFontString(nil, "OVERLAY", "GatherpediaFontHighlightSmall")
    box.idle:SetPoint("TOPRIGHT", -8, -8)
    box.idle:SetTextColor(1, 0.60, 0.24)
    box.idle:Hide()
    box.cells = {}
    for i = 1, 4 do
        local c = CreateFrame("Frame", nil, box, "BackdropTemplate")
        c:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8",
            edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1,
            insets = { left = 1, right = 1, top = 1, bottom = 1 } })
        -- Individual cells have no chrome; the box plus the cross-hair
        -- dividers form the recessed 2x2 grid from Concept 3.
        c:SetBackdropColor(0, 0, 0, 0)
        c:SetBackdropBorderColor(0, 0, 0, 0)
        c.lab = c:CreateFontString(nil, "OVERLAY", "GatherpediaFontNormalSmall")
        c.lab:SetPoint("TOP", 0, -4)
        c.lab:SetTextColor(0.69, 0.59, 0.39)
        c.val = c:CreateFontString(nil, "OVERLAY", "GatherpediaFontHighlight")
        c.val:SetPoint("BOTTOM", 0, 6)
        c.val:SetJustifyH("CENTER")
        if c.val.SetWordWrap then c.val:SetWordWrap(true) end
        c.detail = c:CreateFontString(nil, "OVERLAY", "GatherpediaFontHighlightSmall")
        c.detail:SetPoint("BOTTOM", 0, 3)
        c.detail:SetTextColor(0.90, 0.82, 0.58)
        c.detail:SetJustifyH("CENTER")
        if c.detail.SetWordWrap then c.detail:SetWordWrap(true) end
        c.detail:Hide()
        box.cells[i] = c
    end
    -- Skill-ups tile: hover shows per-profession from/to ranks.
    -- The settings menu is not auto-opened from this cell so the tooltip
    -- isn't covered; right-click still opens it.
    do
        local skillCell, owner = box.cells[3], box
        if skillCell then
            skillCell:EnableMouse(true)
            skillCell:SetScript("OnEnter", function(self)
                if ns.Menu and ns.Menu.CancelTimers then ns.Menu:CancelTimers() end
                SessionUI:ShowSkillUpTooltip(self)
            end)
            skillCell:SetScript("OnLeave", function(self)
                if GameTooltip and GameTooltip.Hide then GameTooltip:Hide() end
                if owner:IsMouseOver() then SessionUI:OnBoxEnter(owner) end
            end)
            skillCell:SetScript("OnMouseUp", function(_, button)
                if button == "RightButton" then
                    if GameTooltip and GameTooltip.Hide then GameTooltip:Hide() end
                    SessionUI:OnRightClick(owner)
                end
            end)
        end
    end
    box.gridV = box:CreateTexture(nil, "ARTWORK")
    box.gridV:SetWidth(1)
    box.gridV:SetColorTexture(0.43, 0.35, 0.16, 0.55)
    box.gridV:Hide()
    box.gridH = box:CreateTexture(nil, "ARTWORK")
    box.gridH:SetHeight(1)
    box.gridH:SetColorTexture(0.43, 0.35, 0.16, 0.55)
    box.gridH:Hide()
    box.gridFrame = CreateFrame("Frame", nil, box, "BackdropTemplate")
    box.gridFrame:SetBackdrop({ edgeFile = "Interface\Buttons\WHITE8X8", edgeSize = 1 })
    do
        local c = ns.Theme and ns.Theme.C.line or { 0.43, 0.35, 0.16 }
        box.gridFrame:SetBackdropBorderColor(c[1], c[2], c[3], ns.Theme and 1 or 0.55)
    end
    box.gridFrame:Hide()
    box.prompt = box:CreateFontString(nil, "OVERLAY", "GatherpediaFontDisableSmall")
    box.prompt:SetPoint("BOTTOM", 0, 8)
    box.prompt:SetTextColor(0.69, 0.59, 0.39)

    box:EnableMouse(true)
    box:SetScript("OnMouseUp", function(self, button)
        if button == "RightButton" then SessionUI:OnRightClick(self) end
    end)
    box:SetScript("OnEnter", function(self) SessionUI:OnBoxEnter(self) end)
    box:SetScript("OnLeave", function(self) SessionUI:OnBoxLeave(self) end)
    self.boxes[#self.boxes + 1] = box
    return box
end

local function DashClock(sec)
    sec = math.floor(sec or 0)
    local h, m, s = math.floor(sec / 3600), math.floor((sec % 3600) / 60), sec % 60
    if h > 0 then return ("%d:%02d:%02d"):format(h, m, s) end
    return ("%d:%02d"):format(m, s)
end

function SessionUI:RenderDashboard(box)
    local o = Opts()
    local s = ns.session
    box.head:ClearAllPoints()
    box.head:SetPoint("TOPLEFT", 8, -8)
    box.head:SetText("THIS SESSION")
    local tag
    if s.paused then
        if s.autoPaused == "afk" then tag = "AFK"
        elseif s.autoPaused then tag = "Idle"
        else tag = "Paused" end
    end
    if box.idle then
        if tag then box.idle:SetText(tag); box.idle:Show() else box.idle:Hide() end
    end
    -- Hide the linear list; the 2x2 cells take its place.
    for _, l in ipairs(box.lines or {}) do
        l.icon:Hide(); l.label:Hide(); l.value:Hide()
    end
    if box.lastIcon then box.lastIcon:Hide() end

    local prof = o.prof
    local n = ns.Session:Count(prof)
    local per = ns.Session:PerHour(n)
    local skillVal, skillDetail = ns.Session:SkillUpSummary(prof)
    local elapsed = ns.Session:Elapsed()
    local stats = {
        { "GATHERS", ns.Session:FormatNumber(n) },
        { "PER HOUR", per and ns.Session:FormatNumber(per) or "\226\128\148" },
        { "SKILL-UPS", skillVal, skillDetail },
        { "TIME", DashClock(elapsed) },
    }
    -- Keep lines[1] populated so callers can still read a label/value.
    if box.lines and box.lines[1] then
        box.lines[1].label:SetText("Gathers")
        box.lines[1].value:SetText(stats[1][2])
    end
    local pad, gap, top, bot = 8, 0, 26, 24
    local innerW = (box.width or box:GetWidth() or 168) - pad * 2
    local innerH = (box:GetHeight() or 148) - top - bot
    local cw, ch = (innerW - gap) / 2, (innerH - gap) / 2
    for i, cell in ipairs(box.cells or {}) do
        local col, row = (i - 1) % 2, math.floor((i - 1) / 2)
        local x = pad + col * (cw + gap)
        local y = -top - row * (ch + gap)
        cell:ClearAllPoints()
        cell:SetSize(cw, ch)
        cell:SetPoint("TOPLEFT", box, "TOPLEFT", x, y)
        cell.lab:SetText(stats[i][1])
        cell.val:SetText(stats[i][2])
        if cell.val.SetWidth then cell.val:SetWidth(math.max(cw - 6, 20)) end
        local detail = stats[i][3]
        if cell.detail then
            if detail and detail ~= "" then
                cell.detail:SetText(detail)
                if cell.detail.SetWidth then cell.detail:SetWidth(math.max(cw - 6, 20)) end
                cell.detail:Show()
                cell.val:ClearAllPoints()
                cell.val:SetPoint("CENTER", 0, 2)
                cell.detail:ClearAllPoints()
                cell.detail:SetPoint("BOTTOM", 0, 3)
            else
                cell.detail:Hide()
                cell.val:ClearAllPoints()
                if i == 3 and (stats[i][2] or ""):find("\n") then
                    -- One profession: "Herbalism" and "+2" stacked in the value.
                    cell.val:SetPoint("TOP", cell.lab, "BOTTOM", 0, -1)
                    cell.val:SetPoint("BOTTOM", cell, "BOTTOM", 0, 3)
                    if cell.val.SetFontObject then cell.val:SetFontObject(GatherpediaFontHighlightSmall) end
                else
                    cell.val:SetPoint("BOTTOM", 0, 6)
                    if cell.val.SetFontObject then cell.val:SetFontObject(GatherpediaFontHighlight) end
                end
            end
        end
        cell:Show()
    end
    if box.gridV then
        box.gridV:ClearAllPoints()
        box.gridV:SetPoint("TOP", box, "TOP", 0, -top)
        box.gridV:SetPoint("BOTTOM", box, "BOTTOM", 0, bot)
        box.gridV:Show()
    end
    if box.gridH then
        box.gridH:ClearAllPoints()
        box.gridH:SetPoint("LEFT", box, "LEFT", pad, 0)
        box.gridH:SetPoint("RIGHT", box, "RIGHT", -pad, 0)
        box.gridH:SetPoint("TOP", box, "TOP", 0, -(top + innerH / 2))
        box.gridH:Show()
    end
    if box.gridFrame then
        box.gridFrame:ClearAllPoints()
        box.gridFrame:SetPoint("TOPLEFT", box, "TOPLEFT", pad, -top)
        box.gridFrame:SetPoint("BOTTOMRIGHT", box, "BOTTOMRIGHT", -pad, bot)
        box.gridFrame:Show()
    end
    if box.prompt then
        if s.last then
            box.prompt:SetText((s.last.name or "?") .. " x" .. tostring(s.last.quantity or 1))
        else
            box.prompt:SetText("Go gather something!")
        end
        box.prompt:Show()
    end
    if box.last then box.last:Hide() end
end

function SessionUI:Render(box)
    local o = Opts()
    local s = ns.session
    if not box.floating and box.cells then
        self:RenderDashboard(box)
        return
    end
    for _, c in ipairs(box.cells or {}) do c:Hide() end
    if box.idle then box.idle:Hide() end
    if box.prompt then box.prompt:Hide() end
    if box.gridV then box.gridV:Hide() end
    if box.gridH then box.gridH:Hide() end
    if box.gridFrame then box.gridFrame:Hide() end
    local headText = "THIS SESSION"
    if o.prof ~= "All" then headText = headText .. "  \194\183  " .. o.prof:upper() end
    if s.paused then
        headText = headText .. ns.Colorize("ff9933", s.autoPaused == "afk" and "  (AFK)" or s.autoPaused and "  (idle)" or "  (paused)")
    end
    box.head:SetText(headText)
    local lines = ns.Session:Lines()
    local rowH = o.compact and 12 or 16
    local top = o.compact and 22 or 26
    local fitsLast = not o.compact and #lines <= 4
    for i, l in ipairs(box.lines) do
        local info = lines[i]
        if info then
            local y = -top - (i - 1) * rowH
            l.icon:ClearAllPoints()
            l.icon:SetPoint("TOPLEFT", box, "TOPLEFT", 10, y)
            l.icon:SetSize(rowH - 3, rowH - 3)
            l.icon:SetTexture(info.icon)
            l.icon:SetShown(o.icons)
            l.label:ClearAllPoints()
            l.label:SetPoint("LEFT", l.icon, o.icons and "RIGHT" or "LEFT", o.icons and 5 or 0, 0)
            l.label:SetText(o.labels and info.label or "")
            l.label:Show()
            l.value:ClearAllPoints()
            if o.labels then
                l.value:SetPoint("RIGHT", box, "RIGHT", -10, 0)
                l.value:SetPoint("TOP", l.icon, "TOP", 0, 0)
            else
                l.value:SetPoint("LEFT", l.icon, o.icons and "RIGHT" or "LEFT", o.icons and 5 or 0, 0)
            end
            l.value:SetText(ns.Colorize("ffffff", info.value))
            l.value:Show()
        else
            l.icon:Hide(); l.label:Hide(); l.value:Hide()
        end
    end
    if fitsLast and s.last then
        box.lastIcon:SetTexture(s.last.icon or ns.QUESTION_ICON)
        box.lastIcon:Show()
        box.last:SetText(("%s x%d"):format(s.last.name or "?", s.last.quantity or 1))
        box.last:Show()
    elseif fitsLast then
        box.lastIcon:Hide()
        box.last:SetText(ns.Colorize(MUTED_HEX, "Go gather something!"))
        box.last:Show()
    else
        box.lastIcon:Hide(); box.last:Hide()
    end
    if box.floating then
        local h = top + #lines * rowH + (fitsLast and 40 or 8)
        box:SetHeight(h)
    end
end

function SessionUI:UpdateAll()
    local o = Opts()
    for _, box in ipairs(self.boxes) do
        if box.floating then
            box:SetShown(o.floating and not o.hidden)
            if box:IsShown() then self:Render(box) end
        else
            box:SetShown(not o.hidden)
            if box:IsShown() then self:Render(box) end
        end
    end
end

---------------------------------------------------------------------------
-- Hover and right-click menu
---------------------------------------------------------------------------

function SessionUI:OnBoxEnter(box)
    ns.Menu:PointerIn()
    ns.Menu:ScheduleOpen(box, self:MenuItems(), { beside = true })
end

function SessionUI:OnBoxLeave(box)
    ns.Menu:PointerOut()
end

-- Right-click is a backup: toggle if this box's menu is already up.
function SessionUI:OnRightClick(box)
    if ns.Menu:IsOpen() and ns.Menu.owner == box then
        ns.Menu:Close()
        return
    end
    self:OpenMenu(box)
end

-- A stand-alone breakdown view.
function SessionUI:ShowSkillUpTooltip(cell)
    local o = Opts()
    local rows = ns.Session:SkillUpBreakdown(o.prof)
    if not GameTooltip then return end
    GameTooltip:SetOwner(cell, "ANCHOR_RIGHT")
    GameTooltip:AddLine("Skill-ups this session")
    if #rows == 0 then
        GameTooltip:AddLine("None yet.", 0.6, 0.6, 0.6)
    else
        for _, r in ipairs(rows) do
            GameTooltip:AddDoubleLine(r.prof, tostring(r.from) .. " to " .. tostring(r.to),
                1, 1, 1, GOLD[1], GOLD[2], GOLD[3])
        end
    end
    GameTooltip:Show()
end

function SessionUI:ShowTooltip(box)
    local o = Opts()
    GameTooltip:SetOwner(box, box.floating and "ANCHOR_BOTTOM" or "ANCHOR_RIGHT")
    GameTooltip:AddLine("This session by zone" .. (o.prof ~= "All" and (" (" .. o.prof .. ")") or ""))
    local rows = ns.Session:ZoneBreakdown()
    if #rows == 0 then
        GameTooltip:AddLine("Nothing gathered yet.", 0.6, 0.6, 0.6)
    else
        local elapsed = ns.Session:Elapsed()
        for _, r in ipairs(rows) do
            GameTooltip:AddDoubleLine(r.zone, ("%s items  \194\183  %s nodes"):format(
                ns.Session:FormatNumber(r.items), ns.Session:FormatNumber(r.gathers)), 1, 1, 1, GOLD[1], GOLD[2], GOLD[3])
        end
        GameTooltip:AddLine(" ")
        GameTooltip:AddDoubleLine("Counted time", ns.Session:FormatTime(elapsed), 0.8, 0.8, 0.8, 1, 1, 1)
    end
    GameTooltip:Show()
end

local function Changed() SessionUI:UpdateAll() end

-- Zone breakdown is folded into the top of the menu so a hover tooltip
-- never overlaps it.
function SessionUI:BreakdownItems()
    local o = Opts()
    local rows = ns.Session:ZoneBreakdown()
    local items = {
        { text = "This session by zone" .. (o.prof ~= "All" and (" (" .. o.prof .. ")") or ""), kind = "title" },
    }
    if #rows == 0 then
        items[#items + 1] = { text = "Nothing gathered yet.", kind = "info", r = 0.6, g = 0.6, b = 0.6 }
    else
        local n = math.min(#rows, MAX_ZONE_ROWS)
        for i = 1, n do
            local r = rows[i]
            items[#items + 1] = { text = ("%s    %s items  \194\183  %s nodes"):format(
                r.zone, ns.Session:FormatNumber(r.items), ns.Session:FormatNumber(r.gathers)), kind = "info" }
        end
        if #rows > MAX_ZONE_ROWS then
            items[#items + 1] = { text = ("\226\128\166and %d more"):format(#rows - MAX_ZONE_ROWS), kind = "info", r = 0.6, g = 0.6, b = 0.6 }
        end
        items[#items + 1] = { text = "Counted time    " .. ns.Session:FormatTime(ns.Session:Elapsed()), kind = "info", r = 0.8, g = 0.8, b = 0.8 }
    end
    items[#items + 1] = { kind = "sep" }
    return items
end

function SessionUI:MenuItems()
    local o = Opts()
    local function radio(text, key, value)
        return { text = text, kind = "radio", checked = function() return o[key] == value end,
            func = function() o[key] = value; Changed() end }
    end
    local function check(text, key, tip)
        return { text = text, kind = "check", tip = tip, checked = function() return o[key] end,
            func = function() o[key] = not o[key]; Changed() end }
    end
    local function multi(text, key)
        return { text = text, kind = "check", checked = function() return o.multi[key] end,
            func = function() o.multi[key] = not o.multi[key]; o.show = "multi"; Changed() end }
    end
    local zone = ns.GetCurrentZone and ns.GetCurrentZone() or nil
    local multiItems = {
        multi("Gathered", "gathered"), multi("Per hour", "perhour"), multi("Nodes", "nodes"),
        multi("Skill-ups", "skillups"), multi("Time", "time"), multi("Top item", "top"),
    }
    if ns.Session:HasVendorPrices() then multiItems[#multiItems + 1] = multi("Est. vendor value", "value") end
    local items = self:BreakdownItems()
    items[#items + 1] = { text = "This Session", kind = "title" }
    items[#items + 1] = { text = "Start a new session", kind = "button", func = function() ns.Session:Reset(); Changed() end,
        tip = "Clear this session's numbers and restart the timer. Your saved counts are not touched." }
    items[#items + 1] = { text = "Forget this zone" .. (zone and (" (" .. zone .. ")") or ""), kind = "button", hidden = not zone,
        func = function() ns.Session:ResetZone(zone); Changed() end,
        tip = "Take what you gathered in this zone out of the session totals." }
    items[#items + 1] = { text = ns.session.paused and "Resume timer" or "Pause timer", kind = "button",
        func = function() ns.Session:TogglePause(); Changed() end,
        tip = "Paused time doesn't count toward per-hour rates." }
    items[#items + 1] = check("Pause when idle (5 min)", "autoPause", "Stop the clock after 5 minutes without a gather, and when you go AFK. Gathering again starts it.")
    items[#items + 1] = { kind = "sep" }
    items[#items + 1] = { text = "Show", kind = "title" }
    items[#items + 1] = radio("Gathered per hour", "show", "perhour")
    items[#items + 1] = radio("Skill-ups this session", "show", "skillups")
    items[#items + 1] = radio("Skill-ups per hour", "show", "skillrate")
    items[#items + 1] = radio("Time to skill cap", "show", "tocap")
    items[#items + 1] = radio("Session time", "show", "time")
    items[#items + 1] = radio("Several at once", "show", "multi")
    items[#items + 1] = { text = "Pick what \"several\" shows", kind = "sub", sub = multiItems }
    items[#items + 1] = { kind = "sep" }
    items[#items + 1] = { text = "Profession", kind = "sub", sub = {
        radio("All professions", "prof", "All"), radio("Herbalism", "prof", "Herbalism"),
        radio("Mining", "prof", "Mining"), radio("Skinning", "prof", "Skinning"), radio("Fishing", "prof", "Fishing") } }
    items[#items + 1] = { text = "Number style", kind = "sub", sub = {
        radio("1,234 (comma)", "sep", ","), radio("1.234 (period)", "sep", ".") } }
    items[#items + 1] = { text = "Look", kind = "sub", sub = {
        check("Show icons", "icons"), check("Show labels", "labels"), check("Compact", "compact") } }
    items[#items + 1] = { kind = "sep" }
    items[#items + 1] = { text = "Keep on screen", kind = "check", checked = function() return o.floating end,
        func = function() o.floating = not o.floating; o.hidden = false; SessionUI:EnsureFloating(); Changed() end,
        tip = "A small movable box that stays up when the Gatherpedia window is closed." }
    items[#items + 1] = check("Lock its position", "lock")
    items[#items + 1] = { text = "Hide this box", kind = "button", func = function()
        o.hidden = true; Changed()
        ns:Print("This Session box hidden. Type /gp session to bring it back.")
    end }
    return items
end

function SessionUI:OpenMenu(owner)
    GameTooltip:Hide()
    ns.Menu:Open(owner, self:MenuItems(), { beside = true })
end

---------------------------------------------------------------------------
-- Floating box
---------------------------------------------------------------------------

function SessionUI:EnsureFloating()
    if self.float then return self.float end
    local f = self:CreateBox(UIParent, 190, 90, true)
    f:SetFrameStrata("MEDIUM")
    f:SetMovable(true)
    f:SetClampedToScreen(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", function(self)
        ns.Menu:CancelTimers()
        if ns.Menu:IsOpen() then ns.Menu:Close() end
        if not Opts().lock then self:StartMoving() end
    end)
    f:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local p, _, rp, x, y = self:GetPoint()
        Opts().float = { point = p, relativePoint = rp, x = x, y = y }
    end)
    local pos = Opts().float or {}
    f:ClearAllPoints()
    f:SetPoint(pos.point or "CENTER", UIParent, pos.relativePoint or "CENTER", pos.x or 300, pos.y or 120)
    self.float = f
    return f
end

-- Login: create the floating box if wanted, and start the 5-second clock.
function SessionUI:Init()
    if ns.Menu and ns.Menu.Init then ns.Menu:Init() end
    if Opts().floating then self:EnsureFloating() end
    if not self.ticker and C_Timer and C_Timer.NewTicker then
        self.ticker = C_Timer.NewTicker(5, function()
            ns.Session:Tick()
            for _, box in ipairs(SessionUI.boxes) do
                if box:IsVisible() then SessionUI:Render(box) end
            end
        end)
    end
    local afk = CreateFrame("Frame")
    afk:RegisterEvent("PLAYER_FLAGS_CHANGED")
    afk:SetScript("OnEvent", function(_, _, unit)
        if unit and unit ~= "player" then return end
        if not Opts().autoPause then return end
        ns.Session:SetAFK(UnitIsAFK and UnitIsAFK("player") and true or false)
        SessionUI:UpdateAll()
    end)
    self:UpdateAll()
end
