-- HarvestMate Enhanced: Core/Util.lua
-- Small pure helpers: numbers, geometry, formatting, bounded lists and a
-- deterministic random generator. No game calls; the tests load it alone.
-- Copyright (C) 2026 HarvestMate Enhanced contributors. GPL-3.0-or-later.

local _, ns = ...
local HME = ns.HME
local U = {}
HME.U = U

local floor, sqrt, max, min, abs = math.floor, math.sqrt, math.max, math.min, math.abs

function U.Clamp(v, lo, hi)
    if v < lo then return lo end
    if v > hi then return hi end
    return v
end

function U.Round(v, places)
    local m = 10 ^ (places or 0)
    return floor(v * m + 0.5) / m
end

function U.Lerp(a, b, t) return a + (b - a) * t end

function U.Dist(ax, ay, bx, by)
    local dx, dy = ax - bx, ay - by
    return sqrt(dx * dx + dy * dy)
end

-- Distance from point p to segment a-b.
function U.SegDist(px, py, ax, ay, bx, by)
    local dx, dy = bx - ax, by - ay
    local len2 = dx * dx + dy * dy
    if len2 == 0 then return U.Dist(px, py, ax, ay) end
    local t = U.Clamp(((px - ax) * dx + (py - ay) * dy) / len2, 0, 1)
    return U.Dist(px, py, ax + t * dx, ay + t * dy)
end

-- Point in polygon (flat {x1,y1,x2,y2,...}), ray casting.
function U.InPolygon(poly, x, y)
    local inside = false
    local n = #poly / 2
    local j = n
    for i = 1, n do
        local xi, yi = poly[2 * i - 1], poly[2 * i]
        local xj, yj = poly[2 * j - 1], poly[2 * j]
        if ((yi > y) ~= (yj > y)) and (x < (xj - xi) * (y - yi) / (yj - yi) + xi) then
            inside = not inside
        end
        j = i
    end
    return inside
end

