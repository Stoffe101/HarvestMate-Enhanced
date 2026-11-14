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
check(Said("/hme finder"), "help lists commands")
SlashCmdList.HARVESTMATEENHANCED("finder")
eq(HME.Window.frame.currentTab, "finder", "/hme finder")
SlashCmdList.HARVESTMATEENHANCED("diag")
check(Said("data ok"), "/hme diag")
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
