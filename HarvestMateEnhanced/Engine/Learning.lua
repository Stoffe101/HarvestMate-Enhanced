-- HarvestMate Enhanced: Engine/Learning.lua
-- Turns what happens while you play into data HME uses next time:
--   * where you gathered each node          -> Spawns (confirmed sites)
--   * what each beast gave when skinned     -> HME.db.obs.skins[npcID]
--   * what a beast's corpse dropped         -> HME.db.obs.loot[npcID]
--   * whether a beast could be skinned      -> HME.db.obs.mobs[npcID]
--   * how long your fights take             -> HME.char.eff.kill (per character)
--   * where you died                        -> HME.db.obs.deaths
--   * measured rates per farming area       -> HME.db.stats[key]
--
-- Measured rates are blended with the model, never swapped in outright:
--   estimate = (hours x measured + H0 x model) / (hours + H0),  H0 = 1 hour
-- so one bad 15-minute session moves a farm's number by a fifth, not all the
-- way, and an area farmed for hours is ranked by what it really gave.
-- Copyright (C) 2026 HarvestMate Enhanced contributors. GPL-3.0-or-later.

local _, ns = ...
local HME = ns.HME
local U = HME.U
local Num, Str = HME.Num, HME.Str

local L = {}
HME.Learning = L

L.H0 = 1.0          -- model weight in hours
L.MIN_HOURS = 0.1   -- below this, measured rates are not used

---------------------------------------------------------------------------
-- Measured rates per area
---------------------------------------------------------------------------

-- The measured rate for a metric ("nodes", "beasts", "catches", "skillups",
-- "value") per hour in an area, with a blend function; nil without data.
function L.Rate(key, metric)
    if not key or not HME.db then return nil end
    local st = HME.db.stats[key]
    if not st or (st.hours or 0) < L.MIN_HOURS then return nil end
    local measured = (st[metric] or 0) / st.hours
    local hours = st.hours
    return {
        value = measured, hours = hours, sessions = st.sessions or 0,
        blend = function(model) return (hours * measured + L.H0 * model) / (hours + L.H0) end,
    }
end

-- Adds a finished stretch of farming to an area's totals.
function L.AddStats(key, delta)
    if not key or not HME.db then return end
    local st = HME.db.stats[key]
    if not st then
        st = { hours = 0, sessions = 0 }
        HME.db.stats[key] = st
    end
    for k, v in pairs(delta) do
        if type(v) == "number" then st[k] = (st[k] or 0) + v end
    end
    st.t = (time and time()) or 0
    HME.DBM.TrimMap(HME.db.stats, HME.DBM.LIMITS.areaStats)
end

-- One session's rates in an area, for ranges (newest 30 kept).
function L.AddSample(key, sample)
    if not key or not HME.db then return end
    local st = HME.db.stats[key]
    if not st then return end
    st.samples = type(st.samples) == "table" and st.samples or {}
    sample.t = (time and time()) or 0
    U.Push(st.samples, sample, 30)
end

-- Observed vs predicted for an area: ratio and whether it is a clear signal
-- (at least 1.5 hours and two sessions).
function L.Verdict(key, metric, model)
    local r = L.Rate(key, metric)
    if not r or not model or model <= 0 then return nil end
    local ratio = r.value / model
    local sure = r.hours >= 1.5 and r.sessions >= 2
    return ratio, sure, r
end

---------------------------------------------------------------------------
-- Beasts: npcID -> bundled levels (for kill-time samples)
---------------------------------------------------------------------------
local npcIndex
function L.Npc(npcID)
    if not npcIndex then
        npcIndex = {}
        for mapID, list in pairs(ns.SkinningMobs or {}) do
            for _, m in ipairs(list) do
                if not npcIndex[m[1]] then npcIndex[m[1]] = { min = m[3], max = m[4], name = m[2], elite = m[5] == 1, mapID = mapID } end
            end
        end
    end
    return npcIndex[npcID]
end

local function NpcIDFromGUID(guid)
    guid = Str(guid)
    if not guid then return nil end
    local kind, id = guid:match("^(%a+)%-%d+%-%d+%-%d+%-%d+%-(%d+)")
    if kind == "Creature" or kind == "Vehicle" then return tonumber(id) end
    return nil
