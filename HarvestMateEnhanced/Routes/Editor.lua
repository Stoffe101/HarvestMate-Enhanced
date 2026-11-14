-- HarvestMate Enhanced: Routes/Editor.lua
-- Editing a route's waypoints on the world map, by hand:
--   left-click      adds a waypoint where it lengthens the loop least
--   right-click     removes the nearest waypoint (within a few pixels)
--   Reverse         rides the loop the other way
--   Undo            takes the last change back (20 steps)
--   Done / Cancel   keeps the edits (the route is then "edited by you") or
--                   puts the route back as it was
-- The map still pans and zooms (the same canvas click handler GatherPath's
-- avoid-area drawing uses). Nothing happens in combat. An edited route is
-- protected: the Farm Finder makes a new route instead of replanning it, and
-- Rebuild asks first.
--
-- Route quality: where a route came from and how far to trust its path.
-- Copyright (C) 2026 HarvestMate Enhanced contributors. GPL-3.0-or-later.

local _, ns = ...
local HME = ns.HME
local T = ns.Theme
local U = HME.U

local E = {}
HME.RouteEditor = E

E.UNDO = 20
E.PICK_PX = 14
local st   -- { route, before, undo = {}, handler }

local function Copy(points) local c = {} for i, v in ipairs(points) do c[i] = v end return c end

local function Push()
    U.Push(st.undo, Copy(st.route.points), E.UNDO)
end

local function Changed()
    local GP = HME.Routes
    st.route.length = GP:RouteLength(st.route)
    GP:Changed()
    E.UpdateBar()
end

-- Inserts (x, y) on the leg where it adds the least length.
function E.AddPoint(route, x, y)
    local p = route.points
    local n = #p / 2
    local w, h = HME.Geo.MapYards(route.mapID)
    w, h = w or 1500, h or 1000
    local best, cost = n, math.huge
    for i = 1, n do
        local j = i % n + 1
        local ax, ay, bx, by = p[2 * i - 1] * w, p[2 * i] * h, p[2 * j - 1] * w, p[2 * j] * h
        local c = U.Dist(ax, ay, x * w, y * h) + U.Dist(x * w, y * h, bx, by) - U.Dist(ax, ay, bx, by)
        if c < cost then best, cost = i, c end
    end
    table.insert(p, 2 * best + 1, U.Round(x, 4))
    table.insert(p, 2 * best + 2, U.Round(y, 4))
    return best + 1
end

-- Removes the waypoint nearest (x, y) if within `tol` (map share). Keeps 3.
function E.RemovePoint(route, x, y, tol)
    local p = route.points
    if #p <= 6 then return false end
    local best, bd
    for i = 1, #p / 2 do
        local d = U.Dist(p[2 * i - 1], p[2 * i], x, y)
        if not bd or d < bd then best, bd = i, d end
    end
    if not best or bd > (tol or 0.01) then return false end
    table.remove(p, 2 * best - 1)
    table.remove(p, 2 * best - 1)
    return true
end

