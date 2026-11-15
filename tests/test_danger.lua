-- 0.7.0: your danger map (players seen, deaths with an enemy in sight, time
-- per zone), how it feeds risk and the Copilot, price trends from HME's own
-- daily log, and the map's danger and quest layers.

local ns, HME = LoadHME()
PLAYER.map, PLAYER.x, PLAYER.y = 1424, 0.50, 0.50   -- Hillsbrad Foothills
CHAR.level = 41
PROFS = { { line = 393, rank = 143, max = 150 } }
HME.Player.Refresh()
local D = HME.Danger

-- A stand-in for the client's unit functions.
local UNITS = {}
function UnitIsPlayer(u) return UNITS[u] ~= nil end
function UnitIsUnit(a, b) return a == b end
function UnitIsEnemy(_, u) return UNITS[u] and UNITS[u].enemy or false end
function UnitGUID(u) return UNITS[u] and UNITS[u].guid end
function UnitInParty(u) return UNITS[u] and UNITS[u].party or false end
function IsInInstance() return INSTANCE == true end

STEP("players seen are recorded where you stand, once per player per 10 minutes")
UNITS.nameplate1 = { enemy = true, guid = "Player-1-AAA" }
HME.Fire("NAME_PLATE_UNIT_ADDED", "nameplate1")
HME.Fire("NAME_PLATE_UNIT_ADDED", "nameplate1")
local z = D.Zone(1424)
eq(z.enemies, 1, "one enemy, counted once")
UNITS.target = { enemy = false, guid = "Player-1-BBB" }
HME.Fire("PLAYER_TARGET_CHANGED")
eq(D.Zone(1424).friends, 1, "a friendly player you targeted")
UNITS.nameplate2 = { enemy = false, guid = "Player-1-CCC", party = true }
HME.Fire("NAME_PLATE_UNIT_ADDED", "nameplate2")
eq(D.Zone(1424).friends, 1, "your party is not counted")
UNITS.nameplate3 = nil
HME.Fire("NAME_PLATE_UNIT_ADDED", "nameplate3")
eq(D.Zone(1424).enemies + D.Zone(1424).friends, 2, "a creature's nameplate is not a player")
INSTANCE = true
UNITS.nameplate4 = { enemy = true, guid = "Player-1-DDD" }
HME.Fire("NAME_PLATE_UNIT_ADDED", "nameplate4")
INSTANCE = false
eq(D.Zone(1424).enemies, 1, "nothing inside instances")
FAKE_TIME = FAKE_TIME + 601
HME.Fire("NAME_PLATE_UNIT_ADDED", "nameplate1")
eq(D.Zone(1424).enemies, 2, "the same player again after 10 minutes")

STEP("a secret answer is not counted")
local realBool = HME.Bool
HME.Bool = function(v) if v == "secret" then return nil end return realBool(v) end
UnitIsEnemy = function() return "secret" end
UNITS.nameplate5 = { guid = "Player-1-EEE" }
check(not D.Seen("nameplate5"), "skipped")
HME.Bool = realBool
UnitIsEnemy = function(_, u) return UNITS[u] and UNITS[u].enemy or false end

STEP("time in the zone makes it an hour")
check(D.Zone(1424).enemiesPerHour == nil, "no rate under half an hour")
HME.Fire("PLAYER_ENTERING_WORLD")
for _ = 1, 120 do RunTimers(30) end   -- an hour in 30-second steps
z = D.Zone(1424)
check(z.hours > 0.9 and z.hours < 1.1, ("about an hour (%.2f)"):format(z.hours))
check(z.enemiesPerHour and z.enemiesPerHour > 1.5 and z.enemiesPerHour < 2.5, "about 2 enemies an hour")
check(z.text:find("enemy players seen in 1.0 h"), z.text)