end
L.NpcIDFromGUID = NpcIDFromGUID

---------------------------------------------------------------------------
-- Loot: who it came from and whether it was a skinning.
---------------------------------------------------------------------------
local skinCastAt = -100
local fishCastAt = -100
local SKIN_SPELLS = { [8613] = true, [8617] = true, [8618] = true, [10768] = true }
local FISH_SPELLS = { [7620] = true, [7731] = true, [7732] = true, [18248] = true }

HME.On("UNIT_SPELLCAST_SUCCEEDED", function(_, unit, _, spellID)
    if unit ~= "player" then return end
    spellID = Num(spellID)
    if not spellID then return end
    if SKIN_SPELLS[spellID] then skinCastAt = HME.Now() end
    if FISH_SPELLS[spellID] then fishCastAt = HME.Now() end
end, "player")

local moneyAtOpen
local lootSource
local processed, processedList = {}, {}

local function ReadLoot()
    local count = Num(GetNumLootItems and GetNumLootItems()) or 0
    local items = {}
    for slot = 1, count do
        local link = GetLootSlotLink and Str(GetLootSlotLink(slot))
        local id = link and tonumber(link:match("item:(%d+)"))
        if id then
            local qty = GetLootSlotInfo and Num((select(3, GetLootSlotInfo(slot)))) or 1
            items[id] = (items[id] or 0) + math.max(qty or 1, 1)
        end
    end
    return items
end

