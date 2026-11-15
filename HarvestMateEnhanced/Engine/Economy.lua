-- HarvestMate Enhanced: Engine/Economy.lua (0.6.0)
-- Sell, process or keep: what a gathered material is worth to you, each way.
--
--   keep     a goal of yours needs it, or you reserved it: shown first,
--            whatever the prices say
--   auction  the auction estimate after the house's 5% cut (Engine/Prices.lua
--            already takes it off), with the deposit you risk if it does not
--            sell (15% of the vendor price per listing of 12 hours, a classic
--            rule; Forever may differ) and the age of the price
--   vendor   what a vendor pays, certain
--   process  recipes in the client's data (Forever-GPS) that use it: the
--            product's value per unit of this material, minus the other
--            reagents' value. Smelting is marked as Mining's (you can do it
--            when you mine); other recipes need a crafting profession HME
--            cannot see, so they are labelled "if you craft".
-- Values are estimates; a listing is not a sale. Nothing here buys, sells,
-- posts or crafts.
-- Copyright (C) 2026 HarvestMate Enhanced contributors. GPL-3.0-or-later.

local _, ns = ...
local HME = ns.HME
local U = HME.U

local E = {}
HME.Economy = E

E.DEPOSIT_SHARE = 0.15
E.MAX_RECIPES = 3
E.MINING_LINE = 186

local function Name(id) return (HME.Goals and HME.Goals.ItemName(id)) or ("item " .. id) end
local function Money(c) return HME.Kit and HME.Kit.Money(c) or U.Money(c, true) end

-- { { kind, label, value (copper per unit) | nil, text, sure } }, best first;
-- and the pick (the first with the highest value, keep first when a goal wants it).
function E.Options(itemID)
    local out = {}
    local plain = HME.Advice.Plain(itemID)
    if plain.action == "keep" then
        out[#out + 1] = { kind = "keep", label = "Keep", text = plain.text:gsub("^Keep: ", ""), sure = true, first = true }
    end
    local p = HME.Prices.Get(itemID)
    if p and p.typical and p.source then
        local deposit = (p.vendor or 0) * E.DEPOSIT_SHARE
        out[#out + 1] = { kind = "auction", label = "Auction house", value = p.typical,
            text = ("about %s each after the 5%% cut (%s, %s)%s; a listing is not a sale."):format(Money(p.typical), p.source,
                HME.Prices.AgeText(p.age) or "age unknown", deposit > 0 and (", deposit about %s a unit if it does not sell"):format(Money(deposit)) or ""),
            sure = false, suspect = p.suspect }
    end
    if p and p.vendor and p.vendor > 0 then
        out[#out + 1] = { kind = "vendor", label = "Vendor", value = p.vendor, text = ("%s each, certain."):format(Money(p.vendor)), sure = true }
    end
    -- Processing, from the client's recipe tables.
    local procs = {}
    for _, u in ipairs((HME.Crafting and HME.Crafting.UsesOf(itemID)) or {}) do
        local reagents, _, perCraft = HME.Crafting.Reagents(u.out)
        local outValue = HME.Prices.Value(u.out) or 0
        if reagents and outValue > 0 and (u.count or 0) > 0 then
            local others = 0
            local unknown = false
            for _, g in ipairs(reagents) do
                if g.id ~= itemID then
                    local v = HME.Prices.Value(g.id)
                    if v then others = others + v * g.n else unknown = true end
                end
            end
            local per = ((perCraft or 1) * outValue - others) / u.count
            if per > 0 and not unknown then
                local smelt = u.line == E.MINING_LINE
                procs[#procs + 1] = { kind = "process", label = smelt and "Smelt" or "Craft", value = per, out = u.out,
                    text = ("%s into %s: about %s per %s%s."):format(smelt and "Smelt" or "Make", Name(u.out), Money(per), Name(itemID),
                        smelt and (u.learn and (" (Mining %d)"):format(u.learn) or " (Mining)") or ", if you have that crafting profession"),
                    sure = false, needs = smelt and "Mining" or "a crafting profession" }
            end
        end
    end
    table.sort(procs, function(a, b) return a.value > b.value end)
    for i = 1, math.min(E.MAX_RECIPES, #procs) do out[#out + 1] = procs[i] end
    -- The pick: keep when wanted; else the highest value (vendor wins ties: certain).
    local pick
    for _, o in ipairs(out) do if o.first then pick = o end end
    if not pick then
        for _, o in ipairs(out) do
            if o.value and (not pick or o.value > pick.value * (o.sure and 0.98 or 1.02)) then pick = o end
        end
    end
    if pick then pick.best = true end
    return out, pick
end

-- Lines for the Materials page.
function E.Lines(itemID)
    local opts, pick = E.Options(itemID)
    local lines = {}
    if #opts == 0 then lines[1] = "No price known yet: no auction data and no vendor value loaded." end
    for _, o in ipairs(opts) do
        local mark = o == pick and "|cff8fcc5c> |r" or "  "
        lines[#lines + 1] = ("%s|cff999b8f%s|r  %s%s"):format(mark, o.label, o.text,
            o.suspect and " |cfff5a345(the auction price looks unusual)|r" or "")
    end
    -- 0.7.0: how the price moved (Engine/Trends.lua).
    if HME.Trends then
        local t = HME.Trends.Of(itemID)
        if t.days > 0 then
            local hex = t.trend == "up" and "8fcc5c" or (t.trend == "down" and "f5a345" or "999b8f")
            lines[#lines + 1] = ("  |cff999b8fTrend|r  |cff%s%s|r"):format(hex, t.text)
            local advice = HME.Trends.Advice(t)
            if advice then lines[#lines + 1] = "  " .. advice end
        end
    end
    return lines
end
