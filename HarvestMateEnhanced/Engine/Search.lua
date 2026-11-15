-- HarvestMate Enhanced: Engine/Search.lua (0.6.0)
-- One search over everything HME knows: pages, materials, creatures, zones,
-- your routes, trainers, profession milestones, saved profiles, goals and the
-- quests in your log. Results are grouped by kind, best match first (a name
-- that starts with the text, then a word that does, then anywhere), five of a
-- kind and fourteen in all. Opening a result goes to where it lives; nothing
-- starts by itself (a profile is applied only when you pick it).
-- Copyright (C) 2026 HarvestMate Enhanced contributors. GPL-3.0-or-later.

local _, ns = ...
local HME = ns.HME
local U = HME.U

local S = {}
HME.Find = S

S.PER_KIND, S.MAX = 5, 14
S.KINDS = {
    { key = "page", label = "Pages" }, { key = "material", label = "Materials" }, { key = "creature", label = "Creatures" },
    { key = "zone", label = "Zones" }, { key = "route", label = "Your routes" }, { key = "trainer", label = "Trainers" },
    { key = "milestone", label = "Milestones" }, { key = "profile", label = "Profiles" }, { key = "goal", label = "Goals" },
    { key = "quest", label = "Your quests" },
}

local PAGES = {
    { "Copilot", "copilot" }, { "Farm Finder", "finder" }, { "Dashboard", "dashboard" }, { "Goals & Plans", "goals" },
    { "Leveling Guides", "guides" }, { "Materials", "materials" }, { "Skinning Explorer", "beasts" },
    { "Profits & Stats", "stats" }, { "Trainers", "trainers" }, { "Routes", "routes" }, { "New route", "newroute" },
    { "Avoid areas", "taboo" }, { "Map display", "display" }, { "Setup", "setup" }, { "Settings", "settings" },
}