-- Convex hull (monotone chain) of { {x,y}, ... }; returns a list of points.
function U.Hull(points)
    local pts = {}
    for i = 1, #points do pts[i] = points[i] end
    if #pts < 3 then return pts end
    table.sort(pts, function(a, b)
        if a[1] ~= b[1] then return a[1] < b[1] end
        return a[2] < b[2]
    end)
    local function cross(o, a, b)
        return (a[1] - o[1]) * (b[2] - o[2]) - (a[2] - o[2]) * (b[1] - o[1])
    end
    local lower, upper = {}, {}
    for i = 1, #pts do
        while #lower >= 2 and cross(lower[#lower - 1], lower[#lower], pts[i]) <= 0 do lower[#lower] = nil end
        lower[#lower + 1] = pts[i]
    end
    for i = #pts, 1, -1 do
        while #upper >= 2 and cross(upper[#upper - 1], upper[#upper], pts[i]) <= 0 do upper[#upper] = nil end
        upper[#upper + 1] = pts[i]
    end
    lower[#lower] = nil
    upper[#upper] = nil
    for i = 1, #upper do lower[#lower + 1] = upper[i] end
    return lower
end

---------------------------------------------------------------------------
-- Gatherpedia's packed spawn points: 4 characters per point, x then y, each
-- two base-36 digits in tenths of a percent (0-999 -> 0.000-0.999).
---------------------------------------------------------------------------
local B36 = {}
do
    local digits = "0123456789abcdefghijklmnopqrstuvwxyz"
    for i = 1, #digits do B36[digits:byte(i)] = i - 1 end
end

-- Calls fn(x, y) with map positions 0-1 for each point in s.
function U.EachPacked(s, fn)
    if type(s) ~= "string" then return 0 end
    local n = 0
    for i = 1, #s - 3, 4 do
        local a, b, c, d = s:byte(i, i + 3)
        local x = (B36[a] or 0) * 36 + (B36[b] or 0)
        local y = (B36[c] or 0) * 36 + (B36[d] or 0)
        fn(x / 1000, y / 1000)
        n = n + 1
    end
    return n
end

function U.PackedCount(s)
    return type(s) == "string" and floor(#s / 4) or 0
end

---------------------------------------------------------------------------
-- A seeded random generator (Park-Miller): the same seed gives the same
-- numbers on every client and in the tests.
---------------------------------------------------------------------------
function U.Random(seed)
    local state = (seed or 1) % 2147483647
    if state <= 0 then state = state + 2147483646 end
    return function(a, b)
        state = (state * 16807) % 2147483647
        local r = (state - 1) / 2147483646
        if a and b then return a + floor(r * (b - a + 1)) end
        if a then return 1 + floor(r * a) end
        return r
    end
end

---------------------------------------------------------------------------
-- Formatting
---------------------------------------------------------------------------
function U.Thousands(v)
    v = floor((v or 0) + 0.5)
    local s = tostring(abs(v)):reverse():gsub("(%d%d%d)", "%1,"):reverse()
    s = s:gsub("^,", "")
    if v < 0 then s = "-" .. s end
    return s
end

-- 123456 copper -> "12g 34s 56c" (plain text; the UI adds coin icons)
function U.Money(copper, short)
    copper = floor((copper or 0) + 0.5)
    local neg = copper < 0
    copper = abs(copper)
    local g, s, c = floor(copper / 10000), floor(copper / 100) % 100, copper % 100
    local out
    if short then
        if g > 0 then
            out = g >= 100 and (U.Thousands(g) .. "g") or (s > 0 and (g .. "g " .. s .. "s") or (g .. "g"))
        elseif s > 0 then
            out = s .. "s"
        else
            out = c .. "c"
        end
    else
        local parts = {}
        if g > 0 then parts[#parts + 1] = "|cffffd100" .. U.Thousands(g) .. "g|r" end
        if s > 0 then parts[#parts + 1] = "|cffc7c7cf" .. s .. "s|r" end
        if c > 0 or #parts == 0 then parts[#parts + 1] = "|cffeda55f" .. c .. "c|r" end
        out = table.concat(parts, " ")
    end
    return neg and ("-" .. out) or out
end

function U.Duration(secs)
    secs = floor((secs or 0) + 0.5)
    if secs < 60 then return secs .. " s" end
    local mins = floor(secs / 60 + 0.5)
    if mins < 60 then return mins .. " min" end
    return ("%d h %02d min"):format(floor(mins / 60), mins % 60)
end

function U.Yards(v) return U.Thousands(v) .. " yd" end

function U.Percent(p, places)
    return ("%." .. (places or 0) .. "f%%"):format((p or 0) * 100)
end

function U.Trim(s)
    if type(s) ~= "string" then return nil end
    return s:match("^%s*(.-)%s*$")
end

---------------------------------------------------------------------------
-- Tables
---------------------------------------------------------------------------
function U.Copy(t)
    if type(t) ~= "table" then return t end
    local c = {}
    for k, v in pairs(t) do c[k] = U.Copy(v) end
    return c
end

function U.Keys(t, sorted)
    local list = {}
    for k in pairs(t or {}) do list[#list + 1] = k end
    if sorted then table.sort(list, function(a, b) return tostring(a) < tostring(b) end) end
    return list
end

function U.Count(t)
    local n = 0
    for _ in pairs(t or {}) do n = n + 1 end
    return n
end

-- Appends to a list kept at most `limit` long (oldest dropped first).
function U.Push(list, item, limit)
    list[#list + 1] = item
    local extra = #list - limit
    if extra > 0 then
        for i = 1, #list - extra do list[i] = list[i + extra] end
        for i = #list, #list - extra + 1, -1 do list[i] = nil end
    end
    return list
end

function U.Contains(list, v)
    for i = 1, #(list or {}) do if list[i] == v then return true end end
    return false
end

-- Quantile of a sorted copy (q in 0-1).
function U.Quantile(values, q)
    if #values == 0 then return nil end
    local s = {}
    for i = 1, #values do s[i] = values[i] end
    table.sort(s)
    local pos = 1 + (#s - 1) * q
    local lo, hi = floor(pos), math.ceil(pos)
    return s[lo] + (s[hi] - s[lo]) * (pos - lo)
end

U.max, U.min = max, min
