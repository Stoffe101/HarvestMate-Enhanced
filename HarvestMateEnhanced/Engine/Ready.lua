-- HarvestMate Enhanced: Engine/Ready.lua
-- "Ready to go?" (0.7.0): what could cut a farming trip short, checked before
-- you leave. Each check says what it read; none of them changes anything.
--
--   bags        free slots against what this farm fills them with, for the
--               trip's farming time (skinning: the farm's materials an hour,
--               stack sizes and the partial stacks you hold; gathering: free
--               slots only, as a node's yield is not known per hour)
--   repair      the lowest durability among the items you wear (the game's
--               figures); a broken item gives no stats
--   cap         skill-ups left before your rank cap, against the farm's rate
--   risk        the farm's risk (Engine/Risk.lua), including your deaths and
--               the enemy players you met there (Engine/Danger.lua)
--   travel      whether the way there is known
--
-- States: "ok", "warn" (worth a look), "stop" (the trip would be cut short).
-- Copyright (C) 2026 HarvestMate Enhanced contributors. GPL-3.0-or-later.

local _, ns = ...
local HME = ns.HME

local R = {}
HME.Ready = R

R.REPAIR_WARN = 0.25
R.FEW_SLOTS = 2

-- The lowest durability share among worn items, and which slot, or nil.
function R.Durability()
    local get = _G.GetInventoryItemDurability
    if type(get) ~= "function" then return nil end
    local low, at
    for slot = 1, 19 do
        local ok, cur, max = pcall(get, slot)
        cur, max = ok and HME.Num(cur), ok and HME.Num(max)
        if cur and max and max > 0 then
            local share = cur / max
            if not low or share < low then low, at = share, slot end
        end
    end
    return low, at
end

-- Minutes until `free` slots are used by `rows` ({ perHour, stack, room }),
-- or nil when they last over 10 hours.
function R.MinutesToFull(rows, free)
    local function Used(m)
        local used = 0
        for _, r in ipairs(rows) do
            local n = r.perHour / 60 * m - r.room
            if n > 0 then used = used + math.ceil(n / r.stack) end
        end
        return used
    end
    if #rows == 0 or Used(600) <= free then return nil end
    local lo, hi = 0, 600
    while hi - lo > 1 do
        local mid = math.floor((lo + hi) / 2)
        if Used(mid) > free then hi = mid else lo = mid end
    end
    return hi
end

-- What a farm fills bags with an hour: { { id, perHour, stack, room } }.
function R.BagRows(r)
    local m = r and r.metrics or {}
    local rows = {}
    if r and r.prof == "Skinning" and m.items and m.beastsPerHour then
        for id, per in pairs(m.items) do
            local perHour = per * m.beastsPerHour
            if perHour > 0 then
                local stack = HME.Bags.StackSize(id)
                local held = HME.Inventory.Held(id) or 0
                rows[#rows + 1] = { id = id, perHour = perHour, stack = stack, room = held % stack == 0 and 0 or stack - held % stack }
            end
        end
    end
    return rows
end

-- The checks for a Farm Finder result and a trip of `budget` seconds.
-- { checks = { { key, state, title, text } }, worst, summary }
function R.Check(r, budget, profile)
    profile = profile or HME.Player.Profile()
    budget = budget or 3600
    local checks = {}
    local function add(key, state, title, text) checks[#checks + 1] = { key = key, state = state, title = title, text = text } end
    local travel = r and r.travel
    local farmMin = math.max(0, budget - (travel or (HME.Copilot and HME.Copilot.UNKNOWN_TRAVEL) or 1200)) / 60

    -- Bags
    local free = HME.Inventory.FreeSlots()
    if free then
        local minutes = R.MinutesToFull(R.BagRows(r), free)
        if free <= R.FEW_SLOTS then
            add("bags", "stop", ("%d free bag slot%s"):format(free, free == 1 and "" or "s"),
                "Make room first: this farm's materials need slots of their own.")
        elseif minutes and minutes < farmMin then
            add("bags", "warn", ("Bags full after about %d minutes"):format(minutes),
                ("%d free slots; this farm's materials fill them in about %d of your %d farming minutes (stack sizes and your "
                    .. "partial stacks counted; other loot fills them sooner)."):format(free, minutes, math.floor(farmMin + 0.5)))
        else
            add("bags", "ok", ("%d free bag slots"):format(free), minutes and ("Full in about %d minutes at this farm."):format(minutes)
                or "Enough for this trip.")
        end
    end
    -- Repair
    local low = R.Durability()
    if low then
        if low <= 0 then
            add("repair", "stop", "Something you wear is broken", "A broken item gives no stats until it is repaired.")
        elseif low < R.REPAIR_WARN then
            add("repair", "warn", ("Repair soon: lowest item at %d%%"):format(math.floor(low * 100 + 0.5)),
                "Deaths and fights wear it further; a repair vendor is on Forever-GPS's services list.")
        else
            add("repair", "ok", ("Gear at %d%% or better"):format(math.floor(low * 100)), "")
        end
    end
    -- Rank cap
    local prof = r and r.prof
    local cap = prof and HME.Copilot and HME.Copilot.CapLeft(profile, prof)
    if cap ~= nil then
        local s = profile.skills[prof]
        local rate = r.metrics and r.metrics.skillPerHour
        if cap == 0 and s and s.max < 300 then
            add("cap", "stop", ("At your rank cap (%d)"):format(s.max), "No skill-ups until you train the next rank.")
        elseif rate and rate > 0 and cap / rate * 60 < farmMin then
            add("cap", "warn", ("Rank cap after about %d minutes"):format(math.floor(cap / rate * 60 + 0.5)),
                ("%d skill-ups left before %d; the rest of the trip gives materials only."):format(cap, s and s.max or 0))
        else
            add("cap", "ok", "Room to skill up", cap > 0 and ("%d skill-ups before your rank cap."):format(cap) or "")
        end
    end
    -- Risk
    if r and r.risk then
        local state = r.risk.score >= 0.6 and "warn" or "ok"
        add("risk", state, r.risk.label or "Risk", table.concat(r.risk.reasons or {}, "; "))
    end
    -- Travel
    if r and not travel then
        add("travel", "warn", "The way there is not known", "Assumed 20 minutes; Forever-GPS can work it out when it is installed.")
    end
    local order = { ok = 0, warn = 1, stop = 2 }
    local worst, n = "ok", 0
    for _, c in ipairs(checks) do
        if order[c.state] > order[worst] then worst = c.state end
        if c.state ~= "ok" then n = n + 1 end
    end
    local summary = worst == "ok" and "Ready to go" or (n == 1 and "One thing to check first" or (n .. " things to check first"))
    return { checks = checks, worst = worst, summary = summary }
end

-- Chat lines for /hme ready.
function R.Lines(res)
    local mark = { ok = "|cff8fcc5cok|r", warn = "|cfff5a345check|r", stop = "|cffed6963first|r" }
    local lines = { res.summary .. ":" }
    for _, c in ipairs(res.checks) do
        lines[#lines + 1] = ("  %s  %s%s"):format(mark[c.state], c.title, c.text ~= "" and (": " .. c.text) or "")
    end
    return lines
end
