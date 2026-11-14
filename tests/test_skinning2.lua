-- Skinning 2.0: character fixtures, eligibility kept apart from efficiency,
-- broad level ranges, specific leather (scenario 3), kill-time learning
-- (multi-mob fights ignored, old samples fade), yields with sample sizes and
-- no double counting, evidence labels and ranges instead of one number.

local ns, HME = LoadHME()
local Sk, SM = HME.Skinning, HME.SkillModel
PLAYER.map, PLAYER.x, PLAYER.y = 1429, 0.42, 0.65
MAPS[1429].w, MAPS[1429].h = nil, nil
HME.Prices.fixed = {
    [2318] = { low = 30, typical = 40 }, [2319] = { low = 90, typical = 120 }, [4234] = { low = 250, typical = 300 },
    [4304] = { low = 500, typical = 600 }, [8170] = { low = 900, typical = 1000 }, [783] = { low = 100, typical = 150 },
    [4232] = { low = 300, typical = 400 }, [4235] = { low = 600, typical = 800 }, [8169] = { low = 1200, typical = 1500 },
}
HME.Prices.Invalidate()

local FIXTURES = {
    { name = "level 12, Skinning 60", level = 12, skill = 60 },
    { name = "level 36 hunter, Skinning 175", level = 36, skill = 175 },
    { name = "level 58, Skinning 300", level = 58, skill = 300 },
    { name = "level 50, Skinning 100 (skill behind level)", level = 50, skill = 100 },
}
local function Profile(fx)
    return { level = fx.level, faction = "Alliance", class = "HUNTER", speed = 7, mapID = 1429, x = 0.42, y = 0.65,
        skills = { Skinning = { rank = fx.skill, max = 300 } }, zone = "Elwynn Forest", real = false }
end

