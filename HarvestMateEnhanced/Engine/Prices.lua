-- HarvestMate Enhanced: Engine/Prices.lua
-- One price for an item, with where it came from and how old it is. HME never
-- scans the auction house itself: it reads what an installed addon already
-- knows, in this order unless the player picks one (Settings, Prices):
--   Forever-GPS   its own scans and searches (lowest unit, typical, age)
--   Auctionator   its last-scan price (and age in days when it says)
--   TSM           dbminbuyout / dbmarket
--   vendor        what a merchant pays (the game's own figure)
--
-- Three estimates per item, so a forecast never pretends to know the sale:
--   conservative  the lowest listing (or 80% of a single price), after the 5% cut
--   typical       the typical price after the 5% cut
--   optimistic    5% above typical, after the cut (prices drift up between scans)
-- Listings are what sellers ask, not what buyers pay; HME says so in the UI.
--
-- Sanity (0.3.0): every provider's figure is copper per single item (checked
-- against each addon's API: Forever-GPS Market.Price buy/typical per unit,
-- Auctionator API v1 per unit, TSM custom prices in copper). A price that is
-- not a positive number, or above MAX_COPPER, is dropped; one far above the
-- vendor price (SUSPECT_X times and over 50 gold) is kept but marked suspect,
-- trusted less and valued at its lowest listing instead of typical.
-- Copyright (C) 2026 HarvestMate Enhanced contributors. GPL-3.0-or-later.

local _, ns = ...
local HME = ns.HME
local Num = HME.Num

local Pr = {}
HME.Prices = Pr

Pr.AH_CUT = 0.05
Pr.MAX_COPPER = 50000000       -- 5000 gold for one gathered item: anything above is a data error
Pr.SUSPECT_X = 200

-- A provider's record made safe: nil when unusable.
local function Sane(raw)
    if type(raw) ~= "table" then return nil end
    local function ok(v) return type(v) == "number" and v == v and v > 0 and v <= Pr.MAX_COPPER end
    local low, typical = ok(raw.low) and raw.low or nil, ok(raw.typical) and raw.typical or nil
    if not (low or typical) then return nil end
    raw.low, raw.typical = low or typical, typical or low
    if raw.low > raw.typical then raw.low = raw.typical end
    if raw.age and not (type(raw.age) == "number" and raw.age >= 0) then raw.age = nil end
    return raw
end
Pr.Sane = Sane
Pr.PROVIDERS = { "ForeverGPS", "Auctionator", "TSM", "vendor" }

local GetItemInfo = (C_Item and C_Item.GetItemInfo) or _G.GetItemInfo

function Pr.Vendor(itemID)
    if not GetItemInfo then return nil end
    local ok, price = pcall(function() return select(11, GetItemInfo(itemID)) end)
    price = ok and Num(price)
    if price and price > 0 then return price end
    if not ok or price == nil then
        if C_Item and C_Item.RequestLoadItemDataByID then pcall(C_Item.RequestLoadItemDataByID, itemID) end
    end
    return nil
end

-- Each reader returns { low, typical, age (seconds) } or nil.
local READERS = {}

function READERS.ForeverGPS(itemID)
    local FG = _G.ForeverGPS
    local m = type(FG) == "table" and type(FG.Market) == "table" and FG.Market
    if not (m and type(m.Price) == "function") then return nil end
    local ok, p = pcall(m.Price, itemID)
    if not ok or type(p) ~= "table" then return nil end
    local low, typical = Num(p.buy), Num(p.typical)
    if not (low or typical) then return nil end
    return { low = low or typical, typical = typical or low, age = Num(p.age), units = Num(p.units) }
end

function READERS.Auctionator(itemID)
    local api = _G.Auctionator and _G.Auctionator.API and _G.Auctionator.API.v1
    if not (api and api.GetAuctionPriceByItemID) then return nil end
    local ok, price = pcall(api.GetAuctionPriceByItemID, HME.ADDON, itemID)
    price = ok and Num(price)
    if not price or price <= 0 then return nil end
    local age
    if api.GetAuctionAgeByItemID then
        local ok2, days = pcall(api.GetAuctionAgeByItemID, HME.ADDON, itemID)
        days = ok2 and Num(days)
        if days then age = days * 86400 end
    end
    return { low = price, typical = price, age = age, single = true }
end

function READERS.TSM(itemID)
    local tsm = _G.TSM_API
    if not (tsm and tsm.GetCustomPriceValue) then return nil end
    local key = "i:" .. itemID
    local ok1, market = pcall(tsm.GetCustomPriceValue, "dbmarket", key)
    local ok2, minb = pcall(tsm.GetCustomPriceValue, "dbminbuyout", key)
    market, minb = ok1 and Num(market), ok2 and Num(minb)
    if not (market or minb) then return nil end
    return { low = minb or market, typical = market or minb, single = not (market and minb) }
