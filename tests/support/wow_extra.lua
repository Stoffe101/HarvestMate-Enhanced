-- The rest of the fake client HarvestMate Enhanced needs on top of wow.lua:
-- the character, professions, items, loot, CVars, bindings, timers, popups,
-- tooltips and the money. Values tests change are plain globals (CHAR, PROFS,
-- ITEMS, CVARS, LOOT...). Nothing here touches the real game or the desktop.

-- A portable random generator: the same numbers on every OS (the CRT's rand
-- differs between Windows and Linux, which changed the solver tests).
do
    local state = 7
    function math.randomseed(s) state = (math.floor(s or 1) % 2147483646) + 1 end
    function math.random(a, b)
        state = (state * 16807) % 2147483647
        local r = (state - 1) / 2147483646
        if a and b then return a + math.floor(r * (b - a + 1)) end
        if a then return 1 + math.floor(r * a) end
        return r
    end
end

CHAR = { level = 36, faction = "Alliance", class = "HUNTER", name = "Tester" }
-- Professions: list of { line, rank, max } in GetProfessions order.
PROFS = { { line = 393, rank = 175, max = 225 }, { line = 186, rank = 150, max = 225 }, nil, { line = 356, rank = 100, max = 150 } }
function UnitLevel(unit) if unit == "player" then return CHAR.level end return UNIT_LEVELS and UNIT_LEVELS[unit] or 1 end
function UnitFactionGroup() return CHAR.faction, CHAR.faction end
function UnitClass() return "Hunter", CHAR.class end
function UnitName(unit) if unit == "player" then return CHAR.name end return UNIT_NAMES and UNIT_NAMES[unit] end
function UnitGUID(unit) return UNIT_GUIDS and UNIT_GUIDS[unit] end
function UnitIsDead() return false end
function UnitExists(unit) return unit == "player" end
function GetProfessions()
    local slots = {}
    for i = 1, 5 do slots[i] = PROFS[i] and i or nil end
    return slots[1], slots[2], slots[3], slots[4], slots[5]
end
function GetProfessionInfo(i)
    local p = PROFS[i]
    if not p then return nil end
    local names = { [182] = "Herbalism", [186] = "Mining", [393] = "Skinning", [356] = "Fishing" }
    return names[p.line], "icon", p.rank, p.max, 0, 0, p.line, p.bonus or 0
end
function IsPlayerSpell() return false end
function GetRealZoneText() return MAPS[PLAYER.map] and MAPS[PLAYER.map].name or "" end

-- Items: [id] = { name, quality, sell }
ITEMS = {}
function GetItemInfo(id)
    local it = ITEMS[id]
    if not it then return nil end
    return it.name, "item:" .. id, it.quality or 1, 1, 1, "Trade Goods", "Trade Goods", 20, "", 134400, it.sell or 0
end
C_Item = {
    GetItemInfo = GetItemInfo,
    GetItemIconByID = function() return 134400 end,
    RequestLoadItemDataByID = function() end,
}
function GetItemIcon() return 134400 end
ITEM_QUALITY_COLORS = setmetatable({}, { __index = function() return { hex = "|cffffffff" } end })

