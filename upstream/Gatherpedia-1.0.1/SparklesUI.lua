-- Gatherpedia: SparklesUI.lua
-- Glimmer settings page (right panel of the main window), the on-node
-- cloud, a short on-screen preview, and the Glimmer Settings sidebar row.

local ADDON_NAME, ns = ...

local SparklesUI = {}
ns.SparklesUI = SparklesUI

local GOLD = { 0.90, 0.75, 0.38 }
local WHITE = "Interface\\Buttons\\WHITE8X8"
local TEX = "Interface\\AddOns\\Gatherpedia\\Media\\GlimmerStar"
local MOTE_TEX = "Interface\\AddOns\\Gatherpedia\\Media\\Disc"
local ICON_RING = "Interface\\AddOns\\Gatherpedia\\Media\\Ring"
local CIRCLE_MASK = "Interface\\AddOns\\Gatherpedia\\Media\\CircleMask"
local CIRCLE_GLOW = "Interface\\AddOns\\Gatherpedia\\Media\\CircleGlow"
-- Soft round node icon with a warm glow, slightly transparent so it sits
-- in the world. It floats a clear gap above the top of the glint column
-- and moves with it when Height changes. Offsets follow the same
-- world-to-screen scale as the cloud.
SparklesUI.NODE_ICON_GAP = 18
SparklesUI.NODE_ICON_SIZE = 32
SparklesUI.NODE_ICON_ALPHA = 0.68

local function ApplyCircleMask(tex, owner)
    if type(tex) ~= "table" then return end
    -- Prefer a mask texture (modern clients); fall back to SetMask.
    if owner and owner.CreateMaskTexture and tex.AddMaskTexture then
        if not tex._gpMask then
            local mask = owner:CreateMaskTexture()
            mask:SetAllPoints(tex)
            mask:SetTexture(CIRCLE_MASK)
            tex:AddMaskTexture(mask)
            tex._gpMask = mask
        end
        return
    end
    if tex.SetMask then
        tex:SetMask(CIRCLE_MASK)
    end
end

local CAT_LABEL = {
    herbs = "Herbs",
    ore = "Ore",
    fish = "Fishing pools",
    skin = "Skinnable beasts",
    quest = "Quest objects",
    other = "Other lootables",
}

-- Set the font object first, then the text, so the label always renders.
local function Text(parent, font, justify)
    local fs = parent:CreateFontString(nil, "OVERLAY")
    fs:SetFontObject(font or "GatherpediaFontNormal")
    fs:SetJustifyH(justify or "LEFT")
    return fs
end

local function Opts()
    return ns.Sparkles and ns.Sparkles:Opts() or {}
end

---------------------------------------------------------------------------
-- Particle cloud (used on a node and for Preview)
---------------------------------------------------------------------------

local function Hash01(i, salt)
    local n = math.abs(math.sin(i * 127.1 + (salt or 0) * 311.7) * 43758.5453)
    return n - math.floor(n)
end

local function EnsureParticles(cloud, n)
    cloud.bits = cloud.bits or {}
    cloud.cores = cloud.cores or {}
    for i = 1, n do
        if not cloud.bits[i] then
            local t = cloud:CreateTexture(nil, "ARTWORK")
            t:SetTexture(TEX)
            if t.SetBlendMode then t:SetBlendMode("ADD") end
            t:SetTexCoord(0, 1, 0, 1)
            cloud.bits[i] = t
            local c = cloud:CreateTexture(nil, "OVERLAY")
            c:SetTexture(TEX)
            if c.SetBlendMode then c:SetBlendMode("ADD") end
            c:SetTexCoord(0, 1, 0, 1)
            cloud.cores[i] = c
        end
        cloud.bits[i]:Show()
        cloud.cores[i]:Show()
    end
    for i = n + 1, #(cloud.bits) do
        cloud.bits[i]:Hide()
        cloud.cores[i]:Hide()
    end
end

-- Tight cluster in UI pixels. Count does not change the radius.
-- Height only scales how far the stars rise (30-45 px at 100%).
--
-- Stars are laid out in 3D around the node (x, z on a filled disk).
-- Each tick they are rotated by the view yaw and projected to the
-- screen so turning the character changes the cloud. They also rise
-- from the base of the cloud and respawn at the bottom, so the
-- glitter streams upward continuously.

local function ViewYaw()
    -- Prefer a camera yaw only when this client actually has one.
    -- Classic / Forever typically do not, so do not rely on it.
    if GetCameraFacing then
        local ok, yaw = pcall(GetCameraFacing)
        if ok and type(yaw) == "number" then return yaw end
    end
    if GetPlayerFacing then
        local ok, yaw = pcall(GetPlayerFacing)
        if ok and type(yaw) == "number" then return yaw end
    end
    return nil
end

-- Project a 3D offset. yaw is radians, or nil for a static (unrotated) layout.
-- Returns screen x, screen y, and depth (positive is farther).
local function Project(x, z, y, yaw)
    local cosT, sinT = 1, 0
    if type(yaw) == "number" then
        cosT, sinT = math.cos(yaw), math.sin(yaw)
    end
    return x * cosT - z * sinT, y, x * sinT + z * cosT
end

-- Exposed for anything that needs the same math.
SparklesUI.ViewYaw = ViewYaw
SparklesUI.Project = Project

-- Rise travel, in UI pixels, and the starting height below the cloud
-- center (the bottom of the object).
local RISE_MIN, RISE_MAX, Y_BASE = 26, 40, 0
-- Glints rise in a tight column over the node (radius ~14 px).
-- Star base size in px at scale 1.
local COLUMN_RADIUS = 14
local STAR_BASE = 14
local MOTES = 6
local CLUSTER_SIZE = 1.30

local function PlaceOnDisk(p, i, gen, radius)
    local seed = i + (gen or 0) * 19
    local ang = Hash01(seed, 1) * 6.28318
    local rad = radius * math.sqrt(Hash01(seed, 2))
    p.x = math.cos(ang) * rad
    p.z = math.sin(ang) * rad
    p.rise = RISE_MIN + Hash01(seed, 8) * (RISE_MAX - RISE_MIN)
    p.yBase = Y_BASE
    -- Seconds for one rise at normal speed; Speed setting scales this.
    p.duration = 2.0 + Hash01(seed, 10) * 0.9
end

