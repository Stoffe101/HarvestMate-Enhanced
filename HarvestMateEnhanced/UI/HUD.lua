-- HarvestMate Enhanced: UI/HUD.lua
-- The farming HUD: a small movable box while a session runs or a farm is
-- followed. Three sizes (the chevron in its title row cycles them, as does
-- Settings): compact shows what you gather, skill-ups, gold an hour and your
-- goal; normal adds your materials and where the route is; detailed adds
-- the prediction check, records and the time split. When nothing has been
-- recognised for a while it says so instead of showing quiet zeros.
-- A plain frame: never in the way of protected frames, and never acts.
--
-- 0.5.0: every text has a width inside the panel. A real-client screenshot
-- showed the route-only title ("Hillsbrad Foothills - Skinning leveling")
-- drawn on one line past the HUD's edge: it had a start and no width. A
-- route's name is now two lines (the zone; then what for, and the stop),
-- each fitted to the panel, with the full name in the tooltip.
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
local SIZES = { "compact", "normal", "detailed" }
local WIDTH = { compact = 252, normal = 268, detailed = 300 }
H.DEFAULT = { "TOPRIGHT", "TOPRIGHT", -220, -190 }

-- What the session is mostly about: skins, nodes or catches.
local function Main(r, g)
    local prof = g and g.prof
    if prof == "Skinning" or (r.skins or 0) > 0 or (r.kills or 0) > 0 then return "skins", r.skins or 0, "skin" end
    if prof == "Fishing" or (r.catches or 0) > 0 then return "catches", r.catches or 0, "catch" end
    if prof == "Herbalism" or prof == "Mining" or (r.nodes or 0) > 0 then return "nodes", r.nodes or 0, "node" end
    if HME.Player.Professions().Skinning then return "skins", r.skins or 0, "skin" end
    return "gathered", (r.nodes or 0) + (r.catches or 0), "gather"
end

