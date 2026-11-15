-- HarvestMate Enhanced: Map/Arrow.lua
-- HME's on-screen arrow: points to the next stop of the farm being followed
-- (or to the farm itself when there is no Forever-GPS). Only Map/Guidance.lua
-- shows it, and never while Forever-GPS (or TomTom) owns the navigation, so
-- there are never two arrows.
--
-- The art is Gatherpedia's (Media/GP_Arrow3D: 64 pre-rendered headings in an
-- 8 x 8 sheet, GPL-3.0); the heading math follows its Arrow.lua: bearing from
-- map or world positions, minus GetPlayerFacing, counter-clockwise.
-- Shift-drag moves it; right-click hides it until the next stop.
-- Copyright (C) 2026 HarvestMate Enhanced contributors. GPL-3.0-or-later.

local _, ns = ...
local HME = ns.HME
local T = ns.Theme
local U = HME.U

local A = {}
HME.Arrow = A

local TEX = "Interface\\AddOns\\HarvestMateEnhanced\\Media\\GP_Arrow3D"
local PI2 = math.pi * 2
local FRAMES, COLS, SHEET = 64, 8, 1024

local frame
A.target = nil   -- { mapID, x, y, label }

function A.FrameIndex(angle)
    local a = (angle or 0) % PI2
    if a < 0 then a = a + PI2 end
    return math.floor(a / PI2 * FRAMES + 0.5) % FRAMES
end

local function SetFrame(tex, angle)
    local i = A.FrameIndex(angle)
    local col, row = i % COLS, math.floor(i / COLS)
    local inset = 1 / SHEET
    tex:SetTexCoord(col / COLS + inset, (col + 1) / COLS - inset, row / COLS + inset, (row + 1) / COLS - inset)
end

-- World position (instance, x north, y west) of a map point.
local function WorldXY(mapID, x, y)
    if not (C_Map and C_Map.GetWorldPosFromMapPos and CreateVector2D and mapID and x) then return nil end
    local ok, inst, pos = pcall(C_Map.GetWorldPosFromMapPos, mapID, CreateVector2D(x, y))
    if not ok or not pos or not pos.GetXY then return nil end
    local wx, wy = pos:GetXY()
    if not (HME.Num(wx) and HME.Num(wy)) then return nil end
    return inst, wx, wy
end
A.WorldXY = WorldXY

-- Distance (yards) and heading (radians, 0 = ahead, counter-clockwise) from
-- the player to the target, or nil when unknown.
function A.Measure(target)
    local mapID, px, py = HME.Player.Position()
    if not (mapID and px and target) then return nil end
    local facing = GetPlayerFacing and HME.Num((select(2, pcall(GetPlayerFacing))))
    -- Same map: map space in yards (x east, y south).
    local zMap, zx, zy = HME.Geo.ZoneOf(mapID, px, py)
    local tMap = target.mapID
    if (mapID == tMap or zMap == tMap) and zx then
        local fx, fy = (mapID == tMap) and px or zx, (mapID == tMap) and py or zy
        local w, h = HME.Geo.MapYards(tMap)
        w, h = w or 1500, h or 1000
        local ax, ay, bx, by = fx * w, fy * h, target.x * w, target.y * h
        local dist = U.Dist(ax, ay, bx, by)
        local bearing = math.atan2(ax - bx, ay - by)
        return dist, facing and ((bearing - facing) % PI2) or nil
    end
    -- Different maps: world positions, when both are in the same instance.
    local i1, wx1, wy1 = WorldXY(mapID, px, py)
    local i2, wx2, wy2 = WorldXY(tMap, target.x, target.y)
    if i1 and i2 and i1 == i2 then
        local dist = U.Dist(wx1, wy1, wx2, wy2)
        local bearing = math.atan2(wy2 - wy1, wx2 - wx1)
        return dist, facing and ((bearing - facing) % PI2) or nil
    end
    return nil
end

local function Build()
    frame = CreateFrame("Frame", "HarvestMateEnhancedArrow", UIParent)
    frame:SetSize(72, 92)
    frame:SetPoint("CENTER", UIParent, "CENTER", 0, 210)
    frame:SetFrameStrata("MEDIUM")
    frame:SetMovable(true)
    frame:SetClampedToScreen(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", function(self) if IsShiftKeyDown() then self:StartMoving() end end)
    frame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local pt, _, rel, x, y = self:GetPoint()
        if HME.char then HME.char.ui.arrow = { pt, rel, x, y } end
    end)
    frame:SetScript("OnMouseUp", function(_, button)
        if button == "RightButton" then
            A.snoozed = A.target
            frame:Hide()
        end
    end)
    frame.tex = frame:CreateTexture(nil, "ARTWORK")
    frame.tex:SetSize(64, 64)
    frame.tex:SetPoint("TOP")
    frame.tex:SetTexture(TEX)
    frame.dist = T.Text(frame, "", "GameFontNormal", T.C.gold)
    frame.dist:SetPoint("TOP", frame.tex, "BOTTOM", 0, 2)
    frame.dist:SetJustifyH("CENTER")
    frame.label = T.Text(frame, "", "GameFontHighlightSmall")
    frame.label:SetPoint("TOP", frame.dist, "BOTTOM", 0, -1)
    frame.label:SetJustifyH("CENTER")
    T.Tooltip(frame, "HarvestMate Enhanced", "Points to your next stop. Shift-drag to move; right-click to hide until the next stop.")
    local pos = HME.char and HME.char.ui.arrow
    if type(pos) == "table" and pos[1] then
        frame:ClearAllPoints()
        frame:SetPoint(pos[1], UIParent, pos[2], pos[3], pos[4])
    end
    local acc = 0
    frame:SetScript("OnUpdate", function(self, dt)
        acc = acc + dt
        if acc < 0.05 then return end
        acc = 0
        A.Update()
    end)
    frame:Hide()
end

function A.Update()
    if not (frame and A.target) then return end
    local dist, angle = A.Measure(A.target)
    local scale = (HME.settings and HME.settings.arrowScale) or 1
    frame:SetScale(scale)
    if dist then
        frame.dist:SetText(dist >= 1000 and ("%.1fk yd"):format(dist / 1000) or (math.floor(dist + 0.5) .. " yd"))
        if angle then SetFrame(frame.tex, angle) end
        frame.tex:SetAlpha(angle and 1 or 0.4)
    else
        frame.dist:SetText("?")
        frame.tex:SetAlpha(0.4)
    end
    if A.onUpdate then A.onUpdate(dist) end
end

-- Shows the arrow toward a target; nil hides it.
function A.Point(target, label)
    if not frame then Build() end
    A.target = target
    if not target or (HME.settings and HME.settings.arrow == false) then
        frame:Hide()
        return
    end
    if A.snoozed and A.snoozed ~= target then A.snoozed = nil end
    frame.label:SetText(label or target.label or "")
    if not A.snoozed then frame:Show() end
    A.Update()
end

-- Minimal-assistance mode: faint while you are on the loop, full when you stray.
function A.Dim(on)
    if frame then frame:SetAlpha(on and 0.35 or 1) end
end

function A.Hide()
    A.target = nil
    if frame then frame:Hide() end
end

function A.Shown() return frame ~= nil and frame:IsShown() end
