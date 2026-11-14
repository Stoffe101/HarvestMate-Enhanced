-- HarvestMate Enhanced: Core/DB.lua
-- One account-wide saved table (HarvestMateEnhancedDB) and one per character
-- (HarvestMateEnhancedCharDB), with sections for each subsystem, a schema
-- number with step-by-step upgrades, size limits, export/import and resets.
--
--   HarvestMateEnhancedDB
--     schema, created
--     settings   HME's own settings (Settings page)
--     hm         HarvestMate's section (opt, learned, banner, achievements...)
--     gp         Gatherpedia's section (counts, gathers, discovered, sparkle...)
--     routes     GatherPath's section (routes, taboo areas, skip list, display)
--     obs        what the player saw: nodes, skins, mob checks, deaths (bounded)
--     stats      per farming area: sessions and measured rates (bounded)
--     sessions   finished farming sessions, newest last (bounded)
--     migrations when each old addon's data was copied in
--   HarvestMateEnhancedCharDB
--     plan       manual overrides for planning (level, skills), off by default
--     guidance   the route being followed, so it survives /reload
--     eff        this character's measured efficiency (kill time, speed)
--     favorites, recents, goals, ui
--
-- Copyright (C) 2026 HarvestMate Enhanced contributors. GPL-3.0-or-later.

local _, ns = ...
local HME = ns.HME
local U = HME.U

local DB = {}
HME.DBM = DB

DB.SCHEMA = 1

-- Limits on what grows with play. Old entries go first.
DB.LIMITS = {
    nodesPerMap = 1500,   -- player-observed node positions per map
    deaths = 200,
    sessions = 120,
    killSamples = 200,
    areaStats = 400,
    recents = 15,
}

DB.SETTINGS = {
    debug = false,
    performance = "normal",      -- "normal" or "low" (smaller background budget, fewer pins)
    scale = 1.0,                 -- main window scale
    layout = "expanded",         -- "expanded" or "compact"
    minimapButton = true,
    minimapAngle = 225,
    -- map overlays
    nodePins = true,             -- spawn pins on the world map while previewing a farm
    nodePinsAlways = false,      -- ... or always, for your gathering professions
    huntAreas = true,            -- shaded hunting areas for skinning farms
    huntAlpha = 30,              -- their opacity (percent)
    pinScale = 1.0,
    -- guidance
    arrow = true,                -- the on-screen arrow to the next stop
    arrowScale = 1.0,
    arriveYards = 30,
    hud = true,                  -- the farming HUD while a farm is active
    hudLocked = false,
    hudCompact = false,
    -- recommendations
    autoGuide = true,            -- say when a better farm opens up as skill rises
    riskMode = "balanced",       -- "fastest", "balanced" or "safer"
    avoidZones = {},             -- [zone name] = true: never recommended
    priceMode = "typical",       -- "conservative", "typical" or "optimistic"
    saleMode = "best",           -- "auction", "vendor" or "best" (higher of the two)
    priceProvider = "auto",      -- "auto", "ForeverGPS", "Auctionator", "TSM" or "vendor"
    profitScope = "skinning",    -- "skinning" (materials only) or "total" (with mob loot)
    sessionMinutes = 60,         -- how long you plan to farm: spreads the trip there over it
    competition = 25,            -- percent of nodes and mobs others take (assumption, changeable)
    includeUnverified = true,    -- use spawn data marked classic/unverified (shown as such)
    -- integrations
    forevergps = true,
    gathermate = true,
    questie = true,
    tomtom = false,
    -- input
    controller = true,           -- controller-friendly focus inside HME's window
    notifications = true,
    tooltips = true,
}

local CHAR_DEFAULTS = {
    plan = { enabled = false, level = nil, skills = {} },
    guidance = {},
    eff = { kill = {}, speed = nil },
    favorites = {},
    recents = {},
    goals = {},
    ui = { tab = "dashboard", finder = { prof = nil, goal = "level" } },
    learnedOrder = {},
    showAllProfessions = false,
    arrowScale = 1,
}

