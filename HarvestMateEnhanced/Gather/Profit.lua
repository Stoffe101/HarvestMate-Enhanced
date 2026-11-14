local _, ns = ... local HG = ns.HG -- HME patch P1

-- Что выгоднее: продать сырьё торговцу или на аукционе, либо сначала
-- переработать (выплавить слиток, собрать кожу) и продать результат.
-- Всё считается за 1 единицу сырья. Цены аукциона — за вычетом комиссии.
-- Варианты, на которые не хватает навыка, показываются серым и не
-- участвуют в выборе лучшего.

local AH_CUT = 0.05
local MINING, LEATHERWORKING = 186, 165
local BRONZE_BAR, BRONZE_SKILL = 2841, 65

-- Сырьё -> { product, need = сколько сырья на 1 шт., line = профессия, req = навык }
local RECIPES = {
	-- Руда -> слиток
	[2770] = { product = 2840, line = MINING, req = 1 },               -- медь
	[2771] = { product = 3576, line = MINING, req = 65 },              -- олово
	[2775] = { product = 2842, line = MINING, req = 75 },              -- серебро
	[2772] = { product = 3575, line = MINING, req = 125 },             -- железо
	[2776] = { product = 3577, line = MINING, req = 155 },             -- золото
	[3858] = { product = 3860, line = MINING, req = 175 },             -- мифрил
	[7911] = { product = 6037, line = MINING, req = 230 },             -- истинное серебро
	[10620] = { product = 12359, line = MINING, req = 250 },           -- торий
	[11370] = { product = 11371, need = 8, line = MINING, req = 230 }, -- чёрное железо
	-- Обрывки и кожа
	[2934] = { product = 2318, need = 3, line = LEATHERWORKING, req = 1 },   -- обрывки -> лёгкая
	[2318] = { product = 2319, need = 4, line = LEATHERWORKING, req = 100 }, -- лёгкая -> средняя
	[2319] = { product = 4234, need = 5, line = LEATHERWORKING, req = 150 }, -- средняя -> толстая
	[4234] = { product = 4304, need = 6, line = LEATHERWORKING, req = 200 }, -- толстая -> плотная
	[4304] = { product = 8170, need = 6, line = LEATHERWORKING, req = 250 }, -- плотная -> грубая
}
HG.RECIPES = RECIPES

-- Бронза: 1 медная + 1 оловянная руда -> 2 слитка. Вторую руду считаем
-- по цене аукциона, как если бы её пришлось докупить.
local BRONZE_PARTNER = { [2770] = 2771, [2771] = 2770 }

local GetItemInfo = (C_Item and C_Item.GetItemInfo) or _G.GetItemInfo

local function PlainName(id)
	local name = HG.Str((GetItemInfo(id)))
	if not name and C_Item and C_Item.RequestLoadItemDataByID then
		C_Item.RequestLoadItemDataByID(id)
	end
	return name
end
HG.ItemName = PlainName

-- Сколько останется после комиссии аукциона.
function HG.AuctionNet(id)
	local price = HG.AuctionPrice(id)
	return price and math.floor(price * (1 - AH_CUT))
end
local AuctionNet = HG.AuctionNet

-- Лучшая известная цена предмета: аукцион (после комиссии) или торговец.
function HG.BestPrice(id)
	local auction, vendor = AuctionNet(id), HG.VendorPrice(id)
	if auction and vendor then
		return math.max(auction, vendor)
	end
	return auction or vendor
end

-- nil, если навыка хватает; иначе текст «нужно: Выплавка 65».
local function Locked(line, req)
	local skill = HG.LineSkill(line)
	if skill and skill >= req then
		return nil
	end
	local L = HG.L
	local label = line == MINING and L.SMELTING or (HG.LineName(line) or L.LEATHERWORKING)
	return L.PROFIT_NEED:format(label, req)
end

