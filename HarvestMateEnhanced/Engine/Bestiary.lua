-- HarvestMate Enhanced: Engine/Bestiary.lua (0.6.0)
-- The Skinning Explorer's engine: every beast in the bundled spawn data, as
-- one profile per creature, with what you saw yourself next to the estimate.
--
--   index      one entry per npcID from Data/Gatherpedia/SkinningMobs.lua
--              (QuestieDB, Forever build): name, levels, elite, the maps it
--              spawns on and how many spawn points each. Built on first use.
--   skinnable  "yes" only when the game told us (a skin, or the skinnable
--              flag on its corpse); "no" when the game said so; otherwise
--              "not confirmed": the data picked beasts by name, it does not
--              prove every one can be skinned.
--   journal    your skins of it (count, materials, per skin, zones, skill-ups
--              right after a skin, last time), from HME.db.obs.skins. Corpse
--              loot is never in it: that is obs.loot, shown apart.
--   for me     a rough per-creature rate for THIS character: kill time
--              (measured or modelled), a skin, and walking that depends on
--              how many spawn points its best zone has; then skill-ups,
--              materials or gold an hour from it. A sorting aid, labelled as
--              rough: the Farm Finder plans real circuits.
-- Copyright (C) 2026 HarvestMate Enhanced contributors. GPL-3.0-or-later.

local _, ns = ...
local HME = ns.HME
local U = HME.U

local Bx = {}
HME.Bestiary = Bx

Bx.SKIN_SECS = 6          -- skin cast and loot
Bx.WALK_MIN, Bx.WALK_MAX = 8, 60

local index, list

local function Decode(points)
    local n = 0
    U.EachPacked(points or "", function() n = n + 1 end)
    return n
end

