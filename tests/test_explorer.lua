-- The Skinning Explorer: the creature index, search by name, zone, level and
-- material, unknown skinnability stays unknown, the drop journal keeps skins
-- apart from corpse loot, skill-ups after a skin, "best for me", and a hunt
-- planned for one creature alone.

local ns, HME = LoadHME()
PLAYER.map, PLAYER.x, PLAYER.y = 1424, 0.46, 0.42
CHAR.level = 41
PROFS = { { line = 393, rank = 143, max = 225 } }
HME.Player.Refresh()
local Bx = HME.Bestiary
local profile = HME.Player.Profile()

STEP("index: one entry per creature, levels and maps merged")
local idx, all = Bx.Index()
check(#all > 300, "hundreds of beasts: " .. #all)
local seen = {}
for _, e in ipairs(all) do
    check(not seen[e.npcID], "once: " .. e.npcID)
    seen[e.npcID] = true
    check(e.min <= e.max and e.spawns >= 0 and next(e.maps) ~= nil, "shape: " .. e.name)
end

STEP("search: name, zone, level")
local bats = Bx.Search({ text = "bloodwing", filter = "all" }, profile)
check(#bats >= 1 and bats[1].name:find("Bloodwing"), "by name")
local hills = Bx.Search({ text = "hillsbrad", filter = "all" }, profile)
check(#hills > 3, "by zone: " .. #hills)
for _, e in ipairs(Bx.Search({ text = "35", filter = "all" }, profile)) do
    check(e.min <= 35 and e.max >= 35, "level 35 in range: " .. e.name)
end

STEP("search: by material gives beasts whose yield has it")
ITEMS[2319] = { name = "Medium Leather" }
local med, mats = Bx.Search({ text = "medium leather", filter = "all", sort = "forme" }, profile)
check(#mats >= 1, "material recognised")
check(#med > 5, "medium leather beasts: " .. #med)
for i = 1, math.min(10, #med) do
    check((HME.Skinning.Yield(med[i]).items[2319] or 0) > 0.02, med[i].name .. " gives it")
end

STEP("filters: can skin, this zone")
for _, e in ipairs(Bx.Search({ text = "", filter = "canskin" }, profile)) do
    check(HME.SkillModel.SkinReq(e.min) <= 143, "skinnable at 143: " .. e.name)
end
for _, e in ipairs(Bx.Search({ text = "", filter = "zone" }, profile)) do
    check(e.maps[1424] ~= nil, "in Hillsbrad: " .. e.name)
end

STEP("skinnable: unknown until the game says")
local e = bats[1]
local v, word = Bx.Skinnable(e.npcID)
eq(v, nil)
check(word:find("not confirmed"), word)
HME.db.obs.mobs[e.npcID] = false
v, word = Bx.Skinnable(e.npcID)
eq(v, false)
check(word:find("^no"), word)
check(#Bx.Search({ text = "bloodwing", filter = "all" }, profile) >= 1, "still listed")
local best = Bx.BestForMe("level", nil, profile, 400)
for _, b in ipairs(best) do check(b.e.npcID ~= e.npcID, "a beast the game said no to is never 'best for me'") end
HME.db.obs.mobs[e.npcID] = nil

STEP("journal: skins only, per skin, zones; corpse loot apart")
local n = 0
local function Guid(id) n = n + 1 return ("Creature-0-1-2-3-%d-%08X"):format(id, n) end
HME.Session.Start()
for _ = 1, 3 do
    RunTimers(6)
    FireEvent("UNIT_SPELLCAST_SUCCEEDED", "player", "cast", 8613)
    LOOT_SOURCE, LOOT = Guid(e.npcID), { { id = 2319, qty = 2 } }
    FireEvent("LOOT_OPENED")
    FireEvent("LOOT_CLOSED")
end
RunTimers(6)
LOOT_SOURCE, LOOT = Guid(e.npcID), { { id = 2589, qty = 1 } }   -- corpse loot, no skinning cast
FireEvent("LOOT_OPENED")
FireEvent("LOOT_CLOSED")
LOOT_SOURCE, LOOT = nil, {}
local j = Bx.Journal(e.npcID)
eq(j.n, 3, "three skins")
eq(j.items[1].id, 2319)
near(j.items[1].perSkin, 2, 1e-9)
for _, it in ipairs(j.items) do check(it.id ~= 2589, "linen is corpse loot, not a skin") end
eq(j.zones[1].mapID, 1424)

STEP("journal: a skill-up right after a skin belongs to that creature")
RunTimers(6)
FireEvent("UNIT_SPELLCAST_SUCCEEDED", "player", "cast", 8613)
LOOT_SOURCE, LOOT = Guid(e.npcID), { { id = 2319, qty = 1 } }
FireEvent("LOOT_OPENED")
FireEvent("LOOT_CLOSED")
PROFS = { { line = 393, rank = 144, max = 225 } }
HME.Player.Refresh()
FireEvent("SKILL_LINES_CHANGED")
RunTimers(1)
HME.Signal("PLAYER_CHANGED")
eq(Bx.Journal(e.npcID).ups, 1, "one skill-up")
HME.Session.Stop("test")
PROFS = { { line = 393, rank = 143, max = 225 } }
HME.Player.Refresh()

STEP("skinned filter lists what you skinned")
local sk = Bx.Search({ text = "", filter = "skinned" }, profile)
check(#sk >= 1 and sk[1].npcID == e.npcID, "the bat")

STEP("best for me: skill-ups, never elites first, gold and material modes")
best = Bx.BestForMe("level", nil, profile, 20)
check(#best >= 5, "a ranking")
for i = 2, #best do check(best[i - 1].me.score >= best[i].me.score, "ordered") end
for _, b in ipairs(best) do
    check(b.me.elig.killable, "only beasts you can kill: " .. b.e.name)
    check((b.me.skillPerHour or 0) > 0, "with skill-ups")
end
local medBest = Bx.BestForMe("material", 2319, profile, 10)
check(#medBest > 0 and (medBest[1].me.itemPerHour or 0) > 0, "medium leather an hour")

STEP("long creature names fit the list (no crash on odd data)")
local fake = { npcID = 999999, name = string.rep("Very Long Creature Name ", 6), min = 30, max = 31, maps = { [1424] = 3 }, spawns = 3 }
local me = Bx.ForMe(fake, profile, "level")
check(me.elig ~= nil, "a profile")

STEP("hunt one creature: circuits from its own spawns only")
local target
for _, b in ipairs(best) do if b.e.maps[1424] then target = b.e break end end
target = target or best[1].e
local got
Bx.Hunt(target, function(res) got = res end, profile)
HME.FinishJobs()
check(got and #got > 0, "hunting areas for " .. target.name)
for _, r in ipairs(got) do
    for _, t in ipairs(r.targets or {}) do eq(t.npcID, target.npcID, "only that creature") end
    check(target.maps[r.mapID] ~= nil, "in its own zones")
end

STEP("the page builds and shows a profile")
HME.OpenWindow("beasts")
RunTimers(1)
local pg = HME.Window.frame.pages.beasts
check(pg and pg.Refresh, "page")
HME.Pages.beastsShow("bloodwing")
check(true, "searched without error")
