-- HarvestMate Enhanced: Engine/Goals.lua
-- Farming goals and what helps reach them:
--   item   "100 Heavy Leather"        progress = held in bags (what the game
--          reports), plus what you gathered since the goal was set
--   list   a shopping list of items   the same, per item
--   skill  "Skinning 225"             progress = current skill
--   value  "50 gold of materials"     progress = value gathered since set
-- Held and gathered are kept apart: bags can change for other reasons. The
-- bank counts only when you have opened it (its counts are remembered with
-- the time); other characters' bags are never guessed.
-- A goal can ask the Farm Finder for the best way to reach it, with an
-- estimate of time and loops. Finishing one says so once and offers to stop.
--
-- Also here: inventory capacity, a sell / keep advisor, and saved profiles.
-- Copyright (C) 2026 HarvestMate Enhanced contributors. GPL-3.0-or-later.

local _, ns = ...
local HME = ns.HME
local U = HME.U

local Goals = {}
HME.Goals = Goals

local function List()
    HME.char.goals = type(HME.char.goals) == "table" and HME.char.goals or {}
    return HME.char.goals
end
Goals.List = List

---------------------------------------------------------------------------
-- Inventory
---------------------------------------------------------------------------
local Inv = {}
HME.Inventory = Inv

local function GetCount(...)
    local fn = (C_Item and C_Item.GetItemCount) or _G.GetItemCount
    if not fn then return nil end
    return fn(...)
end

-- In bags now (the game's own count; 0 when it can't say).
function Inv.Held(itemID)
    local ok, n = pcall(GetCount, itemID, false)
    return ok and HME.Num(n) or 0
end

-- Last seen in the bank: count and when (nil if the bank was never opened).
function Inv.Bank(itemID)
    local b = HME.char and HME.char.bank
    return b and b.items and b.items[itemID], b and b.t
end

HME.On("BANKFRAME_OPENED", function()
    HME.After(0.5, function()
        if not HME.char then return end
        local items = {}
        for _, g in ipairs(List()) do
            local ids = g.type == "list" and g.items or { g }
            for _, it in ipairs(ids) do
                if it.itemID then
                    local ok1, all = pcall(GetCount, it.itemID, true)
                    local ok2, bags = pcall(GetCount, it.itemID, false)
                    if ok1 and ok2 and HME.Num(all) and HME.Num(bags) then items[it.itemID] = math.max(0, all - bags) end
                end
            end
        end
        HME.char.bank = { items = items, t = (time and time()) or 0 }
    end)
end)

function Inv.FreeSlots()
    local get = C_Container and C_Container.GetContainerNumFreeSlots
    local size = C_Container and C_Container.GetContainerNumSlots
    if not get then return nil end
    local free, total = 0, 0
    for bag = 0, 4 do
        local ok, n, kind = pcall(get, bag)
        if ok and HME.Num(n) and (kind == nil or kind == 0) then free = free + n end
        local ok2, s = pcall(size or function() return 0 end, bag)
        if ok2 and HME.Num(s) then total = total + s end
    end
    return free, total
end

---------------------------------------------------------------------------
-- Goals
---------------------------------------------------------------------------
local function ItemName(id)
    local rec = ns.itemIndex[id]
    return (rec and ns.GetItemName(rec.entry)) or (rec and rec.entry.name) or ("item " .. id)
end
Goals.ItemName = ItemName

-- Which profession gathers an item (from the field guide).
function Goals.ProfOf(itemID)
    local rec = ns.itemIndex[itemID]
    return rec and rec.prof
end

local seq = 0
local function NewID()
    seq = seq + 1
    return ((time and time()) or 0) .. "-" .. seq
end

