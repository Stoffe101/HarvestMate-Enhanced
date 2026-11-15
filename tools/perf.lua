-- Performance of the paths a player feels, for comparing versions
-- (tools/perf_compare.py runs this against each version's addon folder).
-- Headless CPU time and Lua memory in the test client, not game frame
-- times: the game draws, lays out text and runs other addons too. Every
-- step is guarded, so an older version without a feature just skips it.

local out = {}
local function Put(label, value, unit) out[#out + 1] = ("PERF\t%s\t%.3f\t%s"):format(label, value, unit or "ms") end
local function Time(label, fn, runs)
    runs = runs or 1
    collectgarbage("collect")
    local kb0 = collectgarbage("count")
    local t0 = os.clock()
    local ok, err = pcall(function() for _ = 1, runs do fn() end end)
    local ms = (os.clock() - t0) * 1000 / runs
    local kb = (collectgarbage("count") - kb0) / runs
    if ok then
        Put(label, ms)
        Put(label .. " (garbage)", math.max(0, kb), "KB")
    else
        Put(label .. " SKIPPED", 0, tostring(err):sub(1, 60))
    end
end

collectgarbage("collect")
local kbStart = collectgarbage("count")
local t0 = os.clock()
local ns, HME = LoadHME()
Put("Load the addon (every file, data indexes)", (os.clock() - t0) * 1000)
collectgarbage("collect")
Put("Memory after load", collectgarbage("count") - kbStart, "KB")

PLAYER.map, PLAYER.x, PLAYER.y = 1424, 0.46, 0.42
CHAR.level = 41
PROFS = { { line = 393, rank = 143, max = 225 } }
HME.Player.Refresh()
local profile = HME.Player.Profile()

Time("Farm Finder, Skinning leveling (cold)", function() HME.Recommend.Find({ prof = "Skinning", goal = "level" }, nil, profile) end)
Time("Farm Finder, Skinning leveling (warm)", function() HME.Recommend.Find({ prof = "Skinning", goal = "level" }, nil, profile) end, 3)
Time("Farm Finder, Medium Leather", function()
    HME.Recommend.Find({ prof = "Skinning", goal = "material", targets = { [2319] = true, ["Medium Leather"] = true } }, nil, profile)
end)

-- The window: open it, build and show every page once.
Time("Open the window and build every page", function()
    local win = HME.OpenWindow("dashboard")
    for key in pairs(win.pages) do HME.OpenWindow(key) end
    HME.FinishJobs()
    win:Hide()
end)
Time("Dashboard refresh", function()
    local p = HME.Window.frame.pages.dashboard
    if p.Refresh then p.Refresh() end
end, 50)

-- A session with skins, then the HUD as it updates once a second.
HME.Session.Start()
local n = 0
Time("Skin events (cast, loot, close) x200", function()
    for _ = 1, 200 do
        n = n + 1
        RunTimers(6)
        FireEvent("UNIT_SPELLCAST_SUCCEEDED", "player", "cast", 8613)
        LOOT_SOURCE, LOOT = ("Creature-0-1-2-3-2354-%08X"):format(n), { { id = 2318, qty = 1 } }
        FireEvent("LOOT_OPENED")
        FireEvent("LOOT_CLOSED")
    end
end)
HME.settings.hud = true
for _, size in ipairs({ "compact", "normal", "detailed" }) do
    HME.settings.hudSize = size
    Time("HUD update, " .. size, function() HME.HUD.Update() end, 200)
end
HME.settings.skinLevels = true
Time("Skinning levels update", function() HME.SkinTracker.Update() end, 200)
Time("Session live figures", function() HME.Session.Live() end, 200)
HME.Session.Stop("perf")

-- 0.6.0's paths (skipped on versions without them).
-- A long history with predictions, for the ledger and the Copilot.
HME.db.sessions = {}
for i = 1, 120 do
    HME.db.sessions[i] = { t = time() - i * 40000, char = CHAR.name, farmSecs = 1800, secs = 1800, value = 40000, skillups = 12,
        counts = { skin = 40, kills = 42 }, items = { [2318] = 30 },
        areas = { { key = "Skinning@1424:" .. (i % 7) .. ":3", secs = 1800, skins = 40, beasts = 42, skillups = 12,
                    predicted = { skins = 90, beasts = 90, skill = 30 } } } }
end
Time("Prediction ledger: factor and report, 120 sessions", function()
    HME.Ledger.Forget()
    HME.Ledger.Factor("Skinning")
    HME.Ledger.Report()
end, 5)
HME.FinishJobs()   -- (whatever earlier steps queued runs first, outside the measurement)
Time("Copilot: first evaluation (searches in the background, run to the end)", function()
    HME.Copilot.searches = {}
    HME.Copilot.Evaluate(true)
    HME.FinishJobs()
end)
Time("Copilot: evaluation, searches cached", function() HME.Copilot.Evaluate(true) end, 20)
Time("Skinning Explorer: search by name", function() HME.Bestiary.Search({ text = "bear", filter = "all" }, profile) end, 10)
Time("Skinning Explorer: search by material, best for you", function()
    HME.Bestiary.Search({ text = "medium leather", filter = "canskin", sort = "forme" }, profile)
end, 3)
Time("Search everything: \"leather\"", function() HME.Find.Run("leather") end, 10)
Time("Sell, process or keep: one material", function() HME.Economy.Options(2319) end, 50)
Time("Notifications: 100 notices", function()
    for i = 1, 100 do HME.Notify.Push("data", "perf" .. i .. ":" .. os.clock(), "Note " .. i) end
end)
Time("Quest log index (35 quests)", function()
    local q = {}
    for i = 1, 35 do q[i] = { questID = 1000 + i, title = "Quest " .. i, objectives = { { text = "Gray Bear slain: 1/8", type = "monster" } } } end
    C_QuestLog = { GetNumQuestLogEntries = function() return #q end,
        GetInfo = function(i) return { questID = q[i].questID, title = q[i].title } end,
        GetQuestObjectives = function(id) return q[id - 1000].objectives end, IsComplete = function() return false end }
    HME.QuestSynergy.Rebuild()
    C_QuestLog = nil
end, 5)
Time("Timed loop on a 60-stop route", function()
    local pts = {}
    for i = 1, 60 do
        local a = i / 60 * 2 * math.pi
        pts[#pts + 1] = 0.5 + 0.2 * math.cos(a)
        pts[#pts + 1] = 0.5 + 0.2 * math.sin(a)
    end
    HME.RouteDirector.Timed({ id = -1, mapID = 1424, name = "perf", points = pts, kinds = { Herb = {} } }, 10)
end, 5)
collectgarbage("collect")
Put("Memory at the end", collectgarbage("count") - kbStart, "KB")

for _, line in ipairs(out) do REAL_PRINT(line) end
