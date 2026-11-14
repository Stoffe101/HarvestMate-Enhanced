-- Gatherpedia: Chrome.lua
-- Shared window chrome. Prefers the game's own frame textures by path
-- (normal for an addon; they are not packed in our zip). We feature-
-- detect each path and fall back to our own art or a simple bevel if
-- it is missing. No secure templates: those can taint.

local ADDON_NAME, ns = ...

local Chrome = {}
ns.Chrome = Chrome

-- How far to inset content when the thick dialog border is in use.
Chrome.INSET = 12

local OUR_RING = "Interface\\AddOns\\Gatherpedia\\Media\\PortraitRing"
local OUR_CAP  = "Interface\\AddOns\\Gatherpedia\\Media\\BarCap"
local OUR_GRAIN = "Interface\\AddOns\\Gatherpedia\\Media\\SidebarGrain"
local WHITE = "Interface\\Buttons\\WHITE8X8"

-- Game textures, in preference order where several are listed.
Chrome.PATHS = {
    dialogBorder     = "Interface\\DialogFrame\\UI-DialogBox-Border",
    dialogBg         = "Interface\\DialogFrame\\UI-DialogBox-Background",
    dialogHeader     = "Interface\\DialogFrame\\UI-DialogBox-Header",
    rock             = "Interface\\FrameGeneral\\UI-Background-Rock",
    marble           = "Interface\\FrameGeneral\\UI-Background-Marble",
    tooltipBorder    = "Interface\\Tooltips\\UI-Tooltip-Border",
    tooltipBg        = "Interface\\Tooltips\\UI-Tooltip-Background",
    closeUp          = "Interface\\Buttons\\UI-Panel-MinimizeButton-Up",
    closeDown        = "Interface\\Buttons\\UI-Panel-MinimizeButton-Down",
    closeHi          = "Interface\\Buttons\\UI-Panel-MinimizeButton-Highlight",
    closeDis         = "Interface\\Buttons\\UI-Panel-MinimizeButton-Disabled",
    btnUp            = "Interface\\Buttons\\UI-Panel-Button-Up",
    btnDown          = "Interface\\Buttons\\UI-Panel-Button-Down",
    btnHi            = "Interface\\Buttons\\UI-Panel-Button-Highlight",
    btnDis           = "Interface\\Buttons\\UI-Panel-Button-Disabled",
    sliderBg         = "Interface\\Buttons\\UI-SliderBar-Background",
    sliderBorder     = "Interface\\Buttons\\UI-SliderBar-Border",
    sliderThumb      = "Interface\\Buttons\\UI-SliderBar-Button-Horizontal",
    checkUp          = "Interface\\Buttons\\UI-CheckBox-Up",
    checkDown        = "Interface\\Buttons\\UI-CheckBox-Down",
    checkHi          = "Interface\\Buttons\\UI-CheckBox-Highlight",
    checkOn          = "Interface\\Buttons\\UI-CheckBox-Check",
    portraitMask     = "Interface\\CharacterFrame\\TempPortraitAlphaMask",
    trackingBorder   = "Interface\\Minimap\\MiniMap-TrackingBorder",
    statusBar        = "Interface\\TargetingFrame\\UI-StatusBar",
}

-- What was actually used, for /gp debug output: path -> "game" | "fallback" | "tried".
Chrome.used = {}

local cache = {}

function Chrome:Has(path)
    if not path then return false end
    if cache[path] ~= nil then return cache[path] end
    if GetFileIDFromPath then
        local ok, id = pcall(GetFileIDFromPath, path)
        if ok and type(id) == "number" then
            cache[path] = id > 0
            return cache[path]
        end
    end
    -- Unknown: let SetTexture try; we record the result after.
    return nil
end

function Chrome:SetTexture(tex, path)
    if not tex or not path or not tex.SetTexture then
        return false
    end
    local known = self:Has(path)
    if known == false then
        Chrome.used[path] = "fallback"
        return false
    end
    local ok = pcall(tex.SetTexture, tex, path)
    if not ok then
        cache[path] = false
        Chrome.used[path] = "fallback"
        return false
    end
    if known == nil and tex.GetTexture then
        local ok2, got = pcall(tex.GetTexture, tex)
        if not ok2 or got == nil or got == "" then
            cache[path] = false
            Chrome.used[path] = "fallback"
            return false
        end
        cache[path] = true
    end
    if known ~= false then
        cache[path] = true
        Chrome.used[path] = "game"
    end
    return true
end

