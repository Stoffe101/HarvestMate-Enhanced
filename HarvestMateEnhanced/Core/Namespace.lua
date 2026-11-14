-- HarvestMate Enhanced: Core/Namespace.lua
-- The addon's private table, the event bus, internal signals, secret-value
-- guards, timers, the background job runner and the diagnostics counters.
--
-- Every other file reads `ns.HME`. Two upstream engines share the same private
-- table under their own names: HarvestMate's at `ns.HG` (Gather/HGCore.lua) and
-- Gatherpedia's helpers directly on `ns` (Core/GPCompat.lua), so their vendored
-- files load with a one-line patch or none at all.
--
-- Copyright (C) 2026 HarvestMate Enhanced contributors. GPL-3.0-or-later.

local ADDON, ns = ...

local HME = {}
ns.HME = HME
HME.ADDON = ADDON
HME.TITLE = "HarvestMate Enhanced"
HME.SHORT = "HarvestMate"

local Meta = (C_AddOns and C_AddOns.GetAddOnMetadata) or _G.GetAddOnMetadata
local version = Meta and Meta(ADDON, "Version")
if type(version) ~= "string" or version:find("@", 1, true) then version = "dev" end
HME.VERSION = version
HME.API_VERSION = 1

---------------------------------------------------------------------------
-- Secret values. On Forever, as on the newest retail clients, some values
-- become "secret" (most often in combat): they cannot be compared, used as a
-- table key or concatenated. Everything read from the client goes through
-- these guards before it is used.
---------------------------------------------------------------------------
local isSecret = _G.issecretvalue
local canAccess = _G.canaccessvalue
local isSecretTable = _G.issecrettable
local canAccessTable = _G.canaccesstable

function HME.Hidden(v)
    if v == nil then return false end
    if isSecret then
        local ok, secret = pcall(isSecret, v)
        if ok and secret then
            if canAccess then
                local ok2, can = pcall(canAccess, v)
                return not (ok2 and can)
            end
            return true
        end
    end
    return false
end

function HME.Str(v)
    if type(v) == "string" and not HME.Hidden(v) and v ~= "" then return v end
    return nil
end

function HME.Num(v)
    if type(v) == "number" and not HME.Hidden(v) and v == v then return v end
    return nil
end

function HME.Tbl(v)
    if type(v) ~= "table" or HME.Hidden(v) then return nil end
    if isSecretTable then
        local ok, secret = pcall(isSecretTable, v)
        if ok and secret then
            local ok2, can = pcall(canAccessTable or function() return false end, v)
            if not (ok2 and can) then return nil end
        end
    end
    return v
end

function HME.Bool(v)
    if type(v) == "boolean" and not HME.Hidden(v) then return v end
    return nil
end

---------------------------------------------------------------------------
-- Errors: a broken module reports to the error frame and the rest go on.
---------------------------------------------------------------------------
local function Report(err)
    local handler = _G.geterrorhandler and _G.geterrorhandler()
    if handler then handler(err) end
    HME.lastError = tostring(err)
    return err
end

-- Plain Lua 5.1's xpcall takes no arguments for fn (the game's does), so they
-- are passed through a closure; both behave the same.
function HME.Try(fn, ...)
    local n = select("#", ...)
    if n == 0 then return xpcall(fn, Report) end
    local args = { ... }
    return xpcall(function() return fn(unpack(args, 1, n)) end, Report)
end

---------------------------------------------------------------------------
-- Chat
---------------------------------------------------------------------------
HME.CHAT_PREFIX = "|cff6fcf97HarvestMate|r |cffe8a040Enhanced|r"
function HME.Print(msg)
    print(HME.CHAT_PREFIX .. ": " .. tostring(msg))
end

function HME.Debug(...)
    if not (HME.db and HME.db.settings and HME.db.settings.debug) then return end
    local parts = {}
    for i = 1, select("#", ...) do parts[i] = tostring((select(i, ...))) end
    print("|cff6fcf97HME|r |cff999999" .. table.concat(parts, " ") .. "|r")
end

---------------------------------------------------------------------------
-- Game events: one frame, many listeners. An event this client does not
-- know is noted (see /hme diag) instead of breaking the load.
---------------------------------------------------------------------------
local bus = CreateFrame("Frame")
local handlers = {}
HME.missingEvents = {}

