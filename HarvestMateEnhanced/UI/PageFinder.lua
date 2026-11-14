-- HarvestMate Enhanced: UI/PageFinder.lua
-- The Farm Finder: pick a profession and a goal, get farms ranked for this
-- character, see why, and start one. The search runs in the background (a
-- few milliseconds a frame), so the game never stutters.
-- Copyright (C) 2026 HarvestMate Enhanced contributors. GPL-3.0-or-later.

local _, ns = ...
local HME = ns.HME
local T = ns.Theme
local K = HME.Kit
local U = HME.U
local C = T.C

local PAGE_W = 738
local LIST_W = 340

local function State()
    local ui = HME.char and HME.char.ui or {}
    ui.finder = ui.finder or {}
    local f = ui.finder
    if not f.prof then
        -- Default: the first gathering profession the character has.
        for _, p in ipairs(K.PROFS) do
            if HME.Player.Professions()[p] then f.prof = p break end
        end
        f.prof = f.prof or "Herbalism"
    end
    f.goal = f.goal or "level"
    f.risk = f.risk or (HME.settings and HME.settings.riskMode) or "balanced"
    return f
end

-- Text -> targets for the material goal: node names and item ids that match.
local function Targets(prof, text)
    text = U.Trim(text or ""):lower()
    if text == "" then return nil end
    local targets, n = {}, 0
    for _, maps in pairs(ns.NodeSpawns and { ns.NodeSpawns[prof] } or {}) do
        for _, list in pairs(maps or {}) do
            for _, e in ipairs(list) do
                if e[1]:lower():find(text, 1, true) then
                    if not targets[e[1]] then n = n + 1 end
                    targets[e[1]] = true
                    targets[e[2]] = true
                end
            end
        end
    end
    local def = ns.professions[prof]
    for _, e in ipairs(def and def.items or {}) do
        if e.id and e.name and e.name:lower():find(text, 1, true) then
            if not targets[e.id] then n = n + 1 end
            targets[e.id] = true
            targets[e.name] = true
        end
    end
    return n > 0 and targets or nil, n
end

