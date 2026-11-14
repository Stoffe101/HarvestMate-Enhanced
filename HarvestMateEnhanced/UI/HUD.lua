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

local C = T.C
local KPI_Y = -26

local function Build()
    f = CreateFrame("Frame", "HarvestMateEnhancedHUD", UIParent)
    f:SetSize(240, 80)
    f:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", -220, -220)
    f:SetFrameStrata("MEDIUM")
    f:SetClampedToScreen(true)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f.shadow = T.Shadow(f, 10)
    T.Panel(f, 0.88)
    f.head = CreateFrame("Frame", nil, f)
    f.head:SetPoint("TOPLEFT", 0, -2)
    f.head:SetPoint("TOPRIGHT", 0, -2)
    f.head:SetHeight(18)
    T.HeaderStrip(f.head, "FARMING")
    f.state = T.Text(f.head, "", "label")
    f.state:SetPoint("RIGHT", -8, 0)
    f.state:SetJustifyH("RIGHT")
    -- Three live numbers: gold an hour, skill-ups an hour, time.
    f.kpi = {}
    for i, label in ipairs({ "GOLD / H", "SKILL / H", "FARMED" }) do
        local col = CreateFrame("Frame", nil, f)
        col:SetSize(70, 34)
        col.value = T.Text(col, "", "strong", nil, 15)
        col.value:SetPoint("TOPLEFT", 0, 0)
        col.value:SetWordWrap(false)
        col.label = T.Text(col, label, "label", nil, 9)
        col.label:SetPoint("TOPLEFT", 0, -19)
        f.kpi[i] = col
    end
    f.big = T.Text(f, "", "strong", C.text, 13)
    f.big:SetPoint("TOPLEFT", 10, KPI_Y)
    f.big:SetWordWrap(false)
    f.text = T.Text(f, "", "small", C.text2)
    f.text:SetPoint("TOPLEFT", 10, KPI_Y - 40)
    f.text:SetWidth(220)
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
    local width = size == "detailed" and 300 or 240
    local colW = (width - 20) / 3
    for i, col in ipairs(f.kpi) do
        col:ClearAllPoints()
        col:SetPoint("TOPLEFT", 10 + (i - 1) * colW, KPI_Y)
        col:SetWidth(colW - 4)
        col:SetShown(r ~= nil)
    end
    f.big:SetShown(r == nil)
    if r then
        f.kpi[1].value:SetText((r.gph or 0) > 0 and K.Money(r.gph) or "–")
        f.kpi[1].value:SetTextColor(C.gold[1], C.gold[2], C.gold[3])
        f.kpi[2].value:SetText(("%.0f"):format(r.sph or 0))
        f.kpi[2].value:SetTextColor(C.accent[1], C.accent[2], C.accent[3])
        f.kpi[3].value:SetText(U.Duration(r.farmSecs or r.secs or 0))
        f.state:SetText(r.paused and K.Paint("PAUSED", T.HEX.warning) or (g and K.Paint("GUIDED", T.HEX.accent) or ""))
    else
        f.big:SetText(g and g.name or "Session not started")
        f.state:SetText(g and K.Paint("GUIDED", T.HEX.accent) or "")
    end
    local lines = {}
    if size ~= "compact" then
        if r then
            lines[#lines + 1] = ("%d nodes  ·  %d skins  ·  %d catches"):format(r.nodes, r.skins, r.catches)
        end
        if g then lines[#lines + 1] = g.phaseText or "" end
        local owner = HME.Guidance.ArrowOwner()
        if g and owner then lines[#lines + 1] = "|cff78808cArrow: " .. owner .. "|r" end
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
            local cmp = size == "detailed" and HME.Records.Compare()
            if cmp then lines[#lines + 1] = cmp.text end
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
    local top = r and 64 or 46
    local h = top + (#lines > 0 and ((f.text:GetStringHeight() or 12) + 10) or 0)
    f.text:ClearAllPoints()
    f.text:SetPoint("TOPLEFT", 10, -(top - 2))
    f:SetHeight(size == "compact" and top or h)
    f:SetWidth(width)
    f.text:SetWidth(width - 20)
    f:Show()
end

function H.Toggle()
    hidden = not hidden
    if hidden and f then f:Hide() else H.Update() end
end

HME.Listen("SESSION_CHANGED", function() H.Update() end)
HME.Listen("GUIDANCE_CHANGED", function() H.Update() end)
