-- Gatherpedia: Core.lua
-- Namespace, saved variables, shared helpers, profession registry and slash commands.
-- Copyright (C) 2026 Curs3d221. Licensed under the GNU GPL v3 or later; see LICENSE.

local ADDON_NAME, ns = ...

ns.VERSION = "1.0.1"
ns.ICON = "Interface\\AddOns\\Gatherpedia\\Media\\Icon"                -- 128x128 TGA (gold G), TOC / large uses
ns.ICON_HEADER = "Interface\\AddOns\\Gatherpedia\\Media\\Icon64"       -- 64x64 TGA, window header (drawn at 36 px)
ns.ICON_MINIMAP = "Interface\\AddOns\\Gatherpedia\\Media\\IconMinimap" -- 64x64 tight round TGA, minimap button
ns.ADDON_NAME = ADDON_NAME

-- Display order of the profession tabs.
ns.PROFESSIONS = { "Herbalism", "Mining", "Fishing", "Skinning" }

ns.professions = {}   -- key -> profession definition (filled by Data/*.lua)
ns.itemIndex = {}     -- itemID -> { prof = key, entry = entry }
ns.canonical = {}     -- alternate itemID -> main itemID (e.g. Dark Iron Ore 11099 -> 11370)

local QUESTION_ICON = "Interface\\Icons\\INV_Misc_QuestionMark"
ns.QUESTION_ICON = QUESTION_ICON

---------------------------------------------------------------------------
-- Secret values
---------------------------------------------------------------------------

-- Some clients (including Forever) can return a "secret" string from
-- UnitGUID, UnitName and similar APIs. Addon code must not compare,
-- concatenate, index a table with, or run string operations on those
-- values. Feature-detect so older clients still work.
function ns.IsSecretValue(v)
    if v == nil then return false end
    if issecretvalue then
        local ok, secret = pcall(issecretvalue, v)
        if ok and secret then return true end
    end
    if canaccessvalue then
        local ok, access = pcall(canaccessvalue, v)
        if ok and access == false then return true end
    end
    -- Fallback: a comparison throws on a secret value.
    local ok = pcall(function()
        if type(v) == "string" then return v ~= "" end
        return v == v
    end)
    return not ok
end

-- A usable non-empty string, or nil if the value is missing, empty, or secret.
function ns.ReadableString(v)
    if type(v) ~= "string" then return nil end
    if ns.IsSecretValue(v) then return nil end
    if v == "" then return nil end
    return v
end

-- Safe for debug or chat output. Never throws on a secret value.
function ns.SafeToString(v, fallback)
    if v == nil then return fallback or "nil" end
    if ns.IsSecretValue(v) then return "unknown" end
    local ok, s = pcall(tostring, v)
    if ok and type(s) == "string" then return s end
    return fallback or "unknown"
end


---------------------------------------------------------------------------
-- Saved variables
---------------------------------------------------------------------------

local DEFAULTS = {
    version = 1,
    counts = {},        -- [itemID] = { [zoneName] = itemsLooted }
    gathers = {},       -- [profKey] = { [zoneName] = nodesOrCatches }
    discovered = {},    -- [profKey] = { [itemID] = { name, icon, quality, first, zone } }
    zoneMaps = {},      -- [zoneName] = uiMapID (last seen)
    firsts = {},        -- [itemID] = time() of the first gather
    minimap = { hide = false, minimapPos = 210, lock = false },
    window = {},        -- point, relativePoint, x, y
    options = {
        showUndiscovered = true,   -- show Forever placeholder entries until found
        onlyGatheredZones = false, -- hide default zones with a count of 0
        announce = true,           -- print new discoveries to chat
        debug = false,             -- log unknown gathering spell IDs to chat
        routeFlow = true,          -- pulse travels along the route line
        windowUnlocked = false,    -- main window is locked in place unless unlocked in options
    },
    debugSpells = {},   -- [spellID] = spell name, gathering casts we didn't know
    trainers = { prof = "All" },  -- faction nil: use the player's faction
    arrow = {},                    -- point, rel, x, y of the movable route arrow
    skinMobs = { yes = {}, no = {} }, -- [npcID] = true: skinned (yes), not a beast (no)
}

local function CopyDefaults(src, dst)
    for k, v in pairs(src) do
        if type(v) == "table" then
            if type(dst[k]) ~= "table" then dst[k] = {} end
            CopyDefaults(v, dst[k])
        elseif dst[k] == nil then
            dst[k] = v
        end
    end
    return dst
end

function ns:InitDB()
    if type(GatherpediaDB) ~= "table" then GatherpediaDB = {} end
    self.db = CopyDefaults(DEFAULTS, GatherpediaDB)
    if self.Session then
        if type(self.db.session) ~= "table" then self.db.session = {} end
        CopyDefaults(self.Session.DEFAULTS, self.db.session)
    end
    if self.Sparkles then
        if type(self.db.sparkle) ~= "table" then self.db.sparkle = {} end
        if self.Sparkles.MigrateOpts then self.Sparkles:MigrateOpts(self.db.sparkle) end
        CopyDefaults(self.Sparkles.DEFAULTS, self.db.sparkle)
    end
    for _, key in ipairs(self.PROFESSIONS) do
        self.db.gathers[key] = self.db.gathers[key] or {}
        self.db.discovered[key] = self.db.discovered[key] or {}
    end

    -- Per-character settings (GatherpediaCharDB).
    if type(GatherpediaCharDB) ~= "table" then GatherpediaCharDB = {} end
    self.charDB = CopyDefaults({
        showAllProfessions = false, -- show professions this character doesn't have
        learnedOrder = {},          -- gathering professions in the order first seen
        arrowScale = 1,             -- 0.50-2.00 in 0.05 steps; route-arrow size
    }, GatherpediaCharDB)
end

function ns:ResetCounts()
    wipe(self.db.counts)
    wipe(self.db.zoneMaps)
    wipe(self.db.firsts)
    for _, key in ipairs(self.PROFESSIONS) do
        wipe(self.db.gathers[key])
        wipe(self.db.discovered[key])
    end
    self:Print("All gathering counts and discoveries have been reset.")
    if self.UI then self.UI:Refresh() end
end

---------------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------------

function ns:Print(msg)
    DEFAULT_CHAT_FRAME:AddMessage("|cff7fbf3fGatherpedia:|r " .. tostring(msg))
end

function ns.GetItemIcon(entry)
    if entry.icon then return entry.icon end
    if entry.id then
        local icon
        if C_Item and C_Item.GetItemIconByID then
            icon = C_Item.GetItemIconByID(entry.id)
        elseif GetItemIcon then
            icon = GetItemIcon(entry.id)
        end
        if icon then return icon end
    end
    return QUESTION_ICON
end

-- Item names come from the client cache. Until the server answers we show the
-- English name from our data table and ask for the item, then refresh.
local requested = {}
function ns.GetItemName(entry)
    if not entry.id then return entry.name end
    local name
    if C_Item and C_Item.GetItemNameByID then
        name = C_Item.GetItemNameByID(entry.id)
    elseif GetItemInfo then
        name = GetItemInfo(entry.id)
    end
    if name then return name end
    if not requested[entry.id] and Item and Item.CreateFromItemID then
        requested[entry.id] = true
        pcall(function()
            local item = Item:CreateFromItemID(entry.id)
            if item and not item:IsItemEmpty() then
                item:ContinueOnItemLoad(function()
                    if ns.UI then ns.UI:RequestRefresh() end
                end)
            end
        end)
    end
    return entry.name or ("Item " .. entry.id)
end

function ns.GetItemLink(entry)
    if not entry.id then return nil end
    if C_Item and C_Item.GetItemInfo then
        local _, link = C_Item.GetItemInfo(entry.id)
        if link then return link end
    elseif GetItemInfo then
        local _, link = GetItemInfo(entry.id)
        if link then return link end
    end
    return nil
end

-- Returns the zone name and uiMapID the player is in. Micro maps (caves,
-- building interiors) are rolled up into their parent zone; dungeons stay as-is.
function ns.GetCurrentZone()
    local mapID = C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
    if not mapID then
        return GetRealZoneText() or UNKNOWN, nil
    end
    local microType = (Enum and Enum.UIMapType and Enum.UIMapType.Micro) or 5
    local info = C_Map.GetMapInfo(mapID)
    local guard = 0
    while info and info.mapType == microType and info.parentMapID and info.parentMapID ~= 0 and guard < 5 do
        local parent = C_Map.GetMapInfo(info.parentMapID)
        if not parent then break end
        info = parent
        guard = guard + 1
    end
    if info and info.name and info.name ~= "" then
        return info.name, info.mapID
    end
    return GetRealZoneText() or UNKNOWN, mapID
end

-- Difficulty of an entry for a given profession skill rank, using the
-- familiar recipe colors. Returns a key into ns.DIFFICULTY.
ns.DIFFICULTY = {
    red     = { hex = "ff3030", label = "Too difficult" },
    orange  = { hex = "ff8040", label = "Guaranteed skill-up" },
    yellow  = { hex = "ffff00", label = "Likely skill-up" },
    green   = { hex = "40bf40", label = "Rare skill-up" },
    gray    = { hex = "808080", label = "No skill-ups" },
    ok      = { hex = "40bf40", label = "You can gather this" },
    nodata  = { hex = "e6d6a8", label = "Skill needed not known yet" },
    partial = { hex = "ffd040", label = "Some sources need more skill" },
    all     = { hex = "40bf40", label = "You have the skill for every source" },
    unknown = { hex = "e6d6a8", label = "Profession not learned" },
}
ns.TIER_KEYS = { "orange", "yellow", "green", "gray" }

-- Fishing catchability is a property of the ZONE, not of the fish.
-- ns.FishingEval picks the player's current zone when that zone is a
-- known source, otherwise the lowest-skill zone the fish is caught in.
function ns.FishingEval(entry)
    if not entry or not ns.Zones or not ns.Zones.FishSkill then
        return nil, nil, nil, "unknown"
    end
    local here = ns.GetCurrentZone and select(1, ns.GetCurrentZone())
    local function skill(zone)
        return ns.Zones:FishSkill(zone)
    end
    if here then
        for _, z in ipairs(entry.zones or {}) do
            if z == here then
                local castMin, noGet = skill(z)
                if castMin then return z, castMin, noGet, "current" end
                return z, nil, nil, "current-unknown"
            end
        end
    end
    local best, bc, bn
    for _, z in ipairs(entry.zones or {}) do
        local castMin, noGet = skill(z)
        if castMin then
            if not best
                or castMin < bc
                or (castMin == bc and noGet < bn)
                or (castMin == bc and noGet == bn and z < best)
            then
                best, bc, bn = z, castMin, noGet
            end
        end
    end
    if best then return best, bc, bn, "best" end
    return nil, nil, nil, "unknown"
end

function ns.FishingSkillText(entry)
    local zone, castMin, noGet = ns.FishingEval(entry)
    if not zone or not castMin then return nil end
    local text = zone .. "  \194\183  skill " .. tostring(castMin)
    if noGet and noGet ~= castMin then
        text = text .. " (no getaways at " .. tostring(noGet) .. ")"
    end
    return text
end

function ns.DifficultyLabel(entry, key)
    if entry and entry.prof == "Fishing" then
        if key == "partial" then return "Fish may get away" end
        if key == "all" then return "No getaways" end
    end
    local d = key and ns.DIFFICULTY[key]
    return d and d.label or ""
end

function ns.GetDifficulty(entry, rank)
    if not rank then return "unknown" end
    if entry and entry.prof == "Fishing" then
        local _, castMin, noGet, why = ns.FishingEval(entry)
        if not castMin then return "nodata" end
        if rank < castMin then return "red" end
        if noGet and rank < noGet then return "partial" end
        return "all"
    end
    if not entry.skill and entry.skillMin then    -- a range (Skinning by mob level)
        if rank < entry.skillMin then return "red" end
        if rank < (entry.skillMax or entry.skillMin) then return "partial" end
        return "all"
    end
    if not entry.skill then return "nodata" end  -- blank in the data: no guessing
    if rank < entry.skill then return "red" end
    local t = entry.tiers
    if not t then return "ok" end                -- required skill known, colors not
    if rank < t[2] then return "orange" end
    if rank < t[3] then return "yellow" end
    if rank < t[4] then return "green" end
    return "gray"
end

function ns.Colorize(hex, text)
    return "|cff" .. hex .. tostring(text) .. "|r"
end

-- Compact requirement for range entries: "Skill 270-280 · Mob level 54-56".
local function Range(a, b) return (not b or a == b) and tostring(a) or (a .. "-" .. b) end
function ns.SkillRangeText(entry)
    if entry and entry.prof == "Fishing" then
        return ns.FishingSkillText(entry)
    end
    if not entry or not entry.skillMin then return nil end
    local text = "Skill " .. Range(entry.skillMin, entry.skillMax)
    if entry.mobMin then
        text = text .. "  \194\183  Mob level " .. Range(entry.mobMin, entry.mobMax)
    end
    return text
end

-- "85  110  135  185" in orange, yellow, green and gray.
-- Each number is a complete |cffRRGGBB...|r; separators are spaces only
-- (never a lone |r, and never ||r).
function ns.FormatTiers(tiers)
    if not tiers then return "" end
    local parts = {}
    for i, key in ipairs(ns.TIER_KEYS) do
        if tiers[i] ~= nil then
            parts[#parts + 1] = ns.Colorize(ns.DIFFICULTY[key].hex, tiers[i])
        end
    end
    return table.concat(parts, "  ")
end

-- Profession detection ------------------------------------------------------
-- Skill line IDs for the modern professions API, English names for the older
-- skill list. Results are cached in ns.learned and refreshed on login and on
-- SKILL_LINES_CHANGED.

local SKILL_LINE_IDS = { Herbalism = 182, Mining = 186, Fishing = 356, Skinning = 393 }
local LINE_TO_PROF = {}

-- Prefer the game's own mapping (C_TradeSkillUI + Enum.Profession) and keep
-- the known IDs as a fallback.
local function BuildSkillLines()
    wipe(LINE_TO_PROF)
    for key, id in pairs(SKILL_LINE_IDS) do LINE_TO_PROF[id] = key end
    if C_TradeSkillUI and C_TradeSkillUI.GetProfessionSkillLineID and Enum and Enum.Profession then
        for key in pairs(SKILL_LINE_IDS) do
            local enumValue = Enum.Profession[key]
            if enumValue then
                local ok, line = pcall(C_TradeSkillUI.GetProfessionSkillLineID, enumValue)
                if ok and type(line) == "number" and line > 0 then LINE_TO_PROF[line] = key end
            end
        end
    end
end
local PRIMARY = { Herbalism = true, Mining = true, Skinning = true }

ns.learned = {}       -- [profKey] = { rank = n, max = n }
ns.learnedList = {}   -- profKeys this character has, in display order

local function ScanProfessions()
    BuildSkillLines()
    local found, order = {}, {}
    local function add(key, rank, max)
        if key and not found[key] then
            found[key] = { rank = rank or 0, max = max or 0 }
            order[#order + 1] = key
        end
    end
    -- Modern API: GetProfessions() returns prof1, prof2, archaeology, fishing, cooking.
    if GetProfessions and GetProfessionInfo then
        local slots = { GetProfessions() }
        for i = 1, 5 do
            if slots[i] then
                local _, _, rank, max, _, _, skillLine = GetProfessionInfo(slots[i])
                add(LINE_TO_PROF[skillLine], rank, max)
            end
        end
    end
    -- Guarded fallback: the older skill list, only if the modern API gave nothing.
    if #order == 0 and not GetProfessions and GetNumSkillLines and GetSkillLineInfo then
        local wanted = {}
        for key in pairs(SKILL_LINE_IDS) do wanted[key] = key end
        wanted["Herb Gathering"] = "Herbalism"
        for i = 1, GetNumSkillLines() do
            local name, isHeader, _, rank, _, _, max = GetSkillLineInfo(i)
            if not isHeader and name and wanted[name] then add(wanted[name], rank, max) end
        end
    end
    return found, order
end

function ns:DetectProfessions()
    local ok, found, order = pcall(ScanProfessions)
    if not ok then
        if self.debug then self:Print("Profession scan failed: " .. tostring(found)) end
        return
    end
    self.learned = found
    if self.Session then self.Session:OnSkills(found) end

    -- Remember the order each profession was first seen on this character.
    local seen = self.charDB.learnedOrder
    local inList = {}
    for _, key in ipairs(seen) do inList[key] = true end
    for _, key in ipairs(order) do
        if not inList[key] then seen[#seen + 1] = key; inList[key] = true end
    end

    -- Primary gathering professions first (learned order), Fishing after them.
    wipe(self.learnedList)
    for _, key in ipairs(seen) do
        if found[key] and PRIMARY[key] then self.learnedList[#self.learnedList + 1] = key end
    end
    if found.Fishing then self.learnedList[#self.learnedList + 1] = "Fishing" end

    if self.UI then self.UI:OnProfessionsChanged() end
end

function ns.GetPlayerSkill(prof)
    local p = ns.learned[prof]
    return p and p.rank or nil
end

-- Tabs to show: learned professions first, then (if the per-character
-- "Show all professions" option is on) the rest in the default order.
function ns:GetVisibleProfessions()
    local list, used = {}, {}
    for _, key in ipairs(self.learnedList) do
        list[#list + 1] = key; used[key] = true
    end
    if self.charDB and self.charDB.showAllProfessions then
        for _, key in ipairs(self.PROFESSIONS) do
            if not used[key] then list[#list + 1] = key end
        end
    end
    return list
end

---------------------------------------------------------------------------
-- Profession registry (called by Data/*.lua)
---------------------------------------------------------------------------

function ns:RegisterProfession(def)
    for order, entry in ipairs(def.items) do
        entry.prof = def.key
        entry.order = order
    end
    self.professions[def.key] = def
end

function ns:BuildIndex()
    wipe(self.itemIndex)
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

-- Bonus drops (gems, stones, scarce extras, seeds, Swiftthistle and
-- similar) come from other nodes or beasts. They are listed, but they
-- are not nodes of their own and are left out of node counts.
local BONUS_CATEGORIES = {
    Scarce = true, Gem = true, Bonus = true, Seed = true, Stone = true,
}

function ns:IsBonusDrop(entry)
    if not entry then return false end
    if entry.bonus == true then return true end
    if entry.bonus == false then return false end
    return entry.category and BONUS_CATEGORIES[entry.category] or false
end

function ns:IsNodeEntry(entry)
    if not entry or entry.placeholder then return false end
    return not self:IsBonusDrop(entry)
end

-- Union of parent-node zones for a bonus drop, then any zones listed on
-- the entry itself. Order follows the parent list, then the entry.
-- Upcoming parents are skipped unless the bonus item is also upcoming.
function ns:SourceZones(entry)
    if not entry then return {} end
    local out, seen = {}, {}
    local function add(z)
        if z and z ~= "" and not seen[z] then
            seen[z] = true
            out[#out + 1] = z
        end
    end
    if entry.parents then
        for _, id in ipairs(entry.parents) do
            local rec = self.itemIndex and self.itemIndex[id]
            local parent = rec and rec.entry
            if parent and parent.zones and (not parent.upcoming or entry.upcoming) then
                for _, z in ipairs(parent.zones) do add(z) end
            end
        end
    end
    if entry.zones then
        for _, z in ipairs(entry.zones) do add(z) end
    end
    return out
end

-- A shallow view of an entry whose .zones is the source-node union, for
-- Known-zones rows. Other fields still come from the original entry.
function ns:EntryWithSourceZones(entry)
    if not entry then return entry end
    local zones = self:SourceZones(entry)
    if not entry.parents and (not entry.zones or #entry.zones == #zones) then
        return entry
    end
    local view = {}
    for k, v in pairs(entry) do view[k] = v end
    view.zones = zones
    return view
end

-- The full list for one tab: built-in entries, then the player's own
-- discoveries, then Forever placeholders that have not been found yet.
function ns:GetEntries(prof)
    local def = self.professions[prof]
    local list = {}
    if not def then return list end
    for _, entry in ipairs(def.items) do
        -- Upcoming (Hyjal) items can be hidden until gathered via options.
        if not entry.upcoming or self.db.options.showUndiscovered or self:GetTotalCount(entry.id) > 0 then
            list[#list + 1] = entry
        end
    end

    local found = {}
    local discovered = self.db.discovered[prof] or {}
    local ids = {}
    for id in pairs(discovered) do ids[#ids + 1] = id end
    table.sort(ids, function(a, b) return (discovered[a].first or 0) < (discovered[b].first or 0) end)
    for _, id in ipairs(ids) do
        local d = discovered[id]
        local entry = {
            id = id, name = d.name, icon = d.icon, prof = prof,
            category = "Discovered", discovered = true,
            found = "Discovered by you" .. (d.zone and (" in " .. d.zone) or "")
                .. ". Not in the built-in database yet.",
            zones = {},
        }
        list[#list + 1] = entry
        if d.name then found[d.name:lower()] = true end
    end

    if self.db.options.showUndiscovered and def.undiscovered then
        for _, p in ipairs(def.undiscovered) do
            if not found[p.name:lower()] then
                list[#list + 1] = {
                    name = p.name, prof = prof, placeholder = true, icon = def.icon,
                    category = "Undiscovered", found = p.found, zones = p.zones or {},
                }
            end
        end
    end
    return list
end

function ns:GetTotalCount(itemID)
    local t = itemID and self.db.counts[itemID]
    if not t then return 0 end
    local total = 0
    for _, n in pairs(t) do total = total + n end
    return total
end

---------------------------------------------------------------------------
-- Slash commands
---------------------------------------------------------------------------

local TAB_ALIASES = {
    herb = "Herbalism", herbs = "Herbalism", herbalism = "Herbalism",
    mine = "Mining", mining = "Mining", ore = "Mining", ores = "Mining",
    fish = "Fishing", fishing = "Fishing",
    skin = "Skinning", skinning = "Skinning", leather = "Skinning",
}

function ns:ToggleMinimapButton()
    local db = self.db.minimap
    db.hide = not db.hide
    if self.RefreshMinimapButton then self:RefreshMinimapButton() end
    self:Print(db.hide and "Minimap button hidden. Type /gp minimap to show it again."
        or "Minimap button shown.")
    if self.Options then self.Options:Refresh() end
end

-- Player's current zone name, or nil if it is not known yet.
function ns.PlayerZoneName()
    local zone
    if ns.GetCurrentZone then
        zone = ns.GetCurrentZone()
    end
    if (not zone or zone == "" or zone == UNKNOWN) and GetRealZoneText then
        zone = GetRealZoneText()
    end
    if not zone or zone == "" or zone == UNKNOWN then return nil end
    return zone
end

-- "Elwynn Forest herbs (1-70)" for the best route in the current zone, or nil.
function ns.RouteSuggestText(zone)
    zone = zone or ns.PlayerZoneName()
    if not zone or not ns.Guides or not ns.Guides.SuggestText then return nil end
    return ns.Guides:SuggestText(zone)
end

-- Minimap (and other) tooltip lines for the one-click route toggle.
function ns.AppendRouteTooltip(tooltip)
    if not tooltip or not tooltip.AddLine then return end
    if ns.Arrow and ns.Arrow.IsActive and ns.Arrow:IsActive() then
        local name = (ns.Arrow.active and ns.Arrow.active.label) or "route"
        tooltip:AddLine("Right-click to stop: " .. name, 0.8, 0.8, 0.8)
        return
    end
    local zone = ns.PlayerZoneName and ns.PlayerZoneName()
    local suggest = ns.RouteSuggestText and ns.RouteSuggestText(zone)
    if suggest then
        tooltip:AddLine("Will start: " .. suggest, 0.8, 0.8, 0.8)
    elseif zone then
        tooltip:AddLine("No route for " .. zone .. " yet", 0.8, 0.8, 0.8)
    else
        tooltip:AddLine("No route for this zone yet", 0.8, 0.8, 0.8)
    end
    tooltip:AddLine("|cffffffffRight-click|r to Start/Stop route", 0.8, 0.8, 0.8)
end

function ns.StartChosenRoute(spot, prof)
    if not spot then return "none" end
    if ns.charDB and prof then ns.charDB.lastRouteProf = prof end
    if ns.Arrow and ns.Arrow.Start then
        ns.Arrow:Start(spot, prof)
    end
    if ns.UI and ns.UI.UpdateRouteToggle then ns.UI:UpdateRouteToggle() end
    return "started"
end

-- One-click start/stop for the best recorded route in the player's
-- current zone (herb, mining, or skinning). If a route is already
-- running, it is stopped. Not listed in /gp help.
function ns.ToggleZoneRoute(opts)
    opts = opts or {}
    if ns.Arrow and ns.Arrow.IsActive and ns.Arrow:IsActive() then
        ns.Arrow:Stop()
        ns:Print("Route stopped.")
        if ns.UI and ns.UI.UpdateRouteToggle then ns.UI:UpdateRouteToggle() end
        return "stopped"
    end
    if opts.stopOnly then
        return "idle"
    end
    local zone = ns.PlayerZoneName and ns.PlayerZoneName()
    if not zone then
        ns:Print("No route for this zone yet")
        return "none"
    end
    local spot, prof
    if opts.spot then
        spot, prof = opts.spot, opts.prof
    elseif ns.Guides and ns.Guides.BestRouteForPlayer then
        spot, prof = ns.Guides:BestRouteForPlayer(zone)
    end
    if not spot then
        ns:Print("No route for " .. zone .. " yet")
        return "none"
    end
    return ns.StartChosenRoute(spot, prof)
end

-- Keybinding in Bindings.xml: "Gatherpedia: Start/Stop route".
BINDING_HEADER_GATHERPEDIA = "Gatherpedia"
BINDING_NAME_GATHERPEDIA_TOGGLE_ROUTE = "Gatherpedia: Start/Stop route"
function Gatherpedia_ToggleRoute()
    ns.ToggleZoneRoute()
end

local function PrintHelp()
    ns:Print("v" .. ns.VERSION .. " commands:")
    print("  /gp  - open or close the Gatherpedia window")
    print("  /gp show  - open the window")
    print("  /gp herbs | mining | fishing | skinning  - open a tab")
    print("  /gp trainers  - open the Trainers list")
    print("  /gp minimap  - show or hide the minimap button")
    print("  /gp options  - open the options window")
    print("  /gp reset  - clear all gathered counts and discoveries (asks first)")
    print("  /gp resetpos  - move the window back to the center of the screen")
    print("  /gp session  - show the This Session box (session float | reset | pause)")
    print("  /gp debug  - log unknown gathering spell IDs (for bug reports)")
    print("  /gp glimmer  - turn Glimmer on or off (also /gp sparkle; on|off|preview|options|reset|debug)")
    print("  /gp glimmer color herbs|ore|fish|quest|other <color>")
    print("  /gp glimmer height|count|thickness|width|bright|speed ...")
    print("  /gp glimmer herbs|ore|fish|quest|other on|off")
end

SLASH_GATHERPEDIA1 = "/gp"
SLASH_GATHERPEDIA2 = "/gatherpedia"
SlashCmdList.GATHERPEDIA = function(msg)
    local cmd = strtrim((msg or ""):lower())
    if cmd == "" then
        ns.UI:Toggle()
    elseif cmd == "show" then
        ns.UI:Show()
    elseif cmd == "hide" then
        ns.UI:Hide()
    elseif TAB_ALIASES[cmd] then
        ns.UI:Show(TAB_ALIASES[cmd])
    elseif cmd == "trainers" or cmd == "trainer" then
        ns.UI:ShowTrainers()
    elseif cmd == "minimap" then
        ns:ToggleMinimapButton()
    elseif cmd == "options" or cmd == "config" or cmd == "opt" then
        ns.Options:Toggle()
    elseif cmd == "reset" then
        StaticPopup_Show("GATHERPEDIA_RESET_COUNTS")
    elseif cmd == "resetpos" then
        ns.UI:ResetPosition()
    elseif cmd == "session" or cmd:match("^session ") then
        local arg = cmd:match("^session%s+(%S+)")
        local o = ns.db.session
        if arg == "reset" then
            ns.Session:Reset(); ns:Print("New session started.")
        elseif arg == "pause" then
            ns.Session:TogglePause(); ns:Print(ns.session.paused and "Session timer paused." or "Session timer running.")
        elseif arg == "float" then
            o.floating = not o.floating; o.hidden = false
            if o.floating then ns.SessionUI:EnsureFloating() end
        else
            o.hidden = false
            ns:Print("This Session box shown. Hover it, or right-click, for options.")
        end
        ns.SessionUI:UpdateAll()
    elseif cmd == "debug" then
        ns.db.options.debug = not ns.db.options.debug
        ns:Print("Debug logging " .. (ns.db.options.debug and "on. Unknown gathering spells will be printed." or "off."))
        if ns.Options then ns.Options:Refresh() end
    elseif cmd == "sparkle" or cmd:match("^sparkle ") or cmd == "glimmer" or cmd:match("^glimmer ") then
        local arg = cmd:match("^sparkle%s*(.*)$") or cmd:match("^glimmer%s*(.*)$") or ""
        if ns.Sparkles then ns.Sparkles:Slash(arg) else PrintHelp() end
    elseif cmd:match("^route%s+debug$") then
        -- Intentionally not listed in /gp help.
        if ns.RouteOverlay and ns.RouteOverlay.ShowDebugPanel then
            ns.RouteOverlay:ShowDebugPanel()
            ns:Print("The report is in a window you can copy from.")
        else
            PrintHelp()
        end
    elseif cmd:match("^route%s+stop$") then
        if ns.Arrow and ns.Arrow.IsActive and ns.Arrow:IsActive() then
            ns.ToggleZoneRoute()
        end
    elseif cmd == "route" then
        -- Opens the picker so the player can see which route will start.
        -- Not listed in /gp help.
        if ns.UI and ns.UI.OpenRoutePicker then
            ns.UI:OpenRoutePicker()
        end
    else
        PrintHelp()
    end
end

StaticPopupDialogs["GATHERPEDIA_RESET_COUNTS"] = {
    text = "Gatherpedia: clear ALL gathered counts and discoveries? This cannot be undone.",
    button1 = YES,
    button2 = NO,
    OnAccept = function() ns:ResetCounts() end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
}

---------------------------------------------------------------------------
-- Startup
---------------------------------------------------------------------------

local loader = CreateFrame("Frame")
local scanQueued = false
loader:RegisterEvent("ADDON_LOADED")
loader:SetScript("OnEvent", function(self, event, name)
    if event == "PLAYER_LOGIN" or event == "SKILL_LINES_CHANGED" then
        -- SKILL_LINES_CHANGED can fire in bursts; coalesce into one scan.
        if not scanQueued then
            scanQueued = true
            C_Timer.After(0.5, function()
                scanQueued = false
                ns:DetectProfessions()
            end)
        end
        return
    end
    if name ~= ADDON_NAME then return end
    self:UnregisterEvent("ADDON_LOADED")
    ns:InitDB()
    ns:BuildIndex()
    if ns.Tracker then ns.Tracker:Enable() end
    if ns.SetupMinimap then ns:SetupMinimap() end
    if ns.Options then ns.Options:Register() end
    if ns.SessionUI then ns.SessionUI:Init() end
    if ns.Sparkles then ns.Sparkles:OnLogin() end
    self:RegisterEvent("PLAYER_LOGIN")
    self:RegisterEvent("SKILL_LINES_CHANGED")
end)
