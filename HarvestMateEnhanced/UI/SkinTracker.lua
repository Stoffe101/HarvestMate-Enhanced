-- HarvestMate Enhanced: UI/SkinTracker.lua
-- "Skinning levels": a small movable box you can switch on (Settings, or
-- /hme skinlevels) that says which beast levels to kill for Skinning
-- skill-ups right now, and keeps up as you go:
--   - the levels where every skin gives a point (orange), most do (yellow),
--     few do (green) and none do (grey), from your current skill;
--   - capped at what is sensible to fight at your level (the risk mode);
--   - the next level you will be able to skin and how many points away;
--   - beasts in this zone in those levels (bundled spawn data: where they
--     appear, not where they are now);
--   - your target's level and colour.
-- It updates on every skill-up, level-up, zone change and target change, and
-- says so in chat when a higher level becomes skinnable. A plain frame:
-- nothing protected, nothing automated.
-- Copyright (C) 2026 HarvestMate Enhanced contributors. GPL-3.0-or-later.

local _, ns = ...
local HME = ns.HME
local T = ns.Theme
local SM = HME.SkillModel

local ST = {}
HME.SkinTracker = ST

ST.MAX_LEVEL = 63          -- the highest beast level considered
ST.ZONE_BEASTS = 4         -- beasts named for the zone
ST.ORDER = { orange = 1, yellow = 2, green = 3 }
ST.SAYS = { orange = "a point every skin", yellow = "most skins give a point", green = "few skins give a point" }

---------------------------------------------------------------------------
-- What to kill (pure: testable without the frame)
---------------------------------------------------------------------------

-- Level bands for a skill: { orange = { lo, hi }, yellow = ..., green = ...,
-- greyTo = highest grey level, maxLevel = highest skinnable level }.
function ST.Bands(skill)
    local out = { maxLevel = SM.MaxSkinLevel(skill) }
    for level = 1, ST.MAX_LEVEL do
        local c = SM.Color(skill, SM.SkinReq(level))
        if c == "grey" then
            out.greyTo = level
        elseif c ~= "red" then
            local b = out[c]
            if b then b[2] = level else out[c] = { level, level } end
        end
    end
    return out
end

-- The next level this skill will be able to skin: level, skill needed, points away.
function ST.Next(skill)
    local level = SM.MaxSkinLevel(skill) + 1
    if level > ST.MAX_LEVEL then return nil end
    local req = SM.SkinReq(level)
    return level, req, math.max(0, req - skill)
end

