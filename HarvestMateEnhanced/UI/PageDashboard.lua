-- HarvestMate Enhanced: UI/PageDashboard.lua
-- At a glance: the character, each gathering profession (skill, cap, next
-- milestone, training), the farm being followed, this session, advice, and
-- which optional addons HME found.
-- Copyright (C) 2026 HarvestMate Enhanced contributors. GPL-3.0-or-later.

local _, ns = ...
local HME = ns.HME
local T = ns.Theme
local K = HME.Kit
local U = HME.U
local C = T.C

local PAGE_W = 738

HME.Pages.dashboard = function(body, page)
    local refs = {}
    page.refs = refs

    -- Who
    refs.who = K.Label(body, "", { template = "GameFontNormalLarge", color = C.title })
    refs.who:SetPoint("TOPLEFT", 0, 0)
    refs.where = K.Label(body, "", { template = "GameFontHighlightSmall", color = C.muted })
    refs.where:SetPoint("TOPLEFT", 0, -22)

    -- Conflicts with the replaced addons
    refs.conflict = T.Card(body, "Old addons still enabled", 0, -44, PAGE_W, 54)
    refs.conflict.text = K.Label(refs.conflict, "", { width = PAGE_W - 200, template = "GameFontHighlightSmall" })
    refs.conflict.text:SetPoint("TOPLEFT", 12, -26)
    refs.conflict.btn = K.Button(refs.conflict, "Import and turn off", 160, 22, function()
        HME.Migrate.Run(true)
        local n = HME.Migrate.DisableReplaced()
        HME.Print(("copied their data in and turned off %d old addon%s. Type /reload to finish."):format(n, n == 1 and "" or "s"))
    end, "Copies their saved data into HME (theirs is kept as it is) and turns them off for this character. "
        .. "Takes effect after /reload.")
    refs.conflict.btn:SetPoint("TOPRIGHT", -12, -22)

    -- Professions: four cards in a row
    local cardW = (PAGE_W - 3 * 8) / 4
    refs.profs = {}
    for i, prof in ipairs(K.PROFS) do
        local c = T.Card(body, prof, (i - 1) * (cardW + 8), -106, cardW, 128)
        c.icon = K.Icon(c, 28, K.PROF_ICON[prof])
        c.icon:SetPoint("TOPRIGHT", -10, -8)
        c.bar = K.Bar(c, cardW - 24, 16)
        c.bar:SetPoint("TOPLEFT", 12, -42)
        c.line1 = K.Label(c, "", { template = "GameFontHighlightSmall", width = cardW - 24 })
        c.line1:SetPoint("TOPLEFT", 12, -64)
        c.line2 = K.Label(c, "", { template = "GameFontDisableSmall", width = cardW - 24 })
        c.line2:SetPoint("TOPLEFT", 12, -82)
        c.find = K.Button(c, "Find a farm", cardW - 24, 20, function()
            HME.OpenWindow("finder")
            if HME.Pages.finderSet then HME.Pages.finderSet(prof, nil) end
        end)
        c.find:SetPoint("BOTTOMLEFT", 12, 8)
        refs.profs[prof] = c
    end

    -- The farm being followed
    local farm = T.Card(body, "Your farm", 0, -242, PAGE_W / 2 - 4, 150)
    refs.farm = farm
    farm.name = K.Label(farm, "", { template = "GameFontNormal", color = C.gold, width = PAGE_W / 2 - 30 })
    farm.name:SetPoint("TOPLEFT", 12, -28)
    farm.text = K.Label(farm, "", { template = "GameFontHighlightSmall", width = PAGE_W / 2 - 30 })
    farm.text:SetPoint("TOPLEFT", 12, -48)
    farm.stop = K.Button(farm, "Stop", 80, 20, function() HME.Guidance.Stop() end)
    farm.stop:SetPoint("BOTTOMRIGHT", -12, 10)
    farm.nav = K.Button(farm, "Navigate", 100, 20, function() HME.Guidance.Navigate() end,
        "Get there: Forever-GPS plans the journey when it is installed; otherwise HME's arrow points the way.")
    farm.nav:SetPoint("RIGHT", farm.stop, "LEFT", -8, 0)
    -- Guide me here: shown only while another Forever-GPS journey leads at the farm.
    farm.here = K.Button(farm, "Guide me here", 120, 20, function()
        local g = HME.Guidance.Active()
        if g and g.tookOver then HME.Guidance.GiveBack() else HME.Guidance.TakeOver() end
    end, "Follow HME's loop arrow here. Your other Forever-GPS journey keeps running: Forever-GPS only pauses its "
        .. "arrow, and gets it back when you stop farming, hand it back, or start a new journey.")
    farm.here:SetPoint("BOTTOMRIGHT", farm.nav, "TOPRIGHT", 0, 6)
    farm.here:Hide()
    farm.find = K.Button(farm, "Open Farm Finder", 150, 20, function() HME.OpenWindow("finder") end)
    farm.find:SetPoint("BOTTOMLEFT", 12, 10)

    -- This session
    local ses = T.Card(body, "This session", PAGE_W / 2 + 4, -242, PAGE_W / 2 - 4, 150)
    refs.ses = ses
    ses.big = K.Label(ses, "", { template = "GameFontNormalLarge", color = C.gold })
    ses.big:SetPoint("TOPLEFT", 12, -28)
    ses.text = K.Label(ses, "", { template = "GameFontHighlightSmall", width = PAGE_W / 2 - 30 })
    ses.text:SetPoint("TOPLEFT", 12, -54)
    ses.start = K.Button(ses, "Start", 70, 20, function()
        if HME.Session.Current() then HME.Session.Pause() else HME.Session.Start() end
    end)
    ses.start:SetPoint("BOTTOMLEFT", 12, 10)
    ses.stop = K.Button(ses, "End", 70, 20, function() HME.Session.Stop("manual") end,
        "Ends the session: its rates go into what HME has learned about this area.")
    ses.stop:SetPoint("LEFT", ses.start, "RIGHT", 8, 0)
    ses.hud = K.Button(ses, "HUD", 60, 20, function() if HME.HUD then HME.HUD.Toggle() end end,
        "Show or hide the small farming display.")
    ses.hud:SetPoint("BOTTOMRIGHT", -12, 10)

    -- Suggestions and advice (left), quick start and goals (right)
    local adv = T.Card(body, "Suggestions", 0, -400, PAGE_W / 2 + 60, 112)
    refs.adv = adv
    adv.text = K.Label(adv, "", { template = "GameFontHighlightSmall", width = PAGE_W / 2 + 36 })
    adv.text:SetPoint("TOPLEFT", 12, -26)
    adv.act = K.Button(adv, "Do it", 120, 18, function(self) if self.s then HME.Suggest.Run(self.s) end end,
        "Does what the newest suggestion offers (opens the Farm Finder, or asks Forever-GPS for the nearest vendor). Only when you click.")
    adv.act:SetPoint("TOPRIGHT", -8, -4)
    adv.act:Hide()
    adv.integ = K.Label(body, "", { template = "GameFontDisableSmall", width = PAGE_W })
    adv.integ:SetPoint("TOPLEFT", 0, -516)
    local qs = T.Card(body, "Quick start", PAGE_W / 2 + 68, -400, PAGE_W / 2 - 68, 112)
    refs.qs = qs
    qs.buttons = {}
    for i = 1, 3 do
        local b = K.Button(qs, "", PAGE_W / 2 - 92, 20, function(self) if self.p then HME.Profiles.Apply(self.p) end end)
        b:SetPoint("TOPLEFT", 12, -24 - (i - 1) * 24)
        qs.buttons[i] = b
    end
    qs.goals = K.Label(qs, "", { template = "GameFontDisableSmall", width = PAGE_W / 2 - 92 })
    qs.goals:SetPoint("BOTTOMLEFT", 12, 8)

    function page.Refresh()
        local profile = HME.Player.Profile()
        local name = UnitName and HME.Str((UnitName("player"))) or "You"
        refs.who:SetText(("%s  |cffcfc4adlevel %d %s|r"):format(name, profile.level, profile.faction))
        refs.where:SetText((profile.zone or "") .. (profile.real and "" or "   |cffff8a3d(planning with your overrides)|r"))
        local conflicts = HME.Migrate.Conflicts()
        if #conflicts > 0 then
            local names = {}
            for i, c in ipairs(conflicts) do names[i] = c.label end
            refs.conflict.text:SetText(table.concat(names, ", ") .. " also running. HME has paused its own copy of "
                .. "their features so nothing happens twice.")
            refs.conflict:Show()
        else
            refs.conflict:Hide()
        end
        for _, prof in ipairs(K.PROFS) do
            local c = refs.profs[prof]
            local st = HME.Guide.Status(prof, profile)
            if st.missing then
                c.bar:Set(0, 0, K.PROF_COLOR[prof], "not learned")
                c.bar:Mark(nil)
                c.line1:SetText("Not learned on this character.")
                c.line2:SetText("")
                c.icon.tex:SetDesaturated(true)
            else
                c.icon.tex:SetDesaturated(false)
                c.bar:Set(st.skill, st.max, K.PROF_COLOR[prof], st.skill .. " / " .. st.max)
                c.bar:Mark(st.milestone and st.milestone.skill)
                local trainText = ({ capped = "|cffff8a3dAt cap: train now|r", ready = "|cff48c75aCan train " .. (st.nextRank and st.nextRank.name or "") .. "|r",
                    level = "|cffffe14dNext rank at level " .. (st.nextRank and st.nextRank.level or "?") .. "|r", max = "|cff48c75aMaxed|r" })[st.train]
                c.line1:SetText(trainText or (st.rank and st.rank.name or ""))
                local eta = ""
                if st.milestone then
                    local sph = HME.Guide.PersonalRate(prof)
                    if sph and sph > 0 then eta = (" · ~%s at your pace"):format(U.Duration((st.milestone.skill - st.skill) / sph * 3600)) end
                end
                c.line2:SetText(st.milestone and ("Next: %s at %d%s"):format(st.milestone.what, st.milestone.skill, eta) or "")
            end
        end
        local g = HME.Guidance.Active()
        if g then
            refs.farm.name:SetText(g.name or "Farm")
            local lines = { g.phaseText or "" }
            local pred = g.planned and g.planned.predicted
            if pred then
                if pred.skill then lines[#lines + 1] = ("Predicted: %.0f skill-ups an hour"):format(pred.skill) end
                if pred.gph then lines[#lines + 1] = "Predicted: " .. K.Money(pred.gph) .. " an hour" end
            end
            refs.farm.text:SetText(table.concat(lines, "\n"))
            refs.farm.stop:Show()
            refs.farm.nav:Show()
            if HME.Guidance.CanTakeOver() then
                refs.farm.here:SetText("Guide me here")
                refs.farm.here:Show()
            elseif g.tookOver then
                refs.farm.here:SetText("Give arrow back")
                refs.farm.here:Show()
            else
                refs.farm.here:Hide()
            end
        else
            refs.farm.name:SetText("No farm selected")
            refs.farm.text:SetText("Pick one in the Farm Finder: it draws the route, points the way and tracks how it goes.")
            refs.farm.stop:Hide()
            refs.farm.nav:Hide()
            refs.farm.here:Hide()
        end
        local r = HME.Session.Rates()
        if r then
            refs.ses.big:SetText(K.Money(r.gph) .. " /h")
            refs.ses.text:SetText(("%s farmed%s\n%d skill-ups (%.0f /h)  ·  %d nodes  ·  %d skins  ·  %d catches\nValue %s")
                :format(U.Duration(r.secs), r.paused and ("  |cffff8a3d(paused" .. (r.paused == "idle" and ": idle" or "") .. ")|r") or "",
                r.skillups, r.sph, r.nodes, r.skins, r.catches, K.Money(r.value)))
            refs.ses.start:SetText(r.paused and "Resume" or "Pause")
            refs.ses.stop:Show()
        else
            refs.ses.big:SetText("Not running")
            refs.ses.text:SetText("A session starts by itself with your first gather, skin or catch.")
            refs.ses.start:SetText("Start")
            refs.ses.stop:Hide()
        end
        local advice = {}
        for i = #HME.Suggest.list, math.max(1, #HME.Suggest.list - 2), -1 do
            local s = HME.Suggest.list[i]
            if s then advice[#advice + 1] = "|cffffd100•|r " .. s.text end
        end
        for _, prof in ipairs(K.PROFS) do
            local st = HME.Guide.Status(prof, profile)
            for _, m in ipairs(st.messages or {}) do
                if m[1] ~= "info" then
                    local hex = m[1] == "good" and "48c75a" or "ffe14d"
                    advice[#advice + 1] = "|cff" .. hex .. "•|r " .. m[2]
                end
            end
        end
        if #advice == 0 then advice[1] = "Nothing needs your attention. Happy gathering." end
        local actionable = HME.Suggest.Actionable()
        refs.adv.act.s = actionable
        if actionable then
            refs.adv.act:SetText((actionable.action.label or (actionable.action.kind == "finder" and "Open Farm Finder") or "Do it"))
        end
        refs.adv.act:SetShown(actionable ~= nil)
        while #advice > 4 do table.remove(advice) end
        refs.adv.text:SetText(table.concat(advice, "\n"))
        refs.adv.integ:SetText(HME.IntegrationLine and HME.IntegrationLine() or "")
        local profiles = HME.Profiles.List()
        for i, b in ipairs(refs.qs.buttons) do
            local p = profiles[i]
            b.p = p
            b:SetShown(p ~= nil)
            if p then b:SetText(p.name) end
        end
        local goals, open = HME.Goals.List(), 0
        local first
        for _, g in ipairs(goals) do
            if not g.doneAt then
                open = open + 1
                first = first or g
            end
        end
        if first then
            local p = HME.Goals.Progress(first)
            refs.qs.goals:SetText(("Goal: %s %d%%%s"):format(first.name, p.fraction * 100, open > 1 and (" (+" .. (open - 1) .. " more)") or ""))
        else
            refs.qs.goals:SetText(#profiles == 0 and "No profiles yet: Save one in the Farm Finder." or "No open goals.")
        end
    end
end
