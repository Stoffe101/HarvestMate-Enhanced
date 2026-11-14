-- HarvestMate Enhanced: UI/PageStats.lua
-- Profits and statistics: finished sessions (with what was predicted next to
-- what happened), the measured rates of every area you farmed, HarvestMate's
-- records and achievements, and where prices come from.
-- Copyright (C) 2026 HarvestMate Enhanced contributors. GPL-3.0-or-later.

local _, ns = ...
local HME = ns.HME
local T = ns.Theme
local K = HME.Kit
local U = HME.U
local C = T.C

local PAGE_W = 738

local VIEWS = { "sessions", "areas", "records", "achievements" }
local VIEW_LABELS = { sessions = "Sessions", areas = "Measured areas", records = "Records", achievements = "Achievements" }

local function AreaLabel(key)
    local prof, mapID = tostring(key):match("^(%a+)@(%d+)")
    if not prof then return tostring(key) end
    return prof .. " in " .. HME.ZoneData.Name(tonumber(mapID))
end

HME.Pages.stats = function(body, page)
    local view = "sessions"
    local seg = K.Segments(body, VIEWS, VIEW_LABELS, function() return view end, function(k)
        view = k
        page.Refresh()
    end, 130)
    seg:SetPoint("TOPLEFT", 0, 0)

    local list = K.List(body, {
        width = PAGE_W, height = 380, rowHeight = 34, empty = "Nothing yet.",
        makeRow = function(row)
            row.a = K.Label(row, "", { template = "GameFontHighlight", width = 300, wrap = false })
            row.a:SetPoint("TOPLEFT", 8, -4)
            row.b = K.Label(row, "", { template = "GameFontDisableSmall", width = 300, wrap = false })
            row.b:SetPoint("TOPLEFT", 8, -19)
            row.c = K.Label(row, "", { template = "GameFontHighlightSmall", width = 400, justify = "RIGHT", wrap = false })
            row.c:SetPoint("RIGHT", -10, 0)
        end,
        fillRow = function(row, it)
            row.a:SetText(it[1] or "")
            row.b:SetText(it[2] or "")
            row.c:SetText(it[3] or "")
        end,
    })
    list:SetPoint("TOPLEFT", 0, -30)

    local foot = T.Card(body, "Prices", 0, -418, PAGE_W, 96)
    foot.text = K.Label(foot, "", { template = "GameFontHighlightSmall", width = PAGE_W - 24 })
    foot.text:SetPoint("TOPLEFT", 12, -26)

    local function Sessions()
        local items = {}
        local list_ = HME.db.sessions
        for i = #list_, 1, -1 do
            local s = list_[i]
            local h = math.max(s.secs, 1) / 3600
            local when = date and date("%d %b %H:%M", s.t) or tostring(s.t)
            local areas = {}
            local predicted
            for _, a in ipairs(s.areas or {}) do
                areas[#areas + 1] = AreaLabel(a.key)
                predicted = predicted or a.predicted
            end
            local pred = ""
            if predicted then
                if predicted.gph then pred = ("  ·  predicted %s/h"):format(K.Money(predicted.gph)) end
                if predicted.skill and s.skillups > 0 then pred = pred .. ("  ·  predicted %.0f skill/h"):format(predicted.skill) end
            end
            items[#items + 1] = {
                ("%s  ·  %s"):format(when, U.Duration(s.secs)),
                table.concat(areas, ", "),
                ("%s/h  ·  %.0f skill/h  ·  %d nodes, %d skins, %d catches%s%s"):format(K.Money(s.value / h), s.skillups / h,
                    (s.counts.herb or 0) + (s.counts.mine or 0), s.counts.skin or 0, s.counts.fish or 0,
                    (s.deaths or 0) > 0 and ("  ·  " .. s.deaths .. " deaths") or "", pred),
            }
        end
        return items
    end

    local function Areas()
        local items = {}
        local keys = U.Keys(HME.db.stats)
        table.sort(keys, function(a, b) return (HME.db.stats[a].t or 0) > (HME.db.stats[b].t or 0) end)
        for _, key in ipairs(keys) do
            local st = HME.db.stats[key]
            local h = math.max(st.hours or 0, 1e-6)
            local pred = HME.Guidance.PredictionFor(key)
            local cmp = ""
            if pred and pred.gph and st.value then
                local ratio = (st.value / h) / math.max(pred.gph, 1)
                cmp = ("  ·  %d%% of predicted gold"):format(ratio * 100)
            end
            items[#items + 1] = {
                AreaLabel(key),
                ("%.1f h over %d session%s%s"):format(st.hours or 0, st.sessions or 0, (st.sessions or 0) == 1 and "" or "s",
                    (st.hours or 0) < 1.5 and "  ·  still settling" or ""),
                ("%s/h  ·  %.0f skill/h  ·  %.0f nodes/h  ·  %.0f beasts/h%s"):format(K.Money((st.value or 0) / h),
                    (st.skillups or 0) / h, (st.nodes or 0) / h, (st.beasts or 0) / h, cmp),
            }
        end
        return items
    end

    local function Records()
        local items = {}
        local HG = ns.HG
        local ok, lines = pcall(HG.RecordLines)
        for _, l in ipairs(ok and lines or {}) do
            if type(l) == "table" then
                items[#items + 1] = { l[1] or l.label, nil, l[2] or l.value }
            else
                items[#items + 1] = { tostring(l) }
            end
        end
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
                    (done and "|cff48c75a" or "|cffffd100") .. (okN and name or "?") .. "|r  |cff9a9a9a" .. (r.category or "") .. "|r",
                    okD and desc or "",
                    ("%d of %d tiers  ·  %s / %s"):format(r.earned, r.total, math.floor(value), tostring(r.threshold or "")),
                }
            end
        end
        local okT, earned, total, points = pcall(HG.AchTotals)
        if okT and total then
            table.insert(items, 1, { ("%d of %d achievements, %d points"):format(earned or 0, total, points or 0) })
        end
        return items
    end

    function page.Refresh()
        seg:Refresh()
        local items
        if view == "sessions" then items = Sessions()
        elseif view == "areas" then items = Areas()
        elseif view == "records" then items = Records()
        else items = Achievements() end
        list:SetItems(items, true)
        local avail = HME.Prices.Available()
        local s = HME.settings
        foot.text:SetText(("Prices from: %s.  Estimate shown: %s.  Selling: %s.  Profit counts: %s.\n"
            .. "Auction prices are listings, not guaranteed sales. Conservative uses the lowest listing (or 80%% of a single price); "
            .. "optimistic adds 5%%. Change these in Settings, Prices.")
            :format(#avail > 0 and table.concat(avail, ", ") or "vendor prices only (install Auctionator, TSM or Forever-GPS for auction prices)",
                s.priceMode, s.saleMode == "best" and "auction or vendor, whichever pays more" or s.saleMode,
                s.profitScope == "total" and "skinning plus mob loot" or "skinning materials only"))
    end
end
