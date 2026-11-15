-- HarvestMate Enhanced: Engine/Quests.lua (0.6.0)
-- Quest-farming synergy: which farms also progress a quest in your log.
--
-- Read-only, from three sources, best first:
--   1. Forever-GPS's API (QuestObjectiveTargets, Forever-GPS 2.7 on its
--      feature/public-api branch): the
--      creature and item ids of each objective and which creatures drop the
--      item, from Questie when it is loaded.
--   2. Questie itself, through a small adapter that checks every function it
--      uses and gives up quietly if Questie changes (personal-use fallback when
--      Forever-GPS is older or missing).
--   3. The game's own quest log text: "Gray Bear slain: 3/8", "Bear Hide: 2/10"
--      matched by name against the creatures and materials HME knows.
-- Only quests in YOUR LOG count: historical quest data is never taken as a
-- sign that a quest is available. HME never accepts, tracks, completes or
-- abandons quests, and draws nothing on the quest map.
-- Copyright (C) 2026 HarvestMate Enhanced contributors. GPL-3.0-or-later.

local _, ns = ...
local HME = ns.HME
local U = HME.U

local Q = {}
HME.QuestSynergy = Q

Q.MAX_QUESTS = 35

---------------------------------------------------------------------------
-- The quest log (C_QuestLog on WoW Forever; the old globals as a fallback)
---------------------------------------------------------------------------
local function Objectives(questID, logIndex)
    local out = {}
    local CQ = C_QuestLog
    if CQ and CQ.GetQuestObjectives and questID then
        local ok, list = pcall(CQ.GetQuestObjectives, questID)
        if ok and type(list) == "table" then
            for i, o in ipairs(list) do
                if type(o) == "table" then
                    out[#out + 1] = { index = i, text = HME.Str(o.text) or "", type = HME.Str(o.type), finished = o.finished == true,
                        have = HME.Num(o.numFulfilled), need = HME.Num(o.numRequired) }
                end
            end
            return out
        end
    end
    if _G.GetNumQuestLeaderBoards and _G.GetQuestLogLeaderBoard and logIndex then
        local ok, n = pcall(_G.GetNumQuestLeaderBoards, logIndex)
        for i = 1, (ok and HME.Num(n)) or 0 do
            local ok2, text, kind, finished = pcall(_G.GetQuestLogLeaderBoard, i, logIndex)
            if ok2 and text then
                local have, need = tostring(text):match("(%d+)%s*/%s*(%d+)")
                out[#out + 1] = { index = i, text = HME.Str(text) or "", type = HME.Str(kind), finished = finished == true or finished == 1,
                    have = tonumber(have), need = tonumber(need) }
            end
        end
    end
    return out
end

-- { { questID, title, level, complete, objectives } } for quests in the log.
function Q.ReadLog()
    local out = {}
    local CQ = C_QuestLog
    if CQ and CQ.GetNumQuestLogEntries and CQ.GetInfo then
        local ok, n = pcall(CQ.GetNumQuestLogEntries)
        for i = 1, (ok and HME.Num(n)) or 0 do
            local ok2, info = pcall(CQ.GetInfo, i)
            if ok2 and type(info) == "table" and not info.isHeader and HME.Num(info.questID) then
                out[#out + 1] = { questID = info.questID, title = HME.Str(info.title) or ("Quest " .. info.questID),
                    level = HME.Num(info.level), complete = CQ.IsComplete and select(2, pcall(CQ.IsComplete, info.questID)) == true,
                    objectives = Objectives(info.questID, i) }
            end
            if #out >= Q.MAX_QUESTS then break end
        end
        return out, "C_QuestLog"
    end
    if _G.GetNumQuestLogEntries and _G.GetQuestLogTitle then
        local ok, n = pcall(_G.GetNumQuestLogEntries)
        for i = 1, (ok and HME.Num(n)) or 0 do
            local ok2, title, level, _, isHeader, _, isComplete, _, questID = pcall(_G.GetQuestLogTitle, i)
            if ok2 and title and not isHeader then
                out[#out + 1] = { questID = HME.Num(questID), title = title, level = HME.Num(level), complete = isComplete == 1 or isComplete == true,
                    objectives = Objectives(HME.Num(questID), i) }
            end
            if #out >= Q.MAX_QUESTS then break end
        end
        return out, "GetQuestLogTitle"
    end
    return out, nil
end

