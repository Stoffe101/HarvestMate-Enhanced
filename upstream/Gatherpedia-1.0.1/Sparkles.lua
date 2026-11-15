-- Gatherpedia: Sparkles.lua
-- Soft-target sparkles on lootable or interactable objects.
-- Uses the game's soft-interact targeting and our own textures.
-- The cloud is drawn only on a live soft-target or a visible nameplate
-- used as an anchor, and hides when that anchor is gone. Original CVars
-- are restored when Glimmer is turned off.

local ADDON_NAME, ns = ...

local Sparkles = {}
ns.Sparkles = Sparkles

local UNIT = "softinteract"
local UNIT_TOKENS = { "softinteract", "softtarget" }
local TEX = "Interface\\AddOns\\Gatherpedia\\Media\\Sparkle"

-- The live soft-target token, when one exists. Forever may use either name.
local function U()
    return Sparkles._unit or UNIT
end

function Sparkles:ResolveUnit()
    local unit = self:ResolveInteract()
    return unit
end

local function PCall(fn, ...)
    if not fn then return nil end
    local ok, a, b = pcall(fn, ...)
    if not ok then return nil end
    return a, b
end

-- IsForbidden is the supported, non-tainting probe. Calling SetAlpha,
-- GetAlpha, GetRegions, Hide, or GetHeight on a forbidden nameplate is
-- what taints; pcall does not make those calls safe.
function Sparkles:FrameIsForbidden(f)
    if type(f) ~= "table" then return true end
    if f.IsForbidden then
        local ok, v = pcall(f.IsForbidden, f)
        if ok and v then return true end
    end
    return false
end

function Sparkles:GetPlateForUnit(unit)
    if not unit or not (C_NamePlate and C_NamePlate.GetNamePlateForUnit) then
        return nil
    end
    local plate = PCall(C_NamePlate.GetNamePlateForUnit, unit)
    if plate and self:FrameIsForbidden(plate) then return nil end
    return plate
end

function Sparkles:NameOf(unit, plate)
    if unit and UnitName then
        local name = ns.ReadableString(PCall(UnitName, unit))
        if name and name ~= "Unknown" then
            return name
        end
    end
    return self:ReadPlateName(plate)
end

function Sparkles:GuidOf(unit)
    if unit and UnitGUID then
        return ns.ReadableString(PCall(UnitGUID, unit))
    end
    return nil
end

function Sparkles:PlateToken(plate)
    if type(plate) ~= "table" then return nil end
    local tok = ns.ReadableString(plate.namePlateUnitToken)
    if tok then return tok end
    local uf = plate.UnitFrame
    if type(uf) == "table" then
        tok = ns.ReadableString(uf.unit)
        if tok then return tok end
    end
    if plate.GetName then
        local name = ns.ReadableString(PCall(plate.GetName, plate))
        if name then
            local i = name:match("^NamePlate(%d+)$")
            if i then return "nameplate" .. i end
        end
    end
    return nil
end

local function FontStringText(fs)
    if type(fs) == "table" and fs.GetText then
        return ns.ReadableString(PCall(fs.GetText, fs))
    end
    return nil
end

function Sparkles:ReadPlateName(plate)
    -- Name text on the Blizzard plate only. We do not search the UI for
    -- another addon's floating icon.
    if type(plate) ~= "table" then return nil end
    local uf = plate.UnitFrame
    local t = FontStringText(plate.name)
        or FontStringText(plate.Name)
        or FontStringText(plate.nameplateName)
    if type(uf) == "table" then
        t = t or FontStringText(uf.name) or FontStringText(uf.Name) or FontStringText(uf.nameplateName)
    end
    return t
end

function Sparkles:SoftInteractPlate()
    for i = 1, #UNIT_TOKENS do
        local tok = UNIT_TOKENS[i]
        local plate = self:GetPlateForUnit(tok)
        if plate then return plate, tok end
    end
    return nil
end

function Sparkles:EachVisiblePlate(fn)
    if C_NamePlate and C_NamePlate.GetNamePlates then
        local plates = PCall(C_NamePlate.GetNamePlates)
        if type(plates) == "table" then
            for i = 1, #plates do
                local p = plates[i]
                if p and not self:FrameIsForbidden(p) then
                    local shown = true
                    if p.IsShown then
                        local ok, v = pcall(p.IsShown, p)
                        shown = ok and v
                    end
                    if shown then fn(p) end
                end
            end
            return
        end
    end
    for i = 1, 40 do
        local p = _G["NamePlate" .. i]
        if type(p) == "table" then
            local shown = true
            if p.IsShown then
                local ok, v = pcall(p.IsShown, p)
                shown = ok and v
            end
            if shown and not self:FrameIsForbidden(p) then fn(p) end
        end
    end
end

function Sparkles:UnitIsDead(unit)
    if not unit then return false end
    if UnitIsDead and PCall(UnitIsDead, unit) then return true end
    if UnitIsDeadOrGhost and PCall(UnitIsDeadOrGhost, unit) then return true end
    return false
end

-- May we use this unit as a glimmer anchor? Gather nodes always qualify.
-- Living creatures and players do not. A dead unit does (loot or skin).
function Sparkles:AnchorAllowed(unit, name, guid)
    name = ns.ReadableString(name)
    guid = ns.ReadableString(guid)
    if guid and (guid:find("Player%-") or guid:find("Pet%-")) then
        return false
    end
    if unit and UnitIsPlayer and PCall(UnitIsPlayer, unit) then
        return false
    end
    local kind = self:Classify(name, guid, unit)
    if kind and self:CategoryOn(kind) then return true end
    if self:UnitIsDead(unit) then return true end
    return false
end

-- Resolve the current interact target. Forever can show an object
-- nameplate (and return it from GetNamePlateForUnit("softinteract"))
-- even when UnitExists("softinteract") is false.
-- Returns unit, name, guid, plate, source.
function Sparkles:ResolveInteract()
    self._softPlate = nil
    -- 1. A real soft-interact / soft-target unit.
    if UnitExists then
        for i = 1, #UNIT_TOKENS do
            local tok = UNIT_TOKENS[i]
            local exists = PCall(UnitExists, tok)
            if exists then
                self._unit = tok
                local plate = self:GetPlateForUnit(tok)
                if plate then self._softPlate = plate end
                self._source = "unit"
                return tok, self:NameOf(tok, plate), self:GuidOf(tok), plate, "unit"
            end
        end
    end
    -- 2. The soft-interact nameplate, even if the unit token does not
    -- "exist". Read name/GUID from the plate's own token, from the
    -- soft token, or from the plate's name FontString.
    local plate, softTok = self:SoftInteractPlate()
    if plate then
        self._softPlate = plate
        local tok = self:PlateToken(plate) or softTok
        self._unit = tok
        local name = self:NameOf(tok, plate) or self:NameOf(softTok, plate)
        local guid = self:GuidOf(tok) or self:GuidOf(softTok)
        self._source = "softplate"
        return tok, name, guid, plate, "softplate"
    end
    -- 3. The current target or mouseover, when that unit has a nameplate
    -- and is a gather node or a dead lootable/skinnable corpse. A living
    -- mob that is only targeted is left alone.
    local extras = { "target", "mouseover" }
    for i = 1, #extras do
        local tok = extras[i]
        if UnitExists and PCall(UnitExists, tok) then
            local tplate = self:GetPlateForUnit(tok)
            if tplate then
                local name = self:NameOf(tok, tplate)
                local guid = self:GuidOf(tok)
                if self:AnchorAllowed(tok, name, guid) then
                    self._unit = tok
                    self._softPlate = tplate
                    self._source = tok
                    return tok, name, guid, tplate, tok
                end
            end
        end
    end
    -- 4. Visible nameplates whose name or GUID looks like a gathering
    -- node. Never latch onto a random creature, player or leftover plate.
    local found
    self:EachVisiblePlate(function(p)
        if found then return end
        local tok = self:PlateToken(p)
        local name = self:NameOf(tok, p)
        local guid = self:GuidOf(tok)
        local kind = self:Classify(name, guid, tok)
        local isGO = guid and guid:find("GameObject%-")
        if kind == "herbs" or kind == "ore" or kind == "fish" or kind == "skin" or isGO then
            found = { tok, name, guid, p, "plate" }
        end
    end)
    if found then
        self._unit = found[1]
        self._softPlate = found[4]
        self._source = found[5]
        return found[1], found[2], found[3], found[4], found[5]
    end
    self._unit = nil
    self._source = nil
    return nil
