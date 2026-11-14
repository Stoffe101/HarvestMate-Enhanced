-- HarvestMate Enhanced: UI/PageSettings.lua
-- Every setting, grouped, each with a tooltip saying what it does. Things
-- that change the player's controls or game settings ask first.
-- Copyright (C) 2026 HarvestMate Enhanced contributors. GPL-3.0-or-later.

local _, ns = ...
local HME = ns.HME
local T = ns.Theme
local K = HME.Kit
local U = HME.U
local C = T.C

local PAGE_W = 738
local COL = 360

HME.Pages.settings = function(body, page)
    local scroll = T.ScrollArea(body, 514)
    local root = scroll.child
    local refreshers = {}
    local y = 0
    local anchors = {}

    local function S() return HME.settings end
    local function HGopt() return ns.HG.db.opt end
    local function Changed()
        HME.Signal("SETTINGS")
        ns.HG.Signal("OPTIONS")
    end

    local EndRow
    local col, rowH = 0, 0
    local function Section(key, title, note)
        EndRow()
        anchors[key] = y
        K.Heading(root, title, 0, y, PAGE_W - 30)
        y = y - 26
        if note then
            local n = K.Label(root, note, { template = "GameFontDisableSmall", width = PAGE_W - 30 })
            n:SetPoint("TOPLEFT", 0, y)
            y = y - (n:GetStringHeight() or 14) - 8
        end
    end

    -- Two columns of rows; Row() places in the next free slot.
    local function NextSlot(h)
        local x = col * COL
        local yy = y
        rowH = math.max(rowH, h or 26)
        if col == 1 then
            y = y - rowH
            col, rowH = 0, 0
        else
            col = 1
        end
        return x, yy
    end
    function EndRow()
        if col == 1 then
            y = y - rowH
            col, rowH = 0, 0
        end
    end

    local function Switch(label, tip, get, set)
        local x, yy = NextSlot()
        local b = T.LabeledSwitch(root, label, x, yy - 4, COL - 50)
        T.Tooltip(b, label, tip)
        b:SetScript("OnClick", function(self)
            if self.disabled then return end
            set(not get())
            self:SetOn(get())
            Changed()
        end)
        refreshers[#refreshers + 1] = function() b:SetOn(get()) end
        return b
    end

    local function Drop(label, tip, keys, labels, get, set)
        local x, yy = NextSlot()
        local l = K.Label(root, label, { template = "GameFontHighlight" })
        l:SetPoint("TOPLEFT", x, yy - 4)
        local d = T.Dropdown(root, 170, keys, labels, get, function(k)
            set(k)
            Changed()
        end)
        d:SetPoint("TOPLEFT", x + COL - 190, yy)
        T.Tooltip(l, label, tip)
        refreshers[#refreshers + 1] = function() d:Refresh() end
        return d
    end

    local function Slider(label, tip, get, set, min, max, step, suffix, fmt)
        local x, yy = NextSlot(48)
        local s = T.Slider(root, label, x, yy, COL - 40, get, function(v)
            set(v)
            HME.Soon("settings-slider", 0.2, Changed)
        end, min, max, suffix, step, fmt)
        T.Tooltip(s, label, tip)
        refreshers[#refreshers + 1] = function() s.Refresh() end
        return s
    end

    local function Button(label, tip, fn, w)
        local x, yy = NextSlot()
        local b = K.Button(root, label, w or 200, 22, fn, tip)
        b:SetPoint("TOPLEFT", x, yy)
        return b
    end

    -------------------------------------------------------------------
    Section("general", "General")
    Drop("Layout", "Expanded shows tab names; compact shows icons only (more room for the pages). Applies when the window reopens.",
        { "expanded", "compact" }, { expanded = "Expanded", compact = "Compact" },
        function() return S().layout end, function(k)
            S().layout = k
            HME.Window.Rebuild()
            HME.After(0.1, function() HME.OpenWindow("settings") end)
        end)
    Drop("Performance", "Low: smaller background work slices and fewer map pins, for slower machines.",
        { "normal", "low" }, { normal = "Normal", low = "Low (lighter)" },
        function() return S().performance end, function(k) S().performance = k end)
    Switch("Minimap button", "The HME button by the minimap. Left-click opens HME, right-click shows or hides the map lines.",
        function() return S().minimapButton end, function(v) S().minimapButton = v end)
    Switch("Chat notifications", "Short notes in chat: imports, arrivals, advice.",
        function() return S().notifications end, function(v) S().notifications = v end)
    Switch("Controller-friendly lists", "Lists keep their selection when they change, so a controller cursor stays put. "
        .. "HME never takes over keys or controller buttons; set 'Next/Previous page' in the game's Key Bindings if you "
        .. "want to page with a key or button.", function() return S().controller end, function(v) S().controller = v end)
    EndRow()
    Drop("Interface font", "Inter, bundled with HME (SIL Open Font License), or the game's own font. Applies after /reload.",
        { "inter", "game" }, { inter = "Inter (modern)", game = "Game font" },
        function() return S().uiFont or "inter" end, function(k) S().uiFont = k; HME.Print("the font changes after /reload.") end)
    Drop("Corners", "Rounded panels and buttons, or square ones. Square is also what HME falls back to where the game "
        .. "cannot draw rounded shapes. Applies after /reload.", { "rounded", "square" }, { rounded = "Rounded", square = "Square" },
        function() return S().uiRounded == false and "square" or "rounded" end,
        function(k) S().uiRounded = (k == "rounded"); HME.Print("corners change after /reload.") end)
    EndRow()
    Slider("Window scale", "Size of HME's window (60-150%).", function() return math.floor((S().scale or 1) * 100 + 0.5) end,
        function(v) S().scale = v / 100 end, 60, 150, 5, "%")

    -------------------------------------------------------------------
    Section("gathering", "Gathering (HarvestMate)",
        "Tooltips, the nearby-resource banner, reminders and one-key gathering. One-key gathering and Soft Target Interact "
        .. "change how a key or the game behaves, so HME asks before turning them on and puts everything back when they are off.")
    local hg = function(k) return function() return HGopt()[k] end, function(v) HGopt()[k] = v end end
    local g1, s1 = hg("enabled")
    Switch("Gathering helpers", "Turn off to keep HarvestMate's tooltips, banner and reminders out of the way.", g1, s1)
    local g2, s2 = hg("nearby")
    Switch("Nearby resource banner", "When the game soft-targets a herb, vein, chest or skinnable corpse: your skill, the "
        .. "requirement, skill-up colors and drops. Needs Soft Target Interact.", g2, s2)
    local gk = Switch("One-key gathering", "While you stand at something you can gather, your chosen key interacts with it. "
        .. "Turning this on asks first and explains exactly what changes.", function() return HGopt().gatherKey end,
        function(v) HME.SetGatherKey(v) end)
    Button("Choose gather key", "Press the key (or mouse button 3-5) to use. Escape cancels. Closes by itself in combat.",
        function() if ns.HG.CaptureGatherKey then ns.HG.CaptureGatherKey() end end, 160)
    local g3, s3 = hg("trainWarn")
    Switch("Trainer reminders", "Says when a new rank can be trained, or when your skill has stopped at the cap.", g3, s3)
    local g4, s4 = hg("trackWarn")
    Switch("Find Herbs / Minerals reminder", "Reminds you when tracking is off (on Forever it resets after dying).", g4, s4)
    local g5, s5 = hg("showLoot")
    Switch("Drops in tooltips", "What a node gives, with chances learned from your own gathering.", g5, s5)
    local g6, s6 = hg("showPrices")
    Switch("Prices in tooltips", "Vendor and auction prices on gathering tooltips.", g6, s6)
    local g7, s7 = hg("announceParty")
    Switch("Announce gathers to group", "Says in group chat what you are gathering (off by default).", g7, s7)
    local g8, s8 = hg("achToast")
    Switch("Achievement pop-ups", "HarvestMate's gathering achievements and records.", g8, s8)
    EndRow()
    Button("Soft Target Interact...", "Asks the game to soft-target objects so the banner and Glimmer can find them. "
        .. "Asks first; '/hme soft off' puts it back.", function() ns.HG.AskSoftTarget() end, 200)
    EndRow()

    -------------------------------------------------------------------
    Section("glimmer", "Glimmer (Gatherpedia)",
        "A glimmer of light on the nearest herb, ore, pool, skinnable beast or lootable the game soft-targets. "
        .. "Your previous soft-target settings come back when it is off; nothing changes in combat.")
    local function GO() return ns.db.sparkle or {} end
    Switch("Glimmer", HME.GlimmerAvailable() and "On or off." or "Paused: Gatherpedia itself is running its own Glimmer.",
        function() return GO().enabled end, function(v) HME.SetGlimmer(v) end)
    for _, kind in ipairs({ { "herbs", "Herbs" }, { "ore", "Ore" }, { "fish", "Fishing pools" }, { "skin", "Skinnable beasts" },
        { "quest", "Quest objects" }, { "other", "Other lootables" } }) do
        Switch("  " .. kind[2], "Glimmer on " .. kind[2]:lower() .. ".", function() return GO()[kind[1]] ~= false end,
            function(v)
                GO()[kind[1]] = v
                if ns.Sparkles and ns.Sparkles.RefreshTarget then pcall(ns.Sparkles.RefreshTarget, ns.Sparkles) end
            end)
    end
    EndRow()
    Button("Preview", "Shows a sample glimmer in the middle of the screen for a few seconds.", function()
        if ns.SparklesUI and ns.SparklesUI.Preview then pcall(ns.SparklesUI.Preview, ns.SparklesUI) end
    end, 120)
    EndRow()

    -------------------------------------------------------------------
    Section("map", "Map and guidance")
    Switch("Arrow", "HME's on-screen arrow to the next stop. Hidden whenever Forever-GPS or TomTom is navigating.",
        function() return S().arrow end, function(v) S().arrow = v; if not v then HME.Arrow.Hide() else HME.Guidance.PointAtStop() end end)
    Switch("Farming HUD", "A small display of the session while a farm is active.", function() return S().hud end,
        function(v) S().hud = v; if HME.HUD then HME.HUD.Update() end end)
    Switch("Skinning levels", "A small box that says which beast levels give Skinning points now, the next level you can skin, "
        .. "beasts in this zone in those levels and your target's colour. Updates as you skin. Also /hme skinlevels.",
        function() return S().skinLevels end, function(v) HME.SkinTracker.Toggle(v) end)
    Switch("Spawn pins for the farm", "Pins on the world map for the farm you preview or follow.", function() return S().nodePins end,
        function(v) S().nodePins = v end)
    Switch("Spawn pins always", "Pins for your gathering professions on every map (busier).", function() return S().nodePinsAlways end,
        function(v) S().nodePinsAlways = v end)
    Switch("Hunting areas", "Shaded areas for skinning farms.", function() return S().huntAreas end, function(v) S().huntAreas = v end)
    Drop("Map detail", "Detailed: a pin per spawn point, grouped where they crowd. Simple: farming areas only. Heatmap: "
        .. "shaded density of spawn points (lighter where data is unconfirmed).", { "detailed", "simple", "heatmap" },
        { detailed = "Detailed pins", simple = "Areas only", heatmap = "Heatmap" },
        function() return S().mapDetail end, function(k) S().mapDetail = k end)
    Drop("Heatmap shows", "Predicted density (bundled spawn data), where you have gathered (your own observations), or "
        .. "density weighted by your skill-up chance. None of them shows live nodes or beasts.", { "density", "observed", "skill" },
        { density = "Predicted density", observed = "Where you gathered", skill = "Skill-up potential" },
        function() return S().heatView end, function(k) S().heatView = k; if HME.MapOverlay then HME.Try(HME.MapOverlay.Draw) end end)
    Drop("Guidance", "Guided: the arrow leads stop by stop. Free: the area stays highlighted, no arrow. Minimal: the arrow fades "
        .. "while you are on the loop. Adaptive: the next stop is the nearest one you have not visited this lap.",
        { "guided", "adaptive", "free", "minimal" }, { guided = "Guided circuit", adaptive = "Adaptive circuit", free = "Free farming", minimal = "Minimal arrow" },
        function() return S().huntMode end, function(k) HME.Guidance.SetMode(k) end)
    Drop("HUD size", "Compact: one line. Detailed: also goals, trip gold and how your time was spent.", { "compact", "normal", "detailed" },
        { compact = "Compact", normal = "Normal", detailed = "Detailed" }, function() return S().hudSize end,
        function(k) S().hudSize = k; if HME.HUD then HME.HUD.Update() end end)
    Switch("Use TomTom for the trip", "Without Forever-GPS: give the way to the farm to TomTom (its arrow) instead of HME's.",
        function() return S().tomtom end, function(v) S().tomtom = v end)
    EndRow()
    Slider("Hunting area opacity", "", function() return S().huntAlpha end, function(v) S().huntAlpha = v end, 10, 80, 5, "%")
    Slider("Stop reached within", "How close a stop has to be to count as reached.", function() return S().arriveYards end,
        function(v) S().arriveYards = v end, 10, 80, 5, " yd")
    Slider("Arrow size", "", function() return math.floor((S().arrowScale or 1) * 100 + 0.5) end,
        function(v) S().arrowScale = v / 100 end, 50, 200, 10, "%")
    Slider("Pin size", "", function() return math.floor((S().pinScale or 1) * 100 + 0.5) end,
        function(v) S().pinScale = v / 100 end, 50, 200, 10, "%")
    EndRow()
    local nRoutes = K.Label(root, "Route lines, colors, widths, arrows and the range circle: Routes and maps, Map display.",
        { template = "GameFontDisableSmall", width = PAGE_W - 30 })
    nRoutes:SetPoint("TOPLEFT", 0, y)
    y = y - 24

    -------------------------------------------------------------------
    Section("finder", "Recommendations",
        "How the Farm Finder ranks. Competition and the planned session length are assumptions you can tune to your realm.")
    Drop("Risk", "How much PvP and creature risk counts against a farm.", { "fastest", "balanced", "safer" },
        { fastest = "Fastest", balanced = "Balanced", safer = "Prefer lower risk" },
        function() return S().riskMode end, function(k) S().riskMode = k end)
    Switch("Suggest the next farm", "Says when your farm has gone grey or a rank opens up.", function() return S().autoGuide end,
        function(v) S().autoGuide = v end)
    EndRow()
    Slider("Competition", "Share of nodes and beasts other players take before you get there.", function() return S().competition end,
        function(v) S().competition = v end, 0, 80, 5, "%")
    Slider("Planned session", "How long you plan to farm: the trip there is spread over this.", function() return S().sessionMinutes end,
        function(v) S().sessionMinutes = v end, 15, 240, 15, " min")
    Slider("Idle after", "No gather, skin, catch or fight for this long: that stretch counts as idle, not farming. "
        .. "Waiting for respawns shorter than this still counts as farming.", function() return S().idleMinutes end,
        function(v) S().idleMinutes = v end, 2, 15, 1, " min")
    EndRow()
    local avoid = T.EditBox(root, 300)
    avoid:SetPoint("TOPLEFT", 0, y)
    local avoidL = K.Label(root, "Zones never to recommend (comma separated)", { template = "GameFontDisableSmall" })
    avoidL:SetPoint("LEFT", avoid, "RIGHT", 8, 0)
    avoid:SetScript("OnEnterPressed", function(self)
        self:ClearFocus()
        local t = {}
        for part in (self:GetText() or ""):gmatch("[^,]+") do
            local z = U.Trim(part)
            if z ~= "" then t[z] = true end
        end
        S().avoidZones = t
        Changed()
    end)
    refreshers[#refreshers + 1] = function() avoid:SetText(table.concat(U.Keys(S().avoidZones or {}, true), ", ")) end
    y = y - 32

    -------------------------------------------------------------------
    Section("suggest", "Suggestions", "Short, rate-limited hints on the Dashboard (and in chat if notifications are on).")
    for _, kind in ipairs(HME.Suggest.KINDS) do
        Switch(kind.label, "Show this kind of suggestion.", function() return HME.Suggest.Enabled(kind.key) end, function(v)
            S().suggest = type(S().suggest) == "table" and S().suggest or {}
            S().suggest[kind.key] = v and nil or false
        end)
    end
    EndRow()

    -------------------------------------------------------------------
    Section("prices", "Prices",
        "HME reads prices other addons already have; it never scans, buys, sells or posts anything.")
    Drop("Price source", "Auto uses the first available: Forever-GPS, Auctionator, TSM, then vendor.",
        { "auto", "ForeverGPS", "Auctionator", "TSM", "vendor" },
        { auto = "Auto", ForeverGPS = "Forever-GPS", Auctionator = "Auctionator", TSM = "TradeSkillMaster", vendor = "Vendor only" },
        function() return S().priceProvider end, function(k) S().priceProvider = k end)
    Drop("Estimate", "Which of the three estimates rankings use.", { "conservative", "typical", "optimistic" },
        { conservative = "Conservative", typical = "Typical", optimistic = "Optimistic" },
        function() return S().priceMode end, function(k) S().priceMode = k end)
    Drop("Sell to", "Auction house, vendor, or whichever pays more for each item.", { "best", "auction", "vendor" },
        { best = "Whichever pays more", auction = "Auction house", vendor = "Vendor" },
        function() return S().saleMode end, function(k) S().saleMode = k end)
    Drop("Skinning profit", "Skinning materials only, or with the mob's ordinary loot (what you actually looted).",
        { "skinning", "total" }, { skinning = "Materials only", total = "Total farming value" },
        function() return S().profitScope end, function(k) S().profitScope = k end)
    EndRow()

    -------------------------------------------------------------------
    Section("integrations", "Other addons", "All optional. HME checks each before using it and works without any of them.")
    Switch("Forever-GPS", "Long journeys go through Forever-GPS; HME takes over at the farm.", function() return S().forevergps end,
        function(v) S().forevergps = v end)
    Switch("GatherMate2 nodes", "Add GatherMate2's recorded nodes to the bundled spawn data.", function() return S().gathermate end,
        function(v) S().gathermate = v; HME.Spawns.Invalidate() end)
    EndRow()
    local integ = K.Label(root, "", { template = "GameFontDisableSmall", width = PAGE_W - 30 })
    integ:SetPoint("TOPLEFT", 0, y)
    refreshers[#refreshers + 1] = function() integ:SetText(HME.IntegrationLine()) end
    y = y - 30

    -------------------------------------------------------------------
    Section("data", "Your data", "Learned nodes, skins, sessions and rates are kept per account; plans and efficiency per character.")
    local size = K.Label(root, "", { template = "GameFontHighlightSmall", width = PAGE_W - 30 })
    size:SetPoint("TOPLEFT", 0, y)
    refreshers[#refreshers + 1] = function()
        local z = HME.DBM.Size()
        size:SetText(("%d learned nodes on %d maps · %d beasts skinned · %d sessions · %d measured areas · %d routes")
            :format(z.nodes, z.maps, z.skins, z.sessions, z.areas, z.routes))
    end
    y = y - 22
    local io = T.EditBox(root, PAGE_W - 30)
    io:SetPoint("TOPLEFT", 0, y)
    y = y - 30
    Button("Export routes and areas", "Puts your routes, avoid areas and skip list in the box above, to copy and share.", function()
        io:SetText(HME.DBM.Export({ routes = true, taboos = true }))
        io:HighlightText()
        io:SetFocus()
    end)
    Button("Import from the box", "Adds routes, avoid areas and nodes from an export pasted above. Never replaces what you have.", function()
        local data, err = HME.DBM.ReadImport(io:GetText())
        if not data then HME.Print("import: " .. err) return end
        local added = HME.DBM.ApplyImport(data)
        HME.Print(("imported %d routes, %d avoid areas, %d nodes."):format(added.routes, added.taboos, added.nodes))
    end)
    Button("Reset settings", "Puts every HME setting back to its default (asks first).", function()
        HME.Routes:Confirm("Put every HarvestMate Enhanced setting back to its default? Routes and learned data stay.",
            "Reset", function() HME.DBM.ResetSettings(); page.Refresh() end)
    end)
    Button("Forget learned data", "Clears learned nodes, skins, sessions and measured rates (asks first; routes stay).", function()
        HME.Routes:Confirm("Forget everything HME has learned (nodes, skins, sessions, measured rates)? This can't be undone. "
            .. "Export first if you want a copy.", "Forget", function() HME.DBM.ResetLearned(); page.Refresh() end)
    end)
    EndRow()
    y = y - 10

    scroll:SetContent(PAGE_W - 20, -y + 20)

    function page.Refresh()
        for _, fn in ipairs(refreshers) do HME.Try(fn) end
        gk:SetOn(HGopt().gatherKey)
    end
    function page.Focus(key)
        local at = anchors[key]
        if at and scroll.bar then scroll.bar:SetValue(-at) end
    end
end
