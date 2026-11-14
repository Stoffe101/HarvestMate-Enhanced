-- Gatherpedia: Menu.lua
-- A small menu of our own (no UIDropDownMenu, so no shared-menu taint on
-- 1.60.1). Two levels: items and one submenu level.
-- Opens on hover (with a short delay) or on right-click.
-- Item: { text, kind = "title"|"sep"|"info"|"button"|"radio"|"check"|"sub",
--         checked = function() -> bool, func = function(), sub = { items }, tip = "..." }

local ADDON_NAME, ns = ...

local Menu = {}
ns.Menu = Menu

local ROW_H, PAD, MIN_W = 18, 8, 150
local GOLD = { 0.90, 0.75, 0.38 }
local OPEN_DELAY, CLOSE_DELAY = 0.25, 0.40

local function CreateLevel(level)
    local f = CreateFrame("Frame", "GatherpediaMenu" .. level, UIParent, "BackdropTemplate")
    f:SetFrameStrata("FULLSCREEN_DIALOG")
    f:SetFrameLevel(10 + level * 5)
    f:SetClampedToScreen(true)
    f:EnableMouse(true)
    if ns.Theme then
        ns.Theme:Panel(f, ns.Theme.C.side, ns.Theme.C.line2, 6)
    else
        f:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            edgeSize = 12, insets = { left = 3, right = 3, top = 3, bottom = 3 } })
        f:SetBackdropColor(0.06, 0.055, 0.065, 0.97)
        f:SetBackdropBorderColor(GOLD[1], GOLD[2], GOLD[3], 0.9)
    end
    f:Hide()
    f.rows = {}
    tinsert(UISpecialFrames, f:GetName())
    f:SetScript("OnEnter", function() Menu:PointerIn() end)
    f:SetScript("OnLeave", function() Menu:PointerOut() end)
    return f
end

local function Row(f, i)
    local b = f.rows[i]
    if b then return b end
    b = CreateFrame("Button", nil, f)
    b:SetHeight(ROW_H)
    b:SetPoint("TOPLEFT", PAD - 2, -PAD - (i - 1) * ROW_H)
    b:SetPoint("RIGHT", f, "RIGHT", -PAD + 2, 0)
    b.hl = b:CreateTexture(nil, "HIGHLIGHT")
    b.hl:SetAllPoints()
    do
        local c = ns.Theme and ns.Theme.C.gold or GOLD
        b.hl:SetColorTexture(c[1], c[2], c[3], 0.10)
    end
    b.mark = b:CreateTexture(nil, "ARTWORK")
    b.mark:SetSize(14, 14)
    b.mark:SetPoint("LEFT", 2, 0)
    b.text = b:CreateFontString(nil, "OVERLAY", "GatherpediaFontHighlightSmall")
    b.text:SetPoint("LEFT", 20, 0)
    b.text:SetJustifyH("LEFT")
    b.arrow = b:CreateTexture(nil, "ARTWORK")
    b.arrow:SetSize(12, 12)
    b.arrow:SetPoint("RIGHT", -2, 0)
    b.arrow:SetTexture("Interface\\ChatFrame\\ChatFrameExpandArrow")
    b.line = b:CreateTexture(nil, "ARTWORK")
    b.line:SetHeight(1)
    b.line:SetPoint("LEFT", 4, 0)
    b.line:SetPoint("RIGHT", -4, 0)
    do
        local c = ns.Theme and ns.Theme.C.line or GOLD
        b.line:SetColorTexture(c[1], c[2], c[3], ns.Theme and 1 or 0.3)
    end
    f.rows[i] = b
    return b
end

function Menu:Close()
    self:CancelTimers()
    self.owner = nil
    for l = 1, 2 do if self[l] then self[l]:Hide() end end
end

function Menu:IsOpen() return self[1] and self[1]:IsShown() end

function Menu:CancelTimers()
    self._openGen = (self._openGen or 0) + 1
    self._closeGen = (self._closeGen or 0) + 1
