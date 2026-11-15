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

-- Your target: { level, color, req, why, name, fight, known } or nil when
-- there is nothing to say. Three different questions, kept apart:
--   color/req  can this level be skinned at your skill, and is it a point
--              (the game's colours; a guide, not a promise per skin);
--   fight      can you reasonably kill it: its level against yours, elite;
--   known      is this creature skinnable at all: you skinned it ("you"),
--              the bundled beast list has it ("data"), or neither ("unknown":
--              plenty of beasts give no skin, and level alone never says).
function ST.Target(skill)
    if not (UnitExists and UnitExists("target")) then return nil end
    if UnitIsPlayer and UnitIsPlayer("target") then return nil end
    local level = HME.Num(UnitLevel and UnitLevel("target"))
    if not level then return nil end
    local name = UnitName and HME.Str((UnitName("target"))) or nil
    local npc
    if UnitGUID and HME.Learning and HME.Learning.NpcIDFromGUID then
        local ok, guid = pcall(UnitGUID, "target")
        npc = ok and HME.Learning.NpcIDFromGUID(guid) or nil
    end
    local known = "unknown"
    local rec = npc and HME.db and HME.db.obs and HME.db.obs.skins and HME.db.obs.skins[npc]
    if rec and (rec.n or 0) > 0 then known = "you"
    elseif npc and HME.Learning.Npc and HME.Learning.Npc(npc) then known = "data" end
    local classif = UnitClassification and HME.Str(UnitClassification("target")) or nil
    local elite = classif == "elite" or classif == "rareelite" or classif == "worldboss"
    if level < 1 then
        return { level = "??", color = "red", why = "far above you", name = name, fight = "no", known = known, skins = rec and rec.n }
    end
    local req = SM.SkinReq(level)
    local mine = HME.Player.Level and HME.Player.Level() or level
    local diff = level - mine
    local fight = (elite and diff > -6) and "elite" or (diff >= 5 and "no" or (diff >= 3 and "risky" or "yes"))
    return { level = level, color = SM.Color(skill, req), req = req, name = name, fight = fight, known = known,
        skins = rec and rec.n, elite = elite }
end
ST.FIGHT_SAYS = { yes = "you can fight it", risky = "risky: a few levels above you", no = "too strong for you",
    elite = "elite: bring help" }
ST.KNOWN_SAYS = { you = "skinnable: you skinned it", data = "skinnable: in the beast list",
    unknown = "not in the beast list: may give no skin" }

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
    add(("|cfff2f0e6Skinning %d|r |cff999b8f/ %d|r"):format(skill, max or 0))
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
        add(("|cff999b8fOrange goes up to %d; above %d is too high for you now.|r"):format(bands.orange[2], safe))
    end
    if bands.greyTo then add(("|cff999b8fLevel %d and below: no points.|r"):format(bands.greyTo)) end
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
        add(("|cff999b8f%s: no beast in those levels in the bundled data.|r"):format(zoneName))
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
local function K_Paint(text, hex) return "|cff" .. hex .. text .. "|r" end
local f
local W = 264
local STRIP_MAX = 28

-- What the box shows, as data (ST.Lines is the same as text).
function ST.Model()
    local profile = HME.Player.Profile()
    local sk = profile.skills and profile.skills.Skinning
    if not sk then return nil end
    local skill, max = sk.rank, sk.max
    local bands = ST.Bands(skill)
    local safe = ST.SafeLevel(profile)
    local m = { skill = skill, max = max, bands = bands, safe = safe, picks = {} }
    for _, c in ipairs({ "orange", "yellow", "green" }) do
        local b = bands[c] and Cut(bands[c], safe)
        if b and #m.picks < 2 then m.picks[#m.picks + 1] = { range = b, color = c, say = ST.SAYS[c] } end
    end
    if bands.orange and bands.orange[2] > safe then
        m.cap = ("Orange goes up to %d; above %d is too high for you now."):format(bands.orange[2], safe)
    end
    local nextLevel, req, away = ST.Next(skill)
    if nextLevel then m.next = { level = nextLevel, req = req, away = away, train = max and req > max } end
    local zone = profile.mapID and HME.Geo.ZoneOf(profile.mapID)
    m.zoneName = (zone and HME.ZoneData.Name(zone)) or "this zone"
    m.here = ST.ZoneBeasts(zone, skill, safe)
    if #m.here == 0 then m.elsewhere = ST.Elsewhere(zone, skill, safe) end
    m.target = ST.Target(skill)
    return m
end

local function Build()
    f = CreateFrame("Frame", "HarvestMateEnhancedSkinLevels", UIParent)
    f:SetSize(W, 120)
    -- Beside the farming HUD by default (0.3.0 put it under the HUD's box).
    f:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", -500, -190)
    f:SetFrameStrata("MEDIUM")
    f:SetClampedToScreen(true)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f.shadow = T.Shadow(f, 10)
    T.Panel(f, 0.9)
    f.head = CreateFrame("Frame", nil, f)
    f.head:SetPoint("TOPLEFT", 0, -2)
    f.head:SetPoint("TOPRIGHT", 0, -2)
    f.head:SetHeight(18)
    T.HeaderStrip(f.head, "Skinning")
    f.head.logo:SetTexture("Interface\\Icons\\INV_Misc_Pelt_Wolf_01")
    f.head.logo:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    f.close = T.FlatButton(f.head, "×", 22, 20, "ghost")
    f.close:SetPoint("RIGHT", -4, 0)
    f.close:SetScript("OnClick", function() ST.Toggle(false) end)
    T.Tooltip(f.close, "Hide", "Open it again from the Dashboard's Skinning card, the Skinning leveling guide, "
        .. "Shift-click on the minimap button, a key binding, or /hme sl.")
    f.skill = T.Text(f.head, "", "strong", nil, 11)
    -- Compact or full: the chevron beside the close button (Settings too).
    f.size = T.FlatButton(f.head, "", 22, 20, "ghost")
    f.size:SetPoint("RIGHT", f.close, "LEFT", -2, 0)
    f.size.arrow = T.MenuArrow(f.size, 5)
    f.size:SetScript("OnClick", function()
        HME.settings.skinLevelsCompact = not HME.settings.skinLevelsCompact
        ST.Update()
    end)
    T.Tooltip(f.size, "Compact or full", "Compact keeps your skill, the highest level, the best levels, the next unlock "
        .. "and your target; full adds the level strip and this zone's beasts.")
    f.skill:SetPoint("RIGHT", f.size, "LEFT", -4, 0)
    f.skill:SetJustifyH("RIGHT")

    -- Two big numbers: the highest level you can skin, and the levels to kill.
    local half = (W - 20) / 2
    f.maxLabel = T.Text(f, "Highest level", "label", nil, 11)
    f.max = T.Text(f, "", "display", nil, 26)
    f.max:SetWordWrap(false)
    f.maxSay = T.Text(f, "you can skin", "meta", nil, 11)
    f.killLabel = T.Text(f, "Best levels", "label", nil, 11)
    f.kill = T.Text(f, "", "display", nil, 26)
    f.kill:SetWordWrap(false)
    f.killSay = T.Text(f, "", "meta", nil, 11)
    f.killSay:SetWidth(half - 4)
    f.killSay:SetWordWrap(false)
    f.half = half
    f.alt = T.Text(f, "", "small")
    f.cap = T.Text(f, "", "meta")
    f.cap:SetWidth(W - 20)
    f.cap:SetWordWrap(true)

    -- A strip of level cells, coloured by what a skin there gives you.
    f.strip = CreateFrame("Frame", nil, f)
    f.strip:SetSize(W - 20, 8)
    f.cells = {}
    for i = 1, STRIP_MAX do
        local c = f.strip:CreateTexture(nil, "ARTWORK")
        c:SetHeight(8)
        f.cells[i] = c
    end
    f.stripLo = T.Text(f, "", "meta", nil, 11)
    f.stripHi = T.Text(f, "", "meta", nil, 11)
    f.stripHi:SetJustifyH("RIGHT")

    f.next = T.Text(f, "", "small")
    f.next:SetWidth(W - 20)
    f.next:SetWordWrap(false)
    f.nextBar = HME.Kit.Bar(f, W - 20, 4)
    f.nextBar.text:Hide()

    f.divider = f:CreateTexture(nil, "BORDER")
    f.divider:SetHeight(1)
    f.divider:SetColorTexture(unpack(T.C.line))
    f.zone = T.Text(f, "", "label", nil, 11)
    f.zone:SetWidth(W - 20)
    f.zone:SetWordWrap(false)
    f.places = T.Text(f, "", "small")
    f.places:SetWidth(W - 20)
    f.places:SetWordWrap(true)
    f.target = T.Text(f, "", "small")
    f.target:SetWidth(W - 20)
    f.target:SetWordWrap(false)
    f.target2 = T.Text(f, "", "meta")
    f.target2:SetWidth(W - 20)
    f.target2:SetWordWrap(true)

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
        .. "The strip runs from no points (grey) to too high to skin (red). Beasts named for the zone are where they "
        .. "appear (bundled data), not live targets. Drag to move; right-click or /hme sl to hide.")
    local pos = HME.char and HME.char.ui and HME.char.ui.skinLevels
    if type(pos) == "table" and pos[1] then
        f:ClearAllPoints()
        f:SetPoint(pos[1], UIParent, pos[2], pos[3], pos[4])
    end
end

function ST.Shown() return f ~= nil and f:IsShown() end

-- Everything the box shows now, as plain text (tests and /hme sl print).
function ST.Text()
    if not (f and f:IsShown()) then return "" end
    local parts = {}
    for _, fs in ipairs({ f.skill, f.maxLabel, f.max, f.maxSay, f.killLabel, f.kill, f.killSay, f.alt, f.cap, f.stripLo, f.stripHi, f.next, f.zone, f.places, f.target, f.target2 }) do
        if fs:IsShown() and (fs:GetText() or "") ~= "" then parts[#parts + 1] = fs:GetText() end
    end
    return table.concat(parts, "\n")
end

local function Place(fs, y, x)
    fs:ClearAllPoints()
    fs:SetPoint("TOPLEFT", x or 10, y)
end

function ST.Update()
    local on = HME.settings and HME.settings.skinLevels
    local m = on and ST.Model()
    if not m then
        if f then f:Hide() end
        return
    end
    if not f then Build() end
    local y = -28
    f.skill:SetText(("%d |cff999b8f/ %d|r"):format(m.skill, m.max or 0))

    -- The highest level you can skin, and what to kill
    local col2 = 10 + f.half
    Place(f.maxLabel, y)
    Place(f.killLabel, y, col2)
    y = y - 16
    f.max:SetText(tostring(m.bands.maxLevel))
    f.max:SetTextColor(T.C.text[1], T.C.text[2], T.C.text[3])
    Place(f.max, y)
    local first, second = m.picks[1], m.picks[2]
    if first then
        f.kill:SetText(Range(first.range))
        local c = SM.COLORS[first.color]
        f.kill:SetTextColor(c[1], c[2], c[3])
        f.killSay:SetText(first.say)
    else
        f.kill:SetText("–")
        f.kill:SetTextColor(T.C.text3[1], T.C.text3[2], T.C.text3[3])
        f.killSay:SetText("nothing you can fight gives points")
    end
    Place(f.kill, y, col2)
    y = y - 30
    Place(f.maxSay, y)
    Place(f.killSay, y, col2)
    y = y - 18
    local compact = HME.settings and HME.settings.skinLevelsCompact
    f.alt:SetShown(second ~= nil and not compact)
    if second and not compact then
        f.alt:SetText(("%s  %s"):format(Paint(second.color, "or " .. Range(second.range)), K_Paint(second.say, T.HEX.text2)))
        Place(f.alt, y)
        y = y - 16
    end
    f.cap:SetShown(m.cap ~= nil and not compact)
    if m.cap and not compact then
        f.cap:SetText(m.cap)
        Place(f.cap, y)
        y = y - (f.cap:GetStringHeight() or 12) - 4
    end

    -- The strip: from a little below the first band that gives points to a little above what you can skin.
    local b = m.bands
    local lo = math.max(1, ((b.green and b.green[1]) or (b.yellow and b.yellow[1]) or (b.orange and b.orange[1]) or 1) - 2)
    local hi = math.min(ST.MAX_LEVEL, b.maxLevel + 3)
    if hi - lo + 1 > STRIP_MAX then lo = hi - STRIP_MAX + 1 end
    local n = hi - lo + 1
    local gap = 1
    local cw = ((W - 20) - (n - 1) * gap) / n
    f.strip:SetShown(not compact)
    f.stripLo:SetShown(not compact)
    f.stripHi:SetShown(not compact)
    if not compact then
    y = y - 6
    f.strip:ClearAllPoints()
    f.strip:SetPoint("TOPLEFT", 10, y)
    for i, cell in ipairs(f.cells) do
        local level = lo + i - 1
        if i <= n then
            local c = SM.Color(m.skill, SM.SkinReq(level))
            local rgb = SM.COLORS[c] or SM.COLORS.grey
            cell:ClearAllPoints()
            cell:SetPoint("TOPLEFT", (i - 1) * (cw + gap), 0)
            cell:SetWidth(cw)
            cell:SetColorTexture(rgb[1], rgb[2], rgb[3], level > m.safe and 0.35 or 0.95)
            cell:Show()
        else
            cell:Hide()
        end
    end
    y = y - 11
    f.stripLo:SetText(("level %d"):format(lo))
    Place(f.stripLo, y)
    f.stripHi:SetText(("%d"):format(hi))
    f.stripHi:ClearAllPoints()
    f.stripHi:SetPoint("TOPRIGHT", -10, y)
    y = y - 18
    end

    -- The next unlock
    if m.next then
        if m.next.train then
            f.next:SetText(("Level %d needs %d Skinning: %s"):format(m.next.level, m.next.req,
                K_Paint(("train first (your cap is %d)"):format(m.max), T.HEX.warning)))
            f.nextBar:Hide()
        else
            f.next:SetText(("Next: level %d at %d Skinning %s"):format(m.next.level, m.next.req, K_Paint(("(+%d)"):format(m.next.away), T.HEX.accent)))
            local from = SM.SkinReq(m.next.level - 1)
            f.nextBar:Set(m.skill - from, m.next.req - from, T.C.accent, "", math.max(1, m.next.req - from))
            f.nextBar:Show()
        end
        Place(f.next, y)
        y = y - 16
        if f.nextBar:IsShown() then
            f.nextBar:ClearAllPoints()
            f.nextBar:SetPoint("TOPLEFT", 10, y)
            y = y - 10
        end
        f.next:Show()
    else
        f.next:Hide()
        f.nextBar:Hide()
    end

    -- Where (full only)
    f.divider:SetShown(not compact)
    f.zone:SetShown(not compact)
    f.places:SetShown(not compact)
    if not compact then
    y = y - 4
    f.divider:ClearAllPoints()
    f.divider:SetPoint("TOPLEFT", 10, y)
    f.divider:SetPoint("TOPRIGHT", -10, y)
    y = y - 9
    local lines = {}
    local function Name(e) return Paint(e.color, ("%s %s"):format(e.name, e.min == e.max and e.min or (e.min .. "-" .. e.max))) end
    if #m.here > 0 then
        f.zone:SetText(m.zoneName)
        for i = 1, math.min(ST.ZONE_BEASTS, #m.here) do lines[#lines + 1] = Name(m.here[i]) end
    else
        f.zone:SetText(m.zoneName .. ": none in range, the closest")
        for _, z in ipairs(m.elsewhere or {}) do
            lines[#lines + 1] = ("%s  %s"):format(z.name, K_Paint("· " .. HME.U.Duration(z.secs), T.HEX.text3))
            lines[#lines + 1] = "   " .. Name(z.best)
        end
        if #lines == 0 then lines[1] = K_Paint("No beast in those levels in the bundled data.", T.HEX.text3) end
    end
    Place(f.zone, y)
    y = y - 14
    f.places:SetText(table.concat(lines, "\n"))
    Place(f.places, y)
    y = y - (f.places:GetStringHeight() or (#lines * 13)) - 6
    end

    -- Your target
    local t = m.target
    f.target:SetShown(t ~= nil)
    f.target2:SetShown(t ~= nil)
    if t then
        local say = t.why or (t.color == "red" and ("needs %d Skinning"):format(t.req)) or (t.color == "grey" and "no points")
            or ST.SAYS[t.color] or ""
        f.target:SetText(("%s  %s  %s"):format(Paint(t.color, t.name or "Target"), K_Paint("level " .. t.level, T.HEX.text2),
            K_Paint(say, T.HEX.text2)))
        Place(f.target, y)
        y = y - 17
        local fightHex = (t.fight == "yes") and T.HEX.text3 or T.HEX.warning
        local knownHex = (t.known == "unknown") and T.HEX.warning or T.HEX.text3
        f.target2:SetText(K_Paint(ST.FIGHT_SAYS[t.fight or "yes"] or "", fightHex) .. "  ·  "
            .. K_Paint(ST.KNOWN_SAYS[t.known or "unknown"] or "", knownHex))
        Place(f.target2, y)
        y = y - (f.target2:GetStringHeight() or 14) - 4
    end
    f:SetHeight(-y + 6)
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
