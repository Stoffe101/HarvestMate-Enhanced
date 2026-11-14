-- HarvestMate Enhanced: Glimmer/Glue.lua
-- Hosts Gatherpedia's Glimmer (Sparkles.lua + the cloud renderer in
-- SparklesCloud.lua) inside HME:
--   * its settings live in HarvestMateEnhancedDB.gp.sparkle (ns.db.sparkle)
--   * its settings page is HME's (UI/PageSettings.lua, Glimmer section); the
--     calls Sparkles makes to its old page land here
--   * while Gatherpedia itself is enabled, HME's Glimmer stays off
--   * HarvestMate's nameplate marker and Glimmer both use the soft-target
--     nameplate; HME keeps the marker off by default so they don't stack
-- Copyright (C) 2026 HarvestMate Enhanced contributors. GPL-3.0-or-later.

local _, ns = ...
local HME = ns.HME
local SUI = ns.SparklesUI

-- The parts of SparklesUI's page Sparkles.lua calls.
if SUI then
    function SUI:Refresh() HME.Signal("UI_REFRESH") end
    function SUI:RefreshTab() HME.Signal("UI_REFRESH") end
    function SUI:Show() if HME.OpenWindow then HME.OpenWindow("settings", "glimmer") end end
    function SUI:Toggle() self:Show() end
    function SUI:Attach() end
    function SUI:ShowDebugPanel()
        local S = ns.Sparkles
        if S and S.DebugLines then
            for _, line in ipairs(S:DebugLines() or {}) do HME.Print(line) end
        end
    end
end
ns.UI = ns.UI or {}
function ns.UI.ShowGlimmer() if HME.OpenWindow then HME.OpenWindow("settings", "glimmer") end end

HME.Listen("DB_READY", function()
    ns.db.sparkle = type(ns.db.sparkle) == "table" and ns.db.sparkle or {}
    local S = ns.Sparkles
    if S then
        if S.MigrateOpts then pcall(S.MigrateOpts, S, ns.db.sparkle) end
        if ns.CopySparkleDefaults then ns.CopySparkleDefaults(ns.db.sparkle) end
    end
end)

-- Glimmer is on unless the player turned it off, and off while Gatherpedia runs.
function HME.GlimmerAvailable()
    return ns.Sparkles ~= nil and not (HME.Paused and HME.Paused("gatherpedia"))
end

-- Gatherpedia started Glimmer from its own login handler; HME does it here,
-- and not at all while Gatherpedia runs (its own copy does the job then; the
-- saved on/off choice is left as it is).
HME.On("PLAYER_LOGIN", function()
    local S = ns.Sparkles
    if not S then return end
    if HME.GlimmerAvailable() then
        S:OnLogin()
    else
        HME.glimmerPaused = true
    end
end)

function HME.SetGlimmer(on)
    local S = ns.Sparkles
    if not (S and HME.GlimmerAvailable()) then return false end
    if HME.InCombat() then
        HME.Print("Glimmer changes game settings, so it waits until the fight is over.")
        return false
    end
    return S:SetEnabled(on)
end
