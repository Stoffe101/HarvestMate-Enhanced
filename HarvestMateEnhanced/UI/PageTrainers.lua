-- HarvestMate Enhanced: UI/PageTrainers.lua
-- Where to train (Gatherpedia's trainer list: every Herbalism, Mining,
-- Fishing and Skinning trainer and the fishing suppliers), for your faction,
-- nearest first in your zone. Navigate hands the trip to Forever-GPS when it
-- is installed, else HME's arrow.
-- Copyright (C) 2026 HarvestMate Enhanced contributors. GPL-3.0-or-later.

local _, ns = ...
local HME = ns.HME
local T = ns.Theme
local K = HME.Kit

local PAGE_W = 738

HME.Pages.trainers = function(body, page)
    local ui = HME.char.ui
    ui.trainerProf = ui.trainerProf or "All"
    local keys = { "All", "Herbalism", "Mining", "Skinning", "Fishing" }
    local seg = K.Segments(body, keys, {}, function() return ui.trainerProf end, function(k)
        ui.trainerProf = k
        page.Refresh()
    end, 100)
    seg:SetPoint("TOPLEFT", 0, 0)
    local note = K.Label(body, "", { template = "small", color = T.C.text2, width = PAGE_W, wrap = false })
    note:SetPoint("TOPLEFT", 2, -34)

    local list = K.List(body, {
        width = PAGE_W, height = 456, rowHeight = 50, empty = "No trainers listed.",
        makeRow = function(row)
            row.icon = row:CreateTexture(nil, "ARTWORK")
            row.icon:SetSize(26, 26)
            row.icon:SetPoint("LEFT", 12, 0)
            row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
            row.a = K.Label(row, "", { template = "strong", width = PAGE_W - 170, wrap = false })
            row.a:SetPoint("TOPLEFT", 48, -8)
            row.b = K.Label(row, "", { template = "small", color = T.C.text2, width = PAGE_W - 170, wrap = false })
            row.b:SetPoint("TOPLEFT", 48, -27)
            row.go = K.Button(row, "Navigate", 96, 26, function(self)
                local e = self.entry
                local mapID = e and ns.Zones and ns.Zones:MapID(e.zone)
                if mapID and e.x then
                    HME.FGPS.GoToPlace(mapID, e.x / 100, e.y / 100, e.name)
                else
                    HME.Print("no position is known for " .. tostring(e and e.name))
                end
            end, "Forever-GPS plans the trip when it is installed; otherwise HME's arrow points the way.")
            row.go:SetPoint("RIGHT", -12, 0)
        end,
        fillRow = function(row, e)
            local Tr = ns.Trainers
            row.icon:SetTexture(K.PROF_ICON[e.prof or ""] or "Interface\\Icons\\INV_Misc_Book_11")
            row.a:SetText(("%s  |cff999b8f%s %s|r"):format(e.name, e.prof or "", e.kind == "trainer" and (e.rank or "") or (e.kind or "")))
            row.b:SetText(Tr:WhereText(e) .. (e.x and ("  ·  " .. Tr:CoordsText(e)) or "") .. (e.note and ("  ·  " .. e.note) or ""))
            row.go.entry = e
            row.go:SetShown(e.x ~= nil)
        end,
    })
    list:SetPoint("TOPLEFT", 0, -56)

    HME.Pages.trainersSet = function(prof)
        ui.trainerProf = prof or "All"
        page.Refresh()
    end

    function page.Refresh()
        seg:Refresh()
        local Tr = ns.Trainers
        if not Tr then return end
        local faction = HME.Player.Faction()
        local items = {}
        for _, e in ipairs(Tr:All()) do
            local side = e.faction == "Neutral" or e.faction == faction or faction == "Neutral"
            if side and (ui.trainerProf == "All" or e.prof == ui.trainerProf) then items[#items + 1] = e end
        end
        local here = HME.Player.ZoneName()
        table.sort(items, function(a, b)
            local ha, hb = a.zone == here, b.zone == here
            if ha ~= hb then return ha end
            if a.zone ~= b.zone then return a.zone < b.zone end
            return a.name < b.name
        end)
        list:SetItems(items, true)
        local st = ui.trainerProf ~= "All" and HME.Guide.Status(ui.trainerProf) or nil
        local msg = st and st.messages and st.messages[1] and st.messages[1][2] or ""
        note:SetText(("%s trainers and suppliers for %s, your zone first.  %s"):format(#items, faction, msg))
    end
end
