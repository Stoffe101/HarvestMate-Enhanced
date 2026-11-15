-- HarvestMate Enhanced: Core/Diagnostics.lua
-- A short, human-readable report to copy after an in-game test (/hme diag):
-- versions, integrations, professions, the map and route you are on, who owns
-- navigation, recent errors, recent loot decisions, timings and data status.
--
-- Privacy: no character, realm or account names, no chat, no GUIDs (creature
-- IDs only), no coordinates of other players. Nothing is sent anywhere: the
-- text sits in a box for you to select and copy (Ctrl+A, Ctrl+C) yourself.
-- Copyright (C) 2026 HarvestMate Enhanced contributors. GPL-3.0-or-later.

local _, ns = ...
local HME = ns.HME
local U = HME.U

local D = {}
HME.Diagnostics = D

D.ERRORS_KEPT = 10
D.errors = {}

-- Every error HME catches is kept (newest 10), without GUIDs or names.
local function Scrub(text)
    text = tostring(text or "")
    text = text:gsub("%a+%-%d+%-%d+%-%d+%-%d+%-%d+%-%x+", "<guid>")   -- creature/player GUIDs
    text = text:gsub("Player%-%d+%-%x+", "<player>")
    local name = UnitName and HME.Str((UnitName("player")))
    if name and #name > 1 then text = text:gsub(name, "<you>") end
    local realm = GetRealmName and HME.Str(GetRealmName())
    if realm and #realm > 1 then text = text:gsub(realm:gsub("%p", "%%%0"), "<realm>") end
    return text
end
D.Scrub = Scrub

function D.NoteError(err)
    U.Push(D.errors, { t = HME.Now(), text = Scrub(err):sub(1, 400) }, D.ERRORS_KEPT)
end

local function Version(addon)
    local get = (C_AddOns and C_AddOns.GetAddOnMetadata) or _G.GetAddOnMetadata
    if not get then return nil end
    local ok, v = pcall(get, addon, "Version")
    return ok and HME.Str(v) or nil
end

local function Loaded(addon)
    local f = (C_AddOns and C_AddOns.IsAddOnLoaded) or _G.IsAddOnLoaded
    if not f then return false end
    local ok, v = pcall(f, addon)
    return ok and v and true or false
end

