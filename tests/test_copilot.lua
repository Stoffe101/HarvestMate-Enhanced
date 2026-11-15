-- The Farming Copilot and what it stands on: the prediction ledger (learning
-- from your sessions without chasing lucky streaks), quest synergy from the
-- quest log, bag forecasts, and the Copilot's rules and arbiter (dismissals,
-- one "where" card at a time, no ping-pong, time budgets).

local ns, HME = LoadHME()
PLAYER.map, PLAYER.x, PLAYER.y = 1424, 0.46, 0.42
CHAR.level = 41
PROFS = { { line = 393, rank = 143, max = 225 } }
HME.Player.Refresh()
local Lg, C, Q = HME.Ledger, HME.Copilot, HME.QuestSynergy
local DAY = 86400

local function Session(t, char, areas) return { t = t, char = char, counts = {}, value = 0, areas = areas } end
local function Area(key, secs, skins, predSkins, calib)
    return { key = key, secs = secs, skins = skins, beasts = skins, skillups = 0, value = 0,
        predicted = { skins = predSkins, beasts = predSkins, calib = calib } }
end

STEP("ledger: nothing measured, no factor")
HME.db.sessions = {}
Lg.Forget()
eq(Lg.Factor("Skinning"), nil, "no entries")

STEP("ledger: five lucky skins in a quarter hour barely move it")
HME.db.sessions = { Session(REAL_TIME - DAY, "Tester", { Area("Skinning@1424:9:8", 900, 30, 60) }) }  -- 120/h vs 60/h
Lg.Forget()
local f = Lg.Factor("Skinning")
check(f and f.sessions == 1 and not f.used, "one session: reported, not used")
check(f.factor > 1 and f.factor < 1.15, "shrunk toward 1: " .. f.factor)

STEP("ledger: four hours at 70% of the prediction pull estimates down")
HME.db.sessions = {}
for i = 1, 4 do
    HME.db.sessions[i] = Session(REAL_TIME - i * DAY, "Tester", { Area("Skinning@1424:9:8", 3600, 42, 60) })
end
Lg.Forget()
f = Lg.Factor("Skinning")
check(f.used, "four sessions: used")
near(f.factor, 0.7 ^ (4 / 5.5), 0.02, "weighted, shrunk geometric mean")
check(f.factor > 0.7 and f.factor < 0.85, "between the evidence and the model: " .. f.factor)
check(f.low < f.factor and f.high > f.factor, "a band around it")
check(f.text:find("high for you"), f.text)

STEP("ledger: a session that was already calibrated is judged against the raw model")
HME.db.sessions[5] = Session(REAL_TIME - DAY, "Tester", { Area("Skinning@1424:3:3", 3600, 42, 42, 0.7) })
Lg.Forget()
local entries = Lg.Entries({ key = "Skinning@1424:3:3" })
near(entries[1].ratio, 0.7, 1e-9, "observed 42 against the model's 60, not the shown 42")

STEP("ledger: gold never counts (prices are not predictions)")
HME.db.sessions[6] = Session(REAL_TIME, "Tester", { { key = "Herbalism@1424:1:1", secs = 3600, nodes = 30, value = 500000,
    predicted = { gph = 100000 } } })