-- { [npcID] = entry }, and the entries in a list.
function Bx.Index()
    if index then return index, list end
    index, list = {}, {}
    for mapID, mobs in pairs(ns.SkinningMobs or {}) do
        for _, m in ipairs(mobs) do
            local id = m[1]
            local e = index[id]
            if not e then
                e = { npcID = id, name = m[2], min = m[3], max = m[4], elite = m[5] == 1, maps = {}, spawns = 0 }
                index[id] = e
                list[#list + 1] = e
            end
            if m[3] < e.min then e.min = m[3] end
            if m[4] > e.max then e.max = m[4] end
            local n = Decode(m[6])
            e.maps[mapID] = (e.maps[mapID] or 0) + n
            e.spawns = e.spawns + n
        end
    end
    table.sort(list, function(a, b)
        if a.min ~= b.min then return a.min < b.min end
        return a.name < b.name
    end)
    return index, list
end

function Bx.Get(npcID) return (Bx.Index())[npcID] end

-- Its zone with the most spawn points: mapID, count.
function Bx.BestMap(e)
    local best, n
    for mapID, c in pairs(e.maps) do
        if not n or c > n then best, n = mapID, c end
    end
    return best, n or 0
end

local SKINNABLE_WORD = { [true] = "yes (the game said so)", [false] = "no (the game said so)" }
function Bx.Skinnable(npcID)
    local v = HME.Spawns.Skinnable(npcID)
    return v, SKINNABLE_WORD[v] or "not confirmed yet"
end

---------------------------------------------------------------------------
-- The journal: what you skinned
---------------------------------------------------------------------------
-- { n, items = { { id, name, total, perSkin, times } }, zones = { { mapID, name, n } }, ups, t, loot = { n, avg } } or nil
function Bx.Journal(npcID)
    local rec = HME.db and HME.db.obs.skins[npcID]
    if not (rec and (rec.n or 0) > 0) then return nil end
    local out = { n = rec.n, items = {}, zones = {}, ups = rec.ups or 0, t = rec.t }
    for id, total in pairs(rec.qty or {}) do
        out.items[#out.items + 1] = { id = id, name = ns.ItemNameByID and ns.ItemNameByID(id) or ("item " .. id), total = total,
            perSkin = total / rec.n, times = rec.items and rec.items[id] or nil }
    end
    table.sort(out.items, function(a, b) return a.total > b.total end)
    for mapID, n in pairs(rec.zones or {}) do
        out.zones[#out.zones + 1] = { mapID = mapID, name = HME.ZoneData.Name(mapID) or ("map " .. mapID), n = n }
    end
    table.sort(out.zones, function(a, b) return a.n > b.n end)
    local loot = HME.db.obs.loot[npcID]
    if loot and (loot.n or 0) > 0 then out.loot = { n = loot.n, avg = ((loot.copper or 0) + (loot.vendor or 0)) / loot.n } end
    return out
end

-- Skill-ups that come right after a skin belong to that creature.
local lastSkin
HME.Listen("BEAST_SKINNED", function(npcID) lastSkin = { id = npcID, at = HME.Now() } end)
HME.Listen("SKILL_UP", function(prof, _, up)
    if prof ~= "Skinning" or not lastSkin or HME.Now() - lastSkin.at > 5 then return end
    local rec = HME.db and HME.db.obs.skins[lastSkin.id]
    if rec then rec.ups = (rec.ups or 0) + (up or 1) end
    lastSkin = nil
end)

-- Every creature you have skinned, most first (the Drop journal view).
function Bx.Skinned()
    local out = {}
    for npcID, rec in pairs((HME.db and HME.db.obs.skins) or {}) do
        if type(rec) == "table" and (rec.n or 0) > 0 then
            local e = Bx.Get(npcID) or { npcID = npcID, name = ("creature %d"):format(npcID), min = rec.lvl or 0, max = rec.lvl or 0,
                maps = {}, spawns = 0, unknown = true }
            out[#out + 1] = e
        end
    end
    table.sort(out, function(a, b) return HME.db.obs.skins[a.npcID].n > HME.db.obs.skins[b.npcID].n end)
    return out
end

---------------------------------------------------------------------------
-- For this character
---------------------------------------------------------------------------
-- Rough skins an hour from this creature alone, and the parts.
function Bx.Pace(e, profile)
    local kill, basis = HME.Skinning.KillSeconds(e, profile)
    local _, n = Bx.BestMap(e)
    -- More spawn points in its best zone, less walking between kills.
    local walk = U.Clamp(1800 / math.max(1, n), Bx.WALK_MIN, Bx.WALK_MAX)
    local secs = kill + Bx.SKIN_SECS + walk
    local perHour = 3600 / secs * (1 - HME.LeatherData.DOWNTIME)
    return perHour, { kill = kill, killBasis = basis, walk = walk, skin = Bx.SKIN_SECS, spawns = n }
end

-- { elig, perHour, skillPerHour, itemPerHour (for itemID), goldPerHour,
--   score (for `goal`), parts, yield } for one creature and this character.
function Bx.ForMe(e, profile, goal, itemID)
    profile = profile or HME.Player.Profile()
    local elig = HME.Skinning.Eligible(e, profile, (HME.settings and HME.settings.riskMode) or "balanced")
    local out = { elig = elig }
    local y = HME.Skinning.Yield(e)
    out.yield = y
    if not elig.killable then
        out.score = 0
        return out
    end
    local pace, parts = Bx.Pace(e, profile)
    pace = pace * (elig.skinShare or 1)
    out.perHour, out.parts = pace, parts
    out.skillPerHour = pace * (elig.chance or 0)
    out.goldPerHour = pace * (HME.Skinning.SkinValue(e) or 0)
    if itemID then out.itemPerHour = pace * (y.items[itemID] or 0) end
    if goal == "material" then out.score = out.itemPerHour or 0
    elseif goal == "profit" then out.score = out.goldPerHour
    else out.score = out.skillPerHour end
    -- Elites and beasts above you are slower and riskier than the model says.
    if e.elite then out.score = out.score * 0.6 end
    if (e.max or 0) > profile.level then out.score = out.score * 0.9 end
    return out
end

-- Creatures ranked for this character: { { e, me } }, best first, skinnable ones only.
function Bx.BestForMe(goal, itemID, profile, limit)
    profile = profile or HME.Player.Profile()
    local _, all = Bx.Index()
    local out = {}
    for _, e in ipairs(all) do
        if HME.Spawns.Skinnable(e.npcID) ~= false then
            local me = Bx.ForMe(e, profile, goal, itemID)
            if (me.score or 0) > 0 then out[#out + 1] = { e = e, me = me } end
        end
    end
    table.sort(out, function(a, b)
        if a.me.score ~= b.me.score then return a.me.score > b.me.score end
        return a.e.npcID < b.e.npcID
    end)
    for i = #out, (limit or 40) + 1, -1 do out[i] = nil end
    return out
end

-- Hunting areas for this one creature (its own maps, real circuits planned
-- the Farm Finder's way). done(results) in the background.
function Bx.Hunt(e, done, profile)
    local maps = {}
    for mapID in pairs(e.maps) do maps[#maps + 1] = mapID end
    table.sort(maps)
    return HME.Recommend.Find({ prof = "Skinning", goal = "level", npcs = { [e.npcID] = true }, maps = maps, limit = 5 },
        done, profile)
end

---------------------------------------------------------------------------
-- Search
---------------------------------------------------------------------------
-- Material names to item ids (leathers and hides HME knows).
local function MaterialIds(text)
    local ids = {}
    local LD = HME.LeatherData
    for _, set in ipairs({ LD.LEATHERS, LD.HIDES }) do
        for _, id in ipairs(set) do
            local name = ns.ItemNameByID and ns.ItemNameByID(id)
            if name and name:lower():find(text, 1, true) then ids[#ids + 1] = id end
        end
    end
    for _, sp in ipairs(LD.SPECIAL or {}) do
        local name = ns.ItemNameByID and ns.ItemNameByID(sp[2])
        if name and name:lower():find(text, 1, true) then ids[#ids + 1] = sp[2] end
    end
    return ids
end
Bx.MaterialIds = MaterialIds

-- filters = { text, filter = "all"|"canskin"|"skillup"|"zone"|"skinned", sort = "level"|"forme"|"name" }
-- Returns the entries, and the material ids the text matched (if any).
function Bx.Search(filters, profile)
    profile = profile or HME.Player.Profile()
    local _, all = Bx.Index()
    local text = U.Trim((filters.text or ""):lower())
    local level = tonumber(text)
    local mats = (#text >= 3 and not level) and MaterialIds(text) or {}
    local hereMap = profile.mapID and HME.Geo.ZoneOf(profile.mapID)
    local skill = profile.skills.Skinning and profile.skills.Skinning.rank
    local out = {}
    local pool = filters.filter == "skinned" and Bx.Skinned() or all
    for _, e in ipairs(pool) do
        local ok = true
        if text ~= "" then
            if level then
                ok = e.min <= level and e.max >= level
            else
                ok = e.name:lower():find(text, 1, true) ~= nil
                if not ok then
                    for mapID in pairs(e.maps) do
                        local z = HME.ZoneData.Name(mapID)
                        if z and z:lower():find(text, 1, true) then ok = true break end
                    end
                end
                if not ok and #mats > 0 then
                    local y = HME.Skinning.Yield(e)
                    for _, id in ipairs(mats) do if (y.items[id] or 0) > 0.02 then ok = true break end end
                end
            end
        end
        if ok and filters.filter == "canskin" then ok = skill ~= nil and skill >= HME.SkillModel.SkinReq(e.min) end
        if ok and filters.filter == "skillup" then
            ok = skill ~= nil and skill >= HME.SkillModel.SkinReq(e.min) and HME.SkillModel.Chance(skill, HME.SkillModel.SkinReq(e.max)) > 0
        end
        if ok and filters.filter == "zone" then ok = hereMap ~= nil and e.maps[hereMap] ~= nil end
        if ok then out[#out + 1] = e end
    end
    if filters.sort == "forme" then
        local goal = #mats > 0 and "material" or "level"
        local score = {}
        for _, e in ipairs(out) do score[e] = Bx.ForMe(e, profile, goal, mats[1]).score or 0 end
        table.sort(out, function(a, b)
            if score[a] ~= score[b] then return score[a] > score[b] end
            return a.npcID < b.npcID
        end)
    elseif filters.sort == "name" then
        table.sort(out, function(a, b) return a.name < b.name end)
    end
    return out, mats
end
