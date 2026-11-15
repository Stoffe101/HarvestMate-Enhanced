# Architecture

One addon folder, one private table (`ns`), one event frame, one account database and one character database. Modules talk through `HME.Signal` / `HME.Listen`; heavy work runs as background jobs.

```
HarvestMateEnhanced/
  Core/         Namespace (events, signals, secret-value guards, jobs, perf), Util, DB (+ export/import),
                Migrate (from the replaced addons), Player (level, faction, skills, position, speed),
                GPCompat (Gatherpedia helpers), Diagnostics (report to copy), Commands
  Data/         Zones (HME), Leather (HME estimates), Index; Gatherpedia/ (vendored data and logic)
  Gather/       HarvestMate's engine (vendored) + HGCore (its core, adapted) + Glue (prices, consent, safety)
  Glimmer/      Gatherpedia's Glimmer (vendored) + Glue
  Engine/       Geo, Spawns, SkillModel, Prices, Risk, Cluster, Optimize (GatherPath), Skinning, Gathering,
                Learning, Evidence, Corrections, Session, Recommend, Planner, Guide, Goals, Expedition, Records,
                Suggest
  Routes/       GatherPath's routes, map lines and their pages (adapted), Editor, Terrain (walked legs),
                Recorder (Record My Route)
  Map/          Overlay (spawn pins, hunting areas, heatmaps), Arrow, Guidance (who navigates and who points), Caves
  Integrations/ ForeverGPS (bridge: journeys, arrow hold, walks, services), TomTom, Crafting (recipes, optional)
  UI/           Theme, Kit, Window, Page*.lua (incl. Setup), HUD, Minimap
```

## Data flow

```
 client events ──► Core/Namespace bus ──► Gather (HarvestMate) ──GATHER_LOOT──► Learning ──► obs.*, stats
                                     └──► Learning (loot, skins, kills, deaths) ─┘          │
 bundled data (QuestieDB via Gatherpedia) ─┐                                                 │
 GatherMate2 (optional) ──────────────────┼──► Spawns (sites, provenance) ◄────────────────┘
 your gathered nodes ─────────────────────┘        │
                                                   ▼
 Player profile ─► Skinning / Gathering ─► Recommend (score, risk, travel, confidence) ─► Farm Finder
                                                   │
                                                   ▼
                                Planner ─► Routes (GatherPath solver, avoid areas) ─► map + minimap lines
                                                   │
                                                   ▼
                       Guidance ─► Forever-GPS (travel) ─► arrival ─► Arrow (loop) ─► Session ─► Learning
```

## Saved data

