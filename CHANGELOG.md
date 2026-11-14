# Changelog

## 0.2.0 (unreleased)

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