function E.ReversePoints(route)
    local p, out = route.points, {}
    for i = #p / 2, 1, -1 do
        out[#out + 1] = p[2 * i - 1]
        out[#out + 1] = p[2 * i]
    end
    route.points = out
end

local function Click(map, button, cx, cy)
    if not st or not map or map:GetMapID() ~= st.route.mapID or not cx then return false end
    if HME.InCombat() then return true end
    if button == "LeftButton" then
        Push()
        E.AddPoint(st.route, cx, cy)
        Changed()
        return true
    elseif button == "RightButton" then
        local canvasW = map.DenormalizeHorizontalSize and map:DenormalizeHorizontalSize(1) or 1000
        local scale = 1
        local sc = rawget(map, "ScrollContainer")
        if type(sc) == "table" and sc.GetCanvasScale then scale = sc:GetCanvasScale() or 1 end
        local before = Copy(st.route.points)
        if E.RemovePoint(st.route, cx, cy, E.PICK_PX / math.max(1, canvasW * scale)) then
            U.Push(st.undo, before, E.UNDO)
            Changed()
            return true
        end
        return false   -- nothing near: let the map zoom out as usual
    end
    return false
end

local bar
local function Bar()
    if bar then return bar end
    local parent = _G.WorldMapFrame
    bar = CreateFrame("Frame", "HarvestMateEnhancedRouteEditBar", parent)
    bar:SetSize(520, 34)
    bar:SetPoint("TOP", parent, "TOP", 0, -70)
    bar:SetFrameStrata("DIALOG")
    T.Panel(bar, 0.92)
    bar.text = T.Text(bar, "", "GameFontHighlightSmall")
    bar.text:SetPoint("LEFT", 10, 0)
    bar.text:SetWidth(220)
    local function B(label, fn, x)
        local b = HME.Kit.Button(bar, label, 66, 22, fn)
        b:SetPoint("RIGHT", x, 0)
        return b
    end
    B("Cancel", function() E.Cancel() end, -8)
    B("Done", function() E.Finish() end, -78)
    B("Undo", function() E.Undo() end, -148)
    B("Reverse", function() E.Reverse() end, -218)
    bar:Hide()
    return bar
end

function E.UpdateBar()
    if not (bar and st) then return end
    bar.text:SetText(("|cffffd100%s|r: %d waypoints, %s. Left-click adds, right-click removes."):format(
        st.route.name, #st.route.points / 2, U.Yards(st.route.length or 0)))
end

function E.Start(route)
    if not route or HME.InCombat() then
        HME.Print("routes can be edited out of combat.")
        return false
    end
    if st then E.Cancel() end
    st = { route = route, before = Copy(route.points), undo = {} }
    local map = _G.WorldMapFrame
    if _G.OpenWorldMap then pcall(_G.OpenWorldMap, route.mapID) end
    if map and map.AddCanvasClickHandler then
        map:AddCanvasClickHandler(Click, 110)
        st.handler = true
    end
    Bar():Show()
    E.UpdateBar()
    if HME.Window and HME.Window.frame then HME.Window.frame:Hide() end
    return true
end

local function End()
    local map = _G.WorldMapFrame
    if st and st.handler and map and map.RemoveCanvasClickHandler then map:RemoveCanvasClickHandler(Click) end
    if bar then bar:Hide() end
    st = nil
end

function E.Undo()
    if not st then return end
    local prev = table.remove(st.undo)
    if prev then
        st.route.points = prev
        Changed()
    end
end

function E.Reverse()
    if not st then return end
    Push()
    E.ReversePoints(st.route)
    Changed()
end

function E.Finish()
    if not st then return end
    local r = st.route
    if #st.undo > 0 then
        r.edited = true
        r.verified = "you"
        r.editedAt = (time and time()) or 0
    end
    End()
    HME.Routes:Changed()
    HME.Print(("|cffffd100%s|r saved (%s)."):format(r.name, r.edited and "edited by you" or "unchanged"))
end

function E.Cancel()
    if not st then return end
    st.route.points = st.before
    local r = st.route
    End()
    r.length = HME.Routes:RouteLength(r)
    HME.Routes:Changed()
end

function E.Active() return st ~= nil end
HME.On("PLAYER_REGEN_DISABLED", function() if st then E.Finish() end end)

---------------------------------------------------------------------------
-- Route quality
---------------------------------------------------------------------------
-- { source, trust = "verified"|"recorded"|"approximate"|"imported", text, longLegs, laps }
function E.Quality(route)
    local q = { laps = route.laps or 0 }
    if route.recorded then
        q.source, q.trust = "recorded in game (Gatherpedia)", "recorded"
    elseif route.edited then
        q.source, q.trust = "edited by you", "verified"
    elseif route.imported then
        q.source, q.trust = "imported", "imported"
    elseif route.source == "GatherPath" then
        q.source, q.trust = "from GatherPath", "approximate"
    else
        q.source, q.trust = route.planned and "planned by the Farm Finder" or "made from nodes", "approximate"
    end
    -- Long straight legs are where cliffs, water or walls may hide.
    local p = route.points or {}
    local w, h = HME.Geo.MapYards(route.mapID)
    w, h = w or 1500, h or 1000
    local long = 0
    for i = 1, #p / 2 do
        local j = i % (#p / 2) + 1
        if U.Dist(p[2 * i - 1] * w, p[2 * i] * h, p[2 * j - 1] * w, p[2 * j] * h) > 350 then long = long + 1 end
    end
    q.longLegs = long
    if q.trust == "approximate" and q.laps >= 2 then q.trust = "verified" end
    local parts = { q.source }
    if q.trust == "approximate" then parts[#parts + 1] = "straight lines, terrain unknown" end
    if long > 0 and q.trust ~= "recorded" then parts[#parts + 1] = long .. " long leg" .. (long == 1 and "" or "s") .. " to check" end
    if q.laps > 0 then parts[#parts + 1] = q.laps .. " lap" .. (q.laps == 1 and "" or "s") .. " ridden" end
    q.text = table.concat(parts, " · ")
    return q
end

-- Laps ridden with HME's guidance count as verification.
HME.Listen("GUIDANCE_CHANGED", function()
    local g = HME.Guidance.Active()
    if not (g and g.phase == "farm") then return end
    if g.lastStop and g.stop and g.stop < g.lastStop then
        local r = HME.Guidance.Route(g.routeID)
        if r then r.laps = (r.laps or 0) + 1 end
    end
    g.lastStop = g.stop
end)