-- Width setting: how far the column spreads left and right (1 = 100%).
function SparklesUI.WidthMult()
    local w = (tonumber(Opts().width) or 100) / 100
    if w < 0.5 then w = 0.5 elseif w > 3 then w = 3 end
    return w
end

-- Thickness setting: how big each glint is (1 = 100%).
function SparklesUI.ThickMult()
    local t = (tonumber(Opts().thickness) or 100) / 100
    if t < 0.5 then t = 0.5 elseif t > 2 then t = 2 end
    return t
end

local function Layout(cloud, n)
    local wm = SparklesUI.WidthMult()
    if cloud._laidN == n and cloud._laidW == wm then return end
    cloud._laidN = n
    cloud._laidW = wm
    cloud._p = {}
    local radius = COLUMN_RADIUS * wm
    cloud._radius = radius
    for i = 1, n do
        -- Filled horizontal disk. Height comes from the rise, not a
        -- static spread, so the tight 40-62 px xz radius still holds
        -- as you turn.
        local p = {
            scale = 0.75 + Hash01(i, 3) * 0.70,
            phase = Hash01(i, 4) * 6.28318,
            twspeed = 0.65 + Hash01(i, 5) * 1.70,
            drift = 0.35 + Hash01(i, 6) * 0.70,
            dphase = Hash01(i, 7) * 6.28318,
            gen = 0,
            -- Stagger so the stream is already continuous on first show.
            progress = Hash01(i, 9),
        }
        PlaceOnDisk(p, i, 0, radius)
        p.y = p.yBase + p.progress * p.rise
        cloud._p[i] = p
    end
    cloud._yawCached = nil
end

-- 100% Height is twice the base rise; 200% doubles it.
function SparklesUI.HeightMult()
    local o = Opts()
    local h = (tonumber(o.height) or 100) / 100
    if h < 0.5 then h = 0.5 elseif h > 2 then h = 2 end
    return h * 2
end

-- Top of the glint column above the node base, in px at scale 1.
function SparklesUI.ColumnTop()
    return Y_BASE + RISE_MAX * SparklesUI.HeightMult()
end

-- Brightness above 100% adds size and core glow (alpha is already full).
function SparklesUI.Boost()
    local b = (tonumber(Opts().bright) or 100) / 100
    if b < 1 then return 0 end
    if b > 2 then b = 2 end
    return b - 1
end

local function EnsureExtras(cloud)
    if not cloud.motes then
        cloud.motes = {}
        for i = 1, MOTES do
            local m = cloud:CreateTexture(nil, "ARTWORK")
            m:SetTexture(MOTE_TEX)
            if m.SetBlendMode then m:SetBlendMode("ADD") end
            cloud.motes[i] = {
                tex = m,
                x = (Hash01(i, 21) - 0.5) * 2,
                progress = Hash01(i, 22),
                duration = 1.4 + Hash01(i, 23) * 0.8,
                rise = 36 + Hash01(i, 24) * 16,
            }
        end
    end
end

-- No ground ring is drawn; hide one if a cloud still carries it.
local function TickRing(cloud, t, world, r, g, b, a)
    if cloud.ring then cloud.ring:Hide() end
end

local function TickMotes(cloud, elapsed, speed, world, height, r, g, b, a)
    for i, m in ipairs(cloud.motes or {}) do
        m.progress = m.progress + ((elapsed or 0) * speed) / m.duration
        if m.progress >= 1 then
            m.progress = m.progress - math.floor(m.progress)
            m.x = (Hash01(i + math.floor(GetTime and GetTime() or 0), 25) - 0.5) * 2
        end
        local fade = math.sin(m.progress * 3.14159)
        local s = 2.4 * SparklesUI.ThickMult() * math.max(0.8, world)
        m.tex:ClearAllPoints()
        m.tex:SetSize(s, s)
        m.tex:SetPoint("CENTER", cloud, "CENTER", m.x * COLUMN_RADIUS * SparklesUI.WidthMult() * world, (Y_BASE + m.progress * m.rise * height) * world)
        m.tex:SetVertexColor(math.min(1, r + 0.25), math.min(1, g + 0.25), math.min(1, b + 0.25), a * 0.65 * fade)
        m.tex:Show()
    end
end

