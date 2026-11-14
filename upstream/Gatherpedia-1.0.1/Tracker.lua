-- Gatherpedia: Tracker.lua
-- Counts what you gather (per item, per zone), learns new gatherables that are
-- not in the built-in data, keeps session statistics and adds a line to item
-- tooltips.
--
-- How a gather is recognised (no hard-coded spell IDs are required):
--   * The loot window opens (LOOT_READY) and we look at where the loot came from.
--   * Fishing:   IsFishingLoot() is true.
--   * Node:      the loot source GUID is a GameObject (herb, vein, pool) and the
--                loot contains a known Herbalism/Mining item, or a gathering cast
--                just happened. Plain treasure chests don't match either rule.
--   * Skinning:  the source is a Creature, there is no money in the loot, every
--                item is a skinning material (or a skinning cast just happened),
--                and this character has Skinning.
-- Spell casts are only hints. With /gp debug on, unknown cast IDs that led to a
-- gather are printed and saved so they can be reported.

local ADDON_NAME, ns = ...

local Tracker = CreateFrame("Frame")
ns.Tracker = Tracker

-- Hint spells. Forever IDs come from Wowhead's Forever database (which one
-- fires in game is unconfirmed); Classic IDs are kept for older clients.
local HINT_SPELLS = {
    [1235236] = "Herbalism",  -- Herb Gathering (Forever)
    [1272737] = "Herbalism",  -- Marefoil "Collecting herbs" (Forever)
    [1272739] = "Herbalism",  -- Demonsage "Collecting herbs" (Forever)
    [2366] = "Herbalism", [2368] = "Herbalism", [3570] = "Herbalism", [11993] = "Herbalism",
    [2575] = "Mining", [2576] = "Mining", [3564] = "Mining", [10248] = "Mining",
    [1240952] = "Skinning", [1240974] = "Skinning", [1240987] = "Skinning", -- Forever ranks
    [8613] = "Skinning", [8617] = "Skinning", [8618] = "Skinning", [10768] = "Skinning",
    [7620] = "Fishing", [7731] = "Fishing", [7732] = "Fishing", [18248] = "Fishing",
}
-- English cast names that also count as hints (localised names are added at load).
local HINT_NAMES = {
    ["Herb Gathering"] = "Herbalism", ["Collecting herbs"] = "Herbalism",
    ["Mining"] = "Mining", ["Skinning"] = "Skinning", ["Fishing"] = "Fishing",
}
local HINT_WINDOW = 8   -- seconds a cast hint stays valid

-- Item classes accepted as new discoveries: Consumable (fish), Gem, Trade Goods.
local DISCOVERY_CLASSES = { [0] = true, [3] = true, [7] = true }

local hint             -- { prof, t, spellID, name, known }
local lastCast         -- most recent player cast, for debug logging
local lootHandled = false

-- Session statistics live in Session.lua (ns.session, not saved).

local function SpellName(id)
    if C_Spell and C_Spell.GetSpellName then return C_Spell.GetSpellName(id) end
    if GetSpellInfo then return (GetSpellInfo(id)) end
end

local function BuildHintNames()
    for id, prof in pairs(HINT_SPELLS) do
        local name = SpellName(id)
        if name and not HINT_NAMES[name] then HINT_NAMES[name] = prof end
    end
end

local function ItemIDFromLink(link)
    if not link then return nil end
    local id
    if C_Item and C_Item.GetItemIDForItemInfo then id = C_Item.GetItemIDForItemInfo(link) end
    if not id then
        local s = link:match("item:(%d+)")
        id = s and tonumber(s)
    end
    return id and (ns.canonical[id] or id)
end

local function ItemClass(id)
    if C_Item and C_Item.GetItemInfoInstant then
        return select(6, C_Item.GetItemInfoInstant(id))
    elseif GetItemInfoInstant then
        return select(6, GetItemInfoInstant(id))
    end
end

-- Which profession an item belongs to (built-in data or your discoveries).
local function ProfOfItem(id)
    local known = ns.itemIndex[id]
    if known then return known.prof end
    for prof, list in pairs(ns.db.discovered) do
        if list[id] then return prof end
    end
end

local function SourceKind(slot)
    if not GetLootSourceInfo then return nil end
    local guid = ns.ReadableString(GetLootSourceInfo(slot))
    return guid and guid:match("^(%a+)") or nil
end

---------------------------------------------------------------------------
-- Classification
---------------------------------------------------------------------------

