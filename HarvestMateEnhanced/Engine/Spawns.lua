-- HarvestMate Enhanced: Engine/Spawns.lua
-- The one place that answers "where can this herb / ore / pool / beast be".
-- It merges, with the source of every point kept:
--   db      the bundled spawn data (QuestieDB, Forever build, via Gatherpedia):
--           every place a node or beast CAN appear, not where one is now
--   gm2     GatherMate2's recorded nodes, when it is installed and allowed
--   player  nodes this account actually gathered (HME.db.obs.nodes)
--   import  nodes someone else shared through an export
--
-- Sites: points closer than SITE_YARDS are one site. A site can hold several
-- node types (Mithril and Truesilver share spawn points, so do several herbs);
-- each type then gets a share of the site, so value and skill-ups are never
-- counted twice. A site confirmed by the player or GatherMate2 is marked
-- confirmed; a site only in the bundled data is a prediction.
-- Copyright (C) 2026 HarvestMate Enhanced contributors. GPL-3.0-or-later.

local _, ns = ...
local HME = ns.HME
local U = HME.U
local Geo = HME.Geo

local S = {}
HME.Spawns = S

S.SITE_YARDS = 6
S.dbEnabled = true   -- tests (and a future setting) can leave the bundled spawns out
S.PROFS = { "Herbalism", "Mining", "Fishing" }
-- GatherMate2's node kinds for our professions.
S.GM2_KIND = { Herbalism = "Herb Gathering", Mining = "Mining", Fishing = "Fishing" }

local nodeTypeIndex   -- [prof][name] = { itemID, skill }

local function TypeIndex()
    if nodeTypeIndex then return nodeTypeIndex end
    nodeTypeIndex = {}
    for prof, maps in pairs(ns.NodeSpawns or {}) do
        local idx = {}
        nodeTypeIndex[prof] = idx
        for _, list in pairs(maps) do
            for _, e in ipairs(list) do
                if not idx[e[1]] then idx[e[1]] = { itemID = e[2], skill = e[3] } end
            end
        end
    end
    -- HarvestMate's resource table adds names and requirements the spawn
    -- data lacks (and the learned lower requirements).
    local HG = ns.HG
    if HG and HG.RESOURCES then
        for name, r in pairs(HG.RESOURCES) do
            local prof = (r.prof == "herb" and "Herbalism") or (r.prof == "mine" and "Mining") or nil
            if prof then
                nodeTypeIndex[prof] = nodeTypeIndex[prof] or {}
                local idx = nodeTypeIndex[prof]
                if not idx[name] then
                    local seed = HG.SEED_DROPS and HG.SEED_DROPS[name]
                    idx[name] = { itemID = seed and seed[1] and seed[1].id, skill = r.req }
                end
            end
        end
    end
    return nodeTypeIndex
end

-- { itemID, skill } for a node name, or nil.
function S.NodeType(prof, name)
    local idx = TypeIndex()[prof]
    return idx and idx[name]
end

