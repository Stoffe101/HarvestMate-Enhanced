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

-- Profession colours for the pin centres (the ring is your skill colour).
O.PROF_COLOR = { Herbalism = { 0.40, 0.85, 0.35 }, Mining = { 0.92, 0.60, 0.25 }, Fishing = { 0.35, 0.68, 1.00 },
    Skinning = { 0.92, 0.38, 0.30 } }
O.CROWD_PX = 22    -- pins closer than this on screen become one pin with a count

local lines, labels = {}, {}

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
    p.count = p:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    p.count:SetPoint("CENTER")
    p:EnableMouse(true)
    p:SetScript("OnEnter", function(self)
        if not self.tip then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        for i2, line in ipairs(self.tip) do
            if i2 == 1 then GameTooltip:AddLine(line) else GameTooltip:AddLine(line, 1, 1, 1, true) end
        end
        if self.fix then GameTooltip:AddLine("Right-click: " .. self.fix.label, 0.7, 0.7, 0.7) end
        if self.fix2 then GameTooltip:AddLine("Shift+right-click: " .. self.fix2.label, 0.7, 0.7, 0.7) end
        GameTooltip:Show()
    end)
    p:SetScript("OnLeave", function() GameTooltip:Hide() end)
    -- Corrections: a wrong or unreachable spawn point, or a wrong beast.
    p:SetScript("OnMouseUp", function(self, button)
        if button ~= "RightButton" or not self.fix or HME.InCombat() then return end
        if self.fix2 and IsShiftKeyDown and IsShiftKeyDown() then self.fix2.run() else self.fix.run() end
        GameTooltip:Hide()
        O.Draw()
    end)
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

local function Line(i)
    local l = lines[i]
    if l then return l end
    l = holder:CreateLine(nil, "ARTWORK")
    l:SetColorTexture(1, 1, 1, 1)
    lines[i] = l
    return l
end

local function Label(i)
    local l = labels[i]
    if l then return l end
    l = holder:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    labels[i] = l
    return l
end

function O.Hide()
    for _, p in ipairs(pins) do p:Hide() end
    for _, d in ipairs(discs) do d:Hide() end
    for _, l in ipairs(lines) do l:Hide() end
    for _, l in ipairs(labels) do l:Hide() end
end

