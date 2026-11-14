-- HarvestMate Enhanced: Map/Guidance.lua
-- Who is navigating, and to where. There is exactly one owner at a time:
--   "fgps"  Forever-GPS is taking you to the farm (its HUD and arrow only)
--   "tomtom" TomTom has the waypoint (its arrow only)
--   "hme"   HME's arrow: to the farm's entry, then stop by stop round the loop
--   nil     nothing is being followed
-- Phases: "travel" (getting to the farm) then "farm" (following the loop).
-- Arrival: Forever-GPS says it arrived, or you are within ARRIVE_YARDS of the
-- loop on its map, whichever comes first. Then HME takes over and Forever-GPS
-- has nothing left to do. Stopping one stops the hand-off cleanly.
-- The state survives /reload (HarvestMateEnhancedCharDB.guidance).
-- Copyright (C) 2026 HarvestMate Enhanced contributors. GPL-3.0-or-later.

local _, ns = ...
local HME = ns.HME
local U = HME.U

local G = {}
HME.Guidance = G

G.ARRIVE_YARDS = 200     -- this close to the loop counts as arrived
G.STOP_YARDS = 30        -- a stop counts as reached this close (Settings: arrive distance)

local function State() return HME.char and HME.char.guidance end
function G.Active()
    local s = State()
    if s and s.routeID then return s end
    return nil
end

local function Route(id)
    for _, r in ipairs((HME.Routes and HME.Routes.db and HME.Routes.db.routes) or {}) do
        if r.id == id then return r end
    end
end
G.Route = Route

local function Stops(route)
    local out = {}
    local p = route and route.points or {}
    for i = 1, #p - 1, 2 do out[#out + 1] = { p[i], p[i + 1] } end
    return out
end

-- The point of the loop nearest the player (or the first), as the entry.
local function Entry(route)
    local stops = Stops(route)
    if #stops == 0 then return nil end
    local mapID, x, y = HME.Player.Position()
    local zMap, zx, zy = HME.Geo.ZoneOf(mapID, x, y)
    local best, bd = 1, math.huge
    if zMap == route.mapID and zx then
        for i, s in ipairs(stops) do
            local d = HME.Geo.Distance(route.mapID, zx, zy, s[1], s[2])
            if d < bd then best, bd = i, d end
        end
    end
    return { mapID = route.mapID, x = stops[best][1], y = stops[best][2], index = best }, bd
end

local function Changed()
    HME.Signal("GUIDANCE_CHANGED")
end

local function PhaseText(s)
    if s.phase == "travel" then
        if s.owner == "fgps" then return "Forever-GPS is taking you there." end
        if s.owner == "tomtom" then return "TomTom has the waypoint." end
        return "Heading to the farm; follow the arrow."
    end
    return ("Following the loop: stop %d of %d."):format(s.stop or 1, s.stops or 0)
end

local function Publish(s)
    s.phaseText = PhaseText(s)
    Changed()
end

-- Starts following a route (made by Engine/Planner.lua, or any saved route).
function G.Start(route, result)
    if not route then return end
    local s = State()
    for k in pairs(s) do s[k] = nil end
    s.routeID = route.id
    s.mapID = route.mapID
    s.name = route.name
    s.key = (route.planned and route.planned.key) or ("route:" .. route.id)
    s.prof = route.planned and route.planned.prof
    s.planned = route.planned
    s.stops = #Stops(route)
    s.stop = 1
    s.startedAt = (time and time()) or 0
    -- Lightweight copy of the result for the guide's "gone grey" check.
    if result then s.result = { prof = result.prof, targets = result.targets } end
    route.shown = true
    local entry, dist = Entry(route)
    if entry and dist <= G.ARRIVE_YARDS then
        G.BeginFarm(entry.index)
    else
        s.phase = "travel"
        G.Navigate()
    end
    if HME.Routes then HME.Routes:Changed() end
    if HME.Session and not HME.Session.Current() then HME.Session.Start() end
    Publish(s)
