-- HarvestMate Enhanced: Map/Overlay.lua
-- What HME draws on the world map besides route lines (Routes/Routes.lua):
--   * spawn pins: one per site (shared sites once), ringed in your skill color;
--     a site you or GatherMate2 confirmed is solid, a predicted one hollow
--   * hunting areas: shaded discs over each area of a skinning farm, with the
--     beast spawns as small dots
-- Shown while previewing a Farm Finder result, for the farm being followed,
-- or always for your professions when the setting is on.
--
-- The holder sits on the map canvas the way Gatherpedia's spawn pins did on
-- Forever (a child of WorldMapFrame.ScrollContainer.Child, redrawn after
-- SetMapID through hooksecurefunc). Pins are reused, and capped (600, or 250
-- in low-performance mode) so a dense zone never floods the map.
-- Copyright (C) 2026 HarvestMate Enhanced contributors. GPL-3.0-or-later.

local _, ns = ...
local HME = ns.HME
local U = HME.U
local SM = HME.SkillModel

local O = {}
HME.MapOverlay = O

local MEDIA = "Interface\\AddOns\\HarvestMateEnhanced\\Media\\"
local DISC = MEDIA .. "GP_Disc"
local RING = MEDIA .. "GP_Ring"

local holder
local pins, discs = {}, {}
local shown = {}   -- { mapID, kind = "preview"|"farm"|"always", result }

local function Canvas()
    local f = _G.WorldMapFrame
    if type(f) ~= "table" then return nil end
    local sc = rawget(f, "ScrollContainer")
    if type(sc) == "table" then
        local child = rawget(sc, "Child")
        return type(child) == "table" and child or sc
    end
    return f
end

local function CanvasScale()
    local sc = _G.WorldMapFrame and rawget(_G.WorldMapFrame, "ScrollContainer")
    if type(sc) == "table" and sc.GetCanvasScale then
        local ok, v = pcall(sc.GetCanvasScale, sc)
        if ok and HME.Num(v) and v > 0 then return v end
    end
    return 1
end

local function MaxPins()
    return (HME.settings and HME.settings.performance == "low") and 250 or 600
end

local function EnsureHolder()
    local canvas = Canvas()
    if not canvas then return nil end
    if not holder then
        holder = CreateFrame("Frame", nil, canvas)
        local last, acc = nil, 0
        holder:SetScript("OnUpdate", function(_, dt)
            acc = acc + dt
            if acc < 0.2 then return end
            acc = 0
            local s = CanvasScale()
            if s ~= last then
                last = s
                O.Draw()
            end
        end)
        if _G.WorldMapFrame.HookScript then
            _G.WorldMapFrame:HookScript("OnHide", function()
                if shown.kind == "preview" then shown = {} end
                O.Hide()
            end)
        end
        if hooksecurefunc and _G.WorldMapFrame.SetMapID then
            hooksecurefunc(_G.WorldMapFrame, "SetMapID", function() HME.After(0, O.Draw) end)
        end
    end
    if holder:GetParent() ~= canvas then holder:SetParent(canvas) end
    holder:ClearAllPoints()
    holder:SetAllPoints(canvas)
    holder:SetFrameStrata("HIGH")
    holder:SetFrameLevel((canvas:GetFrameLevel() or 1) + 100)
    holder:Show()
    return holder
end

local function Pin(i)
    local p = pins[i]
    if p then return p end
    p = CreateFrame("Frame", nil, holder)
    p.ring = p:CreateTexture(nil, "ARTWORK")
    p.ring:SetAllPoints()
    p.ring:SetTexture(RING)
    p.dot = p:CreateTexture(nil, "OVERLAY")
    p.dot:SetPoint("CENTER")
    p.dot:SetTexture(DISC)
    p:EnableMouse(true)
    p:SetScript("OnEnter", function(self)
        if not self.tip then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        for i2, line in ipairs(self.tip) do
            if i2 == 1 then GameTooltip:AddLine(line) else GameTooltip:AddLine(line, 1, 1, 1, true) end
        end
        GameTooltip:Show()
    end)
    p:SetScript("OnLeave", function() GameTooltip:Hide() end)
    pins[i] = p
    return p
end

local function Disc(i)
    local d = discs[i]
    if d then return d end
    d = holder:CreateTexture(nil, "BACKGROUND")
    d:SetTexture(DISC)
    discs[i] = d
    return d
end

function O.Hide()
    for _, p in ipairs(pins) do p:Hide() end
    for _, d in ipairs(discs) do d:Hide() end
end

