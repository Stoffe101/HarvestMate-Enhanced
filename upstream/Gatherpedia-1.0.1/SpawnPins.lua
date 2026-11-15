-- Gatherpedia: SpawnPins.lua
-- Map pins for every profession. "Show beasts" (Skinning) or "Nodes"
-- (Herbalism, Mining) or "Pools" (Fishing) opens the world map on the
-- zone and drops a small icon on every spawn point that suits the range.
-- The ring color is your skill-up chance at your current skill. Hover a
-- pin for the name, the skill it needs and its coordinates.
--
-- Spawn data: Data/SkinningMobs.lua and Data/NodeSpawns.lua (from
-- QuestieDB, GPL-3.0). Beasts were picked by name, so the game gets the
-- final say: target or mouse over one and Gatherpedia notes whether it is
-- really a beast. A beast you have skinned is always kept.

local ADDON_NAME, ns = ...

local SpawnPins = {}
ns.SpawnPins = SpawnPins

local PELT = "Interface\\Icons\\INV_Misc_Pelt_Wolf_01"
local PIN_PX = 14          -- screen size of a pin
local PIN_ELITE_PX = 17
local PIN_HOVER = 1.35

local PROF_ICON = {
    Herbalism = "Interface\\Icons\\Trade_Herbalism",
    Mining    = "Interface\\Icons\\Trade_Mining",
    Fishing   = "Interface\\Icons\\Trade_Fishing",
    Skinning  = PELT,
}
-- Legend nouns: singular, plural, what a point is.
local NOUN = {
    Skinning  = { "beast", "beasts", "spawns" },
    Herbalism = { "herb", "herbs", "nodes" },
    Mining    = { "ore", "ores", "nodes" },
    Fishing   = { "pool", "pools", "spots" },
}

local decoded = {}         -- [prof .. mapID] = { { id, item, name, lo, hi, req, elite, pts = {x, y, ...} } }
local index                -- [npcID] = true for every beast in the data
local active               -- { prof, mapID, zone, smin, smax, mobMin, mobMax, itemID }
local holder, legend
local pins = {}
local lastScale

local function TH() return ns.Theme end

---------------------------------------------------------------------------
-- Data
---------------------------------------------------------------------------

-- Skill needed to skin a beast of this level.
function SpawnPins.Required(level)
    level = tonumber(level) or 1
    if level <= 10 then return 1 end
    if level <= 20 then return (level - 10) * 10 end
    return level * 5
end
local Required = SpawnPins.Required

-- Skill-up color at `skill` for a beast needing `req`.
function SpawnPins.Difficulty(req, skill)
    if not skill then return "unknown" end
    if skill < req then return "red" end
    if skill < req + 25 then return "orange" end
    if skill < req + 50 then return "yellow" end
    if skill < req + 100 then return "green" end
    return "gray"
end
local Difficulty = SpawnPins.Difficulty

