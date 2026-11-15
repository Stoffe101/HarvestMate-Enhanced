-- HarvestMate Enhanced: Engine/Ledger.lua (0.6.0)
-- How well HME's predictions matched what you got, and what that teaches.
--
-- Every farming session that followed a planned farm keeps what was predicted
-- next to what happened (Engine/Session.lua writes both into the journal).
-- The ledger reads them back:
--
--   entry    one area of one session, 10+ farming minutes, with a prediction:
--            predicted and observed PACE (skins, nodes or catches an hour) and,
--            when both are known, skill-ups an hour. Never gold: a price that
--            moved is not a prediction that was wrong.
--   factor   per profession, how far observed runs from predicted, as a
--            weighted geometric mean of observed/predicted shrunk toward 1:
--              log f = sum(w x log r) / (sum(w) + W0)
--            w = hours (at most 2 a session) x recency (half-life 30 days),
--            other characters' sessions at half weight, r clamped to 0.2-3.
--            W0 = 1.5 hours of "the model is right", so five lucky skins in a
--            quarter of an hour move the factor by a seventh of their ratio.
--   skill    skill-ups have their own factor, but skill-ups also fall as a
--            farm turns grey during a session and stop at a rank cap, so it is
--            only used with 4+ sessions and 3+ hours, and then blended with
--            the pace factor (their geometric mean); else pace alone scales
--            skill-ups.
--   applied  to farms you have NOT measured yourself (measured farms already
--            blend your own rates in, Engine/Learning.lua), once at least two
--            sessions back it and it differs from 1 by 5% or more. The factor
--            used is stored with the prediction, so the next comparison is
--            made against the uncalibrated model and the ledger never chases
--            its own tail.
-- Copyright (C) 2026 HarvestMate Enhanced contributors. GPL-3.0-or-later.

local _, ns = ...
local HME = ns.HME
local U = HME.U

local Lg = {}
HME.Ledger = Lg

Lg.MIN_SECS = 600
Lg.W0 = 1.5
Lg.MAX_W = 2
Lg.HALF_LIFE = 30 * 86400
Lg.OTHERS = 0.5
Lg.CLAMP_LOW, Lg.CLAMP_HIGH = 0.2, 3
Lg.MIN_SESSIONS = 2
Lg.SKILL_SESSIONS, Lg.SKILL_HOURS = 4, 3
Lg.MIN_EFFECT = 0.05

-- Which observed count answers which predicted rate.
local PACE = {
    Skinning = { pred = "skins", alt = "beasts", unit = "skins" },
    Herbalism = { pred = "nodes", unit = "nodes" },
    Mining = { pred = "nodes", unit = "nodes" },
    Combined = { pred = "nodes", unit = "nodes" },
    Fishing = { pred = "catches", unit = "catches" },
}
Lg.PACE = PACE

local function ProfOfKey(key) return tostring(key or ""):match("^(%a+)@") end
Lg.ProfOfKey = ProfOfKey

local function Me() return UnitName and HME.Str((UnitName("player"))) or nil end
local function NowT() return (time and time()) or 0 end

-- Observed count of a session area for a profession's pace.
local function Observed(prof, a)
    if prof == "Skinning" then return math.max(a.skins or 0, a.beasts or 0) end
    if prof == "Fishing" then return a.catches or 0 end
    return a.nodes or 0
end

