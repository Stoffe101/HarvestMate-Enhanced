-- HarvestMate Enhanced: Engine/Flights.lua
-- Take flights automatically (0.7.1, Settings: off by default). When you
-- open a flight master's map while HME or Forever-GPS is taking you somewhere,
-- HME picks the flight and takes it:
--
--   1. the flight Forever-GPS's journey plans next (API.PlannedFlight, by the
--      game's taxi node ids): exactly the way it planned;
--   2. otherwise the flight master you can fly to that lands closest to where
--      HME is leading you (the farm's first stop, a guide's place), when it
--      lands at least 400 yards closer and a third nearer than you are now.
--
-- You still walk to the flight master and talk to it (HME never moves you);
-- hold Shift while you talk to it to choose yourself. Nothing is taken in
-- combat. If the game refuses an addon taking the flight, a "Fly to ..."
-- button on the flight map does it with your click. Every flight taken is
-- said in chat.
-- Copyright (C) 2026 HarvestMate Enhanced contributors. GPL-3.0-or-later.

local _, ns = ...
local HME = ns.HME
local U = HME.U

local F = {}
HME.Flights = F

F.MIN_SAVE_YARDS = 400
F.SHARE = 0.67
F.DELAY = 0.3
F.CHECK = 1.5

local function Call(fn, ...)
    if type(fn) ~= "function" then return nil end
    local ok, a, b = pcall(fn, ...)
    if not ok then return nil end
    return a, b
end

-- World position (continent, x, y in yards) of a map position, or nil.
function F.World(mapID, x, y)
    if not (mapID and x and y and C_Map and C_Map.GetWorldPosFromMapPos and CreateVector2D) then return nil end
    local ok, cont, pos = pcall(C_Map.GetWorldPosFromMapPos, mapID, CreateVector2D(x, y))
    if not (ok and pos and pos.GetXY) then return nil end
    local wx, wy = pos:GetXY()
    cont, wx, wy = HME.Num(cont), HME.Num(wx), HME.Num(wy)
    if not (cont and wx and wy) then return nil end
    return cont, wx, wy
end

local function Yards(a, b)
    if not (a and b and a.cont and a.cont == b.cont) then return nil end
    return U.Dist(a.wx, a.wy, b.wx, b.wy)
end

-- Where HME is leading you: { mapID, x, y, label } or nil.
function F.Destination()
    local G = HME.Guidance
    local s = G and G.Active()
    if s and s.phase == "travel" then
        local route = G.Route(s.routeID)
        local e = route and G.Entry(route)
        if e then return { mapID = e.mapID, x = e.x, y = e.y, label = s.name } end
    end
    local FG = HME.FGPS and HME.FGPS.CurrentJourney and HME.FGPS.CurrentJourney()
    if FG and FG.mapID then return { mapID = FG.mapID, x = FG.x, y = FG.y, label = FG.name } end
    return nil
end

