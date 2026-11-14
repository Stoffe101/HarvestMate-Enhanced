-- HarvestMate Enhanced: Gather/HGCore.lua
-- The core HarvestMate's vendored modules (Gather/*.lua) expect at ns.HG:
-- secret-value guards, its event bus and signals, its saved-data shape, chat,
-- CVar helpers and the Soft Target Interact setup. Adapted from HarvestMate
-- 2.0.13 Core.lua by AndreiBerkut (MIT, see upstream/HarvestMate-2.0.13).
--
-- Changes from upstream (see UPSTREAM.md, "HarvestMate core"):
--  * events and signals run on HME's bus, so one frame serves every module;
--  * the saved data is a section of HarvestMateEnhancedDB (HME.db.hm), not
--    HarvestMateDB; Core/Migrate.lua copies an old HarvestMateDB in once;
--  * defaults that change the player's controls or speak in chat start OFF
--    and are offered with an explanation (gather key, click-to-move, auto
--    loot, party/emote announcements); the nameplate marker defers to Glimmer;
--  * no ADDON_LOADED or slash commands of its own (HME owns /hme and /hm).

local _, ns = ...
local HME = ns.HME
local HG = {}
ns.HG = HG

HG.addon = HME.ADDON
HG.title = HME.TITLE

HG.Hidden, HG.Str, HG.Num, HG.Tbl = HME.Hidden, HME.Str, HME.Num, HME.Tbl

-- HarvestMate handlers take the event's arguments without its name.
function HG.On(event, handler, unit)
    HME.On(event, function(_, ...) handler(...) end, unit)
end
HG.Listen = HME.Listen
HG.Signal = HME.Signal
HG.Soon = HME.Soon

HG.DEFAULTS = {
    enabled = true,
    herb = true,
    mine = true,
    skin = true,
    showOwn = true,
    showReq = true,
    colorize = true,
    chatLearn = false,
    trackWarn = true,
    treasureWarn = true,
    trainWarn = true,
    lock = true,
    showBands = true,
    showLoot = true,
    showPrices = true,
    profit = true,
    cultivation = true,
    itemTips = true,
    nearby = true,
    nearbySound = true,
    marker = false,        -- HME: Glimmer's node icon does this job; on only if asked
    announceParty = false, -- HME: speaking in group chat is opt-in
    announceEmote = false, -- HME: and so is the emote
    gatherKey = false,     -- HME: the one-key gather binding needs the player's yes first
    gatherMove = false,    -- HME: never turns on click-to-move unasked
    gatherLoot = false,    -- HME: never turns on auto loot unasked
    gearWarn = true,
    gearSwap = false,
    achToast = true,
    achSound = true,
    achGuild = false,
    gatherKeyBind = "F",
    minimap = false,       -- HME has one minimap button for everything
    fontSize = 18,
    debug = false,
}

local function Section(root, key)
    if type(root[key]) ~= "table" then root[key] = {} end
    return root[key]
end

function HG.PrepareDB(saved)
    if type(saved) ~= "table" then saved = {} end
    local opt = Section(saved, "opt")
    for key, value in pairs(HG.DEFAULTS) do
        if type(opt[key]) ~= type(value) then opt[key] = value end
    end
    local learned = Section(saved, "learned")
    Section(learned, "lowest")
    Section(learned, "custom")
    Section(learned, "skinnable")
    Section(learned, "skinFamily")
    Section(learned, "drops")
    Section(learned, "objects")
    Section(learned, "spells")
    Section(saved, "banner")
    if type(saved.angle) ~= "number" then saved.angle = 215 end
    saved.schema = 1
    return saved
end

function HG.ResetOptions()
    local opt = HG.db.opt
    for key, value in pairs(HG.DEFAULTS) do opt[key] = value end
    HG.db.banner = {}
    HG.Signal("OPTIONS")
end

function HG.ForgetLearned()
    HG.db.learned = nil
    HG.PrepareDB(HG.db)
    HG.Signal("LEARNED")
end

function HG.Active()
    return HG.db ~= nil and HG.db.opt.enabled
end

function HG.Say(text) HME.Print(text) end

function HG.Debug(...)
    if not (HG.db and HG.db.opt.debug) then return end
    local parts = {}
    for i = 1, select("#", ...) do parts[i] = tostring((select(i, ...))) end
    HME.Print("|cff999999" .. table.concat(parts, " ") .. "|r")
end

function HG.Learned(text)
    if HG.db and HG.db.opt.chatLearn then HG.Say(text) end
end

