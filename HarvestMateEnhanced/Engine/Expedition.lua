-- HarvestMate Enhanced: Engine/Expedition.lua
-- Farming expeditions: several materials, possibly from several zones, as one
-- staged plan. "50 Heavy Leather, 30 Iron Ore, 20 Goldthorn" becomes
--   1. travel (Forever-GPS) -> farm A (HME's loop) for the items it serves
--   2. travel -> farm B for what is left ... and an optional last stop.
--
-- How: the materials are grouped by the profession that gathers them; the Farm
-- Finder is asked once per profession (goal "material", all its items at once);
-- then stages are chosen greedily: next is the farm that covers the most of
-- what is still missing per hour of farming PLUS travel from where the last
-- stage ends, so the plan does not zig-zag. A stage lasts until its items are
-- expected to be done (at most MAX_STAGE_HOURS). Items no profession of yours
-- gathers, or with no farm in reach, are listed with the reason.
-- Rates are the Finder's confidence-aware estimates; travel between stages is
-- HME's own estimate (Forever-GPS estimates only from where you stand).
-- Nothing moves you: "Go" starts the stage's navigation like the Farm Finder.
-- Copyright (C) 2026 HarvestMate Enhanced contributors. GPL-3.0-or-later.

local _, ns = ...
local HME = ns.HME
local U = HME.U

local X = {}
HME.Expedition = X

X.MAX_STAGE_HOURS = 2
X.MAX_STAGES = 6
X.PER_PROF = 6          -- Finder results kept per profession

-- Items an hour a farm gives: { [itemID] = n }.
function X.ItemRates(r)
    local m = r.metrics or {}
    local out = {}
    if r.prof == "Skinning" then
        for id, per in pairs(m.items or {}) do out[id] = (m.beastsPerHour or 0) * per end
    elseif r.prof == "Fishing" then
        local fish = m.fish or {}
        for _, f in ipairs(fish) do out[f.id] = (out[f.id] or 0) + (m.catchesPerHour or 0) / math.max(1, #fish) end
    else
        for _, mix in ipairs(m.mix or {}) do
            if mix.itemID then
                local qty = HME.Gathering.PRIOR_QTY[mix.prof or r.prof] or 1.5
                out[mix.itemID] = (out[mix.itemID] or 0) + (m.nodesPerHour or 0) * mix.share * qty
            end
        end
    end
    return out
end

local function ProfOf(itemID) return HME.Goals.ProfOf(itemID) end

-- needs = { { itemID, count } }. done(plan) in the background:
-- plan = { stages = { { prof, mapID, cx, cy, zone, key, items = { [id] = n },
--          hours, travel, confidence } }, missing = { { itemID, count, why } },
--          hours, travel, needs }
function X.Plan(needs, opts, done)
    opts = opts or {}
    local profile = opts.profile or HME.Player.Profile()
    local remaining, order, missing = {}, {}, {}
    local byProf = {}
    for _, n in ipairs(needs or {}) do
        local id, count = tonumber(n.itemID or n[1]), tonumber(n.count or n[2])
        if id and count and count > 0 then
            local prof = ProfOf(id)
            if not prof then
                missing[#missing + 1] = { itemID = id, count = count, why = "no gathering profession gives it" }
            elseif not profile.skills[prof] then
                missing[#missing + 1] = { itemID = id, count = count, why = "needs " .. prof .. ", which you do not have" }
            else
                remaining[id] = (remaining[id] or 0) + count
                order[#order + 1] = id
                byProf[prof] = byProf[prof] or {}
                byProf[prof][id] = true
            end
        end
    end
    local profs = {}
    for prof in pairs(byProf) do profs[#profs + 1] = prof end
    table.sort(profs)
    local candidates = {}
    local function Choose()
        local plan = { stages = {}, missing = missing, needs = needs, created = (time and time()) or 0, hours = 0, travel = 0 }
        local left = {}
        for id, c in pairs(remaining) do left[id] = c end
        local need0 = {}
        for id, c in pairs(remaining) do need0[id] = c end
        local pos = { mapID = profile.mapID and HME.Geo.ZoneOf(profile.mapID, profile.x, profile.y), x = profile.x, y = profile.y }
        if pos.mapID then
            local _, zx, zy = HME.Geo.ZoneOf(profile.mapID, profile.x, profile.y)
            pos.x, pos.y = zx, zy
        end
        local used = {}
        for stageN = 1, X.MAX_STAGES do
            local best, bestV
            for ci, c in ipairs(candidates) do
                if not used[ci] then
                    local hours, served = 0, 0
                    for id, rate in pairs(c.rates) do
                        if (left[id] or 0) > 0 and rate > 0 then
                            hours = math.max(hours, left[id] / rate)
                            served = served + 1
                        end
                    end
                    if served > 0 then
                        hours = math.min(hours, X.MAX_STAGE_HOURS)
                        local gained = 0
                        for id, rate in pairs(c.rates) do
                            if (left[id] or 0) > 0 then gained = gained + math.min(left[id], rate * hours) / need0[id] end
                        end
                        local travel = HME.Geo.TravelTime(pos.mapID, pos.x, pos.y, c.r.mapID, c.r.cx, c.r.cy,
                            { speed = profile.speed, faction = profile.faction, fromPlayer = stageN == 1 and profile.real ~= false })
                        travel = travel or 1800
                        local v = gained / (hours + travel / 3600 + 0.05)
                        if not bestV or v > bestV then best, bestV = { ci = ci, c = c, hours = hours, travel = travel }, v end
                    end
                end
            end
            if not best then break end
            used[best.ci] = true
            local r = best.c.r
            local items = {}
            for id, rate in pairs(best.c.rates) do
                if (left[id] or 0) > 0 then
                    local got = math.min(left[id], rate * best.hours)
                    if got >= 0.5 then
                        items[id] = math.floor(got + 0.5)
                        left[id] = left[id] - got
                    end
                end
            end
            plan.stages[#plan.stages + 1] = { prof = r.prof, mapID = r.mapID, cx = r.cx, cy = r.cy, zone = r.zone, key = r.key,
                items = items, hours = best.hours, travel = best.travel, confidence = r.confidence and r.confidence.label,
                evidence = r.evidence and r.evidence.level, subarea = r.subarea }
            plan.hours = plan.hours + best.hours
            plan.travel = plan.travel + best.travel
            pos = { mapID = r.mapID, x = r.cx, y = r.cy }
            local open = false
            for _, c in pairs(left) do if c >= 0.5 then open = true end end
            if not open then break end
        end
        for _, id in ipairs(order) do
            if (left[id] or 0) >= 0.5 then
                local served = false
                for _, c in ipairs(candidates) do if (c.rates[id] or 0) > 0 then served = true end end
                missing[#missing + 1] = { itemID = id, count = math.ceil(left[id]),
                    why = served and ("not all within %d stages of %d h"):format(X.MAX_STAGES, X.MAX_STAGE_HOURS)
                        or "no farm in reach gives it at your level and skill" }
            end
        end
        if opts.finish then plan.finish = opts.finish end
        if done then done(plan) end
        return plan
    end
    if #profs == 0 then return Choose() end
    -- One Farm Finder search per profession, one after another.
    local i = 0
    local function Next()
        i = i + 1
        local prof = profs[i]
        if not prof then return Choose() end
        local q = { prof = prof, goal = "material", targets = byProf[prof], limit = X.PER_PROF }
        local function Got(results)
            for _, r in ipairs(results or {}) do candidates[#candidates + 1] = { r = r, rates = X.ItemRates(r) } end
            return Next()
        end
        if done then
            HME.Recommend.Find(q, Got, profile)
        else
            return Got(HME.Recommend.Find(q, nil, profile))
        end
    end
    return Next()
end

---------------------------------------------------------------------------
-- Following an expedition
---------------------------------------------------------------------------
local function Cur() return HME.char and HME.char.expedition end
function X.Current() return Cur() end

-- Keeps the plan; what you gather from now on counts toward it.
function X.Start(plan, name)
    if not (plan and #plan.stages > 0) then return nil, "nothing to farm" end
    plan.name = name or plan.name or "Expedition"
    plan.current = 1
    plan.got = {}
    plan.started = (time and time()) or 0
    HME.char.expedition = plan
    HME.Signal("EXPEDITION_CHANGED")
    return plan
end

function X.Stop()
    if HME.char then HME.char.expedition = nil end
    HME.Signal("EXPEDITION_CHANGED")
end

-- What is still needed in total, and per stage.
function X.Progress(plan)
    plan = plan or Cur()
    if not plan then return nil end
    local need = {}
    for _, n in ipairs(plan.needs or {}) do
        local id, c = tonumber(n.itemID or n[1]), tonumber(n.count or n[2])
        if id and c then need[id] = (need[id] or 0) + c end
    end
    local items, done = {}, true
    for id, c in pairs(need) do
        local got = (plan.got and plan.got[id]) or 0
        items[#items + 1] = { itemID = id, need = c, got = got, left = math.max(0, c - got) }
        if got < c then done = false end
    end
    table.sort(items, function(a, b) return a.itemID < b.itemID end)
    return { items = items, done = done, stage = plan.stages[plan.current], current = plan.current, stages = #plan.stages }
end

-- Is the current stage's share gathered (or nothing it serves still missing)?
local function StageDone(plan)
    local st = plan.stages[plan.current]
    if not st then return true end
    local p = X.Progress(plan)
    local leftOf = {}
    for _, it in ipairs(p.items) do leftOf[it.itemID] = it.left end
    for id in pairs(st.items) do
        if (leftOf[id] or 0) > 0 and ((plan.stageGot and plan.stageGot[id]) or 0) < st.items[id] then return false end
    end
    return true
end

local function Count(items)
    local plan = Cur()
    if not plan then return end
    plan.got = plan.got or {}
    plan.stageGot = plan.stageGot or {}
    for id, q in pairs(items or {}) do
        plan.got[id] = (plan.got[id] or 0) + q
        plan.stageGot[id] = (plan.stageGot[id] or 0) + q
    end
    if X.Progress(plan).done then
        HME.Suggest.Add("goalDone", "expedition" .. (plan.started or 0), ("%s: everything gathered. Well done."):format(plan.name))
    elseif StageDone(plan) and not plan.stageDoneSaid then
        plan.stageDoneSaid = true
        local nxt = plan.stages[plan.current + 1]
        HME.Suggest.Add("goalNear", "expedition-stage" .. plan.current, nxt
            and ("%s: stage %d done. Next: %s in %s (/hme exp next)."):format(plan.name, plan.current, nxt.prof, nxt.zone or "?")
            or ("%s: last stage done; what is left can be planned again (/hme exp replan)."):format(plan.name))
    end
    HME.Signal("EXPEDITION_CHANGED")
end
HME.Listen("GATHER_LOOT", function(_, _, counts) Count(counts) end)
HME.Listen("BEAST_SKINNED", function(_, items) Count(items) end)
HME.Listen("FISH_CAUGHT", function(items) Count(items) end)

-- Starts the current stage's farm (navigation and loop, like the Farm Finder).
function X.Go(index)
    local plan = Cur()
    if not plan then return false, "no expedition" end
    if index then plan.current = index end
    local st = plan.stages[plan.current]
    if not st then return false, "no such stage" end
    plan.stageGot, plan.stageDoneSaid = {}, nil
    local targets = {}
    for id in pairs(st.items) do targets[id] = true end
    HME.Recommend.Find({ prof = st.prof, goal = "material", targets = targets, limit = 12 }, function(results)
        local pick, bd
        for _, r in ipairs(results or {}) do
            if r.mapID == st.mapID then
                local d = HME.Geo.Distance(r.mapID, r.cx, r.cy, st.cx, st.cy)
                if not bd or d < bd then pick, bd = r, d end
            end
        end
        pick = pick or (results and results[1])
        if pick then HME.Guidance.StartResult(pick, "material") end
    end)
    HME.Signal("EXPEDITION_CHANGED")
    return true
end

function X.Next()
    local plan = Cur()
    if not plan then return false end
    if plan.current >= #plan.stages then return false, "that was the last stage" end
    plan.current = plan.current + 1
    return X.Go()
end

function X.Skip(index)
    local plan = Cur()
    if not (plan and plan.stages[index or plan.current]) then return false end
    table.remove(plan.stages, index or plan.current)
    if plan.current > #plan.stages then plan.current = math.max(1, #plan.stages) end
    HME.Signal("EXPEDITION_CHANGED")
    return true
end

function X.Move(index, delta)
    local plan = Cur()
    local j = index + delta
    if not (plan and plan.stages[index] and plan.stages[j]) then return false end
    plan.stages[index], plan.stages[j] = plan.stages[j], plan.stages[index]
    HME.Signal("EXPEDITION_CHANGED")
    return true
end

-- Plans again for what is still missing (after a stage, or when things changed).
function X.Replan(done)
    local plan = Cur()
    if not plan then return false end
    local needs = {}
    for _, it in ipairs(X.Progress(plan).items) do
        if it.left > 0 then needs[#needs + 1] = { itemID = it.itemID, count = it.left } end
    end
    return X.Plan(needs, { finish = plan.finish }, function(newPlan)
        newPlan.name = plan.name
        X.Start(newPlan, plan.name)
        if done then done(newPlan) end
    end)
end

-- A shopping-list (or item) goal as expedition needs.
function X.FromGoal(g)
    local needs = {}
    if g.type == "item" then
        local p = HME.Goals.Progress(g)
        needs[1] = { itemID = g.itemID, count = math.max(0, g.target - (p.have or 0)) }
    elseif g.type == "list" then
        for _, part in ipairs(HME.Goals.Progress(g).parts) do
            if part.missing > 0 then needs[#needs + 1] = { itemID = part.itemID, count = part.missing } end
        end
    end
    return needs
end

-- Plain lines for chat and the Goals page.
function X.Lines(plan)
    local out = {}
    for i, st in ipairs(plan.stages) do
        local items = {}
        for id, n in pairs(st.items) do items[#items + 1] = ("%d %s"):format(n, HME.Goals.ItemName(id)) end
        table.sort(items)
        out[#out + 1] = ("%d. %s in %s (%s): %s, about %s farming%s"):format(i, st.prof, st.zone or "?", st.subarea or "",
            table.concat(items, ", "), U.Duration(st.hours * 3600), st.travel and (" + " .. U.Duration(st.travel) .. " travel") or "")
    end
    for _, m in ipairs(plan.missing or {}) do
        out[#out + 1] = ("Not planned: %d %s (%s)"):format(m.count, HME.Goals.ItemName(m.itemID), m.why)
    end
    if plan.finish then out[#out + 1] = ("Then: %s (Forever-GPS: /fgps go nearest %s)"):format(plan.finish, plan.finish) end
    return out
end