`HarvestMateEnhancedDB` (account): `settings`, `hm` (HarvestMate's section), `gp` (Gatherpedia's), `routes` (GatherPath's), `obs` (nodes per map ≤ 1500, skins per beast, loot, mob checks, deaths ≤ 200), `stats` (≤ 400 areas), `sessions` (≤ 120), `migrations`, `schema`. `HarvestMateEnhancedCharDB` (character): `plan` (overrides), `guidance` (survives /reload), `eff` (kill-time samples ≤ 200, speed), `ui`. Schema upgrades run step by step (`DB.UPGRADES`); a newer save is kept as is. Export/import use a typed text format with a checksum; nothing is ever executed on import.

## The recommendation model

For every zone with data, the best area is found and evaluated; results are scored per goal and sorted.

**Herbalism / Mining.** Spawn points within 6 yards form a *site*; a site holding several node types gives each a share (shared Mithril/Truesilver spawns are counted once). Sites are weighted for the goal (skill-up chance, value, the wanted material); unreachable (red) types never count. `Cluster.Region` picks the best compact region (320-yard cells, smoothed, grown while neighbours hold ≥ 30 % of the best). Loop length is estimated (`0.7124·√(n·A)`, n = detection-radius cells) for ranking, then solved for real by GatherPath's solver when chosen.
`nodes/lap = sites × up-fraction (⅓, assumed) × (1 − competition) × min(1, lap / 600 s)`; `lap = loop/speed + nodes × (4.5 s + detour)`. Skill-ups/h = nodes/h × mean chance; gold/h = nodes/h × mean value (yields from HarvestMate's learned drops after 5 gathers).

**Skinning.** Beasts are filtered per character: skinnable at this skill (`1` to 10, `(L−10)·10` to 20, `5L` above), not above level + 2 (balanced; +3 fastest, +1 lower risk), elites only 8+ levels below, never ones the game said can't be skinned. Their spawn points are clustered (DBSCAN, 70 yards) into hunting areas; a circuit joins the best area with up to 3 others within 650 yards.
`time/beast = (kill + 2.5 loot + 2.5 skin + 3 pull + walk) × 1.12 downtime`, `walk = max(0, 0.5/√density − 22 yd)/7 + loop/(7·live beasts)`, kill = 14 s × (1 + 0.15·Δlevel) (×0.07 below, floor 40 %, elite ×3.5) × this character's measured factor (median of observed/model, shrunk with 6 pseudo-samples).
`beasts/h = min(3600/time, spawns × (1 − competition) × 3600 / 300 s respawn (assumed))`.
Yield per skin = estimate × k/(n+k) + observed/(n+k), k = 8 skins, per beast, else per level from HarvestMate's learned drops; a material seen fewer than 3 times without an estimate counts half.
Gold/h = beasts/h × skin value (+ observed mob loot in "total" mode, counted once).

**Fishing.** Zone skill from Gatherpedia; landing share rises from 40 % at the minimum to 100 % at no-getaways; catches/h = 3600/18 s × landing; skill chance per catch 1 until 75, then 1/((skill−75)/25).

**Scoring.** Usefulness × share of a planned session left after travel (`T/(T+travel)`, T = 60 min) × risk penalty (fastest `1−0.15r`, balanced `1−0.45r²`, lower risk `1−1.2r²−0.4r`); profit-type goals × `(0.7 + 0.3·confidence)` so uncertain estimates cannot win on a guess. Measured area rates blend in: `(h·measured + 1·model)/(h + 1)` hours.

**Risk** (0–1): creatures above your level and elites near the area (35 %), territory (25 %), enemy guards' towns (25 %), your recorded deaths (15 %); avoided zones are forced high. Labels: Lower / Moderate / Higher / High risk. It never sees players and never says "safe".

**Confidence** averages the trust of each input (spawn data confirmed or predicted, yields measured or estimated, kill time measured or modelled, assumed respawn, price source and age, zone size from the client or bundled).

**Prices.** Forever-GPS, Auctionator, TSM, then vendor. Conservative = lowest listing (or 80 % of a single price), typical, optimistic = typical + 5 %, all after the 5 % cut; sale mode picks auction, vendor or the higher. Conservative also assumes 15 % fewer nodes/beasts, optimistic 10 % more.

## Navigation ownership

`Map/Guidance.lua` holds the single owner: `fgps`, `tomtom`, `hme` or none. Far farms go to Forever-GPS (published API when present, else its journey panel — the player presses Go); HME's arrow is hidden meanwhile. Arrival (Forever-GPS's event, or being within 200 yards of the loop) hands over to HME's arrow round the loop. Stopping in Forever-GPS does not start HME's arrow by itself.

## Safety rules

No protected call in combat; override bindings and CVars change only with the player's yes and are released before combat, on binding changes, when turned off and at logout; key capture closes in combat and with the window; the window never takes the keyboard; the map overlay is a child of the map canvas (as Gatherpedia's pins were), the route lines use GatherPath's data provider; old addons running at the same time pause HME's copies of their features.

## Performance

Spawn sites are cached per profession and map and invalidated on new data; the Farm Finder runs as a job (8 ms a frame, 4 in low-performance mode); map pins are pooled and capped (600 / 250); pages are built when first opened. `/hme diag` prints timings.

## 0.6.0 additions

See docs/COPILOT.md for the algorithms.

- `Engine/Ledger.lua` (after Evidence): predictions against results from the session journal; `Calibrate(r)` in `Recommend.Find` before `Evidence.Apply`.
- `Engine/Bags.lua`, `Engine/Quests.lua`, `Engine/Copilot.lua`, `Engine/Bestiary.lua`, `Engine/Notify.lua`, `Engine/Review.lua`, `Engine/Search.lua` (`HME.Find`), `Engine/Economy.lua`: after Suggest; they listen to events and never run per frame.
- `Routes/Director.lua` (after `Map/Caves.lua`, because it wraps `Guidance.Advance`): timed loops, laps, stop statistics.
- `UI/PageCopilot.lua`, `UI/PageBeasts.lua`, `UI/Header.lua` (search box, bell, popovers, session review).
- Copilot searches run as their own background jobs (`copilot:<context>`), never in the Farm Finder's slot; jobs for a context that is gone are dropped from the queue.

## 0.2.0 additions

