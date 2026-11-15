-- HarvestMate Enhanced: UI/Header.lua (0.6.0)
-- In the window's header: one search over everything (Engine/Search.lua), the
-- bell with the notification list (Engine/Notify.lua), and the session review
-- panel (Engine/Review.lua). Popovers are their own floating frames over the
-- window; Escape closes them, and they close with the window.
-- Copyright (C) 2026 HarvestMate Enhanced contributors. GPL-3.0-or-later.

local _, ns = ...
local HME = ns.HME
local T = ns.Theme
local K = HME.Kit
local U = HME.U
local C = T.C

local H = {}
HME.Header = H

H.SEARCH_W = 210
local POP_W = 360
local ROW_H = 40

local function Popover(name, w)
    local f = CreateFrame("Frame", name, UIParent)
    f:SetSize(w, 100)
    f:SetFrameStrata("FULLSCREEN_DIALOG")
    f:EnableMouse(true)
    f:Hide()
    table.insert(UISpecialFrames, name)
    f.shadow = T.Shadow(f, 14)
    f.bg = T.Surface(f, C.raised)
    T.Outline(f, C.edge)
    return f
end

---------------------------------------------------------------------------
-- Search
---------------------------------------------------------------------------
local results
local function BuildResults(win)
    if results then return results end
    local f = Popover("HarvestMateEnhancedSearch", POP_W)
    f.rows = {}
    for i = 1, HME.Find.MAX do
        local b = CreateFrame("Button", nil, f)
        b:SetSize(POP_W - 12, ROW_H - 4)
        b.bg = T.Surface(b, { 0, 0, 0, 0 })
        b.kind = K.Label(b, "", { template = "label", width = 80, wrap = false })
        b.kind:SetPoint("LEFT", 8, 0)
        b.name = K.Label(b, "", { template = "strong", width = POP_W - 112, wrap = false })
        b.name:SetPoint("TOPLEFT", 92, -4)
        b.sub = K.Label(b, "", { template = "meta", width = POP_W - 112, wrap = false })
        b.sub:SetPoint("TOPLEFT", 92, -22)
        b:SetScript("OnEnter", function(self) self.bg:Paint(C.raisedHi) end)
        b:SetScript("OnLeave", function(self) self.bg:Paint({ 0, 0, 0, 0 }) end)
        b:SetScript("OnClick", function(self)
            f:Hide()
            if H.box then H.box:ClearFocus() end
            HME.Find.Open(self.result)
        end)
        f.rows[i] = b
    end
    f.empty = K.Label(f, "Nothing found. Try a material, a creature, a zone, a trainer or a page.", { template = "meta", width = POP_W - 24 })
    f.empty:SetPoint("TOPLEFT", 12, -12)
    if win.HookScript then win:HookScript("OnHide", function() f:Hide() end) end
    results = f
    return f
end

local KIND_LABEL = {}
for _, k in ipairs(HME.Find.KINDS) do KIND_LABEL[k.key] = k.label end