function Chrome:Summary()
    local game, fallback = {}, {}
    for path, how in pairs(self.used) do
        if how == "game" then
            game[#game + 1] = path
        else
            fallback[#fallback + 1] = path
        end
    end
    table.sort(game)
    table.sort(fallback)
    return game, fallback
end

---------------------------------------------------------------------------
-- Window, cards, wells
---------------------------------------------------------------------------

function Chrome:ApplyWindow(frame)
    -- Flat dark window with a thin warm border and rounded corners.
    local T = ns.Theme
    if T and T.Panel then
        T:Panel(frame, T.C.window, T.C.frame, 8)
    else
        frame:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = 1,
            insets = { left = 1, right = 1, top = 1, bottom = 1 } })
        frame:SetBackdropColor(0.06, 0.05, 0.04, 0.98)
        frame:SetBackdropBorderColor(0.29, 0.25, 0.19, 1)
    end
    return { left = 1, right = 1, top = 1, bottom = 1 }
end

function Chrome:ApplyCard(frame, kind)
    -- kind: "card" (right-panel boxes), "well" (sidebar rows), "session".
    local T = ns.Theme
    if not (T and T.Panel) then return end
    if kind == "session" then
        T:Panel(frame, T.C.well, T.C.line, 6)
    elseif kind == "well" then
        T:Panel(frame, T.C.well, T.C.line, 6)
    else
        T:Panel(frame, T.C.card, T.C.line, 8)
    end
end

function Chrome:Bevel(parent)
    -- The flat theme has no bevels; kept so older callers still work.
end

---------------------------------------------------------------------------
-- Portrait, title banner, close, buttons, sliders, bar caps
---------------------------------------------------------------------------

function Chrome:AddPortrait(parent, iconPath, size)
    size = size or 56
    local hold = CreateFrame("Frame", nil, parent)
    hold:SetSize(size, size)
    -- 54 px from y=+8 ends at y=-46, leaving a gap above the dropdown at -62.
    hold:SetPoint("TOPLEFT", parent, "TOPLEFT", -4, 8)
    hold:SetFrameLevel((parent:GetFrameLevel() or 1) + 5)
    if hold.EnableMouse then hold:EnableMouse(false) end
    local bg = hold:CreateTexture(nil, "BACKGROUND")
    bg:SetPoint("TOPLEFT", 6, -6)
    bg:SetPoint("BOTTOMRIGHT", -6, 6)
    bg:SetColorTexture(0.08, 0.06, 0.03, 1)
    local icon = hold:CreateTexture(nil, "ARTWORK")
    icon:SetPoint("TOPLEFT", 7, -7)
    icon:SetPoint("BOTTOMRIGHT", -7, 7)
    icon:SetTexture(iconPath)
    if icon.SetTexCoord then icon:SetTexCoord(0.06, 0.94, 0.06, 0.94) end
    -- Circular mask when the client has one.
    if hold.CreateMaskTexture and self:Has(self.PATHS.portraitMask) ~= false then
        local mask = hold:CreateMaskTexture()
        mask:SetAllPoints(icon)
        if self:SetTexture(mask, self.PATHS.portraitMask) and icon.AddMaskTexture then
            pcall(icon.AddMaskTexture, icon, mask)
        end
    end
    local ring = hold:CreateTexture(nil, "OVERLAY")
    ring:SetAllPoints(hold)
    if not self:SetTexture(ring, self.PATHS.trackingBorder) then
        ring:SetTexture(OUR_RING)
        Chrome.used[OUR_RING] = "fallback"
    else
        -- MiniMap-TrackingBorder is a 64x64-ish gold square ring; crop
        -- the empty padding if the tex coord API exists.
        if ring.SetTexCoord then ring:SetTexCoord(0.00, 0.60, 0.00, 0.60) end
    end
    hold.icon, hold.ring = icon, ring
    return hold
end

