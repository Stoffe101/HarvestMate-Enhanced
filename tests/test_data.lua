-- The data layer: packed spawn points, sites (shared spawns counted once),
-- where each point came from, migrations from the old addons (their data
-- untouched), export/import, limits, schema upgrades and resets.

-- Saved data from the three replaced addons, as if they were still enabled
-- for this login.
HarvestMateDB = {
    opt = { gatherKey = true, gatherKeyBind = "G", nearby = false, announceParty = true },
    learned = { lowest = { ["Iron Deposit"] = 120 }, drops = { ["Peacebloom"] = { n = 10, items = { [2447] = 10 }, qty = { [2447] = 18 } } } },
    stats = { gathers = { herb = 5 } },
}
GatherpediaDB = {
    counts = { [2447] = { ["Elwynn Forest"] = 12 } },
    gathers = { Herbalism = { ["Elwynn Forest"] = 7 } },
    skinMobs = { yes = { [1] = true }, no = { [2] = true } },
    sparkle = { enabled = true },
}
GatherpediaCharDB = { learnedOrder = { "Mining", "Herbalism" }, showAllProfessions = true }
GatherPathForeverDB = {
    worldWidth = 7,
    routes = { { id = 3, mapID = 1429, name = "Old loop", kinds = {}, points = { 0.1, 0.1, 0.2, 0.2, 0.3, 0.1 }, color = { 1, 0, 0 }, shown = true } },
    taboos = { [1429] = { { 0.4, 0.4, 0.5, 0.4, 0.5, 0.5 } } },
    skip = { ["Wilted Peacebloom"] = true },
    nextID = 4,
}
local function Snapshot(t)
    local out = {}
    for k, v in pairs(t) do out[k] = type(v) == "table" and Snapshot(v) or v end
    return out
end
local function Same(a, b)
    if type(a) ~= type(b) then return false end
    if type(a) ~= "table" then return a == b end
    for k, v in pairs(a) do if not Same(v, b[k]) then return false end end
    for k in pairs(b) do if a[k] == nil then return false end end
    return true
end
local oldHM, oldGP, oldGPF = Snapshot(HarvestMateDB), Snapshot(GatherpediaDB), Snapshot(GatherPathForeverDB)

local ns, HME = LoadHME()

