-- HarvestMate Enhanced: Routes/RoutesUI.lua
-- The route pages of HME's window: Routes, New route, Avoid areas (GatherPath's
-- "taboo areas") and Map display. Adapted from GatherPath Forever 1.12.1
-- Options.lua by severd8 (MIT). The pages are built by UI/Window.lua from
-- GP.CONFIG_TABS; this file no longer makes a window of its own.
--
-- Layout rules: rows 26 apart; a dropdown after a row label starts at DROP_X;
-- lists that can grow (routes, kinds of node) scroll.

local ADDON, ns = ...
local GP = ns.GP
local HME = ns.HME
local T = ns.Theme
local C, Text, FlatButton, Card = T.C, T.Text, T.FlatButton, T.Card
local U = HME.U

-- HME's window gives a page 738 wide (GatherPath's own window gave 540).
local PAGE_W = 738   -- (UI/Window.lua: 940 wide, a 170 sidebar; this file loads first)
local WINDOW_H = T.WINDOW.H + 120   -- taller than the other addons' windows: room for more nodes
local BODY_H = T.BodyHeight(WINDOW_H)
local DROP_X = 52
local COL2 = 270

local refreshers = {}
local function AddRefresher(fn) table.insert(refreshers, fn) end

-- The window's widgets the tests look at
local refs = {}
GP.ui = refs

-- A colored square that opens the game's color picker. get(self) is the color
-- now ({ r, g, b }, nil = nothing to pick), set(self, r, g, b) keeps a new one.
local function Swatch(parent, get, set, title, tip)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(22, 22)
    b.fill = T.Fill(b, { 1, 1, 1, 1 }, "ARTWORK")
    T.Border(b, C.edge)
    function b:Paint(c) self.fill:SetColorTexture(c[1], c[2], c[3], 1) end
    T.Disabler(b, { b })
    b:SetScript("OnClick", function(self)
        local now = not self.disabled and get(self)
        local picker = ColorPickerFrame
        if not (now and picker and picker.SetupColorPickerAndShow) then return end
        local before = { unpack(now) }
        picker:SetupColorPickerAndShow({
            r = before[1], g = before[2], b = before[3], hasOpacity = false,
            swatchFunc = function()
                local r, g, bl = picker:GetColorRGB()
                set(self, r, g, bl)
            end,
            cancelFunc = function()
                set(self, before[1], before[2], before[3])
            end,
        })
    end)
    T.Tooltip(b, title, tip)
    return b
end

---------------------------------------------------------------------------
-- A small "are you sure" window
---------------------------------------------------------------------------
function GP:Confirm(text, yesLabel, onYes)
    local f = self.confirmWindow
    if not f then
        f = CreateFrame("Frame", "HarvestMateEnhancedConfirm", UIParent)
        f:SetSize(380, 130)
        f:SetPoint("CENTER", 0, 80)
        f:SetFrameStrata("FULLSCREEN_DIALOG")
        f:SetToplevel(true)
        f:EnableMouse(true)
        f:Hide()
        table.insert(UISpecialFrames, "HarvestMateEnhancedConfirm")   -- Escape is Cancel
        T.Fill(f, C.win)
        T.Border(f, C.edge)
        f.text = Text(f, "", "GameFontHighlight")
        f.text:SetPoint("TOPLEFT", 16, -16)
        f.text:SetWidth(348)
        f.text:SetWordWrap(true)
        f.no = FlatButton(f, "Cancel", 100)
        f.no:SetPoint("BOTTOMRIGHT", -16, 14)
        f.no:SetScript("OnClick", function() f:Hide() end)
        f.yes = FlatButton(f, "", 120)
        f.yes:SetPoint("RIGHT", f.no, "LEFT", -8, 0)
        self.confirmWindow = f
    end
    f.text:SetText(text)
    f.yes:SetText(yesLabel)
    f.yes:SetScript("OnClick", function()
        f:Hide()
        onYes()
    end)
    f:Show()
    return f
end

---------------------------------------------------------------------------
-- Routes tab
---------------------------------------------------------------------------
local ROW_H = 92   -- room for three lines of what the route is
local INFO_W = PAGE_W - 16 - 84 - 40 - 10   -- from under the name to Show
local routesZone   -- the map whose routes are listed

local function RoutesZoneChoices()
    local list = GP:RouteZones()
    local here = GP:PlayerMap()
    local has = false
    for _, m in ipairs(list) do if m == here then has = true end end
    if here and not has then table.insert(list, 1, here) end
    return list
end

local function PickRoutesZone()
    local list = RoutesZoneChoices()
    for _, m in ipairs(list) do if m == routesZone then return end end
    local here = GP:PlayerMap()
    if here and #GP:RoutesOn(here) > 0 then routesZone = here return end
    routesZone = GP:RouteZones()[1] or here
end