---------------------------------------------------------------------------
-- Objective targets: Forever-GPS, then Questie, then nothing
---------------------------------------------------------------------------
-- { { kind = "monster"|"item"|"object", ids = { ... }, drops = { npcIDs } } } or nil.
local function FromForeverGPS(questID)
    local api = _G.ForeverGPS and _G.ForeverGPS.API
    if not (api and type(api.QuestObjectiveTargets) == "function") then return nil end
    local ok, t = pcall(api.QuestObjectiveTargets, questID)
    if ok and type(t) == "table" then return t, "forevergps" end
    return nil
end

local questie
local function Questie()
    if questie ~= nil then return questie or nil end
    local L = _G.QuestieLoader
    if not (L and type(L.ImportModule) == "function") or (HME.settings and HME.settings.questie == false) then
        return nil
    end
    local ok, db = pcall(L.ImportModule, L, "QuestieDB")
    if not (ok and type(db) == "table" and type(db.QueryQuestSingle) == "function" and type(db.QueryItemSingle) == "function") then
        questie = false
        return nil
    end
    questie = db
    return db
end
function Q.Forget() questie = nil end

local function IdsOf(list, pickFirst)
    local out = {}
    for _, o in ipairs(type(list) == "table" and list or {}) do
        local id = type(o) == "table" and (pickFirst and o[1]) or o
        if type(id) == "number" then out[#out + 1] = id end
        -- Kill-credit objectives: { { ids... }, baseID, text }.
        if type(o) == "table" and type(o[1]) == "table" then
            for _, x in ipairs(o[1]) do if type(x) == "number" then out[#out + 1] = x end end
        end
    end
    return out
end

local function FromObjectiveData(db, questID)
    if type(db.GetQuest) ~= "function" then return nil end
    local ok, quest = pcall(db.GetQuest, questID)
    local data = ok and type(quest) == "table" and quest.ObjectiveData
    if type(data) ~= "table" then return nil end
    local out, npcs = {}, {}
    for _, o in ipairs(data) do
        if type(o) == "table" then
            if o.Type == "monster" or o.Type == "killcredit" then
                if type(o.Id) == "number" then npcs[#npcs + 1] = o.Id end
                for _, id in ipairs(type(o.IdList) == "table" and o.IdList or {}) do
                    if type(id) == "number" then npcs[#npcs + 1] = id end
                end
            elseif o.Type == "item" and type(o.Id) == "number" then
                local okD, drops = pcall(db.QueryItemSingle, o.Id, "npcDrops")
                out[#out + 1] = { kind = "item", ids = { o.Id }, drops = okD and type(drops) == "table" and drops or {} }
            elseif o.Type == "object" and type(o.Id) == "number" then
                out[#out + 1] = { kind = "object", ids = { o.Id } }
            end
        end
    end
    if #npcs > 0 then table.insert(out, 1, { kind = "monster", ids = npcs }) end
    return out
end

local function FromQuestie(questID)
    local db = Questie()
    if not db then return nil end
    -- Questie's runtime quest object first (what its own tracker reads)...
    local viaData = FromObjectiveData(db, questID)
    if viaData and #viaData > 0 then return viaData, "questie" end
    -- ...else its database row: { creatures, objects, items, rep, killCredit }.
    local ok, obj = pcall(db.QueryQuestSingle, questID, "objectives")
    if not ok or type(obj) ~= "table" then return nil end
    local out = {}
    local npcs = IdsOf(obj[1], true)
    for _, kc in ipairs(type(obj[5]) == "table" and obj[5] or {}) do
        for _, id in ipairs(IdsOf({ kc })) do npcs[#npcs + 1] = id end
    end
    if #npcs > 0 then out[#out + 1] = { kind = "monster", ids = npcs } end
    for _, id in ipairs(IdsOf(obj[3], true)) do
        local okD, drops = pcall(db.QueryItemSingle, id, "npcDrops")
        out[#out + 1] = { kind = "item", ids = { id }, drops = okD and type(drops) == "table" and drops or {} }
    end
    local objects = IdsOf(obj[2], true)
    if #objects > 0 then out[#out + 1] = { kind = "object", ids = objects } end
    return out, "questie"
end

function Q.Targets(questID)
    if not questID then return nil end
    local t, src = FromForeverGPS(questID)
    if t then return t, src end
    return FromQuestie(questID)
end

---------------------------------------------------------------------------
-- The index: what in the log a farm can serve
---------------------------------------------------------------------------
local index = { npc = {}, item = {}, name = {}, quests = {} }
Q.index = index
local signature = ""

-- "Gray Bear slain: 3/8" -> "gray bear"; "Bear Hide: 2/10" -> "bear hide".
local function ObjectiveName(text)
    text = tostring(text or "")
    local name = text:match("^(.-)%s+slain") or text:match("^(.-)%s+killed") or text:match("^Kill%s+(.-)%s*:")
        or text:match("^(.-)%s*:%s*%d") or text:match("^(.-)%s*%(%d")
    if not name or name == "" then return nil end
    name = name:lower():gsub("^%s+", ""):gsub("%s+$", "")
    return name
end
Q.ObjectiveName = ObjectiveName

local function Add(map, key, entry)
    if key == nil then return end
    map[key] = map[key] or {}
    table.insert(map[key], entry)
end

function Q.Rebuild()
    index = { npc = {}, item = {}, name = {}, quests = {}, source = nil }
    Q.index = index
    local log, api = Q.ReadLog()
    index.api = api
    local sig = {}
    for _, q in ipairs(log) do
        if not q.complete then
            local targets, src = Q.Targets(q.questID)
            for _, o in ipairs(q.objectives) do
                if not o.finished then
                    local e = { questID = q.questID, title = q.title, text = o.text, have = o.have, need = o.need, kind = o.type,
                        source = src or "log" }
                    local name = ObjectiveName(o.text)
                    if name then Add(index.name, name, e) end
                    sig[#sig + 1] = q.questID .. ":" .. (o.text or "")
                    -- With ids: every creature or item the objectives name.
                    for _, t in ipairs(targets or {}) do
                        if t.kind == "monster" and (o.type == "monster" or not o.type) then
                            for _, id in ipairs(t.ids or {}) do Add(index.npc, id, e) end
                        elseif t.kind == "item" and (o.type == "item" or not o.type) then
                            for _, id in ipairs(t.ids or {}) do Add(index.item, id, e) end
                            for _, npc in ipairs(t.drops or {}) do Add(index.npc, npc, e) end
                        end
                    end
                end
            end
            index.quests[#index.quests + 1] = q
            if targets then index.source = src end
        end
    end
    local s = table.concat(sig, "|")
    if s ~= signature then
        signature = s
        HME.Signal("QUESTS_CHANGED")
    end
    return index
end

HME.On("QUEST_LOG_UPDATE", function() HME.Soon("quest-index", 2, Q.Rebuild) end)
HME.On("PLAYER_ENTERING_WORLD", function() HME.Soon("quest-index", 4, Q.Rebuild) end)

-- Every unfinished objective entry this creature (npcID, name) serves.
function Q.ForCreature(npcID, name)
    local out, seen = {}, {}
    local function take(list)
        for _, e in ipairs(list or {}) do
            local k = e.questID .. e.text
            if not seen[k] then seen[k] = true out[#out + 1] = e end
        end
    end
    take(npcID and index.npc[npcID])
    if name then take(index.name[name:lower()]) end
    return out
end

-- Every unfinished objective entry this item (id, name) serves.
function Q.ForItem(itemID, name)
    local out, seen = {}, {}
    local function take(list)
        for _, e in ipairs(list or {}) do
            local k = e.questID .. e.text
            if not seen[k] then seen[k] = true out[#out + 1] = e end
        end
    end
    take(itemID and index.item[itemID])
    if name then take(index.name[name:lower()]) end
    return out
end

-- Quest objectives a Farm Finder result serves (its creatures, or what its
-- nodes and catches give), or nil.
function Q.ForResult(r)
    if not r or #index.quests == 0 then return nil end
    local out, seen = {}, {}
    local function take(list)
        for _, e in ipairs(list) do
            local k = e.questID .. e.text
            if not seen[k] then seen[k] = true out[#out + 1] = e end
        end
    end
    for _, t in ipairs(r.targets or {}) do
        if r.prof == "Skinning" then
            take(Q.ForCreature(t.npcID, t.name))
        else
            take(Q.ForItem(t.id or t.itemID, t.name))
        end
    end
    for id in pairs((r.metrics and r.metrics.items) or {}) do
        take(Q.ForItem(id, ns.ItemNameByID and ns.ItemNameByID(id)))
    end
    return #out > 0 and out or nil
end

-- "Bear Hunt (Gray Bear slain: 3/8)" for up to two objectives.
function Q.Text(list)
    local parts = {}
    for i = 1, math.min(2, #list) do
        local e = list[i]
        parts[#parts + 1] = ("%s (%s)"):format(e.title, e.text)
    end
    if #list > 2 then parts[#parts + 1] = ("+%d more"):format(#list - 2) end
    return table.concat(parts, ", ")
end

-- For /hme diag: which source the quest log came from and what it found.
function Q.Status()
    local n = 0
    for _ in pairs(index.npc) do n = n + 1 end
    return ("%d quests read (%s), objective ids from %s, %d creatures matched"):format(#index.quests, index.api or "no quest API",
        index.source or (Questie() and "Questie" or "quest text only"), n)
end
