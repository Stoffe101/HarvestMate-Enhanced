-- HarvestMate Enhanced: UI/PageSetup.lua
-- A short setup, never forced: what HME found (professions, Forever-GPS and
-- other addons, price sources, data from the addons it replaces) and the few
-- choices that matter. Anything that would change a key binding or a game
-- setting only asks (the same consent popups as in Settings). On first login
-- HME only says one line in chat; the page is under Setup and /hme setup.
-- Copyright (C) 2026 HarvestMate Enhanced contributors. GPL-3.0-or-later.

local _, ns = ...
local HME = ns.HME
local T = ns.Theme
local K = HME.Kit
local C = T.C

local PAGE_W = 738

-- What was found, as { ok, text } lines (also used by the tests).
function HME.SetupFindings()
    local out = {}
    local profs = {}
    for name, v in pairs(HME.Player.Professions()) do profs[#profs + 1] = ("%s %d"):format(name, v.rank or 0) end
    table.sort(profs)
    out[#out + 1] = { #profs > 0, #profs > 0 and ("Gathering professions: " .. table.concat(profs, ", "))
        or "No gathering profession yet: the Farm Finder can still plan for one (Plan for)." }
    local mode = HME.FGPS and HME.FGPS.Mode()
    local api = _G.ForeverGPS and _G.ForeverGPS.API
    out[#out + 1] = { mode ~= nil, mode == "api" and ("Forever-GPS %s with its API v%s: it takes you to farms; %s"):format(
            tostring(_G.ForeverGPS.VERSION), tostring(api and api.VERSION),
            (api and api.LocalPaths) and "loops follow its walking grid." or "loops stay straight lines (needs API v2 for terrain).")
        or (mode == "panel" and "Forever-GPS found (older version): HME opens its journey panel; you press Go.")
        or "Forever-GPS not installed: HME's own arrow points the way (straight lines)." }
    local prices = HME.Prices.Available()
    out[#out + 1] = { #prices > 0, #prices > 0 and ("Prices from: " .. table.concat(prices, ", "))
        or "No auction prices (Auctionator, TSM or Forever-GPS): profit uses vendor values and says so." }
    local imports = {}
    for _, src in ipairs(HME.Migrate.SOURCES or {}) do
        local old = _G[src.global] or (src.alt and _G[src.alt])
        local done = HME.db.migrations and HME.db.migrations[src.key]
        if type(old) == "table" then imports[#imports + 1] = src.label .. (done and " (imported)" or " (not imported yet)") end
    end
    out[#out + 1] = { true, #imports > 0 and ("Data from: " .. table.concat(imports, ", ")) or "No data from HarvestMate, Gatherpedia or GatherPath to import." }
    local conflicts = HME.Migrate.Conflicts()
    if #conflicts > 0 then
        local names = {}
        for _, c in ipairs(conflicts) do names[#names + 1] = c.label end
        out[#out + 1] = { false, "Still enabled: " .. table.concat(names, ", ") .. ". Dashboard > Import and turn off, then /reload." }
    end
    return out
end

HME.Pages.setup = function(body, page)
    local root = body
    local find = T.Card(root, "What HME found", 0, 0, PAGE_W - 20, 150)
    find.text = K.Label(find, "", { template = "GameFontHighlightSmall", width = PAGE_W - 50 })
    find.text:SetPoint("TOPLEFT", 12, -28)

    local choose = T.Card(root, "Your choices", 0, -158, PAGE_W - 20, 250)
    local y = -30
    local function Row(label, tip, widget)
        local l = K.Label(choose, label, { template = "GameFontHighlight", width = 260 })
        l:SetPoint("TOPLEFT", 12, y)
        widget:SetPoint("TOPLEFT", 290, y + 3)
        if tip then T.Tooltip(widget, label, tip) end
        y = y - 30
    end
    local s = HME.settings
    local nav = K.Segments(choose, { "fgps", "arrow" }, { fgps = "Forever-GPS", arrow = "HME's arrow" },
        function() return s.forevergps == false and "arrow" or "fgps" end,
        function(k) s.forevergps = (k == "fgps"); page.Refresh() end, 120)
    Row("Getting to a farm", "Forever-GPS plans the trip when it is installed; HME's arrow otherwise.", nav)
    local terrain = K.Segments(choose, { "on", "off" }, { on = "Follow terrain", off = "Straight lines" },
        function() return s.terrain == false and "off" or "on" end,
        function(k) s.terrain = (k == "on"); page.Refresh() end, 120)
    Row("Farming loops", "Walk each leg on Forever-GPS's walking grid (API v2) so loops go round hills and lakes.", terrain)
    local map = K.Segments(choose, { "detailed", "simple", "heatmap" }, { detailed = "Detailed", simple = "Simple", heatmap = "Heatmap" },
        function() return s.mapDetail or "detailed" end, function(k) s.mapDetail = k; page.Refresh() end, 100)
    Row("Map", "Detailed: every spawn point. Simple: areas only. Heatmap: density.", map)
    local hud = K.Segments(choose, { "compact", "normal", "detailed" }, { compact = "Compact", normal = "Normal", detailed = "Detailed" },
        function() return s.hudSize or "normal" end, function(k) s.hudSize = k; HME.HUD.Update(); page.Refresh() end, 100)
    Row("HUD while farming", nil, hud)
    local key = K.Button(choose, "One-key gathering...", 180, 22, function() HME.AskGatherKey() end)
    Row("One-key gathering (asks first)", "A key that gathers while you stand at a node. Your saved bindings never change; "
        .. "a popup explains and asks before anything is turned on.", key)
    local soft = K.Button(choose, "Soft target highlighting...", 180, 22, function()
        if ns.HG and ns.HG.EnableSoftTarget then ns.HG.EnableSoftTarget() end
    end)
    Row("Nearby highlighting (asks first)", "Needs the game's Soft Target Interact setting; HME asks before changing it.", soft)

    local doneBtn = K.Button(root, "Done", 120, 28, function()
        HME.db.setupDone = HME.VERSION
        HME.OpenWindow("dashboard")
    end, "You can come back here any time: Setup in the sidebar, or /hme setup.")
    doneBtn:SetPoint("TOPRIGHT", -20, -416)
    doneBtn:SetKind("primary")

    function page.Refresh()
        local lines = {}
        for _, f in ipairs(HME.SetupFindings()) do
            lines[#lines + 1] = (f[1] and "|cff4fd68c✓|r " or "|cfff2c452•|r ") .. f[2]
        end
        find.text:SetText(table.concat(lines, "\n"))
        for _, w in ipairs({ nav, terrain, map, hud }) do w:Refresh() end
    end
end

-- First login with this version's setup not seen: one line, nothing opens.
HME.Listen("DB_READY", function()
    HME.After(8, function()
        if HME.db and not HME.db.setupDone then
            HME.Print("new here, or updated? /hme setup shows what HME found and the few choices that matter (once, never forced).")
        end
    end)
end)
