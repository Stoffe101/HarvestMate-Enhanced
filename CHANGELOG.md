# Changelog

## 0.3.0 (development build, unreleased)

### Fixed (confirmed by reproduction tests)
- **Two arrows on "Guide me here"**: with another Forever-GPS journey running, taking over at the farm showed HME's arrow next to Forever-GPS's. Now one place decides who points; Forever-GPS pauses its arrow (API v2) or HME guides on the map only. The journey is never stopped.
- A journey started during the farm (e.g. to a trainer) left HME's loop arrow up next to it; HME now steps aside and resumes after.
- The "Guide me here" hint pointed at `/hme guide`, which opens the Guides page; there was no button. Now `/hme here`, `/hme giveback` and a Dashboard button.
- Skinning: a corpse looted within 4 s of a skin was counted as a second skin; a repeated window of a skinned corpse could count as loot.
- Travel estimates between two places other than where you stand used Forever-GPS's from-here estimate.
- One right-click on a beast pin removed that species from recommendations everywhere, for good; now scoped and reversible (old marks migrated).
- The map overlay errored on a plan without a centre.
- 0.2.0 measured areas would have counted at "other characters" weight after the per-character change; they are seeded per character on upgrade.
- No bounds on provider prices: impossible values could inflate rankings.
- A running session's duplicate-event set grew without bound.
- Item names outside the field guide (shopping lists, recipe reagents, live materials) asked only for the global `GetItemInfo`, which the WoW Forever client does not have: they would have shown as "item 12345". Now `C_Item.GetItemInfo` first. The test client no longer has the global either.
- Building a long loop froze the game for a moment when recordings were on the map: every leg was checked against every recorded point in one frame (~0.3 s for 99 stops and 10 recordings). Now a background job with a prepared search.
- Found by the first real-client report: `/hme diag` said "no position" (a `local a, b = x and f()` line keeps only f's first value), and the same mistake made every character's class read as UNKNOWN, so the kill-time model's class adjustment never applied. Both fixed; a static test now rejects that pattern in every HME file.
- The terrain reorder pass changed the route's stops over several frames and could not be stopped: a route rebuilt meanwhile could be reordered or set back. It now works on a copy, commits once, and stops with the route (rebuild, edit, delete).

### New
- **Terrain-aware loops** through Forever-GPS's walking grid (API v2 `LocalPaths`), cached per leg, drawn along the walked turns, approximate legs in orange, the arrow following the turns, lap time from the walked length, and a hybrid reorder pass kept only when really shorter. Real-grid fixture of two real HME loops for tests (docs/TERRAIN.md).
- **Record My Route**: start, pause, resume, stop, cancel, trim; simplified and bounded; loops and there-and-back; gathers along the way; export/import; recordings as preferred corridors for planned loops (docs/RECORDING.md).
- **Caves**: Gatherpedia's cave outlines and entrances you mark; legs go through entrances; inaccessible caves rank lower.
- **Per-character calibration**, area reputation, separate confidence dimensions (spawns, route, yield, profit, fits you), scoped reversible corrections, profit per skin/kill/trip, goal-driven reasons, history verdicts (docs/INTELLIGENCE.md).
- **While farming**: rolling rates, materials with expected rates, kill pace, time between skins, observed vs predicted once there is enough data, now vs your earlier sessions.
- **Adaptive loops** (skip stops you just emptied) and an **Adaptive circuit** guidance mode.
- **Herbs + Ore priorities** and a combined-vs-separate check; best beasts for a material.
- **Expeditions**: a shopping list across professions and zones as staged farms with travel; shopping lists typed in one line on the Goals page.
- **Vendors and mailboxes** through Forever-GPS (API v2 `NavigateToService`) from the bags-full suggestion, on your click.
- **Optional recipes** from Forever-GPS's copy of the client's tables: `/hme recipe` and uses in the sell/keep advisor.
- **Records** with minimum farming times; journal text filter.
- **Heatmap views**: predicted density, your gathering, skill-up potential.
- **Diagnostics** to copy (`/hme diag`), privacy-scrubbed; a short **first-run setup** (`/hme setup`).
- **Best beasts** panel in the Farm Finder (Skinning, a material).
- Walking legs uses 3 ms a frame in batches of 16, and no new batch starts in combat.
- Save format 3. The test runner fails on any Lua error that reaches the error handler.

### Forever-GPS (branch feature/public-api, API v2)
- `HoldArrow`, `ReleaseArrow`, `ArrowHeld`; `ended` and `hold` events; `HasTerrain`, `LocalPath`, `LocalPaths`, `LocalBound`; `NavigateToService`. Tests on the real stack and walking grid (`tests/test_api_v2.lua`).
- Its Luacheck job failed on `CreateVector2D` (W113): declared as a client function in `.luacheckrc` (EasyFind, EasyFind GPS and WoW Forever-only addons call it); `/fgps diag` now probes it and `C_Map.GetMapPosFromWorldPos`. The code was not changed.

## 0.2.0

### Fixed (confirmed by reproduction tests)
- Forever-GPS: any arrival was treated as arriving at the farm, so a journey the player redirected elsewhere still started HME's loop.
- Forever-GPS: walking into the farm while HME's own journey ran left that journey's arrow up next to HME's (two arrows).
- The session clock started at "Start farming", so travel was counted as farming and lowered measured rates.
- A running session was lost on /reload.
- Duplicate loot events could count one corpse twice.
- The route pages' tab icons used single backslashes (missing textures in game).
- With no price known at all, "Best gold" showed nothing.

### New
- Navigation ownership by request token and destination snapshot (pending, active, arrived, cancelled, superseded, released, stale); HME never stops a journey it did not start; "Guide me here" when another journey runs.
- ForeverGPS.API v1 support (Forever-GPS branch feature/public-api), tested against its real code.
- Session time split: travel, farming, combat, gathering, waiting, idle (configurable); farming vs trip gold/hour; sessions survive reloads.
- Skinning 2.0: partly skinnable level ranges, eligibility separate from efficiency, unambiguous-fight kill timing with recency and level weighting, weak class prior, yields counted once with sample sizes, beasts can be marked wrong.
- Evidence levels and ranges for every farm; rankings prefer measured data; zones of unknown size flagged.
- Farm Finder: Herbs + Ore combined loops, several materials at once, play-time selector, filters, plain-language reasons, comparison view, profiles.
- Goals (materials, skill, gold, shopping lists) with held vs gathered progress and time to finish; staged leveling plans; rate-limited suggestions with per-kind switches; inventory capacity; sell/keep advisor.
- Map: profession colours, confirmed vs predicted, grouped crowded pins, hunting-area outlines, start marker, simple and heatmap modes, right-click corrections.
- Route editor (add/remove waypoints, undo, reverse), route quality labels, edited routes protected.
- Profits & Stats: journal, overview with bests and most productive areas and beasts, filters. HUD sizes.
- Damaged saves repaired entry by entry; imports validated and size-limited; schema 2.
- tools/bench.lua benchmarks; tools/upstream_check.py for reviewing upstream releases.

### Changed
- License statement: the combined addon is GPL-3.0 (QuestieDB data has no "or later" grant).

## 0.1.0 (unreleased, first build)

First version of HarvestMate Enhanced: GatherPath Forever 1.12.1, HarvestMate 2.0.13 and Gatherpedia 1.0.1 in one addon.

### New
- Farm Finder for Herbalism, Mining, Skinning and Fishing with seven goals, risk modes, ranked results, three gold estimates, travel, risk and confidence with reasons.
- Skinning as hunting: eligibility, hunting areas, circuits, kill-time and yield learning, respawn-limited throughput, materials-only or total value.
- Spawn sites with provenance and shared spawns counted once.
- Adaptive guide status (caps, training, levels, grey farms).
- Route planner on top of GatherPath's solver; planned routes rebuild for your skill.
- Navigation ownership with Forever-GPS hand-off, HME arrow and optional TomTom.
- Session engine, measured area rates, predicted vs actual history.
- Unified price layer (Forever-GPS, Auctionator, TSM, vendor).
- One window, HUD, minimap button, settings; export/import; migration from the replaced addons.

### Changed from the upstream addons
- One-key gathering, click-to-move/auto-loot during gathering and group/emote announcements now start off and ask first.
- GatherMate2 is optional for routes.
- One minimap button, one window, one session box.

### Tests
- Headless suite on real Lua 5.1, including GatherPath's ported regression tests.

Upstream changelogs: `upstream/*/CHANGELOG.md`.
