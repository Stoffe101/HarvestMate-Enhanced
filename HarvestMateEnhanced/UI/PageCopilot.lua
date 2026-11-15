-- HarvestMate Enhanced: UI/PageCopilot.lua (0.6.0)
-- The Farming Copilot's page: what to do next, why, how sure, and one click.
--   top     plan for (mode), how long you have, which profession
--   hero    the one recommendation: what, the number it is about with its
--           range, confidence, why (up to five lines), what it rests on, and
--           its actions (do it, see it, Not now, Not interested)
--   left    other things worth knowing now (training, goals, quests, bags...)
--   right   what HME learned from your sessions: its predictions against
--           what you got (Engine/Ledger.lua)
-- Nothing here acts on its own: every action is a button you press.
-- Copyright (C) 2026 HarvestMate Enhanced contributors. GPL-3.0-or-later.

local _, ns = ...
local HME = ns.HME
local T = ns.Theme
local K = HME.Kit
local U = HME.U
local C = T.C

local PAGE_W = 738
local HERO_H = 220
local LIST_W = 470
local SIDE_W = PAGE_W - LIST_W - 12
local ROW_H = 66
local ROWS = 3
local WHY_W = 466
local WHY_LINES = 4

local TYPE = {
    farm = { "Farm", T.HEX.accent }, stay = { "Farming", T.HEX.accent }, switch = { "Switch", T.HEX.warning },
    train = { "Training", T.HEX.info }, goal = { "Goal", T.HEX.gold }, quest = { "Quest", T.HEX.brass },
    bags = { "Bags", T.HEX.warning }, grey = { "Grey farm", T.HEX.warning }, prices = { "Prices", T.HEX.text3 },
    learned = { "Learned", T.HEX.info }, setup = { "Start", T.HEX.info }, status = { "Working", T.HEX.text3 },
    route = { "Route", T.HEX.brass },
}
local BUDGET_KEYS = { 15, 30, 60, 120, 0 }
local BUDGET_LABEL = { [15] = "15 min", [30] = "30 min", [60] = "1 hour", [120] = "2 hours", [0] = "No limit" }

local function ConfLevel(v)
    if not v then return 0 end
    if v >= 0.8 then return 4 elseif v >= 0.6 then return 3 elseif v >= 0.4 then return 2 end
    return 1
end
local CONF_WORD = { "Low confidence", "Medium confidence", "Good confidence", "High confidence" }

