# HarvestMate Enhanced

An all-in-one gathering companion for **World of Warcraft: Forever** (1.60.1, interface 16001): where to level Herbalism, Mining, Skinning and Fishing, which farms pay best for *your* character, routes drawn on the world map and minimap, Skinning treated as real hunting (beast clusters, kill time, respawns), goals and staged leveling plans, one-key gathering, and session statistics that teach the recommendations what you actually achieve — with every estimate saying what it rests on.

Version 0.7.0 (development build). What has been seen in the real game client: 0.3.0 and 0.4.0 load, `/hme diag` and `/fgps diag` work, and two screenshots of 0.4.0 (Farm Finder, Dashboard, the farming HUD) led to the fixes in 0.4.0 and 0.5.0. The 0.5.0, 0.6.0 and 0.7.0 changes are tested headless only so far: see [docs/MANUAL_TESTING.md](docs/MANUAL_TESTING.md). A personal-use project: no public releases.

**New in 0.7.0**: route **versions** you can put back, **redo**, moving and **snapping** waypoints, **sharing** one route without your history, your own **danger map** (enemy players you met, deaths with an enemy in sight) on the map and in risk, **price trends**, a **ready to go?** check (bags, repairs, rank cap), **your characters** with their professions, the **session path** on the map, and an optional Copilot line on the HUD.

**New in 0.6.0**: the **Farming Copilot** (what to farm now and why, for your mode and the time you have, with its evidence and one click), a **prediction ledger** that compares every planned session with what you got and adjusts estimates for farms you have not measured, the **Skinning Explorer** (every beast as a profile with your own drop journal), **quest synergy** (farms that also progress quests in your log), the **Route Director** (loops sized to your time, laps, empty stops), a **notification center**, **session reviews**, **search everything**, and sell/process/keep advice. How it all works: [docs/COPILOT.md](docs/COPILOT.md).

It brings three addons together into one coherent addon, one window, one minimap button and one saved database:

