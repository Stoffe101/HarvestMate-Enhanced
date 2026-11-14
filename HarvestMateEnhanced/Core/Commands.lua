-- HarvestMate Enhanced: Core/Commands.lua
-- /hme (and /harvestmateenhanced). HarvestMate's /hm and Gatherpedia's /gp
-- are answered too, but only while those addons are not installed, so
-- nothing is ever registered twice. Key bindings: Bindings.xml.
-- Copyright (C) 2026 HarvestMate Enhanced contributors. GPL-3.0-or-later.

local _, ns = ...
local HME = ns.HME

local cmds = {}
HME.Commands = cmds

local function Help()
    HME.Print("commands:")
    local lines = {
        "/hme  open or close the window",
        "/hme finder | guides | materials | stats | trainers | routes | settings  open a page",
        "/hme farm skin|herb|mine|fish [level|profit]  open the Farm Finder on it",
        "/hme stop  stop following the farm   ·   /hme nav  navigate to it",
        "/hme session start|pause|end   ·   /hme hud  show or hide the HUD",
        "/hme glimmer [on|off|preview]   ·   /hme soft [off]   ·   /hme key [KEY]",
        "/hme export  ·  /hme import <name>  copy data from HarvestMate/Gatherpedia/GatherPath",
        "/hme diag  report addons, data and timings",
        "HarvestMate's: /hme skills, next, bags, near, tip, ach, test",
    }
    for _, l in ipairs(lines) do print("  " .. l) end
end
cmds.help = Help

local PAGES = { finder = "finder", farm = "finder", guides = "guides", guide = "guides", materials = "materials",
    mats = "materials", stats = "stats", profit = "stats", trainers = "trainers", routes = "routes",
    settings = "settings", options = "settings", config = "settings", dashboard = "dashboard" }
local PROF = { herb = "Herbalism", herbs = "Herbalism", herbalism = "Herbalism", mine = "Mining", mining = "Mining",
    ore = "Mining", skin = "Skinning", skinning = "Skinning", fish = "Fishing", fishing = "Fishing" }

function cmds.farm(rest)
    local p, g = rest:match("^(%S*)%s*(%S*)")
    HME.OpenWindow("finder")
    if HME.Pages.finderSet then HME.Pages.finderSet(PROF[p], (g ~= "" and g) or nil) end
end

function cmds.stop() HME.Guidance.Stop() end
function cmds.nav() HME.Guidance.Navigate() end
function cmds.hud() HME.HUD.Toggle() end

function cmds.session(rest)
    if rest == "start" then HME.Session.Start()
    elseif rest == "pause" then HME.Session.Pause()
    elseif rest == "end" or rest == "stop" or rest == "reset" then HME.Session.Stop("manual")
    else HME.OpenWindow("dashboard") end
end

function cmds.glimmer(rest)
    if rest == "on" or rest == "off" then
        HME.SetGlimmer(rest == "on")
    elseif rest == "preview" then
        if ns.SparklesUI and ns.SparklesUI.Preview then ns.SparklesUI:Preview() end
    elseif rest ~= "" and ns.Sparkles and ns.Sparkles.HandleCommand then
        ns.Sparkles:HandleCommand(rest)
    elseif rest == "" then
        HME.SetGlimmer(not (ns.db.sparkle and ns.db.sparkle.enabled))
    else
        HME.OpenWindow("settings", "glimmer")
    end
end
cmds.sparkle = cmds.glimmer

function cmds.routes(rest)
    if HME.Routes then HME.Routes:SlashCommand(rest) end
end

function cmds.export()
    HME.OpenWindow("settings", "data")
end

function cmds.import(rest)
    local done = HME.Migrate.Run(rest ~= "" and rest or true)
    if #done == 0 then
        HME.Print("nothing to import: enable the old addon for one login so its saved data is loaded, then try again.")
    else
        HME.Print("imported from " .. table.concat(done, ", ") .. ". Their own data was not changed.")
    end
end

function cmds.diag()
    local z = HME.DBM.Size()
    HME.Print(("v%s, data %s, %d learned nodes, %d sessions"):format(HME.VERSION, HME.dataReady and "ok" or "PROBLEM",
        z.nodes, z.sessions))
    print("  " .. HME.IntegrationLine())
    if #HME.missingEvents > 0 then print("  events this client lacks: " .. table.concat(HME.missingEvents, ", ")) end
    for _, p in ipairs(HME.dataProblems or {}) do print("  data: " .. p) end
    local conflicts = HME.Migrate.Conflicts()
    for _, c in ipairs(conflicts) do print("  also running: " .. c.label .. " (HME's copy of its features is paused)") end
    for _, l in ipairs(HME.Perf.Lines()) do print("  " .. l) end
    if HME.lastError then print("  last error: " .. HME.lastError) end
end

local function Run(msg)
    if not HME.db then return end
    local word, rest = (msg or ""):match("^%s*(%S*)%s*(.-)%s*$")
    word = (word or ""):lower()
    rest = rest or ""
    if word == "" then return HME.ToggleWindow() end
    if PAGES[word] and word ~= "farm" and word ~= "routes" then return HME.OpenWindow(PAGES[word]) end
    local fn = cmds[word]
    if fn then return fn(rest:lower()) end
    -- HarvestMate's own commands (skills, next, bags, near, key, soft, tip, ach, test...)
    local hg = HME.HGCommands and HME.HGCommands[word]
    if hg then return hg((rest:match("^(%S*)") or ""):lower()) end
    Help()
end
HME.RunCommand = Run

SLASH_HARVESTMATEENHANCED1 = "/hme"
SLASH_HARVESTMATEENHANCED2 = "/harvestmateenhanced"
SlashCmdList.HARVESTMATEENHANCED = Run

HME.On("PLAYER_LOGIN", function()
    local M = HME.Migrate
    if not M.Loaded("HarvestMate") then
        SLASH_HMEHARVESTMATE1 = "/hm"
        SLASH_HMEHARVESTMATE2 = "/harvestmate"
        SlashCmdList.HMEHARVESTMATE = Run
    end
    if not M.Loaded("Gatherpedia") then
        SLASH_HMEGATHERPEDIA1 = "/gp"
        SlashCmdList.HMEGATHERPEDIA = function(msg)
            local w = (msg or ""):match("^%s*(%S*)") or ""
            if w == "glimmer" or w == "sparkle" then return Run(msg) end
            if PROF[w] then
                HME.OpenWindow("materials")
                return
            end
            Run(msg)
        end
    end
end)

-- Key binding (Bindings.xml)
function HarvestMateEnhanced_ToggleWindow() HME.ToggleWindow() end
function HarvestMateEnhanced_ToggleRoute()
    if HME.Guidance.Active() then
        HME.Guidance.Stop()
    else
        HME.OpenWindow("finder")
    end
end
BINDING_HEADER_HARVESTMATEENHANCED = "HarvestMate Enhanced"
BINDING_NAME_HARVESTMATEENHANCED_TOGGLE = "Open or close HarvestMate Enhanced"
BINDING_NAME_HARVESTMATEENHANCED_ROUTE = "Stop the farm (or open the Farm Finder)"
