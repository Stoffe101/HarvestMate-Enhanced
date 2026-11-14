-- Gatherpedia: Minimap.lua
-- Gatherpedia's own minimap button, with no bundled libraries.
-- Left-click: open/close the window. Right-click: start/stop the zone route.
-- Shift-right-click: options. Drag: move it around the minimap.
-- If another addon has loaded LibDataBroker, a launcher is also offered to
-- broker displays (Titan Panel, ChocolateBar and similar).

local ADDON_NAME, ns = ...

local ICON = ns.ICON_MINIMAP   -- tight round crop of the gold G
local BORDER = "Interface\\Minimap\\MiniMap-TrackingBorder"
local HIGHLIGHT = "Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight"

local button

local function OnClick(_, mouse)
    if mouse == "RightButton" then
        if IsShiftKeyDown and IsShiftKeyDown() then
            ns.Options:Toggle()
        elseif ns.ToggleZoneRoute then
            ns.ToggleZoneRoute()
        end
    else
        ns.UI:Toggle()
    end
end

local function FillTooltip(tooltip)
    tooltip:AddLine("Gatherpedia", 0.90, 0.75, 0.38)
    local list = ns.learnedList
    if #list > 0 then
        for _, key in ipairs(list) do
            local p = ns.learned[key]
            tooltip:AddDoubleLine(key, ("%d / %d"):format(p.rank, p.max), 1, 1, 1, 1, 1, 1)
        end
    else
        tooltip:AddLine("No gathering professions on this character", 0.6, 0.6, 0.6)
    end
    local s = ns.session
    if s and s.items and s.items > 0 then
        tooltip:AddDoubleLine("Gathered this session", s.items, 0.8, 0.8, 0.8, 1, 1, 1)
    end
    tooltip:AddLine(" ")
    tooltip:AddLine("|cffffffffLeft-click|r to open the field guide", 0.8, 0.8, 0.8)
    if ns.AppendRouteTooltip then
        ns.AppendRouteTooltip(tooltip)
    else
        tooltip:AddLine("|cffffffffRight-click|r to Start/Stop route", 0.8, 0.8, 0.8)
    end
    tooltip:AddLine("|cffffffffShift-Right-click|r for options", 0.8, 0.8, 0.8)
    tooltip:AddLine("|cffffffffDrag|r to move this button", 0.8, 0.8, 0.8)
end

-- Square minimaps (some UI packs) keep the button on the square's edge.
local function MinimapIsSquare()
    if GetMinimapShape then
        local shape = GetMinimapShape()
        return shape == "SQUARE"
    end
    return false
end

local function Place()
    if not button then return end
    local angle = math.rad(tonumber(ns.db.minimap.minimapPos) or 210)
    local x, y = math.cos(angle), math.sin(angle)
    local w = (Minimap:GetWidth() or 140) / 2 + 5
    local h = (Minimap:GetHeight() or 140) / 2 + 5
    if MinimapIsSquare() then
        local m = math.max(math.abs(x), math.abs(y))
        x, y = x / m, y / m
    end
    button:ClearAllPoints()
    button:SetPoint("CENTER", Minimap, "CENTER", x * w, y * h)
end

local function DragUpdate()
    local mx, my = Minimap:GetCenter()
    local cx, cy = GetCursorPosition()
    local scale = Minimap:GetEffectiveScale()
    cx, cy = cx / scale, cy / scale
    ns.db.minimap.minimapPos = math.deg(math.atan2(cy - my, cx - mx)) % 360
    Place()
end

local function Create()
    if button or not Minimap then return button end
    local b = CreateFrame("Button", "GatherpediaMinimapButton", Minimap)
    b:SetSize(31, 31)
    b:SetFrameStrata("MEDIUM")
    b:SetFrameLevel((Minimap:GetFrameLevel() or 1) + 8)
    b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    b:RegisterForDrag("LeftButton")
    b:SetHighlightTexture(HIGHLIGHT)

    local bg = b:CreateTexture(nil, "BACKGROUND")
    bg:SetSize(20, 20)
    bg:SetPoint("CENTER", 0, 1)
    bg:SetTexture("Interface\\Minimap\\UI-Minimap-Background")

    local icon = b:CreateTexture(nil, "ARTWORK")
    icon:SetSize(20, 20)
    icon:SetPoint("CENTER", 0, 1)
    icon:SetTexture(ICON)
    b.icon = icon

    local border = b:CreateTexture(nil, "OVERLAY")
    border:SetSize(53, 53)
    border:SetPoint("TOPLEFT")
    border:SetTexture(BORDER)

    b:SetScript("OnClick", OnClick)
    b:SetScript("OnEnter", function(self)
        if self.dragging then return end
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        FillTooltip(GameTooltip)
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    b:SetScript("OnDragStart", function(self)
        if ns.db.minimap.lock then return end
        self.dragging = true
        GameTooltip:Hide()
        self:SetScript("OnUpdate", DragUpdate)
    end)
    b:SetScript("OnDragStop", function(self)
        self.dragging = nil
        self:SetScript("OnUpdate", nil)
        Place()
    end)
    button = b
    return b
end

-- Show or hide to match the saved setting.
function ns:RefreshMinimapButton()
    local b = Create()
    if not b then return end
    if self.db.minimap.hide then b:Hide() else b:Show(); Place() end
end

-- Broker launcher, only when some other addon has loaded LibDataBroker.
local function RegisterBroker()
    local LDB = LibStub and LibStub("LibDataBroker-1.1", true)
    if not LDB or LDB:GetDataObjectByName(ADDON_NAME) then return end
    LDB:NewDataObject(ADDON_NAME, {
        type = "launcher",
        text = "Gatherpedia",
        icon = ICON,
        OnClick = OnClick,
        OnTooltipShow = FillTooltip,
    })
end

function ns:SetupMinimap()
    self:RefreshMinimapButton()
    pcall(RegisterBroker)
end
