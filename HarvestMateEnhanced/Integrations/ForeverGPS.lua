-- HarvestMate Enhanced: Integrations/ForeverGPS.lua
-- The bridge to Forever-GPS (a separate, optional addon). HME owns gathering
-- goals, farms, local loops and farming stats; Forever-GPS owns getting
-- there: long journeys, transport, trainers, vendors, mailboxes.
--
-- Contract (checked, never assumed):
--  1. Preferred: a published API, ForeverGPS.API (version >= 1) with
--     NavigateTo(mapID, x, y, label, opts) -> ok, reason; Stop(); IsNavigating();
--     On(event, fn) for "arrived" / "cleared". Proposed in
--     docs/FOREVERGPS_BRIDGE.md; HME uses it as soon as Forever-GPS ships it.
--  2. Fallback for Forever-GPS 2.x without that API: its own coordinate search
--     and journey panel (Search.CoordsFor + Planner.Inspect + Window.ShowRoute),
--     i.e. exactly what typing "/fgps way <zone> <x> <y>" does. The player then
--     presses Go in Forever-GPS: HME never starts a journey on its own.
--     Arrival and stop are heard through its FG.On("route:arrived") and
--     FG.On("route:cleared") topics.
--  Every call is feature-detected and wrapped; a missing piece means
--  "not available", and HME's own arrow is used instead.
-- Prices: Engine/Prices.lua reads ForeverGPS.Market.Price (read-only).
-- Copyright (C) 2026 HarvestMate Enhanced contributors. GPL-3.0-or-later.

local _, ns = ...
local HME = ns.HME

local B = {}
HME.FGPS = B

B.MIN_VERSION = "2.0"

local function FG()
    local g = _G.ForeverGPS
    return type(g) == "table" and g or nil
end

local function VersionAtLeast(v, want)
    if type(v) ~= "string" then return false end
    local a1, a2 = v:match("^(%d+)%.(%d+)")
    local b1, b2 = want:match("^(%d+)%.(%d+)")
    a1, a2, b1, b2 = tonumber(a1), tonumber(a2), tonumber(b1), tonumber(b2)
    if not (a1 and b1) then return false end
    return a1 > b1 or (a1 == b1 and a2 >= b2)
end

-- "api" (published API), "panel" (2.x journey panel) or nil, and why not.
function B.Mode()
    local g = FG()
    if not g then return nil, "Forever-GPS is not installed" end
    local api = type(g.API) == "table" and g.API
    if api and (tonumber(api.VERSION) or 0) >= 1 and type(api.NavigateTo) == "function" then return "api" end
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

function B.Available()
    return B.Mode() ~= nil
end

function B.Status()
    local mode, why = B.Mode()
    if mode == "api" then return "Forever-GPS " .. tostring(FG().VERSION) .. " (bridge API)" end
    if mode == "panel" then return "Forever-GPS " .. tostring(FG().VERSION) .. " (journey panel)" end
    return why
end

local function ZoneName(mapID)
    return HME.ZoneData.Name(mapID)
end

-- Asks Forever-GPS to take the player to a map point. Returns ok, reason.
function B.NavigateTo(mapID, x, y, label)
    local mode, why = B.Mode()
    if not mode then return false, why end
    local g = FG()
    if mode == "api" then
        local ok, res, reason = pcall(g.API.NavigateTo, mapID, x, y, label, { source = "HarvestMateEnhanced" })
        if ok and res then
            B.owned = true
            return true
        end
        return false, ok and reason or res
    end
    -- Journey panel: the same as "/fgps way <zone> <x> <y>".
    local text = ("%s %.1f %.1f"):format(ZoneName(mapID), x * 100, y * 100)
    local ok, result = pcall(g.Search.CoordsFor, text)
    if not ok or not result then return false, "Forever-GPS could not place " .. text end
    local ok2, err = pcall(function()
        if g.Window.Show then g.Window.Show("search") end
        local target = g.Search.Target(result)
        if label then target.name = label end
        g.Planner.Inspect(target)
        if g.Window.ShowRoute then g.Window.ShowRoute() end
    end)
    if not ok2 then return false, tostring(err) end
    B.owned = true
    HME.Print("Forever-GPS has the journey: press Go there to set off. HME takes over at the farm.")
    return true
end

-- HME no longer needs Forever-GPS's journey (arrived, or stopped in HME).
-- Only stops a journey HME asked for, and only if it is still the one running.
function B.Release()
    if not B.owned then return end
    B.owned = false
    local g = FG()
    if not g then return end
    if type(g.API) == "table" and type(g.API.Stop) == "function" then
        pcall(g.API.Stop, { source = "HarvestMateEnhanced" })
    end
    -- The 2.x panel: the journey is the player's; leaving it running is the
    -- safe choice (they may have changed it). Its arrow clears on arrival.
end

-- Listen for arrival / stop.
local hooked = false
local function Hook()
    if hooked then return end
    local g = FG()
    if not g then return end
    if type(g.API) == "table" and type(g.API.On) == "function" then
        pcall(g.API.On, "arrived", function() if B.owned then HME.Guidance.OnExternalArrived() end end)
        pcall(g.API.On, "cleared", function() if B.owned then HME.Guidance.OnExternalCleared() end end)
        hooked = true
    elseif type(g.On) == "function" then
        pcall(g.On, "route:arrived", function() if B.owned then HME.Guidance.OnExternalArrived() end end)
        pcall(g.On, "route:cleared", function()
            if B.owned then
                B.owned = false
                HME.Guidance.OnExternalCleared()
            end
        end)
        hooked = true
    end
end

-- Travel time from Forever-GPS's own estimate, when its API offers one.
local function External(fromMap, fx, fy, toMap, tx, ty)
    local g = FG()
    local api = g and type(g.API) == "table" and g.API
    if not (api and type(api.EstimateSeconds) == "function") then return nil end
    local ok, secs = pcall(api.EstimateSeconds, toMap, tx, ty)
    if ok and HME.Num(secs) and secs >= 0 then return secs, "Forever-GPS" end
    return nil
end

HME.On("PLAYER_LOGIN", function()
    if HME.settings.forevergps == false then return end
    Hook()
    if FG() then HME.Geo.external = External end
end)
HME.On("ADDON_LOADED", function(_, name)
    if name == "ForeverGPS" and HME.settings and HME.settings.forevergps ~= false then
        Hook()
        HME.Geo.external = External
    end
end)

-- Trainers and other places: hand them to Forever-GPS, else HME's arrow.
function B.GoToPlace(mapID, x, y, label)
    if B.Available() and HME.settings.forevergps ~= false then
        local ok = B.NavigateTo(mapID, x, y, label)
        if ok then return true end
    end
    HME.Arrow.Point({ mapID = mapID, x = x, y = y }, label)
    return false
end

---------------------------------------------------------------------------
-- One line for the Dashboard on which optional addons are in use.
---------------------------------------------------------------------------
function HME.IntegrationLine()
    local parts = {}
    parts[#parts + 1] = "Navigation: " .. (B.Available() and B.Status() or "HME's arrow (no Forever-GPS)")
    parts[#parts + 1] = "Prices: " .. (#HME.Prices.Available() > 0 and table.concat(HME.Prices.Available(), ", ") or "vendor only")
    parts[#parts + 1] = "Nodes: bundled" .. (HME.Spawns.UseGM2() and " + GatherMate2" or "")
    if _G.Questie or _G.QuestieLoader then parts[#parts + 1] = "Questie found" end
    return table.concat(parts, "   ·   ")
end
