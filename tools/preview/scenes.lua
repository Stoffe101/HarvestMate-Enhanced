-- The screens and states tools/ui_preview.py draws. The character is the one
-- the first real-client reports came from: level 41, Alliance, Skinning
-- 143/225 and no other gathering profession, in Hillsbrad Foothills, with
-- auction prices for leather, herbs and ore (so gold shows as it does in the
-- game), a long session history, many goals, and the 43-minute session that
-- counted no skins. Every page and its important states, the HUD and the
-- Skinning levels box, and the whole screen at several sizes and UI scales.
-- Writes build/preview/<state>.html and manifest.json.
local R = RENDER
local OUT = PREVIEW_OUT or "build/preview"
local only = PREVIEW_ONLY

local LINES = { Skinning = 393, Herbalism = 182, Mining = 186, Fishing = 356 }
local function Profs(list)
    PROFS = {}
    for prof, v in pairs(list) do PROFS[#PROFS + 1] = { line = LINES[prof], rank = v[1], max = v[2] } end
end

CHAR.level, CHAR.class, CHAR.faction = 41, "WARRIOR", "Alliance"
PLAYER.map, PLAYER.x, PLAYER.y = 1424, 0.46, 0.42   -- Hillsbrad Foothills
Profs({ Skinning = { 143, 225 } })

local ns, HME = LoadHME()
HME.Prices.fixed = {
    [2318] = { low = 2800, typical = 3500 }, [2319] = { low = 5200, typical = 6400 }, [4234] = { low = 11000, typical = 14500 },
    [4304] = { low = 19000, typical = 23000 }, [8170] = { low = 36000, typical = 42000 }, [783] = { low = 4000, typical = 5500 },
    [4232] = { low = 9000, typical = 11000 }, [4235] = { low = 16000, typical = 19500 }, [8169] = { low = 30000, typical = 38000 },
    [2934] = { low = 300, typical = 450 }, [765] = { low = 1500, typical = 2000 }, [2447] = { low = 1800, typical = 2400 },
    [785] = { low = 3500, typical = 4200 }, [2450] = { low = 4500, typical = 5800 }, [2770] = { low = 2500, typical = 3000 },
    [2771] = { low = 4000, typical = 5200 }, [2772] = { low = 9000, typical = 11500 },
}
HME.Prices.Invalidate()
HME.Player.Refresh()

local manifest, written = {}, {}
local SCREEN = { name = "1920×1080, UI scale 1.0", pw = 1920, ph = 1080, scale = 1.0 }

-- A screen in UI units: the game's UI is 768 units tall at UI scale 1.
local function UseScreen(sc)
    local h = 768 / sc.scale
    R.SCREEN_H, R.SCREEN_W = h, h * sc.pw / sc.ph
    UIParent:SetSize(R.SCREEN_W, R.SCREEN_H)
    SCREEN = sc
    if HME.Window.frame then HME.Window.frame:SetUIScale(HME.settings.scale or 1) end
end
UseScreen(SCREEN)

local function Settle()
    for _ = 1, 6 do HME.FinishJobs() RunTimers(0.3) Tick(0.3) end
end

local function Write(name, title, group, opts)
    opts = opts or {}
    if only and not name:find(only, 1, true) then return end
    local zoom = SCREEN.ph / R.SCREEN_H
    opts.zoom = zoom
    local html = R.Render(title, opts)
    local f = assert(io.open(OUT .. "/" .. name .. ".html", "wb"))
    f:write(html)
    f:close()
    local w, h = R.SCREEN_W, R.SCREEN_H
    if opts.around then
        local rr = R.RectOf(opts.around)
        if rr then w, h = rr.r - rr.l + (opts.pad or 24) * 2, rr.t - rr.b + (opts.pad or 24) * 2 end
    end
    manifest[#manifest + 1] = { name = name, title = title, group = group, screen = SCREEN.name, w = w * zoom, h = h * zoom }
    written[#written + 1] = { name = name, title = title }
end

-- A page crop shows the window alone (the HUD and the levels box get their own states).
local function Alone()
    for _, n in ipairs({ "HarvestMateEnhancedHUD", "HarvestMateEnhancedSkinLevels" }) do
        if _G[n] then _G[n]:Hide() end
    end
end
local function Page(key, name, title, group, setup)
    HME.OpenWindow(key)
    if setup then setup() end
    Settle()
    Alone()
    Write(name, title, group, { around = HME.Window.frame, pad = 16 })
end

-- History: 26 sessions over three weeks, so Stats and Records have something real.
local NOW = time()
HME.db.sessions = {}
local zones = { "Skinning@1424", "Skinning@1417", "Skinning@1431", "Skinning@1436" }
for i = 1, 26 do
    local secs = 900 + (i * 397) % 3600
    local skins = math.floor(secs / 60 * (0.9 + (i % 5) * 0.12))
    HME.db.sessions[i] = {
        t = NOW - (27 - i) * 70000, secs = secs, farmSecs = secs, travelSecs = 120 + (i % 4) * 90, combatSecs = secs * 0.45,
        gatherSecs = skins * 2, idleSecs = (i % 3) * 120, totalSecs = secs + 400, value = skins * 5200, skillups = math.floor(skins * 0.4),
        counts = { herb = 0, mine = 0, skin = skins, fish = 0, kills = skins + 4 }, deaths = i % 7 == 0 and 1 or 0,
        items = { [2318] = math.floor(skins * 0.7), [2319] = math.floor(skins * 0.5), [4232] = math.floor(skins * 0.06) },
        areas = { { key = zones[i % 4 + 1], secs = secs, nodes = 0, beasts = skins + 4, skins = skins, catches = 0,
                    skillups = math.floor(skins * 0.4), value = skins * 2100, travel = 120, items = {} } },
        route = i % 3 == 0 and "Hillsbrad bears" or nil,
    }
end

-----------------------------------------------------------------------------
-- 1. The window, page by page (1920×1080 at UI scale 1.0)
-----------------------------------------------------------------------------
local win = HME.OpenWindow("dashboard")
Settle()

Page("dashboard", "dashboard-skinning", "Dashboard: Skinning only, not farming", "Dashboard")

-- The 43-minute session that counted no skins: in combat on and off, no skin seen.
HME.Session.Start()
local cur = HME.Session.Current()
cur.farm, cur.combat, cur.idle, cur.counts.kills = 43 * 60, 21 * 60, 4 * 60, 31
cur.clockStart = HME.Now() - 50 * 60
Page("dashboard", "dashboard-farming-noskins", "Dashboard: farming 43 min, no skins recognised", "Dashboard")

-- The same session going well.
cur.counts.skin, cur.skillups, cur.value = 46, 21, 46 * 2100
cur.items = { [2318] = 31, [2319] = 24, [4232] = 3 }
Page("dashboard", "dashboard-farming", "Dashboard: farming, going well", "Dashboard")
local hudSession = cur

HME.Session.Stop("preview")
HME.db.sessions[#HME.db.sessions] = nil
Profs({ Skinning = { 143, 225 }, Herbalism = { 88, 150 }, Mining = { 201, 300 }, Fishing = { 40, 75 } })
HME.Player.Refresh()
Page("dashboard", "dashboard-all-professions", "Dashboard: all four professions", "Dashboard")
Profs({})
HME.Player.Refresh()
Page("dashboard", "dashboard-no-professions", "Dashboard: no gathering profession", "Dashboard")
Profs({ Skinning = { 143, 225 } })
HME.Player.Refresh()

Page("finder", "finder-level", "Farm Finder: fastest leveling", "Farm Finder", function() HME.Pages.finderSet("Skinning", "level") end)
Page("finder", "finder-profit", "Farm Finder: best profit", "Farm Finder", function() HME.Pages.finderSet("Skinning", "profit") end)
Page("finder", "finder-material", "Farm Finder: Medium Leather", "Farm Finder",
    function() HME.Pages.finderSet("Skinning", "material", "Medium Leather") end)
Page("finder", "finder-beasts", "Farm Finder: best beasts for Medium Leather", "Farm Finder", function()
    HME.Pages.finderSet("Skinning", "material", "Medium Leather")
    Settle()
    HME.Pages.finderBeasts()
end)
Page("finder", "finder-compare", "Farm Finder: comparing two farms", "Farm Finder", function()
    HME.Pages.finderSet("Skinning", "level")
    Settle()
    local res = HME.Pages.finderResults() or {}
    if res[1] then HME.Pages.finderMark(res[1]) end
    if res[2] then HME.Pages.finderMark(res[2]) end
    HME.Pages.finderCompare()
end)
Page("finder", "finder-unlearned", "Farm Finder: a profession you don't have (Herbalism)", "Farm Finder",
    function() HME.Pages.finderSet("Herbalism", "level") end)

Page("goals", "goals-empty", "Goals & Plans: nothing yet", "Goals & Plans")
pcall(function()
    for _, id in ipairs({ 2318, 2319, 4234, 783, 4232, 2934, 765, 2447, 785, 2450, 2770, 2771 }) do
        HME.Goals.Add({ type = "item", itemID = id, target = 20 + (id % 7) * 10 })
    end
    HME.Goals.Add({ type = "skill", prof = "Skinning", target = 225 })
    HME.Goals.Add({ type = "value", target = 500000 })
end)
Page("goals", "goals-many", "Goals & Plans: a long shopping list", "Goals & Plans")

Page("guides", "guides-skinning", "Leveling Guides: Skinning", "Leveling Guides")
Page("materials", "materials", "Materials: the field guide", "Materials")
Page("stats", "stats-history", "Profits & Stats: three weeks of history", "Profits & Stats")
local keep = HME.db.sessions
HME.db.sessions = {}
Page("stats", "stats-empty", "Profits & Stats: no sessions yet", "Profits & Stats")
HME.db.sessions = keep
Page("trainers", "trainers", "Trainers", "Trainers")
for _, key in ipairs({ "routes", "newroute", "taboo", "display" }) do
    if win.pages[key] then Page(key, "routes-" .. key, "Routes and maps: " .. key, "Routes and maps") end
end
Page("setup", "setup", "Setup", "Setup")
Page("settings", "settings", "Settings", "Settings")
win:Hide()

-----------------------------------------------------------------------------
-- 2. On screen while farming: the HUD and the Skinning levels box
-----------------------------------------------------------------------------
HME.Session.Start()
cur = HME.Session.Current()
for k, v in pairs(hudSession) do if type(v) ~= "table" or k == "counts" or k == "items" then cur[k] = v end end
HME.settings.skinLevels = true
HME.SkinTracker.Update()
Settle()
if HME.HUD and HME.HUD.Update then HME.HUD.Update() end
local hud = _G.HarvestMateEnhancedHUD
if hud then Write("hud", "Farming HUD", "On screen", { around = hud, pad = 16 }) end
local box = _G.HarvestMateEnhancedSkinLevels
if box then Write("skinlevels", "Skinning levels", "On screen", { around = box, pad = 16 }) end

-----------------------------------------------------------------------------
-- 3. The whole screen at several sizes and UI scales
-----------------------------------------------------------------------------
local SCREENS = {
    { key = "1280x800-s100", name = "1280×800, UI scale 1.0", pw = 1280, ph = 800, scale = 1.0 },
    { key = "1280x800-s115", name = "1280×800, UI scale 1.15 (largest)", pw = 1280, ph = 800, scale = 1.15 },
    { key = "1366x768-s100", name = "1366×768, UI scale 1.0", pw = 1366, ph = 768, scale = 1.0 },
    { key = "1920x1080-s071", name = "1920×1080, UI scale 0.71 (pixel-perfect)", pw = 1920, ph = 1080, scale = 0.711 },
    { key = "1920x1080-s100", name = "1920×1080, UI scale 1.0", pw = 1920, ph = 1080, scale = 1.0 },
    { key = "2560x1440-s064", name = "2560×1440, UI scale 0.64", pw = 2560, ph = 1440, scale = 0.64 },
    { key = "3440x1440-s080", name = "3440×1440 ultrawide, UI scale 0.8", pw = 3440, ph = 1440, scale = 0.8 },
}
for _, sc in ipairs(SCREENS) do
    UseScreen(sc)
    for _, key in ipairs({ "dashboard", "finder" }) do
        HME.OpenWindow(key)
        if key == "finder" then HME.Pages.finderSet("Skinning", "level") end
        Settle()
        Write("screen-" .. sc.key .. "-" .. key, "Whole screen, " .. key .. ": " .. sc.name, "Screen sizes and UI scales")
    end
end

-----------------------------------------------------------------------------
-- Manifest and index
-----------------------------------------------------------------------------
local function J(s) return '"' .. tostring(s):gsub('\\', '\\\\'):gsub('"', '\\"') .. '"' end
local parts = {}
for _, m in ipairs(manifest) do
    parts[#parts + 1] = ('{"name":%s,"title":%s,"group":%s,"screen":%s,"w":%.0f,"h":%.0f}'):format(J(m.name), J(m.title),
        J(m.group), J(m.screen), m.w, m.h)
end
local f = assert(io.open(OUT .. "/manifest.json", "wb"))
f:write("[" .. table.concat(parts, ",\n") .. "]")
f:close()

local idx = { '<!doctype html><html><head><meta charset="utf-8"><title>HME previews</title><style>'
    .. 'body{background:#111310;color:#e6e4dc;font:14px Segoe UI;margin:20px}a{color:#8fcc5c}li{margin:4px 0}</style></head><body>'
    .. '<h2>HarvestMate Enhanced, layout previews</h2><p>Renders of the real layout code in the test client, not game screenshots. '
    .. 'With --shots: <a href="review.html">the visual review</a>.</p><ul>' }
for _, w in ipairs(written) do idx[#idx + 1] = ('<li><a href="%s.html">%s</a></li>'):format(w.name, w.title) end
idx[#idx + 1] = "</ul></body></html>"
f = assert(io.open(OUT .. "/index.html", "wb"))
f:write(table.concat(idx, "\n"))
f:close()