local function Build()
    f = CreateFrame("Frame", "HarvestMateEnhancedHUD", UIParent)
    f:SetSize(WIDTH.normal, 90)
    f:SetPoint(H.DEFAULT[1], UIParent, H.DEFAULT[2], H.DEFAULT[3], H.DEFAULT[4])
    f:SetFrameStrata("MEDIUM")
    f:SetClampedToScreen(true)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f.shadow = T.Shadow(f, 10)
    T.Panel(f, 0.9)
    f.head = CreateFrame("Frame", nil, f)
    f.head:SetPoint("TOPLEFT", 0, -3)
    f.head:SetPoint("TOPRIGHT", 0, -3)
    f.head:SetHeight(22)
    T.HeaderStrip(f.head, "Farming")
    f.size = T.FlatButton(f.head, "", 22, 20, "ghost")
    f.size:SetPoint("RIGHT", -3, 0)
    f.size.arrow = T.MenuArrow(f.size, 5)
    f.size:SetScript("OnClick", function()
        local cur = (HME.settings.hudSize or "normal")
        local nxt = "normal"
        for i, k in ipairs(SIZES) do if k == cur then nxt = SIZES[i % #SIZES + 1] end end
        HME.settings.hudSize = nxt
        H.Update()
    end)
    T.Tooltip(f.size, "HUD size", "Compact, normal or detailed. Also in Settings.")
    f.state = T.Text(f.head, "", "label", nil, 11)
    f.state:SetPoint("RIGHT", f.size, "LEFT", -4, 0)
    f.state:SetJustifyH("RIGHT")
    f.state:SetWidth(130)
    f.state:SetWordWrap(false)
    f.head.text:ClearAllPoints()
    f.head.text:SetPoint("LEFT", f.head.logo, "RIGHT", 5, 0)
    f.head.text:SetWidth(70)
    -- Three live numbers.
    f.kpi = {}
    for i = 1, 3 do
        local col = CreateFrame("Frame", nil, f)
        col:SetSize(76, 40)
        col.value = T.Text(col, "", "display", nil, 18)
        col.value:SetPoint("TOPLEFT", 0, 0)
        col.value:SetPoint("RIGHT", 0, 0)
        col.value:SetWordWrap(false)
        col.label = T.Text(col, "", "meta", nil, 11)
        col.label:SetPoint("TOPLEFT", 0, -23)
        col.label:SetPoint("RIGHT", 0, 0)
        col.label:SetWordWrap(false)
        f.kpi[i] = col
    end
    -- The first open goal: name, count and a thin bar.
    f.goal = CreateFrame("Frame", nil, f)
    f.goal:SetHeight(22)
    f.goal.name = T.Text(f.goal, "", "small", C.text2)
    f.goal.name:SetPoint("TOPLEFT", 0, 0)
    f.goal.name:SetWordWrap(false)
    f.goal.num = T.Text(f.goal, "", "small")
    f.goal.num:SetPoint("TOPRIGHT", 0, 0)
    f.goal.num:SetJustifyH("RIGHT")
    f.goal.num:SetWidth(90)
    f.goal.num:SetWordWrap(false)
    f.goal.bar = K.Bar(f.goal, 200, 4)
    f.goal.bar.text:Hide()
    f.goal.bar:SetPoint("BOTTOMLEFT", 0, 0)
    -- The route: the zone on top, then what for and where you are on the loop.
    f.title = T.Text(f, "", "strong", C.text, 14)
    f.title:SetWordWrap(false)
    f.sub = T.Text(f, "", "small", C.text2)
    f.sub:SetWordWrap(false)
    f.text = T.Text(f, "", "small", C.text2)
    f.text:SetWordWrap(true)
    if f.text.SetSpacing then f.text:SetSpacing(2) end
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
    f:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        local g = HME.Guidance.Active()
        GameTooltip:AddLine(g and g.name or "Farming HUD")
        if g and g.phaseText then GameTooltip:AddLine(g.phaseText, 1, 1, 1, true) end
        GameTooltip:AddLine("Drag to move (Settings can lock it). Right-click: pause or resume. Middle-click: end the "
            .. "session. The chevron changes its size. /hme hud hides it, /hme hud reset puts it back.", 0.8, 0.8, 0.8, true)
        GameTooltip:Show()
    end)
    f:SetScript("OnLeave", function() GameTooltip:Hide() end)
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

function H.Frame() return f end

-- A route's name as two lines: "Hillsbrad Foothills - Skinning leveling"
-- becomes "Hillsbrad Foothills" and "Skinning leveling".
function H.SplitName(name)
    name = tostring(name or "")
    local a, b = name:match("^(.-)%s+[-–—]%s+(.+)$")
    if a and a ~= "" then return a, b end
    return name, nil
end

-- Text that must fit a width: one size smaller first, then the game's own
-- cut (the full text is in the tooltip).
local function Fit(fs, text, width, role, size)
    fs:SetWidth(width)
    fs:SetText(text)
    if T.StringWidth(fs) > width then T.FitText(fs, width, role, size, size - 2) end
end

-- Back to where it starts (for a HUD dragged somewhere awkward).
function H.ResetPosition()
    if HME.char then HME.char.ui.hud = nil end
    if f then
        f:ClearAllPoints()
        f:SetPoint(H.DEFAULT[1], UIParent, H.DEFAULT[2], H.DEFAULT[3], H.DEFAULT[4])
    end
