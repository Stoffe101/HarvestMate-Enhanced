-- HarvestMate Enhanced: Engine/Skinning.lua
-- Skinning is hunting, not node gathering: a beast has to be found, killed,
-- looted and skinned, and comes back only after a respawn. This module turns
-- the bundled beast spawns into hunting areas and estimates, for one
-- character, how many beasts an hour it can really process there, the
-- skill-ups and the gold.
--
-- Per beast:
--   Eligible     can this character skin it (skill vs level), is it a
--                sensible kill (level difference, elite), skill-up chance
--   KillSeconds  model by level difference, scaled by this character's
--                measured kill times once there are enough
--   Yield        expected materials per skin: the account's own skins of this
--                beast (or level) blended with Data/Leather.lua's estimate,
--                the estimate fading as observations grow (k = 8 skins)
--
-- Per hunting area (a cluster of spawn points, Engine/Cluster.lua):
--   time per beast = kill + loot + skin + walk to the next live beast
--   beasts/hour    = min(3600 / time per beast,
--                        spawns x (1 - competition) x 3600 / respawn)
--   gold/hour      = beasts/hour x value per beast (three price estimates)
--   skill-ups/hour = beasts/hour x average skill-up chance
-- The walk uses the spawn density (nearest live beast ~ 0.5 / sqrt(density)),
-- minus pull range. Respawn is an assumption (5 min) until measured: the
-- result says which limit applies and that the respawn is assumed.
-- Copyright (C) 2026 HarvestMate Enhanced contributors. GPL-3.0-or-later.

local _, ns = ...
local HME = ns.HME
local U = HME.U
local Geo = HME.Geo
local SM = HME.SkillModel
local LD = HME.LeatherData
local Spawns = HME.Spawns
local Cluster = HME.Cluster

local Sk = {}
HME.Skinning = Sk

Sk.PRIOR_SKINS = 8      -- how many observed skins weigh as much as the estimate
Sk.PRIOR_KILLS = 6      -- the same for kill times
Sk.CLUSTER_YARDS = 70
Sk.MIN_CLUSTER = 4

---------------------------------------------------------------------------
-- Eligibility
---------------------------------------------------------------------------

-- The safety limits by risk mode: how far above your level a beast may be.
Sk.LEVEL_ABOVE = { fastest = 3, balanced = 2, safer = 1 }
Sk.ELITE_BELOW = { fastest = 5, balanced = 8 }

-- beast: { npcID, name, min, max, elite }. Returns a table:
--   req, canSkin, chance, color, levelDiff, killable, why (when not)
function Sk.Eligible(beast, profile, mode)
    local skill = profile.skills.Skinning and profile.skills.Skinning.rank
    local level = (beast.min + beast.max) / 2
    local top = beast.max
    local req = SM.SkinReq(top)
    local out = { req = req, reqMin = SM.SkinReq(beast.min), levelDiff = level - profile.level, skinShare = 0, chance = 0 }
    if not skill then
        out.why = "you don't know Skinning"
        return out
    end
    -- A beast spawns at any level of its range: only the levels this skill
    -- can skin count, each with its own skill-up chance.
    local n, ok, chance = 0, 0, 0
    for l = beast.min, beast.max do
        n = n + 1
        if skill >= SM.SkinReq(l) then
            ok = ok + 1
            chance = chance + SM.Chance(skill, SM.SkinReq(l))
        end
    end
    out.skinShare = ok / math.max(1, n)
    out.chance = ok > 0 and chance / ok or 0
    out.canSkin = ok > 0
    local skinTop = math.min(beast.max, SM.MaxSkinLevel(skill))
    out.color = SM.Color(skill, SM.SkinReq(math.floor((beast.min + math.max(beast.min, skinTop)) / 2 + 0.5)))
    local known = Spawns.Skinnable(beast.npcID)
    out.skinnable = known
    if known == false then
        out.why = "the game said it can't be skinned"
        return out
    end
    if HME.db and HME.db.obs.badBeasts and HME.db.obs.badBeasts[beast.npcID] then
        out.why = "you marked it as wrong or not there"
        return out
    end
    if not out.canSkin then
        out.why = ("needs %d Skinning (level %d)"):format(out.reqMin, beast.min)
        return out
    end
    local above = Sk.LEVEL_ABOVE[mode or "balanced"] or 2
    -- Elites: only well below you (8 levels in balanced, 5 in fastest), and
    -- never in lower-risk mode. Their kill time (x3.5) still counts.
    local eliteBelow = Sk.ELITE_BELOW[mode or "balanced"]
    if beast.elite and (not eliteBelow or level > profile.level - eliteBelow) then
        out.why = "elite"
        return out
    end
    if top > profile.level + above then
        out.why = ("level %d is too far above yours"):format(top)
        return out
    end
    out.killable = true
    return out
