-- HarvestMate Enhanced: Engine/Trends.lua
-- How a material's auction price has moved (0.7.0). HME still never scans the
-- auction house: it keeps one point a day for each gathering material it
-- prices (the day's lowest listing and the latest typical figure, from
-- whichever addon Engine/Prices.lua read), 21 days, at most 300 items.
-- When Forever-GPS keeps a history for an item (its own daily scans of items
-- your recipes use), that one is read first.
--
-- A trend needs 3 days or more: today's figure against the median of the
-- days before. Up or down by 10% or more says so; anything else is "steady".
-- These are listings, not sales, and every text says so. A price whose age
-- the addon reports as over a day is not logged as today's.
-- Copyright (C) 2026 HarvestMate Enhanced contributors. GPL-3.0-or-later.

local _, ns = ...
local HME = ns.HME

local Tr = {}
HME.Trends = Tr

Tr.DAYS = 21
Tr.MAX_ITEMS = 300
Tr.MIN_POINTS = 3
Tr.MOVE = 0.10

local function Day() return math.floor(((time and time()) or 0) / 86400) end
local function Log()
    if not HME.db then return nil end
    HME.db.priceLog = type(HME.db.priceLog) == "table" and HME.db.priceLog or {}
    return HME.db.priceLog
end

local function Parse(text)
    local pts = {}
    for d, low, typ in (type(text) == "string" and text or ""):gmatch("(%d+):(%d+):(%d+)") do
        pts[#pts + 1] = { day = tonumber(d), low = tonumber(low), typical = tonumber(typ) }
    end
    return pts
end

local function Pack(pts)
    local parts = {}
    for i, p in ipairs(pts) do parts[i] = ("%d:%d:%d"):format(p.day, math.floor(p.low + 0.5), math.floor(p.typical + 0.5)) end
    return table.concat(parts, ";")
end

-- Called by Engine/Prices.lua with a provider's sane record (copper a unit,
-- before the cut). Only gathering materials HME knows are logged.
function Tr.Note(itemID, raw)
    local log = Log()
    if not (log and itemID and type(raw) == "table" and raw.typical) then return false end
    if not (ns.itemIndex and ns.itemIndex[itemID]) then return false end
    if raw.age and raw.age > 86400 then return false end
    local today = Day()
    local pts = Parse(log[itemID])
    local last = pts[#pts]
    if last and last.day == today then
        last.low = math.min(last.low, raw.low or raw.typical)
        last.typical = raw.typical
    else
        pts[#pts + 1] = { day = today, low = raw.low or raw.typical, typical = raw.typical }
    end
    while #pts > 0 and today - pts[1].day >= Tr.DAYS do table.remove(pts, 1) end
    log[itemID] = Pack(pts)
    -- Bounded: the items priced longest ago go first.
    local n = 0
    for _ in pairs(log) do n = n + 1 end
    if n > Tr.MAX_ITEMS then
        local list = {}
        for id, text in pairs(log) do list[#list + 1] = { id = id, last = tonumber(text:match("(%d+):%d+:%d+$")) or 0 } end
        table.sort(list, function(a, b) return a.last > b.last end)
        for i = Tr.MAX_ITEMS + 1, #list do log[list[i].id] = nil end
    end
    return true
end

-- Forever-GPS's history of an item, when it keeps one.
local function FromForeverGPS(itemID)
    local FG = _G.ForeverGPS
    local H = type(FG) == "table" and type(FG.PriceHistory) == "table" and FG.PriceHistory
    if not (H and type(H.Of) == "function") then return nil end
    local ok, pts = pcall(H.Of, itemID)
    if not ok or type(pts) ~= "table" or #pts < Tr.MIN_POINTS then return nil end
    local out = {}
    for i, p in ipairs(pts) do
        if type(p) ~= "table" or type(p.low) ~= "number" or type(p.day) ~= "number" then return nil end
        out[i] = { day = p.day, low = p.low, typical = p.low }
    end
    return out
end

-- { points = { {day, low, typical} }, trend = "up"|"down"|"steady"|nil,
--   change (0.18 = +18%), median, now, days, source, text }
function Tr.Of(itemID)
    local pts, source = FromForeverGPS(itemID), "Forever-GPS's daily scans"
    if not pts then
        local log = Log()
        pts, source = Parse(log and log[itemID]), "prices HME saw"
    end
    local out = { points = pts, days = #pts, source = source }
    if #pts < Tr.MIN_POINTS then
        out.text = #pts == 0 and "No price history yet." or
            ("Price history: %d day%s so far; a trend needs %d."):format(#pts, #pts == 1 and "" or "s", Tr.MIN_POINTS)
        return out
    end
    local before = {}
    for i = 1, #pts - 1 do before[i] = pts[i].typical end
    table.sort(before)
    local median = before[math.ceil(#before / 2)]
    local now = pts[#pts].typical
    out.median, out.now = median, now
    out.change = median > 0 and (now - median) / median or 0
    out.trend = out.change >= Tr.MOVE and "up" or (out.change <= -Tr.MOVE and "down" or "steady")
    local money = HME.Kit and HME.Kit.Money or function(c) return tostring(c) end
    if out.trend == "steady" then
        out.text = ("Steady: %s against a median of %s over the %d days before (%s; listings, not sales)."):format(
            money(now), money(median), #pts - 1, source)
    else
        out.text = ("%s %d%%: %s against a median of %s over the %d days before (%s; listings, not sales)."):format(
            out.trend == "up" and "Up" or "Down", math.floor(math.abs(out.change) * 100 + 0.5), money(now), money(median),
            #pts - 1, source)
    end
    return out
end

-- A word of advice from a trend (never an instruction to sell or buy).
function Tr.Advice(t)
    if not (t and t.trend) then return nil end
    if t.trend == "up" then return "Above its usual price: a good time to list if you were going to sell." end
    if t.trend == "down" then return "Below its usual price: keeping it a few days may pay, if you have the bag space." end
    return nil
end

-- The materials with the biggest move, for the Copilot: { { id, t } }, up first.
function Tr.Movers(ids, minChange)
    local out = {}
    for _, id in ipairs(ids or {}) do
        local t = Tr.Of(id)
        if t.trend and t.trend ~= "steady" and math.abs(t.change) >= (minChange or 0.2) then out[#out + 1] = { id = id, t = t } end
    end
    table.sort(out, function(a, b) return a.t.change > b.t.change end)
    return out
end

function Tr.Forget()
    if HME.db then HME.db.priceLog = {} end
end

function Tr.Status()
    local log = Log()
    if not log then return "no data" end
    local n, days = 0, 0
    for _, text in pairs(log) do
        n = n + 1
        local p = #Parse(text)
        if p > days then days = p end
    end
    return ("%d materials with a price history, up to %d days"):format(n, days)
end