end

-- Farm Finder: plan the route for a result, then start it.
function G.StartResult(result, goal)
    HME.Print(("planning %s in %s..."):format(result.prof, result.zone or "?"))
    HME.Planner.Create(result, goal, function(route)
        if route and HME.Routes:NodeCount(route) >= 2 then
            G.Start(route, result)
            HME.Print(("route ready: |cffffd100%s|r, %s round."):format(route.name, U.Yards(route.length or 0)))
        else
            HME.Print("there were not enough points for a loop there; try another farm.")
        end
    end)
end

-- Navigate to a result without starting the loop yet (it is planned first,
-- so the arrival hands straight over to it).
function G.NavigateToResult(result, goal)
    HME.Planner.Create(result, goal, function(route)
        if route then G.Start(route, result) end
    end)
end

-- Getting there: Forever-GPS if available, else TomTom if wanted, else HME.
function G.Navigate()
    local s = G.Active()
    if not s then return end
    local route = Route(s.routeID)
    local entry = Entry(route)
    if not entry then return end
    s.phase = "travel"
    local label = s.name
    local FG = HME.FGPS
    if FG and FG.Available() and HME.settings.forevergps ~= false then
        local ok, why = FG.NavigateTo(entry.mapID, entry.x, entry.y, label)
        if ok then
            s.owner = "fgps"
            HME.Arrow.Hide()
            Publish(s)
            return
        end
        HME.Debug("Forever-GPS could not take it:", why)
    end
    if HME.TomTomBridge and HME.TomTomBridge.Available() and HME.settings.tomtom then
        if HME.TomTomBridge.Set(entry.mapID, entry.x, entry.y, label) then
            s.owner = "tomtom"
            HME.Arrow.Hide()
            Publish(s)
            return
        end
    end
    s.owner = "hme"
    HME.Arrow.Point({ mapID = entry.mapID, x = entry.x, y = entry.y }, label)
    Publish(s)
end

-- On the farm: HME owns guidance from here.
function G.BeginFarm(index)
    local s = G.Active()
    if not s then return end
    if s.owner == "fgps" and HME.FGPS then HME.FGPS.Release() end
    if s.owner == "tomtom" and HME.TomTomBridge then HME.TomTomBridge.Clear() end
    s.phase = "farm"
    s.owner = "hme"
    s.stop = index or s.stop or 1
    G.PointAtStop()
    Publish(s)
end

