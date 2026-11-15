-- Gatherpedia: Theme.lua
-- One place for the look: palette, fonts and the rounded panel used by
-- every page. Loaded right after Core.lua so the font objects exist
-- before any FontString is created.
-- Copyright (C) 2026 Curs3d221. Licensed under the GNU GPL v3 or later; see LICENSE.

local ADDON_NAME, ns = ...

local T = {}
ns.Theme = T

local MEDIA = "Interface\\AddOns\\Gatherpedia\\Media\\"
T.ROUND = MEDIA .. "Round"
T.RING = MEDIA .. "Ring"
T.DISC = MEDIA .. "Disc"
T.CIRCLE_MASK = MEDIA .. "CircleMask"
T.WHITE = "Interface\\Buttons\\WHITE8X8"

local function hex(h)
    return {
        tonumber(h:sub(1, 2), 16) / 255,
        tonumber(h:sub(3, 4), 16) / 255,
        tonumber(h:sub(5, 6), 16) / 255,
    }
end

---------------------------------------------------------------------------
-- Palette
---------------------------------------------------------------------------

T.C = {
    window   = hex("0f0d0b"),  -- outer window fill
    side     = hex("15120f"),  -- sidebar
    main     = hex("1a1714"),  -- main page
    card     = hex("16130f"),  -- list and card fill
    well     = hex("120f0d"),  -- recessed: segmented controls, session box
    raised   = hex("221e18"),  -- hovered row, nearest card
    button   = hex("1e1a15"),  -- quiet button fill
    line     = hex("2c261f"),  -- card borders, dividers
    line2    = hex("3a3229"),  -- button borders
    frame    = hex("4a3f30"),  -- window border
    rowLine  = hex("221d17"),  -- row separators
    text     = hex("f1e9d6"),  -- names, values
    text2    = hex("b8ab90"),  -- places, secondary
    text3    = hex("948a76"),  -- labels, hints
    gold     = hex("e2b65c"),  -- actions and selection only
    goldHi   = hex("f3d48f"),
    goldLine = hex("5a4a2c"),
    goldFill = hex("2a231a"),
    goldDeep = hex("b8913f"),
    ink      = hex("1a1408"),  -- text on a gold button
    green    = hex("8fdc84"),
    here     = hex("1c2a1b"),  -- "you are here" row
}

-- Profession accents: dot, bar fill, selected segment, icon ring.
T.PROF = {
    Herbalism = { accent = hex("6fbf5a"), fill = hex("1f2b1b"), line = hex("4c7f3e") },
    Mining    = { accent = hex("c98a4b"), fill = hex("2e2218"), line = hex("8a5d32") },
    Fishing   = { accent = hex("4fa3d9"), fill = hex("1d2a33"), line = hex("3e5f75") },
    Skinning  = { accent = hex("c9a27a"), fill = hex("2b241c"), line = hex("7a6248") },
}

-- Rank badges follow WoW item quality: neutral, rare blue, epic purple.
T.RANK = {
    Apprentice = { text = hex("b8ab90"), line = hex("4a4236"), fill = hex("1a1714") },
    Journeyman = { text = hex("b8ab90"), line = hex("4a4236"), fill = hex("1a1714") },
    Expert     = { text = hex("9fc8f2"), line = hex("3b6a99"), fill = hex("172433") },
    Artisan    = { text = hex("c9a6ef"), line = hex("6d4f93"), fill = hex("22192e") },
    Supplies   = { text = hex("b8ab90"), line = hex("4a4236"), fill = hex("1a1714") },
}

T.FACTION = {
    Alliance = { text = hex("f1e9d6"), line = hex("3c5378"), fill = hex("1b2436") },
    Horde    = { text = hex("f1e9d6"), line = hex("7a3a33"), fill = hex("341a17") },
}

function T:Prof(prof)
    return self.PROF[prof] or { accent = self.C.gold, fill = self.C.goldFill, line = self.C.goldLine }
end

function T:Hex(c)
    return string.format("%02x%02x%02x",
        math.floor(c[1] * 255 + 0.5), math.floor(c[2] * 255 + 0.5), math.floor(c[3] * 255 + 0.5))
end

---------------------------------------------------------------------------
-- Fonts
-- Marcellus (headings) and Alegreya Sans (text) when their .ttf files are
-- in Media\Fonts; otherwise the game's own fonts. Both are SIL Open Font
-- License, free to bundle.
---------------------------------------------------------------------------

