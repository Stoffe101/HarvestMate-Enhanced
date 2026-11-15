-- Gatherpedia: MapLink.lua
-- Click a Known zone or a trainer to open the world map on that zone.
-- Known coordinates get Gatherpedia's own pin: a small gold disc with a
-- soft glow and a thin dark outline. The name, zone and coordinates
-- show in a hover tooltip, never as text on the map. It only draws our
-- own marker: nothing is tracked or added to the game's map tools.

local ADDON_NAME, ns = ...

local MapLink = {}
ns.MapLink = MapLink

local pending          -- { mapID, zone } queued while in combat
local pinData          -- { mapID, zone, x, y, label } current overlay, or nil
local pin              -- the overlay frame, created once

local function InCombat() return InCombatLockdown and InCombatLockdown() end

-- The map canvas the overlay should follow when the player zooms or pans.
local function Canvas()
    local f = WorldMapFrame
    if not f then return nil end
    if f.ScrollContainer then
        return f.ScrollContainer.Child or f.ScrollContainer
    end
    if f.GetCanvas then
        local ok, c = pcall(f.GetCanvas, f)
        if ok and c then return c end
    end
    return f
end

-- Keep trainer / Show-on-map pins near 18 screen pixels at any zoom.
local PIN_SCREEN = 18
local function CanvasScale()
    local sc = WorldMapFrame and WorldMapFrame.ScrollContainer
    local cs = 1
    if sc and sc.GetCanvasScale then
        cs = sc:GetCanvasScale() or 1
    end
    if (not cs or cs <= 0) and WorldMapFrame and WorldMapFrame.GetCanvasScale then
        cs = WorldMapFrame:GetCanvasScale() or 1
    end
    if not cs or cs <= 0 then cs = 1 end
    return cs
end
function MapLink.PinSize()
    return PIN_SCREEN / CanvasScale()
end

-- Show the map frame (closed -> open) without toggling it shut if it's up.
local function ShowMap(mapID)
    local f = WorldMapFrame
    if not f then return false end
    if f.HandleUserActionOpenSelf and OpenWorldMap then
        OpenWorldMap(mapID)                       -- clients whose OpenWorldMap takes a map ID
    elseif not f:IsShown() then
        if ToggleWorldMap then ToggleWorldMap()
        elseif ShowUIPanel then ShowUIPanel(f)
        else f:Show() end
    end
    return f:IsShown()
end

-- Brief zone name over the top of the map.
local function Flash(zone)
    local f = WorldMapFrame
    if not f or not zone then return end
    if not MapLink.flash then
        local holder = CreateFrame("Frame", nil, f)
        holder:SetAllPoints(f.ScrollContainer or f)
        holder:SetFrameLevel((f:GetFrameLevel() or 1) + 50)
        local text = holder:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
        text:SetPoint("TOP", holder, "TOP", 0, -24)
        text:SetTextColor(1, 0.82, 0)
        holder.text = text
        holder:Hide()
        MapLink.flash = holder
    end
    local h = MapLink.flash
    h.text:SetText(zone)
    h:SetAlpha(1)
    h:Show()
    h.token = (h.token or 0) + 1
    local token = h.token
    if C_Timer and C_Timer.After then
        C_Timer.After(1.6, function()
            if h.token ~= token then return end
            if UIFrameFadeOut then UIFrameFadeOut(h, 0.6, 1, 0) end
            C_Timer.After(0.7, function() if h.token == token then h:Hide() end end)
        end)
    end
end

local function FormatXY(x, y)
    if not x or not y then return nil end
    return ("%.1f, %.1f"):format(x, y)
end

---------------------------------------------------------------------------
-- Shared map marker
-- Fills use a light circular indicator so they take a tint (a dark base
-- texture would stay dark). The ornate ring is MiniMap-TrackingBorder.
-- Icons use Classic Interface\Icons paths. The profession icon is
-- always cropped and circular-masked so its square edges cannot show
-- outside the ring. Square fills such as WHITE8X8 are never used for
-- the pin body, shadow, or glow.
---------------------------------------------------------------------------

local WHITE8 = "Interface\\Buttons\\WHITE8X8"
local RING = "Interface\\Minimap\\MiniMap-TrackingBorder"
local MASK = "Interface\\CharacterFrame\\TempPortraitAlphaMask"
local DOT_YELLOW = "Interface\\COMMON\\Indicator-Yellow"
local DOT_GRAY = "Interface\\COMMON\\Indicator-Gray"