STEP("a death just after an enemy was seen is marked, not called a kill")
FAKE_TIME = FAKE_TIME + 700
UNITS.nameplate6 = { enemy = true, guid = "Player-1-FFF" }
HME.Fire("NAME_PLATE_UNIT_ADDED", "nameplate6")
FAKE_TIME = FAKE_TIME + 10
HME.Fire("PLAYER_DEAD")
local deaths = HME.db.obs.deaths
check(deaths[#deaths].pvp == true, "enemy in sight")
FAKE_TIME = FAKE_TIME + 120
HME.Fire("PLAYER_DEAD")
check(deaths[#deaths].pvp == nil, "two minutes later: no enemy in sight")
z = D.Zone(1424)
eq(z.deaths, 2)
eq(z.inSight, 1)
check(z.text:find("you died here 2 times, 1 with an enemy in sight"), z.text)

STEP("enemies an hour raise the zone's risk only with enough time there")
local area = { mapID = 1424, x = 0.5, y = 0.5, radius = 150, beasts = {} }
local before = HME.Risk.Assess(area, HME.Player.Profile())
for i = 1, 12 do D.Note(1424, 0.5, 0.5, true, "Player-2-" .. i) end
local after = HME.Risk.Assess(area, HME.Player.Profile())
check(after.score > before.score, ("riskier: %.2f > %.2f"):format(after.score, before.score))
check(after.score <= 1, "at most 1")
local said = false
for _, r in ipairs(after.reasons) do if r:find("enemy players an hour") then said = true end end
check(said, "says why")
local other = HME.Risk.Assess({ mapID = 1436, x = 0.5, y = 0.5, radius = 150, beasts = {} }, HME.Player.Profile())
check(other.parts.enemies == nil, "a zone you have not spent time in: no figure")

STEP("the Copilot says so where you keep meeting enemies")
HME.Copilot.Evaluate(true)
HME.FinishJobs()
HME.Copilot.Evaluate(true)
local card
for _, c in ipairs(HME.Copilot.cards) do if c.type == "danger" then card = c end end
check(card, "a danger card")
check(card and card.action and card.action.mode == "safe", "its button shows lower-risk farms")
HME.Copilot.Run(card.action)
eq(HME.Copilot.Mode(), "safe", "mode switched")
HME.Copilot.SetMode("level")

STEP("the map's danger layer: deaths as pins, enemy spots shaded, the zone summary")
WorldMapFrame:Show()
WorldMapFrame:SetMapID(1424)
local O = HME.MapOverlay
check(not O.LayersOn(), "off by default")
O.SetLayer("danger", true)
local data = O.Collect(1424)
local deathPins, discs = 0, #data.discs
for _, p in ipairs(data.pins) do if p[6][1] == "You died here" then deathPins = deathPins + 1 end end
eq(deathPins, 2, "two death pins")
check(discs >= 1, "enemy spots shaded")
local summary = false
for _, l in ipairs(data.labels) do if l[3]:find("enemy players seen") then summary = true end end
check(summary, "the zone's summary on the map")
O.Draw()
check(O.lastCount >= 1, "drawn without a farm previewed")
O.SetLayer("danger", false)

STEP("the quest layer: creatures your objectives name")
local QS = HME.QuestSynergy
local idx = QS.Creatures()
local beasts = HME.Spawns.BeastPoints(1424)
check(#beasts > 0, "beasts in Hillsbrad")
idx[beasts[1].npcID] = { { questID = 1, title = "Test Hunt", text = beasts[1].name .. " slain: 0/8" } }
O.SetLayer("quests", true)
data = O.Collect(1424)
local qp = 0
for _, p in ipairs(data.pins) do if p[6][2] and p[6][2]:find("Test Hunt") then qp = qp + 1 end end
eq(qp, #beasts[1].pts, "a gold pin per spawn point of that creature")
idx[beasts[1].npcID] = nil
O.SetLayer("quests", false)

STEP("Forget learned data forgets players seen and time")
HME.DBM.ResetLearned()
eq(D.Zone(1424).enemies, 0)
eq(D.Zone(1424).hours, 0)

---------------------------------------------------------------------------
STEP("price trends: one point a day, a trend from 3 days")
local Tr = HME.Trends
local leather = 2318   -- Light Leather
check(ns.itemIndex[leather], "a known material")
local day0 = REAL_TIME
local function Seen(days, typical, low)
    REAL_TIME = day0 + days * 86400
    Tr.Note(leather, { typical = typical, low = low or typical })
end
Seen(0, 100)
Seen(0, 110, 90)
local t = Tr.Of(leather)
eq(t.days, 1, "one point for the day")
eq(t.points[1].low, 90, "the day's lowest")
eq(t.points[1].typical, 110, "the latest typical")
check(t.trend == nil and t.text:find("a trend needs 3"), t.text)
Seen(1, 100)
Seen(2, 105)
Seen(3, 130)
t = Tr.Of(leather)
eq(t.trend, "up")
check(t.change > 0.2, "up over 20%")
check(t.text:find("listings, not sales"), "says what it is")
check(Tr.Advice(t):find("good time to list"), "advice, not an order")
Seen(4, 80)
eq(Tr.Of(leather).trend, "down")
Seen(5, 106)
eq(Tr.Of(leather).trend, "steady")

STEP("stale prices and items HME does not know are not logged")
check(not Tr.Note(leather, { typical = 500, age = 3 * 86400 }), "a 3-day-old price is not today's")
check(not Tr.Note(999999, { typical = 500 }), "not a gathering material")

STEP("21 days kept")
for d = 6, 40 do Seen(d, 100 + d) end
check(Tr.Of(leather).days <= Tr.DAYS, "at most 21 days")

STEP("Forever-GPS's own history comes first when it has one")
ForeverGPS = { PriceHistory = { Of = function(id)
    if id ~= leather then return {} end
    return { { day = 1, low = 50 }, { day = 2, low = 50 }, { day = 3, low = 80 } } end } }
t = Tr.Of(leather)
eq(t.source, "Forever-GPS's daily scans")
eq(t.trend, "up")
ForeverGPS = nil

STEP("the Materials page's advice shows the trend")
local lines = HME.Economy.Lines(leather)
local trendLine = false
for _, l in ipairs(lines) do if l:find("Trend") then trendLine = true end end
check(trendLine, "a trend line")

STEP("the Copilot's market card for a material in your bags")
local me = HME.Bags.Me()
HME.db.chars = HME.db.chars or {}
HME.db.chars[me] = { bags = { [leather] = 40 } }
Seen(41, 300)
HME.Copilot.Evaluate(true)
local m
for _, c in ipairs(HME.Copilot.cards) do if c.type == "market" then m = c end end
check(m and m.title:find("selling high"), "a market card: " .. tostring(m and m.title))
check(m.why[3]:find("never lists"), "HME never trades")
HME.Copilot.Run(m.action)
REAL_TIME = day0
