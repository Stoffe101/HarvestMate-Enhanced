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
    ui.matProf = ui.matProf or "Herbalism"
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
    filt:SetPoint("TOPLEFT", 364, 0)
    local box = T.EditBox(body, LIST_W)
    box:SetPoint("TOPLEFT", 0, -30)
    box.hint = K.Label(box, "Search", { template = "GameFontDisableSmall" })
    box.hint:SetPoint("LEFT", 6, 0)
    box:SetScript("OnTextChanged", function(self)
        search = (self:GetText() or ""):lower()
        self.hint:SetShown(search == "")
        page.Refresh()
    end)

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
        width = LIST_W, height = 444, rowHeight = 30, empty = "Nothing matches.",
        makeRow = function(row)
            row.icon = K.Icon(row, 22)
            row.icon:SetPoint("LEFT", 4, 0)
            row.name = K.Label(row, "", { template = "GameFontHighlight", width = 190, wrap = false })
            row.name:SetPoint("LEFT", 32, 0)
            row.req = K.Label(row, "", { template = "GameFontHighlightSmall", justify = "RIGHT" })
            row.req:SetPoint("RIGHT", -8, 0)
        end,
        fillRow = function(row, e)
            row.icon.tex:SetTexture(ns.GetItemIcon(e))
            local hex = K.DIFF_HEX[Difficulty(e) or ""] or "ffffff"
            row.name:SetText(K.Paint(ns.GetItemName(e) or e.name or "?", hex))
            local req = e.skill or e.skillMin
            row.req:SetText(req and tostring(req) or (e.category or ""))
        end,
        onClick = function(e) selected = e; page.Detail(e) end,
    })
    list:SetPoint("TOPLEFT", 0, -60)

    local d = T.Card(body, "Field guide", LIST_W + 10, -30, PAGE_W - LIST_W - 10, 474)
    d.icon = K.Icon(d, 36)
    d.icon:SetPoint("TOPLEFT", 12, -28)
    d.title = K.Label(d, "", { template = "GameFontNormalLarge", color = C.gold, width = 340 })
    d.title:SetPoint("TOPLEFT", 56, -30)
    d.sub = K.Label(d, "", { template = "GameFontHighlightSmall", width = 340 })
    d.sub:SetPoint("TOPLEFT", 56, -50)
    local scroll = T.ScrollArea(d, 330)
    scroll:ClearAllPoints()
    scroll:SetPoint("TOPLEFT", 12, -72)
    scroll:SetPoint("BOTTOMRIGHT", -12, 44)
    d.text = K.Label(scroll.child, "", { template = "GameFontHighlightSmall", width = PAGE_W - LIST_W - 50 })
    d.text:SetPoint("TOPLEFT", 0, 0)
    d.farm = K.Button(d, "Farm this", 110, 22, function()
        if not selected then return end
        HME.OpenWindow("finder")
        if HME.Pages.finderSet then HME.Pages.finderSet(selected.prof, "material", selected.name) end
    end, "Opens the Farm Finder with this as the material to farm.")
    d.farm:SetPoint("BOTTOMLEFT", 12, 12)
    d.map = K.Button(d, "Spawns in my zone", 150, 22, function()
        if not selected then return end
        local mapID = HME.Geo.ZoneOf(HME.Player.Position())
        HME.MapOverlay.Preview({ prof = selected.prof, mapID = mapID, cx = 0.5, cy = 0.5, radius = 99999,
            targets = { { name = selected.name } }, zone = HME.ZoneData.Name(mapID) })
    end, "Opens the world map on your zone with this material's spawn points.")
    d.map:SetPoint("LEFT", d.farm, "RIGHT", 8, 0)
    d.farm:Hide()
    d.map:Hide()

    function page.Detail(e)
        d.icon.tex:SetTexture(ns.GetItemIcon(e))
        d.title:SetText(ns.GetItemName(e) or e.name or "?")
        local req = e.skill and ("needs " .. e.skill) or (e.skillMin and ("skill " .. e.skillMin .. "-" .. (e.skillMax or e.skillMin))) or ""
        d.sub:SetText(("%s  ·  %s  ·  %s"):format(e.category or "", req, e.status == "forever" and "confirmed for Forever"
            or (e.status == "classic" and "classic data" or "unverified")))
        local lines = {}
        if e.found then lines[#lines + 1] = e.found end
        if e.tiers then lines[#lines + 1] = ("Skill-up colors: |cfff5a345%d|r |cfffacc5c%d|r |cff8fcc5c%d|r |cff999b8f%d|r")
            :format(e.tiers[1], e.tiers[2], e.tiers[3], e.tiers[4]) end
        if e.id then
            local p = HME.Prices.Get(e.id)
            if p then
                local parts = {}
                if p.typical then parts[#parts + 1] = ("auction %s (%s, %s)"):format(K.Money(p.typical), p.source, HME.Prices.AgeText(p.age)) end
                if p.vendor then parts[#parts + 1] = "vendor " .. K.Money(p.vendor) end
                if #parts > 0 then lines[#lines + 1] = "|cff999b8fPrice|r  " .. table.concat(parts, "  ·  ") end
            end
        end
        lines[#lines + 1] = ""
        lines[#lines + 1] = "|cff999b8fKnown zones|r"
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
        scroll:SetContent(PAGE_W - LIST_W - 50, (d.text:GetStringHeight() or 300) + 10)
        d.farm:SetShown(e.prof ~= "Fishing")
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
        if selected and selected.prof == ui.matProf then page.Detail(selected) end
    end
end