end

function Pr.Available()
    local list = {}
    if READERS.ForeverGPS(2447) ~= nil or (type(_G.ForeverGPS) == "table" and type(_G.ForeverGPS.Market) == "table") then
        list[#list + 1] = "ForeverGPS"
    end
    if _G.Auctionator and _G.Auctionator.API then list[#list + 1] = "Auctionator" end
    if _G.TSM_API then list[#list + 1] = "TSM" end
    return list
end

-- Test hook: a fixed price table { [itemID] = { low, typical, age } }.
Pr.fixed = nil

local cache, cacheAt = {}, 0
local CACHE_SECONDS = 30

-- The full record for one item:
--   { vendor, low, typical, age, source, conservative, typical, optimistic, best }
-- All values are copper per item, after the auction cut where they are
-- auction prices. `best` follows the sale mode (auction, vendor or higher).
function Pr.Get(itemID)
    if not itemID then return nil end
    local now = HME.Now()
    if now - cacheAt > CACHE_SECONDS then
        cache = {}
        cacheAt = now
    end
    local c = cache[itemID]
    if c then return c end
    local s = HME.settings or {}
    local rec = { vendor = Pr.Vendor(itemID) }
    local raw, source
    if Pr.fixed then
        raw = Pr.fixed[itemID]
        source = raw and "test"
    else
        local want = s.priceProvider or "auto"
        if want ~= "auto" and want ~= "vendor" and READERS[want] then
            raw = READERS[want](itemID)
            source = raw and want
        end
        if not raw and want ~= "vendor" then
            for _, name in ipairs({ "ForeverGPS", "Auctionator", "TSM" }) do
                raw = READERS[name](itemID)
                if raw then
                    source = name
                    break
                end
            end
        end
    end
    raw = Sane(raw)
    if not raw then source = nil end
    local net = 1 - Pr.AH_CUT
    if raw and rec.vendor and raw.typical > rec.vendor * Pr.SUSPECT_X and raw.typical > 500000 then
        rec.suspect = true
        raw.typical = raw.low   -- the cheapest listing, not an outlier's typical
    end
    if raw then
        rec.source = source
        rec.age = raw.age
        rec.units = raw.units
        -- Optimistic: a little above typical (5%), as prices drift up between scans.
        rec.optimistic = raw.typical * net * 1.05
        rec.typical = raw.typical * net
        rec.conservative = (raw.single and raw.typical * 0.8 or math.min(raw.low, raw.typical)) * net
    end
    local mode = s.saleMode or "best"
    local pick = s.priceMode or "typical"
    local auction = rec[pick]
    if mode == "vendor" then
        rec.best, rec.bestFrom = rec.vendor, rec.vendor and "vendor"
    elseif mode == "auction" then
        rec.best, rec.bestFrom = auction or rec.vendor, auction and "auction" or (rec.vendor and "vendor")
    else
        if auction and (not rec.vendor or auction >= rec.vendor) then
            rec.best, rec.bestFrom = auction, "auction"
        else
            rec.best, rec.bestFrom = rec.vendor, rec.vendor and "vendor"
        end
    end
    -- The three estimates for this item under the sale mode.
    local function under(v)
        if mode == "vendor" then return rec.vendor end
        if not v then return rec.vendor end
        if mode == "best" and rec.vendor and rec.vendor > v then return rec.vendor end
        return v
    end
    rec.est = { conservative = under(rec.conservative), typical = under(rec.typical), optimistic = under(rec.optimistic) }
    cache[itemID] = rec
    return rec
end

function Pr.Value(itemID, which)
    local r = Pr.Get(itemID)
    if not r then return nil end
    if which then return r.est[which] end
    return r.best
end

function Pr.Invalidate() cache = {} end
HME.Listen("SETTINGS", Pr.Invalidate)

-- How fresh a price is, in words.
function Pr.AgeText(age)
    if not age then return "age unknown" end
    if age < 3600 then return "under an hour old" end
    if age < 86400 then return ("%d h old"):format(math.floor(age / 3600)) end
    return ("%d days old"):format(math.floor(age / 86400))
end

-- 0-1 trust in a price: none, vendor only, stale or fresh auction data.
function Pr.Trust(rec)
    if not rec then return 0 end
    if not rec.source then return rec.vendor and 0.5 or 0 end
    if rec.suspect then return 0.3 end
    if not rec.age then return 0.6 end
    if rec.age <= 2 * 86400 then return 0.9 end
    if rec.age <= 7 * 86400 then return 0.7 end
    return 0.45
end