local function TickCloud(cloud, elapsed)
    if not cloud:IsShown() then return end
    local S = ns.Sparkles
    local o = Opts()
    local look = cloud._look
    if not look then return end
    local n = math.max(3, math.min(32, tonumber(o.count) or 16))
    EnsureParticles(cloud, n)
    Layout(cloud, n)
    local speed = (S.SPEEDS[o.speed] or 1)
    local height = SparklesUI.HeightMult()
    cloud._t = (cloud._t or 0) + (elapsed or 0.016) * speed
    local t = cloud._t
    local r, g, b, a = look[1], look[2], look[3], look[4]
    local boost = SparklesUI.Boost()
    local base = STAR_BASE * SparklesUI.ThickMult() * (1 + 0.35 * boost)
    local radius = cloud._radius or COLUMN_RADIUS
    EnsureExtras(cloud)
    local worldNow = cloud._worldScale or 1
    TickRing(cloud, t, worldNow, r, g, b, a)
    TickMotes(cloud, elapsed, speed, worldNow, height, r, g, b, a)

    -- Throttle the trig: only recompute cos/sin when facing moves a
    -- little (~0.6 deg) or when we first learn the yaw is missing.
    local yaw = ViewYaw()
    local cosT, sinT = cloud._cosT, cloud._sinT
    if yaw == nil then
        if cloud._yawCached ~= false then
            cloud._yawCached, cloud._cosT, cloud._sinT = false, 1, 0
            cloud._orderDirty = true
        end
        cosT, sinT = 1, 0
    else
        local cached = cloud._yawCached
        if type(cached) ~= "number" or math.abs(yaw - cached) > 0.01 then
            cosT, sinT = math.cos(yaw), math.sin(yaw)
            cloud._yawCached, cloud._cosT, cloud._sinT = yaw, cosT, sinT
            cloud._orderDirty = true
        else
            cosT, sinT = cloud._cosT, cloud._sinT
        end
    end

    local orderDirty = cloud._orderDirty
    for i = 1, n do
        local p = cloud._p[i]
        local bit, core = cloud.bits[i], cloud.cores[i]
        -- Rise from the base and wrap back to a new disk position.
        local dur = p.duration or 2
        p.progress = (p.progress or 0) + ((elapsed or 0) * speed) / dur
        if p.progress >= 1 then
            p.gen = (p.gen or 0) + 1
            p.progress = p.progress - math.floor(p.progress)
            PlaceOnDisk(p, i, p.gen, radius)
        end
        -- Rise and the disk radius follow the same world-to-screen
        -- scale as the drop, so the stream stays the same size in the
        -- world as you walk in or out. yBase is also scaled so stars
        -- still spawn at the feet.
        local world = cloud._worldScale or 1
        local sy = ((p.yBase or -10) + p.progress * (p.rise or 37) * height) * world
        p.y = sy
        local fade = math.sin(p.progress * 3.14159)
        if fade < 0 then fade = 0 end
        local sx = (p.x * cosT - p.z * sinT) * world
        local depth = p.x * sinT + p.z * cosT
        -- Tiny screen-space twinkle drift.
        local x = sx + math.sin(t * p.drift + p.dphase) * 3
        local y = sy + math.cos(t * p.drift * 0.8 + p.dphase) * 3
        local pulse = math.max(0, math.sin(t * p.twspeed * 3.2 + p.phase))
        local tw = 0.22 + 0.78 * pulse * pulse
        local dn = 0
        if radius > 0 then
            dn = depth / radius
            if dn > 1 then dn = 1 elseif dn < -1 then dn = -1 end
        end
        -- Farther stars are slightly smaller and dimmer. Rise fade is
        -- applied on top.
        local dScale = 1 - 0.16 * dn
        local dAlpha = 1 - 0.14 * dn
        if dAlpha < 0.05 then dAlpha = 0.05 elseif dAlpha > 1 then dAlpha = 1 end
        local s = math.max(7, base * p.scale * (0.85 + 0.25 * tw) * dScale * math.max(0.7, world))
        bit:ClearAllPoints()
        bit:SetSize(s, s)
        bit:SetPoint("CENTER", cloud, "CENTER", x, y)
        bit:SetVertexColor(r, g, b, a * tw * dAlpha * fade)
        local cs = math.max(3, s * 0.40)
        core:ClearAllPoints()
        core:SetSize(cs, cs)
        core:SetPoint("CENTER", bit, "CENTER")
        -- Core: the chosen color lifted toward white, so the hue still reads.
        core:SetVertexColor(0.45 + 0.55 * r, 0.45 + 0.55 * g, 0.45 + 0.55 * b,
            math.min(1, a * (0.60 + 0.20 * boost)) * tw * dAlpha * fade)
        if orderDirty and bit.SetDrawLayer then
            -- Nearer (negative depth) draws on top. Sublevel is -8..7.
            local sub = math.floor(-dn * 7)
            if sub < -8 then sub = -8 elseif sub > 7 then sub = 7 end
            bit:SetDrawLayer("ARTWORK", sub)
            if core.SetDrawLayer then core:SetDrawLayer("OVERLAY", sub) end
        end
    end
    cloud._orderDirty = false
end

-- World glimmer lives under every UI window, the way nameplates do:
-- a dedicated layer on WorldFrame at BACKGROUND. Preview stays on
-- UIParent at a higher strata (it is meant to sit in front).
-- Alt+Z hides UIParent; we hide this layer with it so the stars
-- do not linger on a UI-less world.
function SparklesUI:WorldLayer()
    if self.layer then return self.layer end
    local parent = WorldFrame or UIParent
    local f = CreateFrame("Frame", "GatherpediaGlimmerLayer", parent)
    f:SetFrameStrata("BACKGROUND")
    if f.SetFrameLevel then f:SetFrameLevel(1) end
    if f.SetAllPoints then f:SetAllPoints(parent) end
    if UIParent and UIParent.HookScript then
        pcall(function()
            UIParent:HookScript("OnHide", function()
                if SparklesUI.layer then SparklesUI.layer:Hide() end
            end)
            UIParent:HookScript("OnShow", function()
                if SparklesUI.layer then SparklesUI.layer:Show() end
            end)
        end)
    end
    if UIParent and UIParent.IsShown and not UIParent:IsShown() then
        f:Hide()
    else
        f:Show()
    end
    self.layer = f
    return f
end

-- Lerp the drop and the world scale toward the current target so a
-- changing scale does not jump the cloud. Snap when the anchor frame
-- itself changes (a new target).
function SparklesUI:PlaceCloud(cloud, fr, rel, x, targetY, scale, snap)
    scale = scale or 1
    if snap or cloud._drop == nil or cloud._ofr ~= fr then
        cloud._drop = targetY
        cloud._worldScale = scale
    else
        local lerp = (ns.Sparkles and ns.Sparkles.CLOUD_SCALE_LERP) or 0.15
        cloud._drop = cloud._drop + (targetY - cloud._drop) * lerp
        cloud._worldScale = (cloud._worldScale or scale) + (scale - (cloud._worldScale or scale)) * lerp
    end
    cloud._oy, cloud._ofr = cloud._drop, fr
    cloud:ClearAllPoints()
    cloud:SetPoint("CENTER", fr, rel, x, cloud._drop)
end

function SparklesUI:NewCloud(name)
    local f = CreateFrame("Frame", name, self:WorldLayer())
    f:SetSize(160, 160)
    f:SetFrameStrata("BACKGROUND")
    if f.SetFrameLevel then f:SetFrameLevel(2) end
    if f.SetScale then f:SetScale(1) end
    f:Hide()
    f:SetScript("OnUpdate", function(frame, elapsed)
        TickCloud(frame, elapsed)
        if frame._anchor and ns.Sparkles then
            local fr, rel, x, y, scale = ns.Sparkles:CloudPoint(
                frame._anchor, frame._anchorKind, frame._cat, frame._guid, frame._unit)
            if fr then
                self:PlaceCloud(frame, fr, rel, x, y, scale, false)
            end
        end
    end)
    return f
end

function SparklesUI:EnsureCloud()
    self.clouds = self.clouds or {}
    if self.cloud then return self.cloud end
    self.cloud = self:NewCloud("GatherpediaSparkleCloud")
    self.clouds[1] = self.cloud
    return self.cloud
end