function Chrome:AddTitleBanner(parent, titleText)
    -- A slim title strip that sits on top of the window, so the window's
    -- own layout is untouched. Dragging the strip moves the window.
    local T = ns.Theme
    local strip = CreateFrame("Frame", nil, parent)
    strip:SetHeight(26)
    strip:SetPoint("BOTTOMLEFT", parent, "TOPLEFT", 0, -1)
    strip:SetPoint("BOTTOMRIGHT", parent, "TOPRIGHT", 0, -1)
    strip:SetFrameLevel(parent:GetFrameLevel() or 1)
    if T and T.Panel then T:Panel(strip, T.C.side, T.C.frame, 8) end
    -- Square off the strip's bottom corners where it meets the window.
    local seam = strip:CreateTexture(nil, "BORDER")
    seam:SetPoint("BOTTOMLEFT", 1, 0)
    seam:SetPoint("BOTTOMRIGHT", -1, 0)
    seam:SetHeight(8)
    local sc = T and T.C.side or { 0.08, 0.07, 0.06 }
    seam:SetColorTexture(sc[1], sc[2], sc[3], 1)
    local rule = strip:CreateTexture(nil, "ARTWORK")
    rule:SetPoint("BOTTOMLEFT", 1, 0)
    rule:SetPoint("BOTTOMRIGHT", -1, 0)
    rule:SetHeight(1)
    local lc = T and T.C.line or { 0.17, 0.15, 0.12 }
    rule:SetColorTexture(lc[1], lc[2], lc[3], 1)
    strip:EnableMouse(true)
    if strip.RegisterForDrag then strip:RegisterForDrag("LeftButton") end
    strip:SetScript("OnDragStart", function()
        local f = parent
        -- Use the window's own handler so its lock and save rules apply.
        local handler = f.GetScript and f:GetScript("OnDragStart")
        if handler then
            handler(f)
        elseif f.StartMoving and f:IsMovable() then
            f:StartMoving()
        end
    end)
    strip:SetScript("OnDragStop", function()
        local f = parent
        local handler = f.GetScript and f:GetScript("OnDragStop")
        if handler then handler(f) elseif f.StopMovingOrSizing then f:StopMovingOrSizing() end
    end)
    local title = strip:CreateFontString(nil, "OVERLAY", "GatherpediaFontNormalSmall")
    title:SetPoint("CENTER", 0, 0)
    title:SetText(string.upper(titleText or "Gatherpedia"))
    if title.SetSpacing then title:SetSpacing(0) end
    strip.title = title
    parent._gpBanner = strip
    return strip
end

function Chrome:MakeCloseButton(parent, onClick)
    local T = ns.Theme
    local host = parent._gpBanner or parent
    local b = CreateFrame("Button", nil, host)
    b:SetSize(20, 20)
    b:SetPoint("RIGHT", host, "RIGHT", -4, 0)
    if host == parent then
        b:ClearAllPoints()
        b:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -6, -6)
    end
    b:SetFrameLevel((host:GetFrameLevel() or 1) + 6)
    if T and T.SkinButton then T:SkinButton(b, "quiet") end
    -- An X from two thin rotated bars; plain text X if rotation is missing.
    local made = false
    for _, deg in ipairs({ 45, -45 }) do
        local bar = b:CreateTexture(nil, "ARTWORK")
        bar:SetSize(10, 1.5)
        bar:SetPoint("CENTER")
        bar:SetColorTexture(0.72, 0.67, 0.56, 1)
        if bar.SetRotation then
            bar:SetRotation(math.rad(deg))
            made = true
        else
            bar:Hide()
        end
    end
    if not made then
        local x = b:CreateFontString(nil, "OVERLAY", "GatherpediaFontHighlightSmall")
        x:SetPoint("CENTER", 0, 0)
        x:SetText("X")
    end
    b:SetScript("OnClick", onClick)
    return b
end

-- Standard gold panel button textures, without UIPanelButtonTemplate.
local BTN_COORD = { 0, 0.625, 0, 0.6875 }

function Chrome:StyleButton(b)
    local T = ns.Theme
    if T and T.SkinButton then
        T:SkinButton(b, "quiet")
        return true
    end
    return false
end

function Chrome:MakeButton(parent, w, h, caption)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(w, h)
    b.label = b:CreateFontString(nil, "OVERLAY", "GatherpediaFontHighlightSmall")
    b.label:SetPoint("CENTER", 0, 0)
    b.label:SetText(caption)
    self:StyleButton(b)
    return b
end

function Chrome:StyleSliderTrack(track, thumb, width)
    -- Game slider border/background when present; otherwise leave the
    -- caller's backdrop in place and only swap the thumb art.
    if track.SetBackdrop and self:Has(self.PATHS.sliderBorder) ~= false then
        track:SetBackdrop({
            bgFile = self.PATHS.sliderBg,
            edgeFile = self.PATHS.sliderBorder,
            edgeSize = 8,
            insets = { left = 3, right = 3, top = 3, bottom = 3 },
        })
        track:SetBackdropColor(1, 1, 1, 1)
        track:SetBackdropBorderColor(1, 1, 1, 1)
        Chrome.used[self.PATHS.sliderBorder] = Chrome.used[self.PATHS.sliderBorder] or "tried"
        Chrome.used[self.PATHS.sliderBg] = Chrome.used[self.PATHS.sliderBg] or "tried"
    end
    if thumb and self:Has(self.PATHS.sliderThumb) ~= false then
        thumb:SetSize(32, 32)
        if thumb.SetBackdrop then
            -- Drop the gold box; the game thumb is the art.
            pcall(thumb.SetBackdrop, thumb, nil)
        end
        local tex = thumb.thumbTex
        if not tex then
            tex = thumb:CreateTexture(nil, "ARTWORK")
            tex:SetAllPoints()
            thumb.thumbTex = tex
        end
        if self:SetTexture(tex, self.PATHS.sliderThumb) then
            -- ok
        end
    end
