-- HarvestMate Enhanced: Engine/Session.lua
-- The farming session: one clock and one set of counters for every
-- profession (HarvestMate's and Gatherpedia's session boxes become this).
--
-- It starts by itself on the first gather, skin or catch (or with Start on
-- the HUD), pauses itself after 5 minutes without anything gathered (that
-- idle time never counts) and ends with Stop, a logout, or 30 idle minutes.
-- Time and counts are kept per farming area: the active farm when one is
-- being followed, else "<profession>@<zone>". When a session ends its areas'
-- totals feed Engine/Learning.lua, and a summary goes to the history, with
-- what the Farm Finder had predicted for comparison.
-- Copyright (C) 2026 HarvestMate Enhanced contributors. GPL-3.0-or-later.

local _, ns = ...
local HME = ns.HME
local U = HME.U

local S = {}
HME.Session = S

S.IDLE_PAUSE = 300
S.IDLE_END = 1800

local cur          -- the running session or nil
local function Now() return HME.Now() end

local function NewSession()
    return {
        startedAt = (time and time()) or 0, active = 0, lastTick = Now(), lastActivity = Now(),
        paused = false, counts = { herb = 0, mine = 0, skin = 0, fish = 0, kills = 0 }, items = {},
        value = 0, skillups = 0, deaths = 0, areas = {}, skills = {},
    }
end

function S.Current() return cur end
function S.Running() return cur ~= nil and not cur.paused end

-- The area this activity is counted for.
function S.AreaKey(profShort)
    local g = HME.Guidance and HME.Guidance.Active()
    if g and g.key then return g.key end
    local mapID = HME.Player.Position()
    local zone = mapID and HME.Geo.ZoneOf(mapID) or 0
    return (HME.Player.FROM_SHORT[profShort] or "any") .. "@" .. tostring(zone)
end

local function Tick()
    if not cur then return end
    local now = Now()
    local dt = now - cur.lastTick
    cur.lastTick = now
    if cur.paused then return end
    if now - cur.lastActivity > S.IDLE_PAUSE then
        -- Count up to the moment of the last activity, then pause.
        cur.paused = "idle"
        return
    end
    cur.active = cur.active + dt
    local a = cur.areaNow and cur.areas[cur.areaNow]
    if a then a.secs = a.secs + dt end
end

function S.Start()
    if cur then
        cur.paused = false
        cur.lastTick, cur.lastActivity = Now(), Now()
        HME.Signal("SESSION_CHANGED")
        return cur
    end
    cur = NewSession()
    for k, v in pairs(HME.Player.Professions()) do cur.skills[k] = v.rank end
    HME.Signal("SESSION_CHANGED")
    return cur
end

function S.Pause()
    if not cur then return end
    Tick()
    cur.paused = cur.paused and false or "manual"
    if not cur.paused then cur.lastTick, cur.lastActivity = Now(), Now() end
    HME.Signal("SESSION_CHANGED")
end

local function Area(key)
    local a = cur.areas[key]
    if not a then
        a = { secs = 0, nodes = 0, beasts = 0, skins = 0, catches = 0, skillups = 0, value = 0 }
        cur.areas[key] = a
    end
    return a
end

-- Something was gathered: (re)start the clock, count it.
local function Activity(profShort, what, n, value, items)
    if not HME.db then return end
    if not cur then S.Start() end
    Tick()
    if cur.paused == "idle" then
        cur.paused = false
        cur.lastTick = Now()
    end
    cur.lastActivity = Now()
    local key = S.AreaKey(profShort)
    cur.areaNow = key
    local a = Area(key)
    if what then a[what] = a[what] + (n or 1) end
    if value and value > 0 then
        a.value = a.value + value
        cur.value = cur.value + value
    end
    for id, q in pairs(items or {}) do cur.items[id] = (cur.items[id] or 0) + q end
    HME.Signal("SESSION_CHANGED")
end

local function ItemsValue(items)
    local v = 0
    for id, q in pairs(items or {}) do v = v + (HME.Prices.Value(id) or 0) * q end
    return v
end

HME.Listen("GATHER_LOOT", function(prof, _, counts)
    if prof ~= "herb" and prof ~= "mine" then return end
    if cur and not cur.paused then Tick() end
    Activity(prof, "nodes", 1, ItemsValue(counts), counts)
    if cur then cur.counts[prof] = cur.counts[prof] + 1 end
end)

HME.Listen("BEAST_SKINNED", function(_, items)
    Activity("skin", "skins", 1, ItemsValue(items), items)
    if cur then cur.counts.skin = cur.counts.skin + 1 end
end)

HME.Listen("BEAST_LOOTED", function(_, items)
    if not cur or cur.paused == "manual" then return end
    local total = HME.settings and HME.settings.profitScope == "total"
    Activity("skin", "beasts", 1, total and ItemsValue(items) or 0, total and items or nil)
    if cur then cur.counts.kills = cur.counts.kills + 1 end
end)

HME.Listen("FISH_CAUGHT", function(items)
    Activity("fish", "catches", 1, ItemsValue(items), items)
    if cur then cur.counts.fish = cur.counts.fish + 1 end
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
end)

HME.Listen("PLAYER_DIED", function()
    if cur then cur.deaths = cur.deaths + 1 end
end)

-- Ends the session: areas feed the learned rates, a summary goes to history.
function S.Stop(reason)
    if not cur then return nil end
    Tick()
    local summary = {
        t = cur.startedAt, secs = U.Round(cur.active, 0), value = U.Round(cur.value, 0), skillups = cur.skillups,
        counts = cur.counts, deaths = cur.deaths, reason = reason, areas = {},
    }
    for key, a in pairs(cur.areas) do
        if a.secs >= 60 then
            local hours = a.secs / 3600
            HME.Learning.AddStats(key, { hours = hours, sessions = 1, nodes = a.nodes, beasts = math.max(a.beasts, a.skins),
                skins = a.skins, catches = a.catches, skillups = a.skillups, value = a.value })
            local predicted = HME.Guidance and HME.Guidance.PredictionFor(key)
            summary.areas[#summary.areas + 1] = { key = key, secs = U.Round(a.secs, 0), nodes = a.nodes, beasts = a.beasts,
                skins = a.skins, catches = a.catches, skillups = a.skillups, value = U.Round(a.value, 0), predicted = predicted }
        end
    end
    if summary.secs >= 60 then U.Push(HME.db.sessions, summary, HME.DBM.LIMITS.sessions) end
    cur = nil
    HME.Signal("SESSION_CHANGED")
    HME.Signal("SESSION_ENDED", summary)
    return summary
end

function S.Elapsed()
    if not cur then return 0 end
    Tick()
    return cur.active
end

function S.Rates()
    if not cur then return nil end
    local secs = math.max(S.Elapsed(), 1)
    local h = secs / 3600
    local c = cur.counts
    return {
        secs = secs, value = cur.value, gph = cur.value / h, skillups = cur.skillups, sph = cur.skillups / h,
        nodes = c.herb + c.mine, nph = (c.herb + c.mine) / h, skins = c.skin, kills = c.kills,
        bph = math.max(c.kills, c.skin) / h, catches = c.fish, deaths = cur.deaths, paused = cur.paused,
    }
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

HME.On("PLAYER_LOGOUT", function() if cur then S.Stop("logout") end end)

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
