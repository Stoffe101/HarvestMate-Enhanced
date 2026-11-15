-- HarvestMate Enhanced: UI/PageBeasts.lua (0.6.0)
-- The Skinning Explorer: every beast in the bundled data as a profile.
--   left    search by name, zone, level ("35") or material ("medium leather"),
--           filters (can skin, skill-ups, this zone, skinned by you) and
--           order (best for you, level, name)
--   right   the creature: Skinning needed and your colour, a rough rate for
--           you, your own skins; then whether the game confirmed it can be
--           skinned, what it gives per skin (yours apart from the estimate),
--           your drop journal, corpse loot apart, kill time, where it lives,
--           quests in your log that want it; Hunt it plans circuits for it.
-- Copyright (C) 2026 HarvestMate Enhanced contributors. GPL-3.0-or-later.

local _, ns = ...
local HME = ns.HME
local T = ns.Theme
local K = HME.Kit
local U = HME.U
local C = T.C

local PAGE_W = 738
local LIST_W = 300

local FILTERS = { "all", "canskin", "skillup", "zone", "skinned" }
local FILTER_LABELS = { all = "All", canskin = "Can skin", skillup = "Skill-ups", zone = "This zone", skinned = "Skinned" }
local SORTS = { "forme", "level", "name" }
local SORT_LABELS = { forme = "Best for you", level = "By level", name = "By name" }
local COLOR_WORD = { orange = "every time", yellow = "often", green = "sometimes", grey = "never", red = "too low" }
-- Why a creature is not for you, in a tile's few words.
local function ShortWhy(why)
    why = why or ""
    if why:find("needs") then return "more skill needed" end
    if why:find("elite") then return "elite" end
    if why:find("above") then return "level too high" end
    if why:find("skinned") then return "not skinnable" end
    if why:find("know") then return "no Skinning" end
    return "not for you"
end