local ICONS = {
    Herbalism = "Interface\\Icons\\Trade_Herbalism",
    Mining    = "Interface\\Icons\\Trade_Mining",
    Fishing   = "Interface\\Icons\\Trade_Fishing",
    Skinning  = "Interface\\Icons\\INV_Misc_Pelt_Wolf_01",
    trainer   = "Interface\\Icons\\INV_Misc_Book_09",
}

local GOLD_R, GOLD_G, GOLD_B = 1.00, 0.86, 0.30
local FLASH_TIME = 0.7

local function TexturePath(tex)
    if not tex or not tex.GetTexture then return nil end
    local ok, got = pcall(tex.GetTexture, tex)
    if ok and got and got ~= "" then return tostring(got) end
end

local function TryTexture(tex, path)
    if not tex or not path or not tex.SetTexture then return false end
    if not pcall(tex.SetTexture, tex, path) then return false end
    if tex.GetTexture then
        if not TexturePath(tex) then
            tex._path, tex._loaded = path, false
            return false
        end
    end
    tex._path, tex._loaded = path, true
    return true
end

local function PaintColor(tex, r, g, b, a)
    if not tex then return end
    if tex.SetVertexColor then pcall(tex.SetVertexColor, tex, r, g, b, a) end
    if tex.SetAlpha then pcall(tex.SetAlpha, tex, a) end
end

-- Colorable fill. Never a dark base texture.
local function FillGold(tex, r, g, b, a, style)
    if not tex then return end
    local paths
    if style == "yellow" then
        paths = { DOT_YELLOW, DOT_GRAY, WHITE8 }
    elseif style == "gray" then
        paths = { DOT_GRAY, DOT_YELLOW, WHITE8 }
    else
        paths = { WHITE8, DOT_YELLOW }
    end
    for i = 1, #paths do
        if TryTexture(tex, paths[i]) then
            PaintColor(tex, r, g, b, a)
            return
        end
    end
    if tex.SetColorTexture and pcall(tex.SetColorTexture, tex, r, g, b, a) then
        tex._path, tex._loaded = "SetColorTexture", true
        return
    end
    tex._path, tex._loaded = "(failed)", false
end

local function PulseOn()
    return ns.RouteOverlay and ns.RouteOverlay.FlowEnabled and ns.RouteOverlay:FlowEnabled()
end

local function IconFor(opts)
    opts = opts or {}
    if opts.kind == "trainer" then return ICONS.trainer end
    if opts.prof and ICONS[opts.prof] then return ICONS[opts.prof] end
    return ICONS.trainer
end

-- Circular fill only; a square fill would show behind the ring.
local function FillCircle(tex, r, g, b, a)
    if not tex then return false end
    if TryTexture(tex, DOT_YELLOW) or TryTexture(tex, DOT_GRAY) then
        PaintColor(tex, r, g, b, a)
        if tex.Show then tex:Show() end
        return true
    end
    if tex.Hide then tex:Hide() end
    tex._path, tex._loaded = "(hidden, no circular texture)", false
    return false
end

-- Crop the icon's square border, then punch it to a circle. SetTexture
-- can clear a mask, so this is called again after every icon path change.
local function ApplyMask(icon, holder)
    if not icon then return "none" end
    if icon.SetTexCoord then pcall(icon.SetTexCoord, icon, 0.08, 0.92, 0.08, 0.92) end
    if icon.SetMask and pcall(icon.SetMask, icon, MASK) then
        return "SetMask"
    end
    if holder and holder.CreateMaskTexture then
        if not icon._mask then
            local ok, mask = pcall(holder.CreateMaskTexture, holder)
            if ok and mask then
                mask:SetAllPoints(icon)
                icon._mask = mask
            end
        end
        local mask = icon._mask
        if mask and TryTexture(mask, MASK) and icon.AddMaskTexture then
            pcall(icon.AddMaskTexture, icon, mask)
            return "mask-texture"
        end
    end
    return "texcrop"
end

