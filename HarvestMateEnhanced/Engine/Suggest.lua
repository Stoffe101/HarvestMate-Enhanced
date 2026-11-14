-- HarvestMate Enhanced: Engine/Suggest.lua
-- Context-sensitive suggestions, with limits so they never spam:
--   nearCap       a profession is close to its rank cap (with the trainer)
--   newTier       the farm you follow has gone mostly grey
--   bagsFull      free bag space is about to run out
--   goalDone      a goal is reached
--   stalePrices   price data used for profit is over a week old
--   underperform  your measured rate here is well below the forecast
--   betterArea    you measured clearly better results elsewhere
-- Each kind can be switched off (Settings, Suggestions). The same suggestion
-- (kind + key) is shown once per 30 minutes at most; at most one chat line a
-- minute; the newest 20 are listed on the Dashboard.
-- Copyright (C) 2026 HarvestMate Enhanced contributors. GPL-3.0-or-later.

local _, ns = ...
local HME = ns.HME
local U = HME.U

local S = {}
HME.Suggest = S

S.KINDS = {
    { key = "nearCap", label = "Near the rank cap" },
    { key = "newTier", label = "Farm has gone grey" },
    { key = "bagsFull", label = "Bags nearly full" },
    { key = "goalDone", label = "Goal reached" },
    { key = "stalePrices", label = "Old prices" },
    { key = "underperform", label = "Farm below forecast" },
    { key = "betterArea", label = "Better area measured" },
    { key = "goalNear", label = "Goal nearly reached" },
    { key = "liveBelow", label = "Below prediction while farming" },
}
S.REPEAT = 1800
S.CHAT_GAP = 60

local last = {}
local lastChat = -1e9
S.list = {}

local function Enabled(kind)
    local s = HME.settings and HME.settings.suggest
    return not (type(s) == "table" and s[kind] == false)
end
S.Enabled = Enabled

-- Adds a suggestion; returns true if it was shown.
function S.Add(kind, key, text, action)
    if not Enabled(kind) then return false end
    local id = kind .. ":" .. tostring(key)
    local now = HME.Now()
    if last[id] and now - last[id] < S.REPEAT then return false end
    last[id] = now
    U.Push(S.list, { kind = kind, key = key, text = text, action = action, t = now }, 20)
    if HME.settings.notifications ~= false and now - lastChat >= S.CHAT_GAP then
        lastChat = now
        HME.Print(text)
    end
    HME.Signal("SUGGESTIONS_CHANGED")
    return true
end

-- Carries out a suggestion's action (only ever when you click it).
function S.Run(s)
    local a = s and s.action
    if not a then return false end
    if a.kind == "service" and HME.FGPS then return HME.FGPS.GoToService(a.what, a.profession) end
    if a.kind == "finder" then
        HME.OpenWindow("finder")
        if HME.Pages.finderSet and a.prof then HME.Pages.finderSet(a.prof, a.goal) end
        return true
    end
    return false
end

-- The newest suggestion that offers something to do.
function S.Actionable()
    for i = #S.list, 1, -1 do
        if S.list[i].action then return S.list[i] end
    end
end

function S.Dismiss(i)
    table.remove(S.list, i)
    HME.Signal("SUGGESTIONS_CHANGED")
end

-- Near the cap: within 5 points, with whether training is possible.
local function CheckCaps()
    for prof, s in pairs(HME.Player.Professions()) do
        if s.max < 300 and s.rank >= s.max - 5 then
            local state, nextRank = HME.Player.TrainingState(prof)
            local text
            if state == "level" then
                text = ("%s is near its cap (%d/%d). The next rank needs level %d."):format(prof, s.rank, s.max, nextRank.level)
            elseif nextRank then
                local t = ns.Trainers and ns.Trainers.Closest and ns.Trainers:Closest({ prof = prof, faction = HME.Player.Faction() })
                local where = ""
                local te = t and (t.entry or t)
                if type(te) == "table" and te.name then where = (" Nearest trainer: %s, %s."):format(te.name, te.zone or "?") end
                text = ("%s is near its cap (%d/%d): train %s.%s"):format(prof, s.rank, s.max, nextRank.name, where)
            end
            if text then S.Add("nearCap", prof .. s.max, text, { kind = "trainers", prof = prof }) end
        end
    end
end

