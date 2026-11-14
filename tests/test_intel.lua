-- Farming intelligence 0.3.0: per-character calibration (scenario I), skin
-- attribution, separate confidence dimensions, corrections in the Finder,
-- profit per effort, live feedback, adaptive loops, best beasts for a
-- material (scenario D), Herbs + Ore priorities (scenario E).

local ns, HME = LoadHME()
local L, R, Sk, Ev = HME.Learning, HME.Recommend, HME.Skinning, HME.Evidence

local function Profile(level, skill)
    return { level = level, faction = "Alliance", class = "HUNTER", speed = 7, mapID = 1429, x = 0.42, y = 0.65,
        skills = { Skinning = { rank = skill, max = 300 } }, zone = "Elwynn Forest", real = false }
end

STEP("scenario I: your own sessions calibrate the farm for you; low samples do not dominate")
local key = "Skinning@test:area"
HME.db.stats[key], HME.char.stats[key] = nil, nil
-- Another character farmed here for 2 hours at 120 beasts an hour.
HME.db.stats[key] = { hours = 2, sessions = 2, beasts = 240, value = 0 }
local r1 = L.Rate(key, "beasts")
check(r1, "other characters' farming counts")
eq(r1.ownHours, 0)
check(math.abs(r1.value - 120) < 0.01, "their rate")
check(r1.hours < 1, "but only a quarter of their hours for a pace-bound metric: " .. r1.hours)
-- 15 minutes of your own at 65 an hour: moves the estimate, does not replace it.
L.AddStats(key, { hours = 0.25, sessions = 1, beasts = 16.25 })
local r2 = L.Rate(key, "beasts")
local model = 120
local blended = r2.blend(model)
check(blended < model and blended > 90, ("a little lower for you after 15 min (%.0f)"):format(blended))
-- Two more hours of your own at 65: now your number leads.
L.AddStats(key, { hours = 2, sessions = 2, beasts = 130 })
local r3 = L.Rate(key, "beasts")
local blended3 = r3.blend(model)
check(blended3 < 90 and blended3 < blended, ("after 2 h more your own pace pulls it down further (%.0f)"):format(blended3))
eq(Ev.Classify({ key = key, prof = "Skinning", metrics = {} }).level, "measured", "measured: your own sessions")
-- Another character's view of the same farm is not condemned by yours.
local mine = HME.char.stats
HME.char.stats = {}
local other = L.Rate(key, "beasts")
check(other.value > 75, ("for a fresh character it is not written off (%.0f)"):format(other.value))
eq(Ev.Classify({ key = key, prof = "Skinning", metrics = {} }).level, "partly measured", "only partly measured for them")
HME.char.stats = mine
L.ResetArea(key)
eq(HME.char.stats[key], nil, "reset for this character")
check(HME.db.stats[key], "kept for the others")
L.ResetArea(key, true)
eq(HME.db.stats[key], nil, "or for everyone")

STEP("reputation comes from evidence only")
HME.char.stats["X@1"] = { hours = 0.05, sessions = 1 }
eq(L.Reputation("X@1")[1].label, "Needs more observations")
HME.char.stats["X@2"] = { hours = 3, sessions = 3, value = 3 * 15000, skillups = 3 * 50, travelHours = 2 }
HME.db.stats["X@2"] = HME.char.stats["X@2"]
local labels = {}
for _, rep in ipairs(L.Reputation("X@2", { value = 10000, gph = 10000 })) do labels[rep.label] = rep.why end
check(labels["Consistently productive"], "productive: measured above the estimate")
check(labels["Good for leveling"], "good for leveling")
check(labels["High travel overhead"], "travel overhead")