HME.Pages.finder = function(body, page)
    local st = State()
    local results, selected = {}, nil

    -- Row 1: profession, goal, risk
    local profs = K.Segments(body, K.PROFS, { Herbalism = "Herbalism", Mining = "Mining", Skinning = "Skinning", Fishing = "Fishing" },
        function() return State().prof end, function(k) State().prof = k; page.Search() end, 88)
    profs:SetPoint("TOPLEFT", 0, 0)
    local goalKeys, goalLabels = {}, {}
    for _, g in ipairs(HME.Recommend.GOALS) do
        goalKeys[#goalKeys + 1] = g.key
        goalLabels[g.key] = g.label
    end
    local goal = T.Dropdown(body, 200, goalKeys, goalLabels, function() return State().goal end, function(k)
        State().goal = k
        page.Layout()
        page.Search()
    end)
    goal:SetPoint("TOPLEFT", 364, 0)
    local riskLabels = { fastest = "Fastest", balanced = "Balanced risk", safer = "Prefer lower risk" }
    local risk = T.Dropdown(body, 160, { "fastest", "balanced", "safer" }, riskLabels, function() return State().risk end,
        function(k) State().risk = k; page.Search() end)
    risk:SetPoint("TOPLEFT", 576, 0)
    T.Tooltip(risk, "PvP and creature risk", "How much risk counts against a farm: territory, enemy guards, creatures "
        .. "above your level, elites, and where you died. HME cannot see other players; no place is ever called safe.")

    -- Row 2: material search / planning overrides / status
    local mat = T.EditBox(body, 200)
    mat:SetPoint("TOPLEFT", 0, -32)
    mat.hint = K.Label(mat, "Material, e.g. Goldthorn", { template = "GameFontDisableSmall" })
    mat.hint:SetPoint("LEFT", 6, 0)
    mat:SetScript("OnTextChanged", function(self)
        self.hint:SetShown(self:GetText() == "")
        State().material = self:GetText()
    end)
    mat:SetScript("OnEnterPressed", function(self) self:ClearFocus(); page.Search() end)

    local plan = HME.char and HME.char.plan or {}
    local planSwitch = T.LabeledSwitch(body, "Plan for", 212, -36)
    T.Tooltip(planSwitch, "Plan for another level or skill", "Off: HME uses this character as the game reports it. "
        .. "On: use the level and skill typed here, to look ahead or plan for an alt.")
    local lvl = T.EditBox(body, 36)
    lvl:SetPoint("TOPLEFT", 300, -32)
    lvl:SetNumeric(true)
    local lvlL = K.Label(body, "lvl", { template = "GameFontDisableSmall" })
    lvlL:SetPoint("LEFT", lvl, "RIGHT", 4, 0)
    local skl = T.EditBox(body, 40)
    skl:SetPoint("TOPLEFT", 362, -32)
    skl:SetNumeric(true)
    local sklL = K.Label(body, "skill", { template = "GameFontDisableSmall" })
    sklL:SetPoint("LEFT", skl, "RIGHT", 4, 0)
    local function SavePlan()
        local p = HME.char.plan
        p.level = tonumber(lvl:GetText())
        p.skills = p.skills or {}
        p.skills[State().prof] = tonumber(skl:GetText())
    end
    planSwitch:SetScript("OnClick", function(self)
        HME.char.plan.enabled = not HME.char.plan.enabled
        self:SetOn(HME.char.plan.enabled)
        SavePlan()
        page.Search()
    end)
    for _, eb in ipairs({ lvl, skl }) do
        eb:SetScript("OnEnterPressed", function(self) self:ClearFocus(); SavePlan(); page.Search() end)
    end
    local go = K.Button(body, "Search", 90, 22, function() SavePlan(); page.Search() end)
    go:SetPoint("TOPLEFT", 440, -32)
    local status = K.Label(body, "", { template = "GameFontDisableSmall", width = 200 })
    status:SetPoint("TOPLEFT", 540, -36)

    -- Results
    local list = K.List(body, {
        width = LIST_W, height = 444, rowHeight = 46,
        empty = "Pick a profession and a goal.",
        makeRow = function(row)
            row.rank = K.Label(row, "", { template = "GameFontNormalLarge", color = C.grey })
            row.rank:SetPoint("LEFT", 6, 0)
            row.title = K.Label(row, "", { template = "GameFontNormal", color = C.title, width = 200, wrap = false })
            row.title:SetPoint("TOPLEFT", 34, -6)
            row.sub = K.Label(row, "", { template = "GameFontHighlightSmall", width = 210, wrap = false })
            row.sub:SetPoint("TOPLEFT", 34, -24)
            row.risk = K.Badge(row, 84, 14)
            row.risk:SetPoint("TOPRIGHT", -4, -6)
            row.conf = K.Badge(row, 84, 14)
            row.conf:SetPoint("TOPRIGHT", -4, -24)
        end,
        fillRow = function(row, r)
            row.rank:SetText(r.rank)
            row.title:SetText(r.zone .. "  |cff9a9a9a" .. r.subarea .. "|r")
            row.sub:SetText(page.Headline(r))
            row.risk:Set(r.risk and r.risk.label or "?", r.risk and r.risk.hex)
            row.conf:Set((r.confidence.label or "?") .. " conf.", K.ConfHex(r.confidence.label))
        end,
        onClick = function(r) selected = r; page.ShowDetail(r) end,
    })
    list:SetPoint("TOPLEFT", 0, -64)

    -- Detail
    local d = T.Card(body, "Details", LIST_W + 10, -64, PAGE_W - LIST_W - 10, 444)
    d.title = K.Label(d, "", { template = "GameFontNormalLarge", color = C.gold, width = 360 })
    d.title:SetPoint("TOPLEFT", 12, -26)
    d.text = K.Label(d, "", { template = "GameFontHighlightSmall", width = PAGE_W - LIST_W - 36 })
    d.text:SetPoint("TOPLEFT", 12, -50)
    d.preview = K.Button(d, "Preview on map", 120, 22, function() if selected then HME.MapOverlay.Preview(selected) end end,
        "Opens the world map on this farm with its spawn points, hunting areas and suggested loop.")
    d.preview:SetPoint("BOTTOMLEFT", 12, 10)
    d.start = K.Button(d, "Start farming route", 150, 22, function()
        if selected then HME.Guidance.StartResult(selected, State().goal) end
    end, "Plans the route on the map and minimap and guides you along it. If the farm is far away, use Navigate first.")
    d.start:SetPoint("LEFT", d.preview, "RIGHT", 8, 0)
    d.nav = K.Button(d, "Navigate", 90, 22, function()
        if selected then HME.Guidance.NavigateToResult(selected, State().goal) end
    end, "Long journeys go through Forever-GPS when it is installed; HME's own arrow takes over on arrival.")
    d.nav:SetPoint("LEFT", d.start, "RIGHT", 8, 0)
    for _, b in ipairs({ d.preview, d.start, d.nav }) do b:Hide() end

    function page.Headline(r)
        local m, g = r.metrics, State().goal
        local mode = (HME.settings and HME.settings.priceMode) or "typical"
        local gph = m.gph and K.Money(m.gph[mode] or 0) .. "/h" or ""
        local travel = r.travel and U.Duration(r.travel) or "travel ?"
        if g == "profit" then
            return gph .. "  ·  " .. travel
        elseif g == "material" then
            return ("%.0f units/h  ·  %s"):format(m.materialPerHour or 0, travel)
        end
        return ("%.0f skill/h  ·  %s  ·  %s"):format(m.skillPerHour or 0, gph, travel)
    end

    function page.ShowDetail(r)
        local m = r.metrics
        local mode = (HME.settings and HME.settings.priceMode) or "typical"
        d.title:SetText(("%s  |cff9a9a9a%s, around %d, %d|r"):format(r.zone, r.subarea, r.cx * 100, r.cy * 100))
        local lines = {}
        local function add(s) lines[#lines + 1] = s end
        if r.levels then add(("Creatures here: about level %d-%d"):format(r.levels[1], r.levels[2])) end
        if m.skillPerHour then add(("Skill-ups: |cffffd100%.0f an hour|r (%.0f%% of gathers give a point now)")
            :format(m.skillPerHour, (m.skillChance or 0) * 100)) end
        if m.gph then
            add(("Gold an hour: |cffffd100%s|r typical, %s conservative, %s optimistic"):format(
                K.Money(m.gph.typical or 0), K.Money(m.gph.conservative or 0), K.Money(m.gph.optimistic or 0)))
        end
        if m.materialPerHour then add(("Material: about %.0f an hour"):format(m.materialPerHour)) end
        if m.beastsPerHour then
            add(("Beasts: about %.0f an hour (%s); a kill about %.0f s (%s), walk %.0f s"):format(m.beastsPerHour,
                m.limit == "respawn" and "respawns limit it" or "your pace limits it", m.killSecs, m.killBasis, m.walkSecs))
        end
        if m.nodesPerHour then
            add(("Nodes: about %.0f an hour, loop about %s (%s a lap)"):format(m.nodesPerHour, U.Yards(m.loopYards),
                U.Duration(m.lapSecs)))
        end
        if m.catchesPerHour then
            add(("Fishing: about %.0f catches an hour; zone needs %d (no getaways %s)"):format(m.catchesPerHour,
                m.zoneMin or 0, m.noGetaway and tostring(m.noGetaway) or "?"))
        end
        add(r.travel and ("Travel: %s (%s)"):format(U.Duration(r.travel), r.travelQuality or "estimate") or "Travel: unknown")
        add("")
        add("|cffe8a040What you will find|r")
        local skill = HME.Player.Profile().skills[r.prof]
        for i, t in ipairs(r.targets or {}) do
            if i > 7 then add("  ...") break end
            local hex = t.color and K.DIFF_HEX[t.color] or "ffffff"
            if r.prof == "Skinning" then
                add(("  |cff%s%s|r  level %d-%d, needs %d%s  ·  %d spawns"):format(hex, t.name, t.min, t.max, t.req,
                    t.skinnable == nil and " (not yet checked)" or "", t.count or 0))
            elseif r.prof == "Fishing" then
                add(("  %s"):format(t.name or "?"))
            else
                add(("  |cff%s%s|r  needs %d  ·  %.0f%% of the nodes"):format(hex, t.name, t.req or 0, (t.share or 0) * 100))
            end
        end
        add("")
        add(("|cffe8a040Risk|r  %s: %s"):format(r.risk.label, table.concat(r.risk.reasons, "; ")))
        add(("|cffe8a040Confidence|r  %s: %s"):format(r.confidence.label, table.concat(r.confidence.reasons, "; ")))
        add("|cffe8a040Source|r  " .. (r.source or "?"))
        if r.prof == "Skinning" then
            add("|cff9a9a9aBeast spawns are where beasts appear, not live targets. Respawn time is assumed until measured.|r")
        elseif r.prof ~= "Fishing" then
            add("|cff9a9a9aSpawn points are where nodes can appear; about one in three is up at a time (assumed until you farm here).|r")
        end
        if m.gph then add("|cff9a9a9aAuction prices are what sellers ask, not guaranteed sales.|r") end
        d.text:SetText(table.concat(lines, "\n"))
        for _, b in ipairs({ d.preview, d.start, d.nav }) do b:Show() end
    end

    function page.Layout()
        local g = State().goal
        mat:SetShown(g == "material")
        planSwitch:SetPoint("TOPLEFT", g == "material" and 212 or 0, -36)
    end

    local searching = false
    function page.Search()
        local s = State()
        local targets, n
        if s.goal == "material" then
            targets, n = Targets(s.prof, s.material)
            if not targets then
                status:SetText(s.material and s.material ~= "" and "No material matches that name." or "Type a material.")
                list:SetItems({})
                return
            end
        end
        status:SetText("Searching...")
        searching = true
        local profile = HME.Player.Profile()
        if not profile.skills[s.prof] then
            status:SetText("You don't know " .. s.prof .. ": showing a plan for skill 1.")
            profile.skills[s.prof] = { rank = 1, max = 75 }
        end
        HME.Recommend.Find({ prof = s.prof, goal = s.goal, risk = s.risk, targets = targets }, function(found, skipped)
            searching = false
            results = found or {}
            list:SetItems(results)
            if #results == 0 then
                list:SetEmptyText("No farm fits this character and goal. " .. (#(skipped or {}) > 0
                    and (#skipped .. " zones were left out (too high, excluded or not released).") or ""))
                status:SetText("Nothing found.")
            else
                status:SetText(("%d farms ranked%s"):format(#results, #(skipped or {}) > 0 and (", " .. #skipped .. " zones left out") or ""))
                list:Select(1)
                selected = results[1]
                page.ShowDetail(results[1])
            end
        end, profile)
    end

    function page.Refresh()
        profs:Refresh()
        goal:Refresh()
        risk:Refresh()
        local p = HME.char.plan
        planSwitch:SetOn(p.enabled)
        lvl:SetText(p.level and tostring(p.level) or tostring(HME.Player.Level()))
        local cur = p.skills and p.skills[State().prof]
        skl:SetText(cur and tostring(cur) or tostring(HME.Player.Skill(State().prof) or 1))
        page.Layout()
        if #results == 0 and not searching then page.Search() end
    end

    -- Other pages open the finder on a profession / goal.
    HME.Pages.finderSet = function(prof, goalKey, material)
        local s = State()
        if prof then s.prof = prof end
        if goalKey then s.goal = goalKey end
        if material then
            s.material = material
            mat:SetText(material)
        end
        page.Refresh()
        page.Search()
    end
end
