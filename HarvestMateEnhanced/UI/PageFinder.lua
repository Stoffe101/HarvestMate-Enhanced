-- HarvestMate Enhanced: UI/PageFinder.lua
-- The Farm Finder. Top: what to farm (profession, goal, risk), how long you
-- can play, filters. Left: ranked farms with their headline figure, risk and
-- how sure. Right: the chosen farm in plain words first (why, what you'll
-- find, what you can expect as a range and what it rests on), then Start.
-- Right-click (or the box) marks farms to compare side by side.
-- The search runs in the background; the game never stutters.
-- Copyright (C) 2026 HarvestMate Enhanced contributors. GPL-3.0-or-later.

local _, ns = ...
local HME = ns.HME
local T = ns.Theme
local K = HME.Kit
local U = HME.U
local C = T.C

local PAGE_W = 738
local LIST_W = 330

local PROF_KEYS = { "Herbalism", "Mining", "Combined", "Skinning", "Fishing" }
local PROF_LABELS = { Herbalism = "Herbs", Mining = "Ore", Combined = "Herbs + Ore", Skinning = "Skinning", Fishing = "Fishing" }

local function State()
    local ui = HME.char and HME.char.ui or {}
    ui.finder = ui.finder or {}
    local f = ui.finder
    if not f.prof then
        for _, p in ipairs(K.PROFS) do
            if HME.Player.Professions()[p] then f.prof = p break end
        end
        f.prof = f.prof or "Herbalism"
    end
    f.goal = f.goal or "level"
    f.risk = f.risk or (HME.settings and HME.settings.riskMode) or "balanced"
    f.filters = f.filters or {}
    return f
end

-- Text -> targets for the material goal: node names and item ids that
-- match any of the comma-separated words (several materials at once).
local function Targets(prof, text)
    text = U.Trim(text or ""):lower()
    if text == "" then return nil, 0 end
    local targets, n = {}, 0
    local profs = prof == "Combined" and { "Herbalism", "Mining" } or { prof }
    for word in text:gmatch("[^,]+") do
        word = U.Trim(word)
        if word ~= "" then
            for _, p in ipairs(profs) do
                for _, list in pairs((ns.NodeSpawns and ns.NodeSpawns[p]) or {}) do
                    for _, e in ipairs(list) do
                        if e[1]:lower():find(word, 1, true) and not targets[e[1]] then
                            n = n + 1
                            targets[e[1]] = true
                            targets[e[2]] = true
                        end
                    end
                end
                local def = ns.professions[p]
                for _, e in ipairs(def and def.items or {}) do
                    if e.id and e.name and e.name:lower():find(word, 1, true) and not targets[e.id] then
                        n = n + 1
                        targets[e.id] = true
                        targets[e.name] = true
                    end
                end
            end
        end
    end
    return n > 0 and targets or nil, n
end

