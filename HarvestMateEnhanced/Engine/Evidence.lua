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
    local allHours = st and st.hours or 0
    -- "Measured" means this character's own sessions; other characters'
    -- farming here only makes it partly measured.
    local hours, sessions = HME.Learning.Own(r.key)
    local m = r.metrics or {}
    if hours >= 1.5 and sessions >= 2 then
        return { level = "measured", text = ("Measured: %d of your sessions here, %.1f h."):format(sessions, hours) }
    end
    if hours >= 0.1 then
        return { level = "partly measured", text = ("Partly measured: %.1f h of your farming here, blended with the model."):format(hours) }
    end
    if allHours >= 0.1 then
        return { level = "partly measured", text = ("Partly measured by your other characters (%.1f h); your own pace may differ."):format(allHours) }
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

---------------------------------------------------------------------------
-- Separate confidence dimensions. One number would hide that a farm can have
-- well-known spawn points and unknown prices at the same time.
--   spawn        where the nodes or beasts are
--   route        whether the loop can be walked as drawn
--   yield        what each node, beast or cast gives
--   profit       what it is worth (prices)
--   suitability  how well it fits this character (level, skill, pace, risk)
-- Each: { level = "high" | "medium" | "low" | "unknown", why }.
---------------------------------------------------------------------------
E.DIMENSIONS = { "spawn", "route", "yield", "profit", "suitability" }
E.DIM_LABEL = { spawn = "Spawns", route = "Route", yield = "Yield", profit = "Profit", suitability = "Fits you" }

local function D(level, why) return { level = level, why = why } end

local function PlannedRoute(r)
    for _, route in ipairs((HME.Routes and HME.Routes.db and HME.Routes.db.routes) or {}) do
        if route.planned and route.planned.key == r.key then return route end
    end
end

function E.Dimensions(r, goal)
    local m = r.metrics or {}
    local dims = {}
    -- Spawn
    if r.prof == "Fishing" then
        dims.spawn = (m.pools or 0) > 0 and D("low", "pool spots are where pools have been seen: pools move, none is known to be up")
            or D("medium", "open water: no pool spots known")
    elseif r.prof == "Skinning" then
        local seenHere = 0
        for _, t in ipairs(r.targets or {}) do
            local rec = t.npcID and HME.db and HME.db.obs.skins[t.npcID]
            if rec and rec.zones and rec.zones[r.mapID] then seenHere = seenHere + 1 end
        end
        dims.spawn = seenHere > 0 and D("high", ("you skinned %d of these beasts here"):format(seenHere))
            or D("medium", "beast spawns from the bundled data, not yet seen by you here")
    else
        local c = m.confirmedShare or 0
        dims.spawn = c >= 0.5 and D("high", ("%d%% of the sites confirmed"):format(c * 100))
            or c >= 0.2 and D("medium", ("%d%% of the sites confirmed"):format(c * 100))
            or D("low", "spawn points predicted from the bundled data")
    end
    -- Route
    local route = PlannedRoute(r)
    local t = route and HME.Terrain and HME.Terrain.Summary(route)
    local caves = r.caveShare or 0
    if route and route.recorded then
        dims.route = D("high", "recorded in game")
    elseif t and t.state == "full" then
        dims.route = D(caves > 0.2 and "medium" or "high", "every leg follows the walking grid" .. (caves > 0.2 and ", but some nodes are in a cave" or ""))
    elseif t and t.state == "partial" then
        dims.route = D("medium", ("%d of %d legs walked on the grid"):format(t.walked, t.legs))
    elseif r.prof == "Fishing" then
        dims.route = D("unknown", "no loop: you fish from the shore")
    elseif route then
        dims.route = D("low", "straight lines between stops: terrain not checked")
    else
        dims.route = D("unknown", (caves > 0.2 and "some nodes are in a cave; " or "") .. "the loop is planned when you start")
    end
    -- Yield
    local skins, gathers = m.observedSkins or 0, m.yieldGathers or 0
    if r.prof == "Skinning" then
        dims.yield = skins >= 60 and D("high", skins .. " of your skins")
            or skins >= 20 and D("medium", skins .. " of your skins")
            or D("low", "estimated yields until you skin these beasts")
    elseif r.prof == "Fishing" then
        dims.yield = m.basis == "measured" and D("medium", "your catch rate here") or D("low", "catch rate assumed")
    else
        dims.yield = gathers >= 60 and D("high", gathers .. " of your gathers")
            or gathers >= 20 and D("medium", gathers .. " of your gathers")
            or D("low", "typical node yields assumed")
    end
    -- Profit
    if goal == "level" then
        dims.profit = D("unknown", "not used for leveling")
    elseif r.noPrice then
        dims.profit = D("unknown", "no prices known")
    else
        local trust, n, oldest = 0, 0, 0
        for id in pairs(m.items or {}) do
            local rec = HME.Prices.Get(id)
            trust = trust + HME.Prices.Trust(rec)
            n = n + 1
            if rec and rec.age and rec.age > oldest then oldest = rec.age end
        end
        trust = n > 0 and trust / n or 0
        local src = HME.Prices.Available()[1] or "vendor values"
        dims.profit = trust >= 0.7 and D("high", "prices from " .. src)
            or trust >= 0.45 and D("medium", "prices from " .. src .. (oldest > 7 * 86400 and ", some old" or ""))
            or D("low", "vendor values or very few prices")
    end
    -- Suitability
    local why, level = {}, "high"
    if r.prof == "Skinning" then
        if m.killBasis == "measured" then why[#why + 1] = "your kill pace is measured"
        else level = "medium"; why[#why + 1] = "kill pace " .. (m.killBasis or "assumed") end
        for _, tg in ipairs(r.targets or {}) do
            if tg.elite then level = "medium"; why[#why + 1] = "elites among the beasts" break end
        end
    elseif r.prof ~= "Fishing" then
        if (m.skillChance or 0) < 0.3 then level = "medium"; why[#why + 1] = "most nodes are grey for you" end
    end
    if r.risk and r.risk.score >= 0.5 then level = "low"; why[#why + 1] = r.risk.label:lower()
    elseif r.risk and r.risk.score >= 0.3 and level == "high" then level = "medium"; why[#why + 1] = r.risk.label:lower() end
    if #why == 0 then why[1] = "within your level and skill" end
    dims.suitability = D(level, table.concat(why, "; "))
    return dims
end

-- "Spawns: high · Route: unknown · ..." for tooltips and the detail panel.
function E.DimensionText(dims)
    local parts = {}
    for _, k in ipairs(E.DIMENSIONS) do
        local d = dims and dims[k]
        if d then parts[#parts + 1] = ("%s: %s"):format(E.DIM_LABEL[k], d.level) end
    end
    return table.concat(parts, " · ")
end

-- Fills r.evidence, r.metrics.range (gold), r.metrics.skillRange and r.dims.
function E.Apply(r, goal)
    local ev = E.Classify(r)
    r.evidence = ev
    r.metrics.range = E.Range(r, "gph", ev)
    r.metrics.skillRange = E.Range(r, "sph", ev)
    r.dims = E.Dimensions(r, goal)
    return ev
end

function E.RangeText(range, money)
    if not range then return "?" end
    local f = money or function(v) return ("%.0f"):format(v) end
    return ("about %s (%s to %s)"):format(f(range.mid), f(range.low), f(range.high))
end
