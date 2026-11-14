-- HarvestMate Enhanced: Engine/Evidence.lua
-- What a farm's numbers rest on, and a range instead of one figure.
--
-- Evidence levels, strongest first:
--   measured         at least 1.5 hours over 2+ of your sessions in this area
--   partly measured  some of your farming here (6+ minutes), blended with the model
--   known yield      what a node or beast gives is measured (20+ gathers/skins),
--                    but pace, respawns and competition are still assumed
--   published data   rests on published data (bundled spawn and fishing tables)
--                    plus the model's assumptions about pace
--   assumption       mostly the model's assumptions (yields, respawn, pace)
--
-- Ranges (gold/hour, and skill-ups/hour):
--   measured   the 20th, 50th and 80th percentile of your session rates here
--              (weighted by hours), blended with the model by h / (h + 1)
--   otherwise  the model's typical value with a spread set by the evidence:
--              assumption x0.6 to x1.35, published data x0.7 to x1.25,
--              known yield x0.8 to x1.15 (conservative/optimistic prices too)
-- The spreads are honest uncertainty bands, not statistics: the UI shows
-- them as "about X (Y to Z)".
-- Copyright (C) 2026 HarvestMate Enhanced contributors. GPL-3.0-or-later.

local _, ns = ...
local HME = ns.HME
local U = HME.U

local E = {}
HME.Evidence = E

E.SPREAD = {
    assumption = { 0.6, 1.35 },
    ["published data"] = { 0.7, 1.25 },
    ["known yield"] = { 0.8, 1.15 },
    ["partly measured"] = { 0.8, 1.15 },
    measured = { 0.85, 1.12 },
}
E.ORDER = { measured = 1, ["partly measured"] = 2, ["known yield"] = 3, ["published data"] = 4, assumption = 5 }

local function Stats(key) return key and HME.db and HME.db.stats[key] or nil end

function E.Classify(r)
    local st = Stats(r.key)
    local hours, sessions = st and st.hours or 0, st and st.sessions or 0
    local m = r.metrics or {}
    if hours >= 1.5 and sessions >= 2 then
        return { level = "measured", text = ("Measured: %d of your sessions here, %.1f h."):format(sessions, hours) }
    end
    if hours >= 0.1 then
        return { level = "partly measured", text = ("Partly measured: %.1f h of your farming here, blended with the model."):format(hours) }
    end
    if r.prof == "Skinning" and (m.observedSkins or 0) >= 20 then
        return { level = "known yield", text = ("Yields from %d of your skins; kill pace and respawns are still assumed."):format(m.observedSkins) }
    end
    if (r.prof == "Herbalism" or r.prof == "Mining" or r.prof == "Combined") and (m.yieldGathers or 0) >= 20 then
        return { level = "known yield", text = "Node yields from your gathering; how many nodes are up is still assumed." }
    end
    if r.prof == "Fishing" then
        return { level = "published data", text = "Zone skill and fish from Gatherpedia's tables; catch rate assumed." }
    end
    if (r.prof == "Herbalism" or r.prof == "Mining" or r.prof == "Combined") and (m.confirmedShare or 0) >= 0.3 then
        return { level = "published data", text = "Spawn points confirmed by your gathering; node rate assumed." }
    end
    return { level = "assumption", text = r.prof == "Skinning"
        and "Built on assumptions: estimated yields, a 5-minute respawn and a modelled kill pace."
        or "Built on assumptions: spawn points that may be up one in three, an assumed node pace." }
end

-- Weighted quantile of samples { v, w }.
local function WQ(list, q)
    table.sort(list, function(a, b) return a.v < b.v end)
    local total = 0
    for _, e in ipairs(list) do total = total + e.w end
    if total <= 0 then return nil end
    local acc = 0
    for _, e in ipairs(list) do
        acc = acc + e.w
        if acc >= total * q then return e.v end
    end
    return list[#list].v
end

local function Ordered(low, mid, high)
    if low > mid then low, mid = mid, low end
    if mid > high then mid, high = high, mid end
    if low > mid then low, mid = mid, low end
    if high - low < math.max(1, mid * 0.05) then low, high = mid * 0.95, mid * 1.05 end
    if low >= mid then low = mid * 0.97 end
    if high <= mid then high = mid * 1.03 end
    return math.max(0, low), mid, high
end

-- A { low, mid, high } range for a metric ("gph" or "sph").
function E.Range(r, metric, evidence)
    local m = r.metrics or {}
    local mode = (HME.settings and HME.settings.priceMode) or "typical"
    local model
    if metric == "sph" then model = m.skillPerHour or 0
    else model = m.gph and (m.gph[mode] or m.gph.typical) or 0 end
    local spread = E.SPREAD[evidence.level] or E.SPREAD.assumption
    local low, high = model * spread[1], model * spread[2]
    if metric ~= "sph" and m.gph then
        low = math.min(low, (m.gph.conservative or model) * spread[1] / 0.85 * 0.85)
        high = math.max(high, (m.gph.optimistic or model) * spread[2] / 1.1 * 1.0)
    end
    local mid = model
    local st = Stats(r.key)
    local samples = st and st.samples or {}
    local list = {}
    for _, s in ipairs(samples) do
        local v = s[metric]
        if type(v) == "number" and (s.h or 0) > 0 then list[#list + 1] = { v = v, w = s.h } end
    end
    if #list >= 2 then
        local hours = st.hours or 0
        local w = hours / (hours + 1)
        local q20, q50, q80 = WQ(list, 0.2), WQ(list, 0.5), WQ(list, 0.8)
        if #list < 4 then
            -- Few sessions: their middle, with at least the model's spread.
            local half = (q80 - q20) / 2
            local floorHalf = q50 * 0.12
            q20, q80 = q50 - math.max(half, floorHalf), q50 + math.max(half, floorHalf)
        end
        low = w * q20 + (1 - w) * low
        mid = w * q50 + (1 - w) * mid
        high = w * q80 + (1 - w) * high
    end
    low, mid, high = Ordered(low, mid, high)
    return { low = low, mid = mid, high = high, samples = #list }
end

-- Fills r.evidence, r.metrics.range (gold) and r.metrics.skillRange.
function E.Apply(r)
    local ev = E.Classify(r)
    r.evidence = ev
    r.metrics.range = E.Range(r, "gph", ev)
    r.metrics.skillRange = E.Range(r, "sph", ev)
    return ev
end

function E.RangeText(range, money)
    if not range then return "?" end
    local f = money or function(v) return ("%.0f"):format(v) end
    return ("about %s (%s to %s)"):format(f(range.mid), f(range.low), f(range.high))
end
