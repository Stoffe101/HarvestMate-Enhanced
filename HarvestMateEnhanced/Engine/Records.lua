-- HarvestMate Enhanced: Engine/Records.lua
-- Personal farming records and "now against before", from your session
-- journal (HarvestMateEnhancedDB.sessions). Rates need enough behind them:
-- a record per hour counts only sessions of MIN_RATE_MINUTES farming or more,
-- so a lucky five minutes never becomes "best gold an hour". Gold is an
-- estimate from prices and says "est."; quantities are observed.
--
--   Rec.List(filter)      { { label, value, detail } } for the Stats page
--   Rec.Compare()         the session now against your earlier sessions in the
--                         same area over the same farming time, or nil when
--                         there are fewer than MIN_PREVIOUS such sessions
-- Copyright (C) 2026 HarvestMate Enhanced contributors. GPL-3.0-or-later.

local _, ns = ...
local HME = ns.HME
local U = HME.U

local Rec = {}
HME.Records = Rec

Rec.MIN_RATE_MINUTES = 30
Rec.MIN_SKILL_UPS = 10
Rec.MIN_PREVIOUS = 2
Rec.MIN_COMPARE_MINUTES = 15

local function ProfOfKey(key) return tostring(key or ""):match("^(%a+)@") end
local function ZoneOfKey(key)
    local mapID = tonumber(tostring(key or ""):match("@(%d+)"))
    return mapID and HME.ZoneData.Name(mapID) or nil
end

local function SessionProf(s)
    for _, a in ipairs(s.areas or {}) do
        local p = ProfOfKey(a.key)
        if p then return p end
    end
end

local function Leather(id)
    return HME.Goals.ProfOf(id) == "Skinning"
end

local function When(t) return date and date("%d %b %Y", t or 0) or tostring(t) end

function Rec.List(filter)
    filter = filter or {}
    local sessions = HME.db and HME.db.sessions or {}
    local best = {}
    local function Try(key, value, s, detail)
        if value and value > 0 and (not best[key] or value > best[key].value) then
            best[key] = { value = value, s = s, detail = detail }
        end
    end
    for _, s in ipairs(sessions) do
        local p = SessionProf(s)
        if (not filter.prof or filter.prof == "All" or filter.prof == p) and type(s.counts) == "table" then
            local farm = s.farmSecs or s.secs or 0
            local h = farm / 3600
            local long = farm >= Rec.MIN_RATE_MINUTES * 60
            local where = s.areas and s.areas[1] and ZoneOfKey(s.areas[1].key) or "?"
            if long and p == "Skinning" then Try("skinGph", s.value / h, s, where) end
            if long and p == "Mining" then Try("mineGph", s.value / h, s, where) end
            if long and p == "Herbalism" then Try("herbNph", (s.counts.herb or 0) / h, s, where) end
            if long and (s.skillups or 0) >= Rec.MIN_SKILL_UPS then Try("sph", s.skillups / h, s, where .. ", " .. p) end
            local leather = 0
            for id, q in pairs(s.items or {}) do if Leather(id) then leather = leather + q end end
            Try("leather", leather, s, where)
            Try("value", s.value, s, where)
            Try("long", farm, s, where)
        end
    end
    -- The most productive farm: the area with the most value an hour over 1.5 h of yours.
    local topArea
    for key, st in pairs((HME.char and HME.char.stats) or {}) do
        if (st.hours or 0) >= 1.5 and (not filter.prof or filter.prof == "All" or ProfOfKey(key) == filter.prof) then
            local v = (st.value or 0) / st.hours
            if not topArea or v > topArea.v then topArea = { key = key, v = v, h = st.hours } end
        end
    end
    -- The longest route you completed a lap of with HME's guidance.
    local longRoute
    for _, r in ipairs((HME.Routes and HME.Routes.db and HME.Routes.db.routes) or {}) do
        if (r.laps or 0) >= 1 and (not longRoute or (r.length or 0) > (longRoute.length or 0)) then longRoute = r end
    end
    local out = {}
    local function Add(key, label, fmt)
        local b = best[key]
        if b then out[#out + 1] = { label, fmt(b.value), ("%s · %s · %s farmed"):format(b.detail, When(b.s.t), U.Duration(b.s.farmSecs or b.s.secs or 0)) } end
    end
    Add("skinGph", "Best Skinning session (est. gold an hour)", function(v) return U.Money(v, true) .. "/h" end)
    Add("leather", "Most leather and hides in one session", function(v) return ("%d"):format(v) end)
    Add("herbNph", "Most efficient herb session (herbs an hour)", function(v) return ("%.0f/h"):format(v) end)
    Add("mineGph", "Best Mining session (est. gold an hour)", function(v) return U.Money(v, true) .. "/h" end)
    Add("sph", "Most skill-ups an hour", function(v) return ("%.0f/h"):format(v) end)
    Add("value", "Most valuable session (est.)", function(v) return U.Money(v, true) end)
    Add("long", "Longest session", function(v) return U.Duration(v) end)
    if topArea then
        out[#out + 1] = { "Most productive farm", U.Money(topArea.v, true) .. "/h est.",
            ("%s · %.1f h of your farming"):format(tostring(ZoneOfKey(topArea.key) or topArea.key), topArea.h) }
    end
    if longRoute then
        out[#out + 1] = { "Longest route you rode round", U.Yards(longRoute.length or 0),
            ("%s · %d lap%s"):format(longRoute.name, longRoute.laps, longRoute.laps == 1 and "" or "s") }
    end
    if #out > 0 then
        out[#out + 1] = { ("Rates count sessions of %d+ minutes only, so a lucky short one cannot set them."):format(Rec.MIN_RATE_MINUTES) }
    end
    return out
end

-- Now against before, for the session going on: the material you got most of.
function Rec.Compare()
    local live = HME.Session.Live and HME.Session.Live()
    local cur = HME.Session.Current()
    if not (live and cur and cur.areaNow and live.items[1]) then return nil end
    local minutes = live.farmSecs / 60
    if minutes < Rec.MIN_COMPARE_MINUTES then return nil end
    local top = live.items[1]
    local rates, n = 0, 0
    for _, s in ipairs((HME.db and HME.db.sessions) or {}) do
        for _, a in ipairs(s.areas or {}) do
            if a.key == cur.areaNow and (a.secs or 0) >= Rec.MIN_COMPARE_MINUTES * 60 and type(a.items) == "table" then
                rates = rates + (a.items[top.id] or 0) / (a.secs / 3600)
                n = n + 1
            end
        end
    end
    if n < Rec.MIN_PREVIOUS then return nil end
    local avg = rates / n * minutes / 60
    return { item = top.name, now = top.n, before = avg, sessions = n, minutes = minutes,
             text = ("You have %d %s in %d minutes. Your %d earlier sessions here averaged %.0f over the same time."):format(
                 top.n, top.name, minutes, n, avg) }
end
