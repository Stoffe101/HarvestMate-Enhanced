-- Goals (scenario 5), staged leveling plans (scenario 11), comparison,
-- combined Herbalism + Mining loops (scenario 4), a wrong spawn point
-- (scenario 9), suggestions, the sell/keep advisor and profiles.

local ns, HME = LoadHME()
PLAYER.map, PLAYER.x, PLAYER.y = 1429, 0.42, 0.65
MAPS[1429].w, MAPS[1429].h = nil, nil
CHAR.level = 40
PROFS = { { line = 393, rank = 210, max = 225 }, { line = 186, rank = 150, max = 225 }, nil, nil }
HME.Player.Refresh()
HME.Prices.fixed = { [4234] = { low = 250, typical = 300 }, [2772] = { low = 120, typical = 150 }, [3821] = { low = 900, typical = 1100 } }
HME.Prices.Invalidate()

-- Bag counts the client reports.
BAG = {}
function GetItemCount(id, bank) return (BAG[id] or 0) + (bank and (BANK and BANK[id] or 0) or 0) end
C_Item.GetItemCount = GetItemCount

STEP("scenario 5: 100 Heavy Leather — a goal, a farm, progress, done")
local g = HME.Goals.Add({ type = "item", itemID = 4234, target = 100 })
check(g, "goal added")
eq(g.name, "Heavy Leather", "named from the field guide")
local found, eta
HME.Goals.Recommend(g, function(r, e) found, eta = r, e end)
HME.FinishJobs()
check(found and found.prof == "Skinning", "a skinning farm for it")
check(found.metrics.materialPerHour > 0, "Heavy Leather an hour")
check(eta and eta.hours > 0 and eta.remaining == 100, "time to finish: " .. tostring(eta and eta.hours))
BAG[4234] = 30
local p = HME.Goals.Progress(g)
eq(p.held, 30, "held in bags")
eq(p.gathered, 0, "nothing gathered yet")
HME.Signal("BEAST_SKINNED", 1, { [4234] = 3 }, "Creature-1")
p = HME.Goals.Progress(g)
eq(p.gathered, 3, "gathered counted apart from held")
check(not p.done, "not done")
local doneSeen
HME.Listen("GOAL_DONE", function(goal) doneSeen = goal end)
BAG[4234] = 100
HME.Signal("BEAST_SKINNED", 1, { [4234] = 1 }, "Creature-2")
check(doneSeen == g, "finished: said once")
check(g.doneAt, "marked done")
doneSeen = nil
HME.Goals.Check()
check(not doneSeen, "not said again")

STEP("the bank only counts once you opened it")
BAG[2772] = 5
local ore = HME.Goals.Add({ type = "item", itemID = 2772, target = 50 })
eq(HME.Goals.Progress(ore).have, 5, "bags only")
BANK = { [2772] = 20 }
FireEvent("BANKFRAME_OPENED")
RunTimers(1)
local op = HME.Goals.Progress(ore)
eq(op.bank, 20, "bank seen")
eq(op.have, 25, "held plus bank")

STEP("goals refuse nonsense")
check(not HME.Goals.Add({ type = "item", itemID = 4234, target = -5 }), "negative amount")
check(not HME.Goals.Add({ type = "skill", prof = "Skinning", target = 999 }), "skill above 300")
check(not HME.Goals.Add({ type = "list", items = {} }), "empty list")

STEP("a shopping list goes to the profession with the most missing")
local list = HME.Goals.Add({ type = "list", name = "Armor kit", items = { { itemID = 4234, target = 120 }, { itemID = 2772, target = 30 } } })
local q = HME.Goals.Query(list)
eq(q.prof, "Skinning", "most missing is leather")
check(q.targets[4234], "with its items")

