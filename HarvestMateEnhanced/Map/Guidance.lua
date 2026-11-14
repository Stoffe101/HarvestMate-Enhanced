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
--
-- The route and the arrow are separate things. G.Present() alone decides who
-- points (s.present): "hme" (HME's arrow), "external" (another journey leads;
-- HME waits), "map" (HME guides on the map and HUD only, because the other
-- addon's arrow cannot be paused) or "none" (free farming). Never two arrows:
-- HME shows its arrow beside another Forever-GPS journey only when the player
-- chose it (G.TakeOver) AND Forever-GPS holds its own arrow (API v2
-- HoldArrow). The journey itself is never stopped or changed, and the hold is
-- released when HME's guidance ends, the other journey ends, or the player
-- starts a new journey (their newest choice leads).
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
    -- A there-and-back recording is followed out and back as one loop.
    if route and route.backforth and #out > 2 then
        for i = #out - 1, 2, -1 do out[#out + 1] = { out[i][1], out[i][2] } end
    end
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
    if s.present == "external" then
        return "At the farm. Forever-GPS is leading you somewhere else, so HME's arrow waits (Guide me here: /hme here)."
    end
    if s.present == "map" then
        return "Following the loop on the map: Forever-GPS's other journey keeps its arrow (this version cannot pause it)."
    end
    if s.mode == "free" then return "Free farming inside the highlighted area." end
    local line = ("Following the loop: stop %d of %d."):format(s.stop or 1, s.stops or 0)
    if s.holdID then line = line .. " Forever-GPS's other journey runs on with its arrow paused." end
    return line
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
            G.Present()
            return
        end
        HME.Debug("Forever-GPS could not take it:", why)
    end
    if HME.TomTomBridge and HME.TomTomBridge.Available() and HME.settings.tomtom then
        if HME.TomTomBridge.Set(entry.mapID, entry.x, entry.y, label) then
            s.owner = "tomtom"
            G.Present()
            return
        end
    end
    s.owner = "hme"
    G.Present()
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
    s.via = nil          -- at the farm already: straight to this stop, the turns from the next on
    G.Present()
    if s.present == "external" then
        HME.Print("you're at the farm. Forever-GPS is leading you somewhere else, so HME's arrow waits: "
            .. "Guide me here (Dashboard, HUD or /hme here) to follow the loop.")
    end
end

local function Foreign() return HME.FGPS ~= nil and HME.FGPS.ForeignJourney() or false end

-- Lets go of Forever-GPS's arrow, if HME holds it.
local function Unhold(s)
    if s and s.holdID then
        if HME.FGPS then HME.FGPS.ReleaseArrow(s.holdID) end
        s.holdID = nil
    end
end

-- The one place that decides who points. Called on every change of phase,
-- mode, choice, or of what Forever-GPS is doing.
function G.Present()
    local s = G.Active()
    if not s then return end
    local foreign = Foreign()
    s.foreign = foreign or nil
    local was = s.present
    if s.phase == "travel" then
        Unhold(s)
        s.tookOver = nil
        if s.owner == "hme" then
            if foreign then
                -- Another journey leads now: HME's arrow to the farm waits.
                s.present = "external"
                HME.Arrow.Hide()
            else
                s.present = "hme"
                local entry = Entry(Route(s.routeID))
                if entry then HME.Arrow.Point({ mapID = entry.mapID, x = entry.x, y = entry.y }, s.name) end
            end
        else
            s.present = (s.owner or foreign) and "external" or "none"
            HME.Arrow.Hide()
        end
        return Publish(s)
    end
    if not foreign then
        Unhold(s)
        s.tookOver = nil
        s.present = s.mode == "free" and "none" or "hme"
    elseif s.tookOver and s.mode ~= "free" then
        if not (s.holdID and HME.FGPS.ArrowHoldStands(s.holdID)) then
            s.holdID = HME.FGPS.HoldArrow("following a farming loop")
        end
        s.present = s.holdID and "hme" or "map"
    else
        Unhold(s)
        s.present = s.mode == "free" and "none" or "external"
    end
    s.arrowHeld = s.present == "external" or nil
    if s.present == "hme" then
        G.PointAtStop()
    else
        HME.Arrow.Hide()
    end
    if was and was ~= s.present then HME.Debug("guidance presentation", was, "->", s.present) end
    Publish(s)
end

-- The player asks HME to guide here although another journey runs. That
-- journey is left as it is: Forever-GPS pauses its arrow (API v2), or, where
-- it cannot, HME guides on the map only. Never two arrows.
function G.TakeOver()
    local s = G.Active()
    if not s then return end
    if s.phase ~= "farm" then
        G.BeginFarm()
        s = G.Active()
        if not s then return end
    end
    if s.mode == "free" then G.SetMode("guided") end
    s.tookOver = true
    G.Present()
    if s.present == "map" then
        HME.Print("Forever-GPS's other journey keeps its arrow (this Forever-GPS cannot pause it), so HME guides on the "
            .. "map and HUD. Stop that journey in Forever-GPS to get HME's arrow.")
    end
end

-- Hands the arrow back to the other journey (undoes Guide me here).
function G.GiveBack()
    local s = G.Active()
    if not s then return end
    s.tookOver = nil
    G.Present()
end

-- Whether "Guide me here" means anything now.
function G.CanTakeOver()
    local s = G.Active()
    return s ~= nil and s.phase == "farm" and s.present == "external"
end

-- Who points now, for the HUD and diagnostics: "HME", "Forever-GPS", "TomTom" or nil.
function G.ArrowOwner()
    local s = G.Active()
    if s and s.present == "hme" and HME.Arrow.Shown() then return "HME" end
    if s and s.phase == "travel" and s.owner == "fgps" then return "Forever-GPS" end
    if s and s.phase == "travel" and s.owner == "tomtom" then return "TomTom" end
    if (s and (s.present == "external" or s.present == "map")) or (not s and HME.FGPS and HME.FGPS.CurrentJourney()) then
        return "Forever-GPS"
    end
    return nil
end

function G.SetMode(mode)
    local s = G.Active()
    HME.settings.huntMode = mode
    if not s then return end
    s.mode = mode
    if s.phase == "farm" then G.Present() else Publish(s) end
end

-- The turns the walking grid found on the leg into stop k (in guidance
-- order), so the arrow goes round a hill rather than at the stop beyond it.
local function ViaInto(route, k, n)
    if not (HME.Terrain and route and n >= 2) then return {} end
    local prev = (k - 2) % n + 1
    local function Orig(i) return route.reversed and (n - i + 1) or i end
    return HME.Terrain.Via(route, Orig(prev), Orig(k))
end
G.ViaInto = ViaInto

function G.PointAtStop()
    local s = G.Active()
    if not s or s.present ~= "hme" or s.mode == "free" then return end
    local route = Route(s.routeID)
    local stops = Stops(route)
    if #stops == 0 then return end
    s.stops = #stops
    s.stop = (((s.stop or 1) - 1) % #stops) + 1
    local via = ViaInto(route, s.stop, #stops)
    local v = s.via and via[s.via]
    if v then
        HME.Arrow.Point({ mapID = route.mapID, x = v[1], y = v[2] },
            ("stop %d of %d (turn %d of %d)"):format(s.stop, #stops, s.via, #via))
        return
    end
    local st = stops[s.stop]
    HME.Arrow.Point({ mapID = route.mapID, x = st[1], y = st[2] }, ("stop %d of %d"):format(s.stop, #stops))
end

-- Reached what the arrow pointed at: the next turn on the walked leg, or the next stop.
function G.Advance()
    local s = G.Active()
    if not s then return end
    local route = Route(s.routeID)
    local n = #Stops(route)
    local via = ViaInto(route, s.stop or 1, n)
    if s.via and s.via <= #via then
        s.via = s.via + 1
    else
        s.stop = (s.stop or 1) + 1
        s.via = 1
    end
    G.PointAtStop()
    Publish(s)
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
        if dist <= reach then G.Advance() end
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
        if not s then return end
        -- Another journey began or ended without an event reaching HME (older
        -- Forever-GPS, the panel): look once a second.
        if (Foreign() or nil) ~= s.foreign then
            if Foreign() and s.tookOver then s.tookOver = nil end   -- a new journey: the player's newest choice
            G.Present()
        elseif s.tookOver and s.holdID and HME.FGPS and not HME.FGPS.ArrowHoldStands(s.holdID) then
            -- Forever-GPS let go of the hold (a journey the player started): it leads again.
            s.holdID, s.tookOver = nil, nil
            G.Present()
        end
        if s.phase ~= "travel" then return end
        local route = Route(s.routeID)
        if not route then return end
        local _, dist = Entry(route)
        if dist and dist <= G.ARRIVE_YARDS then
            G.BeginFarm()
            if s.present == "hme" then HME.Print("you're at the farm: HME's loop guidance takes over.") end
        end
    end)
end

-- Forever-GPS reports, by request token (Integrations/ForeverGPS.lua).
local function Ours(token)
    local s = G.Active()
    return token ~= nil and s and s.token == token and s or nil
end

function G.OnExternalStarted(token)
    local s = Ours(token)
    if s then return G.Present() end
    -- Somebody else's journey started (the player's, or a trip HME sent to a
    -- trainer): it is the newest choice, so HME's arrow steps aside.
    s = G.Active()
    if s then
        s.tookOver = nil
        G.Present()
    end
end

-- Any journey ended, or Forever-GPS let go of a hold: look again.
function G.OnExternalChanged()
    if G.Active() then G.Present() end
end

function G.OnHoldDropped(holdID)
    local s = G.Active()
    if s and s.holdID == holdID then
        s.holdID, s.tookOver = nil, nil
        G.Present()
    end
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
        G.Present()
    end
end

-- The player sent Forever-GPS somewhere else: that journey is theirs.
function G.OnExternalSuperseded(token)
    local s = Ours(token)
    if s and s.phase == "travel" then
        s.owner = nil
        s.why = "Forever-GPS is now going somewhere else; HME stepped back. Navigate brings the farm back."
        G.Present()
    end
end

function G.OnExternalStale(token)
    local s = Ours(token)
    if s and s.phase == "travel" and s.owner == "fgps" then
        s.owner = nil
        s.why = "The journey from before the reload is no longer running. Press Navigate to go on."
        G.Present()
    end
end

function G.Stop()
    local s = State()
    if not s or not s.routeID then return end
    if s.owner == "fgps" and HME.FGPS then HME.FGPS.Forget() elseif HME.FGPS and HME.char then HME.FGPS.Forget() end
    if s.owner == "tomtom" and HME.TomTomBridge then HME.TomTomBridge.Clear() end
    Unhold(s)   -- Forever-GPS's arrow comes back for its own journey
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
        -- Forever-GPS keeps no hold over a reload: ask again if the player had chosen HME.
        -- (PLAYER_ENTERING_WORLD also comes with every loading screen: a hold
        -- that still stands is kept.)
        if s.holdID and not (HME.FGPS and HME.FGPS.ArrowHoldStands(s.holdID)) then s.holdID = nil end
        s.foreign = nil
        G.Present()
    end)
end)
