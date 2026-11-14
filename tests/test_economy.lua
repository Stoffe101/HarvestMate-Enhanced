-- Prices made safe (units, impossible values, outliers) and the optional
-- crafting link (Forever-GPS's copy of the client's recipe tables; the two
-- recipes below are copied in its packed format from its Data/Recipes.lua).

local ns, HME = LoadHME()
local Pr = HME.Prices

STEP("impossible prices are dropped, outliers marked and valued low")
Pr.Invalidate()
Pr.fixed = { [2318] = { low = -5, typical = 0 } }
local r = Pr.Get(2318)
eq(r.source, nil, "a zero or negative price is not a price")
Pr.Invalidate()
Pr.fixed = { [2318] = { low = 1e12, typical = 1e12 } }
eq(Pr.Get(2318).source, nil, "nor is 100 million gold")
Pr.Invalidate()
Pr.fixed = { [2318] = { low = 0 / 0, typical = 120 } }
local nanFixed = Pr.Get(2318)
eq(nanFixed.source, "test", "a missing low falls back to typical")
eq(nanFixed.conservative, 120 * 0.95)
Pr.Invalidate()
Pr.Vendor = function() return 15 end
Pr.fixed = { [2318] = { low = 300, typical = 900000, age = 3600 } }
local odd = Pr.Get(2318)
check(odd.suspect, "far above the vendor price: suspect")
eq(odd.typical, 300 * 0.95, "valued at the cheapest listing")
check(Pr.Trust(odd) < 0.4, "and trusted less")
check(HME.Advice.For(2318).text:find("looks unusual", 1, true), "the advisor says so")
Pr.Invalidate()
Pr.fixed = { [2318] = { low = 40, typical = 50, age = 3600 } }
local ok = Pr.Get(2318)
check(not ok.suspect, "a normal price is not suspect")
eq(ok.typical, 50 * 0.95, "after the auction cut")
Pr.fixed = nil
Pr.Invalidate()

STEP("crafting stays off without Forever-GPS's recipe data")
check(not HME.Crafting.Available())
eq(#HME.Crafting.UsesOf(2318), 0)
SlashCmdList.HARVESTMATEENHANCED("recipe 2 2300")
check(LOG[#LOG]:find("Forever-GPS", 1, true), "says where recipe data comes from")

STEP("with it: what a material is used for, and a recipe as a shopping list")
ForeverGPS = { VERSION = "2.8.0", On = function() end, RecipeData = { build = "1.60.1.70790", recipes = {
    [2160] = "165|2300:1|2318:8,2320:4|35|35|65|95|t||",
    [2149] = "165|2302:1|2318:2,2320:1|1|1|40|70|t||",
} } }
check(HME.Crafting.Available())
local uses = HME.Crafting.UsesOf(2318)
eq(#uses, 2, "Light Leather is used in both")
eq(uses[1].count, 8, "most used first")
local reagents, recipeID = HME.Crafting.Reagents(2300)
eq(recipeID, 2160)
eq(#reagents, 2)
local spec, other = HME.Crafting.ShoppingList(2300, 3)
eq(spec.type, "list")
eq(spec.items[1].itemID, 2318)
eq(spec.items[1].target, 24, "3 crafts x 8")
eq(other[1].itemID, 2320, "thread is not gathered: listed apart")
eq(other[1].n, 12)
check(HME.Advice.For(2318).use, "the advisor knows its uses")
local before = #HME.Goals.List()
SlashCmdList.HARVESTMATEENHANCED("recipe 3 |cffffffff|Hitem:2300::::::::|h[Embossed Leather Vest]|h|r")
eq(#HME.Goals.List(), before + 1, "/hme recipe adds the shopping list")
ForeverGPS = nil
