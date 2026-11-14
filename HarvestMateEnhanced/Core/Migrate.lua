-- HarvestMate Enhanced: Core/Migrate.lua
-- Brings saved data in from the addons HME replaces: HarvestMate
-- (HarvestMateDB), Gatherpedia (GatherpediaDB / GatherpediaCharDB) and
-- GatherPath Forever (GatherPathForeverDB).
--
-- The game only loads an addon's saved variables while that addon is enabled,
-- so the old addon has to be enabled for the one login that copies its data.
-- The old tables are only read, never changed or cleared: the old addon keeps
-- working if the player goes back to it. Each import happens once; the time is
-- kept in HarvestMateEnhancedDB.migrations, and /hme import <name> repeats it
-- (it then only adds what is missing; counts are never doubled).
--
-- Copyright (C) 2026 HarvestMate Enhanced contributors. GPL-3.0-or-later.

local _, ns = ...
local HME = ns.HME
local U = HME.U

local M = {}
HME.Migrate = M

M.SOURCES = {
    { key = "harvestmate", addon = "HarvestMate", global = "HarvestMateDB", alt = "HarvestGaugeDB", label = "HarvestMate" },
    { key = "gatherpedia", addon = "Gatherpedia", global = "GatherpediaDB", label = "Gatherpedia" },
    { key = "gatherpath", addon = "GatherPathForever", global = "GatherPathForeverDB", label = "GatherPath Forever" },
}

local function Loaded(addon)
    local fn = (C_AddOns and C_AddOns.IsAddOnLoaded) or _G.IsAddOnLoaded
    if not fn then return false end
    local ok, v = pcall(fn, addon)
    return ok and v == true
end
M.Loaded = Loaded

-- Copies keys from src into dst where dst has nothing yet (deep for tables).
local function Merge(dst, src, depth)
    depth = depth or 0
    if depth > 10 then return 0 end
    local n = 0
    for k, v in pairs(src) do
        if dst[k] == nil then
            dst[k] = U.Copy(v)
            n = n + 1
        elseif type(dst[k]) == "table" and type(v) == "table" then
            n = n + Merge(dst[k], v, depth + 1)
        end
    end
    return n
end
M.Merge = Merge

-- Counters (gathers per zone, item counts) take the larger of the two, so
-- importing the same data again never counts it twice.
local function MaxCounts(dst, src)
    for k, v in pairs(src) do
        if type(v) == "number" then
            dst[k] = math.max(type(dst[k]) == "number" and dst[k] or 0, v)
        elseif type(v) == "table" then
            dst[k] = type(dst[k]) == "table" and dst[k] or {}
            MaxCounts(dst[k], v)
        end
    end
end

local IMPORT = {}

function IMPORT.harvestmate(old, db)
    -- Options are kept as HME set them (its defaults are safer for controls);
    -- learned data, achievements and records come across.
    local hm = db.hm
    local n = 0
    for k, v in pairs(old) do
        if k ~= "opt" and k ~= "cvarBefore" and k ~= "ctmBefore" and hm[k] == nil then
            hm[k] = U.Copy(v)
            n = n + 1
        end
    end
    if type(old.learned) == "table" then
        hm.learned = type(hm.learned) == "table" and hm.learned or {}
        n = n + Merge(hm.learned, old.learned)
    end
    -- Display choices that change nothing about the player's controls carry over.
    local SAFE_OPTS = { "herb", "mine", "skin", "showOwn", "showReq", "colorize", "showBands", "showLoot",
        "showPrices", "profit", "cultivation", "itemTips", "nearby", "nearbySound", "trackWarn",
        "treasureWarn", "trainWarn", "lock", "gearWarn", "achToast", "achSound", "fontSize" }
    if type(old.opt) == "table" then
        hm.opt = type(hm.opt) == "table" and hm.opt or {}
        for _, k in ipairs(SAFE_OPTS) do
            if old.opt[k] ~= nil then hm.opt[k] = old.opt[k] end
        end
        -- The gather key and announcements need the player's yes again in HME.
        if old.opt.gatherKey then hm.wasGatherKey = old.opt.gatherKeyBind or "F" end
    end
    return n
end

function IMPORT.gatherpedia(old, db)
    local gp = db.gp
    local n = 0
    for _, k in ipairs({ "counts", "gathers" }) do
        if type(old[k]) == "table" then
            gp[k] = type(gp[k]) == "table" and gp[k] or {}
            MaxCounts(gp[k], old[k])
            n = n + 1
        end
    end
    for _, k in ipairs({ "discovered", "zoneMaps", "firsts", "sparkle", "skinMobs", "trainers", "options" }) do
        if type(old[k]) == "table" then
            gp[k] = type(gp[k]) == "table" and gp[k] or {}
            n = n + Merge(gp[k], old[k])
        end
    end
    -- Beasts Gatherpedia saw skinned (or not) feed the shared mob checks.
    local mobs = db.obs.mobs
    if type(old.skinMobs) == "table" then
        for id, on in pairs(old.skinMobs.yes or {}) do if on and mobs[id] == nil then mobs[id] = true end end
        for id, on in pairs(old.skinMobs.no or {}) do if on and mobs[id] == nil then mobs[id] = false end end
    end
    local char = _G.GatherpediaCharDB
    if type(char) == "table" then
        if type(char.learnedOrder) == "table" and #HME.char.learnedOrder == 0 then
            HME.char.learnedOrder = U.Copy(char.learnedOrder)
        end
        for _, k in ipairs({ "showAllProfessions", "arrowScale", "lastRouteProf" }) do
            if char[k] ~= nil then HME.char[k] = U.Copy(char[k]) end
        end
    end
    return n
