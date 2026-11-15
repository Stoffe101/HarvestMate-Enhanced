-- Gatherpedia: Session.lua
-- "This Session" numbers: what you gathered since login (or the last reset),
-- with a pausable timer so paused / AFK time doesn't count toward rates.
-- Pure logic; SessionUI.lua draws it. Settings live in GatherpediaDB.session.

local ADDON_NAME, ns = ...

local Session = {}
ns.Session = Session

Session.AUTO_PAUSE_AFTER = 300      -- seconds with no gather before the timer pauses itself

Session.DEFAULTS = {
    show = "perhour",               -- perhour | skillups | skillrate | tocap | time | multi
    multi = { gathered = true, perhour = true, nodes = true, skillups = false, time = true, top = false, value = false },
    prof = "All",                   -- All | Herbalism | Mining | Skinning | Fishing
    sep = ",",                      -- thousands separator: "," or "."
    icons = true, labels = true, compact = false,
    floating = false, lock = false, hidden = false,
    autoPause = true,
    float = {},                     -- point, relativePoint, x, y
}

local function Now() return GetTime() end

local function NewState(now)
    return {
        start = now, items = 0, gathers = 0,
        byProf = {}, gathersByProf = {},     -- [prof] = n
        byZone = {},                          -- [zone] = { items, gathers, byProf = { [prof] = items }, gathersByProf = {} }
        byItem = {},                          -- [itemID] = { n, name, icon, prof }
        skillStart = {}, skillNow = {}, skillMax = {},
        paused = false, pausedAt = nil, pausedTotal = 0, autoPaused = nil,
        lastActive = now, last = nil,
    }
end

ns.session = NewState(GetTime and GetTime() or 0)

function Session:Opts() return (ns.db and ns.db.session) or self.DEFAULTS end

---------------------------------------------------------------------------
-- Timer
---------------------------------------------------------------------------

-- Seconds that count toward rates: wall time minus paused time.
function Session:Elapsed(now)
    local s = ns.session
    now = now or Now()
    local e = (now - s.start) - s.pausedTotal
    if s.paused and s.pausedAt then e = e - (now - s.pausedAt) end
    return math.max(e, 0)
end

-- reason: nil (you), "idle" or "afk". at: when the pause really began.
function Session:Pause(reason, at)
    local s = ns.session
    if s.paused then return end
    s.paused, s.pausedAt, s.autoPaused = true, at or Now(), reason
end

function Session:Resume(now)
    local s = ns.session
    if not s.paused then return end
    now = now or Now()
    s.pausedTotal = s.pausedTotal + math.max(now - (s.pausedAt or now), 0)
    s.paused, s.pausedAt, s.autoPaused = false, nil, nil
    s.lastActive = now
end

function Session:TogglePause()
    if ns.session.paused then self:Resume() else self:Pause() end
end

-- Called every few seconds: auto-pause after AUTO_PAUSE_AFTER with no gather.
function Session:Tick(now)
    local s = ns.session
    now = now or Now()
    if s.paused or not self:Opts().autoPause then return end
    if now - s.lastActive >= self.AUTO_PAUSE_AFTER then
        self:Pause("idle", s.lastActive + self.AUTO_PAUSE_AFTER)   -- the idle stretch doesn't count
    end
end

function Session:SetAFK(isAFK, now)
    local s = ns.session
    if isAFK then
        if not s.paused then self:Pause("afk", now) end
    elseif s.autoPaused == "afk" then
        self:Resume(now)
    end
end

---------------------------------------------------------------------------
-- Session gathers
---------------------------------------------------------------------------

local function ZoneRec(s, zone)
    zone = zone or "Unknown"
    local z = s.byZone[zone]
    if not z then
        z = { items = 0, gathers = 0, byProf = {}, gathersByProf = {} }
        s.byZone[zone] = z
    end
    return z
end