end

function Chrome:AddBarCaps(bar)
    -- Flat bars have no end caps; kept so older callers still work.
end

function Chrome:StyleSwatch(btn)
    if not btn then return end
    if btn.SetBackdrop and self:Has(self.PATHS.tooltipBorder) ~= false then
        btn:SetBackdrop({ bgFile = WHITE, edgeFile = self.PATHS.tooltipBorder, edgeSize = 8,
            insets = { left = 2, right = 2, top = 2, bottom = 2 } })
        Chrome.used[self.PATHS.tooltipBorder] = Chrome.used[self.PATHS.tooltipBorder] or "tried"
    else
        self:Bevel(btn)
    end
end


---------------------------------------------------------------------------
-- Profession skill bars
-- Prefer the game's own Professions skill-bar textures or atlases when
-- the client has them (path / atlas name only; we never pack game art).
-- Classic and Forever typically do not, so we fall back to our own
-- illustrated fills and a classic casting-bar spark by path.
---------------------------------------------------------------------------

Chrome.PATHS.castSpark = "Interface\\CastingBar\\UI-CastingBar-Spark"

local OUR_FILL = {
    Herbalism = "Interface\\AddOns\\Gatherpedia\\Media\\SkillFill-Herbalism",
    Mining    = "Interface\\AddOns\\Gatherpedia\\Media\\SkillFill-Mining",
    Fishing   = "Interface\\AddOns\\Gatherpedia\\Media\\SkillFill-Fishing",
    Skinning  = "Interface\\AddOns\\Gatherpedia\\Media\\SkillFill-Skinning",
}
local OUR_SPARK = "Interface\\AddOns\\Gatherpedia\\Media\\SkillSpark"
Chrome.OUR_FILL = OUR_FILL
Chrome.OUR_SPARK = OUR_SPARK
local OUR_ENDCAP    = "Interface\\AddOns\\Gatherpedia\\Media\\SkillEndCap"
local OUR_ENDGLOW   = "Interface\\AddOns\\Gatherpedia\\Media\\SkillEndGlow"
local OUR_SKILLMASK = "Interface\\AddOns\\Gatherpedia\\Media\\SkillBarMask"
local OUR_SKILLEND  = "Interface\\AddOns\\Gatherpedia\\Media\\SkillBarEnd"

local SPARK_COLOR = {
    Herbalism = { 0.55, 1.00, 0.40 },
    Mining    = { 1.00, 0.85, 0.35 },
    Fishing   = { 0.45, 0.80, 1.00 },
    Skinning  = { 1.00, 0.82, 0.55 },
}

local FILL_ATLASES = {
    Herbalism = { "Professions-SkillBar-Fill-Herbalism", "Professions-SkillBar-Herbalism", "ui-crafting-skillbar-fill-herbalism" },
    Mining    = { "Professions-SkillBar-Fill-Mining", "Professions-SkillBar-Mining", "ui-crafting-skillbar-fill-mining" },
    Fishing   = { "Professions-SkillBar-Fill-Fishing", "Professions-SkillBar-Fishing", "ui-crafting-skillbar-fill-fishing" },
    Skinning  = { "Professions-SkillBar-Fill-Skinning", "Professions-SkillBar-Skinning", "ui-crafting-skillbar-fill-skinning" },
    _any      = { "Professions-SkillBar-Fill", "ui-crafting-skillbar-fill", "Professions-Skillbar-Fill" },
}
local FILL_PATHS = {
    Herbalism = {
        "Interface\\Professions\\ProfessionsSkillBar-Herbalism",
        "Interface\\Professions\\ProfessionsSkillBar-Fill-Herbalism",
        "Interface\\Professions\\ProfessionBar-Herbalism",
        "Interface\\ProfessionBars\\Herbalism-Fill",
    },
    Mining = {
        "Interface\\Professions\\ProfessionsSkillBar-Mining",
        "Interface\\Professions\\ProfessionsSkillBar-Fill-Mining",
        "Interface\\Professions\\ProfessionBar-Mining",
        "Interface\\ProfessionBars\\Mining-Fill",
    },
    Fishing = {
        "Interface\\Professions\\ProfessionsSkillBar-Fishing",
        "Interface\\Professions\\ProfessionsSkillBar-Fill-Fishing",
        "Interface\\Professions\\ProfessionBar-Fishing",
        "Interface\\ProfessionBars\\Fishing-Fill",
    },
    Skinning = {
        "Interface\\Professions\\ProfessionsSkillBar-Skinning",
        "Interface\\Professions\\ProfessionsSkillBar-Fill-Skinning",
        "Interface\\Professions\\ProfessionBar-Skinning",
        "Interface\\ProfessionBars\\Skinning-Fill",
    },
    _any = {
        "Interface\\Professions\\ProfessionsSkillBar-Fill",
        "Interface\\Professions\\ProfessionBar-Fill",
        "Interface\\Professions\\ProfessionBar",
        "Interface\\Professions\\ProfessionsSkillBar",
    },
}
local BG_ATLASES = { "Professions-SkillBar-Background", "ui-crafting-skillbar-bg", "Professions-Skillbar-Background" }
local BG_PATHS = {
    "Interface\\Professions\\ProfessionsSkillBar-Background",
    "Interface\\Professions\\ProfessionsSkillBarBackground",
    "Interface\\Professions\\ProfessionBar-Background",
}