end

function IMPORT.gatherpath(old, db)
    local r = db.routes
    local n = 0
    -- Settings: everything the route system keeps, where HME has nothing yet.
    for k, v in pairs(old) do
        if k ~= "routes" and k ~= "taboos" and k ~= "skip" and k ~= "nextID" and r[k] == nil then
            r[k] = U.Copy(v)
        end
    end
    r.routes = type(r.routes) == "table" and r.routes or {}
    r.nextID = math.max(type(r.nextID) == "number" and r.nextID or 1, type(old.nextID) == "number" and old.nextID or 1)
    local have = {}
    for _, route in ipairs(r.routes) do have[(route.mapID or 0) .. "|" .. tostring(route.name)] = true end
    for _, route in ipairs(type(old.routes) == "table" and old.routes or {}) do
        if type(route) == "table" and not have[(route.mapID or 0) .. "|" .. tostring(route.name)] then
            local copy = U.Copy(route)
            copy.id = r.nextID
            r.nextID = r.nextID + 1
            copy.source = "GatherPath"
            r.routes[#r.routes + 1] = copy
            n = n + 1
        end
    end
    r.taboos = type(r.taboos) == "table" and r.taboos or {}
    if type(old.taboos) == "table" then
        for mapID, list in pairs(old.taboos) do
            if not r.taboos[mapID] then
                r.taboos[mapID] = U.Copy(list)
                n = n + 1
            end
        end
    end
    r.skip = type(r.skip) == "table" and r.skip or {}
    Merge(r.skip, type(old.skip) == "table" and old.skip or {})
    return n
end

-- Imports every source whose data is loaded and not yet imported (or `force`).
function M.Run(force)
    local db = HME.db
    local done = {}
    for _, src in ipairs(M.SOURCES) do
        local old = _G[src.global]
        if type(old) ~= "table" and src.alt then old = _G[src.alt] end
        local already = db.migrations[src.key]
        if type(old) == "table" and (force == true or force == src.key or not already) then
            local ok, n = pcall(IMPORT[src.key], old, db)
            if ok then
                db.migrations[src.key] = { t = (time and time()) or 0, items = n }
                done[#done + 1] = src.label
            else
                HME.Debug("import from", src.label, "failed:", n)
            end
        end
    end
    if #done > 0 then
        M.justImported = done
    end
    return done
end

-- Which replaced addons are running right now (they would double up on the
-- same events, bindings and map lines). The UI offers to turn them off.
function M.Conflicts()
    local list = {}
    for _, src in ipairs(M.SOURCES) do
        if Loaded(src.addon) then list[#list + 1] = src end
    end
    return list
end

-- True while the old addon that owns this feature is itself running: HME's
-- copy then stays quiet ("harvestmate": one-key gathering, nearby banner,
-- tooltips; "gatherpedia": Glimmer; "gatherpath": route lines).
function M.Paused(key)
    for _, src in ipairs(M.SOURCES) do
        if src.key == key then return Loaded(src.addon) end
    end
    return false
end
HME.Paused = M.Paused

-- Turns the replaced addons off for this character; takes effect on /reload.
-- Only ever called from a button the player pressed.
function M.DisableReplaced()
    local fn = (C_AddOns and C_AddOns.DisableAddOn) or _G.DisableAddOn
    if not fn then return 0 end
    local n = 0
    for _, src in ipairs(M.Conflicts()) do
        if pcall(fn, src.addon) then n = n + 1 end
    end
    return n
end

HME.On("PLAYER_LOGIN", function()
    if M.justImported and HME.settings.notifications ~= false then
        HME.Print("copied your saved data from " .. table.concat(M.justImported, ", ")
            .. ". The old addons' own data was not changed.")
    end
    local conflicts = M.Conflicts()
    if #conflicts > 0 then
        local names = {}
        for i, c in ipairs(conflicts) do names[i] = c.label end
        HME.conflicts = conflicts
        HME.Print("|cffffd100" .. table.concat(names, ", ") .. "|r "
            .. (#names == 1 and "is" or "are") .. " still enabled. HME has paused its own copies of those "
            .. "features so nothing runs twice. Open /hme to import and turn the old ones off.")
    end
end)
