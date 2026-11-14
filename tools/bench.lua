-- Benchmarks on the full bundled data, headless (CPU time outside the game;
-- the game runs these as background jobs of 8 ms a frame).
--   python tools/run_tests.py bench   (runs tests/test_zz_bench.lua, which loads this)

local function Time(label, fn, runs)
    runs = runs or 1
    local t0 = os.clock()
    local out
    for _ = 1, runs do out = fn() end
    local ms = (os.clock() - t0) * 1000 / runs
    REAL_PRINT(("  %-48s %8.1f ms"):format(label, ms))
    BENCH[label] = ms
    return out
end
BENCH = {}

local ns, HME = LoadHME()
PLAYER.map, PLAYER.x, PLAYER.y = 1429, 0.42, 0.65
MAPS[1429].w, MAPS[1429].h = nil, nil
CHAR.level = 45
PROFS = { { line = 393, rank = 225, max = 300 }, { line = 186, rank = 225, max = 300 }, { line = 182, rank = 225, max = 300 } }
HME.Player.Refresh()
local profile = HME.Player.Profile()

HME.Spawns.Invalidate()
Time("Farm Finder, Mining, cold caches", function() return HME.Recommend.Find({ prof = "Mining", goal = "level" }, nil, profile) end)
Time("Farm Finder, Mining, warm", function() return HME.Recommend.Find({ prof = "Mining", goal = "level" }, nil, profile) end, 3)
Time("Farm Finder, Herbalism profit", function() return HME.Recommend.Find({ prof = "Herbalism", goal = "profit" }, nil, profile) end)
Time("Farm Finder, Skinning leveling", function() return HME.Recommend.Find({ prof = "Skinning", goal = "level" }, nil, profile) end)
Time("Farm Finder, Skinning profit", function() return HME.Recommend.Find({ prof = "Skinning", goal = "profit" }, nil, profile) end)
Time("Farm Finder, Herbs + Ore combined", function() return HME.Recommend.Find({ prof = "Combined", goal = "balanced" }, nil, profile) end)
Time("Farm Finder, multi-material (3 items)", function()
    return HME.Recommend.Find({ prof = "Mining", goal = "material", targets = { [2772] = true, [3858] = true, [2776] = true } }, nil, profile)
end)
Time("Switching professions x8 (warm)", function()
    for _ = 1, 2 do
        for _, p in ipairs({ "Herbalism", "Mining", "Skinning", "Fishing" }) do HME.Recommend.Find({ prof = p, goal = "level" }, nil, profile) end
    end
end)
HME.Spawns.Invalidate()
Time("Sites, densest mining zone (Stranglethorn)", function() return HME.Spawns.Sites("Mining", 1434) end)
Time("Hunting areas, Stranglethorn beasts", function() return HME.Skinning.Areas(1434, profile, "profit", "balanced") end)
local res = HME.Recommend.Find({ prof = "Mining", goal = "level" }, nil, profile)
local route = HME.Planner.Create(res[1], "level")
local t0 = os.clock()
for _ = 1, 50000 do if not route.working then break end Tick(0.016) end
local ms = (os.clock() - t0) * 1000
REAL_PRINT(("  %-48s %8.1f ms (%d stops)"):format("Route build (background job, all slices)", ms, #route.points / 2))
BENCH.route = ms
WorldMapFrame:Show()
HME.MapOverlay.Preview(res[1])
Time("Map overlay draw, mining farm", function() HME.MapOverlay.Draw() end, 5)
HME.settings.nodePinsAlways = true
HME.MapOverlay.ClearPreview()
WorldMapFrame:SetMapID(1434)
Time("Map overlay draw, every pin in Stranglethorn", function() HME.MapOverlay.Draw() end, 5)
WorldMapFrame:SetMapID(1434)
HME.settings.mapDetail = "heatmap"
Time("Map overlay draw, heatmap (Stranglethorn)", function() HME.MapOverlay.Draw() end, 5)
HME.settings.mapDetail = "detailed"

collectgarbage("collect")
REAL_PRINT(("  %-48s %8.1f MB"):format("Lua memory at 0.2.0's measuring point", collectgarbage("count") / 1024))
BENCH.memory020 = collectgarbage("count") / 1024

-- 0.3.0
local F = dofile("tests/fixtures/fgps_terrain.lua")
local GP = HME.Routes
local function FixtureRoute(fix)
    local r = { id = GP.db.nextID, mapID = fix.mapID, name = fix.name .. " bench", kinds = {}, sight = 0, shown = true,
                color = { 1, 1, 1 }, points = {} }
    for i, v in ipairs(fix.points) do r.points[i] = v end
    GP.db.nextID = GP.db.nextID + 1
    table.insert(GP.db.routes, r)
    return r
end
local big = FixtureRoute(F.routes[1])
-- The real grid's answers for every leg in the cache, as after a refinement.
local function Key(m, ax, ay, bx, by) return ("%d:%.4f:%.4f:%.4f:%.4f"):format(m, ax, ay, bx, by) end
local n = #big.points / 2
for i = 1, n do
    local j = i % n + 1
    local p = big.points
    local res = F.results[Key(big.mapID, p[2 * i - 1], p[2 * i], p[2 * j - 1], p[2 * j])]
    if res then HME.Terrain._Remember(big.mapID, p[2 * i - 1], p[2 * i], p[2 * j - 1], p[2 * j], res) end
end
Time(("Terrain: assemble a walked %d-leg loop"):format(n), function() return HME.Terrain.Assemble(big) end, 20)
Time("Terrain: route quality with terrain", function() return HME.RouteEditor.Quality(big) end, 20)
WorldMapFrame:SetMapID(1433)
Time("Map route lines, walked 99-leg loop (all routes)", function() GP:DrawWorldMap() end, 5)
local timing = {}
for _, t in ipairs(F.timing or {}) do timing[#timing + 1] = ("%s %d legs: %.0f ms total, slowest leg %.0f ms"):format(t.name, t.legs, t.totalMs, t.slowestMs) end
REAL_PRINT("  Forever-GPS walking grid (fixture, desktop Lua 5.4): " .. table.concat(timing, "; "))
-- Recorder: a second of sampling, many times.
PLAYER.map, PLAYER.x, PLAYER.y = 1429, 0.3, 0.3
HME.Recorder.Start("bench")
local step = 0
Time("Recorder: one sample (position, thresholds)", function()
    step = step + 1
    PLAYER.x, PLAYER.y = 0.3 + (step % 200) * 0.002, 0.3 + math.floor(step / 200) * 0.003
    HME.Recorder.Sample()
end, 2000)
local recState = HME.Recorder.State()
REAL_PRINT(("  recorder kept %d points of %d samples"):format(#recState.points / 2, step))
Time("Recorder: stop (simplify and save)", function() return HME.Recorder.Stop() end)
HME.Session.Start()
for i = 1, 200 do HME.Signal("BEAST_SKINNED", 1126, { [2318] = 1 }, "Creature-0-1-2-3-1126-B" .. i) end
HME.Session.Current().farm = 3600
Time("Session: live feedback (200 events)", function() return HME.Session.Live() end, 50)
HME.Session.Stop("bench")
Time("Expedition: plan 3 materials over 3 professions", function()
    return HME.Expedition.Plan({ { itemID = 4234, count = 50 }, { itemID = 2772, count = 30 }, { itemID = 3821, count = 20 } }, { profile = profile })
end)
Time("Diagnostics report", function() return HME.Diagnostics.Text() end, 10)

collectgarbage("collect")
REAL_PRINT(("  %-48s %8.1f MB"):format("Lua memory after all of this", collectgarbage("count") / 1024))