- `Engine/Evidence.lua`: evidence level per farm and gold/skill ranges (session percentiles weighted by hours and blended with the model by h/(h+1), else model bands: assumption x0.6-1.35, published data x0.7-1.25, known yield x0.8-1.15).
- `Engine/Goals.lua`: goals, inventory (bags; bank only as last seen), sell/keep advisor, profiles. `Engine/Suggest.lua`: rate-limited suggestions.
- `Engine/Guide.lua` `G.Plan`: stages at rank caps and every 40 points; each stage is a Farm Finder search at its starting skill.
- `Routes/Editor.lua`: waypoint editing through the map canvas click handler; route quality.
- Skinning eligibility uses every level of a beast's range (`skinShare`); the kill factor is a weighted median of unambiguous fights (weight halves every 14 days, x0.4 beyond +-2 levels), shrunk by 6 pseudo-fights, times a weak class prior.

### Navigation ownership (Map/Guidance.lua, Integrations/ForeverGPS.lua)

```
NavigateTo -> pending -(route:started, dest matches)-> active -(route:arrived, dest matches)-> arrived -> HME loop
                 |                                       |-(route:cleared)-> cancelled (no automatic takeover)
                 |                                       '-(another destination started)-> superseded (player's journey)
                 '-(another destination started)-> superseded
at the farm by position: active -> HME releases ONLY if the running journey still matches -> released -> HME loop
                         another journey running -> farm phase, HME arrow held, "Guide me here"
after /reload: pending/active that matches nothing running -> stale
```
Duplicate events are no-ops; with ForeverGPS.API the token decides instead of the destination.

### Session timing
`farm` accrues only after arrival or the first gather; idle stretches longer than `idleMinutes` move from farm to idle; combat and gathering casts are parts of farm; `travel` comes from Guidance. Area statistics learn farming hours only; travel per area is learned apart (`travelHours`).

## 0.3.0 additions

- **Who points** (docs/NAVIGATION.md): `Map/Guidance.lua` `G.Present()` is the single decision for the arrow (`hme`, `external`, `map`, `none`). Journeys keep their request tokens; Forever-GPS's arrow is paused through its API v2 hold, never by stopping its journey.
- **Terrain** (docs/TERRAIN.md): `Routes/Terrain.lua` asks Forever-GPS's `LocalPaths` for every leg, caches legs per account, assembles `route.path` (drawn) and `route.terrain` (summary, quality), refines the order with a 2-opt pass, and gives the arrow the turns of each leg. Priority: your edits, then cave entrances (`Map/Caves.lua`), recorded corridors, the grid, and finally the straight line.
- **Recording** (docs/RECORDING.md): `Routes/Recorder.lua`, passive, bounded, saved as recorded routes.
- **Learning and confidence** (docs/INTELLIGENCE.md): per-character area totals (`HarvestMateEnhancedCharDB.stats`, seeded on upgrade), `Evidence.Dimensions`, `Engine/Corrections.lua`, `Session.Live`, `Engine/Records.lua`, `Engine/Expedition.lua`.
- **Optional data from Forever-GPS**: walking grid and recipe tables are read through its API at run time, never copied.
- **Diagnostics** (docs/DIAGNOSTICS.md): `Core/Diagnostics.lua` keeps the last errors and builds a scrubbed report.
- **Saved data**: schema 3; new sections `terrain` (legs, bounded), `corrections` (bounded), `caves`, per-character `stats`, `recording`, `expedition`. Every collection that can grow has a bound.

## 0.7.0 additions

| File | What |
|---|---|
| `Engine/Danger.lua` | players seen (nameplate, target, mouse-over; not in instances) per 4% map spot, time per zone, `EnemyInSight` for deaths; `Zone`, `Near`, `Pressure` (read by `Engine/Risk.lua`), `MapData` |
| `Engine/Trends.lua` | a daily price point per material (`priceLog`), Forever-GPS's `PriceHistory.Of` first; `Of`, `Advice`, `Movers` |
| `Engine/Ready.lua` | the readiness checks for a Farm Finder result and a trip length |
| `Engine/Alts.lua` | professions stored with each character's snapshot; `List`, `Hints`, `ProfText` |
| `Engine/Trail.lua` | a session's path and events, packed into the session summary (5 newest keep one) |
| `Routes/Editor.lua` | redo, move (`E.Click` with shift), `Snap`, `Revise` / `Restore` / `Versions` |
| `Core/DB.lua` | `CleanRoute` (what a shared or exported route carries), `ShareRoute` |
| `Map/Overlay.lua` | layers (`danger`, `quests`) with a button and legend on the world map; `Replay` draws a session path (open polylines) |
| `Engine/Copilot.lua` | rules `ready`, `danger`, `market`; actions `mode`, `material`; `C.pick` (the farm card's result) |

Nothing new runs per frame: sightings are events, the presence and path samplers run every 30 and 15 seconds, prices are logged when Engine/Prices.lua reads one (at most once a day per value).