function Chrome:HasAtlas(name)
    if not name then return false end
    local key = "atlas:" .. name
    if cache[key] ~= nil then return cache[key] end
    if not (C_Texture and C_Texture.GetAtlasInfo) then
        cache[key] = false
        return false
    end
    local ok, info = pcall(C_Texture.GetAtlasInfo, name)
    local found = false
    if ok and info then
        if type(info) == "table" and (info.width or info.filename or info.file or info.left) then
            found = true
        elseif type(info) == "number" and info > 0 then
            found = true
        elseif type(info) == "string" and info ~= "" then
            found = true
        end
    end
    cache[key] = found
    if found then Chrome.used[key] = "game" end
    return found
end

function Chrome:SetAtlas(tex, name)
    if not tex or not name or not tex.SetAtlas then return false end
    if not self:HasAtlas(name) then return false end
    local ok = pcall(tex.SetAtlas, tex, name)
    if ok then
        Chrome.used["atlas:" .. name] = "game"
        return true
    end
    return false
end

local function firstAtlas(self, list)
    for _, name in ipairs(list or {}) do
        if self:HasAtlas(name) then return name end
    end
end

local function firstPath(self, list)
    for _, path in ipairs(list or {}) do
        if self:Has(path) ~= false then
            -- Has() is nil when we cannot probe; still try SetTexture later.
            if self:Has(path) == true then return path, "game" end
            if self:Has(path) == nil then return path, "try" end
        end
    end
end

function Chrome:ResolveSkillFill(prof)
    prof = prof or "Herbalism"
    local atl = firstAtlas(self, FILL_ATLASES[prof]) or firstAtlas(self, FILL_ATLASES._any)
    if atl then return "atlas", atl end
    local path, how = firstPath(self, FILL_PATHS[prof])
    if not path then path, how = firstPath(self, FILL_PATHS._any) end
    if path and how == "game" then return "path", path end
    -- Unconfirmed paths are not used; we would rather show our art
    -- than a missing texture on Classic / Forever.
    local ours = OUR_FILL[prof] or OUR_FILL.Herbalism
    Chrome.used[ours] = "fallback"
    return "path", ours
end

local function Fraction(bar)
    if not bar or not bar.GetMinMaxValues or not bar.GetValue then return 0 end
    local mn, mx = bar:GetMinMaxValues()
    local v = bar:GetValue() or 0
    mn, mx = mn or 0, mx or 1
    if mx <= mn then return 0 end
    local t = (v - mn) / (mx - mn)
    if t < 0 then return 0 end
    if t > 1 then return 1 end
    return t
end

function Chrome:SyncSkillBar(bar)
    -- Flat fill: the StatusBar draws itself; nothing to place.
end

local function HookValue(bar)
    if bar._gpSkillHooked then return end
    bar._gpSkillHooked = true
    local orig = bar.SetValue
    if orig then
        function bar:SetValue(v)
            orig(self, v)
            Chrome:SyncSkillBar(self)
        end
    end
    local origMM = bar.SetMinMaxValues
    if origMM then
        function bar:SetMinMaxValues(a, b)
            origMM(self, a, b)
            Chrome:SyncSkillBar(self)
        end
    end
    if bar.SetScript and bar.GetScript then
        local prev = bar:GetScript("OnSizeChanged")
        bar:SetScript("OnSizeChanged", function(self, ...)
            if prev then prev(self, ...) end
            Chrome:SyncSkillBar(self)
        end)
    end
