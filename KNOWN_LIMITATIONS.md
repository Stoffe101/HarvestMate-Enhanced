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
- Forever-GPS 2.7 (released) has no published API: HME fills its journey panel the way `/fgps way` does, the player presses Go, and HME recognises its journey by destination (within 80 yards). ForeverGPS.API v1 is implemented on the Forever-GPS branch `feature/public-api` (draft PR, not merged); HME uses it automatically when present.
- The hand-off is tested against Forever-GPS's real API code and route engine separately, not in the live game.
- Questie is detected but its data is not read (the bundled QuestieDB-derived spawns cover the same beasts and nodes).
- Prices are what other addons recorded; with none installed, only vendor values are known and profit rankings say so.

## Game restrictions respected
- Since the 12 November 2026 update addons can't read minimap tooltips; HME does not try (HarvestMate's note).
- In combat: no binding, CVar, Glimmer or map-opening changes; key capture closes.
- Secret values (GUIDs, names, speeds in combat) are skipped, not worked around.

## Learning limits
- Kill time is learned only from fights with exactly one beast looted; packs, tagged-by-others and evaded fights count as unclear. Pet-assisted kills count as your pace.
- Respawn time cannot be observed directly; measured beasts/hour per area replaces the assumption.
- Bank contents count only as last seen when you opened the bank; other characters' bags are never known.
- No crafting suggestions: HME has no reliable recipe data, so sell/keep advice is limited to goals, reserved items, vendor vs auction.

## Licensing
- The QuestieDB-derived spawn data has a provenance caveat (THIRD_PARTY.md); the combined addon is offered under GPL-3.0 only.

## Not done yet
- Localization: HarvestMate's strings are in 10 languages; HME's new pages are English only.
- Route sharing is by export text only; no in-game send.
- No vendor/mailbox navigation without Forever-GPS (the suggestion names the Forever-GPS command).
- Terrain is still unknown to the planner: long straight legs are flagged for checking, and the route editor fixes them by hand.
