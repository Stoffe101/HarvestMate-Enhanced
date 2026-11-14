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
collectgarbage("collect")
REAL_PRINT(("  %-48s %8.1f MB"):format("Lua memory after all of this", collectgarbage("count") / 1024))