function G.PointAtStop()
    local s = G.Active()
    if not s then return end
    local route = Route(s.routeID)
    local stops = Stops(route)
    if #stops == 0 then return end
    s.stops = #stops
    s.stop = (((s.stop or 1) - 1) % #stops) + 1
    local st = stops[s.stop]
    HME.Arrow.Point({ mapID = route.mapID, x = st[1], y = st[2] }, ("stop %d of %d"):format(s.stop, #stops))
end

-- Arrow distance updates drive the loop forward.
HME.Arrow.onUpdate = function(dist)
    local s = G.Active()
    if not (s and dist) then return end
    if s.phase == "farm" then
        local reach = (HME.settings and HME.settings.arriveYards) or G.STOP_YARDS
        if dist <= reach then
            s.stop = (s.stop or 1) + 1
            G.PointAtStop()
            Publish(s)
        end
    elseif s.phase == "travel" and s.owner == "hme" and dist <= G.ARRIVE_YARDS then
        local _, _ = Entry(Route(s.routeID))
        G.BeginFarm()
        HME.Print("you're at the farm. Follow the arrow round the loop.")
    end
end

-- While someone else navigates, HME still notices arrival by position.
do
    local f = CreateFrame("Frame")
    local acc = 0
    f:SetScript("OnUpdate", function(_, dt)
        acc = acc + dt
        if acc < 1 then return end
        acc = 0
        local s = G.Active()
        if not (s and s.phase == "travel" and s.owner ~= "hme") then return end
        local route = Route(s.routeID)
        if not route then return end
        local _, dist = Entry(route)
        if dist and dist <= G.ARRIVE_YARDS then
            G.BeginFarm()
            HME.Print("you're at the farm: HME's loop guidance takes over.")
        end
    end)
end

-- Forever-GPS reports (Integrations/ForeverGPS.lua calls these).
function G.OnExternalArrived()
    local s = G.Active()
    if s and s.phase == "travel" then
        G.BeginFarm()
        HME.Print("arrived: HME's loop guidance takes over from Forever-GPS.")
    end
end

function G.OnExternalCleared()
    local s = G.Active()
    if s and s.phase == "travel" and s.owner == "fgps" then
        -- Stopped in Forever-GPS before arriving: HME does not take over by
        -- itself (the player chose to stop). Navigate offers it again.
        s.owner = nil
        Publish(s)
    end
end

function G.Stop()
    local s = State()
    if not s or not s.routeID then return end
    if s.owner == "fgps" and HME.FGPS then HME.FGPS.Release() end
    if s.owner == "tomtom" and HME.TomTomBridge then HME.TomTomBridge.Clear() end
    for k in pairs(s) do s[k] = nil end
    HME.Arrow.Hide()
    Changed()
end

-- What was predicted for a farm key (for the session summary).
function G.PredictionFor(key)
    local s = G.Active()
    if s and s.key == key and s.planned then return s.planned.predicted end
    for _, r in ipairs((HME.Routes and HME.Routes.db and HME.Routes.db.routes) or {}) do
        if r.planned and r.planned.key == key then return r.planned.predicted end
    end
end

-- Gatherpedia's recorded guide routes: saved as a route and followed.
function G.StartGuideSpot(spot, prof)
    if not (spot and spot.mapID and HME.Routes) then return end
    local Gd = ns.Guides
    local pts = Gd and (Gd:RoutePoints(spot) or (Gd:CaveLoops(spot) or {})[1]) or {}
    -- A there-and-back route ("backforth") is ridden out and back as one loop.
    if Gd and #pts > 2 and Gd:RouteType(spot) == "backforth" then
        for i = #pts - 1, 2, -1 do pts[#pts + 1] = pts[i] end
    end
    if #pts < 2 then
        if spot.x then HME.Arrow.Point({ mapID = spot.mapID, x = spot.x / 100, y = spot.y / 100 }, spot.label) end
        return
    end
    local GP = HME.Routes
    local name = (spot.label or spot.zone or "Guide route") .. " (guide)"
    local existing
    for _, r in ipairs(GP.db.routes) do if r.mapID == spot.mapID and r.name == name then existing = r end end
    if not existing then
        local flat = {}
        for _, p in ipairs(pts) do
            flat[#flat + 1] = (p.x or p[1]) / 100
            flat[#flat + 1] = (p.y or p[2]) / 100
        end
        existing = { id = GP.db.nextID, mapID = spot.mapID, name = name, kinds = {}, sight = 0, points = flat,
            color = { 0.85, 0.75, 0.38 }, shown = true, source = "Gatherpedia guide", recorded = true }
        GP.db.nextID = GP.db.nextID + 1
        table.insert(GP.db.routes, existing)
        existing.length = GP:RouteLength(existing)
    end
    G.Start(existing, nil)
    local st = G.Active()
    if st then st.prof = prof end
end

-- After /reload: point the arrow again.
HME.On("PLAYER_ENTERING_WORLD", function()
    HME.After(2, function()
        local s = G.Active()
        if not s then return end
        if not Route(s.routeID) then
            G.Stop()
            return
        end
        if s.phase == "farm" then G.PointAtStop() elseif s.owner == "hme" then G.Navigate() end
        Publish(s)
    end)
end)
