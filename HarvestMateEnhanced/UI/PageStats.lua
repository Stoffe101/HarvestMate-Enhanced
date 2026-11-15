-- HarvestMate Enhanced: UI/PageStats.lua
-- Profits and statistics. Views:
--   Journal     your sessions: where, how long (farming vs travel), what you
--               gathered (observed quantities) and its estimated value, and
--               what the Farm Finder had predicted
--   Overview    totals and bests: materials, skins, skill gained, time,
--               best session, most productive zones and beasts, this week
--               against the week before
--   Areas       measured rates per farming area (what rankings learn from)
--   Records / Achievements   HarvestMate's
-- Filters: profession and period. Quantities are observed; gold is an
-- estimate from prices (marked "est.").
-- Copyright (C) 2026 HarvestMate Enhanced contributors. GPL-3.0-or-later.

local _, ns = ...
local HME = ns.HME
local T = ns.Theme
local K = HME.Kit
local U = HME.U

local PAGE_W = 738

local VIEWS = { "journal", "overview", "areas", "records", "achievements" }
local VIEW_LABELS = { journal = "Journal", overview = "Overview", areas = "Measured areas", records = "Records", achievements = "Achievements" }

local function AreaLabel(key)
    local prof, mapID = tostring(key):match("^(%a+)@(%d+)")
    if not prof then return tostring(key) end
    return prof .. " in " .. HME.ZoneData.Name(tonumber(mapID))
end

local function SessionProf(s)
    for _, a in ipairs(s.areas or {}) do
        local p = tostring(a.key):match("^(%a+)@")
        if p then return p end
    end
end

