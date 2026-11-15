-- HarvestMate Enhanced: Engine/Bags.lua (0.6.0)
-- Bag pressure while farming, and your characters' materials.
--
-- Forecast: when will the bags be full?
--   measured   free slots over this session's farming time (BAG_UPDATE_DELAYED
--              samples): slots used an hour, whatever filled them (corpse
--              loot, cloth and quest items count too). Used after 10 farming
--              minutes once at least one slot was used.
--   estimated  before that: this session's gathered materials an hour, each
--              filling its partial stack first, then a new slot per stack
--              size (C_Item.GetItemInfo's stack count; 20 when unknown).
--   The answer is a range (x0.7 to x1.4 of the middle), never a countdown.
--
-- Characters: each character's gathering materials in its bags (refreshed
-- when the bags change, at most every 10 seconds) and bank (when the bank is
-- open), kept per character in the account data with when they were seen.
-- Another character's numbers are what was there when you last played it,
-- and the page says how old they are. Only materials HME knows (herbs, ore,
-- hides, fish) are kept, nothing else of the bags. Stays on this PC.
-- Copyright (C) 2026 HarvestMate Enhanced contributors. GPL-3.0-or-later.

local _, ns = ...
local HME = ns.HME
local U = HME.U

local B = {}
HME.Bags = B

B.MEASURE_SECS = 600
B.DEFAULT_STACK = 20
B.MAX_CHARS = 30

local function GetItemInfo(id)
    local fn = (C_Item and C_Item.GetItemInfo) or _G.GetItemInfo
    if not fn then return nil end
    local ok, a, b, c, d, e, f, g, stack = pcall(fn, id)
    if ok then return stack end
end

function B.StackSize(itemID)
    local s = GetItemInfo(itemID)
    return HME.Num(s) and s > 0 and s or B.DEFAULT_STACK
end

