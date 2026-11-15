-- HarvestMate Enhanced: UI/PageFinder.lua
-- The Farm Finder (0.4.0 layout). Top: profession and goal; risk, play time,
-- region, confidence and saving sit behind Filters. Left: ranked farms, each
-- led by the one number the goal is about (skill-ups, gold or materials an
-- hour), with how sure (four diamonds), risk and travel underneath. Right:
-- the chosen farm: why, three figures with their ranges, how sure in plain
-- words, then tabs (Overview, Find, Risk, Evidence) and one primary action.
-- Right-click (or the box) marks farms to compare side by side.
-- Skinning: "Best beasts" lists, for the materials typed, which beasts give
-- them best, with levels, Skinning needed, yield, how sure, and where.
-- The search runs in the background; the game never stutters.
-- Copyright (C) 2026 HarvestMate Enhanced contributors. GPL-3.0-or-later.

local _, ns = ...
local HME = ns.HME
local T = ns.Theme
local K = HME.Kit
local U = HME.U
local C = T.C

local PAGE_W = 738
local LIST_W = 336
local LIST_H = 448

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
    local targets, n, ids = {}, 0, {}
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
                        ids[#ids + 1] = e.id
                    end
                end
            end
        end
    end
    return n > 0 and targets or nil, n, ids
end

HME.Pages.finder = function(body, page)
    local results, selected = {}, nil
    local marked = {}
    local comparing = false
    local beastView = false
    local beastIDs = {}     -- the materials typed for the last Skinning search

    -- Row 1: what
    local profs = K.Segments(body, PROF_KEYS, PROF_LABELS, function() return State().prof end, function(k)
        State().prof = k
        page.Search()
    end, 86)
    profs:SetPoint("TOPLEFT", 0, 0)
    local goalKeys, goalLabels = {}, {}
    for _, g in ipairs(HME.Recommend.GOALS) do
        goalKeys[#goalKeys + 1] = g.key
        goalLabels[g.key] = g.label
    end
    local goal = T.Dropdown(body, 190, goalKeys, goalLabels, function() return State().goal end, function(k)
        State().goal = k
        page.Layout()
        page.Search()
    end)
    goal:SetPoint("TOPLEFT", 440, -1)
    goal:SetHeight(26)
    -- Filters: the less used choices, in a panel over the results.
    local filters = CreateFrame("Frame", nil, body)
    filters:SetSize(PAGE_W, 76)
    filters:SetPoint("TOPLEFT", 0, -34)
    filters:SetFrameLevel((body:GetFrameLevel() or 1) + 20)
    filters.bg = T.Surface(filters, C.raised)
    T.Outline(filters, C.edge)
    filters:EnableMouse(true)
    filters:Hide()
    local filterBtn = K.Button(body, "Filters", 88, 26, function() filters:SetShown(not filters:IsShown()) page.Layout() end,
        "Risk, how long you can play, region and confidence. Save keeps this search as a profile.")
    filterBtn:SetPoint("TOPRIGHT", 0, -1)
    local function FLabel(text, x)
        local l = K.Label(filters, text, { template = "label" })
        l:SetPoint("TOPLEFT", x, -10)
        return l
    end
    FLabel("Risk", 14)
    FLabel("Play time", 160)
    FLabel("Region", 344)
    FLabel("Confidence", 488)
    local riskLabels = { fastest = "Fastest", balanced = "Balanced risk", safer = "Lower risk" }
    local risk = T.Dropdown(filters, 134, { "fastest", "balanced", "safer" }, riskLabels, function() return State().risk end,
        function(k) State().risk = k; page.Search() end)
    risk:SetPoint("TOPLEFT", 14, -30)
    T.Tooltip(risk, "PvP and creature risk", "How much risk counts against a farm: territory, enemy guards, creatures "
        .. "above your level, elites, and where you died. HME cannot see other players; no place is ever called safe.")

    -- Row 2: the material (for that goal), what was found, compare.
    local mat = T.EditBox(body, 230)
    mat:SetPoint("TOPLEFT", 0, -36)
    mat.hint = K.Label(mat, "e.g. Goldthorn, Iron Ore", { template = "GameFontDisableSmall" })
    mat.hint:SetPoint("LEFT", 6, 0)
    mat:SetScript("OnTextChanged", function(self)
        self.hint:SetShown(self:GetText() == "")
        State().material = self:GetText()
    end)
    mat:SetScript("OnEnterPressed", function(self) self:ClearFocus(); page.Search() end)
    T.Tooltip(mat, "Materials", "One or more, separated by commas. Farms that give several of them rank higher.")

    local minutes = K.Segments(filters, { 15, 30, 60, 120 }, { [15] = "15m", [30] = "30m", [60] = "1h", [120] = "2h" },
        function() return HME.settings.sessionMinutes end, function(k)
            HME.settings.sessionMinutes = k
            page.Search()
        end, 44)
    minutes:SetPoint("TOPLEFT", 160, -30)
    T.Tooltip(minutes, "How long you can play", "The trip there takes part of it: a farm far away has to be much better to win a short session.")

    local contLabels = { any = "Anywhere", E = "Eastern Kingdoms", K = "Kalimdor", F = "Forever zones" }
    local cont = T.Dropdown(filters, 134, { "any", "E", "K", "F" }, contLabels,
        function() return State().filters.continent or "any" end, function(k)
            State().filters.continent = k ~= "any" and k or nil
            page.Search()
        end)
    cont:SetPoint("TOPLEFT", 344, -30)
    local confLabels = { any = "Any confidence", Medium = "Medium or better", High = "High only" }
    local conf = T.Dropdown(filters, 134, { "any", "Medium", "High" }, confLabels,
        function() return State().filters.minConfidence or "any" end, function(k)
            State().filters.minConfidence = k ~= "any" and k or nil
            page.Search()
        end)
    conf:SetPoint("TOPLEFT", 488, -30)
    local saveProfile = K.Button(filters, "Save search", 96, 24, function()
        local s = State()
        local name = ("%s %s"):format(PROF_LABELS[s.prof] or s.prof, HME.Recommend.GOAL_LABEL[s.goal] or s.goal)
        if s.goal == "material" and s.material and s.material ~= "" then name = s.material .. " (" .. (PROF_LABELS[s.prof] or s.prof) .. ")" end
        local p, why = HME.Profiles.Save(name, { prof = s.prof, goal = s.goal, risk = s.risk, material = s.material,
            minutes = HME.settings.sessionMinutes, filters = s.filters })
        HME.Print(p and ("saved profile |cffffd100%s|r (Dashboard, Goals & Plans)."):format(p.name) or ("not saved: " .. tostring(why)))
    end, "Save this search as a farming profile, to start it again from the Dashboard.", "ghost")
    saveProfile:SetPoint("TOPRIGHT", -14, -14)
    local planBtn = K.Button(filters, "Plan ahead", 96, 24, function() HME.OpenWindow("goals") end,
        "Plan for another level or skill, or a longer climb (Goals & Plans).", "ghost")
    planBtn:SetPoint("TOPRIGHT", -14, -42)

    local status = K.Label(body, "", { template = "meta", width = PAGE_W - 150, wrap = false })
    status:SetPoint("TOPLEFT", 2, -42)

    -- Results
    local NUM_W = 92   -- the right column: the goal's number and its unit
    local list = K.List(body, {
        width = LIST_W, height = LIST_H, rowHeight = 66,
        empty = "Pick a profession and a goal.",
        makeRow = function(row)
            row.rank = K.Label(row, "", { template = "meta", size = 12 })
            row.rank:SetPoint("TOPLEFT", 10, -10)
            row.mark = row:CreateTexture(nil, "OVERLAY")
            row.mark:SetSize(8, 8)
            row.mark:SetPoint("TOPLEFT", 11, -32)
            row.mark:SetTexture(T.ART .. "Pip")
            row.mark:SetVertexColor(C.accent[1], C.accent[2], C.accent[3], 1)
            local tw = LIST_W - 30 - NUM_W - 22
            row.title = K.Label(row, "", { template = "strong", size = 14, width = tw, wrap = false })
            row.title:SetPoint("TOPLEFT", 30, -8)
            row.sub = K.Label(row, "", { template = "small", color = C.text2, width = tw, wrap = false })
            row.sub:SetPoint("TOPLEFT", 30, -27)
            row.pips = K.Pips(row)
            row.pips:SetPoint("TOPLEFT", 30, -48)
            -- The third line runs under the number column too.
            row.sub2 = K.Label(row, "", { template = "meta", width = LIST_W - 30 - 46 - 22, wrap = false })
            row.sub2:SetPoint("LEFT", row.pips, "RIGHT", 6, 0)
            row.num = K.Label(row, "", { template = "display", size = 19, width = NUM_W, wrap = false, justify = "RIGHT" })
            row.num:SetPoint("TOPRIGHT", -12, -9)
            row.unit = K.Label(row, "", { template = "meta", width = NUM_W, wrap = false, justify = "RIGHT" })
            row.unit:SetPoint("TOPRIGHT", -12, -33)
        end,
        fillRow = function(row, r)
            row.rank:SetText(r.rank)
            row.mark:SetShown(marked[r.key] ~= nil)
            -- Zone and part of it; when both don't fit, the part goes under.
            local tw = LIST_W - 30 - NUM_W - 22
            row.title:SetText(r.zone .. "  " .. K.Paint(r.subarea, T.HEX.text3))
            local partBelow = T.StringWidth(row.title) > tw
            if partBelow then row.title:SetText(r.zone) end
            row.sub:SetText(page.SubLine(r, row.sub, tw))
            local num, unit, color = page.Primary(r)
            row.num:SetText(num)
            T.FitText(row.num, NUM_W, "display", 19, 13)
            row.num:SetTextColor(color[1], color[2], color[3])
            row.unit:SetText(unit)
            row.pips:Set(page.ConfLevel(r), K.ConfHex(r.confidence and r.confidence.label))
            row.sub2:SetText((partBelow and (K.Paint(r.subarea or "", T.HEX.text3) .. "  ·  ") or "") .. page.RowFacts(r))
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
    list:SetPoint("TOPLEFT", 0, -64)

    -- Detail / comparison
    local DCARD_H = LIST_H
    local d = T.Card(body, "", LIST_W + 10, -64, PAGE_W - LIST_W - 10, DCARD_H)
    d.title:Hide()
    d.tick:Hide()
    local DW = PAGE_W - LIST_W - 38
    d.head = K.Label(d, "", { template = "title", size = 18, width = DW - 150, wrap = false })
    d.head:SetPoint("TOPLEFT", 14, -14)
    d.title = d.head
    d.where = K.Label(d, "", { template = "meta", width = DW - 150, wrap = false })
    d.where:SetPoint("TOPLEFT", 14, -37)
    d.summary = K.Label(d, "", { template = "small", color = C.text2, width = DW })
    d.summary:SetPoint("TOPLEFT", 14, -58)
    -- Three numbers that matter most, as tiles.
    d.kpis = CreateFrame("Frame", nil, d)
    d.kpis:SetSize(DW, 96)
    local tileW = (DW - 12) / 3
    d.kpi = {}
    for i = 1, 3 do
        local t = K.Stat(d.kpis, "", tileW, 70)
        t:SetPoint("TOPLEFT", (i - 1) * (tileW + 6), 0)
        t.bg:Paint(C.field)
        d.kpi[i] = t
    end
    -- How sure, in words, under the tiles.
    d.sure = K.Pips(d.kpis)
    d.sure:SetPoint("TOPLEFT", 2, -82)
    d.sureText = K.Label(d.kpis, "", { template = "meta", width = DW - 50, wrap = false })
    d.sureText:SetPoint("LEFT", d.sure, "RIGHT", 6, 0)
    -- Tabs over the details.
    local TABS = { "overview", "find", "risk", "evidence" }
    local TAB_LABELS = { overview = "Overview", find = "Find", risk = "Risk", evidence = "Evidence" }
    local tab = "overview"
    d.tabs = K.Segments(d, TABS, TAB_LABELS, function() return tab end, function(k)
        tab = k
        if selected and not comparing and not beastView then page.ShowDetail(selected) end
    end, (DW - 4) / 4)
    local scroll = T.ScrollArea(d, 140)
    scroll:ClearAllPoints()
    scroll:SetPoint("TOPLEFT", 14, -170)
    scroll:SetPoint("BOTTOMRIGHT", -12, 52)
    d.text = K.Label(scroll.child, "", { template = "small", width = DW - 14 })
    d.text:SetPoint("TOPLEFT", 0, 0)
    -- Actions: a quiet row, then the main one.
    local divider = d:CreateTexture(nil, "BORDER")
    divider:SetPoint("BOTTOMLEFT", 12, 46)
    divider:SetPoint("BOTTOMRIGHT", -12, 46)
    divider:SetHeight(1)
    divider:SetColorTexture(unpack(C.line))
    d.start = K.Button(d, "Start farming", 124, 30, function()
        if selected then HME.Guidance.StartResult(selected, State().goal) end
    end, "Plans the loop on the map and minimap and guides you. If it is far away, the trip goes through Forever-GPS "
        .. "(when installed) and HME takes over when you arrive.", "primary")
    d.start:SetPoint("BOTTOMRIGHT", -12, 10)
    d.preview = K.Button(d, "Preview", 84, 30, function() if selected then HME.MapOverlay.Preview(selected) end end,
        "Opens the world map on this farm with its spawn points, hunting areas and loop.")
    d.preview:SetPoint("RIGHT", d.start, "LEFT", -8, 0)
    local modeLabels = { guided = "Guided circuit", adaptive = "Adaptive circuit", free = "Free farming", minimal = "Minimal arrow" }
    d.mode = T.Dropdown(d, 136, { "guided", "adaptive", "free", "minimal" }, modeLabels,
        function() return HME.settings.huntMode or "guided" end, function(k) HME.Guidance.SetMode(k) end)
    d.mode:SetPoint("BOTTOMLEFT", 12, 13)
    T.Tooltip(d.mode, "How to be guided", "Guided: the arrow leads stop by stop. Free: the area stays highlighted and "
        .. "the arrow stays out of the way. Minimal: the arrow fades while you are on the loop and comes back when you stray.")
    d.markBtn = K.Button(d, "Mark", 64, 24, function() if selected then page.ToggleMark(selected) end end,
        "Mark this farm to compare it with others (right-click in the list does the same).", "ghost")
    d.compare = K.Button(body, "Compare (0)", 110, 24, function() page.ShowCompare() end,
        "Side by side: the farms you marked (Mark, or right-click in the list).", "ghost")
    d.compare:SetPoint("TOPRIGHT", 0, -36)
    for _, b in ipairs({ d.preview, d.start, d.mode, d.markBtn, d.kpis, d.tabs }) do b:Hide() end

    -- Places what follows the summary under it, however many lines it took.
    local function Below(withKpis)
        local h = d.summary:GetStringHeight() or 30
        if (d.summary:GetText() or "") == "" then h = 0 end
        local y = -58 - h - 10
        d.kpis:ClearAllPoints()
        d.kpis:SetPoint("TOPLEFT", 14, y)
        d.kpis:SetShown(withKpis and true or false)
        if withKpis then
            y = y - 96 - 8
            d.tabs:ClearAllPoints()
            d.tabs:SetPoint("TOPLEFT", 14, y)
            d.tabs:Show()
            y = y - 26 - 12
        else
            d.tabs:Hide()
        end
        return y
    end
    local function PlaceScroll(y)
        scroll:ClearAllPoints()
        scroll:SetPoint("TOPLEFT", 14, y)
        scroll:SetPoint("BOTTOMRIGHT", -12, 54)
    end

    -- Best beasts for a material (Skinning): one row per beast, at the area
    -- where it gives the most of it an hour; a click opens that area.
    local beasts = K.List(d, {
        width = DW, height = 300, rowHeight = 58,
        empty = "",
        makeRow = function(row)
            row.title = K.Label(row, "", { template = "strong", width = DW - 80, wrap = false })
            row.title:SetPoint("TOPLEFT", 10, -7)
            row.sub = K.Label(row, "", { template = "small", color = C.text2, width = DW - 24, wrap = false })
            row.sub:SetPoint("TOPLEFT", 10, -25)
            row.sub2 = K.Label(row, "", { template = "meta", width = DW - 24, wrap = false })
            row.sub2:SetPoint("TOPLEFT", 10, -41)
            row.conf = K.Pips(row)
            row.conf:SetPoint("TOPRIGHT", -12, -10)
        end,
        fillRow = function(row, e)
            row.title:SetText(page.BeastTitle(e))
            row.sub:SetText(page.BeastSub(e))
            row.sub2:SetText(page.BeastWhere(e))
            row.conf:Set(K.CONF_LEVEL[e.confidence or ""] or 0, K.ConfHex(e.confidence))
        end,
        onClick = function(e) page.OpenBeastArea(e) end,
        onEnter = function(row, e) page.BeastTooltip(row, e) end,
    })
    beasts:SetPoint("TOPLEFT", 12, -100)
    beasts:Hide()
    d.beastsBtn = K.Button(d, "Best beasts", 96, 26, function()
        if beastView then page.ShowDetail(selected) else page.ShowBeasts() end
    end, "Skinning: which beasts give the material you typed best, their levels, the Skinning they need, "
        .. "the yield per skin, how sure, and the hunting areas. Click a beast to open its best area.")
    d.beastsBtn:SetPoint("TOPRIGHT", -12, -12)
    -- Mark sits beside Best beasts, or in its place when that is hidden.
    local function PlaceMark()
        d.markBtn:ClearAllPoints()
        if d.beastsBtn:IsShown() then d.markBtn:SetPoint("RIGHT", d.beastsBtn, "LEFT", -4, 0)
        else d.markBtn:SetPoint("TOPRIGHT", -12, -12) end
    end
    page.PlaceMark = PlaceMark
    d.beastsBtn:Hide()

    function page.ToggleMark(r)
        if marked[r.key] then marked[r.key] = nil else marked[r.key] = r end
        local n = U.Count(marked)
        d.compare:SetText(("Compare (%d)"):format(n))
        list.Render()
    end

    local function Money(v) return K.Money(v or 0) end

    -- The one number a row leads with, for the goal: value, unit, colour.
    function page.Primary(r)
        local m, g = r.metrics or {}, State().goal
        if g == "material" and m.materialPerHour then
            return U.Thousands(m.materialPerHour), "materials/h", C.text
        end
        if (g == "profit" or g == "balanced") and m.range and (m.range.mid or 0) > 0 then
            return K.Money(m.range.mid, true), "gold/h, est.", C.gold
        end
        if m.catchesPerHour and not m.skillRange then
            return U.Thousands(m.catchesPerHour), "catches/h", C.text
        end
        local mid = m.skillRange and m.skillRange.mid or m.skillPerHour
        if mid and mid > 0 then return U.Thousands(mid), "skill-ups/h", C.accent end
        if m.range and (m.range.mid or 0) > 0 then return K.Money(m.range.mid, true), "gold/h, est.", C.gold end
        return "–", "no estimate", C.text3
    end

    -- Under the name: risk and travel, in the risk's colour.
    function page.RowFacts(r)
        local risk = r.risk and K.Paint(r.risk.label or "?", r.risk.hex) or "?"
        local travel = r.travel and U.Duration(r.travel) or "travel ?"
        local measured = r.evidence and r.evidence.level == "measured" and ("  ·  " .. K.Paint("measured", T.HEX.accent)) or ""
        local quest = r.quests and ("  ·  " .. K.Paint("quest", T.HEX.brass)) or ""
        return risk .. "  ·  " .. travel .. measured .. quest
    end

    function page.ConfLevel(r)
        if r.evidence and r.evidence.level == "measured" then return 4 end
        return K.CONF_LEVEL[r.confidence and r.confidence.label or ""] or 0
    end

    -- How sure, in one line a player reads at a glance.
    local EVIDENCE_WORDS = {
        measured = "Measured by you", ["partly measured"] = "Partly measured", ["known yield"] = "Yield measured, pace estimated",
        ["published data"] = "From published data, rate estimated", assumption = "Estimate: not measured yet",
    }
    function page.SureLine(r)
        local ev = r.evidence or {}
        local words = EVIDENCE_WORDS[ev.level or ""] or "Estimate"
        return ("%s  ·  %s confidence"):format(words, (r.confidence and r.confidence.label or "?"):lower())
    end

    function page.Headline(r)
        local m, g = r.metrics, State().goal
        local travel = r.travel and U.Duration(r.travel) or "travel ?"
        if g == "profit" then
            return ("%s/h  ·  %s"):format(Money(m.range and m.range.mid), travel)
        elseif g == "material" then
            return ("%.0f units/h  ·  %s"):format(m.materialPerHour or 0, travel)
        end
        local gold = m.range and (m.range.mid or 0) > 0 and ("  ·  " .. Money(m.range.mid) .. "/h") or ""
        return ("%.0f skill/h%s  ·  %s"):format(m.skillRange and m.skillRange.mid or m.skillPerHour or 0, gold, travel)
    end

    -- As many names as fit, then "+N". With a font string and a width the
    -- names are measured as drawn; without, about 34 letters.
    function page.SubLine(r, fs, width)
        local names, used, n = {}, 0, #(r.targets or {})
        local function Text(list, rest)
            return table.concat(list, ", ") .. (rest > 0 and K.Paint(("  +%d"):format(rest), T.HEX.text3) or "")
        end
        for _, t in ipairs(r.targets or {}) do
            if fs and width then
                names[#names + 1] = t.name
                fs:SetText(Text(names, n - #names))
                if #names > 1 and T.StringWidth(fs) > width then
                    names[#names] = nil
                    break
                end
            else
                local len = #(t.name or "") + (#names > 0 and 2 or 0)
                if #names > 0 and used + len > 34 then break end
                names[#names + 1] = t.name
                used = used + len
            end
        end
        return Text(names, n - #names)
    end

    local function ItemName(id) return (HME.Goals and HME.Goals.ItemName(id)) or ("item " .. id) end

    function page.BeastTitle(e)
        local hex = e.color and K.DIFF_HEX[e.color] or "ffffff"
        local lv = e.min == e.max and ("level %d"):format(e.min) or ("level %d-%d"):format(e.min, e.max)
        local which = #beastIDs > 1 and ("|cff999b8f%s:|r "):format(ItemName(e.itemID)) or ""
        return ("%s|cff%s%s|r  |cff999b8f%s|r"):format(which, hex, e.name or "?", lv)
    end

    function page.BeastSub(e)
        local req = e.req and ("Skinning %d"):format(e.req) or "Skinning ?"
        if e.reqTop and e.req and e.reqTop > e.req then req = req .. (" (%d at %d)"):format(e.reqTop, e.max) end
        local seen = e.observed and (e.observed.skins or 0) > 0
        return ("%s  ·  %.2f per skin%s  ·  %.0f an hour"):format(req, e.perSkin or 0, seen and "" or " (est.)", e.perHour or 0)
    end

    function page.BeastWhere(e)
        local first = e.areas[1]
        local s = first and ("Best: %s (%s)"):format(first.zone or "?", first.subarea or "?") or "Best: ?"
        local also = {}
        for i = 2, #e.areas do also[#also + 1] = e.areas[i].zone end
        if #also > 0 then s = s .. "  ·  also " .. table.concat(also, ", ") end
        return s
    end

    function page.BeastTooltip(row, e)
        GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
        GameTooltip:AddLine(("%s (level %d-%d)"):format(e.name or "?", e.min or 0, e.max or 0))
        GameTooltip:AddLine(page.BeastSub(e), 1, 1, 1, true)
        GameTooltip:AddLine("Yield: " .. HME.Skinning.BeastYieldNote(e), 0.8, 0.8, 0.8)
        if e.skinShare and e.skinShare < 1 then
            GameTooltip:AddLine(("You can skin %d%% of its levels now."):format(e.skinShare * 100), 1, 0.82, 0)
        end
        if e.killSecs then GameTooltip:AddLine(("A kill takes about %.0f s there."):format(e.killSecs), 0.8, 0.8, 0.8) end
        for i, a in ipairs(e.areas) do
            GameTooltip:AddLine(("%d. %s (%s): about %.0f an hour, %s confidence"):format(i, a.zone or "?", a.subarea or "?",
                a.perHour or 0, a.confidence or "?"), 0.8, 0.8, 0.8)
        end
        GameTooltip:AddLine("Click: open the best area. Beast spawns are where beasts appear, not live targets.", 0.7, 0.7, 0.7, true)
        GameTooltip:Show()
    end

    -- Every typed material's best beasts, best first.
    function page.BestBeasts()
        local out = {}
        for _, id in ipairs(beastIDs) do
            for _, e in ipairs(HME.Skinning.BestBeasts(results, id)) do
                e.itemID = id
                out[#out + 1] = e
            end
        end
        if #beastIDs > 1 then table.sort(out, function(a, b) return (a.perHour or 0) > (b.perHour or 0) end) end
        return out
    end

    local function DetailWidgets(on)
        scroll:SetShown(on)
        beasts:SetShown(not on)
    end

    function page.ShowBeasts()
        local s = State()
        beastView = true
        comparing = false
        DetailWidgets(false)
        d:Show()
        d.beastsBtn:SetText("Back")
        local names = {}
        for _, id in ipairs(beastIDs) do names[#names + 1] = ItemName(id) end
        d.head:SetWidth(DW - 80)
        d.title:SetText(#names > 0 and ("Best beasts for " .. table.concat(names, ", ")) or "Best beasts")
        d.where:SetText("Skinning · each at its best area")
        d.summary:SetText("Ranked by how many an hour (the beast's share of the kills). Click one to open that area.")
        beasts:ClearAllPoints()
        beasts:SetPoint("TOPLEFT", 14, Below(false))
        local items = {}
        if s.prof ~= "Skinning" or s.goal ~= "material" then
            beasts:SetEmptyText("Choose Skinning and the goal \"A material\", then type a leather or hide (e.g. Medium Leather).")
        elseif #beastIDs == 0 then
            beasts:SetEmptyText("Type a leather, hide or scale that Skinning gives (e.g. Medium Leather), then search.")
        else
            items = page.BestBeasts()
            beasts:SetEmptyText("No beast in these farms gives it. Try another risk mode or fewer filters.")
        end
        beasts:SetItems(items)
        for _, b in ipairs({ d.preview, d.start, d.markBtn, d.mode, d.compare, d.tabs }) do b:Hide() end
        return items
    end

    function page.OpenBeastArea(e)
        local r = e and e.result
        if not r then return end
        for i, x in ipairs(results) do
            if x == r then list:Select(i) break end
        end
        selected = r
        page.ShowDetail(r)
    end

    -- The three tiles: the goal's own figure, gold an hour, travel.
    function page.FillKpis(r)
        local m, g = r.metrics or {}, State().goal
        local k1, k2, k3 = d.kpi[1], d.kpi[2], d.kpi[3]
        local function range(x) return x and ("range %s"):format(K.Range(x.low, x.high)) or "" end
        local function mrange(x) return ("range %s–%s"):format(K.Money(x.low, true), K.Money(x.high, true)) end
        if g == "material" and m.materialPerHour then
            k1:SetLabel("Materials an hour")
            k1:Set(U.Thousands(m.materialPerHour), "of what you asked for", C.text)
        elseif m.catchesPerHour and not m.skillRange then
            k1:SetLabel("Catches an hour")
            k1:Set(U.Thousands(m.catchesPerHour), "", C.text)
        elseif g == "profit" and m.range then
            k1:SetLabel("Gold an hour")
            local priced = (m.range.mid or 0) > 0
            k1:Set(priced and K.Money(m.range.mid) or "–", priced and mrange(m.range) or "no prices yet", C.gold)
        else
            k1:SetLabel("Skill-ups an hour")
            local mid = m.skillRange and m.skillRange.mid or m.skillPerHour
            k1:Set(mid and U.Thousands(mid) or "–", m.skillRange and range(m.skillRange) or "", C.accent)
        end
        if g == "profit" then
            k2:SetLabel("Over the trip")
            k2:Set((r.tripGph or 0) > 0 and K.Money(r.tripGph) or "–", ("%d min with travel"):format(HME.settings.sessionMinutes or 60), C.gold)
        else
            k2:SetLabel("Gold an hour")
            local priced = m.range and (m.range.mid or 0) > 0
            k2:Set(priced and K.Money(m.range.mid) or "–", priced and "estimate, while farming" or "no prices yet", C.gold)
        end
        k3:SetLabel("Travel")
        k3:Set(r.travel and U.Duration(r.travel) or "?", r.travelQuality or (r.travel and "estimate" or "unknown"), C.text)
        d.sure:Set(page.ConfLevel(r), K.ConfHex(r.confidence and r.confidence.label))
        d.sureText:SetText(page.SureLine(r))
    end

    local secs = {}
    local function Sec(i)
        if secs[i] then return secs[i] end
        local x = {}
        x.head = K.Label(scroll.child, "", { template = "label", color = C.text2 })
        x.body = K.Label(scroll.child, "", { template = "small", width = DW - 22 })
        if x.body.SetSpacing then x.body:SetSpacing(3) end
        secs[i] = x
        return x
    end
    function page.ShowSections(list)
        d.text:Hide()
        local y = 0
        for i, sec in ipairs(list) do
            local x = Sec(i)
            x.head:SetText(sec[1] or "")
            x.head:ClearAllPoints()
            x.head:SetPoint("TOPLEFT", 0, y)
            x.head:Show()
            y = y - 17
            x.body:SetText(table.concat(sec[2], "\n"))
            x.body:ClearAllPoints()
            x.body:SetPoint("TOPLEFT", 0, y)
            x.body:Show()
            y = y - (x.body:GetStringHeight() or 14) - 16
        end
        for i = #list + 1, #secs do
            secs[i].head:Hide()
            secs[i].body:Hide()
        end
        scroll:SetContent(DW, -y + 4)
    end
    local function HideSections()
        for _, x in ipairs(secs) do x.head:Hide() x.body:Hide() end
        d.text:Show()
    end

    function page.ShowDetail(r)
        beastView = false
        DetailWidgets(true)
        d.beastsBtn:SetText("Best beasts")
        if not r then return end
        local m = r.metrics
        d:Show()
        d.head:SetWidth(DW - 150)
        d.title:SetText(r.zone)
        d.where:SetText(("%s  ·  around %d, %d"):format(r.subarea or "", (r.cx or 0) * 100, (r.cy or 0) * 100))
        d.summary:SetText(r.summary or "")
        page.FillKpis(r)
        PlaceScroll(Below(true))
        -- The details as titled sections, each a short list.
        local sections, cur = {}, nil
        local function section(name)
            cur = { name, {} }
            sections[#sections + 1] = cur
        end
        local function add(line)
            if line == "" then return end
            if not cur then section("") end
            local list = cur[2]
            list[#list + 1] = (line:gsub("^  ", ""))
        end
        local ev = r.evidence or {}
        -- Practical alternatives: lower risk, or much closer, for most of the number.
        local alt = HME.Recommend.Alternatives(results, r, State().goal)
        if alt then
            section("Alternatives")
            local unit = State().goal == "profit" and "the gold" or (State().goal == "material" and "the materials" or "the skill-ups")
            if alt.safer then
                local c = alt.safer.result
                add(("  Lower risk: %s (%s), %s instead of %s, about %d%% of %s, %s away."):format(c.zone, c.subarea or "",
                    K.Paint(c.risk.label, c.risk.hex), K.Paint(r.risk.label, r.risk.hex), alt.safer.share * 100, unit,
                    c.travel and U.Duration(c.travel) or "?"))
            end
            if alt.closer then
                local c = alt.closer.result
                add(("  Closer: %s (%s), %s away instead of %s, about %d%% of %s: better for a short session."):format(c.zone,
                    c.subarea or "", U.Duration(c.travel), U.Duration(r.travel), alt.closer.share * 100, unit))
            end
        end
        section("Expect")
        if m.skillRange and (m.skillPerHour or 0) > 0 then
            add(("  Skill-ups: about %.0f an hour (%.0f to %.0f); %.0f%% of gathers give a point now"):format(
                m.skillRange.mid, m.skillRange.low, m.skillRange.high, (m.skillChance or 0) * 100))
        end
        if m.range and (m.range.mid or 0) <= 0 then
            add("  Gold: no prices yet (vendor prices only, or none). Auctionator, TSM or Forever-GPS add auction prices.")
        elseif m.range then
            add(("  Gold while farming: about %s an hour (%s to %s)"):format(Money(m.range.mid), Money(m.range.low), Money(m.range.high)))
            if r.travel then
                add(("  Gold over a %d-minute trip incl. %s travel: about %s an hour"):format(HME.settings.sessionMinutes or 60,
                    U.Duration(r.travel), Money(r.tripGph)))
            end
        end
        if m.materialPerHour then add(("  Materials: about %.0f an hour"):format(m.materialPerHour)) end
        if m.beastsPerHour then
            add(("  Beasts: about %.0f an hour in a real session (%s); a kill about %.0f s (%s), walking %.0f s"):format(
                m.beastsPerHour, m.limit == "respawn" and "respawns limit it" or "your pace limits it", m.killSecs, m.killBasis, m.walkSecs))
            if m.theoretical and m.theoretical > m.beastsPerHour * 1.05 then
                add(("  A perfect, uninterrupted circuit would reach about %.0f: not what to plan on."):format(m.theoretical))
            end
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
        section("What you will find")
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
        section("Risk")
        add(("  %s: %s"):format(K.Paint(r.risk.label, r.risk.hex), table.concat(r.risk.reasons, "; ")))
        add("")
        section("How sure")
        add(("  %s. %s"):format(K.Paint(r.confidence.label, K.ConfHex(r.confidence.label)), ev.text or ""))
        add("  " .. table.concat(r.confidence.reasons, "; ") .. ".")
        add("  Source: " .. (r.source or "?"))
        add("")
        local notes = {}
        if r.prof == "Skinning" then
            notes[#notes + 1] = "Beast spawns are where beasts appear, not live targets."
        elseif r.prof ~= "Fishing" then
            notes[#notes + 1] = "Spawn points are where nodes can appear, not where nodes are now."
        end
        if m.gph then notes[#notes + 1] = "Auction prices are what sellers ask, not guaranteed sales." end
        if r.prof == "Combined" then
            notes[#notes + 1] = "Find Herbs and Find Minerals can't run together: switch tracking yourself as you go; the map shows both."
        end
        if #notes > 0 then section("Good to know") end
        for _, n in ipairs(notes) do add(K.Paint(n, T.HEX.text2)) end
        local TAB_OF = { Alternatives = "overview", Expect = "overview", ["Good to know"] = "overview", ["What you will find"] = "find", Risk = "risk",
            ["How sure"] = "evidence" }
        local shown = {}
        for _, sec in ipairs(sections) do
            if (TAB_OF[sec[1]] or "overview") == tab then shown[#shown + 1] = sec end
        end
        page.allSections = sections
        page.ShowSections(shown)
        d.tabs:Refresh()
        for _, b in ipairs({ d.preview, d.start, d.markBtn, d.compare }) do b:Show() end
        d.mode:SetShown(r.prof == "Skinning")
        d.markBtn:SetText(marked[r.key] and "Marked" or "Mark")
        PlaceMark()
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
        beastView = false
        DetailWidgets(true)
        d.beastsBtn:SetText("Best beasts")
        HideSections()
        local cmp = HME.Recommend.Compare(rows)
        d.title:SetText("Comparing " .. #rows .. " farms")
        d.where:SetText("Side by side, best first")
        d.summary:SetText("Green: best on that line. A lead resting on unmeasured estimates is shown as an estimate only.")
        PlaceScroll(Below(false))
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
            if b and b.index == i then s = (b.sure and "|cff8fcc5c" or "|cfffacc5c") .. s .. "|r" end
            return s
        end
        for i, r in ipairs(rows) do
            lines[#lines + 1] = ("|cfff2f0e6%d. %s (%s)|r  %s, %s"):format(i, r.zone, r.subarea, r.confidence.label .. " confidence",
                r.evidence and r.evidence.level or "")
            for _, col in ipairs(HME.Recommend.COMPARE_COLUMNS) do
                lines[#lines + 1] = ("    %s: %s"):format(col.label, cell(col, i, r))
            end
            local st = HME.db.stats[r.key]
            if st and (st.hours or 0) > 0 then
                lines[#lines + 1] = ("    Your history: %.1f h, %s/h"):format(st.hours, K.Money((st.value or 0) / st.hours))
            end
        end
        for _, n in ipairs(cmp.notes) do lines[#lines + 1] = "|cff999b8f" .. n .. "|r" end
        d.text:SetText(table.concat(lines, "\n"))
        scroll:SetContent(DW, (d.text:GetStringHeight() or 300) + 10)
    end

    function page.Layout()
        local g = State().goal
        mat:SetShown(g == "material")
        status:ClearAllPoints()
        status:SetPoint("TOPLEFT", g == "material" and 240 or 2, -42)
        status:SetWidth(PAGE_W - (g == "material" and 240 or 2) - 120)
        d.beastsBtn:SetShown(State().prof == "Skinning")
        local n = 0
        local f = State().filters or {}
        if f.continent then n = n + 1 end
        if f.minConfidence then n = n + 1 end
        if State().risk ~= "balanced" then n = n + 1 end
        filterBtn:SetText(filters:IsShown() and "Close" or (n > 0 and ("Filters · %d"):format(n) or "Filters"))
    end

    local searching = false
    function page.Search()
        local s = State()
        local targets, ids, _
        beastIDs = {}
        if beastView then
            -- Rows point at the old results: empty until the new ones arrive.
            beasts:SetItems({})
            beasts:SetEmptyText("Searching...")
        end
        if s.goal == "material" then
            targets, _, ids = Targets(s.prof, s.material)
            if s.prof == "Skinning" then beastIDs = ids or {} end
            if not targets then
                status:SetText(s.material and s.material ~= "" and "No material matches that name for this profession." or "Type one or more materials.")
                list:SetItems({})
                list:SetEmptyText("Type a material (e.g. Heavy Leather, Iron Ore). Separate several with commas.")
                results = {}
                if beastView then page.ShowBeasts() end
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
                    d.where:SetText("")
                    d.summary:SetText("")
                    d.text:SetText("")
                    d.kpis:Hide()
                    for _, b in ipairs({ d.preview, d.start, d.markBtn, d.mode }) do b:Hide() end
                    if beastView then page.ShowBeasts() end
                else
                    status:SetText(("%d farms ranked for %d minutes of play%s%s"):format(#results, HME.settings.sessionMinutes or 60,
                        #(skipped or {}) > 0 and (", " .. #skipped .. " zones left out") or "", note))
                    list:Select(1)
                    selected = results[1]
                    if beastView then page.ShowBeasts() else page.ShowDetail(results[1]) end
                    if s.goal == "profit" or s.goal == "balanced" then HME.Suggest.CheckPrices(results) end
                    list.Render()
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
    HME.Pages.finderBeasts = function() return page.ShowBeasts() end
    HME.Pages.finderOpenBeast = function(e) page.OpenBeastArea(e) return selected end
end