HME.Pages.stats = function(body, page)
    local view = "journal"
    local profFilter, period = "All", "all"
    local seg = K.Segments(body, VIEWS, VIEW_LABELS, function() return view end, function(k) view = k; page.Refresh() end, 112)
    seg:SetPoint("TOPLEFT", 0, 0)
    local pf = T.Dropdown(body, 120, { "All", "Herbalism", "Mining", "Skinning", "Fishing" }, {},
        function() return profFilter end, function(k) profFilter = k; page.Refresh() end)
    pf:SetPoint("TOPLEFT", 0, -28)
    local per = T.Dropdown(body, 120, { "all", "week", "month" }, { all = "All time", week = "Last 7 days", month = "Last 30 days" },
        function() return period end, function(k) period = k; page.Refresh() end)
    per:SetPoint("TOPLEFT", 128, -28)
    local headline = K.Label(body, "", { template = "GameFontHighlightSmall", width = 330 })
    headline:SetPoint("TOPLEFT", 256, -32)
    -- Free-text filter: a zone, a material, a route or a character.
    local search = T.EditBox(body, 140)
    search:SetPoint("TOPRIGHT", -4, -28)
    local filterText = ""
    search:SetScript("OnTextChanged", function(self) filterText = U.Trim(self:GetText() or ""):lower() page.Refresh() end)
    T.Tooltip(search, "Filter", "Only sessions whose zone, materials, route or character contain this text.")

    local list = K.List(body, {
        width = PAGE_W, height = 380, rowHeight = 34, empty = "No sessions yet. A session starts by itself with your first gather, skin or catch; pick a farm in the Farm Finder to get going.",
        makeRow = function(row)
            row.a = K.Label(row, "", { template = "GameFontHighlight", width = 330, wrap = false })
            row.a:SetPoint("TOPLEFT", 8, -4)
            row.b = K.Label(row, "", { template = "GameFontDisableSmall", width = 330, wrap = false })
            row.b:SetPoint("TOPLEFT", 8, -19)
            row.c = K.Label(row, "", { template = "GameFontHighlightSmall", width = 380, justify = "RIGHT", wrap = false })
            row.c:SetPoint("TOPRIGHT", -10, -4)
            row.d = K.Label(row, "", { template = "GameFontDisableSmall", width = 380, justify = "RIGHT", wrap = false })
            row.d:SetPoint("TOPRIGHT", -10, -19)
        end,
        fillRow = function(row, it)
            row.a:SetText(it[1] or "")
            row.b:SetText(it[2] or "")
            row.c:SetText(it[3] or "")
            row.d:SetText(it[4] or "")
        end,
    })
    list:SetPoint("TOPLEFT", 0, -56)

    local foot = T.Card(body, "Prices", 0, -442, PAGE_W, 72)
    foot.text = K.Label(foot, "", { template = "GameFontHighlightSmall", width = PAGE_W - 24 })
    foot.text:SetPoint("TOPLEFT", 12, -26)

    local function InPeriod(t)
        if period == "all" then return true end
        local now = (time and time()) or 0
        return (now - (t or 0)) <= (period == "week" and 7 or 30) * 86400
    end

    local function Matches(s)
        if filterText == "" then return true end
        local hay = { tostring(s.char or ""), tostring(s.route or "") }
        for _, a in ipairs(s.areas or {}) do hay[#hay + 1] = AreaLabel(a.key) end
        for id in pairs(s.items or {}) do hay[#hay + 1] = HME.Goals.ItemName(id) end
        return table.concat(hay, " "):lower():find(filterText, 1, true) ~= nil
    end

    local function Sessions()
        local out = {}
        for i = #HME.db.sessions, 1, -1 do
            local s = HME.db.sessions[i]
            local p = SessionProf(s)
            if InPeriod(s.t) and (profFilter == "All" or p == profFilter) and Matches(s) then out[#out + 1] = s end
        end
        return out
    end

    local function ItemsLine(items)
        local parts = {}
        for id, q in pairs(items or {}) do parts[#parts + 1] = { q = q, name = HME.Goals.ItemName(id) } end
        table.sort(parts, function(a, b) return a.q > b.q end)
        local out = {}
        for i = 1, math.min(3, #parts) do out[#out + 1] = parts[i].q .. " " .. parts[i].name end
        return table.concat(out, ", ")
    end

    local function Journal()
        local items = {}
        for _, s in ipairs(Sessions()) do
            local farm = math.max(s.farmSecs or s.secs or 0, 1)
            local h = farm / 3600
            local trip = (farm + (s.travelSecs or 0)) / 3600
            local when = date and date("%d %b %H:%M", s.t) or tostring(s.t)
            local areas, predicted = {}, nil
            for _, a in ipairs(s.areas or {}) do
                areas[#areas + 1] = AreaLabel(a.key)
                predicted = predicted or a.predicted
            end
            local pred = ""
            if predicted and predicted.gph then pred = (" · predicted %s/h"):format(K.Money(predicted.gph)) end
            items[#items + 1] = {
                ("%s · %s farmed%s"):format(when, U.Duration(farm), (s.travelSecs or 0) > 0 and (" + " .. U.Duration(s.travelSecs) .. " travel") or ""),
                table.concat(areas, ", "),
                ("est. %s/h farming · %s/h trip · %.0f skill/h"):format(K.Money(s.value / h), K.Money(s.value / trip), s.skillups / h),
                ("%s%s%s"):format(ItemsLine(s.items), (s.deaths or 0) > 0 and (" · " .. s.deaths .. " deaths") or "", pred),
            }
        end
        return items
    end

    local function Overview()
        local list_ = Sessions()
        local tot = { farm = 0, travel = 0, value = 0, skill = 0, skins = 0, nodes = 0, catches = 0, items = {} }
        local best, bestGph
        local zones, beasts = {}, {}
        local now = (time and time()) or 0
        local thisWeek, lastWeek = { v = 0, h = 0 }, { v = 0, h = 0 }
        for _, s in ipairs(list_) do
            local farm = s.farmSecs or s.secs or 0
            tot.farm = tot.farm + farm
            tot.travel = tot.travel + (s.travelSecs or 0)
            tot.value = tot.value + s.value
            tot.skill = tot.skill + s.skillups
            tot.skins = tot.skins + (s.counts.skin or 0)
            tot.nodes = tot.nodes + (s.counts.herb or 0) + (s.counts.mine or 0)
            tot.catches = tot.catches + (s.counts.fish or 0)
            for id, q in pairs(s.items or {}) do tot.items[id] = (tot.items[id] or 0) + q end
            local gph = farm >= 600 and s.value / (farm / 3600) or nil
            if gph and (not bestGph or gph > bestGph) then best, bestGph = s, gph end
            for _, a in ipairs(s.areas or {}) do
                local z = zones[AreaLabel(a.key)] or { v = 0, h = 0 }
                zones[AreaLabel(a.key)] = z
                z.v, z.h = z.v + (a.value or 0), z.h + (a.secs or 0) / 3600
            end
            local age = now - (s.t or 0)
            local bucket = age <= 7 * 86400 and thisWeek or (age <= 14 * 86400 and lastWeek or nil)
            if bucket then bucket.v, bucket.h = bucket.v + s.value, bucket.h + farm / 3600 end
        end
        for npcID, rec in pairs(HME.db.obs.skins) do
            local npc = HME.Learning.Npc(npcID)
            beasts[#beasts + 1] = { name = npc and npc.name or ("beast " .. npcID), n = rec.n, rec = rec }
        end
        table.sort(beasts, function(a, b) return a.n > b.n end)
        local zl = {}
        for name, z in pairs(zones) do if z.h >= 0.2 then zl[#zl + 1] = { name = name, gph = z.v / z.h, h = z.h } end end
        table.sort(zl, function(a, b) return a.gph > b.gph end)
        local items = {
            { "Time farming", ("%s farming, %s travelling"):format(U.Duration(tot.farm), U.Duration(tot.travel)),
              ("est. %s gathered"):format(K.Money(tot.value)), ("%d skill points gained"):format(tot.skill) },
            { "Gathered (observed)", ItemsLine(tot.items), ("%d nodes · %d skins · %d catches"):format(tot.nodes, tot.skins, tot.catches), "" },
        }
        if best then
            items[#items + 1] = { "Best session", (date and date("%d %b", best.t) or "") .. " · " .. U.Duration(best.farmSecs or best.secs),
                ("est. %s/h"):format(K.Money(bestGph)), ItemsLine(best.items) }
        end
        for i = 1, math.min(3, #zl) do
            items[#items + 1] = { i == 1 and "Most productive areas" or "", zl[i].name, ("est. %s/h"):format(K.Money(zl[i].gph)),
                ("%.1f h measured"):format(zl[i].h) }
        end
        for i = 1, math.min(3, #beasts) do
            local b = beasts[i]
            local top = ItemsLine(b.rec.qty)
            items[#items + 1] = { i == 1 and "Most skinned beasts" or "", b.name, ("%d skins"):format(b.n), top }
        end
        if thisWeek.h > 0 and lastWeek.h > 0 then
            local a, b = thisWeek.v / thisWeek.h, lastWeek.v / lastWeek.h
            items[#items + 1] = { "This week vs last", ("est. %s/h vs %s/h"):format(K.Money(a), K.Money(b)),
                ("%+d%%"):format((a / math.max(b, 1) - 1) * 100), "" }
        end
        return items
    end

    local function Areas()
        local items = {}
        local keys = U.Keys(HME.db.stats)
        table.sort(keys, function(a, b) return (HME.db.stats[a].t or 0) > (HME.db.stats[b].t or 0) end)
        for _, key in ipairs(keys) do
            local st = HME.db.stats[key]
            local prof = tostring(key):match("^(%a+)@")
            if profFilter == "All" or prof == profFilter then
                local h = math.max(st.hours or 0, 1e-6)
                local pred = HME.Guidance.PredictionFor(key)
                local cmp = ""
                if pred and pred.gph and st.value then
                    cmp = (" · %d%% of the forecast"):format(((st.value / h) / math.max(pred.gph, 1)) * 100)
                end
                items[#items + 1] = {
                    AreaLabel(key),
                    ("%.1f h farming over %d session%s%s"):format(st.hours or 0, st.sessions or 0, (st.sessions or 0) == 1 and "" or "s",
                        (st.hours or 0) < 1.5 and " · still settling" or ""),
                    ("est. %s/h · %.0f skill/h"):format(K.Money((st.value or 0) / h), (st.skillups or 0) / h),
                    ("%.0f nodes/h · %.0f beasts/h · %.0f catches/h%s"):format((st.nodes or 0) / h, (st.beasts or 0) / h, (st.catches or 0) / h, cmp),
                }
            end
        end
        return items
    end

    local function Records()
        local items = {}
        -- HME's records from your journal (with minimum farming times), then HarvestMate's.
        for _, r in ipairs(HME.Records.List({ prof = profFilter })) do items[#items + 1] = { r[1], r[3], r[2] } end
        local ok, lines = pcall(ns.HG.RecordLines)
        for _, l in ipairs(ok and lines or {}) do items[#items + 1] = { l[1], nil, l[2] } end
        if #items == 0 then items[1] = { "No records yet", "They fill in as you gather." } end
        return items
    end

    local function Achievements()
        local items = {}
        local HG = ns.HG
        local ok, rows = pcall(HG.AchRows)
        for _, r in ipairs(ok and rows or {}) do
            if type(r) == "table" and r.series then
                local okN, name = pcall(HG.AchName, r.series, r.target)
                local okD, desc = pcall(HG.AchDesc, r.series, r.target)
                local done = r.earned >= r.total
                local value = type(r.value) == "number" and r.value or 0
                items[#items + 1] = {
                    (done and "|cff8fcc5c" or "|cfff2f0e6") .. (okN and name or "?") .. "|r  |cff999b8f" .. (r.category or "") .. "|r",
                    okD and desc or "",
                    ("%d of %d tiers"):format(r.earned, r.total),
                    ("%s / %s"):format(math.floor(value), tostring(r.threshold or "")),
                }
            end
        end
        local okT, earned, total, points = pcall(HG.AchTotals)
        if okT and total then table.insert(items, 1, { ("%d of %d achievements, %d points"):format(earned or 0, total, points or 0) }) end
        return items
    end

    function page.Refresh()
        seg:Refresh()
        pf:Refresh()
        per:Refresh()
        local items
        if view == "journal" then items = Journal()
        elseif view == "overview" then items = Overview()
        elseif view == "areas" then items = Areas()
        elseif view == "records" then items = Records()
        else items = Achievements() end
        list:SetItems(items, true)
        local n = #Sessions()
        headline:SetText(("%d session%s shown · quantities are observed, gold is estimated from prices"):format(n, n == 1 and "" or "s"))
        local avail = HME.Prices.Available()
        local s = HME.settings
        foot.text:SetText(("Prices from: %s. Estimate: %s. Selling: %s. Profit counts: %s. Listings are what sellers ask, not sales.")
            :format(#avail > 0 and table.concat(avail, ", ") or "vendor only (Auctionator, TSM or Forever-GPS add auction prices)",
                s.priceMode, s.saleMode == "best" and "whichever pays more" or s.saleMode,
                s.profitScope == "total" and "skinning plus mob loot" or "skinning materials only"))
    end
end