-- What to draw for the map on screen: a list of { x, y, r, g, b, solid, tip }
-- pins and { x, y, radius (map units), r, g, b } discs.
local function Collect(mapID)
    local out = { pins = {}, discs = {} }
    local s = HME.settings or {}
    local profile = HME.Player.Profile()
    local function addSites(prof, filter, area)
        local skill = profile.skills[prof] and profile.skills[prof].rank
        for _, site in ipairs(HME.Spawns.Sites(prof, mapID)) do
            local inside = not area or HME.Geo.Distance(mapID, site.x, site.y, area.x, area.y) <= area.r
            if inside then
                local bestReq, names = nil, {}
                for name in pairs(site.types) do
                    if not filter or filter[name] then
                        local req = HME.Spawns.Required(prof, name) or 1
                        if not bestReq or req < bestReq then bestReq = req end
                        names[#names + 1] = ("%s (%d)"):format(name, req)
                    end
                end
                if bestReq then
                    local color = skill and SM.Color(skill, bestReq) or "yellow"
                    local c = SM.COLORS[color]
                    table.sort(names)
                    local src = site.confirmed and "confirmed (you or GatherMate2)" or "predicted spawn point"
                    out.pins[#out.pins + 1] = { site.x, site.y, c[1], c[2], c[3], site.confirmed,
                        { table.concat(names, ", "), src } }
                end
            end
        end
    end
    local function addHunt(planned, result)
        local skill = profile.skills.Skinning and profile.skills.Skinning.rank or 0
        local w = HME.Geo.MapYards(mapID) or 1500
        for _, a in ipairs(planned.areas or {}) do
            out.discs[#out.discs + 1] = { a.x, a.y, (a.r + 20) / w, 0.85, 0.42, 0.32 }
        end
        local want = {}
        for _, id in ipairs(planned.beasts or {}) do want[id] = true end
        for _, b in ipairs(HME.Spawns.BeastPoints(mapID)) do
            if want[b.npcID] then
                local lvl = math.floor((b.min + b.max) / 2 + 0.5)
                local c = SM.COLORS[SM.Color(skill, SM.SkinReq(lvl)) or "grey"]
                for _, p in ipairs(b.pts) do
                    out.pins[#out.pins + 1] = { p[1], p[2], c[1], c[2], c[3], false,
                        { ("%s (level %d-%d)"):format(b.name, b.min, b.max),
                          ("needs %d Skinning · a spawn point, not a live beast"):format(SM.SkinReq(b.max)) }, true }
                end
            end
        end
    end
    -- Preview or the active farm on this map
    local result = shown.result
    local planned
    if result and result.mapID == mapID then
        planned = HME.Planner.Describe(result, "preview")
    else
        local g = HME.Guidance.Active()
        if g and g.mapID == mapID and g.planned then planned = g.planned end
    end
    if planned then
        if planned.prof == "Skinning" then
            if s.huntAreas ~= false then addHunt(planned, result) end
        elseif planned.prof and planned.prof ~= "Fishing" then
            local area = { x = planned.cx, y = planned.cy, r = ((planned.radius or 300) * 1.25 + 60) / ((HME.Geo.MapYards(mapID)) or 1500) }
            addSites(planned.prof, planned.types, { x = planned.cx, y = planned.cy, r = (planned.radius or 300) * 1.25 + 60 })
        else
            addSites("Fishing")
        end
    elseif s.nodePinsAlways then
        for prof in pairs(profile.skills) do
            if prof ~= "Skinning" then addSites(prof) end
        end
    end
    return out
end

function O.Draw()
    local map = _G.WorldMapFrame
    if not (map and map:IsShown()) then return end
    local mapID = map.GetMapID and map:GetMapID()
    if not mapID or (not shown.result and not HME.Guidance.Active() and not (HME.settings and HME.settings.nodePinsAlways)) then
        O.Hide()
        return
    end
    if HME.settings and HME.settings.nodePins == false and shown.kind ~= "preview" then
        O.Hide()
        return
    end
    local h = EnsureHolder()
    if not h then return end
    local t0 = HME.Clock()
    local W, H = h:GetWidth(), h:GetHeight()
    if not W or W == 0 then
        HME.After(0.1, O.Draw)
        return
    end
    local data = Collect(mapID)
    local scale = CanvasScale()
    local size = math.max(6, 11 / scale) * ((HME.settings and HME.settings.pinScale) or 1)
    local alpha = ((HME.settings and HME.settings.huntAlpha) or 30) / 100
    local nd = 0
    for _, dsc in ipairs(data.discs) do
        nd = nd + 1
        local d = Disc(nd)
        local r = dsc[3] * W
        d:SetSize(r * 2, r * 2)
        d:ClearAllPoints()
        d:SetPoint("CENTER", h, "TOPLEFT", dsc[1] * W, -dsc[2] * H)
        d:SetVertexColor(dsc[4], dsc[5], dsc[6], alpha)
        d:Show()
    end
    for i = nd + 1, #discs do discs[i]:Hide() end
    local limit = MaxPins()
    local n = 0
    for _, p in ipairs(data.pins) do
        if n >= limit then break end
        n = n + 1
        local pin = Pin(n)
        local sz = p[8] and size * 0.6 or size
        pin:SetSize(sz, sz)
        pin.dot:SetSize(sz * 0.55, sz * 0.55)
        pin:ClearAllPoints()
        pin:SetPoint("CENTER", h, "TOPLEFT", p[1] * W, -p[2] * H)
        pin.ring:SetVertexColor(p[3], p[4], p[5], 1)
        pin.dot:SetVertexColor(p[3], p[4], p[5], p[6] and 1 or 0.25)
        pin.tip = p[7]
        pin:Show()
    end
    for i = n + 1, #pins do pins[i]:Hide() end
    O.lastCount = n
    O.truncated = #data.pins > limit
    HME.Perf.Add("overlay:draw", HME.Clock() - t0)
end

-- Opens the world map on a Farm Finder result and shows it.
function O.Preview(result)
    shown = { kind = "preview", result = result }
    if HME.InCombat() then
        HME.Print("the map preview opens after the fight (the world map can't be opened in combat).")
        return
    end
    if _G.OpenWorldMap then pcall(_G.OpenWorldMap, result.mapID) end
    if _G.WorldMapFrame and _G.WorldMapFrame.SetMapID then pcall(_G.WorldMapFrame.SetMapID, _G.WorldMapFrame, result.mapID) end
    O.Draw()
end

function O.ClearPreview()
    shown = {}
    O.Draw()
end

HME.Listen("GUIDANCE_CHANGED", function() O.Draw() end)
HME.Listen("SETTINGS", function() O.Draw() end)
