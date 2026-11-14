-- The screens tools/ui_preview.py draws: a level-40 hunter with Skinning 125
-- and Mining 150 in Arathi Highlands, the window on every page, the HUD
-- during a session and the Skinning levels box. Writes build/preview/*.html.
local R = RENDER
local OUT = PREVIEW_OUT or "build/preview"
local only = PREVIEW_ONLY

CHAR.level, CHAR.class = 40, "HUNTER"
PLAYER.map, PLAYER.x, PLAYER.y = 1417, 0.46, 0.52
PROFS = { { line = 393, rank = 125, max = 225 }, { line = 186, rank = 150, max = 225 } }

local ns, HME = LoadHME()
HME.Player.Refresh()

local written = {}
local function Write(name, title, opts)
    if only and not name:find(only, 1, true) then return end
    local f = assert(io.open(OUT .. "/" .. name .. ".html", "wb"))
    f:write(R.Render(title, opts))
    f:close()
    written[#written + 1] = { name = name, title = title }
end

local function Settle()
    for _ = 1, 6 do HME.FinishJobs() RunTimers(0.3) Tick(0.3) end
end

-- Some history, so the pages have something to show.
pcall(function()
    HME.Goals.Add({ type = "item", itemID = 2319, target = 60 })
    HME.Goals.Add({ type = "skill", prof = "Skinning", target = 225 })
end)

local win = HME.OpenWindow("dashboard")
Settle()
local tabs = {}
for _, t in ipairs({ "dashboard", "finder", "goals", "guides", "materials", "stats", "trainers", "setup", "settings" }) do tabs[#tabs + 1] = t end
for key in pairs(win.pages) do
    local seen = false
    for _, t in ipairs(tabs) do if t == key then seen = true end end
    if not seen then tabs[#tabs + 1] = key end
end

for _, key in ipairs(tabs) do
    HME.OpenWindow(key)
    if key == "finder" then HME.Pages.finderSet("Skinning", "level") end
    Settle()
    Write("page-" .. key, "Window: " .. key, { around = win, pad = 30 })
end

-- Farm Finder: best beasts for Medium Leather.
HME.OpenWindow("finder")
HME.Pages.finderSet("Skinning", "material", "Medium Leather")
Settle()
HME.Pages.finderBeasts()
Write("finder-beasts", "Farm Finder: best beasts", { around = win, pad = 30 })
win:Hide()

-- The HUD while farming, and the Skinning levels box.
HME.settings.skinLevels = true
HME.SkinTracker.Update()
pcall(HME.Session.Start)
Settle()
if HME.HUD and HME.HUD.Update then HME.HUD.Update() end
local hud = _G.HarvestMateEnhancedHUD
if hud then Write("hud", "Farming HUD", { around = hud, pad = 20 }) end
local box = _G.HarvestMateEnhancedSkinLevels
if box then Write("skinlevels", "Skinning levels", { around = box, pad = 20 }) end
HME.OpenWindow("dashboard")
Settle()
Write("screen", "The whole screen: window, HUD and Skinning levels")

-- An index to walk through them.
local idx = { '<!doctype html><html><head><meta charset="utf-8"><title>HME previews</title><style>'
    .. 'body{background:#111;color:#ddd;font:14px Segoe UI;margin:20px}a{color:#e8a040}li{margin:4px 0}</style></head><body>'
    .. '<h2>HarvestMate Enhanced, layout previews</h2><p>Renders of the real layout code in the test client, not game screenshots.</p><ul>' }
for _, w in ipairs(written) do idx[#idx + 1] = ('<li><a href="%s.html">%s</a></li>'):format(w.name, w.title) end
idx[#idx + 1] = "</ul></body></html>"
if not only then
    local f = assert(io.open(OUT .. "/index.html", "wb"))
    f:write(table.concat(idx, "\n"))
    f:close()
end
REAL_PRINT(("wrote %d previews to %s"):format(#written, OUT))