| From | What it contributes |
|---|---|
| [GatherPath Forever](https://github.com/severd8/gatherpathforever) 1.12.1 (MIT) | Route solver, saved routes, world map and minimap lines, direction arrows, avoid ("taboo") areas, skip list, display options |
| [HarvestMate](https://www.curseforge.com/wow/addons/harvestmate-herbalism-mining-skinning-helper) 2.0.13 (MIT) | One-key gathering, nearby-resource banner, tooltips with skill and drops, learning, achievements and records, reminders, profit comparisons |
| [Gatherpedia](https://www.curseforge.com/wow/addons/gatherpedia) 1.0.1 (GPL-3.0+) | Field guide data, 1-300 guides with recorded routes, trainers, QuestieDB-derived spawn points, Glimmer |

[Forever-GPS](https://github.com/Stoffe101/Forever-GPS) stays a separate, optional addon: HME hands long journeys to it and takes over at the farm.

## Install

1. Download `HarvestMateEnhanced-<version>.zip` (or build it: `python tools/package.py`).
2. Close the game. Unzip so you have `World of Warcraft/_forever_/Interface/AddOns/HarvestMateEnhanced/HarvestMateEnhanced.toc` (not nested twice).
3. Start the game; in the AddOns list make sure **HarvestMate Enhanced** is ticked (tick "Load out of date AddOns" if it says out of date).
4. Type `/hme` or click the leaf button on the minimap.

**Coming from HarvestMate, Gatherpedia or GatherPath Forever?** Keep them enabled for one login: HME copies their saved data in (their own data is not changed) and pauses its own copy of their features while they run. Then press **Import and turn off** on the Dashboard and `/reload`. Details: [docs/MIGRATION.md](docs/MIGRATION.md).

Optional addons HME uses when present: Forever-GPS (navigation, prices, and with its API v2 also terrain-aware loops, one-arrow hand-over, the nearest vendor or mailbox, and recipes), GatherMate2 (extra recorded nodes), Auctionator or TradeSkillMaster (prices), TomTom (waypoint arrow). HME works without any of them.

**Forever-GPS API v2 is not in a Forever-GPS release.** It is on the branch `feature/public-api` of github.com/Stoffe101/Forever-GPS (draft pull request 3). With the released Forever-GPS 2.7, HME works as before: journey panel, straight-line loops, and Guide me here on the map only. To use API v2:

1. In your Forever-GPS checkout: `git fetch origin`, then `git checkout feature/public-api`.
2. There, `python tools/package.py`: it writes and checks `dist/ForeverGPS-2.7.0-forever.zip`.
3. Close the game and install that ZIP as Forever-GPS's own `docs/INSTALL.md` describes ("The API branch, for HarvestMate Enhanced"). It replaces the released Forever-GPS folders; keep a copy of the old ones.
4. In the game, `/hme diag` should say `Forever-GPS: 2.7.0 (API v2)`, `walking grid API yes` and `arrow hold yes`, and `/fgps diag` should say `Game API: all 28 present`.

HME detects the API at login and uses each part it finds. Going back to the released Forever-GPS needs nothing in HME.

**Before trusting it in the game**, run the checklist in [docs/MANUAL_TESTING.md](docs/MANUAL_TESTING.md) (items 37-62 came with 0.3.0, 63-76 with 0.4.0, 77-88 with 0.5.0, 89-104 with 0.6.0, 105-118 with 0.7.0). Everything so far is tested only headless; see [TESTING.md](TESTING.md#verified-where).

## Using it

- **Farm Finder:** pick Herbs, Ore, Herbs + Ore, Skinning or Fishing, a goal (fastest leveling, best gold, one or more materials, balanced, safest, current zone, least travel), a risk mode and how long you can play. Each farm comes with a plain sentence on why, skill-ups and gold per hour as a range, farming vs whole-trip gold, travel, risk, and what the numbers rest on (measured, partly measured, known yield, published data or assumption). Mark farms to compare them side by side; save a search as a profile. **Start farming** plans the loop and guides you; far farms go through Forever-GPS and HME takes over on arrival.
- **Goals & Plans:** goals like "100 Heavy Leather", "Skinning 225" or "50 gold of materials" with progress (in bags and gathered, apart), the best farm for each with time and loops to go; staged leveling plans (e.g. Skinning 175 → 300) with training points; saved profiles.
- **Leveling Guides:** Gatherpedia's 1-300 guides with your status on top: cap, next milestone, whether you can train, and advice when your farm goes grey.
- **Materials:** the field guide, with known zones, your own counts, prices and "Farm this".
- **Profits & Stats:** sessions (predicted vs actual; filter by zone, material, route or character), measured rates per area, records (with minimum farming times) and achievements.
- **Skinning levels** (`/hme sl`): a small box that says which beast levels to kill for Skinning points right now, and keeps up as you skin.
- **Expeditions** (Goals page): a shopping list across professions and zones becomes staged farms with travel.
- **Record My Route** (Routes page): ride your own loop; it becomes a route to follow, edit and share.
- **Setup** (`/hme setup`) and **diagnostics** (`/hme diag`: a report to copy after a test).
- **Routes and maps:** GatherPath's route pages: your routes, New route, Avoid areas, Map display.
- **Settings:** everything, explained; anything that changes your controls or game settings asks first.

Commands: `/hme help`. Old commands `/hm`, `/gp` and `/gpf` still work while those addons are not installed.

## Develop

```bash
pip install lupa
```

```bash
python tools/run_tests.py
```

```bash
python tools/package.py --check
```

Read [docs/NAVIGATION.md](docs/NAVIGATION.md), [docs/TERRAIN.md](docs/TERRAIN.md), [docs/RECORDING.md](docs/RECORDING.md), [docs/INTELLIGENCE.md](docs/INTELLIGENCE.md), [docs/DIAGNOSTICS.md](docs/DIAGNOSTICS.md), [ARCHITECTURE.md](ARCHITECTURE.md), [FEATURES.md](FEATURES.md), [TESTING.md](TESTING.md), [KNOWN_LIMITATIONS.md](KNOWN_LIMITATIONS.md), [UPSTREAM.md](UPSTREAM.md) and [THIRD_PARTY.md](THIRD_PARTY.md).

## License

The combined addon is GPL-3.0 (version 3: the QuestieDB-derived data carries no "or later" grant); HME's own code is also available under GPL-3.0-or-later. Parts from MIT-licensed projects keep their MIT notices in `HarvestMateEnhanced/Licenses/`. See [THIRD_PARTY.md](THIRD_PARTY.md), including a provenance caveat about the QuestieDB data.
