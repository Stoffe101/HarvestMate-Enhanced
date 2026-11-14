-- HarvestMate Enhanced: UI/Kit.lua
-- Widgets the pages share, in the Theme's look: labels, badges, skill bars,
-- icons, a virtual list (only the visible rows exist, so long lists cost
-- nothing), money text and profession colors.
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

-- A heading with a thin line under it.
function K.Heading(parent, text, x, y, w)
    local fs = T.Text(parent, text, "GameFontNormal", C.gold, 14)
    fs:SetPoint("TOPLEFT", x, y)
    local line = parent:CreateTexture(nil, "BORDER")
    line:SetColorTexture(unpack(C.line))
    line:SetHeight(1)
    line:SetPoint("TOPLEFT", x, y - 18)
    line:SetWidth(w or 300)
    return fs, line
end

-- A small colored pill: b:Set(text, hex)
function K.Badge(parent, w, h)
    local b = CreateFrame("Frame", nil, parent)
    b:SetSize(w or 90, h or 16)
    b.bg = T.Fill(b, { 0.2, 0.2, 0.2, 0.9 })
    b.text = T.Text(b, "", "GameFontHighlightSmall")
    b.text:SetPoint("CENTER")
    b.text:SetJustifyH("CENTER")
    function b:Set(text, hex)
        self.text:SetText(text or "")
        local r, g, bl = 0.3, 0.3, 0.3
        if hex then
            r, g, bl = tonumber(hex:sub(1, 2), 16) / 255, tonumber(hex:sub(3, 4), 16) / 255, tonumber(hex:sub(5, 6), 16) / 255
        end
        self.bg:SetColorTexture(r * 0.35, g * 0.35, bl * 0.35, 0.95)
        self.text:SetTextColor(math.min(1, r * 0.6 + 0.45), math.min(1, g * 0.6 + 0.45), math.min(1, bl * 0.6 + 0.45))
    end
    return b
end

-- Skill bar: bar:Set(skill, max, color, label). A thin marker shows the
-- next milestone when given (bar:Mark(skill)).
function K.Bar(parent, w, h)
    local bar = CreateFrame("Frame", nil, parent)
    bar:SetSize(w, h or 14)
    T.Fill(bar, C.field)
    T.Border(bar, C.fieldEdge)
    bar.fill = bar:CreateTexture(nil, "ARTWORK")
    bar.fill:SetPoint("TOPLEFT", 1, -1)
    bar.fill:SetPoint("BOTTOMLEFT", 1, 1)
    bar.cap = bar:CreateTexture(nil, "ARTWORK", nil, 1)
    bar.cap:SetPoint("TOPLEFT", 1, -1)
    bar.cap:SetPoint("BOTTOMLEFT", 1, 1)
    bar.cap:SetColorTexture(1, 1, 1, 0.07)
    bar.mark = bar:CreateTexture(nil, "OVERLAY")
    bar.mark:SetWidth(2)
    bar.mark:SetPoint("TOP", 0, 2)
    bar.mark:SetPoint("BOTTOM", 0, -2)
    bar.mark:SetColorTexture(1, 0.82, 0, 0.9)
    bar.mark:Hide()
    bar.text = T.Text(bar, "", "GameFontHighlightSmall")
    bar.text:SetPoint("CENTER")
    bar.text:SetJustifyH("CENTER")
    local inner = w - 2
    function bar:Set(value, max, color, label, top)
        top = top or 300
        local f = U.Clamp((value or 0) / top, 0, 1)
        self.fill:SetWidth(math.max(1, inner * f))
        local c = color or C.gold
        self.fill:SetColorTexture(c[1], c[2], c[3], 0.85)
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
    f.tex:SetAllPoints()
    f.tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    if texture then f.tex:SetTexture(texture) end
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
    T.Fill(list, C.field)
    T.Border(list, C.line)
    local rh = opts.rowHeight or 28
    local visible = math.floor((opts.height - 4) / rh)
    list.items, list.offset, list.rows, list.selected = {}, 0, {}, nil

    local bar = CreateFrame("Slider", nil, list)
    bar:SetOrientation("VERTICAL")
    bar:SetWidth(6)
    bar:SetPoint("TOPRIGHT", -2, -2)
    bar:SetPoint("BOTTOMRIGHT", -2, 2)
    T.Fill(bar, C.offTrack)
    local thumb = bar:CreateTexture(nil, "OVERLAY")
    thumb:SetSize(6, 30)
    thumb:SetColorTexture(unpack(C.btnEdge))
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
        row:SetSize(opts.width - 12, rh)
        row:SetPoint("TOPLEFT", 2, -2 - (i - 1) * rh)
        row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        row.sel = T.Fill(row, C.tabOn, "BACKGROUND", -6)
        row.sel:Hide()
        local hl = row:CreateTexture(nil, "HIGHLIGHT")
        hl:SetAllPoints()
        hl:SetColorTexture(1, 1, 1, 0.05)
        if i > 1 then
            local sep = row:CreateTexture(nil, "BORDER")
            sep:SetColorTexture(C.line[1], C.line[2], C.line[3], 0.6)
            sep:SetHeight(1)
            sep:SetPoint("TOPLEFT")
            sep:SetPoint("TOPRIGHT")
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
        list.empty = T.Text(list, opts.empty, "GameFontDisable")
        list.empty:SetPoint("TOPLEFT", 12, -12)
        list.empty:SetWidth(opts.width - 30)
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
    f:SetSize(bw * #keys, 22)
    for i, k in ipairs(keys) do
        local b = CreateFrame("Button", nil, f)
        b:SetSize(bw - 2, 22)
        b:SetPoint("LEFT", (i - 1) * bw, 0)
        b.bg = T.Fill(b, C.field)
        T.Border(b, C.fieldEdge)
        b.text = T.Text(b, labels[k] or k, "GameFontHighlightSmall")
        b.text:SetPoint("CENTER")
        b.text:SetJustifyH("CENTER")
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
            b.bg:SetColorTexture(unpack(on and C.tabOn or C.field))
            local c = on and C.gold or C.muted
            b.text:SetTextColor(c[1], c[2], c[3])
        end
    end
    f:Refresh()
    return f
end

function K.Button(parent, text, w, h, onClick, tip)
    local b = T.FlatButton(parent, text, w or 110, h or 22)
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
    return label == "High" and "48c75a" or (label == "Medium" and "ffe14d" or "ff8a3d")
end
