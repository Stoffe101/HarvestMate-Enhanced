# Known limitations

## Not yet seen in the game
Everything in HME has only run against the headless fake client. Layout, textures, the map overlay's place on the canvas, the arrow's heading on Forever, Glimmer inside HME, and the Forever-GPS hand-off are unverified in the real client. Work through [docs/MANUAL_TESTING.md](docs/MANUAL_TESTING.md) before relying on it.

## Estimates and assumptions
- **Practical pace** (0.4.0): Skinning estimates assume a real session keeps 78% of a perfect circuit's pace (finding targets, pathing, adds, bags). It is a round figure, not measured on Forever yet; your own sessions replace it per area.
- **Respawn time** of beasts (5 min) and **node up-fraction** (⅓ of spawn points) and **node respawn** (10 min) are assumptions, flagged wherever they limit a result. Measured rates replace them per area as you farm.
- **Leather yields** start from plain estimates (`Data/Leather.lua`) until you have skinned a beast (or beasts of that level) about 8 times. Forever-only materials (Pristine Leather...) are never assumed.
- **Kill time** starts from a level-difference model (14 s at equal level); your fights teach it. Fights with more than one beast looted are not used.
- **Fishing** catch rate (18 s a cast) and the skill-up curve are approximations.
- **Bundled spawn data** (QuestieDB, Forever build, via Gatherpedia) is where things *can* appear. Zones Forever reworked may differ; Gatherpedia marks most items "classic" rather than confirmed for Forever.
- **Zone sizes and links** for Forever's own zones (Zephras Isle, Riverglades, Shen'dralas, Mount Hyjal) are not bundled: the client's sizes are used in game; without Forever-GPS their travel time shows as unknown.
- **Guarded towns** in `Data/Zones.lua` are approximate positions used only to rate risk.
- **Training**: rank thresholds follow HarvestMate's in-game checks (50/125/200 at levels 10/20/35). Fishing's higher ranks are described as book/quest without specifics.

## Routing
- Terrain comes only from Forever-GPS's walking grid (API v2, branch `feature/public-api`, not in the released Forever-GPS). Without it, planned loops are straight lines labelled approximate; recorded routes, corridors and cave entrances still apply.
- Walking a long loop's legs takes time in the background (about half a minute for 100 stops at 3 ms a frame, estimated from desktop timings) and pauses during fights; until then the loop is drawn with straight legs where not yet walked.
- The solver orders stops by straight distance; terrain only refines legs and reorders round bad detours afterwards (2-opt with the grid's bounds), so the order is not a full terrain-optimal tour.
- Walking a 100-leg loop costs several seconds of background CPU in the game (spread over frames); legs longer than 1500 yards are not walked.
- Caves are known only from Gatherpedia's outlines or your marks; heights and floors are as the grid knows them.
- Hunting circuits connect area centres; inside wide areas a simple sweep is added.
- Travel without Forever-GPS is HME's rough estimate (neighbouring zones, boats), not a planned journey, and ignores flight paths.

## Integrations
- Forever-GPS 2.7 (released) has no published API: HME fills its journey panel the way `/fgps way` does, the player presses Go, and HME recognises its journey by destination (within 80 yards). ForeverGPS.API v2 (journeys, arrow hold, walking grid, nearest service) is on the Forever-GPS branch `feature/public-api` (draft PR, not merged); HME uses each part automatically when present.
- With Forever-GPS 2.7, "Guide me here" beside another journey guides on the map and HUD only: that version cannot pause its arrow, and HME never shows a second one.
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
- Recipes come only from Forever-GPS's copy of the client's recipe tables; without it there is no crafting help. HME does not compare crafting profit (Forever-GPS's own crafting pages do).
- Per-character calibration starts from the journal on upgrade; sessions older than the journal's newest 120 are not split by character.
- Live verdicts wait for 10 farming minutes and 8 events; records need 30-minute sessions.

## Licensing
- Personal-use project: nothing is published as a release. The QuestieDB-derived spawn data has a provenance caveat (THIRD_PARTY.md); the combined addon is offered under GPL-3.0 only. Keep this in mind if the repository is public: its contents are visible.

## 0.6.0
- The Copilot's numbers are the Farm Finder's: where those are estimates, so are its. The ledger needs two planned sessions of 10+ minutes on a profession before it adjusts anything, and it only sees sessions started from HME's farms (routes you started yourself have no prediction).
- Skill-up predictions are compared but only adjust after 4 sessions and 3 hours: skill-ups fall as a farm turns grey and stop at the cap, so a short comparison says little.
- Quest synergy only knows creature and item ids when Questie is loaded (through Forever-GPS 2.7's API or directly); otherwise it matches objective text to names, which can miss renamed or ambiguous creatures. It never knows quests you do not have.
- The Explorer's "for you" rate is per creature and rough; the Farm Finder's circuits are the real plan. "Can be skinned" is unknown until the game says.
- Timed loops are cut from an existing route's order; they do not re-plan the loop or pick nodes the route does not have. The time is estimated, not measured, until you ride it.
- Bag forecasts count slots, not item kinds that cannot stack together, and another character's bags are as they were when you last played it.
- Auction deposits use the classic 15%-of-vendor rule; Forever may differ. Sale chances are not modelled: a listing is not a sale.

## Not done yet
- Localization: HarvestMate's strings are in 10 languages; HME's pages are English only (no Swedish yet).
- Route sharing is by export text only; no in-game send.
- No vendor/mailbox navigation without Forever-GPS (HME has no such data and says so).
- No estimated-profitability heatmap (the views are density, your gathering and skill-up potential).
- Expeditions are greedy (good, not optimal) and plan at most 6 stages of 2 hours.
- The new pages (Setup, Expedition card, Diagnostics window) are laid out but unverified in the game.

## 0.7.0

- **Players seen** depend on nameplates being shown for players (or your targeting them); with player nameplates off, the danger map only knows the players you target or mouse over. Counted where you stood, not where they were. In instances nothing is counted. If WoW Forever marks these unit answers secret, they are skipped and the map stays empty.
- **"Enemy in sight"** on a death means an enemy player was seen in the 30 seconds before, not that one killed you.
- **Price trends** need three days of prices; HME logs a price only when it reads one (opening Materials, a Farm Finder search, the Copilot) and only if the addon's price is under a day old. Listings, not sales.
- **Ready to go?**: bags are forecast for skinning farms (the farm's materials an hour); for herbs, ore and fish only the free slots are checked. Durability is read from the worn items; whether the game would let you skin without a knife is not checked.
- **Characters** show what each last told HME; a character not played since 0.7.0 has no professions listed.
- **Session path** is a point every 15 seconds when you moved 15 yards: not a recording of every turn. Only the 5 newest sessions keep it.
- **The map layer button** sits at the top left of the world map's canvas; another addon's button may share that spot (in-game check 109).
- **Snapping** uses HME's merged nodes (bundled spawns, your gathers, GatherMate2); a node the data places wrongly snaps wrongly. Snap can be turned off on the editor bar.

