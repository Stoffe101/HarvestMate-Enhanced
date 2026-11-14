-- HarvestMate Enhanced: Engine/Session.lua
-- The farming session: one clock and one set of counters for every
-- profession (HarvestMate's and Gatherpedia's session boxes become this).
--
-- Time is split, so a farm's productivity is never diluted by the trip:
--   travel    getting to the farm (Map/Guidance.lua measures it, BeginFarm)
--   farm      active farming: from the first gather/skin/catch or arrival,
--             minus idle time. Made of:
--     combat    in combat
--     gather    casting a gather, skin or fishing cast, and looting
--     wait      everything else while farming: walking between nodes,
--               searching, waiting for respawns
--   idle      no gather, skin, catch or combat for `idleMinutes` (Settings,
--             default 5): that stretch is taken back out of farming
--   total     wall-clock time since the session began, including travel
-- Gold/hour is reported two ways: farming (value / farm time) and trip
-- (value / (farm + travel)). Learned area rates use farming time only; the
-- travel to each area is learned separately for opportunity-cost rankings.
--
-- The running session is saved per character, so /reload, a disconnect or
-- a crash keeps it; time the game was closed never counts.
-- Copyright (C) 2026 HarvestMate Enhanced contributors. GPL-3.0-or-later.

local _, ns = ...
local HME = ns.HME
local U = HME.U

local S = {}
HME.Session = S

S.IDLE_END = 1800

local cur          -- the running session (also HME.char.session) or nil
local inCombat, combatSince = false, nil
local castSince = nil

local function Now() return HME.Now() end
local function IdleLimit() return ((HME.settings and HME.settings.idleMinutes) or 5) * 60 end

local function NewSession()
    return {
        startedAt = (time and time()) or 0, clockStart = Now(), farm = 0, travel = 0, combat = 0, gather = 0,
        idle = 0, lastTick = Now(), lastActivity = Now(), paused = false,
        counts = { herb = 0, mine = 0, skin = 0, fish = 0, kills = 0 }, items = {}, value = 0,
        skillups = 0, deaths = 0, areas = {}, skills = {}, seen = {}, events = {},
    }
end

local function Save()
    if HME.char then HME.char.session = cur end
end

function S.Current() return cur end
function S.Running() return cur ~= nil and not cur.paused end

function S.AreaKey(profShort)
    local g = HME.Guidance and HME.Guidance.Active()
    if g and g.key and g.phase == "farm" then return g.key end
    local mapID = HME.Player.Position()
    local zone = mapID and HME.Geo.ZoneOf(mapID) or 0
    return (HME.Player.FROM_SHORT[profShort] or "any") .. "@" .. tostring(zone)
end

local function Area(key)
    local a = cur.areas[key]
    if not a then
        a = { secs = 0, nodes = 0, beasts = 0, skins = 0, catches = 0, skillups = 0, value = 0, items = {} }
        cur.areas[key] = a
    end
    return a
end

-- Advances the clocks to now.
local function Tick()
    if not cur then return end
    local now = Now()
    local dt = now - cur.lastTick
    cur.lastTick = now
    if dt <= 0 then return end
    if dt > 120 then dt = 0 end          -- the game was frozen or closed: never counts
    if cur.paused then return end
    local quiet = now - cur.lastActivity
    if quiet > IdleLimit() and not inCombat then
        -- The farming time counted since the last activity goes back out.
        local back = cur.quietFarm or 0
        cur.paused = "idle"
        cur.farm = math.max(0, cur.farm - back)
        cur.idle = cur.idle + back
        local a = cur.areaNow and cur.areas[cur.areaNow]
        if a then a.secs = math.max(0, a.secs - back) end
        cur.quietFarm = 0
        Save()
        HME.Signal("SESSION_CHANGED")
        return
    end
    cur.quietFarm = (cur.quietFarm or 0) + dt
    cur.farm = cur.farm + dt
    if inCombat then cur.combat = cur.combat + dt end
    if castSince then cur.gather = cur.gather + dt end
    local a = cur.areaNow and cur.areas[cur.areaNow]
    if a then a.secs = a.secs + dt end
