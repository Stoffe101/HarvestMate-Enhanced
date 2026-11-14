-- HarvestMate Enhanced: Engine/Gathering.lua
-- Herbalism, Mining and Fishing farms. For a zone it finds the best region
-- for the goal and estimates what a loop there gives one character.
--
-- Sites (Engine/Spawns.lua) are weighted by the goal:
--   level      skill-up chance of the types you can gather there
--   profit     value of what they give
--   material   share of the wanted node types
--   balanced   both of the first two, each scaled to the zone's best
-- Sites you cannot gather (too low) never count; a shared site counts only
-- the share of types you can gather.
--
-- The loop: the best compact region (Engine/Cluster.lua Region) holds the
-- sites; its length is estimated (Beardwood-Halton-Hammersley, 0.7124 x
-- sqrt(n x area), n = sites one detection radius apart) for ranking, and
-- solved for real (Engine/Optimize.lua via Engine/Planner.lua) once picked.
--   nodes per lap = sites x up-fraction x (1 - competition) x
--                   min(1, lap time / node respawn)
--   up-fraction   share of spawn points holding a node at once: an
--                 assumption (one in three) until you have farmed the area
-- Copyright (C) 2026 HarvestMate Enhanced contributors. GPL-3.0-or-later.

local _, ns = ...
local HME = ns.HME
local U = HME.U
local Geo = HME.Geo
local SM = HME.SkillModel
local Spawns = HME.Spawns
local Cluster = HME.Cluster

local G = {}
HME.Gathering = G

G.UP_FRACTION = 0.33        -- assumed share of spawn points with a node up
G.NODE_RESPAWN = 600        -- assumed seconds before a gathered node is back somewhere
G.GATHER_SECONDS = 4.5      -- cast, loot, and getting back on the path (mounted)
G.DETECT_YARDS = 90         -- how far off the path a node is still worth riding to
G.REGION_CELL = 320
G.MAX_SITES = 180
G.PRIOR_QTY = { Herbalism = 1.6, Mining = 1.5 }
G.FISH_CYCLE = 18           -- seconds per cast, catch and loot (assumption)
G.POOL_CATCHES = 3.5        -- catches per pool before it is empty (assumption)

local function Prof(prof) return prof == "Herbalism" and "herb" or (prof == "Mining" and "mine") or nil end

-- Average amount of each item one gather of this node gives:
-- { [itemID] = qty }, n = gathers observed. Uses HarvestMate's learned drops
-- when there are at least 5, else the main item at the prior quantity.
function G.NodeYield(prof, name)
    local HG = ns.HG
    local out = {}
    local rec = HG and HG.db and HG.db.learned and HG.db.learned.drops and HG.db.learned.drops[name]
    if type(rec) == "table" and (rec.n or 0) >= 5 then
        for id, q in pairs(rec.qty or {}) do out[id] = q / rec.n end
        return out, rec.n
    end
    local t = Spawns.NodeType(prof, name)
    if t and t.itemID then out[t.itemID] = G.PRIOR_QTY[prof] or 1.5 end
    -- HarvestMate's always-dropping extras (stones with ore).
    local seed = HG and HG.SEED_DROPS and HG.SEED_DROPS[name]
    for i, d in ipairs(seed or {}) do
        if i > 1 and d.sure and not out[d.id] then out[d.id] = 1 end
    end
    return out, rec and rec.n or 0
end

function G.NodeValue(prof, name, which)
    local y = G.NodeYield(prof, name)
    local v = 0
    for id, q in pairs(y) do v = v + q * (HME.Prices.Value(id, which) or 0) end
    return v
end

-- Per-type info for this character: req, chance, gatherable, value.
local function TypeInfo(prof, name, skill, which, cache)
    local c = cache[name]
    if c then return c end
    local req = Spawns.Required(prof, name) or 1
    c = { name = name, prof = prof, req = req, gatherable = skill and skill >= req or false,
          chance = SM.Chance(skill or 0, req), value = G.NodeValue(prof, name, which),
          itemID = (Spawns.NodeType(prof, name) or {}).itemID }
    cache[name] = c
    return c
end

-- Weight of every site for a goal. targets: { [node name] = true } or
-- { [itemID] = true } for "material".
-- "Combined": Herbalism and Mining sites together, each valued for its own
-- profession (one loop, both kinds of node).
G.COMBINED = { "Herbalism", "Mining" }
function G.Profs(prof) return prof == "Combined" and G.COMBINED or { prof } end

