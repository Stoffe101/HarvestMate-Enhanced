-- HarvestMate Enhanced: Engine/Risk.lua
-- An estimate of how risky a farming area is, from what is known in advance
-- and what this account has seen. It cannot see other players and never calls
-- a place safe: the lowest label is "Lower risk".
--
-- Parts (each 0-1, then weighted):
--   creatures  beasts in the area above your level, and elites (spawn data)
--   territory  your faction's home zone, contested, or the other side's
--   guards     how close the area is to a town of the other faction
--   deaths     your own recorded deaths near the area (last 30 days count most)
--   marked     your danger areas (drawn on the map, Routes and Maps tab)
-- Copyright (C) 2026 HarvestMate Enhanced contributors. GPL-3.0-or-later.

local _, ns = ...
local HME = ns.HME
local U = HME.U
local Z = HME.ZoneData
local Geo = HME.Geo

local R = {}
HME.Risk = R

R.WEIGHTS = { creatures = 0.35, territory = 0.25, guards = 0.25, deaths = 0.15 }
R.LABELS = {
    { 0.20, "Lower risk", "48c75a" },
    { 0.40, "Moderate risk", "ffe14d" },
    { 0.60, "Higher risk", "ff8a3d" },
    { 2.00, "High risk", "ff3030" },
}

local function Enemy(f) return f == "Alliance" and "Horde" or (f == "Horde" and "Alliance" or nil) end

-- Territory: 0 own home zone, 0.35 contested, 0.55 contested but leaning to
-- the other side, 0.9 the other side's home zone.
function R.Territory(mapID, faction)
    local name = Z.Name(mapID)
    local zones = ns.Zones
    local home = zones and zones.FACTION and zones.FACTION[name]
    if home then
        if home == faction then return 0, "your faction's territory" end
        return 0.9, "the other faction's territory"
    end
    local enemy = Enemy(faction)
    if enemy and zones and zones.LEANS and zones.LEANS[enemy] and zones.LEANS[enemy][name] then
        return 0.55, "contested, leans to the other faction"
    end
    return 0.35, "contested territory"
end

-- Guards: 1 inside an enemy town's radius, fading to 0 at three radii.
function R.Guards(mapID, x, y, faction)
    local z = Z.Get(mapID)
    local enemy = Enemy(faction)
    if not (z and z.towns and x and enemy) then return 0 end
    local worst, which = 0, nil
    for _, t in ipairs(z.towns) do
        if t[1] == enemy then
            local d = Geo.Distance(mapID, x, y, t[2] / 100, t[3] / 100)
            local r = t[4]
            local v = d <= r and 1 or U.Clamp(1 - (d - r) / (2 * r), 0, 1)
            if v > worst then worst, which = v, t[5] end
        end
    end
    return worst, which
end

-- Creatures: from the beasts in the area (any beast, not only targets).
--   levels  list of { min, max, elite, count }
function R.Creatures(levels, playerLevel)
    local total, danger, elites = 0, 0, 0
    for _, b in ipairs(levels) do
        local mid = (b.min + b.max) / 2
        local d = mid - playerLevel
        local w = b.count or 1
        total = total + w
        if b.elite then
            elites = elites + w
            danger = danger + w * (d >= -3 and 1 or 0.5)
        elseif d >= 5 then
            danger = danger + w
        elseif d >= 3 then
            danger = danger + w * 0.6
        elseif d >= 1 then
            danger = danger + w * 0.25
        end
    end
    if total == 0 then return 0, 0 end
    return U.Clamp(danger / total * 1.4, 0, 1), elites
end

-- Deaths recorded within `radius` yards of the point (recent ones weigh more).
function R.Deaths(mapID, x, y, radius)
    local list = HME.db and HME.db.obs.deaths or {}
    local now = (time and time()) or 0
    local score, n = 0, 0
    for _, d in ipairs(list) do
        if d.m == mapID and d.x and x and Geo.Distance(mapID, x, y, d.x, d.y) <= (radius or 250) then
            local ageDays = (now - (d.t or now)) / 86400
            score = score + (ageDays <= 30 and 1 or 0.4)
            n = n + 1
        end
    end
    return U.Clamp(score / 4, 0, 1), n
end

-- The whole assessment for an area: { score, label, hex, reasons = {...},
-- parts = {...} }. area: { mapID, x, y, radius, beasts = { {min,max,elite,count} } }
function R.Assess(area, profile)
    local faction = profile.faction
    local reasons, parts = {}, {}
    local ter, terWhy = R.Territory(area.mapID, faction)
    parts.territory = ter
    reasons[#reasons + 1] = terWhy
    local g, town = R.Guards(area.mapID, area.x, area.y, faction)
    parts.guards = g
    if g > 0.3 and town then reasons[#reasons + 1] = "near " .. town .. " (enemy guards)" end
    local c, elites = R.Creatures(area.beasts or {}, profile.level)
    parts.creatures = c
    if elites > 0 then reasons[#reasons + 1] = elites .. " elite spawn points nearby" end
    if c >= 0.5 then reasons[#reasons + 1] = "many creatures above your level" end
    local d, n = R.Deaths(area.mapID, area.x, area.y, (area.radius or 150) + 100)
    parts.deaths = d
    if n > 0 then reasons[#reasons + 1] = ("you died here %d time%s"):format(n, n == 1 and "" or "s") end
    local score = 0
    for k, w in pairs(R.WEIGHTS) do score = score + (parts[k] or 0) * w end
    -- A user-avoided zone is flagged regardless.
    if HME.settings and HME.settings.avoidZones and HME.settings.avoidZones[Z.Name(area.mapID)] then
        score = math.max(score, 0.9)
        reasons[#reasons + 1] = "you marked this zone to avoid"
        parts.avoided = true
    end
    local label, hex
    for _, l in ipairs(R.LABELS) do
        if score < l[1] then
            label, hex = l[2], l[3]
            break
        end
    end
    return { score = score, label = label, hex = hex, reasons = reasons, parts = parts }
end

-- How much a ranking penalizes risk, by the player's choice.
function R.Penalty(score, mode)
    if mode == "fastest" then return 1 - 0.15 * score end
    if mode == "safer" then return math.max(0.05, 1 - 1.2 * score * score - 0.4 * score) end
    return 1 - 0.45 * score * score
end

-- Records a death where it happened (Engine/Learning.lua).
function R.NoteDeath(mapID, x, y)
    if not (HME.db and mapID) then return end
    U.Push(HME.db.obs.deaths, { m = mapID, x = x and U.Round(x, 3), y = y and U.Round(y, 3), t = (time and time()) or 0 },
        HME.DBM.LIMITS.deaths)
end
