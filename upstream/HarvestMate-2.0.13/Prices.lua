local _, HG = ...

-- Сведения о предметах: имя, цвет качества, цена у торговца и на аукционе.
-- Аукционная цена берётся из Auctionator, если он установлен, иначе из TSM.

local GetItemInfo = (C_Item and C_Item.GetItemInfo) or _G.GetItemInfo

-- Имя предмета в цвете качества или nil, если клиент его ещё не загрузил
-- (тогда просим загрузить — при следующем показе имя будет).
function HG.ItemLabel(id)
	local name, _, quality = GetItemInfo(id)
	name = HG.Str(name)
	if not name then
		if C_Item and C_Item.RequestLoadItemDataByID then
			C_Item.RequestLoadItemDataByID(id)
		end
		return nil
	end
	local color = ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[quality]
	if color and color.hex then
		return color.hex .. name .. "|r"
	end
	return name
end

function HG.VendorPrice(id)
	local price = select(11, GetItemInfo(id))
	price = HG.Num(price)
	if price and price > 0 then
		return price
	end
	return nil
end

-- Цена на аукционе в меди, или nil и название источника.
function HG.AuctionPrice(id)
	local api = _G.Auctionator and _G.Auctionator.API and _G.Auctionator.API.v1
	if api and api.GetAuctionPriceByItemID then
		local ok, price = pcall(api.GetAuctionPriceByItemID, HG.addon, id)
		if ok and HG.Num(price) and price > 0 then
			return price
		end
		return nil
	end
	local tsm = _G.TSM_API
	if tsm and tsm.GetCustomPriceValue then
		local ok, price = pcall(tsm.GetCustomPriceValue, "dbmarket", "i:" .. id)
		if ok and HG.Num(price) and price > 0 then
			return price
		end
	end
	return nil
end

function HG.HasAuctionSource()
	return (_G.Auctionator and _G.Auctionator.API) ~= nil or _G.TSM_API ~= nil
end

-- 12345 -> "1з 23с 45м" с иконками монет, если клиент умеет.
function HG.Money(copper)
	copper = math.floor(copper + 0.5)
	local coins = (C_CurrencyInfo and C_CurrencyInfo.GetCoinTextureString) or _G.GetCoinTextureString
	if coins then
		return coins(copper)
	end
	local L = HG.L
	local gold = math.floor(copper / 10000)
	local silver = math.floor(copper / 100) % 100
	local rest = copper % 100
	local parts = {}
	if gold > 0 then
		parts[#parts + 1] = "|cffffd100" .. gold .. L.COIN_GOLD .. "|r"
	end
	if silver > 0 then
		parts[#parts + 1] = "|cffc7c7cf" .. silver .. L.COIN_SILVER .. "|r"
	end
	if rest > 0 or #parts == 0 then
		parts[#parts + 1] = "|cffeda55f" .. rest .. L.COIN_COPPER .. "|r"
	end
	return table.concat(parts, " ")
end

-- Строка цен: "торг. 5м · аук. 1з 20с" (что известно).
function HG.PriceText(id)
	local L = HG.L
	local parts = {}
	local vendor = HG.VendorPrice(id)
	if vendor then
		parts[#parts + 1] = L.PRICE_VENDOR .. " " .. HG.Money(vendor)
	end
	local auction = HG.AuctionPrice(id)
	if auction then
		parts[#parts + 1] = L.PRICE_AUCTION .. " " .. HG.Money(auction)
	end
	if #parts == 0 then
		return nil
	end
	return table.concat(parts, "  ")
end