function SparklesUI:EnsurePreview()
    if self.preview then return self.preview end
    local f = CreateFrame("Frame", "GatherpediaSparklePreview", UIParent)
    f:SetSize(160, 160)
    f:SetPoint("CENTER", UIParent, "CENTER", 0, 40)
    f:SetFrameStrata("FULLSCREEN_DIALOG")
    if f.SetScale then f:SetScale(1) end
    f:Hide()
    local cap = Text(f, "GatherpediaFontHighlightSmall", "CENTER")
    cap:SetPoint("BOTTOM", f, "TOP", 0, 2)
    cap:SetText("Glimmer preview")
    f.caption = cap
    f:SetScript("OnUpdate", function(frame, elapsed)
        TickCloud(frame, elapsed)
        if frame._until and GetTime() >= frame._until then
            frame:Hide()
            frame._until = nil
        end
    end)
    self.preview = f
    return f
end


function SparklesUI:EnsureNodeIcon()
    if self.nodeIcon then return self.nodeIcon end
    local size = SparklesUI.NODE_ICON_SIZE
    local f = CreateFrame("Frame", "GatherpediaGlimmerNodeIcon", self:WorldLayer())
    f:SetSize(size, size)
    f:SetFrameStrata("BACKGROUND")
    if f.SetFrameLevel then f:SetFrameLevel(3) end
    -- Soft glow behind the icon; no box, no rim.
    f.glow = f:CreateTexture(nil, "BACKGROUND")
    f.glow:SetTexture(CIRCLE_GLOW)
    if f.glow.SetBlendMode then f.glow:SetBlendMode("ADD") end
    f.glow:SetSize(48, 48)
    f.glow:SetPoint("CENTER")
    f.glow:SetVertexColor(1, 0.86, 0.40, 0.50)
    f.tex = f:CreateTexture(nil, "ARTWORK")
    f.tex:SetSize(size, size)
    f.tex:SetPoint("CENTER")
    f.tex:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    if f.tex.SetAlpha then f.tex:SetAlpha(SparklesUI.NODE_ICON_ALPHA) end
    ApplyCircleMask(f.tex, f)
    -- Keep the icon above the column as the scale and Height change.
    f:SetScript("OnUpdate", function(frame)
        local cloud = frame._cloud
        if not cloud then return end
        local world = cloud._worldScale or 1
        local y = (SparklesUI.ColumnTop() + SparklesUI.NODE_ICON_GAP) * world
        if frame._lastY == nil or math.abs(frame._lastY - y) > 0.5 then
            frame._lastY = y
            frame:ClearAllPoints()
            frame:SetPoint("BOTTOM", cloud, "CENTER", 0, y)
        end
    end)
    f:Hide()
    self.nodeIcon = f
    return f
end

function SparklesUI:HideNodeIcon()
    if self.nodeIcon then self.nodeIcon:Hide() end
end

function SparklesUI:UpdateNodeIcon(cur, cloud)
    local S = ns.Sparkles
    if not cur or not S or not S:ShowNodeIcon(cur.kind) or not cloud or not cloud._anchor then
        self:HideNodeIcon()
        return
    end
    local path = S:NodeIconTexture(cur.kind, cur.entry)
    if not path then
        self:HideNodeIcon()
        return
    end
    local f = self:EnsureNodeIcon()
    f.tex:SetTexture(path)
    if f.tex.SetAlpha then f.tex:SetAlpha(SparklesUI.NODE_ICON_ALPHA) end
    f:SetParent(self:WorldLayer())
    f._cloud = cloud
    f._lastY = nil
    f:ClearAllPoints()
    local y = (SparklesUI.ColumnTop() + SparklesUI.NODE_ICON_GAP) * (cloud._worldScale or 1)
    f:SetPoint("BOTTOM", cloud, "CENTER", 0, y)
    f:SetFrameStrata("BACKGROUND")
    if f.SetFrameLevel then f:SetFrameLevel(3) end
    f:Show()
end

function SparklesUI:HideCloud()
    for _, c in ipairs(self.clouds or {}) do
        c:Hide()
        c._look = nil
        c._anchor = nil
        c._anchorKind = nil
        c._guid = nil
    end
    self:HideNodeIcon()
    if ns.Sparkles then ns.Sparkles:RestorePlateVisuals() end
end