Lg.Forget()
eq(#Lg.Entries({ prof = "Herbalism" }), 0, "a gold-only prediction is not an entry")

STEP("ledger: old sessions weigh less than recent ones")
HME.db.sessions = {
    Session(REAL_TIME - 200 * DAY, "Tester", { Area("Skinning@1424:9:8", 3600, 30, 60) }),
    Session(REAL_TIME - 200 * DAY, "Tester", { Area("Skinning@1424:9:8", 3600, 30, 60) }),
    Session(REAL_TIME - DAY, "Tester", { Area("Skinning@1424:9:8", 3600, 60, 60) }),
    Session(REAL_TIME - DAY, "Tester", { Area("Skinning@1424:9:8", 3600, 60, 60) }),
}
Lg.Forget()
f = Lg.Factor("Skinning")
check(f.factor > 0.97, "half-year-old shortfalls fade: " .. f.factor)

STEP("ledger: other characters count half")
HME.db.sessions = {
    Session(REAL_TIME - DAY, "Alt", { Area("Skinning@1424:9:8", 3600, 30, 60) }),
    Session(REAL_TIME - DAY, "Alt", { Area("Skinning@1424:9:8", 3600, 30, 60) }),
}
Lg.Forget()
local alt = Lg.Factor("Skinning")
HME.db.sessions[1].char, HME.db.sessions[2].char = "Tester", "Tester"
Lg.Forget()
local mine = Lg.Factor("Skinning")
check(mine.factor < alt.factor, "own shortfall weighs more")

STEP("ledger: skill-ups need more evidence than pace before they adjust anything")
HME.db.sessions = {}
for i = 1, 3 do
    local a = Area("Skinning@1424:9:8", 3600, 60, 60)
    a.skillups, a.predicted.skill = 20, 50
    HME.db.sessions[i] = Session(REAL_TIME - i * DAY, "Tester", { a })
end
Lg.Forget()
local sk = Lg.Factor("Skinning", "skill")
check(sk and not sk.used, "three sessions of skill-ups: reported, not used")
local a4 = Area("Skinning@1424:9:8", 3600, 60, 60)
a4.skillups, a4.predicted.skill = 20, 50
HME.db.sessions[4] = Session(REAL_TIME - 4 * DAY, "Tester", { a4 })
Lg.Forget()
check(Lg.Factor("Skinning", "skill").used, "four sessions and four hours: used")

STEP("ledger: per-farm report")
HME.db.sessions = {}
for i = 1, 3 do HME.db.sessions[i] = Session(REAL_TIME - i * DAY, "Tester", { Area("Skinning@1424:9:8", 1800, 24, 60) }) end
Lg.Forget()
local a = Lg.Area("Skinning@1424:9:8")
eq(a.sessions, 3)
near(a.ratio, 0.8, 1e-9)
check(Lg.AreaText(a):find("20%% under"), Lg.AreaText(a))

STEP("ledger: the Farm Finder scales unmeasured farms and says so")
HME.db.sessions = {}
for i = 1, 4 do HME.db.sessions[i] = Session(REAL_TIME - i * DAY, "Tester", { Area("Skinning@1424:0:0", 3600, 30, 60) }) end
Lg.Forget()
local profile = HME.Player.Profile()
HME.settings.calibrate = false
local raw = HME.Recommend.Find({ prof = "Skinning", goal = "level" }, nil, profile)
HME.settings.calibrate = nil
local cal = HME.Recommend.Find({ prof = "Skinning", goal = "level" }, nil, profile)
check(#raw > 0 and #cal > 0, "results")
local rawBy = {}
for _, r in ipairs(raw) do rawBy[r.key] = r end
local scaled = 0
for _, r in ipairs(cal) do
    local o = rawBy[r.key]
    if o and r.calibrated then
        scaled = scaled + 1
        near(r.metrics.beastsPerHour / o.metrics.beastsPerHour, r.calibrated.factor, 1e-6, "beasts an hour scaled")
    end
end
check(scaled > 0, "calibrated results: " .. scaled)
-- The engines cache their figures: searching again must not scale them again.
local again1 = HME.Recommend.Find({ prof = "Skinning", goal = "level" }, nil, profile)
local again2 = HME.Recommend.Find({ prof = "Skinning", goal = "level" }, nil, profile)
local by1 = {}
for _, r in ipairs(cal) do by1[r.key] = r.metrics.beastsPerHour end
for _, r in ipairs(again2) do
    if by1[r.key] then near(r.metrics.beastsPerHour, by1[r.key], 1e-6, "no compounding over searches: " .. r.key) end
end
HME.settings.calibrate = false
local back = HME.Recommend.Find({ prof = "Skinning", goal = "level" }, nil, profile)
for _, r in ipairs(back) do
    if rawBy[r.key] then near(r.metrics.beastsPerHour, rawBy[r.key].metrics.beastsPerHour, 1e-6, "switched off: back to the model") end
end
HME.settings.calibrate = nil
HME.Recommend.Find({ prof = "Skinning", goal = "level" }, nil, profile)
check(cal[1].calibrated and cal[1].calibrated.text:find("Skinning"), "explained")
-- What is planned from it records the factor, so the next comparison is fair.
local d = HME.Planner.Describe(cal[1], "level")
near(d.predicted.calib, cal[1].calibrated.factor, 1e-9, "factor stored with the prediction")

STEP("ledger: a farm you measured yourself is not scaled (your numbers already count)")
local key = cal[1].key
HME.char.stats[key] = { hours = 2, sessions = 3, beasts = 100, skins = 100 }
local again = HME.Recommend.Find({ prof = "Skinning", goal = "level" }, nil, profile)
for _, r in ipairs(again) do
    if r.key == key then check(not r.calibrated, "own farm untouched") end
end
HME.char.stats[key] = nil
HME.db.sessions = {}
Lg.Forget()

---------------------------------------------------------------------------
STEP("copilot scenario 1: level 41, Skinning 143, opens HME")
C.ResetFeedback()
C.SetMode("level")
C.SetMinutes(0)
C.Evaluate(true)
HME.FinishJobs()
local cards = C.Evaluate(true)
local top = cards[1]
check(top and top.type == "farm", "a farm first: " .. tostring(top and top.type))
check(top.title:find("^Skinning in "), top.title)
check(top.action and top.action.kind == "farm" and top.action.result, "one click starts it")
check(#top.why >= 1 and top.why[1]:find("Good choice"), "says why")
check(top.conf > 0 and top.conf <= 1, "how sure")
check(top.benefit and top.benefit.text:find("skill%-ups an hour"), top.benefit and top.benefit.text)
check(top.evidence, "evidence text")
local first = top.id

STEP("copilot: the same farm next time (no ping-pong)")
C.Evaluate(true)
eq(C.cards[1].id, first, "held")

STEP("copilot: one where-card only")
local where = 0
for _, c in ipairs(C.cards) do if c.group == "where" then where = where + 1 end end
eq(where, 1)

STEP("copilot: Not now hides that card; the next farm takes its place")
C.Dismiss(C.cards[1])
local second = C.cards[1]
check(second and second.id ~= first and second.type == "farm", "another farm: " .. tostring(second and second.id))
check(HME.char.copilot.dismissed[first] > HME.Now(), "remembered")

STEP("copilot: Not interested hides the kind until reset")
C.Dismiss(C.cards[1], "type")
for _, c in ipairs(C.cards) do check(c.type ~= "farm", "no farm card") end
C.ResetFeedback()
check(C.cards[1].type == "farm", "back after reset")

STEP("copilot scenario 2: 25 minutes, travel counts")
C.SetMinutes(25)
HME.FinishJobs()
C.Evaluate(true)
top = C.cards[1]
eq(top.trip.farmSecs, math.max(0, 25 * 60 - top.trip.travel), "farming time after the trip")
local said = table.concat(top.why, " ")
check(said:find("In 25 minutes"), said)
-- Every other farm gives less in 25 minutes once travel is counted (weighted by evidence).
for _, e in ipairs(C.ctx.ranked or {}) do
    check(e.score <= C.cards[1].trip.value * C.TRUST.measured * 1.15 + 1e-6, "no better trip left out")
end
C.SetMinutes(0)

STEP("copilot: modes give their own picks")
for _, m in ipairs(C.MODES) do
    C.SetMode(m.key)
    HME.FinishJobs()
    local list = C.Evaluate(true)
    check(list[1] ~= nil, m.key .. ": something to say")
end
C.SetMode("proven")
HME.FinishJobs()
C.Evaluate(true)
check(C.cards[1].id:find("^nofarm"), "proven with nothing measured says so")
check(C.cards[1].objective:find("not measured"), C.cards[1].objective)
C.SetMode("level")
HME.FinishJobs()

STEP("copilot scenario 14: a measured farm beats a slightly higher guess")
C.Evaluate(true)
local ranked = C.ctx.ranked
local second2 = ranked[2]
check(second2, "two farms to compare")
HME.char.stats[second2.r.key] = { hours = 3, sessions = 4, beasts = 0, skins = 0, skillups = 0 }
local measuredLvl = { level = "measured", text = "Measured: 4 of your sessions here, 3.0 h." }
second2.r.evidence = measuredLvl
local s1 = C.Choice(ranked[1].r, "level", "level", 3600)
local s2 = C.Choice(second2.r, "level", "level", 3600)
local v1 = C.Trip(ranked[1].r, "level", 3600).value
local v2 = C.Trip(second2.r, "level", 3600).value
if v2 >= v1 * 0.8 / 0.95 * 0.95 then
    check(s2 >= s1 * 0.95 or v2 < v1 * 0.8, "trust weighting favours what you measured")
end
HME.char.stats[second2.r.key] = nil

STEP("copilot: train when capped")
PROFS = { { line = 393, rank = 150, max = 150 } }
HME.Player.Refresh()
C.Invalidate("player")
HME.FinishJobs()
C.Evaluate(true)
local train
for _, c in ipairs(C.cards) do if c.type == "train" then train = c end end
check(train and train.title == "Train Expert Skinning", "train card: " .. tostring(train and train.title))
eq(train.rank, 1, "capped comes first")
check(train.action.kind == "place" or train.action.kind == "page", "go there")
PROFS = { { line = 393, rank = 143, max = 225 } }
HME.Player.Refresh()
C.Invalidate("player")
HME.FinishJobs()

STEP("copilot: a material goal gets a forecast range")
ITEMS[2319] = { name = "Medium Leather", sell = 15 }
local g = HME.Goals.Add({ type = "item", itemID = 2319, target = 40, name = "Medium Leather" })
C.Invalidate("goals")
HME.FinishJobs()
C.Evaluate(true)
local goalCard
for _, c in ipairs(C.cards) do if c.type == "goal" then goalCard = c end end
check(goalCard, "goal card")
check(goalCard.objective:find("40 +to go") or goalCard.objective:find("to go"), goalCard.objective)
check(goalCard.forecast.hours and goalCard.forecast.hours.low <= goalCard.forecast.hours.mid
    and goalCard.forecast.hours.mid <= goalCard.forecast.hours.high, "a range")
HME.Goals.Remove(g.id)
C.Invalidate("goals")

---------------------------------------------------------------------------
STEP("quests: no quest API, no crash, nothing matched")
C_QuestLog = nil
Q.Rebuild()
eq(#Q.index.quests, 0)
check(Q.ForResult({ prof = "Skinning", targets = { { npcID = 1, name = "Gray Bear" } } }) == nil, "nothing")

STEP("quests: the log's objective text names a creature")
local LOG_QUESTS = {
    { questID = 501, title = "Bear Necessities", objectives = { { text = "Gray Bear slain: 3/8", type = "monster", finished = false, numFulfilled = 3, numRequired = 8 } } },
    { questID = 502, title = "Done Already", objectives = { { text = "Mountain Lion slain: 6/6", type = "monster", finished = true } } },
}
C_QuestLog = {
    GetNumQuestLogEntries = function() return #LOG_QUESTS end,
    GetInfo = function(i) local q = LOG_QUESTS[i] return q and { questID = q.questID, title = q.title, isHeader = false } end,
    GetQuestObjectives = function(id) for _, q in ipairs(LOG_QUESTS) do if q.questID == id then return q.objectives end end end,
    IsComplete = function() return false end,
}
Q.Rebuild()
eq(#Q.index.quests, 2)
local m = Q.ForResult({ prof = "Skinning", targets = { { npcID = 2351, name = "Gray Bear" }, { npcID = 2385, name = "Mountain Lion" } } })
check(m and #m == 1 and m[1].questID == 501, "only the unfinished objective")
eq(m[1].source, "log", "from the quest text")
check(Q.Text(m):find("Bear Necessities %(Gray Bear slain: 3/8%)"), Q.Text(m))

STEP("quests: Questie's ids (read-only) match by creature, and item drops")
QuestieLoader = { ImportModule = function(_, name)
    if name ~= "QuestieDB" then return nil end
    return {
        QueryQuestSingle = function(id, field)
            if id == 501 and field == "objectives" then return { { { 2351, "Gray Bear" } } } end
            if id == 503 and field == "objectives" then return { nil, nil, { { 4582, "Soft Bushy Tail" } } } end
        end,
        QueryItemSingle = function(id, field) if id == 4582 and field == "npcDrops" then return { 2350 } end end,
    }
end }
LOG_QUESTS[3] = { questID = 503, title = "Tails", objectives = { { text = "Soft Bushy Tail: 1/10", type = "item", finished = false } } }
Q.Forget()
Q.Rebuild()
m = Q.ForCreature(2350, "Forest Moss Creeper")
check(#m == 1 and m[1].questID == 503 and m[1].source == "questie", "drops lead to the creature")
m = Q.ForCreature(2351, nil)
check(#m == 1 and m[1].questID == 501, "creature id from Questie")

STEP("quests: Questie's runtime ObjectiveData (kill credit lists too)")
QuestieLoader = { ImportModule = function(_, name)
    if name ~= "QuestieDB" then return nil end
    return {
        QueryQuestSingle = function() return nil end,
        QueryItemSingle = function() return nil end,
        GetQuest = function(id)
            if id == 501 then return { ObjectiveData = { { Type = "killcredit", IdList = { 7001, 7002 }, Text = "Bears" } } } end
        end,
    }
end }
Q.Forget()
Q.Rebuild()
check(#Q.ForCreature(7002) == 1, "kill credit ids count")

STEP("quests: Forever-GPS's API wins when it has the answer")
ForeverGPS = { API = { QuestObjectiveTargets = function(id)
    if id == 501 then return { { kind = "monster", ids = { 9999 } } } end
    return {}
end } }
Q.Rebuild()
check(#Q.ForCreature(9999) == 1, "id from Forever-GPS")
ForeverGPS = nil
QuestieLoader = nil
Q.Forget()

STEP("quests: a broken Questie fails quietly")
QuestieLoader = { ImportModule = function() error("changed") end }
Q.Forget()
Q.Rebuild()
check(Q.Status():find("quests read"), Q.Status())
QuestieLoader = nil
Q.Forget()

STEP("copilot scenario 3: a quest farm says so")
local hunt = HME.Recommend.Find({ prof = "Skinning", goal = "level" }, nil, HME.Player.Profile())
local bear
for _, r in ipairs(hunt) do
    for _, t in ipairs(r.targets or {}) do if not bear and t.name then bear = { r = r, t = t } end end
end
LOG_QUESTS = { { questID = 601, title = "Cull the Herd", objectives = { { text = bear.t.name .. " slain: 0/10", type = "monster", finished = false } } } }
Q.Rebuild()
check(Q.ForResult(bear.r), "the farm serves the quest")
C.SetMode("quest")
HME.FinishJobs()
C.Evaluate(true)
check(C.cards[1].type == "farm" and table.concat(C.cards[1].why, " "):find("Also progresses: Cull the Herd"),
    "quest mode picks it and says why")
C.SetMode("level")
HME.FinishJobs()
C.Evaluate(true)
local qc
for _, c in ipairs(C.cards) do if c.type == "quest" then qc = c end end
check(qc and qc.objective:find("Cull the Herd"), "level mode still mentions it as a side card")
C_QuestLog = nil
Q.Rebuild()

---------------------------------------------------------------------------
STEP("bags: an estimate from gathered materials, then a measured rate")
local FREE = 10
C_Container.GetContainerNumFreeSlots = function(bag) return bag == 0 and FREE or 0, 0 end
HME.Session.Start()
local live = { farmSecs = 300, items = { { id = 2318, perHour = 120 } } }
local fc = HME.Bags.Forecast(live)
check(fc and fc.basis == "estimated", "estimated first")
-- 120 an hour, 20 a stack: 6 slots an hour -> 10 slots in about 100 minutes
check(fc.minutes > 80 and fc.minutes < 120, "about 100 minutes: " .. tostring(fc.minutes))
check(fc.low < fc.minutes and fc.high > fc.minutes, "a range")
HME.Bags.Reset()
local cur = HME.Session.Current()
cur.farm = 0
FireEvent("BAG_UPDATE_DELAYED") RunTimers(2)
cur.farm, FREE = 900, 6
FireEvent("BAG_UPDATE_DELAYED") RunTimers(2)
fc = HME.Bags.Forecast({ farmSecs = 900, items = {} })
eq(fc.basis, "measured")
near(fc.minutes, 6 / 16 * 60, 0.5, "4 slots in 15 minutes: 16 an hour")
HME.Session.Stop("test")

STEP("bags: characters' materials, with their age")
HME.db.chars = { ["Alt-Realm"] = { bags = { [2318] = 12 }, bagsAt = REAL_TIME - 3 * DAY, bank = { [2318] = 40 }, bankAt = REAL_TIME - 3 * DAY } }
local lines = HME.Bags.MaterialLines(2318)
check(lines[1] and lines[1]:find("^Alt: 12 in bags, 40 in the bank %(3 d"), tostring(lines[1]))

---------------------------------------------------------------------------
STEP("copilot scenario 5: below prediction for long enough suggests a switch")
C.Evaluate(true)
local results = C.ctx.results
local rule
for _, r in ipairs(C.rules) do if r.id == "where-live" then rule = r end end
local out = {}
-- (The fixture's best farms are an hour's trip away: a two-hour plan leaves time to switch.)
local ctx = { farming = true, guidance = { key = results[1].key, name = "Here" }, results = results, goal = "level", budget = 7200,
    prof = "Skinning", live = { farmSecs = 1500, verdict = { enough = true, ratio = 0.4, text = "40% of the prediction" } } }
rule.run(ctx, function(c) out[#out + 1] = c end)
check(out[1] and out[1].type == "switch", "switch: " .. tostring(out[1] and out[1].type))
check(out[1].action.result.key ~= results[1].key, "to another farm")
out = {}
ctx.live.verdict.ratio = 0.9
rule.run(ctx, function(c) out[#out + 1] = c end)
eq(out[1].type, "stay", "near the prediction: keep going")
out = {}
ctx.live.verdict.ratio, ctx.live.farmSecs = 0.4, 400
rule.run(ctx, function(c) out[#out + 1] = c end)
eq(out[1].type, "stay", "too early to judge after 7 minutes")

STEP("copilot: the arbiter keeps one card per group, highest priority")
C.Rule({ id = "test-conflict", run = function(_, add)
    add({ id = "t1", type = "test", group = "where", priority = 99, title = "A" })
    add({ id = "t2", type = "test", group = "where", priority = 98, title = "B" })
end })
C.Evaluate(true)
local n = 0
for _, c in ipairs(C.cards) do if c.group == "where" then n = n + 1 eq(c.id, "t1") end end
eq(n, 1)
table.remove(C.rules)
C.Evaluate(true)

STEP("copilot: actions run only what they say")
local started
local orig = HME.Guidance.StartResult
HME.Guidance.StartResult = function(r) started = r end
C.Run(C.cards[1].action)
check(started == C.cards[1].action.result, "starts that farm")
HME.Guidance.StartResult = orig
check(not C.Run({ kind = "nonsense" }), "unknown action does nothing")

STEP("copilot: a full search cache never evicts the result it just stored (no endless re-search)")
C.searches = {}
-- (Their time is later than now, so the fresh result is the "oldest" one: what
-- equal times did by chance in the benchmark that hung.)
for i = 1, C.MAX_CACHED do C.searches["old" .. i] = { results = {}, at = HME.Now() + 1000 } end
local before = HME.Recommend.Find
local calls = 0
HME.Recommend.Find = function(...) calls = calls + 1 return before(...) end
C.Evaluate(true)
local steps = HME.FinishJobs(2000)
HME.Recommend.Find = before
check(steps < 2000, "the job queue empties: " .. steps .. " steps")
check(calls <= 3, "searched a few times, not forever: " .. calls)
check(C.ctx.sig and C.searches[C.ctx.sig], "the fresh result stays cached")
local n = 0
for _ in pairs(C.searches) do n = n + 1 end
check(n <= C.MAX_CACHED, "bounded: " .. n)
