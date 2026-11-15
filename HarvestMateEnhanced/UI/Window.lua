-- HarvestMate Enhanced: UI/Window.lua
-- The one window: every HME page, GatherPath's route pages and the settings,
-- in the shared Theme. Pages are built the first time they are opened. The
-- window remembers its place, scale and last tab per character. Escape
-- closes it; closing it releases any key capture that was open.
-- Copyright (C) 2026 HarvestMate Enhanced contributors. GPL-3.0-or-later.

local _, ns = ...
local HME = ns.HME
local T = ns.Theme

local W = {}
HME.Window = W
HME.Pages = HME.Pages or {}

W.WIDTH, W.HEIGHT = 940, 660

local function Tabs()
    local P = HME.Pages
    local tabs = {
        { key = "dashboard", label = "Dashboard", icon = "Interface\\Icons\\INV_Misc_Book_09", build = P.dashboard,
          tip = "Your gathering professions, the farm you are following and this session." },
        { key = "copilot", label = "Copilot", icon = "Interface\\Icons\\Ability_Hunter_Pathfinding", build = P.copilot,
          tip = "What to farm now and why: one recommendation for your mode and time, with its evidence." },
        { key = "finder", label = "Farm Finder", icon = "Interface\\Icons\\INV_Misc_Spyglass_02", build = P.finder,
          tip = "Where to farm for skill, gold or a material, ranked for this character." },
        { key = "goals", label = "Goals & Plans", icon = "Interface\\Icons\\INV_Misc_Note_06", build = P.goals,
          tip = "Material and skill goals with progress, staged leveling plans, saved profiles." },
        { key = "guides", label = "Leveling Guides", icon = "Interface\\Icons\\INV_Misc_Note_01", build = P.guides,
          tip = "1-300 for each profession, with what to do next." },
        { key = "materials", label = "Materials", icon = "Interface\\Icons\\INV_Misc_Herb_07", build = P.materials,
          tip = "The field guide: every herb, ore, fish and hide, where it is, and its price." },
        { key = "beasts", label = "Skinning Explorer", icon = "Interface\\Icons\\INV_Misc_Pelt_Wolf_01", build = P.beasts,
          tip = "Every beast: Skinning needed, what it gives per skin, what you skinned yourself, where it lives, and a hunt for it alone." },
        { key = "stats", label = "Profits & Stats", icon = "Interface\\Icons\\INV_Misc_Coin_02", build = P.stats,
          tip = "Sessions, measured rates, records and achievements." },
        { key = "trainers", label = "Trainers", icon = "Interface\\Icons\\INV_Misc_Book_11", build = P.trainers,
          tip = "Where to train each gathering profession." },
        { header = "Routes and maps" },
    }
    for _, t in ipairs((HME.Routes and HME.Routes.CONFIG_TABS) or {}) do tabs[#tabs + 1] = t end
    tabs[#tabs + 1] = { header = "" }
    tabs[#tabs + 1] = { key = "setup", label = "Setup", icon = "Interface\\Icons\\INV_Misc_Gear_01", build = P.setup,
        tip = "What HME found and the few choices that matter. Never forced." }
    tabs[#tabs + 1] = { key = "settings", label = "Settings", icon = "Interface\\Icons\\Trade_Engineering",
        build = P.settings, tip = "What HME shows, how it ranks, prices, integrations and your data." }
    return tabs
end

local onTab = {}
function W.Build()
    if W.frame then return W.frame end
    local s = HME.settings or {}
    local ui = HME.char and HME.char.ui or {}
    local tabs = Tabs()
    for _, t in ipairs(tabs) do if t.onTab then onTab[t.key] = t.onTab end end
    local win = T.Window({
        name = "HarvestMateEnhancedWindow",
        width = W.WIDTH,
        height = W.HEIGHT,
        tabs = tabs,
        lazy = true,
        compact = s.layout == "compact",
        tabHeight = 32,
        first = ui.tab or "dashboard",
        hint = "/hme opens this window  ·  /hme help lists commands",
        version = function() return HME.VERSION end,
        onShow = function()
            -- A page that starts fresh each time it is shown (New route) does
            -- so when the window opens on it, too.
            local cur = W.frame and W.frame.currentTab
            if cur and onTab[cur] then onTab[cur]() end
            if HME.Routes and HME.Routes.RefreshConfig then HME.Routes:RefreshConfig() end
            HME.Signal("WINDOW_SHOWN")
        end,
        onHide = function()
            local pt, _, rel, x, y = W.frame:GetPoint()
            if HME.char then HME.char.ui.pos = { pt or "CENTER", rel or "CENTER", x or 0, y or 0 } end
            HME.Signal("WINDOW_HIDDEN")
        end,
        onTab = function(key)
            if HME.char then HME.char.ui.tab = key end
            if onTab[key] then onTab[key]() end
            if HME.Routes and HME.Routes.RefreshConfig then HME.Routes:RefreshConfig() end
            local page = W.frame and W.frame.pages[key]
            if page and page.Refresh then HME.Try(page.Refresh) end
        end,
    })
    W.frame = win
    if HME.Routes then HME.Routes.config = win end
    win:SetUIScale(s.scale or 1)
    local pos = ui.pos
    if type(pos) == "table" and pos[1] then
        win:ClearAllPoints()
        win:SetPoint(pos[1], UIParent, pos[2], pos[3], pos[4])
    end
    -- The window never takes the keyboard (EnableKeyboard is protected in
    -- combat on Forever, and a window that eats keys gets in the way). Tab
    -- cycling is offered as two key bindings the player can choose to set
    -- (Bindings.xml), and the Gamepad UI's cursor clicks everything here.
    return win
end

function W.CycleTab(delta)
    if not (W.frame and W.frame:IsShown()) then return end
    local keys = {}
    for _, t in ipairs(Tabs()) do if t.key then keys[#keys + 1] = t.key end end
    local cur = 1
    for i, k in ipairs(keys) do if k == W.frame.currentTab then cur = i end end
    local nextKey = keys[(cur - 1 + delta) % #keys + 1]
    W.frame:ShowTab(nextKey)
end

-- Opens the window on a page (and sub-section). Opening it while in combat
-- is fine: it is HME's own frame, nothing protected.
function HME.OpenWindow(tab, sub)
    local win = W.Build()
    W.sub = sub
    if not win:IsShown() then win:Show() end
    if tab then win:ShowTab(tab) end
    local page = win.pages[win.currentTab]
    if page and page.Refresh then HME.Try(page.Refresh) end
    if sub and page and page.Focus then HME.Try(page.Focus, sub) end
    return win
end

function HME.ToggleWindow()
    local win = W.Build()
    if win:IsShown() then win:Hide() else HME.OpenWindow() end
end

-- Pages refresh while shown when something they show changes.
local function RefreshCurrent()
    local win = W.frame
    if not (win and win:IsShown()) then return end
    local page = win.pages[win.currentTab]
    if page and page.Refresh then HME.Try(page.Refresh) end
end
-- (0.7.1: COPILOT_CHANGED too. The Dashboard's "Copilot suggests" card used to
-- keep the old advice after a skill-up: the window redrew on PLAYER_CHANGED,
-- before the Copilot had planned again, and never after.)
for _, sig in ipairs({ "UI_REFRESH", "PLAYER_CHANGED", "SESSION_CHANGED", "ROUTES_CHANGED", "GUIDANCE_CHANGED",
    "SETTINGS", "LEARNED", "COPILOT_CHANGED" }) do
    HME.Listen(sig, function() HME.Soon("window-refresh", 0.2, RefreshCurrent) end)
end

HME.Listen("SETTINGS", function()
    if W.frame then W.frame:SetUIScale(HME.settings.scale or 1) end
end)

-- Rebuild after a layout change (compact/expanded): only while closed.
function W.Rebuild()
    if W.frame and W.frame:IsShown() then W.frame:Hide() end
    if W.frame then
        W.frame:SetParent(nil)
        W.frame = nil
    end
end
