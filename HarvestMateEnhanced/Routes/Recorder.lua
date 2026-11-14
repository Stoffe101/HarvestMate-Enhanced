-- HarvestMate Enhanced: Routes/Recorder.lua
-- Record My Route: you ride round a farm the way you like; HME writes your
-- path down and makes a route of it that can be edited, reversed, trimmed,
-- saved, exported and followed later. Entirely passive: it only reads your
-- position once a second and listens for what you gather. Nothing moves,
-- targets or clicks for you.
--
--   R.Start(name)  R.Pause()  R.Resume()  R.Stop() -> route  R.Cancel()
--   R.State()      { state = "recording"|"paused", mapID, points, yards, secs, obs }
--   R.Trim(route, first, last)  keeps stops first..last of a saved recording
--
-- A point is written when you moved at least MIN_STEP yards and either
-- turned TURN_DEG degrees or went KEEP_YARDS since the last one; standing
-- still writes nothing. Leaving the map pauses (coming back resumes). At Stop
-- the path is pulled straight to within SIMPLIFY_YARDS (turns that matter
-- stay) and to at most MAX_SAVED points. What you gather, skin or catch on
-- the way is kept with the route ("seen here", with the place), never as a
-- live node; and your path is not taken as proof that the ground around it is
-- walkable, only the path itself.
-- Copyright (C) 2026 HarvestMate Enhanced contributors. GPL-3.0-or-later.

local _, ns = ...
local HME = ns.HME

local R = {}
HME.Recorder = R

R.MIN_STEP = 6           -- yards: closer than this is standing still
R.KEEP_YARDS = 40        -- a point at least this often along a straight run
R.TURN_DEG = 25          -- a turn this sharp is kept at once
R.MAX_RAW = 3000         -- points while recording (about an hour of riding)
R.MAX_SAVED = 300        -- points in a saved route
R.MAX_OBS = 300          -- gathers kept with a route
R.SIMPLIFY_YARDS = 4
R.LOOP_YARDS = 60        -- an end this near the start closes a loop

local function St() return HME.char and HME.char.recording end

function R.State()
    local s = St()
    if not (s and s.state) then return nil end
    return s
end

function R.Active() return R.State() ~= nil end

local function Here()
    local mapID, x, y = HME.Player.Position()
    if not mapID then return nil end
    local zm, zx, zy = HME.Geo.ZoneOf(mapID, x, y)
    if not (zm and zx) then return nil end
    return zm, zx, zy
end

local function Yards(mapID, ax, ay, bx, by) return HME.Geo.Distance(mapID, ax, ay, bx, by) or 0 end

local function Changed() HME.Signal("RECORDING_CHANGED") end

function R.Start(name)
    if R.Active() then return nil, "already recording" end
    local mapID, x, y = Here()
    if not mapID then return nil, "your position is not known here (an instance or a cave the map cannot show)" end
    HME.char.recording = {
        state = "recording", mapID = mapID, name = type(name) == "string" and name:sub(1, 60) or nil,
        points = { x, y }, yards = 0, secs = 0, obs = {}, since = HME.Now(), started = (time and time()) or 0,
        lastX = x, lastY = y,
    }
    HME.Print(("recording your route in %s. Ride it the way you like; /hme rec stop when done."):format(HME.ZoneData.Name(mapID) or "?"))
    Changed()
    return true
end

local function Clock(s)
    if s.state == "recording" and s.since then
        s.secs = s.secs + math.max(0, HME.Now() - s.since)
        s.since = HME.Now()
    end
end

function R.Pause(why)
    local s = R.State()
    if not s or s.state ~= "recording" then return false end
    Clock(s)
    s.state, s.since, s.why = "paused", nil, why
    Changed()
    return true
end

function R.Resume()
    local s = R.State()
    if not s or s.state ~= "paused" then return false end
    local mapID = Here()
    if mapID ~= s.mapID then
        HME.Print(("back in %s to go on recording."):format(HME.ZoneData.Name(s.mapID) or "the zone you started in"))
        return false
    end
    s.state, s.since, s.why = "recording", HME.Now(), nil
    Changed()
    return true
end

-- The direction change at the last kept point, in degrees.
local function Turn(p, x, y)
    local n = #p / 2
    if n < 2 then return 0 end
    local ax, ay, bx, by = p[2 * n - 3], p[2 * n - 2], p[2 * n - 1], p[2 * n]
    local a1 = math.atan2(by - ay, bx - ax)
    local a2 = math.atan2(y - by, x - bx)
    local d = math.abs(a2 - a1) * 180 / math.pi
    if d > 180 then d = 360 - d end
    return d
