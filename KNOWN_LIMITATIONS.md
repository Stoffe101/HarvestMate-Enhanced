# Known limitations

## Not yet seen in the game
Everything in HME has only run against the headless fake client. Layout, textures, the map overlay's place on the canvas, the arrow's heading on Forever, Glimmer inside HME, and the Forever-GPS hand-off are unverified in the real client. Work through [docs/MANUAL_TESTING.md](docs/MANUAL_TESTING.md) before relying on it.

## Estimates and assumptions
- **Respawn time** of beasts (5 min) and **node up-fraction** (⅓ of spawn points) and **node respawn** (10 min) are assumptions, flagged wherever they limit a result. Measured rates replace them per area as you farm.
- **Leather yields** start from plain estimates (`Data/Leather.lua`) until you have skinned a beast (or beasts of that level) about 8 times. Forever-only materials (Pristine Leather...) are never assumed.
- **Kill time** starts from a level-difference model (14 s at equal level); your fights teach it. Fights with more than one beast looted are not used.
- **Fishing** catch rate (18 s a cast) and the skill-up curve are approximations.
- **Bundled spawn data** (QuestieDB, Forever build, via Gatherpedia) is where things *can* appear. Zones Forever reworked may differ; Gatherpedia marks most items "classic" rather than confirmed for Forever.
- **Zone sizes and links** for Forever's own zones (Zephras Isle, Riverglades, Shen'dralas, Mount Hyjal) are not bundled: the client's sizes are used in game; without Forever-GPS their travel time shows as unknown.
- **Guarded towns** in `Data/Zones.lua` are approximate positions used only to rate risk.
- **Training**: rank thresholds follow HarvestMate's in-game checks (50/125/200 at levels 10/20/35). Fishing's higher ranks are described as book/quest without specifics.

## Routing
- Terrain (cliffs, water, caves) is not known to the solver: loops are straight lines between stops, routed only around your avoid areas. Planned loops through mountains may need an avoid area drawn. Recorded Gatherpedia routes (including cave loops) follow real paths.
- Hunting circuits connect area centres; inside wide areas a simple sweep is added.
- Travel without Forever-GPS is HME's rough estimate (neighbouring zones, boats), not a planned journey, and ignores flight paths.

## Integrations
- Forever-GPS 2.x has no published API yet; HME fills its journey panel the way `/fgps way` does and the player presses Go. A small API is proposed in [docs/FOREVERGPS_BRIDGE.md](docs/FOREVERGPS_BRIDGE.md); HME uses it automatically once it exists.
- Questie is detected but its data is not read (the bundled QuestieDB-derived spawns cover the same beasts and nodes).
- Prices are what other addons recorded; with none installed, only vendor values are known and profit rankings say so.

## Game restrictions respected
- Since the 12 November 2026 update addons can't read minimap tooltips; HME does not try (HarvestMate's note).
- In combat: no binding, CVar, Glimmer or map-opening changes; key capture closes.
- Secret values (GUIDs, names, speeds in combat) are skipped, not worked around.

## Not done yet
- Localization: HarvestMate's strings are in 10 languages; HME's new pages are English only.
- Route sharing is by export text only; no in-game send.
- Farming profiles/goals with progress tracking, zone comparison view and inventory-capacity warnings beyond HarvestMate's bag reminder are not built.
