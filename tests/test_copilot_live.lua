-- 0.7.1: the Copilot follows your skill as it rises, for every gathering
-- profession, and the Dashboard's "Copilot suggests" card follows it (it kept
-- the old advice before: the window redrew before the Copilot planned again).

local ns, HME = LoadHME()
PLAYER.map, PLAYER.x, PLAYER.y = 1429, 0.42, 0.65
CHAR.level = 41
local LINES = { Skinning = 393, Herbalism = 182, Mining = 186, Fishing = 356 }
local Co = HME.Copilot

local function Settle()
    for _ = 1, 8 do HME.FinishJobs() RunTimers(3) Tick(0.3) end
end

HME.OpenWindow("dashboard")
local dash = HME.Window.frame.pages.dashboard
local refreshed, fresh = 0, true
local real = dash.Refresh
dash.Refresh = function(...) refreshed = refreshed + 1 fresh = true return real(...) end
HME.Listen("COPILOT_CHANGED", function() fresh = false end)

for _, prof in ipairs({ "Skinning", "Herbalism", "Mining", "Fishing" }) do
    STEP(prof .. ": a skill-up plans again and the Dashboard shows it")
    PROFS = { { line = LINES[prof], rank = 60, max = 150 } }
    HME.Player.Refresh()
    Co.SetProf("auto")
    Settle()
    local before = Co.ctx and Co.ctx.sig
    check(before and before:find(prof, 1, true), "planning for " .. prof .. ": " .. tostring(before))
    local topBefore = Co.Top()
    PROFS = { { line = LINES[prof], rank = 95, max = 150 } }
    HME.Fire("CHAT_MSG_SKILL", "Your skill in " .. prof .. " has increased to 95.")
    refreshed = 0
    Settle()
    local after = Co.ctx and Co.ctx.sig
    check(after and after ~= before, "a new plan for the new skill")
    eq(HME.Player.Profile().skills[prof].rank, 95, "the profile has the new rank")
    check(refreshed >= 1, "the Dashboard redrew (" .. refreshed .. ")")
    check(fresh, "and it redrew after the Copilot's last update, so it shows the new advice")
    local last = Co.searches[after]
    check(last and last.results, "the search for 95 ran")
    check(Co.Top() ~= nil, "a suggestion")
    if topBefore and Co.Top() and topBefore.result and Co.Top().result then
        -- (the same farm can stay best; its numbers then come from the new search)
        check(Co.Top().result ~= topBefore.result, "the card is from the new search")
    end
end