-- The skill a node needs, with what the player has learned (a successful
-- gather below the table's number lowers it).
function S.Required(prof, name)
    local t = S.NodeType(prof, name)
    local req = t and t.skill
    local HG = ns.HG
    if HG and HG.db and HG.db.learned and HG.db.learned.lowest then
        local low = HG.db.learned.lowest[name]
        if type(low) == "number" and (not req or low < req) then req = low end
    end
    return req
end

---------------------------------------------------------------------------
-- Raw sources
---------------------------------------------------------------------------

-- Node types with bundled points on a map: { { name, itemID, skill, packed } }
function S.DbNodes(prof, mapID)
    if not S.dbEnabled then return {} end
    local maps = ns.NodeSpawns and ns.NodeSpawns[prof]
    return maps and maps[mapID] or {}
end

function S.Beasts(mapID)
    return ns.SkinningMobs and ns.SkinningMobs[mapID] or {}
end

-- Maps with bundled data for a profession (Skinning: beasts).
function S.Maps(prof)
    local list = {}
    if not S.dbEnabled then return list end
    local src = prof == "Skinning" and ns.SkinningMobs or (ns.NodeSpawns and ns.NodeSpawns[prof])
    for id in pairs(src or {}) do list[#list + 1] = id end
    table.sort(list)
    return list
end

local function UseGM2()
    local gm = _G.GatherMate2
    return HME.settings and HME.settings.gathermate ~= false and type(gm) == "table"
        and type(gm.GetNodesForZone) == "function" and type(gm.DecodeLoc) == "function"
end
S.UseGM2 = UseGM2

-- Calls fn(x, y, name) for GatherMate2's nodes of that profession on a map.
function S.EachGM2(prof, mapID, fn)
    if not UseGM2() then return end
    local kind = S.GM2_KIND[prof]
    if not kind then return end
    local gm = _G.GatherMate2
    pcall(function()
        for coord, nodeID in gm:GetNodesForZone(mapID, kind, true) do
            local x, y = gm:DecodeLoc(coord)
            local name = gm.GetNameForNode and gm:GetNameForNode(kind, nodeID) or nil
            if x and y then fn(x, y, name) end
        end
    end)
end

-- The player's own gathered nodes on a map.
function S.EachObserved(prof, mapID, fn)
    local cells = HME.db and HME.db.obs.nodes[mapID]
    if not cells then return end
    for _, rec in pairs(cells) do
        if rec.p == prof and rec.x then fn(rec.x, rec.y, rec.n, rec) end
    end
end

-- Records one gathered node (Engine/Learning.lua calls this).
function S.Observe(prof, mapID, x, y, name)
    if not (HME.db and mapID and x and y) then return end
    local cells = HME.db.obs.nodes[mapID]
    if not cells then
        cells = {}
        HME.db.obs.nodes[mapID] = cells
    end
    local key = math.floor(x * 400) .. ":" .. math.floor(y * 400)
    local rec = cells[key]
    local now = (time and time()) or 0
    if rec then
        rec.c = (rec.c or 1) + 1
        rec.t = now
        rec.imp = nil
        if name and rec.n ~= name then rec.alt = name end
    else
        cells[key] = { p = prof, n = name, x = U.Round(x, 4), y = U.Round(y, 4), c = 1, t = now }
        HME.DBM.TrimMap(cells, HME.DBM.LIMITS.nodesPerMap)
    end
    S.Invalidate(prof, mapID)
end

---------------------------------------------------------------------------
-- Sites
---------------------------------------------------------------------------
local siteCache = {}
local cacheVersion = 0

function S.Invalidate(prof, mapID)
    if prof and mapID then
        siteCache[prof .. ":" .. mapID] = nil
        siteCache[prof .. ":" .. mapID .. ":gm"] = nil
    else
        siteCache = {}
    end
    cacheVersion = cacheVersion + 1
end
HME.Listen("LEARNED", function() S.Invalidate() end)
HME.Listen("SETTINGS", function() S.Invalidate() end)

function S.Version() return cacheVersion end

-- All sites of a profession on a map:
--   { x, y, yx, yy (yards), types = { [name] = share }, sources = { db, gm2, player, import },
--     confirmed, n = points merged }
-- `types` shares add up to 1 at each site.
function S.Sites(prof, mapID)
    -- GatherMate2 being there (or allowed) is part of the key: switching it
    -- off in Settings never shows stale sites.
    local key = prof .. ":" .. mapID .. (UseGM2() and ":gm" or "")
    local cached = siteCache[key]
    if cached then return cached end
    local t0 = HME.Clock()
    local w, h = Geo.MapYards(mapID)
    w, h = w or 1500, h or 1000
    local cell = S.SITE_YARDS
    local grid, sites = {}, {}
    local function add(x, y, name, src)
        local yx, yy = x * w, y * h
        local gx, gy = math.floor(yx / cell), math.floor(yy / cell)
        local found
        for dx = -1, 1 do
            for dy = -1, 1 do
                local list = grid[(gx + dx) .. ":" .. (gy + dy)]
                if list then
                    for _, s in ipairs(list) do
                        if not found and U.Dist(s.yx, s.yy, yx, yy) <= cell then found = s end
                    end
                end
            end
        end
        if not found then
            found = { x = x, y = y, yx = yx, yy = yy, types = {}, sources = {}, n = 0 }
            sites[#sites + 1] = found
            local gk = gx .. ":" .. gy
            grid[gk] = grid[gk] or {}
            table.insert(grid[gk], found)
        end
        found.n = found.n + 1
        found.sources[src] = (found.sources[src] or 0) + 1
        if name then found.types[name] = (found.types[name] or 0) + 1 end
    end
    for _, e in ipairs(S.DbNodes(prof, mapID)) do
        local name = e[1]
        U.EachPacked(e[4], function(x, y) add(x, y, name, "db") end)
    end
    S.EachGM2(prof, mapID, function(x, y, name) add(x, y, name, "gm2") end)
    S.EachObserved(prof, mapID, function(x, y, name, rec) add(x, y, name, rec.imp and "import" or "player") end)
    for _, s in ipairs(sites) do
        local total = 0
        for _, c in pairs(s.types) do total = total + c end
        if total > 0 then
            for name, c in pairs(s.types) do s.types[name] = c / total end
        end
        s.confirmed = (s.sources.player or s.sources.gm2) and true or false
    end
    siteCache[key] = sites
    HME.Perf.Add("spawns:sites", HME.Clock() - t0)
    return sites
end

-- How many sites of each node type on a map: { [name] = { sites, confirmed } }
function S.TypeCounts(prof, mapID)
    local out = {}
    for _, s in ipairs(S.Sites(prof, mapID)) do
        for name, share in pairs(s.types) do
            local t = out[name] or { sites = 0, confirmed = 0, share = 0 }
            out[name] = t
            t.sites = t.sites + 1
            t.share = t.share + share
            if s.confirmed then t.confirmed = t.confirmed + 1 end
        end
    end
    return out
end

-- Every map where a node type (by name) or item (by id) appears, with counts.
function S.WhereIs(prof, nameOrItem)
    local out = {}
    for mapID, list in pairs((ns.NodeSpawns and ns.NodeSpawns[prof]) or {}) do
        local n = 0
        for _, e in ipairs(list) do
            if e[1] == nameOrItem or e[2] == nameOrItem then n = n + U.PackedCount(e[4]) end
        end
        if n > 0 then out[#out + 1] = { mapID = mapID, points = n } end
    end
    table.sort(out, function(a, b) return a.points > b.points end)
    return out
end

---------------------------------------------------------------------------
-- Beast spawn points, decoded once per map: { { npcID, name, min, max, elite,
-- pts = { {x, y}, ... } } }
---------------------------------------------------------------------------
local beastCache = {}
function S.BeastPoints(mapID)
    if beastCache[mapID] then return beastCache[mapID] end
    local out = {}
    for _, m in ipairs(S.Beasts(mapID)) do
        local pts = {}
        U.EachPacked(m[6], function(x, y) pts[#pts + 1] = { x, y } end)
        out[#out + 1] = { npcID = m[1], name = m[2], min = m[3], max = m[4], elite = m[5] == 1, pts = pts }
    end
    beastCache[mapID] = out
    return out
end

-- Has the game told us this beast can (true) or can't (false) be skinned?
function S.Skinnable(npcID)
    local v = HME.db and HME.db.obs.mobs[npcID]
    if v ~= nil then return v end
    local HG = ns.HG
    local learned = HG and HG.db and HG.db.learned and HG.db.learned.skinnable
    if learned and learned[npcID] ~= nil then return learned[npcID] and true or false end
    return nil
end
