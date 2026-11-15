-- The farming HUD in every state it can be in: no text may run outside it.
-- A real-client screenshot (0.4.0) showed a route-only HUD whose title,
-- "Hillsbrad Foothills - Skinning leveling", ran past the panel's right
-- edge: the title had no width, so the game drew it on one long line.
-- Every visible text in the HUD must be bounded: a width that fits inside
-- the panel, or anchors on both sides inside it.

-- The test client gives every frame a width; record which widths were set.
do
    local index = getmetatable(UIParent).__index
    local Methods
    for i = 1, 20 do
        local name, value = debug.getupvalue(index, i)
        if name == "Methods" then Methods = value break end
        if not name then break end
    end
    local setWidth, setSize = Methods.SetWidth, Methods.SetSize
    function Methods:SetWidth(w) rawset(self, "__wset", true) return setWidth(self, w) end
    function Methods:SetSize(w, h) rawset(self, "__wset", true) return setSize(self, w, h) end
end

local ns, HME = LoadHME()
PLAYER.map, PLAYER.x, PLAYER.y = 1424, 0.46, 0.42
CHAR.level = 41
PROFS = { { line = 393, rank = 143, max = 225 } }
HME.Player.Refresh()
HME.settings.hud = true

local function Settle() for _ = 1, 6 do HME.FinishJobs() RunTimers(0.3) Tick(0.3) end end

-- Left edge of a font string inside the HUD, and whether its width is bounded.
local function Bounds(fs, hud)
    local pts = rawget(fs, "__points") or {}
    local left, right, x = false, false, 0
    for _, p in ipairs(pts) do
        local pt = p[1]
        if pt:find("LEFT") then left = true; x = type(p[2]) == "number" and p[2] or (p[4] or 0) end
        if pt:find("RIGHT") then right = true end
    end
    if rawget(fs, "__wset") then return true, x + (fs.__w or 0) end
    return left and right, nil
end

local function Walk(frame, fn)
    for _, c in ipairs(rawget(frame, "__children") or {}) do
        fn(c)
        if rawget(c, "__kind") ~= "FontString" and rawget(c, "__kind") ~= "Texture" then Walk(c, fn) end
    end
end

local function Shown(o, hud)
    local p = o
    while p and p ~= hud do
        if not rawget(p, "__shown") then return false end
        p = rawget(p, "__parent")
    end
    return true
end

local function CheckInside(label)
    HME.HUD.Update()
    local hud = _G.HarvestMateEnhancedHUD
    check(hud and hud:IsShown(), label .. ": the HUD shows")
    local W = hud:GetWidth()
    local n = 0
    Walk(hud, function(c)
        if rawget(c, "__kind") == "FontString" and Shown(c, hud) and (rawget(c, "__text") or "") ~= "" then
            n = n + 1
            local bounded, right = Bounds(c, hud)
            check(bounded, ("%s: %q has no width and no right anchor: it can run outside the HUD"):format(label, c.__text))
            if right and rawget(c, "__parent") == hud then
                check(right <= W + 0.5, ("%s: %q reaches %.0f in a HUD %.0f wide"):format(label, c.__text, right, W))
            end
        end
    end)
    check(n > 0, label .. ": something is written")
end

local LONG = "Hillsbrad Foothills - Skinning leveling"

STEP("a route and no session: the long title stays inside, in every size")
HME.Session.Stop("test")
local route = { name = LONG, mapID = 1424, prof = "Skinning", nodes = {} }
for i = 1, 12 do route.nodes[i] = { x = 0.40 + i * 0.01, y = 0.40 + (i % 3) * 0.02 } end
local ok = pcall(function()
    HME.Routes:AddRoute(route)
end)
local g = HME.Guidance.Active()
if not g then
    -- Guidance from a ranked farm, renamed to the reported title.
    local res = HME.Recommend.Find({ prof = "Skinning", goal = "level" }, nil, HME.Player.Profile())
    HME.Guidance.StartResult(res[1], "level")
    Settle()
    g = HME.Guidance.Active()
end
check(g, "guidance is active")
g.name = LONG
g.stop, g.stops, g.phase = 1, 12, "farm"
g.phaseText = "Following the loop: stop 1 of 12."
check(HME.Session.Current() == nil, "no session")
for _, size in ipairs({ "compact", "normal", "detailed" }) do
    HME.settings.hudSize = size
    CheckInside("route only, " .. size)
end
local hud = _G.HarvestMateEnhancedHUD
check(hud.title and (hud.title:GetText() or ""):find("Hillsbrad Foothills", 1, true), "the zone is the title")
check(hud.sub and (hud.sub:GetText() or ""):find("Skinning leveling", 1, true), "the purpose goes to the second line")

STEP("extremely long, coloured and UTF-8 names")
for _, name in ipairs({
    "Stranglethorn Vale, the Vile Reef and Booty Bay's southern beaches - Skinning leveling (3)",
    "|cffff8000Ashenvale|r - Herbs + Ore - balanced",
    "Zul'Farrak's outskirts — Tanaris: Rugged Leather",
    "Ünïcödé Zöne Ålpha - Fishing",
}) do
    g.name = name
    for _, size in ipairs({ "compact", "normal", "detailed" }) do
        HME.settings.hudSize = size
        CheckInside(name:sub(1, 20) .. ", " .. size)
    end
end
g.name = LONG

STEP("a session and a route, a session alone, paused, idle, nothing recognised")
HME.Session.Start()
local cur = HME.Session.Current()
cur.farm, cur.combat = 43 * 60, 20 * 60
cur.items = { [2318] = 31, [2319] = 24 }
cur.counts.skin = 0
for _, size in ipairs({ "compact", "normal", "detailed" }) do
    HME.settings.hudSize = size
    CheckInside("session and route, nothing recognised, " .. size)
end
cur.counts.skin, cur.skillups, cur.value = 46, 21, 999999999
for _, size in ipairs({ "compact", "normal", "detailed" }) do
    HME.settings.hudSize = size
    CheckInside("session and route, huge value, " .. size)
end
HME.Guidance.Stop()
for _, size in ipairs({ "compact", "normal", "detailed" }) do
    HME.settings.hudSize = size
    CheckInside("session only, " .. size)
end
cur.paused = "manual"
CheckInside("paused")
cur.paused = "idle"
CheckInside("idle")
cur.paused = false
-- A goal with a very long name.
pcall(function() HME.Goals.Add({ type = "item", itemID = 2319, target = 9999 }) end)
for _, gl in ipairs(HME.Goals.List()) do gl.name = "Medium Leather for the Rugged Leather Armor set and the guild bank" end
CheckInside("long goal name")

STEP("the HUD can be put back where it starts")
hud = _G.HarvestMateEnhancedHUD
hud:ClearAllPoints()
hud:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 5000, 5000)
HME.char.ui.hud = { "TOPLEFT", "TOPLEFT", 5000, 5000 }
HME.HUD.ResetPosition()
check(HME.char.ui.hud == nil, "the saved place is forgotten")
local p = hud.__points[1]
eq(p[1], HME.HUD.DEFAULT[1], "back at the default point")
SlashCmdList.HARVESTMATEENHANCED("hud reset")
check(#(ERRORS or {}) == 0, "no errors: " .. tostring(ERRORS and ERRORS[1]))
HME.Session.Stop("test")
