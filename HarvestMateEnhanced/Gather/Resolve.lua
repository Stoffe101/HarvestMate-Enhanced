local _, ns = ... local HG = ns.HG -- HME patch P1

-- Имя из подсказки -> ресурс, и текст, который мы добавляем к имени.

-- Убирает цвета, иконки и наш собственный хвост " (42/50)".
function HG.CleanName(text)
	if type(text) ~= "string" then
		return nil
	end
	text = text:gsub("|c%x%x%x%x%x%x%x%x", "")
	text = text:gsub("|cn[^:|]*:", "") -- новый формат цвета: |cnNORMAL_FONT_COLOR:
	text = text:gsub("|H.-|h(.-)|h", "%1") -- ссылки: оставляем видимый текст
	text = text:gsub("|K.-|k", "")
	text = text:gsub("|r", "")
	text = text:gsub("|T.-|t", "")
	text = text:gsub("|A.-|a", "")
	text = text:gsub("%s*%(\226?\137?\164?%d+/%d+%+?%)%s*$", "")
	text = text:gsub("%s*%(\226?\137?\164?%d+%+?%)%s*$", "")
	text = text:match("^%s*(.-)%s*$")
	if text == "" then
		return nil
	end
	return text
end

-- Английское имя -> имя на языке клиента (если есть перевод).
local localNames
function HG.DisplayName(name)
	if not localNames then
		localNames = {}
		for loc, en in pairs(HG.alias) do
			-- Из нескольких вариантов (ё/е) берём первый по алфавиту — стабильно.
			if not localNames[en] or loc < localNames[en] then
				localNames[en] = loc
			end
		end
	end
	return localNames[name] or name
end

-- Ресурс по имени (английскому, локализованному или изученному).
function HG.Find(name)
	if not name then
		return nil
	end
	local english = HG.alias[name] or name
	local known = HG.RESOURCES[english]
	if known then
		return known
	end
	local custom = HG.db and HG.db.learned.custom[name]
	if type(custom) == "table" and HG.PROF[custom.prof] then
		return custom
	end
	return nil
end

-- Требуемый навык с учётом изученного: если ресурс уже собирали с меньшим
-- навыком, требование не может быть выше этого навыка.
function HG.Requirement(entry)
	local lowest = HG.db and HG.db.learned.lowest[entry.key]
	if type(lowest) == "number" and (not entry.req or lowest < entry.req) then
		return lowest
	end
	return entry.req
end

-- Цифры в скобках по настройкам: "42/50", "42", "50" или nil.
function HG.Numbers(skill, req)
	local opt = HG.db.opt
	if opt.showOwn and opt.showReq then
		return skill .. "/" .. req
	elseif opt.showOwn then
		return tostring(skill)
	elseif opt.showReq then
		return tostring(req)
	end
	return nil
end

-- Цвет по профессии. Для взлома замков точных порогов нет: красный, если
-- навыка мало, иначе зелёный.
function HG.ColorFor(prof, skill, req)
	if prof == "lock" then
		return skill < req and "red" or "green"
	end
	return HG.Difficulty(skill, req)
end

-- Готовая строка для имени ресурса либо nil, если менять нечего.
function HG.Describe(name, entry)
	local opt = HG.db.opt
	if not opt[entry.prof] then
		return nil
	end
	local info = HG.SkillInfo(entry.prof)
	local req = HG.Requirement(entry)
	if not info or not req then
		return nil
	end
	local skill = info.cur
	local skillText = info.estimate and ("~" .. skill) or tostring(skill)
	local reqText = entry.varies and (req .. "+") or tostring(req)
	local text = name
	local numbers = HG.Numbers(skillText, reqText)
	if numbers then
		text = text .. " (" .. numbers .. ")"
	end
	if opt.colorize then
		text = HG.Paint(text, HG.ColorFor(entry.prof, skill, req))
	end
	if text == name then
		return nil
	end
	return text
end
