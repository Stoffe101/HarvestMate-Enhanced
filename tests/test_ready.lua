-- 0.7.0: the readiness check before a trip, your characters and their
-- professions, a session's path kept for the map, and the optional Copilot
-- line on the HUD.

local ns, HME = LoadHME()
PLAYER.map, PLAYER.x, PLAYER.y = 1424, 0.50, 0.50
CHAR.level = 41
PROFS = { { line = 393, rank = 143, max = 150 } }
HME.Player.Refresh()
local R = HME.Ready

local results = HME.Recommend.Find({ prof = "Skinning", goal = "level" }, nil, HME.Player.Profile())
local farm = results[1]
check(farm, "a skinning farm")

STEP("plenty of room and sound gear: ready")
local FREE = 40
C_Container.GetContainerNumFreeSlots = function() return FREE / 5, 0 end
local DUR = { cur = 90, max = 100 }
function GetInventoryItemDurability(slot) if slot == 5 then return DUR.cur, DUR.max end return nil end
PROFS = { { line = 393, rank = 143, max = 225 } }
HME.Player.Refresh()
local res = R.Check(farm, 1800)   -- a short trip: the rank cap is not reached
eq(res.worst, "ok", "nothing to check: " .. res.summary)
eq(res.summary, "Ready to go")

STEP("bags that fill during the trip")
FREE = 5
res = R.Check(farm, 3 * 3600)
local bags
for _, c in ipairs(res.checks) do if c.key == "bags" then bags = c end end
check(bags and bags.state == "warn" and bags.title:find("Bags full after about"), bags and bags.title)
FREE = 2
res = R.Check(farm, 3600)
eq(res.worst, "stop", "two slots: make room first")

STEP("repairs")
FREE = 40
DUR.cur = 15
res = R.Check(farm, 3600)
local rep
for _, c in ipairs(res.checks) do if c.key == "repair" then rep = c end end
check(rep.state == "warn" and rep.title:find("15%%"), rep.title)
DUR.cur = 0
eq(R.Check(farm, 3600).worst, "stop", "a broken item")
DUR.cur = 90
GetInventoryItemDurability = nil
res = R.Check(farm, 3600)
for _, c in ipairs(res.checks) do check(c.key ~= "repair", "no durability API: no line, not a guess") end

STEP("the rank cap")
PROFS = { { line = 393, rank = 150, max = 150 } }
HME.Player.Refresh()
res = R.Check(farm, 3600)
local cap
for _, c in ipairs(res.checks) do if c.key == "cap" then cap = c end end
check(cap.state == "stop" and cap.title:find("rank cap"), cap.title)
PROFS = { { line = 393, rank = 143, max = 150 } }
HME.Player.Refresh()
res = R.Check(farm, 3 * 3600)
for _, c in ipairs(res.checks) do if c.key == "cap" then cap = c end end
check(cap.state == "warn" and cap.title:find("Rank cap after about"), cap.title)

STEP("the Copilot shows a ready card when something needs a look")
FREE = 2
HME.Copilot.Evaluate(true)
HME.FinishJobs()
HME.Copilot.Evaluate(true)
local card
for _, c in ipairs(HME.Copilot.cards) do if c.type == "ready" then card = c end end
check(card, "a ready card")
check(card.objective:find("free bag slot"), card.objective)
local res2 = HME.Commands and HME.Commands.ready and HME.Commands.ready() or nil
FREE = 40

STEP("your characters: professions remembered, hints from plain arithmetic")
local A = HME.Alts
A.Remember()
local me = HME.Bags.Me()
HME.db.chars["Alt-Realm"] = { level = 30, faction = "Alliance", class = "Rogue", t = REAL_TIME - 3 * 86400,
    profs = { Mining = { rank = 150, max = 150 }, Herbalism = { rank = 40, max = 225 } }, bags = { [2318] = 20 }, bank = { [2319] = 5 } }
