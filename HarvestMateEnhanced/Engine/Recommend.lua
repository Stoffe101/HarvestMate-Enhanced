-- HarvestMate Enhanced: Engine/Recommend.lua
-- The Farm Finder's ranking. For a profession and a goal it looks at every
-- zone with data, finds the best area in each (Engine/Gathering.lua or
-- Engine/Skinning.lua), estimates what this character gets there, and ranks.
--
-- Goals:
--   level     skill-ups per hour
--   profit    gold per hour (Settings: price estimate, sale mode, scope)
--   material  units of the chosen material(s) per hour
--   balanced  skill-ups and gold, each against the best found
--   safest    usefulness x (1 - risk)^2, with the strictest level limit
--   here      only the zone you are in
--   near      usefulness against travel time
--
-- Every score is per hour of a planned session (Settings: 60 min): getting
-- there takes part of it, so a farm 20 minutes away has to be much better to
-- win. The risk mode (fastest / balanced / lower risk) scales scores by risk
-- (Engine/Risk.lua). Areas you farmed blend in what you measured
-- (Engine/Learning.lua), so an area that keeps under-delivering drops.
-- Node density alone never ranks anything: a dense area of grey nodes scores
-- nothing for leveling, and a valuable rare drop with no evidence is halved.
-- Copyright (C) 2026 HarvestMate Enhanced contributors. GPL-3.0-or-later.

local _, ns = ...
local HME = ns.HME
local U = HME.U
local Geo = HME.Geo
local Z = HME.ZoneData
local Risk = HME.Risk

local R = {}
HME.Recommend = R