local FONT_DIR = MEDIA .. "Fonts\\"
T.FONT_FILES = {
    display = FONT_DIR .. "Marcellus-Regular.ttf",
    body    = FONT_DIR .. "AlegreyaSans-Regular.ttf",
    medium  = FONT_DIR .. "AlegreyaSans-Medium.ttf",
    bold    = FONT_DIR .. "AlegreyaSans-Bold.ttf",
}

local function GameFontPath(obj, fallback)
    if obj and obj.GetFont then
        local ok, path = pcall(obj.GetFont, obj)
        if ok and type(path) == "string" and path ~= "" then return path end
    end
    return fallback
end

-- name, face, size, color, fallback game font object (for the file only)
local FONTS = {
    { "GatherpediaFontTitle",          "display", 24, "text",  "GameFontNormalHuge" },
    { "GatherpediaFontHeading",        "display", 17, "goldHi", "GameFontNormalLarge" },
    { "GatherpediaFontNormal",         "medium",  13, "gold",  "GameFontNormal" },
    { "GatherpediaFontNormalSmall",    "bold",    11, "gold",  "GameFontNormalSmall" },
    { "GatherpediaFontHighlightLarge", "medium",  15, "text",  "GameFontHighlightLarge" },
    { "GatherpediaFontHighlight",      "body",    13, "text",  "GameFontHighlight" },
    { "GatherpediaFontHighlightSmall", "body",    12, "text",  "GameFontHighlightSmall" },
    { "GatherpediaFontDisable",        "body",    13, "text3", "GameFontDisable" },
    { "GatherpediaFontDisableSmall",   "body",    11, "text3", "GameFontDisableSmall" },
    { "GatherpediaFontLabel",          "bold",    10, "text3", "GameFontNormalSmall" },
}

T.bundledFonts = {}

local function TrySetFont(obj, path, size)
    if not (obj and obj.SetFont and path) then return false end
    local ok, res = pcall(obj.SetFont, obj, path, size, "")
    -- Current clients return true on success and false when the file is
    -- missing. A client that returns nothing gets the benefit of the doubt.
    if not ok then return false end
    return res ~= false
end

function T:BuildFonts()
    for _, spec in ipairs(FONTS) do
        local name, face, size, color, fallback = spec[1], spec[2], spec[3], spec[4], spec[5]
        local obj = _G[name] or (CreateFont and CreateFont(name))
        if obj then
            local ok = TrySetFont(obj, self.FONT_FILES[face], size)
            if ok then
                self.bundledFonts[face] = true
            else
                -- Game fonts run larger than Alegreya Sans; shave a point.
                local base = GameFontPath(_G[fallback], "Fonts\\FRIZQT__.TTF")
                TrySetFont(obj, base, math.max(9, size - 1))
            end
            local c = self.C[color] or self.C.text
            if obj.SetTextColor then obj:SetTextColor(c[1], c[2], c[3]) end
            if obj.SetShadowOffset then obj:SetShadowOffset(1, -1) end
            if obj.SetShadowColor then obj:SetShadowColor(0, 0, 0, 0.75) end
            if obj.SetJustifyH then obj:SetJustifyH("LEFT") end
        end
    end
end

T:BuildFonts()

-- Point a FontString at one of our faces at a given size.
function T:Font(fs, face, size, color)
    if not fs then return end
    local path = self.bundledFonts[face] and self.FONT_FILES[face]
        or GameFontPath(GameFontHighlight, "Fonts\\FRIZQT__.TTF")
    if fs.SetFont then pcall(fs.SetFont, fs, path, size or 12, "") end
    if color then
        local c = type(color) == "string" and self.C[color] or color
        if c and fs.SetTextColor then fs:SetTextColor(c[1], c[2], c[3], c[4] or 1) end
    end
end

---------------------------------------------------------------------------
-- Rounded panel
-- Two nine-slices from one 32 px rounded square: an outer one in the
-- border color, an inner one 1 px in, in the fill color. Corners stay
-- round at any size. SetBackdropColor and SetBackdropBorderColor on the
-- frame are redirected to it, so older paint code keeps working.
---------------------------------------------------------------------------

