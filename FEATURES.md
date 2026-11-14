# Features

Status key: **New** (HME), **Kept** (from upstream, unchanged in behaviour), **Improved**, **Replaced** (by a single HME implementation). Verification of each feature is listed in [TESTING.md](TESTING.md); nothing here has yet been tried in the real client.

## Farm Finder (New)
- Professions: Herbalism, Mining, Skinning, Fishing. Goals: fastest leveling, best gold/hour, a specific material (herb, ore, leather...), balanced, safest practical, current zone, least travel.
- Reads level, faction, skills and caps, position and mounted speed; "Plan for" overrides level and skill for look-ahead or alts.
- Each result: zone and part of zone, creature levels, targets with skill colors and requirements, skill-ups/h, nodes or beasts/h, gold/h (conservative / typical / optimistic), travel time and how sure, risk label with reasons, confidence with reasons, data source.
- Never ranks on density alone; uncertain profit is discounted; zones too high, excluded or unreleased are listed as left out.
- Preview on map, Start farming route, Navigate.

## Skinning (New)
- Eligibility per beast (skill vs level, level difference by risk mode, elites, game-confirmed unskinnable).
- Hunting areas from spawn clusters, circuits of nearby areas, a sweep inside wide areas, shaded areas and spawn dots on the map.
- Kill time learned per character from fights; yields learned per beast and per level; mob loot learned for "total farming value".
- Respawn-limited vs pace-limited throughput, and says which.

## Herbalism and Mining (New / Improved)
- Shared spawn sites counted once with shares; predicted vs confirmed sites (your gathers, GatherMate2).
- Region selection per goal; loops pass within detection range; your gathered nodes join routes (as GatherMate2's did in GatherPath).

## Fishing (Kept / New)
- Gatherpedia's fish data, zone skill and getaways (Kept); ranking of fishing zones, pool loops where pool data exists, catch counting (New).

## Leveling guides (Kept / Improved)
- Gatherpedia's 1-300 guides, ranges, spots, recorded routes including cave loops and there-and-back routes (Kept).
- Your status: cap, next milestone, can you train now or which level you need, Fishing's book/quest ranks; "mostly grey" detection on the farm you follow; best farm for your skill (Improved).

## Field guide (Kept, new look)
- Every herb, ore, fish and hide, colored for you, filters (all, can gather, skill-ups, this zone), Known zones with faction tags and your counts, prices with source and age, Farm this, spawns in your zone.

## Routes and maps (Kept from GatherPath)
- Multiple routes per zone, world map and minimap lines, per-map color/width/opacity, per-route colors, direction arrows, line to the route, range circle, lap time, rebuild, edit, rename, show/hide, skip list, avoid ("taboo") areas drawn on the map and routed around, restore defaults. Planned routes from the Farm Finder rebuild for your current skill (New).

## Guidance (New / Replaced)
- One navigator at a time: Forever-GPS for the trip, HME's arrow round the loop; TomTom optional; survives /reload.

## Gathering helpers (Kept from HarvestMate, safer defaults)
- One-key gathering (asks first), nearby-resource banner, Soft Target Interact setup (asks first), tooltips with skill, skill-up ranges, drops and prices, skinning recognition, lockpicking, Cultivation, learned resources and requirements, profit comparisons (sell vs smelt), bag report, trainer and tracking reminders, gear reminders, achievements, records, toasts. Group/emote announcements kept but off by default.

## Glimmer (Kept from Gatherpedia)
- Glimmer on soft-targeted herbs, ore, pools, skinnable beasts, quest objects and lootables, per-kind switches, preview; settings in HME's Settings.

## Sessions and statistics (Replaced / New)
- One session engine for every profession: auto start, idle pause, gold/h, skill-ups/h, nodes, skins, kills, catches, deaths; history with predicted vs actual; measured rates per area feed the rankings.

## Prices (Replaced)
- One price layer: Forever-GPS, Auctionator, TSM, vendor; three estimates; sale mode; never scans, buys, sells or posts.

## Data (New)
- One account database and one per character, bounded, exportable/importable (routes, avoid areas, nodes), resettable, with migration from the three replaced addons that never changes their data.

## Interface (New)
- One window with sidebar sections, lazy pages, compact layout, scaling, tooltips on every control; HUD; one minimap button and addon compartment entry; key bindings (all unbound by default).

## Added in 0.2.0 (implemented; real-client validation pending)
- **Navigation ownership:** request tokens and destination snapshots; HME never stops a journey it did not start; "Guide me here" beside another journey; reload-safe.
- **Session timing:** travel, farming, combat, gathering, waiting and idle kept apart; farming vs trip gold/hour.
- **Skinning 2.0:** partly skinnable level ranges, efficiency apart from eligibility, unambiguous-fight kill learning (recency and level weighted), yields with sample sizes, beast corrections.
- **Evidence and ranges:** every farm says whether it rests on measured sessions, partial measurements, known yields, published data or assumptions, and shows a range.
- **Farm Finder:** Herbs + Ore loops, several materials at once, play time, filters, reasons in plain words, comparison, profiles.
- **Goals & Plans:** material, skill, gold and shopping-list goals; staged leveling plans with training points; profiles; suggestions; inventory; sell/keep advisor.
- **Maps:** profession colours, confirmed vs predicted, grouped pins, hunting outlines, start marker, simple and heatmap modes, right-click corrections; route editor and route quality.
- **Data:** damaged saves repaired, imports validated and limited, schema 2.

## Proposals, not implemented
- Terrain-aware routing from a road/terrain graph (needs a legally usable data source; Forever-GPS's walking grid could be exposed through its API later).
- Crafting-based "use" advice (needs reliable recipe data).
- Localized HME pages.
- Sharing routes with other players in game (export text only today).
