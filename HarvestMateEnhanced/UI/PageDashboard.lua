-- HarvestMate Enhanced: UI/PageDashboard.lua
-- At a glance: who you are, the one thing worth doing next (with a button),
-- each gathering profession (skill, cap, training, next milestone), the farm
-- being followed, this session, suggestions and saved profiles. Which
-- optional addons HME found is on the window's status line.
-- Copyright (C) 2026 HarvestMate Enhanced contributors. GPL-3.0-or-later.

local _, ns = ...
local HME = ns.HME
local T = ns.Theme
local K = HME.Kit
local U = HME.U
local C = T.C

local PAGE_W = 738

-- The one thing worth doing now: { icon, title, text, button, run }.
local function NextStep(profile)
    local g = HME.Guidance.Active()
    if g then
        return { icon = "Interface\\Icons\\INV_Misc_Map_01", title = "Continue: " .. (g.name or "your farm"),
            text = g.phaseText or "Follow the loop; the arrow points to the next stop.",
            button = "Navigate", run = function() HME.Guidance.Navigate() end }
    end
    local s = HME.Suggest.Actionable()
    if s then
        return { icon = "Interface\\Icons\\INV_Misc_Note_02", title = "Suggested", text = s.text,
            button = s.action.label or (s.action.kind == "finder" and "Open Farm Finder") or "Do it",
            run = function() HME.Suggest.Run(s) end }
    end
    local any
    for _, prof in ipairs(K.PROFS) do
        local st = HME.Guide.Status(prof, profile)
        if not st.missing then
            any = true
            if st.train == "capped" or st.train == "ready" then
                return { icon = K.PROF_ICON[prof], title = ("Train %s"):format(st.nextRank and st.nextRank.name or prof),
                    text = ("Your %s is %d / %d. Training raises the cap so skill-ups keep coming."):format(prof, st.skill, st.max),
                    button = "Find a trainer", run = function() HME.OpenWindow("trainers") end }
            end
        end
    end
    for _, prof in ipairs(K.PROFS) do
        local st = HME.Guide.Status(prof, profile)
        if not st.missing and st.train ~= "max" then
            local nextText = st.milestone and ("Next: %s at %d."):format(st.milestone.what, st.milestone.skill) or ""
            return { icon = K.PROF_ICON[prof], title = ("Level %s: %d / %d"):format(prof, st.skill, st.max),
                text = "The Farm Finder ranks every zone for this character. " .. nextText,
                button = "Find a farm", run = function()
                    HME.OpenWindow("finder")
                    if HME.Pages.finderSet then HME.Pages.finderSet(prof, "level") end
                end }
        end
    end
    if not any then
        return { icon = "Interface\\Icons\\INV_Misc_Book_11", title = "Learn a gathering profession",
            text = "Herbalism, Mining, Skinning or Fishing: the Trainers page says where.",
            button = "Find a trainer", run = function() HME.OpenWindow("trainers") end }
    end
    return { icon = "Interface\\Icons\\INV_Misc_Coin_02", title = "Every profession is maxed",
        text = "Farm for gold or a material: the Farm Finder ranks farms by gold an hour.",
        button = "Farm for gold", run = function()
            HME.OpenWindow("finder")
            if HME.Pages.finderSet then HME.Pages.finderSet(nil, "profit") end
        end }
end

