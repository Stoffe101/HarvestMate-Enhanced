# Audit (2026-11-14)

Sources inspected: GatherPath Forever 1.12.1 (all code, tests, dev notes), HarvestMate 2.0.13 (all modules), Gatherpedia 1.0.1 (all modules and data), Forever-GPS 2.7.0 (`Bridge`, `Commands`, `Journey`, `Market`, `Pad`, docs on taint and controllers).

## Feature matrix and decisions

| Subsystem | GatherPath | HarvestMate | Gatherpedia | HME choice |
|---|---|---|---|---|
| Routes, solver | strong (2-opt/Or-opt, walls, jobs) | — | recorded routes, overlay, 3D arrow | GatherPath's solver and route store; Gatherpedia's recorded routes become saved routes |
| Node data | GatherMate2 only | names/requirements table | QuestieDB spawns (herb, ore, pool, beast) | merged spawn layer with provenance |
| Map pins | — | — | canvas pins, legend | HME overlay (same canvas approach) |
| Key binding | — | temporary override at nodes (on by default) | route toggle binding | HarvestMate's mechanism, off by default + consent |
| Soft target / nameplate | — | banner + marker, CVar changes with popup | Glimmer, CVar changes restored | both kept; marker defaults off so they don't stack |
| Skill detection | — | primary professions | all incl. Fishing | HME Player (all) feeds both |
| Loot/gather tracking | — | spell + loot learning | loot tracker per zone | HarvestMate's learning + HME's (skins, kills, deaths) |
| Session | — | session box, gold/h | session box, rates | one HME session engine |
| Prices | — | Auctionator/TSM | — | unified layer (+ Forever-GPS) |
| Guides | — | next-skill report | 1-300 guides | Gatherpedia's + adaptive status |
| Trainers | — | rank reminders | trainer list | both |
| Windows/buttons | 1 + button | hub + button | window + button | one window, one button |
| Saved data | GatherPathForeverDB | HarvestMateDB | GatherpediaDB(+Char) | one account + one character DB, migration |

## Problems found upstream (and what HME does)
- HarvestMate turns on a key override, click-to-move and auto-loot by default → off, consent first, released on combat/binding change/logout.
- HarvestMate announces gathers to group chat and emotes by default → off by default.
- HarvestMate and Gatherpedia both drive the soft-target nameplate CVar → marker off by default; Glimmer restores its CVars.
- Three addons, three minimap buttons, three sets of event frames, duplicated loot tracking → one of each.
- GatherPath requires GatherMate2 → optional.
- GatherPath's tests relied on the C runtime's `rand()` (differ on Windows) → portable generator in the fake client.
- Plain Lua 5.1 `xpcall` drops arguments (HME's first event bus did) → fixed and tested on real 5.1.
- Forever-GPS documents that `EnableKeyboard` and override bindings are protected in combat → HME's window never takes the keyboard; capture only hides.

## API notes (Forever, verified from working upstream code, not yet by HME in game)
`C_Map.GetMapWorldSize`, `GetWorldPosFromMapPos`, `GetMapRectOnMap`, `GetPlayerMapPosition`; `WorldMapFrame:AddDataProvider` / `AcquirePin` with an XML template; map canvas children; `C_NamePlate.GetNamePlateForUnit("softinteract")`; `PLAYER_SOFT_INTERACT_CHANGED`; `issecretvalue`/`canaccessvalue`; `GetUnitSpeed` may be secret; `SetOverrideBinding` (not in combat); `C_CVar`; `GetLootSourceInfo`; `IsFishingLoot`. Minimap tooltips are unreadable since 12 Nov 2026 (not attempted).
