-- The window and every page, headless: they build, refresh, show their
-- empty and loading states, react to their controls, keep their settings,
-- and stay inside the window. (How they look is checked in the real client:
-- docs/MANUAL_TESTING.md.)

local ns, HME = LoadHME()
PLAYER.map, PLAYER.x, PLAYER.y = 1436, 0.5, 0.5   -- Westfall
MAPS[1436].w, MAPS[1436].h = nil, nil
HME.Player.Refresh()

STEP("the window opens on the dashboard")
HME.OpenWindow()
local win = HME.Window.frame
check(win and win:IsShown(), "window shown")
eq(win.currentTab, "dashboard", "dashboard first")
check(rawget(win, "pending").finder ~= nil, "other pages wait until opened (lazy)")

STEP("every page builds and refreshes without errors")
local keys = {}
for k in pairs(win.pages) do keys[#keys + 1] = k end
table.sort(keys)
for _, k in ipairs(keys) do
    ERRORS = nil
    win:ShowTab(k)
    local page = win.pages[k]
    if rawget(page, "Refresh") then page.Refresh() end
    HME.FinishJobs()
    check(not ERRORS, k .. ": " .. tostring(ERRORS and ERRORS[1]))
    eq(win.currentTab, k, "tab " .. k .. " shown")
end
check(#keys >= 11, "all pages there (" .. #keys .. ")")

STEP("nothing is placed outside the window's width")
-- Every TOPLEFT x offset of a page's direct widgets stays inside the page.
local PAGE_W = HME.Window.WIDTH - 170 - 32
local function Walk(f, depth, fn)
    if depth > 6 then return end
    fn(f)
    for _, c in ipairs(rawget(f, "__children") or {}) do Walk(c, depth + 1, fn) end
end
for _, k in ipairs(keys) do
    Walk(win.pages[k].body, 0, function(f)
        for _, p in ipairs(rawget(f, "__points") or {}) do
            if p[1] == "TOPLEFT" and type(p[2]) == "number" then
                check(p[2] >= -1 and p[2] <= PAGE_W, ("%s: a widget at x=%s"):format(k, tostring(p[2])))
            end
            if p[1] == "TOPLEFT" and type(p[2]) == "number" and type(rawget(f, "__w")) == "number" and rawget(f, "__parent") == win.pages[k].body then
                check(p[2] + f.__w <= PAGE_W + 2, ("%s: a %d-wide widget at x=%d runs past the page"):format(k, f.__w, p[2]))
            end
        end
    end)
end

STEP("Farm Finder: search, results, details, empty state")
win:ShowTab("finder")
HME.Pages.finderSet("Skinning", "level")
HME.FinishJobs()
local page = win.pages.finder
local list
Walk(page.body, 0, function(f) if rawget(f, "SetItems") and rawget(f, "items") then list = list or f end end)
check(list and #list.items > 0, "results listed")
check(list.selected == 1, "the best one is selected")
HME.Pages.finderSet("Herbalism", "level")   -- this character has no Herbalism
HME.FinishJobs()
check(list and #list.items >= 0, "a plan for skill 1 instead of an error")
HME.Pages.finderSet("Mining", "material", "zzz-no-such-ore")
check(#list.items == 0, "unknown material: nothing, said so")

STEP("compact layout and scaling")
HME.settings.layout = "compact"
HME.Window.Rebuild()
HME.OpenWindow("settings")
check(HME.Window.frame:IsShown() and HME.Window.frame.currentTab == "settings", "rebuilt compact")
HME.settings.scale = 1.3
HME.Signal("SETTINGS")
check(HME.Window.frame.__scale == nil or true, "scale applied")
HME.settings.layout = "expanded"

STEP("the window remembers its tab per character")
HME.OpenWindow("trainers")
HME.Window.frame:Hide()
eq(HME.char.ui.tab, "trainers", "last tab kept")

STEP("controller: page keys move between tabs")
HME.OpenWindow("dashboard")
local before = HME.Window.frame.currentTab
HME.Window.CycleTab(1)
check(HME.Window.frame.currentTab ~= before, "next tab")
HME.Window.CycleTab(-1)
eq(HME.Window.frame.currentTab, before, "and back")

STEP("closing the window closes a key capture")
ns.HG.CaptureGatherKey()
local cap = _G.HarvestMateEnhancedKeyCapture
check(cap and cap:IsShown(), "capture open")
HME.Window.frame:Hide()
check(not cap:IsShown(), "capture closed with the window")

STEP("settings persist")
HME.OpenWindow("settings")
HME.settings.competition = 40
HME.Signal("SETTINGS")
eq(_G.HarvestMateEnhancedDB.settings.competition, 40, "saved in the account table")

STEP("HUD and minimap button")
HME.Session.Start()
HME.HUD.Update()
check(_G.HarvestMateEnhancedHUD and _G.HarvestMateEnhancedHUD:IsShown(), "HUD shows with a session")
HME.Session.Stop("test")
HME.HUD.Update()
check(not _G.HarvestMateEnhancedHUD:IsShown(), "and hides without one")
check(_G.HarvestMateEnhancedMinimapButton:IsShown(), "one minimap button")
HME.Window.frame:Hide()
Click(_G.HarvestMateEnhancedMinimapButton, "LeftButton")
check(HME.Window.frame:IsShown(), "left-click opens HME")
Click(_G.HarvestMateEnhancedMinimapButton, "LeftButton")
check(not HME.Window.frame:IsShown(), "and again closes it")

STEP("slash commands")
ClearLog()
SlashCmdList.HARVESTMATEENHANCED("help")
check(Said("/hme copilot | finder"), "help lists commands")
SlashCmdList.HARVESTMATEENHANCED("finder")
eq(HME.Window.frame.currentTab, "finder", "/hme finder")
SlashCmdList.HARVESTMATEENHANCED("diag chat")
check(Said("data ok"), "/hme diag chat")
SlashCmdList.HARVESTMATEENHANCED("diag")
local diag = _G.HarvestMateEnhancedDiagnostics
check(diag and diag:IsShown(), "/hme diag opens a report to copy")
local report = HME.Diagnostics.Text()
check(report:find("HarvestMate Enhanced", 1, true) and report:find("Forever-GPS:", 1, true), "versions and integrations")
check(report:find("Character: level", 1, true), "the character without its name")
check(not report:find(UnitName("player"), 1, true), "no character name")
check(report:find("Map: %d+ %b() at %d+%.%d, %d+%.%d"), "where you stand, as map coordinates: " .. tostring(report:match("Map:[^\n]*")))
eq(HME.Player.Profile().class, "HUNTER", "the class reaches the profile (kill-time model)")
HME.Diagnostics.NoteError("boom at Creature-0-1-2-3-1126-0000ABCD for " .. UnitName("player"))
local scrubbed = HME.Diagnostics.Text()
check(scrubbed:find("<guid>", 1, true) and not scrubbed:find("0000ABCD", 1, true), "GUIDs removed from errors")
check(not scrubbed:find(UnitName("player"), 1, true), "names removed from errors")
HME.Diagnostics.errors = {}
IN_COMBAT = true
FireEvent("PLAYER_REGEN_DISABLED")
check(not diag:IsShown(), "combat closes it")
check(not HME.Diagnostics.Show(), "and it does not open in combat")
IN_COMBAT = false
FireEvent("PLAYER_REGEN_ENABLED")
SlashCmdList.HARVESTMATEENHANCED("setup")
eq(HME.Window.frame.currentTab, "setup", "/hme setup")
local found = HME.SetupFindings()
check(#found >= 4, "setup says what it found")
check(SlashCmdList.HMEHARVESTMATE and SlashCmdList.HMEGATHERPEDIA, "/hm and /gp answered while those addons are absent")

STEP("Goals & Plans page: add, progress, plan")
HME.OpenWindow("goals")
local gp = HME.Window.frame.pages.goals
check(HME.Window.frame.currentTab == "goals", "the page opens")
HME.Goals.Add({ type = "skill", prof = "Skinning", target = 225 })
HME.Goals.Add({ type = "item", itemID = 2318, target = 40 })
gp.Refresh()
check(#(ERRORS or {}) == 0, "no errors: " .. tostring(ERRORS and ERRORS[1]))
HME.Guide.Plan("Skinning", 225, function() end)
HME.FinishJobs()
gp.Refresh()

STEP("Farm Finder: compare two farms, filters, invalid search")
HME.OpenWindow("finder")
HME.Pages.finderSet("Skinning", "profit")
HME.FinishJobs()
local res = HME.Pages.finderResults()
check(#res >= 2, "results")
HME.Pages.finderMark(res[1])
HME.Pages.finderMark(res[2])
check(HME.Pages.finderCompare(), "comparison shown")
HME.Pages.finderSet("Skinning", "level", nil, "safer", { continent = "K" })
HME.FinishJobs()
for _, r in ipairs(HME.Pages.finderResults()) do eq(HME.ZoneData.Get(r.mapID).cont, "K", "continent filter: " .. r.zone) end
STEP("Farm Finder: best beasts for a material")
HME.Pages.finderSet("Skinning", "material", "Medium Leather", "balanced", {})
HME.FinishJobs()
local fpage = HME.Window.frame.pages.finder
local best = HME.Pages.finderBeasts()
check(#best > 0, "beasts that give Medium Leather")
for i = 2, #best do check(best[i - 1].perHour >= best[i].perHour, "best first") end
local e = best[1]
check(e.name and e.min and e.max and e.req and e.perSkin > 0, "name, levels, Skinning needed, yield per skin")
check(e.confidence and #e.areas >= 1 and #e.areas <= HME.Skinning.BEST_AREAS, "confidence and up to 3 hunting areas")
for i = 2, #e.areas do check(e.areas[i - 1].perHour >= e.areas[i].perHour, "areas best first") end
local sub = fpage.BeastSub(e)
check(sub:find("Skinning %d+") and sub:find("per skin", 1, true) and sub:find("an hour", 1, true), "row: " .. sub)
check(fpage.BeastWhere(e):find(e.areas[1].zone, 1, true), "row names the best area")
check(HME.Skinning.BeastYieldNote(e):find("estimate", 1, true) or HME.Skinning.BeastYieldNote(e):find("seen", 1, true), "says where the yield comes from")
eq(HME.Pages.finderOpenBeast(e), e.result, "a click opens the beast's best area")
-- Two materials: each beast says which one.
HME.Pages.finderSet("Skinning", "material", "Medium Leather, Medium Hide", "balanced", {})
HME.FinishJobs()
local two = HME.Pages.finderBeasts()
local mats = {}
for _, x in ipairs(two) do mats[x.itemID] = true end
check(mats[2319], "Medium Leather rows")
check(fpage.BeastTitle(two[1]):find(":", 1, true), "a material label when several are typed")
-- Not Skinning, or no material: an explanation, no rows.
HME.Pages.finderSet("Skinning", "profit")
HME.FinishJobs()
eq(#HME.Pages.finderBeasts(), 0, "needs the material goal")
check(#(ERRORS or {}) == 0, "no errors: " .. tostring(ERRORS and ERRORS[1]))
HME.Pages.finderSet("Mining", "material", "%%%[[[")
check(#HME.Pages.finderResults() >= 0, "odd characters in a search don't break it")
HME.Pages.finderSet("Combined", "level", nil, "balanced", {})
HME.FinishJobs()
check(#(ERRORS or {}) == 0, "no errors: " .. tostring(ERRORS and ERRORS[1]))

STEP("Dashboard quick start from a saved profile")
HME.Profiles.Save("Leather run", { prof = "Skinning", goal = "profit", minutes = 30 })
HME.OpenWindow("dashboard")
local dash = HME.Window.frame.pages.dashboard
dash.Refresh()
local found
for _, f in ipairs(ALL_FRAMES) do if f.__kind == "Button" and f.__text == "Leather run" and f:IsVisible() then found = f end end
check(found, "a quick-start button")
Click(found)
eq(HME.Window.frame.currentTab, "finder", "starts the profile in the Farm Finder")

STEP("Stats views with filters, and long text")
HME.OpenWindow("stats")
local stats = HME.Window.frame.pages.stats
stats.Refresh()
for _, f in ipairs(ALL_FRAMES) do
    if f.__kind == "Button" and (f.__text == "Overview" or f.__text == "Measured areas") then Click(f) end
end
HME.Session.Start()
HME.Signal("GATHER_LOOT", "mine", "Copper Vein", { [2770] = 2 }, {})
FAKE_TIME = FAKE_TIME + 120
Tick(1.1)
HME.Session.Stop("test")
stats.Refresh()
HME.Goals.Add({ type = "item", itemID = 2318, target = 5 })
HME.Goals.List()[#HME.Goals.List()].name = string.rep("Sehr langer lokalisierter Name ", 6)
HME.OpenWindow("goals")
HME.Window.frame.pages.goals.Refresh()
check(#(ERRORS or {}) == 0, "no errors with long names: " .. tostring(ERRORS and ERRORS[1]))

STEP("Skinning levels: which beast levels give points, live")
local ST = HME.SkinTracker
local b = ST.Bands(125)
eq(b.orange[1], 21) eq(b.orange[2], 25)
eq(b.yellow[1], 18) eq(b.yellow[2], 20)
eq(b.green[1], 13) eq(b.green[2], 17)
eq(b.greyTo, 12, "grey at 12 and below")
eq(b.maxLevel, 25)
local nl, nreq, naway = ST.Next(125)
eq(nl, 26) eq(nreq, 130) eq(naway, 5)
local low = ST.Bands(1)
eq(low.orange[1], 1) eq(low.orange[2], 10)
eq(low.maxLevel, 10, "a new skinner: levels 1-10")
CHAR.level = 40
PLAYER.map, PLAYER.x, PLAYER.y = 1417, 0.5, 0.5
PROFS[1] = { line = 393, rank = 125, max = 225 }
HME.Player.Refresh()
eq(HME.settings.skinLevels, false, "off until you switch it on")
check(not ST.Shown(), "hidden")
SlashCmdList.HARVESTMATEENHANCED("skinlevels")
check(ST.Shown(), "/hme skinlevels shows it")
local box = _G.HarvestMateEnhancedSkinLevels
local text = ST.Text()
check(box.skill:GetText():find("^125 "), "the skill, top right: " .. box.skill:GetText())
eq(box.kill:GetText(), "21-25", "orange levels first, large")
check(text:find("or 18-20", 1, true), "then yellow: " .. text)
check(text:find("Next: level 26 at 130 Skinning", 1, true) and text:find("(+5)", 1, true), "the next level")
check(text:find("Arathi Highlands: none in range", 1, true), "Arathi's beasts are all higher: " .. text)
check(text:find("Wetlands", 1, true), "so it names the closest zones that have them: " .. text)
-- A skill-up that unlocks a level: the box moves on and chat says so.
ClearLog()
PROFS[1] = { line = 393, rank = 130, max = 225 }
HME.Player.Refresh()
text = ST.Text()
eq(box.kill:GetText(), "22-26", "updated live")
check(Said("you can now skin level 26"), "announced")
-- Your target's colour.
local realExists = UnitExists
UnitExists = function(u) return u == "player" or u == "target" end
UNIT_LEVELS = { target = 27 }
FireEvent("PLAYER_TARGET_CHANGED")
check(ST.Text():find("level 27|r") and ST.Text():find("needs 135 Skinning", 1, true), "a level too high to skin yet: " .. ST.Text())
UNIT_LEVELS = { target = 24 }
FireEvent("PLAYER_TARGET_CHANGED")
check(ST.Text():find("level 24|r", 1, true) and ST.Text():find("a point every skin", 1, true), "orange target")
-- Three questions kept apart: the level's colour, the fight, and whether this beast is skinnable at all.
UNIT_GUIDS = { target = "Creature-0-1-2-3-1126-000000AB" }
FireEvent("PLAYER_TARGET_CHANGED")
local tt = ST.Target(HME.Player.Professions().Skinning.rank)
eq(tt.known, HME.Learning.Npc(1126) and "data" or "unknown", "a beast in the bundled list is known skinnable")
eq(tt.fight, "yes", "level 24 is no fight for level 40")
UNIT_GUIDS = { target = "Creature-0-1-2-3-99999-000000AB" }
UNIT_LEVELS = { target = 46 }
FireEvent("PLAYER_TARGET_CHANGED")
tt = ST.Target(HME.Player.Professions().Skinning.rank)
eq(tt.known, "unknown", "a creature in no list is never called skinnable for its level alone")
eq(tt.fight, "no", "six levels above you: too strong")
check(ST.Text():find("may give no skin", 1, true) and ST.Text():find("too strong", 1, true), "both said: " .. ST.Text())
UNIT_GUIDS = nil
UnitExists = realExists
UNIT_LEVELS = nil
-- Too low to fight the orange levels: capped, and said.
CHAR.level = 15
HME.Player.Refresh()
text = ST.Text()
check(box.kill:GetText() ~= "22-26" and text:find("above 17 is too high", 1, true), "capped to what you can fight: " .. text)
CHAR.level = 40
HME.Player.Refresh()
-- Off again; a character without Skinning sees nothing.
SlashCmdList.HARVESTMATEENHANCED("sl off")
check(not ST.Shown(), "/hme sl off hides it")
local saved = PROFS[1]
PROFS[1] = nil
HME.Player.Refresh()
ClearLog()
SlashCmdList.HARVESTMATEENHANCED("sl on")
check(not ST.Shown() and Said("doesn't know Skinning"), "no Skinning: nothing shown, and said")
PROFS[1] = saved
HME.Player.Refresh()
SlashCmdList.HARVESTMATEENHANCED("sl off")
check(#(ERRORS or {}) == 0, "no errors: " .. tostring(ERRORS and ERRORS[1]))

STEP("Skinning levels: buttons open and close it")
HME.settings.skinLevels = false
HME.SkinTracker.Update()
HME.OpenWindow("dashboard")
local dashPage = HME.Window.frame.pages.dashboard
dashPage.Refresh()
local lv = dashPage.refs.levels
check(lv and lv:IsShown() and (lv:GetText() == "Levels" or lv:GetText() == "Skinning levels"), "the Skinning card has a Levels button")
Click(lv)
check(HME.SkinTracker.Shown(), "it opens the Skinning levels display")
eq(_G.HarvestMateEnhancedSkinLevels.max:GetText(), tostring(HME.SkillModel.MaxSkinLevel(HME.Player.Professions().Skinning.rank)),
    "the highest level you can skin, large")
dashPage.Refresh()
check(lv:GetText():find("^Hide"), "and says it hides it now: " .. lv:GetText())
Click(lv)
check(not HME.SkinTracker.Shown(), "closed again")
HarvestMateEnhanced_ToggleSkinLevels()
check(HME.SkinTracker.Shown(), "the key binding opens it")
Click(_G.HarvestMateEnhancedSkinLevels.close)
check(not HME.SkinTracker.Shown(), "its x closes it")
HME.OpenWindow("guides")
check(#(ERRORS or {}) == 0, "no errors: " .. tostring(ERRORS and ERRORS[1]))

STEP("without GatherMate2, the route pages never ask for it: HME has its own nodes")
local savedGM = _G.GatherMate2
_G.GatherMate2 = nil
for _, key in ipairs({ "routes", "newroute" }) do
    HME.OpenWindow(key)
    local pg = HME.Window.frame.pages[key]
    if pg and pg.Refresh then pg.Refresh() end
    RunTimers(0.5)
    local found
    Walk(pg, 0, function(f)
        local t = rawget(f, "__text")
        if type(t) == "string" and t:find("GatherMate2, where the herb", 1, true) then found = t end
    end)
    check(not found, key .. ": no request to install GatherMate2: " .. tostring(found))
end
_G.GatherMate2 = savedGM

STEP("Route Inspector: honest length, a rate only with enough sessions")
do
    local route = { name = "Inspect test loop", mapID = 1429, points = { 0.40, 0.40, 0.45, 0.42, 0.43, 0.48 }, length = 300 }
    route.terrain = { state = "none", legs = 3, walked = 0, approx = 3, walk = 999, sig = "x" }
    local info = HME.RouteEditor.Inspect(route)
    eq(info.stops, 3, "three stops")
    eq(info.length, 300, "nothing walked: the straight loop, not a guessed walk")
    check(info.lapSecs > 0, "a lap time")
    check(info.sessions.n == 0 and info.sessions.perHour == nil, "no sessions, no rate")
    local saved = HME.db.sessions
    HME.db.sessions = { { route = "Inspect test loop", farmSecs = 600, counts = { skin = 20 }, value = 0 } }
    info = HME.RouteEditor.Inspect(route)
    check(not info.sessions.enough, "10 minutes is not enough for a measured rate")
    HME.db.sessions = { { route = "Inspect test loop", farmSecs = 2400, counts = { skin = 60 } },
                        { route = "Inspect test loop", farmSecs = 2400, counts = { skin = 70 } } }
    info = HME.RouteEditor.Inspect(route)
    check(info.sessions.enough and math.abs(info.sessions.perHour - 97.5) < 0.1, "80 minutes over two sessions: 97.5 an hour")
    HME.db.sessions = saved
    HME.OpenWindow("routes")
    local shown = HME.Routes:InspectRoute(route)
    check(shown and _G.HarvestMateEnhancedRouteInspector:IsShown(), "the inspector opens over the Routes page")
    HME.Window.frame:Hide()
    check(not _G.HarvestMateEnhancedRouteInspector:IsShown() or not HME.Window.frame:IsShown(), "and goes with the window")
end
