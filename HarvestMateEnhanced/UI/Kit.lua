-- HarvestMate Enhanced: UI/Kit.lua
-- Widgets the pages share, in the Theme's look: labels, badges, skill bars,
-- icons, a virtual list (only the visible rows exist, so long lists cost
-- nothing), segmented controls, buttons in kinds, KPI tiles, empty states,
-- money text and profession colors.
-- Copyright (C) 2026 HarvestMate Enhanced contributors. GPL-3.0-or-later.

local _, ns = ...
local HME = ns.HME
local T = ns.Theme
local C = T.C
local U = HME.U

local K = {}
HME.Kit = K

-- Profession accents (Gatherpedia's, so the two look the same).
K.PROF_COLOR = {
    Herbalism = { 0.40, 0.80, 0.35 }, Mining = { 0.90, 0.58, 0.25 },
    Fishing = { 0.35, 0.65, 1.00 }, Skinning = { 0.85, 0.42, 0.32 },
}
K.PROF_ICON = {
    Herbalism = "Interface\\Icons\\Trade_Herbalism", Mining = "Interface\\Icons\\Trade_Mining",
    Fishing = "Interface\\Icons\\Trade_Fishing", Skinning = "Interface\\Icons\\INV_Misc_Pelt_Wolf_01",
}
K.PROFS = { "Herbalism", "Mining", "Skinning", "Fishing" }

function K.Hex(rgb)
    return ("%02x%02x%02x"):format(math.floor(rgb[1] * 255), math.floor(rgb[2] * 255), math.floor(rgb[3] * 255))
end

function K.Paint(text, hex) return hex and ("|cff" .. hex .. text .. "|r") or text end

function K.Label(parent, text, opts)
    opts = opts or {}
    local fs = T.Text(parent, text, opts.template or "GameFontHighlight", opts.color, opts.size)
    if opts.width then
        fs:SetWidth(opts.width)
        fs:SetWordWrap(opts.wrap ~= false)
    end
    if opts.justify then fs:SetJustifyH(opts.justify) end
    return fs
end

-- A section heading with a hairline under it.
function K.Heading(parent, text, x, y, w)
    local fs = T.Text(parent, text, "strong", C.text, 13)
    fs:SetPoint("TOPLEFT", x, y)
    local line = parent:CreateTexture(nil, "BORDER")
    line:SetColorTexture(unpack(C.line))
    line:SetHeight(1)
    line:SetPoint("TOPLEFT", x, y - 20)
    line:SetWidth(w or 300)
    return fs, line
end

local function Rgb(hex)
    if not hex then return 0.6, 0.6, 0.6 end
    return tonumber(hex:sub(1, 2), 16) / 255, tonumber(hex:sub(3, 4), 16) / 255, tonumber(hex:sub(5, 6), 16) / 255
end
K.Rgb = Rgb

-- A small tinted pill: b:Set(text, hex). The colour washes the pill and
-- colours its text, so meaning reads at a glance without shouting.
function K.Badge(parent, w, h)
    local b = CreateFrame("Frame", nil, parent)
    b:SetSize(w or 90, h or 18)
    b.bg = T.Surface(b, { 0.2, 0.2, 0.2, 0.9 })
    b.text = T.Text(b, "", "label", nil, 10)
    b.text:SetPoint("LEFT", 6, 0)
    b.text:SetPoint("RIGHT", -6, 0)
    b.text:SetJustifyH("CENTER")
    b.text:SetWordWrap(false)
    function b:Set(text, hex)
        self.text:SetText(text or "")
        local r, g, bl = Rgb(hex)
        self.bg:Paint({ r, g, bl, 0.16 })
        self.text:SetTextColor(math.min(1, r * 0.75 + 0.25), math.min(1, g * 0.75 + 0.25), math.min(1, bl * 0.75 + 0.25))
    end
    return b
end

-- A KPI tile: a small label, a big value and an optional line under it.
-- tile:Set(value, sub, color)
function K.Stat(parent, label, w, h)
    local f = CreateFrame("Frame", nil, parent)
    f:SetSize(w or 140, h or 62)
    f.bg = T.Surface(f, C.card)
    T.Outline(f, C.line)
    f.label = T.Text(f, label and label:upper() or "", "label")
    f.label:SetPoint("TOPLEFT", 12, -10)
    f.value = T.Text(f, "", "display", nil, 20)
    f.value:SetPoint("TOPLEFT", 12, -24)
    f.value:SetPoint("RIGHT", -10, 0)
    f.value:SetWordWrap(false)
    f.sub = T.Text(f, "", "meta")
    f.sub:SetPoint("TOPLEFT", f.value, "BOTTOMLEFT", 0, -3)
    f.sub:SetPoint("RIGHT", -10, 0)
    f.sub:SetWordWrap(false)
    function f:Set(value, sub, color)
        self.value:SetText(value or "–")
        local c = color or C.text
        self.value:SetTextColor(c[1], c[2], c[3])
        self.sub:SetText(sub or "")
    end
    return f
end

-- An empty state: an icon, a short title, a line of help and an optional
-- button. e:Set(title, text, buttonText, onClick) changes it.
function K.Empty(parent, icon, title, text, width)
    local f = CreateFrame("Frame", nil, parent)
    width = width or 320
    f:SetSize(width, 150)
    f.icon = f:CreateTexture(nil, "ARTWORK")
    f.icon:SetSize(36, 36)
    f.icon:SetPoint("TOP", 0, -6)
    f.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    f.icon:SetDesaturated(true)
    f.icon:SetAlpha(0.55)
    if icon then f.icon:SetTexture(icon) end
    f.title = T.Text(f, title or "", "strong", C.text, 14)
    f.title:SetPoint("TOP", f.icon, "BOTTOM", 0, -12)
    f.title:SetJustifyH("CENTER")
    f.text = T.Text(f, text or "", "small", C.text2)
    f.text:SetPoint("TOP", f.title, "BOTTOM", 0, -6)
    f.text:SetWidth(width - 20)
    f.text:SetJustifyH("CENTER")
    f.text:SetWordWrap(true)
    f.button = T.FlatButton(f, "", 150, 26, "primary")
    f.button:SetPoint("TOP", f.text, "BOTTOM", 0, -14)
    f.button:Hide()
    function f:Set(t, body, buttonText, onClick)
        self.title:SetText(t or "")
        self.text:SetText(body or "")
        if buttonText then
            self.button:SetText(buttonText)
            self.button:SetScript("OnClick", onClick)
            self.button:Show()
        else
            self.button:Hide()
        end
    end
    return f
end

-- Skill bar: bar:Set(skill, max, color, label). A thin marker shows the
-- next milestone when given (bar:Mark(skill)).
function K.Bar(parent, w, h)
    local bar = CreateFrame("Frame", nil, parent)
    bar:SetSize(w, h or 14)
    bar.track = T.Surface(bar, C.offTrack)
    bar.cap = bar:CreateTexture(nil, "BACKGROUND", nil, -6)
    bar.cap:SetPoint("TOPLEFT")
    bar.cap:SetPoint("BOTTOMLEFT")
    bar.cap:SetColorTexture(1, 1, 1, 0.05)
    bar.fill = bar:CreateTexture(nil, "ARTWORK")
    bar.fill:SetPoint("TOPLEFT")
    bar.fill:SetPoint("BOTTOMLEFT")
    bar.fillShape = T.Surface(bar, C.accent, "ARTWORK", 0)
    bar.fillShape:ClearAllPoints()
    bar.fillShape:SetPoint("TOPLEFT")
    bar.fillShape:SetPoint("BOTTOMLEFT")
    bar.fill:Hide()
    bar.mark = bar:CreateTexture(nil, "OVERLAY")
    bar.mark:SetWidth(2)
    bar.mark:SetPoint("TOP", 0, 2)
    bar.mark:SetPoint("BOTTOM", 0, -2)
    bar.mark:SetColorTexture(1, 1, 1, 0.75)
    bar.mark:Hide()
    bar.text = T.Text(bar, "", "label", C.text, 10)
    bar.text:SetPoint("CENTER")
    bar.text:SetJustifyH("CENTER")
    local inner = w
    function bar:Set(value, max, color, label, top)
        top = top or 300
        local f = U.Clamp((value or 0) / top, 0, 1)
        self.fillShape:SetWidth(math.max(4, inner * f))
        self.fillShape:SetShown(f > 0)
        local c = color or C.accent
        self.fillShape:Paint({ c[1], c[2], c[3], 0.9 })
        self.cap:SetWidth(math.max(1, inner * U.Clamp((max or top) / top, 0, 1)))
        self.text:SetText(label or ((value or 0) .. " / " .. (max or top)))
    end
    function bar:Mark(at, top)
        if not at then self.mark:Hide() return end
        self.mark:ClearAllPoints()
        local x = inner * U.Clamp(at / (top or 300), 0, 1)
        self.mark:SetPoint("TOPLEFT", x, 2)
        self.mark:SetPoint("BOTTOMLEFT", x, -2)
        self.mark:Show()
    end
    return bar
end

function K.Icon(parent, size, texture)
    local f = CreateFrame("Frame", nil, parent)
    f:SetSize(size, size)
    f.tex = f:CreateTexture(nil, "ARTWORK")
    f.tex:SetPoint("TOPLEFT", 1, -1)
    f.tex:SetPoint("BOTTOMRIGHT", -1, 1)
    f.tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    if texture then f.tex:SetTexture(texture) end
    T.Fill(f, { 0, 0, 0, 0.6 })
    T.Border(f, C.edge)
    return f
end

-- Copper with coin icons where the client draws them.
function K.Money(copper)
    copper = math.floor((copper or 0) + 0.5)
    local coins = (C_CurrencyInfo and C_CurrencyInfo.GetCoinTextureString) or _G.GetCoinTextureString
    if coins and copper >= 0 then
        local ok, s = pcall(coins, copper)
        if ok and type(s) == "string" then return s end
    end
    return U.Money(copper)
end

-- Virtual list: rows exist only for what is on screen.
--   list = K.List(parent, { rowHeight, width, height, makeRow(row), fillRow(row, item, index), onClick(item, index, button) })
--   list:SetItems(items); list:Select(index)
function K.List(parent, opts)
    local list = CreateFrame("Frame", nil, parent)
    list:SetSize(opts.width, opts.height)
    list.bg = T.Surface(list, C.field)
    T.Outline(list, C.line)
    local rh = opts.rowHeight or 28
    local visible = math.floor((opts.height - 4) / rh)
    list.items, list.offset, list.rows, list.selected = {}, 0, {}, nil

    local bar = CreateFrame("Slider", nil, list)
    bar:SetOrientation("VERTICAL")
    bar:SetWidth(4)
    bar:SetPoint("TOPRIGHT", -3, -4)
    bar:SetPoint("BOTTOMRIGHT", -3, 4)
    local thumb = T.Surface(bar, { 1, 1, 1, 0.22 }, "OVERLAY")
    thumb:ClearAllPoints()
    thumb:SetSize(4, 30)
    bar:SetThumbTexture(thumb)
    bar:SetMinMaxValues(0, 0)
    bar:SetValueStep(1)
    list.bar = bar

    local function Render()
        for i = 1, visible do
            local row = list.rows[i]
            local idx = list.offset + i
            local item = list.items[idx]
            if item then
                row.index, row.item = idx, item
                row.sel:SetShown(list.selected == idx)
                row.sel.bar:SetShown(list.selected == idx)
                opts.fillRow(row, item, idx)
                row:Show()
            else
                row.index, row.item = nil, nil
                row:Hide()
            end
        end
        if list.empty then list.empty:SetShown(#list.items == 0) end
    end
    list.Render = Render

    for i = 1, visible do
        local row = CreateFrame("Button", nil, list)
        row:SetSize(opts.width - 14, rh - 2)
        row:SetPoint("TOPLEFT", 4, -3 - (i - 1) * rh)
        row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        row.sel = T.Surface(row, C.accentWash, "BACKGROUND", -6)
        row.sel.bar = row:CreateTexture(nil, "ARTWORK")
        row.sel.bar:SetPoint("TOPLEFT", 0, -6)
        row.sel.bar:SetPoint("BOTTOMLEFT", 0, 6)
        row.sel.bar:SetWidth(2)
        row.sel.bar:SetColorTexture(unpack(C.accent))
        row.sel:Hide()
        row.sel.bar:Hide()
        local hl = row:CreateTexture(nil, "HIGHLIGHT")
        hl:SetAllPoints()
        hl:SetColorTexture(1, 1, 1, 0.04)
        if i > 1 then
            local sep = row:CreateTexture(nil, "BORDER")
            sep:SetColorTexture(C.line[1], C.line[2], C.line[3], 0.05)
            sep:SetHeight(1)
            sep:SetPoint("TOPLEFT", 8, 1)
            sep:SetPoint("TOPRIGHT", -8, 1)
        end
        opts.makeRow(row)
        row:SetScript("OnClick", function(self, button)
            if not self.index then return end
            if button ~= "RightButton" then
                list.selected = self.index
                Render()
            end
            if opts.onClick then opts.onClick(self.item, self.index, button) end
        end)
        if opts.onEnter then
            row:SetScript("OnEnter", function(self) if self.item then opts.onEnter(self, self.item) end end)
            row:SetScript("OnLeave", function() GameTooltip:Hide() end)
        end
        list.rows[i] = row
    end

    bar:SetScript("OnValueChanged", function(_, v)
        list.offset = math.floor(v + 0.5)
        Render()
    end)
    list:EnableMouseWheel(true)
    list:SetScript("OnMouseWheel", function(_, delta)
        local max = math.max(0, #list.items - visible)
        bar:SetValue(U.Clamp(list.offset - delta * 3, 0, max))
    end)

    if opts.empty then
        list.empty = T.Text(list, opts.empty, "small", C.text2)
        list.empty:SetPoint("TOP", 0, -40)
        list.empty:SetWidth(opts.width - 40)
        list.empty:SetJustifyH("CENTER")
        list.empty:SetWordWrap(true)
    end

    function list:SetItems(items, keep)
        self.items = items or {}
        local max = math.max(0, #self.items - visible)
        bar:SetMinMaxValues(0, max)
        bar:SetShown(max > 0)
        if not keep then
            self.selected = nil
            self.offset = 0
            bar:SetValue(0)
        else
            self.offset = math.min(self.offset, max)
        end
        Render()
    end
    function list:SetEmptyText(text) if self.empty then self.empty:SetText(text) end end
    function list:Select(i)
        self.selected = i
        if i and (i <= self.offset or i > self.offset + visible) then
            bar:SetValue(U.Clamp(i - 1, 0, math.max(0, #self.items - visible)))
        end
        Render()
    end
    -- Keyboard / controller: move the selection.
    function list:Move(delta)
        if #self.items == 0 then return end
        local i = U.Clamp((self.selected or 0) + delta, 1, #self.items)
        self:Select(i)
        if opts.onClick then opts.onClick(self.items[i], i, "LeftButton") end
    end
    return list
end

-- A row of toggle buttons (segmented control): K.Segments(parent, keys, labels, get, set)
function K.Segments(parent, keys, labels, get, set, w)
    local f = CreateFrame("Frame", nil, parent)
    f.buttons = {}
    local bw = w or 90
    f:SetSize(bw * #keys, 24)
    f.bg = T.Surface(f, C.field)
    T.Outline(f, C.fieldEdge)
    for i, k in ipairs(keys) do
        local b = CreateFrame("Button", nil, f)
        b:SetSize(bw - 4, 18)
        b:SetPoint("LEFT", (i - 1) * bw + 2, 0)
        b.bg = T.Surface(b, C.field)
        b.text = T.Text(b, labels[k] or k, "small")
        b.text:SetPoint("LEFT", 2, 0)
        b.text:SetPoint("RIGHT", -2, 0)
        b.text:SetJustifyH("CENTER")
        b.text:SetWordWrap(false)
        b:SetScript("OnClick", function()
            set(k)
            f:Refresh()
        end)
        f.buttons[k] = b
    end
    function f:Refresh()
        local cur = get()
        for k, b in pairs(self.buttons) do
            local on = k == cur
            b.bg:Paint(on and C.raisedHi or { 0, 0, 0, 0 })
            local c = on and C.text or C.text2
            b.text:SetTextColor(c[1], c[2], c[3])
        end
    end
    f:Refresh()
    return f
end

-- kind: "primary" for the one main action of a view, else secondary (default),
-- "ghost" or "danger". b:SetKind(kind) later.
function K.Button(parent, text, w, h, onClick, tip, kind)
    local b = T.FlatButton(parent, text, w or 110, h or 24, kind)
    T.Disabler(b, { b })
    b.disabled = false
    if onClick then
        b:SetScript("OnClick", function(self, ...)
            if self.disabled then return end
            onClick(self, ...)
        end)
    end
    if tip then T.Tooltip(b, text, tip) end
    return b
end

-- Difficulty colors as hex, for "red/orange/yellow/green/grey".
K.DIFF_HEX = HME.SkillModel.HEX

function K.ConfHex(label)
    return label == "High" and "4fd68c" or (label == "Medium" and "f2c452" or "f7a845")
end