local function BuildRoutes(p)
    T.RowLabel(p, "Zone", 0, 0)
    local zone = T.Dropdown(p, 300, {}, function(k) return GP:MapName(k) end,
        function() return routesZone end, function(k) routesZone = k; GP:RefreshConfig() end)
    zone:SetPoint("TOPLEFT", DROP_X, 0)
    zone.menuScroll = 300
    refs.routesZone = zone

    local make = FlatButton(p, "New route", 110)
    make:SetPoint("TOPRIGHT", 0, 0)
    make:SetScript("OnClick", function() GP:NewRouteInWindow(routesZone) end)
    T.Tooltip(make, "New route", "Make a route in the zone picked here.")
    refs.routesNew = make

    -- HME: Record my route.
    local rec = FlatButton(p, "Record my route", 140)
    rec:SetPoint("RIGHT", make, "LEFT", -8, 0)
    rec:SetScript("OnClick", function()
        local R = HME.Recorder
        if R.Active() then R.Stop() else
            local ok, why = R.Start()
            if not ok then HME.Print("can't record: " .. tostring(why) .. ".") end
        end
        GP:RefreshConfig()
    end)
    T.Tooltip(rec, "Record my route", "Ride round your farm the way you like: HME writes your path down once a "
        .. "second (standing still writes nothing) and saves it as a route you can edit, reverse, trim, export and "
        .. "follow. What you gather on the way is kept with it. /hme rec pause | resume | cancel.")
    refs.routesRec = rec
    HME.Listen("RECORDING_CHANGED", function()
        rec:SetText((HME.Recorder and HME.Recorder.Active()) and "Stop & save" or "Record my route")
    end)

    local holder = CreateFrame("Frame", nil, p)
    holder:SetPoint("TOPLEFT", 0, -34)
    holder:SetSize(PAGE_W, BODY_H - 34)
    local scroll = T.ScrollArea(holder, BODY_H - 34)
    local list = scroll.child
    local empty = T.Note(p, "", 0, -44, PAGE_W)
    refs.routesEmpty = empty
    local rows = {}
    refs.routeRows = rows

    local function Row(i)
        if rows[i] then return rows[i] end
        local r = CreateFrame("Frame", nil, list)
        r:SetSize(PAGE_W - 16, ROW_H - 6)
        T.Fill(r, C.card)
        T.Border(r, C.line)
        -- top: color, name, Edit, Rebuild, Delete; below: what it is, Show
        r.swatch = Swatch(r,
            function(b) return b.route and b.route.color end,
            function(b, cr, cg, cb) GP:SetRouteColor(b.route, cr, cg, cb) end,
            "Line color", "Click to pick the color of this route's line.")
        r.swatch:SetPoint("TOPLEFT", 10, -8)
        r.name = T.EditBox(r, 190)
        r.name:SetPoint("LEFT", r.swatch, "RIGHT", 8, 0)
        local function rename(self)
            if r.route and self:GetText() ~= r.route.name then GP:RenameRoute(r.route, self:GetText()) end
            if r.route then self:SetText(r.route.name) end
        end
        r.name:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
        r.name:SetScript("OnEditFocusLost", rename)
        r.edit = FlatButton(r, "Edit", 60, 20)
        r.edit:SetPoint("LEFT", r.name, "RIGHT", 8, 0)
        r.edit:SetScript("OnClick", function(self)
            if self.disabled or not r.route then return end
            GP:EditRouteInWindow(r.route)
        end)
        T.Disabler(r.edit, { r.edit })
        T.Tooltip(r.edit, "Edit", "Change this route's zone, nodes, name and pass distance, "
            .. "then find its loop again.")
        r.rebuild = FlatButton(r, "Rebuild", 76, 20)
        r.rebuild:SetPoint("LEFT", r.edit, "RIGHT", 6, 0)
        r.rebuild:SetScript("OnClick", function(self)
            if self.disabled or not r.route then return end
            local route = r.route
            if route.edited or route.recorded then
                GP:Confirm(("|cffffd100%s|r was %s. Rebuilding works the loop out again and replaces those waypoints."):format(
                    route.name, route.edited and "edited by hand" or "recorded in game"), "Rebuild", function() GP:RebuildRoute(route, true) end)
                return
            end
            GP:RebuildRoute(route)
        end)
        T.Disabler(r.rebuild, { r.rebuild })
        T.Tooltip(r.rebuild, "Rebuild", "Reads this route's nodes from GatherMate2 again (it may know more by now) "
            .. "and finds the shortest loop again.")
        r.delete = FlatButton(r, "Delete", 70, 20)
        r.delete:SetPoint("LEFT", r.rebuild, "RIGHT", 6, 0)
        r.points = FlatButton(r, "Waypoints", 90, 20)
        r.points:SetPoint("LEFT", r.delete, "RIGHT", 6, 0)
        r.points:SetScript("OnClick", function() if r.route then HME.RouteEditor.Start(r.route) end end)
        T.Tooltip(r.points, "Waypoints", "Edit this route on the world map: left-click adds a waypoint, right-click removes one, "
            .. "with Reverse, Undo and Cancel. Use it to steer round a cliff or into a cave entrance.")
        r.inspect = FlatButton(r, "Inspect", 70, 20)
        r.inspect:SetScript("OnClick", function() if r.route then GP:InspectRoute(r.route) end end)
        T.Tooltip(r.inspect, "Inspect", "Length, lap time, how much follows the terrain, legs to check, what it is for, "
            .. "and how it went for you.")
        r.follow = FlatButton(r, "Follow", 70, 20)
        r.follow:SetPoint("LEFT", r.points, "RIGHT", 6, 0)
        r.follow:SetScript("OnClick", function() if r.route then HME.Guidance.Start(r.route) end end)
        r.inspect:SetPoint("LEFT", r.follow, "RIGHT", 6, 0)
        T.Tooltip(r.follow, "Follow", "Guide me round this route (Forever-GPS takes the trip there if it is far).")
        r.info = Text(r, "", "GameFontDisableSmall")
        r.info:SetPoint("TOPLEFT", 40, -38)
        r.info:SetWidth(INFO_W)
        r.info:SetWordWrap(true)
        r.show = T.LabeledSwitch(r, "Show", PAGE_W - 16 - 84, -40)
        r.show:SetScript("OnClick", function(self)
            if r.route then GP:SetRouteShown(r.route, not self:IsOn()) end
        end)
        T.Tooltip(r.show, "Show", "Draw this route on the world map and the minimap.")
        r.delete:SetScript("OnClick", function()
            local route = r.route
            if not route then return end
            GP:Confirm(("Delete the route |cffffd100%s|r?"):format(route.name), "Delete",
                function() GP:DeleteRoute(route) end)
        end)
        rows[i] = r
        return r
    end

    AddRefresher(function()
        local recState = HME.Recorder and HME.Recorder.State()
        refs.routesRec:SetText(recState and "Stop & save" or "Record my route")
        PickRoutesZone()
        zone.keys = RoutesZoneChoices()
        zone:Refresh()
        local routes = routesZone and GP:RoutesOn(routesZone) or {}
        for i, route in ipairs(routes) do
            local r = Row(i)
            r.route = route
            r:ClearAllPoints()
            r:SetPoint("TOPLEFT", 0, -(i - 1) * ROW_H)
            r:Show()
            r.swatch.route = route
            r.swatch:Paint(route.color)
            if not r.name:HasFocus() then r.name:SetText(route.name) end
            r.show:SetOn(route.shown)
            if route.working then
                r.info:SetText("Working out the shortest loop...")
            else
                local kinds = {}
                for kind, names in pairs(route.kinds) do
                    if next(names) then kinds[#kinds + 1] = GP:KindName(kind) end
                end
                table.sort(kinds)
                -- two short lines, so nothing is cut off
                local line2 = "\n" .. GP:LapTime(route):gsub("^%l", string.upper) .. " a lap"
                    .. (GP.db.speed and "" or " on foot")
                    .. ((route.sight or 0) > 0 and ("  -  passes within " .. route.sight .. " yards") or "")
                -- HME: what was gathered along a recording.
                if route.recordedBy then
                    local seen = {}
                    for k, s in ipairs(HME.Recorder.Seen(route)) do
                        if k > 3 then break end
                        seen[#seen + 1] = ("%d %s"):format(s.count, s.name or s.kind or "?")
                    end
                    if #seen > 0 then kinds[#kinds + 1] = "seen: " .. table.concat(seen, ", ") end
                end
                r.info:SetText(("%d %s  -  %s round  -  %s%s\n%s"):format(GP:RouteNodes(route),
                    route.recordedBy and "points" or "nodes",
                    GP.FormatYards(route.length or GP:RouteLength(route)), table.concat(kinds, ", "), line2,
                    HME.RouteEditor.Quality(route).text))
            end
            r.rebuild:SetDisabled(GP:Busy())
            r.edit:SetDisabled(route.working)
        end
        for i = #routes + 1, #rows do rows[i]:Hide(); rows[i].route = nil end
        scroll:SetContent(PAGE_W - 16, math.max(1, #routes * ROW_H), true)
        if #routes == 0 then
            -- HME always has nodes (its bundled spawns), so this is only ever "none yet".
            empty:SetText("No routes in this zone yet.\n\n"
                .. "|cfff2f0e6New route|r makes a loop through the herbs and ores you pick.\n"
                .. "|cfff2f0e6Record my route|r saves the way you walk, to follow again.\n"
                .. "|cfff2f0e6Start farming|r in the Farm Finder makes one for a farm, Skinning circuits included.")
        else
            empty:SetText("")
        end
    end)
end

---------------------------------------------------------------------------
-- New route tab (also where a route is edited)
---------------------------------------------------------------------------
-- What's picked. Opening the tab starts it blank (ResetNew); Edit fills it
-- from a route (EditInWindow) and Save changes that route.
local newZone, picked, newSight, editing = nil, {}, nil, nil
local nameBox
local prefixZone   -- the zone whose "Zone - " the name box was started with

-- A new route's name starts with its zone: "The Barrens - "
local function Prefix(mapID) return mapID and (GP:MapName(mapID) .. " - ") or "" end
local function Trim(text) return (text or ""):match("^%s*(.-)%s*$") end
-- Only the zone (or nothing) typed: the rest is made from the nodes picked
local function OnlyPrefix(text, mapID)
    local t = Trim(text)
    return t == "" or (mapID and t == Trim(Prefix(mapID)))
end

local function Sight() return newSight or GP.DEFAULTS.sight end

local function ResetNew()
    newZone, picked, newSight, editing, prefixZone = nil, {}, nil, nil, nil
    if nameBox then nameBox:SetText(""); nameBox:ClearFocus() end
end

local function EditInWindow(route)
    newZone, newSight, editing, prefixZone = route.mapID, route.sight or 0, route, route.mapID
    picked = {}
    for kind, names in pairs(route.kinds) do
        for n in pairs(names) do
            picked[kind] = picked[kind] or {}
            picked[kind][n] = true
        end
    end
    nameBox:SetText(route.name)
    nameBox:ClearFocus()
end

local function BuildNew(p, page)
    T.RowLabel(p, "Zone", 0, 0)
    local zone = T.Dropdown(p, 300, {}, function(k) return k and GP:MapName(k) or "Pick a zone" end,
        function() return newZone end, function(k)
            if k ~= newZone then newZone, picked = k, {} end
            GP:RefreshConfig()
        end)
    zone:SetPoint("TOPLEFT", DROP_X, 0)
    zone.menuScroll = 300
    refs.newZone = zone
    local here = FlatButton(p, "My zone", 90)
    here:SetPoint("LEFT", zone, "RIGHT", 8, 0)
    here:SetScript("OnClick", function()
        local m = GP:PlayerMap()
        if m and m ~= newZone then newZone, picked = m, {} end
        GP:RefreshConfig()
    end)
    T.Tooltip(here, "My zone", "Pick the zone you're in.")
    refs.myZone = here

    local LIST_H = 210 + (WINDOW_H - T.WINDOW.H)
    local holder = CreateFrame("Frame", nil, p)
    holder:SetPoint("TOPLEFT", 0, -34)
    holder:SetSize(PAGE_W, LIST_H)
    T.Fill(holder, C.card)
    T.Border(holder, C.line)
    local inner = CreateFrame("Frame", nil, holder)
    inner:SetPoint("TOPLEFT", 10, -8)
    inner:SetPoint("BOTTOMRIGHT", -4, 8)
    local scroll = T.ScrollArea(inner, LIST_H - 16)
    local list = scroll.child
    local note = T.Note(holder, "", 12, -12, PAGE_W - 24)
    refs.newNote = note
    local heads, switches = {}, {}
    refs.kindSwitches = switches
    refs.kindHeads = heads

    -- below the list: name, passes within, make (or save and cancel)
    local y = -34 - LIST_H - 14
    T.RowLabel(p, "Name", 0, y)
    local name = T.EditBox(p, 300)
    name:SetPoint("TOPLEFT", DROP_X, y)
    nameBox = name
    -- grey hint after the zone: the rest of the name, made from what's picked
    local hint = Text(name, "", "GameFontDisableSmall")
    local measure = Text(name, "", "GameFontHighlightSmall")
    measure:Hide()
    local function ShowHint()
        local text = name:GetText()
        local on = not name:HasFocus() and OnlyPrefix(text, newZone)
        if on then
            measure:SetText(text)
            local w = measure:GetStringWidth()
            hint:ClearAllPoints()
            hint:SetPoint("LEFT", 6 + (type(w) == "number" and w or 0), 0)
        end
        hint:SetShown(on)
    end
    name:SetScript("OnEditFocusGained", function() hint:Hide() end)
    name:SetScript("OnEditFocusLost", ShowHint)
    name:SetScript("OnTextChanged", ShowHint)
    refs.newName = name
    refs.newHint = hint

    local sight = T.Slider(p, "Route passes within", 0, y - 36, 300, Sight,
        function(v) newSight = v end,
        GP.RANGES.sight[1], GP.RANGES.sight[2], " yards", 5, nil, "Off")
    T.Tooltip(sight, "Route passes within",
        "With Find Herbs or Find Minerals on, you see a node on the minimap before you reach it. "
        .. "The route only has to come this close to each node, so it cuts corners and is shorter, "
        .. "and nodes close together become one stop. Off takes you right up to every node.")
    AddRefresher(sight.Refresh)
    refs.sightSlider = sight

    local make = FlatButton(p, "Make route", 130, 26)
    make:SetPoint("TOPRIGHT", 0, y - 40)
    refs.makeButton = make
    make:SetScript("OnClick", function(self)
        if self.disabled then return end
        local kinds = {}
        for kind, names in pairs(picked) do
            for n, on in pairs(names) do
                if on and not GP:IsSkipped(n) then
                    kinds[kind] = kinds[kind] or {}
                    kinds[kind][n] = true
                end
            end
        end
        local typed = name:GetText()
        if OnlyPrefix(typed, newZone) then typed = Prefix(newZone) .. GP:RouteName(newZone, kinds) end
        local opts = { mapID = newZone, kinds = kinds, name = typed, sight = Sight() }
        local route
        if editing then
            route = GP:EditRoute(editing, opts) and editing
        else
            route = GP:NewRoute(opts)
        end
        if route then
            ResetNew()
            routesZone = route.mapID
            GP:OpenConfig("routes")
        end
    end)
    T.Disabler(make, { make })

    local cancel = FlatButton(p, "Cancel", 130, 22)
    cancel:SetPoint("TOPRIGHT", 0, y - 74)
    cancel:SetScript("OnClick", function()
        local route = editing
        ResetNew()
        if route then routesZone = route.mapID end
        GP:OpenConfig("routes")
    end)
    T.Tooltip(cancel, "Cancel", "Leave the route as it was.")
    refs.cancelButton = cancel

    -- a kind's heading, with Select all (Clear all once every node of it is on)
    local function Head(i)
        if heads[i] then return heads[i] end
        local h = Text(list, "", "GameFontNormalSmall", C.orange)
        local all = FlatButton(list, "Select all", 84, 18)
        all:SetScript("OnClick", function(self)
            local kind, entries = self.kind, self.entries
            if not kind then return end
            local on = not self.allOn
            picked[kind] = picked[kind] or {}
            for _, e in ipairs(entries) do
                if not e.skip then picked[kind][e.name] = on or nil end
            end
            GP:RefreshConfig()
        end)
        T.Tooltip(all, "Select all", "Switch on every node of this kind (click again to switch them all off). "
            .. "Nodes on your skip list stay off.")
        h.all = all
        heads[i] = h
        return h
    end
    local function Switch(i)
        if switches[i] then return switches[i] end
        local sw = T.LabeledSwitch(list, "", 0, 0, 200)
        sw:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        sw:SetScript("OnClick", function(self, button)
            local e = self.entry
            if not e then return end
            picked[e.kind] = picked[e.kind] or {}
            if button == "RightButton" then
                -- on or off the skip list (in every zone)
                local skip = not GP:IsSkipped(e.name)
                if skip then picked[e.kind][e.name] = nil end
                GP:SetSkipped(e.name, skip)
                GP.Print(skip and ("|cffffd100%s|r is skipped: no route uses it. Routes that had it drop it when "
                    .. "you Rebuild them. Right-click it again to stop skipping it."):format(e.name)
                    or ("|cffffd100%s|r is no longer skipped."):format(e.name))
                return
            end
            if GP:IsSkipped(e.name) then
                GP:SetSkipped(e.name, false)   -- clicking a skipped node takes it off the list and picks it
                picked[e.kind][e.name] = true
            else
                picked[e.kind][e.name] = not self:IsOn() or nil
            end
            GP:RefreshConfig()
        end)
        T.Tooltip(sw, nil, "Click to put this node in the route. Right-click to skip it everywhere "
            .. "(for poor or wilted nodes): Select all, new nodes and rebuilt routes leave it out.")
        switches[i] = sw
        return sw
    end

    AddRefresher(function()
        -- the route being edited was deleted meanwhile
        if editing then
            local found = false
            for _, r in ipairs(GP.db.routes) do if r == editing then found = true end end
            if not found then ResetNew() end
        end
        page.title:SetText(editing and "Edit route" or "New route")
        zone.keys = GP:GatherZones()
        zone:Refresh()
        local nodes = newZone and GP:ZoneNodes(newZone) or {}
        local yy, nh, ns_, col = 0, 0, 0, 0
        local lastKind
        for _, e in ipairs(nodes) do
            if e.kind ~= lastKind then
                if col == 1 then yy = yy - 26 end
                col = 0
                nh = nh + 1
                local h = Head(nh)
                h:ClearAllPoints()
                local top = yy - (nh > 1 and 6 or 0)
                h:SetPoint("TOPLEFT", 0, top - 4)
                h:SetText(GP:KindName(e.kind):upper())
                h:Show()
                h.all:ClearAllPoints()
                h.all:SetPoint("TOPLEFT", PAGE_W - 30 - 84 - 8, top)   -- inside the list, not above its top
                h.all.kind, h.all.entries = e.kind, {}
                h.all:Show()
                yy = top - 24
                lastKind = e.kind
            end
            local hl = heads[nh].all.entries
            hl[#hl + 1] = e
            ns_ = ns_ + 1
            local sw = Switch(ns_)
            sw.entry = e
            sw:ClearAllPoints()
            sw:SetPoint("TOPLEFT", col == 0 and 0 or COL2 - 10, yy)
            if e.skip then
                sw.label:SetText(("|cff8a8070%s (%d) - skipped|r"):format(e.name, e.count))
            else
                sw.label:SetText(("%s |cff8a8070(%d)|r"):format(e.name, e.count))
            end
            T.ClickableLabel(sw, sw.label)
            sw:SetOn(not e.skip and picked[e.kind] and picked[e.kind][e.name] or false)
            sw:Show()
            sw.label:Show()
            if col == 1 then yy = yy - 26 end
            col = 1 - col
        end
        if col == 1 then yy = yy - 26 end
        for i = 1, nh do
            local b = heads[i].all
            b.allOn = true
            for _, e in ipairs(b.entries) do
                if not e.skip and not (picked[b.kind] and picked[b.kind][e.name]) then b.allOn = false end
            end
            b:SetText(b.allOn and "Clear all" or "Select all")
        end
        for i = nh + 1, #heads do heads[i]:Hide(); heads[i].all:Hide(); heads[i].all.kind = nil end
        for i = ns_ + 1, #switches do switches[i]:Hide(); switches[i].label:Hide(); switches[i].entry = nil end
        scroll:SetContent(PAGE_W - 30, math.max(1, -yy), true)

        -- HME always has nodes: its bundled spawn points, your own gathers, and
        -- GatherMate2's when installed (0.4.0 still asked for GatherMate2 here).
        if not newZone then
            note:SetText("Pick a zone above, or click My zone for the one you're in.")
        elseif #nodes == 0 then
            note:SetText("No herb or ore spawn points are known in " .. GP:MapName(newZone) .. " (bundled data, your own "
                .. "gathers" .. (GP:HasGatherMate() and ", GatherMate2" or "") .. "). Gather there, then come back.")
        else
            note:SetText("")
        end

        local any = GP:AnyPicked(picked)
        local kinds = {}
        for kind, names in pairs(picked) do if next(names) then kinds[kind] = names end end
        -- start the name with the zone, and follow a zone change while only that's there
        if not editing and newZone ~= prefixZone then
            if OnlyPrefix(name:GetText(), prefixZone) then name:SetText(Prefix(newZone)) end
            prefixZone = newZone
        end
        if newZone then
            hint:SetText(any and GP:RouteName(newZone, kinds) or "(made from what you pick)")
        else
            hint:SetText("Name (made from what you pick)")
        end
        ShowHint()
        make:SetDisabled(not any or GP:Busy())
        make:SetText(GP:Busy() and "Working..." or editing and "Save changes" or "Make route")
        cancel:SetShown(editing ~= nil)
    end)
end

---------------------------------------------------------------------------
-- Taboo areas tab: the areas in a zone, Draw a taboo area, Delete
---------------------------------------------------------------------------
local tabooZone   -- the map whose taboo areas are listed
local TABOO_ROW = 30

local function TabooZoneChoices()
    local seen, list = {}, {}
    local function Add(m) if m and not seen[m] then seen[m] = true; list[#list + 1] = m end end
    for _, m in ipairs(GP:GatherZones()) do Add(m) end
    for m in pairs(GP.db.taboos) do Add(m) end
    for _, m in ipairs(GP:RouteZones()) do Add(m) end
    Add(GP:PlayerMap())
    table.sort(list, function(a, b) return GP:MapName(a) < GP:MapName(b) end)
    return list
end

-- About how big an area is, in yards across and down
local function AreaSize(mapID, xy)
    local w, h = GP:MapYards(mapID)
    w, h = w or 1500, h or 1000
    local x1, y1, x2, y2 = 1, 1, 0, 0
    for k = 1, #xy, 2 do
        x1, x2 = math.min(x1, xy[k]), math.max(x2, xy[k])
        y1, y2 = math.min(y1, xy[k + 1]), math.max(y2, xy[k + 1])
    end
    return math.floor((x2 - x1) * w + 0.5), math.floor((y2 - y1) * h + 0.5)
end

local function BuildTaboo(p)
    T.RowLabel(p, "Zone", 0, 0)
    local zone = T.Dropdown(p, 300, {}, function(k) return k and GP:MapName(k) or "Pick a zone" end,
        function() return tabooZone end, function(k) tabooZone = k; GP:RefreshConfig() end)
    zone:SetPoint("TOPLEFT", DROP_X, 0)
    zone.menuScroll = 300
    refs.tabooZone = zone
    local here = FlatButton(p, "My zone", 90)
    here:SetPoint("LEFT", zone, "RIGHT", 8, 0)
    here:SetScript("OnClick", function()
        tabooZone = GP:PlayerMap()
        GP:RefreshConfig()
    end)
    T.Tooltip(here, "My zone", "Pick the zone you're in.")
    refs.tabooMyZone = here

    T.Note(p, "A taboo area is a part of a zone your routes stay out of, like the mountains in Eastern "
        .. "Plaguelands. No node inside it is used, and the route's line goes round it. Draw one on the "
        .. "world map: the routes in that zone are then worked out again.", 0, -34, PAGE_W)

    local draw = FlatButton(p, "Draw a taboo area", 180, 24)
    draw:SetPoint("TOPLEFT", 0, -92)
    draw:SetScript("OnClick", function(self)
        if self.disabled then return end
        GP:StartTaboo(tabooZone)
    end)
    T.Tooltip(draw, "Draw a taboo area", "Opens the world map on this zone. Left-click for each corner of "
        .. "the area, right-click to take the last one back, then click Finish at the top of the map.")
    T.Disabler(draw, { draw })
    refs.tabooDraw = draw

    local show = T.LabeledSwitch(p, "Show on the world map", COL2, -96)
    show:SetScript("OnClick", function(self)
        GP.db.tabooShow = not self:IsOn()
        GP:Changed()
    end)
    T.Tooltip(show, "Show on the world map", "Draw the taboo areas on the world map, red and hatched. "
        .. "They're always shown while you're drawing one.")
    refs.tabooShow = show

    local LIST_Y = -130
    local holder = CreateFrame("Frame", nil, p)
    holder:SetPoint("TOPLEFT", 0, LIST_Y)
    holder:SetSize(PAGE_W, BODY_H + LIST_Y)
    T.Fill(holder, C.card)
    T.Border(holder, C.line)
    local inner = CreateFrame("Frame", nil, holder)
    inner:SetPoint("TOPLEFT", 10, -8)
    inner:SetPoint("BOTTOMRIGHT", -4, 8)
    local scroll = T.ScrollArea(inner, BODY_H + LIST_Y - 16)
    local list = scroll.child
    local empty = T.Note(holder, "", 12, -12, PAGE_W - 24)
    refs.tabooEmpty = empty
    local rows = {}
    refs.tabooRows = rows

    local function Row(i)
        if rows[i] then return rows[i] end
        local r = CreateFrame("Frame", nil, list)
        r:SetSize(PAGE_W - 30, TABOO_ROW - 4)
        r.text = Text(r, "", "GameFontHighlight")
        r.text:SetPoint("LEFT", 4, 0)
        r.del = FlatButton(r, "Delete", 80, 20)
        r.del:SetPoint("RIGHT", 0, 0)
        r.del:SetScript("OnClick", function(self)
            local m, idx = self.mapID, self.index
            if not (m and idx) then return end
            GP:Confirm(("Delete taboo area %d in |cffffd100%s|r? Your routes there are worked out again."):format(
                idx, GP:MapName(m)), "Delete", function() GP:DeleteTaboo(m, idx) end)
        end)
        T.Tooltip(r.del, "Delete", "Delete this taboo area. The routes in this zone are worked out again without it.")
        r.view = FlatButton(r, "Show", 80, 20)
        r.view:SetPoint("RIGHT", r.del, "LEFT", -8, 0)
        r.view:SetScript("OnClick", function(self)
            if not self.mapID then return end
            if GP.config then GP.config:Hide() end
            if OpenWorldMap then pcall(OpenWorldMap, self.mapID) end
        end)
        T.Tooltip(r.view, "Show", "Open the world map on this zone.")
        rows[i] = r
        return r
    end

    AddRefresher(function()
        if not tabooZone then tabooZone = GP:PlayerMap() end
        zone.keys = TabooZoneChoices()
        zone:Refresh()
        show:SetOn(GP.db.tabooShow)
        draw:SetDisabled(not tabooZone)
        draw:SetText(GP.drawing and GP.drawing.mapID == tabooZone and "Keep drawing" or "Draw a taboo area")
        local areas = tabooZone and GP:Taboos(tabooZone) or {}
        for i, xy in ipairs(areas) do
            local r = Row(i)
            r:ClearAllPoints()
            r:SetPoint("TOPLEFT", 0, -(i - 1) * TABOO_ROW)
            local aw, ah = AreaSize(tabooZone, xy)
            r.text:SetText(("Area %d  |cff8a8070-  %d corners, about %d x %d yards|r"):format(i, #xy / 2, aw, ah))
            r.del.mapID, r.del.index = tabooZone, i
            r.view.mapID = tabooZone
            r:Show()
        end
        for i = #areas + 1, #rows do rows[i]:Hide(); rows[i].del.index = nil end
        scroll:SetContent(PAGE_W - 30, math.max(1, #areas * TABOO_ROW), true)
        if not tabooZone then
            empty:SetText("Pick a zone above, or click My zone for the one you're in.")
        elseif #areas == 0 then
            empty:SetText("No taboo areas in " .. GP:MapName(tabooZone) .. " yet. Click Draw a taboo area.")
        else
            empty:SetText("")
        end
    end)
end

-- Opens the Taboo areas tab on this zone (after drawing or cancelling)
function GP:TabooTabInWindow(mapID)
    tabooZone = mapID
    self:OpenConfig("taboo")
end

---------------------------------------------------------------------------
-- Display tab
---------------------------------------------------------------------------
local function Setting(parent, text, x, y, key, tip, after)
    local sw = T.LabeledSwitch(parent, text, x, y)
    sw:SetScript("OnClick", function(self)
        GP.db[key] = not self:IsOn()
        if after then after() end
        GP:Changed()
    end)
    if tip then T.Tooltip(sw, text, tip) end
    AddRefresher(function() sw:SetOn(GP.db[key]) end)
    return sw
end

local function Slider(parent, text, x, y, key, suffix, tip)
    local r = GP.RANGES[key]
    local s = T.Slider(parent, text, x, y, 244,
        function() return GP.db[key] end,
        function(v) GP.db[key] = v; GP:Changed() end,
        r[1], r[2], suffix)
    if tip then T.Tooltip(s, text, tip) end
    AddRefresher(s.Refresh)
    return s
end

-- "Each route's own color" and, under it, the one color for every line on
-- that map ("world" or "minimap"), greyed out while routes keep their own
local function LineColor(parent, x, y, where, place)
    local key = where .. "RouteColor"
    local sw = Setting(parent, "Each route's own color", x, y, key,
        "Draw each route " .. place .. " in the color it has on the Routes tab. "
        .. "Turn this off to draw every route there in the color below.")
    local swatch = Swatch(parent,
        function() return GP.db[where .. "Color"] end,
        function(_, r, g, b) GP:SetLineColor(where, r, g, b) end,
        "Line color", "Click to pick the color of every route's line " .. place
        .. ". Turn off Each route's own color to use it.")
    swatch:SetPoint("TOPLEFT", x, y - 28)
    local label = Text(parent, "Line color", "GameFontHighlight")
    label:SetPoint("LEFT", swatch, "RIGHT", 8, 0)
    AddRefresher(function()
        swatch:Paint(GP.db[where .. "Color"])
        swatch:SetDisabled(GP.db[key])
        label:SetAlpha(GP.db[key] and 0.4 or 1)
    end)
    return sw, swatch
end

local function BuildDisplay(p)
    local card = Card(p, "Lines", 0, 0, PAGE_W, 214)
    refs.worldSwitch = Setting(card, "On the world map", 12, -30, "worldMap",
        "Draw the routes on the world map, on their zone's map (and thinner on the continent's).")
    refs.minimapSwitch = Setting(card, "On the minimap", COL2, -30, "minimap",
        "Draw the routes on the minimap, round you.")
    Slider(card, "World map line width", 12, -64, "worldWidth")
    Slider(card, "Minimap line width", COL2, -64, "minimapWidth")
    refs.worldAlpha = Slider(card, "World map opacity", 12, -108, "worldAlpha", "%")
    refs.minimapAlpha = Slider(card, "Minimap opacity", COL2, -108, "minimapAlpha", "%")
    refs.worldRouteColor, refs.worldColor = LineColor(card, 12, -152, "world", "on the world map")
    refs.minimapRouteColor, refs.minimapColor = LineColor(card, COL2, -152, "minimap", "on the minimap")

    local card4 = Card(p, "Following a route", 0, -220, PAGE_W, 90)
    refs.arrowsSwitch = Setting(card4, "Show arrows", 12, -30, "arrows",
        "Small arrows along every route's line, on the world map and the minimap, showing which way round to ride the loop.")
    refs.arrowsReverse = Setting(card4, "Reverse direction", COL2, -30, "arrowsReverse",
        "Turn the arrows round, to ride every loop the other way.")
    AddRefresher(function() refs.arrowsReverse:SetAlpha(GP.db.arrows and 1 or 0.4) end)
    refs.joinSwitch = Setting(card4, "Line to the route", 12, -60, "joinLine",
        "A dashed line on the minimap from you to the nearest point of a route showing in your zone, "
        .. "so you know where to join it. Gone once you're on the route.")

    local card3 = Card(p, "Range circle", 0, -316, PAGE_W, 98)
    refs.rangeSwitch = Setting(card3, "On the minimap", 12, -30, "range",
        "A circle round you on the minimap, as far as Find Herbs and Find Minerals show nodes, so you can see "
        .. "how close you need to get. Set the yards below.")
    local swatch = Swatch(card3,
        function() return GP.db.rangeColor end,
        function(_, r, g, b) GP.db.rangeColor = { r, g, b }; GP:Changed() end,
        "Circle color", "Click to pick the range circle's color.")
    swatch:SetPoint("TOPLEFT", COL2, -30)
    local label = Text(card3, "Circle color", "GameFontHighlight")
    label:SetPoint("LEFT", swatch, "RIGHT", 8, 0)
    AddRefresher(function() swatch:Paint(GP.db.rangeColor) end)
    refs.rangeColor = swatch
    refs.rangeYards = Slider(card3, "Circle radius", 12, -58, "rangeYards", " yards",
        "How far round you the circle is drawn. Find Herbs and Find Minerals show nodes about 100 yards away.")
    refs.rangeAlpha = Slider(card3, "Circle opacity", COL2, -58, "rangeAlpha", "%")

    local card2 = Card(p, "More", 0, -420, PAGE_W, 78)
    Setting(card2, "Add new nodes to routes", 12, -30, "autoAdd",
        "When GatherMate2 records a node you just found, it joins the routes in that zone that have its kind, "
        .. "where it adds the least walking.")
    Setting(card2, "Minimap button", COL2, -30, "minimapButton",
        "The GatherPath button on the minimap: left-click opens this window, right-click shows or hides the lines.",
        function() GP:UpdateMinimapButton() end)
    T.Note(card2, "Right-click the minimap button (or type /gpf hide, /gpf show) to hide every line for a while.",
        12, -56, PAGE_W - 24)

    local restore = FlatButton(p, "Restore defaults", 150, 22)
    restore:SetPoint("TOPLEFT", 0, -506)
    T.Tooltip(restore, "Restore defaults", "Put every setting on this tab back as it was to start. "
        .. "Your routes are kept.")
    restore:SetScript("OnClick", function()
        GP:Confirm("Put every setting on the Display tab back as it was to start? Your routes are kept.",
            "Restore", function() GP:RestoreDefaults() end)
    end)
    refs.restoreDefaults = restore
end

---------------------------------------------------------------------------
-- The window
---------------------------------------------------------------------------
local TABS = {
    { key = "routes",  label = "Routes",      icon = "Interface\\Icons\\INV_Misc_Map_01",   build = BuildRoutes },
    { key = "newroute", label = "New route",  icon = "Interface\\Icons\\INV_Misc_Flower_02", build = BuildNew, onTab = function() ResetNew() end },
    { key = "taboo",   label = "Avoid areas", icon = "Interface\\Icons\\INV_Misc_Bone_Skull_01", build = BuildTaboo },
    { key = "display", label = "Map display", icon = "Interface\\Icons\\INV_Misc_Spyglass_03", build = BuildDisplay },
}
GP.CONFIG_TABS = TABS

-- The Route Inspector: a panel over the Routes page.
local inspector
function GP:InspectRoute(route)
    local info = HME.RouteEditor.Inspect(route)
    if not info then return end
    local win = HME.Window and HME.Window.frame
    local page = win and win.pages and win.pages.routes
    if not page then return end
    local K = HME.Kit
    if not inspector then
        local W = 520
        -- Its own floating frame over the window (closes with it, and with Escape).
        local f = CreateFrame("Frame", "HarvestMateEnhancedRouteInspector", UIParent)
        f:SetSize(W, 360)
        f:SetPoint("TOP", page, "TOP", 0, -40)
        f:SetFrameStrata("FULLSCREEN_DIALOG")
        f:EnableMouse(true)
        f:Hide()
        table.insert(UISpecialFrames, "HarvestMateEnhancedRouteInspector")
        if page.HookScript then page:HookScript("OnHide", function() f:Hide() end) end
        f.shadow = T.Shadow(f, 14)
        f.bg = T.Surface(f, C.raised)
        T.Outline(f, C.edge)
        f.topo = T.Topo(f, C.brass, 0.05)
        f.title = T.Text(f, "", "title", C.text, 17)
        f.title:SetPoint("TOPLEFT", 16, -14)
        f.title:SetWidth(W - 80)
        f.title:SetWordWrap(false)
        f.sub = T.Text(f, "", "meta")
        f.sub:SetPoint("TOPLEFT", 16, -38)
        f.sub:SetWidth(W - 32)
        f.sub:SetWordWrap(false)
        f.close = T.FlatButton(f, "×", 28, 26, "ghost")
        f.close:SetPoint("TOPRIGHT", -8, -8)
        f.close:SetScript("OnClick", function() f:Hide() end)
        local tileW = (W - 32 - 12) / 3
        f.tiles = {}
        for i, label in ipairs({ "Length", "A lap", "Follows terrain" }) do
            local t = K.Stat(f, label, tileW, 70)
            t:SetPoint("TOPLEFT", 16 + (i - 1) * (tileW + 6), -62)
            t.bg:Paint(C.field)
            t.size = 20
            f.tiles[i] = t
        end
        f.text = T.Text(f, "", "small")
        f.text:SetPoint("TOPLEFT", 16, -146)
        f.text:SetWidth(W - 32)
        f.text:SetWordWrap(true)
        if f.text.SetSpacing then f.text:SetSpacing(3) end
        f.follow = T.FlatButton(f, "Follow", 90, 28, "primary")
        f.follow:SetPoint("BOTTOMRIGHT", -14, 12)
        f.edit = T.FlatButton(f, "Waypoints", 100, 28)
        f.edit:SetPoint("RIGHT", f.follow, "LEFT", -8, 0)
        -- The Route Director (0.6.0): a loop sized to your time, or without empty stops.
        f.timedLabel = T.Text(f, "Make a loop of", "label")
        f.timedLabel:SetPoint("BOTTOMLEFT", 16, 56)
        f.timed = {}
        local prev
        for i, m in ipairs(HME.RouteDirector.MINUTES) do
            local b = T.FlatButton(f, ("%d min"):format(m), 62, 24, "secondary")
            if prev then b:SetPoint("LEFT", prev, "RIGHT", 6, 0) else b:SetPoint("LEFT", f.timedLabel, "RIGHT", 10, 0) end
            b.minutes = m
            T.Tooltip(b, ("A %d-minute loop"):format(m), "A new route next to this one: the longest run of its stops that "
                .. "fits, in the same order. This route is not changed. The time is an estimate with a range.")
            f.timed[i] = b
            prev = b
        end
        f.trim = T.FlatButton(f, "Without empty stops", 150, 24, "ghost")
        f.trim:SetPoint("BOTTOMLEFT", 12, 14)
        T.Tooltip(f.trim, "Without empty stops", "A new route without the stops that never gave anything in 4 or more visits. "
            .. "This route is not changed.")
        inspector = f
    end
    local f = inspector
    local q = info.quality
    f.title:SetText(info.name or "Route")
    f.sub:SetText(("%s  ·  %s  ·  %d stops"):format(GP:MapName(info.mapID) or "?", q.label or "", info.stops))
    f.tiles[1]:Set(GP.FormatYards(info.length), info.length ~= info.straight and ("straight %s"):format(GP.FormatYards(info.straight))
        or "straight lines")
    f.tiles[2]:Set(U.Duration(info.lapSecs), ("at %.1f yd/s"):format(info.speed))
    local share = math.floor((info.terrainShare or 0) * 100 + 0.5)
    f.tiles[3]:Set(share .. "%", (info.approxLegs or 0) > 0 and (info.approxLegs .. " approximate legs") or "every leg walked",
        share >= 90 and C.accent or (share > 0 and C.warning or C.text3))
    local lines = {}
    lines[#lines + 1] = "|cff999b8fSource|r  " .. (q.source or "?") .. (info.laps > 0 and ("  ·  %d laps ridden"):format(info.laps) or "")
    if (info.longLegs or 0) > 0 then
        lines[#lines + 1] = ("|cfff5a345%d long leg%s to check|r: straight lines over 350 yards can hide a cliff or water.")
            :format(info.longLegs, info.longLegs == 1 and "" or "s")
    end
    if (info.pendingLegs or 0) > 0 then
        lines[#lines + 1] = ("|cff999b8fTerrain|r  %d legs still being walked in the background."):format(info.pendingLegs)
    end
    if #info.kinds > 0 then lines[#lines + 1] = "|cff999b8fFor|r  " .. table.concat(info.kinds, ", ") end
    local s = info.sessions
    if s.n == 0 then
        lines[#lines + 1] = "|cff999b8fYour sessions|r  none yet on this route."
    elseif s.perHour and s.enough then
        lines[#lines + 1] = ("|cff999b8fYour sessions|r  %d, %.1f h: about %s gathers an hour (measured)."):format(s.n, s.hours,
            U.Thousands(s.perHour))
    else
        lines[#lines + 1] = ("|cff999b8fYour sessions|r  %d, %.1f h: not enough yet for a rate (an hour over two sessions)."):format(
            s.n, s.hours)
    end
    if info.start then
        lines[#lines + 1] = ("|cff999b8fStart|r  stop %d is nearest you (%s)."):format(info.start.index, GP.FormatYards(info.start.yards))
    end
    local lapLines, laps = HME.RouteDirector.LapLines(route)
    for _, l in ipairs(lapLines) do lines[#lines + 1] = l end
    local shortest = HME.RouteDirector.Timed(route, HME.RouteDirector.MINUTES[1])
    if shortest and shortest.whole then
        lines[#lines + 1] = ("|cff999b8fTimed loops|r  the whole loop is %s already, under %d minutes."):format(
            U.Duration(shortest.secs), HME.RouteDirector.MINUTES[1])
    end
    lines[#lines + 1] = K.Paint("A recorded path proves the line you walked, not the ground around it.", T.HEX.text3)
    f.text:SetText(table.concat(lines, "\n"))
    f:SetHeight(146 + (f.text:GetStringHeight() or 80) + 100)
    for _, b in ipairs(f.timed) do
        local plan = HME.RouteDirector.Timed(route, b.minutes)
        b.disabled = plan == nil or plan.whole
        if b.SetAlpha then b:SetAlpha(b.disabled and 0.45 or 1) end
        b:SetScript("OnClick", function(self)
            if self.disabled then return end
            local v, text = HME.RouteDirector.MakeTimed(route, self.minutes)
            if v and v ~= route then
                HME.Print(("made |cffffd100%s|r: %s"):format(v.name, text or ""))
                GP:InspectRoute(v)
            else
                HME.Print(text or "no shorter loop could be made.")
            end
        end)
    end
    f.trim:SetShown(#laps.weak > 0)
    f.trim:SetScript("OnClick", function()
        local v, why = HME.RouteDirector.WithoutWeak(route)
        if v then
            HME.Print(("made |cffffd100%s|r without %d empty stop%s."):format(v.name, #laps.weak, #laps.weak == 1 and "" or "s"))
            GP:InspectRoute(v)
        else
            HME.Print(why or "nothing to trim.")
        end
    end)
    f.follow:SetScript("OnClick", function() HME.Guidance.Start(route) f:Hide() end)
    f.edit:SetScript("OnClick", function() HME.RouteEditor.Start(route) f:Hide() end)
    f:Show()
    return info
end
GP.RESET_NEW = function() ResetNew() end

-- The window is HME's; GatherPath's tab keys map onto its pages.
local KEYS = { new = "newroute" }
function GP:BuildConfig()
    self.config = HME.Window and HME.Window.Build() or nil
    return self.config
end

-- Opens New route blank but on this zone (the Routes tab's New route button)
function GP:NewRouteInWindow(mapID)
    self:OpenConfig("new")
    ResetNew()
    newZone = mapID
    self:RefreshConfig()
end

-- Opens New route filled in from this route; Save changes then changes it
function GP:EditRouteInWindow(route)
    self:OpenConfig("new")
    EditInWindow(route)
    self:RefreshConfig()
end

function GP:RefreshConfig()
    local win = HME.Window and HME.Window.frame
    if not (win and win:IsShown()) then return end
    for _, fn in ipairs(refreshers) do fn() end
end

function GP:OpenConfig(tab)
    if HME.OpenWindow then HME.OpenWindow(KEYS[tab] or tab or "routes") end
    self:RefreshConfig()
end
