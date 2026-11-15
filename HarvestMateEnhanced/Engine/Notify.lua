-- HarvestMate Enhanced: Engine/Notify.lua (0.6.0)
-- The notification center: one list of what HME wanted to tell you, by
-- category, with what you can do about it, kept so nothing scrolls away in
-- chat.
--
--   categories  goal, training, bags, farm, route, session, data
--   each one    "chat" (a line in chat too), "quiet" (the list only) or "off"
--               (Settings, Notifications); defaults keep chat for what needs
--               you now (goals, training, bags) and quiet for the rest
--   limits      the same notice (category + key) once per 30 minutes; at most
--               one chat line a minute (shared with Engine/Suggest.lua, whose
--               suggestions all land here too); the newest 40 kept per
--               character. A notice's button works until /reload (actions can
--               hold a whole farm and are not saved); the text stays.
-- Copyright (C) 2026 HarvestMate Enhanced contributors. GPL-3.0-or-later.

local _, ns = ...
local HME = ns.HME
local U = HME.U

local N = {}
HME.Notify = N

N.CATS = {
    { key = "goal", label = "Goals", default = "chat" },
    { key = "training", label = "Training and milestones", default = "chat" },
    { key = "bags", label = "Bags", default = "chat" },
    { key = "farm", label = "Farming (better farm, below forecast)", default = "quiet" },
    { key = "route", label = "Routes and laps", default = "quiet" },
    { key = "session", label = "Session reviews", default = "quiet" },
    { key = "data", label = "Data and prices", default = "quiet" },
}
N.CAT = {}
for _, c in ipairs(N.CATS) do N.CAT[c.key] = c end
N.REPEAT = 1800
N.KEEP = 40

-- Engine/Suggest.lua's kinds, by category.
N.FROM_SUGGEST = { nearCap = "training", newTier = "farm", bagsFull = "bags", goalDone = "goal", goalNear = "goal",
    stalePrices = "data", underperform = "farm", liveBelow = "farm", betterArea = "farm" }

local actions = {}       -- [notice id] = action (not saved)
local lastAt = {}
local seq = 0

local function List()
    if not HME.char then return {} end
    if type(HME.char.notices) ~= "table" then HME.char.notices = {} end
    return HME.char.notices
end
N.List = List

function N.Pref(cat)
    local p = HME.settings and type(HME.settings.notify) == "table" and HME.settings.notify[cat]
    if p == "chat" or p == "quiet" or p == "off" then return p end
    return (N.CAT[cat] and N.CAT[cat].default) or "quiet"
end
function N.SetPref(cat, v)
    if type(HME.settings.notify) ~= "table" then HME.settings.notify = {} end
    HME.settings.notify[cat] = v
end

-- Adds a notice. opts = { noChat (already said in chat), now (force past the repeat limit) }.
-- Returns the notice, or nil when it was held back.
function N.Push(cat, key, text, action, opts)
    opts = opts or {}
    if not N.CAT[cat] then cat = "data" end
    local pref = N.Pref(cat)
    if pref == "off" then return nil end
    local id = cat .. ":" .. tostring(key)
    local now = HME.Now()
    if not opts.now and lastAt[id] and now - lastAt[id] < N.REPEAT then return nil end
    lastAt[id] = now
    seq = seq + 1
    local n = { id = ("%d.%d"):format(math.floor((time and time()) or 0), seq), cat = cat, key = tostring(key), text = text,
        t = (time and time()) or 0, read = false, label = action and action.label or nil }
    U.Push(List(), n, N.KEEP)
    if action then actions[n.id] = action end
    if pref == "chat" and not opts.noChat and HME.settings.notifications ~= false and HME.Suggest then
        HME.Suggest.Chat(text)
    end
    HME.Signal("NOTICES_CHANGED")
    return n
end

function N.Action(n) return n and actions[n.id] end

function N.Unread()
    local k = 0
    for _, n in ipairs(List()) do if not n.read then k = k + 1 end end
    return k
end

function N.MarkRead()
    for _, n in ipairs(List()) do n.read = true end
    HME.Signal("NOTICES_CHANGED")
end

function N.Clear()
    local l = List()
    for i = #l, 1, -1 do l[i] = nil end
    actions = {}
    HME.Signal("NOTICES_CHANGED")
end

-- Runs a notice's action (a click). The kinds Suggest and the Copilot know.
function N.Run(n)
    local a = N.Action(n)
    if not a then return false end
    n.read = true
    if a.kind == "review" then
        if HME.Review then HME.Review.Show(a.summary) end
        return true
    end
    if HME.Copilot and HME.Copilot.Run(a) then return true end
    if HME.Suggest then return HME.Suggest.Run({ action = a }) end
    return false
end

---------------------------------------------------------------------------
-- Sources
---------------------------------------------------------------------------
-- The Copilot: a new card that needs you now (switch, train, bags) once.
local seenCards = {}
HME.Listen("COPILOT_CHANGED", function()
    for _, c in ipairs((HME.Copilot and HME.Copilot.cards) or {}) do
        if (c.priority or 0) >= 80 and not seenCards[c.id] then
            seenCards[c.id] = true
            local cat = (c.type == "train" and "training") or (c.type == "bags" and "bags") or "farm"
            N.Push(cat, c.id, ("%s: %s"):format(c.title or "Copilot", c.objective or ""), c.action)
        end
    end
end)

-- A route lap faster than every one before it.
HME.Listen("ROUTE_LAP", function(route)
    local log = route and route.lapLog
    local last = log and log[#log]
    if not (last and #log >= 3) then return end
    for i = 1, #log - 1 do if (log[i].secs or 1e9) <= last.secs then return end end
    N.Push("route", "best:" .. tostring(route.id), ("Best lap on %s: %s."):format(route.name, U.Duration(last.secs)))
end)
