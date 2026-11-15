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
        "/hme copilot | finder | beasts | guides | materials | stats | trainers | routes | settings  open a page",
        "/hme find <text>  search everything (materials, creatures, zones, routes, trainers...)",
        "/hme review  the last session's review   ·   /hme notices  the notification list in chat",
        "/hme ready  check bags, repairs, rank cap and risk for the Copilot's farm   ·   /hme danger  this zone's record",
        "/hme flights on|off  take flights automatically at a flight master (see Settings)",
        "/hme farm skin|herb|mine|fish [level|profit]  open the Farm Finder on it",
        "/hme stop  stop following the farm   ·   /hme nav  navigate to it",
        "/hme here  guide the loop beside another Forever-GPS journey   ·   /hme giveback  hand the arrow back",
        "/hme rec [start name|pause|resume|stop|cancel]  record your own route as you ride it",
        "/hme exp [plan|go|next|skip n|replan|stop]  a farming expedition for your shopping list",
        "/hme recipe [n] <item>  the gathered materials a recipe still needs, as a shopping list",
        "/hme corrections  your marks on spawn points, beasts and areas   ·   /hme uncorrect <n>  undo one",
        "/hme session start|pause|end   ·   /hme hud  show or hide the HUD",
        "/hme skinlevels (or /hme sl) [on|off]  which beast levels give Skinning points now, live",
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
    settings = "settings", options = "settings", config = "settings", dashboard = "dashboard", setup = "setup",
    goals = "goals", copilot = "copilot", beasts = "beasts", explorer = "beasts", skinning = "beasts" }
local PROF = { herb = "Herbalism", herbs = "Herbalism", herbalism = "Herbalism", mine = "Mining", mining = "Mining",
    ore = "Mining", skin = "Skinning", skinning = "Skinning", fish = "Fishing", fishing = "Fishing" }

function cmds.farm(rest)
    local p, g = rest:match("^(%S*)%s*(%S*)")
    HME.OpenWindow("finder")
    if HME.Pages.finderSet then HME.Pages.finderSet(PROF[p], (g ~= "" and g) or nil) end
end

function cmds.stop() HME.Guidance.Stop() end
function cmds.nav() HME.Guidance.Navigate() end
-- Guide me here: HME's arrow round the loop although another journey runs
-- (that journey is never stopped); /hme giveback hands the arrow back.
function cmds.here() HME.Guidance.TakeOver() end

-- Record my route: /hme rec [start [name] | pause | resume | stop | cancel]
function cmds.rec(rest)
    local R = HME.Recorder
    local verb, arg = (rest or ""):match("^(%S*)%s*(.-)$")
    if verb == "" then verb = R.Active() and "stop" or "start" end
    if verb == "start" then
        local ok, why = R.Start(arg ~= "" and arg or nil)
        if not ok then HME.Print("can't record: " .. tostring(why) .. ".") end
    elseif verb == "pause" then R.Pause()
    elseif verb == "resume" then R.Resume()
    elseif verb == "stop" or verb == "save" then R.Stop()
    elseif verb == "cancel" then R.Cancel()
    else HME.Print("/hme rec start [name] | pause | resume | stop | cancel") end
end
cmds.record = cmds.rec

-- Expeditions: /hme exp [plan | go | next | skip [n] | replan | stop]
-- "plan" uses your first open shopping list (or item goal).
function cmds.exp(rest)
    local X = HME.Expedition
    local verb, arg = (rest or ""):match("^(%S*)%s*(.-)$")
    local function Show(plan)
        HME.Print(("%s (%s farming, %s travel):"):format(plan.name or "Expedition", HME.U.Duration(plan.hours * 3600),
            HME.U.Duration(plan.travel)))
        for _, l in ipairs(X.Lines(plan)) do print("  " .. l) end
    end
    if verb == "plan" then
        for _, g in ipairs(HME.Goals.List()) do
            if not g.doneAt and (g.type == "list" or g.type == "item") then
                HME.Print("planning an expedition for " .. (g.name or "your goal") .. "...")
                X.Plan(X.FromGoal(g), {}, function(plan)
                    if #plan.stages == 0 then
                        HME.Print("no farm in reach gives those materials.")
                        for _, l in ipairs(X.Lines(plan)) do print("  " .. l) end
                        return
                    end
                    X.Start(plan, g.name)
                    Show(plan)
                    HME.Print("/hme exp go starts stage 1.")
                end)
                return
            end
        end
        HME.Print("make a shopping list or material goal first (Goals page).")
    elseif verb == "go" then X.Go(tonumber(arg))
    elseif verb == "next" then local ok, why = X.Next() if not ok and why then HME.Print(why .. ".") end
    elseif verb == "skip" then X.Skip(tonumber(arg))
    elseif verb == "replan" then X.Replan(function(plan) Show(plan) end)
    elseif verb == "stop" then X.Stop()
    else
        local plan = X.Current()
        if plan then Show(plan) else HME.Print("/hme exp plan | go | next | skip [n] | replan | stop") end
    end
end
cmds.expedition = cmds.exp

