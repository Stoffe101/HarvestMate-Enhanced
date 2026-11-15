-- HarvestMate Enhanced: Engine/Copilot.lua (0.6.0)
-- The Farming Copilot: what to do next, why, how sure, and one click to do it.
--
-- No AI model and no network: rules over what HME already knows (your
-- character, professions, goals, position, session, the Farm Finder's
-- ranked farms, the prediction ledger, your quests and bags).
--
-- Each rule proposes CARDS:
--   id          stable key (the same advice keeps its id, so cooldowns and
--               "not now" hold across re-evaluations)
--   type        farm, stay, switch, train, goal, quest, bags, grey, prices,
--               learned, setup
--   group       cards of one group contradict each other; only the best is
--               kept (where = "where should I farm": farm, stay, switch)
--   title, objective, why = { lines }, evidence (text), conf (0-1), benefit
--   (value, text), priority (0-100), action = { kind, label, ... },
--   secondary actions, expires (seconds; nil = until the context changes)
-- The ARBITER drops what you dismissed ("Not now": 6 hours for that card;
-- "Not interested": that type until you reset it in Settings), keeps one card
-- per group, and holds the farm it suggested for 15 minutes unless another
-- becomes 15% better or the context changes (skill bracket, zone, goal,
-- mode): no ping-pong between two farms.
--
-- Searches are Farm Finder searches (background jobs, cached for 10 minutes
-- or until skill, level, zone, goals or mode change). Nothing here runs on a
-- frame: evaluation happens on events, at most every few seconds.
-- Copyright (C) 2026 HarvestMate Enhanced contributors. GPL-3.0-or-later.

local _, ns = ...
local HME = ns.HME
local U = HME.U

local C = {}
HME.Copilot = C

C.MODES = {
    { key = "level", label = "Level fastest", goal = "level", tip = "Most skill-ups an hour, travel counted." },
    { key = "profit", label = "Most gold", goal = "profit", tip = "Most estimated value an hour (auction or vendor prices)." },
    { key = "material", label = "A material", goal = "material", tip = "What your open material goals still need." },
    { key = "balanced", label = "Balanced", goal = "balanced", tip = "Skill-ups and gold together." },
    { key = "safe", label = "Lower risk", goal = "safest", tip = "Farms with less danger from creatures and the other side, for a smaller share of the number." },
    { key = "short", label = "Short session", goal = "near", tip = "What you get in the time you have, after the trip there." },
    { key = "quest", label = "With my quests", goal = "balanced", tip = "Farms whose creatures or nodes also progress quests in your log." },
    { key = "proven", label = "My proven farms", goal = "balanced", tip = "Only farms you measured yourself, ranked by what you got." },
    { key = "explore", label = "Explore", goal = "balanced", tip = "Promising farms nobody has measured: the upside, labelled as a guess." },
}
C.MODE = {}
for _, m in ipairs(C.MODES) do C.MODE[m.key] = m end
C.BUDGETS = { 15, 30, 60, 120, 0 }       -- minutes; 0 = no limit (the Settings session length)

C.CACHE_SECS = 600
C.HOLD_SECS = 900
C.SWITCH_MARGIN = 1.15
C.NOT_NOW = 6 * 3600
C.MIN_SWITCH_SECS = 15 * 60              -- farm this long before a switch is suggested
C.UNKNOWN_TRAVEL = 1200

-- How much an evidence level is trusted when choosing between farms.
C.TRUST = { measured = 1, ["partly measured"] = 0.95, ["known yield"] = 0.9, ["published data"] = 0.85, assumption = 0.8 }

---------------------------------------------------------------------------
-- State (per character)
---------------------------------------------------------------------------
local function St()
    local c = HME.char
    if not c then return { dismissed = {}, notInterested = {} } end
    if type(c.copilot) ~= "table" then c.copilot = {} end
    local s = c.copilot
    if type(s.dismissed) ~= "table" then s.dismissed = {} end
    if type(s.notInterested) ~= "table" then s.notInterested = {} end
    if not C.MODE[s.mode or ""] then s.mode = nil end
    if type(s.minutes) ~= "number" then s.minutes = nil end
    return s
end
C.State = St

function C.Mode() return St().mode or "level" end
function C.Minutes()
    local m = St().minutes
    if m == nil then return C.Mode() == "short" and 30 or 0 end
    return m
end
-- Seconds of play the plan is for (no limit: the Settings session length).
function C.Budget()
    local m = C.Minutes()
    if m and m > 0 then return m * 60, true end
    return ((HME.settings and HME.settings.sessionMinutes) or 60) * 60, false
end

function C.SetMode(mode)
    if not C.MODE[mode] then return end
    St().mode = mode
    C.Invalidate("mode")
end
function C.SetMinutes(m)
    St().minutes = m
    C.Invalidate("budget")
end
function C.SetProf(prof)
    St().prof = prof ~= "auto" and prof or nil
    C.Invalidate("prof")
end

---------------------------------------------------------------------------
-- Context
---------------------------------------------------------------------------
local LEARNABLE = { "Skinning", "Herbalism", "Mining", "Fishing" }

-- The profession the Copilot plans for: your pick, else the farm you follow,
-- else what an open goal needs (material mode), else the one furthest from
-- its cap that is still below 300, else any you have.
function C.FocusProf(profile)
    profile = profile or HME.Player.Profile()
    local pick = St().prof
    if pick and profile.skills[pick] then return pick, "your choice" end
    local g = HME.Guidance and HME.Guidance.Active()
    if g and g.prof and profile.skills[g.prof] then return g.prof, "the farm you follow" end
    if C.Mode() == "material" then
        for id in pairs(HME.Goals.Needed()) do
            local p = HME.Goals.ProfOf(id)
            if p and profile.skills[p] then return p, "your material goal" end
        end
    end
    local best, gap
    for _, p in ipairs(LEARNABLE) do
        local s = profile.skills[p]
        if s and s.rank < 300 then
            local d = (300 - s.rank) * (p == "Fishing" and 0.5 or 1)
            if not gap or d > gap then best, gap = p, d end
        end
    end
    if best then return best, "furthest from 300" end
    for _, p in ipairs(LEARNABLE) do if profile.skills[p] then return p, "a profession you have" end end
    return nil, "no gathering profession"
