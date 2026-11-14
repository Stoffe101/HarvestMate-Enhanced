-- HarvestMate Enhanced: Core/GPCompat.lua
-- The helpers Gatherpedia's vendored data and logic files (Data/Gatherpedia/*,
-- Glimmer/*) call on the shared private table. Most are taken from Gatherpedia
-- 1.0.1 Core.lua, Copyright (C) 2026 Curs3d221, GPL-3.0-or-later; the profession
-- scan is replaced by HME's Player module so there is one source of skills.

local _, ns = ...
local HME = ns.HME

ns.VERSION = HME.VERSION
ns.ADDON_NAME = HME.ADDON
ns.PROFESSIONS = { "Herbalism", "Mining", "Fishing", "Skinning" }
ns.professions = {}   -- key -> profession definition (filled by Data/Gatherpedia/*.lua)
ns.itemIndex = {}     -- itemID -> { prof = key, entry = entry }
ns.canonical = {}     -- alternate itemID -> main itemID
ns.learned = {}       -- key -> { rank, max } for this character (Core/Player.lua keeps it)
ns.learnedList = {}   -- learned gathering professions, in display order
ns.QUESTION_ICON = "Interface\\Icons\\INV_Misc_QuestionMark"

function ns.IsSecretValue(v) return HME.Hidden(v) end
function ns.ReadableString(v) return HME.Str(v) end
function ns.SafeToString(v, fallback)
    if v == nil then return fallback or "nil" end
    if HME.Hidden(v) then return "unknown" end
    local ok, s = pcall(tostring, v)
    if ok and type(s) == "string" then return s end
    return fallback or "unknown"
end

function ns:Print(msg) HME.Print(msg) end

function ns:RegisterProfession(def)
    for order, entry in ipairs(def.items) do
        entry.prof = def.key
        entry.order = order
    end
    self.professions[def.key] = def
end

function ns:BuildIndex()
    for k in pairs(self.itemIndex) do self.itemIndex[k] = nil end
    for key, def in pairs(self.professions) do
        for _, entry in ipairs(def.items) do
            if entry.id then
                self.itemIndex[entry.id] = { prof = key, entry = entry }
                for _, alt in ipairs(entry.altIDs or {}) do
                    self.itemIndex[alt] = self.itemIndex[entry.id]
                    self.canonical[alt] = entry.id
                end
            end
        end
    end
end

local BONUS_CATEGORIES = { Scarce = true, Gem = true, Bonus = true, Seed = true, Stone = true }
function ns:IsBonusDrop(entry)
    if not entry then return false end
    if entry.bonus ~= nil then return entry.bonus == true end
    return entry.category and BONUS_CATEGORIES[entry.category] or false
end

function ns:IsNodeEntry(entry)
    if not entry or entry.placeholder then return false end
    return not self:IsBonusDrop(entry)
end

function ns:SourceZones(entry)
    if not entry then return {} end
    local out, seen = {}, {}
    local function add(z)
        if z and z ~= "" and not seen[z] then
            seen[z] = true
            out[#out + 1] = z
        end
    end
    for _, id in ipairs(entry.parents or {}) do
        local rec = self.itemIndex[id]
        local parent = rec and rec.entry
        if parent and parent.zones and (not parent.upcoming or entry.upcoming) then
            for _, z in ipairs(parent.zones) do add(z) end
        end
    end
    for _, z in ipairs(entry.zones or {}) do add(z) end
    return out
end

function ns.GetItemIcon(entry)
    if entry.icon then return entry.icon end
    if entry.id then
        local get = (C_Item and C_Item.GetItemIconByID) or _G.GetItemIcon
        local icon = get and get(entry.id)
        if icon and not HME.Hidden(icon) then return icon end
    end
    return ns.QUESTION_ICON
end

function ns.GetItemName(entry)
    if entry.id then
        local get = (C_Item and C_Item.GetItemInfo) or _G.GetItemInfo
        local name = get and HME.Str((get(entry.id)))
        if name then return name end
    end
    return entry.name
end

-- Any item's name by ID: the field guide first, then the client. WoW Forever's
-- client has C_Item.GetItemInfo and no global GetItemInfo, so ask C_Item first.
function ns.ItemNameByID(id)
    id = HME.Num(id)
    if not id then return nil end
    local rec = ns.itemIndex and ns.itemIndex[id]
    local name = rec and rec.entry and (ns.GetItemName(rec.entry) or rec.entry.name)
    if name then return name end
    local get = (C_Item and C_Item.GetItemInfo) or _G.GetItemInfo
    if get then
        local ok, n = pcall(get, id)
        name = ok and HME.Str(n) or nil
    end
    if not name and C_Item and C_Item.RequestLoadItemDataByID then
        pcall(C_Item.RequestLoadItemDataByID, id)
    end
    return name
end

function ns.GetPlayerSkill(prof)
    local p = ns.learned[prof]
    return p and p.rank or nil
end

-- The zone the player is in (micro maps such as caves roll up to the zone).
function ns.GetCurrentZone()
    local mapID = C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
    mapID = HME.Num(mapID)
    if not mapID then return (_G.GetRealZoneText and GetRealZoneText()) or "", nil end
    local microType = (Enum and Enum.UIMapType and Enum.UIMapType.Micro) or 5
    local dungeonType = (Enum and Enum.UIMapType and Enum.UIMapType.Dungeon) or 4
    local info = C_Map.GetMapInfo(mapID)
    local guard = 0
    while info and (info.mapType == microType or info.mapType == dungeonType)
        and info.parentMapID and info.parentMapID ~= 0 and guard < 5 do
        local parent = C_Map.GetMapInfo(info.parentMapID)
        if not parent then break end
        info = parent
        guard = guard + 1
    end
    if info and info.name and info.name ~= "" then return info.name, info.mapID end
    return (_G.GetRealZoneText and GetRealZoneText()) or "", mapID
end
ns.PlayerZoneName = function() return (ns.GetCurrentZone()) end

-- Difficulty of an entry for a skill rank (Gatherpedia's rules).
function ns.GetDifficulty(entry, rank)
    if not rank then return "unknown" end
    if not entry.skill and entry.skillMin then
        if rank < entry.skillMin then return "red" end
        if rank < (entry.skillMax or entry.skillMin) then return "partial" end
        return "all"
    end
    if not entry.skill then return "nodata" end
    if rank < entry.skill then return "red" end
    local t = entry.tiers
    if not t then return "ok" end
    if rank < t[2] then return "orange" end
    if rank < t[3] then return "yellow" end
    if rank < t[4] then return "green" end
    return "gray"
end

-- Gatherpedia's route-start hook (Guides.lua's picker): HME starts the route.
function ns.StartChosenRoute(spot, prof)
    if HME.Guidance and HME.Guidance.StartGuideSpot then HME.Guidance.StartGuideSpot(spot, prof) end
end
