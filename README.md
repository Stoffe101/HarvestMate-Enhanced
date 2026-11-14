# HarvestMate Enhanced

An all-in-one gathering companion for **World of Warcraft: Forever** (1.60.1, interface 16001): where to level Herbalism, Mining, Skinning and Fishing, which farms pay best for *your* character, routes drawn on the world map and minimap, Skinning treated as real hunting (beast clusters, kill time, respawns), one-key gathering, and session statistics that teach the recommendations what you actually achieve.

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

Optional addons HME uses when present: Forever-GPS (navigation, prices), GatherMate2 (extra recorded nodes), Auctionator or TradeSkillMaster (prices), TomTom (waypoint arrow). HME works fully without any of them.

## Using it

- **Farm Finder:** pick a profession and a goal (fastest leveling, best gold, a material, balanced, safest, current zone, least travel) and a risk mode. You get ranked farms with skill-ups/hour, gold/hour (conservative, typical, optimistic), travel time, risk and confidence, and the reasons. **Start farming route** plans a loop and guides you round it; **Navigate** gets you there (through Forever-GPS when installed).
- **Leveling Guides:** Gatherpedia's 1-300 guides with your status on top: cap, next milestone, whether you can train, and advice when your farm goes grey.
- **Materials:** the field guide, with known zones, your own counts, prices and "Farm this".
- **Profits & Stats:** sessions (predicted vs actual), measured rates per area, records and achievements.
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

Read [ARCHITECTURE.md](ARCHITECTURE.md), [FEATURES.md](FEATURES.md), [TESTING.md](TESTING.md), [KNOWN_LIMITATIONS.md](KNOWN_LIMITATIONS.md), [UPSTREAM.md](UPSTREAM.md) and [THIRD_PARTY.md](THIRD_PARTY.md).

## License

GPL-3.0-or-later for the combined addon (it includes GPL work and QuestieDB-derived data). Parts from MIT-licensed projects keep their MIT notices in `HarvestMateEnhanced/Licenses/`. See [THIRD_PARTY.md](THIRD_PARTY.md).
