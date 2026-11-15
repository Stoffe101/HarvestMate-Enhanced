-- HarvestMate Enhanced: Engine/Danger.lua
-- Your own danger map (0.7.0): the other players you see while out in the
-- world, and your deaths, per zone and per spot. Nothing is guessed:
--
--   seen      a player's nameplate appearing, or a player you target or mouse
--             over, outside instances. Recorded where YOU stood (a nameplate
--             shows within about 40-60 yards), once per player per 10 minutes,
--             enemy (the game's UnitIsEnemy) or not, and the hour of day.
--   presence  your time in each zone outside instances (30-second steps), so
--             "seen" becomes "an hour".
--   deaths    Engine/Risk.lua records each death; a death with an enemy player
--             seen in the 30 seconds before is marked "enemy in sight" (not
--             "killed by": the client does not say who killed you).
--
-- Kept per account, small (60 zones x 150 spots). Never shared, never sent.
-- Values the client marks secret are skipped. Read by Engine/Risk.lua (a
-- zone where you meet many enemies an hour scores riskier), the map's danger
-- layer (Map/Overlay.lua) and the Copilot.
-- Copyright (C) 2026 HarvestMate Enhanced contributors. GPL-3.0-or-later.

local _, ns = ...
local HME = ns.HME
local U = HME.U

local D = {}
HME.Danger = D

D.CELL = 0.04            -- a spot: 4% of the zone map (about 100-200 yards)
D.SAME_SECS = 600        -- the same player counts once in 10 minutes
D.IN_SIGHT_SECS = 30     -- a death this soon after an enemy was seen: "enemy in sight"
D.MAX_ZONES = 60
D.MAX_SPOTS = 150
D.MIN_HOURS = 0.5        -- below this, no "an hour" figure
D.STEP = 30

local seenAt = {}        -- [guid] = Now()
local lastEnemy          -- Now() of the last enemy seen

local function Root()
    if not HME.db then return nil end
    local obs = HME.db.obs
    obs.players = type(obs.players) == "table" and obs.players or {}
    obs.presence = type(obs.presence) == "table" and obs.presence or {}
    return obs
end

local function Call(fn, ...)
    if type(fn) ~= "function" then return nil end
    local ok, v = pcall(fn, ...)
    if not ok then return nil end
    return v
end

local function InInstance()
    local v = Call(_G.IsInInstance)
    return HME.Bool(v) == true
end

local function Cell(x, y)
    local cx, cy = math.floor(x / D.CELL), math.floor(y / D.CELL)
    return cx .. ":" .. cy, (cx + 0.5) * D.CELL, (cy + 0.5) * D.CELL
end

local function Hour()
    local d = _G.date and Call(_G.date, "*t")
    return type(d) == "table" and type(d.hour) == "number" and d.hour or nil
end

-- Bounded: the least recently seen spots and zones go first. Counting is
-- cheap; lists are built only when a limit is passed (0.7.0's benchmark:
-- building them on every sighting made 7 KB of garbage each).
local function Trim(players, mapID)
    local spots = players[mapID]
    local n = 0
    for _ in pairs(spots or {}) do n = n + 1 end
    if n > D.MAX_SPOTS then
        local list = {}
        for k, s in pairs(spots) do list[#list + 1] = { k = k, t = s.t or 0 } end
        table.sort(list, function(a, b) return a.t > b.t end)
        for i = D.MAX_SPOTS + 1, #list do spots[list[i].k] = nil end
    end
    local zones = 0
    for _ in pairs(players) do zones = zones + 1 end
    if zones > D.MAX_ZONES then
        local list = {}
        for id, sp in pairs(players) do
            local last = 0
            for _, s in pairs(sp) do if (s.t or 0) > last then last = s.t or 0 end end
            list[#list + 1] = { id = id, last = last }
        end
        table.sort(list, function(a, b) return a.last > b.last end)
        for i = D.MAX_ZONES + 1, #list do players[list[i].id] = nil end
    end
end

-- Records one sighting at the player's position. enemy: boolean.
-- (Also the test hook: D.Note(mapID, x, y, enemy, guid).)
function D.Note(mapID, x, y, enemy, guid)
    local obs = Root()
    if not (obs and mapID and x and y) then return false end
    local now = HME.Now()
    if guid then
        if seenAt[guid] and now - seenAt[guid] < D.SAME_SECS then return false end
        seenAt[guid] = now
    end
    if enemy then lastEnemy = now end
    local spots = obs.players[mapID] or {}
    obs.players[mapID] = spots
    local key, cx, cy = Cell(x, y)
    local s = spots[key] or { x = U.Round(cx, 3), y = U.Round(cy, 3), e = 0, f = 0 }
    spots[key] = s
    if enemy then s.e = s.e + 1 else s.f = s.f + 1 end
    s.t = (time and time()) or 0
    local h = Hour()
    if enemy and h then
        s.h = s.h or {}
        s.h[h + 1] = (s.h[h + 1] or 0) + 1
    end
    Trim(obs.players, mapID)
    HME.Soon("danger-changed", 5, function() HME.Signal("DANGER_CHANGED") end)
    return true
end

-- Reads a unit the client shows; records it when it is another player.
function D.Seen(unit)
    if not unit or InInstance() then return false end
    if HME.Bool(Call(_G.UnitIsPlayer, unit)) ~= true then return false end
    if HME.Bool(Call(_G.UnitIsUnit, unit, "player")) == true then return false end
    if HME.Bool(Call(_G.UnitInParty, unit)) == true or HME.Bool(Call(_G.UnitInRaid, unit)) == true then return false end
    local enemy = HME.Bool(Call(_G.UnitIsEnemy, "player", unit))
    if enemy == nil then return false end   -- (secret or unknown: not counted)
    local guid = HME.Str(Call(_G.UnitGUID, unit))
    local mapID, x, y = HME.Player.Position()
    if not mapID then return false end
    local zm, zx, zy = HME.Geo.ZoneOf(mapID, x, y)
    return D.Note(zm or mapID, zx or x, zy or y, enemy, guid)
end

HME.On("NAME_PLATE_UNIT_ADDED", function(_, unit) D.Seen(unit) end)
HME.On("PLAYER_TARGET_CHANGED", function() D.Seen("target") end)
HME.On("UPDATE_MOUSEOVER_UNIT", function() D.Seen("mouseover") end)

-- Time in each zone, outside instances.
local lastStep
function D.Step()
    local now = HME.Now()
    local dt = lastStep and math.min(now - lastStep, 2 * D.STEP) or 0
    lastStep = now
    local obs = Root()
    if not obs or dt <= 0 or InInstance() then return end
    local mapID, x, y = HME.Player.Position()
    if not mapID then return end
    local zm = HME.Geo.ZoneOf(mapID, x, y) or mapID
    obs.presence[zm] = (obs.presence[zm] or 0) + dt
end

local running
local function Loop()
    D.Step()
    HME.After(D.STEP, Loop)
end
HME.On("PLAYER_ENTERING_WORLD", function()
    lastStep = HME.Now()
    if not running then
        running = true
        HME.After(D.STEP, Loop)
    end
end)

-- A death with an enemy seen just before (called by Engine/Risk.lua).
function D.EnemyInSight()
    return lastEnemy ~= nil and HME.Now() - lastEnemy <= D.IN_SIGHT_SECS
end

---------------------------------------------------------------------------
-- Reading it back
---------------------------------------------------------------------------
local function Window(hours)
    -- The 3 hours of the day with most enemies, as "19-22 h".
    local best, bi = 0, nil
    for i = 1, 24 do
        local n = (hours[i] or 0) + (hours[i % 24 + 1] or 0) + (hours[(i + 1) % 24 + 1] or 0)
        if n > best then best, bi = n, i end
    end
    if not bi or best < 3 then return nil end
    return ("%d-%d h"):format(bi - 1, (bi + 2) % 24)
end

-- Everything known about a zone:
-- { enemies, friends, hours, enemiesPerHour, othersPerHour, deaths, inSight, peak, text }
function D.Zone(mapID)
    local obs = Root()
    local out = { enemies = 0, friends = 0, hours = 0, deaths = 0, inSight = 0 }
    if not (obs and mapID) then out.text = "" return out end
    local hours = {}
    for _, s in pairs(obs.players[mapID] or {}) do
        out.enemies = out.enemies + (s.e or 0)
        out.friends = out.friends + (s.f or 0)
        for i, n in pairs(s.h or {}) do hours[i] = (hours[i] or 0) + n end
    end
    out.hours = (obs.presence[mapID] or 0) / 3600
    if out.hours >= D.MIN_HOURS then
        out.enemiesPerHour = out.enemies / out.hours
        out.othersPerHour = (out.enemies + out.friends) / out.hours
    end
    out.peak = Window(hours)
    for _, d in ipairs(obs.deaths or {}) do
        if d.m == mapID then
            out.deaths = out.deaths + 1
            if d.pvp then out.inSight = out.inSight + 1 end
        end
    end
    local parts = {}
    if out.enemies > 0 or out.hours >= D.MIN_HOURS then
        if out.enemiesPerHour then
            parts[#parts + 1] = ("%d enemy player%s seen in %.1f h here (%s an hour)"):format(out.enemies,
                out.enemies == 1 and "" or "s", out.hours, out.enemiesPerHour >= 10 and tostring(math.floor(out.enemiesPerHour + 0.5))
                or ("%.1f"):format(out.enemiesPerHour))
        else
            parts[#parts + 1] = ("%d enemy player%s seen here"):format(out.enemies, out.enemies == 1 and "" or "s")
        end
        if out.peak then parts[#parts + 1] = "mostly " .. out.peak end
    end
    if out.deaths > 0 then
        parts[#parts + 1] = ("you died here %d time%s%s"):format(out.deaths, out.deaths == 1 and "" or "s",
            out.inSight > 0 and (", %d with an enemy in sight"):format(out.inSight) or "")
    end
    out.text = #parts > 0 and (table.concat(parts, "; ") .. ".") or ""
    return out
end

-- Enemy sightings within `yards` of a point: count, and spots.
function D.Near(mapID, x, y, yards)
    local obs = Root()
    local n, spots = 0, {}
    if not (obs and mapID and x and y) then return 0, spots end
    for _, s in pairs(obs.players[mapID] or {}) do
        if (s.e or 0) > 0 then
            local d = HME.Geo.Distance(mapID, x, y, s.x, s.y)
            if d and d <= (yards or 300) then
                n = n + s.e
                spots[#spots + 1] = s
            end
        end
    end
    return n, spots
end

-- 0-1 for Engine/Risk.lua: enemies an hour in the zone (8 an hour or more
-- is 1), with at least D.MIN_HOURS there; nil when not enough is known.
function D.Pressure(mapID)
    local z = D.Zone(mapID)
    if not z.enemiesPerHour then return nil, z end
    return U.Clamp(z.enemiesPerHour / 8, 0, 1), z
end

-- What the map's danger layer draws: spots with enemies, and deaths.
function D.MapData(mapID)
    local obs = Root()
    local out = { spots = {}, deaths = {} }
    if not (obs and mapID) then return out end
    local most = 1
    for _, s in pairs(obs.players[mapID] or {}) do
        if (s.e or 0) > 0 then
            out.spots[#out.spots + 1] = s
            if s.e > most then most = s.e end
        end
    end
    out.most = most
    for _, d in ipairs(obs.deaths or {}) do
        if d.m == mapID and d.x and d.y then out.deaths[#out.deaths + 1] = d end
    end
    return out
end

-- Forgets sightings and time (Settings, Forget learned data does it too).
function D.Forget()
    local obs = Root()
    if not obs then return end
    obs.players, obs.presence = {}, {}
    seenAt, lastEnemy = {}, nil
end

-- For /hme diag.
function D.Status()
    local obs = Root()
    if not obs then return "no data" end
    local zones, e, f, secs = 0, 0, 0, 0
    for _, spots in pairs(obs.players) do
        zones = zones + 1
        for _, s in pairs(spots) do e, f = e + (s.e or 0), f + (s.f or 0) end
    end
    for _, v in pairs(obs.presence) do secs = secs + v end
    return ("%d enemy and %d other players seen in %d zones, %.1f h in the open world"):format(e, f, zones, secs / 3600)
end
