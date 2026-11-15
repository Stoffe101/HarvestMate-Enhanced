-- Draws HME's frames from the test client (tests/support/wow.lua) as HTML: the
-- addon's real layout code, anchors, colours and text, in a browser, so a
-- person can look at the interface without the game. Loaded only by
-- tools/ui_preview.py; the tests never load it.
--
-- These are renders of the layout in a stand-in client, not screenshots of the
-- game: fonts are stand-ins (the game's are not readable), game textures are
-- placeholders except spell icons (fetched by the browser from a public icon
-- CDN), and text sizes are estimates.

local R = {}
RENDER = R

---------------------------------------------------------------------------
-- 1. Make the test client remember what drawing needs (preview runs only)
---------------------------------------------------------------------------
local Methods
do
    local index = getmetatable(UIParent).__index
    for i = 1, 20 do
        local name, value = debug.getupvalue(index, i)
        if name == "Methods" then Methods = value break end
        if not name then break end
    end
    assert(Methods, "render.lua: could not find the test client's Methods")
end

local FONT = {   -- template = { size, r, g, b }
    GameFontNormal = { 12, 1, 0.82, 0 }, GameFontHighlight = { 12, 1, 1, 1 }, GameFontDisable = { 12, 0.5, 0.5, 0.5 },
    GameFontNormalSmall = { 10, 1, 0.82, 0 }, GameFontHighlightSmall = { 10, 1, 1, 1 }, GameFontDisableSmall = { 10, 0.5, 0.5, 0.5 },
    GameFontNormalLarge = { 16, 1, 0.82, 0 }, GameFontHighlightLarge = { 16, 1, 1, 1 }, GameFontNormalHuge = { 20, 1, 0.82, 0 },
    GameFontNormalMed3 = { 14, 1, 0.82, 0 }, GameFontHighlightMedium = { 14, 1, 1, 1 }, GameFontNormalMed1 = { 13, 1, 0.82, 0 },
    NumberFontNormal = { 12, 1, 1, 1 }, GameFontNormalLeft = { 12, 1, 0.82, 0 }, GameFontHighlightLeft = { 12, 1, 1, 1 },
    SystemFont_Shadow_Med1 = { 12, 1, 1, 1 }, GameFontWhite = { 12, 1, 1, 1 }, GameFontGreen = { 12, 0.1, 1, 0.1 },
    GameFontRed = { 12, 1, 0.1, 0.1 }, GameFontNormalTiny = { 9, 1, 0.82, 0 }, GameFontHighlightExtraSmall = { 9, 1, 1, 1 },
}
for name in pairs(FONT) do _G[name] = _G[name] or { __fontName = name } end
for name, v in pairs(FONT) do if type(_G[name]) == "table" then _G[name].__fontName = name end end

local createTexture, createFontString = Methods.CreateTexture, Methods.CreateFontString
function Methods:CreateTexture(_, layer, _, sub)
    local t = createTexture(self)
    t.__layer, t.__sub = layer or "ARTWORK", sub or 0
    return t
end
function Methods:CreateFontString(_, layer, template)
    local fs = createFontString(self)
    fs.__layer, fs.__template = layer or "OVERLAY", template or "GameFontNormal"
    return fs
end
local setSize, setWidth, setHeight = Methods.SetSize, Methods.SetWidth, Methods.SetHeight
function Methods:SetSize(w, h) self.__wset, self.__hset = true, true return setSize(self, w, h) end
function Methods:SetWidth(w) self.__wset = true return setWidth(self, w) end
function Methods:SetHeight(h) self.__hset = true return setHeight(self, h) end
function Methods:SetAllPoints(rel) self.__all = rel or true end
local clearAllPoints = Methods.ClearAllPoints
function Methods:ClearAllPoints() self.__all = nil return clearAllPoints(self) end
function Methods:SetFrameLevel(n) self.__level = n end
function Methods:SetTextColor(r, g, b, a) self.__tc = { r, g, b, a or 1 } end
function Methods:SetJustifyH(j) self.__jh = j end
function Methods:SetJustifyV(j) self.__jv = j end
function Methods:SetWordWrap(w) self.__wrap = w end
function Methods:SetSpacing(n) self.__spacing = n end
function Methods:SetFont(file, size) self.__ffile, self.__fsize = file, size return true end
function Methods:SetFontObject(o)
    if type(o) == "table" then self.__template = rawget(o, "__fontName") or rawget(o, "__name") or self.__template end
    self.__ffile, self.__fsize = nil, nil
end
-- Font objects (Theme makes one per type role).
function CreateFont(name)
    local fo = NewObj("Font", name)
    fo.__fontName = name
    return fo
end
function Methods:SetTexture(path) self.__file = path; if path then self.__solid = nil end end
function Methods:SetAtlas(atlas) self.__atlas = atlas end
function Methods:SetColorTexture(r, g, b, a) self.__solid = { r, g, b, a or 1 }; self.__file = nil; self.__color = { r, g, b, a } end
function Methods:SetVertexColor(r, g, b, a) self.__tint = { r, g, b, a or 1 }; self.__color = { r, g, b, a } end
function Methods:SetGradient(orient, c1, c2) self.__grad = { orient, c1, c2 } end
function Methods:SetDesaturated(d) self.__desat = d end
function Methods:SetScrollChild(c) self.__scrollChild = c; c.__scrollParent = self end
function Methods:SetVerticalScroll(v) self.__vscroll = v end
function Methods:SetMinMaxValues(a, b) self.__min, self.__max = a, b end
function Methods:SetThumbTexture(t) self.__thumb = t; t.__thumbOf = self end
function Methods:SetOrientation(o) self.__orient = o end
function Methods:SetScale(s) self.__scale = s end
function Methods:SetFontString(fs) self.__fs = fs end
local setText = Methods.SetText
function Methods:SetText(t)
    setText(self, t)
    if self.__fs then self.__fs.__text = self.__text end
end
function Methods:SetStatusBarColor(r, g, b, a) self.__barColor = { r, g, b, a or 1 } end
CreateColor = CreateColor or function(r, g, b, a) return { r = r, g = g, b = b, a = a or 1, GetRGBA = function(c) return c.r, c.g, c.b, c.a end } end

-- Text measures close to the game's, so layouts that size themselves work.
-- Returns size, { size, r, g, b }, weight (nil: the game's font).
local function Weight(file)
    if type(file) ~= "string" then return nil end
    local f = file:lower()
    if f:find("inter%-bold") then return 700 end
    if f:find("inter%-semibold") then return 600 end
    if f:find("inter") then return 400 end
    return nil
end
local function FontOf(fs)
    local tmpl = fs.__template or "GameFontNormal"
    local fo = type(tmpl) == "string" and _G[tmpl]
    if type(fo) == "table" and rawget(fo, "__kind") == "Font" then
        local tc = rawget(fo, "__tc") or { 1, 1, 1, 1 }
        local size = fs.__fsize or rawget(fo, "__fsize") or 12
        return size, { size, tc[1], tc[2], tc[3] }, Weight(fs.__ffile or rawget(fo, "__ffile"))
    end
    local f = FONT[tmpl] or FONT.GameFontNormal
    return fs.__fsize or f[1], f, Weight(fs.__ffile)
end
local function Plain(s)
    return (tostring(s or ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|T.-|t", "WW"):gsub("|n", "\n"))
end
local CHAR_W = 0.58   -- a little wider than Inter's average: room the game will need
function R.TextWidth(fs, text)
    local size = FontOf(fs)
    local widest = 0
    for line in (Plain(text or fs.__text) .. "\n"):gmatch("([^\n]*)\n") do widest = math.max(widest, #line) end
    return widest * size * CHAR_W
end
function R.TextHeight(fs, width)
    local size = FontOf(fs)
    local lines = 0
    local perLine = width and width > 0 and math.max(1, math.floor(width / (size * CHAR_W))) or nil
    for line in (Plain(fs.__text) .. "\n"):gmatch("([^\n]*)\n") do
        if perLine and fs.__wrap ~= false then lines = lines + math.max(1, math.ceil(#line / perLine)) else lines = lines + 1 end
    end
    return math.max(1, lines) * (size + 2 + (fs.__spacing or 0))
end
function Methods:GetStringWidth() return R.TextWidth(self) end
function Methods:GetStringHeight() return R.TextHeight(self, self.__wset and self.__w or nil) end
function Methods:GetUnboundedStringWidth() return R.TextWidth(self) end
function Methods:GetLineHeight() return (FontOf(self)) + 2 end

---------------------------------------------------------------------------
-- 2. Where everything is: anchors to rectangles (game units, y up)
---------------------------------------------------------------------------
R.SCREEN_W, R.SCREEN_H = 1600, 900
local rects, busy

local function Parent(o) return rawget(o, "__parent") end
local function Rel(o, rel)
    if type(rel) == "string" then return _G[rel] end
    if type(rel) == "table" then return rel end
    return Parent(o)
end

local function At(rect, name)
    local x = name:find("LEFT") and rect.l or (name:find("RIGHT") and rect.r or (rect.l + rect.r) / 2)
    local y = name:find("TOP") and rect.t or (name:find("BOTTOM") and rect.b or (rect.t + rect.b) / 2)
    return x, y
end

local RectOf
-- A frame's scale times its parents': sizes and offsets are in its own units.
local function EffScale(o)
    local s = 1
    local p = o
    while p and p ~= UIParent do
        s = s * (rawget(p, "__scale") or 1)
        p = rawget(p, "__parent")
    end
    return s
end
R.EffScale = EffScale
local function Size(o)
    local kind = rawget(o, "__kind")
    local w = rawget(o, "__wset") and o.__w or nil
    local h = rawget(o, "__hset") and o.__h or nil
    if kind == "FontString" then
        if not w then w = R.TextWidth(o) end
        if not h then h = R.TextHeight(o, rawget(o, "__wset") and o.__w or nil) end
    end
    local e = EffScale(o)
    return (w or 0) * e, (h or 0) * e
end

RectOf = function(o)
    if o == UIParent then return { l = 0, b = 0, r = R.SCREEN_W, t = R.SCREEN_H } end
    local cached = rects[o]
    if cached ~= nil then return cached or nil end
    if busy[o] then return nil end
    busy[o] = true
    local pts = {}
    local all = rawget(o, "__all")
    if all then
        local rel = all == true and Parent(o) or Rel(o, all)
        pts = { { "TOPLEFT", rel, "TOPLEFT", 0, 0 }, { "BOTTOMRIGHT", rel, "BOTTOMRIGHT", 0, 0 } }
    end
    for _, p in ipairs(rawget(o, "__points") or {}) do
        local point, rel, rp, x, y = p[1], nil, nil, 0, 0
        if type(p[2]) == "number" then
            x, y = p[2], p[3] or 0
        elseif p[2] ~= nil then
            rel, rp = Rel(o, p[2]), type(p[3]) == "string" and p[3] or point
            if type(p[3]) == "string" then x, y = p[4] or 0, p[5] or 0 else x, y = p[3] or 0, p[4] or 0 end
        end
        pts[#pts + 1] = { point, rel or Parent(o), rp or point, x, y }
    end
    -- A scroll child without anchors sits at its scroll frame's top left, scrolled.
    local sp = rawget(o, "__scrollParent")
    if #pts == 0 and sp then pts = { { "TOPLEFT", sp, "TOPLEFT", 0, sp.__vscroll or 0 } } end
    -- A slider's thumb sits along its track by value.
    local slider = rawget(o, "__thumbOf")
    local rect
    if #pts == 0 and slider then
        local sr = RectOf(slider)
        if sr then
            local w, h = Size(o)
            local lo, hi, v = slider.__min or 0, slider.__max or 0, slider.__value or 0
            local f = hi > lo and (v - lo) / (hi - lo) or 0
            if slider.__orient == "VERTICAL" then
                local y = sr.t - f * (sr.t - sr.b - h)
                rect = { l = (sr.l + sr.r - w) / 2, r = (sr.l + sr.r + w) / 2, t = y, b = y - h }
            else
                local x = sr.l + f * (sr.r - sr.l - w)
                rect = { l = x, r = x + w, t = (sr.t + sr.b + h) / 2, b = (sr.t + sr.b - h) / 2 }
            end
        end
    elseif #pts > 0 then
        local l, r, t, b, cx, cy
        for _, p in ipairs(pts) do
            local rr = p[2] and RectOf(p[2])
            if rr then
                local ax, ay = At(rr, p[3])
                local e = EffScale(o)
                ax, ay = ax + p[4] * e, ay + p[5] * e
                local name = p[1]
                if name:find("LEFT") then l = ax elseif name:find("RIGHT") then r = ax else cx = ax end
                if name:find("TOP") then t = ay elseif name:find("BOTTOM") then b = ay else cy = ay end
            end
        end
        if (l or r or cx) and (t or b or cy) then
            -- (offsets were added in the frame's own units)
            local w, h = Size(o)
            if l and r then w = r - l end
            if t and b then h = t - b end
            if not l then l = r and (r - w) or (cx - w / 2) end
            if not r then r = l + w end
            if not t then t = b and (b + h) or (cy + h / 2) end
            if not b then b = t - h end
            rect = { l = l, r = r, t = t, b = b }
        end
    end
    busy[o] = nil
    rects[o] = rect or false
    return rect
end
R.RectOf = function(o) rects, busy = rects or {}, busy or {} return RectOf(o) end

---------------------------------------------------------------------------
-- 3. HTML
---------------------------------------------------------------------------
local function css(c, alpha)
    if not c then return "transparent" end
    local a = (c[4] or 1) * (alpha or 1)
    return ("rgba(%d,%d,%d,%.3f)"):format((c[1] or 0) * 255, (c[2] or 0) * 255, (c[3] or 0) * 255, a)
end
local function esc(s) return (tostring(s):gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;")) end

R.ICON_CDN = "https://wow.zamimg.com/images/wow/icons/large/"
R.MEDIA = {}   -- addon texture path (lower case) -> png file, filled by the driver
R.WARN = {}   -- warnings found while drawing (missing addon art), per render
local function ImageFor(path)
    if type(path) ~= "string" then return nil end
    local icon = path:match("[Ii]nterface[\\/][Ii]cons[\\/]([%w_%-]+)")
    if icon then return R.ICON_CDN .. icon:lower() .. ".jpg" end
    local key = path:lower():gsub("\\", "/"):gsub("%.tga$", ""):gsub("%.blp$", "")
    if key:find("^interface/addons/harvestmateenhanced/") and not R.MEDIA[key] and not key:find("/fonts/") then
        R.WARN["missing art: " .. key:gsub("^interface/addons/harvestmateenhanced/", "")] = true
    end
    return R.MEDIA[key]
end

-- WoW text markup to HTML: colours, inline textures, line breaks.
local function Markup(text, size)
    text = tostring(text or "")
    local out, depth = {}, 0
    local i = 1
    while i <= #text do
        local c = text:sub(i, i)
        if c == "|" then
            local n = text:sub(i + 1, i + 1)
            if n == "c" and text:sub(i + 2, i + 9):match("^%x+$") then
                local hex = text:sub(i + 4, i + 9)
                out[#out + 1] = ('<span style="color:#%s">'):format(hex)
                depth = depth + 1
                i = i + 10
            elseif n == "r" then
                if depth > 0 then out[#out + 1] = "</span>" depth = depth - 1 end
                i = i + 2
            elseif n == "T" then
                local close = text:find("|t", i, true)
                local spec = text:sub(i + 2, (close or #text) - 1)
                local path = spec:match("^([^:]+)")
                local img = ImageFor(path)
                local px = size
                if img then
                    out[#out + 1] = ('<img src="%s" style="width:%dpx;height:%dpx;vertical-align:-2px">'):format(img, px, px)
                else
                    out[#out + 1] = ('<span class="ph" style="width:%dpx;height:%dpx"></span>'):format(px, px)
                end
                i = (close or #text) + 2
            elseif n == "n" then
                out[#out + 1] = "<br>"
                i = i + 2
            else
                out[#out + 1] = "|"
                i = i + 1
            end
        elseif c == "\n" then
            out[#out + 1] = "<br>"
            i = i + 1
        else
            local j = text:find("[|\n]", i) or (#text + 1)
            out[#out + 1] = esc(text:sub(i, j - 1))
            i = j
        end
    end
    for _ = 1, depth do out[#out + 1] = "</span>" end
    return table.concat(out)
end

local LAYER = { BACKGROUND = 1, BORDER = 2, ARTWORK = 3, OVERLAY = 4, HIGHLIGHT = 9 }

local function Shown(o)
    if not rawget(o, "__shown") then return false end
    return true
end

local function Box(rect, origin)
    return ("left:%.1fpx;top:%.1fpx;width:%.1fpx;height:%.1fpx"):format(rect.l - origin.l, origin.t - rect.t,
        math.max(0, rect.r - rect.l), math.max(0, rect.t - rect.b))
end

local function Region(o, origin, out, alpha)
    local rect = RectOf(o)
    if not rect then return end
    local kind = rawget(o, "__kind")
    local a = (rawget(o, "__alpha") or 1) * alpha
    if kind == "FontString" then
        local text = rawget(o, "__text") or ""
        if text == "" then return end
        local size, f, weight = FontOf(o)
        size = size * EffScale(o)
        local tc = rawget(o, "__tc") or { f[2], f[3], f[4], 1 }
        local lh = ("line-height:%dpx;"):format(size + 3 + (rawget(o, "__spacing") or 0))
        local family = lh .. (weight and ("font-family:Inter;font-weight:" .. weight .. ";text-shadow:0 1px 0 rgba(0,0,0,.5)") or "font-family:'Friz Quadrata TT',Georgia,serif")
        local jh = (rawget(o, "__jh") or "CENTER"):lower()
        if jh == "middle" then jh = "center" end
        -- Text without a set height grows from its top in the game.
        local jv = rawget(o, "__jv") or (rawget(o, "__hset") and "MIDDLE" or "TOP")
        local align = jv == "TOP" and "flex-start" or (jv == "BOTTOM" and "flex-end" or "center")
        -- The game keeps text without a set width on one line.
        local wrap = (rawget(o, "__wrap") == false or not rawget(o, "__wset")) and "nowrap" or "normal"
        local clip = (wrap == "nowrap" and rawget(o, "__wset")) and ";overflow:hidden" or ""
        out[#out + 1] = ('<div class="fs%s" style="%s;font-size:%.1fpx;color:%s;justify-content:%s;align-items:%s;text-align:%s;white-space:%s;opacity:%.2f;%s%s"><span style="%s"><span class="t">%s</span></span></div>')
            :format(rawget(o, "__wset") and "" or " auto", Box(rect, origin), size, css(tc), jh == "left" and "flex-start" or (jh == "right" and "flex-end" or "center"),
                align, jh, wrap, a, family, clip, clip ~= "" and "overflow:hidden;text-overflow:ellipsis" or "", Markup(text, size))
    elseif kind == "Texture" or kind == "Line" then
        if rawget(o, "__layer") == "HIGHLIGHT" then return end
        local style
        local grad = rawget(o, "__grad")
        local file = rawget(o, "__file")
        if grad and grad[2] and grad[3] then
            local function cc(c) return css({ c.r, c.g, c.b, c.a }) end
            style = ("background:linear-gradient(%s,%s,%s)"):format(grad[1] == "HORIZONTAL" and "90deg" or "0deg", cc(grad[2]), cc(grad[3]))
        elseif rawget(o, "__solid") then
            style = "background:" .. css(rawget(o, "__solid"))
        elseif file and tostring(file):find("Media[\\/]UI[\\/]") then
            local shape = tostring(file):match("([%w]+)$")
            local c = css(rawget(o, "__tint") or { 1, 1, 1, 1 })
            if shape == "Round" then
                style = "background:" .. c .. ";border-radius:6px"
            elseif shape == "RoundEdge" then
                style = "border:1px solid " .. c .. ";border-radius:6px;box-sizing:border-box"
            elseif shape == "Track" or shape == "Circle" then
                style = "background:" .. c .. ";border-radius:999px"
            elseif shape == "Chevron" then
                out[#out + 1] = ('<svg class="r" viewBox="0 0 16 16" style="%s;opacity:%.2f"><polyline points="4,6 8,10 12,6" fill="none" stroke="%s" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"/></svg>')
                    :format(Box(rect, origin), a, c)
                return
            elseif shape == "Shadow" then
                local t = rawget(o, "__tint") or { 0, 0, 0, 0.5 }
                out[#out + 1] = ('<div class="r" style="%s"><div style="position:absolute;left:16px;top:16px;right:16px;bottom:16px;border-radius:8px;box-shadow:0 10px 30px rgba(0,0,0,%.2f)"></div></div>')
                    :format(Box(rect, origin), (t[4] or 0.5) * 1.3)
                return
            else
                -- Other UI art (contour lines, medallion, pip, compass, tick, glow): the
                -- white shape as a mask, in its tint.
                local img = ImageFor(file)
                if img then
                    style = ("background:%s;-webkit-mask:url(%s) center/100%% 100%% no-repeat;mask:url(%s) center/100%% 100%% no-repeat")
                        :format(c, img, img)
                else
                    style = "background:" .. c
                end
            end
        elseif file then
            local img = ImageFor(file)
            local tint = rawget(o, "__tint")
            if img then
                out[#out + 1] = ('<img class="r" src="%s" style="%s;opacity:%.2f;%s">'):format(img, Box(rect, origin), a,
                    rawget(o, "__desat") and "filter:grayscale(1)" or "")
                return
            end
            style = ("background:%s;border-radius:2px"):format(css(tint or { 0.6, 0.6, 0.6, 0.35 }))
        elseif rawget(o, "__atlas") then
            style = "background:rgba(160,160,160,.25)"
        else
            return
        end
        out[#out + 1] = ('<div class="r" style="%s;%s;opacity:%.2f"></div>'):format(Box(rect, origin), style, a)
    end
end

local function Frame(o, origin, out, alpha, depth)
    if depth > 40 or not Shown(o) then return end
    local kind = rawget(o, "__kind")
    if kind == "GameTooltip" then return end
    local rect = RectOf(o)
    local a = (rawget(o, "__alpha") or 1) * alpha
    local regions, frames = {}, {}
    for _, c in ipairs(rawget(o, "__children") or {}) do
        local ck = rawget(c, "__kind")
        if ck == "Texture" or ck == "FontString" or ck == "Line" then regions[#regions + 1] = c else frames[#frames + 1] = c end
    end
    local inner = rect or origin
    if rect and o ~= UIParent then
        local clip = kind == "ScrollFrame" and ";overflow:hidden" or ""
        local cls = (kind == "Button" and rawget(o, "__fs")) and "f btn" or "f"
        local offscreen = (rect.l < -1 or rect.b < -1 or rect.r > R.SCREEN_W + 1 or rect.t > R.SCREEN_H + 1) and o ~= UIParent
            and Parent(o) == UIParent
        if offscreen then R.WARN["off screen: a top-level frame reaches past the screen edge"] = true end
        -- Top-level frames are tagged: text in different ones may overlap (one
        -- floats above the other), text in the same one may not.
        -- Panels (top-level frames that draw a surface) are also marked: text must stay inside them.
        local top = depth == 0 and (' data-top="%s"%s'):format(tostring(rawget(o, "__name") or o):gsub('"', ""),
            rawget(o, "bg") and ' data-panel="1"' or "") or ""
        out[#out + 1] = ('<div class="%s"%s style="%s%s">'):format(cls, top, Box(rect, origin), clip)
    end
    table.sort(regions, function(x, y)
        local lx, ly = LAYER[rawget(x, "__layer") or "ARTWORK"] or 3, LAYER[rawget(y, "__layer") or "ARTWORK"] or 3
        if lx ~= ly then return lx < ly end
        return (rawget(x, "__sub") or 0) < (rawget(y, "__sub") or 0)
    end)
    local below, above = {}, {}
    for _, c in ipairs(frames) do
        if rawget(c, "__level") and c.__level < 1 then below[#below + 1] = c else above[#above + 1] = c end
    end
    for _, c in ipairs(below) do Frame(c, inner, out, a, depth + 1) end
    -- An edit box shows its text.
    if kind == "EditBox" and rect and (rawget(o, "__text") or "") ~= "" then
        out[#out + 1] = ('<div class="fs" style="left:8px;top:0;right:8px;height:100%%;font:400 11px Inter;color:#edf0f2;align-items:center;white-space:nowrap;overflow:hidden"><span>%s</span></div>')
            :format(esc(o.__text))
    end
    for _, r in ipairs(regions) do if Shown(r) then Region(r, inner, out, a) end end
    for _, c in ipairs(above) do Frame(c, inner, out, a, depth + 1) end
    if rect and o ~= UIParent then out[#out + 1] = "</div>" end
end

R.STYLE = [[
@font-face{font-family:Inter;font-weight:400;src:url(media/fonts/Inter-Regular.ttf)}
@font-face{font-family:Inter;font-weight:600;src:url(media/fonts/Inter-SemiBold.ttf)}
@font-face{font-family:Inter;font-weight:700;src:url(media/fonts/Inter-Bold.ttf)}
body{margin:0;background:#1b2027;font-family:"Segoe UI",Arial,sans-serif}
.screen{position:relative;overflow:hidden;background:radial-gradient(ellipse at 30% 20%,#3d4a3a 0%,#22291f 45%,#141812 100%)}
.f,.r,.fs{position:absolute}
.fs{display:flex;line-height:1.2;text-shadow:0 1px 1px rgba(0,0,0,.9);overflow:visible}
.fs>span{display:block;width:100%}
.ph{display:inline-block;background:rgba(200,200,200,.35);border-radius:2px;vertical-align:-2px}
.cap{color:#9aa;font:12px Segoe UI;padding:6px 10px;background:#0e1114}
.bad{outline:1px solid #ff3b3b;background:rgba(255,59,59,.18)}
.warn{outline:1px dashed rgba(255,190,60,.7)}
body.clean .bad,body.clean .warn{outline:none;background:none}
body.clean .cap,body.clean #report{display:none}
#report{font:12px Segoe UI;color:#ddd;padding:8px 12px;background:#0e1114}
#report li{margin:2px 0}
]]

-- In the page: once the fonts are in, every piece of text is measured as drawn;
-- pairs that overlap are outlined in red and listed under the picture.
R.CHECK = [=[
if(location.search.indexOf('clean')>=0)document.body.classList.add('clean');
document.fonts.ready.then(function(){
  var screen=document.querySelector('.screen').getBoundingClientRect();
  function visible(r){return r.width>0&&r.height>0&&r.right>screen.left&&r.left<screen.right&&r.bottom>screen.top&&r.top<screen.bottom;}
  function clipOf(el){var p=el.parentElement;while(p){var cs=getComputedStyle(p);if(cs.overflow==='hidden'&&p.classList.contains('f'))return p.getBoundingClientRect();p=p.parentElement;}return null;}
  var items=[];
  document.querySelectorAll('.fs .t').forEach(function(t){
    var r=t.getBoundingClientRect(); var txt=t.textContent.trim(); if(!txt||!visible(r))return;
    var box=t.parentElement; if(getComputedStyle(box).overflow==='hidden'){var q=box.getBoundingClientRect(); r={left:r.left,top:r.top,right:Math.min(r.right,q.right),bottom:r.bottom};}
    var c=clipOf(t); if(c){var l=Math.max(r.left,c.left),tp=Math.max(r.top,c.top),rr=Math.min(r.right,c.right),b=Math.min(r.bottom,c.bottom); if(rr-l<2||b-tp<2)return; r={left:l,top:tp,right:rr,bottom:b};}
    var tp=t.closest('[data-top]'); items.push({el:t,r:r,txt:txt,top:tp?tp.getAttribute('data-top'):''});
  });
  var bad=[];
  for(var i=0;i<items.length;i++)for(var j=i+1;j<items.length;j++){
    if(items[i].top!==items[j].top)continue;
    var a=items[i].r,b=items[j].r; var w=Math.min(a.right,b.right)-Math.max(a.left,b.left), h=Math.min(a.bottom,b.bottom)-Math.max(a.top,b.top);
    if(w>2&&h>2){bad.push([items[i],items[j]]);items[i].el.classList.add('bad');items[j].el.classList.add('bad');}
  }
  // Cut: text wider than its box. Tight: within 8% of its box, which the
  // game's own text measure can tip over (the first real-client screenshots
  // showed cuts the previews did not).
  var cut=[], tight=[], tiny=[], dim=[], narrow=[];
  document.querySelectorAll('.fs:not(.auto)>span').forEach(function(s){
    var r=s.getBoundingClientRect(); if(!visible(r))return; var t=s.querySelector('.t'); if(!t)return;
    var txt=s.textContent.trim(); if(!txt)return;
    var nat=t.getBoundingClientRect().width;
    if(s.scrollWidth>s.clientWidth+1){cut.push(txt.slice(0,50)); s.parentElement.classList.add('bad');}
    else if(getComputedStyle(s.parentElement).whiteSpace==='nowrap' && nat>s.clientWidth*0.92 && s.clientWidth>0){tight.push(txt.slice(0,50)); s.parentElement.classList.add('warn');}
  });
  document.querySelectorAll('.fs .t').forEach(function(t){
    var r=t.getBoundingClientRect(); if(!visible(r)||!t.textContent.trim())return;
    var box=t.closest('.fs'); var cs=getComputedStyle(box); var px=parseFloat(cs.fontSize)*zoom();
    if(px<10.5) tiny.push(t.textContent.trim().slice(0,40)+' ('+px.toFixed(1)+'px)');
    var m=cs.color.match(/[\d.]+/g); if(m){var L=(0.2126*m[0]+0.7152*m[1]+0.0722*m[2])/255; var a=m[3]!==undefined?+m[3]:1; var op=parseFloat(cs.opacity); if(L*a*op<0.30&&!t.closest('.btn')) dim.push(t.textContent.trim().slice(0,40));}
  });
  document.querySelectorAll('.btn').forEach(function(b){
    var r=b.getBoundingClientRect(); if(!visible(r))return;
    var t=b.querySelector('.fs .t'); var txt=t?t.textContent.trim():'';
    if(r.height*1<18*zoom()&&txt) narrow.push(txt.slice(0,30)+' (short: '+Math.round(r.height/zoom())+')');
    if(t&&txt){var tw=t.getBoundingClientRect().width; if(tw>r.width-8) narrow.push(txt.slice(0,30)+' (label fills the button)');}
  });
  function zoom(){return parseFloat(getComputedStyle(document.body).zoom)||1;}
  // Outside: text that runs past the panel it belongs to (its top-level
  // frame), whether or not it overlaps other text. A real-client screenshot
  // showed a HUD title running over the world beside the HUD.
  var outside=[];
  document.querySelectorAll('.fs .t').forEach(function(t){
    var txt=t.textContent.trim(); if(!txt)return;
    var top=t.closest('[data-top]'); if(!top||!top.hasAttribute('data-panel'))return;
    var r=t.getBoundingClientRect(), q=top.getBoundingClientRect();
    if(q.width<4||q.height<4||!visible(r))return;
    // What a clipping ancestor (a scroll area, a cut text box) hides is not outside.
    var a=t.parentElement, hidden=false;
    while(a&&a!==top){ if(getComputedStyle(a).overflow==='hidden'){var b=a.getBoundingClientRect();
        r={left:Math.max(r.left,b.left),top:Math.max(r.top,b.top),right:Math.min(r.right,b.right),bottom:Math.min(r.bottom,b.bottom)};
        if(r.right-r.left<1||r.bottom-r.top<1){hidden=true;break;}} a=a.parentElement; }
    if(hidden)return;
    if(r.right>q.right+1.5||r.left<q.left-1.5||r.bottom>q.bottom+1.5||r.top<q.top-1.5){outside.push(txt.slice(0,50)); t.classList.add('bad');}
  });
  var warn=JSON.parse(document.getElementById('lua-warn').textContent||'[]');
  var rep=document.getElementById('report');
  function list(name,a){return a.length?'<div><b>'+a.length+' '+name+'</b>: '+a.slice(0,12).join(' | ')+'</div>':'';}
  rep.innerHTML='<b>'+bad.length+' overlapping text pairs</b>, '+outside.length+' outside their panel, '+cut.length+' cut short, '+tight.length+' tight, '+narrow.length+' cramped buttons, '+tiny.length+' tiny, '+dim.length+' dim, '+warn.length+' other'
    +'<ol>'+bad.map(function(p){return '<li>'+p[0].txt.slice(0,60)+' &lt;&gt; '+p[1].txt.slice(0,60)+'</li>';}).join('')+'</ol>'
    +list('outside their panel',outside)+list('cut',cut)+list('tight (may cut in game)',tight)+list('cramped buttons',narrow)+list('tiny text',tiny)+list('dim text',dim)+list('other',warn);
  var res={overlap:bad.map(function(p){return [p[0].txt.slice(0,60),p[1].txt.slice(0,60)];}),outside:outside,cut:cut,tight:tight,narrow:narrow,tiny:tiny,dim:dim,other:warn};
  var pre=document.createElement('pre'); pre.id='result'; pre.style.display='none'; pre.textContent=JSON.stringify(res); document.body.appendChild(pre);
  document.title=document.title+' ['+bad.length+']';
});
]=]

-- One picture of the whole screen (or just around a frame with opts.around).
function R.Render(title, opts)
    opts = opts or {}
    rects, busy = {}, {}
    R.WARN = {}
    local origin = { l = 0, t = R.SCREEN_H, r = R.SCREEN_W, b = 0 }
    local out = {}
    for _, c in ipairs(rawget(UIParent, "__children") or {}) do Frame(c, origin, out, 1, 0) end
    local w, h, shift = R.SCREEN_W, R.SCREEN_H, ""
    if opts.around then
        local rr = RectOf(opts.around)
        if rr then
            local pad = opts.pad or 24
            w, h = (rr.r - rr.l) + pad * 2, (rr.t - rr.b) + pad * 2
            shift = ("transform:translate(%.1fpx,%.1fpx)"):format(-(rr.l - pad), -(R.SCREEN_H - rr.t - pad))
        end
    end
    local warn = {}
    for k in pairs(R.WARN) do warn[#warn + 1] = '"' .. k:gsub('"', "'") .. '"' end
    table.sort(warn)
    -- zoom: UI units to the screen's pixels (opts.zoom), so text shows at the size it would have.
    return ('<!doctype html><html><head><meta charset="utf-8"><title>%s</title><style>%s</style></head><body style="zoom:%.4f">'
        .. '<div class="cap">%s · a render of the layout in a stand-in client, not a game screenshot</div>'
        .. '<div class="screen" style="width:%dpx;height:%dpx"><div style="position:absolute;left:0;top:0;width:%dpx;height:%dpx;%s">%s</div></div>'
        .. '<div id="report">checking...</div><script id="lua-warn" type="application/json">[%s]</script><script>%s</script></body></html>')
        :format(esc(title), R.STYLE, opts.zoom or 1, esc(title), w, h, R.SCREEN_W, R.SCREEN_H, shift, table.concat(out, "\n"),
            table.concat(warn, ","), R.CHECK)
end

return R