HME.db.chars["Low-Realm"] = { level = 15, profs = { Skinning = { rank = 75, max = 75 } }, t = REAL_TIME - 60 }
local list = A.List()
eq(list[1].name, me, "this character first")
check(list[1].profs.Skinning and list[1].profs.Skinning.rank == 143, "your Skinning remembered")
local alt
for _, c in ipairs(list) do if c.name == "Alt-Realm" then alt = c end end
eq(alt.materials, 25, "bags and bank")
local texts = {}
for _, h in ipairs(alt.hints) do texts[#texts + 1] = h.text end
local all = table.concat(texts, " | ")
check(all:find("Mining 150/150: train Expert"), all)
local low
for _, c in ipairs(list) do if c.name == "Low-Realm" then low = c end end
check(low.hints[1].text:find("Journeyman needs level 10") == nil and low.hints[1].text:find("train Journeyman"), low.hints[1].text)
eq(A.ProfText(alt.profs, alt.level), "Herbalism 40/225, Mining 150/150 (train Expert)")
eq(A.ProfText(low.profs, 5), "Skinning 75/75 (Journeyman at level 10)")

STEP("the Stats page lists them")
HME.OpenWindow("stats")
local stats = HME.Window.frame.pages.stats
check(stats, "stats page")

STEP("a session's path: points as you move, events where they happen")
local T = HME.Trail
HME.Session.Start()
RunTimers(0)
check(T.Current() and #T.Current().points == 1, "the start point")
RunTimers(15)
eq(#T.Current().points, 1, "not moved: no new point")
PLAYER.x = 0.52
HME.Player.Refresh()
RunTimers(15)
eq(#T.Current().points, 2, "moved: a point")
HME.Signal("BEAST_SKINNED", 1234, {}, nil)
HME.Signal("GATHER_LOOT", "herb", "Peacebloom", {})
eq(#T.Current().events, 2, "a skin and a herb")
PLAYER.x = 0.55
HME.Player.Refresh()
FAKE_TIME = FAKE_TIME + 700
RunTimers(15)
local cur = HME.Session.Current()
cur.farm = 700
local summary = HME.Session.Stop("manual")
check(summary.trail and summary.trail.p ~= "", "kept with the session")
local data = T.Unpack(summary.trail)
check(#data.points >= 3, "points unpacked")
eq(#data.events, 2)
eq(data.events[1][1], "skin")
check(math.abs(data.points[1][2] - 0.50) < 0.001, "positions survive packing")
local zones = T.Zones(data)
eq(zones[1].mapID, 1424)

STEP("the map shows the path in the session's zone")
WorldMapFrame:Show()
local shownData, zone = T.Show(summary)
eq(zone, 1424)
local col = HME.MapOverlay.Collect(1424)
local open = false
for _, o in ipairs(col.outlines) do if o[3] then open = true end end
check(open, "an open path, not a closed loop")
local dots = 0
for _, p in ipairs(col.pins) do if p[6][1] == "Skinned" or p[6][1] == "Herb gathered" then dots = dots + 1 end end
eq(dots, 2, "a dot per event")
HME.MapOverlay.Draw()
check((HME.MapOverlay.lastCount or 0) >= 1, "drawn (nearby dots may group)")

STEP("only the 5 newest sessions keep a path")
for i = 1, 6 do
    HME.Session.Start()
    RunTimers(0)
    PLAYER.x = 0.4 + i * 0.01
    HME.Player.Refresh()
    RunTimers(15)
    HME.Session.Current().farm = 120
    HME.Session.Stop("manual")
end
local kept = 0
for _, s in ipairs(HME.db.sessions) do if s.trail then kept = kept + 1 end end
eq(kept, T.KEEP, "5 kept")

STEP("the review's button for the path")
local rv = HME.Review.Show(HME.db.sessions[#HME.db.sessions])
local panel = _G.HarvestMateEnhancedReview
if rv then check(panel.path:IsShown(), "Show the path") end

STEP("the HUD's Copilot line: off by default, one line when on")
check(HME.HUD.CopilotLine() == nil, "off: the HUD is as before")
HME.settings.hudCopilot = true
FREE = 2
HME.Copilot.Evaluate(true)
HME.FinishJobs()
HME.Copilot.Evaluate(true)
local line = HME.HUD.CopilotLine()
check(line and line:find("Copilot: "), tostring(line))
HME.settings.hudCopilot = false
FREE = 40