end

-- What the Finder is asked for in a mode.
function C.Query(mode, prof, profile)
    local m = C.MODE[mode] or C.MODE.level
    local q = { prof = prof, goal = m.goal, limit = 12 }
    if mode == "safe" then q.risk = "safer" end
    if mode == "short" then
        local s = profile.skills[prof]
        q.goal = (s and s.rank >= 300) and "profit" or "level"
        q.limit = 16
    end
    if mode == "material" then
        q.targets = {}
        for id in pairs(HME.Goals.Needed()) do
            if HME.Goals.ProfOf(id) == prof then q.targets[id] = true end
        end
        if not next(q.targets) then q.targets = nil q.goal = "profit" q.noMaterial = true end
    end
    if mode == "quest" or mode == "explore" or mode == "proven" then q.limit = 20 end
    return q
end

local function Sig(profile, prof, mode)
    local s = prof and profile.skills[prof]
    local zone = profile.mapID and HME.Geo.ZoneOf(profile.mapID) or 0
    return table.concat({ tostring(prof), mode, tostring(profile.level), s and math.floor(s.rank / 5) or "-",
        s and s.max or "-", tostring(zone), tostring(C.Minutes()), tostring(HME.Copilot.goalsVersion or 0) }, "|")
end

---------------------------------------------------------------------------
-- Searches
---------------------------------------------------------------------------
C.searches = {}        -- [sig] = { results, at, query }
C.goalsVersion = 0
local pending = {}

-- Queued searches for a context that is gone are dropped before they run
-- (one that already started finishes; its result is simply not used).
C.MAX_CACHED = 8
local function DropQueued()
    local q = HME.Jobs and HME.Jobs.queue or {}
    for i = #q, 1, -1 do
        local key = q[i].key
        if type(key) == "string" and key:sub(1, 8) == "copilot:" then
            pending[key:sub(9)] = nil
            table.remove(q, i)
        end
    end
end
C.DropQueued = DropQueued

function C.Invalidate(why)
    if why == "goals" then C.goalsVersion = C.goalsVersion + 1 end
    if why ~= "budget" then
        C.searches = {}
        DropQueued()
    end
    C.Evaluate(true)
end

