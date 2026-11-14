-- HarvestMate Enhanced: UI/HUD.lua
-- The farming HUD: a small movable box while a session runs or a farm is
-- followed: gold an hour, skill-ups, counts, the next stop, pause/end.
-- Compact mode is one line. Hidden in combat if you like a clean screen
-- (it is never in the way of protected frames: it is a plain frame).
-- Copyright (C) 2026 HarvestMate Enhanced contributors. GPL-3.0-or-later.

local _, ns = ...
local HME = ns.HME
local T = ns.Theme
local K = HME.Kit
local U = HME.U

local H = {}
HME.HUD = H

local f
local hidden = false

local function Build()
    f = CreateFrame("Frame", "HarvestMateEnhancedHUD", UIParent)
    f:SetSize(230, 74)
    f:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", -220, -220)
    f:SetFrameStrata("MEDIUM")
    f:SetClampedToScreen(true)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    T.Panel(f, 0.82)
    f.head = CreateFrame("Frame", nil, f)
    f.head:SetPoint("TOPLEFT")
    f.head:SetPoint("TOPRIGHT")
    f.head:SetHeight(16)
    T.HeaderStrip(f.head, "HarvestMate")
    f.big = T.Text(f, "", "GameFontNormal", T.C.gold)
    f.big:SetPoint("TOPLEFT", 8, -20)
    f.text = T.Text(f, "", "GameFontHighlightSmall")
    f.text:SetPoint("TOPLEFT", 8, -36)
    f.text:SetWidth(214)
    f.text:SetWordWrap(true)
    f:SetScript("OnDragStart", function(self)
        if not (HME.settings and HME.settings.hudLocked) then self:StartMoving() end
    end)
    f:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local pt, _, rel, x, y = self:GetPoint()
        if HME.char then HME.char.ui.hud = { pt, rel, x, y } end
    end)
    f:SetScript("OnMouseUp", function(_, button)
        if button == "RightButton" then
            HME.Session.Pause()
        elseif button == "MiddleButton" then
            HME.Session.Stop("manual")
        end
    end)
    T.Tooltip(f, "Farming HUD", "Drag to move. Right-click: pause or resume. Middle-click: end the session. /hme hud hides it.")
    local pos = HME.char and HME.char.ui.hud
    if type(pos) == "table" and pos[1] then
        f:ClearAllPoints()
        f:SetPoint(pos[1], UIParent, pos[2], pos[3], pos[4])
    end
    local acc = 0
    f:SetScript("OnUpdate", function(_, dt)
        acc = acc + dt
        if acc >= 1 then
            acc = 0
            H.Update()
        end
    end)
end

function H.Update()
    local s = HME.settings
    local want = s and s.hud and not hidden and (HME.Session.Current() or HME.Guidance.Active())
    if not want then
        if f then f:Hide() end
        return
    end
    if not f then Build() end
    local r = HME.Session.Rates()
    local g = HME.Guidance.Active()
    if r then
        f.big:SetText(("%s/h  ·  %.0f skill/h%s"):format(K.Money(r.gph), r.sph, r.paused and "  |cffff8a3dpaused|r" or ""))
    else
        f.big:SetText("Session not started")
    end
    local lines = {}
    if r then
        lines[#lines + 1] = ("%s  ·  %d nodes  ·  %d skins  ·  %d catches"):format(U.Duration(r.secs), r.nodes, r.skins, r.catches)
    end
    if g and not s.hudCompact then lines[#lines + 1] = (g.name or "") .. ": " .. (g.phaseText or "") end
    f.text:SetText(table.concat(lines, "\n"))
    local h = 40 + (f.text:GetStringHeight() or 12)
    f:SetHeight(s.hudCompact and 38 or h)
    f:Show()
end

function H.Toggle()
    hidden = not hidden
    if hidden and f then f:Hide() else H.Update() end
end

HME.Listen("SESSION_CHANGED", function() H.Update() end)
HME.Listen("GUIDANCE_CHANGED", function() H.Update() end)