end

-- How well this character farms a beast (apart from whether it may):
-- seconds per kill and where that number comes from.
function Sk.Efficiency(beast, profile)
    local k, basis = Sk.KillSeconds(beast, profile)
    return { killSecs = k, basis = basis }
end

---------------------------------------------------------------------------
-- Kill time
---------------------------------------------------------------------------
Sk.BASE_KILL = 14   -- seconds for a beast of your own level, pull to death (model)

-- A weak starting guess by class (1 = the plain model). Measured fights
-- replace it quickly; it is never treated as a fact about a class.
Sk.CLASS_PRIOR = { HUNTER = 0.9, WARLOCK = 0.95, MAGE = 0.95, WARRIOR = 1.05, PRIEST = 1.1, PALADIN = 1.05 }

local function ModelKill(diff, elite, class)
    local t
    if diff >= 0 then t = Sk.BASE_KILL * (1 + 0.15 * diff) else t = Sk.BASE_KILL * math.max(0.4, 1 + 0.07 * diff) end
    if elite then t = t * 3.5 end
    return t * (Sk.CLASS_PRIOR[class or ""] or 1)
end
Sk.ModelKill = ModelKill

-- This character's pace relative to the model: a weighted median of its
-- fights (observed / model), where a fight weighs less as it ages (half
-- after 14 days) and when it was fought at a level more than 2 away from
-- now (gear and level change pace), shrunk toward 1 by PRIOR_KILLS.
function Sk.KillFactor(profile)
    local samples = HME.char and HME.char.eff and HME.char.eff.kill or {}
    if #samples == 0 then return 1, 0 end
    local now = (time and time()) or 0
    local level = profile and profile.level or (HME.Player and HME.Player.Level()) or 1
    local list, total = {}, 0
    for _, s in ipairs(samples) do
        if type(s.s) == "number" and s.s > 0 then
            local w = 1
            if s.t then w = w * 0.5 ^ (math.max(0, now - s.t) / (14 * 86400)) end
            if s.lvl and math.abs(level - s.lvl) > 2 then w = w * 0.4 end
            list[#list + 1] = { r = s.s / ModelKill(s.d or 0, false), w = w }
            total = total + w
        end
    end
    if total <= 0 then return 1, 0 end
    table.sort(list, function(a, b) return a.r < b.r end)
    local acc, med = 0, list[#list].r
    for _, e in ipairs(list) do
        acc = acc + e.w
        if acc >= total / 2 then med = e.r break end
    end
    local f = (med * total + 1 * Sk.PRIOR_KILLS) / (total + Sk.PRIOR_KILLS)
    return U.Clamp(f, 0.25, 4), total
end

function Sk.KillSeconds(beast, profile)
    local diff = (beast.min + beast.max) / 2 - profile.level
    local f, n = Sk.KillFactor(profile)
    return ModelKill(diff, beast.elite, profile.class) * f,
        n >= Sk.PRIOR_KILLS and "measured" or (n > 0.5 and "partly measured" or "model")
end

---------------------------------------------------------------------------
-- Yield
---------------------------------------------------------------------------

local bandCache
local function Bands()
    if bandCache then return bandCache end
    bandCache = { leather = {}, hide = {} }
    local function add(list, ids)
        for _, id in ipairs(ids) do
            local rec = ns.itemIndex[id]
            local e = rec and rec.entry
            if e and e.mobMin then list[#list + 1] = { id = id, min = e.mobMin, max = e.mobMax or e.mobMin } end
        end
    end
    add(bandCache.leather, LD.LEATHERS)
    add(bandCache.hide, LD.HIDES)
    return bandCache
end

local function Split(list, level)
    local out, total = {}, 0
    for _, b in ipairs(list) do
        if level >= b.min and level <= b.max then
            local mid, half = (b.min + b.max) / 2, (b.max - b.min) / 2 + 1
            local w = math.max(0.25, 1 - math.abs(level - mid) / half * 0.6)
            out[#out + 1] = { id = b.id, w = w }
            total = total + w
        end
    end
    for _, o in ipairs(out) do o.w = o.w / total end
    return out
end

-- The estimate alone: { [itemID] = per skin }.
function Sk.PriorYield(beast)
    local level = math.floor((beast.min + beast.max) / 2 + 0.5)
    local bands = Bands()
    local out = {}
    for _, o in ipairs(Split(bands.leather, level)) do out[o.id] = (out[o.id] or 0) + LD.PRIMARY * o.w end
    for _, o in ipairs(Split(bands.hide, level)) do out[o.id] = (out[o.id] or 0) + LD.HIDE * o.w end
    local name = (beast.name or ""):lower()
    for _, sp in ipairs(LD.SPECIAL) do
        if name:find(sp[1], 1, true) and level >= sp[4] and level <= sp[5] then
            out[sp[2]] = (out[sp[2]] or 0) + sp[3]
        end
    end
    return out
end

-- What this account has seen: per beast (HME obs.skins) and per level
-- (HarvestMate's learned drops, key "skin:<level>").
local function Observed(beast)
    local rec = HME.db and HME.db.obs.skins[beast.npcID]
    if rec and (rec.n or 0) > 0 then return rec.n, rec.qty or {}, "this beast" end
    local HG = ns.HG
    local drops = HG and HG.db and HG.db.learned and HG.db.learned.drops
    if drops then
        local n, qty = 0, {}
        for l = beast.min, beast.max do
            local d = drops["skin:" .. l]
            if type(d) == "table" and (d.n or 0) > 0 then
                n = n + d.n
                for id, q in pairs(d.qty or d.items or {}) do qty[id] = (qty[id] or 0) + q end
            end
        end
        if n > 0 then return n, qty, "beasts of this level" end
    end
    return 0, {}, nil
end

-- { items = { [itemID] = per skin }, n = observed skins, basis = text,
--   prior = { ... } }
function Sk.Yield(beast)
    local prior = Sk.PriorYield(beast)
    local n, qty, basis = Observed(beast)
    local k = Sk.PRIOR_SKINS
    local items = {}
    for id, v in pairs(prior) do items[id] = v * k / (n + k) end
    for id, total in pairs(qty) do
        items[id] = (items[id] or 0) + total / (n + k)
    end
    -- A material seen only once in many skins stays in, but never drives a
    -- ranking: anything with fewer than 3 sightings counts at half value.
    local seen = {}
    for id, total in pairs(qty) do seen[id] = total end
    return { items = items, n = n, basis = basis or "estimate", prior = prior, seen = seen }
end

-- "Heavy Leather: 42 observed from 31 skins" (or the estimate, labelled).
function Sk.YieldText(y, itemID)
    local name = ns.itemIndex[itemID] and ns.itemIndex[itemID].entry.name or ("item " .. itemID)
    local seen = y.seen and y.seen[itemID]
    if y.n > 0 and seen then
        return ("%s: %d observed from %d skins (%.2f per skin, smoothed)"):format(name, seen, y.n, y.items[itemID] or 0)
    end
    if y.prior[itemID] then
        return ("%s: about %.2f per skin (estimate%s)"):format(name, y.prior[itemID], y.n > 0 and (", " .. y.n .. " skins so far") or "")
    end
    return name .. ": not seen yet"
end

-- Copper per successful skin under one price estimate. Items with fewer than
-- three sightings and no estimate are counted at half value.
function Sk.SkinValue(beast, which)
    local y = Sk.Yield(beast)
    local total, lines = 0, {}
    for id, per in pairs(y.items) do
        local v = HME.Prices.Value(id, which) or 0
        local weight = 1
        if not y.prior[id] and (y.seen[id] or 0) < 3 then weight = 0.5 end
        total = total + per * v * weight
        lines[#lines + 1] = { id = id, per = per, value = v, weight = weight }
    end
    table.sort(lines, function(a, b) return a.per * a.value > b.per * b.value end)
    return total, lines, y
end

-- Ordinary mob loot (Total farming value): only what was observed.
function Sk.LootValue(beast)
    local rec = HME.db and HME.db.obs.loot[beast.npcID]
    if rec and (rec.n or 0) >= 3 then return ((rec.copper or 0) + (rec.vendor or 0)) / rec.n, rec.n end
    return nil, rec and rec.n or 0
end

---------------------------------------------------------------------------
-- Hunting areas
---------------------------------------------------------------------------

-- All beasts of a map with their eligibility for this character.
function Sk.Candidates(mapID, profile, mode)
    local out = {}
    for _, b in ipairs(Spawns.BeastPoints(mapID)) do
        local e = Sk.Eligible(b, profile, mode)
        out[#out + 1] = { beast = b, elig = e }
    end
    return out
end

-- Hunting areas on a map: clusters of eligible spawn points.
-- goal: "level" weighs points by skill-up chance, "profit" by value/time.
-- Returns areas sorted by weight, each:
--   { mapID, cx, cy (map 0-1), yx, yy (yards), radius (yards), spawns,
--     beasts = { [npcID] = { beast, elig, count } }, points = { {x,y}... } }
local areaCache, areaCacheVersion = {}, -1
function Sk.Areas(mapID, profile, goal, mode, targets)
    -- Cached per map, goal, mode, skill and level while the data is unchanged
    -- (material searches are not cached: their targets vary).
    local key
    if not targets then
        local skill = profile.skills.Skinning and profile.skills.Skinning.rank or 0
        key = table.concat({ mapID, goal or "", mode or "", skill, profile.level }, ":")
        local v = Spawns.Version() .. ":" .. U.Count(HME.db and HME.db.obs.mobs or {}) .. ":" .. U.Count(HME.db and HME.db.obs.badBeasts or {})
        if v ~= areaCacheVersion then areaCache, areaCacheVersion = {}, v end
        local hit = areaCache[key]
        if hit then return hit[1], hit[2] end
    end
    local areas, cands = Sk.AreasUncached(mapID, profile, goal, mode, targets)
    if key then areaCache[key] = { areas, cands } end
    return areas, cands
end

function Sk.AreasUncached(mapID, profile, goal, mode, targets)
    local w, h = Geo.MapYards(mapID)
    w, h = w or 1500, h or 1000
    local pts = {}
    local cands = Sk.Candidates(mapID, profile, mode)
    for _, c in ipairs(cands) do
        if c.elig.killable then
            local weight
            if goal == "level" then
                weight = c.elig.chance or 0
            elseif goal == "material" and targets then
                -- How much of the wanted material one skin gives (estimate or measured).
                weight = 0
                for id, per in pairs(Sk.Yield(c.beast).items) do
                    if targets[id] then weight = weight + per end
                end
            else
                weight = 1
            end
            if weight > 0 then
                for _, p in ipairs(c.beast.pts) do
                    pts[#pts + 1] = { p[1] * w, p[2] * h, w = weight, cand = c }
                end
            end
        end
    end
    if #pts == 0 then return {}, cands end
    local groups = Cluster.Groups(pts, Sk.CLUSTER_YARDS, Sk.MIN_CLUSTER)
    local areas = {}
    for _, g in ipairs(groups) do
        local a = { mapID = mapID, yx = g.cx, yy = g.cy, cx = g.cx / w, cy = g.cy / h, radius = math.max(40, g.radius),
            spawns = #g.members, beasts = {}, points = {}, weight = g.weight }
        for _, j in ipairs(g.members) do
            local p = pts[j]
            local id = p.cand.beast.npcID
            local rec = a.beasts[id]
            if not rec then
                rec = { beast = p.cand.beast, elig = p.cand.elig, count = 0 }
                a.beasts[id] = rec
            end
            rec.count = rec.count + 1
            a.points[#a.points + 1] = { p[1] / w, p[2] / h }
        end
        -- Size: the hull's area, at least a 40-yard circle.
        local hullPts = {}
        for _, j in ipairs(g.members) do hullPts[#hullPts + 1] = { pts[j][1], pts[j][2] } end
        local hull = U.Hull(hullPts)
        local area = 0
        for i = 1, #hull do
            local p, q = hull[i], hull[i % #hull + 1]
            area = area + p[1] * q[2] - q[1] * p[2]
        end
        a.areaYards = math.max(math.abs(area) / 2 + 2 * math.pi * 25 * 25, math.pi * 40 * 40)
        a.hull = {}
        for _, p in ipairs(hull) do
            a.hull[#a.hull + 1] = p[1] / w
            a.hull[#a.hull + 1] = p[2] / h
        end
        areas[#areas + 1] = a
    end
    return areas, cands
end

-- Joins nearby areas into a circuit worth riding: the best area and others
-- within `reach` yards, up to `max` areas, until there are enough spawns to
-- outlast the respawn at this pace.
function Sk.Circuit(areas, startIndex, reach, max)
    local first = areas[startIndex or 1]
    if not first then return nil end
    local chosen = { first }
    local used = { [first] = true }
    local list = {}
    for _, a in ipairs(areas) do
        if not used[a] then
            local d = U.Dist(first.yx, first.yy, a.yx, a.yy)
            if d <= (reach or 650) then list[#list + 1] = { a = a, d = d } end
        end
    end
    table.sort(list, function(x, y) return x.a.weight / (1 + x.d / 300) > y.a.weight / (1 + y.d / 300) end)
    for _, e in ipairs(list) do
        if #chosen >= (max or 4) then break end
        chosen[#chosen + 1] = e.a
    end
    return chosen
end

---------------------------------------------------------------------------
-- Evaluation of a circuit for this character.
---------------------------------------------------------------------------
-- Returns a metrics table:
--   beastsPerHour, limit ("pace" or "respawn"), killSecs, walkSecs, perBeast,
--   skillChance, skillPerHour, gph = { conservative, typical, optimistic },
--   valuePerBeast, yieldBasis, observedSkins, loopYards, spawns, details...
function Sk.Evaluate(circuit, profile, opts)
    opts = opts or {}
    local s = HME.settings or {}
    local competition = U.Clamp((s.competition or 25) / 100, 0, 0.9)
    local speedFoot = 7
    local spawns, areaYards = 0, 0
    local byBeast = {}
    for _, a in ipairs(circuit) do
        spawns = spawns + a.spawns
        areaYards = areaYards + a.areaYards
        for id, rec in pairs(a.beasts) do
            local b = byBeast[id]
            if not b then
                b = { beast = rec.beast, elig = rec.elig, count = 0 }
                byBeast[id] = b
            end
            b.count = b.count + rec.count
        end
    end
    if spawns == 0 then return nil end
    -- Weighted averages over the spawn points.
    local kill, chance, skinP = 0, 0, 0
    local value = { conservative = 0, typical = 0, optimistic = 0 }
    local loot, lootN = 0, 0
    local observed, priorOnly = 0, true
    local items = {}
    local killBasis = "model"
    for _, b in pairs(byBeast) do
        local share = b.count / spawns
        local k, basis = Sk.KillSeconds(b.beast, profile)
        killBasis = basis
        kill = kill + share * k
        chance = chance + share * (b.elig.chance or 0)
        -- Share of spawns you can skin: the levels you can, times 0.85 while
        -- the game has not confirmed the beast is skinnable at all.
        local p = (b.elig.skinShare or 1) * (b.elig.skinnable == true and 1 or 0.85)
        skinP = skinP + share * p
        for which in pairs(value) do
            local v, lines, y = Sk.SkinValue(b.beast, which)
            value[which] = value[which] + share * p * v
            if which == "typical" then
                observed = observed + y.n
                if y.n > 0 then priorOnly = false end
                for _, l in ipairs(lines) do
                    items[l.id] = (items[l.id] or 0) + share * p * l.per
                end
            end
        end
        local lv, ln = Sk.LootValue(b.beast)
        if lv then
            loot = loot + share * lv
            lootN = lootN + ln
        end
    end
    -- Walk to the next live beast: nearest-neighbour distance in the live
    -- density, less pull range; plus the loop between areas spread over the
    -- beasts met on it.
    local alive = spawns * (1 - competition) * 0.85
    local density = alive / areaYards
    local nn = 0.5 / math.sqrt(math.max(density, 1e-9))
    local walk = math.max(0, nn - LD.PULL_YARDS) / speedFoot
    local loop = 0
    if #circuit > 1 then
        for i = 1, #circuit do
            local a, b = circuit[i], circuit[i % #circuit + 1]
            loop = loop + U.Dist(a.yx, a.yy, b.yx, b.yy)
        end
        walk = walk + (loop / speedFoot) / math.max(1, alive)
    end
    local perBeast = (kill + LD.LOOT_SECONDS + LD.SKIN_SECONDS + LD.PULL_SECONDS + walk) * (1 + LD.DOWNTIME)
    local pace = 3600 / perBeast
    local respawn = LD.RESPAWN_SECONDS
    local supply = spawns * (1 - competition) * 3600 / respawn
    local bph, limit = pace, "pace"
    if supply < pace then bph, limit = supply, "respawn" end
    local learned = HME.Learning and HME.Learning.Rate(opts.key, "beasts")
    if learned then
        bph = learned.blend(bph)
    end
    -- The three estimates move pace as well as prices: conservative assumes
    -- 15% fewer beasts, optimistic 10% more (Engine/Prices.lua for prices).
    local gph = {}
    local total = s.profitScope == "total"
    local PACE = { conservative = 0.85, typical = 1, optimistic = 1.1 }
    for which, v in pairs(value) do
        gph[which] = math.min(bph * PACE[which], supply) * (v + (total and loot or 0))
    end
    local material
    if opts.targets then
        material = 0
        for id, per in pairs(items) do if opts.targets[id] then material = material + bph * per end end
    end
    return {
        materialPerHour = material,
        beastsPerHour = bph, limit = limit, pace = pace, supply = supply, killSecs = kill, killBasis = killBasis,
        walkSecs = walk, perBeast = perBeast, skillChance = chance, skillPerHour = bph * chance * skinP,
        gph = gph, valuePerBeast = value, lootPerBeast = lootN > 0 and loot or nil, lootObserved = lootN,
        yieldBasis = priorOnly and "estimate" or "measured", observedSkins = observed, items = items,
        loopYards = loop, spawns = spawns, beasts = byBeast, respawnAssumed = true, competition = competition,
    }
end
