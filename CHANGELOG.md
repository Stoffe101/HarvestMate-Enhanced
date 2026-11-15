# Changelog

## 0.7.0 (development build, unreleased)

What 0.6.0 left from its brief. Tested headless only (unit and integration tests, rendered previews, benchmarks); nothing of 0.7.0 has been run in the game yet: docs/MANUAL_TESTING.md items 105-118.

### New
- **Route editor**: Redo next to Undo; **shift-click** picks up a waypoint and the next click puts it down (moving one; right-click keeps it where it was); **Snap** (on by default) puts new and moved waypoints on a known node of the route's kinds within 20 yards (herb, ore and fishing routes; beasts wander, so skinning loops never snap).
- **Route versions**: Done, Rebuild and trimming a recording keep the waypoints they replaced (6 per route). The Route Inspector's **Versions** menu puts one back; the waypoints it replaces are kept as a version too.
- **Share a route** (Route Inspector): one route as text with its waypoints, zone and purpose. It leaves out your laps and lap times, stop visits and yields, versions, when and how long you recorded it, the gathers you saw on the way and the prediction (rates, gold). Nothing is sent; you copy the text.
- **Your danger map** (`Engine/Danger.lua`): the players you see (a nameplate, a target, a mouse-over) outside instances, enemy or not, where you stood and at what hour, once per player per 10 minutes; your time in each zone; deaths marked "enemy in sight" when one was seen in the 30 seconds before (not "killed by": the client does not say). A zone where you met many enemies an hour (half an hour there or more) scores riskier; the Copilot says "Enemies common here" with a button for lower-risk farms; `/hme danger`.
- **Price trends** (`Engine/Trends.lua`): one point a day per gathering material HME prices (the day's lowest listing and the latest typical figure, from whichever addon it reads), 21 days; Forever-GPS's own daily history first when it has one. From 3 days: up, down or steady against the median, on the Materials page with a word of advice, and a Copilot "selling high/low" card for a material in your bags. Listings, not sales, and it says so.
- **Map layers**: an "HME layers" button on the world map (and Settings) with a legend: your deaths and the spots where you met enemy players; the spawn points of creatures your open quest objectives name.
- **Ready to go?** (`Engine/Ready.lua`): before the Copilot's farm, bags against what the farm fills them with in your time, the lowest durability you wear, the rank cap against the farm's rate, risk, unknown travel. A "Ready?" card when something needs a look (Nearest vendor or repair through Forever-GPS); `/hme ready`.
- **Your characters** (Profits & Stats, Characters): each character as it last showed HME, with its gathering professions and ranks, what a capped one needs next (training, or a level), and its HME materials with their age.
- **Session path** (`Engine/Trail.lua`): where you went during a session (a point every 15 seconds when you moved) and each skin, gather, skill-up and death, kept with the 5 newest sessions. The session review's **Show the path** draws it on the map with a mark every 10 minutes.
- **Copilot on the HUD** (Settings, off by default): the Copilot's top suggestion as one line on the farming HUD. With it off the HUD is exactly 0.5.0's.
- `/hme diag`: danger map, price history, characters, map layers lines (counts only).

### Changed
- **Exports carry no personal history**: Settings' "Export routes and areas" used to copy whole routes, laps, stop yields and recording times included. It now carries waypoints and purpose only; the gathers seen while recording go only with "... with recorded gathers". Importing an older export drops those fields.
- Danger and the price log are cleared by Settings, Forget learned data, with the rest.

### Saved data
- Schema 4 still: new sections start empty (`obs.players`, `obs.presence`, `priceLog`, routes' `revisions`, characters' `profs`, sessions' `trail`); settings `mapLayers`, `hudCopilot`, `editorSnap`. A 0.6.0 save keeps everything.

## 0.6.0 (development build, unreleased)

Tested headless only (unit, integration against Forever-GPS's real API code, rendered previews, benchmarks). Nothing of 0.6.0 has been run in the game yet: docs/MANUAL_TESTING.md items 89-104.

### New
- **Farming Copilot** (its own page, and the Dashboard's next step): one recommendation for your mode (level fastest, most gold, a material, balanced, lower risk, short session, with my quests, my proven farms, explore) and the time you have, with why, how sure, what it rests on, a range, and its button; training at the cap, goal forecasts as ranges, quest farms, bags filling, a farm gone grey, empty route stops. Not now (6 hours) and Not interested (that kind); one "where to farm" card at a time, held for 15 minutes unless another is 15% better. Skill-ups are capped at your rank cap (a farm no longer promises 246 skill-ups when 82 are left before training). docs/COPILOT.md.
- **Prediction ledger**: every planned session's prediction against what you got (counts, never gold), weighted by hours and recency, other characters at half weight, shrunk toward the model (1.5 hours of prior); after two sessions it scales farms you have not measured, and says so. Skill-ups adjust only after 4 sessions and 3 hours. The Copilot page lists predicted against observed per farm.
- **Skinning Explorer**: every beast in the spawn data as a profile; search by name, zone, level or leather; can it be skinned (only what the game said, else "not confirmed"); per skin, yours apart from the estimate; your drop journal with skill-ups right after a skin, corpse loot apart; a rough rate for you; where it lives; your quests that want it; **Hunt it** plans circuits for that creature alone.
- **Quest synergy**: the quest log (C_QuestLog) matched to farms: creature and item ids from Forever-GPS's new `QuestObjectiveTargets` or Questie, else the objective text. Farm Finder rows say "quest"; the Copilot has a "With my quests" mode. Read-only.
- **Route Director**: "Make a loop of 10/15/20/30 min" from a route (a new variant, the original untouched, the time as a range, rough when the legs were not walked); laps recorded while following (time, gathers, skins, skill-ups); stops that never gave anything in 4+ visits, and a variant without them (Route Inspector, and offered by the Copilot).
- **Notification center** (the bell in the window header): goals, training, bags, better farms, routes, session reviews, data; each to chat and the list, the list only, or off.
- **Session review** when you stop a session yourself: time, counts, skill-ups, value as an estimate, against the prediction and your last 10 sessions, laps, goals, deaths. `/hme review`.
- **Search everything** (the header, `/hme find`): pages, materials, creatures, zones, your routes, trainers, milestones, profiles, goals, your quests.
- **Bags**: when they fill (measured from free slots, or estimated from what you gather), as a range; your characters' materials with how old the numbers are (Materials page).
- **Sell, process or keep** on the Materials page: keep for a goal, auction after the cut with the deposit at risk, vendor, smelting or crafting from the client's recipes when every reagent has a price.
- **Farm profiles** restore the whole workspace: Copilot mode and time, HUD size, map detail, risk and price modes, notifications.
- `/hme diag`: Copilot, prediction ledger, quests and notices lines.

### Fixed
- **Laps were miscounted**: a lap counted when the stop number went down, which guided mode never does, while a re-entry at a nearer stop counted one that was not ridden. The Route Director counts them now.
- A Farm Finder search started by the Copilot could have replaced the one you started on its page (they shared a job slot); each now has its own.

### Saved data
- Schema 4: new sections checked on load (characters' materials, notices, Copilot feedback); a 0.5.0 save keeps everything, its predictions included (the ledger reads them).

### Forever-GPS (feature/public-api)
- `API.QuestObjectiveTargets(questID)`, read-only: the ids a quest's objectives name, from Questie.


## 0.5.0 (development build, unreleased)

### Fixed (found in the real client or by new tests, each reproduced first)
- **The farming HUD's route title ran outside the panel** (real-client screenshot: "Hillsbrad Foothills - Skinning leveling" over the world beside a route-only HUD). The title had a start and no width. A route's name is now two lines, each fitted to the panel: the zone, then what for and the stop ("Skinning leveling · stop 1/12"); the full name is in the tooltip. Every text in the HUD now has a width inside it. `/hme hud reset` puts the HUD back.
- **A failed or interrupted skinning cast could turn the next ordinary loot into a skin** (since 0.4.0's cast-start detection). Failed and interrupted casts now clear it.
- A skin after a skinning cast but **without a named creature** is counted once, as uncertain, and `/hme diag` says how many.
- **Skins during a manual pause** went into the session; now only the beast's yield record learns from them.
- **New route asked everyone without GatherMate2 to install it**, though HME always has nodes (bundled spawns, your gathers, GatherMate2 when there).
- **The route pages were laid out for a 540-wide page** (HME's is 738): buttons ran past their row. Rows now have room for three lines; the terrain note no longer names a git branch or says "straight lines" twice. Zone names fall back to HME's bundled names before "Map 1424".
- **The detailed HUD showed "0 s" and "0c/h"** in its time split, and repeated the stop count; only parts with something in them show now.

### New
- **Route Inspector** (Inspect on each route): length (walked only when legs were walked, else the straight loop), lap time at your speed, how much follows the terrain, approximate and long legs to check, what it is for, your sessions on it (a measured rate only after an hour over two sessions), the stop nearest you, Follow and Waypoints.
- **Practical alternatives** in the Farm Finder: the best farm from the same search with clearly lower risk and at least 70% of the goal's number, and, for a far farm, the closest with half the travel and 80% of the number.
- **Materials** as an encyclopedia entry: opens on your profession with a material selected; skill needed and your colour in words, price (auction estimate or vendor), what you gathered and where, the zones with your side, Farm this, Add goal.
- **Profits & Stats** opens with the period at a glance: farming time with travel and idle, what was gathered, skill-ups with an estimated value, and a trend of skill-ups an hour over the last 12 sessions.
- **Skinning levels: compact mode** (a chevron in its title row): skill, highest and best levels, the next unlock and your target.
- `/hme diag` has an **Interface** line: font in use (and whether Inter loaded), corners, window scale and fitted scale, HUD state and size, Skinning levels.

### Tools and tests
- Previews: a **text outside its panel** check (respecting scroll clipping), which flags the 0.4.0 HUD; 16 new states (the HUD route-only in every size, travelling, nothing recognised, session only, paused; Skinning levels with targets and compact; Routes with a route; the Route Inspector); the gallery shows **before and after** against the approved baseline.
- `tools/perf.lua` and `tools/perf_compare.py`: the same headless measurements against any versions (docs/PERFORMANCE.md).
- New tests: `test_hud.lua` (every HUD text bounded, in every state and size; fails on 0.4.0), `test_skincount.lua` (ten skin-counting cases), the GatherMate2 message, the Route Inspector, alternatives, the compact levels box.

### Forever-GPS (feature/public-api)
- The intermittent `manyReroutesInAMinute_pause` failure: reproduced every time at an ordinary machine speed. The test assumed a fast machine (planning slices use real time); it now sets the machine's speed, with new variants for ordinary and slow machines. Not a product bug.

## 0.4.0 (development build, unreleased)

### Fixed (found in the real client, reproduced in tests)
- **Skins were not counted in WoW Forever.** A 43-minute session showed zero skins and zero skill-ups while Gatherpedia's leather counts rose: Forever's Skinning cast has a spell ID the classic list lacks. A cast is now a skin when its spell has Skinning's name (the ID is remembered), HarvestMate's own gather start counts too, and HarvestMate's skinning loot is a once-only backstop. `/hme diag` shows both counts. The 43 minutes were real: fights keep the farming clock going.
- **Gold an hour cut to "3[g]13..."** in tiles: money used the game's coin icons. It is short text now ("3g 13s", "45s 20c", "1,240g"), and a tile steps its number down a size before it would cut it.
- **Cut labels** ("Find a f...", "Medium c...", "Preview on map" squeezed): buttons and badges grow to fit their label; long names in the Farm Finder are fitted by measuring them.
- **Optimistic farm figures**: the Skinning model promised a level-41 character 209 beasts and 175 skill-ups an hour (a 6-second kill, every spawn alive, no interruptions). The kill floor is 55% of an even fight, the area thins to a steady state, and a practical factor (0.78) stands for real sessions. A perfect circuit is shown apart, never planned on. Measured sessions replace all of it.
- The farming HUD and the Skinning levels box opened on top of each other.
- Two icon paths had single backslashes (broken textures): caught by the static test before release.

### New look: a field atlas
- Warm charcoal surfaces, moss green for what is selected and the one main action, brass for ornament only (contour lines in the header and hero cards, corner ticks, medallions around profession icons, diamond pips), gold kept for money. All art generated by `tools/make_ui_art.py` (no third-party art).
- A size larger type everywhere, sentence-case labels (no more shouting capitals), nothing under 11 px.
- The window fits the screen at any UI scale and resolution, keeping its proportions.

### Dashboard
- Arranged around what you do now. Farming: a panel with active time against elapsed, what was recognised, skill-ups and gold an hour against the prediction, a plain warning when nothing has been recognised ("No skins recognised in 43 min of farming... /hme diag shows what HME saw"), and actions that fit the state (Navigate, Guide me here, Pause/Resume, Stop farming). Not farming: the next step.
- Learned professions are large cards with a progress bar, training tick, milestone and time at your pace; unlearned ones share a single line.
- Goals with bars, and your last session or suggestions, fill the rest.

### Farm Finder
- Profession and goal first; risk, play time, region, confidence, Save search and Plan ahead behind **Filters**.
- Each result leads with the goal's number (skill-ups, gold or materials an hour), shows confidence as four diamonds, risk in its colour and travel.
- Details: why, three tiles with ranges, how sure in words ("Estimate: not measured yet · medium confidence"), then tabs (Overview, Find, Risk, Evidence) and one primary action.
- Best beasts rows with diamonds; compare unchanged in content.

### HUD and Skinning
- The HUD has three sizes (compact, normal, detailed), cycled from its title row: what you gather, skill-ups, gold an hour, your first goal with a bar, materials against what was expected, route stop, prediction check, records, time split.
- Skinning levels: sentence case; the target line keeps three questions apart: can this level be skinned and is it a point; can you fight it (level, elite); is the creature skinnable at all (you skinned it, the beast list has it, or unknown).

### Other pages
- Goals: one calm row per goal with item icon, count and bar; Best farm and a quiet x (Plan trip on shopping lists).
- Leveling Guides open on a profession you have and show the 1-300 journey: ranges, a track filled to your skill, training ticks and where you are.
- Trainers: profession icons and room for the location.

### Tools
- `python tools/ui_preview.py --shots`: 40 states from realistic data (this character, prices, three weeks of sessions, many goals, the session without skins) and seven screen sizes and UI scales, screenshotted by headless Chrome or Edge (no window, no focus change), checked for overlap, cut and tight text, cramped buttons, tiny and dim text, missing art and frames off screen, with a review gallery (`build/preview/review.html`) and baseline diffs (`--approve`, `--strict`).

### Forever-GPS (feature/public-api)
- "integer overflow attempting to store 99999990100" when an item was listed at the highest buyout: fixed there (see its changelog).

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
- **A new, modern interface**: an own design system (docs/DESIGN.md).
  - Inter as the interface font, bundled under the SIL OFL.
  - Calm charcoal surfaces, rounded panels, a leaf-green accent kept for the one main action of each view.
  - Primary, secondary, ghost and danger buttons; pill switches; tinted badges; KPI tiles.
  - The Dashboard leads with one "Next step", and the Farm Finder details lead with three numbers.
  - The HUD and the Skinning levels box lead with large figures; the Skinning box adds a coloured level strip.
  - Settings can switch to the game's font or to square corners.
  - `tools/ui_preview.py` draws every screen as HTML, to check layouts without the game.
- **Skinning levels** display: MAX LEVEL (the highest level you can skin) and BEST LEVELS side by side, large; opens from a Levels button on the Dashboard's Skinning card, the Skinning leveling guide, Shift-click on the minimap button, a key binding, Settings or `/hme sl`.
- Interface previews check themselves: each page measures its text as drawn and lists any overlap (0 on every screen).
- **Skinning levels** box (`/hme skinlevels` or `/hme sl`, or Settings): which beast levels to kill for skill-ups right now, updated on every skill-up, level-up, zone and target change; the next unlock; this zone's beasts in those levels or the two closest zones that have them; a chat line when a higher level becomes skinnable.
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
