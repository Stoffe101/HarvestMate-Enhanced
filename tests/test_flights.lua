-- 0.7.1: taking flights automatically (Forever-GPS's planned flight first,
-- else the master closest to where HME leads; never in combat, never with
-- Shift, off by default; a button when the game refuses), the soft-target
-- tooltip kept short and out of the middle of the screen, and routes HME made
-- leaving the map when you stop following them.

local ns, HME = LoadHME()
PLAYER.map, PLAYER.x, PLAYER.y = 1429, 0.42, 0.65   -- Goldshire, Elwynn
CHAR.level = 30
PROFS = { { line = 393, rank = 120, max = 150 }, { line = 182, rank = 60, max = 150 } }
HME.Player.Refresh()
local F = HME.Flights

-- A stand-in world: Elwynn and Duskwood side by side on one continent (yards).
local ORIGIN = { [1429] = { 0, 0, 4000, 2700 }, [1431] = { 0, 2700, 3000, 2000 }, [1415] = { 0, 0, 20000, 30000 } }
C_Map.GetWorldPosFromMapPos = function(mapID, v)
    local o = ORIGIN[mapID]
    if not o then return nil end
    return 0, { GetXY = function() return o[1] + v.x * o[3], o[2] + v.y * o[4] end }
end
local function Pos(x, y) return { x = x, y = y, GetXY = function() return x, y end } end
Enum.FlightPathState = { Current = 0, Reachable = 1, Unreachable = 2 }
-- The flight master's map (continent 1415, positions as shares of it).
local NODES = {
    { nodeID = 2, slotIndex = 1, name = "Stormwind", state = 0, position = Pos(0.05, 0.03) },
    { nodeID = 12, slotIndex = 2, name = "Darkshire, Duskwood", state = 1, position = Pos(0.12, 0.15) },
    { nodeID = 4, slotIndex = 3, name = "Sentinel Hill, Westfall", state = 1, position = Pos(0.01, 0.13) },
    { nodeID = 99, slotIndex = 4, name = "Not learned", state = 2, position = Pos(0.13, 0.155) },
}
C_TaxiMap = { GetAllTaxiNodes = function() return NODES end }
function GetTaxiMapID() return 1415 end
local TAKEN = {}
local REFUSE = false
function TakeTaxiNode(slot) if not REFUSE then TAKEN[#TAKEN + 1] = slot end end
local ON_TAXI = false
function UnitOnTaxi() return ON_TAXI end
TaxiFrame = CreateFrame("Frame", "TaxiFrame", UIParent)

local function Open(shift)
    TaxiFrame:Show()
    return F.Opened(shift or false)
end

-- HME leads to a farm in Duskwood: a route there, followed.
local GP = HME.Routes
local route = { id = GP.db.nextID, mapID = 1431, name = "Duskwood wolves", kinds = {}, sight = 0, color = { 1, 1, 1 }, shown = true,
    points = { 0.70, 0.40, 0.75, 0.45, 0.72, 0.50 }, planned = { prof = "Skinning", key = "test:dusk" } }
GP.db.nextID = GP.db.nextID + 1
table.insert(GP.db.routes, route)
route.length = GP:RouteLength(route)

STEP("off by default: nothing is taken")
check(not HME.settings.autoFlight, "off")
HME.Guidance.Start(route)
check(HME.Guidance.Active().phase == "travel", "on the way")
Open()
eq(#TAKEN, 0, "nothing taken")

STEP("on: the master closest to the farm")
HME.settings.autoFlight = true
ClearLog()
local node = Open()
check(node and node.name == "Darkshire, Duskwood", "Darkshire: " .. tostring(node and node.name))
eq(TAKEN[#TAKEN], 2, "its slot taken")
check(Said("flying to"), "said in chat")

STEP("never an unlearned master, never with Shift, never in combat")
for _, n in ipairs(NODES) do check(not (TAKEN[#TAKEN] == 4), "not the unreachable one") end
local count = #TAKEN
check(Open(true) == nil, "Shift: you choose")
eq(F.last.skipped, "shift")
IN_COMBAT = true
check(Open() == nil, "in combat: nothing")
IN_COMBAT = false
eq(#TAKEN, count, "nothing more taken")

STEP("Forever-GPS's planned flight comes first")
local realAPI = HME.FGPS.APIv2
HME.FGPS.APIv2 = function() return { PlannedFlight = function() return { fromID = 2, toID = 4 } end } end
node = Open()
eq(node.name, "Sentinel Hill, Westfall", "the journey's flight, not HME's guess")
HME.FGPS.APIv2 = realAPI

STEP("not when flying lands no nearer")
PLAYER.map, PLAYER.x, PLAYER.y = 1431, 0.70, 0.30   -- already in Duskwood, near the farm
HME.Player.Refresh()
NODES[1].state = 1
NODES[1], NODES[2] = NODES[2], NODES[1]
NODES[1].state = 0   -- standing at Darkshire's master
NODES[2].state = 1
count = #TAKEN
local n2, why = F.Choose()
check(n2 == nil and why:find("no nearer"), tostring(why))
check(Open() == nil, "nothing taken")
eq(#TAKEN, count)
NODES[1], NODES[2] = NODES[2], NODES[1]
NODES[1].state, NODES[2].state = 0, 1
PLAYER.map, PLAYER.x, PLAYER.y = 1429, 0.42, 0.65
HME.Player.Refresh()

STEP("when the game refuses, a Fly to button does it with your click")
REFUSE = true
Open()
RunTimers(F.CHECK + 0.1)
check(F.last.button, "a button")
REFUSE = false
local b
for _, f in ipairs(ALL_FRAMES) do if f.__text == "Fly to Darkshire, Duskwood" then b = f end end
check(b and b:IsShown(), "Fly to Darkshire, Duskwood")
Click(b)
eq(TAKEN[#TAKEN], 2, "your click took it")

STEP("nothing to lead to: nothing taken")
HME.Guidance.Stop()
count = #TAKEN
check(Open() == nil, "no destination")
check(F.last.why:find("not taking you anywhere"), F.last.why)
eq(#TAKEN, count)

STEP("/hme flights")
SlashCmdList.HARVESTMATEENHANCED("flights off")
check(not HME.settings.autoFlight, "off")
SlashCmdList.HARVESTMATEENHANCED("flights on")
check(HME.settings.autoFlight, "on")
HME.settings.autoFlight = false

---------------------------------------------------------------------------
STEP("a route HME made leaves the map when you stop following it")
check(not route.shown, "the Duskwood route is hidden after Stop")
local mine = { id = GP.db.nextID, mapID = 1429, name = "My own loop", kinds = {}, sight = 0, color = { 1, 1, 1 }, shown = true,
    points = { 0.40, 0.60, 0.45, 0.62, 0.42, 0.66 } }
GP.db.nextID = GP.db.nextID + 1
table.insert(GP.db.routes, mine)
HME.Guidance.Start(mine)
HME.Guidance.Stop()
check(mine.shown, "your own route stays as you had it")
GP:SetRouteShown(route, true)
HME.Guidance.Start(route)
HME.Guidance.Stop()
check(route.shown, "shown by you on the Routes page: it stays")
GP:SetRouteShown(route, false)

STEP("following another farm hides the one before")
local r2 = { id = GP.db.nextID, mapID = 1429, name = "Elwynn wolves", kinds = {}, sight = 0, color = { 1, 1, 1 }, shown = false,
    points = { 0.40, 0.60, 0.45, 0.62, 0.42, 0.66 }, planned = { prof = "Skinning", key = "test:elwynn" } }
GP.db.nextID = GP.db.nextID + 1
table.insert(GP.db.routes, r2)
HME.Guidance.Start(route)
check(route.shown, "the followed one is drawn")
HME.Guidance.Start(r2)
check(r2.shown, "the new one is drawn")
check(not route.shown, "the one before is gone from the map")
HME.Guidance.Stop()

STEP("once: planned routes earlier versions left drawn are hidden")
local old = { id = GP.db.nextID, mapID = 1429, name = "Old plan", kinds = {}, sight = 0, color = { 1, 1, 1 }, shown = true,
    points = { 0.40, 0.60, 0.45, 0.62, 0.42, 0.66 }, planned = { prof = "Skinning", key = "test:old" } }
GP.db.nextID = GP.db.nextID + 1
table.insert(GP.db.routes, old)
GP.db.leftoversHidden = nil
check(GP:HideLeftovers() >= 1, "hidden")
check(not old.shown and mine.shown, "the plan hidden, your route not")
eq(GP:HideLeftovers(), 0, "only once")

STEP("a planned farm's new route is drawn only when followed")
local res = HME.Recommend.Find({ prof = "Skinning", goal = "level" }, nil, HME.Player.Profile())
local planned = HME.Planner.Create(res[1], "level")
for _ = 1, 200 do if not planned.working then break end Tick(0.016) end
check(not planned.shown, "made hidden")

---------------------------------------------------------------------------
STEP("the soft-target tooltip of a node: short, and out of the middle of the screen")
local HG = ns.HG
local function Tip(name, cx, cy, anchor)
    local t = CreateFrame("GameTooltip", "TestTip" .. math.random(100000), UIParent)
    t.lines = {}
    t.TextLeft1 = t:CreateFontString()
    t.TextLeft1:SetText(name)
    t.AddLine = function(self, text) self.lines[#self.lines + 1] = text end
    t.NumLines = function(self) return 1 + #self.lines end
    t.GetCenter = function() return cx, cy end
    t.GetAnchorType = function() return anchor or "ANCHOR_NONE" end
    t:Show()
    return t
end
UIParent:SetSize(1920, 1080)
local hooks = POSTCALLS[Enum.TooltipDataType.Object]
check(hooks and #hooks >= 3, "HME's hooks around HarvestMate's (" .. #(hooks or {}) .. ")")
local post = { function(tip, data) for _, fn in ipairs(hooks) do fn(tip, data) end end }
local entry = HG.Find("Peacebloom")
check(entry, "Peacebloom known")
local tip = Tip("Peacebloom", 960, 500)
post[1](tip, {})
check(#tip.lines <= 1, "short: at most the next-colour line (" .. #tip.lines .. ")")
local p = tip.__points and tip.__points[#tip.__points]
check(p and p[1] == "BOTTOMRIGHT", "moved to the corner")
HME.settings.worldTooltipDetail = "full"
local full = Tip("Peacebloom", 960, 500)
post[1](full, {})
check(#full.lines > #tip.lines, "full: every line as before (" .. #full.lines .. ")")
HME.settings.worldTooltipDetail = "short"
local cursor = Tip("Peacebloom", 960, 500, "ANCHOR_CURSOR")
cursor.__points = nil
post[1](cursor, {})
check(cursor.__points == nil or #cursor.__points == 0, "a tooltip following the cursor is left where it is")
local corner = Tip("Peacebloom", 1800, 100)
corner.__points = nil
post[1](corner, {})
check(corner.__points == nil or #corner.__points == 0, "one already at the edge stays")
HME.settings.worldTooltipPlace = "game"
local game = Tip("Peacebloom", 960, 500)
game.__points = nil
post[1](game, {})
check(game.__points == nil or #game.__points == 0, "where the game puts it: untouched")
HME.settings.worldTooltipPlace = "corner"
local mailbox = Tip("Mailbox", 960, 500)
mailbox.__points = nil
post[1](mailbox, {})
check(mailbox.__points == nil or #mailbox.__points == 0, "a mailbox's tooltip (not a node HME knows) stays put")
local mini = POSTCALLS[Enum.TooltipDataType.MinimapMouseover]
if mini then
    local m = Tip("Peacebloom", 960, 500)
    for _, fn in ipairs(mini) do fn(m, {}) end
    eq(#m.lines, #full.lines, "minimap tooltips keep every line")
end

STEP("the game's soft-target tooltip off, and back as it was")
CVARS.SoftTargetTooltipInteract = "1"
check(HME.WorldTip.SetSoftTooltip(false), "off")
eq(CVARS.SoftTargetTooltipInteract, "0")
check(HME.WorldTip.SetSoftTooltip(true), "back")
eq(CVARS.SoftTargetTooltipInteract, "1", "as it was")
