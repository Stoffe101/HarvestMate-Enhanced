-- HarvestMate Enhanced: UI/Theme.lua
-- HME's design system. Started as the shared look of severd8's WoW: Forever
-- addons (MIT; from GatherPath Forever 1.12.1, see UPSTREAM.md); 0.3.0 redraws
-- it: calm charcoal surfaces, one leaf-green accent, gold kept for money,
-- Inter for type (bundled, SIL OFL 1.1: Media/Fonts/Inter-LICENSE.txt),
-- rounded shapes drawn as nine slices, primary and secondary buttons, pill
-- switches, and a window with a slim header, a quiet sidebar and a status line.
--
-- Every shape falls back to a flat square where the client lacks nine-slice
-- textures, and the type to the game's font where a font file will not load
-- (Settings: "Interface font" and "Rounded corners").

local ADDON, ns = ...
local T = {}
ns.Theme = T

-- What each addon calls itself and where its logo is (inside its own folder)
local BRANDS = {
    TauntMasterForever = { name = "TauntMaster Forever", short = "TauntMaster", logo = "Media\\logo" },
    ToppedOffForever   = { name = "ToppedOff Forever",   short = "ToppedOff",   logo = "Media\\Icon" },
    OutfitterForever   = { name = "Outfitter Forever",   short = "Outfitter",   logo = "Textures\\Logo" },
    BattleTextForever  = { name = "BattleText Forever",  short = "BattleText",  logo = "Media\\Icon" },
    GatherPathForever  = { name = "GatherPath Forever",  short = "GatherPath",  logo = "Media\\Icon" },
    HarvestMateEnhanced = { name = "HarvestMate Enhanced", short = "HarvestMate", logo = "Media\\Logo" },
}
local brand = BRANDS[ADDON] or { name = tostring(ADDON), short = tostring(ADDON), logo = "" }
T.NAME = brand.name     -- window titles, chat, tooltips
T.SHORT = brand.short   -- the header bar, where room is tight
local BASE = "Interface\\AddOns\\" .. tostring(ADDON) .. "\\"
T.LOGO = BASE .. brand.logo
T.ART = BASE .. "Media\\UI\\"
-- Chat lines start with the logo and the addon's name in the accent colour
T.CHAT_PREFIX = "|T" .. T.LOGO .. ":0|t |cff4fd68c" .. T.NAME .. "|r"

---------------------------------------------------------------------------
-- Tokens
---------------------------------------------------------------------------
local C = {
    -- surfaces, darkest to lightest
    side    = { 0.055, 0.060, 0.068, 1 },     -- sidebar, status line
    win     = { 0.078, 0.084, 0.095, 0.98 },  -- the window
    field   = { 0.058, 0.062, 0.071, 1 },     -- inputs, list wells
    card    = { 0.105, 0.113, 0.127, 1 },     -- cards
    raised  = { 0.145, 0.155, 0.173, 1 },     -- secondary buttons, selected segments
    raisedHi = { 0.190, 0.202, 0.225, 1 },    -- their hover
    line    = { 1, 1, 1, 0.07 },              -- hairlines inside
    edge    = { 1, 1, 1, 0.11 },              -- outlines of cards and windows
    fieldEdge = { 1, 1, 1, 0.13 },            -- outlines of inputs
    -- text
    text    = { 0.93, 0.94, 0.95 },
    text2   = { 0.74, 0.77, 0.81 },
    text3   = { 0.56, 0.59, 0.64 },
    -- the accent: leaf green
    accent  = { 0.31, 0.84, 0.55, 1 },
    accentHi = { 0.42, 0.90, 0.64, 1 },
    accentInk = { 0.03, 0.11, 0.07, 1 },      -- text on accent buttons
    accentWash = { 0.31, 0.84, 0.55, 0.12 },  -- selected rows and tabs
    -- meaning
    gold    = { 0.95, 0.77, 0.32, 1 },        -- money and value
    success = { 0.31, 0.84, 0.55, 1 },
    warning = { 0.97, 0.66, 0.27, 1 },
    danger  = { 0.94, 0.39, 0.43, 1 },
    info    = { 0.40, 0.67, 1.00, 1 },
}
-- Older names other files still use, on the new palette.
C.red, C.redHi = C.raised, C.raisedHi
C.btnEdge = C.edge
C.offTrack = { 0.21, 0.22, 0.25, 1 }
C.onTrack = C.accent
C.orange = C.text3                 -- small labels and card titles
C.muted, C.grey, C.title, C.version = C.text2, C.text3, C.text, C.text3
C.tabOn = C.accentWash
C.fill = C.accent

T.HEX = { accent = "4fd68c", gold = "f2c452", text2 = "bdc4cf", text3 = "8f97a3", danger = "f0646d", warning = "f7a845", info = "66abff" }