end

-- Bright, slightly lifted colors: added over dark grass or stone they
-- keep their hue instead of turning muddy.
Sparkles.COLORS = {
    gold   = { 1.00, 0.82, 0.42 },
    white  = { 0.95, 0.97, 1.00 },
    blue   = { 0.45, 0.78, 1.00 },
    green  = { 0.52, 0.95, 0.48 },
    purple = { 0.80, 0.55, 1.00 },
    red    = { 1.00, 0.42, 0.36 },
}
Sparkles.COLOR_NAMES = { "gold", "white", "blue", "green", "purple", "red" }
-- Rise speed multipliers.
Sparkles.SPEEDS = { slow = 1.00, normal = 1.85, fast = 2.80 }
Sparkles.GREY = { 0.58, 0.58, 0.58 }

Sparkles.CATEGORIES = { "herbs", "ore", "fish", "skin", "quest", "other" }
Sparkles.COLOR_KEYS = {
    herbs = "colorHerbs", ore = "colorOre", fish = "colorFish", skin = "colorSkin",
    quest = "colorQuest", other = "colorOther",
}
Sparkles.DEFAULTS = {
    enabled = false,
    herbs = true,
    ore = true,
    fish = true,
    skin = true,
    quest = true,
    other = false,
    colorHerbs = "green",
    colorOre = "gold",
    colorFish = "blue",
    colorSkin = "red",
    colorQuest = "gold",
    colorOther = "white",
    -- 100% is the baseline; every slider can go higher.
    height = 100,
    count = 16,
    thickness = 130,   -- glint size
    width = 200,       -- column spread to the left and right
    bright = 125,
    dim = 80,
    speed = "normal",
    nodeIcon = true,
    lookVer = 3,
}

-- Most clouds we will draw at once. A short recent list can be a little longer.
Sparkles.MAX_CLOUDS = 4
local MAX_RECENT = 8

-- CVars we may change while sparkles are on. Saved and restored exactly.
-- Only names that actually exist on this client are touched.
local MANAGED = {
    "SoftTargetInteract",
    "SoftTargetNameplateInteract",
    "SoftTargetInteractOnlyInRange",
}
-- CVars no longer managed. If a saved original is still in the table,
-- restore it and stop managing it.
local RETIRED = {
    "SoftTargetInteractArc",
    "SoftTargetInteractRange",
    "SoftTargetEnemyArc",
    "SoftTargetFriendArc",
    "nameplateShowDead",
}

local function Opts()
    local db = ns.db
    if not db then return Sparkles.DEFAULTS end
    db.sparkle = db.sparkle or {}
    Sparkles:MigrateOpts(db.sparkle)
    return db.sparkle
end

function Sparkles:Opts() return Opts() end

-- Converts settings saved by earlier versions of the addon to the
-- current scale (lookVer 3) so the look on screen does not change.
function Sparkles:MigrateOpts(o)
    if type(o) ~= "table" then return o end
    if o.lookVer == 3 then return o end
    local fromOld = (o.lookVer == nil and o.size ~= nil)
    if o.height == nil then o.height = 100 end
    if fromOld and o.bright ~= nil then
        local b = tonumber(o.bright) or 200
        o.bright = math.floor(b / 2 + 0.5)
    end
    local function half(v, def)
        v = math.floor((tonumber(v) or def) / 2 + 0.5)
        if v < 50 then v = 50 end
        if v > 200 then v = 200 end
        return v
    end
    if o.lookVer ~= nil or o.height ~= 100 or o.bright ~= nil then
        o.height = half(o.height, 100)
        o.bright = half(o.bright, 100)
        if o.speed == "fast" then
            o.speed = "normal"
        else
            o.speed = "slow"
        end
    end
    o.lookVer = 3
    return o
end

local function Clamp(v, lo, hi)
    v = tonumber(v)
    if not v then return nil end
    if v < lo then return lo end
    if v > hi then return hi end
    return v
end

function Sparkles:ColorRGB(name)
    return unpack(self.COLORS[name] or self.COLORS.gold)
end

---------------------------------------------------------------------------
-- Herb, vein and fishing-pool names from our data plus well-known Classic
-- object names. Everything else the soft-target picks up is a quest object
-- or "other" (chests, lockboxes, levers and similar).
---------------------------------------------------------------------------

local EXTRA_ORE = {
    ["copper vein"] = "Copper Ore",
    ["tin vein"] = "Tin Ore",
    ["silver vein"] = "Silver Ore",
    ["iron deposit"] = "Iron Ore",
    ["gold vein"] = "Gold Ore",
    ["mithril deposit"] = "Mithril Ore",
    ["truesilver deposit"] = "Truesilver Ore",
    ["small thorium vein"] = "Thorium Ore",
    ["rich thorium vein"] = "Thorium Ore",
    ["thorium vein"] = "Thorium Ore",
    ["dark iron deposit"] = "Dark Iron Ore",
    ["heavy thorium vein"] = "Heavy Thorium Ore",
}

local EXTRA_FISH = {
    "floating wreckage", "floating debris", "waterlogged wreckage",
    "schooner wreckage", "bloodsail wreckage", "patch of elemental water",
    "oil spill", "stonescale eel swarm",
}

function Sparkles:BuildIndex()
    local idx = {}
    local function add(name, kind, entry)
        if name and name ~= "" then idx[name:lower()] = { kind = kind, entry = entry } end
    end
    local herbs = ns.professions and ns.professions.Herbalism
    if herbs then
        for _, e in ipairs(herbs.items or {}) do add(e.name, "herbs", e) end
    end
    local mining = ns.professions and ns.professions.Mining
    local oreByName = {}
    if mining then
        for _, e in ipairs(mining.items or {}) do
            add(e.name, "ore", e)
            oreByName[e.name] = e
        end
    end
    for node, item in pairs(EXTRA_ORE) do
        add(node, "ore", oreByName[item])
        add("ooze covered " .. node, "ore", oreByName[item])
    end
    local fishing = ns.professions and ns.professions.Fishing
    if fishing then
        for _, e in ipairs(fishing.items or {}) do
            add(e.name, "fish", e)
            add(e.name .. " school", "fish", e)
            add("school of " .. e.name, "fish", e)
            local raw = e.name:gsub("^Raw ", "")
            if raw ~= e.name then
                add(raw .. " school", "fish", e)
                add("school of " .. raw, "fish", e)
            end
        end
    end
    for _, n in ipairs(EXTRA_FISH) do add(n, "fish", nil) end
    self.index = idx
end