HME.Pages.finder = function(body, page)
    local results, selected = {}, nil
    local marked = {}
    local comparing = false

    -- Row 1: what
    local profs = K.Segments(body, PROF_KEYS, PROF_LABELS, function() return State().prof end, function(k)
        State().prof = k
        page.Search()
    end, 84)
    profs:SetPoint("TOPLEFT", 0, 0)
    local goalKeys, goalLabels = {}, {}
    for _, g in ipairs(HME.Recommend.GOALS) do
        goalKeys[#goalKeys + 1] = g.key
        goalLabels[g.key] = g.label
    end
    local goal = T.Dropdown(body, 170, goalKeys, goalLabels, function() return State().goal end, function(k)
        State().goal = k
        page.Layout()
        page.Search()
    end)
    goal:SetPoint("TOPLEFT", 428, 0)
    local riskLabels = { fastest = "Fastest", balanced = "Balanced risk", safer = "Lower risk" }
    local risk = T.Dropdown(body, 132, { "fastest", "balanced", "safer" }, riskLabels, function() return State().risk end,
        function(k) State().risk = k; page.Search() end)
    risk:SetPoint("TOPLEFT", 606, 0)
    T.Tooltip(risk, "PvP and creature risk", "How much risk counts against a farm: territory, enemy guards, creatures "
        .. "above your level, elites, and where you died. HME cannot see other players; no place is ever called safe.")

    -- Row 2: material, time, filters, plan-for
    local mat = T.EditBox(body, 178)
    mat:SetPoint("TOPLEFT", 0, -30)
    mat.hint = K.Label(mat, "e.g. Goldthorn, Iron Ore", { template = "GameFontDisableSmall" })
    mat.hint:SetPoint("LEFT", 6, 0)
    mat:SetScript("OnTextChanged", function(self)
        self.hint:SetShown(self:GetText() == "")
        State().material = self:GetText()
    end)
    mat:SetScript("OnEnterPressed", function(self) self:ClearFocus(); page.Search() end)
    T.Tooltip(mat, "Materials", "One or more, separated by commas. Farms that give several of them rank higher.")

    local minutes = K.Segments(body, { 15, 30, 60, 120 }, { [15] = "15m", [30] = "30m", [60] = "1h", [120] = "2h" },
        function() return HME.settings.sessionMinutes end, function(k)
            HME.settings.sessionMinutes = k
            page.Search()
        end, 40)
    minutes:SetPoint("TOPLEFT", 186, -30)
    T.Tooltip(minutes, "How long you can play", "The trip there takes part of it: a farm far away has to be much better to win a short session.")

    local contLabels = { any = "Anywhere", E = "Eastern Kingdoms", K = "Kalimdor", F = "Forever zones" }
    local cont = T.Dropdown(body, 128, { "any", "E", "K", "F" }, contLabels,
        function() return State().filters.continent or "any" end, function(k)
            State().filters.continent = k ~= "any" and k or nil
            page.Search()
        end)
    cont:SetPoint("TOPLEFT", 352, -30)
    local confLabels = { any = "Any confidence", Medium = "Medium or better", High = "High only" }
    local conf = T.Dropdown(body, 128, { "any", "Medium", "High" }, confLabels,
        function() return State().filters.minConfidence or "any" end, function(k)
            State().filters.minConfidence = k ~= "any" and k or nil
            page.Search()
        end)
    conf:SetPoint("TOPLEFT", 486, -30)
    local saveProfile = K.Button(body, "Save", 56, 22, function()
        local s = State()
        local name = ("%s %s"):format(PROF_LABELS[s.prof] or s.prof, HME.Recommend.GOAL_LABEL[s.goal] or s.goal)
        if s.goal == "material" and s.material and s.material ~= "" then name = s.material .. " (" .. (PROF_LABELS[s.prof] or s.prof) .. ")" end
        local p, why = HME.Profiles.Save(name, { prof = s.prof, goal = s.goal, risk = s.risk, material = s.material,
            minutes = HME.settings.sessionMinutes, filters = s.filters })
        HME.Print(p and ("saved profile |cffffd100%s|r (Dashboard, Goals & Plans)."):format(p.name) or ("not saved: " .. tostring(why)))
    end, "Save this search as a farming profile, to start it again from the Dashboard.")
    saveProfile:SetPoint("TOPLEFT", 620, -30)
    local planBtn = K.Button(body, "Plan", 56, 22, function() HME.OpenWindow("goals") end,
        "Plan for another level or skill, or a longer climb (Goals & Plans).")
    planBtn:SetPoint("TOPLEFT", 682, -30)

    local status = K.Label(body, "", { template = "GameFontDisableSmall", width = PAGE_W })
    status:SetPoint("TOPLEFT", 0, -56)

    -- Results
    local list = K.List(body, {
        width = LIST_W, height = 438, rowHeight = 50,
        empty = "Pick a profession and a goal.",
        makeRow = function(row)
            row.rank = K.Label(row, "", { template = "GameFontNormalLarge", color = C.grey })
            row.rank:SetPoint("LEFT", 6, 0)
            row.mark = row:CreateTexture(nil, "OVERLAY")
            row.mark:SetSize(12, 12)
            row.mark:SetPoint("TOPLEFT", 6, -4)
            row.mark:SetTexture("Interface\\Buttons\\UI-CheckBox-Check")
            row.title = K.Label(row, "", { template = "GameFontNormal", color = C.title, width = 196, wrap = false })
            row.title:SetPoint("TOPLEFT", 32, -6)
            row.sub = K.Label(row, "", { template = "GameFontHighlightSmall", width = 206, wrap = false })
            row.sub:SetPoint("TOPLEFT", 32, -23)
            row.sub2 = K.Label(row, "", { template = "GameFontDisableSmall", width = 206, wrap = false })
            row.sub2:SetPoint("TOPLEFT", 32, -36)
            row.risk = K.Badge(row, 80, 14)
            row.risk:SetPoint("TOPRIGHT", -4, -6)
            row.conf = K.Badge(row, 80, 14)
            row.conf:SetPoint("TOPRIGHT", -4, -24)
        end,
        fillRow = function(row, r)
            row.rank:SetText(r.rank)
            row.mark:SetShown(marked[r.key] ~= nil)
            row.title:SetText(r.zone .. "  |cff9a9a9a" .. r.subarea .. "|r")
            row.sub:SetText(page.Headline(r))
            row.sub2:SetText(page.SubLine(r))
            row.risk:Set(r.risk and r.risk.label or "?", r.risk and r.risk.hex)
            row.conf:Set((r.evidence and r.evidence.level == "measured") and "measured" or ((r.confidence.label or "?") .. " conf."),
                K.ConfHex(r.confidence.label))
        end,
        onClick = function(r, _, button)
            if button == "RightButton" then
                page.ToggleMark(r)
                return
            end
            selected = r
            comparing = false
            page.ShowDetail(r)
        end,
        onEnter = function(row, r)
            GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
            GameTooltip:AddLine(r.zone .. " (" .. r.subarea .. ")")
            GameTooltip:AddLine(r.summary or "", 1, 1, 1, true)
            GameTooltip:AddLine("Right-click: mark to compare", 0.7, 0.7, 0.7)
            GameTooltip:Show()
        end,
    })
    list:SetPoint("TOPLEFT", 0, -74)

    -- Detail / comparison
    local d = T.Card(body, "Details", LIST_W + 10, -74, PAGE_W - LIST_W - 10, 438)
    local DW = PAGE_W - LIST_W - 36
    d.title = K.Label(d, "", { template = "GameFontNormalLarge", color = C.gold, width = DW })
    d.title:SetPoint("TOPLEFT", 12, -26)
    d.summary = K.Label(d, "", { template = "GameFontHighlight", width = DW })
    d.summary:SetPoint("TOPLEFT", 12, -48)
    local scroll = T.ScrollArea(d, 250)
    scroll:ClearAllPoints()
    scroll:SetPoint("TOPLEFT", 12, -100)
    scroll:SetPoint("BOTTOMRIGHT", -12, 72)
    d.text = K.Label(scroll.child, "", { template = "GameFontHighlightSmall", width = DW - 14 })
    d.text:SetPoint("TOPLEFT", 0, 0)
    d.preview = K.Button(d, "Preview on map", 116, 22, function() if selected then HME.MapOverlay.Preview(selected) end end,
        "Opens the world map on this farm with its spawn points, hunting areas and loop.")
    d.preview:SetPoint("BOTTOMLEFT", 12, 40)
    d.start = K.Button(d, "Start farming", 116, 22, function()
        if selected then HME.Guidance.StartResult(selected, State().goal) end
    end, "Plans the loop on the map and minimap and guides you. If it is far away, the trip goes through Forever-GPS "
        .. "(when installed) and HME takes over when you arrive.")
    d.start:SetPoint("LEFT", d.preview, "RIGHT", 6, 0)
    d.compare = K.Button(d, "Compare (0)", 116, 22, function() page.ShowCompare() end,
        "Side by side: the farms you marked (right-click in the list).")
    d.compare:SetPoint("LEFT", d.start, "RIGHT", 6, 0)
    local modeLabels = { guided = "Guided circuit", free = "Free farming", minimal = "Minimal arrow" }
    d.mode = T.Dropdown(d, 150, { "guided", "free", "minimal" }, modeLabels,
        function() return HME.settings.huntMode or "guided" end, function(k) HME.Guidance.SetMode(k) end)
    d.mode:SetPoint("BOTTOMLEFT", 12, 12)
    T.Tooltip(d.mode, "How to be guided", "Guided: the arrow leads stop by stop. Free: the area stays highlighted and "
        .. "the arrow stays out of the way. Minimal: the arrow fades while you are on the loop and comes back when you stray.")
    d.markBtn = K.Button(d, "Mark to compare", 130, 22, function() if selected then page.ToggleMark(selected) end end)
    d.markBtn:SetPoint("LEFT", d.mode, "RIGHT", 8, 0)
    for _, b in ipairs({ d.preview, d.start, d.mode, d.markBtn }) do b:Hide() end

    function page.ToggleMark(r)
        if marked[r.key] then marked[r.key] = nil else marked[r.key] = r end
        local n = U.Count(marked)
        d.compare:SetText(("Compare (%d)"):format(n))
        list.Render()
    end

    local function Money(v) return K.Money(v or 0) end

    function page.Headline(r)
        local m, g = r.metrics, State().goal
        local travel = r.travel and U.Duration(r.travel) or "travel ?"
        if g == "profit" then
            return ("%s/h  ·  %s"):format(Money(m.range and m.range.mid), travel)
        elseif g == "material" then
            return ("%.0f units/h  ·  %s"):format(m.materialPerHour or 0, travel)
        end
        return ("%.0f skill/h  ·  %s/h  ·  %s"):format(m.skillRange and m.skillRange.mid or m.skillPerHour or 0,
            Money(m.range and m.range.mid), travel)
    end

    function page.SubLine(r)
        local names = {}
        for i, t in ipairs(r.targets or {}) do
            if i > 3 then break end
            names[#names + 1] = t.name
        end
        return table.concat(names, ", ")
    end

    function page.ShowDetail(r)
        local m = r.metrics
        d:Show()
        d.title:SetText(("%s  |cff9a9a9a%s, around %d, %d|r"):format(r.zone, r.subarea, r.cx * 100, r.cy * 100))
        d.summary:SetText(r.summary or "")
        local lines = {}
        local function add(s) lines[#lines + 1] = s end
        local ev = r.evidence or {}
        add(("|cffe8a040Expect|r  (%s)"):format(ev.level or "estimate"))
        if m.skillRange and (m.skillPerHour or 0) > 0 then
            add(("  Skill-ups: about %.0f an hour (%.0f to %.0f); %.0f%% of gathers give a point now"):format(
                m.skillRange.mid, m.skillRange.low, m.skillRange.high, (m.skillChance or 0) * 100))
        end
        if m.range then
            add(("  Gold while farming: about %s an hour (%s to %s)"):format(Money(m.range.mid), Money(m.range.low), Money(m.range.high)))
            if r.travel then
                add(("  Gold over a %d-minute trip incl. %s travel: about %s an hour"):format(HME.settings.sessionMinutes or 60,
                    U.Duration(r.travel), Money(r.tripGph)))
            end
        end
        if m.materialPerHour then add(("  Materials: about %.0f an hour"):format(m.materialPerHour)) end
        if m.beastsPerHour then
            add(("  Beasts: about %.0f an hour (%s); a kill about %.0f s (%s), walking %.0f s"):format(m.beastsPerHour,
                m.limit == "respawn" and "respawns limit it" or "your pace limits it", m.killSecs, m.killBasis, m.walkSecs))
        end
        if m.nodesPerHour then
            add(("  Nodes: about %.0f an hour; loop about %s, %s a lap"):format(m.nodesPerHour, U.Yards(m.loopYards), U.Duration(m.lapSecs)))
        end
        if m.catchesPerHour then
            add(("  Fishing: about %.0f catches an hour; the zone needs %d (no getaways at %s)"):format(m.catchesPerHour,
                m.zoneMin or 0, m.noGetaway and tostring(m.noGetaway) or "?"))
        end
        add(r.travel and ("  Travel: %s (%s)"):format(U.Duration(r.travel), r.travelQuality or "estimate") or "  Travel: unknown")
        if r.levels then add(("  Creatures here: about level %d-%d"):format(r.levels[1], r.levels[2])) end
        add("")
        add("|cffe8a040What you will find|r")
        for i, t in ipairs(r.targets or {}) do
            if i > 8 then add("  ...") break end
            local hex = t.color and K.DIFF_HEX[t.color] or "ffffff"
            if r.prof == "Skinning" then
                local part = (t.skinShare and t.skinShare < 1) and (" (you can skin %d%% of its levels)"):format(t.skinShare * 100) or ""
                add(("  |cff%s%s|r  level %d-%d, %d+ Skinning%s%s · %d spawns"):format(hex, t.name, t.min, t.max, t.reqMin or t.req,
                    part, t.skinnable == nil and " · not yet checked in game" or "", t.count or 0))
            elseif r.prof == "Fishing" then
                add("  " .. (t.name or "?"))
            else
                add(("  |cff%s%s|r  needs %d · %.0f%% of the nodes"):format(hex, t.name, t.req or 0, (t.share or 0) * 100))
            end
        end
        if r.prof == "Skinning" and m.beasts then
            local shown = 0
            for _, b in pairs(m.beasts) do
                local y = HME.Skinning.Yield(b.beast)
                for id in pairs(y.items) do
                    if shown < 4 and (y.seen[id] or y.prior[id] and y.prior[id] >= 0.1) then
                        add("  " .. HME.Skinning.YieldText(y, id))
                        shown = shown + 1
                    end
                end
            end
        end
        add("")
        add(("|cffe8a040Risk|r  %s: %s"):format(r.risk.label, table.concat(r.risk.reasons, "; ")))
        add(("|cffe8a040How sure|r  %s. %s"):format(r.confidence.label, ev.text or ""))
        add("  " .. table.concat(r.confidence.reasons, "; ") .. ".")
        add("|cffe8a040Source|r  " .. (r.source or "?"))
        if r.prof == "Skinning" then
            add("|cff9a9a9aBeast spawns are where beasts appear, not live targets.|r")
        elseif r.prof ~= "Fishing" then
            add("|cff9a9a9aSpawn points are where nodes can appear, not where nodes are now.|r")
        end
        if m.gph then add("|cff9a9a9aAuction prices are what sellers ask, not guaranteed sales.|r") end
        if r.prof == "Combined" then
            add("|cff9a9a9aFind Herbs and Find Minerals can't run together: switch tracking yourself as you go; the map shows both.|r")
        end
        d.text:SetText(table.concat(lines, "\n"))
        scroll:SetContent(DW, (d.text:GetStringHeight() or 300) + 10)
        for _, b in ipairs({ d.preview, d.start, d.markBtn }) do b:Show() end
        d.mode:SetShown(r.prof == "Skinning")
        d.markBtn:SetText(marked[r.key] and "Unmark" or "Mark to compare")
    end

    function page.ShowCompare()
        local rows = {}
        for _, r in pairs(marked) do rows[#rows + 1] = r end
        table.sort(rows, function(a, b) return (a.rank or 99) < (b.rank or 99) end)
        if #rows < 2 then
            HME.Print("mark two or more farms first: right-click them in the list.")
            return
        end
        comparing = true
        local cmp = HME.Recommend.Compare(rows)
        d.title:SetText("Comparing " .. #rows .. " farms")
        d.summary:SetText("Green: best on that line. A lead resting on unmeasured estimates is shown as an estimate only.")
        local lines = {}
        local function cell(col, i, r)
            local v = col.get(r)
            local s
            if v == nil then s = "?"
            elseif col.money then s = K.Money(v)
            elseif col.duration then s = U.Duration(v)
            elseif col.key == "risk" then s = r.risk.label
            elseif col.key == "loop" then s = U.Yards(v)
            else s = ("%.0f"):format(v) end
            local b = cmp.best[col.key]
            if b and b.index == i then s = (b.sure and "|cff48c75a" or "|cffffe14d") .. s .. "|r" end
            return s
        end
        for i, r in ipairs(rows) do
            lines[#lines + 1] = ("|cffffd100%d. %s (%s)|r  %s, %s"):format(i, r.zone, r.subarea, r.confidence.label .. " confidence",
                r.evidence and r.evidence.level or "")
            for _, col in ipairs(HME.Recommend.COMPARE_COLUMNS) do
                lines[#lines + 1] = ("    %s: %s"):format(col.label, cell(col, i, r))
            end
            local st = HME.db.stats[r.key]
            if st and (st.hours or 0) > 0 then
                lines[#lines + 1] = ("    Your history: %.1f h, %s/h"):format(st.hours, K.Money((st.value or 0) / st.hours))
            end
        end
        for _, n in ipairs(cmp.notes) do lines[#lines + 1] = "|cff9a9a9a" .. n .. "|r" end
        d.text:SetText(table.concat(lines, "\n"))
        scroll:SetContent(DW, (d.text:GetStringHeight() or 300) + 10)
    end

    function page.Layout()
        local g = State().goal
        mat:SetShown(g == "material")
    end

    local searching = false
    function page.Search()
        local s = State()
        local targets
        if s.goal == "material" then
            targets = Targets(s.prof, s.material)
            if not targets then
                status:SetText(s.material and s.material ~= "" and "No material matches that name for this profession." or "Type one or more materials.")
                list:SetItems({})
                list:SetEmptyText("Type a material (e.g. Heavy Leather, Iron Ore). Separate several with commas.")
                return
            end
        end
        local profile = HME.Player.Profile()
        local note = ""
        for _, p in ipairs(HME.Gathering.Profs(s.prof)) do
            if not profile.skills[p] then
                profile.skills[p] = { rank = 1, max = 75 }
                note = ("  (you don't know %s: planning for skill 1)"):format(p)
            end
        end
        status:SetText("Searching..." .. note)
        searching = true
        list:SetEmptyText("Searching every zone in the background...")
        list:SetItems({})
        HME.Recommend.Find({ prof = s.prof, goal = s.goal, risk = s.risk, targets = targets, filters = s.filters },
            function(found, skipped)
                searching = false
                results = found or {}
                list:SetItems(results)
                if #results == 0 then
                    list:SetEmptyText("No farm fits this character, goal and filters. " .. (#(skipped or {}) > 0
                        and (#skipped .. " zones were left out (too high, filtered, excluded or not released).") or ""))
                    status:SetText("Nothing found." .. note)
                    d.title:SetText("")
                    d.summary:SetText("")
                    d.text:SetText("")
                else
                    status:SetText(("%d farms ranked for %d minutes of play%s%s"):format(#results, HME.settings.sessionMinutes or 60,
                        #(skipped or {}) > 0 and (", " .. #skipped .. " zones left out") or "", note))
                    list:Select(1)
                    selected = results[1]
                    page.ShowDetail(results[1])
                    if s.goal == "profit" or s.goal == "balanced" then HME.Suggest.CheckPrices(results) end
                end
            end, profile)
    end

    function page.Refresh()
        profs:Refresh()
        goal:Refresh()
        risk:Refresh()
        minutes:Refresh()
        cont:Refresh()
        conf:Refresh()
        d.mode:Refresh()
        page.Layout()
        if #results == 0 and not searching then page.Search() end
    end

    -- Other pages open the finder on a profession / goal / material.
    HME.Pages.finderSet = function(prof, goalKey, material, riskKey, filters)
        local s = State()
        if prof then s.prof = prof end
        if goalKey then s.goal = goalKey end
        if riskKey then s.risk = riskKey end
        if filters then s.filters = U.Copy(filters) end
        if material then
            s.material = material
            mat:SetText(material)
        end
        page.Refresh()
        page.Search()
    end
    HME.Pages.finderResults = function() return results end
    HME.Pages.finderMark = function(r) page.ToggleMark(r) end
    HME.Pages.finderCompare = function() page.ShowCompare() return comparing end
end