---------------------------------------------------------------------------
-- Type: Inter, in a few roles (the game's own font where Inter won't load)
---------------------------------------------------------------------------
local FONT = BASE .. "Media\\Fonts\\"
T.FONT = { regular = FONT .. "Inter-Regular.ttf", semibold = FONT .. "Inter-SemiBold.ttf", bold = FONT .. "Inter-Bold.ttf" }
-- role = { weight, size, colour, game template it stands in for }
local ROLES = {
    body    = { "regular", 12, C.text, "GameFontHighlight" },
    small   = { "regular", 11, C.text, "GameFontHighlightSmall" },
    meta    = { "regular", 11, C.text3, "GameFontDisableSmall" },
    metaLg  = { "regular", 12, C.text3, "GameFontDisable" },
    strong  = { "semibold", 12, C.text, "GameFontNormal" },
    label   = { "semibold", 10, C.text3, "GameFontNormalSmall" },
    title   = { "semibold", 16, C.text, "GameFontNormalLarge" },
    display = { "bold", 22, C.text, "GameFontNormalHuge" },
}
T.ROLES = ROLES
local BY_TEMPLATE = {
    GameFontHighlight = "body", GameFontHighlightSmall = "small", GameFontDisableSmall = "meta", GameFontDisable = "metaLg",
    GameFontNormal = "strong", GameFontNormalSmall = "label", GameFontNormalLarge = "title", GameFontHighlightLarge = "title",
    GameFontNormalHuge = "display",
}
local fontObjects = {}

local function UseInter()
    local s = ns.HME and ns.HME.settings
    return not (s and s.uiFont == "game")
end

-- The font object for a role (made once), or nil to use the game's template.
local function FontObject(role)
    if fontObjects[role] ~= nil then return fontObjects[role] or nil end
    local r = ROLES[role]
    if not (r and CreateFont and UseInter()) then return nil end
    local name = "HarvestMateEnhancedFont_" .. role
    local fo = _G[name] or CreateFont(name)
    -- Success is read back from the font object: SetFont's own return value
    -- differs between clients, and a file that fails to load leaves no font.
    if fo and fo.SetFont then pcall(fo.SetFont, fo, T.FONT[r[1]], r[2], "") end
    local ok = fo and fo.GetFont and fo:GetFont() ~= nil
    if not ok then
        fontObjects[role] = false
        return nil
    end
    fo:SetTextColor(r[3][1], r[3][2], r[3][3])
    if fo.SetShadowColor then fo:SetShadowColor(0, 0, 0, 0.55) end
    if fo.SetShadowOffset then fo:SetShadowOffset(0, -1) end
    fontObjects[role] = fo
    return fo
end
T.FontObject = FontObject

-- A font string in a role (or a game template name, mapped to its role).
local function Text(parent, text, template, color, size)
    template = template or "GameFontHighlight"
    local role = ROLES[template] and template or BY_TEMPLATE[template]
    local fo = role and FontObject(role)
    local fs = parent:CreateFontString(nil, "OVERLAY", fo and fo:GetName() or (role and ROLES[role][4]) or template)
    if size then
        if fo then
            fs:SetFont(T.FONT[ROLES[role][1]], size, "")
        else
            local font, _, flags = fs:GetFont()
            if font then fs:SetFont(font, size, flags) end
        end
    end
    if color then
        fs:SetTextColor(color[1], color[2], color[3])
    elseif not fo and role then
        local c = ROLES[role][3]
        fs:SetTextColor(c[1], c[2], c[3])
    end
    fs:SetJustifyH("LEFT")
    fs:SetText(text or "")
    return fs
end

-- Restyle an existing font string into a role.
function T.SetRole(fs, role, size)
    local r = ROLES[role]
    if not r then return end
    local fo = FontObject(role)
    if fo then
        fs:SetFontObject(fo)
        if size then fs:SetFont(T.FONT[r[1]], size, "") end
    end
    fs:SetTextColor(r[3][1], r[3][2], r[3][3])
end

---------------------------------------------------------------------------
-- Shapes
---------------------------------------------------------------------------
local function Fill(frame, color, layer, sub)
    local t = frame:CreateTexture(nil, layer or "BACKGROUND", nil, sub or -8)
    t:SetAllPoints()
    t:SetColorTexture(unpack(color))
    return t
end