-- spec: { type = "item", itemID, target } | { type = "list", items = { {itemID, target} } }
--     | { type = "skill", prof, target } | { type = "value", copper }
function Goals.Add(spec)
    if type(spec) ~= "table" then return nil, "no goal" end
    local g = { id = NewID(), type = spec.type, created = (time and time()) or 0, gathered = 0, gatheredItems = {} }
    if spec.type == "item" then
        local id, target = tonumber(spec.itemID), tonumber(spec.target)
        if not (id and target and target > 0 and target <= 100000) then return nil, "an item and an amount are needed" end
        g.itemID, g.target, g.name = id, math.floor(target), ItemName(id)
        g.startHeld = Inv.Held(id)
    elseif spec.type == "list" then
        g.items = {}
        for _, it in ipairs(spec.items or {}) do
            local id, target = tonumber(it.itemID), tonumber(it.target)
            if id and target and target > 0 then g.items[#g.items + 1] = { itemID = id, target = math.floor(target), name = ItemName(id) } end
        end
        if #g.items == 0 then return nil, "the list is empty" end
        g.name = spec.name or "Shopping list"
    elseif spec.type == "skill" then
        local target = tonumber(spec.target)
        if not (spec.prof and target and target >= 1 and target <= 300) then return nil, "a profession and a skill up to 300 are needed" end
        g.prof, g.target, g.name = spec.prof, math.floor(target), spec.prof .. " " .. math.floor(target)
    elseif spec.type == "value" then
        local copper = tonumber(spec.copper)
        if not (copper and copper > 0) then return nil, "an amount is needed" end
        g.target, g.name = math.floor(copper), U.Money(copper, true) .. " of materials"
    else
        return nil, "unknown goal type"
    end
    table.insert(List(), g)
    HME.Signal("GOALS_CHANGED")
    return g
end

function Goals.Remove(id)
    local list = List()
    for i = #list, 1, -1 do if list[i].id == id then table.remove(list, i) end end
    HME.Signal("GOALS_CHANGED")
end

-- { done, target, held, gathered, bank, bankAt, fraction, parts = {...} }
function Goals.Progress(g)
    if g.type == "item" then
        local held = Inv.Held(g.itemID)
        local bank, bankAt = Inv.Bank(g.itemID)
        local have = held + (bank or 0)
        return { done = have >= g.target, target = g.target, held = held, bank = bank, bankAt = bankAt,
            gathered = g.gatheredItems[g.itemID] or 0, have = have, fraction = U.Clamp(have / g.target, 0, 1) }
    elseif g.type == "list" then
        local parts, sum, total, all = {}, 0, 0, true
        for _, it in ipairs(g.items) do
            local held = Inv.Held(it.itemID)
            local bank = Inv.Bank(it.itemID) or 0
            local have = held + bank
            parts[#parts + 1] = { itemID = it.itemID, name = it.name, target = it.target, held = held, bank = bank,
                have = have, missing = math.max(0, it.target - have), gathered = g.gatheredItems[it.itemID] or 0 }
            sum = sum + math.min(have, it.target)
            total = total + it.target
            if have < it.target then all = false end
        end
        return { done = all, target = total, have = sum, fraction = total > 0 and sum / total or 0, parts = parts }
    elseif g.type == "skill" then
        local skill = HME.Player.Skill(g.prof) or 0
        return { done = skill >= g.target, target = g.target, have = skill, fraction = U.Clamp(skill / g.target, 0, 1) }
    else
        return { done = g.gathered >= g.target, target = g.target, have = g.gathered, fraction = U.Clamp(g.gathered / g.target, 0, 1) }
    end
end

-- Gathering counts toward goals: items gathered and their value.
local function Count(items)
    local list = List()
    for _, g in ipairs(list) do
        if not g.doneAt then
            for id, q in pairs(items or {}) do
                g.gatheredItems[id] = (g.gatheredItems[id] or 0) + q
                if g.type == "value" then g.gathered = g.gathered + (HME.Prices.Value(id) or 0) * q end
            end
        end
    end
    Goals.Check()
end
HME.Listen("GATHER_LOOT", function(_, _, counts) Count(counts) end)
HME.Listen("BEAST_SKINNED", function(_, items) Count(items) end)
HME.Listen("FISH_CAUGHT", function(items) Count(items) end)
HME.Listen("PLAYER_CHANGED", function() Goals.Check() end)

-- Finished goals: said once (a suggestion), marked done; never removed.
function Goals.Check()
    for _, g in ipairs(List()) do
        if not g.doneAt then
            local p = Goals.Progress(g)
            if p.done then
                g.doneAt = (time and time()) or 0
                HME.Signal("GOAL_DONE", g)
                if HME.Suggest then
                    HME.Suggest.Add("goalDone", g.id, ("Goal reached: %s. Stop farming or pick the next goal on the Goals page."):format(g.name))
                end
            end
        end
    end
    HME.Signal("GOALS_CHANGED")
end

-- The Farm Finder query that serves a goal.
function Goals.Query(g)
    if g.type == "item" then
        local prof = Goals.ProfOf(g.itemID)
        if not prof then return nil end
        return { prof = prof, goal = "material", targets = { [g.itemID] = true } }
    elseif g.type == "list" then
        -- The profession with the most missing items; its items all at once.
        local p = Goals.Progress(g)
        local byProf = {}
        for _, part in ipairs(p.parts) do
            local prof = part.missing > 0 and Goals.ProfOf(part.itemID)
            if prof then
                byProf[prof] = byProf[prof] or { n = 0, targets = {} }
                byProf[prof].n = byProf[prof].n + part.missing
                byProf[prof].targets[part.itemID] = true
            end
        end
        local best, bn
        for prof, v in pairs(byProf) do if not bn or v.n > bn then best, bn = prof, v.n end end
        if not best then return nil end
        return { prof = best, goal = "material", targets = byProf[best].targets }
    elseif g.type == "skill" then
        return { prof = g.prof, goal = "level" }
    else
        local profs = HME.Player.Professions()
        for _, p in ipairs({ "Skinning", "Herbalism", "Mining", "Fishing" }) do
            if profs[p] then return { prof = p, goal = "profit" } end
        end
    end
end

-- Best farm for a goal, with time and loops to finish (or nil, why).
-- done(result, eta) in the background when given.
function Goals.Recommend(g, done)
    local q = Goals.Query(g)
    if not q then
        if done then done(nil, "no profession gathers that") end
        return nil
    end
    local profile = HME.Player.Profile()
    HME.Recommend.Find(q, function(results)
        local r = results and results[1]
        if not r then
            if done then done(nil, "no farm found for it") end
            return
        end
        local p = Goals.Progress(g)
        local remaining = math.max(0, (p.target or 0) - (p.have or 0))
        local rate
        if g.type == "skill" then rate = r.metrics.skillRange and r.metrics.skillRange.mid or r.metrics.skillPerHour
        elseif g.type == "value" then rate = r.metrics.range and r.metrics.range.mid
        else rate = r.metrics.materialPerHour end
        local eta
        if rate and rate > 0 then
            local hours = remaining / rate
            eta = { hours = hours, travel = r.travel, loops = r.metrics.lapSecs and (hours * 3600 / r.metrics.lapSecs) or nil,
                rate = rate, remaining = remaining }
        end
        if done then done(r, eta) end
    end, profile)
end

---------------------------------------------------------------------------
-- Sell, keep or use
---------------------------------------------------------------------------
local Advice = {}
HME.Advice = Advice

-- { action = "keep"|"auction"|"vendor"|"unknown", text, value }
function Advice.For(itemID)
    local reserved = HME.char and HME.char.reserved and HME.char.reserved[itemID]
    for _, g in ipairs(List()) do
        if not g.doneAt then
            local wants = g.itemID == itemID
            for _, it in ipairs(g.items or {}) do if it.itemID == itemID then wants = true end end
            if wants then return { action = "keep", text = "Keep: your goal \"" .. g.name .. "\" needs it." } end
        end
    end
    if reserved then return { action = "keep", text = "Keep: you reserved it." } end
    local p = HME.Prices.Get(itemID)
    if not p or (not p.vendor and not p.conservative) then
        return { action = "unknown", text = "No price known yet." }
    end
    if p.conservative and p.source and (not p.vendor or p.conservative > p.vendor * 1.2) then
        return { action = "auction", value = p.conservative, text = ("Auction house: about %s each after the cut (%s, %s). Listings are not sales."):format(
            U.Money(p.conservative, true), p.source, HME.Prices.AgeText(p.age)) }
    end
    if p.vendor then
        return { action = "vendor", value = p.vendor, text = ("Vendor: %s each%s."):format(U.Money(p.vendor, true),
            p.source and "; the auction house pays little more" or "; no auction price known") }
    end
    return { action = "unknown", text = "No price known yet." }
end

---------------------------------------------------------------------------
-- Profiles: saved Farm Finder setups to start again in one click.
---------------------------------------------------------------------------
local Profiles = {}
HME.Profiles = Profiles

local function PList()
    HME.char.profiles = type(HME.char.profiles) == "table" and HME.char.profiles or {}
    return HME.char.profiles
end
Profiles.List = PList

function Profiles.Save(name, state)
    name = U.Trim(name or "")
    if name == "" then return nil, "a name is needed" end
    local p = { name = name:sub(1, 40), prof = state.prof, goal = state.goal, risk = state.risk, material = state.material,
        minutes = state.minutes, filters = U.Copy(state.filters), routeID = state.routeID, mode = state.mode }
    local list = PList()
    for i, old in ipairs(list) do
        if old.name == p.name then
            list[i] = p
            HME.Signal("PROFILES_CHANGED")
            return p
        end
    end
    if #list >= 20 then return nil, "20 profiles at most" end
    list[#list + 1] = p
    HME.Signal("PROFILES_CHANGED")
    return p
end

function Profiles.Delete(name)
    local list = PList()
    for i = #list, 1, -1 do if list[i].name == name then table.remove(list, i) end end
    HME.Signal("PROFILES_CHANGED")
end

-- Puts a profile into the Farm Finder and searches (or resumes its route).
function Profiles.Apply(p)
    if p.minutes then HME.settings.sessionMinutes = p.minutes end
    if p.mode then HME.settings.huntMode = p.mode end
    if p.routeID and HME.Guidance.Route(p.routeID) then
        HME.Guidance.Start(HME.Guidance.Route(p.routeID))
        return "route"
    end
    HME.OpenWindow("finder")
    if HME.Pages.finderSet then HME.Pages.finderSet(p.prof, p.goal, p.material, p.risk, p.filters) end
    return "search"
end