-- Time and timers: C_Timer.After runs when the test calls RunTimers().
local timers = {}
C_Timer = {
    After = function(delay, fn) timers[#timers + 1] = { at = FAKE_TIME + (delay or 0), fn = fn } end,
    NewTicker = function() return { Cancel = function() end } end,
    NewTimer = function(delay, fn) timers[#timers + 1] = { at = FAKE_TIME + delay, fn = fn } return { Cancel = function() end } end,
}
function RunTimers(advance)
    FAKE_TIME = FAKE_TIME + (advance or 0)
    local due = {}
    local rest = {}
    for _, t in ipairs(timers) do
        if t.at <= FAKE_TIME then due[#due + 1] = t else rest[#rest + 1] = t end
    end
    timers = rest
    for _, t in ipairs(due) do t.fn() end
    return #due
end
REAL_TIME = 1790000000
function time() return REAL_TIME end

-- CVars through C_CVar too
function SetCVar(k, v) CVARS[k] = tostring(v) return true end
C_CVar = { GetCVar = function(k) return CVARS[k] end, SetCVar = function(k, v) CVARS[k] = tostring(v) return true end }
CVARS.SoftTargetInteract = "0"
CVARS.SoftTargetNameplateInteract = "0"
CVARS.autoInteract = "0"
CVARS.autoLootDefault = "0"

-- Bindings
BINDINGS = { F = "INTERACTMOUSEOVER" }
OVERRIDES = {}
function GetBindingAction(key) return OVERRIDES[key] or BINDINGS[key] end
function GetBindingText(key) return key end
function SetOverrideBinding(owner, _, key, action)
    if IN_COMBAT then error("SetOverrideBinding in combat (protected)") end
    OVERRIDES[key] = action
    OVERRIDE_OWNER = owner
end
function ClearOverrideBindings(owner)
    if IN_COMBAT then error("ClearOverrideBindings in combat (protected)") end
    OVERRIDES = {}
end
function IsShiftKeyDown() return false end
function IsAltKeyDown() return false end
function IsControlKeyDown() return false end

-- Popups
StaticPopupDialogs = {}
POPUPS = {}
function StaticPopup_Show(which) POPUPS[#POPUPS + 1] = which return {} end
function StaticPopup_Hide() end

-- Money and loot
MONEY = 0
function GetMoney() return MONEY end
LOOT = {}  -- { { id = , qty = } }
LOOT_SOURCE = nil
function GetNumLootItems() return #LOOT end
function GetLootSlotLink(i) return LOOT[i] and ("|cffffffff|Hitem:" .. LOOT[i].id .. "::::|h[x]|h|r") end
function GetLootSlotInfo(i) return 134400, "x", LOOT[i] and LOOT[i].qty or 1 end
function GetLootSourceInfo() return LOOT_SOURCE end
function IsFishingLoot() return FISHING_LOOT == true end

-- Misc client bits the vendored modules touch
SOUNDKIT = setmetatable({}, { __index = function() return 1 end })
function PlaySound() end
function hooksecurefunc(t, name, fn)
    if type(t) == "string" then t, name, fn = _G, t, name end
    local old = t[name]
    t[name] = function(...) local a, b, c = old and old(...) fn(...) return a, b, c end
end
Enum = { UIMapType = { Cosmic = 0, World = 1, Continent = 2, Zone = 3, Dungeon = 4, Micro = 5, Orphan = 6 },
    LootSlotType = { Item = 1, Money = 2 } }
function CreateVector2D(x, y) return { x = x, y = y, GetXY = function(self) return self.x, self.y end } end
C_NamePlate = { GetNamePlateForUnit = function() return nil end, GetNamePlates = function() return {} end }
C_Spell = { GetSpellName = function() return nil end, GetSpellInfo = function() return nil end }
C_GamePad = nil
TooltipDataProcessor = { AddTooltipPostCall = function() end }
Enum.TooltipDataType = { Unit = 2, Item = 0, Object = 8 }
GameTooltip.AddLine = function() end
GameTooltip.AddDoubleLine = function() end
GameTooltip.SetOwner = function() end
GameTooltip.NumLines = function() return 0 end
ItemRefTooltip = NewObj("GameTooltip", "ItemRefTooltip")
WorldFrame = NewObj("Frame", "WorldFrame")
DEFAULT_CHAT_FRAME = { AddMessage = function(_, m) print(m) end }
function geterrorhandler() return function(e) ERRORS = ERRORS or {} ERRORS[#ERRORS + 1] = tostring(e) end end
function GetLocale() return "enUS" end
function GetNumGroupMembers() return 0 end
function IsInGroup() return false end
function IsInRaid() return false end
function GetMinimapShape() return "ROUND" end
function GetCursorInfo() return nil end
function GetContainerNumSlots() return 0 end
C_Container = { GetContainerNumSlots = function() return 16 end, GetContainerNumFreeSlots = function() return 10, 0 end,
    GetContainerItemInfo = function() return nil end }
NUM_BAG_SLOTS = 4
C_TradeSkillUI = nil
UnitPosition = function() return nil end
function GetSpellInfo() return nil end
function IsSpellKnown() return false end
function GetShapeshiftFormID() return nil end
function IsMounted() return false end
C_Minimap.GetNumTrackingTypes = function() return 0 end
C_Minimap.GetTrackingInfo = function() return nil end
function GetNumTrackingTypes() return 0 end
function GetTrackingInfo() return nil end
function strtrim(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end
function wipe(t) for k in pairs(t) do t[k] = nil end return t end
function tContains(t, v) for _, x in ipairs(t) do if x == v then return true end end return false end
function Mixin(t, ...) for i = 1, select("#", ...) do for k, v in pairs((select(i, ...))) do t[k] = v end end return t end
UNKNOWN = "Unknown"
ERR_CANT_SKIN = "That creature can't be skinned."
ColorPickerFrame = nil
GameFontNormal, GameFontHighlight, GameFontNormalSmall, GameFontDisableSmall = {}, {}, {}, {}
function UnitIsDeadOrGhost() return false end
function UnitAffectingCombat() return IN_COMBAT end
function IsResting() return false end
function UnitOnTaxi() return false end
function UnitIsAFK() return false end
function GetAddOnMetadata() return nil end
C_AddOns.IsAddOnLoaded = function(name) return LOADED_ADDONS and LOADED_ADDONS[name] or false end
C_AddOns.DisableAddOn = function(name) DISABLED_ADDONS = DISABLED_ADDONS or {} DISABLED_ADDONS[name] = true end
function UnitRace() return "Human", CHAR.race or "Human" end
function GetInventoryItemLink() return nil end
function GetSpellCooldown() return 0, 0 end
function IsInGuild() return false end
function UnitCanAttack() return false end
function UnitCastingInfo() return nil end
function UnitCreatureType(unit) return UNIT_TYPES and UNIT_TYPES[unit] end
function UnitIsPlayer() return false end
function UnitIsTapDenied() return false end
function UnitPlayerControlled() return false end
function UnitTokenFromGUID() return nil end
C_TooltipInfo = nil
