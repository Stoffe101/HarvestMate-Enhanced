-- HarvestMate Enhanced: UI/Minimap.lua
-- One minimap button for everything (HarvestMate, Gatherpedia and GatherPath
-- each had their own), and the addon compartment entry.
-- Left-click: the window. Right-click: route lines on/off. Drag: move it.
-- Copyright (C) 2026 HarvestMate Enhanced contributors. GPL-3.0-or-later.

local _, ns = ...
local HME = ns.HME

local button

local function Position()
    local angle = math.rad(HME.settings.minimapAngle or 225)
    local radius = (Minimap:GetWidth() / 2) + 10
    button:ClearAllPoints()
    button:SetPoint("CENTER", Minimap, "CENTER", math.cos(angle) * radius, math.sin(angle) * radius)
end

local function Tooltip(owner)
    GameTooltip:SetOwner(owner, "ANCHOR_LEFT")
    GameTooltip:AddLine("|T" .. ns.Theme.LOGO .. ":0|t HarvestMate Enhanced")
    local g = HME.Guidance.Active()
    if g then GameTooltip:AddLine(g.name, 1, 0.82, 0) end
    local r = HME.Session.Rates()
    if r then GameTooltip:AddLine(("Session: %s/h, %.0f skill-ups/h"):format(HME.Kit.Money(r.gph), r.sph), 1, 1, 1) end
    GameTooltip:AddLine("Left-click: open", 0.8, 0.8, 0.8)
    GameTooltip:AddLine("Right-click: show or hide route lines", 0.8, 0.8, 0.8)
    GameTooltip:AddLine("Shift-click: Skinning levels", 0.8, 0.8, 0.8)
    GameTooltip:AddLine("Drag: move this button", 0.8, 0.8, 0.8)
    GameTooltip:Show()
end

local function Build()
    button = CreateFrame("Button", "HarvestMateEnhancedMinimapButton", Minimap)
    button:SetSize(31, 31)
    button:SetFrameStrata("MEDIUM")
    button:SetFrameLevel(8)
    button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    button:RegisterForDrag("LeftButton")
    button:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
    local icon = button:CreateTexture(nil, "BACKGROUND")
    icon:SetSize(22, 22)
    icon:SetTexture(ns.Theme.LOGO)
    icon:SetPoint("TOPLEFT", 5, -4)
    local border = button:CreateTexture(nil, "OVERLAY")
    border:SetSize(53, 53)
    border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
    border:SetPoint("TOPLEFT")
    button:SetScript("OnClick", function(_, which)
        if which == "RightButton" then
            if HME.Routes and HME.Routes.ToggleLines then HME.Routes:ToggleLines() end
        elseif IsShiftKeyDown and IsShiftKeyDown() then
            if HME.SkinTracker then HME.SkinTracker.Toggle() end
        else
            HME.ToggleWindow()
        end
    end)
    button:SetScript("OnDragStart", function(self)
        self:SetScript("OnUpdate", function()
            local mx, my = Minimap:GetCenter()
            local px, py = GetCursorPosition()
            local scale = Minimap:GetEffectiveScale()
            HME.settings.minimapAngle = math.deg(math.atan2(py / scale - my, px / scale - mx))
            Position()
        end)
    end)
    button:SetScript("OnDragStop", function(self) self:SetScript("OnUpdate", nil) end)
    button:SetScript("OnEnter", Tooltip)
    button:SetScript("OnLeave", function() GameTooltip:Hide() end)
    Position()
end

local function Update()
    if not button then Build() end
    button:SetShown(HME.settings.minimapButton ~= false)
    local GP = HME.Routes
    if GP and GP.db then
        GP.minimapButton = button
        GP.db.minimapButton = HME.settings.minimapButton ~= false
    end
end

HME.On("PLAYER_LOGIN", Update)
HME.Listen("SETTINGS", function() if button then Update() end end)

-- Addon compartment (named in the .toc)
function HarvestMateEnhanced_OnCompartmentClick() HME.ToggleWindow() end
function HarvestMateEnhanced_OnCompartmentEnter(_, owner) Tooltip(owner or UIParent) end
function HarvestMateEnhanced_OnCompartmentLeave() GameTooltip:Hide() end