function G.Weigh(prof, mapID, profile, goal, targets, which)
    local cache = {}
    local w, h = Geo.MapYards(mapID)
    w, h = w or 1500, h or 1000
    local list = {}
    local maxLevel, maxProfit = 0, 0
    for _, p in ipairs(G.Profs(prof)) do
    local skill = profile.skills[p] and profile.skills[p].rank
    for i, s in ipairs(Spawns.Sites(p, mapID)) do
        local lv, pv, mv, gshare = 0, 0, 0, 0
        for name, share in pairs(s.types) do
            local t = TypeInfo(p, name, skill, which, cache)
            if t.gatherable then
                gshare = gshare + share
                lv = lv + share * t.chance
                pv = pv + share * t.value
                if targets and (targets[name] or (t.itemID and targets[t.itemID])) then mv = mv + share end
            end
        end
        if gshare > 0 then
            list[#list + 1] = { s.yx, s.yy, site = s, level = lv, profit = pv, material = mv, gshare = gshare, index = i, prof = p }
            if lv > maxLevel then maxLevel = lv end
            if pv > maxProfit then maxProfit = pv end
        end
    end
    end
    for _, e in ipairs(list) do
        if goal == "level" then e.w = e.level
        elseif goal == "profit" then e.w = e.profit
        elseif goal == "material" then e.w = e.material
        else e.w = (maxLevel > 0 and e.level / maxLevel or 0) + (maxProfit > 0 and e.profit / maxProfit or 0)
        end
    end
    return list, cache, w, h
end

-- Candidate farming areas for a profession on a map (one region per map, the
-- best one; `opts.regions` > 1 gives more, each excluding the previous).
function G.Areas(prof, mapID, profile, goal, opts)
    opts = opts or {}
    local which = (HME.settings and HME.settings.priceMode) or "typical"
    local weighed, cache, w, h = G.Weigh(prof, mapID, profile, goal, opts.targets, which)
    local areas = {}
    local remaining = {}
    for _, e in ipairs(weighed) do if e.w > 0 then remaining[#remaining + 1] = e end end
    for _ = 1, opts.regions or 1 do
        if #remaining < 3 then break end
        local region = Cluster.Region(remaining, G.REGION_CELL, 0.3, opts.maxCells or 8)
        if not region then break end
        local members = {}
        for _, i in ipairs(region.members) do members[#members + 1] = remaining[i] end
        table.sort(members, function(a, b) return a.w > b.w end)
        while #members > G.MAX_SITES do members[#members] = nil end
        local area = { prof = prof, mapID = mapID, goal = goal, cx = region.cx / w, cy = region.cy / h,
            yx = region.cx, yy = region.cy, sites = members, types = cache, cells = region.cells }
        local r = 0
        for _, m in ipairs(members) do
            local d = U.Dist(m[1], m[2], region.cx, region.cy)
            if d > r then r = d end
        end
        area.radius = r
        areas[#areas + 1] = area
        local taken = {}
        for _, m in ipairs(members) do taken[m] = true end
        local rest = {}
        for _, e in ipairs(remaining) do if not taken[e] then rest[#rest + 1] = e end end
        remaining = rest
    end
    return areas
end

-- Loop length estimate for n sites spread over a region.
function G.LoopEstimate(sites, detect)
    if #sites < 2 then return 0, 0 end
    local cells, n = {}, 0
    local cell = math.max(20, detect * 1.2)
    local minx, miny, maxx, maxy = math.huge, math.huge, -math.huge, -math.huge
    for _, s in ipairs(sites) do
        local k = math.floor(s[1] / cell) .. ":" .. math.floor(s[2] / cell)
        if not cells[k] then
            cells[k] = true
            n = n + 1
        end
        if s[1] < minx then minx = s[1] end
        if s[1] > maxx then maxx = s[1] end
        if s[2] < miny then miny = s[2] end
        if s[2] > maxy then maxy = s[2] end
    end
    local area = math.max((maxx - minx) * (maxy - miny), cell * cell)
    return 0.7124 * math.sqrt(n * area), n
end

-- What a loop through `area` gives this character. Fills and returns metrics:
--   loopYards, lapSecs, nodesPerLap, nodesPerHour, skillChance, skillPerHour,
--   gph = { conservative, typical, optimistic }, mix = { {name, share, req,
--   chance, value} }, confirmedShare, upFraction, basis
function G.Evaluate(area, profile, opts)
    opts = opts or {}
    local s = HME.settings or {}
    local competition = U.Clamp((s.competition or 25) / 100, 0, 0.9)
    local speed = profile.speed or 7
    local detect = opts.detect or G.DETECT_YARDS
    local sites = area.sites
    if #sites < 2 then return nil end
    local loop = area.loopYards or G.LoopEstimate(sites, detect)
    local up = G.UP_FRACTION
    local learned = HME.Learning and HME.Learning.Rate(opts.key, "nodes")
    -- Mix of what you will gather: shares over the gatherable part of sites.
    local mixT, totalShare, confirmed = {}, 0, 0
    for _, m in ipairs(sites) do
        for name, share in pairs(m.site.types) do
            local t = area.types[name]
            if t and t.gatherable then
                mixT[name] = (mixT[name] or 0) + share
                totalShare = totalShare + share
            end
        end
        if m.site.confirmed then confirmed = confirmed + 1 end
    end
    local mix, chance, yieldGathers = {}, 0, 0
    local value = { conservative = 0, typical = 0, optimistic = 0 }
    for name, share in pairs(mixT) do
        local t = area.types[name]
        local p = share / totalShare
        chance = chance + p * t.chance
        for which in pairs(value) do value[which] = value[which] + p * G.NodeValue(t.prof, name, which) end
        local _, seen = G.NodeYield(t.prof, name)
        yieldGathers = yieldGathers + (seen or 0)
        mix[#mix + 1] = { name = name, prof = t.prof, share = p, req = t.req, chance = t.chance, value = t.value, itemID = t.itemID }
    end
    table.sort(mix, function(a, b) return a.share > b.share end)
    local n = #sites
    -- Solve lap time with the respawn cap: try the full count, then cap.
    local function lap(nodes) return loop / speed + nodes * (G.GATHER_SECONDS + detect / speed) end
    local perLap = n * up * (1 - competition)
    local secs = lap(perLap)
    local cap = math.min(1, secs / G.NODE_RESPAWN)
    if cap < 1 then
        perLap = perLap * cap
        secs = lap(perLap)
    end
    local nph = perLap * 3600 / math.max(secs, 1)
    if learned then nph = learned.blend(nph) end
    -- Conservative assumes 15% fewer nodes, optimistic 10% more.
    local PACE = { conservative = 0.85, typical = 1, optimistic = 1.1 }
    local gph = {}
    for which, v in pairs(value) do gph[which] = nph * PACE[which] * v end
    return {
        loopYards = loop, lapSecs = secs, nodesPerLap = perLap, nodesPerHour = nph, skillChance = chance,
        skillPerHour = nph * chance, gph = gph, valuePerNode = value, mix = mix, sites = n,
        confirmedShare = n > 0 and confirmed / n or 0, upFraction = up, respawnCapped = cap < 1, yieldGathers = yieldGathers,
        basis = learned and "measured" or "estimate", competition = competition,
    }
end

---------------------------------------------------------------------------
-- Fishing
---------------------------------------------------------------------------

-- The fish a zone gives (Gatherpedia's Fishing list), each with a value.
function G.ZoneFish(zoneName, which)
    local def = ns.professions and ns.professions.Fishing
    local out = {}
    for _, e in ipairs(def and def.items or {}) do
        if e.id and not e.upcoming then
            for _, z in ipairs(e.zones or {}) do
                if z == zoneName then
                    out[#out + 1] = { id = e.id, name = e.name, value = HME.Prices.Value(e.id, which) or 0, water = e.water }
                    break
                end
            end
        end
    end
    return out
end

-- Open-water fishing in a zone: { catchesPerHour, landing, skillPerHour, gph,
-- fish, zoneMin, noGetaway } or nil when the zone's fishing skill is unknown.
function G.EvaluateFishing(mapID, profile, opts)
    local zone = HME.ZoneData.Name(mapID)
    local Zones = ns.Zones
    local zoneMin, noGet
    if Zones and Zones.FishSkill then zoneMin, noGet = Zones:FishSkill(zone) end
    local skill = profile.skills.Fishing and profile.skills.Fishing.rank
    if not skill or not zoneMin then return nil end
    local landing = SM.FishLanding(skill, zoneMin, noGet)
    if landing <= 0 then return { zoneMin = zoneMin, noGetaway = noGet, tooLow = true } end
    local cph = 3600 / G.FISH_CYCLE * landing
    local learned = HME.Learning and HME.Learning.Rate(opts and opts.key, "catches")
    if learned then cph = learned.blend(cph) end
    local fish = {}
    for _, which in ipairs({ "conservative", "typical", "optimistic" }) do
        fish[which] = G.ZoneFish(zone, which)
    end
    local gph = {}
    for which, list in pairs(fish) do
        local v = 0
        for _, f in ipairs(list) do v = v + f.value end
        gph[which] = #list > 0 and cph * v / #list or 0
    end
    local material
    if opts and opts.targets then
        local hits = 0
        for _, f in ipairs(fish.typical) do if opts.targets[f.id] or opts.targets[f.name] then hits = hits + 1 end end
        if hits == 0 then return nil end
        material = cph * hits / math.max(1, #fish.typical)
    end
    local pools = 0
    for _, e in ipairs(Spawns.DbNodes("Fishing", mapID)) do pools = pools + U.PackedCount(e[4]) end
    return {
        catchesPerHour = cph, landing = landing, skillChance = SM.FishChance(skill, zoneMin),
        skillPerHour = cph * SM.FishChance(skill, zoneMin), gph = gph, fish = fish.typical,
        zoneMin = zoneMin, noGetaway = noGet, pools = pools, basis = learned and "measured" or "estimate", materialPerHour = material,
    }
end
