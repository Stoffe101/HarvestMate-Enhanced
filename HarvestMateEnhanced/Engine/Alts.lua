-- HarvestMate Enhanced: Engine/Alts.lua
-- Your characters (0.7.0), from what each one last showed HME when you
-- played it: level, faction, class, gathering professions and ranks, and the
-- HME materials in its bags and bank (Engine/Bags.lua). Nothing is read from
-- a character you are not playing; every figure says when it was seen.
--
-- The planner's hints are plain arithmetic on those figures: a profession at
-- its rank cap needs training, or a level first (the classic rank levels:
-- Journeyman 10, Expert 20, Artisan 35).
-- Copyright (C) 2026 HarvestMate Enhanced contributors. GPL-3.0-or-later.

local _, ns = ...
local HME = ns.HME

local A = {}
HME.Alts = A

-- What a gathering profession's rank allows: { rank name, max, level to learn }.
A.RANKS = { { "Apprentice", 75, 5 }, { "Journeyman", 150, 10 }, { "Expert", 225, 20 }, { "Artisan", 300, 35 } }
A.PROFS = { Herbalism = true, Mining = true, Skinning = true, Fishing = true }

-- Stores this character's professions with its snapshot (called on login and
-- when a skill changes).
function A.Remember()
    if not (HME.db and HME.Bags and HME.Bags.Me()) then return end
    local root = HME.db.chars
    if type(root) ~= "table" then
        HME.db.chars = {}
        root = HME.db.chars
    end
    local me = HME.Bags.Me()
    local e = root[me]
    if type(e) ~= "table" then
        e = {}
        root[me] = e
    end
    local p = HME.Player.Profile()
    e.level, e.faction, e.class = HME.Player.Level(), HME.Player.Faction(), HME.Player.Class()
    e.profs = {}
    for prof, s in pairs(p.skills or {}) do
        if A.PROFS[prof] then e.profs[prof] = { rank = s.rank, max = s.max } end
    end
    e.t = (time and time()) or 0
end
HME.Listen("PLAYER_CHANGED", function() HME.Soon("alts-remember", 3, A.Remember) end)
HME.On("PLAYER_ENTERING_WORLD", function() HME.Soon("alts-remember", 6, A.Remember) end)

local function NextRank(max)
    for i, r in ipairs(A.RANKS) do
        if r[2] > max then return r, A.RANKS[i] end
    end
    return nil
end

-- Hints for one character: { text, kind }.
function A.Hints(e)
    local out = {}
    for prof, s in pairs(type(e.profs) == "table" and e.profs or {}) do
        if type(s) == "table" and s.rank and s.max then
            local nxt = NextRank(s.max)
            if s.rank >= s.max and nxt then
                if (e.level or 0) >= nxt[3] then
                    out[#out + 1] = { kind = "train", text = ("%s %d/%d: train %s (up to %d) at a trainer."):format(prof, s.rank, s.max, nxt[1], nxt[2]) }
                else
                    out[#out + 1] = { kind = "level", text = ("%s %d/%d: %s needs level %d."):format(prof, s.rank, s.max, nxt[1], nxt[3]) }
                end
            end
        end
    end
    table.sort(out, function(a, b) return a.text < b.text end)
    return out
end

-- Every character: { name, short, me, level, faction, class, profs, seen, materials (count), hints }.
function A.List()
    local out = {}
    local me = HME.Bags and HME.Bags.Me()
    local now = (time and time()) or 0
    for name, e in pairs((HME.db and type(HME.db.chars) == "table" and HME.db.chars) or {}) do
        if type(e) == "table" then
            local n = 0
            for _, where in ipairs({ e.bags, e.bank }) do
                for _, c in pairs(type(where) == "table" and where or {}) do n = n + (tonumber(c) or 0) end
            end
            local class = type(e.class) == "string" and (e.class:sub(1, 1):upper() .. e.class:sub(2):lower()) or nil
            out[#out + 1] = { name = name, short = (name:gsub("%-.*", "")), me = name == me, level = e.level, faction = e.faction,
                class = class, profs = type(e.profs) == "table" and e.profs or {}, seen = e.t and math.max(0, now - e.t) or nil,
                materials = n, hints = A.Hints(e) }
        end
    end
    table.sort(out, function(a, b)
        if a.me ~= b.me then return a.me end
        return (a.level or 0) > (b.level or 0)
    end)
    return out
end

-- "Mining 150/150 (train Expert), Skinning 143/225" for a character; with
-- its level, what a capped profession needs next.
function A.ProfText(profs, level)
    local parts = {}
    for prof, s in pairs(profs or {}) do
        if type(s) == "table" then
            local note = ""
            local nxt = s.rank and s.max and s.rank >= s.max and NextRank(s.max)
            if nxt and level then
                note = level >= nxt[3] and (" (train %s)"):format(nxt[1]) or (" (%s at level %d)"):format(nxt[1], nxt[3])
            end
            parts[#parts + 1] = ("%s %d/%d%s"):format(prof, s.rank or 0, s.max or 0, note)
        end
    end
    table.sort(parts)
    return #parts > 0 and table.concat(parts, ", ") or "no gathering profession seen"
end