HME.Pages.copilot = function(body, page)
    local Co = HME.Copilot
    local refs = {}
    page.refs = refs

    ---------------------------------------------------------------- controls
    refs.planFor = K.Label(body, "Plan for", { template = "label" })
    refs.planFor:SetPoint("TOPLEFT", 0, -6)
    local modeKeys, modeLabels = {}, {}
    for _, m in ipairs(Co.MODES) do
        modeKeys[#modeKeys + 1] = m.key
        modeLabels[m.key] = m.label
    end
    refs.mode = T.Dropdown(body, 158, modeKeys, modeLabels, function() return Co.Mode() end, function(k)
        Co.SetMode(k)
        page.Refresh()
    end)
    refs.mode:SetPoint("TOPLEFT", 58, -1)
    refs.mode.menuTitle = "What the Copilot plans for"
    T.Tooltip(refs.mode, "Plan for", "Level fastest, most gold, a material from your goals, balanced, lower risk, a short "
        .. "session, farms that also progress your quests, farms you measured yourself, or promising unmeasured ones.")
    refs.time = K.Segments(body, BUDGET_KEYS, BUDGET_LABEL, function() return Co.Minutes() end, function(k)
        Co.SetMinutes(k)
        page.Refresh()
    end, 66)
    refs.time:SetPoint("TOPLEFT", 232, 0)
    T.Tooltip(refs.time, "How long you have", "Farms are compared by what they give in this time, after the trip there. "
        .. "No limit uses the session length from Settings.")
    local profKeys = { "auto", "Skinning", "Herbalism", "Mining", "Fishing" }
    refs.prof = T.Dropdown(body, 150, profKeys, function(k)
        if k == "auto" then
            local p = Co.ctx and Co.ctx.prof
            return p and ("Auto: " .. p) or "Auto"
        end
        return k
    end, function() return Co.State().prof or "auto" end, function(k)
        Co.SetProf(k)
        page.Refresh()
    end)
    refs.prof:SetPoint("TOPRIGHT", 0, -1)
    refs.prof.menuTitle = "Profession"

    ---------------------------------------------------------------- hero
    local hero = CreateFrame("Frame", nil, body)
    hero:SetSize(PAGE_W, HERO_H)
    hero:SetPoint("TOPLEFT", 0, -38)
    hero.bg = T.Surface(hero, { 0.10, 0.14, 0.08, 1 })
    hero.topo = T.Topo(hero, C.accent, 0.06)
    T.Outline(hero, { C.accent[1], C.accent[2], C.accent[3], 0.30 })
    refs.hero = hero
    hero.kicker = K.Label(hero, "Copilot suggests", { template = "label", color = C.accent })
    hero.kicker:SetPoint("TOPLEFT", 18, -14)
    hero.badge = K.Badge(hero, 0, 18)
    hero.badge:SetPoint("LEFT", hero.kicker, "RIGHT", 8, 0)
    hero.title = K.Label(hero, "", { template = "title", size = 19, width = 450, wrap = false })
    hero.title:SetPoint("TOPLEFT", 18, -34)
    hero.sub = K.Label(hero, "", { template = "small", color = C.text2, width = 450, wrap = false })
    hero.sub:SetPoint("TOPLEFT", 18, -58)
    hero.why = K.Label(hero, "", { template = "small", width = WHY_W })
    hero.why:SetPoint("TOPLEFT", 18, -80)
    hero.why:SetJustifyV("TOP")
    -- Measures a reason on one line, to know how many lines it will wrap to.
    hero.measure = K.Label(hero, "", { template = "small" })
    hero.measure:Hide()
    -- Every reason, when not all fit: hover the reasons.
    hero.whyHit = CreateFrame("Frame", nil, hero)
    hero.whyHit:SetPoint("TOPLEFT", 14, -78)
    hero.whyHit:SetSize(WHY_W + 8, 80)
    hero.whyHit:EnableMouse(true)
    hero.whyHit:SetScript("OnEnter", function(self)
        local card = refs.card
        if not (card and GameTooltip and #(card.why or {}) > 0) then return end
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOMRIGHT")
        GameTooltip:AddLine(card.title or "Why", 1, 1, 1)
        for _, w in ipairs(card.why) do GameTooltip:AddLine("• " .. w, 0.85, 0.85, 0.8, true) end
        GameTooltip:Show()
    end)
    hero.whyHit:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
    -- The number it is about, its range and how sure.
    hero.value = K.Label(hero, "", { template = "display", color = C.gold, width = 220, wrap = false, justify = "RIGHT" })
    hero.value:SetPoint("TOPRIGHT", -18, -18)
    hero.unit = K.Label(hero, "", { template = "small", color = C.text2, width = 220, wrap = false, justify = "RIGHT" })
    hero.unit:SetPoint("TOPRIGHT", -18, -48)
    hero.range = K.Label(hero, "", { template = "meta", width = 220, wrap = false, justify = "RIGHT" })
    hero.range:SetPoint("TOPRIGHT", -18, -66)
    hero.pips = K.Pips(hero, 4)
    hero.pips:SetPoint("TOPRIGHT", -18, -90)
    hero.conf = K.Label(hero, "", { template = "meta", width = 170, wrap = false, justify = "RIGHT" })
    hero.conf:SetPoint("RIGHT", hero.pips, "LEFT", -6, 0)
    hero.risk = K.Label(hero, "", { template = "meta", width = 220, wrap = false, justify = "RIGHT" })
    hero.risk:SetPoint("TOPRIGHT", -18, -108)
    hero.more = K.Label(hero, "", { template = "meta", width = 220, wrap = false, justify = "RIGHT" })
    hero.more:SetPoint("TOPRIGHT", -18, -126)
    hero.evidence = K.Label(hero, "", { template = "meta", width = PAGE_W - 36, wrap = false })
    hero.evidence:SetPoint("BOTTOMLEFT", 18, 50)
    hero.go = K.Button(hero, "Start farming", 140, 30, function(self) if self.action then Co.Run(self.action) end end, nil, "primary")
    hero.go:SetPoint("BOTTOMLEFT", 18, 14)
    hero.alt = K.Button(hero, "See in Farm Finder", 150, 30, function(self) if self.action then Co.Run(self.action) end end)
    hero.alt:SetPoint("LEFT", hero.go, "RIGHT", 8, 0)
    hero.never = K.Button(hero, "Not interested", 120, 30, function()
        if refs.card then Co.Dismiss(refs.card, "type") page.Refresh() end
    end, "Stop suggesting this kind of thing. Settings, Copilot, brings them back.", "ghost")
    hero.never:SetPoint("BOTTOMRIGHT", -18, 14)
    hero.later = K.Button(hero, "Not now", 90, 30, function()
        if refs.card then Co.Dismiss(refs.card) page.Refresh() end
    end, "Hide this suggestion for six hours; the next best one takes its place.", "ghost")
    hero.later:SetPoint("RIGHT", hero.never, "LEFT", -6, 0)

    ---------------------------------------------------------------- more
    local more = T.Card(body, "Also worth knowing", 0, -38 - HERO_H - 12, LIST_W, ROWS * ROW_H + 40)
    refs.more = more
    more.rows = {}
    for i = 1, ROWS do
        local row = CreateFrame("Frame", nil, more)
        row:SetSize(LIST_W - 24, ROW_H - 6)
        row:SetPoint("TOPLEFT", 12, -32 - (i - 1) * ROW_H)
        row.bg = T.Surface(row, C.raised)
        row.badge = K.Badge(row, 0, 18)
        row.badge:SetPoint("TOPLEFT", 10, -9)
        row.title = K.Label(row, "", { template = "strong", width = 200, wrap = false })
        row.title:SetPoint("LEFT", row.badge, "RIGHT", 8, 0)
        row.text = K.Label(row, "", { template = "meta", width = LIST_W - 24 - 50 })
        row.text:SetPoint("TOPLEFT", 10, -32)
        row.text:SetJustifyV("TOP")
        if row.text.SetMaxLines then row.text:SetMaxLines(2) end
        row.go = K.Button(row, "Do it", 90, 24, function(self) if self.action then Co.Run(self.action) end end)
        row.go:SetPoint("TOPRIGHT", -34, -6)
        row.x = K.Button(row, "×", 22, 22, function(self)
            if self.card then Co.Dismiss(self.card) page.Refresh() end
        end, "Not now: hide this for six hours.", "ghost")
        row.x.autoFit = false
        row.x:SetPoint("TOPRIGHT", -6, -7)
        row:SetScript("OnEnter", function(self)
            if not (self.card and GameTooltip) then return end
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:AddLine(self.card.title or "", 1, 1, 1)
            if self.card.objective then GameTooltip:AddLine(self.card.objective, 0.85, 0.85, 0.8, true) end
            for _, w in ipairs(self.card.why or {}) do GameTooltip:AddLine("• " .. w, 0.7, 0.7, 0.65, true) end
            GameTooltip:Show()
        end)
        row:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
        more.rows[i] = row
    end
    more.empty = K.Label(more, "Nothing else right now. Training, goals, quests in your log and full bags show here when they matter.",
        { template = "meta", width = LIST_W - 28 })
    more.empty:SetPoint("TOPLEFT", 14, -36)

    ---------------------------------------------------------------- learned
    local side = T.Card(body, "Learned from your sessions", LIST_W + 12, -38 - HERO_H - 12, SIDE_W, ROWS * ROW_H + 40)
    refs.side = side
    side.text = K.Label(side, "", { template = "meta", width = SIDE_W - 28 })
    side.text:SetPoint("TOPLEFT", 14, -34)
    side.text:SetJustifyV("TOP")
    side.measure = K.Label(side, "", { template = "meta" })
    side.measure:Hide()
    side.reset = K.Button(side, "Show dismissed again", 150, 24, function()
        Co.ResetFeedback()
        page.Refresh()
    end, "Brings back every suggestion you put off or said you are not interested in.", "ghost")
    side.reset:SetPoint("BOTTOMLEFT", 10, 10)

    ---------------------------------------------------------------- fill
    local function FillHero(card, ctx)
        refs.card = card
        if not card then
            hero.title:SetText("Nothing to suggest")
            hero.sub:SetText("")
            hero.why:SetText("The Copilot needs a gathering profession, or a mode with something to rank. Try another mode above.")
            for _, w in ipairs({ hero.value, hero.unit, hero.range, hero.conf, hero.risk, hero.evidence, hero.more }) do w:SetText("") end
            hero.pips:Hide()
            hero.badge:Hide()
            for _, b in ipairs({ hero.go, hero.alt, hero.later, hero.never }) do b:Hide() end
            return
        end
        local ty = TYPE[card.type] or TYPE.status
        hero.kicker:SetText(card.type == "switch" and "Copilot suggests a change" or "Copilot suggests")
        hero.badge:Set(ty[1], ty[2])
        hero.badge:Show()
        hero.title:SetText(card.title or "")
        T.FitText(hero.title, 450, "title", 19, 15)
        local sub, reasons = {}, {}
        -- A short objective is the subtitle; a sentence leads the reasons.
        local obj = card.objective
        if obj and #obj > 64 then reasons[1] = obj obj = nil end
        if obj then sub[#sub + 1] = obj end
        if card.sub then sub[#sub + 1] = card.sub end
        if card.travel then sub[#sub + 1] = U.Duration(card.travel) .. " away" end
        hero.sub:SetText(table.concat(sub, "  ·  "))
        for _, w in ipairs(card.why or {}) do reasons[#reasons + 1] = "• " .. w end
        -- As many reasons as fit in five lines; the rest on hover.
        local lines, used, hidden = {}, 0, 0
        for i, w in ipairs(reasons) do
            hero.measure:SetText(w)
            local n = math.max(1, math.ceil((T.StringWidth(hero.measure) + 8) / WHY_W))
            if used + n > WHY_LINES then
                hidden = #reasons - i + 1
                break
            end
            lines[#lines + 1] = w
            used = used + n
        end
        hero.why:SetText(table.concat(lines, "\n"))
        hero.more:SetText(hidden > 0 and ("%d more reason%s: hover the text"):format(hidden, hidden == 1 and "" or "s") or "")
        -- The number, when there is one.
        local b = card.benefit
        if b and b.value then
            local v = Co.Fmt(b.value, b.unit)
            hero.value:SetText(v)
            T.FitText(hero.value, 220, "display", 24, 16)
            hero.unit:SetText(b.unit == "gold" and "an hour (estimate)" or (b.unit .. " an hour"))
            local rg = card.range
            hero.range:SetText(rg and rg.low and rg.high and ("range " .. Co.Fmt(rg.low, b.unit) .. " to " .. Co.Fmt(rg.high, b.unit)) or "")
        elseif card.forecast and card.forecast.hours then
            hero.value:SetText(U.Duration(card.forecast.hours.mid * 3600 + (card.forecast.travel or 0)))
            T.FitText(hero.value, 220, "display", 24, 16)
            hero.unit:SetText("to finish, travel included")
            hero.range:SetText("")
        else
            hero.value:SetText("")
            hero.unit:SetText("")
            hero.range:SetText("")
        end
        local lvl = ConfLevel(card.conf)
        hero.pips:SetShown(lvl > 0)
        hero.pips:Set(lvl, lvl >= 3 and T.HEX.accent or (lvl == 2 and T.HEX.warning or T.HEX.danger))
        hero.conf:SetText(lvl > 0 and CONF_WORD[lvl] or "")
        local risk = card.risk
        hero.risk:SetText(risk and risk.label and K.Paint(risk.label, risk.hex) or "")
        hero.evidence:SetText(card.evidence and ("Rests on: " .. card.evidence) or "")
        local a = card.action
        hero.go.action = a
        hero.go:SetShown(a ~= nil)
        if a then hero.go:SetText(a.label or "Do it") end
        local s = card.secondary and card.secondary[1]
        hero.alt.action = s
        hero.alt:SetShown(s ~= nil)
        if s then hero.alt:SetText(s.label or "More") end
        hero.later:SetShown(card.type ~= "status")
        hero.never:SetShown(card.type ~= "status" and card.type ~= "setup")
    end

    local function FillRow(row, card)
        row.card = card
        row:SetShown(card ~= nil)
        if not card then return end
        local ty = TYPE[card.type] or TYPE.status
        row.badge:Set(ty[1], ty[2])
        row.title:SetText(card.title or "")
        T.FitText(row.title, card.action and 200 or 330, "strong", 13, 11)
        row.title:SetWidth(card.action and 200 or 330)
        row.text:SetText(card.objective or (card.why and card.why[1]) or "")
        row.go.action = card.action
        row.go:SetShown(card.action ~= nil)
        if card.action then row.go:SetText(card.action.label or "Do it") end
        row.x.card = card
    end

    -- What fits the card (about nine lines), most useful first.
    local SIDE_LINES = 9
    local function FillSide()
        local rep = HME.Ledger.Report()
        local blocks = {}
        for _, p in ipairs(rep.profs) do blocks[#blocks + 1] = p.pace.text end
        for _, a in ipairs(rep.farms) do
            local zone = HME.ZoneData.Name(tonumber(tostring(a.key):match("@(%d+)")) or 0) or "?"
            local pct = a.ratio and math.floor((a.ratio - 1) * 100 + 0.5) or 0
            blocks[#blocks + 1] = ("%s  %s\npredicted %.0f %s/h, got %.0f (%s%d%%, %d session%s)"):format(
                K.Paint(zone, T.HEX.text), a.sure and "" or K.Paint("small sample", T.HEX.text3), a.predicted, a.unit, a.observed,
                pct > 0 and "+" or "", pct, a.sessions, a.sessions == 1 and "" or "s")
        end
        if #blocks == 0 then
            blocks[1] = "Nothing yet. After a session on a farm you started from HME (10 minutes or more), its prediction is "
                .. "compared with what you got. After two sessions, estimates for farms you have not measured are adjusted to you."
        end
        local out, used = {}, 0
        for _, b in ipairs(blocks) do
            local n = 0
            for line in (b .. "\n"):gmatch("(.-)\n") do
                side.measure:SetText(line)
                n = n + math.max(1, math.ceil((T.StringWidth(side.measure) + 6) / (SIDE_W - 28)))
            end
            if used + n + (#out > 0 and 1 or 0) > SIDE_LINES then break end
            out[#out + 1] = b
            used = used + n + (#out > 1 and 1 or 0)
        end
        side.text:SetText(table.concat(out, "\n\n"))
    end

    function page.Refresh()
        refs.mode:Refresh()
        refs.time:Refresh()
        local cards = Co.Evaluate(false)
        refs.prof:Refresh()
        local ctx = Co.ctx or {}
        -- The hero is the first card with something to do (else the first).
        local heroCard
        for _, c in ipairs(cards) do if c.action and c.type ~= "status" then heroCard = c break end end
        heroCard = heroCard or cards[1]
        FillHero(heroCard, ctx)
        local others = {}
        for _, c in ipairs(cards) do
            if c ~= heroCard and c.type ~= "status" then others[#others + 1] = c end
        end
        for i = 1, ROWS do FillRow(more.rows[i], others[i]) end
        more.empty:SetShown(#others == 0)
        FillSide()
    end

    HME.Listen("COPILOT_CHANGED", function()
        if body:IsVisible() then HME.Soon("copilot-page", 0.2, page.Refresh) end
    end)
end
