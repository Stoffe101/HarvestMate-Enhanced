-- HarvestMate Enhanced: Routes/Editor.lua
-- Editing a route's waypoints on the world map, by hand:
--   left-click      adds a waypoint where it lengthens the loop least
--   right-click     removes the nearest waypoint (within a few pixels)
--   shift-click     picks up the nearest waypoint; the next click puts it
--                   down there (moving a waypoint; right-click drops it back)
--   Snap            new and moved waypoints land on a known node of the
--                   route's kinds within 20 yards (on by default; herb, ore
--                   and fishing routes only: beasts wander)
--   Reverse         rides the loop the other way
--   Undo / Redo     takes the last change back, or puts it back (20 steps)
--   Done / Cancel   keeps the edits (the route is then "edited by you") or
--                   puts the route back as it was
-- The map still pans and zooms (the same canvas click handler GatherPath's
-- avoid-area drawing uses). Nothing happens in combat. An edited route is
-- protected: the Farm Finder makes a new route instead of replanning it, and
-- Rebuild asks first.
--
-- Versions (0.7.0): every saved edit, rebuild, restore and trim keeps the
-- waypoints it replaced (route.revisions, 6 kept); the Route Inspector lists
-- them and puts one back. Restoring keeps the current waypoints as a version
-- too, so nothing is lost by restoring.
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
E.SNAP_YARDS = 20
E.REVISIONS = 6
local st   -- { route, before, undo = {}, redo = {}, handler, moving = index, snap = bool }

local function Copy(points) local c = {} for i, v in ipairs(points) do c[i] = v end return c end

local function Push()
    U.Push(st.undo, Copy(st.route.points), E.UNDO)
    st.redo = {}
end

local function Same(a, b)
    if type(a) ~= "table" or type(b) ~= "table" or #a ~= #b then return false end
    for i = 1, #a do if a[i] ~= b[i] then return false end end
    return true
end