STEP("packed points decode to map positions")
local pts = {}
HME.U.EachPacked("0a0bzzzz", function(x, y) pts[#pts + 1] = { x, y } end)
eq(#pts, 2, "two points")
near(pts[1][1], (0 * 36 + 10) / 1000, 1e-9, "x")
near(pts[1][2], (0 * 36 + 11) / 1000, 1e-9, "y")
near(pts[2][1], (35 * 36 + 35) / 1000, 1e-9, "the largest value")

STEP("migration copies old data in once, leaving the old tables as they were")
check(Same(oldHM, HarvestMateDB) and Same(oldGP, GatherpediaDB) and Same(oldGPF, GatherPathForeverDB), "old saved data untouched")
local db = HarvestMateEnhancedDB
check(db.migrations.harvestmate and db.migrations.gatherpedia and db.migrations.gatherpath, "each import noted")
eq(db.hm.learned.lowest["Iron Deposit"], 120, "HarvestMate's learned requirement")
eq(db.hm.opt.gatherKey, false, "the gather key is NOT carried over on: HME asks again")
eq(db.hm.wasGatherKey, "G", "but the old key is remembered for the offer")
eq(db.hm.opt.nearby, false, "a display choice carries over")
eq(db.hm.opt.announceParty, false, "announcing to the group is not carried over on")
eq(db.gp.counts[2447]["Elwynn Forest"], 12, "Gatherpedia's counts")
eq(db.obs.mobs[1], true, "Gatherpedia's skinnable beasts feed the shared checks")
eq(db.obs.mobs[2], false, "and the not-skinnable ones")
eq(HarvestMateEnhancedCharDB.learnedOrder[1], "Mining", "per-character order")
local found
for _, r in ipairs(db.routes.routes) do if r.name == "Old loop" then found = r end end
check(found and found.source == "GatherPath", "GatherPath's route, marked where it came from")
check(db.routes.taboos[1429] and db.routes.skip["Wilted Peacebloom"], "taboo areas and the skip list")
eq(db.routes.worldWidth, 7, "display settings")
local n = #db.routes.routes
HME.Migrate.Run(false)
eq(#db.routes.routes, n, "running again does nothing")
HME.Migrate.Run(true)
eq(#db.routes.routes, n, "forced again: no duplicate routes")
eq(db.gp.counts[2447]["Elwynn Forest"], 12, "counts are not doubled by importing again")

STEP("sites: shared spawn points count once, with shares")
local sites = HME.Spawns.Sites("Mining", 1434)   -- Stranglethorn: shared ore spawns
check(#sites > 50, "sites found")
local shared = 0
for _, s in ipairs(sites) do
    local total, kinds = 0, 0
    for _, share in pairs(s.types) do total = total + share; kinds = kinds + 1 end
    near(total, 1, 1e-9, "shares add to one")
    if kinds > 1 then shared = shared + 1 end
    check(s.sources.db, "bundled source noted")
    check(not s.confirmed, "a bundled point is a prediction")
end
check(shared > 0, "some sites hold more than one ore (" .. shared .. ")")

STEP("what you gather confirms a site, and an unknown spot becomes one")
local s1 = sites[1]
HME.Spawns.Observe("Mining", 1434, s1.x, s1.y, next(s1.types))
local after = HME.Spawns.Sites("Mining", 1434)
local confirmed = 0
for _, s in ipairs(after) do if s.confirmed then confirmed = confirmed + 1 end end
eq(confirmed, 1, "the gathered site is confirmed")
eq(#after, #sites, "no extra site for a known spot")
HME.Spawns.Observe("Mining", 1434, 0.999, 0.001, "Tin Vein")
eq(#HME.Spawns.Sites("Mining", 1434), #sites + 1, "a new spot from your own gathering")

STEP("learned data stays within its limits")
local cells = {}
for i = 1, HME.DBM.LIMITS.nodesPerMap + 50 do cells["c" .. i] = { t = i, x = 0.5, y = 0.5, p = "Mining" } end
HME.db.obs.nodes[9999] = cells
HME.DBM.TrimMap(cells, HME.DBM.LIMITS.nodesPerMap)
eq(HME.U.Count(cells), HME.DBM.LIMITS.nodesPerMap, "trimmed to the limit")
check(cells.c1 == nil and cells["c" .. (HME.DBM.LIMITS.nodesPerMap + 50)] ~= nil, "oldest dropped first")
HME.db.obs.nodes[9999] = nil
for i = 1, HME.DBM.LIMITS.deaths + 20 do HME.Risk.NoteDeath(1429, 0.5, 0.5) end
eq(#HME.db.obs.deaths, HME.DBM.LIMITS.deaths, "deaths bounded")

STEP("export and import: round trip, never replacing")
local text = HME.DBM.Export({ routes = true, taboos = true })
check(text:sub(1, 5) == "HME1:", "has the header")
local data, err = HME.DBM.ReadImport(text)
check(data, "reads back: " .. tostring(err))
local routes = #HME.db.routes.routes
local added = HME.DBM.ApplyImport(data)
eq(added.routes, routes, "every route added again")
eq(#HME.db.routes.routes, routes * 2, "alongside the originals")
local names = {}
for _, r in ipairs(HME.db.routes.routes) do
    local key = r.mapID .. "|" .. r.name
    check(not names[key], "no two routes share a name in a zone: " .. key)
    names[key] = true
end
check(not HME.DBM.ReadImport(text:sub(1, -3)), "a cut-short export is refused")
local tampered = text:gsub("Old loop", "Evil loop")
check(not HME.DBM.ReadImport(tampered), "a changed export fails its checksum")
check(not HME.DBM.ReadImport("return os.exit()"), "anything else is refused, and never run")
local bad = HME.DBM.Deserialize("{s1:an5;}")
check(bad and bad.a == 5, "the reader handles plain tables")
check(HME.DBM.Deserialize("{s1:a") == nil, "and refuses broken ones")

STEP("schema: a newer save is kept, an older one upgraded")
local newer = HME.DBM.Prepare({ schema = 99, settings = { scale = 1.2 }, futureThing = { x = 1 } })
eq(newer.schema, 99, "newer schema kept")
check(newer.futureThing.x == 1, "unknown sections kept")
local older = HME.DBM.Prepare({})
eq(older.schema, HME.DBM.SCHEMA, "fresh data gets the current schema")
check(older.settings.riskMode == "balanced", "with defaults")

STEP("resets")
HME.settings.competition = 70
HME.DBM.ResetSettings()
eq(HME.settings.competition, 25, "settings back to defaults")
check(#HME.db.routes.routes > 0, "routes kept")
HME.DBM.ResetLearned()
eq(HME.U.Count(HME.db.obs.nodes), 0, "learned nodes gone")
check(#HME.db.routes.routes > 0, "routes still kept")

STEP("upgrade from 0.1.0 data")
local old = {
    schema = 1, settings = { hudCompact = true, riskMode = "safer" },
    stats = { ["Skinning@1431:1:2"] = { hours = 2, sessions = 2, beasts = 300, value = 50000 } },
    sessions = { { t = 1, secs = 1800, value = 9000, skillups = 10, counts = { herb = 0, mine = 0, skin = 30, fish = 0, kills = 30 } } },
    routes = { routes = { { id = 1, mapID = 1429, name = "Kept", points = { 0.1, 0.1, 0.2, 0.2, 0.3, 0.1 }, kinds = {} } } },
}
local up = HME.DBM.Prepare(old)
eq(up.schema, HME.DBM.SCHEMA, "upgraded to the current schema")
eq(up.settings.hudSize, "compact", "the compact HUD carries over")
eq(up.settings.riskMode, "safer", "settings kept")
eq(up.stats["Skinning@1431:1:2"].travelHours, 0, "travel time starts at zero for old areas")
eq(up.sessions[1].farmSecs, 1800, "old sessions keep their time")
check(up.sessions[1].mixedTravel, "and are marked as possibly including travel")
eq(up.routes.routes[1].name, "Kept", "routes untouched")

STEP("upgrade from 0.2.0 data: one character's history becomes its own; several are split by the journal")
local v2 = {
    schema = 2, settings = { hudSize = "detailed" },
    stats = { ["Skinning@1433:1:1"] = { hours = 3, sessions = 3, beasts = 300, value = 90000, travelHours = 0.5,
                                        samples = { { h = 1, gph = 30000 } } } },
    sessions = { { t = 1, char = "Alpha", farmSecs = 3600, secs = 3600, value = 30000, skillups = 0, counts = { skin = 100 },
                   areas = { { key = "Skinning@1433:1:1", secs = 3600, beasts = 100, skins = 100, value = 30000 } } } },
    obs = { badBeasts = { [1126] = true } },
    routes = { routes = { { id = 1, mapID = 1433, name = "Kept", points = { 0.1, 0.1, 0.2, 0.2, 0.3, 0.1 }, kinds = {} } } },
}
local up2 = HME.DBM.Prepare(v2)
eq(up2.schema, HME.DBM.SCHEMA, "the current schema")
eq(up2.settings.hudSize, "detailed", "settings kept")
eq(up2.settings.combinedPriority, "equal", "new settings get their defaults")
eq(up2.routes.routes[1].name, "Kept", "routes untouched")
check(up2.obs.badBeasts[1126], "0.2.0 beast marks kept (they become corrections at load)")
local alpha = {}
eq(HME.DBM.SeedCharStats(up2, alpha, "Alpha"), 1, "one character in the journal: the account's history is theirs")
eq(alpha.stats["Skinning@1433:1:1"].hours, 3)
eq(alpha.stats["Skinning@1433:1:1"].samples, nil, "the per-session samples stay with the account")
eq(HME.DBM.SeedCharStats(up2, alpha, "Alpha"), 0, "once only")
table.insert(up2.sessions, { t = 2, char = "Beta", farmSecs = 1800, secs = 1800, value = 5000, skillups = 0, counts = { skin = 20 },
    areas = { { key = "Skinning@1433:1:1", secs = 1800, beasts = 20, skins = 20, value = 5000 } } })
local beta = {}
HME.DBM.SeedCharStats(up2, beta, "Beta")
eq(beta.stats["Skinning@1433:1:1"].hours, 0.5, "several characters: only Beta's own sessions")
eq(beta.stats["Skinning@1433:1:1"].beasts, 20)

STEP("damaged saves are repaired, not fatal")
local bad = {
    schema = 2, settings = { scale = "huge", riskMode = 5 }, obs = { nodes = { [1429] = "junk", junk = {}, [1436] = { a = { x = 0.1 }, b = { p = "Mining", x = 0.2, y = 0.3 } } },
        skins = { [1] = "x", [2] = { n = 3, qty = {} } }, deaths = { "x", { m = 1 } }, loot = { [5] = 7 } },
    stats = { bad = "x" }, sessions = { "x", { value = 1 } },
}
HME.repaired = 0
local fixed = HME.DBM.Prepare(bad)
check(HME.repaired >= 8, "bad entries counted (" .. HME.repaired .. ")")
eq(fixed.settings.scale, 1.0, "a broken setting back to its default")
check(fixed.obs.nodes[1429] == nil and fixed.obs.nodes.junk == nil, "broken maps dropped")
check(fixed.obs.nodes[1436].b and not fixed.obs.nodes[1436].a, "only the broken node goes")
check(fixed.obs.skins[2] and not fixed.obs.skins[1], "good skins kept")
eq(#fixed.sessions, 0, "broken sessions dropped")
eq(#fixed.obs.deaths, 1, "good deaths kept")
local char = HME.DBM.PrepareChar({ goals = "x", profiles = { "y", { name = "ok" } }, session = 5 })
eq(#char.goals, 0, "broken goals list replaced")
eq(#char.profiles, 1, "only good profiles kept")
eq(char.session, nil, "a broken saved session is dropped")

STEP("imports are size-limited")
local huge = "HME1:00000000:" .. string.rep("s1:a", 10)
check(not HME.DBM.ReadImport(huge), "a forged checksum is refused")

STEP("imported routes are validated")
local payload = { v = 1, routes = { { mapID = 1429, name = "ok", points = { 0.1, 0.1, 0.2, 0.2 } },
    { mapID = 1429, name = "bad", points = { 0.1, "x", 5, 0.2 } }, { mapID = 1429, name = "neg", points = { -1, 0, 0, 0 } } } }
local before = #HME.db.routes.routes
local added = HME.DBM.ApplyImport(payload)
eq(added.routes, 1, "only the valid route")
check(HME.db.routes.routes[before + 1].imported, "marked imported")
check(not HME.DBM.ReadImport(string.rep("x", 2000001)), "over 2 MB refused")

STEP("schema 4 (0.6.0): a 0.5.0 save keeps everything; new sections are checked")
local v5 = { schema = 3, settings = { hudSize = "compact", riskMode = "safer" },
    sessions = { { t = 1, secs = 900, farmSecs = 900, value = 10, counts = { skin = 5 }, skillups = 2,
        areas = { { key = "Skinning@1424:3:10", secs = 900, skins = 5, predicted = { skins = 30 } } } } },
    stats = { ["Skinning@1424:3:10"] = { hours = 0.25, sessions = 1 } }, chars = "broken" }
local up4 = HME.DBM.Prepare(v5)
eq(up4.schema, HME.DBM.SCHEMA)
eq(up4.settings.hudSize, "compact", "settings kept")
eq(up4.settings.riskMode, "safer")
eq(up4.sessions[1].areas[1].predicted.skins, 30, "predictions kept for the ledger")
eq(up4.chars, nil, "a broken characters section is dropped, nothing else")
eq(up4.settings.sessionReview, true, "new settings get their defaults")
local ok4 = HME.DBM.Prepare({ schema = 3, chars = { ["Alt-Realm"] = { bags = { [2318] = 4 } }, bad = "x", worse = { bags = 5 } } })
check(ok4.chars["Alt-Realm"] and ok4.chars.bad == nil and ok4.chars.worse == nil, "only well-formed characters kept")
local ch = HME.DBM.PrepareChar({ notices = { { text = "ok", cat = "goal" }, "junk", { cat = "x" } }, copilot = { dismissed = 5 } })
eq(#ch.notices, 1, "only notices with text")
eq(type(ch.copilot.dismissed), "table", "copilot state repaired")

