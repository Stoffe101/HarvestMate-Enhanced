-- HarvestMate Enhanced: Engine/SkillModel.lua
-- Skill colors and the chance of a skill-up. The colors are the game's
-- (orange from the requirement, yellow +25, green +50, grey +100; for a
-- requirement of 1: 25 / 50 / 100, as HarvestMate does). The chance is a model:
-- 100% while orange, then falling in a straight line to 0% at grey. That is
-- the usual community approximation; HME replaces it with what you measure
-- (Engine/Learning.lua) once you have gathered enough.
--
-- Fishing works by zone, not by fish: a zone needs a minimum skill to land a
-- catch at all, and more for no getaways (Gatherpedia's Zones:FishSkill).
-- Copyright (C) 2026 HarvestMate Enhanced contributors. GPL-3.0-or-later.

local _, ns = ...
local HME = ns.HME
local U = HME.U

local M = {}
HME.SkillModel = M

M.COLORS = {
    red = { 1.00, 0.19, 0.19 }, orange = { 1.00, 0.54, 0.24 }, yellow = { 1.00, 0.88, 0.30 },
    green = { 0.28, 0.78, 0.35 }, grey = { 0.60, 0.60, 0.60 },
}
M.HEX = { red = "ff3030", orange = "ff8a3d", yellow = "ffe14d", green = "48c75a", grey = "9a9a9a" }

function M.Thresholds(req)
    local base = req <= 1 and 0 or req
    return base + 25, base + 50, base + 100
end

function M.Color(skill, req)
    if not skill or not req then return nil end
    local yellow, green, grey = M.Thresholds(req)
    if skill < req then return "red" end
    if skill < yellow then return "orange" end
    if skill < green then return "yellow" end
    if skill < grey then return "green" end
    return "grey"
end

-- Chance (0-1) that one successful gather gives a point.
function M.Chance(skill, req)
    if not skill or not req or skill < req then return 0 end
    local yellow, _, grey = M.Thresholds(req)
    if skill < yellow then return 1 end
    if skill >= grey then return 0 end
    return U.Clamp((grey - skill) / (grey - yellow), 0, 1)
end

-- Skinning: the skill a beast of this level needs (HarvestMate's rule,
-- matching the game: 1 to level 10, (level-10)*10 to 20, level*5 above).
function M.SkinReq(level)
    if level <= 10 then return 1 end
    if level <= 20 then return (level - 10) * 10 end
    return level * 5
end

-- The highest beast level this skinning skill can skin.
function M.MaxSkinLevel(skill)
    if skill >= 100 then return math.floor(skill / 5) end
    if skill >= 10 then return 10 + math.floor(skill / 10) end
    return 10
end

-- Fishing: chance of a skill point per catch. A catch gives a point every
-- time up to 75, then needs about (skill - 75) / 25 catches per point
-- (approximation). Below the zone's minimum nothing is landed.
function M.FishChance(skill, zoneMin)
    if zoneMin and skill < zoneMin then return 0 end
    if skill < 75 then return 1 end
    return U.Clamp(1 / math.max(1, (skill - 75) / 25), 0, 1)
end

-- Share of casts that land a catch: all past the no-getaway skill, none
-- below the minimum, a straight line in between.
function M.FishLanding(skill, zoneMin, noGetaway)
    if not zoneMin then return 0.8 end
    if skill < zoneMin then return 0 end
    if not noGetaway or skill >= noGetaway then return 1 end
    return U.Clamp(0.4 + 0.6 * (skill - zoneMin) / math.max(1, noGetaway - zoneMin), 0.4, 1)
end

-- Expected skill points per hour from a stream of gathers, each of a type with
-- requirement req and a share of the gathers. Applies the chance at the
-- current skill only (a planning estimate, not a simulation of the climb).
function M.PointsPerGather(skill, typesWithShare)
    local p = 0
    for _, t in ipairs(typesWithShare) do
        p = p + t.share * M.Chance(skill, t.req)
    end
    return p
end

-- How many points until every type here is grey, at the current rates.
function M.Headroom(skill, reqs)
    local top = 0
    for _, req in ipairs(reqs) do
        local _, _, grey = M.Thresholds(req)
        if grey > top then top = grey end
    end
    return math.max(0, top - skill)
end
