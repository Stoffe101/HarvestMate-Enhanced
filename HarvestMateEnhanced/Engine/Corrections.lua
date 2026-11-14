-- HarvestMate Enhanced: Engine/Corrections.lua
-- What you tell HME the data got wrong, with a scope that fits the mistake,
-- and always reversible (Settings > Your corrections, or /hme corrections).
--
--   kind          scope (default)   effect
--   notHere       spot (40 yd)      that beast's spawn points there are left out
--   notSkinnable  zone              that beast is left out of skinning in the zone
--                                   ("everywhere" only when you choose it)
--   inaccessible  area (150 yd)     farms centred there are left out, saying why
--   dangerous     area              counted as risky (risk +0.3)
--   crowded       area              ranked lower (x0.7), fading out over 7 days
--   inefficient   area              ranked lower (x0.8)
--   observe       area              "needs more observation": shown, no penalty
--
-- One mistaken mark never erases a whole species everywhere by default, and
-- crowding passes. Corrections are kept per account (bounded).
-- Copyright (C) 2026 HarvestMate Enhanced contributors. GPL-3.0-or-later.

local _, ns = ...
local HME = ns.HME

local C = {}
HME.Corrections = C

C.MAX = 300
C.SPOT_YARDS = 40
C.AREA_YARDS = 150
C.CROWD_DAYS = 7

C.KINDS = {
    notHere = { label = "beast does not spawn here", scope = "spot" },
    notSkinnable = { label = "beast is not skinnable", scope = "zone" },
    inaccessible = { label = "farm is inaccessible", scope = "area" },
    dangerous = { label = "area is dangerous", scope = "area" },
    crowded = { label = "area is overcrowded", scope = "area" },
    inefficient = { label = "route is inefficient", scope = "area" },
    observe = { label = "needs more observation", scope = "area" },
}

