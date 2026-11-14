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
--
-- Per character first (0.3.0): each character keeps its own totals per area
-- (HarvestMateEnhancedCharDB.stats). Your own hours count in full; other
-- characters' hours in the same area count OTHERS_WEIGHT as much (a quarter
-- for beasts, whose pace depends on the character), so a farm that is slow
-- for one character is not written off for all.
-- Copyright (C) 2026 HarvestMate Enhanced contributors. GPL-3.0-or-later.

local _, ns = ...
local HME = ns.HME
local U = HME.U
local Num, Str = HME.Num, HME.Str

local L = {}
HME.Learning = L

L.H0 = 1.0          -- model weight in hours
L.MIN_HOURS = 0.1   -- below this, measured rates are not used
L.OTHERS_WEIGHT = { beasts = 0.25, skins = 0.25, value = 0.5, skillups = 0.5 }
L.OTHERS_DEFAULT = 0.6

local function Own(key) return HME.char and type(HME.char.stats) == "table" and HME.char.stats[key] or nil end
local function All(key) return HME.db and HME.db.stats[key] or nil end

-- This character's and the others' hours and totals for one metric.
local function Split(key, metric)
    local own, all = Own(key), All(key)
    local oh, oc = own and own.hours or 0, own and own[metric] or 0
    local ah, ac = all and all.hours or 0, all and all[metric] or 0
    -- The account totals include this character's own (both are written).
    local xh, xc = math.max(0, ah - oh), math.max(0, ac - oc)
    return oh, oc, xh, xc, own, all
end
L.Split = Split

---------------------------------------------------------------------------
-- Measured rates per area
---------------------------------------------------------------------------

-- The measured rate for a metric ("nodes", "beasts", "catches", "skillups",
-- "value") per hour in an area, with a blend function; nil without data.
function L.Rate(key, metric)
    if not key or not HME.db then return nil end
    local oh, oc, xh, xc, own, all = Split(key, metric)
    local w = L.OTHERS_WEIGHT[metric] or L.OTHERS_DEFAULT
    local hours = oh + w * xh
    if hours < L.MIN_HOURS then return nil end
    local measured = (oc + w * xc) / hours
    return {
        value = measured, hours = hours, ownHours = oh, otherHours = xh,
        sessions = (own and own.sessions or 0) + (all and math.max(0, (all.sessions or 0) - (own and own.sessions or 0)) or 0),
        ownSessions = own and own.sessions or 0,
        blend = function(model) return (hours * measured + L.H0 * model) / (hours + L.H0) end,
    }
end

-- How much of an area's evidence is this character's own: hours and sessions.
function L.Own(key)
    local own = Own(key)
    return own and own.hours or 0, own and own.sessions or 0
end

-- Adds a finished stretch of farming to an area's totals.
function L.AddStats(key, delta)
    if not key or not HME.db then return end
    local function Into(root)
        local st = root[key]
        if not st then
            st = { hours = 0, sessions = 0 }
            root[key] = st
        end
        for k, v in pairs(delta) do
            if type(v) == "number" then st[k] = (st[k] or 0) + v end
        end
        st.t = (time and time()) or 0
    end
    Into(HME.db.stats)
    HME.DBM.TrimMap(HME.db.stats, HME.DBM.LIMITS.areaStats)
    if HME.char then
        if type(HME.char.stats) ~= "table" then HME.char.stats = {} end
        Into(HME.char.stats)
        HME.DBM.TrimMap(HME.char.stats, HME.DBM.LIMITS.areaStats)
    end
end

-- Forgets what was learned about an area (Stats page: Reset this area), for
-- this character only or for every character.
function L.ResetArea(key, everyone)
    if HME.char and type(HME.char.stats) == "table" then HME.char.stats[key] = nil end
    if everyone and HME.db then HME.db.stats[key] = nil end
    HME.Signal("LEARNED")
end

---------------------------------------------------------------------------
-- Area reputation: plain labels derived from evidence only.
---------------------------------------------------------------------------
-- { { label, why } }: "Consistently productive", "Often underperforming",
-- "Good for leveling", "Good for profit", "High travel overhead",
-- "Frequently interrupted", "Needs more observations".
function L.Reputation(key, model)
    local out = {}
    local own, sessions = L.Own(key)
    local st = Own(key) or All(key)
    if not st or (st.hours or 0) < L.MIN_HOURS then
        out[1] = { label = "Needs more observations", why = "you have not farmed here long enough to judge" }
        return out
    end
    model = model or {}
    local hours = st.hours
    if model.value and model.value > 0 then
        local ratio, sure = L.Verdict(key, "value", model.value)
        if ratio and sure and ratio >= 1.1 then
            out[#out + 1] = { label = "Consistently productive", why = ("%d%% above the estimate over %d sessions"):format((ratio - 1) * 100, sessions) }
        elseif ratio and sure and ratio <= 0.8 then
            out[#out + 1] = { label = "Often underperforming", why = ("%d%% below the estimate over %d sessions"):format((1 - ratio) * 100, sessions) }
        end
    end
    local sph = (st.skillups or 0) / hours
    if sph >= 40 and hours >= 0.5 then out[#out + 1] = { label = "Good for leveling", why = ("%.0f skill-ups an hour measured"):format(sph) } end
    local gph = (st.value or 0) / hours
    if model.gph and model.gph > 0 and gph >= model.gph * 1.1 and hours >= 1 then
        out[#out + 1] = { label = "Good for profit", why = "more value an hour than the estimate" }
    end
    local travel = st.travelHours or 0
    if travel > 0 and travel / (travel + hours) >= 0.3 then
        out[#out + 1] = { label = "High travel overhead", why = ("%d%% of the trips was travel"):format(travel / (travel + hours) * 100) }
    end
    if (st.deaths or 0) >= 2 or (st.idleHours or 0) / hours >= 0.25 then
        out[#out + 1] = { label = "Frequently interrupted", why = (st.deaths or 0) >= 2 and ((st.deaths) .. " deaths here") or "much idle time" }
    end
    if hours < 1.5 or sessions < 2 then
        out[#out + 1] = { label = "Needs more observations", why = ("%.1f h over %d of your sessions so far"):format(own, sessions) }
    end
    return out
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
-- What the loot tracker decided, newest last (for /hme diag after a test).
---------------------------------------------------------------------------
L.recent = {}
local function Note(kind, npcID, items, how)
    local n = 0
    for _, q in pairs(items or {}) do n = n + q end
    U.Push(L.recent, { t = HME.Now(), kind = kind, npc = npcID, items = n, how = how }, 30)
end
L.Note = Note

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
        Note("fish", nil, items, IsFishingLoot and "fishing loot" or "after a cast")
        HME.Signal("FISH_CAUGHT", items)
        return
    end
    if not npcID then
        -- A node, a chest, or a source the game did not name: not attributed here.
        if next(items) then Note("unattributed", nil, items, "no creature source") end
        return
    end
    local g = Str(guid)
    -- A corpse already skinned has no other loot: a repeated window is that skin.
    if g and processed["s:" .. g] then return end
    local skinning = now - skinCastAt < 4
    local skinAt = skinCastAt
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
        -- One skinning cast is one skin: a corpse looted right after is loot.
        skinCastAt = -100
        Note("skin", npcID, items, "skin cast " .. string.format("%.1f", now - skinAt) .. " s before")
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
        Note("loot", npcID, items, guid and "corpse" or "no source")
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
            Note("fight", loots[1], nil, ("unclear (%d looted, %.0f s): not a kill-time sample"):format(#loots, secs))
            return
        end
        Note("fight", loots[1], nil, ("kill-time sample %.0f s"):format(secs))
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