-- Free-slot samples for the session going on: { { f = farmSecs, free } }.
local samples = {}
local function Sample()
    local live = HME.Session.Current()
    if not live then samples = {} return end
    local free = HME.Inventory.FreeSlots()
    if not free then return end
    local f = live.farm or 0
    local last = samples[#samples]
    if last and last.free == free then return end
    U.Push(samples, { f = f, free = free }, 200)
end
HME.On("BAG_UPDATE_DELAYED", function() HME.Soon("bags-sample", 1, Sample) end)
HME.Listen("SESSION_CHANGED", function()
    if not HME.Session.Current() then samples = {} elseif #samples == 0 then Sample() end
end)
B.samples = function() return samples end
function B.Reset() samples = {} end

-- Slots an hour from gathered materials and their stacks.
local function ItemSlotsPerHour(live)
    local perHour = 0
    for _, it in ipairs(live.items or {}) do
        if (it.perHour or 0) > 0 then perHour = perHour + it.perHour / B.StackSize(it.id) end
    end
    return perHour
end

-- Minutes until `free` slots are used, given material rates and their partial stacks.
local function ItemMinutes(live, free)
    local rows = {}
    for _, it in ipairs(live.items or {}) do
        if (it.perHour or 0) > 0 then
            local stack = B.StackSize(it.id)
            local held = HME.Inventory.Held(it.id)
            local room = held % stack == 0 and 0 or stack - held % stack
            rows[#rows + 1] = { rate = it.perHour / 60, stack = stack, room = room }
        end
    end
    if #rows == 0 then return nil end
    for m = 1, 600 do
        local used = 0
        for _, r in ipairs(rows) do
            local n = r.rate * m - r.room
            if n > 0 then used = used + math.ceil(n / r.stack) end
        end
        if used > free then return m end
    end
    return nil
end

-- { free, total, minutes, low, high, basis, text, conf } or nil.
function B.Forecast(live)
    live = live or HME.Session.Live()
    if not live then return nil end
    local free, total = HME.Inventory.FreeSlots()
    if not free then return nil end
    local out = { free = free, total = total }
    local first, last = samples[1], samples[#samples]
    local used = first and last and first.free - last.free or 0
    local span = first and last and (last.f - first.f) or 0
    local minutes
    if live.farmSecs >= B.MEASURE_SECS and used > 0 and span >= 300 then
        local perHour = used / (span / 3600)
        minutes = free / perHour * 60
        out.basis, out.perHour, out.conf = "measured", perHour, 0.65
        out.text = ("%d free slots; this session used about %.0f an hour."):format(free, perHour)
    else
        minutes = ItemMinutes(live, free)
        if minutes then
            out.basis, out.perHour, out.conf = "estimated", ItemSlotsPerHour(live), 0.45
            out.text = ("%d free slots; from what you gathered so far (other loot may fill them sooner)."):format(free)
        end
    end
    if not minutes then
        out.text = ("%d free slots; nothing yet says how fast they fill."):format(free)
        return out
    end
    out.minutes = minutes
    out.low, out.high = minutes * 0.7, minutes * 1.4
    out.text = out.text .. (" Full in about %d minutes (%d to %d)."):format(math.floor(minutes + 0.5),
        math.floor(out.low + 0.5), math.floor(out.high + 0.5))
    return out
end

---------------------------------------------------------------------------
-- Your characters' materials
---------------------------------------------------------------------------
local function Me()
    local name = UnitName and HME.Str((UnitName("player")))
    local realm = GetRealmName and HME.Str((GetRealmName()))
    if not name then return nil end
    return realm and (name .. "-" .. realm) or name
end
B.Me = Me

local function Root()
    if not HME.db then return nil end
    if type(HME.db.chars) ~= "table" then HME.db.chars = {} end
    return HME.db.chars
end

local function Known(id) return ns.itemIndex and ns.itemIndex[id] ~= nil end

local function ScanBags(first, last)
    local info = C_Container and C_Container.GetContainerItemInfo
    local slots = C_Container and C_Container.GetContainerNumSlots
    if not (info and slots) then return nil end
    local out = {}
    for bag = first, last do
        local ok, n = pcall(slots, bag)
        for slot = 1, (ok and HME.Num(n)) or 0 do
            local ok2, it = pcall(info, bag, slot)
            local id = ok2 and type(it) == "table" and HME.Num(it.itemID)
            if id and Known(id) then out[id] = (out[id] or 0) + (HME.Num(it.stackCount) or 1) end
        end
    end
    return out
end

local function Entry()
    local root, me = Root(), Me()
    if not (root and me) then return nil end
    local e = root[me]
    if type(e) ~= "table" then
        e = {}
        root[me] = e
    end
    e.level = HME.Player.Level()
    e.faction = HME.Player.Faction()
    e.class = HME.Player.Class()
    e.t = (time and time()) or 0
    HME.DBM.TrimMap(root, B.MAX_CHARS)
    return e
end

function B.SnapshotBags()
    local items = ScanBags(0, 4)
    local e = items and Entry()
    if not e then return end
    e.bags, e.bagsAt = items, (time and time()) or 0
end
HME.On("BAG_UPDATE_DELAYED", function() HME.Soon("bags-snapshot", 10, B.SnapshotBags) end)
HME.On("PLAYER_ENTERING_WORLD", function() HME.Soon("bags-snapshot", 5, B.SnapshotBags) end)

function B.SnapshotBank()
    local nBags = _G.NUM_BAG_SLOTS or 4
    local nBank = _G.NUM_BANKBAGSLOTS or 7
    local items = ScanBags(-1, -1)
    if not items then return end
    local more = ScanBags(nBags + 1, nBags + nBank) or {}
    for id, n in pairs(more) do items[id] = (items[id] or 0) + n end
    local e = Entry()
    if e then e.bank, e.bankAt = items, (time and time()) or 0 end
end
HME.On("BANKFRAME_OPENED", function() HME.After(0.6, B.SnapshotBank) end)

-- Every character's count of an item: { { name, bags, bank, bagsAt, bankAt, me } },
-- most first. Only characters that have any.
function B.Material(itemID)
    local out = {}
    local me = Me()
    for name, e in pairs(Root() or {}) do
        if type(e) == "table" then
            local bags = type(e.bags) == "table" and e.bags[itemID] or 0
            local bank = type(e.bank) == "table" and e.bank[itemID] or 0
            if bags + bank > 0 then
                out[#out + 1] = { name = name, bags = bags, bank = bank, bagsAt = e.bagsAt, bankAt = e.bankAt, me = name == me,
                    total = bags + bank }
            end
        end
    end
    table.sort(out, function(a, b) return a.total > b.total end)
    return out
end

-- "12 minutes", "5 hours", "3 days": how long ago something was seen.
function B.Age(secs)
    secs = math.max(0, secs or 0)
    if secs < 3600 then return ("%d min"):format(math.max(1, math.floor(secs / 60 + 0.5))) end
    if secs < 2 * 86400 then return ("%d h"):format(math.floor(secs / 3600 + 0.5)) end
    return ("%d days"):format(math.floor(secs / 86400 + 0.5))
end

-- "Alt-Realm: 12 (bank, 3 days ago)" lines for a tooltip or the Materials page.
function B.MaterialLines(itemID)
    local lines = {}
    local now = (time and time()) or 0
    for _, c in ipairs(B.Material(itemID)) do
        local parts = {}
        if c.bags > 0 then parts[#parts + 1] = ("%d in bags"):format(c.bags) end
        if c.bank > 0 then parts[#parts + 1] = ("%d in the bank"):format(c.bank) end
        local at = math.max(c.bagsAt or 0, c.bankAt or 0)
        local age = c.me and "now" or (at > 0 and (B.Age(now - at) .. " ago") or "when last seen")
        lines[#lines + 1] = ("%s: %s (%s)"):format(c.me and "This character" or c.name:gsub("%-.*", ""), table.concat(parts, ", "), age)
    end
    return lines
end

function B.ForgetCharacter(name)
    local root = Root()
    if root then root[name] = nil end
end