local COORDS = {
    { 0, 0.25, 0, 0.25 }, { 0.25, 0.75, 0, 0.25 }, { 0.75, 1, 0, 0.25 },
    { 0, 0.25, 0.25, 0.75 }, { 0.25, 0.75, 0.25, 0.75 }, { 0.75, 1, 0.25, 0.75 },
    { 0, 0.25, 0.75, 1 }, { 0.25, 0.75, 0.75, 1 }, { 0.75, 1, 0.75, 1 },
}

local function Slice(frame, sub, inset, c)
    local t = {}
    for i = 1, 9 do
        local x = frame:CreateTexture(nil, "BACKGROUND", nil, sub)
        x:SetTexture(T.ROUND)
        x:SetTexCoord(COORDS[i][1], COORDS[i][2], COORDS[i][3], COORDS[i][4])
        t[i] = x
    end
    t[1]:SetSize(c, c); t[1]:SetPoint("TOPLEFT", inset, -inset)
    t[3]:SetSize(c, c); t[3]:SetPoint("TOPRIGHT", -inset, -inset)
    t[7]:SetSize(c, c); t[7]:SetPoint("BOTTOMLEFT", inset, inset)
    t[9]:SetSize(c, c); t[9]:SetPoint("BOTTOMRIGHT", -inset, inset)
    t[2]:SetPoint("TOPLEFT", t[1], "TOPRIGHT"); t[2]:SetPoint("BOTTOMRIGHT", t[3], "BOTTOMLEFT")
    t[8]:SetPoint("TOPLEFT", t[7], "TOPRIGHT"); t[8]:SetPoint("BOTTOMRIGHT", t[9], "BOTTOMLEFT")
    t[4]:SetPoint("TOPLEFT", t[1], "BOTTOMLEFT"); t[4]:SetPoint("BOTTOMRIGHT", t[7], "TOPRIGHT")
    t[6]:SetPoint("TOPLEFT", t[3], "BOTTOMLEFT"); t[6]:SetPoint("BOTTOMRIGHT", t[9], "TOPRIGHT")
    t[5]:SetPoint("TOPLEFT", t[1], "BOTTOMRIGHT"); t[5]:SetPoint("BOTTOMRIGHT", t[9], "TOPLEFT")
    return t
end

local function Tint(list, c, a)
    if not list or not c then return end
    for i = 1, 9 do
        list[i]:SetVertexColor(c[1], c[2], c[3], a or c[4] or 1)
    end
end

-- frame: any Frame or Button. fill / border: palette colors or nil.
-- radius: corner size in px (default 6). Returns the panel handle.
function T:Panel(frame, fill, border, radius)
    if not frame then return end
    radius = radius or 6
    local p = frame._gpPanel
    if not p then
        if frame.SetBackdrop then pcall(frame.SetBackdrop, frame, nil) end
        p = {
            outer = Slice(frame, -7, 0, radius),
            inner = Slice(frame, -6, 1, math.max(2, radius - 1)),
        }
        frame._gpPanel = p
        -- Old paint code calls these; route them to the panel.
        frame.SetBackdropColor = function(_, r, g, b, a)
            Tint(p.inner, { r or 0, g or 0, b or 0 }, a or 1)
        end
        frame.SetBackdropBorderColor = function(_, r, g, b, a)
            Tint(p.outer, { r or 0, g or 0, b or 0 }, a or 1)
        end
    end
    self:PanelColors(frame, fill, border)
    return p
end

function T:PanelColors(frame, fill, border, fillAlpha, borderAlpha)
    local p = frame and frame._gpPanel
    if not p then return end
    if fill then Tint(p.inner, fill, fillAlpha or 1) else Tint(p.inner, self.C.card, 0) end
    if border then Tint(p.outer, border, borderAlpha or 1) else Tint(p.outer, fill or self.C.card, fill and (fillAlpha or 1) or 0) end
end

---------------------------------------------------------------------------
-- Buttons and chips
-- style: "primary" (gold), "quiet" (dark), "selected" (gold outline),
-- "segment" / "segmentOn" (inside a segmented control), "danger".
---------------------------------------------------------------------------

function T:SkinButton(b, style, accent)
    if not b then return end
    self:Panel(b, self.C.button, self.C.line2, 5)
    b._gpStyle = style or "quiet"
    b._gpAccent = accent
    self:HoverPaint(b,
        function(btn) btn._gpHover = true; T:PaintButton(btn) end,
        function(btn) btn._gpHover = nil; T:PaintButton(btn) end)
    self:PaintButton(b)