-- Readable tooltip text for a unit. Uses C_TooltipInfo only, or lines
-- already shown on GameTooltip. Never calls SetUnit or SetOwner, and
-- never creates a hidden GameTooltip scanner (that taints Blizzard's
-- tooltip pipeline and can compare secret strings).
function Sparkles:UnitTooltipText(unit)
    unit = ns.ReadableString(unit)
    if not unit then return nil end
    local now = (GetTime and GetTime()) or 0
    if self._tipCache and self._tipCache[unit] and now - self._tipCache[unit].t < 1.0 then
        return self._tipCache[unit].text
    end
    local parts = {}
    if C_TooltipInfo and C_TooltipInfo.GetUnit then
        local ok, data = pcall(C_TooltipInfo.GetUnit, unit)
        if ok and type(data) == "table" and type(data.lines) == "table" then
            for _, line in ipairs(data.lines) do
                if type(line) == "table" then
                    local left = ns.ReadableString(line.leftText)
                    local right = ns.ReadableString(line.rightText)
                    if left then parts[#parts + 1] = left end
                    if right then parts[#parts + 1] = right end
                end
            end
        end
    end
    local text = (#parts > 0) and table.concat(parts, "\n") or nil
    self._tipCache = self._tipCache or {}
    self._tipCache[unit] = { t = now, text = text }
    return text
end

-- Read the already-shown GameTooltip only. Never SetUnit / SetOwner.
function Sparkles:VisibleTooltipText()
    local tooltip = GameTooltip
    if type(tooltip) ~= "table" then return nil end
    if tooltip.IsShown then
        local ok, shown = pcall(tooltip.IsShown, tooltip)
        if not (ok and shown) then return nil end
    end
    local parts = {}
    local tipName = tooltip.GetName and ns.ReadableString(PCall(tooltip.GetName, tooltip))
    local n = 0
    if tooltip.NumLines then
        local ok, v = pcall(tooltip.NumLines, tooltip)
        if ok and type(v) == "number" then n = v end
    end
    if n < 1 then n = 4 end
    if tipName and _G then
        for i = 1, n do
            local fs = _G[tipName .. "TextLeft" .. i]
            local tx = fs and fs.GetText and ns.ReadableString(PCall(fs.GetText, fs))
            if tx then parts[#parts + 1] = tx end
        end
    end
    if #parts == 0 and tooltip.GetText then
        local tx = ns.ReadableString(PCall(tooltip.GetText, tooltip))
        if tx then parts[#parts + 1] = tx end
    end
    if #parts == 0 then return nil end
    return table.concat(parts, "\n")
end

function Sparkles:TooltipText(unit)
    if self._tooltipForTest then return self._tooltipForTest end
    unit = ns.ReadableString(unit) or U()
    return self:UnitTooltipText(unit) or self:VisibleTooltipText()
end

function Sparkles:IsQuestTarget(name, guid, unit)
    unit = ns.ReadableString(unit) or U()
    if unit and C_QuestLog and C_QuestLog.UnitIsRelatedToActiveQuest then
        local ok, v = pcall(C_QuestLog.UnitIsRelatedToActiveQuest, unit)
        if ok and v then return true end
    end
    -- The live soft-interact tooltip is only meaningful for that target.
    if unit and unit ~= U() then return false end
    local text = self:TooltipText(unit)
    if text and text:find("[Qq]uest") then return true end
    return false
end

function Sparkles:LockedInfo(unit)
    local text = self:TooltipText(unit)
    if not text then return false, nil end
    if not (text:find("[Ll]ocked") or text:find("[Ll]ockpicking")) then
        return false, nil
    end
    local need = tonumber(text:match("[Ll]ockpicking[^%d]*(%d+)"))
    return true, need
end

function Sparkles:LockpickingSkill()
    if not (GetNumSkillLines and GetSkillLineInfo) then return nil end
    local n = GetNumSkillLines() or 0
    for i = 1, n do
        local name, _, _, rank = GetSkillLineInfo(i)
        name = ns.ReadableString(name)
        if name == "Lockpicking" then return rank end
    end
    return nil
end

local SKINNABLE_TYPES = { beast = true, dragonkin = true }

-- Loot still on a corpse. A corpse cannot be skinned until it has been
-- looted, so a corpse with loot is a lootable, not a skin.
-- Returns hasLoot, canLoot, or nil when the client cannot tell.
function Sparkles:CorpseLoot(guid)
    guid = ns.ReadableString(guid)
    if not guid or not CanLootUnit then return nil end
    if not guid:find("Creature%-") and not guid:find("Vehicle%-") then return nil end
    local ok, hasLoot, canLoot = pcall(CanLootUnit, guid)
    if not ok then return nil end
    if ns.IsSecretValue and (ns.IsSecretValue(hasLoot) or ns.IsSecretValue(canLoot)) then return nil end
    return hasLoot and true or false, canLoot and true or false
end

-- What a dead creature should glimmer as: "skin" once it is looted and
-- can be skinned, "other" while it still has loot you can take, or nil.
function Sparkles:CorpseKind(name, guid, unit)
    local hasLoot, canLoot = self:CorpseLoot(guid)
    if hasLoot then
        return canLoot and "other" or nil
    end
    if self:IsSkinnable(name, guid, unit) then return "skin" end
    return nil
end

function Sparkles:IsSkinnable(name, guid, unit)
    -- No GameTooltip scanner and no SetUnit. A "Skinnable" line is used
    -- only when C_TooltipInfo (or the test hook) gives readable text.
    -- Otherwise: a dead Beast or Dragonkin, or a dead corpse the player
    -- is pointing at whose type we cannot read.
    name = ns.ReadableString(name)
    guid = ns.ReadableString(guid)
    unit = ns.ReadableString(unit)
    local dead = unit and self:UnitIsDead(unit) and true or false
    local key = guid or unit or name
    if key then key = key .. (dead and ":d" or ":a") end
    local now = (GetTime and GetTime()) or 0
    if not self._tooltipForTest and key and self._skinCache and self._skinCache[key] then
        local c = self._skinCache[key]
        if now - c.t < 1.0 then return c.v end
    end
    local function store(v)
        v = v and true or false
        if not self._tooltipForTest and key then
            self._skinCache = self._skinCache or {}
            self._skinCache[key] = { t = now, v = v }
        end
        return v
    end
    local ok, result = pcall(function()
        if guid and (guid:find("Player%-") or guid:find("Pet%-")) then
            return false
        end
        if unit and UnitIsPlayer and PCall(UnitIsPlayer, unit) then
            return false
        end
        -- Not skinnable while loot is still on it.
        if dead and self:CorpseLoot(guid) then
            return false
        end
        local text
        if self._tooltipForTest and (not unit or unit == U()) then
            text = self._tooltipForTest
        end
        if not text and unit then
            text = self:UnitTooltipText(unit)
        end
        if text and (text:find("[Ss]kinnable") or text:find("Requires%s+[Ss]kinning")) then
            return true
        end
        if not unit or not dead then
            return false
        end
        local ctype = UnitCreatureType and ns.ReadableString(PCall(UnitCreatureType, unit))
        if ctype then
            return SKINNABLE_TYPES[ctype:lower()] and true or false
        end
        -- Type missing or secret: still glimmer a corpse the player is
        -- targeting, mousing over, or soft-interacting with.
        local soft = U()
        return unit == "softinteract" or unit == "softtarget"
            or unit == "target" or unit == "mouseover"
            or (soft and unit == soft)
    end)
    if not ok then return store(false) end
    return store(result)
end

function Sparkles:ShowNodeIcon(kind)
    if Opts().nodeIcon == false then return false end
    return kind == "herbs" or kind == "ore" or kind == "fish" or kind == "skin"
end

function Sparkles:NodeIconTexture(kind, entry)
    if not self:ShowNodeIcon(kind) then return nil end
    if kind == "skin" then
        local def = ns.professions and ns.professions.Skinning
        if def and def.icon then return def.icon end
        return "Interface\\Icons\\INV_Misc_Pelt_Wolf_01"
    end
    if entry and ns.GetItemIcon then
        return ns.GetItemIcon(entry)
    end
    return nil
end

function Sparkles:DebugLines()
    local lines = {}
    local function add(s) lines[#lines + 1] = s end
    local unit, name, guid, plate, source = self:ResolveInteract()
    local kind, entry = nil, nil
    if unit or name or guid or plate then
        kind, entry = self:Classify(name, guid, unit)
        if not kind and source == "softplate" then kind = "other" end
    end
    local anchor, akind = self:AnchorFrame()
    local aname = "none"
    if anchor then
        if anchor.GetName then
            local n = ns.ReadableString(PCall(anchor.GetName, anchor))
            if n then aname = n end
        end
        if aname == "none" or aname == "" then aname = akind or "unnamed" end
    end
    local function CVarVal(cvar)
        if not GetCVar then return "n/a" end
        local v = PCall(GetCVar, cvar)
        if v == nil then return "n/a" end
        return tostring(v)
    end
    add("Glimmer debug:")
    add("  enabled: " .. tostring(Opts().enabled))
    add("  unit token: " .. ns.SafeToString(unit, "none") .. (source and (" (" .. source .. ")") or ""))
    add("  name: " .. ns.SafeToString(name, "nil"))
    add("  guid: " .. ns.SafeToString(guid, "nil"))
    add("  category: " .. tostring(kind or "nil") .. (entry and entry.name and (" (" .. entry.name .. ")") or ""))
    add("  in reach: " .. ((unit or plate) and tostring(self:InReach()) or "n/a"))
    add("  anchor: " .. (anchor and (tostring(akind or "?") .. " " .. tostring(aname)) or "none"))
    add("  node icon: " .. (kind and tostring(self:ShowNodeIcon(kind)) or "n/a"))
    do
        local scale, down = self._lastScale, self._lastDrop
        if anchor then
            local _, _, _, y, sc = self:CloudPoint(anchor, akind, kind, guid, unit)
            if type(sc) == "number" then scale = sc end
            if type(y) == "number" then down = math.abs(y) end
        end
        add("  scale: " .. (type(scale) == "number" and (("%.2f"):format(scale)) or "n/a")
            .. "  offset: " .. (type(down) == "number" and (("%.1f"):format(down)) or "n/a"))
    end
    local iconY = (ns.SparklesUI and ns.SparklesUI.ColumnTop and (ns.SparklesUI.ColumnTop() + (ns.SparklesUI.NODE_ICON_GAP or 18))) or 100
    add(("  drop offsets (at scale 1):"))
    add(("    herbs / ore / fish / game-object quest items: %d px (just under the plate)")
        :format(self.CLOUD_DROP_OBJECT_AT_1 or 8))
    add(("    corpses / unit plates: %d px (at the feet)"):format(self.CLOUD_DROP_AT_1 or 120))
    do
        local d1, style = self:DropAt1(kind, guid, unit)
        local sc = self._lastScale or 1
        add(("    this target: %d px (%s) x scale %.2f = %.1f px")
            :format(d1 or 0, style or "?", sc, (d1 or 0) * sc))
    end
    add(("  node icon: %d px above the cloud at scale 1, times the same distance scale"):format(iconY))
    add("  CVar SoftTargetInteract: " .. CVarVal("SoftTargetInteract"))
    add("  CVar SoftTargetNameplateInteract: " .. CVarVal("SoftTargetNameplateInteract"))
    add("  CVar SoftTargetInteractOnlyInRange: " .. CVarVal("SoftTargetInteractOnlyInRange"))
    add("  nameplates:")
    local listed = 0
    self:EachVisiblePlate(function(p)
        listed = listed + 1
        local tok = self:PlateToken(p) or "?"
        local pname = self:NameOf(tok, p) or "nil"
        local pguid = self:GuidOf(tok)
        local prefix = "nil"
        if pguid then
            prefix = pguid:match("^(%w+)") or pguid
        end
        local pnameplate = "?"
        if p.GetName then
            local n = ns.ReadableString(PCall(p.GetName, p))
            if n then pnameplate = n end
        end
        add("    " .. ns.SafeToString(pnameplate) .. " token=" .. ns.SafeToString(tok) .. " name=" .. ns.SafeToString(pname) .. " guid=" .. ns.SafeToString(prefix))
    end)
    if listed == 0 then
        add("    (none visible)")
    end
    if not unit and not plate then
        add("  note: no soft-interact unit and no object nameplate; this client may not expose game-object units for addons.")
    elseif source == "softplate" and not unit then
        add("  note: no soft-interact unit, but a soft-interact nameplate was found and used as the anchor.")
    elseif source == "softplate" then
        add("  note: UnitExists was false for softinteract; used the nameplate unit token instead.")
    elseif source == "plate" then
        add("  note: no soft-interact unit; used a visible nameplate whose name or GUID matched a gathering node.")
    elseif not anchor then
        add("  note: a unit is present but no nameplate or Blizzard soft-target frame was found, so the cloud cannot be placed on the node.")
    end
    return lines
end

function Sparkles:PrintDebug()
    local lines = self:DebugLines()
    for i, line in ipairs(lines) do
        if i == 1 then
            ns:Print(line)
        else
            print(line)
        end
    end
end

function Sparkles:Classify(name, guid, unit)
    if not self.index then self:BuildIndex() end
    name = ns.ReadableString(name)
    guid = ns.ReadableString(guid)
    unit = ns.ReadableString(unit)
    if name then
        local hit = self.index[name:lower()]
        if hit then return hit.kind, hit.entry end
    end
    if guid and (guid:find("Player%-") or guid:find("Pet%-")) then
        return nil
    end
    -- Corpses are units (creatures), not objects: a lootable until it is
    -- looted, then a skin if it can be skinned.
    if unit and self:UnitIsDead(unit) then
        local ck = self:CorpseKind(name, guid, unit)
        if ck then return ck, nil end
    elseif self:IsSkinnable(name, guid, unit) then
        return "skin", nil
    end
    if self:IsQuestTarget(name, guid, unit) then return "quest", nil end
    -- Vendors and other living NPCs stay unsparkled; unidentified
    -- objects are "other" (chests, levers, lockboxes and the like).
    if guid and guid:find("Creature%-") then return nil end
    -- Interactable but unknown: still glimmer as Other, unless that
    -- category is switched off.
    return "other", nil
end

function Sparkles:CategoryOn(kind)
    local o = Opts()
    if kind == "herbs" then return o.herbs ~= false end
    if kind == "ore" then return o.ore ~= false end
    if kind == "fish" then return o.fish ~= false end
    if kind == "quest" then return o.quest ~= false end
    if kind == "other" then return o.other ~= false end
    if kind == "skin" then return o.skin ~= false end
    -- Other lootable corpses follow the master switch only.
    if kind == "loot" then return true end
    return false
end

function Sparkles:SkillTooLow(kind, entry)
    if kind == "herbs" or kind == "ore" then
        if not entry then return false end
        local prof = (kind == "herbs" and "Herbalism") or "Mining"
        local need = entry.skill or (entry.tiers and entry.tiers[1]) or entry.skillMin
        if not need then return false end
        local have = ns.GetPlayerSkill(prof)
        if not have then return true end
        return have < need
    end
    local locked, need = self:LockedInfo()
    if not locked then return false end
    local have = self:LockpickingSkill()
    if not have then return true end
    if need then return have < need end
    return false
end

-- CheckInteractDistance is protected on Forever when the unit is a
-- soft-interact or nameplate token. pcall does not stop ADDON_ACTION_BLOCKED,
-- so Glimmer must never call it (or UnitInRange / InteractUnit).
-- Safe signal: a live soft-interact target counts as in range; a
-- proactively-found or targeted plate counts as out of range and is dimmed.
function Sparkles:InReachOf(unit, plate, source)
    if source == "recent" or source == "visible" or source == "plate"
        or source == "target" or source == "mouseover" then
        return false
    end
    if source == "unit" or source == "softplate" then
        return true
    end
    -- Current() / implicit path: only the live soft-interact is in reach.
    return (self._unit or self._softPlate) ~= nil and (source == nil)
end

function Sparkles:InReach()
    return self:InReachOf(self._unit, self._softPlate, self._source)
end

-- r, g, b, alpha, and a grey flag for the current look.
function Sparkles:Look(kind, entry, inReach)
    local o = Opts()
    local grey = self:SkillTooLow(kind, entry)
    local key = self.COLOR_KEYS[kind]
    local rgb
    if grey then
        rgb = self.GREY
    else
        rgb = self.COLORS[key and o[key]] or self.COLORS.gold
    end
    -- 100% brightness is full strength; above it the renderer adds size
    -- and core glow (see SparklesUI), since alpha cannot go past 1.
    local bright = (tonumber(o.bright) or 100) / 100
    local dim = (tonumber(o.dim) or 80) / 100
    local a = math.min(1, 0.92 * bright * 4)
    if not inReach then a = a * dim end
    if a < 0.05 then a = 0.05 end
    if a > 1 then a = 1 end
    return rgb[1], rgb[2], rgb[3], a, grey
end

---------------------------------------------------------------------------
-- CVars: save originals the first time we turn sparkles on, restore
-- exactly when they are turned off. Never change them in combat.
---------------------------------------------------------------------------

function Sparkles:SoftTargetAvailable()
    if not GetCVar or not SetCVar then return false end
    local ok, val = pcall(GetCVar, "SoftTargetInteract")
    return ok and val ~= nil
end

function Sparkles:InCombat()
    return InCombatLockdown and InCombatLockdown()
end

function Sparkles:ApplyCVars(enable)
    if self:InCombat() then
        self.pendingCVars = enable and "on" or "off"
        return false
    end
    self.pendingCVars = nil
    if not self:SoftTargetAvailable() then
        return false
    end
    local o = Opts()
    if enable then
        -- Save originals for any managed CVar we have not saved yet, so a
        -- mid-session upgrade still restores the player's values.
        if type(o.cvars) ~= "table" then o.cvars = {} end
        for _, name in ipairs(MANAGED) do
            if o.cvars[name] == nil then
                local ok, val = pcall(GetCVar, name)
                if ok and val ~= nil then o.cvars[name] = val end
            end
        end
        local function hasCV(name)
            local ok, val = pcall(GetCVar, name)
            return ok and val ~= nil
        end
        local function setCV(name, value)
            if not hasCV(name) then return end
            pcall(SetCVar, name, value)
            local got = PCall(GetCVar, name)
            if tostring(got) ~= tostring(value) then
                pcall(SetCVar, name, tonumber(value) or value)
            end
        end
        -- Restore saved originals for CVars that are no longer managed.
        for _, name in ipairs(RETIRED) do
            local saved = o.cvars[name]
            if saved ~= nil then
                pcall(SetCVar, name, saved)
                o.cvars[name] = nil
            end
        end
        setCV("SoftTargetInteract", "3")
        setCV("SoftTargetNameplateInteract", "1")
        setCV("SoftTargetInteractOnlyInRange", "0")
        return true
    end
    if type(o.cvars) == "table" then
        for name, val in pairs(o.cvars) do
            pcall(SetCVar, name, val)
        end
        o.cvars = nil
    end
    return true
end

function Sparkles:FlushPendingCVars()
    if not self.pendingCVars then return end
    if self:InCombat() then return end
    local want = self.pendingCVars
    self.pendingCVars = nil
    self:ApplyCVars(want == "on")
end

function Sparkles:SetEnabled(on, quiet)
    local o = Opts()
    on = on and true or false
    o.enabled = on
    if on then
        local ok = self:ApplyCVars(true)
        if not ok and not self:InCombat() and not self._warned and not quiet then
            self._warned = true
            if ns.Print then
                ns:Print("This client doesn't appear to support soft targeting, so Glimmer can't attach to nodes in the world. Preview still works.")
            end
        end
        self:Start()
    else
        self:ApplyCVars(false)
        self:Stop()
    end
    if ns.SparklesUI then ns.SparklesUI:Refresh() end
    return o.enabled
end

function Sparkles:Toggle()
    return self:SetEnabled(not Opts().enabled)
end

---------------------------------------------------------------------------
-- Live target
---------------------------------------------------------------------------

function Sparkles:Current()
    local unit, name, guid, plate, source = self:ResolveInteract()
    if not unit and not plate then return nil end
    if plate and self:FrameIsForbidden(plate) then
        plate = nil
        if not unit then return nil end
    end
    local kind, entry = self:Classify(name, guid, unit)
    -- A soft-interact plate with no readable name is still an
    -- interactable object: glimmer it as Other unless that category is off.
    if not kind and source == "softplate" then
        kind = "other"
    end
    if not kind and (source == "target" or source == "mouseover") and self:UnitIsDead(unit) then
        local hasLoot, canLoot = self:CorpseLoot(guid)
        if hasLoot == nil or canLoot then kind = "other" end
    end
    if not kind or not self:CategoryOn(kind) then return nil end
    return {
        name = name, guid = guid, kind = kind, entry = entry,
        inReach = self:InReachOf(unit, plate, source),
        unit = unit, plate = plate, source = source,
    }
end

---------------------------------------------------------------------------
-- Keep glimmer on recent targets after soft-interact moves on, as long
-- as that nameplate is still visible and still the same GUID. Drops
-- when the plate is gone. No world-pose or screen-delta projection.
---------------------------------------------------------------------------

function Sparkles:Remember(t)
    if not t then return end
    local guid = ns.ReadableString(t.guid)
    if not guid then return end
    if not t.plate or not self:PlateIsUsable(t.plate) then return end
    self._recent = self._recent or {}
    local rec = {
        guid = guid, unit = t.unit, name = ns.ReadableString(t.name), kind = t.kind,
        entry = t.entry, plate = t.plate, seen = (GetTime and GetTime()) or 0,
    }
    for i = 1, #self._recent do
        if self._recent[i].guid == guid then
            table.remove(self._recent, i)
            break
        end
    end
    table.insert(self._recent, 1, rec)
    while #self._recent > MAX_RECENT do
        self._recent[#self._recent] = nil
    end
end

function Sparkles:OnPlateRemoved(unit)
    if not unit then return end
    local guid = self:GuidOf(unit)
    -- The plate is gone, so this GUID can no longer be an anchor.
    if self._recent then
        for i = #self._recent, 1, -1 do
            local r = self._recent[i]
            if (guid and r.guid == guid) or r.unit == unit then
                table.remove(self._recent, i)
            end
        end
    end
    if self._qualCache then
        if guid then self._qualCache[guid] = nil end
        self._qualCache[unit] = nil
    end
    if self._skinCache then
        local function drop(id)
            if not id then return end
            self._skinCache[id] = nil
            self._skinCache[id .. ":d"] = nil
            self._skinCache[id .. ":a"] = nil
        end
        drop(guid)
        drop(unit)
    end
    if self._tipCache then
        self._tipCache[unit] = nil
    end
end

function Sparkles:PlateIsUsable(plate)
    if not plate or self:FrameIsForbidden(plate) then return false end
    if plate.IsShown then
        local ok, v = pcall(plate.IsShown, plate)
        if not (ok and v) then return false end
    end
    return true
end

function Sparkles:PlateStillMatches(rec)
    if not rec or not ns.ReadableString(rec.guid) then return nil end
    local plate = rec.plate
    if plate and not self:PlateIsUsable(plate) then plate = nil end
    local tok = (plate and self:PlateToken(plate)) or rec.unit
    if tok then
        local fromTok = self:GetPlateForUnit(tok)
        if fromTok and self:PlateIsUsable(fromTok) then plate = plate or fromTok end
        local guid = self:GuidOf(tok)
        if guid and guid == rec.guid and self:PlateIsUsable(plate) then
            return plate, tok, guid
        end
    end
    -- Search visible plates for the same GUID.
    local found, foundTok
    self:EachVisiblePlate(function(p)
        if found then return end
        local ptok = self:PlateToken(p)
        local guid = ptok and self:GuidOf(ptok)
        if guid and guid == rec.guid then
            found, foundTok = p, ptok
        end
    end)
    if found then return found, foundTok, rec.guid end
    return nil
end

-- Qualify a visible nameplate for a proactive cloud. Only cheap, safe
-- checks: a known gather name, a GameObject we already know, a dead
-- unit that is skinnable or quest-related. Never living mobs or players.
-- Does not call CheckInteractDistance or the default GameTooltip.
function Sparkles:QualifyPlate(plate)
    if type(plate) ~= "table" or self:FrameIsForbidden(plate) then return nil end
    local tok = self:PlateToken(plate)
    local name = self:NameOf(tok, plate)
    local guid = self:GuidOf(tok)
    local cacheKey = guid or tok
    local now = (GetTime and GetTime()) or 0
    if cacheKey and self._qualCache and self._qualCache[cacheKey] then
        local c = self._qualCache[cacheKey]
        if now - c.t < 1.0 then return c.target end
    end
    local function store(target)
        if cacheKey then
            self._qualCache = self._qualCache or {}
            self._qualCache[cacheKey] = { t = now, target = target }
        end
        return target
    end
    if guid and (guid:find("Player%-") or guid:find("Pet%-")) then
        return store(nil)
    end
    if tok and UnitIsPlayer and PCall(UnitIsPlayer, tok) then
        return store(nil)
    end
    -- Known gather node by name (herb, ore, fish).
    if name then
        if not self.index then self:BuildIndex() end
        local hit = self.index[name:lower()]
        if hit and self:CategoryOn(hit.kind) then
            return store({
                name = name, guid = guid, kind = hit.kind, entry = hit.entry,
                unit = tok, plate = plate, source = "visible",
                inReach = self:InReachOf(tok, plate, "visible"),
            })
        end
    end
    -- Dead lootable / skinnable / quest corpse. UnitIsDead is not protected.
    local dead = false
    if tok and UnitIsDead then
        dead = PCall(UnitIsDead, tok) and true or false
    end
    if not dead and tok and UnitIsDeadOrGhost then
        dead = PCall(UnitIsDeadOrGhost, tok) and true or false
    end
    if dead then
        local kind = self:CorpseKind(name, guid, tok)
        if not kind and tok and self:IsQuestTarget(name, guid, tok) and self:CategoryOn("quest") then
            kind = "quest"
        end
        -- A dead unit we just cannot prove is lootable or skinnable is
        -- left alone; the recent-GUID list still covers a corpse the
        -- player already soft-targeted.
        if kind and self:CategoryOn(kind) then
            return store({
                name = name, guid = guid, kind = kind, entry = nil,
                unit = tok, plate = plate, source = "visible",
                inReach = self:InReachOf(tok, plate, "visible"),
            })
        end
        return store(nil)
    end
    -- Living creatures stay unsparkled (name already checked for gather nodes).
    if guid and guid:find("Creature%-") then
        return store(nil)
    end
    -- Quest object, only via the unit API (no soft-interact tooltip).
    if tok and C_QuestLog and C_QuestLog.UnitIsRelatedToActiveQuest then
        local v = PCall(C_QuestLog.UnitIsRelatedToActiveQuest, tok)
        if v and self:CategoryOn("quest") then
            return store({
                name = name, guid = guid, kind = "quest", entry = nil,
                unit = tok, plate = plate, source = "visible",
                inReach = self:InReachOf(tok, plate, "visible"),
            })
        end
    end
    return store(nil)
end

function Sparkles:CollectTargets()
    local out, seen = {}, {}
    local maxN = self.MAX_CLOUDS or 4
    local function add(t)
        if not t or not t.kind or not self:CategoryOn(t.kind) then return end
        if t.plate and self:FrameIsForbidden(t.plate) then
            t.plate = nil
        end
        if not t.plate then return end
        local key = ns.ReadableString(t.guid) or ns.ReadableString(t.unit) or tostring(t.plate)
        if seen[key] then return end
        seen[key] = true
        out[#out + 1] = t
        if ns.ReadableString(t.guid) then self:Remember(t) end
    end
    -- 1. Live soft-interact (or the single-plate fallback Current() uses).
    local cur = self:Current()
    if cur then
        if not cur.plate then
            local anc = select(1, self:AnchorFrame())
            if anc and not self:FrameIsForbidden(anc) then cur.plate = anc end
        end
        add(cur)
    end
    -- 2. Recently glimmered GUIDs still on a matching visible plate.
    for i = 1, #(self._recent or {}) do
        if #out >= maxN then break end
        local rec = self._recent[i]
        local plate, tok, guid = self:PlateStillMatches(rec)
        if plate then
            add({
                guid = guid or rec.guid, unit = tok or rec.unit, name = rec.name,
                kind = rec.kind, entry = rec.entry, plate = plate, source = "recent",
                inReach = self:InReachOf(tok or rec.unit, plate, "recent"),
            })
        end
    end
    -- 3. Other visible qualifying plates (gather nodes, corpses, quest objects).
    self:EachVisiblePlate(function(p)
        if #out >= maxN then return end
        add(self:QualifyPlate(p))
    end)
    return out
end

function Sparkles:NameplateForSoft()
    if self._softPlate and not self:FrameIsForbidden(self._softPlate) then
        return self._softPlate
    end
    local plate = self:SoftInteractPlate()
    if plate then return plate end
    return self:GetPlateForUnit(self._unit or U())
end

function Sparkles:AnchorFrame()
    -- Only Blizzard frames. A floating herb icon from another addon is
    -- not an anchor, and we do not search the UI for one.
    local _, _, _, resolved = self:ResolveInteract()
    local plate = resolved or self:NameplateForSoft()
    if plate and not self:FrameIsForbidden(plate) then return plate, "nameplate" end
    local st = _G.SoftTargetFrame
    if type(st) == "table" and not self:FrameIsForbidden(st) and st.IsShown then
        local ok, shown = pcall(st.IsShown, st)
        if ok and shown then return st, "soft" end
    end
    return nil
end

-- The nameplate sits at the name / quest '?' , above the model. A
-- fixed pixel drop (or one based on the plate's layout height) does
-- not track the on-screen distance from that point to the feet: as
-- you walk in, the body grows on screen and a constant drop slides
-- up from the ground to the chest. The drop and the rise have to
-- follow the target's world-to-screen scale.
--
-- At scale 1 (a close, fully-scaled target) the drop is 120 px from
-- the unit-frame bottom to the cloud center: the plate-to-feet span is
-- about 130 px up close, and the cloud center sits ~10 px above the
-- feet so the stars can spawn at the base (yBase). Corpses and other
-- unit plates use the same drop. Herbs, ore, fishing pools, and game-object
-- quest items have a plate that already sits on the object, so they
-- use a tiny drop (just under the plate) instead.
Sparkles.CLOUD_DROP_AT_1 = 120
Sparkles.CLOUD_DROP_OBJECT_AT_1 = 44
Sparkles.CLOUD_DROP_OBJECT_MAX = 110
-- How far below the nameplate anchor the base of each kind of object sits,
-- in px at scale 1. The glints start at this point and rise from it.
Sparkles.CLOUD_DROP_BY_KIND = { herbs = 72, ore = 52, fish = 16, quest = 34, other = 30 }
Sparkles.CLOUD_SCALE_LERP = 0.15

local function SafeCall(frame, method)
    if type(frame) ~= "table" or type(frame[method]) ~= "function" then return nil end
    if Sparkles:FrameIsForbidden(frame) then return nil end
    local ok, v = pcall(frame[method], frame)
    if ok and type(v) == "number" then return v end
    return nil
end

function Sparkles:EffectiveScale(frame)
    local s = SafeCall(frame, "GetEffectiveScale")
    if s and s > 0 then return s end
    s = SafeCall(frame, "GetScale")
    if s and s > 0 then return s end
    return nil
end

function Sparkles:ScreenBottom(frame)
    local b = SafeCall(frame, "GetBottom")
    if not b then return nil end
    return b * (self:EffectiveScale(frame) or 1)
end

function Sparkles:ScreenHeight(frame)
    local h = SafeCall(frame, "GetHeight")
    if not h or h <= 0 then return nil end
    return h * (self:EffectiveScale(frame) or 1)
end

local function CVarNumber(name)
    if not GetCVar then return nil end
    local v = PCall(GetCVar, name)
    v = tonumber(v)
    if v and v > 0 then return v end
    return nil
end

-- World-to-screen scale of this target, 1.0 when close.
-- Prefers a real measured gap when the nameplate root sits lower than
-- its UnitFrame by a body-sized amount (the root is at the unit, the
-- UnitFrame at the name) -- that gap already includes camera pitch.
-- Otherwise uses the plate's GetEffectiveScale, un-lerped through the
-- nameplate min/max scale CVars when those actually change with
-- range, so a compressed 0.8-1.0 CVar range still maps to 1/distance.
function Sparkles:PlateWorldScale(anchor, unitFrame)
    local ref = self:EffectiveScale(WorldFrame) or self:EffectiveScale(UIParent) or 1

    if anchor and unitFrame and anchor ~= unitFrame then
        local aBot = self:ScreenBottom(anchor)
        local uBot = self:ScreenBottom(unitFrame)
        if aBot and uBot then
            local gap = uBot - aBot
            local ufH = self:ScreenHeight(unitFrame) or 0
            if gap > math.max(48, ufH * 1.8) then
                local scale = gap / (self.CLOUD_DROP_AT_1 + 10)
                if scale < 0.25 then scale = 0.25 end
                if scale > 2.5 then scale = 2.5 end
                return scale, "gap"
            end
        end
    end

    local plate = unitFrame or anchor
    local eff = self:EffectiveScale(plate) or self:EffectiveScale(anchor)
    if not eff or eff <= 0 then return 1, "default" end
    local s = eff / (ref > 0 and ref or 1)

    local minS = CVarNumber("nameplateMinScale")
    local maxS = CVarNumber("nameplateMaxScale")
    local minD = CVarNumber("nameplateMinScaleDistance")
    local maxD = CVarNumber("nameplateMaxScaleDistance")
    if minS and maxS and minD and maxD and maxS > minS + 0.02 and minD > maxD + 1 then
        local t = (maxS - s) / (maxS - minS)
        if t < 0 then t = 0 elseif t > 1 then t = 1 end
        local dist = maxD + t * (minD - maxD)
        if dist < 3 then dist = 3 end
        return maxD / dist, "cvar"
    end

    local norm = (maxS and maxS > 0) and maxS or 1
    local scale = s / norm
    if scale < 0.2 then scale = 0.2 end
    if scale > 2.5 then scale = 2.5 end
    return scale, "plate"
end

-- True for a corpse or other unit whose plate sits up at the name,
-- so the cloud has to drop to the feet. Game objects (herbs, ore,
-- pools, crates, chests) return false.
function Sparkles:IsBodyKind(kind, guid, unit)
    guid = ns.ReadableString(guid)
    if kind == "skin" or kind == "loot" then return true end
    if guid and guid:find("GameObject%-") then return false end
    if kind == "herbs" or kind == "ore" or kind == "fish" then return false end
    if guid and guid:find("Creature%-") then return true end
    if unit and self:UnitIsDead(unit) then return true end
    return false
end

function Sparkles:DropAt1(kind, guid, unit)
    if self:IsBodyKind(kind, guid, unit) then
        return self.CLOUD_DROP_AT_1, "feet"
    end
    if kind == "herbs" or kind == "ore" or kind == "fish"
        or kind == "quest" or kind == "other" then
        local byKind = self.CLOUD_DROP_BY_KIND and self.CLOUD_DROP_BY_KIND[kind]
        return byKind or self.CLOUD_DROP_OBJECT_AT_1, "object"
    end
    -- No category (legacy CloudPoint calls): keep the feet drop so
    -- existing unit-plate math stays the default.
    return self.CLOUD_DROP_AT_1, "feet"
end

-- anchorKind is "nameplate" / "soft". category is the gather kind.
function Sparkles:CloudPoint(anchor, anchorKind, category, guid, unit)
    if not anchor or self:FrameIsForbidden(anchor) then return nil end
    local frame = anchor
    if type(anchor.UnitFrame) == "table" and anchor.UnitFrame.GetHeight
        and not self:FrameIsForbidden(anchor.UnitFrame) then
        frame = anchor.UnitFrame
    end
    local scale, reason = self:PlateWorldScale(anchor, frame ~= anchor and frame or nil)
    local dropAt1, style = self:DropAt1(category, guid, unit)
    local down = dropAt1 * scale
    if style == "object" then
        -- The plate's own height is not the object's height, so it is no
        -- longer used as a cap; only a sane maximum applies.
        local cap = (self.CLOUD_DROP_OBJECT_MAX or 110) * scale
        if down > cap then down = cap end
        if down < 0 then down = 0 end
    else
        if down < 28 then down = 28 end
        if down > 260 then down = 260 end
        -- Never drop farther than a measured body height when we have one.
        if reason == "gap" then
            local aBot = self:ScreenBottom(anchor)
            local uBot = self:ScreenBottom(frame)
            if aBot and uBot then
                local gap = uBot - aBot
                if gap > 0 and down > gap then down = gap end
            end
        end
    end
    self._lastScale, self._lastDrop, self._lastDropReason = scale, down, reason
    self._lastDropStyle, self._lastDropAt1, self._lastDropCategory = style, dropAt1, category
    return frame, "BOTTOM", 0, -down, scale
end

---------------------------------------------------------------------------
-- Drop a recent GUID, or the whole recent list. Used when loot closes
-- or Glimmer is turned off.
---------------------------------------------------------------------------

function Sparkles:ForgetMemory(guid)
    if guid then
        guid = ns.ReadableString(guid)
        if not guid or not self._recent then return end
        for i = #self._recent, 1, -1 do
            if self._recent[i].guid == guid then
                table.remove(self._recent, i)
            end
        end
        return
    end
    self._recent = nil
end

---------------------------------------------------------------------------
-- Hide the soft-interact nameplate's name and health bar while it is used
-- as an anchor.
-- Only the plate for unit "softinteract" is touched; other units' plates
-- are left alone. Visuals are restored when that plate is reused.
---------------------------------------------------------------------------

local function ObjectType(frame)
    if type(frame) ~= "table" then return nil end
    if frame.GetObjectType then
        local ok, typ = pcall(frame.GetObjectType, frame)
        if ok then return typ end
    end
    return frame._kind
end

local function EachPlateVisual(frame, fn, depth)
    if not frame or (depth or 0) > 4 then return end
    if Sparkles:FrameIsForbidden(frame) then return end
    fn(frame)
    if frame.GetRegions then
        local ok, a, b, c, d, e, r1, r2, r3 = pcall(frame.GetRegions, frame)
        if ok then
            local regs = { a, b, c, d, e, r1, r2, r3 }
            for i = 1, #regs do
                if type(regs[i]) == "table" then fn(regs[i]) end
            end
        end
    end
    if frame.GetChildren then
        local ok, a, b, c, d, e, k1, k2, k3, k4, k5 = pcall(frame.GetChildren, frame)
        if ok then
            local kids = { a, b, c, d, e, k1, k2, k3, k4, k5 }
            for n = 1, #kids do
                if type(kids[n]) == "table" then EachPlateVisual(kids[n], fn, (depth or 0) + 1) end
            end
        end
    end
    -- Named widgets used by default and many custom nameplates.
    local keys = {
        "UnitFrame", "name", "Name", "nameplateName", "healthBar", "HealthBar",
        "healthbar", "Level", "level", "RaidTargetFrame", "raidTarget",
        "selectionHighlight", "aggroHighlight", "castBar", "CastBar",
        "ClassificationFrame", "WidgetContainer",
    }
    for n = 1, #keys do
        local child = frame[keys[n]]
        if type(child) == "table" and child ~= frame then
            EachPlateVisual(child, fn, (depth or 0) + 1)
        end
    end
end

local function IsVisual(f)
    local typ = ObjectType(f)
    return typ == "FontString" or typ == "Texture" or typ == "StatusBar"
        or typ == "Frame" or typ == "Button"
end

function Sparkles:RestorePlateVisuals()
    local rec = self._suppressed
    if not rec then return end
    self._suppressed = nil
    for i = 1, #rec.items do
        local it = rec.items[i]
        if it.frame and it.frame.SetAlpha and not Sparkles:FrameIsForbidden(it.frame) then
            it.frame:SetAlpha(it.alpha)
        end
    end
end

-- Hide name / bar / icon chrome on this plate without moving it.
-- Skips the root plate so its position (and any child we do not own) stays valid.
function Sparkles:SuppressPlateVisuals(plate)
    if not plate or self:FrameIsForbidden(plate) then
        self:RestorePlateVisuals()
        return
    end
    if self._suppressed and self._suppressed.plate == plate then
        return
    end
    self:RestorePlateVisuals()
    local items = {}
    local seen = {}
    EachPlateVisual(plate, function(f)
        if type(f) ~= "table" or f == plate or seen[f] then return end
        if self:FrameIsForbidden(f) then return end
        if not IsVisual(f) then return end
        seen[f] = true
        local alpha = 1
        if f.GetAlpha then
            local v = f:GetAlpha()
            if type(v) == "number" then alpha = v end
        end
        items[#items + 1] = { frame = f, alpha = alpha }
        if f.SetAlpha then f:SetAlpha(0) end
    end, 0)
    self._suppressed = { plate = plate, items = items }
end

-- If a nameplate we hid is later used for a real unit, put its visuals back.
function Sparkles:OnNamePlateUnit(unit)
    if not unit or unit == UNIT then
        -- softinteract appeared or changed; UpdateCloud handles suppress.
        return
    end
    if not self._suppressed then return end
    local plate
    plate = self:GetPlateForUnit(unit)
    if plate and plate == self._suppressed.plate then
        self:RestorePlateVisuals()
    end
end

function Sparkles:RefreshTarget()
    if ns.SparklesUI then pcall(ns.SparklesUI.UpdateCloud, ns.SparklesUI) end
end

function Sparkles:Start()
    self:BuildIndex()
    if not self.frame then
        local f = CreateFrame("Frame", "GatherpediaSparkleDriver")
        self.frame = f
        f:RegisterEvent("PLAYER_REGEN_ENABLED")
        f:RegisterEvent("PLAYER_LOGOUT")
        pcall(f.RegisterEvent, f, "PLAYER_SOFT_INTERACT_CHANGED")
        pcall(f.RegisterEvent, f, "NAME_PLATE_UNIT_ADDED")
        pcall(f.RegisterEvent, f, "NAME_PLATE_UNIT_REMOVED")
        pcall(f.RegisterEvent, f, "LOOT_CLOSED")
        pcall(f.RegisterEvent, f, "LOOT_OPENED")
        f:SetScript("OnEvent", function(_, event, unit)
            if event == "PLAYER_REGEN_ENABLED" then
                Sparkles:FlushPendingCVars()
            elseif event == "PLAYER_LOGOUT" then
                -- Leave originals stored if glimmer stays on; they are
                -- applied again on the next login.
                Sparkles:RestorePlateVisuals()
            elseif event == "LOOT_CLOSED" or event == "LOOT_OPENED" then
                -- The object was used or looted; drop the recent list.
                Sparkles:ForgetMemory()
                Sparkles:RefreshTarget()
            elseif event == "NAME_PLATE_UNIT_REMOVED" then
                Sparkles:OnPlateRemoved(unit)
                Sparkles:OnNamePlateUnit(unit)
                Sparkles:RefreshTarget()
            elseif event == "NAME_PLATE_UNIT_ADDED" then
                Sparkles:OnNamePlateUnit(unit)
                Sparkles:RefreshTarget()
            else
                Sparkles:RefreshTarget()
            end
        end)
        -- Poll in case PLAYER_SOFT_INTERACT_CHANGED is missing on this client.
        f._accum = 0
        f:SetScript("OnUpdate", function(_, elapsed)
            f._accum = (f._accum or 0) + (elapsed or 0.1)
            if f._accum < 0.15 then return end
            f._accum = 0
            if Opts().enabled then Sparkles:RefreshTarget() end
        end)
    end
    if ns.SparklesUI then ns.SparklesUI:EnsureCloud() end
    self:RefreshTarget()
end

function Sparkles:Stop()
    self:RestorePlateVisuals()
    self._recent = nil
    self._qualCache = nil
    self._skinCache = nil
    self._tipCache = nil
    self._scanTip = nil
    if ns.SparklesUI then ns.SparklesUI:HideCloud() end
end

function Sparkles:OnLogin()
    self:BuildIndex()
    if Opts().enabled then
        self:SetEnabled(true, true)
    end
end

---------------------------------------------------------------------------
-- Slash: /gp sparkle ...
---------------------------------------------------------------------------

local function PrintUsage()
    ns:Print("Glimmer commands (also /gp sparkle):")
    print("  /gp glimmer  - turn Glimmer on or off")
    print("  /gp glimmer on | off")
    print("  /gp glimmer preview")
    print("  /gp glimmer options")
    print("  /gp glimmer debug")
    print("  /gp glimmer color herbs | ore | fish | skin | quest | other <gold|white|blue|green|purple|red>")
    print("  /gp glimmer height <50-200>")
    print("  /gp glimmer thickness <50-200>")
    print("  /gp glimmer width <50-300>")
    print("  /gp glimmer count <3-32>")
    print("  /gp glimmer bright <50-200>")
    print("  /gp glimmer speed <slow|normal|fast>")
    print("  /gp glimmer herbs | ore | fish | quest | other on | off")
    print("  /gp glimmer reset")
end

function Sparkles:Slash(msg)
    msg = strtrim(msg or "")
    local o = Opts()
    if msg == "" then
        local on = self:Toggle()
        ns:Print(on and "Glimmer on." or "Glimmer off.")
        return
    end
    local cmd, rest = msg:match("^(%S+)%s*(.*)$")
    cmd = cmd and cmd:lower() or ""
    rest = rest or ""
    if cmd == "on" then
        self:SetEnabled(true); ns:Print("Glimmer on.")
    elseif cmd == "off" then
        self:SetEnabled(false); ns:Print("Glimmer off.")
    elseif cmd == "preview" then
        if ns.SparklesUI then ns.SparklesUI:Preview() end
    elseif cmd == "options" or cmd == "option" or cmd == "config" then
        if ns.UI and ns.UI.ShowGlimmer then ns.UI:ShowGlimmer()
        elseif ns.SparklesUI then ns.SparklesUI:Show() end
    elseif cmd == "debug" then
        if ns.SparklesUI and ns.SparklesUI.ShowDebugPanel then
            ns.SparklesUI:ShowDebugPanel()
            ns:Print("Glimmer debug is in a window you can copy from.")
        else
            self:PrintDebug()
        end
    elseif cmd == "reset" then
        local was, saved = o.enabled, o.cvars
        for k, v in pairs(self.DEFAULTS) do o[k] = v end
        o.enabled, o.cvars = was, saved
        self:RefreshTarget()
        if ns.SparklesUI then ns.SparklesUI:Refresh() end
        ns:Print("Glimmer settings reset to defaults.")
    elseif cmd == "height" or cmd == "size" then
        -- `size` is kept as an alias; it now sets Height (rise length).
        local v = Clamp(rest, 50, 200)
        if not v then PrintUsage(); return end
        o.height = v; self:RefreshTarget(); if ns.SparklesUI then ns.SparklesUI:Refresh() end
        ns:Print("Glimmer height " .. v .. "%.")
    elseif cmd == "thickness" or cmd == "thick" then
        local v = Clamp(rest, 50, 200)
        if not v then PrintUsage(); return end
        o.thickness = v; self:RefreshTarget(); if ns.SparklesUI then ns.SparklesUI:Refresh() end
        ns:Print("Glimmer thickness " .. v .. "%.")
    elseif cmd == "width" or cmd == "spread" then
        local v = Clamp(rest, 50, 300)
        if not v then PrintUsage(); return end
        o.width = v; self:RefreshTarget(); if ns.SparklesUI then ns.SparklesUI:Refresh() end
        ns:Print("Glimmer width " .. v .. "%.")
    elseif cmd == "count" then
        local v = Clamp(rest, 3, 32)
        if not v then PrintUsage(); return end
        o.count = v; self:RefreshTarget(); if ns.SparklesUI then ns.SparklesUI:Refresh() end
        ns:Print("Glimmer count " .. v .. ".")
    elseif cmd == "bright" or cmd == "brightness" then
        local v = Clamp(rest, 50, 200)
        if not v then PrintUsage(); return end
        o.bright = v; self:RefreshTarget(); if ns.SparklesUI then ns.SparklesUI:Refresh() end
        ns:Print("Glimmer brightness " .. v .. "%.")
    elseif cmd == "speed" then
        local s = rest:lower()
        if not self.SPEEDS[s] then PrintUsage(); return end
        o.speed = s; self:RefreshTarget(); if ns.SparklesUI then ns.SparklesUI:Refresh() end
        ns:Print("Glimmer speed " .. s .. ".")
    elseif cmd == "color" then
        local who, col = rest:match("^(%S+)%s+(%S+)$")
        who = who and who:lower() or ""
        col = col and col:lower() or ""
        if who == "herb" then who = "herbs" end
        if who == "skinning" or who == "beasts" then who = "skin" end
        local key = self.COLOR_KEYS[who]
        if not self.COLORS[col] or not key then
            PrintUsage(); return
        end
        o[key] = col
        self:RefreshTarget(); if ns.SparklesUI then ns.SparklesUI:Refresh() end
        ns:Print("Glimmer color for " .. who .. ": " .. col .. ".")
    elseif cmd == "herbs" or cmd == "ore" or cmd == "fish" or cmd == "skin" or cmd == "quest" or cmd == "other" then
        local arg = rest:lower()
        if arg ~= "on" and arg ~= "off" then PrintUsage(); return end
        o[cmd] = (arg == "on")
        self:RefreshTarget(); if ns.SparklesUI then ns.SparklesUI:Refresh() end
        ns:Print("Glimmer for " .. cmd .. " " .. arg .. ".")
    else
        PrintUsage()
    end
end

ns.CopySparkleDefaults = function(dst)
    for k, v in pairs(Sparkles.DEFAULTS) do
        if dst[k] == nil then dst[k] = v end
    end
    return dst
end