HME.Pages.dashboard = function(body, page)
    local refs = {}
    page.refs = refs

    -- Who
    refs.who = K.Label(body, "", { template = "title", size = 17 })
    refs.who:SetPoint("TOPLEFT", 0, 2)
    refs.where = K.Label(body, "", { template = "small", color = C.text2 })
    refs.where:SetPoint("TOPLEFT", 0, -20)
    -- The greeting is the title here: the body takes the title's room.
    page.title:SetText("")
    body:ClearAllPoints()
    body:SetPoint("TOPLEFT", page, "TOPLEFT", 0, 0)
    body:SetPoint("BOTTOMRIGHT", page, "BOTTOMRIGHT", 0, 0)

    -- Conflicts with the replaced addons
    refs.conflict = T.Card(body, "Old addons still enabled", 0, -44, PAGE_W, 54)
    refs.conflict.bg:Paint({ C.warning[1] * 0.18, C.warning[2] * 0.14, C.warning[3] * 0.08, 1 })
    refs.conflict.title:SetTextColor(C.warning[1], C.warning[2], C.warning[3])
    refs.conflict.text = K.Label(refs.conflict, "", { width = PAGE_W - 210, template = "small" })
    refs.conflict.text:SetPoint("TOPLEFT", 12, -27)
    refs.conflict.btn = K.Button(refs.conflict, "Import and turn off", 170, 26, function()
        HME.Migrate.Run(true)
        local n = HME.Migrate.DisableReplaced()
        HME.Print(("copied their data in and turned off %d old addon%s. Type /reload to finish."):format(n, n == 1 and "" or "s"))
    end, "Copies their saved data into HME (theirs is kept as it is) and turns them off for this character. "
        .. "Takes effect after /reload.", "primary")
    refs.conflict.btn:SetPoint("RIGHT", -12, 0)

    -- Next step: one card, one primary button.
    local hero = CreateFrame("Frame", nil, body)
    hero:SetSize(PAGE_W, 70)
    hero.bg = T.Surface(hero, { 0.09, 0.15, 0.12, 1 })
    T.Outline(hero, { C.accent[1], C.accent[2], C.accent[3], 0.28 })
    hero.icon = K.Icon(hero, 40, nil)
    hero.icon:SetPoint("LEFT", 14, 0)
    hero.kicker = K.Label(hero, "NEXT STEP", { template = "label", color = C.accent })
    hero.kicker:SetPoint("TOPLEFT", 68, -13)
    hero.title = K.Label(hero, "", { template = "strong", size = 15, width = PAGE_W - 260, wrap = false })
    hero.title:SetPoint("TOPLEFT", 68, -27)
    hero.text = K.Label(hero, "", { template = "small", color = C.text2, width = PAGE_W - 260, wrap = false })
    hero.text:SetPoint("TOPLEFT", 68, -47)
    hero.go = K.Button(hero, "", 150, 30, function(self) if self.run then self.run() end end, nil, "primary")
    hero.go:SetPoint("RIGHT", -16, 0)
    refs.hero = hero

    -- Professions: four cards in a row
    local cardW = (PAGE_W - 3 * 10) / 4
    refs.profs = {}
    for i, prof in ipairs(K.PROFS) do
        local c = T.Card(body, "", (i - 1) * (cardW + 10), 0, cardW, 128)
        c.title:Hide()
        c.icon = K.Icon(c, 22, K.PROF_ICON[prof])
        c.icon:SetPoint("TOPLEFT", 12, -12)
        c.name = K.Label(c, prof, { template = "strong" })
        c.name:SetPoint("LEFT", c.icon, "RIGHT", 8, 0)
        c.skill = K.Label(c, "", { template = "strong", color = C.text })
        c.skill:SetPoint("TOPRIGHT", -12, -16)
        c.skill:SetJustifyH("RIGHT")
        c.bar = K.Bar(c, cardW - 24, 6)
        c.bar.text:Hide()
        c.bar:SetPoint("TOPLEFT", 12, -42)
        c.line1 = K.Label(c, "", { template = "small", width = cardW - 24, wrap = false })
        c.line1:SetPoint("TOPLEFT", 12, -55)
        c.line2 = K.Label(c, "", { template = "meta", width = cardW - 24, wrap = false })
        c.line2:SetPoint("TOPLEFT", 12, -71)
        c.find = K.Button(c, "Find a farm", cardW - 24, 24, function()
            HME.OpenWindow("finder")
            if HME.Pages.finderSet then HME.Pages.finderSet(prof, nil) end
        end)
        c.find:SetPoint("BOTTOMLEFT", 12, 10)
        refs.profs[prof] = c
    end

    -- The farm being followed
    local half = (PAGE_W - 10) / 2
    local farm = T.Card(body, "Your farm", 0, 0, half, 140)
    refs.farm = farm
    farm.name = K.Label(farm, "", { template = "strong", size = 14, width = half - 24, wrap = false })
    farm.name:SetPoint("TOPLEFT", 12, -30)
    farm.text = K.Label(farm, "", { template = "small", color = C.text2, width = half - 24 })
    farm.text:SetPoint("TOPLEFT", 12, -50)
    farm.stop = K.Button(farm, "Stop", 70, 24, function() HME.Guidance.Stop() end, nil, "ghost")
    farm.stop:SetPoint("BOTTOMRIGHT", -12, 10)
    farm.nav = K.Button(farm, "Navigate", 100, 24, function() HME.Guidance.Navigate() end,
        "Get there: Forever-GPS plans the journey when it is installed; otherwise HME's arrow points the way.")
    farm.nav:SetPoint("RIGHT", farm.stop, "LEFT", -6, 0)
    -- Guide me here: shown only while another Forever-GPS journey leads at the farm.
    farm.here = K.Button(farm, "Guide me here", 120, 24, function()
        local g = HME.Guidance.Active()
        if g and g.tookOver then HME.Guidance.GiveBack() else HME.Guidance.TakeOver() end
    end, "Follow HME's loop arrow here. Your other Forever-GPS journey keeps running: Forever-GPS only pauses its "
        .. "arrow, and gets it back when you stop farming, hand it back, or start a new journey.", "primary")
    farm.here:SetPoint("BOTTOMLEFT", 12, 10)
    farm.here:Hide()
    farm.find = K.Button(farm, "Open Farm Finder", 140, 24, function() HME.OpenWindow("finder") end)
    farm.find:SetPoint("BOTTOMLEFT", 12, 10)

    -- This session
    local ses = T.Card(body, "This session", half + 10, 0, half, 140)
    refs.ses = ses
    ses.big = K.Label(ses, "", { template = "display", size = 20 })
    ses.big:SetPoint("TOPLEFT", 12, -28)
    ses.text = K.Label(ses, "", { template = "small", color = C.text2, width = half - 24 })
    ses.text:SetPoint("TOPLEFT", 12, -56)
    ses.start = K.Button(ses, "Start", 76, 24, function()
        if HME.Session.Current() then HME.Session.Pause() else HME.Session.Start() end
    end)
    ses.start:SetPoint("BOTTOMLEFT", 12, 10)
    ses.stop = K.Button(ses, "End", 64, 24, function() HME.Session.Stop("manual") end,
        "Ends the session: its rates go into what HME has learned about this area.", "ghost")
    ses.stop:SetPoint("LEFT", ses.start, "RIGHT", 6, 0)
    ses.hud = K.Button(ses, "HUD", 60, 24, function() if HME.HUD then HME.HUD.Toggle() end end,
        "Show or hide the small farming display.", "ghost")
    ses.hud:SetPoint("BOTTOMRIGHT", -12, 10)

    -- Suggestions (left), quick start and goals (right)
    local advW = PAGE_W - 250
    local adv = T.Card(body, "Suggestions", 0, 0, advW, 104)
    refs.adv = adv
    adv.text = K.Label(adv, "", { template = "small", width = advW - 150 })
    adv.text:SetPoint("TOPLEFT", 12, -28)
    adv.act = K.Button(adv, "Do it", 120, 24, function(self) if self.s then HME.Suggest.Run(self.s) end end,
        "Does what the newest suggestion offers (opens the Farm Finder, or asks Forever-GPS for the nearest vendor). Only when you click.")
    adv.act:SetPoint("TOPRIGHT", -12, -10)
    adv.act:Hide()
    local qs = T.Card(body, "Quick start", advW + 10, 0, 240, 104)
    refs.qs = qs
    qs.buttons = {}
    for i = 1, 2 do
        local b = K.Button(qs, "", 216, 22, function(self) if self.p then HME.Profiles.Apply(self.p) end end)
        b:SetPoint("TOPLEFT", 12, -26 - (i - 1) * 26)
        qs.buttons[i] = b
    end
    qs.goals = K.Label(qs, "", { template = "meta", width = 216, wrap = false })
    qs.goals:SetPoint("BOTTOMLEFT", 12, 10)

    -- Rows placed from the top, so the conflict card can push the rest down.
    local function Layout(conflict)
        local y = -44
        if conflict then y = y - 64 end
        hero:ClearAllPoints()
        hero:SetPoint("TOPLEFT", 0, y)
        y = y - 82
        for i, prof in ipairs(K.PROFS) do
            local c = refs.profs[prof]
            c:ClearAllPoints()
            c:SetPoint("TOPLEFT", (i - 1) * (cardW + 10), y)
        end
        y = y - 140
        farm:ClearAllPoints()
        farm:SetPoint("TOPLEFT", 0, y)
        ses:ClearAllPoints()
        ses:SetPoint("TOPLEFT", half + 10, y)
        y = y - 152
        adv:ClearAllPoints()
        adv:SetPoint("TOPLEFT", 0, y)
        qs:ClearAllPoints()
        qs:SetPoint("TOPLEFT", advW + 10, y)
        adv:SetShown(not conflict)
        qs:SetShown(not conflict)
    end

    function page.Refresh()
        local profile = HME.Player.Profile()
        local name = UnitName and HME.Str((UnitName("player"))) or "You"
        refs.who:SetText(name)
        local parts = { ("Level %d %s"):format(profile.level or 0, profile.faction or "") }
        if profile.zone and profile.zone ~= "" then parts[#parts + 1] = profile.zone end
        if not profile.real then parts[#parts + 1] = K.Paint("planning with your overrides", T.HEX.warning) end
        refs.where:SetText(table.concat(parts, "  ·  "))
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
        Layout(#conflicts > 0)

        local step = NextStep(profile)
        refs.hero.icon.tex:SetTexture(step.icon)
        refs.hero.title:SetText(step.title)
        refs.hero.text:SetText(step.text or "")
        refs.hero.go:SetText(step.button)
        refs.hero.go.run = step.run

        for _, prof in ipairs(K.PROFS) do
            local c = refs.profs[prof]
            local st = HME.Guide.Status(prof, profile)
            local color = K.PROF_COLOR[prof]
            if st.missing then
                c.bar:Set(0, 0, color, "")
                c.bar:Mark(nil)
                c.skill:SetText("")
                c.line1:SetText(K.Paint("Not learned", T.HEX.text3))
                c.line2:SetText("Trainers page: where to learn it")
                c.icon.tex:SetDesaturated(true)
                c.name:SetTextColor(C.text2[1], C.text2[2], C.text2[3])
                c.find:SetText("Trainers")
                c.find:SetScript("OnClick", function() HME.OpenWindow("trainers") end)
            else
                c.icon.tex:SetDesaturated(false)
                c.name:SetTextColor(C.text[1], C.text[2], C.text[3])
                c.skill:SetText(("%d |cff78808c/ %d|r"):format(st.skill, st.max))
                c.bar:Set(st.skill, st.max, color, "", st.max > 0 and st.max or 300)
                c.bar:Mark(nil)
                local trainText = ({ capped = K.Paint("At cap: train now", T.HEX.warning),
                    ready = K.Paint("Can train " .. (st.nextRank and st.nextRank.name or ""), T.HEX.accent),
                    level = "Next rank at level " .. (st.nextRank and st.nextRank.level or "?"),
                    max = K.Paint("Maxed", T.HEX.accent) })[st.train]
                c.line1:SetText(trainText or (st.rank and st.rank.name or ""))
                local eta = ""
                if st.milestone then
                    local sph = HME.Guide.PersonalRate(prof)
                    if sph and sph > 0 then eta = (" · ~%s"):format(U.Duration((st.milestone.skill - st.skill) / sph * 3600)) end
                end
                c.line2:SetText(st.milestone and ("Next: %s at %d%s"):format(st.milestone.what, st.milestone.skill, eta) or "")
                c.find:SetText("Find a farm")
                c.find:SetScript("OnClick", function()
                    if c.find.disabled then return end
                    HME.OpenWindow("finder")
                    if HME.Pages.finderSet then HME.Pages.finderSet(prof, nil) end
                end)
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
            refs.farm.find:Hide()
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
            refs.farm.name:SetText(K.Paint("No farm selected", T.HEX.text2))
            refs.farm.text:SetText("Pick one in the Farm Finder: it draws the route, points the way and tracks how it goes.")
            refs.farm.stop:Hide()
            refs.farm.nav:Hide()
            refs.farm.here:Hide()
            refs.farm.find:Show()
        end

        local r = HME.Session.Rates()
        if r then
            refs.ses.big:SetText(K.Money(r.gph) .. K.Paint(" /h", T.HEX.text3))
            refs.ses.big:SetTextColor(C.gold[1], C.gold[2], C.gold[3])
            refs.ses.text:SetText(("%s farmed%s\n%d skill-ups (%.0f /h)  ·  %d nodes  ·  %d skins  ·  %d catches")
                :format(U.Duration(r.secs), r.paused and ("  " .. K.Paint("(paused" .. (r.paused == "idle" and ": idle" or "") .. ")", T.HEX.warning)) or "",
                r.skillups, r.sph, r.nodes, r.skins, r.catches))
            refs.ses.start:SetText(r.paused and "Resume" or "Pause")
            refs.ses.stop:Show()
        else
            refs.ses.big:SetText("Not running")
            refs.ses.big:SetTextColor(C.text2[1], C.text2[2], C.text2[3])
            refs.ses.text:SetText("A session starts by itself with your first gather, skin or catch.")
            refs.ses.start:SetText("Start")
            refs.ses.stop:Hide()
        end

        local advice = {}
        for i = #HME.Suggest.list, math.max(1, #HME.Suggest.list - 2), -1 do
            local s = HME.Suggest.list[i]
            if s then advice[#advice + 1] = K.Paint("•", T.HEX.accent) .. "  " .. s.text end
        end
        for _, prof in ipairs(K.PROFS) do
            local st = HME.Guide.Status(prof, profile)
            for _, m in ipairs(st.messages or {}) do
                if m[1] ~= "info" then
                    advice[#advice + 1] = K.Paint("•", m[1] == "good" and T.HEX.accent or T.HEX.warning) .. "  " .. m[2]
                end
            end
        end
        if #advice == 0 then advice[1] = K.Paint("Nothing needs your attention. Happy gathering.", T.HEX.text2) end
        local actionable = HME.Suggest.Actionable()
        refs.adv.act.s = actionable
        if actionable then
            refs.adv.act:SetText((actionable.action.label or (actionable.action.kind == "finder" and "Open Farm Finder") or "Do it"))
        end
        refs.adv.act:SetShown(actionable ~= nil)
        while #advice > 3 do table.remove(advice) end
        refs.adv.text:SetText(table.concat(advice, "\n"))
        if HME.Window.frame and HME.Window.frame.hint and HME.IntegrationLine then
            HME.Window.frame.hint:SetText(HME.IntegrationLine())
        end

        local profiles = HME.Profiles.List()
        for i, b in ipairs(refs.qs.buttons) do
            local p = profiles[i]
            b.p = p
            b:SetShown(p ~= nil)
            if p then b:SetText(p.name) end
        end
        local goals, open = HME.Goals.List(), 0
        local first
        for _, g2 in ipairs(goals) do
            if not g2.doneAt then
                open = open + 1
                first = first or g2
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
