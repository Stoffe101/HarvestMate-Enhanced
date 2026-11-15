-- Notifications, the session review and the universal search (0.6.0).

local ns, HME = LoadHME()
PLAYER.map, PLAYER.x, PLAYER.y = 1424, 0.46, 0.42
CHAR.level = 41
PROFS = { { line = 393, rank = 143, max = 225 } }
HME.Player.Refresh()
local N, F = HME.Notify, HME.Find

STEP("notify: categories decide chat; repeats are held back")
N.Clear()
ClearLog()
check(N.Push("goal", "g1", "Goal reached: Medium Leather."), "pushed")
check(Said("Goal reached"), "goals say themselves in chat by default")
check(not N.Push("goal", "g1", "Goal reached again."), "the same notice within 30 minutes is held back")
ClearLog()
RunTimers(70)
check(N.Push("farm", "f1", "A better farm."), "farm notice listed")
check(not Said("A better farm"), "farm notices are quiet by default")
N.SetPref("farm", "off")
check(not N.Push("farm", "f2", "Off."), "off: nothing")
N.SetPref("farm", nil)
eq(N.Unread(), 2)
N.MarkRead()
eq(N.Unread(), 0)

STEP("notify: Suggest lands in the list, its category decides chat")
ClearLog()
RunTimers(70)
HME.Suggest.Add("betterArea", "zz", "You measured more elsewhere.")
check(not Said("You measured more"), "farm kind: quiet")
local last = N.List()[#N.List()]
eq(last.cat, "farm")
RunTimers(70)
HME.Suggest.Add("nearCap", "Skinning225", "Skinning is near its cap.", { kind = "trainers", prof = "Skinning" })
check(Said("near its cap"), "training: in chat")

STEP("notify: bounded, actions work until reload")
for i = 1, 60 do N.Push("data", "k" .. i, "Note " .. i) end
eq(#N.List(), N.KEEP, "newest 40 kept")
local ran
local n = N.Push("bags", "bag", "Bags.", { kind = "page", page = "stats", label = "Stats" })
check(N.Action(n), "action kept in memory")
check(N.Run(n), "runs")
eq(HME.Window.frame.currentTab, "stats", "opened the page")

STEP("review: built from a session, with prediction and recent sessions")
HME.db.sessions = {}
for i = 1, 5 do
    HME.db.sessions[i] = { t = REAL_TIME - i * 86400, farmSecs = 1800, secs = 1800, value = 50000, skillups = 15, counts = { skin = 30, kills = 32 },
        items = { [2318] = 20 } }
end
local summary = { t = REAL_TIME, farmSecs = 2400, secs = 2400, travelSecs = 300, idleSecs = 60, value = 90000, skillups = 30,
    counts = { skin = 48, kills = 50, herb = 0, mine = 0, fish = 0 }, items = { [2318] = 30, [2319] = 12 }, deaths = 1,
    areas = { { key = "Skinning@1424:3:10", secs = 2400, skins = 48, beasts = 50, predicted = { skins = 60, beasts = 60 } } } }
local r = HME.Review.Build(summary)
check(r.title:find("40 min"), r.title)
eq(r.tiles[2].value, "48", "skins")
eq(r.tiles[3].value, "30", "skill-ups")
local text = table.concat(r.lines, "\n")
check(text:find("75 skins an hour against 60 predicted"), text)
check(text:find("your best of them"), "best of the last sessions")
check(text:find("Deaths"), "deaths said")
check(r.tiles[4].sub:find("estimate") and text:find("not money received"), "value is an estimate")

STEP("review: stopping yourself opens it; idle endings only notify")
HME.Session.Start()
local cur = HME.Session.Current()
cur.farm = 900
cur.counts.skin = 10
local shown
local orig = HME.Review.Show
HME.Review.Show = function(s) shown = s end
HME.Session.Stop("manual")
RunTimers(1)
check(shown and shown.farmSecs >= 900, "opened after Stop farming")
shown = nil
HME.Session.Start()
HME.Session.Current().farm = 900
HME.Session.Stop("idle")
RunTimers(1)
eq(shown, nil, "an idle ending does not pop up")
HME.Review.Show = orig
check(N.List()[#N.List()].cat == "session", "the review waits in the list")

STEP("review panel builds")
check(HME.Review.Show(summary), "panel")
check(_G.HarvestMateEnhancedReview:IsShown(), "shown")

STEP("search: kinds, order, open")
ITEMS[2319] = { name = "Medium Leather" }
local list = F.Run("medium")
check(#list > 0, "found")
local kinds = {}
for _, x in ipairs(list) do kinds[x.kind] = true end
check(kinds.material, "the material")
list = F.Run("bloodwing")
eq(list[1].kind, "creature")
check(F.Open(list[1]), "opens")
eq(HME.Window.frame.currentTab, "beasts", "in the Explorer")
list = F.Run("artisan skin")
eq(list[1].kind, "milestone")
list = F.Run("copilot")
eq(list[1].kind, "page")
F.Open(list[1])
eq(HME.Window.frame.currentTab, "copilot")
eq(#F.Run("x"), 0, "one letter: nothing")
check(#F.Run("e") == 0 and #F.Run("zzzzqq") == 0, "nothing for nonsense")
check(#F.Run("a") == 0, "short")
local all = F.Run("an")
check(#all <= F.MAX, "fourteen at most")

STEP("search box and bell sit in the header")
HME.OpenWindow("dashboard")
RunTimers(1)
check(HME.Header.box and HME.Header.bell, "attached")
HME.Header.box:SetText("medium")
HME.Header.box:GetScript("OnTextChanged")(HME.Header.box)   -- (the stand-in client does not fire it on SetText)
RunTimers(1)
check(_G.HarvestMateEnhancedSearch and _G.HarvestMateEnhancedSearch:IsShown(), "results shown")
HME.Header.ShowBell(HME.Window.frame)
check(_G.HarvestMateEnhancedNotices:IsShown(), "bell list shown")
eq(N.Unread(), 0, "opening it marks read")
local pop = _G.HarvestMateEnhancedNotices
check(pop.close and pop.close:IsShown(), "a close button")
Click(pop.close)
check(not pop:IsShown(), "× closes it")
Click(HME.Header.bell)
check(pop:IsShown(), "the bell opens it")
Click(HME.Header.bell)
check(not pop:IsShown(), "the bell again closes it")

STEP("slash: find, review, notices")
ClearLog()
SlashCmdList.HARVESTMATEENHANCED("find stranglethorn")
check(Said("found"), "find")
SlashCmdList.HARVESTMATEENHANCED("notices")
SlashCmdList.HARVESTMATEENHANCED("review")
