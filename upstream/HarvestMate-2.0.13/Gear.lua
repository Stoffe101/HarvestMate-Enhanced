local _, HG = ...

-- Вещи с бонусом к сбору и место в сумках.
--
-- Аддон ищет в сумках вещи, в подсказке которых есть название профессии
-- и «+N» (перчатки травника, чары на перчатках, нож для шкур и т.п.).
-- Когда вы подходите к ресурсу этой профессии, он либо напоминает о вещи,
-- либо (если включено) надевает её и возвращает прежнюю, когда вы отошли.

local SLOT = {
	INVTYPE_HEAD = 1, INVTYPE_HAND = 10, INVTYPE_FINGER = 11, INVTYPE_TRINKET = 13,
	INVTYPE_WEAPON = 16, INVTYPE_WEAPONMAINHAND = 16, INVTYPE_2HWEAPON = 16,
}
local PROFS = { "herb", "mine", "skin" }
local HINT_REPEAT = 600  -- одно напоминание про вещь не чаще раза в 10 минут
local RESTORE_DELAY = 3  -- секунд после ухода от ресурса
local FEW_SLOTS = 2
local BAGS_REPEAT = 120

local GetItemInfo = (C_Item and C_Item.GetItemInfo) or _G.GetItemInfo

local found = {}      -- prof -> { link, name, slot, bonus }
local dirty = true
local swapped = {}    -- слот -> ссылка на прежнюю вещь (false, если слот был пуст)
local near            -- профессия ресурса, у которого стоим
local lastHint = {}
local lastBagWarn = -math.huge

local function Equip(link, slot)
	local equip = (C_Item and C_Item.EquipItemByName) or _G.EquipItemByName
	if equip then
		pcall(equip, link, slot)
	end
end

local function Scan()
	dirty = false
	found = {}
	if not (C_Container and C_Container.GetContainerNumSlots and C_TooltipInfo and C_TooltipInfo.GetBagItem) then
		return
	end
	for bag = 0, HG.LAST_BAG do
		for slot = 1, HG.Num(C_Container.GetContainerNumSlots(bag)) or 0 do
			local info = HG.Tbl(C_Container.GetContainerItemInfo(bag, slot))
			local id = info and HG.Num(info.itemID)
			local link = info and HG.Str(info.hyperlink)
			local equipLoc = id and select(9, GetItemInfo(id))
			local inventorySlot = equipLoc and SLOT[equipLoc]
			if link and inventorySlot then
				local ok, data = pcall(C_TooltipInfo.GetBagItem, bag, slot)
				local lines = ok and HG.Tbl(data) and HG.Tbl(data.lines)
				for _, line in ipairs(lines or {}) do
					local text = HG.Tbl(line) and HG.Str(line.leftText)
					local bonus = text and tonumber(text:match("%+(%d+)"))
					if bonus then
						for _, prof in ipairs(PROFS) do
							if text:find(HG.ProfName(prof), 1, true) and (not found[prof] or bonus > found[prof].bonus) then
								found[prof] = { link = link, name = HG.Str((GetItemInfo(id))) or link, slot = inventorySlot, bonus = bonus }
							end
						end
					end
				end
			end
		end
	end
end

local function Busy()
	if InCombatLockdown and InCombatLockdown() then
		return true
	end
	return UnitCastingInfo ~= nil and UnitCastingInfo("player") ~= nil
end

local function Restore()
	if near or next(swapped) == nil then
		return
	end
	if Busy() then
		HG.Soon("gear", RESTORE_DELAY, Restore)
		return
	end
	for slot, previous in pairs(swapped) do
		if previous then
			Equip(previous, slot)
		end
		swapped[slot] = nil
	end
	dirty = true
end

HG.Listen("NEAR_NODE", function(prof)
	near = prof
	local opt = HG.db.opt
	if not opt.gearWarn or not HG.Skill(prof) then
		return
	end
	if dirty then
		Scan()
	end
	local item = found[prof]
	if not item then
		return
	end
	if opt.gearSwap then
		if not Busy() and swapped[item.slot] == nil then
			swapped[item.slot] = HG.Str(GetInventoryItemLink("player", item.slot)) or false
			Equip(item.link, item.slot)
			dirty = true
		end
		return
	end
	local now = GetTime()
	if not lastHint[item.link] or now - lastHint[item.link] >= HINT_REPEAT then
		lastHint[item.link] = now
		HG.Say(HG.L.GEAR_HINT:format(item.name, HG.ProfName(prof)))
	end
end)

HG.Listen("NEAR_NONE", function()
	if near then
		near = nil
		if next(swapped) ~= nil then
			HG.Soon("gear", RESTORE_DELAY, Restore)
		end
	end
end)

HG.On("BAG_UPDATE_DELAYED", function()
	dirty = true
end)
HG.On("PLAYER_REGEN_ENABLED", Restore)
HG.Listen("SKILLS", function()
	dirty = true
end)

------------------------------------------------------------------------
-- Место в сумках
------------------------------------------------------------------------

function HG.FreeBagSlots()
	if not (C_Container and C_Container.GetContainerNumFreeSlots) then
		return nil
	end
	local free = 0
	for bag = 0, HG.LAST_BAG do
		free = free + (HG.Num(C_Container.GetContainerNumFreeSlots(bag)) or 0)
	end
	return free
end

HG.Listen("GATHER_START", function()
	local free = HG.FreeBagSlots()
	if not free or free > FEW_SLOTS then
		return
	end
	local now = GetTime()
	if now - lastBagWarn < BAGS_REPEAT then
		return
	end
	lastBagWarn = now
	local text = HG.L.BAGS_FULL:format(free)
	HG.FlashBanner("bags", text, 5, "capped")
	HG.Say("|cffff8c1a" .. text .. "|r")
end)