function Session:OnGather(prof, zone, now)
    local s = ns.session
    now = now or Now()
    if s.paused and s.autoPaused then self:Resume(now) end    -- gathering again ends an auto-pause
    s.lastActive = now
    s.gathers = s.gathers + 1
    s.gathersByProf[prof] = (s.gathersByProf[prof] or 0) + 1
    local z = ZoneRec(s, zone)
    z.gathers = z.gathers + 1
    z.gathersByProf[prof] = (z.gathersByProf[prof] or 0) + 1
end

function Session:OnItem(prof, itemID, quantity, zone, name, icon)
    local s = ns.session
    quantity = quantity or 1
    s.items = s.items + quantity
    s.byProf[prof] = (s.byProf[prof] or 0) + quantity
    local z = ZoneRec(s, zone)
    z.items = z.items + quantity
    z.byProf[prof] = (z.byProf[prof] or 0) + quantity
    local it = s.byItem[itemID]
    if not it then it = { n = 0, name = name, icon = icon, prof = prof, byZone = {} }; s.byItem[itemID] = it end
    it.n = it.n + quantity
    local zk = zone or "Unknown"
    it.byZone[zk] = (it.byZone[zk] or 0) + quantity
    s.last = { id = itemID, name = name, icon = icon, quantity = quantity, zone = zone }
end

-- learned: { [prof] = { rank, max } } from the skill scan.
function Session:OnSkills(learned)
    local s = ns.session
    for prof, p in pairs(learned or {}) do
        if s.skillStart[prof] == nil then s.skillStart[prof] = p.rank end
        if p.rank < s.skillStart[prof] then s.skillStart[prof] = p.rank end
        s.skillNow[prof], s.skillMax[prof] = p.rank, p.max
    end
end

---------------------------------------------------------------------------
-- Resets
---------------------------------------------------------------------------

function Session:Reset(now)
    now = now or Now()
    local old = ns.session
    local s = NewState(now)
    for prof, r in pairs(old.skillNow) do s.skillStart[prof], s.skillNow[prof], s.skillMax[prof] = r, r, old.skillMax[prof] end
    ns.session = s
end

-- Take one zone's numbers out of the session (time is kept).
function Session:ResetZone(zone)
    local s = ns.session
    local z = s.byZone[zone]
    if not z then return false end
    s.items = math.max(s.items - z.items, 0)
    s.gathers = math.max(s.gathers - z.gathers, 0)
    for prof, n in pairs(z.byProf) do s.byProf[prof] = math.max((s.byProf[prof] or 0) - n, 0) end
    for prof, n in pairs(z.gathersByProf) do s.gathersByProf[prof] = math.max((s.gathersByProf[prof] or 0) - n, 0) end
    s.byZone[zone] = nil
    if s.last and s.last.zone == zone then s.last = nil end
    for id, it in pairs(s.byItem) do
        local here = it.byZone[zone]
        if here then
            it.n, it.byZone[zone] = it.n - here, nil
            if it.n <= 0 then s.byItem[id] = nil end
        end
    end
    return true
end

---------------------------------------------------------------------------
-- Numbers
---------------------------------------------------------------------------

function Session:Count(prof)
    local s = ns.session
    if not prof or prof == "All" then return s.items, s.gathers end
    return s.byProf[prof] or 0, s.gathersByProf[prof] or 0
end

function Session:SkillUps(prof)
    local s = ns.session
    local total = 0
    for p, r in pairs(s.skillNow) do
        if not prof or prof == "All" or prof == p then total = total + math.max(r - (s.skillStart[p] or r), 0) end
    end
    return total
end

-- Short labels used when several professions leveled in one session.
local SKILL_SHORT = { Herbalism = "Herb", Mining = "Mine", Skinning = "Skin", Fishing = "Fish" }

