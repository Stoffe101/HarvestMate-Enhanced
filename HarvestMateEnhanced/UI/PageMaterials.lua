-- HarvestMate Enhanced: UI/PageMaterials.lua
-- The field guide (Gatherpedia's, in HME's look): every herb, ore, fish and
-- hide, colored for your skill, with where it comes from (Known zones, your
-- own counts merged in), its price and where it came from, and buttons to
-- farm it or see its spawns on the map.
-- Copyright (C) 2026 HarvestMate Enhanced contributors. GPL-3.0-or-later.

local _, ns = ...
local HME = ns.HME
local T = ns.Theme
local K = HME.Kit
local U = HME.U
local C = T.C

local PAGE_W = 738
local LIST_W = 300

local FILTERS = { "all", "gather", "skillup", "zone" }
local FILTER_LABELS = { all = "All", gather = "Can gather", skillup = "Skill-ups", zone = "This zone" }

HME.Pages.materials = function(body, page)
    local ui = HME.char.ui
    -- Open on a profession this character has (0.4.0 always began at Herbalism).
    if not ui.matProf or not HME.Player.Professions()[ui.matProf] then
        for _, p in ipairs(K.PROFS) do
            if HME.Player.Professions()[p] then ui.matProf = p break end
        end
        ui.matProf = ui.matProf or "Herbalism"
    end
    ui.matFilter = ui.matFilter or "all"
    local search = ""
    local selected

    local profs = K.Segments(body, K.PROFS, {}, function() return ui.matProf end, function(k)
        ui.matProf = k
        page.Refresh()
    end, 88)
    profs:SetPoint("TOPLEFT", 0, 0)
    local filt = K.Segments(body, FILTERS, FILTER_LABELS, function() return ui.matFilter end, function(k)
        ui.matFilter = k
        page.Refresh()
    end, 86)
    filt:SetPoint("TOPRIGHT", 0, 0)
    local box = T.EditBox(body, LIST_W)
    box:SetPoint("TOPLEFT", 0, -36)
    box.hint = K.Label(box, "Search", { template = "GameFontDisableSmall" })
    box.hint:SetPoint("LEFT", 6, 0)
    box:SetScript("OnTextChanged", function(self)
        search = (self:GetText() or ""):lower()
        self.hint:SetShown(search == "")
        page.Refresh()
    end)

    local DIFF_WORD = { orange = "a point every time", yellow = "points often", green = "points sometimes",
        grey = "no points", red = "skill too low" }
    local function Difficulty(entry)
        local rank = ns.GetPlayerSkill(entry.prof)
        if entry.prof == "Skinning" then
            if not rank or not entry.skillMin then return nil end
            if rank < entry.skillMin then return "red" end
            if rank < (entry.skillMax or entry.skillMin) then return "yellow" end
            return "green"
        end
        local d = ns.GetDifficulty(entry, rank)
        if d == "gray" then return "grey" end
        if d == "ok" then return "green" end
        return HME.SkillModel.HEX[d] and d or nil
    end

    local list = K.List(body, {
        width = LIST_W, height = 448, rowHeight = 40, empty = "Nothing matches. Clear the search or choose All.",
        makeRow = function(row)
            row.icon = K.Icon(row, 28)
            row.icon:SetPoint("LEFT", 8, 0)
            row.name = K.Label(row, "", { template = "strong", width = LIST_W - 110, wrap = false })
            row.name:SetPoint("TOPLEFT", 44, -5)
            row.cat = K.Label(row, "", { template = "meta", width = LIST_W - 110, wrap = false })
            row.cat:SetPoint("TOPLEFT", 44, -22)
            row.req = K.Label(row, "", { template = "strong", width = 48, wrap = false, justify = "RIGHT" })
            row.req:SetPoint("RIGHT", -14, 0)
        end,
        fillRow = function(row, e)
            row.icon.tex:SetTexture(ns.GetItemIcon(e))
            local diff = Difficulty(e)
            local hex = K.DIFF_HEX[diff or ""] or "f2f0e6"
            row.name:SetText(ns.GetItemName(e) or e.name or "?")
            row.cat:SetText((e.category or "") .. (diff and ("  ·  " .. K.Paint(DIFF_WORD[diff] or diff, hex)) or ""))
            local req = e.skill or e.skillMin
            row.req:SetText(req and K.Paint(tostring(req), hex) or "")
        end,
        onClick = function(e) selected = e; page.Detail(e) end,
    })
    list:SetPoint("TOPLEFT", 0, -66)

    local DW = PAGE_W - LIST_W - 10
    local d = T.Card(body, "", LIST_W + 10, -36, DW, 478)
    d.title:Hide()
    d.tick:Hide()
    d.icon = K.Icon(d, 46)
    d.icon:SetPoint("TOPLEFT", 14, -14)
    d.name = K.Label(d, "", { template = "title", size = 18, width = DW - 90, wrap = false })
    d.name:SetPoint("TOPLEFT", 72, -16)
    d.sub = K.Label(d, "", { template = "meta", width = DW - 90, wrap = false })
    d.sub:SetPoint("TOPLEFT", 72, -40)
    -- Three tiles: what it needs, what it is worth, what you have gathered.
    local tileW = (DW - 28 - 12) / 3
    d.kpi = {}
    for i, label in ipairs({ "Skill needed", "Price", "You gathered" }) do
        local t = K.Stat(d, label, tileW, 72)
        t:SetPoint("TOPLEFT", 14 + (i - 1) * (tileW + 6), -72)
        t.bg:Paint(C.field)
        t.size = 20
        d.kpi[i] = t
    end
    local scroll = T.ScrollArea(d, 250)
    scroll:ClearAllPoints()
    scroll:SetPoint("TOPLEFT", 14, -156)
    scroll:SetPoint("BOTTOMRIGHT", -12, 52)
    d.text = K.Label(scroll.child, "", { template = "small", width = DW - 44 })
    if d.text.SetSpacing then d.text:SetSpacing(3) end
    d.text:SetPoint("TOPLEFT", 0, 0)
    d.empty = K.Empty(d, "Interface\\Icons\\INV_Misc_Book_09", "Pick a material",
        "Every herb, ore, fish and hide: where it grows, what it needs, what it is worth and what you have gathered.", DW - 40)
    d.empty:SetPoint("TOP", 0, -120)
    local divider = d:CreateTexture(nil, "BORDER")
    divider:SetPoint("BOTTOMLEFT", 12, 46)
    divider:SetPoint("BOTTOMRIGHT", -12, 46)
    divider:SetHeight(1)
    divider:SetColorTexture(unpack(C.line))
    d.farm = K.Button(d, "Farm this", 110, 30, function()
        if not selected then return end
        HME.OpenWindow("finder")
        if HME.Pages.finderSet then HME.Pages.finderSet(selected.prof, "material", selected.name) end
    end, "Opens the Farm Finder with this as the material to farm.", "primary")
    d.farm:SetPoint("BOTTOMRIGHT", -12, 10)
    d.goal = K.Button(d, "Add goal", 90, 30, function()
        if not (selected and selected.id) then return end
        local g, why = HME.Goals.Add({ type = "item", itemID = selected.id, target = 20 })
        HME.Print(g and ("goal added: 20 %s (change it on Goals & Plans)."):format(g.name) or ("no goal: " .. tostring(why)))
    end, "Adds a goal of 20 (change the number on Goals & Plans); it counts what you gather.")
    d.goal:SetPoint("RIGHT", d.farm, "LEFT", -8, 0)
    d.map = K.Button(d, "Spawns in my zone", 140, 30, function()
        if not selected then return end
        local mapID = HME.Geo.ZoneOf(HME.Player.Position())
        HME.MapOverlay.Preview({ prof = selected.prof, mapID = mapID, cx = 0.5, cy = 0.5, radius = 99999,
            targets = { { name = selected.name } }, zone = HME.ZoneData.Name(mapID) })
    end, "Opens the world map on your zone with this material's spawn points.", "ghost")
    d.map:SetPoint("BOTTOMLEFT", 12, 10)
    for _, w in ipairs({ d.farm, d.map, d.goal, d.kpi[1], d.kpi[2], d.kpi[3] }) do w:Hide() end

    function page.Detail(e)
        d.empty:Hide()
        for _, w in ipairs({ d.kpi[1], d.kpi[2], d.kpi[3] }) do w:Show() end
        d.icon:Show()
        d.icon.tex:SetTexture(ns.GetItemIcon(e))
        local diff = Difficulty(e)
        local hex = K.DIFF_HEX[diff or ""] or "f2f0e6"
        d.name:SetText(K.Paint(ns.GetItemName(e) or e.name or "?", hex))
        d.sub:SetText(("%s  ·  %s  ·  %s"):format(e.prof or "", e.category or "", e.status == "forever" and "confirmed for Forever"
            or (e.status == "classic" and "classic data, may differ on Forever" or "not yet confirmed")))
        -- Skill needed, and your colour for it.
        local req = e.skill or e.skillMin
        local rank = ns.GetPlayerSkill(e.prof)
        d.kpi[1]:Set(req and (e.skillMax and e.skillMax ~= req and (req .. "–" .. e.skillMax) or tostring(req)) or "–",
            rank and ("you: %d%s"):format(rank, diff and (", " .. (DIFF_WORD[diff] or diff)) or "") or "not learned",
            K.Rgb and { K.Rgb(hex) } or C.text)
        -- Price: an auction estimate apart from what a vendor pays.
        local p = e.id and HME.Prices.Get(e.id)
        if p and p.typical then
            d.kpi[2]:Set(K.Money(p.typical), "auction estimate", C.gold)
        elseif p and p.vendor then
            d.kpi[2]:Set(K.Money(p.vendor), "vendor (no auction price)", C.gold)
        else
            d.kpi[2]:Set("–", "no price known", C.text3)
        end
        -- What you have gathered, from the field guide's counts.
        local counts = ns.db.counts and e.id and ns.db.counts[e.id]
        local total, zones = 0, 0
        for _, q in pairs(counts or {}) do total, zones = total + q, zones + 1 end
        d.kpi[3]:Set(total > 0 and U.Thousands(total) or "0", total > 0 and ("in %d zone%s"):format(zones, zones == 1 and "" or "s")
            or "none yet", total > 0 and C.text or C.text3)
        local lines = {}
        if e.found then lines[#lines + 1] = e.found end
        if e.tiers then
            lines[#lines + 1] = ("|cff999b8fSkill-up colours|r  |cfff5a345%d|r  ·  |cfffacc5c%d|r  ·  |cff8fcc5c%d|r  ·  |cff999b8f%d|r")
                :format(e.tiers[1], e.tiers[2], e.tiers[3], e.tiers[4])
        end
        if p and p.typical and p.vendor then lines[#lines + 1] = ("|cff999b8fVendor|r  %s"):format(K.Money(p.vendor)) end
        if p and p.typical and p.source then
            lines[#lines + 1] = ("|cff999b8fPrice from|r  %s, %s"):format(p.source, HME.Prices.AgeText(p.age) or "age unknown")
        end
        lines[#lines + 1] = ""
        lines[#lines + 1] = "|cff999b8fWhere it is|r  " .. K.Paint("(> your zone; ×N what you gathered there)", T.HEX.text3)
        local Zones = ns.Zones
        local view = ns:SourceZones(e)
        local counts = ns.db.counts and e.id and ns.db.counts[e.id]
        local here = HME.Player.ZoneName()
        local faction = HME.Player.Faction()
        local rows, hint = {}, nil
        if Zones and Zones.Build then
            rows, hint = Zones:Build({ zones = view, zoneNotes = e.zoneNotes, prof = e.prof, water = e.water }, counts, here, faction,
                ns.db.options and ns.db.options.onlyGatheredZones)
        end
        if hint then lines[#lines + 1] = "|cff999b8f" .. hint .. "|r" end
        for i, r in ipairs(rows) do
            if i > 24 then lines[#lines + 1] = "  ..." break end
            local name = r.zone or "?"
            local tag = r.faction and (r.faction == faction and " |cff8fcc5c(your side)|r" or " |cfff5a345(" .. r.faction .. ")|r") or ""
            if r.yours then tag = tag .. " |cff6fcf97yours|r" end
            local mine = (r.n or 0) > 0 and (" |cffffd100x" .. r.n .. "|r") or ""
            local note = r.note and ("  |cff999b8f" .. r.note .. "|r") or ""
            local cur = name == here and "|cffffffff> |r" or "  "
            lines[#lines + 1] = cur .. name .. tag .. mine .. note
        end
        d.text:SetText(table.concat(lines, "\n"))
        scroll:SetContent(DW - 44, (d.text:GetStringHeight() or 300) + 10)
        d.farm:SetShown(e.prof ~= "Fishing")
        d.goal:SetShown(e.id ~= nil)
        d.map:SetShown(e.prof == "Herbalism" or e.prof == "Mining")
    end

    function page.Refresh()
        profs:Refresh()
        filt:Refresh()
        local def = ns.professions[ui.matProf]
        local items = {}
        local here = HME.Player.ZoneName()
        for _, e in ipairs(def and def.items or {}) do
            local name = (e.name or ""):lower()
            local ok = search == "" or name:find(search, 1, true)
            if ok and ui.matFilter ~= "all" then
                local diff = Difficulty(e)
                if ui.matFilter == "gather" then ok = diff ~= nil and diff ~= "red"
                elseif ui.matFilter == "skillup" then ok = diff == "orange" or diff == "yellow" or diff == "green"
                elseif ui.matFilter == "zone" then ok = U.Contains(ns:SourceZones(e), here) end
            end
            if ok and not e.placeholder then items[#items + 1] = e end
        end
        list:SetItems(items, true)
        -- Something is always open: the last one, else the first that gives skill-ups, else the first.
        if not (selected and selected.prof == ui.matProf) then
            selected = nil
            for _, e in ipairs(items) do
                local diff = Difficulty(e)
                if diff == "orange" or diff == "yellow" then selected = e break end
            end
            selected = selected or items[1]
        end
        if selected then
            for i, e in ipairs(items) do if e == selected then list:Select(i) end end
            page.Detail(selected)
        else
            d.empty:Show()
            d.text:SetText("")
            for _, w in ipairs({ d.farm, d.map, d.goal, d.kpi[1], d.kpi[2], d.kpi[3], d.icon }) do w:Hide() end
            d.name:SetText("")
            d.sub:SetText("")
        end
    end
end
