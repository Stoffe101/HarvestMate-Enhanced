-- HarvestMate Enhanced: Integrations/TomTom.lua
-- Optional: when Forever-GPS is not installed and the TomTom setting is on,
-- the way to a farm can be a TomTom waypoint (its arrow then, not HME's).
-- Uses TomTom's documented AddWaypoint / RemoveWaypoint only.
-- Copyright (C) 2026 HarvestMate Enhanced contributors. GPL-3.0-or-later.

local _, ns = ...
local HME = ns.HME

local B = {}
HME.TomTomBridge = B

local uid

function B.Available()
    local tt = _G.TomTom
    return type(tt) == "table" and type(tt.AddWaypoint) == "function"
end

function B.Set(mapID, x, y, label)
    if not B.Available() then return false end
    B.Clear()
    local ok, id = pcall(_G.TomTom.AddWaypoint, _G.TomTom, mapID, x, y,
        { title = label or "HarvestMate Enhanced", persistent = false, minimap = true, world = true })
    if ok and id then
        uid = id
        return true
    end
    return false
end

function B.Clear()
    if uid and B.Available() and type(_G.TomTom.RemoveWaypoint) == "function" then
        pcall(_G.TomTom.RemoveWaypoint, _G.TomTom, uid)
    end
    uid = nil
end