end

-- Run enter/leave painters before whatever OnEnter/OnLeave the frame has,
-- including handlers set later with SetScript (a plain HookScript would
-- be wiped by a later SetScript).
function T:HoverPaint(frame, onEnter, onLeave)
    if not frame or not frame.SetScript then return end
    frame._gpEnterPaint, frame._gpLeavePaint = onEnter, onLeave
    if frame._gpHoverWrapped then return end
    frame._gpHoverWrapped = true
    local orig = frame.SetScript
    local user = {
        OnEnter = frame.GetScript and frame:GetScript("OnEnter") or nil,
        OnLeave = frame.GetScript and frame:GetScript("OnLeave") or nil,
    }
    local function wrapped(name)
        return function(f, ...)
            local paint = (name == "OnEnter") and f._gpEnterPaint or f._gpLeavePaint
            if paint then paint(f) end
            local fn = user[name]
            if fn then return fn(f, ...) end
        end
    end
    frame.SetScript = function(f, name, fn)
        if name == "OnEnter" or name == "OnLeave" then
            user[name] = fn
            return orig(f, name, wrapped(name))
        end
        return orig(f, name, fn)
    end
    orig(frame, "OnEnter", wrapped("OnEnter"))
    orig(frame, "OnLeave", wrapped("OnLeave"))
    if frame.EnableMouse then frame:EnableMouse(true) end
end

-- Repaint a skinned button; pass a new style to switch (e.g. on/off chips).
function T:PaintButton(b, style, accent)
    if not (b and b._gpPanel) then return end
    if style then b._gpStyle = style end
    if accent ~= nil then b._gpAccent = accent end
    local C, s, hover = self.C, b._gpStyle, b._gpHover
    local fill, line, text
    if s == "primary" then
        fill, line, text = hover and C.goldHi or C.gold, C.goldDeep, C.ink
    elseif s == "selected" then
        fill, line, text = C.goldFill, C.goldLine, C.goldHi
    elseif s == "segmentOn" then
        local a = b._gpAccent
        if type(a) == "table" and a.fill then
            fill, line, text = a.fill, a.line, a.text or C.text
        else
            fill, line, text = C.goldFill, C.goldLine, C.text
        end
    elseif s == "segment" then
        fill, line, text = hover and C.raised or C.well, hover and C.line2 or C.well, hover and C.text or C.text2
    else
        fill, line, text = hover and C.raised or C.button, hover and C.goldLine or C.line2, hover and C.text or C.text2
    end
    self:PanelColors(b, fill, line)
    local label = b.label or b.text
    if label and label.SetTextColor then label:SetTextColor(text[1], text[2], text[3]) end
end

-- A small filled circle, e.g. the profession dot in a segment.
function T:Dot(parent, size, color)
    local d = parent:CreateTexture(nil, "ARTWORK")
    d:SetSize(size or 7, size or 7)
    d:SetTexture(self.DISC)
    local c = color or self.C.gold
    d:SetVertexColor(c[1], c[2], c[3], 1)
    return d
end

-- A rank or status pill: rounded, 1 px border, small text.
function T:Badge(parent)
    local b = CreateFrame("Frame", nil, parent)
    b:SetHeight(18)
    self:Panel(b, self.RANK.Journeyman.fill, self.RANK.Journeyman.line, 8)
    b.label = b:CreateFontString(nil, "OVERLAY", "GatherpediaFontDisableSmall")
    b.label:SetPoint("CENTER", 0, 0)
    return b
end

function T:SetBadge(b, text, palette)
    if not b then return end
    palette = palette or self.RANK.Journeyman
    b.label:SetText(text or "")
    b.label:SetTextColor(palette.text[1], palette.text[2], palette.text[3])
    self:PanelColors(b, palette.fill, palette.line)
    local w = (b.label.GetStringWidth and b.label:GetStringWidth()) or 60
    b:SetWidth(math.floor(w + 16))
    b:SetShown(text and text ~= "")
end

-- Small square icon button with a map-pin glyph (game map icon, cropped).
function T:MapButton(parent, size)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(size or 24, size or 24)
    self:SkinButton(b, "quiet")
    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetSize((size or 24) - 10, (size or 24) - 10)
    b.icon:SetPoint("CENTER")
    b.icon:SetTexture("Interface\\Icons\\INV_Misc_Map_01")
    b.icon:SetTexCoord(0.10, 0.90, 0.10, 0.90)
    return b