function H.ShowResults(win, text)
    local f = BuildResults(win)
    local list = HME.Find.Run(text)
    if (text or ""):len() < 2 then f:Hide() return list end
    f:ClearAllPoints()
    f:SetPoint("TOPRIGHT", H.box, "BOTTOMRIGHT", 0, -6)
    local lastKind
    for i, b in ipairs(f.rows) do
        local r = list[i]
        b.result = r
        b:SetShown(r ~= nil)
        if r then
            b:SetPoint("TOPLEFT", 6, -6 - (i - 1) * ROW_H)
            b.kind:SetText(r.kind ~= lastKind and (KIND_LABEL[r.kind] or r.kind) or "")
            lastKind = r.kind
            b.name:SetText(r.label)
            T.FitText(b.name, POP_W - 112, "strong", 13, 11)
            b.sub:SetText(r.sub or "")
        end
    end
    f.empty:SetShown(#list == 0)
    f:SetHeight(#list == 0 and 44 or (#list * ROW_H + 12))
    f:Show()
    return list
end

---------------------------------------------------------------------------
-- Notifications
---------------------------------------------------------------------------
local bellPop
local CAT_HEX = { goal = T.HEX.gold, training = T.HEX.info, bags = T.HEX.warning, farm = T.HEX.accent, route = T.HEX.brass,
    session = T.HEX.text2, data = T.HEX.text3 }

local function BuildBell(win)
    if bellPop then return bellPop end
    local f = Popover("HarvestMateEnhancedNotices", POP_W + 40)
    local W = POP_W + 40
    f.title = K.Label(f, "Notifications", { template = "strong" })
    f.title:SetPoint("TOPLEFT", 12, -10)
    f.clear = K.Button(f, "Clear", 60, 22, function() HME.Notify.Clear() H.ShowBell(win) end, "Empties the list.", "ghost")
    f.clear:SetPoint("TOPRIGHT", -8, -6)
    f.rows = {}
    for i = 1, 7 do
        local r = CreateFrame("Frame", nil, f)
        r:SetSize(W - 16, 56)
        r:SetPoint("TOPLEFT", 8, -34 - (i - 1) * 58)
        r.bg = T.Surface(r, C.card)
        r.text = K.Label(r, "", { template = "small", width = W - 120 })
        r.text:SetPoint("TOPLEFT", 8, -5)
        r.text:SetJustifyV("TOP")
        if r.text.SetMaxLines then r.text:SetMaxLines(2) end
        r.when = K.Label(r, "", { template = "meta", width = 90, wrap = false })
        r.when:SetPoint("BOTTOMLEFT", 8, 5)
        r.go = K.Button(r, "Do it", 70, 22, function(self)
            if self.notice then HME.Notify.Run(self.notice) f:Hide() end
        end)
        r.go:SetPoint("RIGHT", -6, 0)
        f.rows[i] = r
    end
    f.empty = K.Label(f, "Nothing yet. Goals reached, training, full bags, session reviews and better farms show here.",
        { template = "meta", width = W - 24 })
    f.empty:SetPoint("TOPLEFT", 12, -36)
    if win.HookScript then win:HookScript("OnHide", function() f:Hide() end) end
    bellPop = f
    return f
end

function H.ShowBell(win)
    local f = BuildBell(win)
    f:ClearAllPoints()
    f:SetPoint("TOPRIGHT", H.bell, "BOTTOMRIGHT", 0, -6)
    local list = HME.Notify.List()
    local now = (time and time()) or 0
    local shown = 0
    for i, r in ipairs(f.rows) do
        local n = list[#list - i + 1]
        r:SetShown(n ~= nil)
        if n then
            shown = shown + 1
            r.text:SetText(K.Paint("● ", CAT_HEX[n.cat] or T.HEX.text3) .. (n.text or ""))
            r.when:SetText(HME.Bags.Age(now - (n.t or now)) .. " ago")
            r.go.notice = n
            local a = HME.Notify.Action(n)
            r.go:SetShown(a ~= nil)
            if a then r.go:SetText(n.label or a.label or "Do it") end
        end
    end
    f.empty:SetShown(shown == 0)
    f.clear:SetShown(shown > 0)
    f:SetHeight(shown == 0 and 70 or (40 + shown * 58))
    f:Show()
    HME.Notify.MarkRead()
end

---------------------------------------------------------------------------
-- The session review
---------------------------------------------------------------------------
local review
function HME.Review.Show(summary)
    summary = summary or HME.Review.last
    local data = HME.Review.Build(summary)
    if not data then
        HME.Print("no session to review yet (one of 10 minutes or more).")
        return nil
    end
    if not review then
        local W = 520
        local f = Popover("HarvestMateEnhancedReview", W)
        f:SetPoint("CENTER", 0, 60)
        f.topo = T.Topo(f, C.accent, 0.05)
        f.kicker = K.Label(f, "Session review", { template = "label", color = C.accent })
        f.kicker:SetPoint("TOPLEFT", 16, -14)
        f.title = K.Label(f, "", { template = "title", size = 18, width = W - 80, wrap = false })
        f.title:SetPoint("TOPLEFT", 16, -30)
        f.close = K.Button(f, "×", 28, 26, function() f:Hide() end, nil, "ghost")
        f.close.autoFit = false
        f.close:SetPoint("TOPRIGHT", -8, -8)
        local tileW = (W - 32 - 18) / 4
        f.tiles = {}
        for i = 1, 4 do
            local t = K.Stat(f, "", tileW, 70)
            t:SetPoint("TOPLEFT", 16 + (i - 1) * (tileW + 6), -62)
            t.bg:Paint(C.field)
            t.size = 18
            f.tiles[i] = t
        end
        f.text = K.Label(f, "", { template = "small", width = W - 32 })
        f.text:SetPoint("TOPLEFT", 16, -146)
        if f.text.SetSpacing then f.text:SetSpacing(3) end
        f.stats = K.Button(f, "Profits & Stats", 130, 28, function() f:Hide() HME.OpenWindow("stats") end)
        f.stats:SetPoint("BOTTOMRIGHT", -14, 12)
        f.ok = K.Button(f, "Close", 80, 28, function() f:Hide() end, nil, "ghost")
        f.ok:SetPoint("RIGHT", f.stats, "LEFT", -8, 0)
        -- 0.7.0: the session's path on the map (Engine/Trail.lua).
        f.path = K.Button(f, "Show the path", 120, 28, function()
            f:Hide()
            HME.Trail.Show(f.summary)
        end, "Where you went during this session and what happened where, on the world map.", "secondary")
        f.path:SetPoint("BOTTOMLEFT", 14, 12)
        review = f
    end
    local f = review
    f.summary = summary
    f.path:SetShown(type(summary) == "table" and summary.trail ~= nil)
    f.title:SetText(data.title)
    T.FitText(f.title, 440, "title", 18, 14)
    for i, t in ipairs(f.tiles) do
        local d = data.tiles[i]
        if t.SetLabel then t:SetLabel(d.label) end
        t:Set(d.value, d.sub, i == 4 and C.gold or C.text)
    end
    f.text:SetText(#data.lines > 0 and table.concat(data.lines, "\n") or "Nothing more to say about this one.")
    f:SetHeight(146 + (f.text:GetStringHeight() or 60) + 60)
    f:Show()
    return data
end

---------------------------------------------------------------------------
-- Into the window's header (after it is built)
---------------------------------------------------------------------------
function H.Attach(win)
    if not (win and win.header) or H.win == win then return end
    H.win = win           -- (a rebuilt window, after a layout change, gets its own)
    local header = win.header
    local box = T.EditBox(header, H.SEARCH_W)
    box:SetPoint("RIGHT", header, "RIGHT", -96, 0)
    box.hint = K.Label(box, "Search everything", { template = "GameFontDisableSmall" })
    box.hint:SetPoint("LEFT", 6, 0)
    box:SetScript("OnTextChanged", function(self)
        local text = self:GetText() or ""
        self.hint:SetShown(text == "")
        HME.Soon("header-search", 0.2, function() H.ShowResults(win, text) end)
    end)
    box:SetScript("OnEnterPressed", function(self)
        local list = HME.Find.Run(self:GetText() or "")
        if list[1] then
            if results then results:Hide() end
            self:ClearFocus()
            HME.Find.Open(list[1])
        end
    end)
    box:SetScript("OnEscapePressed", function(self)
        self:ClearFocus()
        if results then results:Hide() end
    end)
    T.Tooltip(box, "Search everything", "Materials, creatures, zones, your routes, trainers, milestones, profiles, goals, "
        .. "your quests and pages. Enter opens the first.")
    H.box = box
    local bell = K.Button(header, "", 46, 28, function() H.ShowBell(win) end, nil, "ghost")
    bell.autoFit = false
    bell:SetPoint("RIGHT", header, "RIGHT", -46, 0)
    T.Tooltip(bell, "Notifications", "What HME wanted to tell you: goals, training, bags, better farms, session reviews.")
    H.bell = bell
    function H.RefreshBell()
        local n = HME.Notify.Unread()
        bell:SetText(n > 0 and K.Paint(("● %d"):format(math.min(n, 99)), T.HEX.gold) or "●")
    end
    H.RefreshBell()
    HME.Listen("NOTICES_CHANGED", function() H.RefreshBell() end)
end

HME.Listen("WINDOW_SHOWN", function()
    if HME.Window and HME.Window.frame then H.Attach(HME.Window.frame) end
end)