end

-- True when the cursor is over the owner box, the menu, or a submenu, so a
-- diagonal move into a submenu doesn't count as leaving.
function Menu:IsPointerInside()
    if self.owner and self.owner.IsMouseOver and self.owner:IsShown() and self.owner:IsMouseOver() then
        return true
    end
    for l = 1, 2 do
        local f = self[l]
        if f and f:IsShown() and f.IsMouseOver and f:IsMouseOver() then return true end
    end
    return false
end

function Menu:PointerIn()
    self:CancelTimers()
end

function Menu:PointerOut()
    -- Stay up for CLOSE_DELAY after the pointer leaves every related frame.
    self._closeGen = (self._closeGen or 0) + 1
    local gen = self._closeGen
    if C_Timer and C_Timer.After then
        C_Timer.After(CLOSE_DELAY, function()
            if gen ~= Menu._closeGen then return end
            if Menu:IsPointerInside() then return end
            Menu:Close()
        end)
    else
        if not self:IsPointerInside() then self:Close() end
    end
end

function Menu:ScheduleOpen(owner, items, opts)
    self:CancelTimers()
    if self:IsOpen() and self.owner == owner then
        -- Already showing for this box: refresh contents, don't flicker.
        self:Open(owner, items, opts)
        return
    end
    local gen = self._openGen
    local function go()
        if gen ~= Menu._openGen then return end
        Menu:Open(owner, items, opts)
    end
    if C_Timer and C_Timer.After then
        C_Timer.After(OPEN_DELAY, go)
    else
        go()
    end
end

function Menu:Fill(level, items, anchor, point, relPoint, x, y)
    self[level] = self[level] or CreateLevel(level)
    local f = self[level]
    f.items = items
    local width, n = MIN_W, 0
    for _, it in ipairs(items) do
        if not it.hidden then
            n = n + 1
            local b = Row(f, n)
            b.item = it
            b.mark:Hide(); b.arrow:Hide(); b.line:Hide(); b.text:Show()
            b:EnableMouse(true)
            b.hl:SetAlpha(1)
            if it.kind == "sep" then
                b.text:Hide(); b.line:Show(); b:EnableMouse(false)
            elseif it.kind == "title" then
                b.text:SetText(it.text); b.text:SetTextColor(GOLD[1], GOLD[2], GOLD[3]); b:EnableMouse(false)
                b.text:SetPoint("LEFT", 4, 0)
            elseif it.kind == "info" then
                b.text:SetText(it.text)
                b.text:SetTextColor(it.r or 0.85, it.g or 0.85, it.b or 0.85)
                b.text:SetPoint("LEFT", 4, 0)
                b:EnableMouse(false)
                b.hl:SetAlpha(0)
            else
                b.text:SetPoint("LEFT", 20, 0)
                b.text:SetText(it.text); b.text:SetTextColor(1, 1, 1)
                local on = it.checked and it.checked()
                if it.kind == "radio" then
                    b.mark:SetTexture("Interface\\Buttons\\UI-RadioButton")
                    if on then b.mark:SetTexCoord(0.25, 0.5, 0, 1) else b.mark:SetTexCoord(0, 0.25, 0, 1) end
                    b.mark:Show()
                elseif it.kind == "check" then
                    b.mark:SetTexture(on and "Interface\\Buttons\\UI-CheckBox-Check" or "Interface\\Buttons\\UI-CheckBox-Up")
                    b.mark:SetTexCoord(0, 1, 0, 1)
                    b.mark:Show()
                elseif it.kind == "sub" then
                    b.arrow:Show()
                end
            end
            local w = (b.text.GetStringWidth and b.text:GetStringWidth() or 100) + 46
            if w > width then width = w end
            b:SetScript("OnEnter", function(btn)
                Menu:PointerIn()
                if level == 1 then
                    if btn.item.kind == "sub" then
                        -- Overlap the parent slightly so a diagonal move into the
                        -- submenu doesn't fall through a gap and close it.
                        Menu:Fill(2, btn.item.sub, btn, "TOPLEFT", "TOPRIGHT", -2, PAD)
                    elseif Menu[2] then
                        Menu[2]:Hide()
                    end
                end
                if btn.item.tip then
                    GameTooltip:SetOwner(btn, "ANCHOR_RIGHT")
                    GameTooltip:AddLine(btn.item.text)
                    GameTooltip:AddLine(btn.item.tip, 1, 1, 1, true)
                    GameTooltip:Show()
                end
            end)
            b:SetScript("OnLeave", function()
                GameTooltip:Hide()
                Menu:PointerOut()
            end)
            b:SetScript("OnClick", function(btn)
                local item = btn.item
                if item.kind == "sub" then return end
                if item.func then item.func() end
                if item.close then
                    Menu:Close()
                elseif item.kind == "check" or item.kind == "radio" then
                    Menu:Refresh()                      -- stay open so several boxes can be ticked
                else
                    Menu:Close()
                end
            end)
            b:Show()
        end
    end
    for i = n + 1, #f.rows do f.rows[i]:Hide() end
    f:SetSize(width + PAD * 2, n * ROW_H + PAD * 2)
    f:ClearAllPoints()
    f:SetPoint(point, anchor, relPoint, x or 0, y or 0)
    f:Show()
    f.anchorArgs = { anchor, point, relPoint, x, y }
    return f