-- Called once by Core/DB.lua with the saved section.
-- While the original HarvestMate addon is also running, HME's copy reads its
-- settings as "disabled" (without saving that), so nothing runs twice.
function HG.Init(section)
    local saved = HG.PrepareDB(section)
    if HME.Paused and HME.Paused("harvestmate") then
        local opt = setmetatable({}, {
            __index = function(_, k)
                if k == "enabled" then return false end
                return saved.opt[k]
            end,
            __newindex = saved.opt,
        })
        HG.db = setmetatable({ opt = opt }, { __index = saved, __newindex = saved })
        HG.paused = true
    else
        HG.db = saved
    end
    HG.Signal("READY")
end

---------------------------------------------------------------------------
-- Commands (registered under /hme and, when HarvestMate itself is not
-- installed, /hm). Modules add to this table.
---------------------------------------------------------------------------
local commands = {}
HG.commands = commands

function commands.debug()
    HG.db.opt.debug = not HG.db.opt.debug
    HG.Say("debug " .. (HG.db.opt.debug and "on" or "off"))
end

function commands.skills()
    HG.ReadSkills()
    for _, prof in ipairs({ "herb", "mine", "skin" }) do
        local s = HG.SkillInfo(prof)
        if s then HG.Say(("%s: %d (%d/%d)"):format(HG.ProfName(prof), s.cur, s.base, s.max)) end
    end
end

---------------------------------------------------------------------------
-- Game settings (CVars). The modern client has C_CVar; old globals may be gone.
---------------------------------------------------------------------------
function HG.GetCVar(name)
    local get = (C_CVar and C_CVar.GetCVar) or _G.GetCVar
    if not get then return nil end
    local ok, value = pcall(get, name)
    return ok and value or nil
end

function HG.SetCVar(name, value)
    if HME.InCombat() then return false end
    local set = (C_CVar and C_CVar.SetCVar) or _G.SetCVar
    if not set then return false end
    local ok = pcall(set, name, value)
    return ok and HG.GetCVar(name) == tostring(value)
end

local SOFT = "SoftTargetInteract"

function HG.GamepadDevices()
    if not (C_GamePad and C_GamePad.GetAllDeviceIDs) then return nil end
    local ok, ids = pcall(C_GamePad.GetAllDeviceIDs)
    if not ok or type(ids) ~= "table" or HG.Hidden(ids) then return nil end
    local count = 0
    for _ in pairs(ids) do count = count + 1 end
    return count
end

function HG.GamepadMode()
    local enabled = false
    if C_GamePad and C_GamePad.IsEnabled then
        local ok, value = pcall(C_GamePad.IsEnabled)
        enabled = ok and not HG.Hidden(value) and value == true
    end
    if not enabled then enabled = HG.GetCVar("GamePadEnable") == "1" end
    if not enabled then return false end
    local devices = HG.GamepadDevices()
    return devices == nil or devices > 0
end

function HG.SoftTargetOn()
    local value = HG.GetCVar(SOFT)
    if value == "2" or value == "3" then return true end
    return value == "1" and HG.GamepadMode()
end

-- Turns Soft Target Interact on, remembering what it was. Only ever called
-- after the player said yes (the popup in Nearby.lua or /hme soft).
function HG.EnableSoftTarget()
    if HG.SoftTargetOn() then
        HG.db.softWanted = true
        return true
    end
    local before = HG.GetCVar(SOFT)
    if HG.SetCVar(SOFT, "3") then
        if HG.db.softBefore == nil then HG.db.softBefore = before end
        HG.db.softWanted = true
        return true
    end
    return false
end

function commands.soft(arg)
    if HME.InCombat() then
        HG.Say(HG.L.SOFT_COMBAT)
        return
    end
    if arg == "off" then
        HG.SetCVar(SOFT, HG.db.softBefore or "0")
        HG.db.softBefore = nil
        HG.db.softWanted = false
        HG.Say(HG.L.SOFT_OFF)
        return
    end
    if HG.EnableSoftTarget() then HG.Say(HG.L.SOFT_ON) else HG.Say(HG.L.SOFT_FAILED) end
    HG.Signal("OPTIONS")
end

function commands.near() HG.NearbyReport() end
function commands.reset()
    HG.ResetOptions()
    HG.Say(HG.L.RESET_DONE)
end
function commands.forget()
    HG.ForgetLearned()
    HG.Say(HG.L.FORGET_DONE)
end
function commands.config() if HME.OpenWindow then HME.OpenWindow("settings") end end

-- HarvestMate's own windows are replaced by HME's pages.
function HG.OpenSettings() if HME.OpenWindow then HME.OpenWindow("settings") end end
function HG.OpenHub(page) if HME.OpenWindow then HME.OpenWindow(page == "ach" and "stats" or "dashboard") end end
function HG.RefreshHub() HME.Signal("UI_REFRESH") end