-- Every usable entry, newest first. filter = { prof, key, char } (all optional).
function Lg.Entries(filter)
    filter = filter or {}
    local out = {}
    local me = Me()
    local sessions = (HME.db and HME.db.sessions) or {}
    for i = #sessions, 1, -1 do
        local s = sessions[i]
        for _, a in ipairs(type(s) == "table" and s.areas or {}) do
            local pred = type(a) == "table" and a.predicted
            local prof = type(a) == "table" and ProfOfKey(a.key)
            local spec = prof and PACE[prof]
            if type(pred) == "table" and spec and (a.secs or 0) >= Lg.MIN_SECS
                and (not filter.prof or filter.prof == prof) and (not filter.key or filter.key == a.key)
                and (not filter.char or filter.char == s.char) then
                local calib = type(pred.calib) == "number" and pred.calib > 0 and pred.calib or 1
                local p = pred[spec.pred] or (spec.alt and pred[spec.alt])
                local hours = a.secs / 3600
                if type(p) == "number" and p > 0 then
                    local model = p / calib
                    local obs = Observed(prof, a) / hours
                    local e = { key = a.key, prof = prof, t = s.t or 0, hours = hours, unit = spec.unit,
                        predicted = model, shown = p, observed = obs, ratio = obs / model,
                        char = s.char, mine = (s.char == nil or s.char == me) }
                    if type(pred.skill) == "number" and pred.skill > 0 and a.skillups then
                        local sc = type(pred.skillCalib) == "number" and pred.skillCalib > 0 and pred.skillCalib or calib
                        e.skillPredicted = pred.skill / sc
                        e.skillObserved = a.skillups / hours
                    end
                    out[#out + 1] = e
                end
            end
        end
    end
    return out
end

local function Clamp(r) return math.max(Lg.CLAMP_LOW, math.min(Lg.CLAMP_HIGH, r)) end

-- Weighted, shrunk factor from a list of { ratio, hours, t, mine }.
local function Fit(list, ratioOf)
    local now = NowT()
    local num, den, sq, n, hours, mineN = 0, 0, 0, 0, 0, 0
    local logs = {}
    for _, e in ipairs(list) do
        local r = ratioOf(e)
        if r and r > 0 then
            local age = math.max(0, now - (e.t or now))
            local w = math.min(e.hours, Lg.MAX_W) * 0.5 ^ (age / Lg.HALF_LIFE) * (e.mine and 1 or Lg.OTHERS)
            local l = math.log(Clamp(r))
            num, den, sq = num + w * l, den + w, sq + w * w
            logs[#logs + 1] = { l = l, w = w }
            n, hours = n + 1, hours + e.hours
            if e.mine then mineN = mineN + 1 end
        end
    end
    if n == 0 then return nil end
    local lf = num / (den + Lg.W0)
    -- Spread of the observations around their own mean, for an honest band.
    local mean = num / den
    local var = 0
    for _, x in ipairs(logs) do var = var + x.w * (x.l - mean) ^ 2 end
    var = var / den
    local nEff = den * den / math.max(sq, 1e-9)
    local se = math.sqrt(var / math.max(1, nEff) + 0.15 ^ 2 / math.max(1, nEff)) * den / (den + Lg.W0)
    return { factor = math.exp(lf), low = math.exp(lf - 1.28 * se), high = math.exp(lf + 1.28 * se),
        sessions = n, mine = mineN, hours = hours, weight = den, raw = math.exp(mean) }
end

local cache = {}
HME.Listen("SESSION_ENDED", function() cache = {} end)
HME.Listen("LEARNED", function() cache = {} end)
function Lg.Forget() cache = {} end

-- { factor, low, high, sessions, hours, weight, raw, used, text } for a
-- profession's pace ("pace") or skill-ups ("skill"); nil without entries.
function Lg.Factor(prof, which)
    which = which or "pace"
    local ck = prof .. ":" .. which
    if cache[ck] ~= nil then return cache[ck] or nil end
    local list = Lg.Entries({ prof = prof })
    local f = Fit(list, function(e)
        if which == "skill" then return e.skillPredicted and e.skillObserved and e.skillObserved / e.skillPredicted end
        return e.ratio
    end)
    if f then
        f.used = f.sessions >= Lg.MIN_SESSIONS and math.abs(f.factor - 1) >= Lg.MIN_EFFECT
        if which == "skill" then f.used = f.used and f.sessions >= Lg.SKILL_SESSIONS and f.hours >= Lg.SKILL_HOURS end
        f.text = Lg.FactorText(prof, f, which)
    end
    cache[ck] = f or false
    return f
end

function Lg.FactorText(prof, f, which)
    local what = which == "skill" and "skill-up estimates" or "pace estimates"
    local base = ("%d session%s, %.1f h"):format(f.sessions, f.sessions == 1 and "" or "s", f.hours)
    if f.sessions < Lg.MIN_SESSIONS then
        return ("%s %s: one session so far (%s), not enough to adjust."):format(prof, what, base)
    end
    local pct = math.floor(math.abs(f.factor - 1) * 100 + 0.5)
    if f.factor <= 0.95 then
        return ("%s %s run about %d%% high for you (%s): unmeasured farms are scaled down to match."):format(prof, what, pct, base)
    elseif f.factor >= 1.05 then
        return ("%s %s run about %d%% low for you (%s): unmeasured farms are scaled up to match."):format(prof, what, pct, base)
    end
    return ("%s %s match your results (within 5%%, %s)."):format(prof, what, base)
end

-- Predicted against observed for one farm: { sessions, hours, predicted,
-- observed, ratio, error, sure } (sure: 1.5 h over 2 sessions, as Learning).
function Lg.Area(key)
    local list = Lg.Entries({ key = key })
    if #list == 0 then return nil end
    local ph, oh, hours = 0, 0, 0
    for _, e in ipairs(list) do
        ph, oh, hours = ph + e.predicted * e.hours, oh + e.observed * e.hours, hours + e.hours
    end
    local predicted, observed = ph / hours, oh / hours
    local ratio = predicted > 0 and observed / predicted or nil
    return { sessions = #list, hours = hours, predicted = predicted, observed = observed, ratio = ratio,
        error = ratio and (ratio - 1) or nil, unit = list[1].unit, sure = hours >= 1.5 and #list >= 2, entries = list }
end

-- Scales a Farm Finder result's model numbers by its profession's factor,
-- when this character has not measured the farm. Returns the factor or nil.
-- Idempotent: the engines cache their figures between searches, so the factor
-- already applied is kept on the figures and only the difference is applied
-- (scaling again on every search would compound; caught in 0.6.0's previews).
function Lg.Calibrate(r)
    if not (r and r.metrics and r.prof and PACE[r.prof]) then return nil end
    local m = r.metrics
    local want, wantSkill, f = 1, 1, nil
    local own = HME.Learning.Own(r.key)
    if not (HME.settings and HME.settings.calibrate == false) and not (own and own >= HME.Learning.MIN_HOURS) then
        f = Lg.Factor(r.prof, "pace")
        if f and f.used then
            want = f.factor
            local s = Lg.Factor(r.prof, "skill")
            wantSkill = (s and s.used) and math.sqrt(s.factor * want) or want
        else
            f = nil
        end
    end
    local k = want / (m.calibPace or 1)
    local ks = wantSkill / (m.calibSkill or 1)
    if k ~= 1 then
        for _, field in ipairs({ "beastsPerHour", "nodesPerHour", "catchesPerHour", "materialPerHour" }) do
            if type(m[field]) == "number" then m[field] = m[field] * k end
        end
        if type(m.gph) == "table" then
            for mode, v in pairs(m.gph) do if type(v) == "number" then m.gph[mode] = v * k end end
        end
    end
    if ks ~= 1 and type(m.skillPerHour) == "number" then m.skillPerHour = m.skillPerHour * ks end
    m.calibPace, m.calibSkill = want, wantSkill
    r.calibrated = f and { factor = want, skill = wantSkill, text = f.text } or nil
    return f and want or nil
end

-- A short report for the Copilot page and /hme diag:
-- { profs = { { prof, pace, skill } }, farms = { area summaries, worst first }, entries = n }
function Lg.Report()
    local out = { profs = {}, farms = {}, entries = 0 }
    for _, prof in ipairs({ "Skinning", "Herbalism", "Mining", "Fishing", "Combined" }) do
        local f = Lg.Factor(prof, "pace")
        if f then out.profs[#out.profs + 1] = { prof = prof, pace = f, skill = Lg.Factor(prof, "skill") } end
    end
    local seen = {}
    for _, e in ipairs(Lg.Entries()) do
        out.entries = out.entries + 1
        if not seen[e.key] then
            seen[e.key] = true
            local a = Lg.Area(e.key)
            if a then
                a.key, a.prof = e.key, e.prof
                out.farms[#out.farms + 1] = a
            end
        end
    end
    table.sort(out.farms, function(x, y) return (x.hours or 0) > (y.hours or 0) end)
    return out
end

-- "Predicted 60 skins/h, observed 48/h: 20% under (3 sessions, 1.4 h)."
function Lg.AreaText(a)
    if not (a and a.ratio) then return nil end
    local pct = math.floor(math.abs(a.ratio - 1) * 100 + 0.5)
    local how = a.ratio >= 1.05 and ("%d%% over"):format(pct) or (a.ratio <= 0.95 and ("%d%% under"):format(pct) or "on target")
    return ("Predicted %.0f %s/h, observed %.0f/h: %s (%d session%s, %.1f h)%s."):format(a.predicted, a.unit, a.observed, how,
        a.sessions, a.sessions == 1 and "" or "s", a.hours, a.sure and "" or ", still a small sample")
end