-- NPC ID of the creature this loot slot came from, or nil.
local function SourceNPC(slot)
    if not GetLootSourceInfo then return nil end
    local guid = ns.ReadableString(GetLootSourceInfo(slot))
    if type(guid) ~= "string" then return nil end
    local kind, _, _, _, _, id = strsplit("-", guid)
    if kind ~= "Creature" then return nil end
    return tonumber(id)
end

-- Returns the profession this loot window belongs to, or nil.
function Tracker:Classify(slots)
    if IsFishingLoot and IsFishingLoot() then return "Fishing" end

    local recentHint = hint and (GetTime() - hint.t) <= HINT_WINDOW and hint.prof or nil
    local kind
    for _, s in ipairs(slots) do kind = kind or s.kind end

    if kind == "GameObject" then
        local votes = {}
        for _, s in ipairs(slots) do
            local p = s.itemID and ProfOfItem(s.itemID)
            if p == "Herbalism" or p == "Mining" then votes[p] = (votes[p] or 0) + 1 end
        end
        if votes.Herbalism or votes.Mining then
            return (votes.Herbalism or 0) >= (votes.Mining or 0) and "Herbalism" or "Mining"
        end
        if recentHint == "Herbalism" or recentHint == "Mining" or recentHint == "Fishing" then
            return recentHint
        end
        return nil
    end

    if kind == "Creature" or kind == "Vehicle" then
        if not ns.learned.Skinning then return nil end
        local allSkins, anyItem = true, false
        for _, s in ipairs(slots) do
            if s.isMoney then return nil end            -- skinning never gives coins
            if s.itemID then
                anyItem = true
                if ProfOfItem(s.itemID) ~= "Skinning" then allSkins = false end
            end
        end
        if not anyItem then return nil end
        if allSkins or recentHint == "Skinning" then return "Skinning" end
        return nil
    end

    -- No source info available (older clients): fall back to a cast hint.
    if kind == nil and recentHint then return recentHint end
    return nil
end

---------------------------------------------------------------------------
-- Log a gather
---------------------------------------------------------------------------

function Tracker:LogGather(prof, itemID, quantity, zone, mapID, name, icon, quality)
    local db = ns.db

    if not ns.itemIndex[itemID] then
        -- Not in our data: learn it if it looks like a real gatherable.
        local classID = ItemClass(itemID)
        if (quality or 1) < 1 or (classID and not DISCOVERY_CLASSES[classID]) then
            return
        end
        local list = db.discovered[prof]
        if not list[itemID] then
            list[itemID] = { name = name, icon = icon, quality = quality, first = time(), zone = zone }
            if db.options.announce then
                ns:Print(("New discovery for %s: %s. It now has its own page."):format(
                    prof, name or ("item " .. itemID)))
            end
        end
    end

    local perZone = db.counts[itemID]
    if not perZone then
        perZone = {}
        db.counts[itemID] = perZone
    end
    perZone[zone] = (perZone[zone] or 0) + quantity
    if mapID then db.zoneMaps[zone] = mapID end
    if not db.firsts[itemID] then db.firsts[itemID] = time() end

    ns.Session:OnItem(prof, itemID, quantity, zone, name, icon)
end

function Tracker:HandleLoot()
    if lootHandled then return end
    local n = GetNumLootItems() or 0
    if n == 0 then return end

    local slots = {}
    for slot = 1, n do
        local link = GetLootSlotLink(slot)
        local icon, name, quantity, _, quality = GetLootSlotInfo(slot)
        local money = (Enum and Enum.LootSlotType and Enum.LootSlotType.Money) or 2
        local isMoney = (GetLootSlotType and GetLootSlotType(slot) == money)
            or (not link and LootSlotIsCoin and LootSlotIsCoin(slot)) or false
        slots[#slots + 1] = {
            itemID = ItemIDFromLink(link), icon = icon, name = name, quality = quality,
            quantity = (quantity and quantity > 0) and quantity or 1,
            isMoney = isMoney,
            kind = SourceKind(slot),
            npcID = SourceNPC(slot),
        }
    end

    local prof = self:Classify(slots)
    if not prof then return end
    lootHandled = true

    local zone, mapID = ns.GetCurrentZone()
    local db = ns.db
    db.gathers[prof][zone] = (db.gathers[prof][zone] or 0) + 1
    ns.Session:OnGather(prof, zone)

    if prof == "Skinning" and ns.SpawnPins then
        for _, s in ipairs(slots) do
            if s.npcID then ns.SpawnPins:LearnSkinned(s.npcID); break end
        end
    end

    for _, s in ipairs(slots) do
        if s.itemID then
            self:LogGather(prof, s.itemID, s.quantity, zone, mapID, s.name, s.icon, s.quality)
        end
    end

    -- Debug: report the cast that preceded this gather if we didn't know it.
    if db.options.debug and lastCast and (GetTime() - lastCast.t) <= HINT_WINDOW and not lastCast.known then
        db.debugSpells[lastCast.spellID] = lastCast.name or "?"
        ns:Print(("debug: %s gather after unknown spell %d (%s). Please report this ID."):format(
            prof, lastCast.spellID, lastCast.name or "?"))
    end
    hint = nil
    lastCast = nil

    if ns.UI then ns.UI:RequestRefresh() end