end

function S.Start()
    if cur then
        if cur.paused then
            cur.paused = false
            cur.lastTick, cur.lastActivity = Now(), Now()
            Save()
            HME.Signal("SESSION_CHANGED")
        end
        return cur
    end
    cur = NewSession()
    for k, v in pairs(HME.Player.Professions()) do cur.skills[k] = v.rank end
    Save()
    HME.Signal("SESSION_CHANGED")
    return cur
end

-- Arrived at a farm (Map/Guidance.lua): the trip's travel time goes on record.
function S.BeginFarm(key, travelSecs)
    if not cur then S.Start() end
    Tick()
    cur.travel = cur.travel + math.max(0, travelSecs or 0)
    cur.areaNow = key
    local a = Area(key)
    a.travel = (a.travel or 0) + math.max(0, travelSecs or 0)
    cur.lastActivity = Now()
    if cur.paused == "idle" then cur.paused = false end
    Save()
    HME.Signal("SESSION_CHANGED")
end

function S.Pause()
    if not cur then return end
    Tick()
    cur.paused = cur.paused and false or "manual"
    if not cur.paused then cur.lastTick, cur.lastActivity = Now(), Now() end
    Save()
    HME.Signal("SESSION_CHANGED")
end

-- Something was gathered: (re)start the clock, count it. `id` (a loot
-- source and time) suppresses duplicates of the same event.
local function Activity(profShort, what, n, value, items, id)
    if not HME.db then return false end
    if not cur then S.Start() end
    if id then
        if cur.seen[id] then return false end
        -- Bounded: a duplicate arrives within seconds, so the newest 500 are enough.
        cur.seenN = (cur.seenN or 0) + 1
        if cur.seenN > 500 then
            cur.seen, cur.seenN = {}, 1
        end
        cur.seen[id] = true
    end
    Tick()
    if cur.paused == "idle" then
        cur.paused = false
        cur.lastTick = Now()
    end
    cur.lastActivity = Now()
    cur.quietFarm = 0
    -- When, on the farming clock: for the rolling rates (newest 400).
    cur.events = cur.events or {}
    U.Push(cur.events, { f = cur.farm, k = what }, 400)
    local key = S.AreaKey(profShort)
    cur.areaNow = key
    local a = Area(key)
    if what then a[what] = a[what] + (n or 1) end
    if value and value > 0 then
        a.value = a.value + value
        cur.value = cur.value + value
    end
    for itemID, q in pairs(items or {}) do
        cur.items[itemID] = (cur.items[itemID] or 0) + q
        a.items[itemID] = (a.items[itemID] or 0) + q
    end
    Save()
    HME.Signal("SESSION_CHANGED")
    return true
end

local function ItemsValue(items, which)
    local v = 0
    for id, q in pairs(items or {}) do v = v + (HME.Prices.Value(id, which) or 0) * q end
    return v
end
S.ItemsValue = ItemsValue

HME.Listen("GATHER_LOOT", function(prof, _, counts)
    if prof ~= "herb" and prof ~= "mine" then return end
    if Activity(prof, "nodes", 1, ItemsValue(counts), counts) and cur then cur.counts[prof] = cur.counts[prof] + 1 end
end)

HME.Listen("BEAST_SKINNED", function(npcID, items, guid)
    if Activity("skin", "skins", 1, ItemsValue(items), items, guid and ("skin:" .. guid)) and cur then
        cur.counts.skin = cur.counts.skin + 1
    end
end)

HME.Listen("BEAST_LOOTED", function(npcID, items, guid)
    if not cur or cur.paused == "manual" then return end
    local total = HME.settings and HME.settings.profitScope == "total"
    if Activity("skin", "beasts", 1, total and ItemsValue(items) or 0, total and items or nil, guid and ("loot:" .. guid)) then
        cur.counts.kills = cur.counts.kills + 1
    end
end)