R.GOALS = {
    { key = "level", label = "Fastest leveling" },
    { key = "profit", label = "Best gold per hour" },
    { key = "balanced", label = "Balanced: skill and gold" },
    { key = "material", label = "Farm a specific material" },
    { key = "safest", label = "Safest practical farm" },
    { key = "here", label = "In my current zone" },
    { key = "near", label = "Least travel" },
}
-- The number a goal is about, for one result (as the Farm Finder's rows lead with).
function R.GoalValue(r, goal)
    local m = r and r.metrics or {}
    if goal == "material" then return m.materialPerHour or 0 end
    if goal == "profit" then return (m.range and m.range.mid) or 0 end
    if m.skillRange and m.skillRange.mid then return m.skillRange.mid end
    if m.skillPerHour then return m.skillPerHour end
    if m.catchesPerHour then return m.catchesPerHour end
    return (m.range and m.range.mid) or 0
end

-- Practical alternatives to a farm, among the same search's results:
--   safer   clearly lower risk, at least 70% of the goal's number
--   closer  at least five minutes and half the travel saved, at least 80%
-- Risk is one side of the choice, never a ban: these are offered, not ranked
-- above it. nil when nothing qualifies.
R.SAFER_SHARE, R.CLOSER_SHARE = 0.7, 0.8
function R.Alternatives(results, r, goal)
    if not (r and results) then return nil end
    local base = R.GoalValue(r, goal)
    if base <= 0 then return nil end
    local out = {}
    local rs = r.risk and r.risk.score or 0
    if rs >= 0.2 then
        for _, c in ipairs(results) do
            if c ~= r and c.risk and c.risk.score <= rs - 0.15 then
                local share = R.GoalValue(c, goal) / base
                if share >= R.SAFER_SHARE and (not out.safer or share > out.safer.share) then
                    out.safer = { result = c, share = share }
                end
            end
        end
    end
    if r.travel and r.travel >= 300 then
        for _, c in ipairs(results) do
            if c ~= r and c.travel and c.travel <= r.travel * 0.5 and r.travel - c.travel >= 300 then
                local share = R.GoalValue(c, goal) / base
                if share >= R.CLOSER_SHARE and (not out.closer or c.travel < out.closer.result.travel) then
                    out.closer = { result = c, share = share }
                end
            end
        end
    end
    if not (out.safer or out.closer) then return nil end
    return out
end

R.GOAL_LABEL = {}
for _, g in ipairs(R.GOALS) do R.GOAL_LABEL[g.key] = g.label end

R.CONF_LABELS = { { 0.45, "Low" }, { 0.7, "Medium" }, { 2, "High" } }

local function ConfLabel(v)
    for _, l in ipairs(R.CONF_LABELS) do if v < l[1] then return l[2] end end
end
R.ConfLabel = ConfLabel

-- Which underlying goal an area is built for.
local function BaseGoal(goal)
    if goal == "level" or goal == "profit" or goal == "material" then return goal end
    if goal == "safest" or goal == "here" or goal == "near" then return "balanced" end
    return "balanced"
end

local function AreaKey(prof, mapID, cx, cy)
    return ("%s@%d:%d:%d"):format(prof, mapID, math.floor(cx * 20), math.floor(cy * 20))
end
R.AreaKey = AreaKey

-- Beasts near an area, for its creature risk.
local function BeastsNear(mapID, x, y, radiusYards)
    local w, h = Geo.MapYards(mapID)
    w, h = w or 1500, h or 1000
    local out = {}
    for _, b in ipairs(HME.Spawns.BeastPoints(mapID)) do
        local n = 0
        for _, p in ipairs(b.pts) do
            if U.Dist(p[1] * w, p[2] * h, x * w, y * h) <= radiusYards then n = n + 1 end
        end
        if n > 0 then out[#out + 1] = { min = b.min, max = b.max, elite = b.elite, count = n } end
    end
    return out
end
R.BeastsNear = BeastsNear

-- Too far above the character to farm, for the risk mode?
local function LevelBlocked(mapID, profile, mode)
    local lv = Geo.ZoneLevels(mapID)
    if not lv then return false end
    local margin = mode == "safer" and 3 or (mode == "fastest" and 8 or 5)
    return lv[1] > profile.level + margin, lv
end

local function Travel(profile, mapID, x, y)
    if not profile.mapID then return nil, "unknown" end
    local fromMap, fx, fy = Geo.ZoneOf(profile.mapID, profile.x, profile.y)
    return Geo.TravelTime(fromMap, fx, fy, mapID, x, y, { speed = profile.speed, faction = profile.faction,
        fromPlayer = profile.real ~= false })
end

-- Share of a planned session left after travelling there.
local function TimeShare(travelSecs)
    local T = ((HME.settings and HME.settings.sessionMinutes) or 60) * 60
    if not travelSecs then return 0.8 end   -- unknown travel: a flat haircut
    return T / (T + travelSecs)
end
R.TimeShare = TimeShare

---------------------------------------------------------------------------
-- Confidence: 0-1 with reasons.
---------------------------------------------------------------------------
local function Confidence(parts)
    local v, n = 0, 0
    local reasons = {}
    for _, p in ipairs(parts) do
        v = v + p[1] * (p[3] or 1)
        n = n + (p[3] or 1)
        if p[2] then reasons[#reasons + 1] = p[2] end
    end
    v = n > 0 and v / n or 0
    return { value = v, label = ConfLabel(v), reasons = reasons }
end
R.Confidence = Confidence

local function PriceTrust(items)
    local t, n = 0, 0
    for id in pairs(items or {}) do
        local rec = HME.Prices.Get(id)
        t = t + HME.Prices.Trust(rec)
        n = n + 1
    end
    return n > 0 and t / n or 0.4
end

---------------------------------------------------------------------------
-- Gathering (Herbalism, Mining)
---------------------------------------------------------------------------
local function GatherResult(prof, area, profile, query)
    local key = AreaKey(prof, area.mapID, area.cx, area.cy)
    local m = HME.Gathering.Evaluate(area, profile, { key = key })
    if not m then return nil end
    local useful
    if query.goal == "material" then
        local units = 0
        for _, mix in ipairs(m.mix) do
            if query.targets and (query.targets[mix.name] or (mix.itemID and query.targets[mix.itemID])) then
                units = units + m.nodesPerHour * mix.share * (HME.Gathering.PRIOR_QTY[prof] or 1.5)
            end
        end
        m.materialPerHour = units
    end
    local _, exact = Geo.MapYards(area.mapID)
    local items = {}
    for _, mix in ipairs(m.mix) do if mix.itemID then items[mix.itemID] = true end end
    local conf = Confidence({
        { 0.5 + 0.4 * m.confirmedShare, m.confirmedShare > 0.2 and ("%d%% of sites confirmed by you or GatherMate2"):format(m.confirmedShare * 100)
            or "spawn points are predictions from the bundled data" },
        { m.basis == "measured" and 0.85 or 0.45, m.basis == "measured" and "rates include your own farming here"
            or "node rate uses an assumed one-in-three up-fraction" },
        { exact and 0.8 or 0.5, not exact and "zone size from bundled data" or nil, 0.5 },
        { (query.goal == "profit" or query.goal == "balanced") and PriceTrust(items) or 0.7,
          (query.goal == "profit" or query.goal == "balanced") and "prices: " .. (HME.Prices.Available()[1] or "vendor only") or nil },
    })
    local targets = {}
    for _, mix in ipairs(m.mix) do
        local sk = profile.skills[mix.prof or prof]
        targets[#targets + 1] = { name = mix.name, prof = mix.prof, req = mix.req, share = mix.share, chance = mix.chance,
            itemID = mix.itemID, color = HME.SkillModel.Color(sk and sk.rank, mix.req) }
    end
    local res = { key = key, prof = prof, mapID = area.mapID, cx = area.cx, cy = area.cy, area = area, metrics = m,
        confidence = conf, targets = targets, radius = area.radius,
        source = (m.confirmedShare > 0 and "bundled spawns + your gathers" or "bundled spawns (QuestieDB via Gatherpedia)") }
    -- Nodes in a cave: how many, and how many with no known way in (Map/Caves.lua).
    if HME.Caves then res.caveShare, res.caveBlind = HME.Caves.Share(res) end
    return res
end

---------------------------------------------------------------------------
-- Skinning
---------------------------------------------------------------------------
local function SkinResults(mapID, profile, query)
    local goal = BaseGoal(query.goal)
    local areaGoal = (goal == "level" and "level") or (goal == "material" and "material") or "profit"
    local areas = HME.Skinning.Areas(mapID, profile, areaGoal, query.risk, query.targets, query.npcs)
    local out = {}
    -- Up to two circuits per zone, starting from the two best areas.
    local starts = 0
    local used = {}
    for i, a in ipairs(areas) do
        if starts >= 2 then break end
        if not used[a] then
            local circuit = HME.Skinning.Circuit(areas, i, 650, 4)
            for _, c in ipairs(circuit) do used[c] = true end
            local sx, sy, n = 0, 0, 0
            for _, c in ipairs(circuit) do sx, sy, n = sx + c.cx, sy + c.cy, n + 1 end
            local cx, cy = sx / n, sy / n
            local key = AreaKey("Skinning", mapID, cx, cy)
            local m = HME.Skinning.Evaluate(circuit, profile, { key = key, targets = query.targets })
            if m then
                starts = starts + 1
                local targets = {}
                local skill = profile.skills.Skinning.rank
                for _, b in pairs(m.beasts) do
                    local lvl = math.floor((b.beast.min + b.beast.max) / 2 + 0.5)
                    targets[#targets + 1] = { name = b.beast.name, npcID = b.beast.npcID, min = b.beast.min, max = b.beast.max,
                        req = b.elig.req, reqMin = b.elig.reqMin, skinShare = b.elig.skinShare, chance = b.elig.chance,
                        count = b.count, elite = b.beast.elite,
                        color = HME.SkillModel.Color(skill, HME.SkillModel.SkinReq(lvl)), skinnable = b.elig.skinnable }
                end
                table.sort(targets, function(x, y) return x.count > y.count end)
                local radius = 0
                for _, c in ipairs(circuit) do
                    local d = U.Dist(c.yx, c.yy, circuit[1].yx, circuit[1].yy) + c.radius
                    if d > radius then radius = d end
                end
                local conf = Confidence({
                    { 0.6, "beast spawns from the bundled data (QuestieDB, Forever build)" },
                    { m.yieldBasis == "measured" and math.min(0.9, 0.5 + m.observedSkins / 60) or 0.3,
                      m.yieldBasis == "measured" and (m.observedSkins .. " of your skins inform the yields")
                      or "yields are estimates until you skin here" },
                    { m.killBasis == "measured" and 0.85 or (m.killBasis == "partly measured" and 0.6 or 0.4),
                      "kill time: " .. m.killBasis },
                    { 0.45, m.limit == "respawn" and "limited by an assumed 5-minute respawn" or "respawn time is assumed", 0.5 },
                    { (goal ~= "level") and PriceTrust(m.items) or 0.7,
                      goal ~= "level" and ("prices: " .. (HME.Prices.Available()[1] or "vendor only")) or nil },
                })
                out[#out + 1] = { key = key, prof = "Skinning", mapID = mapID, cx = cx, cy = cy, circuit = circuit,
                    metrics = m, confidence = conf, targets = targets, radius = radius,
                    source = "bundled beast spawns (QuestieDB via Gatherpedia)" }
            end
        end
    end
    return out
end

---------------------------------------------------------------------------
-- Fishing
---------------------------------------------------------------------------
local function FishResult(mapID, profile, query)
    local m = HME.Gathering.EvaluateFishing(mapID, profile, { key = "Fishing@" .. mapID, targets = query and query.targets })
    if not m or m.tooLow then return nil end
    -- Where to stand: the zone's pools if known, else the zone centre.
    local cx, cy, n = 0, 0, 0
    for _, e in ipairs(HME.Spawns.DbNodes("Fishing", mapID)) do
        U.EachPacked(e[4], function(x, y) cx, cy, n = cx + x, cy + y, n + 1 end)
    end
    if n > 0 then cx, cy = cx / n, cy / n else cx, cy = 0.5, 0.5 end
    local items = {}
    for _, f in ipairs(m.fish or {}) do items[f.id] = true end
    local conf = Confidence({
        { 0.6, "zone fishing skill from Gatherpedia's table" },
        { m.basis == "measured" and 0.85 or 0.4, m.basis == "measured" and "catch rate measured" or "catch rate assumed (18 s a cast)" },
        { PriceTrust(items), "fish value averaged over the zone's catch list" },
    })
    return { key = "Fishing@" .. mapID, prof = "Fishing", mapID = mapID, cx = cx, cy = cy, metrics = m, confidence = conf,
        targets = m.fish or {}, pools = m.pools, source = "Gatherpedia fishing data" }
end

---------------------------------------------------------------------------
-- Scoring
---------------------------------------------------------------------------
local function Usefulness(r, goal, priceMode)
    local m = r.metrics
    local gph = m.range and m.range.mid or (m.gph and (m.gph[priceMode] or m.gph.typical) or 0)
    if goal == "level" then return m.skillRange and m.skillRange.mid or m.skillPerHour or 0 end
    if goal == "profit" then return gph end
    if goal == "material" then return m.materialPerHour or 0 end
    return nil
end

-- Ranks results in place and returns them.
function R.Score(results, query, profile)
    local priceMode = (HME.settings and HME.settings.priceMode) or "typical"
    local mode = query.risk or (HME.settings and HME.settings.riskMode) or "balanced"
    local maxSkill, maxGold = 0, 0
    for _, r in ipairs(results) do
        local m = r.metrics
        r.shareApplied = nil
        r.share = TimeShare(r.travel)
        local sk = (m.skillPerHour or 0) * r.share
        local gp = (m.gph and (m.gph[priceMode] or m.gph.typical) or 0) * r.share
        if sk > maxSkill then maxSkill = sk end
        if gp > maxGold then maxGold = gp end
    end
    for _, r in ipairs(results) do
        local m = r.metrics
        local goal = query.goal
        local base = Usefulness(r, goal, priceMode)
        if not base then
            local sk = maxSkill > 0 and (m.skillPerHour or 0) * r.share / maxSkill or 0
            local gp = maxGold > 0 and (m.gph and (m.gph[priceMode] or m.gph.typical) or 0) * r.share / maxGold or 0
            local skillMatters = false
            for _, p in ipairs(HME.Gathering.Profs(r.prof)) do
                if profile.skills[p] and profile.skills[p].rank < 300 then skillMatters = true end
            end
            base = skillMatters and (0.5 * sk + 0.5 * gp) or gp
            r.shareApplied = true
        end
        if not r.shareApplied and goal ~= "near" then base = base * r.share end
        local riskScore = r.risk and r.risk.score or 0.3
        local penalty = Risk.Penalty(riskScore, goal == "safest" and "safer" or mode)
        local score = base * penalty
        if goal == "safest" then score = base * (1 - riskScore) ^ 2 end
        if goal == "near" then score = base / (1 + (r.travel or 600) / 600) end
        -- Uncertain profit counts for less: a low-confidence estimate cannot
        -- outrank a well-known farm on a lucky guess.
        if goal == "profit" or goal == "balanced" then score = score * (0.7 + 0.3 * r.confidence.value) end
        -- Measured beats assumed when the estimates are close.
        local EV = { measured = 1, ["partly measured"] = 0.97, ["known yield"] = 0.94, ["published data"] = 0.9, assumption = 0.87 }
        score = score * (EV[r.evidence and r.evidence.level or "assumption"] or 0.87)
        if r.sizeUnknown then score = score * 0.75 end
        -- Valuable ore in a cave nobody can say how to reach is not an excellent farm.
        if (r.caveBlind or 0) > 0 then score = score * (1 - 0.35 * r.caveBlind) end
        -- Your marks (crowded, inefficient) and your open goals.
        if r.correction and r.correction.mult then score = score * r.correction.mult end
        r.forGoal = nil
        local needed = HME.Goals and HME.Goals.Needed() or {}
        for id in pairs(m.items or {}) do
            if needed[id] then r.forGoal = needed[id].goal break end
        end
        if not r.forGoal then
            for _, t in ipairs(r.targets or {}) do
                if t.itemID and needed[t.itemID] then r.forGoal = needed[t.itemID].goal break end
            end
        end
        if r.forGoal and goal ~= "material" then score = score * 1.08 end
        -- No price known at all (no auction addon, item data not loaded yet):
        -- still list the farm, ranked by how much it yields, and say so.
        r.noPrice = nil
        if (goal == "profit" or goal == "balanced") and score <= 0 then
            local units = m.materialPerHour or m.beastsPerHour or m.nodesPerHour or m.catchesPerHour or 0
            if units > 0 then
                score = units * 1e-6 * penalty
                r.noPrice = true
            end
        end
        r.score = score
        r.scoreBase = base
        r.riskPenalty = penalty
    end
    table.sort(results, function(a, b) return a.score > b.score end)
    return results
end

-- Smart filters: { continent = "E"|"K"|"F", maxRisk = 0-1, minConfidence =
-- "Low"|"Medium"|"High", maxTravel = seconds, zone = name }. Returns why a
-- result is left out, or nil.
local CONF = { Low = 1, Medium = 2, High = 3 }
function R.Filtered(r, f)
    if not f then return nil end
    local z = HME.ZoneData.Get(r.mapID)
    if f.continent and z and z.cont ~= f.continent then return "another continent" end
    if f.maxRisk and r.risk and r.risk.score > f.maxRisk then return "above your risk limit" end
    if f.minConfidence and CONF[r.confidence.label] < (CONF[f.minConfidence] or 1) then return "below your confidence limit" end
    if f.maxTravel and (not r.travel or r.travel > f.maxTravel) then return "too far" end
    if f.zone and r.zone ~= f.zone then return "another zone" end
    return nil
end

-- One plain sentence on why this farm is suggested, and what to watch.
function R.Summary(r, query, profile, all)
    local m = r.metrics
    local good, warn = {}, {}
    local goal = query.goal
    if r.noPrice then warn[1] = "no prices known yet, so this is ranked by how much it yields" end
    if r.forGoal then good[#good + 1] = ("you need it for your goal %s"):format(r.forGoal.name or "") end
    -- Your own sessions here, compared with the estimate.
    local model = m.range and m.range.mid
    local ratio, sure = HME.Learning.Verdict(r.key, "value", model)
    if ratio and sure and ratio >= 1.1 then good[#good + 1] = "it did better than estimated in your previous sessions"
    elseif ratio and sure and ratio <= 0.8 then warn[#warn + 1] = "your previous sessions here fell short of the estimate" end
    -- Cheaper to reach than the best earner, when that is the trade-off.
    local top
    for _, o in ipairs(all or {}) do
        if o ~= r and o.metrics.range and (not top or o.metrics.range.mid > top.metrics.range.mid) then top = o end
    end
    if top and r.travel and top.travel and r.travel < top.travel * 0.6 and model and model < top.metrics.range.mid
        and (goal == "profit" or goal == "balanced") then
        good[#good + 1] = ("less travel than the top earner in %s"):format(top.zone or "?")
    end
    local d = r.dims
    if d and d.route and d.route.level == "low" then warn[#warn + 1] = "the route may cross unchecked terrain" end
    if d and d.yield and d.yield.level == "low" and d.profit and d.profit.level ~= "unknown" and (goal == "profit" or goal == "material") then
        warn[#warn + 1] = "drop estimates are uncertain"
    end
    if (r.caveBlind or 0) > 0.2 then
        warn[#warn + 1] = ("%d%% of the nodes are in a cave with no known entrance (Shift+right-click one on the map at the mouth)"):format(r.caveBlind * 100)
    elseif (r.caveShare or 0) > 0.2 then
        warn[#warn + 1] = ("%d%% of the nodes are in a cave"):format(r.caveShare * 100)
    end
    for _, n in ipairs((r.correction and r.correction.notes) or {}) do warn[#warn + 1] = n end
    if r.prof == "Skinning" then
        local n, top = 0, nil
        for _, t in ipairs(r.targets or {}) do
            n = n + 1
            top = top or t
        end
        if (m.skillChance or 0) > 0.6 and goal ~= "profit" then good[#good + 1] = "the beasts still give skill-ups most of the time" end
        if top then good[#good + 1] = ("%s (level %d-%d) are within your reach"):format(top.name, top.min, top.max) end
        if #(r.circuit or {}) > 1 then good[#good + 1] = ("they form %d hunting areas close together"):format(#r.circuit) end
        if m.limit == "respawn" then warn[#warn + 1] = "respawns, not your pace, limit it" end
    elseif r.prof == "Fishing" then
        good[#good + 1] = ("your skill lands catches here (zone needs %d)"):format(m.zoneMin or 0)
        if (m.pools or 0) > 0 then good[#good + 1] = "there are known pools" end
    else
        if (m.skillChance or 0) > 0.6 and goal ~= "profit" then good[#good + 1] = "most nodes here still give skill-ups" end
        if (m.confirmedShare or 0) > 0.3 then good[#good + 1] = "many spawn points are confirmed by your own gathering" end
        if m.respawnCapped then warn[#warn + 1] = "the loop is short, so you'll wait for nodes" end
        if r.prof == "Combined" then
            good[#good + 1] = "herbs and ore together on one loop"
            if r.combined and r.combined.better == false then warn[#warn + 1] = r.combined.text end
            -- The game tracks one of Find Herbs / Find Minerals at a time.
            warn[#warn + 1] = "only one of Find Herbs or Find Minerals tracks at a time: switch it yourself if you like"
        end
    end
    if r.travel and r.travel < 300 then good[#good + 1] = "it is close by" end
    if r.travel and r.travel > 1200 then warn[#warn + 1] = ("the trip takes about %s"):format(U.Duration(r.travel)) end
    if not r.travel then warn[#warn + 1] = "travel time unknown" end
    if r.evidence and r.evidence.level == "assumption" then warn[#warn + 1] = "the numbers are estimates, not yet measured" end
    if m.gph and (goal == "profit" or goal == "balanced") then
        local rec
        for id in pairs(m.items or {}) do rec = rec or HME.Prices.Get(id) end
        if not (rec and rec.source) then warn[#warn + 1] = "no auction prices: vendor values only"
        elseif rec.age and rec.age > 7 * 86400 then warn[#warn + 1] = "auction data is old" end
    end
    if r.risk and r.risk.score >= 0.4 then warn[#warn + 1] = r.risk.label:lower() end
    local s = "Good choice"
    if #good > 0 then s = s .. " because " .. table.concat(good, ", ", 1, math.min(3, #good)) end
    s = s .. "."
    if #warn > 0 then s = s .. " Watch: " .. table.concat(warn, "; ", 1, math.min(3, #warn)) .. "." end
    return s
end

-- Side by side: rows of the chosen results with the figures to compare, and
-- per column which is best, where "best" is only claimed when the data
-- behind it is at least partly measured or the margin is large (25%+):
-- a weakly supported top figure is shown as "highest estimate", not best.
R.COMPARE_COLUMNS = {
    { key = "skill", label = "Skill-ups/h", get = function(r) return r.metrics.skillRange and r.metrics.skillRange.mid end },
    { key = "gold", label = "Gold/h (farming)", get = function(r) return r.metrics.range and r.metrics.range.mid end, money = true },
    { key = "trip", label = "Gold/h (trip)", get = function(r) return r.tripGph end, money = true },
    { key = "units", label = "Materials/h", get = function(r) return r.metrics.materialPerHour or r.metrics.nodesPerHour or r.metrics.beastsPerHour end },
    { key = "travel", label = "Travel", get = function(r) return r.travel end, lower = true, duration = true },
    { key = "risk", label = "Risk", get = function(r) return r.risk and r.risk.score end, lower = true },
    { key = "loop", label = "Route length", get = function(r) return r.metrics.loopYards end, lower = true },
    { key = "perSkin", label = "Gold/skin", get = function(r) return r.effort and r.effort.perSkin end, money = true },
    { key = "perKill", label = "Gold/kill", get = function(r) return r.effort and r.effort.perKill end, money = true },
    { key = "perTrip", label = "Gold/trip", get = function(r) return r.effort and r.effort.perTrip end, money = true },
}

-- Profit per effort: gold per skin, per kill, per node and per whole trip
-- (the planned play time with the travel there), for comparing farms by
-- more than gold an hour. Fills r.effort.
function R.Effort(r)
    local m = r.metrics
    local gph = m.range and m.range.mid or 0
    local e = {}
    local skins = m.skinsPerHour or (m.beastsPerHour and m.beastsPerHour * (m.skinShare or 1))
    if gph <= 0 then gph = nil end      -- no prices: no gold per anything, rather than a false zero
    if not gph then
        e.skillPerTrip = (m.skillRange and m.skillRange.mid or m.skillPerHour or 0) * (((HME.settings and HME.settings.sessionMinutes) or 60) / 60)
        e.materialPerHour = m.materialPerHour
        r.effort = e
        return e
    end
    if r.prof == "Skinning" then
        if skins and skins > 0 then e.perSkin = (m.skinGph or gph) / skins end
        if m.beastsPerHour and m.beastsPerHour > 0 then e.perKill = gph / m.beastsPerHour end
    elseif m.nodesPerHour and m.nodesPerHour > 0 then
        e.perNode = gph / m.nodesPerHour
    end
    local minutes = (HME.settings and HME.settings.sessionMinutes) or 60
    local hours = minutes / 60
    e.perTrip = gph * hours
    e.tripHours = hours + (r.travel or 0) / 3600
    e.skillPerTrip = (m.skillRange and m.skillRange.mid or m.skillPerHour or 0) * hours
    e.materialPerHour = m.materialPerHour
    r.effort = e
    return e
end

function R.Compare(results)
    local out = { rows = results, best = {}, notes = {} }
    for _, col in ipairs(R.COMPARE_COLUMNS) do
        local best, second, bv, sv
        for i, r in ipairs(results) do
            local v = col.get(r)
            if v then
                local better = not bv or (col.lower and v < bv) or (not col.lower and v > bv)
                if better then second, sv = best, bv; best, bv = i, v
                elseif not sv or (col.lower and v < sv) or (not col.lower and v > sv) then second, sv = i, v end
            end
        end
        if best then
            local r = results[best]
            local strong = r.evidence and HME.Evidence.ORDER[r.evidence.level] <= 2
            local margin = sv and bv and sv ~= 0 and math.abs(bv - sv) / math.abs(sv) or 1
            out.best[col.key] = { index = best, sure = strong or margin >= 0.25 or col.key == "travel" or col.key == "risk" or col.key == "loop" }
            if not out.best[col.key].sure then
                out.notes[#out.notes + 1] = ("%s: %s has the highest estimate, but it is not measured and the lead is small."):format(
                    col.label, r.zone)
            end
        end
    end
    return out
end

-- Is one combined loop worth it against two loops of half the time each?
-- Compares nodes an hour per profession. Fills r.combined { better, text }.
function R.CombinedCheck(r, profile)
    if r.prof ~= "Combined" or not r.area then return nil end
    profile = profile or HME.Player.Profile()
    local per = {}
    for _, mix in ipairs(r.metrics.mix or {}) do
        per[mix.prof] = (per[mix.prof] or 0) + r.metrics.nodesPerHour * mix.share
    end
    local alone = {}
    for _, p in ipairs(HME.Gathering.COMBINED) do
        local areas = HME.Gathering.Areas(p, r.mapID, profile, "balanced", {})
        local m = areas[1] and HME.Gathering.Evaluate(areas[1], profile, {})
        alone[p] = m and m.nodesPerHour or 0
    end
    local herbs, ore = per.Herbalism or 0, per.Mining or 0
    local split = (alone.Herbalism + alone.Mining) / 2
    local together = herbs + ore
    local better = together >= split * 0.95
    r.combined = { better = better, herbs = herbs, ore = ore, aloneHerbs = alone.Herbalism, aloneOre = alone.Mining,
        text = better and ("one loop gives about %.0f herbs and %.0f ore an hour, more than two separate loops (%.0f nodes an hour)"):format(herbs, ore, split)
            or ("two separate loops would give more here (%.0f vs %.0f nodes an hour)"):format(split, together) }
    return r.combined
end

-- Why this result ranks where it does, in short lines.
function R.Explain(r, query)
    local m = r.metrics
    local lines = {}
    local priceMode = (HME.settings and HME.settings.priceMode) or "typical"
    if m.skillPerHour then lines[#lines + 1] = ("about %.0f skill-ups an hour"):format(m.skillPerHour) end
    if m.gph then lines[#lines + 1] = ("about %s an hour (%s prices)"):format(U.Money(m.gph[priceMode] or 0, true), priceMode) end
    if m.beastsPerHour then
        lines[#lines + 1] = ("about %.0f beasts an hour, %s"):format(m.beastsPerHour,
            m.limit == "respawn" and "limited by respawns" or "limited by your pace")
    end
    if m.nodesPerHour then lines[#lines + 1] = ("about %.0f nodes an hour"):format(m.nodesPerHour) end
    if r.travel then
        lines[#lines + 1] = ("%s away (%s)"):format(U.Duration(r.travel), r.travelQuality or "estimate")
    else
        lines[#lines + 1] = "travel time unknown"
    end
    if r.risk then lines[#lines + 1] = r.risk.label .. ": " .. table.concat(r.risk.reasons, "; ") end
    return lines
end

---------------------------------------------------------------------------
-- The search
---------------------------------------------------------------------------
-- query = { prof, goal, targets, risk, limit, mapID (for "here") }
-- Runs as a background job; done(results) gets the ranked list.
function R.Find(query, done, profile)
    profile = profile or HME.Player.Profile()
    query.risk = query.risk or (HME.settings and HME.settings.riskMode) or "balanced"
    local prof = query.prof
    local maps
    if query.maps then
        maps = query.maps        -- a fixed list (the Skinning Explorer's "Hunt this creature")
    elseif query.goal == "here" then
        local here = profile.mapID and Geo.ZoneOf(profile.mapID)
        maps = { here }
    else
        if prof == "Combined" then
            local seen = {}
            maps = {}
            for _, p in ipairs(HME.Gathering.COMBINED) do
                for _, id in ipairs(HME.Spawns.Maps(p)) do
                    if not seen[id] then seen[id] = true maps[#maps + 1] = id end
                end
            end
        else
            maps = HME.Spawns.Maps(prof == "Fishing" and "Fishing" or prof)
        end
        if prof == "Fishing" then
            -- Open water counts too: every zone with a fishing skill.
            local seen = {}
            for _, id in ipairs(maps) do seen[id] = true end
            for id, z in pairs(Z.ZONES) do
                if not seen[id] and not z.city and not z.upcoming then maps[#maps + 1] = id end
            end
        end
    end
    local avoid = (HME.settings and HME.settings.avoidZones) or {}
    local function work()
        local results = {}
        local skipped = {}
        for _, mapID in ipairs(maps) do
            local z = Z.Get(mapID)
            local name = Z.Name(mapID)
            local blocked, lv = LevelBlocked(mapID, profile, query.risk)
            if avoid[name] then
                skipped[#skipped + 1] = { mapID = mapID, why = "you excluded this zone" }
            elseif z and z.city then
                -- never a farm
            elseif z and z.upcoming then
                skipped[#skipped + 1] = { mapID = mapID, why = "not released yet" }
            elseif blocked and query.goal ~= "here" then
                skipped[#skipped + 1] = { mapID = mapID, why = ("creatures level %d+, too high for %d"):format(lv[1], profile.level) }
            else
                local found = {}
                if prof == "Skinning" then
                    found = SkinResults(mapID, profile, query)
                elseif prof == "Fishing" then
                    local r = FishResult(mapID, profile, query)
                    if r then found = { r } end
                else
                    local areas = HME.Gathering.Areas(prof, mapID, profile, BaseGoal(query.goal), { targets = query.targets })
                    for _, a in ipairs(areas) do
                        local r = GatherResult(prof, a, profile, query)
                        if r then found[#found + 1] = r end
                    end
                end
                for _, r in ipairs(found) do
                    r.zone = name
                    r.levels = lv
                    r.subarea = Geo.Compass(r.cx, r.cy)
                    r.travel, r.travelQuality = Travel(profile, mapID, r.cx, r.cy)
                    r.risk = Risk.Assess({ mapID = mapID, x = r.cx, y = r.cy, radius = r.radius or 150,
                        beasts = BeastsNear(mapID, r.cx, r.cy, (r.radius or 150) + 60) }, profile)
                    -- No size from the client or the bundled table: distances and
                    -- density are guesses (a 1500 x 1000 default), so say so.
                    if not Geo.MapYards(mapID) then
                        r.sizeUnknown = true
                        r.confidence.value = r.confidence.value * 0.7
                        r.confidence.label = ConfLabel(r.confidence.value)
                        table.insert(r.confidence.reasons, "this zone's size is unknown here, so density and distances are rough")
                    end
                    -- Your corrections near this farm (Engine/Corrections.lua).
                    local corr = HME.Corrections and HME.Corrections.ForArea(mapID, r.cx, r.cy)
                    if corr then
                        r.correction = corr
                        if corr.risk > 0 then
                            r.risk.score = math.min(1, r.risk.score + corr.risk)
                            table.insert(r.risk.reasons, 1, "you marked it dangerous")
                        end
                    end
                    -- Your past sessions against their predictions (Engine/Ledger.lua).
                    if HME.Ledger then HME.Ledger.Calibrate(r) end
                    HME.Evidence.Apply(r, query.goal)
                    r.tripShare = TimeShare(r.travel)
                    r.tripGph = r.metrics.range.mid * r.tripShare
                    R.Effort(r)
                    local why = R.Filtered(r, query.filters)
                    if corr and corr.exclude then
                        skipped[#skipped + 1] = { mapID = mapID, why = corr.exclude }
                    elseif r.risk.parts.avoided then
                        skipped[#skipped + 1] = { mapID = mapID, why = "avoided" }
                    elseif why then
                        skipped[#skipped + 1] = { mapID = mapID, why = why }
                    else
                        results[#results + 1] = r
                    end
                end
            end
            HME.Yield()
        end
        R.Score(results, query, profile)
        -- Results with nothing to give for this goal go.
        local kept = {}
        for _, r in ipairs(results) do
            if r.score > 0 and #kept < (query.limit or 12) then kept[#kept + 1] = r end
        end
        for i, r in ipairs(kept) do
            r.rank = i
            if r.prof == "Combined" and i <= 3 then HME.Try(R.CombinedCheck, r, profile) end
            r.dims = HME.Evidence.Dimensions(r, query.goal)
            r.reputation = HME.Learning.Reputation(r.key, { value = r.metrics.range and r.metrics.range.mid,
                gph = r.metrics.range and r.metrics.range.mid })
            r.why = R.Explain(r, query)
            r.summary = R.Summary(r, query, profile, kept)
        end
        return kept, skipped
    end
    if done then
        return HME.RunJob("finder:" .. prof .. ":" .. query.goal, work, done, { key = "finder" })
    end
    return work()
end
