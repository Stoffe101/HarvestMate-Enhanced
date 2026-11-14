-- HarvestMate Enhanced: Engine/Guide.lua
-- The adaptive leveling guide. Gatherpedia's 1-300 guides (brackets with
-- zones, recorded routes, training notes and tips) say where people usually
-- go; this module adds where THIS character should go now, and notices when
-- that changes:
--   * the next milestone (rank to train, end of the bracket, 300)
--   * whether the next rank can be trained now, or needs a level first
--   * whether the farm being followed has gone mostly grey
--   * a better farm for the current skill (Farm Finder, goal "level")
-- Copyright (C) 2026 HarvestMate Enhanced contributors. GPL-3.0-or-later.

local _, ns = ...
local HME = ns.HME
local SM = HME.SkillModel

local G = {}
HME.Guide = G

G.GREY_SHARE = 0.65   -- the farm counts as "mostly grey" past this share

-- Gatherpedia guide bracket for a skill (its DefaultKey picks it).
function G.Bracket(prof, skill)
    local Guides = ns.Guides
    if not Guides then return nil end
    local key = Guides:DefaultKey(prof, skill or 1)
    return key and Guides:Bracket(prof, key), key
end

-- Everything the Guides page shows for a profession:
-- { prof, skill, max, rank, nextRank, train = state, milestone = { skill, what },
--   bracket, spots (for your faction), messages = { {kind, text} } }
function G.Status(prof, profile)
    profile = profile or HME.Player.Profile()
    local s = profile.skills[prof]
    local out = { prof = prof, messages = {} }
    if not s then
        out.missing = true
        out.messages[#out.messages + 1] = { "info", ("You don't know %s on this character. Pick it in the Farm Finder "
            .. "with \"plan for another skill\" to look ahead."):format(prof) }
        return out
    end
    out.skill, out.max = s.rank, s.max
    out.rank, out.nextRank = HME.Player.RankFor(s.max)
    local state, nextRank, why = HME.Player.TrainingState(prof, profile)
    out.train = state
    if state == "capped" then
        out.messages[#out.messages + 1] = { "warn", ("%s is at its cap (%d). Train %s to keep gaining skill.")
            :format(prof, s.max, nextRank.name) }
    elseif state == "ready" then
        out.messages[#out.messages + 1] = { "good", ("You can train %s %s now (skill %d+).")
            :format(nextRank.name, prof, nextRank.from) }
    elseif state == "level" then
        out.messages[#out.messages + 1] = { "warn", ("%s %s needs character level %d; you are %d. Until then your skill "
            .. "stops at %d."):format(nextRank.name, prof, nextRank.level, profile.level, s.max) }
    elseif state == "max" then
        out.messages[#out.messages + 1] = { "good", prof .. " is maxed at 300. The Farm Finder's Best gold goal is for you." }
    end
    if why == "quest" then
        out.messages[#out.messages + 1] = { "info", "Fishing's higher ranks come from a book and a quest, not a trainer." }
    end
    -- Next milestone
    if s.rank < 300 then
        local m
        if nextRank and s.rank < nextRank.from then
            m = { skill = nextRank.from, what = "train " .. nextRank.name }
        elseif s.rank < s.max then
            m = { skill = s.max, what = "rank cap" }
        else
            m = { skill = 300, what = "300" }
        end
        out.milestone = m
    end
    local bracket, key = G.Bracket(prof, s.rank)
    out.bracket, out.bracketKey = bracket, key
    if bracket and ns.Guides then
        out.spots = ns.Guides:Spots(bracket, profile.faction)
    end
    -- The farm being followed: is it still worth it for skill?
    local g = HME.Guidance and HME.Guidance.Active()
    if g and g.prof == prof and g.result then
        local grey = G.GreyShare(g.result, s.rank)
        if grey and grey >= G.GREY_SHARE then
            out.messages[#out.messages + 1] = { "warn", ("%d%% of what this farm gives is grey for you now. The Farm "
                .. "Finder will suggest the next area."):format(grey * 100) }
            out.greyFarm = true
        end
    end
    return out
end

-- Share of a result's targets (by share/count) that are grey at this skill.
function G.GreyShare(result, skill)
    local total, grey = 0, 0
    for _, t in ipairs(result.targets or {}) do
        local w = t.share or t.count or 1
        total = total + w
        local req = t.req
        if t.min and result.prof == "Skinning" then req = SM.SkinReq(math.floor((t.min + t.max) / 2 + 0.5)) end
        if req and SM.Color(skill, req) == "grey" then grey = grey + w end
    end
    if total == 0 then return nil end
    return grey / total
end

-- Checked after every skill-up: says once when the active farm has gone grey
-- or a rank opens up (with the "autoGuide" setting on).
local said = {}
HME.Listen("SKILL_UP", function(prof, rank)
    if not (HME.settings and HME.settings.autoGuide) then return end
    local st = G.Status(prof)
    for _, m in ipairs(st.messages) do
        if m[1] ~= "info" then
            local k = prof .. ":" .. m[2]
            if not said[k] then
                said[k] = true
                HME.Print(m[2])
                HME.Signal("GUIDE_ADVICE", prof, m)
            end
        end
    end
end)
