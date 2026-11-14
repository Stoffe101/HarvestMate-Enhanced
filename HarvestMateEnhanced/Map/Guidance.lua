-- HarvestMate Enhanced: Map/Guidance.lua
-- Who is navigating, and to where. There is exactly one owner at a time:
--   "fgps"  Forever-GPS is taking you to the farm (its HUD and arrow only)
--   "tomtom" TomTom has the waypoint (its arrow only)
--   "hme"   HME's arrow: to the farm's entry, then stop by stop round the loop
--   nil     nothing is being followed
-- Phases: "travel" (getting to the farm) then "farm" (following the loop).
-- Arrival: Forever-GPS says HME's journey arrived (its destination matches
-- the request), or you are within ARRIVE_YARDS of the loop, whichever comes
-- first. HME then stops its own journey (never anyone else's) and guides the
-- loop; if another journey the player chose is running, HME's arrow waits.
-- Travel is timed apart from farming: the session clock starts at the farm.
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
    if route and route.reversed and #out > 1 then
        local rev = {}
        for i = #out, 1, -1 do rev[#rev + 1] = out[i] end
        out = rev
    end
    return out
end
G.Stops = Stops

-- The point of the loop nearest the player (or the first), and how far.
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
G.Entry = Entry

local function Changed() HME.Signal("GUIDANCE_CHANGED") end

local function PhaseText(s)
    if s.phase == "travel" then
        if s.owner == "fgps" then return "Forever-GPS is taking you there." end
        if s.owner == "tomtom" then return "TomTom has the waypoint." end
        if s.owner == "hme" then return "Heading to the farm; follow the arrow." end
        if s.why then return s.why end
        return "Not navigating. Press Navigate when you want directions."
    end
    if s.arrowHeld then return "At the farm. Another Forever-GPS journey is running, so HME's arrow waits (Guide me here)." end
    if s.mode == "free" then return "Free farming inside the highlighted area." end
    return ("Following the loop: stop %d of %d."):format(s.stop or 1, s.stops or 0)
end

local function Publish(s)
    s.phaseText = PhaseText(s)
    Changed()
end

-- Starts following a route (made by Engine/Planner.lua, or any saved route).
-- The farming clock does NOT start here: travelling is not farming.
function G.Start(route, result)
    if not route then return end
    if G.Active() then G.Stop() end
    local s = State()
    for k in pairs(s) do s[k] = nil end
    s.routeID = route.id
    s.mapID = route.mapID
    s.name = route.name
    s.key = (route.planned and route.planned.key) or ("route:" .. route.id)
    s.prof = route.planned and route.planned.prof
    s.planned = route.planned
    s.mode = (HME.settings and HME.settings.huntMode) or "guided"
    s.stops = #Stops(route)
    s.stop = 1
    s.startedAt = HME.Now()
    if result then s.result = { prof = result.prof, targets = result.targets } end
    route.shown = true
    local entry, dist = Entry(route)
    if entry and dist <= G.ARRIVE_YARDS then
        G.BeginFarm(entry.index)
    else
        s.phase = "travel"
        s.travelSince = HME.Now()
        G.Navigate()
    end
    if HME.Routes then HME.Routes:Changed() end
    Publish(s)
end

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

function G.NavigateToResult(result, goal) G.StartResult(result, goal) end

-- Getting there: Forever-GPS if available, else TomTom if wanted, else HME.
function G.Navigate()
    local s = G.Active()
    if not s then return end
    local route = Route(s.routeID)
    local entry = Entry(route)
    if not entry then return end
    s.phase = "travel"
    s.travelSince = s.travelSince or HME.Now()
    s.why = nil
    local label = s.name
    local FGPS = HME.FGPS
    if FGPS and FGPS.Available() then
        local token, why = FGPS.NavigateTo(entry.mapID, entry.x, entry.y, label)
        if token then
            s.owner, s.token = "fgps", token
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

-- On the farm. HME's loop guidance starts, unless another navigation task
-- the player chose is running: then the arrow waits (G.TakeOver to use it).
function G.BeginFarm(index)
    local s = G.Active()
    if not s then return end
    if s.owner == "fgps" and HME.FGPS then HME.FGPS.Release(s.token) end
    if s.owner == "tomtom" and HME.TomTomBridge then HME.TomTomBridge.Clear() end
    if s.phase ~= "farm" then
        local travel = s.travelSince and (HME.Now() - s.travelSince) or 0
        s.travelSecs = (s.travelSecs or 0) + math.max(0, travel)
        s.travelSince = nil
        s.farmSince = HME.Now()
        if HME.Session then HME.Session.BeginFarm(s.key, s.travelSecs) end
    end
    s.phase = "farm"
    s.owner = "hme"
    s.stop = index or s.stop or 1
    s.arrowHeld = HME.FGPS and HME.FGPS.ForeignJourney() or false
    if s.arrowHeld then
        HME.Arrow.Hide()
        HME.Print("you're at the farm. Forever-GPS is navigating somewhere else, so HME's arrow waits: "
            .. "/hme guide (or Guide me here) to follow the loop.")
    else
        G.PointAtStop()
    end
    Publish(s)
end

-- The player asks HME to guide here although another journey runs. That
-- journey is left as it is; only the arrows' owner changes.
function G.TakeOver()
    local s = G.Active()
    if not s then return end
    if s.phase ~= "farm" then
        G.BeginFarm()
        s = G.Active()
    end
    s.arrowHeld = false
    G.PointAtStop()
    Publish(s)
end

function G.SetMode(mode)
    local s = G.Active()
    HME.settings.huntMode = mode
    if not s then return end
    s.mode = mode
    if s.phase == "farm" and not s.arrowHeld then
        if mode == "free" then HME.Arrow.Hide() else G.PointAtStop() end
    end
    Publish(s)
end

function G.PointAtStop()
    local s = G.Active()
    if not s or s.arrowHeld or s.mode == "free" then return end
    local route = Route(s.routeID)
    local stops = Stops(route)
    if #stops == 0 then return end
    s.stops = #stops
    s.stop = (((s.stop or 1) - 1) % #stops) + 1
    local st = stops[s.stop]
    HME.Arrow.Point({ mapID = route.mapID, x = st[1], y = st[2] }, ("stop %d of %d"):format(s.stop, #stops))
end

-- Minimal mode: the arrow only reappears when you stray from the loop.
local function MinimalCheck(s, dist)
    if s.mode ~= "minimal" then return end
    if dist and dist < 120 then HME.Arrow.Dim(true) else HME.Arrow.Dim(false) end
end

HME.Arrow.onUpdate = function(dist)
    local s = G.Active()
    if not (s and dist) then return end
    if s.phase == "farm" then
        MinimalCheck(s, dist)
        local reach = (HME.settings and HME.settings.arriveYards) or G.STOP_YARDS
        if dist <= reach then
            s.stop = (s.stop or 1) + 1
            G.PointAtStop()
            Publish(s)
        end
    elseif s.phase == "travel" and s.owner == "hme" and dist <= G.ARRIVE_YARDS then
        G.BeginFarm()
        HME.Print("you're at the farm. Follow the arrow round the loop.")
    end
end

-- Arrival by position, whoever navigates (or nobody).
do
    local f = CreateFrame("Frame")
    local acc = 0
    f:SetScript("OnUpdate", function(_, dt)
        acc = acc + dt
        if acc < 1 then return end
        acc = 0
        local s = G.Active()
        if not (s and s.phase == "travel") then return end
        local route = Route(s.routeID)
        if not route then return end
        local _, dist = Entry(route)
        if dist and dist <= G.ARRIVE_YARDS then
            G.BeginFarm()
            if not s.arrowHeld then HME.Print("you're at the farm: HME's loop guidance takes over.") end
        end
    end)
end

-- Forever-GPS reports, by request token (Integrations/ForeverGPS.lua).
local function Ours(token)
    local s = G.Active()
    return s and s.token == token and s or nil
end

function G.OnExternalStarted(token)
    local s = Ours(token)
    if s then Publish(s) end
end

function G.OnExternalArrived(token)
    local s = Ours(token)
    if s and s.phase == "travel" then
        G.BeginFarm()
        HME.Print("arrived: HME's loop guidance takes over from Forever-GPS.")
    end
end

-- The player stopped HME's journey: HME does not take over by itself.
function G.OnExternalCleared(token)
    local s = Ours(token)
    if s and s.phase == "travel" then
        s.owner = nil
        s.why = "You stopped the journey. Press Navigate to go on, or walk there: HME notices when you arrive."
        Publish(s)
    end
end

-- The player sent Forever-GPS somewhere else: that journey is theirs.
function G.OnExternalSuperseded(token)
    local s = Ours(token)
    if s and s.phase == "travel" then
        s.owner = nil
        s.why = "Forever-GPS is now going somewhere else; HME stepped back. Navigate brings the farm back."
        Publish(s)
    end
end

function G.OnExternalStale(token)
    local s = Ours(token)
    if s and s.phase == "travel" and s.owner == "fgps" then
        s.owner = nil
        s.why = "The journey from before the reload is no longer running. Press Navigate to go on."
        Publish(s)
    end
end

function G.Stop()
    local s = State()
    if not s or not s.routeID then return end
    if s.owner == "fgps" and HME.FGPS then HME.FGPS.Forget() elseif HME.FGPS and HME.char then HME.FGPS.Forget() end
    if s.owner == "tomtom" and HME.TomTomBridge then HME.TomTomBridge.Clear() end
    for k in pairs(s) do s[k] = nil end
    HME.Arrow.Hide()
    Changed()
end

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
        if s.phase == "farm" then
            G.PointAtStop()
        elseif s.owner == "hme" then
            HME.Arrow.Point(Entry(Route(s.routeID)), s.name)
        end
        Publish(s)
    end)
end)