function HME.On(event, fn, unit)
    local list = handlers[event]
    if not list then
        list = {}
        handlers[event] = list
        local ok
        if unit then
            ok = pcall(bus.RegisterUnitEvent, bus, event, unit)
        else
            ok = pcall(bus.RegisterEvent, bus, event)
        end
        if not ok then HME.missingEvents[#HME.missingEvents + 1] = event end
    end
    list[#list + 1] = fn
end

bus:SetScript("OnEvent", function(_, event, ...)
    local list = handlers[event]
    if not list then return end
    for i = 1, #list do HME.Try(list[i], event, ...) end
end)

-- Test hook: feed an event as if the client sent it.
function HME.Fire(event, ...)
    local list = handlers[event]
    if not list then return end
    for i = 1, #list do HME.Try(list[i], event, ...) end
end

---------------------------------------------------------------------------
-- Internal signals between modules (never the game's events).
---------------------------------------------------------------------------
local signals = {}
function HME.Listen(name, fn)
    signals[name] = signals[name] or {}
    table.insert(signals[name], fn)
end

function HME.Signal(name, ...)
    local list = signals[name]
    if not list then return end
    for i = 1, #list do HME.Try(list[i], ...) end
end

---------------------------------------------------------------------------
-- Timers
---------------------------------------------------------------------------
function HME.After(delay, fn)
    if C_Timer and C_Timer.After then
        C_Timer.After(delay, function() HME.Try(fn) end)
    else
        HME.Try(fn)
    end
end

-- Several calls within `delay` collapse into one.
local queued = {}
function HME.Soon(id, delay, fn)
    if queued[id] then return end
    queued[id] = true
    HME.After(delay, function()
        queued[id] = nil
        fn()
    end)
end

function HME.Now()
    return (GetTime and GetTime()) or 0
end

function HME.Clock()
    if debugprofilestop then return debugprofilestop() end
    return HME.Now() * 1000
end

function HME.InCombat()
    if not InCombatLockdown then return false end
    local ok, v = pcall(InCombatLockdown)
    return ok and v == true
end

---------------------------------------------------------------------------
-- Background jobs. Heavy work (planning a route, ranking every zone) runs as
-- a coroutine a few milliseconds a frame, so the client never freezes. Jobs
-- queue; one runs at a time. A job calls HME.Yield() now and then.
---------------------------------------------------------------------------
local Jobs = { queue = {}, budget = 8 }
HME.Jobs = Jobs

function HME.Yield()
    local co = coroutine.running()
    if co and Jobs.current and Jobs.current.co == co then coroutine.yield() end
end

local driver = CreateFrame("Frame")
local function Step()
    local job = Jobs.current
    if not job then
        job = table.remove(Jobs.queue, 1)
        if not job then
            driver:SetScript("OnUpdate", nil)
            return
        end
        Jobs.current = job
        job.started = HME.Clock()
    end
    local start = HME.Clock()
    local budget = Jobs.budget
    if HME.db and HME.db.settings and HME.db.settings.performance == "low" then budget = 4 end
    repeat
        local ok, a, b = coroutine.resume(job.co)
        if not ok then
            Jobs.current = nil
            Report(("HarvestMate Enhanced job %s failed: %s"):format(job.name, tostring(a)))
            if job.fail then HME.Try(job.fail, a) end
            return
        end
        if coroutine.status(job.co) == "dead" then
            Jobs.current = nil
            HME.Perf.Add("job:" .. job.name, HME.Clock() - job.started)
            if job.done then HME.Try(job.done, a, b) end
            return
        end
    until HME.Clock() - start > budget
end

-- Runs fn in the background. done(result...) when it finishes. A job with the
-- same `key` already waiting is replaced, so repeated requests coalesce.
function HME.RunJob(name, fn, done, opts)
    opts = opts or {}
    local job = { name = name, co = coroutine.create(fn), done = done, fail = opts.fail, key = opts.key }
    if job.key then
        for i = #Jobs.queue, 1, -1 do
            if Jobs.queue[i].key == job.key then table.remove(Jobs.queue, i) end
        end
    end
    Jobs.queue[#Jobs.queue + 1] = job
    driver:SetScript("OnUpdate", Step)
    return job
end

-- Tests and /hme diag: run every queued job to the end right now.
function HME.FinishJobs(limit)
    limit = limit or 1e6
    local n = 0
    while (Jobs.current or #Jobs.queue > 0) and n < limit do
        Step()
        n = n + 1
    end
    return n
end

function HME.Busy() return Jobs.current ~= nil or #Jobs.queue > 0 end

---------------------------------------------------------------------------
-- Diagnostics: how often and how long the expensive parts run.
---------------------------------------------------------------------------
local Perf = { stats = {} }
HME.Perf = Perf
function Perf.Add(name, ms)
    local s = Perf.stats[name]
    if not s then
        s = { n = 0, total = 0, max = 0 }
        Perf.stats[name] = s
    end
    s.n = s.n + 1
    s.total = s.total + ms
    if ms > s.max then s.max = ms end
end

function Perf.Measure(name, fn, ...)
    local t = HME.Clock()
    local a, b, c, d = fn(...)
    Perf.Add(name, HME.Clock() - t)
    return a, b, c, d
end

function Perf.Lines()
    local names = {}
    for k in pairs(Perf.stats) do names[#names + 1] = k end
    table.sort(names)
    local out = {}
    for _, k in ipairs(names) do
        local s = Perf.stats[k]
        out[#out + 1] = ("%s: %d runs, avg %.1f ms, max %.1f ms"):format(k, s.n, s.total / s.n, s.max)
    end
    return out
end

---------------------------------------------------------------------------
-- Module registry: modules can be switched off one by one (settings) and the
-- rest keeps working. Each module: { name, settingKey, init, enable, disable }.
---------------------------------------------------------------------------
HME.modules = {}
function HME.Module(name, def)
    def = def or {}
    def.name = name
    HME.modules[#HME.modules + 1] = def
    HME.modules[name] = def
    return def
end

-- The public, versioned surface other addons may use (see ARCHITECTURE.md).
-- Only functions listed in API are supported; everything else is private.
_G.HarvestMateEnhanced = { API = {}, VERSION = HME.VERSION, API_VERSION = HME.API_VERSION }
HME.Public = _G.HarvestMateEnhanced