-- Варианты для предмета: список { label, value, raw, locked },
-- индекс лучшего доступного и «есть ли хоть одна цена аукциона».
function HG.ProfitOptions(id)
	local recipe = RECIPES[id]
	if not recipe then
		return nil
	end
	local L = HG.L
	local need = recipe.need or 1
	local options = {}
	local function Add(label, value, raw, locked)
		options[#options + 1] = { label = label, value = value, raw = raw, locked = locked }
	end

	local vendor = HG.VendorPrice(id)
	if vendor then
		Add(L.PROFIT_VENDOR, vendor, true)
	end
	local auction = AuctionNet(id)
	if auction then
		Add(L.PROFIT_AUCTION, auction, true)
	end
	local hasAuction = auction ~= nil

	local name = PlainName(recipe.product)
	if name then
		local locked = Locked(recipe.line, recipe.req)
		local ratio = need > 1 and (" (" .. need .. " : 1)") or ""
		local productAuction = AuctionNet(recipe.product)
		if productAuction then
			hasAuction = true
			Add(L.PROFIT_MAKE_AUCTION:format(name) .. ratio, productAuction / need, false, locked)
		end
		local productVendor = HG.VendorPrice(recipe.product)
		if productVendor then
			Add(L.PROFIT_MAKE_VENDOR:format(name) .. ratio, productVendor / need, false, locked)
		end
	end

	local partner = BRONZE_PARTNER[id]
	if partner then
		local bronzeName, partnerName = PlainName(BRONZE_BAR), PlainName(partner)
		local bronze, partnerCost = AuctionNet(BRONZE_BAR), HG.AuctionPrice(partner)
		if bronzeName and partnerName and bronze and partnerCost then
			Add(L.PROFIT_MAKE_AUCTION:format(bronzeName) .. " (+ " .. partnerName .. ")",
				bronze * 2 - partnerCost, false, Locked(MINING, BRONZE_SKILL))
		end
	end

	local best
	for i, option in ipairs(options) do
		if not option.locked and (not best or option.value > options[best].value) then
			best = i
		end
	end
	return options, best, hasAuction
end

local hinted = false

function HG.ProfitLines(tooltip, id)
	local L = HG.L
	local options, best, hasAuction = HG.ProfitOptions(id)
	if not options then
		-- Обычный предмет: предупредим, если на аукционе выйдет меньше, чем у торговца.
		local auction, vendor = AuctionNet(id), HG.VendorPrice(id)
		if auction and vendor and auction < vendor then
			tooltip:AddLine(HG.Paint(L.AH_BELOW_VENDOR, "orange"))
		end
		return
	end

	if #options > 0 then
		tooltip:AddLine(" ")
		tooltip:AddLine(L.PROFIT_HEAD, 1, 0.82, 0)
		for i, option in ipairs(options) do
			local money = HG.Money(option.value)
			if option.locked then
				tooltip:AddLine(HG.Paint("  " .. option.label .. ": " .. money .. "  (" .. option.locked .. ")", "grey"))
			elseif i == best and #options > 1 then
				tooltip:AddLine(HG.Paint("> " .. option.label, "green") .. ": " .. money, 1, 1, 1)
			else
				tooltip:AddLine("  " .. option.label .. ": " .. money, 1, 1, 1)
			end
		end
	end

	if not HG.HasAuctionSource() then
		tooltip:AddLine(HG.Paint(L.PROFIT_NO_AH, "grey"))
		if not hinted then
			hinted = true
			HG.Say(L.PROFIT_HINT)
		end
	elseif not hasAuction then
		tooltip:AddLine(HG.Paint(L.PROFIT_NO_DATA, "grey"))
	end
end

------------------------------------------------------------------------
-- /hm bags — что выгоднее сделать с рудой и кожей в сумках
------------------------------------------------------------------------

-- Обычные сумки 0–4 и сумка для реагентов (5).
HG.LAST_BAG = math.max(5, _G.NUM_TOTAL_EQUIPPED_BAG_SLOTS or 0)

-- Количество каждого предмета в сумках: id -> штук.
function HG.BagCounts()
	local counts = {}
	if not (C_Container and C_Container.GetContainerNumSlots and C_Container.GetContainerItemInfo) then
		return counts
	end
	for bag = 0, HG.LAST_BAG do
		for slot = 1, HG.Num(C_Container.GetContainerNumSlots(bag)) or 0 do
			local info = HG.Tbl(C_Container.GetContainerItemInfo(bag, slot))
			local id = info and HG.Num(info.itemID)
			if id then
				counts[id] = (counts[id] or 0) + (HG.Num(info.stackCount) or 1)
			end
		end
	end
	return counts
end

-- Строки отчёта: как выгоднее продать руду и кожу из сумок.
function HG.BagReport()
	local L = HG.L
	local counts = HG.BagCounts()
	local ids = {}
	for id in pairs(counts) do
		if RECIPES[id] then
			ids[#ids + 1] = id
		end
	end
	table.sort(ids)
	local lines, total = {}, 0
	for _, id in ipairs(ids) do
		local options, best = HG.ProfitOptions(id)
		local name = PlainName(id)
		if best and name then
			local sum = options[best].value * counts[id]
			total = total + sum
			lines[#lines + 1] = ("  %s x%d: %s = %s"):format(name, counts[id], HG.Paint(options[best].label, "green"), HG.Money(sum))
		end
	end
	if #lines == 0 then
		lines[1] = L.BAGS_NONE
	else
		table.insert(lines, 1, L.BAGS_HEAD)
		lines[#lines + 1] = "  " .. L.BAGS_TOTAL:format(HG.Money(total))
	end
	if not HG.HasAuctionSource() then
		lines[#lines + 1] = HG.Paint(L.PROFIT_HINT, "grey")
	end
	HG.Signal("USED_BAGS")
	return lines
end

HG.commands.bags = function()
	for i, line in ipairs(HG.BagReport()) do
		if i == 1 then
			HG.Say(line)
		else
			print(line)
		end
	end
end
