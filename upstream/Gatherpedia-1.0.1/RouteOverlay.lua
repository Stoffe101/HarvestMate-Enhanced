-- Gatherpedia: RouteOverlay.lua
-- The active farm route, on the world map and the minimap, as a thin
-- light-grey/white loop. A small gold marker sits on the current stop.
-- When the travel-direction option is on, a short translucent dark
-- dash slides along the path in travel order. No glow, no chevrons,
-- no pulsing halo. No Blizzard user-waypoint or SuperTrack APIs.

local ADDON_NAME, ns = ...

local Overlay = {}
ns.RouteOverlay = Overlay

-- Minimap diameter in yards for zoom levels 0-5.
local OUTDOOR = { 466 + 2 / 3, 400, 333 + 1 / 3, 266 + 2 / 3, 200, 133 + 1 / 3 }
local INDOOR  = { 300, 240, 180, 120, 80, 50 }

local DOT_NEXT = "Interface\\COMMON\\Indicator-Yellow"
local LINE_RGB = { 0.92, 0.92, 0.90 }
-- Pulse period is derived from on-screen length, then clamped.
local PULSE_MIN, PULSE_MAX = 6, 10
local PULSE_PX_PER_SEC = 120

local function PCall(fn, ...)
    if not fn then return nil end
    local ok, a, b, c, d = pcall(fn, ...)
    if ok then return a, b, c, d end
    return nil
end

local function SafeFrame(kind, name, parent, template)
    if template then
        local ok, f = pcall(CreateFrame, kind, name, parent, template)
        if ok and f then return f end
    end
    local ok, f = pcall(CreateFrame, kind, name, parent)
    if ok then return f end
    return nil
end

function Overlay:FlowEnabled()
    local o = ns.db and ns.db.options
    if o and o.routeFlow == false then return false end
    return true
end

local function Active()
    return ns.Arrow and ns.Arrow.active
end

-- World position of a map point. x, y are 0-100 map percent.
local function WorldPos(mapID, x, y)
    if not (C_Map and C_Map.GetWorldPosFromMapPos and mapID and x and y) then return end
    local vec
    if CreateVector2D then
        vec = CreateVector2D(x / 100, y / 100)
    else
        vec = { x = x / 100, y = y / 100 }
    end
    local continent, world = PCall(C_Map.GetWorldPosFromMapPos, mapID, vec)
    if not world then return end
    local wx, wy
    if world.GetXY then
        wx, wy = PCall(world.GetXY, world)
    end
    if not wx and world.x then wx, wy = world.x, world.y end
    if wx and wy then return continent, wx, wy end
end

local function PlayerWorld()
    local arrow = ns.Arrow
    if not arrow or not arrow.PlayerMapXY then return end
    local px, py, pMap = arrow:PlayerMapXY()
    if not px or not py then return end
    return WorldPos(pMap or (arrow.active and arrow.active.mapID), px * 100, py * 100)
end

-- Cached world positions of the active route's stops.
local function RouteWorld()
    local a = Active()
    if not a or not a.route then return nil end
    if not a.world then
        a.world = {}
        for i, s in ipairs(a.drawRoute or a.route) do
            local c, x, y = WorldPos(a.mapID, s.x, s.y)
            if c then a.world[i] = { c = c, x = x, y = y } end
        end
    end
    return a.world
end

---------------------------------------------------------------------------
-- Clipping helpers (segments must stay inside the minimap)
---------------------------------------------------------------------------

-- Clip segment A-B to a circle of radius r around the origin.
local function ClipCircle(x1, y1, x2, y2, r)
    local dx, dy = x2 - x1, y2 - y1
    local a = dx * dx + dy * dy
    if a == 0 then return nil end
    local b = 2 * (x1 * dx + y1 * dy)
    local c = x1 * x1 + y1 * y1 - r * r
    local disc = b * b - 4 * a * c
    if disc <= 0 then return nil end
    local sq = math.sqrt(disc)
    local t1, t2 = (-b - sq) / (2 * a), (-b + sq) / (2 * a)
    t1, t2 = math.max(t1, 0), math.min(t2, 1)
    if t1 >= t2 then return nil end
    return x1 + dx * t1, y1 + dy * t1, x1 + dx * t2, y1 + dy * t2
end

-- Clip segment A-B to the square [-h, h] x [-h, h] (Liang-Barsky).
local function ClipSquare(x1, y1, x2, y2, h)
    local dx, dy = x2 - x1, y2 - y1
    local t1, t2 = 0, 1
    local p = { -dx, dx, -dy, dy }
    local q = { x1 + h, h - x1, y1 + h, h - y1 }
    for i = 1, 4 do
        if p[i] == 0 then
            if q[i] < 0 then return nil end
        else
            local t = q[i] / p[i]
            if p[i] < 0 then t1 = math.max(t1, t) else t2 = math.min(t2, t) end
        end
    end
    if t1 >= t2 then return nil end
    return x1 + dx * t1, y1 + dy * t1, x1 + dx * t2, y1 + dy * t2
end

---------------------------------------------------------------------------
-- Pools
---------------------------------------------------------------------------

local function GetPin(holder, i, layer)
    holder.pins = holder.pins or {}
    local p = holder.pins[i]
    -- Route stops use a small Indicator-Yellow texture.
    if p and not p.SetTexture then
        if p.Hide then p:Hide() end
        p = nil
    end
    if not p then
        if holder.CreateTexture then
            p = holder:CreateTexture(nil, layer or "OVERLAY")
        end
        holder.pins[i] = p
    end
    return p
end