local function Search(sig, query, profile)
    local hit = C.searches[sig]
    if hit and HME.Now() - hit.at < C.CACHE_SECS then return hit.results, "ready" end
    if pending[sig] then return hit and hit.results, "searching" end
    pending[sig] = true
    -- Its own job (not the Farm Finder's "finder" slot): a Copilot search never
    -- replaces the search you started on the Farm Finder page, and vice versa.
    HME.RunJob("copilot", function() return HME.Recommend.Find(query, nil, profile) end, function(results)
        pending[sig] = nil
        C.searches[sig] = { results = results or {}, at = HME.Now(), query = query }
        -- Bounded: the oldest go past MAX_CACHED.
        -- (Never the one just stored: equal times would make it look oldest,
        -- and evicting it would search for it again, forever.)
        local n, oldest, oldestAt = 0, nil, nil
        for k, v in pairs(C.searches) do
            n = n + 1
            if k ~= sig and (not oldestAt or v.at < oldestAt) then oldest, oldestAt = k, v.at end
        end
        if n > C.MAX_CACHED and oldest then C.searches[oldest] = nil end
        C.Evaluate(true)
    end, { key = "copilot:" .. sig, fail = function() pending[sig] = nil end })
    return hit and hit.results, "searching"
end
C.Search = Search

---------------------------------------------------------------------------
-- Value of a farm for a mode and a time budget
---------------------------------------------------------------------------
local UNIT = { level = "skill-ups", profit = "gold", material = "materials", balanced = "skill-ups", safest = "skill-ups", near = "skill-ups" }

-- The number the mode is about, an hour of farming: value, low, high, unit.
function C.Rate(r, goal)
    local m = r.metrics or {}
    if goal == "profit" or (goal == "balanced" and not (m.skillRange and m.skillRange.mid and m.skillRange.mid > 0)) then
        local rg = m.range
        if (not rg or rg.mid <= 0) and r.noPrice then
            -- No price known at all: what it yields, and the card says so.
            local v = m.materialPerHour or m.beastsPerHour or m.nodesPerHour or m.catchesPerHour or 0
            return v, v * 0.75, v * 1.25, "materials"
        end
        return rg and rg.mid or 0, rg and rg.low or 0, rg and rg.high or 0, "gold"
    end
    if goal == "material" then
        local v = m.materialPerHour or 0
        local rg = m.range
        local lowF = rg and rg.mid > 0 and rg.low / rg.mid or 0.75
        local highF = rg and rg.mid > 0 and rg.high / rg.mid or 1.25
        return v, v * lowF, v * highF, "materials"
    end
    local rg = m.skillRange
    if rg and rg.mid then return rg.mid, rg.low, rg.high, "skill-ups" end
    local v = m.skillPerHour or m.catchesPerHour or 0
    return v, v * 0.75, v * 1.25, "skill-ups"
end

-- What a trip of `budget` seconds gives: farming time after the trip there.
-- `cap`: skill-ups left before the rank cap (no more skill-ups past it).
function C.Trip(r, goal, budget, cap)
    local v, lo, hi, unit = C.Rate(r, goal)
    -- Unknown travel is assumed long (20 minutes), so a farm nobody can say
    -- how to reach never wins a short plan on a guess.
    local travel = r.travel or C.UNKNOWN_TRAVEL
    local farm = math.max(0, budget - travel)
    local f = farm / 3600
    local out = { value = v * f, low = lo * f, high = hi * f, perHour = v, unit = unit, farmSecs = farm, travel = travel,
        travelKnown = r.travel ~= nil }
    if cap and unit == "skill-ups" and v > 0 then
        out.cap = cap
        out.toCap = cap / v * 3600
        if out.value > cap then out.value, out.capped = cap, true end
        out.low, out.high = math.min(out.low, cap), math.min(out.high, cap)
    end
    return out
end

-- Skill-ups left before this profession's rank cap (nil when maxed or unknown).
function C.CapLeft(profile, prof)
    local s = profile and prof and profile.skills[prof]
    if not s then return nil end
    return math.max(0, s.max - s.rank)
end

local function Trust(r)
    local t = C.TRUST[r.evidence and r.evidence.level or "assumption"] or 0.8
    if not r.travel then t = t * 0.85 end
    return t
end

-- The figure farms are compared by: the trip's value, weighted by how well
-- it is known (a measured farm beats an unmeasured one unless that one is
-- clearly better) and by risk in the lower-risk mode.
function C.Choice(r, mode, goal, budget, cap)
    local trip = C.Trip(r, goal, budget, cap)
    local score = trip.value * Trust(r)
    if mode == "safe" and r.risk then score = score * (1 - r.risk.score) ^ 2 end
    if mode == "explore" then
        -- Upside of the unknown: the optimistic end, widened by how unsure it
        -- is, only for farms nobody measured (a test session tells).
        local lvl = r.evidence and r.evidence.level
        if lvl == "measured" or lvl == "partly measured" then return 0, trip end
        local spread = trip.value > 0 and (trip.high - trip.low) / trip.value or 0
        score = trip.high * (1 + spread)
    end
    if mode == "proven" then
        local lvl = r.evidence and r.evidence.level
        if lvl ~= "measured" and lvl ~= "partly measured" then return 0, trip end
        score = trip.value
    end
    if mode == "quest" then
        local q = HME.QuestSynergy and HME.QuestSynergy.ForResult(r)
        if not q then return 0, trip end
        score = trip.value * (1 + 0.25 * math.min(3, #q))
    end
    if r.forGoal and mode ~= "material" then score = score * 1.05 end
    return score, trip
end

local function Fmt(v, unit)
    if unit == "gold" then return HME.Kit and HME.Kit.Money and HME.Kit.Money(v) or U.Money(v, true) end
    return ("%d"):format(math.floor(v + 0.5))
end
C.Fmt = Fmt

local function Pct(x) return math.floor(x * 100 + 0.5) end

---------------------------------------------------------------------------
-- Rules
---------------------------------------------------------------------------
C.rules = {}
function C.Rule(def) C.rules[#C.rules + 1] = def end

-- Where to farm (not farming now): the best farm for the mode and time.
C.Rule({ id = "farm", run = function(ctx, add)
    if ctx.farming then return end
    local results = ctx.results
    if not results then
        if ctx.searching then
            add({ id = "searching", type = "status", group = "where", priority = 10,
                title = ("Looking for %s farms..."):format(ctx.prof), objective = "Ranking farms for this character." })
        end
        return
    end
    local best, bestScore, bestTrip
    local ranked = {}
    local cap = C.CapLeft(ctx.profile, ctx.prof)
    -- At the rank cap no farm gives skill-ups: the training card leads, and
    -- this says what to do meanwhile instead of "nothing found".
    if cap == 0 and ctx.goal == "level" then
        add({ id = "capped:" .. ctx.prof, type = "farm", group = "where", priority = 20,
            title = "Skill-ups wait for training",
            objective = ("Your %s is at its cap: no farm gives skill-ups until you train. Meanwhile, farm for gold or a goal."):format(ctx.prof),
            action = { kind = "finder", label = "Farm for gold", prof = ctx.prof, goal = "profit" } })
        return
    end
    for _, r in ipairs(results) do
        local score, trip = C.Choice(r, ctx.mode, ctx.goal, ctx.budget, cap)
        -- A farm you said "not now" to makes room for the next one.
        if score > 0 and trip.farmSecs > 0 and not C.Blocked("farm:" .. r.key) then
            ranked[#ranked + 1] = { r = r, score = score, trip = trip }
        end
    end
    table.sort(ranked, function(a, b) return a.score > b.score end)
    -- Hold the farm suggested a moment ago unless another is clearly better.
    local hold = ctx.state.where
    if hold and ranked[1] and hold.sig == ctx.sig and HME.Now() - (hold.t or 0) < C.HOLD_SECS then
        for _, e in ipairs(ranked) do
            if e.r.key == hold.key and ranked[1].score < e.score * C.SWITCH_MARGIN then
                best, bestScore, bestTrip = e.r, e.score, e.trip
                break
            end
        end
    end
    if not best and ranked[1] then best, bestScore, bestTrip = ranked[1].r, ranked[1].score, ranked[1].trip end
    if not best then
        local why = {
            proven = "You have not measured a farm for this profession yet: farm one for 6 minutes or more and it shows here.",
            quest = "No farm found whose creatures or nodes are in your quest log's objectives.",
            explore = "Every farm here is already measured by you, or none was found.",
        }
        add({ id = "nofarm:" .. ctx.mode, type = "farm", group = "where", priority = 40,
            title = "Nothing to suggest for this mode", objective = why[ctx.mode] or "The Farm Finder found no farm for this.",
            action = { kind = "finder", label = "Open the Farm Finder", prof = ctx.prof, goal = ctx.goal } })
        return
    end
    ctx.state.where = { key = best.key, t = (hold and hold.key == best.key and hold.t) or HME.Now(), sig = ctx.sig }
    ctx.ranked = ranked
    ctx.pick = { r = best, trip = bestTrip }
    C.pick = ctx.pick
    local why = {}
    if best.summary then why[#why + 1] = best.summary end
    if ctx.mode == "short" or ctx.limited then
        why[#why + 1] = ("In %d minutes: about %s %s (%s farming after a %s trip)."):format(ctx.budget / 60,
            Fmt(bestTrip.value, bestTrip.unit), bestTrip.unit ~= "gold" and bestTrip.unit or "", U.Duration(bestTrip.farmSecs),
            bestTrip.travelKnown and U.Duration(bestTrip.travel) or "20-minute (assumed: unknown)")
        -- A farther farm that pays more an hour but less in this time.
        for _, e in ipairs(ranked) do
            if e.r ~= best and e.trip.perHour > bestTrip.perHour * 1.15 and e.trip.value < bestTrip.value then
                why[#why + 1] = ("%s gives more an hour (%s) but its %s trip leaves less in %d minutes."):format(e.r.zone,
                    Fmt(e.trip.perHour, e.trip.unit), U.Duration(e.trip.travel), ctx.budget / 60)
                break
            end
        end
    end
    -- Chosen over a higher but unverified estimate (measured beats a guess).
    local plain = ctx.mode ~= "explore" and ctx.mode ~= "safe" and ctx.mode ~= "quest" and ctx.mode ~= "proven"
    for _, e in ipairs(ranked) do
        if plain and e.r ~= best and e.trip.value > bestTrip.value * 1.03 and e.score < bestScore then
            why[#why + 1] = ("Chosen over %s (estimate %d%% higher, %s) because this one is better known."):format(e.r.zone,
                Pct(e.trip.value / math.max(1e-9, bestTrip.value) - 1), (e.r.evidence and e.r.evidence.level) or "an estimate")
            break
        end
    end
    if bestTrip.capped or (bestTrip.toCap and bestTrip.toCap < bestTrip.farmSecs) then
        local s = ctx.profile.skills[ctx.prof]
        why[#why + 1] = ("You reach your %s cap (%d) after about %s of farming: no skill-ups after that until you train."):format(
            ctx.prof, s and s.max or 0, U.Duration(bestTrip.toCap))
    end
    if bestTrip.unit == "materials" and best.noPrice then
        why[#why + 1] = "No prices known (no auction data, item values not loaded): ranked by materials an hour."
    end
    if best.risk and best.risk.score >= 0.3 then
        why[#why + 1] = ("%s: %s."):format(best.risk.label, table.concat(best.risk.reasons or {}, "; ", 1, math.min(2, #(best.risk.reasons or {}))))
    end
    -- Lower-risk mode: what the safety costs, against the best regardless of risk.
    if ctx.mode == "safe" then
        local fast
        for _, e in ipairs(ranked) do
            if e.r ~= best and (not fast or e.trip.value > fast.trip.value) then fast = e end
        end
        if fast and fast.trip.value > bestTrip.value * 1.05 and fast.r.risk and best.risk and fast.r.risk.score > best.risk.score then
            why[#why + 1] = ("Safer than %s (%s), which gives about %d%% more in this time."):format(fast.r.zone or "?",
                fast.r.risk.label:lower(), Pct(fast.trip.value / math.max(1e-9, bestTrip.value) - 1))
        end
    end
    if ctx.mode == "explore" then
        why[#why + 1] = ("A guess worth testing: up to %s %s an hour if its optimistic end holds; a 20-minute session tells."):format(
            Fmt(select(3, C.Rate(best, ctx.goal)), bestTrip.unit), bestTrip.unit ~= "gold" and bestTrip.unit or "")
    end
    local alt = HME.Recommend.Alternatives(results, best, ctx.goal)
    if alt and alt.safer then
        local c = alt.safer.result
        why[#why + 1] = ("Lower risk: %s (%s), about %d%% of the number."):format(c.zone, c.risk.label:lower(), Pct(alt.safer.share))
    end
    local q = HME.QuestSynergy and HME.QuestSynergy.ForResult(best)
    if q and q[1] then why[#why + 1] = "Also progresses: " .. HME.QuestSynergy.Text(q) .. "." end
    if best.calibrated then why[#why + 1] = best.calibrated.text end
    local m = best.metrics or {}
    local rate = bestTrip.perHour
    add({ id = "farm:" .. best.key, type = "farm", group = "where", priority = 60,
        title = ("%s in %s"):format(best.prof == "Combined" and "Herbs and ore" or best.prof, best.zone or "?"),
        sub = best.subarea and best.subarea ~= "" and best.subarea or nil,
        objective = (C.MODE[ctx.mode] or C.MODE.level).label,
        benefit = { value = rate, unit = bestTrip.unit, text = ("about %s %s an hour"):format(Fmt(rate, bestTrip.unit),
            bestTrip.unit == "gold" and "" or bestTrip.unit):gsub("  ", " ") },
        range = { low = select(2, C.Rate(best, ctx.goal)), high = select(3, C.Rate(best, ctx.goal)) },
        trip = bestTrip, why = why, evidence = best.evidence and best.evidence.text, conf = best.confidence and best.confidence.value or 0.4,
        risk = best.risk, result = best, goal = ctx.goal, travel = best.travel, kind = m.limit,
        action = { kind = "farm", label = "Start farming", result = best, goal = ctx.goal },
        secondary = { { kind = "finder", label = "See in Farm Finder", prof = best.prof, goal = ctx.goal } } })
end })

-- While farming: keep going, or switch when the evidence says so.
C.Rule({ id = "where-live", run = function(ctx, add)
    if not ctx.farming then return end
    local g = ctx.guidance
    local live = ctx.live
    local v = live and live.verdict
    local area = HME.Ledger.Area(g.key)
    local ratio, sure, basis
    if v and v.enough and v.ratio then ratio, sure, basis = v.ratio, true, ("this session: %s"):format(v.text or "") end
    if area and area.sure and area.ratio and (not ratio or live.farmSecs < 1800) then
        ratio, sure, basis = area.ratio, true, HME.Ledger.AreaText(area)
    end
    local farmed = live and live.farmSecs or 0
    if ratio and sure and ratio < 0.7 and farmed >= C.MIN_SWITCH_SECS and ctx.results then
        -- A farm that beats what you actually get here, after the trip.
        local hereRate
        local cur
        for _, r in ipairs(ctx.results) do if r.key == g.key then cur = r end end
        if cur then hereRate = C.Rate(cur, ctx.goal) * ratio end
        local remain = math.max(900, ctx.budget - farmed)
        local best, bestGain
        for _, r in ipairs(ctx.results) do
            if r.key ~= g.key then
                local trip = C.Trip(r, ctx.goal, remain)
                local stay = (hereRate or 0) * remain / 3600
                local gain = trip.value * Trust(r) - stay
                if (not hereRate or trip.value > stay * 1.25) and (not bestGain or gain > bestGain) then best, bestGain = r, gain end
            end
        end
        if best then
            local trip = C.Trip(best, ctx.goal, remain)
            add({ id = "switch:" .. g.key .. ">" .. best.key, type = "switch", group = "where", priority = 80,
                title = ("Try %s instead"):format(best.zone or "?"),
                objective = ("This farm gives about %d%% of its prediction for you."):format(Pct(ratio)),
                why = { basis, ("%s: about %s %s in the next %s, after a %s trip."):format(best.zone or "?", Fmt(trip.value, trip.unit),
                    trip.unit ~= "gold" and trip.unit or "", U.Duration(remain), U.Duration(trip.travel)),
                    "Few gathers can swing a rate: this shows only after 15 farming minutes and a clear shortfall." },
                evidence = basis, conf = 0.6, result = best, goal = ctx.goal,
                action = { kind = "farm", label = "Switch farm", result = best, goal = ctx.goal },
                secondary = { { kind = "finder", label = "Compare in Farm Finder", prof = ctx.prof, goal = ctx.goal } } })
            return
        end
    end
    local text = v and v.text or "Farming: the session's rates show here after 10 minutes."
    add({ id = "stay:" .. tostring(g.key), type = "stay", group = "where", priority = 35,
        title = ("Keep farming %s"):format(g.name or "here"), objective = "You are on a farm.",
        why = { text, area and HME.Ledger.AreaText(area) or nil }, evidence = basis, conf = sure and 0.7 or 0.4,
        action = { kind = "page", label = "Session details", page = "stats" } })
end })

-- Training: capped now, or a rank ready to learn.
C.Rule({ id = "train", run = function(ctx, add)
    for _, prof in ipairs(LEARNABLE) do
        local s = ctx.profile.skills[prof]
        if s then
            local state, nextRank, how = HME.Player.TrainingState(prof, ctx.profile)
            local near = s.max < 300 and s.rank >= s.max - 10
            if (state == "capped" or (state == "ready" and near)) and how ~= "quest" then
                local t = C.Trainer(prof, nextRank and nextRank.name, ctx.profile)
                add({ id = "train:" .. prof .. ":" .. s.max, type = "train", priority = state == "capped" and 90 or 70,
                    title = ("Train %s %s"):format(nextRank.name, prof),
                    objective = state == "capped" and ("%s is at its cap (%d): no skill-ups until you train."):format(prof, s.max)
                        or ("%s %d/%d: the cap is close and %s is ready to learn."):format(prof, s.rank, s.max, nextRank.name),
                    why = { t and ("Nearest: %s, %s%s."):format(t.name, t.zone or "?", t.travel and (", about " .. U.Duration(t.travel)) or "")
                        or "No trainer position known for that rank; the Trainers page lists them." },
                    conf = 0.95, evidence = "Profession ranks from the game; trainers from Gatherpedia's list.",
                    action = t and { kind = "place", label = "Go to trainer", mapID = t.mapID, x = t.x, y = t.y, name = t.name }
                        or { kind = "page", label = "Trainers", page = "trainers", prof = prof } })
            elseif state == "level" and near then
                add({ id = "trainlvl:" .. prof .. ":" .. s.max, type = "train", priority = 30,
                    title = ("%s %s needs level %d"):format(nextRank.name, prof, nextRank.level),
                    objective = ("Your %s stops at %d until then; you are level %d."):format(prof, s.max, ctx.profile.level),
                    conf = 0.95, why = { "Leveling the character opens the next rank." } })
            end
        end
    end
end })

-- Open material and skill goals: how long, at the best known rate.
C.Rule({ id = "goals", run = function(ctx, add)
    local n = 0
    for _, g in ipairs(HME.Goals.List()) do
        if not g.doneAt and n < 3 then
            local f = C.Forecast(g, ctx)
            if f then
                n = n + 1
                add({ id = "goal:" .. tostring(g.id), type = "goal", priority = f.priority or 45,
                    title = g.name or "Goal", objective = f.text, why = f.why, conf = f.conf, forecast = f,
                    evidence = f.evidence, action = f.action, secondary = { { kind = "page", label = "Goals", page = "goals" } } })
            end
        end
    end
end })

-- Quests in your log that a farm's creatures or nodes progress.
C.Rule({ id = "quest", run = function(ctx, add)
    if ctx.farming or not ctx.results or not HME.QuestSynergy then return end
    if ctx.mode == "quest" then return end   -- the farm card already is the quest farm
    for _, r in ipairs(ctx.results) do
        local q = HME.QuestSynergy.ForResult(r)
        if q and q[1] then
            local trip = C.Trip(r, ctx.goal, ctx.budget)
            add({ id = "quest:" .. r.key, type = "quest", priority = 50,
                title = ("%s (%s)"):format(r.zone or "?", r.prof == "Combined" and "herbs and ore" or r.prof),
                objective = HME.QuestSynergy.Text(q),
                why = { ("A %s farm: about %s %s an hour."):format(r.prof, Fmt(trip.perHour, trip.unit), trip.unit ~= "gold" and trip.unit or ""),
                    "From the objectives in your quest log, matched to this farm's creatures or nodes. HME never accepts, completes or tracks quests." },
                conf = 0.7, evidence = q[1].source == "questie" and "Objective creatures from Questie (through Forever-GPS)" or "Objective names from your quest log",
                result = r, goal = ctx.goal,
                action = { kind = "farm", label = "Farm and quest", result = r, goal = ctx.goal } })
            return
        end
    end
end })

-- Bags: will they fill during this session?
C.Rule({ id = "bags", run = function(ctx, add)
    if not ctx.live then return end
    local f = HME.Bags and HME.Bags.Forecast(ctx.live)
    if not (f and f.minutes) then return end
    if f.free <= 2 or f.minutes <= 15 then
        add({ id = "bags", type = "bags", priority = f.free <= 2 and 85 or 65,
            title = f.free <= 2 and ("Bags nearly full (%d free)"):format(f.free) or ("Bags full in about %d minutes"):format(math.floor(f.minutes + 0.5)),
            objective = f.text, why = { "From your free slots, what fills them this session and stack sizes. Selling stays your move." },
            conf = f.conf or 0.6, evidence = "Bag slots from the game; rates from this session.",
            action = HME.FGPS and HME.FGPS.Available() and { kind = "service", label = "Nearest vendor", what = "vendor" } or nil })
    end
end })

-- The route you follow has stops that keep coming up empty (Route Director).
C.Rule({ id = "route", run = function(ctx, add)
    local g = ctx.guidance
    local route = g and g.routeID and HME.Guidance.Route(g.routeID)
    if not (route and HME.RouteDirector) then return end
    local laps = HME.RouteDirector.Laps(route)
    if #laps.weak >= 2 then
        add({ id = "trim:" .. route.id .. ":" .. #laps.weak, type = "route", priority = 55,
            title = ("%d stops keep coming up empty"):format(#laps.weak),
            objective = ("On %s, %d stops gave nothing in %d or more visits each."):format(route.name, #laps.weak,
                HME.RouteDirector.WEAK_VISITS),
            why = { "A copy of the route without them is made next to it; this route stays as it is.",
                "Someone else may be gathering there, or the spawn data is wrong for Forever: either way they cost you time." },
            conf = 0.6, evidence = "Your laps on this route (Route Director).",
            action = { kind = "trim", label = "Make it without them", routeID = route.id } })
    end
end })

-- The farm you follow has gone grey.
C.Rule({ id = "grey", run = function(ctx, add)
    if not (ctx.guidance and ctx.guidance.prof) then return end
    local st = HME.Guide.Status(ctx.guidance.prof, ctx.profile)
    if st.greyFarm then
        add({ id = "grey:" .. ctx.guidance.prof .. ":" .. math.floor((st.skill or 0) / 25), type = "grey", group = "where", priority = 75,
            title = "This farm has gone grey", objective = "Most of what it gives no longer brings skill-ups.",
            why = { "The Copilot's farm card shows the next one once you stop following this route." }, conf = 0.85,
            action = { kind = "finder", label = "Find the next farm", prof = ctx.guidance.prof, goal = "level" } })
    end
end })

-- Old prices for a gold plan.
C.Rule({ id = "prices", run = function(ctx, add)
    if ctx.mode ~= "profit" or not ctx.results or not ctx.results[1] then return end
    for id in pairs(ctx.results[1].metrics and ctx.results[1].metrics.items or {}) do
        local p = HME.Prices.Get(id)
        if p and p.source and p.age and p.age > 7 * 86400 then
            add({ id = "prices:" .. p.source, type = "prices", priority = 25, title = "Old auction prices",
                objective = ("Your %s prices are %s: the gold figures may be off."):format(p.source, HME.Prices.AgeText(p.age)),
                why = { "A scan at the auction house refreshes them." }, conf = 0.9 })
            return
        end
    end
end })

-- 0.7.0: what could cut the suggested trip short (Engine/Ready.lua).
C.Rule({ id = "ready", run = function(ctx, add)
    if ctx.farming or not (ctx.pick and HME.Ready) then return end
    local res = HME.Ready.Check(ctx.pick.r, ctx.budget, ctx.profile)
    if res.worst == "ok" then return end
    local why, first = {}, nil
    for _, c in ipairs(res.checks) do
        if c.state ~= "ok" then
            first = first or c
            why[#why + 1] = c.title .. (c.text ~= "" and (": " .. c.text) or "")
        end
    end
    add({ id = ("ready:%s:%s:%s"):format(ctx.pick.r.key, first.key, res.worst), type = "ready", priority = res.worst == "stop" and 70 or 50,
        title = res.summary, objective = ("Before %s in %s: %s."):format(ctx.pick.r.prof or "farming", ctx.pick.r.zone or "?", first.title),
        why = why, conf = 0.8, evidence = "Your bags, gear and skill as the game reports them now.",
        action = first.key == "repair" and HME.FGPS and HME.FGPS.Available() and { kind = "service", label = "Nearest repair", what = "repair" }
            or (first.key == "bags" and HME.FGPS and HME.FGPS.Available() and { kind = "service", label = "Nearest vendor", what = "vendor" })
            or nil })
end })

-- 0.7.0: you keep meeting enemy players in this zone (Engine/Danger.lua).
C.Rule({ id = "danger", run = function(ctx, add)
    if not (HME.Danger and ctx.profile.mapID) then return end
    local zm = HME.Geo.ZoneOf(ctx.profile.mapID, ctx.profile.x, ctx.profile.y) or ctx.profile.mapID
    local z = HME.Danger.Zone(zm)
    if not (z.enemiesPerHour and z.enemiesPerHour >= 4) then return end
    local why = { z.text, "Counted from enemy players' nameplates and the players you targeted, where you stood; "
        .. "it says nothing about who is here now." }
    add({ id = ("danger:%d:%d"):format(zm, math.floor(z.enemiesPerHour / 4)), type = "danger", priority = ctx.mode == "safe" and 30 or 52,
        title = "Enemies common here", objective = ("About %s an hour in %s, from your own time here."):format(
            z.enemiesPerHour >= 10 and tostring(math.floor(z.enemiesPerHour + 0.5)) or ("%.1f"):format(z.enemiesPerHour),
            HME.ZoneData.Name(zm) or "this zone"),
        why = why, conf = math.min(0.85, 0.4 + z.hours / 6), evidence = ("%.1f h of your time in the zone"):format(z.hours),
        action = ctx.mode ~= "safe" and { kind = "mode", label = "Lower-risk farms", mode = "safe" } or nil })
end })

-- 0.7.0: a material in your bags whose price moved a lot (Engine/Trends.lua).
C.Rule({ id = "market", run = function(ctx, add)
    if not (HME.Trends and HME.Bags) then return end
    local me = HME.db and HME.db.chars and HME.Bags.Me() and HME.db.chars[HME.Bags.Me()]
    local ids = {}
    for id in pairs(type(me) == "table" and type(me.bags) == "table" and me.bags or {}) do ids[#ids + 1] = id end
    table.sort(ids)
    local movers = HME.Trends.Movers(ids, 0.2)
    local m = movers[1]
    if not m then return end
    local name = (HME.Goals and HME.Goals.ItemName(m.id)) or ("item " .. m.id)
    local up = m.t.trend == "up"
    add({ id = ("market:%d:%s:%d"):format(m.id, m.t.trend, m.t.days), type = "market", priority = ctx.mode == "profit" and 40 or 20,
        title = up and (name .. " is selling high") or (name .. " is selling low"),
        objective = m.t.short, why = { m.t.text, HME.Trends.Advice(m.t) or "", "HME never lists, buys or sells: the auction house is your move." },
        conf = math.min(0.75, 0.35 + m.t.days * 0.05), evidence = ("%d days of %s"):format(m.t.days, m.t.source),
        action = { kind = "material", label = "See it", itemID = m.id, name = name } })
end })

-- What the ledger learned from your sessions.
C.Rule({ id = "learned", run = function(ctx, add)
    if not ctx.prof then return end
    local f = HME.Ledger.Factor(ctx.prof, "pace")
    if f and f.used then
        add({ id = ("learned:%s:%d"):format(ctx.prof, math.floor(Pct(f.factor) / 5)), type = "learned", priority = 15,
            title = "Estimates adjusted to you", objective = f.text,
            why = { ("Range of the adjustment: %d%% to %d%%."):format(Pct(f.low), Pct(f.high)),
                "Farms you measured yourself use your own numbers instead." }, conf = 0.6 })
    end
end })

---------------------------------------------------------------------------
-- Helpers the rules use
---------------------------------------------------------------------------
-- The closest trainer for a profession (and rank), with travel time.
function C.Trainer(prof, rankName, profile)
    local Tr = ns.Trainers
    if not (Tr and Tr.Filtered) then return nil end
    local ORDER = { Apprentice = 1, Journeyman = 2, Expert = 3, Artisan = 4 }
    local want = ORDER[rankName or ""] or 1
    local best
    for _, e in ipairs(Tr:Filtered({ prof = prof, faction = profile.faction })) do
        local okRank = (ORDER[e.rank or ""] or 4) >= want
        local mapID = ns.Zones and ns.Zones.MapID and ns.Zones:MapID(e.zone)
        if okRank and (e.kind == nil or e.kind == "trainer") and mapID and e.x then
            local travel
            if profile.mapID then
                local fm, fx, fy = HME.Geo.ZoneOf(profile.mapID, profile.x, profile.y)
                travel = HME.Geo.TravelTime(fm, fx, fy, mapID, e.x / 100, e.y / 100, { speed = profile.speed, faction = profile.faction })
            end
            local cand = { name = e.name, zone = e.zone, mapID = mapID, x = e.x / 100, y = e.y / 100, travel = travel }
            if not best or (travel or 1e9) < (best.travel or 1e9) then best = cand end
        end
    end
    return best
end

-- How long a goal takes: { text, why, conf, priority, action, hours = {low, mid, high} }.
function C.Forecast(g, ctx)
    local p = HME.Goals.Progress(g)
    if p.done then return nil end
    local remaining = math.max(0, (p.target or 0) - (p.have or 0))
    if remaining <= 0 then return nil end
    local q = HME.Goals.Query(g)
    if not q then
        return { text = ("%d to go. No gathering profession gives it, so no forecast."):format(remaining), conf = 0.2, priority = 20 }
    end
    local profile = ctx.profile
    if not profile.skills[q.prof] then
        return { text = ("%d to go; it needs %s, which this character does not know."):format(remaining, q.prof), conf = 0.3, priority = 20 }
    end
    local sig = "goal|" .. tostring(g.id) .. "|" .. Sig(profile, q.prof, "goal")
    q.limit = 6
    local results = Search(sig, q, profile)
    local r = results and results[1]
    if not r then return { text = ("%d to go; finding the best farm for it..."):format(remaining), conf = 0.2, priority = 20 } end
    local mid, low, high
    if g.type == "skill" then
        mid, low, high = C.Rate(r, "level")
    elseif g.type == "value" then
        mid, low, high = C.Rate(r, "profit")
    else
        mid, low, high = C.Rate(r, "material")
    end
    if not mid or mid <= 0 then
        return { text = ("%d to go; no rate is known for it yet."):format(remaining), conf = 0.2, priority = 20 }
    end
    local travel = r.travel or 600
    local hMid, hFast, hSlow = remaining / mid, remaining / math.max(high, mid), remaining / math.max(1e-9, low)
    local function T(h) return U.Duration(h * 3600 + travel) end
    local unit = g.type == "skill" and "points" or (g.type == "value" and "" or "")
    local text = ("%s %s to go: about %s at %s (%s to %s, travel included)."):format(g.type == "value" and Fmt(remaining, "gold") or remaining,
        unit, T(hMid), r.zone or "?", T(hFast), T(hSlow))
    local evidence = r.evidence and r.evidence.text or nil
    local conf = r.confidence and r.confidence.value or 0.4
    -- Already farming for it: the session's own rate says more.
    local live = ctx.live
    if live and g.itemID then
        for _, it in ipairs(live.items or {}) do
            if it.id == g.itemID and it.perHour and it.perHour > 0 and live.farmSecs >= 600 then
                text = text .. (" At this session's pace (%.0f an hour): about %s."):format(it.perHour, U.Duration(remaining / it.perHour * 3600))
            end
        end
    end
    return { text = text:gsub("%s+", " "), hours = { low = hFast, mid = hMid, high = hSlow }, travel = travel, conf = conf,
        evidence = evidence, why = { ("Best farm for it: %s, %s."):format(r.zone or "?", r.summary or ""),
            "A range, not a promise: the slow end assumes the farm's low estimate." },
        priority = 45, result = r, action = { kind = "farm", label = "Farm for it", result = r, goal = q.goal } }
end

---------------------------------------------------------------------------
-- Evaluation and arbitration
---------------------------------------------------------------------------
C.cards = {}
C.lastEval = -1e9

function C.Context()
    local profile = HME.Player.Profile()
    local s = St()
    local mode = C.Mode()
    local prof, profWhy = C.FocusProf(profile)
    local budget, limited = C.Budget()
    local guidance = HME.Guidance and HME.Guidance.Active()
    local ctx = { profile = profile, state = s, mode = mode, prof = prof, profWhy = profWhy, budget = budget, limited = limited,
        guidance = guidance, live = HME.Session.Live(), farming = guidance ~= nil and guidance.phase == "farm" }
    if prof then
        local q = C.Query(mode, prof, profile)
        ctx.goal, ctx.query = q.goal, q
        ctx.sig = Sig(profile, prof, mode)
        local results, status = Search(ctx.sig, q, profile)
        ctx.results, ctx.searching = results, status == "searching"
        if q.noMaterial then ctx.noMaterial = true end
    end
    return ctx
end

-- Whether a card id was put off ("Not now") and is still waiting.
function C.Blocked(id)
    local t = St().dismissed[id]
    return t ~= nil and t > HME.Now()
end

local function Allowed(card, s, now)
    if s.notInterested[card.type] then return false end
    local until_ = s.dismissed[card.id]
    if until_ and until_ > now then return false end
    if HME.settings and type(HME.settings.copilot) == "table" and HME.settings.copilot[card.type] == false then return false end
    return true
end

-- Runs every rule and picks what to show. Cheap when nothing changed.
function C.Evaluate(force)
    local now = HME.Now()
    if not force and now - C.lastEval < 5 then return C.cards end
    C.lastEval = now
    local ctx = C.Context()
    C.ctx = ctx
    local raw = {}
    local function add(card)
        if not card or not card.id then return end
        card.why = card.why or {}
        for i = #card.why, 1, -1 do if not card.why[i] or card.why[i] == "" then table.remove(card.why, i) end end
        raw[#raw + 1] = card
    end
    if not ctx.prof then
        add({ id = "setup:noprof", type = "setup", priority = 50, title = "No gathering profession yet",
            objective = "Learn Herbalism, Mining, Skinning or Fishing at a trainer; the Copilot plans from there.",
            action = { kind = "page", label = "Trainers", page = "trainers" } })
    end
    for _, rule in ipairs(C.rules) do
        HME.Try(rule.run, ctx, add)
    end
    -- Arbitrate.
    local s = St()
    for id, t in pairs(s.dismissed) do if t <= now then s.dismissed[id] = nil end end
    local byGroup, out = {}, {}
    table.sort(raw, function(a, b) return (a.priority or 0) > (b.priority or 0) end)
    local seen = {}
    for _, card in ipairs(raw) do
        if not seen[card.id] and Allowed(card, s, now) then
            seen[card.id] = true
            if card.group then
                if not byGroup[card.group] then
                    byGroup[card.group] = card
                    out[#out + 1] = card
                end
            else
                out[#out + 1] = card
            end
        end
    end
    -- A switch that was just turned down holds "stay" for a while: the
    -- arbiter keeps whichever "where" card won, so nothing else to do here.
    for i, card in ipairs(out) do card.rank = i end
    C.cards = out
    HME.Signal("COPILOT_CHANGED")
    return out
end

function C.Cards(force)
    if force or #C.cards == 0 then return C.Evaluate(force) end
    return C.cards
end

-- The first card with something to do (the Dashboard's and HUD's pick).
function C.Top()
    for _, c in ipairs(C.Cards()) do if c.action and c.type ~= "status" then return c end end
end

-- "Not now": this card, for six hours. "Not interested": its kind, until reset.
function C.Dismiss(card, kind)
    local s = St()
    if kind == "type" then s.notInterested[card.type] = true
    else s.dismissed[card.id] = HME.Now() + C.NOT_NOW end
    if card.group == "where" then s.where = nil end
    C.Evaluate(true)
end
function C.ResetFeedback()
    local s = St()
    s.dismissed, s.notInterested, s.where = {}, {}, nil
    C.Evaluate(true)
end

-- Carries out a card's action. Only ever called from a click.
function C.Run(action)
    if type(action) ~= "table" then return false end
    local k = action.kind
    if k == "farm" and action.result then
        HME.Guidance.StartResult(action.result, action.goal)
        return true
    elseif k == "finder" then
        HME.OpenWindow("finder")
        if HME.Pages.finderSet then HME.Pages.finderSet(action.prof, action.goal, action.material) end
        return true
    elseif k == "place" and action.mapID then
        return HME.FGPS.GoToPlace(action.mapID, action.x, action.y, action.name)
    elseif k == "service" then
        return HME.FGPS.GoToService(action.what, action.profession)
    elseif k == "trim" and HME.RouteDirector then
        local route = HME.Guidance.Route(action.routeID)
        local v, why
        if route then v, why = HME.RouteDirector.WithoutWeak(route) end
        if v then
            HME.Print(("made |cffffd100%s|r. Follow it from the Routes page when you like."):format(v.name))
            return true
        end
        HME.Print(why or "no route to trim.")
        return false
    elseif k == "mode" and action.mode then
        C.SetMode(action.mode)
        HME.OpenWindow("copilot")
        return true
    elseif k == "material" then
        HME.OpenWindow("materials")
        if HME.Pages.materialsShow then
            local entry = ns.itemIndex and ns.itemIndex[action.itemID]
            HME.Pages.materialsShow(type(entry) == "table" and entry.prof or nil, action.name)
        end
        return true
    elseif k == "page" then
        HME.OpenWindow(action.page)
        if action.page == "trainers" and action.prof and HME.Pages.trainersSet then HME.Pages.trainersSet(action.prof) end
        return true
    end
    return false
end

---------------------------------------------------------------------------
-- When to look again (events only; never per frame)
---------------------------------------------------------------------------
local function Later(why, delay) HME.Soon("copilot-" .. why, delay or 3, function() C.Evaluate(true) end) end
HME.Listen("PLAYER_CHANGED", function() C.searches = {} DropQueued() Later("player", 2) end)
HME.Listen("GOALS_CHANGED", function() C.goalsVersion = C.goalsVersion + 1 Later("goals", 1) end)
HME.Listen("GUIDANCE_CHANGED", function() Later("guidance", 2) end)
HME.Listen("SESSION_ENDED", function() Later("session", 2) end)
HME.Listen("SESSION_CHANGED", function() Later("live", 30) end)
HME.Listen("QUESTS_CHANGED", function() Later("quests", 3) end)
HME.On("ZONE_CHANGED_NEW_AREA", function() Later("zone", 5) end)