-- The highest beast level that is sensible to fight now (Skinning's risk rule).
function ST.SafeLevel(profile)
    local above = HME.Skinning.LEVEL_ABOVE[(HME.settings and HME.settings.riskMode) or "balanced"] or 2
    return (profile.level or 1) + above
end

-- A band cut to what you can fight: { lo, hi } or nil.
local function Cut(band, safe)
    if not band or band[1] > safe then return nil end
    return { band[1], math.min(band[2], safe) }
end

-- Beasts of this zone in the levels worth killing, best first:
-- { { name, min, max, color, elite, count } }.
function ST.ZoneBeasts(mapID, skill, safe)
    local out = {}
    if not mapID then return out end
    local Corr = HME.Corrections
    local top = math.min(SM.MaxSkinLevel(skill), safe)
    for _, b in ipairs(HME.Spawns.BeastPoints(mapID)) do
        local blocked = Corr and Corr.BeastBlocked(b.npcID, mapID)
        if not blocked and HME.Spawns.Skinnable(b.npcID) ~= false and not b.elite then
            local best
            for level = b.min, math.min(b.max, top) do
                local c = SM.Color(skill, SM.SkinReq(level))
                if ST.ORDER[c] and (not best or ST.ORDER[c] < ST.ORDER[best]) then best = c end
            end
            if best then
                out[#out + 1] = { name = b.name, min = b.min, max = b.max, color = best, count = #(b.pts or {}) }
            end
        end
    end
    table.sort(out, function(a, b)
        if ST.ORDER[a.color] ~= ST.ORDER[b.color] then return ST.ORDER[a.color] < ST.ORDER[b.color] end
        if a.count ~= b.count then return a.count > b.count end
        return a.name < b.name
    end)
    return out
end

-- When this zone has none: the closest zones that do, by HME's travel
-- estimate: { { mapID, name, secs, best = first ZoneBeasts entry } }, up to n.
-- Worked out again only when the zone, skill or safe level changes.
ST.ELSEWHERE = 2
local elsewhereKey, elsewhere
function ST.Elsewhere(fromMap, skill, safe, n)
    local key = ("%s:%d:%d"):format(tostring(fromMap), skill, safe)
    if key == elsewhereKey then return elsewhere end
    local out = {}
    for _, mapID in ipairs(HME.Spawns.Maps("Skinning")) do
        local z = HME.ZoneData.Get(mapID)
        if mapID ~= fromMap and not (z and (z.city or z.upcoming)) then
            local here = ST.ZoneBeasts(mapID, skill, safe)
            if #here > 0 then
                local secs = fromMap and HME.Geo.TravelTime(fromMap, nil, nil, mapID, nil, nil)
                if secs then
                    out[#out + 1] = { mapID = mapID, name = HME.ZoneData.Name(mapID) or tostring(mapID), secs = secs, best = here[1] }
                end
            end
        end
    end
    table.sort(out, function(a, b)
        if a.secs ~= b.secs then return a.secs < b.secs end
        return a.mapID < b.mapID
    end)
    for i = #out, (n or ST.ELSEWHERE) + 1, -1 do out[i] = nil end
    elsewhereKey, elsewhere = key, out
    return out
end

-- Your target: { level, color, req, why } or nil when there is nothing to say.
function ST.Target(skill)
    if not (UnitExists and UnitExists("target")) then return nil end
    if UnitIsPlayer and UnitIsPlayer("target") then return nil end
    local level = HME.Num(UnitLevel and UnitLevel("target"))
    if not level then return nil end
    if level < 1 then return { level = "??", color = "red", why = "far above you" } end
    local req = SM.SkinReq(level)
    return { level = level, color = SM.Color(skill, req), req = req }
end

local function Paint(color, text) return "|cff" .. (SM.HEX[color] or "ffffff") .. text .. "|r" end
local function Range(b) return b[1] == b[2] and tostring(b[1]) or (b[1] .. "-" .. b[2]) end

-- Everything the box says, as lines. nil when you don't know Skinning.
function ST.Lines()
    local profile = HME.Player.Profile()
    local sk = profile.skills and profile.skills.Skinning
    if not sk then return nil end
    local skill, max = sk.rank, sk.max
    local bands = ST.Bands(skill)
    local safe = ST.SafeLevel(profile)
    local lines = {}
    local function add(s) lines[#lines + 1] = s end
    add(("|cffffd100Skinning %d|r / %d"):format(skill, max or 0))
    local shown = 0
    for _, c in ipairs({ "orange", "yellow", "green" }) do
        local b = bands[c] and Cut(bands[c], safe)
        if b and shown < 2 then
            add(("%s %s"):format(Paint(c, (shown == 0 and "Kill level " or "or level ") .. Range(b)), ST.SAYS[c]))
            shown = shown + 1
        end
    end
    if shown == 0 then
        add(Paint("grey", "Nothing you can fight gives a point now: train, or level up."))
    end
    if bands.orange and bands.orange[2] > safe then
        add(("|cff9a9a9aOrange goes up to %d; above %d is too high for you now.|r"):format(bands.orange[2], safe))
    end
    if bands.greyTo then add(("|cff9a9a9aLevel %d and below: no points.|r"):format(bands.greyTo)) end
    local nextLevel, req, away = ST.Next(skill)
    if nextLevel then
        if max and req > max then
            add(("Level %d needs %d Skinning: train first (your cap is %d)."):format(nextLevel, req, max))
        else
            add(("Next: level %d at %d Skinning (+%d)"):format(nextLevel, req, away))
        end
    end
    local zone = profile.mapID and HME.Geo.ZoneOf(profile.mapID)
    local here = ST.ZoneBeasts(zone, skill, safe)
    local zoneName = (zone and HME.ZoneData.Name(zone)) or "this zone"
    if #here == 0 then
        add(("|cff9a9a9a%s: no beast in those levels in the bundled data.|r"):format(zoneName))
        for _, z in ipairs(ST.Elsewhere(zone, skill, safe)) do
            local e = z.best
            add(("Closest: %s, %s (about %s)"):format(z.name,
                Paint(e.color, ("%s %s"):format(e.name, e.min == e.max and e.min or (e.min .. "-" .. e.max))), HME.U.Duration(z.secs)))
        end
    else
        local names = {}
        for i = 1, math.min(ST.ZONE_BEASTS, #here) do
            local e = here[i]
            names[#names + 1] = Paint(e.color, ("%s %s"):format(e.name, e.min == e.max and e.min or (e.min .. "-" .. e.max)))
        end
        add(zoneName .. ": " .. table.concat(names, ", "))
    end
    local t = ST.Target(skill)
    if t then
        local say = t.why or (t.color == "red" and ("needs %d Skinning"):format(t.req)) or (t.color == "grey" and "no points")
            or ST.SAYS[t.color] or ""
        add(("Target: %s %s"):format(Paint(t.color, "level " .. t.level), say))
    end
    return lines, skill
end

---------------------------------------------------------------------------
-- The box
---------------------------------------------------------------------------
local f

local function Build()
    f = CreateFrame("Frame", "HarvestMateEnhancedSkinLevels", UIParent)
    f:SetSize(250, 60)
    f:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", -220, -320)
    f:SetFrameStrata("MEDIUM")
    f:SetClampedToScreen(true)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    T.Panel(f, 0.82)
    f.head = CreateFrame("Frame", nil, f)
    f.head:SetPoint("TOPLEFT")
    f.head:SetPoint("TOPRIGHT")
    f.head:SetHeight(16)
    T.HeaderStrip(f.head, "Skinning levels")
    f.text = T.Text(f, "", "GameFontHighlightSmall")
    f.text:SetPoint("TOPLEFT", 8, -20)
    f.text:SetWidth(234)
    f.text:SetWordWrap(true)
    f.text:SetJustifyH("LEFT")
    f:SetScript("OnDragStart", function(self)
        if not (HME.settings and HME.settings.hudLocked) then self:StartMoving() end
    end)
    f:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local pt, _, rel, x, y = self:GetPoint()
        if HME.char then HME.char.ui.skinLevels = { pt, rel, x, y } end
    end)
    f:SetScript("OnMouseUp", function(_, button)
        if button == "RightButton" then ST.Toggle(false) end
    end)
    T.Tooltip(f, "Skinning levels", "Which beast levels give Skinning points now, from your skill; it updates as you skin. "
        .. "Beasts named for the zone are where they appear (bundled data), not live targets. Drag to move; right-click or "
        .. "/hme skinlevels to hide.")
    local pos = HME.char and HME.char.ui and HME.char.ui.skinLevels
    if type(pos) == "table" and pos[1] then
        f:ClearAllPoints()
        f:SetPoint(pos[1], UIParent, pos[2], pos[3], pos[4])
    end
end

function ST.Shown() return f ~= nil and f:IsShown() end

function ST.Update()
    local on = HME.settings and HME.settings.skinLevels
    local lines = on and ST.Lines()
    if not lines then
        if f then f:Hide() end
        return
    end
    if not f then Build() end
    f.text:SetText(table.concat(lines, "\n"))
    f:SetHeight(26 + (f.text:GetStringHeight() or (#lines * 12)))
    f:Show()
end

function ST.Toggle(on)
    if not HME.settings then return end
    if on == nil then on = not HME.settings.skinLevels end
    HME.settings.skinLevels = on and true or false
    ST.Update()
    if on and not ST.Lines() then HME.Print("Skinning levels: this character doesn't know Skinning.") end
end

-- A higher level became skinnable: say so once.
local function Announce()
    local sk = HME.Player.Professions().Skinning
    if not (sk and HME.char) then return end
    local top = SM.MaxSkinLevel(sk.rank)
    local before = HME.char.skinMaxLevel
    HME.char.skinMaxLevel = top
    if before and top > before and HME.settings and HME.settings.skinLevels then
        HME.Print(("Skinning %d: you can now skin level %d beasts."):format(sk.rank, top))
    end
end

HME.Listen("PLAYER_CHANGED", function() Announce() ST.Update() end)
for _, event in ipairs({ "PLAYER_TARGET_CHANGED", "PLAYER_LEVEL_UP", "ZONE_CHANGED_NEW_AREA", "PLAYER_ENTERING_WORLD" }) do
    HME.On(event, function() ST.Update() end)
end