-- Your corrections: /hme corrections lists them, /hme uncorrect <n> undoes one.
function cmds.corrections()
    local list = HME.Corrections.List()
    if #list == 0 then
        HME.Print("no corrections. Right-click a pin on the map to mark a spawn point or a beast.")
        return
    end
    HME.Print(("your corrections (%d):"):format(#list))
    for _, c in ipairs(list) do print(("  %d. %s"):format(c.id, HME.Corrections.Text(c))) end
    print("  /hme uncorrect <number> undoes one.")
end
function cmds.uncorrect(rest)
    local id = tonumber(rest)
    if id and HME.Corrections.Remove(id) then HME.Print("correction " .. id .. " undone.")
    else HME.Print("no correction with that number (/hme corrections lists them).") end
end

-- /hme recipe [crafts] <item link or ID>: the gathered materials still missing
-- for that many crafts, as a shopping list goal (recipes: the client's data
-- through Forever-GPS; nothing without it).
function cmds.recipe(rest)
    if not (HME.Crafting and HME.Crafting.Available()) then
        HME.Print("recipe data comes from Forever-GPS (the client's own tables); it is not installed or too old.")
        return
    end
    local crafts, what = (rest or ""):match("^(%d+)%s+(.+)$")
    what = what or rest
    local id = tonumber((what or ""):match("item:(%d+)")) or tonumber(what)
    if not id then
        HME.Print("/hme recipe [how many] <shift-click the item, or its ID>")
        return
    end
    local spec, other = HME.Crafting.ShoppingList(id, tonumber(crafts) or 1)
    if not spec then
        HME.Print(tostring(other) .. ".")
        return
    end
    if #spec.items == 0 then
        HME.Print("you already have the gathered materials for that.")
    else
        local g = HME.Goals.Add(spec)
        HME.Print(("shopping list added: %s (Goals page; Expedition plans the farms)."):format(g and g.name or spec.name))
    end
    if #other > 0 then
        local names = {}
        for _, o in ipairs(other) do names[#names + 1] = ("%d %s"):format(o.n, HME.Goals.ItemName(o.itemID)) end
        HME.Print("also needed, not gathered: " .. table.concat(names, ", ") .. ".")
    end
end
function cmds.giveback() HME.Guidance.GiveBack() end

-- 0.6.0: search, the last session's review, notifications in chat.
function cmds.find(rest)
    local list = HME.Find.Run(rest or "")
    if #list == 0 then
        HME.Print("nothing found for \"" .. tostring(rest or "") .. "\".")
        return list
    end
    HME.Print(("%d found; the first opens (the search box in the window lists them all):"):format(#list))
    for i, r in ipairs(list) do
        if i <= 6 then print(("  %s: %s (%s)"):format(r.kind, r.label, r.sub or "")) end
    end
    HME.Find.Open(list[1])
    return list
end
cmds.search = cmds.find
function cmds.review() return HME.Review.Show() end
-- 0.7.0: the readiness check for the Copilot's farm, and this zone's danger.
function cmds.ready()
    local pick = HME.Copilot.pick
    if not pick then
        HME.Print("no farm to check yet: open the Copilot (/hme copilot) and let it find one.")
        return nil
    end
    local res = HME.Ready.Check(pick.r, HME.Copilot.Budget(), HME.Player.Profile())
    HME.Print(("%s in %s:"):format(pick.r.prof or "?", pick.r.zone or "?"))
    for _, l in ipairs(HME.Ready.Lines(res)) do print("  " .. l) end
    return res
end
function cmds.flights(rest)
    if rest == "on" or rest == "off" then HME.settings.autoFlight = rest == "on" end
    HME.Print(("taking flights automatically is %s. %s"):format(HME.settings.autoFlight and "on" or "off",
        HME.settings.autoFlight and "Talk to a flight master while HME or Forever-GPS leads you somewhere; hold Shift to choose yourself."
            or "/hme flights on turns it on."))
    local last = HME.Flights.last
    if last and (last.node or last.why) then
        -- (what the game did, not what HME asked for: "flying", "refused", "not started")
        local RESULT = { flying = "flew to %s", refused = "the game refused the flight to %s (the button was offered)",
            ["not started"] = "the flight to %s did not start", asked = "asked for %s, no answer yet" }
        print(("  last flight map: %s%s"):format(last.node and (RESULT[last.result] or "asked for %s"):format(last.node.name)
            or ("did not fly: " .. tostring(last.skipped or last.why)),
            last.planSkipped and (" (" .. last.planSkipped .. ")") or ""))
    end
    return HME.settings.autoFlight
end
function cmds.danger()
    local mapID, x, y = HME.Player.Position()
    local zm = mapID and (HME.Geo.ZoneOf(mapID, x, y) or mapID)
    local z = HME.Danger.Zone(zm)
    HME.Print((HME.ZoneData.Name(zm) or "this zone") .. ": " .. (z.text ~= "" and z.text or "nothing recorded here yet."))
    return z
end
function cmds.notices()
    local list = HME.Notify.List()
    if #list == 0 then HME.Print("no notifications.") return end
    for i = #list, math.max(1, #list - 9), -1 do print(("  [%s] %s"):format(list[i].cat, list[i].text or "")) end
    HME.Notify.MarkRead()
end
function cmds.hud(rest)
    if rest == "reset" then
        HME.HUD.ResetPosition()
        HME.Print("the farming HUD is back at the top right.")
        return
    end
    HME.HUD.Toggle()
end
function cmds.skinlevels(rest)
    if rest == "on" or rest == "off" then HME.SkinTracker.Toggle(rest == "on") else HME.SkinTracker.Toggle() end
end
cmds.sl = cmds.skinlevels

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

-- /hme diag: a report to copy (window); /hme diag chat: the short form in chat.
function cmds.diag(rest)
    if rest ~= "chat" and HME.Diagnostics and HME.Diagnostics.Show() then return end
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
BINDING_NAME_HARVESTMATEENHANCED_NEXTTAB = "Next page of the window"
BINDING_NAME_HARVESTMATEENHANCED_PREVTAB = "Previous page of the window"
BINDING_NAME_HARVESTMATEENHANCED_SKINLEVELS = "Show or hide Skinning levels"
function HarvestMateEnhanced_ToggleSkinLevels() if HME.SkinTracker then HME.SkinTracker.Toggle() end end
function HarvestMateEnhanced_CycleTab(delta) HME.Window.CycleTab(delta) end