end

function Menu:Refresh()
    for l = 1, 2 do
        local f = self[l]
        if f and f:IsShown() and f.items and f.anchorArgs then
            local a = f.anchorArgs
            self:Fill(l, f.items, a[1], a[2], a[3], a[4], a[5])
        end
    end
end

-- opts.beside: to the right of the owner (hover menu).
-- opts.below: under the owner (dropdowns).
-- Reopening for the same owner refreshes in place so the menu does not flicker.
function Menu:Open(owner, items, opts)
    opts = opts or {}
    self:CancelTimers()
    GameTooltip:Hide()
    if not (self:IsOpen() and self.owner == owner) then
        self:Close()
        self:CancelTimers()
    end
    self.owner = owner
    local anchor, point, rel, x, y
    if opts.below and owner then
        anchor, point, rel, x, y = owner, "TOPLEFT", "BOTTOMLEFT", 0, -2
    elseif opts.beside and owner then
        anchor, point, rel, x, y = owner, "TOPLEFT", "TOPRIGHT", 4, 0
    else
        local cx, cy = GetCursorPosition and GetCursorPosition()
        if cx and cy and UIParent.GetEffectiveScale then
            local scale = UIParent:GetEffectiveScale()
            anchor, point, rel, x, y = UIParent, "TOPLEFT", "BOTTOMLEFT", cx / scale, cy / scale
        else
            anchor, point, rel, x, y = owner, "TOPLEFT", "BOTTOMLEFT", 0, 0
        end
    end
    self:Fill(1, items, anchor, point, rel, x, y)
    -- Click anywhere else closes it.
    if not self.watcher then
        self.watcher = CreateFrame("Frame")
        self.watcher:SetScript("OnEvent", function()
            if not Menu:IsOpen() then return end
            for l = 1, 2 do
                local f = Menu[l]
                if f and f:IsShown() and f.IsMouseOver and f:IsMouseOver() then return end
            end
            if Menu.owner and Menu.owner.IsMouseOver and Menu.owner:IsMouseOver() then return end
            Menu:Close()
        end)
        pcall(self.watcher.RegisterEvent, self.watcher, "GLOBAL_MOUSE_DOWN")
    end
end

-- Build the two menu frames at login so the first hover never creates frames
-- in combat.
function Menu:Init()
    self[1] = self[1] or CreateLevel(1)
    self[2] = self[2] or CreateLevel(2)
end
