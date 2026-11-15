-- Gatherpedia: Arrow.lua
-- Gatherpedia's on-screen arrow for a recorded farm route. No Blizzard
-- user-waypoint or SuperTrack APIs. Original art in
-- Media/Arrow3D.tga: a 64-frame sheet of a pre-rendered beveled 3D arrow.

local ADDON_NAME, ns = ...

local Arrow = {}
ns.Arrow = Arrow

local TEX_PATHS = {
    "Interface\\AddOns\\Gatherpedia\\Media\\Arrow3D",
    "Interface\\AddOns\\Gatherpedia\\Media\\Arrow3D.tga",
}
local GOLD = { 0.90, 0.75, 0.38 }
local GREEN = { 0.30, 0.88, 0.36 }
local WHITE = "Interface\\Buttons\\WHITE8X8"
local ARRIVE_YARDS = 30
-- A stop is auto-skipped only when the player has gone past it within
-- this many yards on either side. Farther than this is just off-path.
local PASS_YARDS = 30
local PAST_EPS = 0.5
local ARROW_SIZE = 96
local PI2 = math.pi * 2
local SHEET_FRAMES = 64
local SHEET_COLS = 8
local SHEET_ROWS = 8
local SHEET_SIZE = 1024

local function RefreshGuides()
    local ui = ns.GuidesUI
    if ui and ui.page and ui.page.IsShown and ui.page:IsShown() and ui.Paint then
        ui:Paint()
    end
    if ns.UI and ns.UI.UpdateRouteToggle then
        ns.UI:UpdateRouteToggle()
    end
end

local function Print(msg)
    if ns.Print then
        ns:Print(msg)
    elseif DEFAULT_CHAT_FRAME and DEFAULT_CHAT_FRAME.AddMessage then
        DEFAULT_CHAT_FRAME:AddMessage("|cff7fbf3fGatherpedia:|r " .. tostring(msg))
    end
end

local function PCall(fn, ...)
    if not fn then return nil end
    local ok, a, b, c, d = pcall(fn, ...)
    if ok then return a, b, c, d end
    return nil
end

-- Usable number from a client API. A plain number from pcall is
-- accepted. Values are dropped only when they are nil,
-- not a number, NaN, or that throw when used (a secret wrapper).
local function Num(v)
    if v == nil then return nil end
    if type(v) ~= "number" then
        v = tonumber(v)
        if type(v) ~= "number" then return nil end
    end
    if v ~= v then return nil end
    local ok = pcall(function() return v + 0 end)
    if not ok then return nil end
    return v
end

local function ZoneName()
    if GetRealZoneText then
        local z = PCall(GetRealZoneText)
        if type(z) == "string" and z ~= "" then return z end
    end
    if GetZoneText then
        local z = PCall(GetZoneText)
        if type(z) == "string" and z ~= "" then return z end
    end
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

function Arrow:PlayerMapID()
    if C_Map and C_Map.GetBestMapForUnit then
        local id = Num(PCall(C_Map.GetBestMapForUnit, "player"))
        if id and id > 0 then return id end
    end
    if GetCurrentMapAreaID then
        local id = Num(PCall(GetCurrentMapAreaID))
        if id and id > 0 then return id end
    end
end

-- Player 0-1 position on a specific uiMapID, or nil.
function Arrow:CoordsOnMap(mapID)
    if not (C_Map and C_Map.GetPlayerMapPosition and mapID) then return end
    local pos = PCall(C_Map.GetPlayerMapPosition, mapID, "player")
    if not pos then return end
    local x, y
    if pos.GetXY then
        x, y = PCall(pos.GetXY, pos)
    end
    if not x and pos.x then x, y = pos.x, pos.y end
    x, y = Num(x), Num(y)
    if x and y then return x, y, mapID end
end

-- Prefer the route map, then the best map, then the legacy API.
function Arrow:PlayerMapXY()
    local a = self.active
    if a and a.mapID then
        local x, y, id = self:CoordsOnMap(a.mapID)
        if x then return x, y, id end
    end
    local mapID = self:PlayerMapID()
    if mapID then
        local x, y, id = self:CoordsOnMap(mapID)
        if x then return x, y, id end
    end
    if GetPlayerMapPosition then
        local x, y = PCall(GetPlayerMapPosition, "player")
        x, y = Num(x), Num(y)
        if x and y then return x, y, mapID end
    end
end

local function WorldXY(mapID, x, y)
    if not (C_Map and C_Map.GetWorldPosFromMapPos and mapID and x and y) then return end
    local vec
    if CreateVector2D then
        vec = CreateVector2D(x, y)
    else
        vec = { x = x, y = y }
    end
    local continent, world = PCall(C_Map.GetWorldPosFromMapPos, mapID, vec)
    if not world then return end
    local wx, wy
    if world.GetXY then
        wx, wy = PCall(world.GetXY, world)
    end
    if not wx and world.x then wx, wy = world.x, world.y end
    wx, wy = Num(wx), Num(wy)
    if wx and wy then return continent, wx, wy end
end

function Arrow:YardsTo(stop)
    if not self.active or not stop then return nil end
    local px, py, pMap = self:PlayerMapXY()
    if not px or not py then return nil end
    local tx, ty = stop.x / 100, stop.y / 100
    local c1, wx1, wy1 = WorldXY(pMap or self.active.mapID, px, py)
    local c2, wx2, wy2 = WorldXY(self.active.mapID, tx, ty)
    if c1 and c2 and c1 == c2 and wx1 and wx2 then
        local dx, dy = wx1 - wx2, wy1 - wy2
        return math.sqrt(dx * dx + dy * dy)
    end
    -- Last resort: treat 100 map percent as 1000 yards. Only used when
    -- the world-position API is missing, so arrival may be approximate.
    local mx, my = px, py
    if pMap and self.active.mapID and pMap ~= self.active.mapID then
        return nil
    end
    local dx, dy = (mx - tx) * 1000, (my - ty) * 1000
    return math.sqrt(dx * dx + dy * dy)
