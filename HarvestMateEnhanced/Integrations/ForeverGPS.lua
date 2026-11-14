-- HarvestMate Enhanced: Integrations/ForeverGPS.lua
-- The bridge to Forever-GPS (separate and optional). HME owns farms, loops
-- and farming stats; Forever-GPS owns getting there.
--
-- Ownership is tracked per request, never with a flag. A request is
--   { token, mapID, x, y, label, t, state, apiToken }
-- and moves through these states (each transition is idempotent, so a
-- duplicated or late event changes nothing):
--   pending     HME asked; Forever-GPS has not started a journey yet
--   active      a journey started whose destination matches the request
--               (within MATCH_YARDS on the same map) — HME's journey
--   arrived     that journey arrived (Forever-GPS's later clear is ignored)
--   cancelled   that journey was cleared before arriving (the player stopped it)
--   superseded  a journey to somewhere else started: it is the player's, not HME's
--   released    HME stopped its own journey (arrived at the farm on foot)
--   stale       after a reload nothing matching the request is running
-- HME only ever stops a journey that is "active" AND whose destination still
-- matches the request at that moment.
--
-- Two ways to talk to Forever-GPS, both feature-detected and pcall-wrapped:
--  * ForeverGPS.API (VERSION >= 1, proposed in docs/FOREVERGPS_BRIDGE.md and
--    on the Forever-GPS branch feature/public-api): tokens, Status, Release.
--  * Forever-GPS 2.x without it: its journey panel (Search.CoordsFor +
--    Planner.Inspect), the same as "/fgps way"; the player presses Go there.
--    Journeys are recognised from its route:started / route:arrived (with the
--    destination) and route:cleared topics.
-- Copyright (C) 2026 HarvestMate Enhanced contributors. GPL-3.0-or-later.

local _, ns = ...
local HME = ns.HME

local B = {}
HME.FGPS = B

B.MIN_VERSION = "2.0"
B.MATCH_YARDS = 80

local function FG()
    local g = _G.ForeverGPS
    return type(g) == "table" and g or nil
end

local function API()
    local g = FG()
    local api = g and type(g.API) == "table" and g.API or nil
    if api and (tonumber(api.VERSION) or 0) >= 1 and type(api.NavigateTo) == "function" then return api end
    return nil
end

local function VersionAtLeast(v, want)
    if type(v) ~= "string" then return false end
    local a1, a2 = v:match("^(%d+)%.(%d+)")
    local b1, b2 = want:match("^(%d+)%.(%d+)")
    a1, a2, b1, b2 = tonumber(a1), tonumber(a2), tonumber(b1), tonumber(b2)
    if not (a1 and b1) then return false end
    return a1 > b1 or (a1 == b1 and a2 >= b2)
end

function B.Mode()
    local g = FG()
    if not g then return nil, "Forever-GPS is not installed" end
    if API() then return "api" end
    if not VersionAtLeast(g.VERSION, B.MIN_VERSION) then
        return nil, "Forever-GPS " .. tostring(g.VERSION) .. " is older than " .. B.MIN_VERSION
    end
    local S, P, W = g.Search, g.Planner, g.Window
    if type(S) == "table" and type(S.CoordsFor) == "function" and type(S.Target) == "function"
        and type(P) == "table" and type(P.Inspect) == "function" and type(W) == "table" then
        return "panel"
    end
    return nil, "this Forever-GPS version has no way to take a destination"
end

function B.Available() return B.Mode() ~= nil and (not HME.settings or HME.settings.forevergps ~= false) end

function B.Status()
    local mode, why = B.Mode()
    if mode == "api" then return "Forever-GPS " .. tostring(FG().VERSION) .. " (bridge API)" end
    if mode == "panel" then return "Forever-GPS " .. tostring(FG().VERSION) .. " (journey panel)" end
    return why
end

---------------------------------------------------------------------------
-- The request, kept per character so a reload can check it.
---------------------------------------------------------------------------
local function Req()
    return HME.char and HME.char.fgpsRequest
end

local function SetState(state, why)
    local r = Req()
    if not r or r.state == state then return false end
    r.state = state
    r.changedAt = (time and time()) or 0
    HME.Debug("Forever-GPS request", r.token, "->", state, why or "")
    return true
end

function B.State(token)
    local r = Req()
    if not r then return nil end
    if token and r.token ~= token then return nil end
    return r.state
end

function B.Token() local r = Req() return r and r.token end

-- Does a Forever-GPS destination ({ mapID, x, y }) match the request?
local function Matches(dest, r)
    if type(dest) ~= "table" or not r then return false end
    local m, x, y = HME.Num(dest.mapID or dest.m), HME.Num(dest.x), HME.Num(dest.y)
    if not (m and x and y) then return false end
    local zm, zx, zy = m, x, y
    if m ~= r.mapID then zm, zx, zy = HME.Geo.ZoneOf(m, x, y) end
    if zm ~= r.mapID or not zx then return false end
    return HME.Geo.Distance(r.mapID, zx, zy, r.x, r.y) <= B.MATCH_YARDS
end
B.Matches = Matches

local seq = 0
local function NewToken()
    seq = seq + 1
    return ("hme-%d-%d"):format((time and time()) or 0, seq)
end

local function ZoneName(mapID) return HME.ZoneData.Name(mapID) end

-- Asks Forever-GPS to take the player to a point. Returns token or nil, why.
function B.NavigateTo(mapID, x, y, label)
    local mode, why = B.Mode()
    if not mode then return nil, why end
    local g = FG()
    local req = { token = NewToken(), mapID = mapID, x = x, y = y, label = label, t = (time and time()) or 0,
        state = "pending", mode = mode }
    if mode == "api" then
        -- start = true: the player just asked HME for directions.
        local ok, apiToken, reason = pcall(g.API.NavigateTo, { mapID = mapID, x = x, y = y, label = label,
            source = "HarvestMateEnhanced", start = true })
        if not ok or not apiToken then return nil, ok and reason or apiToken end
        req.apiToken = apiToken
    else
        local text = ("%s %.1f %.1f"):format(ZoneName(mapID), x * 100, y * 100)
        local ok, result = pcall(g.Search.CoordsFor, text)
        if not ok or not result then return nil, "Forever-GPS could not place " .. text end
        local ok2, err = pcall(function()
            if g.Window.Show then g.Window.Show("search") end
            local target = g.Search.Target(result)
            if label then target.name = label end
            g.Planner.Inspect(target)
            if g.Window.ShowRoute then g.Window.ShowRoute() end
        end)
        if not ok2 then return nil, tostring(err) end
        HME.Print("Forever-GPS has the journey: press Go there to set off. HME takes over at the farm.")
    end
    HME.char.fgpsRequest = req
    return req.token
end

-- The journey Forever-GPS is following now: { mapID, x, y } or nil.
function B.CurrentJourney()
    local g = FG()
    if not g then return nil end
    local api = API()
    if api and type(api.Current) == "function" then
        local ok, cur = pcall(api.Current)
        return ok and type(cur) == "table" and cur or nil
    end
    local br = type(g.Bridge) == "table" and g.Bridge
    if br and type(br.ActiveRoute) == "function" then
        local ok, route = pcall(br.ActiveRoute)
        if ok and type(route) == "table" then return route.dest or route end
    end
    return nil
end

-- Is Forever-GPS navigating somewhere that is not HME's request?
function B.ForeignJourney()
    local cur = B.CurrentJourney()
    if not cur then return false end
    local r = Req()
    if r and (r.state == "active" or r.state == "pending") and (cur.token == r.apiToken and r.apiToken or Matches(cur, r)) then
        return false
    end
    return true
end

-- Stops HME's own journey: only while it is active and still the one running.
function B.Release(token)
    local r = Req()
    if not r or (token and r.token ~= token) then return false end
    if r.state ~= "active" and r.state ~= "pending" then return false end
    local g = FG()
    if not g then return false end
    if r.apiToken and API() and type(g.API.Release) == "function" then
        local ok, done = pcall(g.API.Release, r.apiToken)
        if ok and done then SetState("released") return true end
        return false
    end
    if r.state == "pending" then
        -- Never started: nothing of HME's is running.
        SetState("released", "not started")
        return true
    end
    local cur = B.CurrentJourney()
    if cur and Matches(cur, r) and type(g.StopNavigation) == "function" then
        SetState("released")
        pcall(g.StopNavigation)
        return true
    end
    return false
end

---------------------------------------------------------------------------
-- The arrow (API v2): HME may ask Forever-GPS to pause its arrow while HME
-- guides a loop beside another journey. The journey is never touched.
---------------------------------------------------------------------------
-- Version 2 or later; each feature is checked where it is used.
local function APIv2()
    local api = API()
    if api and (tonumber(api.VERSION) or 0) >= 2 then return api end
    return nil
end
B.APIv2 = APIv2

function B.CanHoldArrow()
    local api = APIv2()
    return api ~= nil and type(api.HoldArrow) == "function" and type(api.ReleaseArrow) == "function"
end

function B.HoldArrow(reason)
    local api = APIv2()
    if not (api and B.CanHoldArrow()) then return nil end
    local ok, id = pcall(api.HoldArrow, "HarvestMateEnhanced", reason)
    return ok and type(id) == "string" and id or nil
end

function B.ReleaseArrow(id)
    local api = APIv2()
    if not (api and id) then return false end
    local ok, done = pcall(api.ReleaseArrow, id)
    return ok and done == true
end

function B.ArrowHoldStands(id)
    local api = APIv2()
    if not (api and id and type(api.ArrowHeld) == "function") then return false end
    local ok, held, list = pcall(api.ArrowHeld)
    if not (ok and held and type(list) == "table") then return false end
    for _, h in ipairs(list) do if h.id == id then return true end end
    return false
end

-- Forgets the request (HME's farm stopped). Releases it first if it is HME's.
function B.Forget()
    B.Release()
    if HME.char then HME.char.fgpsRequest = nil end
end

---------------------------------------------------------------------------
-- Events from Forever-GPS
---------------------------------------------------------------------------
local function OnStarted(dest, apiToken)
    local r = Req()
    local live = r and (r.state == "pending" or r.state == "active")
    local ours = live and ((apiToken and r.apiToken and apiToken == r.apiToken) or (not apiToken and Matches(dest, r)))
    if ours then
        if SetState("active") then HME.Guidance.OnExternalStarted(r.token) end
        return
    end
    if live and SetState("superseded", "another destination started") then
        HME.Guidance.OnExternalSuperseded(r.token)
    end
    -- Not HME's journey: whatever HME shows steps aside for it.
    HME.Guidance.OnExternalStarted(nil)
end

local function OnArrived(dest, apiToken)
    local r = Req()
    if not r or r.state ~= "active" then return end
    local ours = (apiToken and r.apiToken and apiToken == r.apiToken) or (not apiToken and Matches(dest, r))
    if ours and SetState("arrived") then HME.Guidance.OnExternalArrived(r.token) end
end

local function OnCleared(apiToken)
    local r = Req()
    if not r or r.state ~= "active" then return end
    if apiToken and r.apiToken and apiToken ~= r.apiToken then return end
    if SetState("cancelled", "cleared before arriving") then HME.Guidance.OnExternalCleared(r.token) end
end
B._OnStarted, B._OnArrived, B._OnCleared = OnStarted, OnArrived, OnCleared

-- After a reload (or any doubt): does the saved request still describe what runs?
function B.Reconcile()
    local r = Req()
    if not r then return end
    if not (r.state == "pending" or r.state == "active") then return end
    local api = API()
    if r.apiToken and api and type(api.Status) == "function" then
        local ok, st = pcall(api.Status, r.apiToken)
        if ok and st == "active" then SetState("active") return end
        if ok and st == "pending" then return end
        SetState(ok and st == "arrived" and "arrived" or "stale", "after reload")
    else
        local cur = B.CurrentJourney()
        if cur and Matches(cur, r) then
            SetState("active")
            return
        end
        -- A request that was never started stays pending a while (the panel may be open).
        if r.state == "pending" and ((time and time()) or 0) - (r.t or 0) < 600 then return end
        SetState("stale", "nothing matching runs")
    end
    HME.Guidance.OnExternalStale(r.token)
end

local hooked = false
local function Hook()
    if hooked then return end
    local g = FG()
    if not g then return end
    local api = API()
    if api and type(api.On) == "function" then
        pcall(api.On, "started", function(token, dest) OnStarted(dest, token) end)
        pcall(api.On, "arrived", function(token, dest) OnArrived(dest, token) end)
        pcall(api.On, "cancelled", function(token) OnCleared(token) end)
        pcall(api.On, "superseded", function(token)
            local r = Req()
            if r and r.apiToken == token and SetState("superseded", "API") then HME.Guidance.OnExternalSuperseded(r.token) end
        end)
        -- v2: every journey's end, and holds Forever-GPS let go of by itself.
        pcall(api.On, "ended", function() HME.Guidance.OnExternalChanged() end)
        pcall(api.On, "hold", function(id, held) if not held then HME.Guidance.OnHoldDropped(id) end end)
        hooked = true
    elseif type(g.On) == "function" then
        pcall(g.On, "route:started", function(dest) OnStarted(dest) end)
        pcall(g.On, "route:arrived", function(dest) OnArrived(dest) end)
        pcall(g.On, "route:cleared", function() OnCleared() end)
        hooked = true
    end
end
B.Hook = Hook

local function External(fromMap, fx, fy, toMap, tx, ty)
    local api = API()
    if not (api and type(api.EstimateSeconds) == "function") then return nil end
    local ok, secs = pcall(api.EstimateSeconds, toMap, tx, ty)
    if ok and HME.Num(secs) and secs >= 0 then return secs, "Forever-GPS" end
    return nil
end

local function Setup()
    if HME.settings and HME.settings.forevergps == false then return end
    if not FG() then return end
    Hook()
    HME.Geo.external = External
end
HME.On("PLAYER_LOGIN", function()
    Setup()
    HME.After(3, B.Reconcile)
end)
HME.On("ADDON_LOADED", function(_, name) if name == "ForeverGPS" then Setup() end end)

-- The nearest vendor, mailbox, repair, bank or trainer: Forever-GPS finds it
-- (faction-safe, API v2) and opens the journey for you to start with Go.
-- HME has no vendor or mailbox data of its own, so without Forever-GPS it
-- says so instead of guessing. Returns true, name | false, why.
function B.GoToService(kind, profession)
    local api = APIv2()
    if api and type(api.NavigateToService) == "function" and B.Available() then
        local ok, done, name = pcall(api.NavigateToService, kind, { profession = profession })
        if ok and done then
            HME.Print(("Forever-GPS found the nearest %s%s: press Go there. HME's farm guidance waits and comes back after."):format(
                kind, name and (" (" .. name .. ")") or ""))
            return true, name
        end
        return false, ok and name or "Forever-GPS could not search"
    end
    if FG() then
        HME.Print(("type /fgps go nearest %s (this Forever-GPS has no API for it)."):format(kind == "vendor" and "vendor" or kind))
        return false, "needs Forever-GPS API v2"
    end
    HME.Print("HME has no vendor or mailbox locations of its own; Forever-GPS knows them.")
    return false, "no Forever-GPS"
end

-- Trainers, vendors, mailboxes: Forever-GPS if available, else HME's arrow.
-- These are one-off trips, not farms: no ownership hand-over needed.
function B.GoToPlace(mapID, x, y, label)
    if B.Available() then
        local mode = B.Mode()
        local g = FG()
        if mode == "api" then
            local ok, tok = pcall(g.API.NavigateTo, { mapID = mapID, x = x, y = y, label = label, source = "HarvestMateEnhanced" })
            if ok and tok then return true end
        else
            local ok = pcall(function()
                local result = g.Search.CoordsFor(("%s %.1f %.1f"):format(ZoneName(mapID), x * 100, y * 100))
                if not result then error("no place") end
                if g.Window.Show then g.Window.Show("search") end
                local target = g.Search.Target(result)
                target.name = label or target.name
                g.Planner.Inspect(target)
                if g.Window.ShowRoute then g.Window.ShowRoute() end
            end)
            if ok then return true end
        end
    end
    if not (HME.Guidance.Active() and HME.Arrow.Shown()) then
        HME.Arrow.Point({ mapID = mapID, x = x, y = y }, label)
    else
        HME.Print(("%s is at %s %.1f, %.1f."):format(label or "It", ZoneName(mapID), x * 100, y * 100))
    end
    return false
end

function HME.IntegrationLine()
    local parts = {}
    parts[#parts + 1] = "Navigation: " .. (B.Available() and B.Status() or "HME's arrow (no Forever-GPS)")
    parts[#parts + 1] = "Prices: " .. (#HME.Prices.Available() > 0 and table.concat(HME.Prices.Available(), ", ") or "vendor only")
    parts[#parts + 1] = "Nodes: bundled" .. (HME.Spawns.UseGM2() and " + GatherMate2" or "")
    if _G.Questie or _G.QuestieLoader then parts[#parts + 1] = "Questie found" end
    return table.concat(parts, "   ·   ")
end