-- Rotated textures are the default: CreateLine/SetStartPoint is missing
-- or silent on some 1.60.1 map frames, which left the path invisible.
local function GetLine(holder, i, pool, layer)
    pool = pool or "lines"
    holder[pool] = holder[pool] or {}
    local l = holder[pool][i]
    if not l then
        if holder.CreateTexture then
            l = holder:CreateTexture(nil, layer or "ARTWORK")
            if l then
                l._tex = true
                if l.SetDrawLayer then pcall(l.SetDrawLayer, l, layer or "ARTWORK", 7) end
            end
        end
        if not l and holder.CreateLine then
            local ok, line = pcall(holder.CreateLine, holder, nil, layer or "ARTWORK")
            if ok and line and line.SetStartPoint then l = line end
        end
        holder[pool][i] = l
    end
    return l
end

local function HideFrom(list, first)
    if not list then return end
    for i = first, #list do
        if list[i] and list[i].Hide then list[i]:Hide() end
    end
end

local function Note(msg)
    Overlay._errors = Overlay._errors or {}
    Overlay._errors[#Overlay._errors + 1] = tostring(msg)
end

local function PaintTex(tex, r, g, b, a)
    if not tex then return false end
    if tex.SetColorTexture then
        local ok = pcall(tex.SetColorTexture, tex, r, g, b, a)
        if ok then return true end
    end
    if tex.SetTexture then
        pcall(tex.SetTexture, tex, "Interface\\Buttons\\WHITE8X8")
        if tex.SetVertexColor then pcall(tex.SetVertexColor, tex, r, g, b, a) end
        if tex.SetAlpha then pcall(tex.SetAlpha, tex, a) end
        return true
    end
    return false
end

local function ApplyGradient(line, r, g, b, a1, a2)
    if not line or not a2 then return end
    if line.SetGradientAlpha then
        pcall(line.SetGradientAlpha, line, "HORIZONTAL", r, g, b, a1, r, g, b, a2)
    elseif line.SetGradient and CreateColor then
        pcall(line.SetGradient, line, "HORIZONTAL", CreateColor(r, g, b, a1), CreateColor(r, g, b, a2))
    end
end

-- Place a line. Prefer a rotated texture so the path stays visible on
-- clients where CreateLine exists but does not actually paint.
local function PlaceLine(line, thickness, r, g, b, a, anchor, rel, x1, y1, x2, y2, a2)
    if not line then return false end
    local dx, dy = x2 - x1, y2 - y1
    local len = math.sqrt(dx * dx + dy * dy)
    if len < 0.5 then
        if line.Hide then line:Hide() end
        return false
    end
    if line._tex or not line.SetStartPoint then
        if not line.SetSize then
            Note("line texture has no SetSize")
            return false
        end
        PaintTex(line, r, g, b, a)
        if line.ClearAllPoints then line:ClearAllPoints() end
        line:SetSize(len, math.max(2, thickness))
        line:SetPoint("CENTER", rel, anchor, (x1 + x2) / 2, (y1 + y2) / 2)
        local ok
        if line.SetRotation then
            ok = pcall(line.SetRotation, line, math.atan2(dy, dx))
        end
        if not ok then
            Note("SetRotation failed or missing; line may be axis-aligned")
        end
        Overlay._lineMethod = ok and "rotated texture" or "texture (no SetRotation)"
        if a2 then ApplyGradient(line, r, g, b, a, a2) end
        line:Show()
        return true
    end
    if line.SetThickness then pcall(line.SetThickness, line, thickness) end
    if line.SetColorTexture then
        pcall(line.SetColorTexture, line, r, g, b, a)
    elseif line.SetColor then
        pcall(line.SetColor, line, r, g, b, a)
    end
    line:SetStartPoint(anchor, rel, x1, y1)
    line:SetEndPoint(anchor, rel, x2, y2)
    Overlay._lineMethod = "CreateLine"
    if a2 then ApplyGradient(line, r, g, b, a, a2) end
    line:Show()
    return true
end

-- Extend a segment a little past each end so corners overlap instead of gapping.
local function Extend(x1, y1, x2, y2, pad)
    local dx, dy = x2 - x1, y2 - y1
    local len = math.sqrt(dx * dx + dy * dy)
    if len < 0.5 then return x1, y1, x2, y2 end
    local ux, uy = dx / len, dy / len
    return x1 - ux * pad, y1 - uy * pad, x2 + ux * pad, y2 + uy * pad
end

-- Thin light line with a hairline dark underlay for contrast. No glow.
local function Segment(holder, n, x1, y1, x2, y2, thickness, anchor, rel)
    local c = LINE_RGB
    local pad = thickness * 0.5
    local ex1, ey1, ex2, ey2 = Extend(x1, y1, x2, y2, pad)
    local sh = GetLine(holder, n, "shadows", "BACKGROUND")
    PlaceLine(sh, thickness + 1.2, 0, 0, 0, 0.28, anchor, rel, ex1, ey1, ex2, ey2)
    local line = GetLine(holder, n, "lines", "ARTWORK")
    PlaceLine(line, thickness, c[1], c[2], c[3], 0.94, anchor, rel, ex1, ey1, ex2, ey2)
end

-- Soft square caps at each stop so joints stay filled and smooth.
local function PlaceCap(holder, i, pool, layer, x, y, size, r, g, b, a, rel, anchor)
    local tex = GetLine(holder, i, pool, layer)
    if not tex then return end
    PaintTex(tex, r, g, b, a)
    if tex.SetRotation then pcall(tex.SetRotation, tex, 0) end
    if tex.ClearAllPoints then tex:ClearAllPoints() end
    if tex.SetSize then tex:SetSize(size, size) end
    tex:SetPoint("CENTER", rel, anchor, x, y)
    tex:Show()
end

local function DrawJoints(holder, pts, thickness, anchor, rel, inside)
    local n = 0
    for _, P in pairs(pts) do
        local x, y = P[1], P[2]
        if x and (not inside or inside(x, y)) then
            n = n + 1
            PlaceCap(holder, n, "shadowCaps", "BACKGROUND", x, y, thickness + 1.2, 0, 0, 0, 0.28, rel, anchor)
            PlaceCap(holder, n, "caps", "ARTWORK", x, y, thickness * 1.05, LINE_RGB[1], LINE_RGB[2], LINE_RGB[3], 0.95, rel, anchor)
        end
    end
    HideFrom(holder.shadowCaps, n + 1)
    HideFrom(holder.glowCaps, 1)
    HideFrom(holder.caps, n + 1)
end

-- Every consecutive pair, plus the closing segment back to stop 1
-- unless the data already repeats the first point at the end.
local function SegmentPairs(route, routeType)
    local n = #route
    local pairs_ = {}
    if n < 2 then return pairs_ end
    for i = 1, n - 1 do
        pairs_[#pairs_ + 1] = { i, i + 1 }
    end
    -- Back-and-forth routes are drawn open; loops close unless the
    -- first point is already repeated at the end.
    if routeType ~= "backforth" then
        local first, last = route[1], route[n]
        if not (first.x == last.x and first.y == last.y) then
            pairs_[#pairs_ + 1] = { n, 1 }
        end
    end
    return pairs_
end
Overlay.SegmentPairs = SegmentPairs

local function PointAlong(segs, dist)
    local d = dist
    for i = 1, #segs do
        local s = segs[i]
        if d <= s.len then
            local t = (s.len > 0) and (d / s.len) or 0
            return s.x1 + (s.x2 - s.x1) * t,
                   s.y1 + (s.y2 - s.y1) * t,
                   s.x2 - s.x1, s.y2 - s.y1
        end
        d = d - s.len
    end
    local s = segs[#segs]
    return s.x2, s.y2, s.x2 - s.x1, s.y2 - s.y1
end

local function PathLength(segs)
    local total = 0
    for i = 1, #segs do total = total + segs[i].len end
    return total
end

local function SampleAlong(segs, dist, total)
    if not segs or #segs == 0 or not total or total <= 0 then return end
    local d = dist % total
    if d < 0 then d = d + total end
    return PointAlong(segs, d)
end

-- Constant on-screen speed, clamped to a 6-10 second lap.
local function PulsePeriod(total)
    if total <= 0 then return PULSE_MAX end
    local p = total / PULSE_PX_PER_SEC
    if p < PULSE_MIN then p = PULSE_MIN end
    if p > PULSE_MAX then p = PULSE_MAX end
    return p
end

local LINE_POOLS = {
    "pins", "lines", "shadows", "glows",
    "caps", "glowCaps", "shadowCaps",
    "pulses", "pulseGlows", "pulseHeads", "chevrons",
}

local function HideDrawn(holder)
    if not holder then return end
    for i = 1, #LINE_POOLS do
        HideFrom(holder[LINE_POOLS[i]], 1)
    end
end

local function HideLeftoverLines(holder, nLines)
    HideFrom(holder.lines, nLines + 1)
    HideFrom(holder.shadows, nLines + 1)
    HideFrom(holder.glows, 1)
    HideFrom(holder.glowCaps, 1)
end

local function HideMotion(holder)
    HideFrom(holder.pulses, 1)
    HideFrom(holder.pulseGlows, 1)
    HideFrom(holder.pulseHeads, 1)
    HideFrom(holder.chevrons, 1)
end

local function TickInterval()
    if Overlay:FlowEnabled() and Active() then return 0.04 end
    return 0.15
end

-- A short translucent dark dash sliding along the path in travel order.
-- No glow, no chevron, no fading bright tail.
local function DrawDash(holder, segs, thickness, dashLen, anchor, rel, inside)
    HideMotion(holder)
    if not Overlay:FlowEnabled() or not segs or #segs == 0 then
        return
    end
    local total = PathLength(segs)
    if total < 16 then
        return
    end
    local period = PulsePeriod(total)
    local len = math.max(18, math.min(dashLen or 36, total * 0.16))
    local t = (GetTime and GetTime()) or 0
    local a = Active()
    local ping = a and a.routeType == "backforth"
    local lap = ping and (total * 2) or total
    local raw = ((t / period) % 1) * lap
    local pieces = 4
    local step = len / pieces
    -- Dark grey over the light line, alpha 0.35-0.5, so the dash reads
    -- as a short darker segment rather than a glow.
    local r, g, b, alpha = 0.10, 0.10, 0.10, 0.42
    local used = 0

    local function PathDist(d)
        if not ping then
            return d % total, true
        end
        local c = d % lap
        if c <= total then
            return c, true
        end
        return lap - c, false
    end

    local head, fwd = PathDist(raw)
    local behind = fwd and -1 or 1
    for i = 0, pieces - 1 do
        local d2 = PathDist(raw + behind * i * step)
        local d1 = PathDist(raw + behind * (i + 1) * step)
        local x1, y1 = SampleAlong(segs, fwd and d1 or d2, total)
        local x2, y2 = SampleAlong(segs, fwd and d2 or d1, total)
        if x1 and x2 then
            local dx, dy = x2 - x1, y2 - y1
            local plen = math.sqrt(dx * dx + dy * dy)
            if plen >= 0.4 and plen <= step * 3 then
                local visible = (not inside) or inside(x1, y1) or inside(x2, y2)
                if visible then
                    used = used + 1
                    PlaceLine(GetLine(holder, used, "pulses", "OVERLAY"),
                        thickness, r, g, b, alpha, anchor, rel, x1, y1, x2, y2, alpha)
                end
            end
        end
    end
    HideFrom(holder.pulses, used + 1)
    HideFrom(holder.pulseGlows, 1)
    HideFrom(holder.pulseHeads, 1)
    HideFrom(holder.chevrons, 1)
    Overlay._pulses = used
end

local function CollectSegs(pts, pairs, clip)
    local segs = {}
    for _, pr in ipairs(pairs) do
        local A, B = pts[pr[1]], pts[pr[2]]
        if A and B then
            local x1, y1, x2, y2 = A[1], A[2], B[1], B[2]
            if clip then
                x1, y1, x2, y2 = clip(x1, y1, x2, y2)
            end
            if x1 then
                local len = math.sqrt((x2 - x1) * (x2 - x1) + (y2 - y1) * (y2 - y1))
                if len > 1 then
                    segs[#segs + 1] = { x1 = x1, y1 = y1, x2 = x2, y2 = y2, len = len }
                end
            end
        end
    end
    return segs
end

-- Small gold next-stop marker: Indicator-Yellow, tinted gold, 10/cs on
-- the world map and 8 on the minimap.
local function StyleMarker(tex, size)
    if not tex then return end
    if tex.SetTexture then tex:SetTexture(DOT_NEXT) end
    if tex.SetVertexColor then tex:SetVertexColor(1, 0.90, 0.35, 1) end
    tex:SetSize(size, size)
end

---------------------------------------------------------------------------
-- Map surfaces
---------------------------------------------------------------------------

-- A map frame we can actually parent to: shown, visible, and large enough.
local function Usable(frame)
    if not frame then return end
    local w = (frame.GetWidth and frame:GetWidth()) or 0
    local h = (frame.GetHeight and frame:GetHeight()) or 0
    if w < 32 or h < 32 then return end
    if frame.IsShown and not frame:IsShown() then return end
    if frame.IsVisible and not frame:IsVisible() then return end
    return w, h
end

local function FrameName(frame)
    if not frame then return "?" end
    if frame.GetName then
        local n = PCall(frame.GetName, frame)
        if type(n) == "string" and n ~= "" then return n end
    end
    return frame._kind or "unnamed"
end

-- Prefer the classic map art (WorldMapDetailFrame / WorldMapButton) on
-- 1.60.1 clients. ScrollContainer.Child can exist with a size but not be
-- the visible map, which left the path drawing into an empty frame.
function Overlay:MapCandidates()
    local map = WorldMapFrame
    local list = {}
    local function add(frame, label)
        if not frame then return end
        local w, h = Usable(frame)
        list[#list + 1] = { frame = frame, label = label, w = w, h = h,
            usable = w ~= nil }
    end
    add(WorldMapDetailFrame, "WorldMapDetailFrame")
    add(WorldMapButton, "WorldMapButton")
    if map then
        if map.ScrollContainer and map.ScrollContainer.Child then
            add(map.ScrollContainer.Child, "ScrollContainer.Child")
        end
        if map.ScrollContainer then
            add(map.ScrollContainer, "ScrollContainer")
            if map.ScrollContainer.GetCanvas then
                local c = PCall(map.ScrollContainer.GetCanvas, map.ScrollContainer)
                add(c, "ScrollContainer:GetCanvas()")
            end
        end
        if map.GetCanvas then
            add(PCall(map.GetCanvas, map), "WorldMapFrame:GetCanvas()")
        end
        add(map, "WorldMapFrame")
    end
    return list
end

function Overlay:MapSurface()
    local used
    for _, c in ipairs(self:MapCandidates()) do
        if c.usable then
            used = c
            break
        end
    end
    self._parentInfo = used
    if not used then return end
    return used.frame, used.w, used.h, used.label
end

local function MapName(id)
    if not id then return end
    if C_Map and C_Map.GetMapInfo then
        local info = PCall(C_Map.GetMapInfo, id)
        if type(info) == "table" and type(info.name) == "string" and info.name ~= "" then
            return info.name
        end
    end
    if ns.Zones and ns.Zones.MAP_IDS then
        for name, mid in pairs(ns.Zones.MAP_IDS) do
            if mid == id then return name end
        end
    end
end

function Overlay:ShownMapID()
    local ids = self:ShownMapIDs()
    return ids and ids[1]
end

-- Every ID the open world map might be reporting. Forever and classic
-- expose this in different places; we accept any of them.
function Overlay:ShownMapIDs()
    local ids, seen = {}, {}
    local function add(id)
        if type(id) == "number" and id > 0 and not seen[id] then
            seen[id] = true
            ids[#ids + 1] = id
        end
    end
    local map = WorldMapFrame
    if map and map.GetMapID then add(PCall(map.GetMapID, map)) end
    if map and type(map.mapID) == "number" then add(map.mapID) end
    if GetCurrentMapAreaID then add(PCall(GetCurrentMapAreaID)) end
    return ids
end

-- Does the map currently on screen belong to this route? Match by map
-- ID, or by zone name if Forever reports a different uiMapID for Elwynn
-- than the 1429 we stored.
function Overlay:MapMatchesRoute(a)
    if not a then return false, "no route" end
    local ids = self:ShownMapIDs()
    local names = {}
    for _, id in ipairs(ids) do
        if a.mapID and id == a.mapID then
            return true, "mapID " .. id, ids
        end
        local name = MapName(id)
        if name then names[#names + 1] = name end
        if a.zone and name and name == a.zone then
            return true, "name " .. name .. " (id " .. id .. ")", ids
        end
    end
    if #ids == 0 then
        -- No API to read the shown map. Draw anyway rather than hide it.
        return true, "unknown (drawn anyway)", ids
    end
    return false, "mismatch (shown " .. table.concat(ids, ",") .. ")", ids
end

-- If the world map is already open, switch it to the route's zone so
-- the line is visible. Does not open the map unless openIfClosed is set.
function Overlay:FocusRouteMap(openIfClosed)
    local a = Active()
    if not a or not a.mapID then return false end
    local f = WorldMapFrame
    if not f then return false end
    local shown = f.IsShown and f:IsShown()
    local ui = ns.UI and ns.UI.frame
    local uiWasShown = ui and ui.IsShown and ui:IsShown()
    if not shown then
        if not openIfClosed then return false end
        if OpenWorldMap then
            pcall(OpenWorldMap, a.mapID)
        elseif ToggleWorldMap then
            pcall(ToggleWorldMap)
        elseif ShowUIPanel then
            pcall(ShowUIPanel, f)
        elseif f.Show then
            f:Show()
        end
        shown = f.IsShown and f:IsShown()
    end
    if f.SetMapID then
        pcall(f.SetMapID, f, a.mapID)
    end
    if C_Timer and C_Timer.After then
        C_Timer.After(0, function()
            if not Active() then return end
            if f.IsShown and f:IsShown() and f.SetMapID then
                pcall(f.SetMapID, f, a.mapID)
            end
            Overlay:Refresh()
        end)
    end
    Overlay:Refresh()
    -- Show on map (openIfClosed) is a user open-map action: dock the
    -- main window beside the map if it is up.
    if openIfClosed and shown and ns.UI and ns.UI.DockAfterMapOpen then
        ns.UI:DockAfterMapOpen(uiWasShown)
    end
    return shown and true or false
end

function Overlay:EnsureMini()
    if self.mini or not Minimap then return self.mini end
    local f = SafeFrame("Frame", "GatherpediaRouteMini", Minimap)
    if not f then return nil end
    f:SetAllPoints(Minimap)
    if f.SetFrameLevel then
        f:SetFrameLevel((Minimap.GetFrameLevel and Minimap:GetFrameLevel() or 1) + 5)
    end
    f:Hide()
    f:SetScript("OnUpdate", function(frame, elapsed)
        frame.t = (frame.t or 0) + (elapsed or 0)
        if frame.t < TickInterval() then return end
        frame.t = 0
        Overlay:DrawMinimap()
    end)
    self.mini = f
    return f
end

function Overlay:EnsureWorld()
    local parent = select(1, self:MapSurface())
    if not parent then return nil end
    if self.world then
        if self.world.GetParent and self.world:GetParent() ~= parent then
            self.world:SetParent(parent)
            self.world:SetAllPoints(parent)
            if self.world.SetFrameStrata then self.world:SetFrameStrata("HIGH") end
            if self.world.SetFrameLevel then
                self.world:SetFrameLevel((parent.GetFrameLevel and parent:GetFrameLevel() or 1) + 100)
            end
        end
        return self.world
    end
    local f = SafeFrame("Frame", "GatherpediaRouteWorld", parent)
    if not f then return nil end
    f:SetAllPoints(parent)
    if f.SetFrameStrata then f:SetFrameStrata("HIGH") end
    if f.SetFrameLevel then
        f:SetFrameLevel((parent.GetFrameLevel and parent:GetFrameLevel() or 1) + 100)
    end
    if f.EnableMouse then f:EnableMouse(false) end
    f:Hide()
    f:SetScript("OnUpdate", function(frame, elapsed)
        frame.t = (frame.t or 0) + (elapsed or 0)
        -- Only tick quickly while a route is up and the pulse is on.
        if frame.t < TickInterval() then return end
        frame.t = 0
        Overlay:DrawWorldMap()
    end)
    self.world = f
    return f
end

---------------------------------------------------------------------------
-- Minimap
---------------------------------------------------------------------------

function Overlay:DrawMinimap()
    local f = self:EnsureMini()
    if not f then return end
    local a = Active()
    local world = RouteWorld()
    local pc, px, py = PlayerWorld()
    if not a or not a.route or not world or not pc then
        HideDrawn(f)
        return
    end

    local zoom = (Minimap.GetZoom and Minimap:GetZoom()) or 0
    local sizes = (IsIndoors and IsIndoors()) and INDOOR or OUTDOOR
    local diameter = sizes[zoom + 1] or sizes[1]
    local width = (Minimap.GetWidth and Minimap:GetWidth()) or 140
    if width < 1 then width = 140 end
    local half = width / 2
    local scale = width / diameter
    local square = GetMinimapShape and GetMinimapShape() == "SQUARE"
    local rotate = GetCVar and PCall(GetCVar, "rotateMinimap") == "1"
    local facing = (rotate and GetPlayerFacing and PCall(GetPlayerFacing)) or 0
    local s, c = math.sin(facing), math.cos(facing)

    -- Project every stop into minimap pixels (x = right, y = up).
    local pts = {}
    for i, w in pairs(world) do
        if w.c == pc then
            local east = (py - w.y) * scale    -- world Y grows to the west
            local north = (w.x - px) * scale   -- world X grows to the north
            if rotate then east, north = east * c + north * s, -east * s + north * c end
            pts[i] = { east, north }
        end
    end

    local edge = half - 5
    local function Inside(x, y)
        if square then return math.abs(x) <= edge and math.abs(y) <= edge end
        return x * x + y * y <= edge * edge
    end
    local function Clip(x1, y1, x2, y2)
        if square then return ClipSquare(x1, y1, x2, y2, edge) end
        return ClipCircle(x1, y1, x2, y2, edge)
    end

    local pairs_ = a.drawPairs or SegmentPairs(a.route, a.routeType)
    local nLines = 0
    for _, pr in ipairs(pairs_) do
        local A, B = pts[pr[1]], pts[pr[2]]
        if A and B then
            local x1, y1, x2, y2 = Clip(A[1], A[2], B[1], B[2])
            if x1 then
                nLines = nLines + 1
                Segment(f, nLines, x1, y1, x2, y2, 1.35, "CENTER", f)
            end
        end
    end
    HideLeftoverLines(f, nLines)
    DrawJoints(f, pts, 1.35, "CENTER", f, Inside)
    -- Unclipped path so the dash travels the whole loop at a steady speed;
    -- pieces off the disc are simply skipped.
    DrawDash(f, CollectSegs(pts, pairs_), 1.35, 28, "CENTER", f, Inside)

    -- Only the current/next stop is marked. If it's off the disc, pin
    -- it to the edge so you can still see which way to go.
    HideFrom(f.pins, 1)
    local step = a.step or 1
    local P = pts[step]
    if P then
        local x, y = P[1], P[2]
        local show = Inside(x, y)
        if not show then
            local d = math.sqrt(x * x + y * y)
            if d > 0 then
                local k = square and (edge / math.max(math.abs(x), math.abs(y))) or (edge / d)
                x, y, show = x * k, y * k, true
            end
        end
        if show then
            local pin = GetPin(f, 1)
            StyleMarker(pin, 8)
            pin:ClearAllPoints()
            pin:SetPoint("CENTER", f, "CENTER", x, y)
            pin:Show()
        end
    end
    HideFrom(f.pins, 2)
end

---------------------------------------------------------------------------
-- World map
---------------------------------------------------------------------------

function Overlay:DrawWorldMap()
    local f = self:EnsureWorld()
    if not f then return end
    local a = Active()
    Overlay._errors = {}
    local match, reason = self:MapMatchesRoute(a)
    self._match = reason
    if not a or not a.route or not match then
        HideDrawn(f)
        self._segments = 0
        return
    end
    local parent, w, h = self:MapSurface()
    if not parent or not w or w < 1 or not h or h < 1 then
        HideDrawn(f)
        return
    end
    local cs = 1
    local sc = WorldMapFrame and WorldMapFrame.ScrollContainer
    if sc and sc.GetCanvasScale then cs = sc:GetCanvasScale() or 1 end
    if cs <= 0 then cs = 1 end

    -- Stop positions (0-1) on the map being shown.
    local pts = {}
    for i, s in ipairs(a.drawRoute or a.route) do
        pts[i] = { s.x / 100, s.y / 100 }
    end

    -- About 1.7 px on screen at default zoom, a little thicker when zoomed in.
    local zoomPct = (sc and sc.GetCanvasZoomPercent and sc:GetCanvasZoomPercent()) or 0
    local px = 1.7 + 1.0 * math.max(0, math.min(1, zoomPct))
    local thick = px / cs
    local pairs_ = a.drawPairs or SegmentPairs(a.route, a.routeType)
    local nLines = 0
    for _, pr in ipairs(pairs_) do
        local A, B = pts[pr[1]], pts[pr[2]]
        if A and B then
            nLines = nLines + 1
            Segment(f, nLines, A[1] * w, -A[2] * h, B[1] * w, -B[2] * h, thick, "TOPLEFT", f)
        end
    end
    HideLeftoverLines(f, nLines)
    self._segments = nLines
    self._lastW, self._lastH = w, h

    local pix = {}
    for i, pt in pairs(pts) do
        pix[i] = { pt[1] * w, -pt[2] * h }
    end
    DrawJoints(f, pix, thick, "TOPLEFT", f)
    DrawDash(f, CollectSegs(pix, pairs_), thick, 36, "TOPLEFT", f)

    -- Small gold marker on the current stop only; no numbered dots.
    HideFrom(f.pins, 1)
    local step = a.step or 1
    local P = pts[step]
    if P then
        local pin = GetPin(f, 1)
        StyleMarker(pin, 10 / cs)
        pin:ClearAllPoints()
        pin:SetPoint("CENTER", f, "TOPLEFT", P[1] * w, -P[2] * h)
        if pin.SetFrameLevel and f.GetFrameLevel then
            pin:SetFrameLevel((f:GetFrameLevel() or 1) + 5)
        end
        pin:Show()
    end
    HideFrom(f.pins, 2)
end

---------------------------------------------------------------------------
-- Setup
---------------------------------------------------------------------------

function Overlay:HookMapID()
    if self._hookedMapID or not WorldMapFrame or not WorldMapFrame.SetMapID then return end
    self._hookedMapID = true
    if hooksecurefunc then
        pcall(hooksecurefunc, WorldMapFrame, "SetMapID", function() Overlay:Refresh() end)
    else
        local oldSet = WorldMapFrame.SetMapID
        WorldMapFrame.SetMapID = function(frame, ...)
            oldSet(frame, ...)
            Overlay:Refresh()
        end
    end
end

function Overlay:Refresh()
    if self._refreshing then return end
    self._refreshing = true
    self:HookMapID()
    self:EnsureMini()
    self:EnsureWorld()
    local a = Active()
    if a then self:StartWatch() else self:StopWatch() end
    if a then a.world = nil end
    if self.mini then
        self.mini:SetShown(a ~= nil)
        if self.mini:IsShown() then
            self:DrawMinimap()
        else
            HideDrawn(self.mini)
        end
    end
    local mapOn = WorldMapFrame and WorldMapFrame.IsShown and WorldMapFrame:IsShown()
    if self.world then
        self.world:SetShown(a ~= nil and mapOn and true or false)
        if self.world:IsShown() then
            self:DrawWorldMap()
        else
            HideDrawn(self.world)
        end
    elseif a and mapOn then
        -- Surface wasn't ready yet; try again now that the map is up.
        self:EnsureWorld()
        if self.world then
            self.world:Show()
            self:DrawWorldMap()
        end
    end
    self._refreshing = false
end

function Overlay:Hook()
    if self._hooked then return end
    self._hooked = true
    if WorldMapFrame and WorldMapFrame.HookScript then
        pcall(WorldMapFrame.HookScript, WorldMapFrame, "OnShow", function()
            -- If the map just opened and the player is not in the route
            -- zone, switch it to that zone so the line is visible.
            local a = Active()
            if a and ns.Arrow and not ns.Arrow:InZone() then
                Overlay:FocusRouteMap(false)
            else
                Overlay:Refresh()
            end
        end)
        pcall(WorldMapFrame.HookScript, WorldMapFrame, "OnHide", function() Overlay:Refresh() end)
        pcall(WorldMapFrame.HookScript, WorldMapFrame, "OnSizeChanged", function() Overlay:Refresh() end)
    end
    if WorldMapFrame and WorldMapFrame.GetCanvasContainer then
        local cc = PCall(WorldMapFrame.GetCanvasContainer, WorldMapFrame)
        if cc and cc.HookScript then
            pcall(cc.HookScript, cc, "OnMapChanged", function() Overlay:Refresh() end)
        end
    end
    if WorldMapFrame and WorldMapFrame.ScrollContainer and WorldMapFrame.ScrollContainer.HookScript then
        pcall(WorldMapFrame.ScrollContainer.HookScript, WorldMapFrame.ScrollContainer, "OnMapChanged", function() Overlay:Refresh() end)
    end
    if WorldMapFrame and WorldMapFrame.SetMapID then
        if hooksecurefunc then
            pcall(hooksecurefunc, WorldMapFrame, "SetMapID", function() Overlay:Refresh() end)
        else
            local oldSet = WorldMapFrame.SetMapID
            WorldMapFrame.SetMapID = function(self, ...)
                oldSet(self, ...)
                Overlay:Refresh()
            end
        end
    end
    local ev = CreateFrame("Frame")
    ev:SetScript("OnEvent", function() Overlay:Refresh() end)
    for _, name in ipairs({
        "WORLD_MAP_UPDATE", "WORLD_MAP", "ZONE_CHANGED_NEW_AREA", "PLAYER_ENTERING_WORLD",
    }) do
        pcall(ev.RegisterEvent, ev, name)
    end
    -- Keep retrying while a route is active and the map is open, in case
    -- the canvas had no size the first time we tried to draw.
    if not self.watch then
        local w = CreateFrame("Frame")
        w:Hide()
        w:SetScript("OnUpdate", function(frame, elapsed)
            frame.t = (frame.t or 0) + (elapsed or 0)
            if frame.t < 0.25 then return end
            frame.t = 0
            if not Active() then frame:Hide() return end
            if WorldMapFrame and WorldMapFrame:IsShown() then
                local _, ww, hh = Overlay:MapSurface()
                if not Overlay.world or (Overlay._segments or 0) == 0
                    or (ww and (ww ~= Overlay._lastW or hh ~= Overlay._lastH)) then
                    Overlay._lastW, Overlay._lastH = ww, hh
                    Overlay:Refresh()
                end
            end
        end)
        self.watch = w
    end
end

function Overlay:DebugLines()
    local lines = {}
    local function add(s) lines[#lines + 1] = s end
    add("Route overlay debug:")
    local a = Active()
    if not a then
        add("Route: none")
    else
        add("Route: active")
        add("  zone: " .. tostring(a.zone))
        add("  label: " .. tostring(a.label))
        add("  mapID: " .. tostring(a.mapID))
        add("  stops: " .. tostring(a.route and #a.route))
        add("  step: " .. tostring(a.step))
    end
    local pMap = ns.Arrow and ns.Arrow.PlayerMapID and ns.Arrow:PlayerMapID()
    add("Player mapID: " .. tostring(pMap))
    add("Player zone: " .. tostring(GetRealZoneText and GetRealZoneText() or "?"))
    add("In route zone: " .. (ns.Arrow and ns.Arrow:InZone() and "yes" or "no"))
    local map = WorldMapFrame
    add("World map shown: " .. (map and map:IsShown() and "yes" or "no"))
    local ids = self:ShownMapIDs() or {}
    if #ids == 0 then
        add("Shown map IDs: (none)")
    else
        local bits = {}
        for _, id in ipairs(ids) do
            bits[#bits + 1] = tostring(id) .. (MapName(id) and (" " .. MapName(id)) or "")
        end
        add("Shown map IDs: " .. table.concat(bits, ", "))
    end
    add("Match: " .. tostring(self._match or "(not drawn yet)"))
    add("Candidates:")
    for _, c in ipairs(self:MapCandidates()) do
        local mark = (self._parentInfo and c.frame == self._parentInfo.frame) and "  <-- used" or ""
        add(string.format("  %s  %s  %s",
            c.label,
            c.usable and (tostring(math.floor(c.w + 0.5)) .. "x" .. tostring(math.floor(c.h + 0.5))) or "not usable",
            mark))
    end
    local used = self._parentInfo
    add("Parent: " .. (used and (used.label .. " " .. math.floor((used.w or 0) + 0.5) .. "x" .. math.floor((used.h or 0) + 0.5)) or "(none)"))
    add("Line method: " .. tostring(self._lineMethod or "(none)"))
    add("Segments drawn: " .. tostring(self._segments or 0))
    local function count(list)
        local n = 0
        if list then for _, o in ipairs(list) do if o.IsShown and o:IsShown() then n = n + 1 end end end
        return n
    end
    if self.world then
        add("  shadows shown: " .. count(self.world.shadows))
        add("  glows shown: " .. count(self.world.glows))
        add("  pulses shown: " .. count(self.world.pulses))
    end
    if ns.MapLink and ns.MapLink.PinTextureReport then
        for _, line in ipairs(ns.MapLink:PinTextureReport()) do add(line) end
    end
    if ns.Arrow and ns.Arrow.DebugLines then
        for _, line in ipairs(ns.Arrow:DebugLines()) do add(line) end
    end
    local errs = self._errors or {}
    if #errs == 0 then
        add("Errors: none")
    else
        add("Errors:")
        for i = 1, math.min(#errs, 12) do add("  " .. errs[i]) end
    end
    return lines
end

function Overlay:ShowDebugPanel()
    self:Refresh()
    local f = self.debugPanel
    if not f then
        f = CreateFrame("Frame", "GatherpediaRouteDebug", UIParent, "BackdropTemplate")
        f:SetSize(520, 420)
        f:SetPoint("CENTER", 0, 40)
        f:SetFrameStrata("FULLSCREEN_DIALOG")
        if f.SetToplevel then f:SetToplevel(true) end
        if f.SetClampedToScreen then f:SetClampedToScreen(true) end
        f:SetMovable(true)
        f:EnableMouse(true)
        if f.RegisterForDrag then f:RegisterForDrag("LeftButton") end
        f:SetScript("OnDragStart", f.StartMoving)
        f:SetScript("OnDragStop", f.StopMovingOrSizing)
        if f.SetBackdrop then
            f:SetBackdrop({
                bgFile = "Interface\\Buttons\\WHITE8X8",
                edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
                edgeSize = 16,
                insets = { left = 4, right = 4, top = 4, bottom = 4 },
            })
            f:SetBackdropColor(0.07, 0.05, 0.04, 0.97)
            f:SetBackdropBorderColor(0.90, 0.75, 0.38, 1)
        end
        local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        title:SetPoint("TOP", 0, -14)
        title:SetText("Route overlay debug")
        title:SetTextColor(0.90, 0.75, 0.38)
        local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
        if close then
            close:SetPoint("TOPRIGHT", -6, -6)
        else
            close = CreateFrame("Button", nil, f)
            close:SetSize(24, 24)
            close:SetPoint("TOPRIGHT", -6, -6)
            close:SetScript("OnClick", function() f:Hide() end)
        end
        local scroll = CreateFrame("ScrollFrame", "GatherpediaRouteDebugScroll", f)
        scroll:SetPoint("TOPLEFT", 18, -40)
        scroll:SetPoint("BOTTOMRIGHT", -36, 44)
        local edit = CreateFrame("EditBox", "GatherpediaRouteDebugEdit", scroll)
        edit:SetMultiLine(true)
        if edit.SetAutoFocus then edit:SetAutoFocus(false) end
        if edit.SetFontObject then edit:SetFontObject("GameFontHighlightSmall") end
        edit:SetWidth(450)
        if edit.SetTextInsets then edit:SetTextInsets(4, 4, 4, 4) end
        if edit.SetMaxLetters then edit:SetMaxLetters(20000) end
        if edit.SetAltArrowKeyMode then edit:SetAltArrowKeyMode(false) end
        edit:SetScript("OnEscapePressed", function(self) if self.ClearFocus then self:ClearFocus() end end)
        scroll:SetScrollChild(edit)
        local refresh = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
        refresh:SetSize(110, 24)
        refresh:SetPoint("BOTTOM", 0, 14)
        refresh:SetText("Refresh")
        refresh:SetScript("OnClick", function() Overlay:RefreshDebugPanel(true) end)
        f.scroll, f.edit, f.refresh = scroll, edit, refresh
        if UISpecialFrames then tinsert(UISpecialFrames, "GatherpediaRouteDebug") end
        self.debugPanel = f
    end
    self:RefreshDebugPanel(true)
    f:Show()
    if f.Raise then f:Raise() end
end

function Overlay:RefreshDebugPanel(selectAll)
    local f = self.debugPanel
    if not f or not f.edit then return end
    local text = table.concat(self:DebugLines(), "\n")
    f.edit:SetText(text)
    if f.edit.GetNumLetters and f.edit.SetHeight then
        local n = f.edit:GetNumLetters() or #text
        local h = math.max(320, math.floor(n / 8) * 4 + 40)
        f.edit:SetHeight(h)
    end
    if selectAll and f.edit.HighlightText then f.edit:HighlightText() end
    if f.edit.SetFocus then f.edit:SetFocus() end
    if f.scroll and f.scroll.SetVerticalScroll then f.scroll:SetVerticalScroll(0) end
end

function Overlay:StartWatch()
    self:Hook()
    if self.watch then self.watch:Show() end
end

function Overlay:StopWatch()
    if self.watch then self.watch:Hide() end
end

Overlay:Hook()
local boot = CreateFrame("Frame")
boot:RegisterEvent("PLAYER_LOGIN")
boot:SetScript("OnEvent", function() Overlay:Hook(); Overlay:EnsureMini(); Overlay:Refresh() end)