function SparklesUI:UpdateCloud()
    local S = ns.Sparkles
    if not S or not S:Opts().enabled then
        self:HideCloud()
        return
    end
    local targets = S:CollectTargets()
    if #targets == 0 then
        self:HideCloud()
        return
    end
    self:EnsureCloud()
    local maxN = S.MAX_CLOUDS or 4
    for i = 1, math.min(#targets, maxN) do
        if not self.clouds[i] then
            self.clouds[i] = (i == 1) and self.cloud or self:NewCloud(nil)
        end
    end
    local used = {}
    for i, tgt in ipairs(targets) do
        if i > maxN then break end
        local cloud
        if i == 1 then
            cloud = self.cloud
        else
            for j = 2, #self.clouds do
                local c = self.clouds[j]
                local cguid = ns.ReadableString(c._guid)
                local tguid = ns.ReadableString(tgt.guid)
                if not used[c] and cguid and tguid and cguid == tguid then
                    cloud = c
                    break
                end
            end
            if not cloud then
                for j = 2, #self.clouds do
                    local c = self.clouds[j]
                    if not used[c] then cloud = c; break end
                end
            end
        end
        if not cloud then break end
        local frame, rel, x, y, scale = S:CloudPoint(tgt.plate, tgt.plate and tgt.plate._ghost and "ghost" or "nameplate", tgt.kind, tgt.guid, tgt.unit)
        if not frame then
            -- No safe Blizzard frame to pin to (forbidden or missing).
        else
            local r, g, b, a = S:Look(tgt.kind, tgt.entry, tgt.inReach)
            cloud._look = { r, g, b, a }
            cloud._guid = ns.ReadableString(tgt.guid)
            cloud._cat = tgt.kind
            cloud._unit = tgt.unit
            cloud:SetParent(self:WorldLayer())
            if cloud.SetScale then cloud:SetScale(1) end
            local snap = (cloud._guid ~= ns.ReadableString(tgt.guid)) or (cloud._ofr ~= frame)
            self:PlaceCloud(cloud, frame, rel, x, y, scale, snap)
            cloud._anchor = tgt.plate
            cloud._anchorKind = tgt.plate and tgt.plate._ghost and "ghost" or "nameplate"
            cloud:SetFrameStrata("BACKGROUND")
            if cloud.SetFrameLevel then cloud:SetFrameLevel(2) end
            cloud:Show()
            used[cloud] = true
        end
    end
    local t1 = targets[1]
    if t1 and used[self.cloud] and self.cloud:IsShown() then
        self:UpdateNodeIcon(t1, self.cloud)
        if t1.source == "unit" or t1.source == "softplate" then
            S:SuppressPlateVisuals(S:NameplateForSoft() or t1.plate)
        else
            S:RestorePlateVisuals()
        end
    else
        self:HideNodeIcon()
        S:RestorePlateVisuals()
    end
    for _, c in ipairs(self.clouds) do
        if not used[c] then
            c:Hide()
            c._look = nil
            c._anchor = nil
            c._anchorKind = nil
            c._guid = nil
        end
    end
end

function SparklesUI:Preview()
    local S = ns.Sparkles
    local f = self:EnsurePreview()
    local kind = "herbs"
    for _, k in ipairs(S.CATEGORIES) do
        if S:CategoryOn(k) then kind = k; break end
    end
    local r, g, b, a = S:Look(kind, nil, true)
    f._look = { r, g, b, a }
    f._t = 0
    f._until = GetTime() + 8
    f:Show()
end

---------------------------------------------------------------------------
-- Custom gold/dark widgets (no taint-prone Blizzard templates)
---------------------------------------------------------------------------

local function MakeCheck(parent, label, tooltip, get, set)
    return ns.Theme:CheckRow(parent, label, tooltip, get, set, function()
        SparklesUI:Refresh()
        if ns.Sparkles then ns.Sparkles:RefreshTarget() end
    end)
end

local function MakeSlider(parent, w, label, minV, maxV, step, fmt, get, set, tip)
    return ns.Theme:SliderRow(parent, w, label, minV, maxV, step, fmt, get, set, tip, function()
        if ns.Sparkles then ns.Sparkles:RefreshTarget() end
    end)
end

local function MakeSwatches(parent, get, set)
    local row = {}
    local S = ns.Sparkles
    local TH = ns.Theme
    local hold = CreateFrame("Frame", nil, parent)
    hold:SetSize(6 * 22 - 2, 20)
    for i, name in ipairs(S.COLOR_NAMES) do
        local b = CreateFrame("Button", nil, hold)
        b:SetSize(20, 20)
        b:SetPoint("LEFT", (i - 1) * 22, 0)
        local rgb = S.COLORS[name]
        TH:Panel(b, TH.C.well, TH.C.line2, 5)
        b.chip = b:CreateTexture(nil, "ARTWORK")
        b.chip:SetTexture(TH.ROUND)
        b.chip:SetPoint("TOPLEFT", 3, -3)
        b.chip:SetPoint("BOTTOMRIGHT", -3, 3)
        b.chip:SetVertexColor(rgb[1], rgb[2], rgb[3], 1)
        b.colorName = name
        b:SetScript("OnClick", function()
            set(name)
            SparklesUI:Refresh()
            if ns.Sparkles then ns.Sparkles:RefreshTarget() end
        end)
        b:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:SetText(name:sub(1, 1):upper() .. name:sub(2))
            GameTooltip:Show()
        end)
        b:SetScript("OnLeave", function() GameTooltip:Hide() end)
        b.Refresh = function(self)
            local on = get() == name
            TH:PanelColors(self, on and TH.C.raised or TH.C.well, on and TH.C.goldHi or TH.C.line2)
            self.chip:SetAlpha(on and 1 or 0.75)
        end
        row[i] = b
    end
    row.frame = hold
    return row
end

---------------------------------------------------------------------------
-- Right-panel Glimmer Settings page (owned by the main window)
---------------------------------------------------------------------------