end

function Chrome:SetSkillBarProfession(bar, prof)
    if not bar then return end
    prof = prof or "Herbalism"
    bar._skillProf = prof
    local T = ns.Theme
    local c = T and T:Prof(prof).accent or { 0.9, 0.75, 0.38 }
    if bar.SetStatusBarTexture then bar:SetStatusBarTexture(WHITE) end
    if bar.SetStatusBarColor then bar:SetStatusBarColor(c[1], c[2], c[3], 1) end
end

local function StyleTrack(self, track, height)
    if not track then return end
    if track.SetBackdropColor then
        -- Prefer a game background if one exists; otherwise a dark empty well.
        local bgAtlas = firstAtlas(self, BG_ATLASES)
        local bgPath = not bgAtlas and select(1, firstPath(self, BG_PATHS))
        track:SetBackdropColor(0.035, 0.03, 0.02, 1)
        -- Thin gold-bronze rim.
        track:SetBackdropBorderColor(0.55, 0.42, 0.18, 1)
        if bgAtlas or (bgPath and self:Has(bgPath) == true) then
            Chrome.used[bgAtlas and ("atlas:" .. bgAtlas) or bgPath] = "game"
        end
    end
end

local function AddEndArt(self, bar, height)
    height = height or 14
    -- Soft profession-colored glow behind the cap.
    local glow = bar:CreateTexture(nil, "OVERLAY")
    glow:SetSize(math.max(20, height * 1.8), math.max(8, height - 2))
    if not self:SetTexture(glow, OUR_ENDGLOW) then
        -- Fall back to the classic spark by path, then our spark.
        if not self:SetTexture(glow, self.PATHS.castSpark) then
            glow:SetTexture(OUR_SPARK)
            Chrome.used[OUR_SPARK] = "fallback"
        end
    else
        Chrome.used[OUR_ENDGLOW] = "fallback"
    end
    if glow.SetBlendMode then pcall(glow.SetBlendMode, glow, "ADD") end
    glow:Hide()
    bar.glow = glow
    -- Crisp white vertical cap on the fill end.
    local cap = bar:CreateTexture(nil, "OVERLAY")
    cap:SetSize(4, math.max(8, height - 4))
    if not self:SetTexture(cap, OUR_ENDCAP) then
        cap:SetColorTexture(1, 1, 1, 0.95)
        Chrome.used[OUR_ENDCAP] = "fallback"
    else
        Chrome.used[OUR_ENDCAP] = "fallback"
    end
    if cap.SetBlendMode then pcall(cap.SetBlendMode, cap, "ADD") end
    cap:Hide()
    bar.cap = cap
    -- Keep a spark handle so other code can still find one.
    bar.spark = glow
    return cap, glow
end

local function BarFont(fs, px, dim)
    if not fs then return end
    local path
    if GameFontHighlightSmall and GameFontHighlightSmall.GetFont then
        local ok, p = pcall(GameFontHighlightSmall.GetFont, GameFontHighlightSmall)
        if ok and type(p) == "string" then path = p end
    end
    path = path or "Fonts\\FRIZQT__.TTF"
    -- No outline: a thin drop shadow only.
    if fs.SetFont then pcall(fs.SetFont, fs, path, px, "") end
    if fs.SetShadowOffset then pcall(fs.SetShadowOffset, fs, 1, -1) end
    if fs.SetShadowColor then pcall(fs.SetShadowColor, fs, 0, 0, 0, dim and 0.55 or 0.80) end
    if fs.SetTextColor then
        if dim then
            fs:SetTextColor(0.62, 0.58, 0.48)
        else
            fs:SetTextColor(1, 1, 1)
        end
    end
end

function Chrome:SetSkillBarLabel(bar, text, dim)
    if not bar or not bar.text then return end
    bar.text:SetText(text or "")
    local T = ns.Theme
    if T then
        local c = dim and T.C.text3 or T.C.text
        bar.text:SetTextColor(c[1], c[2], c[3])
    end
end