-- What to draw on a map:
--   pins   { x, y, ring rgb, prof rgb, solid, tip, small, fix }
--   discs  { x, y, radius (map share), rgb, alpha }
--   outlines { { x1, y1, x2, y2, ... }, rgb }
--   labels { x, y, text }
local function Collect(mapID)
    local out = { pins = {}, discs = {}, outlines = {}, labels = {} }
    local s = HME.settings or {}
    local detail = s.mapDetail or "detailed"
    local profile = HME.Player.Profile()
    local W = HME.Geo.MapYards(mapID) or 1500
    local function addSites(prof, filter, area)
        local skill = profile.skills[prof] and profile.skills[prof].rank
        local pc = O.PROF_COLOR[prof] or { 1, 1, 1 }
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
                    local ckey = skill and SM.Color(skill, bestReq) or "yellow"
                    local c = SM.COLORS[ckey]
                    table.sort(names)
                    local src = site.confirmed and "confirmed by you or GatherMate2" or "a predicted spawn point (bundled data)"
                    out.pins[#out.pins + 1] = { site.x, site.y, c, pc, site.confirmed, { table.concat(names, ", "), src },
                        false, { label = "mark this spawn point wrong or unreachable", run = function()
                            HME.Spawns.Exclude(prof, mapID, site.x, site.y, true)
                            HME.Print("spawn point left out of routes and rankings (Settings, Your data to see the count).")
                        end }, { label = "it is in a cave: its entrance is where I stand", run = function()
                            local pm, px, py = HME.Player.Position()
                            local zm, zx, zy = HME.Geo.ZoneOf(pm, px, py)
                            if zm ~= mapID or not zx then
                                HME.Print("stand at the cave's mouth in this zone, then Shift+right-click a node inside.")
                                return
                            end
                            HME.Caves.Mark(mapID, site.x, site.y, zx, zy)
                            HME.Print(("cave marked: nodes within %d yards of that one are entered here. Routes go through it."):format(HME.Caves.CAVE_YARDS))
                        end }, ckey }
                end
            end
        end
    end
    local function addHunt(planned)
        local skill = profile.skills.Skinning and profile.skills.Skinning.rank or 0
        local pc = O.PROF_COLOR.Skinning
        for i, a in ipairs(planned.areas or {}) do
            -- A light fill and a clear boundary, not a big opaque circle.
            out.discs[#out.discs + 1] = { a.x, a.y, (a.r + 15) / W, pc, 0.35 }
            if a.hull and #a.hull >= 6 then out.outlines[#out.outlines + 1] = { a.hull, pc } end
            out.labels[#out.labels + 1] = { a.x, a.y - (a.r + 25) / W, ("Area %d · %d spawns"):format(i, a.spawns or 0) }
        end
        if detail == "simple" then return end
        local want = {}
        for _, id in ipairs(planned.beasts or {}) do want[id] = true end
        for _, b in ipairs(HME.Spawns.BeastPoints(mapID)) do
            if want[b.npcID] then
                local lvl = math.floor((b.min + b.max) / 2 + 0.5)
                local c = SM.COLORS[SM.Color(skill, SM.SkinReq(lvl)) or "grey"]
                local known = HME.Spawns.Skinnable(b.npcID)
                for _, p in ipairs(b.pts) do
                    out.pins[#out.pins + 1] = { p[1], p[2], c, pc, known == true,
                        { ("%s (level %d-%d)"):format(b.name, b.min, b.max),
                          ("%d+ Skinning · a spawn point, not a live beast%s"):format(SM.SkinReq(b.min),
                              known == nil and " · not yet checked in game" or "") }, true,
                        { label = "mark: this beast does not spawn here (this spot only)", run = function()
                            local c = HME.Corrections.Add("notHere", { mapID = mapID, x = p[1], y = p[2], npcID = b.npcID, name = b.name })
                            if c then
                                HME.Print(("%s: left out within %d yards of here. Undo: /hme corrections."):format(b.name, HME.Corrections.SPOT_YARDS))
                            end
                        end } }
                end
            end
        end
    end
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
            if s.huntAreas ~= false then addHunt(planned) end
        elseif planned.prof == "Fishing" then
            addSites("Fishing")
        elseif planned.prof then
            -- (A plan without a centre, such as an older saved one, shows the whole map's sites.)
            local area = planned.cx and planned.cy and { x = planned.cx, y = planned.cy, r = (planned.radius or 300) * 1.25 + 60 } or nil
            for _, p in ipairs(HME.Gathering.Profs(planned.prof)) do
                if detail ~= "simple" then addSites(p, planned.types, area) end
            end
            if area then
                out.discs[#out.discs + 1] = { planned.cx, planned.cy, area.r / W, O.PROF_COLOR[planned.prof] or { 1, 0.82, 0 }, 0.15 }
            end
        end
    elseif s.nodePinsAlways then
        for prof in pairs(profile.skills) do
            if prof ~= "Skinning" then addSites(prof) end
        end
    end
    -- The farm being followed: where the loop starts.
    local g = HME.Guidance.Active()
    if g and g.mapID == mapID then
        local route = HME.Guidance.Route(g.routeID)
        local stops = route and HME.Guidance.Stops(route) or {}
        if stops[1] then out.labels[#out.labels + 1] = { stops[1][1], stops[1][2] - 0.012, "Start", true } end
    end
    return out
end
O.Collect = Collect

-- Heatmap: spawn points counted on a grid; confirmed points weigh full,
-- predicted ones half (lighter where the data is unconfirmed).
-- Heatmap views (Settings > Heatmap shows). None of them is live: the label
-- on the map says what is shown.
--   density   predicted spawn density (bundled data; confirmed sites weigh more)
--   observed  where YOU gathered (your own node observations)
--   skill     density weighted by skill-up chance for you (orange 1, yellow
--             0.75, green 0.35, grey 0)
O.HEAT_VIEWS = { "density", "observed", "skill" }
O.HEAT_LABEL = { density = "Heatmap: predicted spawn density (bundled data), not live nodes",
                 observed = "Heatmap: where you have gathered (your observations), not live nodes",
                 skill = "Heatmap: spawn density weighted by your skill-up chance, not live nodes" }
local SKILL_W = { orange = 1, yellow = 0.75, green = 0.35, grey = 0, red = 0 }

local function Heat(data, W, H, view, mapID)
    local cell = 0.03
    local grid, maxv = {}, 0
    local function Add(x, y, w, c)
        if w <= 0 then return end
        local k = math.floor(x / cell) .. ":" .. math.floor(y / cell)
        local e = grid[k]
        if not e then
            e = { x = (math.floor(x / cell) + 0.5) * cell, y = (math.floor(y / cell) + 0.5) * cell, v = 0, c = c }
            grid[k] = e
        end
        e.v = e.v + w
        if e.v > maxv then maxv = e.v end
    end
    if view == "observed" then
        local cells = HME.db and HME.db.obs.nodes[mapID] or {}
        for _, rec in pairs(cells) do
            if type(rec) == "table" and rec.x and rec.y then
                Add(rec.x, rec.y, rec.c or 1, O.PROF_COLOR[rec.p] or { 1, 0.82, 0 })
            end
        end
    else
        for _, p in ipairs(data.pins) do
            local w = p[5] and 1 or 0.5
            if view == "skill" then w = SKILL_W[p[10] or "yellow"] or 0.5 end
            Add(p[1], p[2], w, p[4])
        end
    end
    local out = {}
    for _, e in pairs(grid) do out[#out + 1] = { e.x, e.y, cell * 0.75, e.c, 0.15 + 0.6 * e.v / math.max(maxv, 1) } end
    return out, maxv
end
O.Heat = Heat

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
    local s = HME.settings or {}
    local scale = CanvasScale()
    local size = math.max(6, 11 / scale) * (s.pinScale or 1)
    local alphaScale = (s.huntAlpha or 30) / 100
    if s.mapDetail == "heatmap" then
        local view = s.heatView or "density"
        local heat = Heat(data, W, H, view, mapID)
        for _, d in ipairs(heat) do data.discs[#data.discs + 1] = d end
        data.pins = {}
        data.labels[#data.labels + 1] = { 0.5, 0.03, (#heat > 0 and O.HEAT_LABEL[view])
            or (view == "observed" and "Heatmap: you have not gathered here yet" or "Heatmap: nothing to show here") }
    end
    -- Discs (fills)
    local nd = 0
    for _, dsc in ipairs(data.discs) do
        nd = nd + 1
        local d = Disc(nd)
        local r = dsc[3] * W
        d:SetSize(r * 2, r * 2)
        d:ClearAllPoints()
        d:SetPoint("CENTER", h, "TOPLEFT", dsc[1] * W, -dsc[2] * H)
        d:SetVertexColor(dsc[4][1], dsc[4][2], dsc[4][3], (dsc[5] or 0.3) * alphaScale)
        d:Show()
    end
    for i = nd + 1, #discs do discs[i]:Hide() end
    -- Outlines (hunting-area boundaries)
    local nl = 0
    for _, o in ipairs(data.outlines) do
        local poly, c = o[1], o[2]
        local n = #poly / 2
        for i = 1, n do
            local j = i % n + 1
            nl = nl + 1
            local l = Line(nl)
            l:SetStartPoint("TOPLEFT", h, poly[2 * i - 1] * W, -poly[2 * i] * H)
            l:SetEndPoint("TOPLEFT", h, poly[2 * j - 1] * W, -poly[2 * j] * H)
            l:SetThickness(math.max(1.5, 2 / scale))
            l:SetVertexColor(c[1], c[2], c[3], 0.75)
            l:Show()
        end
    end
    for i = nl + 1, #lines do lines[i]:Hide() end
    -- Labels
    for i, lb in ipairs(data.labels) do
        local l = Label(i)
        l:ClearAllPoints()
        l:SetPoint("CENTER", h, "TOPLEFT", lb[1] * W, -lb[2] * H)
        l:SetText(lb[3])
        l:SetTextColor(lb[4] and 0.3 or 1, lb[4] and 1 or 0.82, lb[4] and 0.4 or 0.3)
        l:Show()
    end
    for i = #data.labels + 1, #labels do labels[i]:Hide() end
    -- Pins, grouped where they crowd on screen.
    local limit = MaxPins()
    local crowd = O.CROWD_PX * scale
    local cells = {}
    local groups = {}
    for _, p in ipairs(data.pins) do
        local k = math.floor(p[1] * W / crowd) .. ":" .. math.floor(p[2] * H / crowd)
        local g = cells[k]
        if not g then
            g = { p = p, n = 0 }
            cells[k] = g
            groups[#groups + 1] = g
        end
        g.n = g.n + 1
        if p[5] then g.confirmed = (g.confirmed or 0) + 1 end
    end
    local n = 0
    for _, g in ipairs(groups) do
        if n >= limit then break end
        n = n + 1
        local p = g.p
        local pin = Pin(n)
        local sz = (p[7] and size * 0.65 or size) * (g.n > 1 and 1.35 or 1)
        pin:SetSize(sz, sz)
        pin.dot:SetSize(sz * 0.55, sz * 0.55)
        pin:ClearAllPoints()
        pin:SetPoint("CENTER", h, "TOPLEFT", p[1] * W, -p[2] * H)
        pin.ring:SetVertexColor(p[3][1], p[3][2], p[3][3], 1)
        pin.dot:SetVertexColor(p[4][1], p[4][2], p[4][3], p[5] and 1 or 0.3)
        pin.count:SetText(g.n > 1 and tostring(g.n) or "")
        if g.n > 1 then
            pin.tip = { ("%d spawn points here"):format(g.n), ("%d confirmed, %d predicted. Zoom in to see each."):format(
                g.confirmed or 0, g.n - (g.confirmed or 0)) }
            pin.fix, pin.fix2 = nil, nil
        else
            pin.tip, pin.fix, pin.fix2 = p[6], p[8], p[9]
        end
        pin:Show()
    end
    for i = n + 1, #pins do pins[i]:Hide() end
    O.lastCount = n
    O.lastGroups = #groups
    O.truncated = #groups > limit
    HME.Perf.Add("overlay:draw", HME.Clock() - t0)
end

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