HME.Pages.beasts = function(body, page)
    local Bx = HME.Bestiary
    local ui = HME.char.ui
    ui.bxFilter = ui.bxFilter or "canskin"
    ui.bxSort = ui.bxSort or "forme"
    local search = ""
    local selected
    local mats = {}

    local box = T.EditBox(body, LIST_W)
    box:SetPoint("TOPLEFT", 0, 0)
    box.hint = K.Label(box, "Creature, zone, level or leather", { template = "GameFontDisableSmall" })
    box.hint:SetPoint("LEFT", 6, 0)
    box:SetScript("OnTextChanged", function(self)
        search = (self:GetText() or ""):lower()
        self.hint:SetShown(search == "")
        HME.Soon("beasts-search", 0.25, function() page.Refresh() end)
    end)
    local filt = K.Segments(body, FILTERS, FILTER_LABELS, function() return ui.bxFilter end, function(k)
        ui.bxFilter = k
        page.Refresh()
    end, 86)
    filt:SetPoint("TOPRIGHT", 0, 0)
    local sort = T.Dropdown(body, 150, SORTS, SORT_LABELS, function() return ui.bxSort end, function(k)
        ui.bxSort = k
        page.Refresh()
    end)
    sort:SetPoint("TOPLEFT", 0, -34)
    sort.menuTitle = "Order"
    local count = K.Label(body, "", { template = "meta", width = LIST_W - 160, wrap = false, justify = "RIGHT" })
    count:SetPoint("TOPLEFT", 158, -40)
    T.Tooltip(count, "Found", "How many creatures match, and the material your search named.")

    local profile
    local function Color(e)
        local skill = profile and profile.skills.Skinning and profile.skills.Skinning.rank
        if not skill then return nil end
        local req = HME.SkillModel.SkinReq(e.min)
        if skill < req then return "red" end
        return HME.SkillModel.Color(skill, HME.SkillModel.SkinReq(math.floor((e.min + e.max) / 2 + 0.5)))
    end

    local list = K.List(body, {
        width = LIST_W, height = 444, rowHeight = 40, empty = "Nothing matches. Clear the search or choose All.",
        makeRow = function(row)
            row.name = K.Label(row, "", { template = "strong", width = LIST_W - 96, wrap = false })
            row.name:SetPoint("TOPLEFT", 10, -5)
            row.sub = K.Label(row, "", { template = "meta", width = LIST_W - 96, wrap = false })
            row.sub:SetPoint("TOPLEFT", 10, -22)
            row.req = K.Label(row, "", { template = "strong", width = 70, wrap = false, justify = "RIGHT" })
            row.req:SetPoint("TOPRIGHT", -12, -5)
            row.mine = K.Label(row, "", { template = "meta", width = 70, wrap = false, justify = "RIGHT" })
            row.mine:SetPoint("TOPRIGHT", -12, -22)
        end,
        fillRow = function(row, e)
            local c = Color(e)
            local hex = K.DIFF_HEX[c or ""] or T.HEX.text
            row.name:SetText(e.name .. (e.elite and K.Paint("  elite", T.HEX.warning) or ""))
            T.FitText(row.name, LIST_W - 96, "strong", 13, 11)
            local map = Bx.BestMap(e)
            local rec = HME.db.obs.skins[e.npcID]
            row.sub:SetText(("Level %s  ·  %s"):format(e.min == e.max and e.min or (e.min .. "-" .. e.max),
                map and (HME.ZoneData.Name(map) or "?") or "unknown zone"))
            row.req:SetText(K.Paint(tostring(HME.SkillModel.SkinReq(e.min)), hex))
            row.mine:SetText(rec and rec.n and rec.n > 0 and K.Paint(("%d skins"):format(rec.n), T.HEX.accent) or "")
        end,
        onClick = function(e) selected = e page.Detail(e) end,
    })
    list:SetPoint("TOPLEFT", 0, -66)

    ---------------------------------------------------------------- detail
    local DW = PAGE_W - LIST_W - 10
    local d = T.Card(body, "", LIST_W + 10, -34, DW, 476)
    d.title:Hide()
    d.tick:Hide()
    d.name = K.Label(d, "", { template = "title", size = 18, width = DW - 28, wrap = false })
    d.name:SetPoint("TOPLEFT", 14, -14)
    d.sub = K.Label(d, "", { template = "meta", width = DW - 28, wrap = false })
    d.sub:SetPoint("TOPLEFT", 14, -38)
    local tileW = (DW - 28 - 12) / 3
    d.kpi = {}
    for i, label in ipairs({ "Skinning needed", "For you, roughly", "Your skins" }) do
        local t = K.Stat(d, label, tileW, 72)
        t:SetPoint("TOPLEFT", 14 + (i - 1) * (tileW + 6), -62)
        t.bg:Paint(C.field)
        t.size = 20
        d.kpi[i] = t
    end
    local scroll = T.ScrollArea(d, 250)
    scroll:ClearAllPoints()
    scroll:SetPoint("TOPLEFT", 14, -146)
    scroll:SetPoint("BOTTOMRIGHT", -12, 52)
    d.text = K.Label(scroll.child, "", { template = "small", width = DW - 44 })
    if d.text.SetSpacing then d.text:SetSpacing(3) end
    d.text:SetPoint("TOPLEFT", 0, 0)
    d.empty = K.Empty(d, "Interface\\Icons\\INV_Misc_Pelt_Wolf_01", "Pick a creature",
        "Every beast in HME's spawn data: what Skinning it needs, what it gives per skin, what you skinned yourself and where it lives.",
        DW - 40)
    d.empty:SetPoint("TOP", 0, -120)
    local divider = d:CreateTexture(nil, "BORDER")
    divider:SetPoint("BOTTOMLEFT", 12, 46)
    divider:SetPoint("BOTTOMRIGHT", -12, 46)
    divider:SetHeight(1)
    divider:SetColorTexture(unpack(C.line))
    d.status = K.Label(d, "", { template = "meta", width = DW - 170, wrap = false })
    d.status:SetPoint("BOTTOMLEFT", 14, 18)
    d.hunt = K.Button(d, "Hunt it", 110, 30, function(self)
        if not selected then return end
        local e = selected
        d.status:SetText("Planning hunting areas for " .. e.name .. "...")
        self.disabled = true
        Bx.Hunt(e, function(results)
            self.disabled = false
            local r = results and results[1]
            if not r then
                d.status:SetText(K.Paint("No hunting area this character can use (too few spawn points, or out of reach).", T.HEX.warning))
                return
            end
            d.status:SetText(("%s, %s: %s away."):format(r.zone or "?", r.subarea or "", r.travel and U.Duration(r.travel) or "travel unknown"))
            HME.Guidance.StartResult(r, "level")
        end)
    end, "Plans a hunting circuit for this creature alone, in the zone that suits you best, and starts guiding (you press "
        .. "Go in Forever-GPS for the trip).", "primary")
    d.hunt:SetPoint("BOTTOMRIGHT", -12, 10)
    for _, w in ipairs({ d.hunt, d.kpi[1], d.kpi[2], d.kpi[3] }) do w:Hide() end

    local function Line(label, text) return ("|cff999b8f%s|r  %s"):format(label, text) end

    function page.Detail(e)
        profile = profile or HME.Player.Profile()
        d.empty:Hide()
        for _, w in ipairs({ d.kpi[1], d.kpi[2], d.kpi[3], d.hunt }) do w:Show() end
        d.status:SetText("")
        local c = Color(e)
        local hex = K.DIFF_HEX[c or ""] or T.HEX.text
        d.name:SetText(K.Paint(e.name, hex))
        T.FitText(d.name, DW - 28, "title", 18, 14)
        d.sub:SetText(("Level %s%s  ·  creature %d  ·  %d spawn points in %d zone%s"):format(
            e.min == e.max and e.min or (e.min .. "–" .. e.max), e.elite and ", elite" or "", e.npcID, e.spawns,
            U.Count(e.maps), U.Count(e.maps) == 1 and "" or "s"))
        local reqMin, reqTop = HME.SkillModel.SkinReq(e.min), HME.SkillModel.SkinReq(e.max)
        local skill = profile.skills.Skinning and profile.skills.Skinning.rank
        d.kpi[1]:Set(reqMin == reqTop and tostring(reqMin) or (reqMin .. "–" .. reqTop),
            skill and ("you %d: %s"):format(skill, COLOR_WORD[c or ""] or "?") or "no Skinning", { K.Rgb(hex) })
        local goal = #mats > 0 and "material" or "level"
        local me = Bx.ForMe(e, profile, goal, mats[1])
        if me.elig and me.elig.killable then
            if goal == "material" then
                d.kpi[2]:Set(("%.0f/h"):format(me.itemPerHour or 0), ns.ItemNameByID(mats[1]) or "of the material", C.gold)
            else
                d.kpi[2]:Set(("%.0f/h"):format(me.skillPerHour or 0), "skill-ups", C.accent)
            end
        else
            d.kpi[2]:Set("–", ShortWhy(me.elig and me.elig.why), C.text3)
        end
        local j = Bx.Journal(e.npcID)
        d.kpi[3]:Set(j and tostring(j.n) or "0", j and (j.ups > 0 and ("%d skill-ups"):format(j.ups) or "recorded") or "none yet",
            j and C.text or C.text3)

        local lines = {}
        local _, sk = Bx.Skinnable(e.npcID)
        lines[#lines + 1] = Line("Can be skinned", sk)
        if me.perHour then
            lines[#lines + 1] = Line("For you", ("about %.0f skins an hour from it alone%s (rough)"):format(me.perHour,
                goal == "material" and "" or (", %.0f%% of them a skill-up"):format((me.elig.chance or 0) * 100)))
        elseif me.elig and me.elig.why then
            lines[#lines + 1] = Line("For you", me.elig.why)
        end
        -- Per skin: yours apart from the estimate.
        local y = HME.Skinning.Yield(e)
        local parts = {}
        local ids = {}
        for id in pairs(y.items) do ids[#ids + 1] = id end
        table.sort(ids, function(a, b) return (y.items[a] or 0) > (y.items[b] or 0) end)
        for _, id in ipairs(ids) do
            if (y.items[id] or 0) >= 0.01 then
                local name = ns.ItemNameByID(id) or ("item " .. id)
                local seen = y.seen and y.seen[id]
                parts[#parts + 1] = ("  %s: %.2f per skin%s"):format(name, y.items[id],
                    seen and K.Paint((" (%d seen in %d of your skins)"):format(seen, y.n), T.HEX.accent)
                    or K.Paint(" (estimate)", T.HEX.text3))
            end
        end
        lines[#lines + 1] = Line("Per skin", y.n > 0 and ("blended: your %d skins and the estimate"):format(y.n) or "estimate by level, not seen yet")
        for _, p in ipairs(parts) do lines[#lines + 1] = p end
        local value = HME.Skinning.SkinValue(e)
        if value and value > 0 then lines[#lines + 1] = Line("Worth per skin", "about " .. K.Money(value) .. " (estimate)") end
        lines[#lines + 1] = ""
        if j then
            lines[#lines + 1] = Line("Your journal", ("%d skins%s, last %s ago"):format(j.n,
                j.ups > 0 and (", %d skill-ups right after"):format(j.ups) or "", HME.Bags.Age(((time and time()) or 0) - (j.t or 0))))
            for i, it in ipairs(j.items) do
                if i > 6 then break end
                lines[#lines + 1] = ("  %s: %d (%.2f per skin)"):format(it.name, it.total, it.perSkin)
            end
            local zs = {}
            for i, z in ipairs(j.zones) do if i <= 3 then zs[#zs + 1] = ("%s ×%d"):format(z.name, z.n) end end
            if #zs > 0 then lines[#lines + 1] = "  where: " .. table.concat(zs, ", ") end
            if j.loot then
                lines[#lines + 1] = Line("Corpse loot", ("%d looted, about %s each (not skinning)"):format(j.loot.n, K.Money(j.loot.avg)))
            end
        else
            lines[#lines + 1] = Line("Your journal", "not skinned yet. Skins of it are recorded here (corpse loot apart).")
        end
        lines[#lines + 1] = ""
        if me.parts then
            lines[#lines + 1] = Line("Kill time", ("about %d s (%s), plus a skin and about %d s between kills"):format(
                me.parts.kill + 0.5, me.parts.killBasis, me.parts.walk + 0.5))
        end
        local q = HME.QuestSynergy and HME.QuestSynergy.ForCreature(e.npcID, e.name)
        if q and q[1] then lines[#lines + 1] = Line("Your quests", HME.QuestSynergy.Text(q)) end
        lines[#lines + 1] = Line("Where it lives", "")
        local zones = {}
        for mapID, n in pairs(e.maps) do zones[#zones + 1] = { mapID = mapID, n = n } end
        table.sort(zones, function(a, b) return a.n > b.n end)
        local here = profile.mapID and HME.Geo.ZoneOf(profile.mapID)
        for i, z in ipairs(zones) do
            if i > 10 then lines[#lines + 1] = ("  +%d more"):format(#zones - 10) break end
            lines[#lines + 1] = ("%s%s: %d spawn points"):format(z.mapID == here and "> " or "  ", HME.ZoneData.Name(z.mapID) or ("map " .. z.mapID), z.n)
        end
        lines[#lines + 1] = ""
        lines[#lines + 1] = K.Paint("Spawns from QuestieDB (Forever build, via Gatherpedia). \"For you\" is a rough per-creature figure; "
            .. "Hunt it plans real circuits.", T.HEX.text3)
        d.text:SetText(table.concat(lines, "\n"))
        scroll:SetContent(DW - 44, (d.text:GetStringHeight() or 300) + 10)
        d.hunt:SetShown(me.elig and me.elig.killable or false)
    end

    function page.Refresh()
        profile = HME.Player.Profile()
        filt:Refresh()
        sort:Refresh()
        local items
        items, mats = Bx.Search({ text = search, filter = ui.bxFilter, sort = ui.bxSort }, profile)
        list:SetItems(items, true)
        count:SetText(("%d found"):format(#items))
        count.tipBody = #mats > 0 and ("Creatures whose skins give " .. (ns.ItemNameByID(mats[1]) or "it") .. ", best for you first.") or nil
        local still
        for i, e in ipairs(items) do if e == selected then still = i end end
        if not still then selected = items[1] still = selected and 1 end
        if selected then
            list:Select(still)
            page.Detail(selected)
        else
            d.empty:Show()
            d.text:SetText("")
            for _, w in ipairs({ d.hunt, d.kpi[1], d.kpi[2], d.kpi[3] }) do w:Hide() end
            d.name:SetText("")
            d.sub:SetText("")
        end
    end
    -- Other pages and the Copilot open a creature or a material here.
    HME.Pages.beastsShow = function(text, npcID)
        box:SetText(text or "")
        search = (text or ""):lower()
        if npcID then ui.bxFilter = "all" end
        page.Refresh()
        if npcID then
            selected = Bx.Get(npcID)
            if selected then page.Detail(selected) end
        end
    end
end