function SparklesUI:Create(parent)
    if self.page then return self.page end
    local f = CreateFrame("Frame", "GatherpediaGlimmerPage", parent)
    self.page = f
    -- Opaque fill so the item list or Options can never show through.
    local bg = f:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    -- Warm veil so the window's rock/leather texture can show through,
    -- still opaque enough that the item list cannot bleed in.
    do
        local c = ns.Theme and ns.Theme.C.main or { 0.10, 0.09, 0.08 }
        bg:SetColorTexture(c[1], c[2], c[3], 1)
    end
    f:Hide()

    local TH, TC = ns.Theme, ns.Theme.C
    local COL_GAP = 16
    local LEFT_W = 300
    local ROW_H = 34

    ----------------------------------------------------------------------
    -- Status card: what Glimmer does, and the master On/Off switch.
    ----------------------------------------------------------------------
    local status = CreateFrame("Frame", nil, f)
    status:SetPoint("TOPLEFT", 0, 0)
    status:SetPoint("TOPRIGHT", 0, 0)
    status:SetHeight(56)
    TH:Panel(status, TC.card, TC.line, 8)
    local stTitle = Text(status, "GatherpediaFontHighlight")
    stTitle:SetPoint("TOPLEFT", 14, -11)
    local stSub = Text(status, "GatherpediaFontDisableSmall")
    stSub:SetPoint("TOPLEFT", stTitle, "BOTTOMLEFT", 0, -4)
    stSub:SetText("Sparkles on the herbs, ore, pools, beasts and lootables you can interact with.")
    if stSub.SetWordWrap then stSub:SetWordWrap(false) end
    self.statusTitle = stTitle

    local seg = CreateFrame("Frame", nil, status)
    seg:SetSize(2 * 58 + 8, 30)
    seg:SetPoint("RIGHT", -12, 0)
    TH:Panel(seg, TC.well, TC.line, 8)
    local function SegButton(caption, x, on)
        local b = CreateFrame("Button", nil, seg)
        b:SetSize(58, 24)
        b:SetPoint("LEFT", x, 0)
        b.label = Text(b, "GatherpediaFontHighlightSmall", "CENTER")
        b.label:SetPoint("CENTER")
        b.label:SetText(caption)
        TH:SkinButton(b, "segment")
        b:SetScript("OnClick", function()
            ns.Sparkles:SetEnabled(on)
            SparklesUI:Refresh()
        end)
        b:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
            GameTooltip:SetText("Glimmer")
            GameTooltip:AddLine("The cloud appears on a node or corpse you soft-target, or that has a nameplate, and hides when that is gone.", 1, 1, 1, true)
            GameTooltip:Show()
        end)
        b:SetScript("OnLeave", function() GameTooltip:Hide() end)
        return b
    end
    self.masterOn = SegButton("On", 3, true)
    self.masterOff = SegButton("Off", 3 + 58 + 2, false)
    stSub:SetPoint("RIGHT", seg, "LEFT", -12, 0)

    ----------------------------------------------------------------------
    -- Left: what glimmers, one row per kind with its color.
    ----------------------------------------------------------------------
    local top = 56 + 14
    local leftLabel = TH:SectionLabel(f, "What glimmers")
    leftLabel:SetPoint("TOPLEFT", 0, -top)
    leftLabel:SetWidth(LEFT_W)

    local rows = #ns.Sparkles.CATEGORIES + 1
    local card = CreateFrame("Frame", nil, f)
    card:SetPoint("TOPLEFT", 0, -(top + 22))
    card:SetSize(LEFT_W, rows * ROW_H + 2)
    TH:Panel(card, TC.card, TC.line, 8)

    self.widgets = {}
    self.catChecks, self.catSwatches = {}, {}
    local function Sep(y)
        local t = card:CreateTexture(nil, "ARTWORK")
        t:SetHeight(1)
        t:SetPoint("TOPLEFT", 1, -y)
        t:SetPoint("TOPRIGHT", -1, -y)
        t:SetColorTexture(TC.rowLine[1], TC.rowLine[2], TC.rowLine[3], 1)
    end
    for i, kind in ipairs(ns.Sparkles.CATEGORIES) do
        local key = kind
        local y = 1 + (i - 1) * ROW_H
        if i > 1 then Sep(y) end
        local tip = (kind == "other") and "Chests, lockboxes, levers and other interactable objects."
            or (kind == "skin") and "Corpses you can skin."
            or nil
        local ck = MakeCheck(card, CAT_LABEL[kind], tip,
            function() return Opts()[key] ~= false end,
            function(v) Opts()[key] = v end)
        ck:SetPoint("LEFT", card, "TOPLEFT", 14, -(y + ROW_H / 2))
        ck:SetWidth(LEFT_W - 14 - 12 - 132 - 8)
        self.catChecks[kind] = ck
        local ckKey = ns.Sparkles.COLOR_KEYS[kind]
        local sw = MakeSwatches(card,
            function() return Opts()[ckKey] end,
            function(v) Opts()[ckKey] = v end)
        sw.frame:SetPoint("RIGHT", card, "TOPRIGHT", -12, -(y + ROW_H / 2))
        self.catSwatches[kind] = sw
    end
    do
        local y = 1 + #ns.Sparkles.CATEGORIES * ROW_H
        Sep(y)
        local icons = MakeCheck(card, "Show node icons",
            "A soft, round item icon floats above herbs, ore, fishing pools and skinnable beasts. Not shown on quest objects, chests or other lootables.",
            function() return Opts().nodeIcon ~= false end,
            function(v) Opts().nodeIcon = v and true or false end)
        icons:SetPoint("LEFT", card, "TOPLEFT", 14, -(y + ROW_H / 2))
        icons:SetWidth(LEFT_W - 28)
        self.widgets[1] = icons
    end

    local preview = CreateFrame("Button", nil, f)
    preview:SetSize(110, 26)
    preview:SetPoint("TOPLEFT", card, "BOTTOMLEFT", 0, -14)
    preview.label = Text(preview, "GatherpediaFontHighlightSmall", "CENTER")
    preview.label:SetPoint("CENTER")
    preview.label:SetText("Preview")
    TH:SkinButton(preview, "primary")
    preview:SetScript("OnClick", function() SparklesUI:Preview() end)
    self.previewBtn = preview

    local reset = CreateFrame("Button", nil, f)
    reset:SetSize(140, 26)
    reset:SetPoint("LEFT", preview, "RIGHT", 8, 0)
    reset.label = Text(reset, "GatherpediaFontHighlightSmall", "CENTER")
    reset.label:SetPoint("CENTER")
    reset.label:SetText("Reset to defaults")
    TH:SkinButton(reset, "quiet")
    reset:SetScript("OnClick", function()
        ns.Sparkles:Slash("reset")
        SparklesUI:Refresh()
    end)

    ----------------------------------------------------------------------
    -- Right: the look.
    ----------------------------------------------------------------------
    local rightLabel = TH:SectionLabel(f, "Look")
    rightLabel:SetPoint("TOPLEFT", LEFT_W + COL_GAP, -top)
    rightLabel:SetPoint("RIGHT", f, "RIGHT", 0, 0)

    local look = CreateFrame("Frame", nil, f)
    look:SetPoint("TOPLEFT", LEFT_W + COL_GAP, -(top + 22))
    look:SetPoint("RIGHT", f, "RIGHT", 0, 0)
    TH:Panel(look, TC.card, TC.line, 8)
    local pageW = (f:GetParent() and f:GetParent():GetWidth() or 800) - 200 - 16
    local sw = math.max(180, math.floor(pageW - LEFT_W - COL_GAP - 32))

    local SPEED_NAMES = { "slow", "normal", "fast" }
    self.sliders = {
        MakeSlider(look, sw, "Height", 50, 200, 5, "%d%%",
            function() return Opts().height or 100 end, function(v) Opts().height = v end,
            "How far the stars rise from the base of the object. 100% is the standard look; go higher for a taller column. The icon moves up with it."),
        MakeSlider(look, sw, "Count", 3, 32, 1, "%d",
            function() return Opts().count end, function(v) Opts().count = v end,
            "How many stars in the column. 16 is the standard look."),
        MakeSlider(look, sw, "Thickness", 50, 200, 5, "%d%%",
            function() return Opts().thickness or 100 end, function(v) Opts().thickness = v end,
            "How big and bold each glint is. 100% is the standard look."),
        MakeSlider(look, sw, "Width", 50, 300, 5, "%d%%",
            function() return Opts().width or 100 end, function(v) Opts().width = v end,
            "How far the column spreads to the left and right of the node. 100% is the standard look."),
        MakeSlider(look, sw, "Brightness", 50, 200, 5, "%d%%",
            function() return Opts().bright end, function(v) Opts().bright = v end,
            "How bright the stars are. 100% is the standard look; above it the stars grow and their cores glow brighter."),
        MakeSlider(look, sw, "Out of reach", 10, 100, 5, "%d%%",
            function() return Opts().dim end, function(v) Opts().dim = v end,
            "How bright the cloud is when you cannot reach the object yet."),
        MakeSlider(look, sw, "Speed", 1, 3, 1,
            function(v) return ({ "Slow", "Normal", "Fast" })[v] or "Normal" end,
            function()
                local sp = Opts().speed or "normal"
                if sp == "slow" then return 1 end
                if sp == "fast" then return 3 end
                return 2
            end,
            function(v) Opts().speed = SPEED_NAMES[v] or "normal" end),
    }
    local SL_STEP = 44
    for i, sl in ipairs(self.sliders) do
        sl:SetPoint("TOPLEFT", look, "TOPLEFT", 16, -14 - (i - 1) * SL_STEP)
    end
    look:SetHeight(14 + #self.sliders * SL_STEP - 4 + 6)

    f:SetScript("OnShow", function() SparklesUI:Refresh() end)
    return f
end

function SparklesUI:RefreshTab()
    local b = self.toggle
    if not b then return end
    local on = Opts().enabled
    local selected = ns.UI and ns.UI.state and ns.UI.state.view == "glimmer"
    b.label:SetText("Glimmer")
    if b.state then
        b.state:SetText(on and "On" or "Off")
        local TC = ns.Theme and ns.Theme.C
        if TC then
            local c = on and TC.green or TC.text3
            b.state:SetTextColor(c[1], c[2], c[3])
        elseif on then
            b.state:SetTextColor(0.25, 0.75, 0.25)
        else
            b.state:SetTextColor(0.69, 0.59, 0.39)
        end
        b.state:Show()
    end
    if ns.UI and ns.UI.PaintSidebarRow then
        ns.UI:PaintSidebarRow(b, selected, false)
    else
        if b.label then
            b.label:SetTextColor(selected and 1 or GOLD[1], selected and 1 or GOLD[2], selected and 1 or GOLD[3])
        end
    end
    -- Keep the star readable when Glimmer is off, just a touch dimmer.
    if b.icon and b.icon.SetVertexColor then
        if on then
            b.icon:SetVertexColor(1, 1, 1, 1)
        else
            b.icon:SetVertexColor(0.7, 0.7, 0.7, 1)
        end
    end
end

function SparklesUI:Refresh()
    -- Tab refresh must not depend on the settings page existing.
    self:RefreshTab()
    if not self.page then return end
    for _, w in ipairs(self.widgets or {}) do w:Refresh() end
    for _, cb in pairs(self.catChecks or {}) do cb:Refresh() end
    for _, row in pairs(self.catSwatches or {}) do
        for _, b in ipairs(row) do b:Refresh() end
    end
    for _, sl in ipairs(self.sliders or {}) do sl:Refresh() end
    local on = Opts().enabled
    if self.masterOn and ns.Theme then
        ns.Theme:PaintButton(self.masterOn, on and "segmentOn" or "segment")
        ns.Theme:PaintButton(self.masterOff, on and "segment" or "segmentOn")
    end
    if self.statusTitle then
        local TC = ns.Theme.C
        self.statusTitle:SetText(on and "Glimmer is on" or "Glimmer is off")
        local c = on and TC.green or TC.text2
        self.statusTitle:SetTextColor(c[1], c[2], c[3])
    end
end

function SparklesUI:Show()
    if ns.UI and ns.UI.ShowGlimmer then
        ns.UI:ShowGlimmer()
    end
end

function SparklesUI:Toggle()
    self:Show()
end

-- Glimmer row in the left sidebar, under Trainers. Same stone-frame
-- chrome as the profession and Trainers rows.
function SparklesUI:Attach(parent)
    if self.toggle then return self.toggle end
    local b
    if ns.UI and ns.UI.CreateSidebarRow then
        b = ns.UI:CreateSidebarRow(parent)
    else
        b = CreateFrame("Button", "GatherpediaSparkleToggle", parent)
        b:SetSize(168, 38)
        b.label = Text(b, "GatherpediaFontNormal")
        b.label:SetPoint("LEFT", 46, 8)
        b.icon = b:CreateTexture(nil, "ARTWORK")
        b.icon:SetSize(32, 32)
        b.icon:SetPoint("LEFT", 6, 0)
    end
    if b.SetName then b:SetName("GatherpediaSparkleToggle") end
    -- Name the button for debugging if it was created without one.
    -- (CreateSidebarRow does not assign a global name.)
    -- Large Glimmering Shard: a game icon that fits the name.
    b.icon:SetTexture("Interface\\Icons\\INV_Enchant_ShardGlimmeringLarge")
    if b.icon.SetTexCoord then b.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93) end
    b.label:SetText("Glimmer")
    if b.rank then b.rank:Hide() end
    if b.skillTrack then b.skillTrack:Hide() end
    if b.sub then
        b.state = b.sub
    else
        b.state = Text(b, "GatherpediaFontHighlightSmall")
        b.state:SetPoint("BOTTOMLEFT", b.icon, "BOTTOMRIGHT", 8, 2)
    end
    -- Title on the top line, On/Off as the subtitle, like a profession row.
    if b.slot then
        b.label:ClearAllPoints()
        b.label:SetPoint("TOPLEFT", b.slot, "TOPRIGHT", 8, -1)
        b.label:SetPoint("RIGHT", b, "RIGHT", -8, 0)
    end
    b.state:SetText("Off")
    b:SetScript("OnClick", function()
        SparklesUI:Show()
    end)
    b:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText("Glimmer Settings")
        GameTooltip:AddLine("Open the Glimmer page to turn the effect on or off, pick colors, and adjust the look.", 1, 1, 1, true)
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    self.toggle = b
    self:RefreshTab()
    return b