local function Section(root, key)
    if type(root[key]) ~= "table" then root[key] = {} end
    return root[key]
end

local function Fill(dst, defaults)
    for k, v in pairs(defaults) do
        if type(v) == "table" then
            if type(dst[k]) ~= "table" then dst[k] = U.Copy(v) end
        elseif dst[k] == nil or type(dst[k]) ~= type(v) then
            dst[k] = v
        end
    end
    return dst
end

-- Schema upgrades: UPGRADES[n] turns a schema n-1 table into schema n.
DB.UPGRADES = {
    [1] = function(db)
        Section(db, "settings")
    end,
}

function DB.Prepare(saved)
    if type(saved) ~= "table" then saved = {} end
    local from = type(saved.schema) == "number" and saved.schema or 0
    for n = from + 1, DB.SCHEMA do
        local up = DB.UPGRADES[n]
        if up then up(saved) end
        saved.schema = n
    end
    if from > DB.SCHEMA then
        -- Saved by a newer version: keep everything, use what we understand.
        HME.newerData = from
    end
    saved.created = saved.created or (time and time()) or 0
    Fill(Section(saved, "settings"), DB.SETTINGS)
    Section(saved, "hm")
    Section(saved, "gp")
    Section(saved, "routes")
    local obs = Section(saved, "obs")
    Section(obs, "nodes")    -- [mapID] = { [cell] = { p = prof, n = name, x, y, c = count, t = last } }
    Section(obs, "skins")    -- [npcID] = { n = skins, items = { [id] = times }, qty = { [id] = total }, lvl }
    Section(obs, "mobs")     -- [npcID] = true (skinnable) / false (checked, not skinnable)
    Section(obs, "deaths")   -- { { m = mapID, x, y, t }, ... }
    Section(obs, "loot")     -- [npcID] = { n = looted, copper = total, vendor = total value }
    Section(saved, "stats")
    Section(saved, "sessions")
    Section(saved, "migrations")
    return saved
end

function DB.PrepareChar(saved)
    if type(saved) ~= "table" then saved = {} end
    Fill(saved, CHAR_DEFAULTS)
    if type(saved.plan.skills) ~= "table" then saved.plan.skills = {} end
    if type(saved.eff.kill) ~= "table" then saved.eff.kill = {} end
    return saved
end

function DB.Init()
    _G.HarvestMateEnhancedDB = DB.Prepare(_G.HarvestMateEnhancedDB)
    _G.HarvestMateEnhancedCharDB = DB.PrepareChar(_G.HarvestMateEnhancedCharDB)
    HME.db = _G.HarvestMateEnhancedDB
    HME.char = _G.HarvestMateEnhancedCharDB
    HME.settings = HME.db.settings
    if HME.Migrate then HME.Try(HME.Migrate.Run) end
    -- Gatherpedia's modules read ns.db (their section) and ns.charDB.
    ns.db = HME.db.gp
    ns.db.zoneMaps = type(ns.db.zoneMaps) == "table" and ns.db.zoneMaps or {}
    ns.db.counts = type(ns.db.counts) == "table" and ns.db.counts or {}
    ns.db.options = type(ns.db.options) == "table" and ns.db.options or { showUndiscovered = true }
    ns.charDB = HME.char
    -- HarvestMate's modules read ns.HG.db.
    ns.HG.Init(HME.db.hm)
    HME.Signal("DB_READY")
end

---------------------------------------------------------------------------
-- Bounded growth
---------------------------------------------------------------------------