HME.Listen("FISH_CAUGHT", function(items)
    if Activity("fish", "catches", 1, ItemsValue(items), items) and cur then cur.counts.fish = cur.counts.fish + 1 end
end)

HME.Listen("PLAYER_CHANGED", function()
    if not cur then return end
    for k, v in pairs(HME.Player.Professions()) do
        local before = cur.skills[k]
        if before and v.rank > before then
            local up = v.rank - before
            cur.skillups = cur.skillups + up
            if cur.areaNow then Area(cur.areaNow).skillups = Area(cur.areaNow).skillups + up end
            HME.Signal("SKILL_UP", k, v.rank, up)
        end
        cur.skills[k] = v.rank
    end
    Save()
end)

HME.Listen("PLAYER_DIED", function() if cur then cur.deaths = cur.deaths + 1 end end)

-- Combat and casting time (no protected calls; plain events).
HME.On("PLAYER_REGEN_DISABLED", function()
    Tick()
    inCombat, combatSince = true, Now()
    if cur and not cur.paused then cur.lastActivity, cur.quietFarm = Now(), 0 end
end)
HME.On("PLAYER_REGEN_ENABLED", function()
    Tick()
    inCombat = false
    if cur and not cur.paused then cur.lastActivity, cur.quietFarm = Now(), 0 end
end)
HME.Listen("GATHER_START", function()
    Tick()
    castSince = Now()
end)
local function CastEnd() Tick() castSince = nil end
HME.On("UNIT_SPELLCAST_STOP", CastEnd, "player")
HME.On("LOOT_CLOSED", CastEnd)

-- Ends the session: farming time feeds the learned area rates, travel is
-- learned apart, and a summary goes to the history.
function S.Stop(reason)
    if not cur then return nil end
    Tick()
    local farmSecs = U.Round(cur.farm, 0)
    local summary = {
        t = cur.startedAt, secs = farmSecs, farmSecs = farmSecs, travelSecs = U.Round(cur.travel, 0),
        combatSecs = U.Round(cur.combat, 0), gatherSecs = U.Round(cur.gather, 0), idleSecs = U.Round(cur.idle, 0),
        totalSecs = U.Round(Now() - (cur.clockStart or Now()), 0),
        value = U.Round(cur.value, 0), skillups = cur.skillups, counts = cur.counts, deaths = cur.deaths, reason = reason,
        areas = {}, items = cur.items, char = UnitName and HME.Str((UnitName("player"))) or nil,
        route = HME.Guidance and HME.Guidance.Active() and HME.Guidance.Active().name or nil,
    }
    for key, a in pairs(cur.areas) do
        if a.secs >= 60 then
            local hours = a.secs / 3600
            local skillGph = a.value / hours
            HME.Learning.AddStats(key, { hours = hours, sessions = 1, nodes = a.nodes, beasts = math.max(a.beasts, a.skins),
                skins = a.skins, catches = a.catches, skillups = a.skillups, value = a.value,
                travelHours = (a.travel or 0) / 3600, trips = (a.travel or 0) > 0 and 1 or 0 })
            HME.Learning.AddSample(key, { h = hours, gph = skillGph, sph = a.skillups / hours,
                nph = (a.nodes + math.max(a.beasts, a.skins) + a.catches) / hours })
            local predicted = HME.Guidance and HME.Guidance.PredictionFor(key)
            summary.areas[#summary.areas + 1] = { key = key, secs = U.Round(a.secs, 0), nodes = a.nodes, beasts = a.beasts,
                skins = a.skins, catches = a.catches, skillups = a.skillups, value = U.Round(a.value, 0),
                travel = U.Round(a.travel or 0, 0), predicted = predicted, items = a.items }
        end
    end
    if summary.farmSecs >= 60 then U.Push(HME.db.sessions, summary, HME.DBM.LIMITS.sessions) end
    cur = nil
    Save()
    HME.Signal("SESSION_CHANGED")
    HME.Signal("SESSION_ENDED", summary)
    return summary