end

---------------------------------------------------------------------------
-- Glimmer debug window: movable, closable, copyable text
---------------------------------------------------------------------------

function SparklesUI:ShowDebugPanel()
    local f = self.debugPanel
    if not f then
        f = CreateFrame("Frame", "GatherpediaGlimmerDebug", UIParent, "BackdropTemplate")
        f:SetSize(520, 420)
        f:SetPoint("CENTER", 0, 40)
        f:SetFrameStrata("FULLSCREEN_DIALOG")
        f:SetToplevel(true)
        f:SetClampedToScreen(true)
        f:SetMovable(true)
        f:EnableMouse(true)
        f:RegisterForDrag("LeftButton")
        f:SetScript("OnDragStart", f.StartMoving)
        f:SetScript("OnDragStop", f.StopMovingOrSizing)
        if ns.Chrome and ns.Chrome.ApplyWindow then
            ns.Chrome:ApplyWindow(f)
        else
            f:SetBackdrop({
                bgFile = WHITE,
                edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
                edgeSize = 16,
                insets = { left = 4, right = 4, top = 4, bottom = 4 },
            })
            f:SetBackdropColor(0.07, 0.05, 0.04, 0.97)
            f:SetBackdropBorderColor(GOLD[1], GOLD[2], GOLD[3], 1)
        end
        local title = Text(f, "GatherpediaFontHeading", "CENTER")
        title:SetPoint("TOP", 0, -14)
        title:SetText("Glimmer debug")
        title:SetTextColor(GOLD[1], GOLD[2], GOLD[3])
        if ns.Chrome and ns.Chrome.MakeCloseButton then
            ns.Chrome:MakeCloseButton(f, function() f:Hide() end)
        else
            local close = CreateFrame("Button", nil, f)
            close:SetSize(24, 24)
            close:SetPoint("TOPRIGHT", -6, -6)
            close:SetScript("OnClick", function() f:Hide() end)
            local x = Text(close, "GatherpediaFontNormal", "CENTER")
            x:SetPoint("CENTER")
            x:SetText("X")
            x:SetTextColor(GOLD[1], GOLD[2], GOLD[3])
        end

        local scroll = CreateFrame("ScrollFrame", "GatherpediaGlimmerDebugScroll", f)
        scroll:SetPoint("TOPLEFT", 18, -40)
        scroll:SetPoint("BOTTOMRIGHT", -36, 44)
        local bar = CreateFrame("Slider", "GatherpediaGlimmerDebugBar", scroll, "BackdropTemplate")
        bar:SetPoint("TOPRIGHT", f, "TOPRIGHT", -16, -40)
        bar:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -16, 44)
        bar:SetWidth(14)
        bar:SetOrientation("VERTICAL")
        bar:SetMinMaxValues(0, 1)
        bar:SetValue(0)
        bar:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = 1 })
        bar:SetBackdropColor(0.12, 0.10, 0.08, 1)
        bar:SetBackdropBorderColor(GOLD[1], GOLD[2], GOLD[3], 0.4)
        local thumb = bar:CreateTexture(nil, "ARTWORK")
        thumb:SetSize(12, 28)
        thumb:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], 0.7)
        bar:SetThumbTexture(thumb)

        local edit = CreateFrame("EditBox", "GatherpediaGlimmerDebugEdit", scroll)
        edit:SetMultiLine(true)
        edit:SetAutoFocus(false)
        if edit.SetFontObject then edit:SetFontObject("GatherpediaFontHighlightSmall") end
        edit:SetWidth(450)
        edit:SetTextInsets(4, 4, 4, 4)
        if edit.SetMaxLetters then edit:SetMaxLetters(20000) end
        if edit.SetAltArrowKeyMode then edit:SetAltArrowKeyMode(false) end
        edit:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
        edit:SetScript("OnKeyDown", function(self, key)
            if (key == "A" or key == "a") and IsControlKeyDown and IsControlKeyDown() then
                self:HighlightText()
            end
        end)
        scroll:SetScrollChild(edit)
        bar:SetScript("OnValueChanged", function(self, v)
            local range = scroll:GetVerticalScrollRange() or 0
            scroll:SetVerticalScroll(v * range)
        end)
        scroll:SetScript("OnMouseWheel", function(self, delta)
            local range = self:GetVerticalScrollRange() or 0
            local cur = self:GetVerticalScroll() or 0
            cur = cur - delta * 32
            if cur < 0 then cur = 0 elseif cur > range then cur = range end
            self:SetVerticalScroll(cur)
            if range > 0 then bar:SetValue(cur / range) end
        end)
        edit:SetScript("OnCursorChanged", function()
            local range = scroll:GetVerticalScrollRange() or 0
            if range > 0 then bar:SetValue((scroll:GetVerticalScroll() or 0) / range) end
        end)

        local refresh
        if ns.Chrome and ns.Chrome.MakeButton then
            refresh = ns.Chrome:MakeButton(f, 110, 24, "Refresh")
        else
            refresh = CreateFrame("Button", nil, f, "BackdropTemplate")
            refresh:SetSize(110, 24)
            refresh:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = 1,
                insets = { left = 1, right = 1, top = 1, bottom = 1 } })
            refresh:SetBackdropColor(GOLD[1], GOLD[2], GOLD[3], 0.12)
            refresh:SetBackdropBorderColor(GOLD[1], GOLD[2], GOLD[3], 0.75)
            local lab = Text(refresh, "GatherpediaFontNormal", "CENTER")
            lab:SetPoint("CENTER")
            lab:SetText("Refresh")
            lab:SetTextColor(GOLD[1], GOLD[2], GOLD[3])
        end
        refresh:SetPoint("BOTTOM", 0, 14)
        refresh:SetScript("OnClick", function() SparklesUI:RefreshDebugPanel(true) end)

        f.scroll, f.bar, f.edit, f.refresh = scroll, bar, edit, refresh
        tinsert(UISpecialFrames, "GatherpediaGlimmerDebug")
        self.debugPanel = f
    end
    self:RefreshDebugPanel(true)
    f:Show()
    f:Raise()
end

function SparklesUI:RefreshDebugPanel(selectAll)
    local f = self.debugPanel
    if not f or not f.edit then return end
    local lines = (ns.Sparkles and ns.Sparkles.DebugLines and ns.Sparkles:DebugLines()) or { "(no debug)" }
    local text = table.concat(lines, "\n")
    f.edit:SetText(text)
    -- Size the edit box to the text so the scroll frame can move.
    if f.edit.GetNumLetters and f.edit.SetHeight then
        local n = f.edit:GetNumLetters() or #text
        local h = math.max(320, math.floor(n / 8) * 4 + 40)
        f.edit:SetHeight(h)
    end
    if selectAll and f.edit.HighlightText then
        f.edit:HighlightText()
    end
    if f.edit.SetFocus then f.edit:SetFocus() end
    if f.scroll and f.scroll.SetVerticalScroll then f.scroll:SetVerticalScroll(0) end
    if f.bar and f.bar.SetValue then f.bar:SetValue(0) end
end