local function Store()
    if not HME.db then return { list = {}, next = 1 } end
    local s = HME.db.corrections
    if type(s) ~= "table" or type(s.list) ~= "table" then
        s = { list = {}, next = 1 }
        HME.db.corrections = s
    end
    s.next = tonumber(s.next) or (#s.list + 1)
    return s
end
C.Store = Store

local function Changed()
    if HME.Skinning and HME.Skinning.ClearCache then HME.Skinning.ClearCache() end
    HME.Signal("LEARNED")
    HME.Signal("CORRECTIONS_CHANGED")
end

local function Valid(c)
    return type(c) == "table" and C.KINDS[c.kind] ~= nil and type(c.mapID) == "number"
end

-- spec = { mapID, x, y, npcID, name, scope }. Returns the correction.
function C.Add(kind, spec)
    local k = C.KINDS[kind]
    if not (k and type(spec) == "table" and HME.Num(spec.mapID)) then return nil, "unknown correction" end
    if (kind == "notHere" or kind == "notSkinnable") and not HME.Num(spec.npcID) then return nil, "which beast?" end
    if k.scope ~= "zone" and not (HME.Num(spec.x) and HME.Num(spec.y)) then return nil, "where?" end
    local s = Store()
    local c = { id = s.next, kind = kind, mapID = spec.mapID, x = spec.x, y = spec.y, npcID = spec.npcID,
                name = type(spec.name) == "string" and spec.name:sub(1, 60) or nil,
                scope = (spec.scope == "everywhere" and kind == "notSkinnable") and "everywhere" or k.scope,
                t = (time and time()) or 0 }
    s.next = s.next + 1
    s.list[#s.list + 1] = c
    while #s.list > C.MAX do table.remove(s.list, 1) end
    Changed()
    return c
end

function C.Remove(id)
    local s = Store()
    for i = #s.list, 1, -1 do
        if s.list[i].id == id then
            table.remove(s.list, i)
            Changed()
            return true
        end
    end
    return false
end

function C.List(mapID)
    local out = {}
    for _, c in ipairs(Store().list) do
        if Valid(c) and (not mapID or c.mapID == mapID or c.scope == "everywhere") then out[#out + 1] = c end
    end
    return out
end

function C.Text(c)
    local k = C.KINDS[c.kind]
    local where = c.scope == "everywhere" and "everywhere" or (HME.ZoneData.Name(c.mapID) or "?")
    if c.x then where = ("%s %.1f, %.1f"):format(where, c.x * 100, c.y * 100) end
    return ("%s%s (%s, %s)"):format(c.name and (c.name .. ": ") or "", k and k.label or c.kind, c.scope, where)
end

local function Near(c, mapID, x, y, yards)
    if c.mapID ~= mapID or not (c.x and x) then return false end
    local d = HME.Geo.Distance(mapID, c.x, c.y, x, y)
    return d and d <= yards
end

-- Is this beast left out of skinning on this map? true, why
function C.BeastBlocked(npcID, mapID)
    for _, c in ipairs(Store().list) do
        if Valid(c) and c.kind == "notSkinnable" and c.npcID == npcID and (c.scope == "everywhere" or c.mapID == mapID) then
            return true, c.scope == "everywhere" and "you marked it not skinnable" or "you marked it not skinnable in this zone"
        end
    end
    return false
end

-- A beast's spawn points without the spots you said it is not at.
function C.FilterBeastPoints(npcID, mapID, pts)
    local marks
    for _, c in ipairs(Store().list) do
        if Valid(c) and c.kind == "notHere" and c.npcID == npcID and c.mapID == mapID then
            marks = marks or {}
            marks[#marks + 1] = c
        end
    end
    if not marks then return pts, 0 end
    local out, dropped = {}, 0
    for _, p in ipairs(pts) do
        local bad = false
        for _, c in ipairs(marks) do
            if Near(c, mapID, p[1], p[2], C.SPOT_YARDS) then bad = true break end
        end
        if bad then dropped = dropped + 1 else out[#out + 1] = p end
    end
    return out, dropped
end

-- What your marks say about a farm centred at (x, y):
-- { exclude = why?, risk = add, mult = score factor, notes = { ... }, observe = bool }
function C.ForArea(mapID, x, y)
    local out = { risk = 0, mult = 1, notes = {} }
    local now = (time and time()) or 0
    for _, c in ipairs(Store().list) do
        if Valid(c) and C.KINDS[c.kind].scope == "area" and Near(c, mapID, x, y, C.AREA_YARDS) then
            if c.kind == "inaccessible" then
                out.exclude = "you marked it inaccessible"
            elseif c.kind == "dangerous" then
                out.risk = math.max(out.risk, 0.3)
                out.notes[#out.notes + 1] = "you marked it dangerous"
            elseif c.kind == "crowded" then
                local days = (now - (c.t or now)) / 86400
                local f = 1 - 0.3 * math.max(0, 1 - days / C.CROWD_DAYS)
                if f < 1 then
                    out.mult = out.mult * f
                    out.notes[#out.notes + 1] = ("you found it crowded %d day%s ago"):format(days, math.floor(days) == 1 and "" or "s")
                end
            elseif c.kind == "inefficient" then
                out.mult = out.mult * 0.8
                out.notes[#out.notes + 1] = "you marked its route inefficient"
            elseif c.kind == "observe" then
                out.observe = true
                out.notes[#out.notes + 1] = "you asked for more observation here"
            end
        end
    end
    return out
end

-- The beast marks HME 0.2.0 kept as "left out everywhere" become
-- reversible corrections (the old table is kept, unused).
function C.Migrate()
    local bad = HME.db and HME.db.obs and HME.db.obs.badBeasts
    if type(bad) ~= "table" or HME.db.obs.badBeastsMigrated then return 0 end
    local n = 0
    for npcID, on in pairs(bad) do
        if on and type(npcID) == "number" then
            local npc = HME.Learning and HME.Learning.Npc(npcID)
            C.Add("notSkinnable", { mapID = npc and npc.mapID or 0, npcID = npcID, name = npc and npc.name, scope = "everywhere" })
            n = n + 1
        end
    end
    HME.db.obs.badBeastsMigrated = true
    return n
end
HME.Listen("DB_READY", function() HME.Try(C.Migrate) end)