-- The flight master map's nodes you can fly to: { { slot, nodeID, name, cont, wx, wy } }.
function F.Nodes()
    local mapID = Call(_G.GetTaxiMapID)
    mapID = HME.Num(mapID)
    if not (mapID and C_TaxiMap and C_TaxiMap.GetAllTaxiNodes) then return {}, nil end
    local list = Call(C_TaxiMap.GetAllTaxiNodes, mapID)
    local reach = Enum and Enum.FlightPathState and Enum.FlightPathState.Reachable
    local current = Enum and Enum.FlightPathState and Enum.FlightPathState.Current
    local out, here = {}, nil
    for _, n in ipairs(type(list) == "table" and list or {}) do
        if type(n) == "table" and n.position and n.position.GetXY then
            local x, y = n.position:GetXY()
            local cont, wx, wy = F.World(mapID, x, y)
            local e = { slot = HME.Num(n.slotIndex), nodeID = HME.Num(n.nodeID), name = HME.Str(n.name) or "?",
                cont = cont, wx = wx, wy = wy }
            if n.state == reach and e.slot then out[#out + 1] = e end
            if n.state == current then here = e end
        end
    end
    return out, here
end

-- The flight to take: node, why (or nil, why not).
function F.Choose()
    local nodes, here = F.Nodes()
    if #nodes == 0 then return nil, "no flight you can take from here" end
    -- 1. Forever-GPS's planned flight.
    local api = HME.FGPS and HME.FGPS.APIv2 and HME.FGPS.APIv2()
    if api and type(api.PlannedFlight) == "function" then
        local ok, plan = pcall(api.PlannedFlight)
        if ok and type(plan) == "table" and plan.toID then
            for _, n in ipairs(nodes) do
                if n.nodeID == plan.toID then return n, "Forever-GPS's journey flies there" end
            end
        end
    end
    -- 2. The node closest to HME's destination.
    local dest = F.Destination()
    if not dest then return nil, "HME is not taking you anywhere" end
    local zm, zx, zy = HME.Geo.ZoneOf(dest.mapID, dest.x, dest.y)
    local dc, dx, dy = F.World(zm or dest.mapID, zx or dest.x, zy or dest.y)
    if not dc then return nil, "the destination's position is not known" end
    local target = { cont = dc, wx = dx, wy = dy }
    local mapID, px, py = HME.Player.Position()
    local pc, pwx, pwy = F.World(mapID, px, py)
    local me = here or (pc and { cont = pc, wx = pwx, wy = pwy })
    local now = Yards(me, target)
    local best, bd
    for _, n in ipairs(nodes) do
        local d = Yards(n, target)
        if d and (not bd or d < bd) then best, bd = n, d end
    end
    if not best then return nil, "no flight lands on the destination's continent" end
    if now and (bd > now - F.MIN_SAVE_YARDS or bd > now * F.SHARE) then
        return nil, ("flying lands no nearer than walking (%s against %s)"):format(U.Yards(bd), U.Yards(now))
    end
    return best, ("lands %s from %s"):format(U.Yards(bd), dest.label or "where HME is leading you")
end

---------------------------------------------------------------------------
-- At the flight master
---------------------------------------------------------------------------
local button
local function Button(node)
    local parent = _G.TaxiFrame or _G.FlightMapFrame
    if not parent then return nil end
    if not button then
        local T = ns.Theme
        button = T.FlatButton(parent, "", 220, 26, "primary")
        button:SetPoint("BOTTOM", parent, "BOTTOM", 0, 16)
        if button.SetFrameStrata then button:SetFrameStrata("DIALOG") end
    end
    button:SetParent(parent)
    button:SetText("Fly to " .. node.name)
    button:SetScript("OnClick", function()
        Call(_G.TakeTaxiNode, node.slot)
        button:Hide()
    end)
    button:Show()
    return button
end

local function OnTaxi()
    return HME.Bool(Call(_G.UnitOnTaxi, "player")) == true
end

-- Called when the flight map opens (after the game filled it in).
function F.Opened(shift)
    F.last = nil
    if button then button:Hide() end
    if not (HME.settings and HME.settings.autoFlight) then return nil end
    if HME.InCombat() then return nil end
    if shift == nil then shift = _G.IsShiftKeyDown and _G.IsShiftKeyDown() and true or false end
    if shift then
        F.last = { skipped = "shift" }
        return nil
    end
    local node, why = F.Choose()
    F.last = { node = node, why = why }
    if not node then
        HME.Debug("auto flight:", why)
        return nil
    end
    HME.Print(("flying to |cffffd100%s|r (%s). Hold Shift at a flight master to choose yourself; Settings turns this off.")
        :format(node.name, why))
    Call(_G.TakeTaxiNode, node.slot)
    -- Refused (the game can block an addon from taking flights): one click does it.
    HME.After(F.CHECK, function()
        if not OnTaxi() and (_G.TaxiFrame and _G.TaxiFrame:IsShown() or _G.FlightMapFrame and _G.FlightMapFrame:IsShown()) then
            Button(node)
            F.last.button = true
        end
    end)
    return node
end

HME.On("TAXIMAP_OPENED", function()
    local shift = _G.IsShiftKeyDown and _G.IsShiftKeyDown() and true or false
    HME.After(F.DELAY, function() F.Opened(shift) end)
end)
HME.On("TAXIMAP_CLOSED", function() if button then button:Hide() end end)
