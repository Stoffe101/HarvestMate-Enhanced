-- HarvestMate Enhanced: Core/Player.lua
-- What the game says about this character: level, faction, class, every
-- gathering profession with skill and cap (Fishing included), where it is and
-- how fast it moves. Cached, refreshed by events. The Farm Finder reads
-- HME.Player.Profile(), which applies the player's manual overrides when
-- "plan for another character / skill" is on.
-- Copyright (C) 2026 HarvestMate Enhanced contributors. GPL-3.0-or-later.

local _, ns = ...
local HME = ns.HME
local Num, Str = HME.Num, HME.Str

local P = {}
HME.Player = P

-- Skill line ids (GetProfessionInfo's 7th value) of the gathering professions.
P.LINES = { [182] = "Herbalism", [186] = "Mining", [393] = "Skinning", [356] = "Fishing" }
P.KEYS = { "Herbalism", "Mining", "Skinning", "Fishing" }
P.SHORT = { Herbalism = "herb", Mining = "mine", Skinning = "skin", Fishing = "fish" }
P.FROM_SHORT = { herb = "Herbalism", mine = "Mining", skin = "Skinning", fish = "Fishing" }

-- Rank caps and what opens the next one (character level), WoW Forever.
-- The trainer thresholds are the ones HarvestMate checks in game (Data.lua
-- RANKS); Fishing's Expert and Artisan come from quests/books, not levels.
P.RANKS = {
    { name = "Apprentice", cap = 75, from = 0, level = 1 },
    { name = "Journeyman", cap = 150, from = 50, level = 10 },
    { name = "Expert", cap = 225, from = 125, level = 20 },
    { name = "Artisan", cap = 300, from = 200, level = 35 },
}
P.MAX_SKILL = 300
P.MAX_LEVEL = 60

local cache = { profs = {}, at = -1 }

local function ScanProfessions()
    local found = {}
    if GetProfessions and GetProfessionInfo then
        local slots = { GetProfessions() }
        for i = 1, 5 do
            local idx = Num(slots[i])
            if idx then
                local ok, name, _, rank, max, _, _, line, bonus = pcall(GetProfessionInfo, idx)
                line, rank, max = ok and Num(line), ok and Num(rank), ok and Num(max)
                local key = line and P.LINES[line]
                if key and rank and max then
                    found[key] = { rank = rank + (Num(bonus) or 0), base = rank, max = max, name = Str(name) }
                end
            end
        end
    end
    -- Older clients: the skill list, only when the modern call is missing.
    if not GetProfessions and GetNumSkillLines and GetSkillLineInfo then
        local wanted = { Herbalism = "Herbalism", ["Herb Gathering"] = "Herbalism", Mining = "Mining",
            Skinning = "Skinning", Fishing = "Fishing" }
        for i = 1, Num(GetNumSkillLines()) or 0 do
            local name, header, _, rank, _, _, max = GetSkillLineInfo(i)
            name = Str(name)
            if name and not header and wanted[name] and Num(rank) then
                found[wanted[name]] = { rank = rank, base = rank, max = Num(max) or rank }
            end
        end
    end
    return found
end

function P.Refresh()
    local ok, found = pcall(ScanProfessions)
    if not ok then return end
    cache.profs = found
    cache.at = HME.Now()
    -- Gatherpedia's modules read ns.learned / ns.learnedList.
    for k in pairs(ns.learned) do ns.learned[k] = nil end
    for k, v in pairs(found) do ns.learned[k] = { rank = v.rank, max = v.max } end
    for i = #ns.learnedList, 1, -1 do ns.learnedList[i] = nil end
    local order = HME.char and HME.char.learnedOrder or {}
    local seen = {}
    for _, k in ipairs(order) do seen[k] = true end
    for _, k in ipairs(P.KEYS) do
        if found[k] and not seen[k] then
            order[#order + 1] = k
            seen[k] = true
        end
    end
    for _, k in ipairs(order) do
        if found[k] and k ~= "Fishing" then ns.learnedList[#ns.learnedList + 1] = k end
    end
    if found.Fishing then ns.learnedList[#ns.learnedList + 1] = "Fishing" end
    HME.Signal("PLAYER_CHANGED")
end

function P.Professions()
    if cache.at < 0 then P.Refresh() end
    return cache.profs
end

function P.Skill(prof)
    local p = P.Professions()[prof]
    return p and p.rank, p and p.max
end

function P.Level()
    return Num(UnitLevel and UnitLevel("player")) or 1
end

function P.Faction()
    local f = UnitFactionGroup and Str((UnitFactionGroup("player")))
    if f == "Alliance" or f == "Horde" then return f end
    return "Neutral"
end

function P.Class()
    local _, token = UnitClass and UnitClass("player")
    return Str(token) or "UNKNOWN"
end

-- The current map and position (0-1). Micro maps (caves) are reported as is;
-- HME.Geo rolls them up to their zone where needed.
function P.Position()
    if not (C_Map and C_Map.GetBestMapForUnit) then return nil end
    local mapID = Num(C_Map.GetBestMapForUnit("player"))
    if not mapID then return nil end
    local pos = C_Map.GetPlayerMapPosition and C_Map.GetPlayerMapPosition(mapID, "player")
    if not pos then return mapID end
    local x, y = pos.x, pos.y
    if x == nil and pos.GetXY then x, y = pos:GetXY() end
    x, y = Num(x), Num(y)
    if not x or (x == 0 and y == 0) then return mapID end
    return mapID, x, y
end

function P.ZoneName()
    return (ns.GetCurrentZone())
end

-- Travel speed in yards per second: what the character was last seen moving
-- at when mounted (kept per character), else 7 on foot. GetUnitSpeed can be a
-- secret value on Forever; then the old figure stays.
P.FOOT_SPEED = 7
function P.Speed()
    local s = HME.char and HME.char.eff and HME.char.eff.speed
    return (type(s) == "number" and s > 0) and s or P.FOOT_SPEED
end

function P.SampleSpeed()
    if not (GetUnitSpeed and HME.char) then return end
    local ok, _, run = pcall(GetUnitSpeed, "player")
    run = ok and Num(run)
    if not run or run <= P.FOOT_SPEED + 0.5 or run > 60 then return end
    run = math.floor(run * 10 + 0.5) / 10
    if run ~= HME.char.eff.speed then
        HME.char.eff.speed = run
        HME.Signal("SPEED_CHANGED", run)
    end
end

-- The rank this skill cap belongs to, and the next one.
function P.RankFor(max)
    for i, r in ipairs(P.RANKS) do
        if max <= r.cap then return r, P.RANKS[i + 1] end
    end
    return P.RANKS[#P.RANKS], nil
end

-- Everything the planner needs, with manual overrides applied:
-- { level, faction, class, speed, skills = { [prof] = { rank, max } }, zone,
--   mapID, x, y, real = true when nothing is overridden }
function P.Profile()
    local mapID, x, y = P.Position()
    local profile = {
        level = P.Level(), faction = P.Faction(), class = P.Class(), speed = P.Speed(),
        skills = {}, mapID = mapID, x = x, y = y, zone = P.ZoneName(), real = true,
    }
    for k, v in pairs(P.Professions()) do profile.skills[k] = { rank = v.rank, max = v.max } end
    local plan = HME.char and HME.char.plan
    if plan and plan.enabled then
        profile.real = false
        if type(plan.level) == "number" then profile.level = plan.level end
        if plan.faction == "Alliance" or plan.faction == "Horde" then profile.faction = plan.faction end
        for k, v in pairs(plan.skills or {}) do
            if type(v) == "number" then
                local cap = 75
                for _, r in ipairs(P.RANKS) do
                    if v >= r.from and profile.level >= r.level then cap = r.cap end
                end
                profile.skills[k] = { rank = v, max = math.max(cap, v) }
            end
        end
    end
    return profile
end

-- Can this character train the next rank now? Returns state, rank, why.
--   "max"     at 300
--   "capped"  skill = cap, next rank needed now
--   "ready"   the next rank can be trained already (skill >= its threshold)
--   "level"   skill is there but the character is too low
--   "later"   nothing to train yet
function P.TrainingState(prof, profile)
    profile = profile or P.Profile()
    local s = profile.skills[prof]
    if not s then return "none" end
    if s.max >= P.MAX_SKILL and s.rank >= P.MAX_SKILL then return "max" end
    local _, nextRank = P.RankFor(s.max)
    if not nextRank then return "later" end
    if prof == "Fishing" and nextRank.cap > 150 then
        -- Fishing's Expert and Artisan come from a book and a quest, not a trainer.
        if s.rank >= nextRank.from then return s.rank >= s.max and "capped" or "ready", nextRank, "quest" end
        return "later", nextRank
    end
    if s.rank < nextRank.from then return "later", nextRank end
    if profile.level < nextRank.level then return "level", nextRank end
    if s.rank >= s.max then return "capped", nextRank end
    return "ready", nextRank
end

HME.On("PLAYER_LOGIN", function() P.Refresh() end)
HME.On("PLAYER_ENTERING_WORLD", function() HME.Soon("player-refresh", 1, P.Refresh) end)
HME.On("SKILL_LINES_CHANGED", function() HME.Soon("player-refresh", 0.5, P.Refresh) end)
HME.On("CHAT_MSG_SKILL", function() HME.Soon("player-refresh", 0.5, P.Refresh) end)
HME.On("PLAYER_LEVEL_UP", function() HME.Soon("player-refresh", 0.5, P.Refresh) end)
