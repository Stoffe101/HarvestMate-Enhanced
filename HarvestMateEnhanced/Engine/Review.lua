-- HarvestMate Enhanced: Engine/Review.lua (0.6.0)
-- The session review: when a farming session of 10 minutes or more ends, a
-- summary of what it gave and how that compares with what was predicted and
-- with your own recent sessions. Nothing is guessed: what the session did not
-- record (no planned farm, no route) is left out, and gold is called an
-- estimate (auction or vendor prices, not money received).
--
-- It opens by itself only when YOU ended the session (Stop farming, /hme
-- stop) and Settings has "Session review" on; otherwise it waits in the
-- notification list (and /hme review shows the last one).
-- Copyright (C) 2026 HarvestMate Enhanced contributors. GPL-3.0-or-later.

local _, ns = ...
local HME = ns.HME
local U = HME.U

local R = {}
HME.Review = R

R.MIN_SECS = 600

local function Prof(summary)
    local c = summary.counts or {}
    if (c.skin or 0) > 0 or (c.kills or 0) > 0 then return "Skinning", "skins", math.max(c.skin or 0, 0) end
    if (c.fish or 0) > 0 then return "Fishing", "catches", c.fish end
    if (c.herb or 0) + (c.mine or 0) > 0 then return "Gathering", "nodes", (c.herb or 0) + (c.mine or 0) end
    return nil, "gathers", 0
end