end

-- Round profession icon: the game icon in a circle with a colored ring.
function T:RoundIcon(parent, size)
    local f = CreateFrame("Frame", nil, parent)
    f:SetSize(size or 30, size or 30)
    f.bg = f:CreateTexture(nil, "BACKGROUND")
    f.bg:SetAllPoints()
    f.bg:SetTexture(self.DISC)
    f.bg:SetVertexColor(self.C.well[1], self.C.well[2], self.C.well[3], 1)
    f.icon = f:CreateTexture(nil, "ARTWORK")
    f.icon:SetPoint("TOPLEFT", 2, -2)
    f.icon:SetPoint("BOTTOMRIGHT", -2, 2)
    f.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    if f.CreateMaskTexture then
        local mask = f:CreateMaskTexture()
        mask:SetAllPoints(f.icon)
        local ok = pcall(mask.SetTexture, mask, self.CIRCLE_MASK, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
        if ok and f.icon.AddMaskTexture then pcall(f.icon.AddMaskTexture, f.icon, mask) end
    end
    f.ring = f:CreateTexture(nil, "OVERLAY")
    f.ring:SetAllPoints()
    f.ring:SetTexture(self.RING)
    return f
end

function T:SetRoundIcon(f, texture, ringColor, dim)
    if not f then return end
    if texture then f.icon:SetTexture(texture) end
    if f.icon.SetDesaturated then f.icon:SetDesaturated(dim and true or false) end
    f.icon:SetAlpha(dim and 0.55 or 1)
    local c = ringColor or self.C.goldLine
    f.ring:SetVertexColor(c[1], c[2], c[3], dim and 0.5 or 1)
end

-- Section label: small caps text with a hairline to the right.
function T:SectionLabel(parent, caption, noLine)
    local h = CreateFrame("Frame", nil, parent)
    h:SetHeight(16)
    h.label = h:CreateFontString(nil, "OVERLAY", "GatherpediaFontLabel")
    h.label:SetPoint("LEFT", 0, 0)
    h.label:SetText(caption and caption:upper() or "")
    if not noLine then
        h.line = h:CreateTexture(nil, "ARTWORK")
        h.line:SetHeight(1)
        h.line:SetPoint("LEFT", h.label, "RIGHT", 8, 0)
        h.line:SetPoint("RIGHT", h, "RIGHT", 0, 0)
        h.line:SetColorTexture(self.C.line[1], self.C.line[2], self.C.line[3], 1)
    end
    return h
end

---------------------------------------------------------------------------
-- Shared form controls: a checkbox row and a slider row. Used by the
-- Options window, the Glimmer page and the arrow menu so they match.
---------------------------------------------------------------------------

local function Tip(frame, title, text)
    if not text then return end
    frame:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(title)
        GameTooltip:AddLine(text, 1, 1, 1, true)
        GameTooltip:Show()
    end)
    frame:SetScript("OnLeave", function() GameTooltip:Hide() end)
end

-- Rounded box with a gold check square, label to the right. Clicking the
-- row flips the setting: set(not get()), then onChange().
function T:CheckRow(parent, label, tooltip, get, set, onChange)
    local C = self.C
    local row = CreateFrame("Button", nil, parent)
    row:SetSize(300, 24)
    local box = CreateFrame("Frame", nil, row)
    box:SetSize(18, 18)
    box:SetPoint("LEFT", 0, 0)
    self:Panel(box, C.well, C.line2, 5)
    row.box = box
    row.mark = box:CreateTexture(nil, "ARTWORK")
    row.mark:SetTexture(self.ROUND)
    row.mark:SetPoint("TOPLEFT", 4, -4)
    row.mark:SetPoint("BOTTOMRIGHT", -4, 4)
    row.mark:SetVertexColor(C.gold[1], C.gold[2], C.gold[3], 1)
    row.label = row:CreateFontString(nil, "OVERLAY", "GatherpediaFontHighlight")
    row.label:SetPoint("LEFT", box, "RIGHT", 10, 0)
    row.label:SetPoint("RIGHT", row, "RIGHT", 0, 0)
    row.label:SetJustifyH("LEFT")
    if row.label.SetWordWrap then row.label:SetWordWrap(false) end
    row.label:SetText(label)
    row:SetScript("OnClick", function(self)
        set(not get())
        self:Refresh()
        if onChange then onChange() end
    end)
    Tip(row, label, tooltip)
    self:HoverPaint(row,
        function(r) r._hover = true; r:Refresh() end,
        function(r) r._hover = nil; r:Refresh() end)
    row.Refresh = function(self)
        local on = get() and true or false
        self.mark:SetShown(on)
        local line = (on or self._hover) and C.goldLine or C.line2
        T:PanelColors(self.box, C.well, line)
        local tc = self._hover and C.goldHi or C.text
        self.label:SetTextColor(tc[1], tc[2], tc[3])
    end
    row:Refresh()
    return row
