-- The engines one by one: skill model, skinning (eligibility, kill time,
-- yields, profit), gathering, learning, risk, travel, planning routes
-- (gathering loops, hunting circuits, avoid areas), the guide, sessions, and
-- how long the heavy parts take on the full bundled data.

local ns, HME = LoadHME()
local SM, Sk = HME.SkillModel, HME.Skinning
PLAYER.map, PLAYER.x, PLAYER.y = 1429, 0.42, 0.65
MAPS[1429].w, MAPS[1429].h = nil, nil
HME.Player.Refresh()
local profile = HME.Player.Profile()

STEP("skill colors and chances")
eq(SM.Color(1, 1), "orange", "req 1 at 1")
eq(SM.Color(24, 1), "orange", "orange to 24")
eq(SM.Color(25, 1), "yellow", "yellow from 25 (req 1)")
eq(SM.Color(100, 1), "grey", "grey at 100 (req 1)")
eq(SM.Color(150, 150), "orange", "orange at the requirement")
eq(SM.Color(149, 150), "red", "red below it")
eq(SM.Color(250, 150), "grey", "grey at +100")
eq(SM.Chance(160, 150), 1, "orange: always")
near(SM.Chance(212.5, 150), 0.5, 1e-9, "halfway yellow-grey: half")
eq(SM.Chance(250, 150), 0, "grey: never")
eq(SM.Chance(100, 150), 0, "red: can't")

STEP("skinning requirements match the game's rule")
eq(SM.SkinReq(5), 1)
eq(SM.SkinReq(15), 50)
eq(SM.SkinReq(20), 100)
eq(SM.SkinReq(36), 180)
eq(SM.MaxSkinLevel(175), 35, "175 skins up to level 35")
eq(SM.MaxSkinLevel(55), 15, "55 skins up to level 15")

STEP("eligibility for a level-36 hunter with 175 Skinning")
local function Beast(min, max, elite, name) return { npcID = 1, name = name or "Test Wolf", min = min, max = max, elite = elite } end
check(Sk.Eligible(Beast(30, 31), profile).killable, "level 30 wolves: yes")
local e = Sk.Eligible(Beast(36, 37), profile)
check(not e.killable and e.why:find("needs 180"), "level 36-37 needs at least 180 Skinning: " .. tostring(e.why))
check(not Sk.Eligible(Beast(30, 31, true), profile).killable, "elites: no")
local hi = Sk.Eligible(Beast(39, 40), { level = 36, skills = { Skinning = { rank = 300 } } }, "balanced")
check(not hi.killable and hi.why:find("too far above"), "a beast 4 levels up: too dangerous in balanced mode")
check(Sk.Eligible(Beast(38, 39), { level = 36, skills = { Skinning = { rank = 300 } } }, "fastest").killable, "fastest mode allows +3")
HME.db.obs.mobs[1] = false
check(not Sk.Eligible(Beast(30, 31), profile).killable, "a beast the game said can't be skinned: no")
HME.db.obs.mobs[1] = nil

STEP("kill time learns this character's pace, slowly")
local model = Sk.KillSeconds(Beast(36, 36), profile)
near(model, Sk.BASE_KILL * Sk.CLASS_PRIOR.HUNTER, 0.01, "model at equal level, for a hunter")
HME.char.eff.kill = { { d = 0, s = 7 } }
local one = Sk.KillSeconds(Beast(36, 36), profile)
check(one < model and one > 7, "one fast fight moves it a little (" .. one .. ")")
for i = 1, 30 do HME.char.eff.kill[i] = { d = 0, s = 7 } end
local many = Sk.KillSeconds(Beast(36, 36), profile)
check(many < one and many < 9, "thirty fast fights move it a lot (" .. many .. ")")
HME.char.eff.kill = {}

STEP("yields: estimates until skins say otherwise")
local wolf = { npcID = 77, name = "Grey Wolf", min = 30, max = 31 }
local prior = Sk.Yield(wolf)
eq(prior.n, 0, "no skins yet")
check(prior.items[4234] and prior.items[4234] > 0, "Heavy Leather expected at level 30")
check(prior.items[2319] and prior.items[2319] > 0, "Medium Leather too (bands overlap)")
HME.db.obs.skins[77] = { n = 40, qty = { [4234] = 80 }, items = { [4234] = 40 } }
local seen = Sk.Yield(wolf)
check(seen.items[4234] > prior.items[4234], "40 skins of 2 Heavy each pull it up")
check((seen.items[2319] or 0) < prior.items[2319], "and Medium (never seen) down")
eq(seen.basis, "this beast", "says where the numbers come from")
HME.db.obs.skins[77] = nil

STEP("a rare drop seen once doesn't dominate")
HME.Prices.fixed = { [249427] = { low = 1000000, typical = 1000000 }, [4234] = { low = 300, typical = 300 } }
HME.Prices.Invalidate()
HME.db.obs.skins[78] = { n = 50, qty = { [4234] = 60, [249427] = 1 }, items = { [4234] = 50, [249427] = 1 } }
local v, lines = Sk.SkinValue({ npcID = 78, name = "Wolf", min = 30, max = 31 }, "typical")
local rare
for _, l in ipairs(lines) do if l.id == 249427 then rare = l end end
check(rare and rare.weight == 0.5, "seen once, no estimate: counted at half")
HME.db.obs.skins[78] = nil