local function AddCapsule(self, host, height, fillTex, bgTex)
    if not host then return end
    height = height or (host.GetHeight and host:GetHeight()) or 18
    -- Clip fill and background to a capsule when the client can mask.
    if host.CreateMaskTexture then
        local mask = host:CreateMaskTexture()
        mask:SetAllPoints(host)
        if self:SetTexture(mask, OUR_SKILLMASK) or (mask.SetTexture and pcall(mask.SetTexture, mask, OUR_SKILLMASK)) then
            if fillTex and fillTex.AddMaskTexture then pcall(fillTex.AddMaskTexture, fillTex, mask) end
            if bgTex and bgTex.AddMaskTexture then pcall(bgTex.AddMaskTexture, bgTex, mask) end
            Chrome.used[OUR_SKILLMASK] = "fallback"
            host._skillMask = mask
        end
    end
    -- 3-piece bronze capsule border: rounded ends plus top/bottom rules.
    local endH = height + 2
    local L = host:CreateTexture(nil, "OVERLAY")
    L:SetSize(endH, endH)
    L:SetPoint("LEFT", host, "LEFT", -1, 0)
    if not self:SetTexture(L, OUR_SKILLEND) then
        L:SetTexture(OUR_SKILLEND)
    end
    Chrome.used[OUR_SKILLEND] = "fallback"
    local R = host:CreateTexture(nil, "OVERLAY")
    R:SetSize(endH, endH)
    R:SetPoint("RIGHT", host, "RIGHT", 1, 0)
    if not self:SetTexture(R, OUR_SKILLEND) then
        R:SetTexture(OUR_SKILLEND)
    end
    if R.SetTexCoord then R:SetTexCoord(1, 0, 0, 1) end
    local inset = height / 2
    local top = host:CreateTexture(nil, "OVERLAY")
    top:SetHeight(1)
    top:SetPoint("TOPLEFT", host, "TOPLEFT", inset, 0)
    top:SetPoint("TOPRIGHT", host, "TOPRIGHT", -inset, 0)
    top:SetColorTexture(0.70, 0.52, 0.22, 1)
    local bot = host:CreateTexture(nil, "OVERLAY")
    bot:SetHeight(1)
    bot:SetPoint("BOTTOMLEFT", host, "BOTTOMLEFT", inset, 0)
    bot:SetPoint("BOTTOMRIGHT", host, "BOTTOMRIGHT", -inset, 0)
    bot:SetColorTexture(0.45, 0.32, 0.12, 1)
    host._capL, host._capR, host._edgeTop, host._edgeBot = L, R, top, bot
end

-- Restyle an existing StatusBar (sidebar or header) with themed fill, end cap, and capsule track.
function Chrome:StyleSkillBar(bar, opts)
    if not bar then return bar end
    opts = opts or {}
    local T = ns.Theme
    local track = opts.track
    if track and T then
        T:Panel(track, T.C.well, nil, 3)
    end
    if not bar.bg and T then
        local bg = bar:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()
        bg:SetColorTexture(T.C.well[1], T.C.well[2], T.C.well[3], 1)
        bar.bg = bg
    end
    if opts.text then bar.text = bar.text or opts.text end
    self:SetSkillBarProfession(bar, opts.prof or "Herbalism")
    return bar
end

-- A standalone header-sized skill bar. Points are set on the returned StatusBar.
function Chrome:MakeSkillBar(parent, width, height)
    -- Header bar: a rounded well with a flat fill and the label inside.
    height = height or 18
    width = width or 240
    local T = ns.Theme
    local well = CreateFrame("Frame", nil, parent)
    well:SetSize(width, height)
    if T then T:Panel(well, T.C.well, T.C.line, math.min(6, math.floor(height / 2))) end
    local bar = CreateFrame("StatusBar", nil, well)
    bar:SetPoint("TOPLEFT", 2, -2)
    bar:SetPoint("BOTTOMRIGHT", -2, 2)
    bar:SetMinMaxValues(0, 1)
    bar:SetValue(0)
    local textHold = CreateFrame("Frame", nil, bar)
    textHold:SetAllPoints(well)
    textHold:SetFrameLevel((bar:GetFrameLevel() or 1) + 3)
    local text = textHold:CreateFontString(nil, "OVERLAY", "GatherpediaFontHighlightSmall")
    text:SetPoint("CENTER", 0, 0)
    text:SetJustifyH("CENTER")
    bar.text, bar.textHold, bar.well = text, textHold, well
    self:SetSkillBarProfession(bar, "Herbalism")
    -- Callers position the returned bar; move the well with it.
    local origSetPoint, origClear = bar.SetPoint, bar.ClearAllPoints
    local placed = false
    bar.SetPoint = function(self, ...)
        if not placed then placed = true end
        well:SetPoint(...)
    end
    bar.ClearAllPoints = function() well:ClearAllPoints() end
    bar.Show = function() well:Show() end
    bar.Hide = function() well:Hide() end
    bar._origSetPoint, bar._origClear = origSetPoint, origClear
    return bar
