-- HarvestMate Enhanced: Integrations/Crafting.lua
-- Optional crafting intelligence, only from data that is reliable: Forever-GPS
-- ships the WoW Forever client's own recipe tables (ForeverGPS.RecipeData,
-- build 1.60.1, generated from the client by its upstream "profit"). HME reads
-- them; it has no recipe data of its own and invents none. Without
-- Forever-GPS this module is simply off.
--
--   C.Available()            whether recipe data is there
--   C.UsesOf(itemID)         recipes that use a material: { { recipeID, out,
--                            count (per craft), line, learn } }, most used first
--   C.Reagents(outItemID)    what one craft of an item needs: { { id, n } }, recipeID
--   C.ShoppingList(outItemID, crafts)  the gathered materials still missing for
--                            that many crafts (what is in your bags counts),
--                            as a Goals "list" spec, and the reagents HME cannot
--                            gather (bought or crafted), listed apart
-- Copyright (C) 2026 HarvestMate Enhanced contributors. GPL-3.0-or-later.

local _, ns = ...
local HME = ns.HME

local C = {}
HME.Crafting = C

C.MAX_INDEX = 6000

local function Data()
    local fg = _G.ForeverGPS
    local d = type(fg) == "table" and type(fg.RecipeData) == "table" and fg.RecipeData or nil
    if d and type(d.recipes) == "table" then return d end
    return nil
end

function C.Available() return Data() ~= nil end

local function Pairs(text)
    local out = {}
    for id, n in (text or ""):gmatch("(%d+):(%d+)") do out[#out + 1] = { id = tonumber(id), n = tonumber(n) } end
    return out
end

-- One packed recipe: "line|item:count|reagents|learn|trainer|yellow|grey|sources|recipeItems|issues".
local function Parse(id, packed)
    if type(packed) ~= "string" then return nil end
    local f = {}
    for field in (packed .. "|"):gmatch("([^|]*)|") do f[#f + 1] = field end
    local make = Pairs(f[2])[1]
    if not make then return nil end
    return { id = id, line = tonumber((f[1] or ""):match("%d+")), out = make.id, count = make.n, reagents = Pairs(f[3]),
             learn = tonumber(f[4]), unsure = (f[10] or "") ~= "" }
end

local byReagent, byOut, indexed
local function Index()
    local d = Data()
    if not d then return false end
    if indexed == d then return true end
    byReagent, byOut = {}, {}
    local n = 0
    for id, packed in pairs(d.recipes) do
        n = n + 1
        if n > C.MAX_INDEX then break end
        local r = Parse(id, packed)
        if r and not r.unsure then
            byOut[r.out] = byOut[r.out] or r
            for _, g in ipairs(r.reagents) do
                byReagent[g.id] = byReagent[g.id] or {}
                table.insert(byReagent[g.id], { recipeID = id, out = r.out, count = g.n, line = r.line, learn = r.learn })
            end
        end
    end
    indexed = d
    return true
end

function C.UsesOf(itemID)
    if not (itemID and Index()) then return {} end
    local list = {}
    for _, u in ipairs(byReagent[itemID] or {}) do list[#list + 1] = u end
    table.sort(list, function(a, b) return a.count > b.count end)
    return list
end

function C.Reagents(outItemID)
    if not (outItemID and Index()) then return nil end
    local r = byOut[outItemID]
    if not r then return nil end
    return r.reagents, r.id, r.count
end

-- The gathered materials still missing for `crafts` crafts of outItemID.
function C.ShoppingList(outItemID, crafts)
    local reagents, recipeID, perCraft = C.Reagents(outItemID)
    if not reagents then return nil, "no recipe makes that (in the client's data)" end
    crafts = math.max(1, math.floor(tonumber(crafts) or 1))
    local items, other = {}, {}
    for _, g in ipairs(reagents) do
        local need = g.n * crafts
        if HME.Goals.ProfOf(g.id) then
            local have = HME.Inventory.Held(g.id) + (HME.Inventory.Bank(g.id) or 0)
            if need > have then items[#items + 1] = { itemID = g.id, target = need } end
        else
            other[#other + 1] = { itemID = g.id, n = need }
        end
    end
    local name = HME.Goals.ItemName(outItemID)
    return { type = "list", items = items, name = ("%d x %s"):format(crafts * (perCraft or 1), name) }, other, recipeID
end

-- A line for the sell/keep advisor: what a material is used for.
function C.UseLine(itemID)
    local uses = C.UsesOf(itemID)
    if #uses == 0 then return nil end
    local names = {}
    for i, u in ipairs(uses) do
        if i > 3 then break end
        names[#names + 1] = HME.Goals.ItemName(u.out)
    end
    return ("Used in %d recipe%s, e.g. %s (client data via Forever-GPS)."):format(#uses, #uses == 1 and "" or "s", table.concat(names, ", "))
end
