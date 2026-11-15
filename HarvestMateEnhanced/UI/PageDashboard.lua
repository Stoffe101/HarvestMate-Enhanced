-- HarvestMate Enhanced: UI/PageDashboard.lua
-- At a glance, arranged around what you are doing now (0.4.0):
--   not farming  the next step (one card, one primary button), your learned
--                professions large, unlearned ones in a single line, goals
--                and your last session or suggestions;
--   farming      the farm panel first: what you follow, active time against
--                elapsed, what was recognised (and plainly when nothing was),
--                rates against the prediction, and the actions that fit the
--                state (navigate, hand the arrow over, pause, stop).
-- Which optional addons HME found is on the window's status line.
-- Copyright (C) 2026 HarvestMate Enhanced contributors. GPL-3.0-or-later.

local _, ns = ...
local HME = ns.HME
local T = ns.Theme
local K = HME.Kit
local U = HME.U
local C = T.C

local PAGE_W = 738
local GAP = 12
local PROF_H = 142

-- The one thing worth doing now: { icon, title, text, button, run }.
local function NextStep(profile)
    local s = HME.Suggest.Actionable()
    if s then
        return { icon = "Interface\\Icons\\INV_Misc_Note_02", kicker = "Suggested", title = s.title or "A suggestion", text = s.text,
            button = s.action.label or (s.action.kind == "finder" and "Open Farm Finder") or "Do it",
            run = function() HME.Suggest.Run(s) end }
    end
    local any
    for _, prof in ipairs(K.PROFS) do
        local st = HME.Guide.Status(prof, profile)
        if not st.missing then
            any = true
            if st.train == "capped" or st.train == "ready" then
                return { icon = K.PROF_ICON[prof], kicker = "Next step", title = ("Train %s"):format(st.nextRank and st.nextRank.name or prof),
                    text = ("Your %s is %d / %d. Training raises the cap so skill-ups keep coming."):format(prof, st.skill, st.max),
                    button = "Find a trainer", run = function() HME.OpenWindow("trainers") end }
            end
        end
    end
    for _, prof in ipairs(K.PROFS) do
        local st = HME.Guide.Status(prof, profile)
        if not st.missing and st.train ~= "max" then
            local nextText = st.milestone and ("Next: %s at %d."):format(st.milestone.what, st.milestone.skill) or ""
            return { icon = K.PROF_ICON[prof], kicker = "Next step", title = ("Level %s: %d / %d"):format(prof, st.skill, st.max),
                text = "The Farm Finder ranks every zone for this character. " .. nextText,
                button = "Find a farm", prof = prof, run = function()
                    HME.OpenWindow("finder")
                    if HME.Pages.finderSet then HME.Pages.finderSet(prof, "level") end
                end }
        end
    end
    if not any then
        return { icon = "Interface\\Icons\\INV_Misc_Book_11", kicker = "Start here", title = "Learn a gathering profession",
            text = "Herbalism, Mining, Skinning or Fishing: the Trainers page says where, for your side.",
            button = "Find a trainer", run = function() HME.OpenWindow("trainers") end }
    end
    return { icon = "Interface\\Icons\\INV_Misc_Coin_02", kicker = "Next step", title = "Every profession is maxed",
        text = "Farm for gold or a material: the Farm Finder ranks farms by gold an hour.",
        button = "Farm for gold", run = function()
            HME.OpenWindow("finder")
            if HME.Pages.finderSet then HME.Pages.finderSet(nil, "profit") end
        end }
end
HME.DashboardNextStep = NextStep

-- What the session is counting: skins, nodes or catches.
local function MainCount(r, g)
    local prof = g and g.prof
    if prof == "Skinning" or (r.skins or 0) > 0 or (r.kills or 0) > 0 then return "Skins", r.skins or 0, "skin" end
    if prof == "Fishing" or (r.catches or 0) > 0 then return "Catches", r.catches or 0, "catch" end
    if (r.nodes or 0) > 0 or prof == "Herbalism" or prof == "Mining" then return "Nodes", r.nodes or 0, "node" end
    if HME.Player.Professions().Skinning then return "Skins", r.skins or 0, "skin" end
    return "Gathered", (r.nodes or 0) + (r.catches or 0), "gather"