local function ApplyLook(m)
    if not m or not m._base then return end
    local flash = 0
    if m._flashFor and m._flashFor > 0 and m._flashDur and m._flashDur > 0 then
        flash = math.max(0, math.min(1, m._flashFor / m._flashDur))
    end
    local breathe = 0
    if PulseOn() then
        breathe = 0.5 + 0.5 * math.sin((m._t or 0) * 2.0)
    end
    local hover = m._hover and 1 or 0
    local core = m._base * (1 + 0.18 * flash + 0.02 * breathe + 0.10 * hover)
    local glow = core * (1.45 + 0.20 * flash + 0.10 * breathe + 0.16 * hover)
    if m.shadow then
        m.shadow:SetSize(core * 1.10, core * 1.10)
        if m.shadow.ClearAllPoints then m.shadow:ClearAllPoints() end
        m.shadow:SetPoint("CENTER", 1, -1)
        if m.shadow.SetAlpha then m.shadow:SetAlpha(0.35) end
    end
    if m.glow then
        m.glow:SetSize(glow, glow)
        if m.glow.SetAlpha then m.glow:SetAlpha(0.28 + 0.16 * breathe + 0.28 * flash + 0.18 * hover) end
    end
    if m.icon then
        -- Sit inside the ring's inner disc so cropped corners cannot poke out.
        m.icon:SetSize(core * 0.72, core * 0.72)
    end
    if m.ring then
        -- Tracking border is padded; size it larger than the icon.
        m.ring:SetSize(core * 1.55, core * 1.55)
        if m.ring.SetAlpha then m.ring:SetAlpha(1) end
    end
    if m.core then
        m.core:SetSize(core * 0.80, core * 0.80)
        local showCore = not (m.icon and m.icon._loaded)
        if m.core.SetShown then m.core:SetShown(showCore) elseif showCore then m.core:Show() else m.core:Hide() end
    end
    local side = math.max(core * 1.55, 14)
    m:SetSize(side, side)
end

function MapLink:CreateMarker(parent, name)
    local ok, m
    if name then
        ok, m = pcall(CreateFrame, "Frame", name, parent)
    else
        ok, m = pcall(CreateFrame, "Frame", nil, parent)
    end
    if not ok or not m then return nil end
    m:SetSize(PIN_SCREEN, PIN_SCREEN)
    if m.EnableMouse then m:EnableMouse(true) end

    -- Circular drop shadow only.
    m.shadow = m:CreateTexture(nil, "BACKGROUND")
    m.shadow:SetPoint("CENTER", 1, -1)
    FillCircle(m.shadow, 0, 0, 0, 0.35)

    m.glow = m:CreateTexture(nil, "BACKGROUND")
    m.glow:SetPoint("CENTER")
    FillCircle(m.glow, GOLD_R, GOLD_G, GOLD_B, 0.40)

    -- Solid gold disc, shown only if the profession icon fails to load.
    m.core = m:CreateTexture(nil, "BORDER")
    m.core:SetPoint("CENTER")
    FillCircle(m.core, GOLD_R, GOLD_G, GOLD_B, 1)

    m.icon = m:CreateTexture(nil, "ARTWORK")
    m.icon:SetPoint("CENTER")
    m._maskMode = ApplyMask(m.icon, m)

    m.ring = m:CreateTexture(nil, "OVERLAY")
    m.ring:SetPoint("CENTER")
    if TryTexture(m.ring, RING) then
        if m.ring.SetTexCoord then pcall(m.ring.SetTexCoord, m.ring, 0.00, 0.60, 0.00, 0.60) end
        PaintColor(m.ring, GOLD_R, GOLD_G, GOLD_B, 1)
    else
        -- A simple gold bezel if the ornate ring is missing.
        FillGold(m.ring, GOLD_R, GOLD_G, GOLD_B, 0.95, "yellow")
    end

    m.num = m:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    m.num:SetPoint("CENTER", 0, -1)
    m.num:SetTextColor(1, 0.95, 0.75)
    if m.num.SetShadowOffset then m.num:SetShadowOffset(1, -1) end
    if m.num.SetShadowColor then m.num:SetShadowColor(0, 0, 0, 1) end
    if m.num.Hide then m.num:Hide() end

    m._base = PIN_SCREEN
    m:SetScript("OnUpdate", function(self, elapsed)
        self._t = (self._t or 0) + (elapsed or 0)
        if self._flashFor and self._flashFor > 0 then
            self._flashFor = self._flashFor - (elapsed or 0)
        else
            self._flashFor = nil
        end
        if (not PulseOn()) and not self._flashFor then
            if not self._rested then
                ApplyLook(self)
                self._rested = true
            end
            return
        end
        self._rested = nil
        ApplyLook(self)
    end)
    m:SetScript("OnEnter", function(self)
        self._hover = true
        self._rested = nil
        ApplyLook(self)
        if not self.tipTitle or not GameTooltip then return end
        if GameTooltip.SetOwner then GameTooltip:SetOwner(self, "ANCHOR_RIGHT") end
        if GameTooltip.ClearLines then GameTooltip:ClearLines() end
        if GameTooltip.AddLine then
            GameTooltip:AddLine(self.tipTitle, 1, 0.82, 0)
            if self.tipExtra and self.tipExtra ~= "" then
                GameTooltip:AddLine(self.tipExtra, 0.92, 0.90, 0.82, true)
            end
            if self.tipZone and self.tipZone ~= "" and self.tipZone ~= self.tipTitle then
                GameTooltip:AddLine(self.tipZone, 1, 1, 1, true)
            end
            if self.tipXY and self.tipXY ~= "" then
                GameTooltip:AddLine(self.tipXY, 0.80, 0.75, 0.62)
            end
        end
        if GameTooltip.Show then GameTooltip:Show() end
    end)
    m:SetScript("OnLeave", function(self)
        self._hover = nil
        self._rested = nil
        ApplyLook(self)
        if GameTooltip and GameTooltip.Hide then GameTooltip:Hide() end
    end)
    ApplyLook(m)
    return m
