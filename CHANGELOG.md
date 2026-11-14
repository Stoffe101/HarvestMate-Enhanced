# Changelog

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