STEP("scenario 11: Skinning 210 -> 300, staged")
local plan
HME.Guide.Plan("Skinning", 300, function(pl) plan = pl end)
HME.FinishJobs()
check(plan and #plan.stages >= 2, "several stages")
eq(plan.stages[1].from, 210, "starts at your skill")
eq(plan.stages[#plan.stages].to, 300, "ends at the target")
local trainSeen = false
for _, st in ipairs(plan.stages) do
    check(st.farm, ("stage %d-%d has a farm"):format(st.from, st.to))
    check(st.farm.metrics.skillChance > 0, "that still gives points")
    if st.train then trainSeen = true end
    REAL_PRINT(("  %d-%d: %s (%s)%s"):format(st.from, st.to, st.farm.zone, st.farm.subarea, st.train and (" then train " .. st.train.name) or ""))
end
check(trainSeen, "says where training is needed (225 -> Artisan)")
check(plan.hours.mid > 0 and plan.hours.low <= plan.hours.mid and plan.hours.mid <= plan.hours.high, "an hours range")

STEP("comparison: best only claimed on solid ground")
local res = HME.Recommend.Find({ prof = "Skinning", goal = "profit" }, nil, HME.Player.Profile())
local cmp = HME.Recommend.Compare({ res[1], res[2], res[3] })
check(cmp.best.gold, "a gold column")
check(cmp.best.travel.sure, "travel is a fact, so the shortest is simply best")
for _, n in ipairs(cmp.notes) do check(n:find("highest estimate", 1, true), "an unsure lead is called an estimate") end

STEP("scenario 4: herbs and ore on one loop")
PROFS[3] = { line = 182, rank = 150, max = 225 }
HME.Player.Refresh()
local both = HME.Recommend.Find({ prof = "Combined", goal = "level" }, nil, HME.Player.Profile())
check(#both > 0, "combined farms")
local herbs, ores = 0, 0
for _, t in ipairs(both[1].targets) do
    if t.prof == "Herbalism" then herbs = herbs + 1 elseif t.prof == "Mining" then ores = ores + 1 end
end
check(herbs > 0 and ores > 0, ("both kinds in the top loop (%d herbs, %d ores)"):format(herbs, ores))
local route = HME.Planner.Create(both[1], "level")
for _ = 1, 20000 do if not route.working then break end Tick(0.016) end
check(route.kinds["Herb Gathering"] and route.kinds["Mining"], "the route takes new nodes of both kinds")

STEP("scenario 9: a wrong spawn point is excluded from then on")
local sites = HME.Spawns.Sites("Mining", 1434)
local s1 = sites[1]
HME.Spawns.Exclude("Mining", 1434, s1.x, s1.y, true)
local after = HME.Spawns.Sites("Mining", 1434)
eq(#after, #sites - 1, "one site fewer")
for _, s in ipairs(after) do check(s ~= s1 and not (s.x == s1.x and s.y == s1.y), "not the excluded one") end
HME.Spawns.Exclude("Mining", 1434, s1.x, s1.y, false)
eq(#HME.Spawns.Sites("Mining", 1434), #sites, "and it can be put back")
-- A beast marked not skinnable: in that zone only (unless you say everywhere), reversible.
local function Killable(npcID, mapID)
    for _, c in ipairs(HME.Skinning.Candidates(mapID, HME.Player.Profile(), "balanced")) do
        if c.beast.npcID == npcID then return c.elig.killable, c.elig.why end
    end
end
local wolfMap
for _, id in ipairs(HME.Spawns.Maps("Skinning")) do
    for _, b in ipairs(HME.Spawns.BeastPoints(id)) do
        if not wolfMap and HME.Skinning.Eligible(b, HME.Player.Profile()).killable then wolfMap, wolf = id, b end
    end
end
check(wolfMap, "a beast to mark")
local mark = HME.Corrections.Add("notSkinnable", { mapID = wolfMap, npcID = wolf.npcID, name = wolf.name })
local ok, why = Killable(wolf.npcID, wolfMap)
check(not ok and why:find("this zone", 1, true), "left out in that zone: " .. tostring(why))
check(HME.Corrections.Remove(mark.id), "undone")
check(Killable(wolf.npcID, wolfMap), "and back")
-- 0.2.0's global marks become reversible "everywhere" corrections, the old table kept.
HME.db.obs.badBeasts = { [wolf.npcID] = true }
HME.db.obs.badBeastsMigrated = nil
eq(HME.Corrections.Migrate(), 1, "migrated")
check(not Killable(wolf.npcID, wolfMap), "still left out")
eq(HME.Corrections.List()[1].scope, "everywhere")
check(HME.db.obs.badBeasts[wolf.npcID], "the old data is kept")
HME.Corrections.Remove(HME.Corrections.List()[1].id)
-- Area marks: inaccessible farms leave the list, crowding fades.
local cr = HME.Corrections.Add("crowded", { mapID = 1429, x = 0.4, y = 0.4 })
check(HME.Corrections.ForArea(1429, 0.401, 0.401).mult < 1, "crowded counts lower")
cr.t = cr.t - 8 * 86400
eq(HME.Corrections.ForArea(1429, 0.401, 0.401).mult, 1, "a week later it no longer does")
HME.Corrections.Add("inaccessible", { mapID = 1429, x = 0.4, y = 0.4 })
check(HME.Corrections.ForArea(1429, 0.4, 0.41).exclude, "inaccessible: left out")
check(not HME.Corrections.ForArea(1429, 0.7, 0.7).exclude, "only there")
ClearLog()
SlashCmdList.HARVESTMATEENHANCED("corrections")
check(Said("your corrections"), "/hme corrections lists them")
local firstId = HME.Corrections.List()[1].id
SlashCmdList.HARVESTMATEENHANCED("uncorrect " .. firstId)
check(Said("undone"), "/hme uncorrect undoes one")
for _, c in ipairs(HME.Corrections.List()) do HME.Corrections.Remove(c.id) end

STEP("suggestions: shown once, can be switched off")
ClearLog()
check(HME.Suggest.Add("bagsFull", "x", "Bags nearly full."), "shown")
check(not HME.Suggest.Add("bagsFull", "x", "Bags nearly full."), "not again soon")
HME.settings.suggest = { stalePrices = false }
check(not HME.Suggest.Add("stalePrices", "y", "Old prices"), "a switched-off kind stays quiet")
HME.settings.suggest = nil
PROFS[1] = { line = 393, rank = 221, max = 225 }
HME.Player.Refresh()
HME.Signal("SKILL_UP", "Skinning", 221, 1)
local near
for _, s in ipairs(HME.Suggest.list) do if s.kind == "nearCap" then near = s end end
check(near and near.text:find("train Artisan"), "near the cap: train (" .. tostring(near and near.text) .. ")")

STEP("sell, keep or use")
local a = HME.Advice.For(2772)
eq(a.action, "keep", "the ore goal still needs Iron Ore")
local gold = HME.Advice.For(3821)
eq(gold.action, "auction", "Goldthorn sells better at auction")
check(gold.text:find("not sales", 1, true), "and says listings are not sales")

STEP("profiles: save and start again")
local prof = HME.Profiles.Save("Heavy Leather Profit", { prof = "Skinning", goal = "material", material = "Heavy Leather", risk = "safer", minutes = 30 })
check(prof, "saved")
eq(#HME.Profiles.List(), 1, "listed")
HME.Profiles.Save("Heavy Leather Profit", { prof = "Skinning", goal = "profit" })
eq(#HME.Profiles.List(), 1, "same name replaces")
eq(HME.Profiles.Apply(HME.Profiles.List()[1]), "search", "applying opens the Farm Finder on it")

STEP("item names come from C_Item (the client has no global GetItemInfo)")
check(_G.GetItemInfo == nil, "the stand-in client matches WoW Forever: no global GetItemInfo")
ITEMS[90001] = { name = "Test Reagent", sell = 5 }
eq(HME.Goals.ItemName(90001), "Test Reagent", "a reagent outside the field guide gets its client name")
eq(HME.Goals.ItemName(90002), "item 90002", "an unknown item says so")
check(HME.Goals.ItemName(2772):find("Iron Ore", 1, true), "a field guide item keeps its name")
