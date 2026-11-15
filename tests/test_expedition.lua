-- Scenario F: a shopping list across professions and zones becomes a staged
-- expedition; progress is tracked; stages can be skipped, reordered and
-- planned again. Nothing moves the character: "go" starts navigation only.

local ns, HME = LoadHME()
local X = HME.Expedition

local HEAVY, IRON, GOLDTHORN, PEARL = 4234, 2772, 3821, 13926
local profile = { level = 40, faction = "Alliance", class = "HUNTER", speed = 7, mapID = 1453, x = 0.6, y = 0.6,
    skills = { Skinning = { rank = 230, max = 300 }, Mining = { rank = 200, max = 225 }, Herbalism = { rank = 200, max = 225 } },
    zone = "Stormwind City", real = false }

STEP("the rates a farm gives per item")
local res = HME.Recommend.Find({ prof = "Mining", goal = "material", targets = { [IRON] = true } }, nil, profile)
check(#res > 0, "iron farms")
local rates = X.ItemRates(res[1])
check((rates[IRON] or 0) > 0, "iron an hour")

STEP("scenario F: Heavy Leather, Iron Ore and Goldthorn become stages")
local plan = X.Plan({ { itemID = HEAVY, count = 50 }, { itemID = IRON, count = 30 }, { itemID = GOLDTHORN, count = 20 } },
    { profile = profile })
check(#plan.stages >= 2, "more than one stage (" .. #plan.stages .. ")")
local covered = {}
for _, st in ipairs(plan.stages) do
    check(st.hours > 0 and st.hours <= X.MAX_STAGE_HOURS, "each stage has a farming time")
    check(st.travel and st.travel >= 0, "and a travel time")
    for id, n in pairs(st.items) do covered[id] = (covered[id] or 0) + n end
    check(st.confidence, "and how sure")
end
check(covered[HEAVY] and covered[IRON] and covered[GOLDTHORN], "all three are planned")
check(plan.hours > 0, "total farming time")
for _, l in ipairs(X.Lines(plan)) do LOG[#LOG + 1] = l end

STEP("what cannot be gathered by you is listed with the reason")
local p2 = X.Plan({ { itemID = HEAVY, count = 10 }, { itemID = PEARL, count = 3 }, { itemID = 999999, count = 2 } },
    { profile = { level = 40, faction = "Alliance", speed = 7, mapID = 1453, x = 0.6, y = 0.6, real = false,
                  skills = { Skinning = { rank = 230, max = 300 } } } })
local why = {}
for _, m in ipairs(p2.missing) do why[m.itemID] = m.why end
check(why[999999] and why[999999]:find("no gathering profession", 1, true), "unknown item: " .. tostring(why[999999]))
check(#p2.stages >= 1, "the rest still planned")

STEP("a simple one-zone list stays one stage")
local p3 = X.Plan({ { itemID = IRON, count = 5 } }, { profile = profile })
eq(#p3.stages, 1, "one stage")

STEP("start, gather, stage done, next, skip, reorder, replan")
X.Start(plan, "Test list")
local prog = X.Progress()
eq(prog.current, 1)
check(not prog.done)
local first = plan.stages[1]
local got = {}
for id, n in pairs(first.items) do got[id] = n end
HME.Signal("GATHER_LOOT", "mine", "x", got)
HME.Signal("BEAST_SKINNED", 1, got, "Creature-0-1-2-3-1-ABC")
check(plan.stageDoneSaid, "the stage is done and it says so")
local said = false
for _, s in ipairs(HME.Suggest.list) do if s.text:find("stage 1 done", 1, true) then said = true end end
check(said, "with what comes next")
local n0 = #plan.stages
if n0 >= 3 then
    local second = plan.stages[2]
    check(X.Move(2, 1), "reordered")
    eq(plan.stages[3], second)
end
check(X.Skip(n0), "a stage skipped")
eq(#plan.stages, n0 - 1)
local replanned
X.Replan(function(newPlan) replanned = newPlan end)
for _ = 1, 4000 do if replanned then break end HME.FinishJobs() Tick(0.05) end
check(replanned, "planned again for what is left")
for _, st in ipairs(replanned.stages) do
    for id, n in pairs(st.items) do
        if first.items[id] and id ~= nil then check(n <= 60, "only what is still missing") end
    end
end
check(X.Current() == replanned, "the new plan is followed")

STEP("go starts the stage's navigation, nothing more")
local started
local real = HME.Guidance.StartResult
HME.Guidance.StartResult = function(r, goal) started = { r = r, goal = goal } end
X.Go(1)
for _ = 1, 4000 do if started then break end HME.FinishJobs() Tick(0.05) end
HME.Guidance.StartResult = real
check(started and started.goal == "material", "the Farm Finder's way of starting a farm")
X.Stop()
eq(X.Current(), nil)

STEP("travel between two other places never uses the from-here estimate")
HME.Geo.external = function() return 5, "measured" end
local secs, quality = HME.Geo.TravelTime(1429, 0.3, 0.3, 1436, 0.5, 0.5, {})
check(secs ~= 5 and quality ~= "measured", "HME's own estimate between two places")
secs = HME.Geo.TravelTime(1429, 0.3, 0.3, 1436, 0.5, 0.5, { fromPlayer = true })
eq(secs, 5, "Forever-GPS's only from where you stand")
HME.Geo.external = nil

STEP("the Goals page: a shopping list typed in one line, and the expedition card")
local items, unknown = HME.Goals.ParseList("50 Heavy Leather, 30 Iron Ore; goldthorn 20, 5 Unobtainium")
eq(#items, 3, "three materials read")
eq(items[1].itemID, HEAVY)
eq(items[3].itemID, GOLDTHORN)
eq(items[3].target, 20, "the count may come after the name")
eq(unknown[1], "5 Unobtainium", "and what it could not read is said")
local list = HME.Goals.Add({ type = "list", items = items, name = "Trip" })
check(list, "a shopping list goal")
HME.OpenWindow("goals")
X.Start(X.Plan(X.FromGoal(list), { profile = profile }), "Trip")
HME.Signal("EXPEDITION_CHANGED")
check(HME.Window and HME.Window.frame and HME.Window.frame:IsShown(), "the page shows with an expedition running")
X.Stop()
HME.Goals.Remove(list.id)