-- Drops the oldest entries of a { [key] = { t = time } } map down to `limit`.
function DB.TrimMap(map, limit)
    local n = U.Count(map)
    if n <= limit then return 0 end
    local list = {}
    for k, v in pairs(map) do list[#list + 1] = { k = k, t = type(v) == "table" and v.t or 0 } end
    table.sort(list, function(a, b) return a.t < b.t end)
    local drop = n - limit
    for i = 1, drop do map[list[i].k] = nil end
    return drop
end

function DB.Size()
    local nodes, maps = 0, 0
    for _, cells in pairs(HME.db.obs.nodes) do
        maps = maps + 1
        nodes = nodes + U.Count(cells)
    end
    return {
        nodes = nodes, maps = maps,
        skins = U.Count(HME.db.obs.skins),
        deaths = #HME.db.obs.deaths,
        sessions = #HME.db.sessions,
        areas = U.Count(HME.db.stats),
        routes = HME.db.routes.routes and #HME.db.routes.routes or 0,
    }
end

---------------------------------------------------------------------------
-- Resets. Each asks first in the UI; these do the work.
---------------------------------------------------------------------------
function DB.ResetSettings()
    for k in pairs(HME.db.settings) do HME.db.settings[k] = nil end
    Fill(HME.db.settings, DB.SETTINGS)
    HME.Signal("SETTINGS")
end

function DB.ResetLearned()
    local obs = HME.db.obs
    for _, k in ipairs({ "nodes", "skins", "mobs", "deaths", "loot" }) do obs[k] = {} end
    HME.db.stats = {}
    HME.db.sessions = {}
    HME.char.eff = { kill = {} }
    HME.Signal("LEARNED")
end

---------------------------------------------------------------------------
-- Export / import. A small typed text format (no code is ever run on
-- import): s<len>:<text>  n<number>;  t / f  {  }  — keys and values alternate.
---------------------------------------------------------------------------
local function Ser(v, out, depth)
    local tv = type(v)
    if tv == "string" then
        out[#out + 1] = "s" .. #v .. ":" .. v
    elseif tv == "number" then
        out[#out + 1] = "n" .. (v == math.floor(v) and string.format("%d", v) or string.format("%.6g", v)) .. ";"
    elseif tv == "boolean" then
        out[#out + 1] = v and "t" or "f"
    elseif tv == "table" then
        if depth > 12 then error("too deep") end
        out[#out + 1] = "{"
        local keys = {}
        for k in pairs(v) do
            if type(k) == "string" or type(k) == "number" then keys[#keys + 1] = k end
        end
        table.sort(keys, function(a, b)
            if type(a) ~= type(b) then return type(a) == "number" end
            return a < b
        end)
        for _, k in ipairs(keys) do
            local val = v[k]
            local t = type(val)
            if t == "string" or t == "number" or t == "boolean" or t == "table" then
                Ser(k, out, depth + 1)
                Ser(val, out, depth + 1)
            end
        end
        out[#out + 1] = "}"
    end
end

function DB.Serialize(v)
    local out = {}
    Ser(v, out, 0)
    return table.concat(out)
end

function DB.Deserialize(s)
    if type(s) ~= "string" then return nil, "not text" end
    local pos = 1
    local function value(depth)
        if depth > 14 then error("too deep") end
        local c = s:sub(pos, pos)
        if c == "s" then
            local len, colon = s:match("^s(%d+)():", pos)
            if not len then error("bad string at " .. pos) end
            len = tonumber(len)
            local start = colon + 1
            local str = s:sub(start, start + len - 1)
            if #str ~= len then error("short string") end
            pos = start + len
            return str
        elseif c == "n" then
            local num, after = s:match("^n([%-%d%.eE+]+);()", pos)
            if not num then error("bad number at " .. pos) end
            pos = after
            return tonumber(num)
        elseif c == "t" then
            pos = pos + 1
            return true
        elseif c == "f" then
            pos = pos + 1
            return false
        elseif c == "{" then
            pos = pos + 1
            local t = {}
            while s:sub(pos, pos) ~= "}" do
                if pos > #s then error("unclosed table") end
                local k = value(depth + 1)
                local val = value(depth + 1)
                if type(k) ~= "string" and type(k) ~= "number" then error("bad key") end
                t[k] = val
            end
            pos = pos + 1
            return t
        end
        error("unexpected '" .. c .. "' at " .. pos)
    end
    local ok, result = pcall(value, 0)
    if not ok then return nil, result end
    if pos <= #s then return nil, "trailing data" end
    return result
end

-- What can be shared: routes, taboo areas, the skip list and learned nodes.
local EXPORT_HEADER = "HME1:"

local function Checksum(s)
    local h = 0
    for i = 1, #s do h = (h * 31 + s:byte(i)) % 4294967291 end
    return string.format("%08x", h)
end

function DB.Export(what)
    what = what or { routes = true, taboos = true, nodes = false }
    local payload = { v = 1 }
    local r = HME.db.routes
    if what.routes then payload.routes = r.routes end
    if what.taboos then
        payload.taboos = r.taboos
        payload.skip = r.skip
    end
    if what.nodes then payload.nodes = HME.db.obs.nodes end
    local body = DB.Serialize(payload)
    return EXPORT_HEADER .. Checksum(body) .. ":" .. body
end

-- Returns the decoded payload without changing anything (the UI shows what
-- would be added, then calls DB.ApplyImport).
function DB.ReadImport(text)
    text = U.Trim(text or "")
    local sum, body = text:match("^HME1:(%x+):(.*)$")
    if not sum then return nil, "This is not a HarvestMate Enhanced export." end
    if Checksum(body) ~= sum then return nil, "The text was changed or cut short (checksum)." end
    local data, err = DB.Deserialize(body)
    if not data then return nil, "Could not read it: " .. tostring(err) end
    if type(data) ~= "table" or data.v ~= 1 then return nil, "Unknown export version." end
    return data
end

-- Adds imported routes (renamed on a clash), taboo areas and nodes. Never
-- replaces what is there. Returns counts.
function DB.ApplyImport(data)
    local added = { routes = 0, taboos = 0, nodes = 0 }
    local r = HME.db.routes
    r.routes = r.routes or {}
    r.taboos = r.taboos or {}
    r.skip = r.skip or {}
    r.nextID = r.nextID or 1
    for _, route in ipairs(type(data.routes) == "table" and data.routes or {}) do
        if type(route) == "table" and type(route.mapID) == "number" and type(route.points) == "table" then
            local copy = U.Copy(route)
            copy.id = r.nextID
            r.nextID = r.nextID + 1
            copy.working = nil
            local base = type(copy.name) == "string" and copy.name or "Imported route"
            local name, n = base, 1
            local taken = true
            while taken do
                taken = false
                for _, other in ipairs(r.routes) do
                    if other.mapID == copy.mapID and other.name == name then taken = true end
                end
                if taken then
                    n = n + 1
                    name = base .. " (" .. n .. ")"
                end
            end
            copy.name = name
            r.routes[#r.routes + 1] = copy
            added.routes = added.routes + 1
        end
    end
    for mapID, list in pairs(type(data.taboos) == "table" and data.taboos or {}) do
        if type(mapID) == "number" and type(list) == "table" then
            r.taboos[mapID] = r.taboos[mapID] or {}
            for _, poly in ipairs(list) do
                if type(poly) == "table" and #poly >= 6 then
                    table.insert(r.taboos[mapID], U.Copy(poly))
                    added.taboos = added.taboos + 1
                end
            end
        end
    end
    for name, on in pairs(type(data.skip) == "table" and data.skip or {}) do
        if type(name) == "string" and on == true then r.skip[name] = true end
    end
    for mapID, cells in pairs(type(data.nodes) == "table" and data.nodes or {}) do
        if type(mapID) == "number" and type(cells) == "table" then
            local mine = HME.db.obs.nodes[mapID] or {}
            HME.db.obs.nodes[mapID] = mine
            for cell, rec in pairs(cells) do
                if type(rec) == "table" and mine[cell] == nil and type(rec.x) == "number" then
                    mine[cell] = U.Copy(rec)
                    mine[cell].imp = true   -- came from someone else: shown as imported
                    added.nodes = added.nodes + 1
                end
            end
            DB.TrimMap(mine, DB.LIMITS.nodesPerMap)
        end
    end
    HME.Signal("LEARNED")
    HME.Signal("ROUTES_CHANGED")
    return added
end

HME.On("ADDON_LOADED", function(_, name)
    if name ~= HME.ADDON or HME.db then return end
    DB.Init()
end)