local function CheckBags()
    local free, total = HME.Inventory.FreeSlots()
    if not free or not HME.Session.Current() then return end
    if free <= 2 and total and total > 0 then
        local where = HME.FGPS and HME.FGPS.Available() and " Do it: the nearest vendor through Forever-GPS (you press Go; "
            .. "HME's loop waits and comes back after)." or ""
        S.Add("bagsFull", "bags", ("Bags nearly full (%d free).%s"):format(free, where),
            HME.FGPS and HME.FGPS.Available() and { kind = "service", what = "vendor", label = "Nearest vendor" } or nil)
    end
end

local function CheckFarm()
    local g = HME.Guidance.Active()
    if not (g and g.phase == "farm" and g.key) then return end
    local pred = g.planned and g.planned.predicted
    local metric, model
    if pred then
        if pred.beasts then metric, model = "beasts", pred.beasts
        elseif pred.nodes then metric, model = "nodes", pred.nodes end
    end
    if metric then
        local ratio, sure = HME.Learning.Verdict(g.key, metric, model)
        if ratio and sure and ratio < 0.6 then
            S.Add("underperform", g.key, ("This farm gives about %d%% of its forecast for you. The Farm Finder now ranks it by what you measured."):format(ratio * 100),
                { kind = "finder", prof = g.prof })
        end
    end
    -- Somewhere else measured clearly better for the same profession.
    local here = HME.db.stats[g.key]
    local hereGph = here and here.hours and here.hours > 0.5 and (here.value or 0) / here.hours
    if hereGph then
        for key, st in pairs(HME.db.stats) do
            if key ~= g.key and key:match("^" .. tostring(g.prof) .. "@") and (st.hours or 0) >= 1.5 and (st.sessions or 0) >= 2 then
                local gph = (st.value or 0) / st.hours
                if gph > hereGph * 1.3 then
                    S.Add("betterArea", key, ("You measured about %s an hour at another %s farm, %d%% more than here."):format(
                        U.Money(gph, true), tostring(g.prof), (gph / hereGph - 1) * 100))
                    break
                end
            end
        end
    end
end

-- While farming: a material goal nearly done, or a rate clearly below the
-- prediction once there is enough to judge (10 minutes and 8 gathers).
function S.CheckLive()
    local live = HME.Session.Live()
    if not live then return end
    local v = live.verdict
    if v and v.enough and v.ratio and v.ratio < 0.6 then
        local g = HME.Guidance.Active()
        S.Add("liveBelow", g and g.key or "here", ("You are getting about %d%% of the predicted %s here. Low-sample numbers can "
            .. "swing; if it stays like this, another farm may suit you better."):format(v.ratio * 100, v.metric),
            { kind = "finder", prof = g and g.prof })
    end
    for id, need in pairs(HME.Goals.Needed()) do
        local g = need.goal
        if g.type == "item" and g.target and need.missing > 0 and need.missing <= math.max(3, g.target * 0.15) then
            local rate
            for _, it in ipairs(live.items) do if it.id == id then rate = it.perHour end end
            local mins = rate and rate > 0 and need.missing / rate * 60 or nil
            S.Add("goalNear", g.id, ("%s: %d to go%s. A shorter loop or a last lap will do."):format(g.name or "Goal",
                need.missing, mins and (" (about %d min at your pace)"):format(mins + 0.5) or ""))
        end
    end
end
HME.Listen("SESSION_CHANGED", function() HME.Soon("suggest-live", 20, S.CheckLive) end)

HME.Listen("SKILL_UP", function(prof)
    CheckCaps()
    local st = HME.Guide.Status(prof)
    if st.greyFarm then
        S.Add("newTier", prof .. math.floor((st.skill or 0) / 25), "Your current route is becoming inefficient: most of it is grey now. "
            .. "A higher-level farm is available in the Farm Finder.", { kind = "finder", prof = prof, goal = "level" })
    end
end)
HME.On("BAG_UPDATE_DELAYED", function() HME.Soon("suggest-bags", 2, CheckBags) end)
HME.Listen("SESSION_CHANGED", function() HME.Soon("suggest-farm", 30, CheckFarm) end)

-- Price age, checked when a profit search finishes.
function S.CheckPrices(results)
    for _, r in ipairs(results or {}) do
        for id in pairs(r.metrics and r.metrics.items or {}) do
            local p = HME.Prices.Get(id)
            if p and p.source and p.age and p.age > 7 * 86400 then
                S.Add("stalePrices", p.source, ("Your %s prices are %s: profit rankings may be off. Visit the auction house to refresh them."):format(
                    p.source, HME.Prices.AgeText(p.age)))
                return
            end
        end
    end
end