end

function MapLink:PaintMarker(m, opts)
    if not m then return end
    opts = opts or {}
    m._base = opts.size or PIN_SCREEN
    m._rested = nil
    m._opts = opts
    if m.icon then
        local path = IconFor(opts)
        if TryTexture(m.icon, path) then
            PaintColor(m.icon, 1, 1, 1, 1)
        end
        -- Re-apply after SetTexture; some clients drop the mask on a new path.
        m._maskMode = ApplyMask(m.icon, m)
    end
    if m.num then
        if opts.number then
            m.num:SetText(tostring(opts.number))
            m.num:Show()
        else
            m.num:SetText("")
            m.num:Hide()
        end
    end
    m.tipTitle = opts.tipTitle
    m.tipZone = opts.tipZone
    m.tipXY = opts.tipXY
    m.tipExtra = opts.tipExtra
    ApplyLook(m)
end

function MapLink:FlashMarker(m, duration)
    if not m then return end
    m._flashDur = duration or FLASH_TIME
    m._flashFor = m._flashDur
    m._rested = nil
    ApplyLook(m)
end

function MapLink:PinTextureReport()
    local lines = {}
    local function add(tex, label)
        if not tex then
            lines[#lines + 1] = "  " .. label .. ": (none)"
            return
        end
        local path = tex._path or TexturePath(tex) or "(unknown)"
        local loaded = tex._loaded
        if loaded == nil then loaded = TexturePath(tex) ~= nil end
        lines[#lines + 1] = string.format("  %s: %s  loaded=%s", label, path, loaded and "yes" or "no")
    end
    if not pin then
        lines[#lines + 1] = "Map pin: (not created yet)"
        return lines
    end
    lines[#lines + 1] = "Map pin textures:"
    add(pin.shadow, "shadow")
    add(pin.glow, "glow")
    add(pin.core, "core")
    add(pin.icon, "icon")
    add(pin.ring, "ring")
    if pin._maskMode then
        lines[#lines + 1] = "  mask: " .. tostring(pin._maskMode)
    end
    return lines
end

local function EnsurePin()
    if pin then return pin end
    local parent = Canvas() or UIParent
    pin = MapLink:CreateMarker(parent, "GatherpediaMapPin")
    if not pin then return nil end
    if pin.SetFrameStrata then pin:SetFrameStrata("FULLSCREEN_DIALOG") end
    if pin.SetFrameLevel then pin:SetFrameLevel(80) end
    pin:Hide()
    -- Drop the overlay when the map is closed. Stay up across zone switches
    -- only while this trainer's map is the one being shown.
    if WorldMapFrame then
        if WorldMapFrame.HookScript then
            WorldMapFrame:HookScript("OnHide", function() MapLink:ClearPin() end)
            WorldMapFrame:HookScript("OnShow", function() MapLink:SyncPin() end)
        end
        if WorldMapFrame.SetMapID then
            if hooksecurefunc then
                hooksecurefunc(WorldMapFrame, "SetMapID", function() MapLink:SyncPin() end)
            else
                local oldSet = WorldMapFrame.SetMapID
                WorldMapFrame.SetMapID = function(self, ...)
                    oldSet(self, ...)
                    MapLink:SyncPin()
                end
            end
        end
    end
    return pin
end

function MapLink:ClearPin()
    pinData = nil
    if pin then pin:Hide() end
end

function MapLink:PinData() return pinData end

function MapLink:SyncPin()
    if not pinData or not pinData.x or not pinData.y then
        if pin then pin:Hide() end
        return
    end
    local f = WorldMapFrame
    if not f or not f:IsShown() then
        if pin then pin:Hide() end
        return
    end
    local current = f.GetMapID and f:GetMapID()
    if current and pinData.mapID and current ~= pinData.mapID then
        if pin then pin:Hide() end
        return
    end
    local canvas = Canvas()
    if not canvas then return end
    local p = EnsurePin()
    p:SetParent(canvas)
    local w, h = canvas:GetWidth() or 0, canvas:GetHeight() or 0
    if w == 0 or h == 0 then
        -- The canvas may not have a size until the next frame.
        if C_Timer and C_Timer.After then C_Timer.After(0, function() MapLink:SyncPin() end) end
        return
    end
    p:ClearAllPoints()
    p:SetPoint("CENTER", canvas, "TOPLEFT", (pinData.x / 100) * w, -(pinData.y / 100) * h)
    local xy = FormatXY(pinData.x, pinData.y)
    local title = pinData.label or pinData.zone or ""
    MapLink:PaintMarker(p, {
        size = MapLink.PinSize(),
        tipTitle = title,
        tipZone = pinData.zone,
        tipXY = xy,
        prof = pinData.prof,
        kind = pinData.kind,
        number = pinData.number,
    })
    p:Show()
    if pinData.flash then
        pinData.flash = false
        MapLink:FlashMarker(p, FLASH_TIME)
    end
end

-- Returns true when the map was opened (or switched) now, false when queued
-- or not possible.
function MapLink:Open(zone, mapID)
    mapID = mapID or ns.Zones:MapID(zone)
    if not mapID then return false end
    local shown = WorldMapFrame and WorldMapFrame:IsShown()
    if InCombat() and not shown then
        pending = { mapID = mapID, zone = zone }
        self.events:RegisterEvent("PLAYER_REGEN_ENABLED")
        ns:Print("Can't open the map in combat. It will open on " .. (zone or "that zone") .. " when combat ends.")
        return false
    end
    local ui = ns.UI and ns.UI.frame
    local wasShown = ui and ui.IsShown and ui:IsShown()
    if not ShowMap(mapID) then return false end
    if ns.UI and ns.UI.DockAfterMapOpen then
        ns.UI:DockAfterMapOpen(wasShown)
    end
    if WorldMapFrame.SetMapID and (not WorldMapFrame.GetMapID or WorldMapFrame:GetMapID() ~= mapID) then
        WorldMapFrame:SetMapID(mapID)
    end
    -- Some clients pick the player's map in OnShow a frame later; set it again then.
    if C_Timer and C_Timer.After then
        C_Timer.After(0, function()
            if WorldMapFrame:IsShown() and WorldMapFrame.GetMapID and WorldMapFrame:GetMapID() ~= mapID then
                WorldMapFrame:SetMapID(mapID)
            end
            MapLink:SyncPin()
        end)
    end
    Flash(zone)
    MapLink:SyncPin()
    return true
end

-- Open the zone and, when x,y are known, drop our own overlay pin and print
-- the coordinates in chat. With no coordinates, only the zone is opened.
function MapLink:OpenAt(zone, x, y, label, opts)
    opts = opts or {}
    if ns.SpawnPins then ns.SpawnPins:Clear() end
    local mapID = ns.Zones:MapID(zone)
    local xy = FormatXY(x, y)
    local title = label or zone or "Trainer"
    if xy then
        pinData = {
            mapID = mapID, zone = zone, x = x, y = y, label = title, flash = true,
            prof = opts.prof, kind = opts.kind, number = opts.number,
        }
        ns:Print(("%s — %s (%s)."):format(title, zone or "this zone", xy))
    else
        self:ClearPin()
        if zone then ns:Print(title .. " — " .. zone .. ".") end
    end
    if not mapID then return false end
    return self:Open(zone, mapID)
end

function MapLink:Pending() return pending end

MapLink.events = CreateFrame("Frame")
MapLink.events:SetScript("OnEvent", function(self, event)
    if event ~= "PLAYER_REGEN_ENABLED" then return end
    self:UnregisterEvent("PLAYER_REGEN_ENABLED")
    local p = pending
    pending = nil
    if p then MapLink:Open(p.zone, p.mapID) end
end)
