-- HarvestMate Enhanced: Engine/Trail.lua
-- Session replay (0.7.0): where you went during a farming session and what
-- happened where, to look at on the map afterwards.
--
-- While a session runs, your position is noted every 15 seconds when you
-- moved 15 yards or more (zone map, x, y, the session's farming clock), and
-- each skin, gather, catch, skill-up and death with where it happened. At
-- most 480 points (two hours of riding) and 400 events. When the session
-- ends, its trail is kept with it, packed as text; only the 5 newest
-- sessions keep a trail (older ones keep their numbers, not their path).
--
-- The map shows one session's path in the zone you choose (the zone with the
-- most of it first), with a mark every 10 minutes and a dot per event; the
-- Session review has the button. It shows where you were, not why.
-- Copyright (C) 2026 HarvestMate Enhanced contributors. GPL-3.0-or-later.

local _, ns = ...
local HME = ns.HME
local U = HME.U

local Tr = {}
HME.Trail = Tr

Tr.STEP = 15
Tr.MIN_YARDS = 15
Tr.MAX_POINTS = 480
Tr.MAX_EVENTS = 400
Tr.KEEP = 5
Tr.KINDS = { skin = "s", herb = "h", mine = "m", fish = "f", skillup = "u", death = "d" }
local KIND_OF = {}
for k, v in pairs(Tr.KINDS) do KIND_OF[v] = k end

local cur      -- { points = { {m, x, y, f} }, events = { {k, m, x, y, f} } }

local function Where()
    local mapID, x, y = HME.Player.Position()
    if not mapID then return nil end
    local zm, zx, zy = HME.Geo.ZoneOf(mapID, x, y)
    return zm or mapID, zx or x, zy or y
end

local function Clock()
    local s = HME.Session.Current()
    return s and math.floor(s.farm or 0) or 0
end