STEP("skin attribution: one cast is one skin; a corpse looted right after is loot")
HME.db.obs.skins, HME.db.obs.loot = {}, {}
local function Loot(guid, items) LOOT_SOURCE, LOOT = guid, items FireEvent("LOOT_OPENED") FireEvent("LOOT_CLOSED") end
FireEvent("UNIT_SPELLCAST_SUCCEEDED", "player", "cast", 8613)
Loot("Creature-0-1-2-3-1126-000000A1", { { id = 2318, qty = 1 } })
Loot("Creature-0-1-2-3-1126-000000A2", { { id = 2589, qty = 1 } })     -- another corpse, 0 s later
eq(HME.db.obs.skins[1126].n, 1, "one skin")
eq(HME.db.obs.loot[1126].n, 1, "the other corpse is loot, not a second skin")
Loot("Creature-0-1-2-3-1126-000000A1", { { id = 2318, qty = 1 } })     -- the skinned corpse's window again
eq(HME.db.obs.skins[1126].n, 1, "a repeated window is the same skin")
eq(HME.db.obs.loot[1126].n, 1, "and not loot either")
Loot(nil, { { id = 2770, qty = 1 } })
local recent = L.recent[#L.recent]
eq(recent.kind, "unattributed", "loot with no creature source is not attributed")
check(#L.recent >= 3, "the decisions are kept for diagnostics")

STEP("separate confidence dimensions on every result")
local profile = Profile(36, 175)
-- No auction addon in the test world: without prices, gold per anything is
-- unknown (nil), never a false zero.
local noPrices = R.Find({ prof = "Skinning", goal = "profit" }, nil, profile)
eq(noPrices[1].effort.perSkin, nil, "no prices: no gold per skin")
eq(noPrices[1].dims.profit.level, "unknown", "and profit confidence unknown")
-- From here on: a flat test price for every item.
HME.Prices.Value = function() return 500 end
local res = R.Find({ prof = "Skinning", goal = "profit" }, nil, profile)
check(#res > 0)
local d = res[1].dims
for _, k in ipairs(Ev.DIMENSIONS) do check(d[k] and d[k].level and d[k].why, k) end
eq(d.route.level, "unknown", "no route planned yet")
check(Ev.DimensionText(d):find("Spawns:", 1, true))
local lv = R.Find({ prof = "Skinning", goal = "level" }, nil, profile)
eq(lv[1].dims.profit.level, "unknown", "profit is not judged when leveling")

STEP("profit per effort")
local e = res[1].effort
check(e and e.perSkin and e.perSkin > 0, "gold per skin")
check(e.perKill and e.perKill > 0, "gold per kill")
check(e.perTrip and e.perTrip > 0, "gold per trip")
local cmp = R.Compare({ res[1], res[2] })
check(cmp.best.perSkin, "comparable per skin")

STEP("corrections reach the Finder: inaccessible leaves, dangerous counts, crowded ranks lower")
local top = res[1]
local mark = HME.Corrections.Add("inaccessible", { mapID = top.mapID, x = top.cx, y = top.cy })
local again, skipped = R.Find({ prof = "Skinning", goal = "profit" }, nil, profile)
for _, r in ipairs(again) do
    check(not (r.mapID == top.mapID and math.abs(r.cx - top.cx) < 0.01 and math.abs(r.cy - top.cy) < 0.01), "not listed")
end
local said = false
for _, s in ipairs(skipped) do if s.why == "you marked it inaccessible" then said = true end end
check(said, "left out, saying why")
HME.Corrections.Remove(mark.id)
local dmark = HME.Corrections.Add("dangerous", { mapID = top.mapID, x = top.cx, y = top.cy })
local risky = R.Find({ prof = "Skinning", goal = "profit" }, nil, profile)
for _, r in ipairs(risky) do
    if r.mapID == top.mapID and math.abs(r.cx - top.cx) < 0.01 then
        check(r.risk.score >= 0.3, "risk raised")
        check(r.summary:find("dangerous", 1, true), r.summary)
    end
end
HME.Corrections.Remove(dmark.id)

STEP("a saved goal is a reason")
local g = HME.Goals.Add({ type = "item", itemID = 2319, target = 100 })
local withGoal = R.Find({ prof = "Skinning", goal = "profit" }, nil, profile)
local any = false
for _, r in ipairs(withGoal) do if r.forGoal then any = true check(r.summary:find("your goal", 1, true), r.summary) end end
check(any, "a farm giving Medium Leather says it serves the goal")

STEP("scenario D: the best beasts for one material, with where and how sure")
local mat = R.Find({ prof = "Skinning", goal = "material", targets = { [2319] = true } }, nil, profile)
check(#mat > 0, "farms for Medium Leather")
local best = Sk.BestBeasts(mat, 2319)
check(#best > 0, "beasts that give it")
for i = 2, #best do check(best[i - 1].perHour >= best[i].perHour, "best first") end
local b1 = best[1]
check(b1.zone and b1.perSkin > 0 and b1.min and b1.req, "zone, yield per skin, levels and skill")
check(b1.result and b1.result.key, "with the hunting area to go to")
local goalRec
HME.Goals.Recommend(g, function(r, eta) goalRec = { r = r, eta = eta } end)
for _ = 1, 2000 do if goalRec then break end HME.FinishJobs() Tick(0.05) end
check(goalRec and goalRec.r and goalRec.eta and goalRec.eta.hours > 0, "and a time to finish the goal")
HME.Goals.Remove(g.id)

STEP("live feedback: rolling rates, materials, pace, and a verdict only with enough data")
local S = HME.Session
S.Stop("test")
S.Start()
local cur = S.Current()
HME.Guidance.PredictionFor = function() return { skins = 120, items = { [2319] = 90 } } end
cur.areaNow = "Skinning@live"
for i = 1, 5 do
    cur.farm = cur.farm + 60
    HME.Signal("BEAST_SKINNED", 1126, { [2319] = 1 }, "Creature-0-1-2-3-1126-1" .. i)
end
local live = S.Live()
eq(live.skins, 5)
check(live.items[1].n == 5 and live.items[1].expectedPerHour == 90, "material with its expected rate")
check(live.verdict and not live.verdict.enough, "five minutes: too early to judge")
check(live.verdict.text:find("too early", 1, true), live.verdict.text)
for i = 6, 30 do
    cur.farm = cur.farm + 60
    HME.Signal("BEAST_SKINNED", 1126, { [2319] = 1 }, "Creature-0-1-2-3-1126-2" .. i)
end
live = S.Live()
check(live.verdict.enough, "30 minutes and 30 skins: enough")
check(live.verdict.ratio < 0.6, ("about 60 an hour against 120 predicted (%.2f)"):format(live.verdict.ratio))
check(live.verdict.text:find("below the prediction", 1, true), live.verdict.text)
check(live.recent.skins and live.recent.skins > 0, "a rolling 20-minute rate")
check(live.betweenSkins and live.betweenSkins > 50, "time between skins")
HME.Suggest.CheckLive()
local saw = false
for _, s in ipairs(HME.Suggest.list) do if s.kind == "liveBelow" then saw = true end end
check(saw, "a suggestion, once there is enough data")
S.Stop("test")

STEP("adaptive loops: a stop you just gathered is skipped on the next pass")
local G, GP = HME.Guidance, HME.Routes
local loop = { id = GP.db.nextID, mapID = 1429, name = "adaptive", kinds = {}, sight = 0, shown = true, color = { 1, 1, 1 },
               points = { 0.40, 0.40, 0.45, 0.40, 0.45, 0.45, 0.40, 0.45 }, planned = { key = "Mining@adaptive", prof = "Mining" } }
GP.db.nextID = GP.db.nextID + 1
table.insert(GP.db.routes, loop)
PLAYER.map, PLAYER.x, PLAYER.y = 1429, 0.45, 0.40       -- at stop 2
G.Start(loop)
local st = G.Active()
st.prof = "Mining"
eq(st.phase, "farm")
st.stop = 1
HME.Signal("GATHER_LOOT", "mine", "Copper Vein", {})   -- gathered at stop 2
G.Advance()
eq(st.stop, 3, "stop 2 was just emptied by you: on to stop 3")
-- Every stop emptied: never skip them all.
for i = 1, 4 do st.gathered[i] = HME.Now() end
st.stop = 1
G.Advance()
eq(st.skippedLast, 3, "at most all but one skipped")
check(st.stop >= 1 and st.stop <= 4, "and the arrow points at a real stop")
G.Stop()

STEP("scenario E: Herbs + Ore priorities and the combined-vs-separate check")
local both = { level = 30, faction = "Alliance", class = "HUNTER", speed = 7, mapID = 1429, x = 0.42, y = 0.65,
    skills = { Herbalism = { rank = 150, max = 225 }, Mining = { rank = 100, max = 150 } }, zone = "Elwynn Forest", real = false }
local function Kinds(prio)
    HME.settings.combinedPriority = prio
    local list = R.Find({ prof = "Combined", goal = "level" }, nil, both)
    local herbs, ores = 0, 0
    for _, t in ipairs(list[1].targets) do
        if t.prof == "Herbalism" then herbs = herbs + t.share else ores = ores + t.share end
    end
    return herbs, ores, list[1]
end
local h1, o1 = Kinds("herb")
local h2, o2, r2c = Kinds("mine")
check(h1 / math.max(o1, 0.01) > h2 / math.max(o2, 0.01), ("herbs first gives more herbs (%.2f/%.2f vs %.2f/%.2f)"):format(h1, o1, h2, o2))
local _, _, lower = Kinds("lower")
check(lower, "lower skill first runs")
check(r2c.combined and r2c.combined.text, "says whether one loop beats two")
check(r2c.summary:find("Find Herbs or Find Minerals", 1, true), "and that tracking is one at a time")
HME.settings.combinedPriority = "equal"