local function Border(frame, color)
    local edges = {}
    for _, side in ipairs({ "TOP", "BOTTOM", "LEFT", "RIGHT" }) do
        local t = frame:CreateTexture(nil, "BORDER")
        t:SetColorTexture(unpack(color))
        if side == "TOP" or side == "BOTTOM" then
            t:SetPoint(side .. "LEFT"); t:SetPoint(side .. "RIGHT"); t:SetHeight(1)
        else
            t:SetPoint("TOP" .. side); t:SetPoint("BOTTOM" .. side); t:SetWidth(1)
        end
        edges[#edges + 1] = t
    end
    return edges
end

local function Rounded()
    local s = ns.HME and ns.HME.settings
    return not (s and s.uiRounded == false)
end
T.Rounded = Rounded

-- A texture painted as a nine-slice shape, tinted. Falls back to a flat colour.
-- tex:Paint(color) recolours it either way.
local function Shape(tex, file, margin, color)
    local sliced = Rounded() and tex.SetTextureSliceMargins ~= nil
    if sliced then
        tex:SetTexture(T.ART .. file)
        tex:SetTextureSliceMargins(margin, margin, margin, margin)
        if tex.SetTextureSliceMode then pcall(tex.SetTextureSliceMode, tex, 0) end
    end
    tex.sliced = sliced
    function tex:Paint(c)
        if not c then return end
        if self.sliced then self:SetVertexColor(c[1], c[2], c[3], c[4] or 1) else self:SetColorTexture(c[1], c[2], c[3], c[4] or 1) end
    end
    tex:Paint(color)
    return tex
end

-- A rounded surface behind a frame (BACKGROUND). Returns the texture (:Paint).
function T.Surface(frame, color, layer, sub)
    local t = frame:CreateTexture(nil, layer or "BACKGROUND", nil, sub or -8)
    t:SetAllPoints()
    return Shape(t, "Round", 8, color)
end

-- A rounded outline (BORDER). Flat: four hairlines.
function T.Outline(frame, color)
    if Rounded() and frame.CreateTexture then
        local t = frame:CreateTexture(nil, "BORDER")
        if t.SetTextureSliceMargins then
            t:SetAllPoints()
            Shape(t, "RoundEdge", 8, color)
            return { t }
        end
        t:Hide()
    end
    return Border(frame, color)
end

-- A soft shadow around a frame, for things that float (window, HUD).
function T.Shadow(frame, spread)
    spread = spread or 14
    local holder = CreateFrame("Frame", nil, frame)
    holder:SetPoint("TOPLEFT", -spread, spread)
    holder:SetPoint("BOTTOMRIGHT", spread, -spread)
    if holder.SetFrameLevel and frame.GetFrameLevel then holder:SetFrameLevel(math.max(0, (frame:GetFrameLevel() or 1) - 1)) end
    local t = holder:CreateTexture(nil, "BACKGROUND", nil, -8)
    t:SetAllPoints()
    if Rounded() and t.SetTextureSliceMargins then
        t:SetTexture(T.ART .. "Shadow")
        t:SetTextureSliceMargins(24, 24, 24, 24)
        t:SetVertexColor(0, 0, 0, 0.55)
    else
        t:Hide()
    end
    holder.tex = t
    return holder
end

---------------------------------------------------------------------------
-- Buttons
---------------------------------------------------------------------------
-- kind: "primary" (accent), "secondary" (default), "ghost" (text only),
-- "danger" (red text). b:SetKind(kind) changes it later.
local KINDS = {
    primary   = { bg = C.accent, hover = C.accentHi, text = C.accentInk, edge = nil, role = "strong" },
    secondary = { bg = C.raised, hover = C.raisedHi, text = C.text, edge = C.edge, role = "strong" },
    ghost     = { bg = { 1, 1, 1, 0 }, hover = { 1, 1, 1, 0.06 }, text = C.text2, edge = nil, role = "strong" },
    danger    = { bg = { 1, 1, 1, 0 }, hover = { 0.94, 0.39, 0.43, 0.12 }, text = C.danger, edge = nil, role = "strong" },
}
T.BUTTON_KINDS = KINDS

local function FlatButton(parent, text, width, height, kind)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(width or 100, height or 24)
    b.bg = T.Surface(b, C.raised)
    b.edges = T.Outline(b, C.edge)
    local fs = Text(b, "", "strong")
    fs:SetPoint("LEFT", 8, 0)
    fs:SetPoint("RIGHT", -8, 0)
    fs:SetJustifyH("CENTER")
    if fs.SetWordWrap then fs:SetWordWrap(false) end
    b:SetFontString(fs)
    b.label = fs
    b:SetText(text)
    function b:SetKind(k)
        self.kind = KINDS[k] and k or "secondary"
        local s = KINDS[self.kind]
        self.bg:Paint(s.bg)
        for _, e in ipairs(self.edges) do e:SetShown(s.edge ~= nil) end
        self.label:SetTextColor(s.text[1], s.text[2], s.text[3])
    end
    function b:SetHover(on)
        local s = KINDS[self.kind or "secondary"]
        self.bg:Paint(on and s.hover or s.bg)
    end
    b:SetScript("OnEnter", function(self) self:SetHover(true) end)
    b:SetScript("OnLeave", function(self) self:SetHover(false) end)
    b:SetKind(kind or "secondary")
    return b
end

-- Hover tooltip: a title line and/or a wrapped white one. Keeps a button's own
-- hover colour working.
function T.Tooltip(widget, title, body)
    widget:SetScript("OnEnter", function(self)
        if self.SetHover then self:SetHover(true) end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        if title then GameTooltip:AddLine(title) end
        if body then GameTooltip:AddLine(body, 1, 1, 1, true) end
        GameTooltip:Show()
    end)
    widget:SetScript("OnLeave", function(self)
        if self.SetHover then self:SetHover(false) end
        GameTooltip:Hide()
    end)
end

-- Kept for callers of the old look: a quiet surface now, not a red gradient.
function T.HeaderGradient(tex)
    tex:SetColorTexture(C.card[1], C.card[2], C.card[3], 1)
end

-- On/off switch: a pill with a round knob. b:SetOn(bool) paints it; b:IsOn() reads it.
function T.SwitchWidget(parent)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(30, 16)
    b.isSwitch = true
    local track = b:CreateTexture(nil, "BACKGROUND")
    track:SetAllPoints()
    if Rounded() and track.SetTexture then track:SetTexture(T.ART .. "Track") track.shaped = true end
    local knob = b:CreateTexture(nil, "ARTWORK")
    knob:SetSize(12, 12)
    if Rounded() then knob:SetTexture(T.ART .. "Circle") knob.shaped = true end
    local function Tint(tex, c)
        if tex.shaped then tex:SetVertexColor(c[1], c[2], c[3], c[4] or 1) else tex:SetColorTexture(c[1], c[2], c[3], c[4] or 1) end
    end
    function b:SetOn(on)
        self.on = on and true or false
        Tint(track, self.on and C.accent or C.offTrack)
        Tint(knob, self.on and { 1, 1, 1, 1 } or C.text2)
        knob:ClearAllPoints()
        knob:SetPoint("LEFT", self, "LEFT", self.on and 16 or 2, 0)
    end
    function b:IsOn() return self.on end
    b:SetOn(false)
    return b
end

T.C, T.Fill, T.Border, T.Text, T.FlatButton = C, Fill, Border, Text, FlatButton

---------------------------------------------------------------------------
-- An on-screen panel (HUD, Skinning levels): dark, a little see-through,
-- rounded, outlined.
---------------------------------------------------------------------------
function T.Panel(frame, alpha)
    frame.bg = T.Surface(frame, { C.win[1], C.win[2], C.win[3], alpha or 0.9 })
    T.Outline(frame, C.edge)
    return frame
end

---------------------------------------------------------------------------
-- The title row of an on-screen panel: a small logo and the name, quiet.
-- Adds .bg, .logo and .text to the frame it's given.
---------------------------------------------------------------------------
function T.HeaderStrip(frame, text)
    frame.bg = frame:CreateTexture(nil, "BACKGROUND")
    frame.bg:SetPoint("BOTTOMLEFT", 6, 0)
    frame.bg:SetPoint("BOTTOMRIGHT", -6, 0)
    frame.bg:SetHeight(1)
    frame.bg:SetColorTexture(unpack(C.line))
    frame.logo = frame:CreateTexture(nil, "ARTWORK")
    frame.logo:SetPoint("LEFT", 6, 0)
    frame.logo:SetSize(12, 12)
    frame.logo:SetTexture(T.LOGO)
    frame.text = Text(frame, text or T.SHORT, "label")
    frame.text:SetPoint("LEFT", frame.logo, "RIGHT", 5, 0)
    frame.text:SetPoint("RIGHT", -6, 0)
    frame.text:SetJustifyH("LEFT")
    frame.text:SetWordWrap(false)
    function frame:FitLogo(_height)   -- kept for callers; the logo is a fixed 12
        self.logo:SetSize(12, 12)
    end
    return frame
end

---------------------------------------------------------------------------
-- Widgets for a settings page
---------------------------------------------------------------------------
-- The small chevron at the right of anything that opens a menu
function T.MenuArrow(button, inset)
    local arrow = button:CreateTexture(nil, "OVERLAY")
    arrow:SetSize(12, 12)
    arrow:SetPoint("RIGHT", -inset, 0)
    arrow:SetTexture(T.ART .. "Chevron")
    arrow:SetVertexColor(C.text3[1], C.text3[2], C.text3[3])
    return arrow
end

-- Card: a rounded panel with a small uppercase title. Content starts at y = -28.
function T.Card(parent, title, x, y, w, h)
    local f = CreateFrame("Frame", nil, parent)
    f:SetPoint("TOPLEFT", x, y)
    f:SetSize(w, h)
    f.bg = T.Surface(f, C.card)
    T.Outline(f, C.line)
    f.title = Text(f, title and title:upper() or "", "label")
    f.title:SetPoint("TOPLEFT", 12, -11)
    return f
end

function T.Note(parent, text, x, y, width)
    local n = Text(parent, text, "meta")
    n:SetPoint("TOPLEFT", x, y)
    if width then n:SetWidth(width); n:SetWordWrap(true) end
    return n
end

function T.RowLabel(parent, text, x, y)
    local fs = Text(parent, text, "body")
    fs:SetPoint("TOPLEFT", x, y - 4)
    return fs
end

-- Greys a control out (and back): b:SetDisabled(true). Widgets that take clicks
-- check b.disabled; the tooltip still shows, to say why.
local DISABLED_ALPHA = 0.4
local function Disabler(widget, parts)
    function widget:SetDisabled(off)
        self.disabled = off and true or false
        local a = self.disabled and DISABLED_ALPHA or 1
        for _, part in ipairs(parts) do part:SetAlpha(a) end
    end
end
T.Disabler = Disabler

-- Makes the text beside a control part of it: hovering or clicking the text
-- is the same as the control (its click area stretches over the text)
function T.ClickableLabel(widget, label, gap)
    local w = label.GetStringWidth and label:GetStringWidth()
    w = type(w) == "number" and w or 0
    widget:SetHitRectInsets(0, -((gap or 8) + math.ceil(w)), -4, -4)
end

-- A switch with its label to the right. Returns the switch and the label.
-- Clicking or hovering the label works like the switch.
function T.LabeledSwitch(parent, text, x, y, labelWidth)
    local b = T.SwitchWidget(parent)
    b:SetPoint("TOPLEFT", x, y)
    local label = Text(parent, text, "body")
    label:SetPoint("LEFT", b, "RIGHT", 10, 0)
    if labelWidth then label:SetWidth(labelWidth); label:SetWordWrap(true) end
    b.label = label
    T.ClickableLabel(b, label, 10)
    Disabler(b, { b, label })
    return b, label
end

-- Dropdown: shows the current choice; click for a menu of the choices (or step
-- to the next one where the game has no menus). labels[key] is the text shown.
-- Set b.menuScroll to a height to make a long menu scroll.
function T.Dropdown(parent, width, keys, labels, getter, setter)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(width, 24)
    b.bg = T.Surface(b, C.field)
    T.Outline(b, C.fieldEdge)
    local fs = Text(b, "", "small")
    fs:SetPoint("LEFT", 9, 0)
    fs:SetPoint("RIGHT", -22, 0)
    fs:SetWordWrap(false)
    b:SetFontString(fs)
    T.MenuArrow(b, 7)
    b.keys, b.labels, b.getter, b.setter = keys, labels, getter, setter
    function b:SetHover(on) self.bg:Paint(on and C.card or C.field) end
    b:SetScript("OnEnter", function(self) self:SetHover(true) end)
    b:SetScript("OnLeave", function(self) self:SetHover(false) end)

    local function label(k)
        if type(b.labels) == "function" then return b.labels(k) end
        return b.labels[k] or tostring(k)
    end
    local function refresh() b:SetText(label(b.getter())) end
    local function choose(k) b.setter(k); refresh() end
    Disabler(b, { b })
    b:SetScript("OnClick", function(self)
        if self.disabled then return end
        if MenuUtil and MenuUtil.CreateContextMenu then
            MenuUtil.CreateContextMenu(self, function(_, root)
                if self.menuTitle then root:CreateTitle(self.menuTitle) end
                if self.menuScroll and root.SetScrollMode then root:SetScrollMode(self.menuScroll) end
                for _, k in ipairs(self.keys) do
                    root:CreateRadio(self.menuLabels and self.menuLabels[k] or label(k),
                        function() return self.getter() == k end, function() choose(k) end)
                end
            end)
        else
            local cur, nextIdx = self.getter(), 1
            for i, k in ipairs(self.keys) do
                if k == cur then nextIdx = (i % #self.keys) + 1 break end
            end
            if self.keys[nextIdx] ~= nil then choose(self.keys[nextIdx]) end
        end
    end)
    b.Refresh = refresh
    b.Choose = choose
    return b
end

-- Slider: label on the left, value on the right, a thin rounded track with an
-- accent fill and a round knob. get() reads the setting, set(v) saves it;
-- s.Refresh() repaints it. zeroText: what the value reads at 0 ("Off").
function T.Slider(parent, text, x, y, width, get, set, min, max, suffix, step, fmt, zeroText)
    suffix, step, fmt = suffix or "", step or 1, fmt or "%d"
    local function show(v)
        if zeroText and v == 0 then return zeroText end
        return fmt:format(v) .. suffix
    end
    local title = Text(parent, text, "body")
    title:SetPoint("TOPLEFT", x, y)
    local value = Text(parent, "", "strong", C.accent)
    value:SetPoint("TOPRIGHT", parent, "TOPLEFT", x + width, y)
    value:SetJustifyH("RIGHT")

    local s = CreateFrame("Slider", nil, parent)
    s:SetOrientation("HORIZONTAL")
    s:SetSize(width, 14)
    s:SetPoint("TOPLEFT", x, y - 20)
    s:SetHitRectInsets(0, 0, -6, -6)
    local track = s:CreateTexture(nil, "BACKGROUND")
    track:SetHeight(4)
    track:SetPoint("LEFT"); track:SetPoint("RIGHT")
    Shape(track, "Round", 2, C.offTrack)
    local thumb = s:CreateTexture(nil, "OVERLAY")
    thumb:SetSize(12, 12)
    if Rounded() then thumb:SetTexture(T.ART .. "Circle") thumb:SetVertexColor(1, 1, 1, 1) else thumb:SetColorTexture(1, 1, 1, 1) end
    s:SetThumbTexture(thumb)
    local fill = s:CreateTexture(nil, "ARTWORK")
    fill:SetHeight(4)
    fill:SetPoint("LEFT", track, "LEFT")
    fill:SetPoint("RIGHT", thumb, "CENTER")
    Shape(fill, "Round", 2, C.accent)
    s:SetMinMaxValues(min, max)
    s:SetValueStep(step)
    if s.SetObeyStepsOnDrag then s:SetObeyStepsOnDrag(true) end   -- missing on Forever

    s:SetScript("OnValueChanged", function(_, v)
        v = math.floor(v / step + 0.5) * step
        if step >= 1 then v = math.floor(v + 0.5) end
        value:SetText(show(v))
        if get() ~= v then set(v) end
    end)
    function s.Refresh()
        s:SetValue(get())
        value:SetText(show(get()))
    end
    s.title, s.valueText = title, value
    Disabler(s, { s, title, value })
    local setDisabled = s.SetDisabled
    function s:SetDisabled(off)
        setDisabled(self, off)
        self:EnableMouse(not off)
    end
    return s
end

-- Text box: a field with an outline that turns accent while typing.
function T.EditBox(parent, width)
    local eb = CreateFrame("EditBox", nil, parent)
    eb:SetSize(width, 24)
    eb:SetAutoFocus(false)
    eb:SetFontObject(FontObject("small") or GameFontHighlightSmall)
    eb:SetTextInsets(8, 8, 0, 0)
    eb.bg = T.Surface(eb, C.field)
    local edges = T.Outline(eb, C.fieldEdge)
    local function Edge(c) for _, e in ipairs(edges) do if e.Paint then e:Paint(c) else e:SetColorTexture(c[1], c[2], c[3], c[4] or 1) end end end
    eb:SetScript("OnEditFocusGained", function() Edge(C.accent) end)
    eb:SetScript("OnEditFocusLost", function() Edge(C.fieldEdge) end)
    eb:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    eb:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    return eb
end

-- A page that can outgrow the window: scrolls with the mouse wheel or the slim
-- bar at its right. Put the content in scroll.child, then call
-- scroll:SetContent(width, height) whenever it changes.
function T.ScrollArea(parent, viewHeight)
    local scroll = CreateFrame("ScrollFrame", nil, parent)
    scroll:SetPoint("TOPLEFT")
    scroll:SetPoint("BOTTOMRIGHT", -12, 0)
    local child = CreateFrame("Frame", nil, scroll)
    child:SetSize(10, 10)
    scroll:SetScrollChild(child)
    scroll.child = child

    local bar = CreateFrame("Slider", nil, parent)
    bar:SetOrientation("VERTICAL")
    bar:SetWidth(4)
    bar:SetPoint("TOPRIGHT", -2, 0)
    bar:SetPoint("BOTTOMRIGHT", -2, 0)
    local thumb = bar:CreateTexture(nil, "OVERLAY")
    thumb:SetSize(4, 40)
    Shape(thumb, "Round", 2, { 1, 1, 1, 0.22 })
    bar:SetThumbTexture(thumb)
    bar:SetMinMaxValues(0, 0)
    bar:SetValue(0)
    bar:SetScript("OnValueChanged", function(_, v) scroll:SetVerticalScroll(v) end)
    scroll.bar = bar

    local range = 0
    scroll:EnableMouseWheel(true)
    scroll:SetScript("OnMouseWheel", function(_, delta)
        bar:SetValue(math.max(0, math.min(range, (bar:GetValue() or 0) - delta * 40)))
    end)
    -- keepPlace: stay where the reader was (when the same content is drawn again)
    function scroll:SetContent(width, height, keepPlace)
        child:SetSize(width, height)
        range = math.max(0, height - viewHeight)
        local at = keepPlace and math.min(bar:GetValue() or 0, range) or 0
        bar:SetMinMaxValues(0, range)
        bar:SetShown(range > 0)
        bar:SetValue(at)
        self:SetVerticalScroll(at)
    end
    return scroll
end

---------------------------------------------------------------------------
-- The window: a slim header (logo, name, version, close) you drag it by, a
-- quiet sidebar of tabs, one page per tab, and a status line.
--   opts.name     global frame name (Escape closes it)
--   opts.tabs     { { key =, label =, icon =, build = function(body, page) }, ... }
--   opts.hint     status line text
--   opts.version  function returning the version shown beside the name
--   opts.onShow / onHide / onTab(key)   optional
--   opts.height   optional: taller (or shorter) than T.WINDOW.H; T.BodyHeight(h) is what a page then gets
-- Returns the window, with .pages[key], .tabButtons[key], :ShowTab(key) and .currentTab
---------------------------------------------------------------------------
T.WINDOW = { W = 740, H = 556, HEADER = 52, FOOTER = 40, SIDE = 170, PAGE_W = 540 }
-- what's left for a page's content in a window this tall
function T.BodyHeight(h) return (h or T.WINDOW.H) - T.WINDOW.HEADER - T.WINDOW.FOOTER - 54 end
T.WINDOW.BODY_H = T.BodyHeight()

function T.Window(opts)
    local W, H, HEADER, FOOTER = opts.width or T.WINDOW.W, opts.height or T.WINDOW.H, T.WINDOW.HEADER, T.WINDOW.FOOTER
    local SIDE = opts.compact and 48 or (opts.side or T.WINDOW.SIDE)
    local TAB_H = opts.tabHeight or 34
    local win = CreateFrame("Frame", opts.name, UIParent)
    win:SetSize(W, H)
    win:SetPoint("CENTER")
    win:SetFrameStrata("DIALOG")
    win:SetToplevel(true)
    win:SetMovable(true)
    win:SetClampedToScreen(true)
    win:EnableMouse(true)
    win:Hide()
    table.insert(UISpecialFrames, opts.name)
    win.shadow = T.Shadow(win, 18)
    win.bg = T.Surface(win, C.win)
    T.Outline(win, C.edge)
    win.pages, win.tabButtons, win.pending = {}, {}, {}

    -- Header: drag to move
    local header = CreateFrame("Frame", nil, win)
    header:SetPoint("TOPLEFT", 1, -1)
    header:SetPoint("TOPRIGHT", -1, -1)
    header:SetHeight(HEADER)
    header:EnableMouse(true)
    header:RegisterForDrag("LeftButton")
    header:SetScript("OnDragStart", function() win:StartMoving() end)
    header:SetScript("OnDragStop", function() win:StopMovingOrSizing() end)
    local hline = header:CreateTexture(nil, "BORDER")
    hline:SetPoint("BOTTOMLEFT"); hline:SetPoint("BOTTOMRIGHT"); hline:SetHeight(1)
    hline:SetColorTexture(unpack(C.line))
    local logo = header:CreateTexture(nil, "ARTWORK")
    logo:SetSize(26, 26)
    logo:SetPoint("LEFT", 16, 0)
    logo:SetTexture(T.LOGO)
    local title = Text(header, T.NAME, "title", C.text, 15)
    title:SetPoint("LEFT", logo, "RIGHT", 10, 0)
    local chip = CreateFrame("Frame", nil, header)
    chip:SetSize(52, 18)
    chip:SetPoint("LEFT", title, "RIGHT", 10, 0)
    chip.bg = T.Surface(chip, C.raised)
    local ver = Text(chip, "", "meta")
    ver:SetPoint("CENTER")
    ver:SetJustifyH("CENTER")
    local x = FlatButton(header, "×", 28, 28, "ghost")
    if FontObject("body") then x.label:SetFont(T.FONT.regular, 18, "") end
    x:SetPoint("RIGHT", -12, 0)
    x:SetScript("OnClick", function() win:Hide() end)
    T.Tooltip(x, "Close", "Escape closes it too.")
    win.header, win.logo, win.title, win.version = header, logo, title, ver

    win:SetScript("OnShow", function()
        local v = opts.version and opts.version()
        ver:SetText(v and ("v" .. v) or "")
        chip:SetShown(v ~= nil)
        if opts.onShow then opts.onShow() end
    end)
    win:SetScript("OnHide", function() if opts.onHide then opts.onHide() end end)

    function win:ShowTab(key)
        if not self.pages[key] then return end
        self.currentTab = key
        local build = self.pending[key]
        if build then
            self.pending[key] = nil
            build(self.pages[key].body, self.pages[key])
        end
        for k, p in pairs(self.pages) do p:SetShown(k == key) end
        for k, b in pairs(self.tabButtons) do
            local sel = (k == key)
            b.selBg:SetShown(sel)
            b.accent:SetShown(sel)
            b.icon:SetDesaturated(not sel)
            b.icon:SetAlpha(sel and 1 or 0.6)
            local c = sel and C.text or C.text2
            b.label:SetTextColor(c[1], c[2], c[3])
        end
        if opts.onTab then opts.onTab(key) end
    end

    -- Sidebar tabs
    local side = CreateFrame("Frame", nil, win)
    side:SetPoint("TOPLEFT", 1, -(HEADER + 1))
    side:SetPoint("BOTTOMLEFT", 1, FOOTER + 1)
    side:SetWidth(SIDE)
    Fill(side, C.side)
    local sline = side:CreateTexture(nil, "BORDER")
    sline:SetPoint("TOPRIGHT"); sline:SetPoint("BOTTOMRIGHT"); sline:SetWidth(1)
    sline:SetColorTexture(unpack(C.line))
    local yTab = -10
    for _, t in ipairs(opts.tabs) do
      if t.header then
        if not opts.compact then
            if t.header ~= "" then
                local h = Text(side, t.header:upper(), "label")
                h:SetPoint("TOPLEFT", 18, yTab - 12)
                h:SetWidth(SIDE - 30)
                h:SetWordWrap(false)
                yTab = yTab - 30
            else
                yTab = yTab - 14
            end
        else
            yTab = yTab - 10
        end
      else
        local b = CreateFrame("Button", nil, side)
        b:SetSize(SIDE - 17, TAB_H - 4)
        b:SetPoint("TOPLEFT", 8, yTab - 2)
        yTab = yTab - TAB_H
        b.selBg = T.Surface(b, C.raised)
        b.accent = b:CreateTexture(nil, "ARTWORK")
        b.accent:SetPoint("TOPLEFT", 0, -7); b.accent:SetPoint("BOTTOMLEFT", 0, 7); b.accent:SetWidth(3)
        Shape(b.accent, "Round", 1, C.accent)
        local hl = b:CreateTexture(nil, "HIGHLIGHT")
        hl:SetAllPoints()
        Shape(hl, "Round", 8, { 1, 1, 1, 0.04 })
        b.icon = b:CreateTexture(nil, "ARTWORK")
        b.icon:SetSize(16, 16)
        b.icon:SetPoint("LEFT", 12, 0)
        b.icon:SetTexture(t.icon)
        b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        local fs = Text(b, "", "body")
        fs:SetPoint("LEFT", b.icon, "RIGHT", 10, 0)
        fs:SetPoint("RIGHT", -6, 0)
        fs:SetWordWrap(false)
        b:SetFontString(fs)
        b.label = fs
        b:SetText(t.label)
        if opts.compact then
            fs:Hide()
            b.icon:ClearAllPoints()
            b.icon:SetPoint("CENTER")
            T.Tooltip(b, t.label, t.tip)
        elseif t.tip then
            T.Tooltip(b, t.label, t.tip)
        end
        b:SetScript("OnClick", function() win:ShowTab(t.key) end)
        win.tabButtons[t.key] = b
      end
    end

    -- Pages (built now, or the first time shown with opts.lazy)
    for _, t in ipairs(opts.tabs) do
      if not t.header then
        local page = CreateFrame("Frame", nil, win)
        page:SetPoint("TOPLEFT", SIDE + 16, -(HEADER + 14))
        page:SetPoint("BOTTOMRIGHT", -16, FOOTER + 10)
        page.title = Text(page, t.label, "title", C.text, 19)
        page.title:SetPoint("TOPLEFT", 0, 0)
        local body = CreateFrame("Frame", nil, page)
        body:SetPoint("TOPLEFT", 0, -30)
        body:SetPoint("BOTTOMRIGHT")
        page.body = body
        page:Hide()
        win.pages[t.key] = page
        if opts.lazy then
            win.pending[t.key] = t.build
        else
            t.build(body, page)
        end
      end
    end

    -- Status line
    local foot = CreateFrame("Frame", nil, win)
    foot:SetPoint("BOTTOMLEFT", 1, 1)
    foot:SetPoint("BOTTOMRIGHT", -1, 1)
    foot:SetHeight(FOOTER)
    Fill(foot, C.side)
    local fline = foot:CreateTexture(nil, "BORDER")
    fline:SetPoint("TOPLEFT"); fline:SetPoint("TOPRIGHT"); fline:SetHeight(1)
    fline:SetColorTexture(unpack(C.line))
    local hint = Text(foot, opts.hint or "", "meta")
    hint:SetPoint("LEFT", 16, 0)
    hint:SetPoint("RIGHT", -16, 0)
    hint:SetWordWrap(false)
    win.footer = foot

    win.hint = hint
    function win:SetUIScale(s) self:SetScale(math.max(0.6, math.min(1.5, s or 1))) end
    for _, t in ipairs(opts.tabs) do
        if t.key then
            win:ShowTab(opts.first or t.key)
            break
        end
    end
    return win
end