-- The report, as lines.
function D.Lines()
    local out = {}
    local function Add(fmt, ...) out[#out + 1] = select("#", ...) > 0 and fmt:format(...) or fmt end
    Add("HarvestMate Enhanced %s report", tostring(HME.VERSION))
    local build, _, _, iface = "?", nil, nil, nil
    if GetBuildInfo then
        local ok, v, b, d, i = pcall(GetBuildInfo)
        if ok then build, iface = ("%s (%s)"):format(tostring(v), tostring(b)), i end
    end
    Add("Client %s, interface %s, locale %s", build, tostring(iface or "?"), tostring(GetLocale and GetLocale() or "?"))
    -- Integrations
    local fg = _G.ForeverGPS
    local api = type(fg) == "table" and type(fg.API) == "table" and fg.API or nil
    Add("Forever-GPS: %s%s; navigation mode %s; walking grid API %s; arrow hold %s",
        fg and tostring(fg.VERSION) or "not installed", api and (" (API v" .. tostring(api.VERSION) .. ")") or "",
        tostring(HME.FGPS and HME.FGPS.Mode() or "none"),
        (api and api.LocalPaths) and "yes" or "no", (HME.FGPS and HME.FGPS.CanHoldArrow()) and "yes" or "no")
    local others = {}
    for _, a in ipairs({ "TomTom", "GatherMate2", "Auctionator", "TradeSkillMaster", "Questie", "HarvestMate", "Gatherpedia", "GatherPathForever" }) do
        if Loaded(a) then others[#others + 1] = a .. (Version(a) and (" " .. Version(a)) or "") end
    end
    Add("Other addons loaded: %s", #others > 0 and table.concat(others, ", ") or "none of the known ones")
    Add("Prices: %s", #HME.Prices.Available() > 0 and table.concat(HME.Prices.Available(), ", ") or "vendor only")
    -- The interface, for layout reports: what is shown, where, and in which font.
    do
        local st = HME.settings or {}
        local hud = HME.HUD and HME.HUD.Frame and HME.HUD.Frame()
        local T = ns.Theme
        local inter = T and T.FontObject and T.FontObject("body") ~= nil
        local win = HME.Window and HME.Window.frame
        local hw = hud and hud.GetWidth and hud:GetWidth()
        Add("Interface: font %s%s; corners %s; window scale %s (fitted %s); HUD %s, %s, %s%s; Skinning levels %s",
            inter and "Inter" or "game font", st.uiFont == "game" and " (chosen)" or (inter and "" or " (Inter did not load)"),
            st.uiRounded == false and "square" or "rounded", tostring(st.scale or 1),
            win and win.fitScale and ("%.2f"):format(win.fitScale) or "-",
            (hud and hud:IsShown()) and ("shown, %d wide"):format(hw or 0) or "hidden", tostring(st.hudSize or "normal"),
            st.hudLocked and "locked" or "movable", (HME.char and HME.char.ui and HME.char.ui.hud) and ", moved by you" or "",
            (HME.SkinTracker and HME.SkinTracker.Shown and HME.SkinTracker.Shown()) and "shown" or "hidden")
    end
    -- Character (no name): level, faction, professions
    local profile = HME.Player.Profile()
    local profs = {}
    for name, v in pairs(HME.Player.Professions()) do profs[#profs + 1] = ("%s %d/%d"):format(name, v.rank or 0, v.max or 0) end
    table.sort(profs)
    Add("Character: level %d %s; %s", profile.level or 0, tostring(profile.faction), #profs > 0 and table.concat(profs, ", ") or "no gathering professions")
    -- Where (map only)
    local mapID, x, y = HME.Player.Position()
    local zm, zx, zy
    if mapID then zm, zx, zy = HME.Geo.ZoneOf(mapID, x, y) end   -- not `a and f()`: that keeps one value
    Add("Map: %s (%s) at %s; zone size %s", tostring(mapID), tostring(HME.ZoneData.Name(zm or mapID) or "?"),
        zx and ("%.1f, %.1f"):format(zx * 100, zy * 100) or "no position",
        (zm and HME.Geo.MapYards(zm)) and "known" or "unknown")
    -- Guidance and navigation ownership
    local g = HME.Guidance.Active()
    if g then
        local route = HME.Guidance.Route(g.routeID)
        Add("Following: route %s '%s', phase %s, mode %s, stop %s/%s, travel owner %s, arrow %s, presentation %s%s",
            tostring(g.routeID), tostring(g.name), tostring(g.phase), tostring(g.mode), tostring(g.stop), tostring(g.stops),
            tostring(g.owner), tostring(HME.Guidance.ArrowOwner()), tostring(g.present),
            g.tookOver and (", guide-me-here" .. (g.holdID and " (Forever-GPS arrow held)" or " (no hold)")) or "")
        if route then
            local q = HME.RouteEditor.Quality(route)
            Add("Route: %d stops, %s, %s; %s", #route.points / 2, U.Yards(route.length or 0), q.label, q.text)
        end
    else
        Add("Following: nothing")
    end
    local req = HME.char and HME.char.fgpsRequest
    if req then Add("Forever-GPS request: %s, state %s, mode %s%s", tostring(req.token), tostring(req.state), tostring(req.mode),
        req.apiToken and (", API token " .. tostring(req.apiToken)) or "") end
    local journey = HME.FGPS and HME.FGPS.CurrentJourney()
    Add("Forever-GPS journey now: %s", journey and ("to map %s %.1f, %.1f%s"):format(tostring(journey.mapID),
        (journey.x or 0) * 100, (journey.y or 0) * 100, journey.token and (" (" .. journey.token .. ")") or " (not an API journey)") or "none")
    -- Recorder, expedition, session
    local rec = HME.Recorder and HME.Recorder.State()
    if rec then Add("Recording: %s, map %d, %d points, %s, %s", rec.state, rec.mapID, #rec.points / 2, U.Yards(rec.yards), U.Duration(rec.secs)) end
    local exp = HME.Expedition and HME.Expedition.Current()
    if exp then Add("Expedition: stage %d of %d", exp.current or 0, #exp.stages) end
    local r = HME.Session.Rates()
    if r then
        Add("Session: %s farming, %s travel, %d nodes, %d skins, %d kills, %d catches, %d skill-ups%s", U.Duration(r.farmSecs),
            U.Duration(r.travelSecs), r.nodes, r.skins, r.kills, r.catches, r.skillups, r.paused and (" (paused: " .. tostring(r.paused) .. ")") or "")
    end
    -- Skin detection: HME's own count against HarvestMate's skinning loot.
    local det = HME.Learning.detect
    if det then
        Add("Skin detection: %d skins counted (%d by the backstop, %d uncertain: no creature named), HarvestMate saw %d "
            .. "skinning loots; %d skin casts failed or were interrupted; %d loot windows without a source", det.skins + det.backstop
            + (det.uncertain or 0), det.backstop, det.uncertain or 0, det.gatherSkins, det.failed or 0, det.unattributed or 0)
    end
    -- 0.6.0: the Copilot, the prediction ledger, quests, notices (no names, no positions).
    if HME.Copilot then
        local ctx = HME.Copilot.ctx or {}
        local top = HME.Copilot.cards and HME.Copilot.cards[1]
        Add("Copilot: mode %s, %s min, profession %s (%s), %d cards, top: %s; searches cached %d",
            HME.Copilot.Mode(), tostring(HME.Copilot.Minutes()), tostring(ctx.prof), tostring(ctx.profWhy),
            #(HME.Copilot.cards or {}), top and top.type or "none", U.Count(HME.Copilot.searches or {}))
    end
    if HME.Ledger then
        local rep = HME.Ledger.Report()
        local parts = {}
        for _, pf in ipairs(rep.profs) do
            parts[#parts + 1] = ("%s x%.2f (%d sessions%s)"):format(pf.prof, pf.pace.factor, pf.pace.sessions, pf.pace.used and ", used" or "")
        end
        Add("Prediction ledger: %d entries; %s", rep.entries, #parts > 0 and table.concat(parts, "; ") or "no factor yet")
    end
    if HME.QuestSynergy then Add("Quests: %s", HME.QuestSynergy.Status()) end
    if HME.Notify then Add("Notices: %d kept, %d unread", #HME.Notify.List(), HME.Notify.Unread()) end
    -- 0.7.0: counts only (no names, no positions).
    if HME.Danger then Add("Danger map: %s", HME.Danger.Status()) end
    if HME.Trends then Add("Price history: %s", HME.Trends.Status()) end
    if HME.Alts then Add("Characters: %d remembered", #HME.Alts.List()) end
    if HME.MapOverlay and HME.MapOverlay.LayersOn then
        local on = {}
        for _, k in ipairs(HME.MapOverlay.LAYERS) do if HME.MapOverlay.Layer(k) then on[#on + 1] = k end end
        Add("Map layers: %s; HUD Copilot line %s", #on > 0 and table.concat(on, ", ") or "none",
            HME.settings.hudCopilot and "on" or "off")
    end
    -- Loot decisions (creature IDs only)
    local recent = HME.Learning.recent or {}
    if #recent > 0 then
        Add("Recent loot decisions (newest last):")
        for i = math.max(1, #recent - 7), #recent do
            local e = recent[i]
            Add("  %s npc %s, %d items: %s", e.kind, tostring(e.npc or "-"), e.items or 0, tostring(e.how))
        end
    end
    -- Errors
    if #D.errors > 0 then
        Add("Errors caught (newest last):")
        for _, e in ipairs(D.errors) do Add("  [%.0f s ago] %s", HME.Now() - e.t, e.text) end
    else
        Add("Errors caught: none")
    end
    for _, p in ipairs(HME.dataProblems or {}) do Add("Data problem: %s", p) end
    if (HME.repaired or 0) > 0 then Add("Saved data repaired at load: %d entries", HME.repaired) end
    local z = HME.DBM.Size()
    Add("Saved data: %d learned nodes on %d maps, %d sessions, %d areas, %d routes, %d corrections, %d walked legs",
        z.nodes, z.maps, z.sessions, z.areas, z.routes, HME.Corrections and #HME.Corrections.List() or 0,
        HME.db and HME.db.terrain and #(HME.db.terrain.order or {}) or 0)
    if #HME.missingEvents > 0 then Add("Events this client lacks: %s", table.concat(HME.missingEvents, ", ")) end
    local perf = HME.Perf.Lines()
    if #perf > 0 then
        Add("Timings:")
        for _, l in ipairs(perf) do Add("  %s", l) end
    end
    for i = 1, #out do out[i] = Scrub(out[i]) end
    return out
end

function D.Text() return table.concat(D.Lines(), "\n") end

-- A window with the report selected, ready to copy. Never in combat.
local frame
function D.Show()
    if HME.InCombat() then
        HME.Print("the report opens after combat (/hme diag chat prints it now).")
        return false
    end
    if not frame then
        frame = CreateFrame("Frame", "HarvestMateEnhancedDiagnostics", UIParent, "BackdropTemplate")
        frame:SetSize(620, 420)
        frame:SetPoint("CENTER")
        frame:SetFrameStrata("DIALOG")
        if frame.SetBackdrop then
            frame:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
            frame:SetBackdropColor(0.06, 0.06, 0.07, 0.97)
            frame:SetBackdropBorderColor(0.3, 0.3, 0.3, 1)
        end
        frame:EnableMouse(true)
        frame:SetMovable(true)
        frame:RegisterForDrag("LeftButton")
        frame:SetScript("OnDragStart", frame.StartMoving)
        frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
        local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        title:SetPoint("TOPLEFT", 12, -10)
        title:SetText("HarvestMate Enhanced diagnostics: Ctrl+A, Ctrl+C to copy (nothing is sent anywhere)")
        local scroll = CreateFrame("ScrollFrame", nil, frame, "UIPanelScrollFrameTemplate")
        scroll:SetPoint("TOPLEFT", 12, -32)
        scroll:SetPoint("BOTTOMRIGHT", -32, 40)
        local box = CreateFrame("EditBox", nil, scroll)
        box:SetMultiLine(true)
        box:SetAutoFocus(false)
        box:SetFontObject("ChatFontSmall")
        box:SetWidth(560)
        box:SetScript("OnEscapePressed", function(self) self:ClearFocus() frame:Hide() end)
        scroll:SetScrollChild(box)
        frame.box = box
        local close = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
        close:SetSize(100, 22)
        close:SetPoint("BOTTOMRIGHT", -12, 10)
        close:SetText("Close")
        close:SetScript("OnClick", function() frame:Hide() end)
        local refresh = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
        refresh:SetSize(100, 22)
        refresh:SetPoint("RIGHT", close, "LEFT", -8, 0)
        refresh:SetText("Refresh")
        refresh:SetScript("OnClick", function() D.Show() end)
    end
    frame.box:SetText(D.Text())
    frame.box:HighlightText()
    frame.box:SetFocus()
    frame:Show()
    return true
end

-- Combat closes the box (it holds the keyboard while focused).
HME.On("PLAYER_REGEN_DISABLED", function()
    if frame and frame:IsShown() then
        frame.box:ClearFocus()
        frame:Hide()
    end
end)