local function Points(s)
    local pts = {}
    s = s or ""
    for p = 1, #s - 3, 4 do
        local x = tonumber(s:sub(p, p + 1), 36)
        local y = tonumber(s:sub(p + 2, p + 3), 36)
        if x and y then
            pts[#pts + 1] = x / 10
            pts[#pts + 1] = y / 10
        end
    end
    return pts
end

local function RawFor(prof, mapID)
    if not mapID then return nil end
    if prof == "Skinning" then
        return ns.SkinningMobs and ns.SkinningMobs[mapID]
    end
    local t = ns.NodeSpawns and ns.NodeSpawns[prof]
    return t and t[mapID]
end

local function Decode(prof, mapID)
    local key = prof .. ":" .. tostring(mapID)
    if decoded[key] then return decoded[key] end
    local raw = RawFor(prof, mapID)
    if not raw then return nil end
    local out = {}
    for i = 1, #raw do
        local r = raw[i]
        if prof == "Skinning" then
            out[i] = { id = r[1], name = r[2], lo = r[3], hi = r[4], elite = r[5] == 1,
                req = Required(r[4]), reqLo = Required(r[3]), pts = Points(r[6]) }
        else
            local skill = (r[3] and r[3] > 0) and r[3] or nil
            out[i] = { name = r[1], item = (r[2] and r[2] > 0) and r[2] or nil,
                req = skill, reqLo = skill, pts = Points(r[4]) }
        end
    end
    decoded[key] = out
    return out
end

local function Index()
    if index then return index end
    index = {}
    for _, list in pairs(ns.SkinningMobs or {}) do
        for i = 1, #list do index[list[i][1]] = true end
    end
    return index
end

local function Learned()
    local db = ns.db
    if not db then return { yes = {}, no = {} } end
    if type(db.skinMobs) ~= "table" then db.skinMobs = {} end
    db.skinMobs.yes = db.skinMobs.yes or {}
    db.skinMobs.no = db.skinMobs.no or {}
    return db.skinMobs
end

-- Is there pin data for this map? prof defaults to Skinning.
function SpawnPins:Has(mapID, prof)
    return RawFor(prof or "Skinning", mapID) ~= nil
end

-- What sits on this map that suits a skill window, a mob level window or
-- one item.
--   opts.smin, opts.smax      skill range (a guide bracket)
--   opts.mobMin, opts.mobMax  level range (a Skinning item page)
--   opts.itemID               only nodes that give this item
function SpawnPins:Entries(prof, mapID, opts)
    local list = Decode(prof, mapID)
    if not list then return {} end
    opts = opts or {}
    local learned = Learned()
    local out = {}
    for _, b in ipairs(list) do
        local keep = not (b.id and learned.no[b.id]) or learned.yes[b.id]
        if keep and opts.smax and b.req then
            keep = b.reqLo <= opts.smax and b.req + 100 > (opts.smin or 1)
        end
        if keep and opts.itemID then
            keep = b.item == opts.itemID
        end
        if keep and opts.mobMax and b.lo then
            keep = b.hi >= (opts.mobMin or 1) and b.lo <= opts.mobMax
        end
        if keep then out[#out + 1] = b end
    end
    return out
end

function SpawnPins:Beasts(mapID, opts)
    return self:Entries("Skinning", mapID, opts)
end

---------------------------------------------------------------------------
-- Learning from the game
---------------------------------------------------------------------------

local NOT_BEAST = {
    Humanoid = true, Undead = true, Demon = true, Elemental = true, Mechanical = true,
    Critter = true, Giant = true, Totem = true, ["Not specified"] = true,
    ["Non-combat Pet"] = true, ["Gas Cloud"] = true, Aberration = true,
}

local function NpcIDFromGUID(guid)
    guid = ns.ReadableString and ns.ReadableString(guid) or guid
    if type(guid) ~= "string" then return nil end
    local kind, _, _, _, _, id = strsplit("-", guid)
    if kind ~= "Creature" and kind ~= "Vehicle" then return nil end
    return tonumber(id)
end
SpawnPins.NpcIDFromGUID = NpcIDFromGUID

function SpawnPins:CheckUnit(unit)
    if not (UnitExists and UnitExists(unit)) then return end
    if UnitIsPlayer and UnitIsPlayer(unit) then return end
    local id = NpcIDFromGUID(UnitGUID and UnitGUID(unit))
    if not id or not Index()[id] then return end
    local learned = Learned()
    if learned.yes[id] or learned.no[id] then return end
    local ctype = UnitCreatureType and UnitCreatureType(unit)
    if ns.IsSecretValue and ns.IsSecretValue(ctype) then return end
    if type(ctype) == "string" and NOT_BEAST[ctype] then
        learned.no[id] = true
        if active and active.prof == "Skinning" then self:Draw() end
    end
end

-- Called by the tracker after a skinning loot.
function SpawnPins:LearnSkinned(npcID)
    if not npcID then return end
    local learned = Learned()
    learned.yes[npcID] = true
    learned.no[npcID] = nil
end

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_TARGET_CHANGED")
events:RegisterEvent("UPDATE_MOUSEOVER_UNIT")
events:SetScript("OnEvent", function(_, event)
    if not ns.db then return end
    local unit = event == "PLAYER_TARGET_CHANGED" and "target" or "mouseover"
    pcall(SpawnPins.CheckUnit, SpawnPins, unit)
end)

---------------------------------------------------------------------------
-- Drawing
---------------------------------------------------------------------------

-- The visible map art. On 1.60.1 that is WorldMapDetailFrame or
-- WorldMapButton; ScrollContainer.Child can have a size without being
-- the map you see. Same surface the route overlay draws on.
local function Canvas()
    local RO = ns.RouteOverlay
    if RO and RO.MapSurface then
        local ok, frame = pcall(RO.MapSurface, RO)
        if ok and frame then return frame end
    end
    local f = WorldMapFrame
    if not f then return nil end
    if f.ScrollContainer then return f.ScrollContainer.Child or f.ScrollContainer end
    return f
end

-- Map units per screen pixel, so pins stay the same size on screen.
local function CanvasScale()
    local c = Canvas()
    local sc = WorldMapFrame and WorldMapFrame.ScrollContainer
    local cs
    if c and sc and c == sc.Child and sc.GetCanvasScale then
        cs = sc:GetCanvasScale()
    elseif c and c.GetEffectiveScale and UIParent and UIParent.GetEffectiveScale then
        local ui = UIParent:GetEffectiveScale()
        if ui and ui > 0 then cs = c:GetEffectiveScale() / ui end
    end
    if not cs or cs <= 0 then cs = 1 end
    return cs
end

local function DiffColor(key)
    local d = ns.DIFFICULTY and ns.DIFFICULTY[key]
    local hex = d and d.hex or "e2b65c"
    return tonumber(hex:sub(1, 2), 16) / 255, tonumber(hex:sub(3, 4), 16) / 255, tonumber(hex:sub(5, 6), 16) / 255
end

local function PinTooltip(p)
    local b = p.beast
    if not b or not GameTooltip then return end
    GameTooltip:SetOwner(p, "ANCHOR_RIGHT")
    GameTooltip:ClearLines()
    local prof = p.prof or "Skinning"
    GameTooltip:AddLine(b.name, 1, 0.82, 0)
    if b.lo then
        local lv = (b.lo == b.hi) and tostring(b.lo) or (b.lo .. "-" .. b.hi)
        GameTooltip:AddLine("Level " .. lv .. (b.elite and "  \194\183  Elite" or ""), 0.92, 0.90, 0.82)
    elseif prof ~= "Skinning" then
        GameTooltip:AddLine(prof == "Fishing" and "Fishing pool. Pools move between these spots."
            or "A node can appear here. Only some are up at a time.", 0.92, 0.90, 0.82, true)
    end
    if b.req then
        local need = (b.reqLo == b.req) and tostring(b.req) or (b.reqLo .. "-" .. b.req)
        local diff = p.diff
        local label = diff ~= "unknown" and ns.DIFFICULTY and ns.DIFFICULTY[diff] and ns.DIFFICULTY[diff].label
        local r, g, bl = DiffColor(diff)
        if label then
            GameTooltip:AddLine(prof .. " " .. need .. "  \194\183  " .. label, r, g, bl)
        else
            GameTooltip:AddLine(prof .. " " .. need, 0.80, 0.75, 0.62)
        end
    end
    if p.others and #p.others > 0 then
        GameTooltip:AddLine("Also spawns here: " .. table.concat(p.others, ", "), 0.80, 0.75, 0.62, true)
    end
    GameTooltip:AddLine(("%.1f, %.1f"):format(p.x, p.y), 0.58, 0.54, 0.46)
    GameTooltip:Show()
end

local function SizePin(p, scale)
    local px = (p.beast and p.beast.elite) and PIN_ELITE_PX or PIN_PX
    if p.hover then px = px * PIN_HOVER end
    local s = px / scale
    p:SetSize(s, s)
end

local function NewPin(parent)
    local p = CreateFrame("Button", nil, parent)
    p.ring = p:CreateTexture(nil, "BORDER")
    p.ring:SetAllPoints()
    p.ring:SetTexture(TH() and TH().DISC or "Interface\\COMMON\\Indicator-Gray")
    p.icon = p:CreateTexture(nil, "ARTWORK")
    p.icon:SetPoint("TOPLEFT", p, "TOPLEFT", 0, 0)
    p.icon:SetPoint("BOTTOMRIGHT", p, "BOTTOMRIGHT", 0, 0)
    p.icon:SetTexture(PELT)
    p.icon:SetTexCoord(0.10, 0.90, 0.10, 0.90)
    local mask = TH() and TH().CIRCLE_MASK
    if mask and p.CreateMaskTexture and p.icon.AddMaskTexture then
        local m = p:CreateMaskTexture()
        m:SetTexture(mask, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
        m:SetAllPoints(p.icon)
        p.icon:AddMaskTexture(m)
        p.mask = m
    end
    p:SetScript("OnEnter", function(self)
        self.hover = true
        SizePin(self, CanvasScale())
        self:SetFrameLevel((holder and holder:GetFrameLevel() or 1) + 20)
        PinTooltip(self)
    end)
    p:SetScript("OnLeave", function(self)
        self.hover = nil
        SizePin(self, CanvasScale())
        self:SetFrameLevel((holder and holder:GetFrameLevel() or 1) + 1)
        if GameTooltip then GameTooltip:Hide() end
    end)
    return p
end

-- Inset the icon so a colored rim of ~2 screen pixels shows around it.
local function InsetIcon(p, scale)
    local inset = 2 / scale
    p.icon:ClearAllPoints()
    p.icon:SetPoint("TOPLEFT", p, "TOPLEFT", inset, -inset)
    p.icon:SetPoint("BOTTOMRIGHT", p, "BOTTOMRIGHT", -inset, inset)
end

local function EnsureHolder()
    local canvas = Canvas()
    if not canvas then return nil end
    if not holder then
        holder = CreateFrame("Frame", nil, canvas)
        holder:SetAllPoints(canvas)
        holder:SetScript("OnUpdate", function(self, elapsed)
            self.t = (self.t or 0) + (elapsed or 0)
            if self.t < 0.1 then return end
            self.t = 0
            local sc = CanvasScale()
            if sc ~= lastScale then
                lastScale = sc
                for _, p in ipairs(pins) do
                    if p:IsShown() then SizePin(p, sc); InsetIcon(p, sc) end
                end
            end
        end)
        if WorldMapFrame and WorldMapFrame.HookScript then
            WorldMapFrame:HookScript("OnHide", function() SpawnPins:Clear() end)
        end
        if WorldMapFrame and WorldMapFrame.SetMapID and hooksecurefunc then
            hooksecurefunc(WorldMapFrame, "SetMapID", function() SpawnPins:Sync() end)
        end
    end
    if holder:GetParent() ~= canvas then holder:SetParent(canvas) end
    holder:ClearAllPoints()
    holder:SetAllPoints(canvas)
    holder:SetFrameStrata("HIGH")
    holder:SetFrameLevel((canvas:GetFrameLevel() or 1) + 110)
    holder:Show()
    return holder
end

---------------------------------------------------------------------------
-- Legend: a small card in the map's top-left corner
---------------------------------------------------------------------------

local function EnsureLegend()
    if legend then return legend end
    local parent = Canvas()
    if not parent then return nil end
    local T = TH()
    legend = CreateFrame("Frame", nil, parent)
    legend:SetSize(260, 52)
    -- Drag it anywhere on the map; the spot is saved.
    legend:SetMovable(true)
    legend:EnableMouse(true)
    legend:RegisterForDrag("LeftButton")
    legend:SetScript("OnDragStart", function(self) self:StartMoving() end)
    legend:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local p = self._surface
        local l, t, pl, pt = self:GetLeft(), self:GetTop(), p and p:GetLeft(), p and p:GetTop()
        if l and t and pl and pt and ns.db then
            ns.db.pinLegend = { x = l - pl, y = t - pt }
        end
        SpawnPins:PlaceLegend()
    end)
    legend:SetScript("OnEnter", function(self)
        if not GameTooltip then return end
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOMRIGHT")
        GameTooltip:AddLine("Drag to move", 1, 1, 1)
        GameTooltip:Show()
    end)
    legend:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
    legend:SetFrameStrata("HIGH")
    legend:SetFrameLevel((parent:GetFrameLevel() or 1) + 160)
    if T then T:Panel(legend, T.C.card, T.C.line, 6) end
    legend.title = legend:CreateFontString(nil, "OVERLAY", "GatherpediaFontHighlight")
    legend.title:SetPoint("TOPLEFT", 12, -9)
    legend.title:SetPoint("RIGHT", -64, 0)
    legend.title:SetJustifyH("LEFT")
    if legend.title.SetWordWrap then legend.title:SetWordWrap(false) end
    legend.sub = legend:CreateFontString(nil, "OVERLAY", "GatherpediaFontDisableSmall")
    legend.sub:SetPoint("TOPLEFT", legend.title, "BOTTOMLEFT", 0, -4)
    legend.sub:SetPoint("RIGHT", -64, 0)
    legend.sub:SetJustifyH("LEFT")
    if legend.sub.SetWordWrap then legend.sub:SetWordWrap(false) end
    local hide = CreateFrame("Button", nil, legend)
    hide:SetSize(48, 22)
    hide:SetPoint("RIGHT", -10, 0)
    hide.label = hide:CreateFontString(nil, "OVERLAY", "GatherpediaFontHighlightSmall")
    hide.label:SetPoint("CENTER")
    hide.label:SetText("Hide")
    if T then T:SkinButton(hide, "quiet") end
    hide:SetScript("OnClick", function() SpawnPins:Clear() end)
    legend.hide = hide
    legend:Hide()
    return legend
end

-- Default: right of the map's round corner buttons. A dragged spot is kept,
-- clamped so the card never leaves the map.
local LEGEND_X, LEGEND_Y = 64, -10
function SpawnPins:PlaceLegend()
    local l = legend
    local p = Canvas()
    if not l or not p then return end
    if l:GetParent() ~= p then l:SetParent(p) end
    l._surface = p
    local saved = ns.db and ns.db.pinLegend
    local x = saved and saved.x or LEGEND_X
    local y = saved and saved.y or LEGEND_Y
    local pw, ph = p:GetWidth() or 0, p:GetHeight() or 0
    local lw, lh = l:GetWidth() or 0, l:GetHeight() or 0
    if pw > 0 and ph > 0 then
        x = math.max(0, math.min(x, pw - lw))
        y = math.min(0, math.max(y, -(ph - lh)))
    end
    l:ClearAllPoints()
    l:SetPoint("TOPLEFT", p, "TOPLEFT", x, y)
    l:SetFrameStrata("HIGH")
    l:SetFrameLevel((p:GetFrameLevel() or 1) + 160)
end

local KEY = {
    { "orange", "Sure" }, { "yellow", "Likely" }, { "green", "Rare" }, { "gray", "None" }, { "red", "Too high" },
}

local function PaintKey(l, show)
    if not l.key then
        l.key = {}
        local prev
        for i, k in ipairs(KEY) do
            local dot = l:CreateTexture(nil, "OVERLAY")
            dot:SetSize(8, 8)
            dot:SetTexture(TH() and TH().DISC or "Interface\\COMMON\\Indicator-Gray")
            local r, g, b = DiffColor(k[1])
            dot:SetVertexColor(r, g, b, 1)
            if prev then
                dot:SetPoint("LEFT", prev, "RIGHT", 10, 0)
            else
                dot:SetPoint("TOPLEFT", l.sub, "BOTTOMLEFT", 0, -7)
            end
            local fs = l:CreateFontString(nil, "OVERLAY", "GatherpediaFontDisableSmall")
            fs:SetPoint("LEFT", dot, "RIGHT", 4, 0)
            fs:SetText(k[2])
            l.key[i] = { dot = dot, fs = fs }
            prev = fs
        end
    end
    local w = 0
    for _, k in ipairs(l.key) do
        k.dot:SetShown(show)
        k.fs:SetShown(show)
        w = w + 8 + 4 + (k.fs:GetStringWidth() or 30) + 10
    end
    return w
end

local function PaintLegend(nBeasts, nPins, skill)
    local l = EnsureLegend()
    if not l then return end
    local prof = active and active.prof or "Skinning"
    local noun = NOUN[prof] or NOUN.Skinning
    local zone = active and (active.zone or "") or ""
    l.title:SetText(prof .. "  \194\183  " .. zone)
    local sub
    if nBeasts == 0 then
        sub = "No " .. noun[2] .. " recorded here for this range."
    else
        sub = ("%d %s, %d %s"):format(nBeasts, nBeasts == 1 and noun[1] or noun[2], nPins, noun[3])
        if not skill and prof ~= "Fishing" then
            sub = sub .. "  \194\183  learn " .. prof .. " to see skill-up colors"
        end
    end
    if prof == "Fishing" then skill = nil end
    l.sub:SetText(sub)
    local showKey = skill ~= nil and nBeasts > 0
    local keyW = PaintKey(l, showKey)
    local w = math.max(l.title:GetStringWidth() or 0, l.sub:GetStringWidth() or 0)
    if showKey then w = math.max(w, keyW) end
    l:SetWidth(math.min(440, math.max(220, math.floor(w + 86))))
    l:SetHeight(showKey and 68 or 52)
    SpawnPins:PlaceLegend()
    l:Show()
end

---------------------------------------------------------------------------
-- Public
---------------------------------------------------------------------------

-- Show pins for a spot or zone.
--   info.prof               Skinning (default), Herbalism, Mining, Fishing
--   info.zone, info.mapID   where
--   info.itemID             only nodes for this item, optional
--   info.smin, info.smax    skill window (guide bracket), optional
--   info.mobMin, info.mobMax  mob level window (item page), optional
function SpawnPins:Show(info)
    if not info then return false end
    local mapID = info.mapID or (ns.Zones and ns.Zones:MapID(info.zone))
    local prof = info.prof or "Skinning"
    if not self:Has(mapID, prof) then return false end
    active = {
        prof = prof, mapID = mapID, zone = info.zone, smin = info.smin, smax = info.smax,
        mobMin = info.mobMin, mobMax = info.mobMax, itemID = info.itemID,
    }
    if ns.MapLink then
        ns.MapLink:ClearPin()
        ns.MapLink:Open(info.zone, mapID)
    end
    self:Sync()
    if C_Timer and C_Timer.After then C_Timer.After(0, function() SpawnPins:Sync() end) end
    return true
end

function SpawnPins:IsShowing(zone, prof)
    return active ~= nil and (zone == nil or active.zone == zone)
        and (prof == nil or active.prof == prof)
        and WorldMapFrame ~= nil and WorldMapFrame:IsShown() == true
end

function SpawnPins:Clear()
    local was = active ~= nil
    active = nil
    for _, p in ipairs(pins) do p:Hide() end
    if legend then legend:Hide() end
    -- Flip a "Hide beasts" button in the guide back to "Show beasts".
    local G = ns.GuidesUI
    if was and G and G.page and G.page:IsShown() then G:Paint() end
end

function SpawnPins:Sync()
    if not active then return end
    local f = WorldMapFrame
    if not f or not f:IsShown() then return end
    local current = f.GetMapID and f:GetMapID()
    if current and current ~= active.mapID then
        for _, p in ipairs(pins) do p:Hide() end
        if legend then legend:Hide() end
        return
    end
    self:Draw()
end

function SpawnPins:Draw()
    if not active then return end
    local h = EnsureHolder()
    local canvas = Canvas()
    if not h or not canvas then return end
    local w, ht = canvas:GetWidth() or 0, canvas:GetHeight() or 0
    if w == 0 or ht == 0 then
        if C_Timer and C_Timer.After then C_Timer.After(0, function() SpawnPins:Draw() end) end
        return
    end
    local prof = active.prof or "Skinning"
    local skill = ns.GetPlayerSkill and ns.GetPlayerSkill(prof)
    local beasts = self:Entries(prof, active.mapID, active)
    local scale = CanvasScale()
    lastScale = scale
    local n = 0
    -- Nodes share spawn spots (a spot can hold Silver, Iron or Gold), so
    -- one pin per spot, colored by the easiest node there; the tooltip
    -- lists the rest. Beasts keep a pin per spawn.
    local shared = prof ~= "Skinning"
    local spot = {}
    table.sort(beasts, function(a, b) return (a.req or 0) < (b.req or 0) end)
    for _, b in ipairs(beasts) do
        local diff = b.req and Difficulty(b.req, skill) or "unknown"
        if prof == "Fishing" then diff = "unknown" end
        local icon = PROF_ICON[prof] or PELT
        if b.item then
            local got = (C_Item and C_Item.GetItemIconByID and C_Item.GetItemIconByID(b.item))
                or (GetItemIcon and GetItemIcon(b.item))
            if got then icon = got end
        end
        local r, g, bl
        if diff == "unknown" then
            local gold = TH() and TH().C.gold or { 0.89, 0.71, 0.36 }
            r, g, bl = gold[1], gold[2], gold[3]
        else
            r, g, bl = DiffColor(diff)
        end
        local dim = (diff == "gray" or diff == "red") and 0.55 or 1
        local pts = b.pts
        for i = 1, #pts - 1, 2 do
          local key = shared and (math.floor(pts[i] + 0.5) * 1000 + math.floor(pts[i + 1] + 0.5)) or nil
          local taken = key and spot[key]
          if taken then
            local seen = taken.beast.name == b.name
            for _, o in ipairs(taken.others) do if o == b.name then seen = true end end
            if not seen then taken.others[#taken.others + 1] = b.name end
          else
            n = n + 1
            local p = pins[n]
            if not p then
                p = NewPin(h)
                pins[n] = p
            end
            p:SetParent(h)
            p.beast, p.diff, p.x, p.y, p.hover, p.prof = b, diff, pts[i], pts[i + 1], nil, prof
            if p.iconPath ~= icon then
                p.icon:SetTexture(icon)
                p.iconPath = icon
            end
            p.ring:SetVertexColor(r, g, bl, 1)
            p.icon:SetVertexColor(1, 1, 1, 1)
            p:SetAlpha(dim)
            p:SetFrameLevel((h:GetFrameLevel() or 1) + 1)
            SizePin(p, scale)
            InsetIcon(p, scale)
            p:ClearAllPoints()
            p:SetPoint("CENTER", canvas, "TOPLEFT", (pts[i] / 100) * w, -(pts[i + 1] / 100) * ht)
            p:Show()
            p.others = {}
            if key then spot[key] = p end
          end
        end
    end
    for i = n + 1, #pins do pins[i]:Hide() end
    PaintLegend(#beasts, n, skill)
end