end

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------

Tracker:SetScript("OnEvent", function(self, event, ...)
    if event == "UNIT_SPELLCAST_SUCCEEDED" then
        local unit, _, spellID = ...
        if unit ~= "player" or not spellID then return end
        local name = SpellName(spellID)
        local prof = HINT_SPELLS[spellID] or (name and HINT_NAMES[name])
        lastCast = { spellID = spellID, name = name, t = GetTime(), known = HINT_SPELLS[spellID] ~= nil }
        if prof then hint = { prof = prof, t = GetTime() } end
    elseif event == "LOOT_READY" or event == "LOOT_OPENED" then
        self:HandleLoot()
    elseif event == "LOOT_CLOSED" then
        lootHandled = false
    end
end)

---------------------------------------------------------------------------
-- Tooltip line: "Gatherpedia: 37 gathered - Mining 125 (Guaranteed skill-up)"
---------------------------------------------------------------------------

local function AddTooltipLine(tooltip, itemID)
    if not itemID or not ns.db then return end
    itemID = ns.canonical[itemID] or itemID
    local prof = ProfOfItem(itemID)
    if not prof then return end

    local known = ns.itemIndex[itemID]
    local text = ns.Colorize("e6c35c", "Gatherpedia: ") .. ns:GetTotalCount(itemID) .. " gathered"
    if known and known.entry.skill then
        local diff = ns.GetDifficulty(known.entry, ns.GetPlayerSkill(prof))
        text = text .. "  " .. ns.Colorize(ns.DIFFICULTY[diff].hex,
            prof .. " " .. known.entry.skill .. (diff ~= "unknown" and (" - " .. ns.DIFFICULTY[diff].label) or ""))
    elseif known and known.entry.skillMin then
        local diff = ns.GetDifficulty(known.entry, ns.GetPlayerSkill(prof))
        local e = known.entry
        local range = (e.skillMax and e.skillMax ~= e.skillMin) and (e.skillMin .. "-" .. e.skillMax) or tostring(e.skillMin)
        text = text .. "  " .. ns.Colorize(ns.DIFFICULTY[diff].hex, prof .. " " .. range)
    elseif known and known.entry.upcoming then
        text = text .. "  " .. ns.Colorize("9a8f78", known.entry.upcoming)
    end
    tooltip:AddLine(text)
    if known and known.entry and known.entry.found and known.entry.found ~= "" then
        tooltip:AddLine(known.entry.found, 1, 0.82, 0.2, true)
    end
    tooltip:Show()
end

local function HookTooltips()
    if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum and Enum.TooltipDataType then
        TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, function(tooltip, data)
            if tooltip ~= GameTooltip and tooltip ~= ItemRefTooltip then return end
            local id = data and data.id
            if id and ns.IsSecretValue(id) then return end
            pcall(AddTooltipLine, tooltip, id)
        end)
    elseif GameTooltip and GameTooltip.HookScript then
        local function OnSetItem(tooltip)
            local ok, _, link = pcall(function() return tooltip:GetItem() end)
            if not ok then return end
            pcall(AddTooltipLine, tooltip, ItemIDFromLink(ns.ReadableString(link)))
        end
        GameTooltip:HookScript("OnTooltipSetItem", OnSetItem)
        if ItemRefTooltip then ItemRefTooltip:HookScript("OnTooltipSetItem", OnSetItem) end
    end
end

function Tracker:Enable()
    BuildHintNames()
    self:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED")
    self:RegisterEvent("LOOT_READY")
    self:RegisterEvent("LOOT_OPENED")
    self:RegisterEvent("LOOT_CLOSED")
    HookTooltips()
end
