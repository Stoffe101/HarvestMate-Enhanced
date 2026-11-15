-- Sell, process or keep (Engine/Economy.lua) and farm profiles that restore a
-- whole workspace (0.6.0).

local ns, HME = LoadHME()
PLAYER.map, PLAYER.x, PLAYER.y = 1424, 0.46, 0.42
CHAR.level = 41
PROFS = { { line = 393, rank = 143, max = 225 }, { line = 186, rank = 120, max = 150 } }
HME.Player.Refresh()
local E = HME.Economy
local ORE, BAR, OTHER = 2770, 2840, 3576

STEP("economy: vendor only, no auction data")
ITEMS[ORE] = { name = "Copper Ore", sell = 5 }
HME.Prices.Invalidate()
local opts, pick = E.Options(ORE)
eq(pick and pick.kind, "vendor")
check(E.Lines(ORE)[1]:find("Vendor"), E.Lines(ORE)[1])

STEP("economy: auction after the cut, with the deposit and the age")
HME.Prices.fixed = { [ORE] = { low = 80, typical = 100 } }
HME.Prices.Invalidate()
opts, pick = E.Options(ORE)
eq(pick.kind, "auction")
check(pick.text:find("5%% cut") and pick.text:find("deposit") and pick.text:find("not a sale"), pick.text)

STEP("economy: smelting when the bar is worth more (client recipe data)")
ITEMS[BAR] = { name = "Copper Bar", sell = 10 }
ForeverGPS = { RecipeData = { recipes = { [2657] = "186|" .. BAR .. ":1|" .. ORE .. ":1|1|||||" } } }
HME.Prices.fixed = { [ORE] = { low = 80, typical = 100 }, [BAR] = { low = 300, typical = 330 } }
HME.Prices.Invalidate()
opts, pick = E.Options(ORE)
eq(pick.kind, "process")
eq(pick.label, "Smelt")
check(pick.text:find("Copper Bar") and pick.text:find("Mining"), pick.text)

STEP("economy: a recipe with an unpriced reagent is left out (no invented value)")
ForeverGPS = { RecipeData = { recipes = { [9999] = "164|" .. BAR .. ":1|" .. ORE .. ":1," .. OTHER .. ":2|1|||||" } } }
HME.Crafting = HME.Crafting   -- (index rebuilt for the new data)
opts = E.Options(ORE)
for _, o in ipairs(opts) do check(o.kind ~= "process", "no processing value without the other reagent's price") end

STEP("economy: a goal keeps it, whatever it is worth")
local g = HME.Goals.Add({ type = "item", itemID = ORE, target = 40, name = "Copper Ore" })
opts, pick = E.Options(ORE)
eq(pick.kind, "keep")
eq(opts[1].kind, "keep", "keep listed first")
HME.Goals.Remove(g.id)
ForeverGPS = nil
HME.Prices.fixed = nil
HME.Prices.Invalidate()

STEP("profiles: one click restores the workspace")
HME.settings.hudSize, HME.settings.mapDetail, HME.settings.riskMode = "detailed", "heatmap", "safer"
HME.Copilot.SetMode("profit")
HME.Copilot.SetMinutes(60)
local p = HME.Profiles.Save("Gold Farming", { prof = "Skinning", goal = "profit" })
check(p and p.workspace, "workspace saved")
HME.settings.hudSize, HME.settings.mapDetail, HME.settings.riskMode = "compact", "simple", "fastest"
HME.Copilot.SetMode("level")
HME.Copilot.SetMinutes(15)
HME.Profiles.Apply(p)
eq(HME.settings.hudSize, "detailed")
eq(HME.settings.mapDetail, "heatmap")
eq(HME.settings.riskMode, "safer")
eq(HME.Copilot.Mode(), "profit")
eq(HME.Copilot.Minutes(), 60)

STEP("profiles: an old profile without a workspace still applies")
local old = { name = "Old", prof = "Skinning", goal = "level" }
HME.Profiles.Apply(old)
eq(HME.settings.hudSize, "detailed", "unchanged")