end

-- Label "Name: value" over a thin rounded track with a gold fill and a
-- round knob. Drag anywhere on the row. fmt is a format string or a
-- function(v) -> text. set(v) runs on user changes, then onChange(v).
function T:SliderRow(parent, w, label, minV, maxV, step, fmt, get, set, tip, onChange)
    local C = self.C
    local wrap = CreateFrame("Frame", nil, parent)
    wrap:SetSize(w, 40)
    wrap:EnableMouse(true)
    Tip(wrap, label, tip)
    local name = wrap:CreateFontString(nil, "OVERLAY", "GatherpediaFontHighlightSmall")
    name:SetPoint("TOPLEFT", 0, 0)
    name:SetJustifyH("LEFT")
    wrap.label = name
    local track = CreateFrame("Frame", nil, wrap)
    track:SetPoint("TOPLEFT", 0, -22)
    track:SetSize(w, 6)
    self:Panel(track, C.well, C.line, 3)
    local fill = track:CreateTexture(nil, "ARTWORK")
    fill:SetTexture(self.ROUND)
    fill:SetVertexColor(C.gold[1], C.gold[2], C.gold[3], 0.9)
    fill:SetPoint("TOPLEFT", 1, -1)
    fill:SetPoint("BOTTOMLEFT", 1, 1)
    local knob = track:CreateTexture(nil, "OVERLAY")
    knob:SetTexture(self.DISC)
    knob:SetSize(14, 14)
    knob:SetVertexColor(C.goldHi[1], C.goldHi[2], C.goldHi[3], 1)
    local knobRim = track:CreateTexture(nil, "OVERLAY", nil, -1)
    knobRim:SetTexture(self.DISC)
    knobRim:SetSize(18, 18)
    knobRim:SetVertexColor(C.window[1], C.window[2], C.window[3], 1)
    local hex = self:Hex(C.goldHi)

    local function apply(v, fromUser)
        v = math.floor((v / step) + 0.5) * step
        if v < minV then v = minV elseif v > maxV then v = maxV end
        wrap._value = v
        local t = (v - minV) / (maxV - minV)
        if t < 0 then t = 0 elseif t > 1 then t = 1 end
        fill:SetWidth(math.max(1, (w - 2) * t))
        knob:ClearAllPoints()
        knob:SetPoint("CENTER", track, "LEFT", 1 + (w - 2) * t, 0)
        knobRim:ClearAllPoints()
        knobRim:SetPoint("CENTER", knob, "CENTER")
        local shown = (type(fmt) == "function") and fmt(v) or fmt:format(v)
        name:SetText(label .. ":  |cff" .. hex .. shown .. "|r")
        if fromUser then
            set(v)
            if onChange then onChange(v) end
        end
    end

    local function fromCursor()
        if not GetCursorPosition or not track.GetLeft then return end
        local cx = GetCursorPosition()
        local left, width = track:GetLeft(), track:GetWidth()
        local scale = (track.GetEffectiveScale and track:GetEffectiveScale()) or 1
        if not left or not width or width == 0 or scale == 0 then return end
        apply(minV + (((cx / scale) - left) / width) * (maxV - minV), true)
    end
    local function down() wrap._drag = true; fromCursor() end
    local function up() wrap._drag = false end
    wrap:SetScript("OnMouseDown", down)
    wrap:SetScript("OnMouseUp", up)
    wrap:SetScript("OnUpdate", function() if wrap._drag then fromCursor() end end)
    track:EnableMouse(true)
    track:SetScript("OnMouseDown", down)
    track:SetScript("OnMouseUp", up)
    wrap.Refresh = function() apply(get(), false) end
    wrap.apply = apply
    wrap:Refresh()
    return wrap
end
