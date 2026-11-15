-- HarvestMate Enhanced: UI/WorldTip.lua
-- The soft-target tooltip of a node or a corpse (0.7.1). With Soft Target
-- Interact on, the game draws that tooltip next to the object: while skinning,
-- the middle of the screen. HarvestMate's lines (Gather/Tooltip.lua, kept as
-- upstream wrote it) made it seven lines tall there. Around HarvestMate's own
-- handler, without changing it:
--
--   * before it (a tooltip hook registered earlier, which runs first) HME notes
--     that a world tooltip is being filled, so HG.ExtraLines gives the short
--     form: how far to the next colour only (Settings: "... their HME lines",
--     Short or Full). The title keeps your numbers, as before;
--   * after it (a hook registered later) the tooltip is moved to the bottom
--     right corner, where other tooltips go, when it sits in the middle of the
--     screen (Settings: "Node and corpse tooltips": in the corner, where the
--     game puts it, or the game's soft-target tooltip off). A tooltip that
--     follows the cursor is left alone. Minimap tooltips keep everything.
--
-- Loads before Gather/Tooltip.lua so its first hook runs before HarvestMate's.
-- Copyright (C) 2026 HarvestMate Enhanced contributors. GPL-3.0-or-later.

local _, ns = ...
local HME = ns.HME
local HG = ns.HG

local W = {}
HME.WorldTip = W

local filling = false   -- a world (Object or Corpse) tooltip is being filled now
local recognised = false -- ... and HarvestMate knew what it is (a node or a beast)

local function S() return HME.settings or {} end
local function Num(v) return HME.Num(v) end

-- HarvestMate's extra lines, short while a world tooltip is filled.
local realExtra
local function ShortExtra(entry)
    if filling then recognised = true end
    if not (filling and S().worldTooltipDetail ~= "full") then return realExtra(entry) end
    local opt = HG.db and HG.db.opt or {}
    if entry.prof == "lock" or not opt[entry.prof] then return realExtra(entry) end
    local skill, req = HG.Skill(entry.prof), HG.Requirement(entry)
    local line = skill and req and HG.UntilNextLine and HG.UntilNextLine(skill, req)
    return line and { line } or {}
end
local function Wrap()
    if HG.ExtraLines and HG.ExtraLines ~= ShortExtra then
        realExtra = HG.ExtraLines
        HG.ExtraLines = ShortExtra
    end
end

-- Moves a tooltip that sits in the middle of the screen to the corner.
function W.MoveAside(tooltip)
    if not tooltip or (S().worldTooltipPlace or "corner") ~= "corner" then return false end
    local anchor = tooltip.GetAnchorType and HME.Str(tooltip:GetAnchorType())
    if anchor and anchor:find("CURSOR") then return false end
    local x, y = tooltip:GetCenter()
    x, y = Num(x), Num(y)
    local w, h = Num(UIParent:GetWidth()), Num(UIParent:GetHeight())
    if not (x and y and w and h) then return false end
    if x < w * 0.25 or x > w * 0.75 or y < h * 0.2 or y > h * 0.8 then return false end
    tooltip:ClearAllPoints()
    tooltip:SetPoint("BOTTOMRIGHT", UIParent, "BOTTOMRIGHT", -(Num(_G.CONTAINER_OFFSET_X) or 0) - 13, Num(_G.CONTAINER_OFFSET_Y) or 70)
    return true
end

local function MoveAsideSoon(tooltip)
    if W.MoveAside(tooltip) or not (C_Timer and C_Timer.After) then return end
    -- (the game may place it after the hooks: look again on the next frame)
    C_Timer.After(0, function()
        if tooltip:IsShown() then W.MoveAside(tooltip) end
    end)
end

-- The game's soft-target tooltip for nodes and corpses, on or off (what it was
-- is remembered). Only from Settings.
local SOFT_TIP = "SoftTargetTooltipInteract"
function W.SetSoftTooltip(on)
    local db = HME.db
    if not db then return false end
    if on then
        local before = db.softTipBefore
        db.softTipBefore = nil
        return HG.SetCVar(SOFT_TIP, before or "1")
    end
    local now = HG.GetCVar(SOFT_TIP)
    if now == "0" then return true end
    if HG.SetCVar(SOFT_TIP, "0") then
        if db.softTipBefore == nil then db.softTipBefore = now end
        return true
    end
    return false
end

-- The hooks: before HarvestMate's (now, this file loads first) and after it
-- (at login, once every file has registered its own).
local kinds = Enum and Enum.TooltipDataType
local WORLD = kinds and { kinds.Object, kinds.Corpse } or {}
if TooltipDataProcessor and kinds then
    for _, kind in ipairs(WORLD) do
        TooltipDataProcessor.AddTooltipPostCall(kind, function()
            Wrap()
            filling, recognised = true, false
        end)
    end
end
local after = false
function W.HookAfter()
    if after or not (TooltipDataProcessor and kinds) then return end
    after = true
    for _, kind in ipairs(WORLD) do
        TooltipDataProcessor.AddTooltipPostCall(kind, function(tooltip)
            local known = filling and recognised
            filling, recognised = false, false
            -- Only tooltips of nodes and beasts HarvestMate knows (a mailbox's stays put).
            if known and tooltip then HME.Try(MoveAsideSoon, tooltip) end
        end)
    end
end
HME.On("PLAYER_LOGIN", function() W.HookAfter() end)