end

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
    local width = WIDTH[size] or WIDTH.normal
    f:SetWidth(width)
    local inner = width - 24
    -- Title row: farming time and state.
    local state
    if r and r.paused then state = K.Paint("Paused", T.HEX.warning)
    elseif r then state = U.Duration(r.farmSecs or 0) .. (g and K.Paint("  ·  guided", T.HEX.accent) or "")
    elseif g then state = K.Paint(g.phase == "travel" and "travelling" or "guided", T.HEX.accent) end
    f.state:SetText(state or "")
    local y = -30
    -- The route, when one is followed: two fitted lines.
    if g then
        local zone, what = H.SplitName(g.name or "Your farm")
        local where
        if g.phase == "farm" and g.mode ~= "free" and (g.stops or 0) > 0 then
            where = ("stop %d/%d"):format(g.stop or 1, g.stops)
        elseif g.phase == "travel" then
            where = g.owner == "fgps" and "Forever-GPS is leading" or (g.owner and "on the way" or "not navigating")
        elseif g.mode == "free" then
            where = "free farming"
        end
        local parts = {}
        if what then parts[#parts + 1] = what end
        if where then parts[#parts + 1] = where end
        local subText = table.concat(parts, "  ·  ")
        if subText == "" then subText = g.phaseText or "" end
        f.title:ClearAllPoints()
        f.title:SetPoint("TOPLEFT", 12, y)
        Fit(f.title, zone, inner, "strong", 14)
        f.sub:ClearAllPoints()
        f.sub:SetPoint("TOPLEFT", 12, y - 18)
        Fit(f.sub, subText, inner, "small", 12)
        f.title:Show()
        f.sub:SetShown(subText ~= "")
        y = y - (subText ~= "" and 40 or 22)
    else
        f.title:Hide()
        f.sub:Hide()
    end
    local colW = inner / 3
    for i, col in ipairs(f.kpi) do
        col:ClearAllPoints()
        col:SetPoint("TOPLEFT", 12 + (i - 1) * colW, y)
        col:SetWidth(colW - 6)
        col:SetShown(r ~= nil)
    end
    local lines, warn = {}, nil
    if r then
        local label, n, noun = Main(r, g)
        local per = (r.farmSecs or 0) >= 300 and n > 0 and (" · %s/h"):format(U.Thousands(n / math.max(1, r.farmSecs) * 3600)) or ""
        f.kpi[1].value:SetText(U.Thousands(n))
        f.kpi[1].value:SetTextColor(C.text[1], C.text[2], C.text[3])
        f.kpi[1].label:SetText(label .. per)
        f.kpi[2].value:SetText(tostring(r.skillups or 0))
        f.kpi[2].value:SetTextColor(C.accent[1], C.accent[2], C.accent[3])
        f.kpi[2].label:SetText("skill-ups" .. ((r.skillups or 0) > 0 and (" · %s/h"):format(U.Thousands(r.sph or 0)) or ""))
        local gph = (r.gph or 0) > 0 and (r.farmSecs or 0) >= 300
        f.kpi[3].value:SetText(gph and K.Money(r.gph, true) or "–")
        T.FitText(f.kpi[3].value, colW - 6, "display", 18, 12)
        f.kpi[3].value:SetTextColor(C.gold[1], C.gold[2], C.gold[3])
        f.kpi[3].label:SetText("gold/h, est.")
        y = y - 44
        if n == 0 and (r.farmSecs or 0) >= 600 and not r.paused then
            warn = K.Paint(("No %ss recognised in %s."):format(noun, U.Duration(r.farmSecs)), T.HEX.warning)
                .. " /hme diag shows what HME saw."
        end
    end
    -- The first open goal, in every size.
    local goal
    for _, gl in ipairs(HME.Goals.List()) do
        if not gl.doneAt then goal = gl break end
    end
    if goal then
        local p = HME.Goals.Progress(goal)
        f.goal:ClearAllPoints()
        f.goal:SetPoint("TOPLEFT", 12, y)
        f.goal:SetWidth(inner)
        f.goal.name:SetWidth(inner - 70)
        f.goal.name:SetText(goal.name or "Goal")
        f.goal.num:SetText(goal.type == "value" and K.Money(p.have or 0, true) or ("%s/%s"):format(U.Thousands(p.have or 0), U.Thousands(p.target or 0)))
        f.goal.bar:SetWidth(inner)
        f.goal.bar:Set((p.fraction or 0) * 100, 100, C.accent, "", 100)
        f.goal:Show()
        y = y - 28
    else
        f.goal:Hide()
    end
    if warn then lines[#lines + 1] = warn end
    -- 0.7.0, off unless chosen in Settings: the Copilot's top card in one line.
    local tip = H.CopilotLine()
    if tip then lines[#lines + 1] = tip end
    if size ~= "compact" then
        local live = r and HME.Session.Live()
        if live then
            for i = 1, math.min(size == "detailed" and 3 or 2, #live.items) do
                local it = live.items[i]
                local exp = it.expectedPerHour and K.Paint((" (expected %s)"):format(U.Thousands(it.expectedPerHour)), T.HEX.text3) or ""
                lines[#lines + 1] = ("%s  %s  ·  %s/h%s"):format(it.name, K.Paint(U.Thousands(it.n), T.HEX.text),
                    U.Thousands(it.perHour), exp)
            end
            if size == "detailed" and (live.skins > 0 or live.kills > 0) then
                lines[#lines + 1] = ("%d kills%s%s"):format(live.kills, live.avgKill and (" · %.0f s a kill"):format(live.avgKill) or "",
                    live.betweenSkins and (" · a skin every %.0f s"):format(live.betweenSkins) or "")
            end
        end
        if g then
            -- The phase in words only when the title's "stop N/M" does not already say it.
            if size == "detailed" and g.phaseText and (g.phase ~= "farm" or g.present or g.mode == "free" or g.holdID) then
                lines[#lines + 1] = g.phaseText
            end
            local owner = HME.Guidance.ArrowOwner()
            if owner then lines[#lines + 1] = K.Paint("Arrow: " .. owner, T.HEX.text3) end
        end
    end
    if size == "detailed" and r then
        local live = HME.Session.Live()
        if live and live.verdict then lines[#lines + 1] = live.verdict.text end
        local cmp = HME.Records.Compare()
        if cmp then lines[#lines + 1] = cmp.text end
        -- Only the parts that have something in them (no "0 s" and "0c/h").
        local split = {}
        if (r.combatSecs or 0) >= 1 then split[#split + 1] = "combat " .. U.Duration(r.combatSecs) end
        if (r.gatherSecs or 0) >= 1 then split[#split + 1] = "gathering " .. U.Duration(r.gatherSecs) end
        if (r.idleSecs or 0) >= 1 then split[#split + 1] = "idle " .. U.Duration(r.idleSecs) end
        if (r.travelSecs or 0) >= 1 and (r.tripGph or 0) > 0 then
            split[#split + 1] = ("with %s travel %s/h"):format(U.Duration(r.travelSecs), K.Money(r.tripGph, true))
        end
        if #split > 0 then lines[#lines + 1] = K.Paint(table.concat(split, " · "), T.HEX.text3) end
    end
    f.text:SetText(table.concat(lines, "\n"))
    f.text:SetShown(#lines > 0)
    f.text:ClearAllPoints()
    f.text:SetPoint("TOPLEFT", 12, y - 2)
    f.text:SetWidth(inner)
    local h = -y + 8 + (#lines > 0 and ((f.text:GetStringHeight() or 12) + 6) or 0)
    f:SetHeight(h)
    f:Show()
end

-- The Copilot line, or nil (setting off, nothing worth saying, or just "keep going").
function H.CopilotLine()
    if not (HME.settings and HME.settings.hudCopilot and HME.Copilot) then return nil end
    local top = HME.Copilot.Top()
    if not top or top.type == "stay" or top.type == "status" then return nil end
    return K.Paint("Copilot: ", T.HEX.brass) .. (top.title or "")
end
HME.Listen("COPILOT_CHANGED", function() if HME.settings and HME.settings.hudCopilot then H.Update() end end)

function H.Toggle()
    hidden = not hidden
    if hidden and f then f:Hide() else H.Update() end
end

HME.Listen("SESSION_CHANGED", function() H.Update() end)
HME.Listen("GUIDANCE_CHANGED", function() H.Update() end)
HME.Listen("GOALS_CHANGED", function() H.Update() end)