end

-- Angle the arrow texture should rotate, in radians. World x is north,
-- world y is west; GetPlayerFacing is counter-clockwise from north.
-- Falls back to map-space (x east, y south) when world positions are missing.
function Arrow.Angle(px, py, tx, ty, facing, fromMap)
    local bearing
    if fromMap then
        -- west = -(tx-px), north = -(ty-py)
        bearing = math.atan2(px - tx, py - ty)
    else
        bearing = math.atan2(ty - py, tx - px)
    end
    -- Target bearing minus facing: turning right (facing decreases)
    -- increases the angle, so the arrow counter-rotates to the left.
    return (bearing - (facing or 0)) % PI2
end

-- Sprite-sheet frame for a relative heading. Angle 0 is forward (up /
-- into the screen); increasing angle is counterclockwise, so +pi/2 is
-- the left side of the screen and 3pi/2 (or -pi/2) is the right.
function Arrow.FrameIndex(angle)
    local a = (angle or 0) % PI2
    if a < 0 then a = a + PI2 end
    return math.floor(a / PI2 * SHEET_FRAMES + 0.5) % SHEET_FRAMES
end

-- True if fromID is target, or a descendant (walk parents).
function Arrow:MapOrParentIs(fromID, target)
    if not fromID or not target then return false end
    if fromID == target then return true end
    if not (C_Map and C_Map.GetMapInfo) then return false end
    local id, guard = fromID, 0
    while id and guard < 8 do
        guard = guard + 1
        local info = PCall(C_Map.GetMapInfo, id)
        if type(info) ~= "table" then break end
        local parent = Num(info.parentMapID)
        if parent and parent == target then return true end
        if not parent or parent == 0 or parent == id then break end
        id = parent
    end
    return false
end

function Arrow:InZone()
    local a = self.active
    self._inZoneWhy = "no route"
    self._routeXY = nil
    if not a then return false end
    if a.mapID then
        local x, y = self:CoordsOnMap(a.mapID)
        if x and y then
            self._routeXY = { x, y }
            self._inZoneWhy = "player coords on route map " .. a.mapID
            return true
        end
    end
    local best = self:PlayerMapID()
    if best and a.mapID and best == a.mapID then
        self._inZoneWhy = "best map " .. best
        return true
    end
    if best and a.mapID and self:MapOrParentIs(best, a.mapID) then
        self._inZoneWhy = "parent of " .. best .. " is route map " .. a.mapID
        return true
    end
    local here = ZoneName()
    if here and a.zone and here == a.zone then
        self._inZoneWhy = "zone name " .. here
        return true
    end
    if best and a.zone and C_Map and C_Map.GetMapInfo then
        local info = PCall(C_Map.GetMapInfo, best)
        if type(info) == "table" and info.name == a.zone then
            self._inZoneWhy = "best map name " .. a.zone
            return true
        end
    end
    self._inZoneWhy = string.format("no match (best=%s, route=%s, zone=%s)",
        tostring(best), tostring(a.mapID), tostring(here))
    return false
end

function Arrow:CurrentStop()
    local a = self.active
    if not a then return nil end
    return a.route[a.step], a.step, #a.route
end

function Arrow:IsFor(spot)
    local a = self.active
    if not a or not spot then return false end
    if a.spot == spot then return true end
    return a.zone == spot.zone and a.label == (spot.label or spot.zone)
        and (not spot.mapID or not a.mapID or spot.mapID == a.mapID)
end

function Arrow:IsActive()
    return self.active ~= nil
end

-- Shown when the player is truly out of the route's zone.
function Arrow:OutOfZoneText()
    local zone = self.active and self.active.zone or "another zone"
    return "Go to " .. zone .. " to start"
end


-- Open the world map on the route's zone. Safe to call from the arrow
-- button; does not force a user waypoint.
function Arrow:ShowOnMap()
    if not self.active then return end
    if ns.RouteOverlay and ns.RouteOverlay.FocusRouteMap then
        ns.RouteOverlay:FocusRouteMap(true)
    end
end

local function SuggestLocalRoute()
    if not GetRealZoneText then return end
    local here = ZoneName()
    if not here or here == "" then return end
    if not (ns.Guides and ns.Guides.RoutesInZone) then return end
    local faction = ns.GuidesUI and ns.GuidesUI.faction
    for _, r in ipairs(ns.Guides:RoutesInZone(here, faction)) do
        if r.spot and not Arrow:IsFor(r.spot) then
            Print("A route in " .. here .. " is ready: " .. (r.spot.label or here) .. ".")
            return
        end
    end
end

-- Remember the running route per character so it survives /reload and relog.
function Arrow:SaveState()
    local a = self.active
    if not (ns.charDB and a) then return end
    ns.charDB.activeRoute = {
        prof = a.prof, zone = a.zone, label = a.label, mapID = a.mapID,
        step = a.step, dir = a.dir or 1, needSnap = a.needSnap and true or nil,
    }
end

function Arrow:ClearState()
    if ns.charDB then ns.charDB.activeRoute = nil end
end

-- Put the player on the route: find the nearest checkpoint. If the player
-- is within ARRIVE_YARDS (30 yd) of it, count it as reached and aim at
-- the next checkpoint in the travel direction. Otherwise aim at the nearest
-- one. Returns false when the player's position is not available yet.
function Arrow:SnapToNearest()
    local a = self.active
    if not a or not a.route then return false end
    if not self:InZone() then return false end
    if a.routeType == "cave" then
        a.step, a.dir = 1, 1
        self._arrived = false
        self:SaveState()
        return true
    end
    local best, bestYards
    for i, stop in ipairs(a.route) do
        local y = self:YardsTo(stop)
        if y and (not bestYards or y < bestYards) then best, bestYards = i, y end
    end
    if not best then return false end
    a.step = best
    a.dir = 1
    self._arrived = false
    if bestYards <= ARRIVE_YARDS then
        self:Advance(1)   -- reached this checkpoint, head for the next
    else
        self._lockout = 0
        self:SaveState()
    end
    return true