-- Professions that gained skill this session, in sidebar order.
-- Each row: { prof, short, ups, from, to }.
function Session:SkillUpBreakdown(prof)
    local s = ns.session
    local rows, seen = {}, {}
    local function add(p)
        if prof and prof ~= "All" and prof ~= p then return end
        local nowR, startR = s.skillNow[p], s.skillStart[p]
        if not nowR then return end
        startR = startR or nowR
        local ups = math.max(nowR - startR, 0)
        if ups <= 0 then return end
        rows[#rows + 1] = {
            prof = p,
            short = SKILL_SHORT[p] or p,
            ups = ups,
            from = startR,
            to = nowR,
        }
    end
    for _, p in ipairs(ns.PROFESSIONS or { "Herbalism", "Mining", "Fishing", "Skinning" }) do
        seen[p] = true
        add(p)
    end
    local extra = {}
    for p in pairs(s.skillNow) do
        if not seen[p] then extra[#extra + 1] = p end
    end
    table.sort(extra)
    for _, p in ipairs(extra) do add(p) end
    return rows
end

-- Tile text: one profession -> "Herbalism +2"; several -> total plus
-- "Herb +2  Mine +1". Returns value, detail (detail may be nil).
function Session:SkillUpSummary(prof)
    local rows = self:SkillUpBreakdown(prof)
    local total = self:SkillUps(prof)
    if #rows == 0 then
        return self:FormatNumber(total), nil
    elseif #rows == 1 then
        return rows[1].prof .. "\n+" .. tostring(rows[1].ups), nil
    else
        local parts = {}
        for _, r in ipairs(rows) do
            parts[#parts + 1] = r.short .. " +" .. tostring(r.ups)
        end
        return self:FormatNumber(total), table.concat(parts, "  ")
    end
end

-- Per hour over counted (unpaused) time; nil until a minute has counted.
function Session:PerHour(n, now)
    local e = self:Elapsed(now)
    if e < 60 then return nil end
    return n / e * 3600
end

-- Seconds until the profession reaches its current skill cap at this
-- session's skill-up rate. nil when unknown (no skill-ups yet, or at cap).
function Session:TimeToCap(prof, now)
    local s = ns.session
    if not prof or prof == "All" then
        local best
        for p in pairs(s.skillNow) do
            local t = self:TimeToCap(p, now)
            if t and (not best or t < best) then best = t end
        end
        return best
    end
    local rank, max = s.skillNow[prof], s.skillMax[prof]
    if not rank or not max or rank >= max then return nil end
    local ups = self:SkillUps(prof)
    local rate = ups > 0 and self:PerHour(ups, now)
    if not rate or rate <= 0 then return nil end
    return (max - rank) / rate * 3600
end

function Session:TopItem(prof)
    local best, bestID
    for id, it in pairs(ns.session.byItem) do
        if (not prof or prof == "All" or it.prof == prof) and (not best or it.n > best.n) then best, bestID = it, id end
    end
    return best, bestID
end

-- Vendor value in copper, from the client's item info. nil if the client
-- doesn't give sell prices.
function Session:VendorValue(prof)
    if not GetItemInfo then return nil end
    local total, known = 0, false
    for id, it in pairs(ns.session.byItem) do
        if not prof or prof == "All" or it.prof == prof then
            local price = select(11, GetItemInfo(id))
            if type(price) == "number" then total = total + price * it.n; known = true end
        end
    end
    return known and total or nil
end

function Session:HasVendorPrices()
    if not GetItemInfo then return false end
    return type(select(11, GetItemInfo(2589))) == "number"   -- Linen Cloth: any cached item will do
end

---------------------------------------------------------------------------
-- Formatting
---------------------------------------------------------------------------

function Session:FormatNumber(n, sep)
    n = math.floor((n or 0) + 0.5)
    local str = tostring(math.abs(n))
    sep = sep or self:Opts().sep or ","
    local out = str:reverse():gsub("(%d%d%d)", "%1" .. sep):reverse()
    if out:sub(1, 1) == sep then out = out:sub(2) end
    return (n < 0 and "-" or "") .. out
end

function Session:FormatTime(sec)
    sec = math.floor(sec or 0)
    local h, m = math.floor(sec / 3600), math.floor(sec % 3600 / 60)
    if h > 0 then return ("%dh %02dm"):format(h, m) end
    return ("%dm %02ds"):format(m, sec % 60)
end

function Session:FormatMoney(c)
    local g, s = math.floor(c / 10000), math.floor(c % 10000 / 100)
    if g > 0 then return ("%sg %ds"):format(self:FormatNumber(g), s) end
    return ("%ds %dc"):format(s, c % 100)
end

local ICONS = {
    gathered = "Interface\\Icons\\INV_Misc_Bag_10", perhour = "Interface\\Icons\\INV_Misc_PocketWatch_01",
    nodes = "Interface\\Icons\\INV_Misc_Map_01", skillups = "Interface\\Icons\\INV_Misc_Book_09",
    skillrate = "Interface\\Icons\\INV_Misc_Book_09", tocap = "Interface\\Icons\\Spell_Holy_BorrowedTime",
    time = "Interface\\Icons\\INV_Misc_PocketWatch_02", top = "Interface\\Icons\\INV_Misc_QuestionMark",
    value = "Interface\\Icons\\INV_Misc_Coin_02",
}

-- The lines to draw: { key, label, value, icon }.
function Session:Lines(now)
    local o = self:Opts()
    local prof = o.prof
    local n, nodes = self:Count(prof)
    local fmt = function(x) return self:FormatNumber(x, o.sep) end
    local function line(key)
        if key == "gathered" then return { key, "Gathered", fmt(n) } end
        if key == "perhour" then local r = self:PerHour(n, now); return { key, "Per hour", r and fmt(r) or "-" } end
        if key == "nodes" then return { key, "Nodes", fmt(nodes) } end
        if key == "skillups" then return { key, "Skill-ups", fmt(self:SkillUps(prof)) } end
        if key == "skillrate" then
            local ups = self:SkillUps(prof); local r = ups > 0 and self:PerHour(ups, now)
            return { key, "Skill-ups / hr", r and ("%.1f"):format(r):gsub("%.", o.sep == "." and "," or ".") or "-" }
        end
        if key == "tocap" then local t = self:TimeToCap(prof, now); return { key, "To skill cap", t and self:FormatTime(t) or "-" } end
        if key == "time" then return { key, "Time", self:FormatTime(self:Elapsed(now)) .. (ns.session.paused and " (paused)" or "") } end
        if key == "top" then
            local it = self:TopItem(prof)
            return { key, "Top item", it and ((it.name or "?") .. " x" .. fmt(it.n)) or "-", it and it.icon }
        end
        if key == "value" then local v = self:VendorValue(prof); return { key, "Vendor value", v and self:FormatMoney(v) or "-" } end
    end
    local keys
    if o.show == "multi" then
        keys = {}
        for _, k in ipairs({ "gathered", "perhour", "nodes", "skillups", "time", "top", "value" }) do
            if o.multi[k] and (k ~= "value" or self:HasVendorPrices()) then keys[#keys + 1] = k end
        end
    elseif o.show == "skillups" then keys = { "skillups" }
    elseif o.show == "skillrate" then keys = { "skillrate" }
    elseif o.show == "tocap" then keys = { "tocap" }
    elseif o.show == "time" then keys = { "time" }
    else keys = { "perhour" } end
    local out = {}
    for _, k in ipairs(keys) do
        local l = line(k)
        out[#out + 1] = { key = l[1], label = l[2], value = l[3], icon = l[4] or ICONS[l[1]] }
    end
    return out
end

-- Per-zone breakdown for the hover tooltip: { zone, items, gathers } sorted by items.
function Session:ZoneBreakdown()
    local prof = self:Opts().prof
    local out = {}
    for zone, z in pairs(ns.session.byZone) do
        local items = (prof == "All") and z.items or (z.byProf[prof] or 0)
        local g = (prof == "All") and z.gathers or (z.gathersByProf[prof] or 0)
        if items > 0 or g > 0 then out[#out + 1] = { zone = zone, items = items, gathers = g } end
    end
    table.sort(out, function(a, b) if a.items == b.items then return a.zone < b.zone end return a.items > b.items end)
    return out
end