-- The review of one finished session (Engine/Session.lua's summary).
-- { title, tiles = { {label, value, sub} x4 }, lines = { ... }, secs }
function R.Build(summary)
    if type(summary) ~= "table" then return nil end
    local farm = summary.farmSecs or summary.secs or 0
    local h = math.max(farm, 1) / 3600
    local prof, noun, count = Prof(summary)
    local out = { secs = farm, lines = {}, tiles = {} }
    out.title = ("%s of %s"):format(U.Duration(farm), prof and prof:lower() or "farming")
    out.tiles[1] = { label = "Farming time", value = U.Duration(farm),
        sub = ("+%s travel"):format(U.Duration(summary.travelSecs or 0)) }
    out.tiles[2] = { label = noun:sub(1, 1):upper() .. noun:sub(2), value = tostring(count), sub = ("%.0f an hour"):format(count / h) }
    out.tiles[3] = { label = "Skill-ups", value = tostring(summary.skillups or 0), sub = ("%.0f an hour"):format((summary.skillups or 0) / h) }
    out.tiles[4] = { label = "Value", value = HME.Kit and HME.Kit.Money(summary.value or 0) or U.Money(summary.value or 0, true),
        sub = "an estimate" }
    -- (Idle time and that the value is prices, not money received, in the lines.)
    -- Materials, most first.
    local items = {}
    for id, q in pairs(summary.items or {}) do items[#items + 1] = { id = id, q = q } end
    table.sort(items, function(a, b) return a.q > b.q end)
    local mats = {}
    for i, it in ipairs(items) do
        if i > 5 then mats[#mats + 1] = ("+%d more"):format(#items - 5) break end
        mats[#mats + 1] = ("%d %s"):format(it.q, ns.ItemNameByID and ns.ItemNameByID(it.id) or ("item " .. it.id))
    end
    if #mats > 0 then out.lines[#out.lines + 1] = "|cff999b8fGathered|r  " .. table.concat(mats, ", ") end
    out.lines[#out.lines + 1] = ("|cff999b8fTime|r  %s farming, %s travel, %s idle (idle is not counted as farming). "
        .. "Value is at auction or vendor prices, not money received."):format(U.Duration(farm), U.Duration(summary.travelSecs or 0),
        U.Duration(summary.idleSecs or 0))
    -- Against the prediction, area by area (counts, never gold).
    for _, a in ipairs(summary.areas or {}) do
        local pred = a.predicted
        local p = HME.Ledger and HME.Ledger.PACE[HME.Ledger.ProfOfKey(a.key) or ""]
        if type(pred) == "table" and p and (a.secs or 0) >= R.MIN_SECS then
            local want = pred[p.pred] or (p.alt and pred[p.alt])
            local got
            if p.pred == "skins" then got = math.max(a.skins or 0, a.beasts or 0)
            elseif p.pred == "catches" then got = a.catches or 0 else got = a.nodes or 0 end
            got = got / (a.secs / 3600)
            if want and want > 0 then
                local r = got / want
                local how = r >= 1.1 and "better than predicted" or (r <= 0.9 and "below the prediction" or "about as predicted")
                out.lines[#out.lines + 1] = ("|cff999b8fPrediction|r  %.0f %s an hour against %.0f predicted: %s (one session; "
                    .. "the ledger weighs it with the others)."):format(got, p.unit, want, how)
            end
        end
    end
    -- Against your recent sessions of the same kind.
    local rates = {}
    for i = #(HME.db and HME.db.sessions or {}), 1, -1 do
        local s = HME.db.sessions[i]
        if s ~= summary and #rates < 10 and (s.farmSecs or 0) >= R.MIN_SECS and Prof(s) == prof then
            rates[#rates + 1] = (s.skillups or 0) / (s.farmSecs / 3600)
        end
    end
    if #rates >= 3 and prof then
        table.sort(rates)
        local mine = (summary.skillups or 0) / h
        local median = rates[math.floor((#rates + 1) / 2)]
        local best = mine >= rates[#rates]
        out.lines[#out.lines + 1] = ("|cff999b8fYour recent sessions|r  %.0f skill-ups an hour against a typical %.0f over the last %d%s."):format(
            mine, median, #rates, best and ": your best of them" or "")
    end
    -- Laps on the route followed.
    if summary.route and HME.Routes and HME.Routes.db then
        for _, route in ipairs(HME.Routes.db.routes or {}) do
            if route.name == summary.route and type(route.lapLog) == "table" then
                local n, total = 0, 0
                for _, l in ipairs(route.lapLog) do
                    if (l.t or 0) >= (summary.t or 0) then n, total = n + 1, total + (l.secs or 0) end
                end
                if n > 0 then
                    out.lines[#out.lines + 1] = ("|cff999b8fRoute|r  %s: %d lap%s, about %s each."):format(route.name, n,
                        n == 1 and "" or "s", U.Duration(total / n))
                end
            end
        end
    end
    -- Goals that moved.
    local moved = {}
    for _, g in ipairs((HME.Goals and HME.Goals.List()) or {}) do
        local got = g.itemID and summary.items and summary.items[g.itemID]
        if got and got > 0 then
            local p = HME.Goals.Progress(g)
            moved[#moved + 1] = ("%s +%d (%d/%d)"):format(g.name or "goal", got, p.have or 0, p.target or 0)
        end
    end
    if #moved > 0 then out.lines[#out.lines + 1] = "|cff999b8fGoals|r  " .. table.concat(moved, ", ") end
    if (summary.deaths or 0) > 0 then
        out.lines[#out.lines + 1] = ("|cfff5a345Deaths|r  %d: marked where, for the risk on your farms."):format(summary.deaths)
    end
    if count == 0 and farm >= R.MIN_SECS then
        out.lines[#out.lines + 1] = "|cfff5a345Nothing recognised|r  no skins, nodes or catches were counted: /hme diag shows what HME saw."
    end
    return out
end

R.last = nil
HME.Listen("SESSION_ENDED", function(summary)
    if not summary or (summary.farmSecs or 0) < R.MIN_SECS then return end
    R.last = summary
    local _, noun, count = Prof(summary)
    local text = ("Session review: %s, %d %s, %d skill-ups."):format(U.Duration(summary.farmSecs), count, noun, summary.skillups or 0)
    if HME.Notify then HME.Notify.Push("session", summary.t or 0, text, { kind = "review", label = "Review", summary = summary }) end
    if summary.reason == "manual" and HME.settings and HME.settings.sessionReview ~= false and R.Show then
        HME.After(0.5, function() HME.Try(R.Show, summary) end)
    end
end)
