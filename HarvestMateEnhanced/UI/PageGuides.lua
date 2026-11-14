-- HarvestMate Enhanced: UI/PageGuides.lua
-- Leveling guides 1-300: Gatherpedia's guide for each range (where to go,
-- what you'll find, training, gear, tips, recorded routes) with this
-- character's status on top: skill, cap, next milestone, training, advice,
-- and the Farm Finder's best farm for the current skill.
-- Copyright (C) 2026 HarvestMate Enhanced contributors. GPL-3.0-or-later.

local _, ns = ...
local HME = ns.HME
local T = ns.Theme
local K = HME.Kit

local PAGE_W = 738

HME.Pages.guides = function(body, page)
    local ui = HME.char.ui
    ui.guideProf = ui.guideProf or "Herbalism"
    local bracketKey

    local profs = K.Segments(body, K.PROFS, {}, function() return ui.guideProf end, function(k)
        ui.guideProf = k
        bracketKey = nil
        page.Refresh()
    end, 88)
    profs:SetPoint("TOPLEFT", 0, 0)

    local status = T.Card(body, "You", 0, -30, PAGE_W, 92)
    status.bar = K.Bar(status, 300, 16)
    status.bar:SetPoint("TOPLEFT", 12, -28)
    status.text = K.Label(status, "", { template = "GameFontHighlightSmall", width = PAGE_W - 340 })
    status.text:SetPoint("TOPLEFT", 324, -26)
    status.best = K.Button(status, "Best farm for my skill", 180, 24, function()
        HME.OpenWindow("finder")
        if HME.Pages.finderSet then HME.Pages.finderSet(ui.guideProf, "level") end
    end)
    status.best:SetPoint("BOTTOMLEFT", 12, 10)
    status.trainers = K.Button(status, "Trainers", 100, 22, function()
        HME.OpenWindow("trainers")
        if HME.Pages.trainersSet then HME.Pages.trainersSet(ui.guideProf) end
    end)
    status.trainers:SetPoint("LEFT", status.best, "RIGHT", 8, 0)
    status.levels = K.Button(status, "Skinning levels", 140, 24, function() HME.SkinTracker.Toggle() page.Refresh() end,
        "A small live display of the highest beast level you can skin and the levels that give points.", "primary")
    status.levels:SetPoint("LEFT", status.trainers, "RIGHT", 8, 0)

    -- Range buttons (one per guide bracket)
    local ranges = CreateFrame("Frame", nil, body)
    ranges:SetPoint("TOPLEFT", 0, -130)
    ranges:SetSize(PAGE_W, 22)
    ranges.buttons = {}

    local guide = T.Card(body, "Guide", 0, -160, PAGE_W, 354)
    local scroll = T.ScrollArea(guide, 300)
    scroll:ClearAllPoints()
    scroll:SetPoint("TOPLEFT", 12, -28)
    scroll:SetPoint("BOTTOMRIGHT", -12, 12)
    local content = scroll.child
    guide.text = K.Label(content, "", { template = "GameFontHighlightSmall", width = PAGE_W - 60 })
    guide.text:SetPoint("TOPLEFT", 0, 0)
    guide.spots = {}

    local function SpotRow(i)
        local r = guide.spots[i]
        if r then return r end
        r = CreateFrame("Frame", nil, content)
        r:SetSize(PAGE_W - 60, 26)
        r.text = K.Label(r, "", { template = "GameFontHighlight", width = 380, wrap = false })
        r.text:SetPoint("LEFT", 0, 0)
        r.go = K.Button(r, "Follow route", 110, 20, function(self) HME.Guidance.StartGuideSpot(self.spot, ui.guideProf) end,
            "Saves this recorded route and follows it, with the arrow and the map lines.")
        r.go:SetPoint("RIGHT", 0, 0)
        r.nav = K.Button(r, "Navigate", 90, 20, function(self)
            local s = self.spot
            if s and s.mapID then
                HME.FGPS.GoToPlace(s.mapID, (s.x or 50) / 100, (s.y or 50) / 100, s.label or s.zone)
            end
        end)
        r.nav:SetPoint("RIGHT", r.go, "LEFT", -6, 0)
        guide.spots[i] = r
        return r
    end

    function page.Refresh()
        profs:Refresh()
        local prof = ui.guideProf
        status.levels:SetShown(prof == "Skinning")
        status.levels:SetText(HME.SkinTracker.Shown() and "Hide Skinning levels" or "Skinning levels")
        local st = HME.Guide.Status(prof)
        if st.missing then
            status.bar:Set(0, 0, K.PROF_COLOR[prof], "not learned")
            status.text:SetText(st.messages[1] and st.messages[1][2] or "")
        else
            status.bar:Set(st.skill, st.max, K.PROF_COLOR[prof])
            status.bar:Mark(st.milestone and st.milestone.skill)
            local lines = {}
            lines[#lines + 1] = ("%s, cap %d (%s)"):format(prof, st.max, st.rank and st.rank.name or "")
            if st.milestone then lines[#lines + 1] = ("Next: %s at %d"):format(st.milestone.what, st.milestone.skill) end
            for _, m in ipairs(st.messages) do lines[#lines + 1] = m[2] end
            status.text:SetText(table.concat(lines, "\n"))
        end
        -- Brackets
        local brackets = ns.Guides and ns.Guides:Brackets(prof) or {}
        if not bracketKey then bracketKey = st.bracketKey or (brackets[1] and brackets[1].key) end
        local bw = math.floor(PAGE_W / math.max(1, #brackets))
        for i, b in ipairs(brackets) do
            local btn = ranges.buttons[i]
            if not btn then
                btn = K.Button(ranges, "", bw - 4, 22)
                ranges.buttons[i] = btn
            end
            btn:SetWidth(bw - 4)
            btn:ClearAllPoints()
            btn:SetPoint("LEFT", (i - 1) * bw, 0)
            btn:SetText(b.key)
            btn:SetScript("OnClick", function() bracketKey = b.key; page.Refresh() end)
            btn:SetKind(b.key == bracketKey and "primary" or "secondary")
            btn:Show()
        end
        for i = #brackets + 1, #ranges.buttons do ranges.buttons[i]:Hide() end
        local bracket = ns.Guides and bracketKey and ns.Guides:Bracket(prof, bracketKey)
        local lines = {}
        if bracket then
            local mine = st.skill and st.skill >= bracket.min and st.skill < bracket.max
            lines[#lines + 1] = ("|cffedf0f2%s|r   |cff78808cskill %d-%d%s|r"):format(bracket.title or "", bracket.min, bracket.max,
                mine and "  ·  you are here" or "")
            if bracket.short then lines[#lines + 1] = bracket.short end
            lines[#lines + 1] = ""
            if bracket.catches then lines[#lines + 1] = "|cff78808cWhat you'll find|r  " .. bracket.catches end
            if bracket.train then lines[#lines + 1] = "|cff78808cTraining|r  " .. bracket.train end
            if bracket.gear then lines[#lines + 1] = "|cff78808cGear|r  " .. bracket.gear end
            if bracket.tips then lines[#lines + 1] = "|cff78808cTips|r  " .. bracket.tips end
            lines[#lines + 1] = ""
            lines[#lines + 1] = "|cff78808cWhere to go|r (" .. HME.Player.Faction() .. ")"
        elseif ns.Guides then
            lines[#lines + 1] = ns.Guides:Intro(prof) or ""
        end
        guide.text:SetText(table.concat(lines, "\n"))
        local y = -(guide.text:GetStringHeight() or 200) - 8
        local spots = (bracket and ns.Guides:Spots(bracket, HME.Player.Faction())) or {}
        for i, spot in ipairs(spots) do
            local r = SpotRow(i)
            r:ClearAllPoints()
            r:SetPoint("TOPLEFT", 0, y)
            local hasRoute = ns.Guides:HasRoute(spot)
            r.text:SetText(("%s  |cff78808c%s%s|r"):format(spot.label or spot.zone or "?", spot.zone or "",
                hasRoute and "  ·  recorded route" or ""))
            r.go.spot, r.nav.spot = spot, spot
            r.go:SetShown(hasRoute)
            r.nav:SetShown(spot.mapID ~= nil)
            r:Show()
            y = y - 28
        end
        for i = #spots + 1, #guide.spots do guide.spots[i]:Hide() end
        scroll:SetContent(PAGE_W - 60, -y + 10, true)
    end
end