end

---------------------------------------------------------------------------
-- Inset scrollbar used by the Guides and Trainers lists. A gold track
-- and thumb, shown only when the child is taller than the view, so the
-- default Blizzard arrows never collide with a header.
---------------------------------------------------------------------------

Chrome.SCROLL_GUTTER = 16
Chrome.SCROLL_TRACK_W = 6

local SCROLL_GOLD = { 0.90, 0.75, 0.38 }

function Chrome:CreateScroll(parent, name)
    local T = ns.Theme
    local scroll = CreateFrame("ScrollFrame", name, parent)
    local content = CreateFrame("Frame", nil, scroll)
    content:SetSize(1, 1)
    scroll:SetScrollChild(content)
    scroll.content = content

    local bar = CreateFrame("Frame", nil, parent)
    bar:SetWidth(self.SCROLL_TRACK_W)
    if T then T:Panel(bar, T.C.well, nil, 3) end
    local thumb = CreateFrame("Button", nil, bar)
    thumb:SetWidth(self.SCROLL_TRACK_W)
    if T then T:Panel(thumb, T.C.line2, nil, 3) end
    thumb:SetScript("OnEnter", function(t) if T then T:PanelColors(t, T.C.goldLine) end end)
    thumb:SetScript("OnLeave", function(t) if T then T:PanelColors(t, T.C.line2) end end)
    bar.thumb = thumb
    bar:Hide()
    scroll.bar = bar

    if scroll.EnableMouseWheel then scroll:EnableMouseWheel(true) end
    scroll:SetScript("OnMouseWheel", function(self, delta)
        Chrome:ScrollBy(self, -(delta or 0) * 28)
    end)
    return scroll, content, bar
end

function Chrome:ScrollBy(scroll, dy)
    if not scroll then return end
    local cur = (scroll.GetVerticalScroll and scroll:GetVerticalScroll()) or 0
    local sh = scroll:GetHeight() or 0
    local ch = (scroll.content and scroll.content:GetHeight()) or 0
    local max = (scroll.GetVerticalScrollRange and scroll:GetVerticalScrollRange()) or math.max(0, ch - sh)
    local v = cur + (dy or 0)
    if v < 0 then v = 0 end
    if v > max then v = max end
    if scroll.SetVerticalScroll then scroll:SetVerticalScroll(v) end
    self:UpdateScrollBar(scroll)
end

function Chrome:ScrollToTop(scroll)
    if scroll and scroll.SetVerticalScroll then scroll:SetVerticalScroll(0) end
    self:UpdateScrollBar(scroll)
end

-- top/bot are offsets from the parent (top is a positive inset from the
-- parent's top; bot is a positive inset from the parent's bottom).
function Chrome:PlaceScroll(scroll, top, bot)
    if not scroll then return end
    scroll._topPad = top or 0
    scroll._botPad = bot or 0
    self:UpdateScrollBar(scroll)
end

function Chrome:UpdateScrollBar(scroll)
    if not scroll or not scroll.bar then return end
    local parent = scroll:GetParent()
    local bar = scroll.bar
    if not parent then return end
    local top = scroll._topPad or 0
    local bot = scroll._botPad or 0
    local sh = scroll:GetHeight() or 0
    local ch = (scroll.content and scroll.content:GetHeight()) or 0
    -- Before the frame has a real height, treat it as not overflowing
    -- until the caller sizes the page (first Show).
    local overflow = (sh > 1) and (ch > sh + 1)
    local gutter = overflow and (self.SCROLL_GUTTER or 16) or 8
    scroll:ClearAllPoints()
    scroll:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, -top)
    scroll:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", -gutter, bot)
    if overflow then
        bar:ClearAllPoints()
        bar:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -3, -top)
        bar:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", -3, bot)
        bar:Show()
        local sh2 = scroll:GetHeight() or sh
        local thumbH = math.max(24, math.min(sh2 - 4, sh2 * sh2 / math.max(ch, 1)))
        local range = math.max(1, ch - sh2)
        local cur = (scroll.GetVerticalScroll and scroll:GetVerticalScroll()) or 0
        local y = (cur / range) * math.max(0, sh2 - thumbH)
        bar.thumb:ClearAllPoints()
        bar.thumb:SetHeight(thumbH)
        bar.thumb:SetPoint("TOPLEFT", bar, "TOPLEFT", 0, -y)
    else
        bar:Hide()
        if scroll.SetVerticalScroll then scroll:SetVerticalScroll(0) end
    end
end