end

function S.Elapsed()
    if not cur then return 0 end
    Tick()
    return cur.farm
end

function S.Rates()
    if not cur then return nil end
    Tick()
    local farm = math.max(cur.farm, 1)
    local h = farm / 3600
    local trip = (cur.farm + cur.travel) / 3600
    local c = cur.counts
    return {
        secs = cur.farm, farmSecs = cur.farm, travelSecs = cur.travel, combatSecs = cur.combat,
        gatherSecs = cur.gather, idleSecs = cur.idle,
        waitSecs = math.max(0, cur.farm - cur.combat - cur.gather),
        value = cur.value, gph = cur.value / h, tripGph = cur.value / math.max(trip, 1 / 3600),
        skillups = cur.skillups, sph = cur.skillups / h,
        nodes = c.herb + c.mine, nph = (c.herb + c.mine) / h, skins = c.skin, kills = c.kills,
        bph = math.max(c.kills, c.skin) / h, catches = c.fish, deaths = cur.deaths, paused = cur.paused,
        items = cur.items,
    }
end

---------------------------------------------------------------------------
-- While farming: rolling rates, materials, pace, and observed vs predicted.
---------------------------------------------------------------------------
S.LIVE_WINDOW = 20 * 60     -- the rolling window: the last 20 farming minutes
S.LIVE_MIN_SECS = 10 * 60   -- no verdict before 10 farming minutes...
S.LIVE_MIN_EVENTS = 8       -- ...and 8 gathers, skins or catches

local function ItemName(id)
    return ns.ItemNameByID(id) or ("item " .. id)
end