local function OnLoot()
    if not HME.db then return end
    local now = HME.Now()
    local guid
    if GetLootSourceInfo then
        local ok, g = pcall(GetLootSourceInfo, 1)
        guid = ok and g or nil
    end
    local npcID = NpcIDFromGUID(guid)
    local items = ReadLoot()
    local fishing = (IsFishingLoot and IsFishingLoot()) or (now - fishCastAt < 3 and not npcID)
    if fishing then
        HME.Signal("FISH_CAUGHT", items)
        return
    end
    if not npcID then return end
    local g = Str(guid)
    local skinning = now - skinCastAt < 4
    -- The same corpse can be reported more than once (LOOT_OPENED twice, a
    -- reopened window): each corpse is counted once per kind of loot.
    local key = g and ((skinning and "s:" or "l:") .. g)
    if key then
        if processed[key] then return end
        processed[key] = true
        processedList[#processedList + 1] = key
        if #processedList > 200 then processed[table.remove(processedList, 1)] = nil end
    end
    if skinning then
        local rec = HME.db.obs.skins[npcID]
        if not rec then
            rec = { n = 0, qty = {}, items = {}, zones = {} }
            HME.db.obs.skins[npcID] = rec
        end
        rec.n = rec.n + 1
        rec.t = (time and time()) or 0
        rec.zones = rec.zones or {}
        local mapID = HME.Player.Position()
        if mapID then rec.zones[mapID] = (rec.zones[mapID] or 0) + 1 end
        for id, q in pairs(items) do
            rec.qty[id] = (rec.qty[id] or 0) + q
            rec.items[id] = (rec.items[id] or 0) + 1
        end
        HME.db.obs.mobs[npcID] = true
        HME.Signal("BEAST_SKINNED", npcID, items, g)
    else
        lootSource = { npcID = npcID, items = items, at = now }
        moneyAtOpen = Num(GetMoney and GetMoney())
        HME.Signal("BEAST_LOOTED", npcID, items, g)
    end
end
HME.On("LOOT_OPENED", OnLoot)

HME.On("LOOT_CLOSED", function()
    local src = lootSource
    lootSource = nil
    if not (src and HME.db) then return end
    local money = Num(GetMoney and GetMoney())
    local copper = (money and moneyAtOpen) and math.max(0, money - moneyAtOpen) or 0
    local vendor = 0
    for id, q in pairs(src.items) do vendor = vendor + (HME.Prices.Vendor(id) or 0) * q end
    local rec = HME.db.obs.loot[src.npcID]
    if not rec then
        rec = { n = 0, copper = 0, vendor = 0 }
        HME.db.obs.loot[src.npcID] = rec
    end
    rec.n, rec.copper, rec.vendor = rec.n + 1, rec.copper + copper, rec.vendor + vendor
    rec.t = (time and time()) or 0
    HME.DBM.TrimMap(HME.db.obs.loot, 3000)
end)

-- "That creature can't be skinned" style errors teach the beast is not skinnable.
HME.On("UI_ERROR_MESSAGE", function(_, _, msg)
    msg = Str(msg)
    if not msg then return end
    local unskinnable = _G.ERR_CANT_SKIN or "can't be skinned"
    if msg == unskinnable then
        local guid = UnitGUID and UnitGUID("target")
        local id = NpcIDFromGUID(guid)
        if id and HME.db and HME.db.obs.mobs[id] == nil then HME.db.obs.mobs[id] = false end
    end
end)

---------------------------------------------------------------------------
-- Kill time: one sample per fight that ended with exactly one beast looted
-- whose level we know. Kept per character, newest 200.
---------------------------------------------------------------------------
local fightStart
local fightLoots = {}

HME.On("PLAYER_REGEN_DISABLED", function()
    fightStart = HME.Now()
    fightLoots = {}
end)

HME.Listen("BEAST_LOOTED", function(npcID)
    fightLoots[#fightLoots + 1] = npcID
end)

-- A fight is a sample only when it is unambiguous: exactly one beast of
-- known level looted, 2-180 seconds. Fights with several beasts (or adds),
-- nothing looted (someone else's tag, an evade, a flight) or an unknown beast
-- are counted as unclear, never as kill time. A hunter's pet is part of the
-- character's own pace, so pet-assisted kills are measured as they are.
HME.On("PLAYER_REGEN_ENABLED", function()
    local started = fightStart
    fightStart = nil
    if not started then return end
    local secs = HME.Now() - started
    local loots = fightLoots
    -- Loot usually comes right after combat ends: wait for it.
    HME.After(6, function()
        if not HME.char then return end
        local npc = #loots == 1 and L.Npc(loots[1])
        if not npc or secs < 2 or secs > 180 then
            HME.char.eff.ambiguous = (HME.char.eff.ambiguous or 0) + 1
            return
        end
        local level = HME.Player.Level()
        local diff = (npc.min + npc.max) / 2 - level
        U.Push(HME.char.eff.kill, { d = U.Round(diff, 1), s = U.Round(secs, 1), e = npc.elite or nil,
            t = (time and time()) or 0, lvl = level }, HME.DBM.LIMITS.killSamples)
    end)
end)

---------------------------------------------------------------------------
-- Nodes gathered (HarvestMate's Learn.lua tells which node and profession).
---------------------------------------------------------------------------
HME.Listen("GATHER_LOOT", function(prof, key)
    local full = HME.Player.FROM_SHORT[prof]
    if not (full and key and full ~= "Skinning") then return end
    local mapID, x, y = HME.Player.Position()
    if not (mapID and x) then return end
    HME.Spawns.Observe(full, mapID, x, y, key)
end)

-- The field guide's own counts (Gatherpedia's "Known zones" check marks):
-- items gathered per zone, kept in HarvestMateEnhancedDB.gp.counts.
local function Count(items)
    if not (ns.db and ns.db.counts) then return end
    local zone = HME.Player.ZoneName()
    if not zone or zone == "" then return end
    for id, q in pairs(items or {}) do
        local main = ns.canonical[id] or id
        if ns.itemIndex[main] then
            local t = ns.db.counts[main] or {}
            ns.db.counts[main] = t
            t[zone] = (t[zone] or 0) + q
        end
    end
end
HME.Listen("GATHER_LOOT", function(_, _, counts) Count(counts) end)
HME.Listen("BEAST_SKINNED", function(_, items) Count(items) end)
HME.Listen("FISH_CAUGHT", function(items) Count(items) end)

HME.On("PLAYER_DEAD", function()
    local mapID, x, y = HME.Player.Position()
    HME.Risk.NoteDeath(mapID, x, y)
    HME.Signal("PLAYER_DIED", mapID, x, y)
end)