---------------------------------------------------------------------------
-- Versions
---------------------------------------------------------------------------
-- Keeps `points` (the route's own when nil) as a version, with why and when.
-- A version equal to the newest one or to the route as it is now is not kept twice.
function E.Revise(route, why, points)
    if type(route) ~= "table" then return false end
    points = points or route.points
    if type(points) ~= "table" or #points < 4 then return false end
    route.revisions = route.revisions or {}
    local last = route.revisions[#route.revisions]
    if last and Same(last.points, points) then return false end
    U.Push(route.revisions, { t = (time and time()) or 0, why = why or "changed", points = Copy(points),
        length = math.floor((HME.Routes and HME.Routes:RouteLength({ mapID = route.mapID, points = points })) or 0) },
        E.REVISIONS)
    return true
end

-- Puts version i back. The waypoints it replaces are kept as a version.
function E.Restore(route, i)
    local rev = route and route.revisions and route.revisions[i]
    if not rev or st then return false end
    local current = Copy(route.points)
    table.remove(route.revisions, i)
    E.Revise(route, "before restoring an older version", current)
    route.points = Copy(rev.points)
    route.edited = true
    route.verified = "you"
    route.editedAt = (time and time()) or 0
    route.path, route.pathLeg, route.terrain, route.walkLength = nil, nil, nil, nil
    route.length = HME.Routes:RouteLength(route)
    HME.Routes:Changed()
    if HME.Terrain and HME.Terrain.Auto then HME.Terrain.Auto(route) end
    return true
end

-- "3 versions: 2 h ago (before your edit, 12 stops) ..." for the Inspector.
function E.Versions(route)
    local out = {}
    local now = (time and time()) or 0
    for i = #(route and route.revisions or {}), 1, -1 do
        local rev = route.revisions[i]
        local ago = math.max(0, now - (rev.t or now))
        out[#out + 1] = { index = i, why = rev.why, stops = math.floor(#rev.points / 2), length = rev.length,
            ago = ago, text = ("%s ago: %s, %d stops"):format(HME.Bags and HME.Bags.Age(ago) or (math.floor(ago / 60) .. " min"),
                rev.why or "changed", math.floor(#rev.points / 2)) }
    end
    return out
end

---------------------------------------------------------------------------
-- Snapping
---------------------------------------------------------------------------
-- The known node of the route's kinds nearest (x, y), within E.SNAP_YARDS.
-- Returns x, y (snapped or as given) and the node's name when it snapped.
function E.Snap(route, x, y)
    local GP = HME.Routes
    if not (GP and route and route.kinds) then return x, y end
    local best, bd, bx, by
    for kind, names in pairs(route.kinds) do
        if GP.KIND_PROF and GP.KIND_PROF[kind] then
            GP:EachNode(route.mapID, kind, function(nx, ny, name)
                if type(names) ~= "table" or names[name] then
                    local d = HME.Geo.Distance(route.mapID, x, y, nx, ny)
                    if d and d <= E.SNAP_YARDS and (not bd or d < bd) then best, bd, bx, by = name, d, nx, ny end
                end
            end)
        end
    end
    if best then return U.Round(bx, 4), U.Round(by, 4), best end
    return x, y
end

-- The waypoint nearest (x, y) within tol (map share), or nil.
function E.Nearest(route, x, y, tol)
    local p = route.points
    local best, bd
    for i = 1, #p / 2 do
        local d = U.Dist(p[2 * i - 1], p[2 * i], x, y)
        if not bd or d < bd then best, bd = i, d end
    end
    if best and bd <= (tol or 0.01) then return best end
    return nil
end

-- Moves waypoint i to (x, y).
function E.MovePoint(route, i, x, y)
    local p = route.points
    if not (p[2 * i - 1] and p[2 * i]) then return false end
    p[2 * i - 1], p[2 * i] = U.Round(x, 4), U.Round(y, 4)
    return true
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

local function PickTolerance(map)
    local canvasW = map.DenormalizeHorizontalSize and map:DenormalizeHorizontalSize(1) or 1000
    local scale = 1
    local sc = rawget(map, "ScrollContainer")
    if type(sc) == "table" and sc.GetCanvasScale then scale = sc:GetCanvasScale() or 1 end
    return E.PICK_PX / math.max(1, canvasW * scale)
end

local function Place(x, y)
    if st.snap ~= false then
        local sx, sy, name = E.Snap(st.route, x, y)
        st.snapped = name
        return sx, sy
    end
    st.snapped = nil
    return x, y
end

-- The click handler (also called by the tests with a stand-in map).
-- shift: whether Shift is down (read from the client when nil).
function E.Click(map, button, cx, cy, shift)
    if not st or not map or map:GetMapID() ~= st.route.mapID or not cx then return false end
    if HME.InCombat() then return true end
    if shift == nil then shift = _G.IsShiftKeyDown and _G.IsShiftKeyDown() and true or false end
    if button == "LeftButton" then
        if st.moving then
            local x, y = Place(cx, cy)
            Push()
            E.MovePoint(st.route, st.moving, x, y)
            st.moving = nil
            Changed()
            return true
        end
        if shift then
            local i = E.Nearest(st.route, cx, cy, PickTolerance(map))
            if i then
                st.moving = i
                E.UpdateBar()
                return true
            end
        end
        local x, y = Place(cx, cy)
        Push()
        E.AddPoint(st.route, x, y)
        Changed()
        return true
    elseif button == "RightButton" then
        if st.moving then
            st.moving = nil
            E.UpdateBar()
            return true
        end
        local before = Copy(st.route.points)
        if E.RemovePoint(st.route, cx, cy, PickTolerance(map)) then
            U.Push(st.undo, before, E.UNDO)
            st.redo = {}
            Changed()
            return true
        end
        return false   -- nothing near: let the map zoom out as usual
    end
    return false
end
local function Click(...) return E.Click(...) end

local bar
local function Bar()
    if bar then return bar end
    local parent = _G.WorldMapFrame
    bar = CreateFrame("Frame", "HarvestMateEnhancedRouteEditBar", parent)
    bar:SetSize(680, 34)
    bar:SetPoint("TOP", parent, "TOP", 0, -70)
    bar:SetFrameStrata("DIALOG")
    T.Panel(bar, 0.92)
    bar.text = T.Text(bar, "", "GameFontHighlightSmall")
    bar.text:SetPoint("LEFT", 10, 0)
    bar.text:SetWidth(300)
    bar.text:SetWordWrap(true)
    local function B(label, fn, x)
        local b = HME.Kit.Button(bar, label, 66, 22, fn)
        b:SetPoint("RIGHT", x, 0)
        return b
    end
    B("Cancel", function() E.Cancel() end, -8)
    B("Done", function() E.Finish() end, -78)
    B("Redo", function() E.Redo() end, -148)
    B("Undo", function() E.Undo() end, -218)
    B("Reverse", function() E.Reverse() end, -288)
    bar.snap = B("Snap: on", function() E.ToggleSnap() end, -358)
    bar:Hide()
    return bar
end

-- The bar's text (kept apart for the tests).
function E.BarText()
    if not st then return "" end
    local head = ("|cffffd100%s|r: %d waypoints, %s."):format(st.route.name, #st.route.points / 2, U.Yards(st.route.length or 0))
    if st.moving then
        return head .. (" Click where waypoint %d goes; right-click keeps it."):format(st.moving)
    end
    return head .. " Click adds, right-click removes, shift-click moves." .. (st.snapped and (" Snapped to " .. st.snapped .. ".") or "")
end

function E.UpdateBar()
    if not (bar and st) then return end
    bar.text:SetText(E.BarText())
    if bar.snap and bar.snap.SetText then bar.snap:SetText(st.snap == false and "Snap: off" or "Snap: on") end
end

function E.ToggleSnap()
    if not st then return end
    st.snap = st.snap == false
    HME.settings.editorSnap = st.snap
    E.UpdateBar()
end

function E.Start(route)
    if not route or HME.InCombat() then
        HME.Print("routes can be edited out of combat.")
        return false
    end
    if st then E.Cancel() end
    st = { route = route, before = Copy(route.points), undo = {}, redo = {},
           snap = not (HME.settings and HME.settings.editorSnap == false) }
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
    st.moving = nil
    local prev = table.remove(st.undo)
    if prev then
        U.Push(st.redo, Copy(st.route.points), E.UNDO)
        st.route.points = prev
        Changed()
    end
end

function E.Redo()
    if not st then return end
    st.moving = nil
    local nxt = table.remove(st.redo)
    if nxt then
        U.Push(st.undo, Copy(st.route.points), E.UNDO)
        st.route.points = nxt
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
    local changed = not Same(st.before, r.points)
    if changed then
        E.Revise(r, "before your edit", st.before)
        r.edited = true
        r.verified = "you"
        r.editedAt = (time and time()) or 0
    end
    End()
    HME.Routes:Changed()
    HME.Print(("|cffffd100%s|r saved (%s)."):format(r.name, changed and "edited by you; the old waypoints are kept as a version"
        or "unchanged"))
    -- Your waypoints stay as they are; only the legs between them are walked on the grid.
    if changed and HME.Terrain then HME.Terrain.Auto(r) end
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
function E.State() return st end
HME.On("PLAYER_REGEN_DISABLED", function() if st then E.Finish() end end)

---------------------------------------------------------------------------
-- Route quality
---------------------------------------------------------------------------
-- { label, source, trust, text, longLegs, laps, terrain }
-- label (what the Routes page and the map say), most trusted first:
--   "Recorded and observed"  recorded in game and ridden with HME since
--   "Recorded"               recorded in game (by you, or Gatherpedia's guides)
--   "User-corrected"         waypoints edited by you
--   "Terrain-aware"          every leg walked on Forever-GPS's walking grid
--   "Partly terrain-aware"   some legs walked, the rest straight lines
--   "Approximate"            straight lines, terrain unknown
-- A route ridden two laps or more is also "observed". Waypoints an algorithm
-- returned never make a route verified by themselves.
-- trust (kept for older callers): "recorded" | "verified" | "terrain" |
-- "partial" | "approximate" | "imported"
function E.Quality(route)
    local q = { laps = route.laps or 0 }
    local T = HME.Terrain
    local t = T and T.Summary(route)
    q.terrain = t
    if route.recorded then
        q.source = route.recordedBy == "you" and "recorded by you" or "recorded in game (Gatherpedia)"
        q.trust, q.label = "recorded", q.laps > 0 and "Recorded and observed" or "Recorded"
    elseif route.edited then
        q.source, q.trust, q.label = "edited by you", "verified", "User-corrected"
    elseif route.imported then
        q.source, q.trust, q.label = "imported", "imported", "Unverified"
    else
        q.source = route.source == "GatherPath" and "from GatherPath"
            or (route.planned and "planned by the Farm Finder" or "made from nodes")
        q.trust, q.label = "approximate", "Approximate"
    end
    if not route.recorded and t then
        if t.state == "full" then
            q.label = route.edited and "User-corrected" or "Terrain-aware"
            if q.trust == "approximate" then q.trust = "terrain" end
        elseif t.state == "partial" then
            q.label = route.edited and "User-corrected" or "Partly terrain-aware"
            if q.trust == "approximate" then q.trust = "partial" end
        end
    end
    -- Long straight legs are where cliffs, water or walls may hide (walked legs excepted).
    local p = route.points or {}
    local w, h = HME.Geo.MapYards(route.mapID)
    w, h = w or 1500, h or 1000
    local long = 0
    local walkedLegs = t and (t.state == "full" or t.state == "partial")
    for i = 1, #p / 2 do
        local j = i % (#p / 2) + 1
        if U.Dist(p[2 * i - 1] * w, p[2 * i] * h, p[2 * j - 1] * w, p[2 * j] * h) > 350 then
            local approx = not walkedLegs or (t.approxLegs and t.approxLegs[i])
            if approx then long = long + 1 end
        end
    end
    q.longLegs = long
    if q.laps >= 2 and q.trust ~= "recorded" and q.trust ~= "verified" then
        q.trust = "verified"
        q.observed = true
    end
    local parts = { q.label, q.source }
    local tt = T and T.Text(route)
    -- One note about the terrain, not two ("straight lines" twice in 0.4.0).
    if tt and not route.recorded then parts[#parts + 1] = tt
    elseif q.label == "Approximate" then parts[#parts + 1] = "straight lines, terrain unknown" end
    if long > 0 and q.trust ~= "recorded" then parts[#parts + 1] = long .. " long leg" .. (long == 1 and "" or "s") .. " to check" end
    if q.laps > 0 then parts[#parts + 1] = q.laps .. " lap" .. (q.laps == 1 and "" or "s") .. " ridden" .. (q.observed and " (observed)" or "") end
    q.text = table.concat(parts, " · ")
    return q
end

-- The Route Inspector: everything known about a route, in one table.
--   length (yards walked, or the straight loop), straight, lapSecs, stops,
--   terrainShare (0-1 of legs walked on the grid), approxLegs, longLegs,
--   quality (E.Quality), laps, kinds, sessions (your sessions on it, with
--   farming hours and gathers an hour when there is enough), start (the
--   stop nearest you, when you are in its zone).
-- Recorded paths prove only the line walked, not the ground around it.
function E.Inspect(route)
    if type(route) ~= "table" then return nil end
    local GP = HME.Routes
    local q = E.Quality(route)
    local t = q.terrain
    local out = { name = route.name, mapID = route.mapID, quality = q, laps = route.laps or 0 }
    local straight = route.length or (GP and GP.RouteLength and GP:RouteLength(route)) or 0
    out.straight = straight
    -- Walked length only when legs were walked; else the straight loop.
    out.length = (t and (t.walked or 0) > 0 and (t.walk or 0) > 0) and t.walk or (route.recorded and route.walkLength) or straight
    out.stops = math.floor(#(route.points or {}) / 2)
    local speed = (GP and GP.Speed and GP:Speed()) or 7
    out.speed = speed
    out.lapSecs = out.length / math.max(1, speed)
    if route.recorded then
        out.terrainShare, out.approxLegs = 1, 0
    elseif t and (t.legs or 0) > 0 then
        out.terrainShare = (t.walked or 0) / t.legs
        out.approxLegs = t.approx or 0
        out.pendingLegs = t.missing or 0
    else
        out.terrainShare, out.approxLegs = 0, out.stops
    end
    out.longLegs = q.longLegs or 0
    -- What the loop is for.
    local kinds = {}
    for kind, names in pairs(route.kinds or route.picked or {}) do
        if type(names) == "table" then
            for name in pairs(names) do kinds[#kinds + 1] = tostring(name) end
        else
            kinds[#kinds + 1] = tostring(kind)
        end
    end
    table.sort(kinds)
    out.kinds = kinds
    -- Your sessions on it (sessions remember the route's name).
    local n, secs, gathers, value = 0, 0, 0, 0
    for _, s in ipairs((HME.db and HME.db.sessions) or {}) do
        if s.route and s.route == route.name then
            n = n + 1
            secs = secs + (s.farmSecs or s.secs or 0)
            local c = s.counts or {}
            gathers = gathers + (c.herb or 0) + (c.mine or 0) + (c.skin or 0) + (c.fish or 0)
            value = value + (s.value or 0)
        end
    end
    out.sessions = { n = n, hours = secs / 3600, gathers = gathers, value = value,
        perHour = (secs >= 1800 and n >= 1) and gathers / (secs / 3600) or nil,
        enough = secs >= 3600 and n >= 2 }
    -- Where to start: the stop nearest you, when you are in its zone.
    local mapID, x, y = HME.Player.Position()
    local zMap, zx, zy
    if mapID then zMap, zx, zy = HME.Geo.ZoneOf(mapID, x, y) end
    if zMap and zMap == route.mapID and zx and out.stops > 0 then
        local best, bd = 1, math.huge
        local p = route.points
        for i = 1, out.stops do
            local d = HME.Geo.Distance(route.mapID, zx, zy, p[2 * i - 1], p[2 * i])
            if d and d < bd then best, bd = i, d end
        end
        out.start = { index = best, yards = bd }
    end
    return out
end

-- Laps ridden with HME's guidance count as verification. Counted by the
-- Route Director since 0.6.0 (Routes/Director.lua): before, a lap was counted
-- when the stop number went DOWN, which guided mode never does (it counts on)
-- and which a re-entry at a nearer stop did without a lap being ridden.