end

-- One look at where you are (once a second while recording).
function R.Sample()
    local s = R.State()
    if not s then return end
    local mapID, x, y = Here()
    if s.state == "paused" then
        if s.why == "left" and mapID == s.mapID then R.Resume() end
        return
    end
    Clock(s)
    if not mapID then return end
    if mapID ~= s.mapID then
        R.Pause("left")
        HME.Print("you left the zone you are recording: paused until you come back.")
        return
    end
    local moved = Yards(s.mapID, s.lastX, s.lastY, x, y)
    if moved < R.MIN_STEP then return end      -- standing still
    local p = s.points
    local n = #p / 2
    local fromKept = Yards(s.mapID, p[2 * n - 1], p[2 * n], x, y)
    s.yards = s.yards + moved
    s.lastX, s.lastY = x, y
    if fromKept >= R.KEEP_YARDS or (fromKept >= R.MIN_STEP * 2 and Turn(p, x, y) >= R.TURN_DEG) then
        if n >= R.MAX_RAW then
            HME.Print("this recording is as long as a route can be: stopped and saved.")
            return R.Stop()
        end
        p[#p + 1], p[#p + 2] = x, y
        Changed()
    end
end

-- What you gathered on the way, where you stood.
local function Observe(kind, name, n)
    local s = R.State()
    if not (s and s.state == "recording") then return end
    local mapID, x, y = Here()
    if mapID ~= s.mapID then return end
    if #s.obs >= R.MAX_OBS then return end
    s.obs[#s.obs + 1] = { k = kind, n = type(name) == "string" and name:sub(1, 40) or nil, x = math.floor(x * 10000 + 0.5) / 10000,
                          y = math.floor(y * 10000 + 0.5) / 10000, q = n }
    -- And the point where it happened, so the gather sits on the path.
    local p = s.points
    local last = #p / 2
    if Yards(s.mapID, p[2 * last - 1], p[2 * last], x, y) >= R.MIN_STEP then p[#p + 1], p[#p + 2] = x, y end
end
HME.Listen("GATHER_LOOT", function(prof, name) Observe(prof, name) end)
HME.Listen("BEAST_SKINNED", function(npcID) Observe("skin", HME.Skinning and HME.Skinning.BeastName and HME.Skinning.BeastName(npcID) or tostring(npcID)) end)
HME.Listen("FISH_CAUGHT", function() Observe("fish") end)

-- Douglas-Peucker in yards: turns that matter stay, the ends always.
local function Simplify(mapID, pts, tol)
    local n = #pts / 2
    if n <= 2 then return pts end
    local w, h = HME.Geo.MapYards(mapID)
    w, h = w or 1500, h or 1000
    local keep = { [1] = true, [n] = true }
    local stack = { { 1, n } }
    while #stack > 0 do
        local seg = table.remove(stack)
        local a, b = seg[1], seg[2]
        local ax, ay, bx, by = pts[2 * a - 1] * w, pts[2 * a] * h, pts[2 * b - 1] * w, pts[2 * b] * h
        local dx, dy = bx - ax, by - ay
        local len2 = dx * dx + dy * dy
        local far, at = -1, nil
        for i = a + 1, b - 1 do
            local px, py = pts[2 * i - 1] * w, pts[2 * i] * h
            local t = len2 > 0 and math.max(0, math.min(1, ((px - ax) * dx + (py - ay) * dy) / len2)) or 0
            local d = (px - ax - t * dx) ^ 2 + (py - ay - t * dy) ^ 2
            if d > far then far, at = d, i end
        end
        if at and far > tol * tol then
            keep[at] = true
            stack[#stack + 1] = { a, at }
            stack[#stack + 1] = { at, b }
        end
    end
    local out = {}
    for i = 1, n do if keep[i] then out[#out + 1], out[#out + 2] = pts[2 * i - 1], pts[2 * i] end end
    return out
end
R.Simplify = Simplify

local function R4(v) return math.floor(v * 10000 + 0.5) / 10000 end

-- Ends the recording and saves it as a route. nil, why when it is too short.
function R.Stop()
    local s = R.State()
    if not s then return nil, "not recording" end
    Clock(s)
    HME.char.recording = nil
    Changed()
    local pts = s.points
    if #pts / 2 < 3 or s.yards < 40 then
        HME.Print("that recording was too short for a route; nothing saved.")
        return nil, "too short"
    end
    local tol = R.SIMPLIFY_YARDS
    local simple = Simplify(s.mapID, pts, tol)
    while #simple / 2 > R.MAX_SAVED and tol < 200 do
        tol = tol * 1.5
        simple = Simplify(s.mapID, pts, tol)
    end
    for i = 1, #simple do simple[i] = R4(simple[i]) end
    local n = #simple / 2
    local loop = Yards(s.mapID, simple[1], simple[2], simple[2 * n - 1], simple[2 * n]) <= R.LOOP_YARDS
    -- A loop's last point and its first are one place.
    if loop and n > 3 and Yards(s.mapID, simple[1], simple[2], simple[2 * n - 1], simple[2 * n]) < R.MIN_STEP * 2 then
        simple[#simple], simple[#simple - 1] = nil, nil
    end
    local GP = HME.Routes
    local name = s.name
    if not name or name == "" or GP:RouteNamed(s.mapID, name) then
        local base = (s.name and s.name ~= "" and s.name) or ((HME.ZoneData.Name(s.mapID) or "Zone") .. " - my route")
        name = base
        local k = 2
        while GP:RouteNamed(s.mapID, name) do
            name = ("%s %d"):format(base, k)
            k = k + 1
        end
    end
    local route = { id = GP.db.nextID, mapID = s.mapID, name = name, kinds = {}, sight = 0, points = simple,
                    color = { 0.45, 0.85, 1 }, shown = true, recorded = true, recordedBy = "you",
                    source = "Recorded by you", recordedAt = s.started, recordSecs = math.floor(s.secs),
                    recordYards = math.floor(s.yards), loop = loop, backforth = not loop or nil, obs = s.obs }
    GP.db.nextID = GP.db.nextID + 1
    table.insert(GP.db.routes, route)
    route.length = GP:RouteLength(route)
    if HME.Terrain then HME.Terrain.Assemble(route) end
    GP:Changed()
    HME.Print(("saved |cffffd100%s|r: %d points, %s ridden in %s%s%s."):format(name, n, HME.U.Yards(s.yards),
        HME.U.Duration(s.secs), loop and ", a loop" or ", there and back (followed out and back)",
        #s.obs > 0 and (", " .. #s.obs .. " gathers on the way") or ""))
    return route
end

function R.Cancel()
    if not R.Active() then return false end
    HME.char.recording = nil
    Changed()
    HME.Print("recording thrown away.")
    return true
end

-- Keeps stops first..last of a recorded route (cuts a start or an end you
-- did not mean to ride). Gathers outside what is left stay with the route.
function R.Trim(route, first, last)
    if not (route and route.points) then return false end
    local n = #route.points / 2
    first, last = math.max(1, math.floor(first or 1)), math.min(n, math.floor(last or n))
    if last - first + 1 < 2 then return false end
    local out = {}
    for i = first, last do out[#out + 1], out[#out + 2] = route.points[2 * i - 1], route.points[2 * i] end
    route.points = out
    route.trimmed = true
    route.length = HME.Routes:RouteLength(route)
    if HME.Terrain then HME.Terrain.Assemble(route) end
    HME.Routes:Changed()
    return true
end

-- Gathers seen along a route, by kind and name: { { kind, name, count } }.
function R.Seen(route)
    local by, out = {}, {}
    for _, o in ipairs((route and route.obs) or {}) do
        local key = (o.k or "?") .. ":" .. (o.n or "")
        if not by[key] then
            by[key] = { kind = o.k, name = o.n, count = 0 }
            out[#out + 1] = by[key]
        end
        by[key].count = by[key].count + 1
    end
    table.sort(out, function(a, b) return a.count > b.count end)
    return out
end

-- Once a second while recording.
do
    local f = CreateFrame("Frame")
    local acc = 0
    f:SetScript("OnUpdate", function(_, dt)
        acc = acc + dt
        if acc < 1 then return end
        acc = 0
        if R.Active() then HME.Try(R.Sample) end
    end)
end

-- A recording survives /reload: it waits paused until you move again.
HME.On("PLAYER_LOGIN", function()
    HME.After(1, function()
        local s = R.State()
        if s and s.state == "recording" then
            s.since = HME.Now()
            HME.Print("still recording your route (/hme rec pause, stop or cancel).")
        end
    end)
end)
