-- Gatherpedia: Options.lua
-- A small options window (right-click the minimap button or /gp options),
-- plus an entry in the game's AddOns settings list that opens it.

local ADDON_NAME, ns = ...

local Options = {}
ns.Options = Options

local GOLD = { 0.90, 0.75, 0.38 }

local function MakeCheck(parent, y, label, tooltip, get, set, x)
    local row = ns.Theme:CheckRow(parent, label, tooltip, get, set, function()
        if ns.UI then ns.UI:Refresh() end
    end)
    row:SetPoint("TOPLEFT", x or 18, y - 2)
    row:SetWidth(320)
    return row
end

-- A labelled slider; label shows the current value through fmt.
local function MakeSlider(parent, x, y, label, minV, maxV, step, fmt, get, set)
    local row = ns.Theme:SliderRow(parent, 300, label, minV, maxV, step, fmt, get, set)
    -- The label sits above the bar.
    row:SetPoint("TOPLEFT", x + 2, y + 18)
    return row
end

function Options:Create()
    if self.frame then return self.frame end
    local f = CreateFrame("Frame", "GatherpediaOptionsFrame", UIParent)
    self.frame = f
    f:SetSize(360, 560)
    f:SetPoint("CENTER", 0, 40)
    f:SetFrameStrata("DIALOG")
    f:SetClampedToScreen(true)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    if ns.Chrome and ns.Chrome.ApplyWindow then ns.Chrome:ApplyWindow(f) end
    f:Hide()
    tinsert(UISpecialFrames, "GatherpediaOptionsFrame")

    local RX = 330
    local title = f:CreateFontString(nil, "OVERLAY", "GatherpediaFontHeading")
    title:SetPoint("TOPLEFT", 16, -14)
    title:SetText("Gatherpedia Options")
    local close
    if ns.Chrome and ns.Chrome.MakeCloseButton then
        close = ns.Chrome:MakeCloseButton(f, function() f:Hide() end)
    else
        close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
        close:SetPoint("TOPRIGHT", -2, -2)
    end
    -- A hairline under the title, like the main window's sections.
    local rule = f:CreateTexture(nil, "ARTWORK")
    rule:SetHeight(1)
    rule:SetPoint("TOPLEFT", 16, -38)
    rule:SetPoint("TOPRIGHT", -16, -38)
    do
        local c = ns.Theme and ns.Theme.C.line or { 0.17, 0.15, 0.12 }
        rule:SetColorTexture(c[1], c[2], c[3], 1)
    end

    local db = function() return ns.db end
    self.checks = {
        MakeCheck(f, -46, "Show all professions",
            "Also show gathering professions this character hasn't learned. Saved per character.",
            function() return ns.charDB.showAllProfessions end,
            function(v)
                if ns.UI and ns.UI.SetShowAllProfessions then
                    ns.UI:SetShowAllProfessions(v)
                else
                    ns.charDB.showAllProfessions = v
                end
            end),
        MakeCheck(f, -74, "Show minimap button",
            "Show the Gatherpedia button on the minimap. /gp minimap also toggles it.",
            function() return not db().minimap.hide end,
            function(v) if (not db().minimap.hide) ~= v then ns:ToggleMinimapButton() end end),
        MakeCheck(f, -102, "Lock minimap button",
            "Stop the minimap button from being dragged around the minimap.",
            function() return db().minimap.lock end,
            function(v)
                db().minimap.lock = v
            end),
        MakeCheck(f, -130, "Show upcoming Mount Hyjal items",
            "Show announced Mount Hyjal herbs, ore, gems and leather as silhouettes until you gather them.",
            function() return db().options.showUndiscovered end,
            function(v) db().options.showUndiscovered = v end),
        MakeCheck(f, -158, "Only list zones I've gathered in",
            "On detail pages, hide default zones where your count is still 0.",
            function() return db().options.onlyGatheredZones end,
            function(v) db().options.onlyGatheredZones = v end),
        MakeCheck(f, -186, "Announce new discoveries in chat",
            "Print a chat message when you gather something that isn't in the built-in database.",
            function() return db().options.announce end,
            function(v) db().options.announce = v end),
        MakeCheck(f, -214, "Show the This Session box",
            "The session numbers at the bottom of the sidebar. Hover the box, or right-click it, for more options.",
            function() return not db().session.hidden end,
            function(v) db().session.hidden = not v; if ns.SessionUI then ns.SessionUI:UpdateAll() end end),
        MakeCheck(f, -242, "Show travel direction on routes",
            "A short dark dash slides along the route in the direction of travel, on the world map and the minimap. The line itself stays still. Turn this off for a plain line.",
            function() return db().options.routeFlow ~= false end,
            function(v)
                db().options.routeFlow = v
                if ns.RouteOverlay and ns.RouteOverlay.Refresh then ns.RouteOverlay:Refresh() end
            end),
        MakeCheck(f, -270, "Debug: log unknown gathering spells",
            "Print and save gathering spell IDs Gatherpedia doesn't know yet, so they can be reported. Same as /gp debug.",
            function() return db().options.debug end,
            function(v) db().options.debug = v end),
        MakeCheck(f, -298, "Unlock the main window",
            "Let the Gatherpedia window be dragged. It is locked in place by default, like the world map, and still docks beside the map when the map opens.",
            function() return db().options.windowUnlocked end,
            function(v)
                if ns.UI and ns.UI.SetLocked then
                    ns.UI:SetLocked(not v)
                else
                    db().options.windowUnlocked = v
                end
            end),
    }

    self.sliders = {
        MakeSlider(f, 16, -346, "Arrow size", 50, 200, 5, "%d%%",
            function()
                if ns.Arrow and ns.Arrow.ScalePercent then return ns.Arrow:ScalePercent() end
                local v = ns.charDB and tonumber(ns.charDB.arrowScale)
                return math.floor(((v or 1) * 100) + 0.5)
            end,
            function(v)
                if ns.Arrow and ns.Arrow.SetScalePercent then
                    ns.Arrow:SetScalePercent(v)
                elseif ns.charDB then
                    ns.charDB.arrowScale = (v or 100) / 100
                end
            end),
    }

    local sparkles = ns.Chrome:MakeButton(f, 170, 26, "Glimmer Settings...")
    sparkles:SetPoint("TOPLEFT", 16, -388)
    sparkles:SetScript("OnClick", function()
        -- Open the main window on the Glimmer page and close Options so
        -- the two frames never stack in the same spot.
        if ns.UI and ns.UI.ShowGlimmer then
            ns.UI:ShowGlimmer()
        elseif ns.SparklesUI then
            ns.SparklesUI:Show()
        end
        Options:Hide()
    end)
    self.sparklesBtn = sparkles

    local resetPos = ns.Chrome:MakeButton(f, 156, 26, "Reset window position")
    resetPos:SetPoint("BOTTOMLEFT", 16, 16)
    resetPos:SetScript("OnClick", function() ns.UI:ResetPosition() end)

    local resetCounts = ns.Chrome:MakeButton(f, 156, 26, "Reset all counts...")
    resetCounts:SetPoint("BOTTOMRIGHT", -16, 16)
    resetCounts:SetScript("OnClick", function() StaticPopup_Show("GATHERPEDIA_RESET_COUNTS") end)

    local note = f:CreateFontString(nil, "OVERLAY", "GatherpediaFontDisableSmall")
    note:SetPoint("BOTTOMLEFT", resetPos, "TOPLEFT", 0, 12)
    note:SetWidth(328)
    note:SetJustifyH("LEFT")
    note:SetText("Counts are shared by all your characters. \"Show all professions\" and arrow size are saved for this character only.")

    f:SetScript("OnShow", function() Options:Refresh() end)
    return f
