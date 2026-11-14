-- Optional addons: Forever-GPS (published API and the 2.x journey panel),
-- TomTom, Auctionator, TSM and missing ones. One navigator at a time, and a
-- clean hand-over at the farm (scenario G).

-- A fake Forever-GPS 2.7 with its journey panel and topics (no API table).
local fgTopics = {}
local inspected
ForeverGPS = {
    VERSION = "2.7.0",
    On = function(topic, fn) fgTopics[topic] = fgTopics[topic] or {}; table.insert(fgTopics[topic], fn) end,
    Search = {
        CoordsFor = function(text) return { data = { text = text }, name = text } end,
        Target = function(result) return { data = result.data, name = result.name } end,
    },
    Planner = { Inspect = function(target) inspected = target end },
    Window = { Show = function() end, ShowRoute = function() end },
    Market = { Price = function(id) if id == 2318 then return { buy = 30, typical = 40, age = 3600, units = 50 } end end },
}
local function Emit(topic) for _, fn in ipairs(fgTopics[topic] or {}) do fn() end end

local ns, HME = LoadHME()
PLAYER.map, PLAYER.x, PLAYER.y = 1429, 0.42, 0.65   -- Elwynn
MAPS[1429].w, MAPS[1429].h = nil, nil
HME.Player.Refresh()

STEP("Forever-GPS is found and its kind of bridge recognised")
eq(HME.FGPS.Mode(), "panel", "2.x: the journey panel")
check(HME.FGPS.Status():find("2.7.0"), "status names the version")

STEP("prices come from Forever-GPS first")
local p = HME.Prices.Get(2318)
eq(p.source, "ForeverGPS", "source")
near(p.typical, 40 * 0.95, 1e-6, "typical after the 5% cut")
near(p.conservative, 30 * 0.95, 1e-6, "conservative = the lowest listing")
eq(p.age, 3600, "age kept")

STEP("scenario G: a far farm goes to Forever-GPS, then HME at the farm")
local profile = HME.Player.Profile()
local results = HME.Recommend.Find({ prof = "Mining", goal = "level" }, nil, profile)
local far
for _, r in ipairs(results) do if r.mapID ~= 1429 then far = r break end end
check(far, "a farm in another zone")
HME.Guidance.StartResult(far, "level")
for _ = 1, 4000 do
    Tick(0.016)
    if HME.Guidance.Active() then break end
end
local g = HME.Guidance.Active()
check(g, "the farm is being followed")
eq(g.phase, "travel", "travelling first")
eq(g.owner, "fgps", "Forever-GPS owns the trip")
check(inspected and inspected.name, "Forever-GPS got the destination (the player presses Go there)")
check(not HME.Arrow.Shown(), "no HME arrow while Forever-GPS navigates")
Emit("route:arrived")
g = HME.Guidance.Active()
eq(g.phase, "farm", "on arrival: farming")
eq(g.owner, "hme", "HME owns the loop now")
check(HME.Arrow.Shown(), "HME's arrow points round the loop")

STEP("stopping in Forever-GPS before arriving does not start HME's arrow by itself")
HME.Guidance.Navigate()
eq(HME.Guidance.Active().owner, "fgps", "back with Forever-GPS")
Emit("route:cleared")
eq(HME.Guidance.Active().owner, nil, "nobody navigates: the player stopped it")
HME.Guidance.Stop()
check(not HME.Guidance.Active() and not HME.Arrow.Shown(), "stopped cleanly")

STEP("a published API is preferred when Forever-GPS has one")
local calls = {}
ForeverGPS.API = {
    VERSION = 1,
    NavigateTo = function(mapID, x, y, label) calls[#calls + 1] = { mapID, x, y, label } return true end,
    Stop = function() calls.stopped = true end,
    On = function() end,
}
eq(HME.FGPS.Mode(), "api", "API mode")
check(HME.FGPS.NavigateTo(1436, 0.5, 0.5, "Test"), "navigates")
eq(calls[1][1], 1436, "with the map")
HME.FGPS.Release()
check(calls.stopped, "and HME stops only the journey it asked for")
ForeverGPS.API = nil

STEP("old or broken Forever-GPS: HME's own arrow")
ForeverGPS.VERSION = "1.0.0"
check(HME.FGPS.Mode() == nil, "too old")
HME.Guidance.StartResult(far, "level")
for _ = 1, 4000 do
    Tick(0.016)
    if HME.Guidance.Active() then break end
end
eq(HME.Guidance.Active().owner, "hme", "HME's arrow instead")
check(HME.Arrow.Shown(), "shown")
HME.Guidance.Stop()

STEP("TomTom when chosen and Forever-GPS is missing")
ForeverGPS = nil
local tt = { wps = {} }
function tt:AddWaypoint(mapID, x, y, opts) self.wps[#self.wps + 1] = { mapID, x, y } return #self.wps end
function tt:RemoveWaypoint(id) self.wps[id] = nil end
TomTom = tt
HME.settings.tomtom = true
HME.Guidance.StartResult(far, "level")
for _ = 1, 4000 do
    Tick(0.016)
    if HME.Guidance.Active() then break end
end
eq(HME.Guidance.Active().owner, "tomtom", "TomTom owns the trip")
check(#tt.wps == 1 and not HME.Arrow.Shown(), "one waypoint, no second arrow")
HME.Guidance.Stop()
check(tt.wps[1] == nil, "waypoint removed on stop")
HME.settings.tomtom = false
TomTom = nil

STEP("price providers: Auctionator, then TSM, then vendor")
HME.Prices.Invalidate()
Auctionator = { API = { v1 = { GetAuctionPriceByItemID = function(_, id) return id == 2319 and 200 or nil end,
    GetAuctionAgeByItemID = function() return 2 end } } }
local a = HME.Prices.Get(2319)
eq(a.source, "Auctionator", "Auctionator")
eq(a.age, 2 * 86400, "its age in days, kept as seconds")
near(a.conservative, 200 * 0.8 * 0.95, 1e-6, "a single price: conservative is 80%")
Auctionator = nil
TSM_API = { GetCustomPriceValue = function(src, key) if key == "i:2319" then return src == "dbmarket" and 150 or 120 end end }
HME.Prices.Invalidate()
local t = HME.Prices.Get(2319)
eq(t.source, "TSM", "TSM")
near(t.conservative, 120 * 0.95, 1e-6, "TSM's min buyout")
HME.settings.priceProvider = "vendor"
HME.Prices.Invalidate()
ITEMS[2319] = { name = "Medium Leather", sell = 50 }
local v = HME.Prices.Get(2319)
check(v.source == nil and v.best == 50, "vendor only when chosen")
HME.settings.priceProvider = "auto"
TSM_API = nil

STEP("nothing optional installed: everything still works (scenario F)")
HME.Prices.Invalidate()
check(HME.FGPS.Mode() == nil, "no Forever-GPS")
check(HME.IntegrationLine():find("HME's arrow", 1, true), "the dashboard says what is used instead")
local r2 = HME.Recommend.Find({ prof = "Skinning", goal = "profit" }, nil, HME.Player.Profile())
check(#r2 > 0, "profit farms still ranked (vendor values)")
check(#(ERRORS or {}) == 0, "no errors: " .. tostring(ERRORS and ERRORS[1]))
