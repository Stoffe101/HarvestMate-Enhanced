local _, ns = ... local HG = ns.HG -- HME patch P1

-- Сообщения о начале сбора: строка в чат группы (если вы в группе)
-- и эмоция. Каждое включается отдельно, по умолчанию оба включены.
-- Не чаще раза в THROTTLE секунд, чтобы не засорять чат.

local THROTTLE = 8
-- Подпись аддона: в группе — в начале, в эмоции — в конце
-- (эмоция начинается с имени персонажа, подпись там мешала бы).
local TAG = "[" .. HG.title .. "]"

local TEXT = {
	herb = { party = "PARTY_HERB", emote = "EMOTE_HERB" },
	mine = { party = "PARTY_MINE", emote = "EMOTE_MINE" },
	skin = { party = "PARTY_SKIN", emote = "EMOTE_SKIN" },
}

local lastSent = -math.huge

-- Канал группы: подземелье по поиску, рейд или обычная группа.
local function GroupChannel()
	if not IsInGroup then
		return nil
	end
	local instance = LE_PARTY_CATEGORY_INSTANCE
	if instance and IsInGroup(instance) then
		return "INSTANCE_CHAT"
	end
	if IsInRaid and IsInRaid() then
		return "RAID"
	end
	if IsInGroup() then
		return "PARTY"
	end
	return nil
end

local function Send(text, channel)
	local send = (C_ChatInfo and C_ChatInfo.SendChatMessage) or _G.SendChatMessage
	if send then
		pcall(send, text, channel)
	end
end

-- Вызывается при начале сбора. name — что собираем (может быть nil).
function HG.AnnounceGather(prof, name)
	local keys = TEXT[prof]
	local opt = HG.db and HG.db.opt
	if not keys or not HG.Active() or not opt[prof] then
		return
	end
	if not opt.announceParty and not opt.announceEmote then
		return
	end
	local now = GetTime()
	if now - lastSent < THROTTLE then
		return
	end
	local L = HG.L
	local what = name or HG.ProfName(prof)
	local sent = false
	if opt.announceParty then
		local channel = GroupChannel()
		if channel then
			Send(TAG .. " " .. L[keys.party]:format(what), channel)
			sent = true
		end
	end
	if opt.announceEmote then
		Send(L[keys.emote]:format(what) .. " " .. TAG, "EMOTE")
		sent = true
	end
	if sent then
		lastSent = now
	end
end

HG.Listen("GATHER_START", HG.AnnounceGather)
