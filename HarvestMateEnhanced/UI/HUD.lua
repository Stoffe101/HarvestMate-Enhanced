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

-- Sizes: "compact" one line; "normal" adds counts and the farm; "detailed"
-- adds goal progress, farming vs trip gold and the time split.
function H.Update()
    local s = HME.settings
    local want = s and s.hud and not hidden and (HME.Session.Current() or HME.Guidance.Active())
    if not want then
        if f then f:Hide() end
        return
    end
    if not f then Build() end
    local size = s.hudSize or (s.hudCompact and "compact") or "normal"
    local r = HME.Session.Rates()
    local g = HME.Guidance.Active()
    if r then
        f.big:SetText(("%s/h  ·  %.0f skill/h%s"):format(K.Money(r.gph), r.sph, r.paused and "  |cffff8a3dpaused|r" or ""))
    else
        f.big:SetText(g and g.name or "Session not started")
    end
    local lines = {}
    if size ~= "compact" then
        if r then
            lines[#lines + 1] = ("%s farming  ·  %d nodes  ·  %d skins  ·  %d catches"):format(U.Duration(r.farmSecs), r.nodes, r.skins, r.catches)
        end
        if g then lines[#lines + 1] = g.phaseText or "" end
        local owner = HME.Guidance.ArrowOwner()
        if g and owner then lines[#lines + 1] = "|cff9d9d9dArrow: " .. owner .. "|r" end
    end
    if size ~= "compact" and r then
        -- What you get, and against the prediction once there is enough to judge.
        local live = HME.Session.Live()
        if live then
            local top = live.items[1]
            if top then
                local exp = top.expectedPerHour and (" vs %.0f expected"):format(top.expectedPerHour) or ""
                lines[#lines + 1] = ("%s: %d (%.0f/h%s)"):format(top.name, top.n, top.perHour, exp)
            end
            if live.skins > 0 or live.kills > 0 then
                lines[#lines + 1] = ("%d kills · %d skins%s%s"):format(live.kills, live.skins,
                    live.avgKill and (" · %.0f s a kill"):format(live.avgKill) or "",
                    live.betweenSkins and (" · a skin every %.0f s"):format(live.betweenSkins) or "")
            end
            if size == "detailed" and live.verdict then lines[#lines + 1] = live.verdict.text end
        end
    end
    if size == "detailed" then
        if r then
            lines[#lines + 1] = ("Trip incl. %s travel: %s/h  ·  combat %s, gathering %s, idle %s"):format(U.Duration(r.travelSecs),
                K.Money(r.tripGph), U.Duration(r.combatSecs), U.Duration(r.gatherSecs), U.Duration(r.idleSecs))
        end
        for _, goal in ipairs(HME.Goals.List()) do
            if not goal.doneAt then
                local p = HME.Goals.Progress(goal)
                lines[#lines + 1] = ("Goal %s: %d%%"):format(goal.name, p.fraction * 100)
                break
            end
        end
        for prof, v in pairs(HME.Player.Professions()) do
            if g and g.prof == prof then lines[#lines + 1] = ("%s %d/%d"):format(prof, v.rank, v.max) end
        end
    end
    f.text:SetText(table.concat(lines, "\n"))
    f.text:SetShown(#lines > 0)
    local h = 40 + (#lines > 0 and (f.text:GetStringHeight() or 12) or 0)
    f:SetHeight(size == "compact" and 38 or h)
    f:SetWidth(size == "detailed" and 300 or 230)
    f.text:SetWidth(size == "detailed" and 284 or 214)
    f:Show()
end

function H.Toggle()
    hidden = not hidden
    if hidden and f then f:Hide() else H.Update() end
end

HME.Listen("SESSION_CHANGED", function() H.Update() end)
HME.Listen("GUIDANCE_CHANGED", function() H.Update() end)