-- Everything the HUD and Dashboard show about the session going on now.
function S.Live()
    if not cur then return nil end
    Tick()
    local farm = cur.farm
    local h = math.max(farm, 1) / 3600
    local c = cur.counts
    local out = { farmSecs = farm, skins = c.skin, kills = c.kills, nodes = c.herb + c.mine, catches = c.fish,
                  value = cur.value, skillups = cur.skillups, perHour = {}, recent = {}, items = {} }
    out.perHour.skins, out.perHour.kills = c.skin / h, c.kills / h
    out.perHour.nodes, out.perHour.catches = (c.herb + c.mine) / h, c.fish / h
    out.perHour.value, out.perHour.skill = cur.value / h, cur.skillups / h
    -- The rolling window: events within the last LIVE_WINDOW farming seconds.
    local from = math.max(0, farm - S.LIVE_WINDOW)
    local span = math.max(60, farm - from)
    local counts = {}
    for _, e in ipairs(cur.events or {}) do
        if e.f >= from then counts[e.k or "?"] = (counts[e.k or "?"] or 0) + 1 end
    end
    for k, n in pairs(counts) do out.recent[k] = n / span * 3600 end
    out.recentMinutes = span / 60
    -- Materials, most first, with their rate.
    for id, n in pairs(cur.items or {}) do out.items[#out.items + 1] = { id = id, name = ItemName(id), n = n, perHour = n / h } end
    table.sort(out.items, function(a, b) return a.n > b.n end)
    -- Pace: kill time from this session's clear fights, time between skins.
    local sum, nk = 0, 0
    for _, k in ipairs((HME.char and HME.char.eff and HME.char.eff.kill) or {}) do
        if (k.t or 0) >= (cur.startedAt or 0) then sum, nk = sum + (k.s or 0), nk + 1 end
    end
    out.avgKill, out.killSamples = nk > 0 and sum / nk or nil, nk
    out.betweenSkins = c.skin > 0 and farm / c.skin or nil
    -- Observed against what the farm was predicted to give.
    local pred = cur.areaNow and HME.Guidance and HME.Guidance.PredictionFor(cur.areaNow)
    if pred then
        local events = c.skin + c.herb + c.mine + c.fish
        local enough = farm >= S.LIVE_MIN_SECS and events >= S.LIVE_MIN_EVENTS
        local metric, observed, expected, unit
        if (pred.skins or 0) > 0 and c.skin > 0 then metric, observed, expected, unit = "skins", out.perHour.skins, pred.skins, "skins"
        elseif (pred.nodes or 0) > 0 then metric, observed, expected, unit = "nodes", out.perHour.nodes, pred.nodes, "nodes"
        elseif (pred.catches or 0) > 0 then metric, observed, expected, unit = "catches", out.perHour.catches, pred.catches, "catches"
        elseif (pred.beasts or 0) > 0 then metric, observed, expected, unit = "kills", out.perHour.kills, pred.beasts, "kills" end
        if metric then
            local ratio = expected > 0 and observed / expected or nil
            out.verdict = { metric = metric, observed = observed, expected = expected, ratio = ratio, enough = enough, events = events }
            if not enough then
                out.verdict.text = ("%.0f %s/h so far (predicted %.0f): too early to judge (%d min, %d events)"):format(
                    observed, unit, expected, farm / 60, events)
            else
                local how = ratio >= 1.15 and "better than predicted" or (ratio <= 0.85 and "below the prediction" or "about as predicted")
                out.verdict.text = ("%.0f %s/h vs %.0f predicted after %d min: %s. This farm's numbers for you follow when the session ends."):format(
                    observed, unit, expected, farm / 60, how)
            end
        end
        if pred.items then
            for _, it in ipairs(out.items) do
                if pred.items[it.id] then it.expectedPerHour = pred.items[it.id] end
            end
        end
    end
    return out
end

-- Clock: once a second while running; ends a long-idle session.
do
    local f = CreateFrame("Frame")
    local acc = 0
    f:SetScript("OnUpdate", function(_, dt)
        acc = acc + dt
        if acc < 1 then return end
        acc = 0
        if not cur then return end
        Tick()
        if Now() - cur.lastActivity > S.IDLE_END then S.Stop("idle") end
        HME.Player.SampleSpeed()
    end)
end

-- Restore after /reload or a disconnect. GetTime keeps counting across a
-- reload; after a relog it restarts, so the clocks are simply re-based and
-- the time the game was closed never counts.
HME.Listen("DB_READY", function()
    local saved = HME.char and HME.char.session
    if type(saved) ~= "table" or type(saved.counts) ~= "table" then return end
    local away = ((time and time()) or 0) - (saved.savedAt or saved.startedAt or 0)
    if away > S.IDLE_END then
        cur = saved
        cur.lastTick, cur.lastActivity = Now(), Now()
        S.Stop("closed")
        return
    end
    cur = saved
    cur.seen = cur.seen or {}
    cur.lastTick = Now()
    cur.lastActivity = Now()
    cur.clockStart = Now() - (cur.farm + cur.travel + cur.idle)
end)
HME.On("PLAYER_LOGOUT", function()
    if cur then
        Tick()
        cur.savedAt = (time and time()) or 0
        Save()
    end
end)

---------------------------------------------------------------------------
-- HarvestMate's Stats.lua (records, achievements) reads these.
---------------------------------------------------------------------------
local HG = ns.HG
HG.session = setmetatable({}, { __index = function(_, k)
    if k == "gathers" then
        return cur and (cur.counts.herb + cur.counts.mine + cur.counts.skin) or 0
    end
end })
function HG.SessionElapsed() return S.Elapsed() end
function HG.SessionValue() return cur and cur.value or 0 end
function HG.SessionProfession(prof) return cur and (cur.counts[prof] or 0) > 0 or false end
function HG.SessionReset() S.Stop("reset") end
function HG.ToggleSession() if HME.HUD then HME.HUD.Toggle() end end