function Tr.Sample(force)
    local s = HME.Session.Current()
    if not s then cur = nil return false end
    cur = cur or { points = {}, events = {} }
    local m, x, y = Where()
    if not m then return false end
    local last = cur.points[#cur.points]
    if not force and last and last[1] == m then
        local d = HME.Geo.Distance(m, last[2], last[3], x, y)
        if d and d < Tr.MIN_YARDS then return false end
    end
    U.Push(cur.points, { m, U.Round(x, 4), U.Round(y, 4), Clock() }, Tr.MAX_POINTS)
    return true
end

function Tr.Event(kind)
    if not HME.Session.Current() then return end
    cur = cur or { points = {}, events = {} }
    local m, x, y = Where()
    if not (m and Tr.KINDS[kind]) then return end
    U.Push(cur.events, { Tr.KINDS[kind], m, U.Round(x, 4), U.Round(y, 4), Clock() }, Tr.MAX_EVENTS)
end

local running
local function Loop()
    if not HME.Session.Current() then running = false return end
    Tr.Sample()
    HME.After(Tr.STEP, Loop)
end
HME.Listen("SESSION_CHANGED", function()
    if HME.Session.Current() and not running then
        running = true
        Tr.Sample(true)
        HME.After(Tr.STEP, Loop)
    end
end)
HME.Listen("BEAST_SKINNED", function() Tr.Event("skin") end)
HME.Listen("FISH_CAUGHT", function() Tr.Event("fish") end)
HME.Listen("GATHER_LOOT", function(prof)
    -- (prof is "herb", "mine", "skin" or "lock"; skins come through BEAST_SKINNED)
    if prof == "herb" or prof == "mine" then Tr.Event(prof) end
end)
HME.On("PLAYER_DEAD", function() Tr.Event("death") end)
HME.Listen("SKILL_UP", function() Tr.Event("skillup") end)

-- Packing: "m:x:y:f;..." with x and y as 0-10000.
local function PackList(list, withKind)
    local parts = {}
    for i, p in ipairs(list) do
        if withKind then
            parts[i] = ("%s%d:%d:%d:%d"):format(p[1], p[2], math.floor(p[3] * 10000 + 0.5), math.floor(p[4] * 10000 + 0.5), p[5])
        else
            parts[i] = ("%d:%d:%d:%d"):format(p[1], math.floor(p[2] * 10000 + 0.5), math.floor(p[3] * 10000 + 0.5), p[4])
        end
    end
    return table.concat(parts, ";")
end

function Tr.Unpack(trail)
    local out = { points = {}, events = {} }
    if type(trail) ~= "table" then return out end
    for m, x, y, f in (type(trail.p) == "string" and trail.p or ""):gmatch("(%d+):(%d+):(%d+):(%d+)") do
        out.points[#out.points + 1] = { tonumber(m), tonumber(x) / 10000, tonumber(y) / 10000, tonumber(f) }
    end
    for k, m, x, y, f in (type(trail.e) == "string" and trail.e or ""):gmatch("(%a)(%d+):(%d+):(%d+):(%d+)") do
        out.events[#out.events + 1] = { KIND_OF[k] or k, tonumber(m), tonumber(x) / 10000, tonumber(y) / 10000, tonumber(f) }
    end
    return out
end

-- The session ends: its trail goes with it; older sessions' trails are dropped.
HME.Listen("SESSION_ENDED", function(summary)
    if cur and summary and #cur.points >= 1 then
        -- Where it ended (the session is already closed here: its clock is in the summary).
        local m, x, y = Where()
        if m then U.Push(cur.points, { m, U.Round(x, 4), U.Round(y, 4), math.floor(summary.farmSecs or 0) }, Tr.MAX_POINTS) end
    end
    if cur and summary and #cur.points >= 2 then
        summary.trail = { p = PackList(cur.points), e = PackList(cur.events, true) }
        local kept = 0
        local list = HME.db and HME.db.sessions or {}
        for i = #list, 1, -1 do
            if list[i].trail then
                kept = kept + 1
                if kept > Tr.KEEP then list[i].trail = nil end
            end
        end
    end
    cur = nil
end)

-- The zones a trail visits, most points first: { { mapID, n } }.
function Tr.Zones(data)
    local count = {}
    for _, p in ipairs(data.points) do count[p[1]] = (count[p[1]] or 0) + 1 end
    local out = {}
    for m, n in pairs(count) do out[#out + 1] = { mapID = m, n = n } end
    table.sort(out, function(a, b) return a.n > b.n end)
    return out
end

-- What the map draws for one zone: { line = { x, y, ... }, marks = { {x, y, text} }, dots = { {kind, x, y, f} } }.
function Tr.MapData(data, mapID)
    local out = { line = {}, marks = {}, dots = {} }
    local nextMark = 600
    for _, p in ipairs(data.points) do
        if p[1] == mapID then
            out.line[#out.line + 1] = p[2]
            out.line[#out.line + 1] = p[3]
            if p[4] >= nextMark then
                out.marks[#out.marks + 1] = { p[2], p[3], ("%d min"):format(math.floor(p[4] / 60)) }
                nextMark = (math.floor(p[4] / 600) + 1) * 600
            end
        end
    end
    for _, e in ipairs(data.events) do
        if e[2] == mapID then out.dots[#out.dots + 1] = { e[1], e[3], e[4], e[5] } end
    end
    return out
end

-- Shows a session's trail on the world map (the zone with most of it).
function Tr.Show(summary)
    local data = Tr.Unpack(summary and summary.trail)
    local zones = Tr.Zones(data)
    if not zones[1] then
        HME.Print("this session has no path kept (only the 5 newest sessions keep one).")
        return nil
    end
    if HME.MapOverlay and HME.MapOverlay.Replay then HME.MapOverlay.Replay(summary, data, zones[1].mapID) end
    return data, zones[1].mapID
end

function Tr.Current() return cur end