end

function Options:Refresh()
    if not self.frame then return end
    for _, cb in ipairs(self.checks) do cb:Refresh() end
    for _, sl in ipairs(self.sliders or {}) do sl:Refresh() end
end

function Options:Toggle()
    self:Create()
    self.frame:SetShown(not self.frame:IsShown())
end

function Options:Hide()
    if self.frame then self.frame:Hide() end
end

-- Entry in Esc > Options > AddOns that opens the window above.
function Options:Register()
    local panel = CreateFrame("Frame")
    panel.name = "Gatherpedia"
    local title = panel:CreateFontString(nil, "OVERLAY", "GatherpediaFontHeading")
    title:SetPoint("TOPLEFT", 16, -16)
    title:SetText("Gatherpedia")
    local text = panel:CreateFontString(nil, "OVERLAY", "GatherpediaFontHighlight")
    text:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -8)
    text:SetText("Type /gp to open the field guide, or /gp options for settings.")
    local open = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    open:SetSize(180, 24)
    open:SetPoint("TOPLEFT", text, "BOTTOMLEFT", 0, -12)
    open:SetText("Open Gatherpedia options")
    open:SetScript("OnClick", function()
        if SettingsPanel and SettingsPanel:IsShown() then HideUIPanel(SettingsPanel) end
        Options:Toggle()
    end)
    pcall(function()
        if Settings and Settings.RegisterCanvasLayoutCategory then
            local category = Settings.RegisterCanvasLayoutCategory(panel, "Gatherpedia")
            Settings.RegisterAddOnCategory(category)
        elseif InterfaceOptions_AddCategory then
            InterfaceOptions_AddCategory(panel)
        end
    end)
end
