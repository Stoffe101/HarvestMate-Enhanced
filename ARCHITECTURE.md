# Architecture

One addon folder, one private table (`ns`), one event frame, one account database and one character database. Modules talk through `HME.Signal` / `HME.Listen`; heavy work runs as background jobs.

```
HarvestMateEnhanced/
  Core/         Namespace (events, signals, secret-value guards, jobs, perf), Util, DB (+ export/import),
                Migrate (from the replaced addons), Player (level, faction, skills, position, speed),
                GPCompat (Gatherpedia helpers), Commands
  Data/         Zones (HME), Leather (HME estimates), Index; Gatherpedia/ (vendored data and logic)
  Gather/       HarvestMate's engine (vendored) + HGCore (its core, adapted) + Glue (prices, consent, safety)
  Glimmer/      Gatherpedia's Glimmer (vendored) + Glue
  Engine/       Geo, Spawns, SkillModel, Prices, Risk, Cluster, Optimize (GatherPath), Skinning, Gathering,
                Learning, Session, Recommend, Planner, Guide
  Routes/       GatherPath's routes, map lines and their pages (adapted)
  Map/          Overlay (spawn pins, hunting areas), Arrow, Guidance (who navigates)
  Integrations/ ForeverGPS (bridge), TomTom
  UI/           Theme, Kit, Window, Page*.lua, HUD, Minimap
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