STEP("fixtures: every recommended beast can be skinned and fought")
for _, fx in ipairs(FIXTURES) do
    local profile = Profile(fx)
    local res = HME.Recommend.Find({ prof = "Skinning", goal = "level" }, nil, profile)
    check(#res > 0, fx.name .. ": farms found")
    for _, r in ipairs(res) do
        for _, t in ipairs(r.targets) do
            check(t.min <= SM.MaxSkinLevel(fx.skill), ("%s: %s (level %d-%d) has skinnable levels"):format(fx.name, t.name, t.min, t.max))
            check(t.max <= fx.level + 3, fx.name .. ": nothing far above the character")
            check(not t.elite, fx.name .. ": no elites in balanced mode")
        end
    end
    local top = res[1]
    REAL_PRINT(("  %s -> %s (%s): %.0f skill/h"):format(fx.name, top.zone, top.subarea, top.metrics.skillPerHour))
    if fx.skill < 300 then check(top.metrics.skillChance > 0.3, fx.name .. ": the top farm still gives points") end
end

STEP("broad level ranges: partly skinnable beasts count only for the levels you can skin")
local wide = { npcID = 9001, name = "Wide Wolf", min = 30, max = 40 }
local e = Sk.Eligible(wide, Profile({ level = 40, skill = 175 }))
check(e.killable, "skinnable at 30-35 of 30-40")
near(e.skinShare, 6 / 11, 1e-9, "6 of 11 levels")
local all = Sk.Eligible(wide, Profile({ level = 40, skill = 200 }))
eq(all.skinShare, 1, "all levels at 200")

STEP("eligibility is not efficiency: a skinnable, far-below beast is a poor leveling farm")
local low = { npcID = 9002, name = "Tiny Boar", min = 10, max = 11 }
local el = Sk.Eligible(low, Profile({ level = 36, skill = 175 }))
check(el.killable, "eligible")
eq(el.chance, 0, "but grey: no skill-ups")
local ef = Sk.Efficiency(low, Profile({ level = 36, skill = 175 }))
check(ef.killSecs < Sk.BASE_KILL, "it dies fast")

STEP("scenario 3: Heavy Leather goes by yield per hour, not chance per kill")
local heavy = HME.Recommend.Find({ prof = "Skinning", goal = "material", targets = { [4234] = true } }, nil,
    Profile({ level = 40, skill = 210 }))
check(#heavy > 0, "Heavy Leather farms")
for i = 2, #heavy do
    check(heavy[i - 1].score >= heavy[i].score, "ranked by score")
end
check(heavy[1].metrics.materialPerHour > 0, "units an hour")
for _, t in ipairs(heavy[1].targets) do
    check(t.max >= 28 and t.min <= 42, "beasts in Heavy Leather's level band: " .. t.name)
end

STEP("kill time: multi-mob fights and unclear fights are not samples")
HME.char.eff.kill = {}
HME.char.eff.ambiguous = 0
local function Fight(secs, loots)
    FireEvent("PLAYER_REGEN_DISABLED")
    FAKE_TIME = FAKE_TIME + secs
    for i = 1, loots do
        UNIT_GUIDS = nil
        LOOT_SOURCE = ("Creature-0-1-2-3-%d-%08X"):format(1126, math.random(1, 1e7))
        LOOT = { { id = 2318, qty = 1 } }
        FireEvent("LOOT_OPENED")
        FireEvent("LOOT_CLOSED")
    end
    FireEvent("PLAYER_REGEN_ENABLED")
    RunTimers(7)
end
Fight(12, 1)
eq(#HME.char.eff.kill, 1, "a one-beast fight is a sample")
Fight(20, 2)
eq(#HME.char.eff.kill, 1, "a two-beast fight is not")
Fight(15, 0)
eq(#HME.char.eff.kill, 1, "a fight with no loot (someone else's kill, evaded) is not")
check(HME.char.eff.ambiguous >= 2, "they are counted as unclear instead")

STEP("old samples and samples from far lower levels fade")
HME.char.eff.kill = {}
for i = 1, 20 do HME.char.eff.kill[i] = { d = 0, s = 30, t = REAL_TIME - 90 * 86400, lvl = 20 } end
local fOld = Sk.KillFactor({ level = 36 })
HME.char.eff.kill = {}
for i = 1, 20 do HME.char.eff.kill[i] = { d = 0, s = 30, t = REAL_TIME, lvl = 36 } end
local fNew = Sk.KillFactor({ level = 36 })
check(fNew > fOld, ("recent samples at your level weigh more (%.2f vs %.2f)"):format(fNew, fOld))
HME.char.eff.kill = {}

STEP("yields: one corpse counted once, with its sample size")
HME.db.obs.skins = {}
local guid = "Creature-0-1-2-3-1126-0000ABCD"
local function SkinLoot(g, items)
    HME.Signal("TEST_SKIN_CAST")
    FireEvent("UNIT_SPELLCAST_SUCCEEDED", "player", "cast", 8613)
    LOOT_SOURCE = g
    LOOT = items
    FireEvent("LOOT_OPENED")
end
SkinLoot(guid, { { id = 2318, qty = 2 } })
SkinLoot(guid, { { id = 2318, qty = 2 } })   -- the same loot window reported twice
local rec = HME.db.obs.skins[1126]
eq(rec.n, 1, "one skin")
eq(rec.qty[2318], 2, "two leather")
for i = 1, 30 do SkinLoot(("Creature-0-1-2-3-1126-%08X"):format(i), { { id = 2318, qty = 1 } }) end
local y = Sk.Yield({ npcID = 1126, name = "Timber Wolf", min = 5, max = 6 })
eq(y.n, 31, "31 skins")
local text = Sk.YieldText(y, 2318)
check(text:find("32 observed from 31", 1, true), "says how many: " .. text)

STEP("evidence: what a number is based on, and a range")
local profile = Profile({ level = 36, skill = 175 })
local res = HME.Recommend.Find({ prof = "Skinning", goal = "profit" }, nil, profile)
local r = res[1]
check(r.evidence and r.evidence.level, "an evidence level")
eq(r.evidence.level, "assumption", "nothing measured yet: built on assumptions")
check(r.metrics.range.low < r.metrics.range.mid and r.metrics.range.mid < r.metrics.range.high, "a range low < mid < high")
check(r.metrics.range.high / math.max(1, r.metrics.range.low) >= 1.8, "an unmeasured estimate is wide")
-- Measured sessions in that area narrow it and take over.
for i = 1, 4 do
    HME.Learning.AddStats(r.key, { hours = 1, sessions = 1, beasts = 150, value = 30000 + i * 1000 })
    HME.Learning.AddSample(r.key, { h = 1, gph = 30000 + i * 1000 })
end
res = HME.Recommend.Find({ prof = "Skinning", goal = "profit" }, nil, profile)
local again
for _, x in ipairs(res) do if x.key == r.key then again = x end end
check(again, "the area is still listed")
eq(again.evidence.level, "measured", "measured sessions")
check(again.metrics.range.high / again.metrics.range.low < r.metrics.range.high / r.metrics.range.low, "narrower once measured")
near(again.metrics.range.mid, 32500, 9000, "centred near what you earned")