end

-- Bring back the route saved before a /reload or relog.
function Arrow:Restore()
    if self.active or not (ns.charDB and ns.Guides) then return false end
    local s = ns.charDB.activeRoute
    if type(s) ~= "table" or not s.zone then return false end
    local found, foundProf
    local loose, looseProf, looseCount = nil, nil, 0
    for _, prof in ipairs(ns.PROFESSIONS) do
        if not s.prof or s.prof == prof then
            for _, b in ipairs(ns.Guides:Brackets(prof) or {}) do
                for _, sp in ipairs(b.spots or {}) do
                    if sp.zone == s.zone and ns.Guides:HasRoute(sp) then
                        if (sp.label or sp.zone) == s.label then
                            found, foundProf = found or sp, found and foundProf or prof
                        end
                        loose, looseProf = sp, prof
                        looseCount = looseCount + 1
                    end
                end
            end
        end
    end
    if not found and looseCount == 1 then found, foundProf = loose, looseProf end
    if not found then
        self:ClearState()
        return false
    end
    return self:Start(found, foundProf, { step = s.step, dir = s.dir, needSnap = s.needSnap })
end

function Arrow:Start(spot, prof, resume)
    local routeType = "loop"
    if ns.Guides and ns.Guides.RouteType then
        routeType = ns.Guides:RouteType(spot)
    end
    -- Caves: the arrow goes to the first point of the first cave and stays
    -- there; every cave outline is drawn on the map.
    local pts, drawRoute, drawPairs
    if routeType == "cave" then
        local loops = ns.Guides and ns.Guides.CaveLoops and ns.Guides:CaveLoops(spot)
        if loops then
            pts = { { x = loops[1][1].x, y = loops[1][1].y } }
            drawRoute, drawPairs = {}, {}
            for _, loop in ipairs(loops) do
                local base = #drawRoute
                for _, p in ipairs(loop) do
                    drawRoute[#drawRoute + 1] = { x = p.x, y = p.y }
                end
                for i = 1, #loop do
                    drawPairs[#drawPairs + 1] = { base + i, base + (i % #loop) + 1 }
                end
            end
        end
    else
        pts = ns.Guides and ns.Guides:RoutePoints(spot)
    end
    if not pts then
        Print("No route recorded yet.")
        return false
    end
    prof = prof or (ns.GuidesUI and ns.GuidesUI.prof) or spot.prof
    if ns.charDB and prof then
        ns.charDB.lastRouteProf = prof
    end
    self.active = {
        spot = spot,
        zone = spot.zone,
        mapID = spot.mapID or (ns.Zones and ns.Zones:MapID(spot.zone)),
        label = spot.label or spot.zone,
        route = pts,
        drawRoute = drawRoute,
        drawPairs = drawPairs,
        step = 1,
        dir = 1,
        routeType = routeType,
        prof = prof,
    }
    self._arrived = false
    self._lockout = 0
    self._lastError = nil
    self:Create()
    self:EnsureDriver()
    self:ApplyPosition()
    if resume then
        local st = math.floor(tonumber(resume.step) or 1)
        if st < 1 or st > #pts then st = 1 end
        self.active.step = st
        self.active.dir = (resume.dir == -1) and -1 or 1
        self.active.needSnap = resume.needSnap and true or nil
    elseif not self:SnapToNearest() then
        self.active.needSnap = true   -- not in the zone yet; snap once we arrive
    end
    self:SaveState()
    self:Update()
    if ns.RouteOverlay then
        -- If the world map is already open, switch it to this route's
        -- zone so the line is visible. Do not force the map open.
        if ns.RouteOverlay.FocusRouteMap then
            ns.RouteOverlay:FocusRouteMap(false)
        elseif ns.RouteOverlay.Refresh then
            ns.RouteOverlay:Refresh()
        end
    end
    local msg = ("Route %s: %s."):format(resume and "resumed" or "started", self.active.label)
    if not resume and not self.active.needSnap then
        msg = msg .. (" Heading to stop %d of %d."):format(self.active.step, #self.active.route)
    end
    if not self:InZone() and self.active.zone then
        msg = msg .. " " .. self:OutOfZoneText() .. "."
        Print(msg)
        SuggestLocalRoute()
    else
        Print(msg)
    end
    RefreshGuides()
    return true
end

function Arrow:Stop()
    if self.CloseMenu then self:CloseMenu() end
    self.active = nil
    self:ClearState()
    self._arrived = false
    if self.driver and self.driver.Hide then self.driver:Hide() end
    if self.frame then self.frame:Hide() end
    if ns.RouteOverlay and ns.RouteOverlay.Refresh then
        ns.RouteOverlay:Refresh()
    end
    RefreshGuides()
end

function Arrow:SetStep(i)
    local a = self.active
    if not a then return end
    local n = #a.route
    if n < 1 then return end
    if a.routeType == "backforth" then
        if i < 1 then i = 1 end
        if i > n then i = n end
    else
        i = ((i - 1) % n) + 1
    end
    a.step = i
    self._arrived = false
    self._lockout = 0.6
    self:SaveState()
    self:Update()
    if ns.RouteOverlay and ns.RouteOverlay.DrawWorldMap then
        ns.RouteOverlay:DrawWorldMap()
    end
end

-- sign +1 is Next (with the travel direction), -1 is Prev (against it).
function Arrow:Advance(sign)
    local a = self.active
    if not a then return end
    local n = #a.route
    if n < 1 then return end
    if a.routeType ~= "backforth" then
        self:SetStep(a.step + sign)
        return
    end
    local dir = a.dir or 1
    local i = a.step + dir * sign
    if sign > 0 then
        -- Arrival and Next reverse at the ends, then take one step back.
        if i > n then
            a.dir = -dir
            i = math.max(1, n - 1)
        elseif i < 1 then
            a.dir = -dir
            i = math.min(n, 2)
        end
    else
        -- Prev stays on the current direction; clamp at the ends.
        if i < 1 then i = 1 elseif i > n then i = n end
    end
    self:SetStep(i)
end

function Arrow:Next()
    self:Advance(1)
end

function Arrow:Prev()
    self:Advance(-1)
end

-- Previous / current / next stops in the current travel direction.
function Arrow:AdjacentStops()
    local a = self.active
    if not a or not a.route then return end
    local route, i, n = a.route, a.step, #a.route
    if n < 1 or not route[i] then return end
    local curr = route[i]
    local prev, nxt
    if a.routeType == "backforth" then
        local dir = a.dir or 1
        local pi, ni = i - dir, i + dir
        if pi >= 1 and pi <= n then prev = route[pi] end
        if ni >= 1 and ni <= n then
            nxt = route[ni]
        elseif ni > n then
            nxt = route[math.max(1, n - 1)]
        else
            nxt = route[math.min(n, 2)]
        end
    else
        prev = route[((i - 2) % n) + 1]
        nxt = route[(i % n) + 1]
    end
    return prev, curr, nxt
end

-- along: yards past (cx,cy) along (dx,dy). lateral: perpendicular yards.
function Arrow.ProjectAround(px, py, cx, cy, dx, dy)
    local len = math.sqrt(dx * dx + dy * dy)
    if not len or len < 1e-6 then return 0, 0 end
    local ux, uy = dx / len, dy / len
    local vx, vy = px - cx, py - cy
    local along = vx * ux + vy * uy
    local lat = math.abs(vx * uy - vy * ux)
    return along, lat
end

local function StopWorld(mapID, stop)
    if not stop then return end
    local _, wx, wy = WorldXY(mapID, stop.x / 100, stop.y / 100)
    if wx and wy then return wx, wy end
    return (stop.x / 100) * 1000, (stop.y / 100) * 1000
end

-- True when the player has gone past the current stop on either side
-- (or cut toward the next stop) within PASS_YARDS of the path, without
-- entering the arrival radius. Never auto-skips out of the route's zone.
function Arrow:ShouldAutoSkip()
    if not self.active or not self:InZone() then return false end
    if self.active.routeType == "cave" then return false end
    if self._lockout and self._lockout > 0 then return false end
    local prev, curr, nxt = self:AdjacentStops()
    if not curr then return false end
    local yards = self:YardsTo(curr)
    if yards and yards <= ARRIVE_YARDS then return false end

    local px, py, pMap = self:PlayerMapXY()
    if not px or not py then return false end
    local mapID = self.active.mapID
    local cwx, cwy = StopWorld(mapID, curr)
    local pwx, pwy
    local _, wx, wy = WorldXY(pMap or mapID, px, py)
    if wx and wy then
        pwx, pwy = wx, wy
    else
        pwx, pwy = px * 1000, py * 1000
    end
    if not (cwx and pwx) then return false end

    local dx, dy
    if prev then
        local prx, pry = StopWorld(mapID, prev)
        if prx then dx, dy = cwx - prx, cwy - pry end
    end
    if (not dx) and nxt then
        local nx, ny = StopWorld(mapID, nxt)
        if nx then dx, dy = nx - cwx, ny - cwy end
    end
    if not dx then return false end

    local along, lat = Arrow.ProjectAround(pwx, pwy, cwx, cwy, dx, dy)
    if along > PAST_EPS and lat <= PASS_YARDS then
        return true
    end

    -- Already closer to the next stop than to the current one, and still
    -- within PASS_YARDS of the outgoing leg. This catches a corner cut
    -- once the player is clearly on the way to the next stop, without
    -- treating a wide miss (more than 10 yd off the stop) as a pass.
    if nxt then
        local nx, ny = StopWorld(mapID, nxt)
        if nx then
            local dPlayerN = math.sqrt((pwx - nx) ^ 2 + (pwy - ny) ^ 2)
            local dPlayerC = yards or math.sqrt((pwx - cwx) ^ 2 + (pwy - cwy) ^ 2)
            local along2, lat2 = Arrow.ProjectAround(pwx, pwy, cwx, cwy, nx - cwx, ny - cwy)
            if dPlayerN < dPlayerC and lat2 <= PASS_YARDS and along2 > PAST_EPS then
                return true
            end
        end
    end
    return false
end

local function ApplyArrowTexture(tex)
    if not tex then return end
    Arrow._texTried = {}
    Arrow._texLoaded = nil
    for _, path in ipairs(TEX_PATHS) do
        local ok, err = pcall(function() tex:SetTexture(path) end)
        Arrow._texTried[path] = ok
        if not ok then
            Arrow._texError = tostring(err)
        elseif tex.GetTexture then
            local got = tex:GetTexture()
            if got and got ~= "" then
                Arrow._texLoaded = path
                return path
            end
        else
            Arrow._texLoaded = path
            return path
        end
    end
    Arrow._texLoaded = nil
    Arrow._texError = Arrow._texError or "no arrow texture loaded"
end

local function Outline(fs, size)
    if not fs then return end
    local font, px, flags
    if GameFontHighlight and GameFontHighlight.GetFont then
        font, px, flags = GameFontHighlight:GetFont()
    end
    local TH = ns.Theme
    if TH and TH.bundledFonts and TH.bundledFonts.bold then
        font = TH.FONT_FILES.bold
    end
    if font and fs.SetFont then
        pcall(fs.SetFont, fs, font, size or px or 12, "OUTLINE")
    elseif fs.SetFontObject then
        fs:SetFontObject(GameFontHighlight)
    end
    if fs.SetShadowColor then
        fs:SetShadowColor(0, 0, 0, 1)
        fs:SetShadowOffset(1, -1)
    end
    fs:SetTextColor(1, 1, 1)
end

-- Pick the pre-rendered 3D frame for this heading. Angle 0 is forward
-- (into the screen); increasing angle is counterclockwise, matching
-- SetRotation. The sheet texture itself is never rotated.
local function ApplyArrowFrame(tex, angle)
    if not tex then return end
    local i = Arrow.FrameIndex(angle)
    local col = i % SHEET_COLS
    local row = math.floor(i / SHEET_COLS)
    -- 1-texel inset avoids bilinear bleed from the next cell. The sheet
    -- itself leaves a safe margin around every heading, so this does not clip.
    local inset = 1 / SHEET_SIZE
    local u0 = col / SHEET_COLS + inset
    local u1 = (col + 1) / SHEET_COLS - inset
    local v0 = row / SHEET_ROWS + inset
    local v1 = (row + 1) / SHEET_ROWS - inset
    if tex.SetTexCoord then tex:SetTexCoord(u0, u1, v0, v1) end
    Arrow._frame = i
end

local function StyleArrow(tex, dim, near)
    if not tex then return end
    if not Arrow._texLoaded then ApplyArrowTexture(tex) end
    if dim then
        tex:SetVertexColor(0.50, 0.50, 0.54, 0.80)
    elseif near then
        tex:SetVertexColor(GREEN[1], GREEN[2], GREEN[3], 1)
    else
        tex:SetVertexColor(GOLD[1], GOLD[2], GOLD[3], 1)
    end
end

local function TextButton(parent, label, width, click)
    local b = SafeFrame("Button", nil, parent)
    if not b then return end
    b:SetSize(width, 22)
    if b.EnableMouse then b:EnableMouse(true) end
    if b.RegisterForClicks then b:RegisterForClicks("LeftButtonUp") end
    local fs = b:CreateFontString(nil, "OVERLAY", "GatherpediaFontHighlightSmall")
    fs:SetPoint("CENTER", 0, 0)
    fs:SetText(label)
    b.label = fs
    if ns.Theme and ns.Theme.SkinButton then ns.Theme:SkinButton(b, "quiet") end
    b:SetScript("OnClick", click)
    return b
end

function Arrow:Locked()
    return ns.db and ns.db.arrow and ns.db.arrow.locked
end

function Arrow:SetLocked(on)
    if ns.db then
        ns.db.arrow = ns.db.arrow or {}
        ns.db.arrow.locked = not not on
    end
end

function Arrow:Create()
    if self.frame then return self.frame end
    local f = SafeFrame("Frame", "GatherpediaArrowFrame", UIParent)
    if not f then return nil end
    f:SetSize(220, 210)
    f:SetFrameStrata("DIALOG")
    if f.SetFrameLevel then f:SetFrameLevel(120) end
    if f.SetClampedToScreen then f:SetClampedToScreen(true) end
    f:SetMovable(true)
    f:EnableMouse(true)
    if f.RegisterForDrag then f:RegisterForDrag("LeftButton") end
    if f.RegisterForClicks then f:RegisterForClicks("LeftButtonUp", "RightButtonUp") end
    f:SetScript("OnDragStart", function(frame)
        if Arrow:Locked() then return end
        if frame.StartMoving then frame:StartMoving() end
    end)
    f:SetScript("OnDragStop", function(frame)
        if frame.StopMovingOrSizing then frame:StopMovingOrSizing() end
        if ns.db then
            ns.db.arrow = ns.db.arrow or {}
            local point, _, rel, x, y = frame:GetPoint(1)
            ns.db.arrow.point, ns.db.arrow.rel, ns.db.arrow.x, ns.db.arrow.y = point, rel, x, y
        end
    end)
    f:SetScript("OnMouseUp", function(_, button)
        if button == "RightButton" then
            Arrow:ToggleMenu()
        end
    end)

    -- The 3D arrow itself, with its drop shadow baked into the sheet.
    f.arrow = f:CreateTexture(nil, "ARTWORK")
    f.arrow:SetSize(ARROW_SIZE, ARROW_SIZE)
    f.arrow:SetPoint("TOP", 0, -10)
    ApplyArrowTexture(f.arrow)
    ApplyArrowFrame(f.arrow, 0)
    f.arrow:SetVertexColor(GOLD[1], GOLD[2], GOLD[3], 1)

    f.plate = SafeFrame("Frame", nil, f)
    if f.plate and ns.Theme then
        ns.Theme:Panel(f.plate, ns.Theme.C.window, nil, 8)
        ns.Theme:PanelColors(f.plate, ns.Theme.C.window, nil, 0.55)
    end
    local textHost = f.plate or f
    f.stop = textHost:CreateFontString(nil, "OVERLAY")
    Outline(f.stop, 13)
    f.stop:SetPoint("TOP", f.arrow, "BOTTOM", 0, -6)
    f.stop:SetWidth(200)
    if f.stop.SetJustifyH then f.stop:SetJustifyH("CENTER") end

    f.dist = textHost:CreateFontString(nil, "OVERLAY")
    Outline(f.dist, 13)
    f.dist:SetPoint("TOP", f.stop, "BOTTOM", 0, -2)
    f.dist:SetTextColor(GOLD[1], GOLD[2], GOLD[3])
    f.dist:SetWidth(200)
    if f.dist.SetJustifyH then f.dist:SetJustifyH("CENTER") end

    if f.plate then
        -- Anchored to the arrow, not to its own text, so nothing loops.
        f.plate:SetPoint("TOP", f.arrow, "BOTTOM", 0, -1)
        f.plate:SetSize(120, 42)
        -- Fit the plate to the longer line.
        f.plate:SetScript("OnUpdate", function(pl)
            local w1 = f.stop.GetStringWidth and f.stop:GetStringWidth() or 0
            local w2 = f.dist.GetStringWidth and f.dist:GetStringWidth() or 0
            local w = math.max(w1, w2) + 26
            if math.abs((pl:GetWidth() or 0) - w) > 1 then pl:SetWidth(w) end
        end)
    end
    f.btns = SafeFrame("Frame", nil, f)
    f.btns:SetSize(200, 50)
    f.btns:SetPoint("TOP", f.dist, "BOTTOM", 0, -8)
    f.prev = TextButton(f.btns, "Prev", 56, function() Arrow:Prev() end)
    f.next = TextButton(f.btns, "Next", 56, function() Arrow:Next() end)
    f.stopBtn = TextButton(f.btns, "Stop", 56, function() Arrow:Stop() end)
    if f.prev then f.prev:SetPoint("TOP", -62, 0) end
    if f.next then f.next:SetPoint("TOP", 0, 0) end
    if f.stopBtn then f.stopBtn:SetPoint("TOP", 62, 0) end
    f.showMap = TextButton(f.btns, "Show on map", 140, function() Arrow:ShowOnMap() end)
    if f.showMap then f.showMap:SetPoint("TOP", 0, -26) end
    f.btns:Hide()

    local function hovering()
        if not MouseIsOver then return false end
        if MouseIsOver(f) then return true end
        if f.btns and f.btns:IsShown() and MouseIsOver(f.btns) then return true end
        return false
    end
    f:SetScript("OnEnter", function() f.btns:Show() end)
    f:SetScript("OnLeave", function()
        if not hovering() then f.btns:Hide() end
    end)
    f.btns:SetScript("OnEnter", function() f.btns:Show() end)
    f.btns:SetScript("OnLeave", function()
        if not hovering() then f.btns:Hide() end
    end)

    f:SetScript("OnUpdate", function(frame, elapsed)
        if frame.btns and frame.btns:IsShown() and not hovering() then
            frame.btns:Hide()
        end
    end)
    f:Hide()
    self.frame = f
    self:ApplyScale()
    return f
end

-- Per-character arrow size, 50% to 200% in 5% steps. SetScale on the
-- whole HUD so the art, Follow Path title, distance and hover buttons
-- grow together; the saved anchor point stays put.
local function SnapPercent(pct)
    pct = tonumber(pct) or 100
    pct = math.floor(pct / 5 + 0.5) * 5
    if pct < 50 then pct = 50 end
    if pct > 200 then pct = 200 end
    return pct
end

function Arrow:ScalePercent()
    local v = ns.charDB and tonumber(ns.charDB.arrowScale)
    return SnapPercent((v or 1) * 100)
end

function Arrow:SetScalePercent(pct)
    pct = SnapPercent(pct)
    if ns.charDB then ns.charDB.arrowScale = pct / 100 end
    self:ApplyScale()
    if self.RefreshMenu then self:RefreshMenu() end
end

function Arrow:ApplyScale()
    local f = self.frame
    if f and f.SetScale then
        f:SetScale(self:ScalePercent() / 100)
    end
end

function Arrow:ApplyPosition()
    local f = self.frame
    if not f then return end
    f:ClearAllPoints()
    local p = ns.db and ns.db.arrow
    if p and p.point then
        f:SetPoint(p.point, UIParent, p.rel or p.point, p.x or 0, p.y or 0)
    else
        f:SetPoint("TOP", UIParent, "TOP", 0, -180)
    end
    self:ApplyScale()
end

function Arrow:OnUpdate(dt)
    if self._lockout and self._lockout > 0 then
        self._lockout = self._lockout - (dt or 0)
    end
    self:Update()
end

function Arrow:Update()
    local a = self.active
    local f = self.frame
    if not a then
        if f then f:Hide() end
        return
    end
    f = self:Create()
    if not f then return end
    f:Show()
    if f.arrow then f.arrow:Show() end

    if not self:InZone() then
        StyleArrow(f.arrow, true)
        ApplyArrowFrame(f.arrow, 0)
        f.stop:SetText(self:OutOfZoneText())
        f.stop:SetTextColor(0.85, 0.85, 0.85, 1)
        f.dist:SetText("")
        self.angle, self.yards = 0, nil
        return
    end

    if a.needSnap then
        a.needSnap = nil
        if self:SnapToNearest() then
            return self:Update()
        end
        a.needSnap = true   -- position not ready yet, retry next tick
    end

    local stop, i, n = self:CurrentStop()
    local yards = self:YardsTo(stop)
    local cave = a.routeType == "cave"
    if cave then
        f.stop:SetText((yards and yards <= ARRIVE_YARDS) and "Farm this cave" or "Go to the cave")
    else
        f.stop:SetText("Follow Path")
    end
    f.stop:SetTextColor(1, 1, 1, 1)
    StyleArrow(f.arrow, false, yards and yards <= ARRIVE_YARDS)
    if yards then
        local shown = math.floor(yards + 0.5)
        if shown < 1 then shown = 1 end
        f.dist:SetText(shown .. " yd")
        local near = yards <= ARRIVE_YARDS
        local col = near and GREEN or GOLD
        f.dist:SetTextColor(col[1], col[2], col[3], 1)
        if cave then
            -- Caves never advance: stay pointed at the entrance.
            self._arrived = yards <= ARRIVE_YARDS
        elseif yards <= ARRIVE_YARDS and (not self._lockout or self._lockout <= 0) then
            if not self._arrived then
                self._arrived = true
                self:Next()
                return
            end
        else
            self._arrived = false
            if (not self._lockout or self._lockout <= 0) and self:ShouldAutoSkip() then
                self:Next()
                return
            end
        end
    else
        f.dist:SetText("")
    end

    -- Point the arrow. Facing comes straight from GetPlayerFacing; it is
    -- not run through a secret filter that could drop a valid heading.
    local facing = Num(GetPlayerFacing and PCall(GetPlayerFacing))
    self._facing = facing
    local px, py, pMap = self:PlayerMapXY()
    if not stop then
        self._lastError = "no current stop"
        return
    end
    if not facing or not px then
        ApplyArrowFrame(f.arrow, self.angle or 0)
        self._lastError = (not facing and "facing unavailable") or "position unavailable"
        return
    end
    local tx, ty = stop.x / 100, stop.y / 100
    local c1, wx1, wy1 = WorldXY(pMap or a.mapID, px, py)
    local c2, wx2, wy2 = WorldXY(a.mapID, tx, ty)
    local angle
    if c1 and c2 and c1 == c2 and wx1 and wx2 then
        angle = Arrow.Angle(wx1, wy1, wx2, wy2, facing, false)
    else
        angle = Arrow.Angle(px, py, tx, ty, facing, true)
    end
    ApplyArrowFrame(f.arrow, angle)
    self.angle, self.yards = angle, yards
    self._lastError = nil
end


function Arrow:EnsureMenu()
    if self.menu then return self.menu end
    local f = SafeFrame("Frame", "GatherpediaArrowMenu", UIParent, "BackdropTemplate")
    if not f then return nil end
    f:SetSize(220, 150)
    f:SetFrameStrata("FULLSCREEN_DIALOG")
    if f.SetFrameLevel then f:SetFrameLevel(130) end
    if f.SetClampedToScreen then f:SetClampedToScreen(true) end
    if ns.Theme then
        ns.Theme:Panel(f, ns.Theme.C.side, ns.Theme.C.line2, 8)
    elseif f.SetBackdrop then
        f:SetBackdrop({
            bgFile = WHITE,
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            edgeSize = 12,
            insets = { left = 3, right = 3, top = 3, bottom = 3 },
        })
        f:SetBackdropColor(0.06, 0.055, 0.065, 0.97)
        f:SetBackdropBorderColor(GOLD[1], GOLD[2], GOLD[3], 0.9)
    end
    f:EnableMouse(true)
    f:Hide()
    if tinsert and UISpecialFrames then tinsert(UISpecialFrames, "GatherpediaArrowMenu") end

    f.title = f:CreateFontString(nil, "OVERLAY", "GatherpediaFontHeading")
    f.title:SetPoint("TOPLEFT", 10, -10)
    f.title:SetPoint("TOPRIGHT", -10, -10)
    f.title:SetJustifyH("LEFT")
    f.title:SetTextColor(GOLD[1], GOLD[2], GOLD[3])
    f.title:SetText("Follow Path")

    f.skip = SafeFrame("Button", nil, f)
    if f.skip then
        f.skip:SetHeight(18)
        f.skip:SetPoint("TOPLEFT", 10, -32)
        f.skip:SetPoint("RIGHT", -10, 0)
        if f.skip.EnableMouse then f.skip:EnableMouse(true) end
        if f.skip.RegisterForClicks then f.skip:RegisterForClicks("LeftButtonUp") end
        f.skip.label = f.skip:CreateFontString(nil, "OVERLAY", "GatherpediaFontHighlightSmall")
        f.skip.label:SetPoint("LEFT")
        f.skip.label:SetTextColor(1, 1, 1, 1)
        f.skip.label:SetText("Skip to next stop")
        f.skip:SetScript("OnClick", function()
            Arrow:Next()
            Arrow:CloseMenu()
        end)
    end

    f.stopRoute = SafeFrame("Button", nil, f)
    if f.stopRoute then
        f.stopRoute:SetHeight(18)
        f.stopRoute:SetPoint("TOPLEFT", 10, -52)
        f.stopRoute:SetPoint("RIGHT", -10, 0)
        if f.stopRoute.EnableMouse then f.stopRoute:EnableMouse(true) end
        if f.stopRoute.RegisterForClicks then f.stopRoute:RegisterForClicks("LeftButtonUp") end
        f.stopRoute.label = f.stopRoute:CreateFontString(nil, "OVERLAY", "GatherpediaFontHighlightSmall")
        f.stopRoute.label:SetPoint("LEFT")
        f.stopRoute.label:SetTextColor(1, 1, 1, 1)
        f.stopRoute.label:SetText("Stop route")
        f.stopRoute:SetScript("OnClick", function()
            Arrow:Stop()
        end)
    end

    f.lock = SafeFrame("Button", nil, f)
    if f.lock then
        f.lock:SetHeight(18)
        f.lock:SetPoint("TOPLEFT", 10, -72)
        f.lock:SetPoint("RIGHT", -10, 0)
        f.lock.label = f.lock:CreateFontString(nil, "OVERLAY", "GatherpediaFontHighlightSmall")
        f.lock.label:SetPoint("LEFT")
        f.lock:SetScript("OnClick", function()
            Arrow:SetLocked(not Arrow:Locked())
            Arrow:RefreshMenu()
        end)
    end

    -- Hover highlight on the three action rows.
    for _, row in ipairs({ f.skip, f.stopRoute, f.lock }) do
        if row and ns.Theme then
            row.hl = row:CreateTexture(nil, "BACKGROUND")
            row.hl:SetPoint("TOPLEFT", -4, 1)
            row.hl:SetPoint("BOTTOMRIGHT", 4, -1)
            row.hl:SetColorTexture(ns.Theme.C.raised[1], ns.Theme.C.raised[2], ns.Theme.C.raised[3], 0)
            ns.Theme:HoverPaint(row,
                function(r) r.hl:SetAlpha(1); r.label:SetTextColor(ns.Theme.C.goldHi[1], ns.Theme.C.goldHi[2], ns.Theme.C.goldHi[3]) end,
                function(r) r.hl:SetAlpha(0); r.label:SetTextColor(ns.Theme.C.text[1], ns.Theme.C.text[2], ns.Theme.C.text[3]) end)
            row.hl:SetAlpha(0)
        end
    end

    -- Size: the same slider as the Options window.
    if ns.Theme and ns.Theme.SliderRow then
        f.slider = ns.Theme:SliderRow(f, 196, "Arrow size", 50, 200, 5, "%d%%",
            function() return Arrow:ScalePercent() end,
            function(v) Arrow:SetScalePercent(v) end)
        f.slider:SetPoint("TOPLEFT", 12, -98)
    end

    if not f.watcher then
        f.watcher = CreateFrame("Frame")
        f.watcher:SetScript("OnEvent", function()
            if not (Arrow.menu and Arrow.menu:IsShown()) then return end
            if Arrow.menu.IsMouseOver and Arrow.menu:IsMouseOver() then return end
            if Arrow.frame and Arrow.frame.IsMouseOver and Arrow.frame:IsMouseOver() then return end
            Arrow:CloseMenu()
        end)
        pcall(f.watcher.RegisterEvent, f.watcher, "GLOBAL_MOUSE_DOWN")
    end

    self.menu = f
    return f
end

function Arrow:RefreshMenu()
    local f = self.menu
    if not f then return end
    local name
    if self.active and self.active.label and self.active.label ~= "" then
        name = self.active.label
    else
        name = "Follow Path"
    end
    if f.title then f.title:SetText(name) end
    if f.lock and f.lock.label then
        f.lock.label:SetText(self:Locked() and "Unlock arrow" or "Lock arrow")
    end
    if f.slider and f.slider.Refresh then f.slider:Refresh() end
end

function Arrow:CloseMenu()
    if self.menu then self.menu:Hide() end
end

function Arrow:ToggleMenu()
    self:EnsureMenu()
    if not self.menu then return end
    if self.menu:IsShown() then
        self:CloseMenu()
        return
    end
    self:RefreshMenu()
    self.menu:ClearAllPoints()
    local owner = self.frame or UIParent
    self.menu:SetPoint("TOPLEFT", owner, "TOPRIGHT", 8, 0)
    self.menu:Show()
end

function Arrow:DebugLines()
    local lines = { "Arrow:" }
    local f = self.frame
    lines[#lines + 1] = "  frame shown: " .. tostring(not not (f and f.IsShown and f:IsShown()))
    lines[#lines + 1] = "  graphic shown: " .. tostring(not not (f and f.arrow and f.arrow.IsShown and f.arrow:IsShown()))
    if f and f.GetPoint then
        local point, _, _, x, y = f:GetPoint(1)
        lines[#lines + 1] = string.format("  position: %s (%.1f, %.1f)", tostring(point), x or 0, y or 0)
    end
    lines[#lines + 1] = "  locked: " .. tostring(not not self:Locked())
    lines[#lines + 1] = "  scale: " .. tostring(self:ScalePercent()) .. "%"
    lines[#lines + 1] = "  texture: " .. tostring(self._texLoaded or "none")
    lines[#lines + 1] = "  frame: " .. tostring(self._frame)
    if self._texTried then
        for path, ok in pairs(self._texTried) do
            lines[#lines + 1] = "    tried " .. path .. ": " .. (ok and "ok" or "fail")
        end
    end
    local a = self.active
    local best = self:PlayerMapID()
    lines[#lines + 1] = "  best map ID: " .. tostring(best)
    lines[#lines + 1] = "  route map ID: " .. tostring(a and a.mapID)
    local rx, ry
    if a and a.mapID then
        rx, ry = self:CoordsOnMap(a.mapID)
    end
    if self._routeXY then rx, ry = self._routeXY[1], self._routeXY[2] end
    if rx then
        lines[#lines + 1] = string.format("  player coords on route map: %.4f, %.4f", rx, ry)
    else
        lines[#lines + 1] = "  player coords on route map: nil"
    end
    local inside = self:InZone()
    lines[#lines + 1] = "  in-zone: " .. (inside and "yes" or "no") .. " (" .. tostring(self._inZoneWhy) .. ")"
    lines[#lines + 1] = "  facing: " .. tostring(self._facing)
    lines[#lines + 1] = "  yards: " .. tostring(self.yards)
    lines[#lines + 1] = "  last error: " .. tostring(self._lastError or self._texError or "none")
    if a then
        lines[#lines + 1] = "  routeType: " .. tostring(a.routeType or "loop")
        lines[#lines + 1] = "  dir: " .. tostring(a.dir or 1)
        lines[#lines + 1] = "  step: " .. tostring(a.step)
    end
    return lines
end

-- A dedicated driver so the arrow keeps ticking while a route is
-- active, even if the HUD frame's OnUpdate does not fire.
function Arrow:EnsureDriver()
    if not self.driver then
        local d = SafeFrame("Frame", "GatherpediaArrowDriver", UIParent)
        if not d then return end
        d:SetScript("OnUpdate", function(frame, elapsed)
            if not Arrow.active then
                if frame.Hide then frame:Hide() end
                return
            end
            if Arrow.frame and Arrow.frame.Show and not (Arrow.frame.IsShown and Arrow.frame:IsShown()) then
                Arrow.frame:Show()
            end
            frame.t = (frame.t or 0) + (elapsed or 0)
            if frame.t < 0.05 then return end
            local dt = frame.t
            frame.t = 0
            Arrow:OnUpdate(dt)
        end)
        self.driver = d
    end
    if self.driver.Show then self.driver:Show() end
end

-- Events: hide or show when the zone changes.
local ev = CreateFrame("Frame")
ev:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_ENTERING_WORLD" and not Arrow.active then
        Arrow:Restore()
    end
    if Arrow.active then Arrow:Update() end
end)
for _, name in ipairs({
    "PLAYER_ENTERING_WORLD", "ZONE_CHANGED", "ZONE_CHANGED_NEW_AREA", "ZONE_CHANGED_INDOORS",
}) do
    pcall(ev.RegisterEvent, ev, name)
end
