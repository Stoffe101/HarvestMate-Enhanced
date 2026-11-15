-- Skin counting, case by case: exactly one skin per successful skinning
-- loot, never two, never one for a failed cast, and an honest "uncertain"
-- when the game does not say which creature it was.

local ns, HME = LoadHME()
PLAYER.map, PLAYER.x, PLAYER.y = 1424, 0.46, 0.42
CHAR.level = 41
PROFS = { { line = 393, rank = 143, max = 225 } }
HME.Player.Refresh()
local L = HME.Learning

local n = 0
local function Guid(id) n = n + 1 return ("Creature-0-1-2-3-%d-%08X"):format(id or 2354, n) end
local function Cast(spell) FireEvent("UNIT_SPELLCAST_SUCCEEDED", "player", "cast", spell or 8613) end
local function Loot(guid, items)
    LOOT_SOURCE, LOOT = guid, items or { { id = 2318, qty = 1 } }
    FireEvent("LOOT_OPENED")
end
local function Close() FireEvent("LOOT_CLOSED") LOOT_SOURCE, LOOT = nil, {} end
local function Skins() return (HME.Session.Rates() or {}).skins or 0 end
local function Kills() return (HME.Session.Rates() or {}).kills or 0 end

HME.Session.Start()

STEP("five successful skins are five skins")
local before = Skins()
for _ = 1, 5 do
    RunTimers(6)
    Cast()
    Loot(Guid())
    Close()
end
eq(Skins(), before + 5, "five")

STEP("a reopened loot window and a doubled spell event count once")
RunTimers(6)
local g = Guid()
Cast()
Cast()   -- the same cast reported twice
Loot(g)
Loot(g)  -- the window reported again
Close()
Loot(g)  -- reopened
Close()
eq(Skins(), before + 6, "one more")

STEP("a corpse looted right after skinning another is loot, not a skin")
RunTimers(6)
Cast()
Loot(Guid())
Close()
local k = Kills()
Loot(Guid(), { { id = 2589, qty = 1 } })   -- the next corpse's ordinary loot, at once
Close()
eq(Skins(), before + 7, "one skin")
eq(Kills(), k + 1, "and one corpse looted")

STEP("a failed or interrupted skin is not a skin")
RunTimers(6)
HME.Signal("GATHER_START", "skin", "Gray Bear")      -- HarvestMate saw the cast begin
FireEvent("UNIT_SPELLCAST_FAILED", "player", "cast", 8613)
Loot(Guid(), { { id = 2589, qty = 1 } })               -- then loots a corpse
Close()
eq(Skins(), before + 7, "the failed cast did not turn loot into a skin")
RunTimers(6)
HME.Signal("GATHER_START", "skin", "Gray Bear")
FireEvent("UNIT_SPELLCAST_INTERRUPTED", "player", "cast", 8613)
Loot(Guid(), { { id = 2589, qty = 1 } })
Close()
eq(Skins(), before + 7, "nor an interrupted one")

STEP("no creature named: counted once, marked uncertain")
RunTimers(6)
local unc = L.detect.uncertain or 0
Cast()
Loot(nil, { { id = 2318, qty = 2 } })                  -- the game gave no source
HME.Signal("GATHER_LOOT", "skin", nil, { [2318] = 2 })  -- HarvestMate saw skinning loot
RunTimers(1)
Close()
eq(Skins(), before + 8, "counted once")
eq((L.detect.uncertain or 0), unc + 1, "and said to be uncertain")
check(HME.Diagnostics and HME.Diagnostics.Text():find("uncertain", 1, true),
    "/hme diag says how many were uncertain")

STEP("delayed loot: the backstop counts it once")
RunTimers(6)
Cast()
RunTimers(5)   -- the window opens late
Loot(Guid())
HME.Signal("GATHER_LOOT", "skin", nil, { [2318] = 1 })
RunTimers(1)
Close()
eq(Skins(), before + 9, "late, but once")

STEP("an unknown creature ID still counts")
RunTimers(6)
Cast()
Loot(Guid(987654))
Close()
eq(Skins(), before + 10, "unknown beast, one skin")

STEP("paused: skins are kept for the beast's yield, not added to the session")
HME.Session.Pause()
local obsBefore = (HME.db.obs.skins[2354] or { n = 0 }).n
RunTimers(6)
Cast()
Loot(Guid())
Close()
eq(Skins(), before + 10, "the paused session did not count it")
eq(HME.db.obs.skins[2354].n, obsBefore + 1, "the yield record did")
HME.Session.Pause()   -- resume

STEP("no session and no route: a skin starts the session")
HME.Session.Stop("test")
check(HME.Session.Current() == nil, "stopped")
RunTimers(6)
Cast()
Loot(Guid())
Close()
check(HME.Session.Current(), "a session began")
eq(Skins(), 1, "with that skin")

STEP("after /reload: the session and its count come back")
local saved = HME.char.session
check(saved and saved.counts.skin == 1, "saved per character")
HME.Signal("DB_READY")
eq(Skins(), 1, "restored")
HME.Session.Stop("test")