-- 3: starts with the text, 2: a word starts with it, 1: anywhere, 0: no.
local function Match(name, text)
    name = (name or ""):lower()
    if name == "" then return 0 end
    if name:sub(1, #text) == text then return 3 end
    if name:find("[%s%-%(]" .. text:gsub("%p", "%%%0")) then return 2 end
    if name:find(text, 1, true) then return 1 end
    return 0
end
S.Match = Match

-- { { kind, label, sub, score, open = { ... } } } grouped by kind order.
function S.Run(text)
    text = U.Trim((text or ""):lower())
    if #text < 2 then return {} end
    local byKind = {}
    local function add(kind, label, sub, open, bonus)
        local m = Match(label, text)
        if m == 0 then return end
        byKind[kind] = byKind[kind] or {}
        table.insert(byKind[kind], { kind = kind, label = label, sub = sub, score = m + (bonus or 0), open = open })
    end
    for _, p in ipairs(PAGES) do add("page", p[1], "page", { kind = "page", page = p[2] }) end
    -- Materials of the four professions (the field guide).
    for _, prof in ipairs({ "Herbalism", "Mining", "Skinning", "Fishing" }) do
        local def = ns.professions and ns.professions[prof]
        for _, e in ipairs(def and def.items or {}) do
            if not e.placeholder then
                add("material", e.name, prof .. (e.skill and (", skill " .. e.skill) or ""), { kind = "material", prof = prof, name = e.name })
            end
        end
    end
    -- Creatures (Skinning Explorer).
    if HME.Bestiary then
        local _, all = HME.Bestiary.Index()
        for _, e in ipairs(all) do
            add("creature", e.name, ("level %s"):format(e.min == e.max and e.min or (e.min .. "-" .. e.max)),
                { kind = "creature", npcID = e.npcID, name = e.name })
        end
    end
    -- Zones.
    local seenZone = {}
    for mapID in pairs((HME.ZoneData and HME.ZoneData.ZONES) or {}) do
        local name = HME.ZoneData.Name(mapID)
        if name and not seenZone[name] then
            seenZone[name] = true
            local z = HME.ZoneData.Get(mapID)
            add("zone", name, z and z.levels and ("levels %d-%d"):format(z.levels[1], z.levels[2]) or "zone",
                { kind = "zone", mapID = mapID, name = name })
        end
    end
    -- Your routes.
    for _, r in ipairs((HME.Routes and HME.Routes.db and HME.Routes.db.routes) or {}) do
        add("route", r.name, HME.Routes:MapName(r.mapID) or "", { kind = "route", id = r.id }, 0.5)
    end
    -- Trainers of your side.
    local faction = HME.Player.Faction()
    for _, e in ipairs((ns.Trainers and ns.Trainers.List) or {}) do
        if e.faction == faction or e.faction == "Neutral" then
            add("trainer", e.name, ("%s, %s"):format(e.prof, e.zone or "?"), { kind = "trainer", prof = e.prof })
        end
    end
    -- Milestones: "Artisan Skinning", "Expert Mining"...
    for _, prof in ipairs({ "Herbalism", "Mining", "Skinning", "Fishing" }) do
        for _, rank in ipairs(HME.Player.RANKS) do
            add("milestone", rank.name .. " " .. prof, ("skill %d, level %d, cap %d"):format(rank.from, rank.level, rank.cap),
                { kind = "trainer", prof = prof })
        end
    end
    -- Saved profiles, goals, quests in your log.
    for _, p in ipairs((HME.Profiles and HME.Profiles.List()) or {}) do
        add("profile", p.name, ("%s, %s"):format(p.prof or "any", p.goal or ""), { kind = "profile", name = p.name }, 0.5)
    end
    for _, g in ipairs((HME.Goals and HME.Goals.List()) or {}) do
        add("goal", g.name or "Goal", g.doneAt and "done" or "open", { kind = "page", page = "goals" }, 0.5)
    end
    for _, q in ipairs((HME.QuestSynergy and HME.QuestSynergy.index.quests) or {}) do
        add("quest", q.title, "in your log", { kind = "quest", questID = q.questID }, 0.5)
    end
    -- Best first within a kind, five a kind, fourteen in all, kinds in order.
    local out = {}
    for _, k in ipairs(S.KINDS) do
        local list = byKind[k.key]
        if list then
            table.sort(list, function(a, b)
                if a.score ~= b.score then return a.score > b.score end
                if #a.label ~= #b.label then return #a.label < #b.label end
                return a.label < b.label
            end)
            for i = 1, math.min(S.PER_KIND, #list) do
                if #out < S.MAX then out[#out + 1] = list[i] end
            end
        end
    end
    return out
end

-- Goes to a result. Only ever from a click.
function S.Open(r)
    local o = r and r.open
    if not o then return false end
    local P = HME.Pages
    if o.kind == "page" then
        HME.OpenWindow(o.page)
    elseif o.kind == "material" then
        HME.OpenWindow("materials")
        if P.materialsShow then P.materialsShow(o.prof, o.name) end
    elseif o.kind == "creature" then
        HME.OpenWindow("beasts")
        if P.beastsShow then P.beastsShow(o.name, o.npcID) end
    elseif o.kind == "zone" then
        HME.OpenWindow("beasts")
        if P.beastsShow then P.beastsShow(o.name) end
    elseif o.kind == "route" then
        HME.OpenWindow("routes")
        local route = HME.Guidance.Route(o.id)
        if route and HME.Routes.InspectRoute then HME.After(0, function() HME.Routes:InspectRoute(route) end) end
    elseif o.kind == "trainer" then
        HME.OpenWindow("trainers")
        if P.trainersSet then P.trainersSet(o.prof) end
    elseif o.kind == "profile" then
        for _, p in ipairs(HME.Profiles.List()) do
            if p.name == o.name then HME.Profiles.Apply(p) break end
        end
    elseif o.kind == "quest" then
        if HME.Copilot then HME.Copilot.SetMode("quest") end
        HME.OpenWindow("copilot")
    else
        return false
    end
    return true
end
