-- Acceptance scenarios from the brief, on the real bundled data, headless.
-- A: level-36 Alliance hunter, 175 Skinning, Fastest leveling
-- B: the same, Best profit (with fixed test prices)
-- C: Goldthorn as a material
-- D: Mining fastest leveling (no grey/red ore drives the route)
-- E: Best profit, lower PvP risk
-- F: no optional addons installed (this whole file runs without them)

local ns, HME = LoadHME({ skipMissing = SKIP_MISSING })

STEP("loads without optional addons (scenario F)")
check(HME and HME.db, "saved data ready")
check(HME.dataReady, "bundled data is well formed: " .. table.concat(HME.dataProblems or {}, ", "))
check(_G.GatherMate2 == nil and _G.ForeverGPS == nil and _G.Auctionator == nil, "no optional addons present")
check(#(ERRORS or {}) == 0, "no errors while loading: " .. tostring(ERRORS and ERRORS[1]))

-- Character: level 36 Alliance hunter, Skinning 175/225, Mining 150/225, Fishing 100/150
PLAYER.map, PLAYER.x, PLAYER.y = 1429, 0.42, 0.65   -- Elwynn Forest
MAPS[1429].w, MAPS[1429].h = nil, nil              -- use bundled sizes
HME.Player.Refresh()
local profile = HME.Player.Profile()
eq(profile.level, 36, "level read")
eq(profile.faction, "Alliance", "faction read")
eq(profile.skills.Skinning.rank, 175, "skinning read")
eq(profile.skills.Fishing.rank, 100, "fishing read from the secondary slot")

-- Prices for the leathers (copper), as if Auctionator had them.
HME.Prices.fixed = {
    [2318] = { low = 30, typical = 40 },       -- Light Leather
    [2319] = { low = 90, typical = 120 },      -- Medium Leather
    [4234] = { low = 250, typical = 300 },     -- Heavy Leather
    [4304] = { low = 500, typical = 600 },     -- Thick Leather
    [783] = { low = 100, typical = 150 },      -- Light Hide
    [4232] = { low = 300, typical = 400 },     -- Medium Hide
    [4235] = { low = 600, typical = 800 },     -- Heavy Hide
    [3821] = { low = 900, typical = 1100 },    -- Goldthorn
    [2772] = { low = 120, typical = 150 },     -- Iron Ore
    [3858] = { low = 250, typical = 300 },     -- Mithril Ore
}
HME.Prices.Invalidate()

STEP("A: skinning, fastest leveling")
local results = HME.Recommend.Find({ prof = "Skinning", goal = "level" }, nil, profile)
check(#results >= 3, "several farms found (" .. #results .. ")")
local top = results[1]
REAL_PRINT(("  top: %s (%s) %.0f skill/h, %.0f beasts/h, %s, risk %s, conf %s"):format(top.zone, top.subarea,
    top.metrics.skillPerHour, top.metrics.beastsPerHour, top.metrics.limit, top.risk.label, top.confidence.label))
for i = 2, math.min(5, #results) do
    local r = results[i]
    REAL_PRINT(("  #%d %s (%s) %.0f skill/h travel %s"):format(i, r.zone, r.subarea, r.metrics.skillPerHour,
        r.travel and math.floor(r.travel / 60) .. "m" or "?"))
end
for _, r in ipairs(results) do
    for _, t in ipairs(r.targets) do
        check(t.max <= 38, ("no beast far above level 36 (%s %d)"):format(t.name, t.max))
        check(t.req <= 175, ("every target is skinnable at 175 (%s needs %d)"):format(t.name, t.req))
        check(not t.elite, "no elites")
    end
end
check(top.metrics.skillChance > 0.5, "the top farm still gives skill-ups most of the time")
check(top.levels == nil or top.levels[1] <= 40, "zone is not far above the character")
check(top.confidence.label ~= "High", "yields and respawn are estimates: confidence is not High")

STEP("B: skinning, best profit")
local profit = HME.Recommend.Find({ prof = "Skinning", goal = "profit" }, nil, profile)
check(#profit >= 3, "profit farms found")
local p1 = profit[1]
REAL_PRINT(("  top: %s %s/h typical (cons %s, opt %s), %.0f beasts/h"):format(p1.zone,
    HME.U.Money(p1.metrics.gph.typical, true), HME.U.Money(p1.metrics.gph.conservative, true),
    HME.U.Money(p1.metrics.gph.optimistic, true), p1.metrics.beastsPerHour))
check(p1.metrics.gph.conservative <= p1.metrics.gph.typical, "conservative <= typical")
check(p1.metrics.gph.typical <= p1.metrics.gph.optimistic, "typical <= optimistic")
check(p1.metrics.gph.typical > 0, "some gold per hour")
check(p1.metrics.beastsPerHour <= p1.metrics.supply + 1e-6, "never more beasts than respawns allow")

STEP("E: best profit, lower PvP risk")
HME.settings.riskMode = "safer"
local safer = HME.Recommend.Find({ prof = "Skinning", goal = "profit", risk = "safer" }, nil, profile)
HME.settings.riskMode = "balanced"
check(#safer >= 1, "lower-risk farms found")
check(safer[1].risk.score <= p1.risk.score + 1e-9, "the lower-risk pick is no riskier than the plain profit pick")
for _, r in ipairs(safer) do
    check(r.risk.label ~= "Safe" and r.risk.label ~= "safe", "nothing is ever called safe")
end
REAL_PRINT(("  safer top: %s, %s"):format(safer[1].zone, safer[1].risk.label))

STEP("C: Goldthorn")
PROFS[2] = { line = 182, rank = 200, max = 225 }   -- now a herbalist
HME.Player.Refresh()
profile = HME.Player.Profile()
local gold = HME.Recommend.Find({ prof = "Herbalism", goal = "material", targets = { ["Goldthorn"] = true } }, nil, profile)
check(#gold >= 1, "Goldthorn farms found")
for _, r in ipairs(gold) do
    local has = false
    for _, t in ipairs(r.targets) do if t.name == "Goldthorn" then has = true end end
    check(has, r.zone .. " has Goldthorn")
end
REAL_PRINT(("  goldthorn top: %s (%s), %.1f per hour"):format(gold[1].zone, gold[1].subarea, gold[1].metrics.materialPerHour or 0))

STEP("D: mining, fastest leveling")
PROFS[2] = { line = 186, rank = 150, max = 225 }
HME.Player.Refresh()
profile = HME.Player.Profile()
local mining = HME.Recommend.Find({ prof = "Mining", goal = "level" }, nil, profile)
check(#mining >= 1, "mining farms found")
for _, r in ipairs(mining) do
    for _, t in ipairs(r.targets) do
        check(t.req <= 150, ("only ore you can mine (%s needs %d)"):format(t.name, t.req))
    end
end
local m1 = mining[1]
check(m1.metrics.skillChance > 0.3, "the top mining farm mostly gives skill-ups")
REAL_PRINT(("  mining top: %s (%s) %.0f skill/h, %.0f nodes/h"):format(m1.zone, m1.subarea, m1.metrics.skillPerHour,
    m1.metrics.nodesPerHour))