STEP("profit: materials only vs total, never counted twice")
HME.Prices.fixed = { [4234] = { low = 300, typical = 300 }, [2319] = { low = 100, typical = 100 } }
HME.Prices.Invalidate()
local areas = Sk.Areas(1431, profile, "profit", "balanced")   -- Duskwood
check(#areas > 0, "hunting areas in Duskwood")
local circuit = Sk.Circuit(areas, 1, 650, 3)
HME.settings.profitScope = "skinning"
local m1 = Sk.Evaluate(circuit, profile)
for id in pairs(m1.beasts) do HME.db.obs.loot[id] = { n = 10, copper = 500, vendor = 500 } end
HME.settings.profitScope = "total"
local m2 = Sk.Evaluate(circuit, profile)
HME.settings.profitScope = "skinning"
local m3 = Sk.Evaluate(circuit, profile)
near(m3.gph.typical, m1.gph.typical, 1e-6, "materials only ignores mob loot")
near(m2.gph.typical - m1.gph.typical, math.min(m2.beastsPerHour, m2.supply) * 100, 1e-3,
    "total adds exactly the observed loot (1s a beast), once")
check(m1.beastsPerHour <= m1.supply + 1e-9, "never more beasts than respawns allow")
check(m1.respawnAssumed, "the respawn is flagged as assumed")
for id in pairs(m1.beasts) do HME.db.obs.loot[id] = nil end

STEP("measured rates blend in; one short session doesn't take over")
local key = "Skinning@1431:test"
HME.Learning.AddStats(key, { hours = 0.25, sessions = 1, beasts = 5 })
local r = HME.Learning.Rate(key, "beasts")
check(r, "a measured rate")
local blended = r.blend(200)
check(blended > 150, "15 minutes of 20/h barely moves a 200/h model (" .. blended .. ")")
HME.Learning.AddStats(key, { hours = 5, sessions = 5, beasts = 250 })
blended = HME.Learning.Rate(key, "beasts").blend(200)
check(blended < 80, "five hours of ~50/h does (" .. blended .. ")")
local ratio, sure = HME.Learning.Verdict(key, "beasts", 200)
check(ratio < 0.5 and sure, "and the verdict says it under-delivers")

STEP("risk: labels, territory, guards, deaths; never 'safe'")
local own = HME.Risk.Assess({ mapID = 1429, x = 0.5, y = 0.5, beasts = {} }, { level = 30, faction = "Alliance" })
local enemy = HME.Risk.Assess({ mapID = 1411, x = 0.5, y = 0.5, beasts = {} }, { level = 30, faction = "Alliance" })
check(own.score < enemy.score, "home zone less risky than the other faction's")
eq(own.label, "Lower risk", "the lowest label is 'Lower risk'")
local town = HME.Risk.Assess({ mapID = 1424, x = 0.62, y = 0.20, beasts = {} }, { level = 30, faction = "Alliance" })
local away = HME.Risk.Assess({ mapID = 1424, x = 0.30, y = 0.80, beasts = {} }, { level = 30, faction = "Alliance" })
check(town.score > away.score, "next to Tarren Mill is riskier for Alliance")
for i = 1, 4 do HME.Risk.NoteDeath(1424, 0.30, 0.80) end
local died = HME.Risk.Assess({ mapID = 1424, x = 0.30, y = 0.80, beasts = {} }, { level = 30, faction = "Alliance" })
check(died.score > away.score, "your deaths count")
for _, l in ipairs(HME.Risk.LABELS) do check(not l[2]:lower():find("safe"), "no label says safe") end
HME.db.obs.deaths = {}

STEP("travel: estimates, and unknown when there is no basis")
local same = HME.Geo.TravelTime(1429, 0.4, 0.6, 1429, 0.6, 0.6, { speed = 7 })
check(same and same > 0, "same zone")
local next_ = HME.Geo.TravelTime(1429, 0.4, 0.6, 1436, 0.5, 0.5, { speed = 7 })
check(next_ and next_ > same, "next zone takes longer")
local boat = HME.Geo.TravelTime(1429, 0.4, 0.6, 1440, 0.5, 0.5, { speed = 7, faction = "Alliance" })
check(boat and boat > next_, "another continent: by boat")
local unknown, q = HME.Geo.TravelTime(1429, 0.4, 0.6, 2548, 0.5, 0.5, { speed = 7 })
check(unknown == nil and q == "unknown", "a Forever zone with no links: unknown, not a guess")

STEP("planning a gathering loop from a Farm Finder result")
PROFS[2] = { line = 182, rank = 120, max = 150 }
HME.Player.Refresh()
profile = HME.Player.Profile()
local herbs = HME.Recommend.Find({ prof = "Herbalism", goal = "level" }, nil, profile)
check(#herbs > 0, "herb farms")
local top = herbs[1]
local route = HME.Planner.Create(top, "level")
for _ = 1, 20000 do
    if not route.working then break end
    Tick(0.016)
end
check(not route.working, "the route was worked out in the background")
check(HME.Routes:NodeCount(route) >= 3, "a loop with stops (" .. HME.Routes:NodeCount(route) .. ")")
check(route.planned and route.planned.prof == "Herbalism", "it remembers how it was made")
eq(route.sight, HME.Planner.DETECT, "passes within the detection distance")
local again = HME.Planner.Create(top, "level")
eq(again, route, "the same farm again: the same route, rebuilt, not a copy")
for _ = 1, 20000 do if not route.working then break end Tick(0.016) end

STEP("avoid areas keep the loop out")
local poly = { top.cx - 0.03, top.cy - 0.03, top.cx + 0.03, top.cy - 0.03, top.cx + 0.03, top.cy + 0.03, top.cx - 0.03, top.cy + 0.03 }
HME.Routes:AddTaboo(top.mapID, poly)
for _ = 1, 40000 do
    if not HME.Routes:Busy() and not route.working then break end
    Tick(0.016)
end
local p = route.points
for i = 1, #p - 1, 2 do
    check(not HME.U.InPolygon(poly, p[i], p[i + 1]), "no stop inside the avoid area")
end

STEP("a hunting circuit for skinning")
local hunt = HME.Recommend.Find({ prof = "Skinning", goal = "level" }, nil, profile)
local hroute = HME.Planner.Create(hunt[1], "level")
for _ = 1, 20000 do if not hroute.working then break end Tick(0.016) end
check(HME.Routes:NodeCount(hroute) >= 3, "a circuit through the hunting areas")
check(hroute.planned.areas and #hroute.planned.areas >= 1, "the areas are kept for the map's shading")
eq(hroute.sight, 0, "it goes to each area, not past it")

STEP("the guide notices caps, levels and grey farms")
PROFS[1] = { line = 393, rank = 150, max = 150 }
HME.Player.Refresh()
local st = HME.Guide.Status("Skinning")
eq(st.train, "capped", "skill at the cap")
check(st.messages[1][2]:find("Train Expert"), "says to train: " .. st.messages[1][2])
CHAR.level = 18
PROFS[1] = { line = 393, rank = 130, max = 150 }
HME.Player.Refresh()
st = HME.Guide.Status("Skinning")
eq(st.train, "level", "Expert needs level 20")
check(st.messages[1][2]:find("level 20"), "explains why")
CHAR.level = 36
PROFS[1] = { line = 393, rank = 175, max = 225 }
HME.Player.Refresh()
local grey = HME.Guide.GreyShare({ prof = "Skinning", targets = { { min = 10, max = 11, count = 10 }, { min = 34, max = 35, count = 1 } } }, 175)
check(grey > 0.8, "a farm of level-10 beasts is grey at 175")

STEP("sessions: start by themselves, pause when idle, feed the areas")
HME.Session.Stop("reset")
HME.Signal("GATHER_LOOT", "herb", "Peacebloom", { [2447] = 2 }, {})
check(HME.Session.Current(), "the first gather starts a session")
FAKE_TIME = FAKE_TIME + 120
Tick(1.1)
FAKE_TIME = FAKE_TIME + 400   -- idle
Tick(1.1)
eq(HME.Session.Current().paused, "idle", "paused after 5 idle minutes")
local secs = HME.Session.Elapsed()
check(secs <= 120 + 2, "idle time not counted (" .. secs .. ")")
HME.Signal("GATHER_LOOT", "herb", "Peacebloom", { [2447] = 1 }, {})
check(not HME.Session.Current().paused, "a gather resumes it")
FAKE_TIME = FAKE_TIME + 60
local summary = HME.Session.Stop("manual")
check(summary and summary.counts.herb == 2, "two gathers counted")
check(#HME.db.sessions >= 1, "kept in the history")
local any = false
for k in pairs(HME.db.stats) do if k:find("^Herbalism@") then any = true end end
check(any, "the area's measured totals were updated")

STEP("performance on the full data")
local t0 = os.clock()
HME.Spawns.Invalidate()
for _, prof in ipairs({ "Herbalism", "Mining", "Skinning" }) do
    HME.Recommend.Find({ prof = prof, goal = "profit" }, nil, profile)
end
local took = os.clock() - t0
REAL_PRINT(("  three full Farm Finder searches, cold caches: %.2f s of CPU outside the game"):format(took))
check(took < 6, "fast enough to run in the background in a few seconds")
local job = HME.Recommend.Find({ prof = "Mining", goal = "level" }, function() end, profile)
local frames = 0
while HME.Busy() and frames < 5000 do
    HME.Jobs.budget = 8
    HME.FinishJobs(1)
    frames = frames + 1
end
check(frames > 1, "as a job it is split across frames (" .. frames .. " slices)")