end

-- A plain sentence when the numbers need one (nothing recognised, idle, paused).
local function SessionNotice(r, label, n, noun)
    local active = r.farmSecs or 0
    if r.paused == "manual" then return K.Paint("Paused. ", T.HEX.warning) .. "The clock waits until you resume." end
    if r.paused == "idle" then
        return K.Paint("Idle. ", T.HEX.warning) .. "Nothing happened for a while, so that time is not counted as farming."
    end
    if n == 0 and active >= 600 then
        local kills = (r.kills or 0) > 0 and (" You looted %d corpses."):format(r.kills) or ""
        return K.Paint(("No %ss recognised in %s of farming.%s"):format(noun, U.Duration(active), kills), T.HEX.warning)
            .. " If you have been " .. (noun == "skin" and "skinning" or "gathering") .. ", type /hme diag: it shows what HME saw."
    end
    if n == 0 then return "Counting starts with your first " .. noun .. "." end
    return nil
end

HME.Pages.dashboard = function(body, page)
    local refs = {}
    page.refs = refs
    page.title:SetText("")
    if page.pip then page.pip:Hide() end
    body:ClearAllPoints()
    body:SetPoint("TOPLEFT", page, "TOPLEFT", 0, 0)
    body:SetPoint("BOTTOMRIGHT", page, "BOTTOMRIGHT", 0, 0)

    ---------------------------------------------------------------- greeting
    refs.who = K.Label(body, "", { template = "title", size = 19 })
    refs.who:SetPoint("TOPLEFT", 0, 2)
    refs.where = K.Label(body, "", { template = "small", color = C.text2 })
    refs.where:SetPoint("TOPLEFT", 0, -22)
    refs.state = K.Badge(body, 60, 22)
    refs.state:SetPoint("TOPRIGHT", 0, -4)

    ---------------------------------------------------------------- conflicts
    refs.conflict = T.Card(body, "Old addons still enabled", 0, 0, PAGE_W, 58)
    refs.conflict.bg:Paint({ C.warning[1] * 0.18, C.warning[2] * 0.14, C.warning[3] * 0.08, 1 })
    refs.conflict.title:SetTextColor(C.warning[1], C.warning[2], C.warning[3])
    refs.conflict.text = K.Label(refs.conflict, "", { width = PAGE_W - 230, template = "small" })
    refs.conflict.text:SetPoint("TOPLEFT", 14, -30)
    refs.conflict.btn = K.Button(refs.conflict, "Import and turn off", 170, 28, function()
        HME.Migrate.Run(true)
        local n = HME.Migrate.DisableReplaced()
        HME.Print(("copied their data in and turned off %d old addon%s. Type /reload to finish."):format(n, n == 1 and "" or "s"))
    end, "Copies their saved data into HME (theirs is kept as it is) and turns them off for this character. "
        .. "Takes effect after /reload.", "primary")
    refs.conflict.btn:SetPoint("RIGHT", -14, 0)

    ---------------------------------------------------------------- next step (not farming)
    local hero = CreateFrame("Frame", nil, body)
    hero:SetSize(PAGE_W, 96)
    hero.bg = T.Surface(hero, { 0.10, 0.14, 0.08, 1 })
    hero.topo = T.Topo(hero, C.accent, 0.07)
    T.Outline(hero, { C.accent[1], C.accent[2], C.accent[3], 0.30 })
    hero.ring = hero:CreateTexture(nil, "ARTWORK", nil, 1)
    hero.ring:SetSize(58, 58)
    hero.ring:SetPoint("LEFT", 16, 0)
    hero.ring:SetTexture(T.ART .. "Medallion")
    hero.ring:SetVertexColor(C.brass[1], C.brass[2], C.brass[3], 0.85)
    hero.icon = hero:CreateTexture(nil, "ARTWORK")
    hero.icon:SetSize(40, 40)
    hero.icon:SetPoint("CENTER", hero.ring, "CENTER")
    hero.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    hero.kicker = K.Label(hero, "", { template = "label", color = C.accent })
    hero.kicker:SetPoint("TOPLEFT", 90, -16)
    hero.title = K.Label(hero, "", { template = "title", size = 17, width = PAGE_W - 300, wrap = false })
    hero.title:SetPoint("TOPLEFT", 90, -33)
    hero.text = K.Label(hero, "", { template = "small", color = C.text2, width = PAGE_W - 280 })
    hero.text:SetPoint("TOPLEFT", 90, -56)
    hero.go = K.Button(hero, "", 160, 32, function(self) if self.run then self.run() end end, nil, "primary")
    hero.go:SetPoint("RIGHT", -18, 0)
    refs.hero = hero

    ---------------------------------------------------------------- farming now
    local act = CreateFrame("Frame", nil, body)
    act:SetSize(PAGE_W, 214)
    act.bg = T.Surface(act, { 0.10, 0.14, 0.08, 1 })
    act.topo = T.Topo(act, C.accent, 0.06)
    T.Outline(act, { C.accent[1], C.accent[2], C.accent[3], 0.30 })
    act.kicker = K.Label(act, "", { template = "label", color = C.accent })
    act.kicker:SetPoint("TOPLEFT", 18, -14)
    act.name = K.Label(act, "", { template = "title", size = 18, width = PAGE_W - 330, wrap = false })
    act.name:SetPoint("TOPLEFT", 18, -30)
    act.text = K.Label(act, "", { template = "small", color = C.text2, width = PAGE_W - 330 })
    act.text:SetPoint("TOPLEFT", 18, -54)
    -- Actions, right to left: the one that fits the state is primary.
    act.stop = K.Button(act, "Stop farming", 110, 28, function()
        if HME.Guidance.Active() then HME.Guidance.Stop() end
        if HME.Session.Current() then HME.Session.Stop("manual") end
    end, "Stops following the farm and ends the session: its rates go into what HME has learned about this area.", "danger")
    act.stop:SetPoint("TOPRIGHT", -16, -16)
    act.pause = K.Button(act, "Pause", 80, 28, function()
        if HME.Session.Current() then HME.Session.Pause() else HME.Session.Start() end
    end, "Pauses the session clock (a break, a trip to town). Resume when you are back.")
    act.pause:SetPoint("RIGHT", act.stop, "LEFT", -8, 0)
    act.main = K.Button(act, "", 120, 28, function(self) if self.run then self.run() end end, nil, "primary")
    act.main:SetPoint("RIGHT", act.pause, "LEFT", -8, 0)
    act.tiles = {}
    local tileW = (PAGE_W - 36 - 3 * 10) / 4
    for i, label in ipairs({ "Active time", "Skins", "Skill-ups", "Gold" }) do
        local t = K.Stat(act, label, tileW, 74)
        t:SetPoint("TOPLEFT", 18 + (i - 1) * (tileW + 10), -86)
        act.tiles[i] = t
    end
    act.note = K.Label(act, "", { template = "small", color = C.text2, width = PAGE_W - 36 })
    act.note:SetPoint("TOPLEFT", 18, -168)
    refs.act = act

    ---------------------------------------------------------------- professions
    refs.profs = {}
    for _, prof in ipairs(K.PROFS) do
        local c = T.Card(body, "", 0, 0, 200, PROF_H)
        c.title:Hide()
        c.tick:Hide()
        c.ring = c:CreateTexture(nil, "ARTWORK", nil, 1)
        c.ring:SetSize(40, 40)
        c.ring:SetPoint("TOPLEFT", 12, -12)
        c.ring:SetTexture(T.ART .. "Medallion")
        local pc = K.PROF_COLOR[prof]
        c.ring:SetVertexColor(pc[1], pc[2], pc[3], 0.9)
        c.icon = c:CreateTexture(nil, "ARTWORK")
        c.icon:SetSize(28, 28)
        c.icon:SetPoint("CENTER", c.ring, "CENTER")
        c.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        c.icon:SetTexture(K.PROF_ICON[prof])
        c.name = K.Label(c, prof, { template = "strong", size = 15 })
        c.name:SetPoint("TOPLEFT", 60, -15)
        c.rank = K.Label(c, "", { template = "meta" })
        c.rank:SetPoint("TOPLEFT", 60, -34)
        c.skill = K.Label(c, "", { template = "display", size = 24 })
        c.skill:SetPoint("TOPRIGHT", -14, -13)
        c.skill:SetJustifyH("RIGHT")
        c.bar = K.Bar(c, 100, 8)
        c.bar.text:Hide()
        c.bar:SetPoint("TOPLEFT", 12, -62)
        c.line = K.Label(c, "", { template = "small", color = C.text2, width = 100, wrap = false })
        c.line:SetPoint("TOPLEFT", 12, -80)
        c.find = K.Button(c, "Find a farm", 100, 26, function()
            HME.OpenWindow("finder")
            if HME.Pages.finderSet then HME.Pages.finderSet(prof, "level") end
        end, "The Farm Finder, ranked for leveling " .. prof .. ".")
        if prof == "Skinning" then
            c.levels = K.Button(c, "Skinning levels", 100, 26, function() HME.SkinTracker.Toggle() page.Refresh() end,
                "A small live display: the highest beast level you can skin, the levels that give points, and what you "
                .. "target. Also Shift-click on the minimap button, a key binding, or /hme sl.")
            refs.levels = c.levels
        end
        refs.profs[prof] = c
    end
    -- Unlearned professions: one line.
    local strip = CreateFrame("Frame", nil, body)
    strip:SetSize(PAGE_W, 36)
    strip.bg = T.Surface(strip, C.card)
    T.Outline(strip, C.line)
    strip.icons = {}
    strip.text = K.Label(strip, "", { template = "small", color = C.text2 })
    strip.btn = K.Button(strip, "Where to train", 120, 24, function() HME.OpenWindow("trainers") end, nil, "ghost")
    strip.btn:SetPoint("RIGHT", -8, 0)
    refs.strip = strip

    ---------------------------------------------------------------- goals and last session
    local goals = T.Card(body, "Goals", 0, 0, 363, 160)
    goals.rows = {}
    for i = 1, 3 do
        local row = CreateFrame("Frame", nil, goals)
        row:SetSize(335, 34)
        row:SetPoint("TOPLEFT", 14, -32 - (i - 1) * 38)
        row.name = K.Label(row, "", { template = "small", width = 250, wrap = false })
        row.name:SetPoint("TOPLEFT", 0, 0)
        row.num = K.Label(row, "", { template = "small", color = C.text2 })
        row.num:SetPoint("TOPRIGHT", 0, 0)
        row.num:SetJustifyH("RIGHT")
        row.bar = K.Bar(row, 335, 5)
        row.bar.text:Hide()
        row.bar:SetPoint("TOPLEFT", 0, -20)
        goals.rows[i] = row
    end
    goals.empty = K.Label(goals, "No goals yet. A goal (60 Medium Leather, Skinning 225) tracks itself as you gather.",
        { template = "small", color = C.text2, width = 335 })
    goals.empty:SetPoint("TOPLEFT", 14, -34)
    goals.more = K.Label(goals, "", { template = "meta" })
    goals.more:SetPoint("BOTTOMLEFT", 14, 14)
    -- Links sit in the title row, so short cards never cover them.
    goals.open = K.Button(goals, "Goals & Plans", 100, 24, function() HME.OpenWindow("goals") end, nil, "ghost")
    goals.open:SetPoint("TOPRIGHT", -8, -5)
    refs.goals = goals

    local side = T.Card(body, "", 0, 0, 363, 160)
    side.text = K.Label(side, "", { template = "small", width = 335 })
    side.text:SetPoint("TOPLEFT", 14, -32)
    side.act = K.Button(side, "", 100, 24, function(self) if self.run then self.run() end end)
    side.act:SetPoint("TOPRIGHT", -8, -5)
    side.quick = {}
    for i = 1, 2 do
        local b = K.Button(side, "", 100, 26, function(self) if self.p then HME.Profiles.Apply(self.p) end end,
            "Opens the Farm Finder with this saved search.")
        side.quick[i] = b
    end
    refs.side = side

    ---------------------------------------------------------------- layout
    local function Stack(list, y)
        for _, f in ipairs(list) do
            f:ClearAllPoints()
            f:SetPoint("TOPLEFT", 0, y)
            y = y - f:GetHeight() - GAP
        end
        return y
    end

    -- compact: while farming the cards drop their buttons (the farm panel has the actions).
    local function LayoutProfs(learned, y, compact)
        local n = #learned
        if n == 0 then return y end
        local w = (PAGE_W - (n - 1) * 10) / n
        local narrow = w < 260
        local h = compact and 104 or PROF_H
        for i, prof in ipairs(learned) do
            local c = refs.profs[prof]
            c:SetSize(w, h)
            c.skill:ClearAllPoints()
            if narrow then
                c.skill:SetPoint("TOPLEFT", 60, -34)
                c.skill:SetJustifyH("LEFT")
                T.SetRole(c.skill, "strong", 14)
                c.rank:Hide()
            else
                c.skill:SetPoint("TOPRIGHT", -14, -13)
                c.skill:SetJustifyH("RIGHT")
                T.SetRole(c.skill, "display", 24)
                c.rank:Show()
            end
            c.find:SetShown(not compact)
            c:ClearAllPoints()
            c:SetPoint("TOPLEFT", (i - 1) * (w + 10), y)
            c.bar:SetWidth(w - 24)
            c.bar.inner = w - 24
            c.line:SetWidth(w - 24)
            c.find:ClearAllPoints()
            c.find:SetPoint("BOTTOMLEFT", 12, 10)
            local levels = rawget(c, "levels")
            if levels then
                levels:ClearAllPoints()
                if narrow then
                    c.find:SetText("Farms")
                    levels:SetText(HME.SkinTracker.Shown() and "Hide levels" or "Levels")
                    c.find:SetWidth((w - 32) / 2)
                    levels:SetWidth((w - 32) / 2)
                    levels:SetPoint("LEFT", c.find, "RIGHT", 8, 0)
                else
                    c.find:SetText("Find a farm")
                    levels:SetText(HME.SkinTracker.Shown() and "Hide Skinning levels" or "Skinning levels")
                    c.find:SetWidth(120)
                    levels:SetWidth(150)
                    levels:SetPoint("LEFT", c.find, "RIGHT", 8, 0)
                end
                levels:SetShown(not compact)
            else
                c.find:SetText(narrow and "Farms" or "Find a farm")
                c.find:SetWidth(narrow and (w - 24) or 120)
            end
            c:Show()
        end
        return y - h - GAP
    end

    function page.Refresh()
        local profile = HME.Player.Profile()
        local name = UnitName and HME.Str((UnitName("player"))) or "You"
        refs.who:SetText(name)
        local parts = { ("Level %d %s"):format(profile.level or 0, profile.faction or "") }
        if profile.zone and profile.zone ~= "" then parts[#parts + 1] = profile.zone end
        if not profile.real then parts[#parts + 1] = K.Paint("planning with your overrides", T.HEX.warning) end
        refs.where:SetText(table.concat(parts, "  ·  "))

        local g = HME.Guidance.Active()
        local r = HME.Session.Rates()
        local farming = g ~= nil or r ~= nil
        if r and r.paused then
            refs.state:Set("Paused", T.HEX.warning)
        elseif farming then
            refs.state:Set("Farming", T.HEX.accent)
        else
            refs.state:Set("Not farming", T.HEX.text3)
        end

        local y = -50
        local conflicts = HME.Migrate.Conflicts()
        if #conflicts > 0 then
            local names = {}
            for i, c in ipairs(conflicts) do names[i] = c.label end
            refs.conflict.text:SetText(table.concat(names, ", ") .. " also running. HME has paused its own copy of "
                .. "their features so nothing happens twice.")
            refs.conflict:Show()
            y = Stack({ refs.conflict }, y)
        else
            refs.conflict:Hide()
        end

        -- Farming now, or the next step.
        if farming then
            hero:Hide()
            act:Show()
            page.FillActive(g, r)
            act:SetHeight((act.note:GetText() or "") ~= "" and 214 or 182)
            y = Stack({ act }, y)
        else
            act:Hide()
            hero:Show()
            local step = NextStep(profile)
            hero.icon:SetTexture(step.icon)
            hero.kicker:SetText(step.kicker or "Next step")
            hero.title:SetText(step.title)
            hero.text:SetText(step.text or "")
            hero.go:SetText(step.button)
            hero.go.run = step.run
            y = Stack({ hero }, y)
        end

        -- Professions: learned ones large; the rest on one line.
        local nLearned = 0
        for _, prof in ipairs(K.PROFS) do if HME.Player.Professions()[prof] then nLearned = nLearned + 1 end end
        local narrow = nLearned > 0 and (PAGE_W - (nLearned - 1) * 10) / nLearned < 260
        local learned, missing = {}, {}
        for _, prof in ipairs(K.PROFS) do
            local st = HME.Guide.Status(prof, profile)
            local c = refs.profs[prof]
            if st.missing then
                missing[#missing + 1] = prof
                c:Hide()
            else
                learned[#learned + 1] = prof
                local color = K.PROF_COLOR[prof]
                c.skill:SetText(("%d|cff%s / %d|r"):format(st.skill, T.HEX.text3, st.max))
                c.bar:Set(st.skill, st.max, color, "", st.max > 0 and st.max or 300)
                c.bar:Mark(st.nextRank and st.nextRank.from or nil, st.max > 0 and st.max or 300)
                local train = ({ capped = K.Paint("At the cap: train now", T.HEX.warning),
                    ready = K.Paint("Can train " .. (st.nextRank and st.nextRank.name or ""), T.HEX.accent),
                    max = K.Paint("Maxed", T.HEX.accent) })[st.train]
                c.rank:SetText(train or (st.rank and st.rank.name or ""))
                local eta = ""
                if st.milestone then
                    local sph = HME.Guide.PersonalRate(prof)
                    if sph and sph > 0 then eta = ("  ·  about %s at your pace"):format(U.Duration((st.milestone.skill - st.skill) / sph * 3600)) end
                end
                if narrow then
                    c.line:SetText(st.milestone and ("%s at %d"):format(st.milestone.what:gsub("^train ", ""), st.milestone.skill)
                        or (st.rank and st.rank.name or ""))
                else
                c.line:SetText(st.milestone and ("Next: %s at %d%s"):format(st.milestone.what, st.milestone.skill, eta)
                    or (st.train == "level" and ("Next rank at level %s"):format(st.nextRank and st.nextRank.level or "?") or ""))
                end
            end
        end
        y = LayoutProfs(learned, y, farming)
        if #missing > 0 and #learned > 0 then
            for i, prof in ipairs(missing) do
                local ic = strip.icons[i]
                if not ic then
                    ic = strip:CreateTexture(nil, "ARTWORK")
                    ic:SetSize(18, 18)
                    ic:SetTexCoord(0.08, 0.92, 0.08, 0.92)
                    ic:SetDesaturated(true)
                    ic:SetAlpha(0.7)
                    strip.icons[i] = ic
                end
                ic:SetTexture(K.PROF_ICON[prof])
                ic:ClearAllPoints()
                ic:SetPoint("LEFT", 12 + (i - 1) * 22, 0)
                ic:Show()
            end
            for i = #missing + 1, #strip.icons do strip.icons[i]:Hide() end
            strip.text:ClearAllPoints()
            strip.text:SetPoint("LEFT", 12 + #missing * 22 + 6, 0)
            strip.text:SetText(K.Paint("Not learned: ", T.HEX.text3) .. table.concat(missing, ", "))
            strip:Show()
            y = Stack({ strip }, y)
        else
            strip:Hide()
        end

        -- Goals and the side card share what is left.
        local left = 544 + y
        local h = math.max(100, left)
        local half = (PAGE_W - 10) / 2
        refs.goals:SetSize(half, h)
        refs.side:SetSize(half, h)
        refs.goals:ClearAllPoints()
        refs.goals:SetPoint("TOPLEFT", 0, y)
        refs.side:ClearAllPoints()
        refs.side:SetPoint("TOPLEFT", half + 10, y)
        page.FillGoals(h)
        page.FillSide(h)
        refs.goals:SetShown(left >= 96)
        refs.side:SetShown(left >= 96)

        if HME.Window.frame and HME.Window.frame.hint and HME.IntegrationLine then
            HME.Window.frame.hint:SetText(HME.IntegrationLine())
        end
    end

    -- The farming panel.
    function page.FillActive(g, r)
        local paused = r and r.paused
        act.kicker:SetText(paused and "Paused" or (g and g.phase == "travel" and "On the way" or "Farming now"))
        act.kicker:SetTextColor(unpack(paused and C.warning or C.accent))
        local zone = HME.Player.Profile().zone
        act.name:SetText(g and (g.name or "Your farm") or "Free farming")
        local lines = {}
        if g then
            lines[1] = g.phaseText or ""
        else
            lines[1] = "No route: HME counts what you gather" .. (zone and zone ~= "" and (" in " .. zone) or "") .. "."
        end
        act.text:SetText(table.concat(lines, "\n"))
        -- The main action fits the state.
        act.main.run = nil
        if g and HME.Guidance.CanTakeOver() then
            act.main:SetText("Guide me here")
            act.main.run = function() HME.Guidance.TakeOver() end
        elseif g and g.tookOver then
            act.main:SetText("Give arrow back")
            act.main.run = function() HME.Guidance.GiveBack() end
        elseif g and g.phase == "travel" and not g.owner then
            act.main:SetText("Navigate")
            act.main.run = function() HME.Guidance.Navigate() end
        elseif not g then
            act.main:SetText("Find a farm")
            act.main.run = function() HME.OpenWindow("finder") end
        end
        act.main:SetShown(act.main.run ~= nil)
        act.pause:SetText(paused and "Resume" or (r and "Pause" or "Start"))
        act.pause:SetKind(paused and "primary" or "secondary")
        -- Numbers.
        local pred = g and g.planned and g.planned.predicted or {}
        if r then
            local label, n, noun = MainCount(r, g)
            act.tiles[1]:Set(U.Duration(r.farmSecs or 0), ("of %s since it began"):format(U.Duration(r.totalSecs or r.farmSecs or 0)))
            act.tiles[2]:SetLabel(label)
            local perH = (r.farmSecs or 0) >= 300 and n > 0 and ("%s/h"):format(U.Thousands(n / math.max(1, r.farmSecs) * 3600)) or nil
            act.tiles[2]:Set(tostring(n), perH or (n == 0 and "none recognised yet" or "rate after 5 min"),
                n == 0 and (r.farmSecs or 0) >= 600 and C.warning or C.text)
            act.tiles[3]:Set(tostring(r.skillups or 0), pred.skill and ("predicted ~%s/h"):format(U.Thousands(pred.skill))
                or ((r.skillups or 0) > 0 and ("%s/h"):format(U.Thousands(r.sph or 0)) or "none yet"), C.accent)
            local gph = (r.gph or 0) > 0 and (r.farmSecs or 0) >= 300
            act.tiles[4]:SetLabel("Gold an hour")
            act.tiles[4]:Set(gph and K.Money(r.gph) or "–", gph and ("%s gathered, est."):format(K.Money(r.value or 0, true))
                or (pred.gph and ("predicted %s"):format(K.Money(pred.gph, true)) or "after 5 min with prices"), C.gold)
            act.note:SetText(SessionNotice(r, label, n, noun) or "")
            for _, t in ipairs(act.tiles) do t:Show() end
        else
            act.tiles[1]:Set("–", "starts with your first gather")
            act.tiles[2]:Set("0", "")
            act.tiles[3]:Set("0", pred.skill and ("predicted ~%s/h"):format(U.Thousands(pred.skill)) or "", C.accent)
            act.tiles[4]:Set("–", pred.gph and ("predicted %s"):format(K.Money(pred.gph, true)) or "", C.gold)
            act.note:SetText("The session starts by itself with your first gather, skin or catch at the farm.")
        end
    end

    function page.FillGoals(h)
        local list, open = {}, 0
        for _, gl in ipairs(HME.Goals.List()) do
            if not gl.doneAt then
                open = open + 1
                list[#list + 1] = gl
            end
        end
        local fit = math.max(1, math.min(3, math.floor((h - 66) / 38)))
        for i, row in ipairs(goals.rows) do
            local gl = list[i]
            if gl and i <= fit then
                local p = HME.Goals.Progress(gl)
                row.name:SetText(gl.name or "Goal")
                if gl.type == "value" then
                    row.num:SetText(("%s / %s"):format(K.Money(p.have or 0, true), K.Money(p.target or 0, true)))
                else
                    row.num:SetText(("%s / %s"):format(U.Thousands(p.have or 0), U.Thousands(p.target or 0)))
                end
                row.bar:Set((p.fraction or 0) * 100, 100, C.accent, "", 100)
                row:Show()
            else
                row:Hide()
            end
        end
        goals.empty:SetShown(open == 0)
        goals.more:SetText((open > fit and h >= 150) and ("+%d more"):format(open - fit) or "")
        goals.open:SetText(open == 0 and "Add a goal" or "Goals & Plans")
        goals.open:SetKind("ghost")
    end

    -- Suggestions when there are any; else your last session, and saved searches.
    function page.FillSide(h)
        local shown = HME.Suggest.Actionable()
        local tips = {}
        for i = #HME.Suggest.list, 1, -1 do
            local s = HME.Suggest.list[i]
            if s and s ~= shown then tips[#tips + 1] = K.Paint("•", T.HEX.accent) .. "  " .. s.text end
            if #tips >= 3 then break end
        end
        for _, b in ipairs(side.quick) do b:Hide() end
        side.act:Hide()
        if #tips > 0 then
            side.title:SetText("Suggestions")
            side.text:SetText(table.concat(tips, "\n"))
            return
        end
        local sessions = HME.db and HME.db.sessions or {}
        local last = sessions[#sessions]
        side.title:SetText(last and "Last session" or "Sessions")
        if last then
            local skins, nodes, catches = (last.counts or {}).skin or 0, ((last.counts or {}).herb or 0) + ((last.counts or {}).mine or 0),
                (last.counts or {}).fish or 0
            local what = {}
            if skins > 0 then what[#what + 1] = skins .. " skins" end
            if nodes > 0 then what[#what + 1] = nodes .. " nodes" end
            if catches > 0 then what[#what + 1] = catches .. " catches" end
            local hrs = math.max(1, last.farmSecs or last.secs or 0) / 3600
            local lines = {
                ("%s of farming%s"):format(U.Duration(last.farmSecs or last.secs or 0), last.route and (" on " .. last.route) or ""),
                ("%s  ·  %d skill-ups"):format(#what > 0 and table.concat(what, ", ") or "nothing gathered", last.skillups or 0),
            }
            if (last.value or 0) > 0 then
                lines[#lines + 1] = ("about %s gathered (%s an hour, est.)"):format(K.Money(last.value, true), K.Money(last.value / hrs, true))
            end
            side.text:SetText(table.concat(lines, "\n"))
            side.act:SetText("Profits & Stats")
            side.act:SetKind("ghost")
            side.act.run = function() HME.OpenWindow("stats") end
            side.act:Show()
        else
            side.text:SetText(K.Paint("Your farming sessions show here: time, what you gathered, skill-ups and an "
                .. "estimate of their worth. A session starts by itself with your first gather.", T.HEX.text2))
        end
        -- Saved searches, one click away.
        local profiles = HME.Profiles.List()
        local x = 14
        for i, b in ipairs(side.quick) do
            local p = profiles[i]
            b.p = p
            if p and h >= 140 then
                b:SetText(p.name)
                b:ClearAllPoints()
                b:SetPoint("BOTTOMLEFT", x, 8)
                x = x + b:GetWidth() + 8
                b:Show()
            end
        end
    end
end
