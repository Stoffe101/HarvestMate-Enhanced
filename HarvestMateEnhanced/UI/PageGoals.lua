-- HarvestMate Enhanced: UI/PageGoals.lua
-- Goals & Plans: material, skill and gold goals with progress (held in bags
-- and gathered, kept apart), the best farm for each and how long it may take;
-- a staged leveling plan (e.g. Skinning 175 -> 300); saved profiles.
-- Copyright (C) 2026 HarvestMate Enhanced contributors. GPL-3.0-or-later.

local _, ns = ...
local HME = ns.HME
local T = ns.Theme
local K = HME.Kit
local U = HME.U
local C = T.C

local PAGE_W = 738

HME.Pages.goals = function(body, page)
    local scroll = T.ScrollArea(body, 514)
    local root = scroll.child
    local ui = HME.char.ui
    local currentPlan
    ui.goalType = ui.goalType or "item"
    ui.planProf = ui.planProf or "Skinning"

    -- New goal
    local add = T.Card(root, "New goal", 0, 0, PAGE_W - 20, 70)
    local typeLabels = { item = "Material", skill = "Profession skill", value = "Gold of materials" }
    local typ = T.Dropdown(add, 140, { "item", "skill", "value" }, typeLabels, function() return ui.goalType end,
        function(k) ui.goalType = k; page.Refresh() end)
    typ:SetPoint("TOPLEFT", 12, -32)
    local what = T.EditBox(add, 220)
    what:SetPoint("TOPLEFT", 160, -32)
    what.hint = K.Label(what, "", { template = "GameFontDisableSmall" })
    what.hint:SetPoint("LEFT", 6, 0)
    what:SetScript("OnTextChanged", function(self) self.hint:SetShown(self:GetText() == "") end)
    local amount = T.EditBox(add, 70)
    amount:SetPoint("TOPLEFT", 390, -32)
    amount:SetNumeric(true)
    local amountL = K.Label(add, "amount", { template = "GameFontDisableSmall" })
    amountL:SetPoint("LEFT", amount, "RIGHT", 6, 0)
    local status = K.Label(add, "", { template = "GameFontDisableSmall", width = 200 })
    status:SetPoint("TOPLEFT", 12, -56)
    local addBtn = K.Button(add, "Add goal", 100, 22, function()
        local text = U.Trim(what:GetText() or "")
        local n = tonumber(amount:GetText())
        local g, why
        if ui.goalType == "item" then
            local id
            for itemID, rec in pairs(ns.itemIndex) do
                if rec.entry.name and rec.entry.name:lower() == text:lower() then id = itemID end
            end
            if not id then
                for itemID, rec in pairs(ns.itemIndex) do
                    if not id and rec.entry.name and rec.entry.name:lower():find(text:lower(), 1, true) then id = itemID end
                end
            end
            g, why = HME.Goals.Add({ type = "item", itemID = id, target = n })
            if not id then why = "no gathered material by that name" end
        elseif ui.goalType == "skill" then
            local prof
            for _, p in ipairs(K.PROFS) do if p:lower():find(text:lower(), 1, true) then prof = p end end
            g, why = HME.Goals.Add({ type = "skill", prof = prof, target = n })
        else
            g, why = HME.Goals.Add({ type = "value", copper = n and n * 10000 })
        end
        status:SetText(g and ("Added: " .. g.name) or ("Not added: " .. tostring(why)))
        if g then what:SetText(""); amount:SetText(""); page.Refresh() end
    end)
    addBtn:SetPoint("TOPLEFT", 520, -32)

    -- Goals list (rows made as needed)
    local goalsCard = T.Card(root, "Your goals", 0, -78, PAGE_W - 20, 60)
    local rows = {}
    local function Row(i)
        if rows[i] then return rows[i] end
        local r = CreateFrame("Frame", nil, goalsCard)
        r:SetSize(PAGE_W - 44, 52)
        r.name = K.Label(r, "", { template = "GameFontNormal", color = C.title, width = 260, wrap = false })
        r.name:SetPoint("TOPLEFT", 0, 0)
        r.bar = K.Bar(r, 260, 14)
        r.bar:SetPoint("TOPLEFT", 0, -18)
        r.info = K.Label(r, "", { template = "GameFontHighlightSmall", width = 380 })
        r.info:SetPoint("TOPLEFT", 272, 0)
        r.find = K.Button(r, "Best farm", 90, 20, function(self)
            local g = self.goal
            self:SetText("...")
            HME.Goals.Recommend(g, function(res, eta)
                self:SetText("Best farm")
                if not res then
                    r.info:SetText("|cffff8a3d" .. tostring(eta) .. "|r")
                    return
                end
                local text = ("Best: %s (%s)"):format(res.zone, res.subarea)
                if type(eta) == "table" then
                    text = text .. ("  ·  about %s to go%s"):format(U.Duration(eta.hours * 3600),
                        eta.loops and ("  ·  ~%d loops"):format(math.ceil(eta.loops)) or "")
                end
                r.info:SetText(r.info:GetText():match("^[^\n]*") .. "\n" .. text)
                local q = HME.Goals.Query(g)
                if q then
                    HME.OpenWindow("finder")
                    if HME.Pages.finderSet then
                        local mats = {}
                        for id in pairs(q.targets or {}) do mats[#mats + 1] = HME.Goals.ItemName(id) end
                        HME.Pages.finderSet(q.prof, q.goal, #mats > 0 and table.concat(mats, ", ") or nil)
                    end
                end
            end)
        end, "Finds the best farm for this goal and opens it in the Farm Finder.")
        r.find:SetPoint("TOPRIGHT", -70, -26)
        r.del = K.Button(r, "Remove", 64, 20, function(self) HME.Goals.Remove(self.goal.id); page.Refresh() end)
        r.del:SetPoint("TOPRIGHT", 0, -26)
        rows[i] = r
        return r
    end

    -- Leveling plan
    local plan = T.Card(root, "Leveling plan", 0, -146, PAGE_W - 20, 60)
    local pprof = K.Segments(plan, K.PROFS, {}, function() return ui.planProf end, function(k) ui.planProf = k end, 88)
    pprof:SetPoint("TOPLEFT", 12, -30)
    local to = T.EditBox(plan, 50)
    to:SetPoint("TOPLEFT", 372, -30)
    to:SetNumeric(true)
    to:SetText("300")
    local toL = K.Label(plan, "target skill", { template = "GameFontDisableSmall" })
    toL:SetPoint("LEFT", to, "RIGHT", 6, 0)
    plan.text = K.Label(plan, "", { template = "GameFontHighlightSmall", width = PAGE_W - 50 })
    plan.text:SetPoint("TOPLEFT", 12, -60)
    local build = K.Button(plan, "Build plan", 100, 22, function(self)
        self:SetText("Planning...")
        plan.text:SetText("Working out each stage in the background...")
        HME.Guide.Plan(ui.planProf, tonumber(to:GetText()) or 300, function(p)
            self:SetText("Build plan")
            currentPlan = p
            page.Refresh()
        end)
    end, "Splits the climb into stages (at rank caps and every 40 points) and finds the best farm for each, "
        .. "as if you were already there. Rebuild it any time: it starts from your current skill.")
    build:SetPoint("TOPLEFT", 500, -30)

    -- Profiles
    local prof = T.Card(root, "Farming profiles", 0, -214, PAGE_W - 20, 60)
    prof.text = K.Label(prof, "", { template = "GameFontDisableSmall", width = PAGE_W - 50 })
    prof.text:SetPoint("TOPLEFT", 12, -28)
    local prow = {}

    local function PlanText(p)
        if not p then return "No plan yet." end
        local lines = { ("%s %d -> %d"):format(p.prof, p.from, p.to) }
        for _, st in ipairs(p.stages) do
            local f = st.farm
            local where = f and ("%s (%s)"):format(f.zone, f.subarea) or "no farm found for this stage"
            local hours = st.hours and (" · about %s (%s to %s)"):format(U.Duration(st.hours.mid * 3600),
                U.Duration(st.hours.low * 3600), U.Duration(st.hours.high * 3600)) or ""
            local alts = {}
            for _, a in ipairs(st.alternatives or {}) do if a then alts[#alts + 1] = a.zone end end
            lines[#lines + 1] = ("|cffffd100%d-%d|r  %s%s"):format(st.from, st.to, where, hours)
            if f and f.targets and f.targets[1] then
                local names = {}
                for i, t in ipairs(f.targets) do if i <= 3 then names[#names + 1] = t.name end end
                lines[#lines + 1] = "      " .. table.concat(names, ", ")
            end
            if #alts > 0 then lines[#lines + 1] = "      or: " .. table.concat(alts, ", ") end
            if st.train then
                lines[#lines + 1] = ("      |cffff8a3dthen train %s (character level %d)|r"):format(st.train.name, st.train.level)
            end
            if (st.level or 0) > HME.Player.Level() then
                lines[#lines + 1] = ("      |cff9a9a9aplanned for level %d|r"):format(st.level)
            end
        end
        if p.hours and p.hours.mid > 0 then
            lines[#lines + 1] = ("In all: about %s of farming (%s to %s), plus travel."):format(U.Duration(p.hours.mid * 3600),
                U.Duration(p.hours.low * 3600), U.Duration(p.hours.high * 3600))
        end
        return table.concat(lines, "\n")
    end

    function page.Refresh()
        typ:Refresh()
        pprof:Refresh()
        what.hint:SetText(({ item = "Heavy Leather", skill = "Skinning", value = "(leave empty)" })[ui.goalType])
        amountL:SetText(({ item = "how many", skill = "skill", value = "gold" })[ui.goalType])
        local goals = HME.Goals.List()
        local y = -28
        for i, g in ipairs(goals) do
            local r = Row(i)
            r:ClearAllPoints()
            r:SetPoint("TOPLEFT", 12, y)
            local p = HME.Goals.Progress(g)
            r.goal = g
            r.find.goal, r.del.goal = g, g
            r.name:SetText((g.doneAt and "|cff48c75a✓ |r" or "") .. g.name)
            local label
            if g.type == "value" then label = ("%s / %s"):format(U.Money(p.have or 0, true), U.Money(p.target, true))
            else label = ("%d / %d"):format(p.have or 0, p.target or 0) end
            r.bar:Set(p.fraction * 300, 300, g.doneAt and { 0.28, 0.78, 0.35 } or C.gold, label, 300)
            local info
            if g.type == "item" then
                info = ("In bags %d%s  ·  gathered since set: %d"):format(p.held or 0,
                    p.bank and ((" · bank %d (seen %s)"):format(p.bank, date and date("%d %b", p.bankAt or 0) or "")) or "",
                    p.gathered or 0)
            elseif g.type == "list" then
                local miss = {}
                for _, part in ipairs(p.parts) do
                    if part.missing > 0 then miss[#miss + 1] = ("%d %s"):format(part.missing, part.name) end
                end
                info = #miss > 0 and ("Missing: " .. table.concat(miss, ", ")) or "All there."
            elseif g.type == "skill" then
                info = ("%s now %d"):format(g.prof, p.have or 0)
            else
                info = "Value gathered since the goal was set (typical prices)."
            end
            r.info:SetText(info)
            r:Show()
            y = y - 56
        end
        for i = #goals + 1, #rows do rows[i]:Hide() end
        if #goals == 0 then
            goalsCard.title:SetText("YOUR GOALS: NONE YET — add one above")
        else
            goalsCard.title:SetText("YOUR GOALS")
        end
        local gh = math.max(40, -y + 6)
        goalsCard:SetHeight(gh)
        local py = -78 - gh - 8
        plan:ClearAllPoints()
        plan:SetPoint("TOPLEFT", 0, py)
        plan.text:SetText(PlanText(currentPlan))
        local ph = 70 + (plan.text:GetStringHeight() or 20)
        plan:SetHeight(ph)
        local fy = py - ph - 8
        prof:ClearAllPoints()
        prof:SetPoint("TOPLEFT", 0, fy)
        local list = HME.Profiles.List()
        prof.text:SetText(#list == 0 and "Save a search in the Farm Finder (Save) to start it again here or from the Dashboard."
            or "Start a saved setup in one click.")
        local yy = -46
        for i, p in ipairs(list) do
            local r = prow[i]
            if not r then
                r = CreateFrame("Frame", nil, prof)
                r:SetSize(PAGE_W - 44, 22)
                r.text = K.Label(r, "", { template = "GameFontHighlight", width = 450, wrap = false })
                r.text:SetPoint("LEFT", 0, 0)
                r.go = K.Button(r, "Start", 64, 20, function(self) HME.Profiles.Apply(self.p) end)
                r.go:SetPoint("RIGHT", -70, 0)
                r.del = K.Button(r, "Delete", 64, 20, function(self) HME.Profiles.Delete(self.p.name); page.Refresh() end)
                r.del:SetPoint("RIGHT", 0, 0)
                prow[i] = r
            end
            r:ClearAllPoints()
            r:SetPoint("TOPLEFT", 12, yy)
            r.text:SetText(("%s  |cff9a9a9a%s · %s · %s%s|r"):format(p.name, p.prof or "?", HME.Recommend.GOAL_LABEL[p.goal] or p.goal or "?",
                p.risk or "balanced", p.minutes and (" · " .. p.minutes .. " min") or ""))
            r.go.p, r.del.p = p, p
            r:Show()
            yy = yy - 26
        end
        for i = #list + 1, #prow do prow[i]:Hide() end
        local fh = math.max(52, -yy + 6)
        prof:SetHeight(fh)
        scroll:SetContent(PAGE_W - 20, -fy + fh + 10, true)
    end
    HME.Listen("GOALS_CHANGED", function() if body:IsVisible() then page.Refresh() end end)
end
