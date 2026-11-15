# The Farming Copilot and what it stands on (0.6.0)

How HME decides what to suggest, how it learns from your sessions, and where each number comes from. Code: `Engine/Copilot.lua`, `Engine/Ledger.lua`, `Engine/Quests.lua`, `Engine/Bags.lua`, `Engine/Bestiary.lua`, `Routes/Director.lua`, `Engine/Notify.lua`, `Engine/Review.lua`, `Engine/Search.lua`, `Engine/Economy.lua`.

Nothing here uses a network, an AI model or any automated game action. Every action is a button you press.

## The loop

1. **Recommend.** The Copilot asks the Farm Finder for farms (background jobs, cached for 10 minutes or until skill, level, zone, goals or mode change), applies your mode and time, and proposes cards.
2. **Record the assumptions.** Starting a farm stores its prediction (skins, nodes or catches an hour, skill-ups an hour, and the calibration factor used) with the route (`Engine/Planner.lua`).
3. **Observe.** The session counts what happened (`Engine/Session.lua`), per area.
4. **Compare.** The session journal keeps each area's prediction next to its result; the **ledger** reads them back.
5. **Update.** The ledger's factor scales farms you have not measured; farms you have measured already use your own rates (`Engine/Learning.lua`).
6. **Recommend again**, with the adjusted numbers and a sentence saying they were adjusted.

## The prediction ledger (`Engine/Ledger.lua`)

| | |
|---|---|
| Entry | one area of one session: 10+ farming minutes and a stored prediction |
| Compared | **pace**: skins (or corpses looted, whichever is higher), nodes or catches an hour; and skill-ups an hour. **Never gold**: a price that moved is not a prediction that was wrong. |
| Weight | hours of the session, at most 2, × recency (half-life 30 days) × 1 for this character, ½ for others |
| Factor | `log f = Σ w·log r / (Σ w + 1.5)`, r = observed / predicted clamped to 0.2–3 |
| Used | 2+ sessions and at least 5% away from 1; skill-ups only with 4+ sessions and 3+ hours, then blended with pace (their geometric mean), because skill-ups fall as a farm turns grey and stop at a rank cap |
| Band | ±1.28 standard errors of the weighted log ratios, shrunk the same way |

The 1.5 "hours of the model being right" is the prior: one lucky quarter hour at twice the prediction moves the factor by about a seventh of the way. A prediction made with a factor stores that factor, and the next comparison divides it back out, so the ledger compares against the plain model and never chases its own tail. The engines cache their figures, so the factor already applied is kept on them and only the difference is applied (found in 0.6.0's own previews, where repeated searches compounded it).

Per farm, `Ledger.Area` gives predicted and observed over all your sessions there ("Predicted 60 skins/h, observed 48/h: 20% under (3 sessions, 1.4 h)"); the Copilot page lists them, worst first.

## The Copilot (`Engine/Copilot.lua`)

**Cards.** Each rule proposes cards: `id` (stable, so "Not now" holds), `type`, `group` (cards of one group contradict each other), `title`, `objective`, `why` (reasons), `evidence` (what it rests on), `conf` (0–1), `benefit` (the number and its unit, with a range), `priority`, `action` and secondary actions.

| Rule | When | Priority |
|---|---|---|
| farm | not farming: the best farm for the mode and time | 60 |
| where-live | farming: keep going (35), or try another farm (80) after 15+ farming minutes when you get under 70% of the prediction (this session's rolling verdict, or the ledger over 1.5 h and 2 sessions) and another farm beats what you actually get here by 25% after its trip | 35 / 80 |
| train | at the rank cap (90), or the next rank ready within 10 points (70); level-locked rank (30) | 30–90 |
| goals | up to three open goals: the best farm for each, and how long, as a range | 45 |
| quest | a farm whose creatures or nodes are in your quest log | 50 |
| bags | full within 15 minutes, or 2 slots left | 65 / 85 |
| route | the route you follow has 2+ stops that never gave anything | 55 |
| grey | the farm you follow has gone grey | 75 |
| prices | gold mode with auction prices over a week old | 25 |
| ready | 0.7.0: the farm card's trip has something to check (Engine/Ready.lua) | 50 / 70 |
| danger | 0.7.0: you met 4+ enemy players an hour in this zone (30 in Lower risk mode) | 52 |
| market | 0.7.0: a material in your bags moved 20%+ against its median (40 in gold mode) | 20 |
| learned | the ledger adjusts this profession's estimates | 15 |

**Arbiter.** Drops cards you put off ("Not now": 6 hours for that card; the farm rule then offers the next farm) or said you are not interested in (that type, until Settings brings them back); keeps the highest-priority card of each group, so "keep going" and "switch" never show together; holds the suggested farm for 15 minutes unless another becomes 15% better or the context changes.

**Comparing farms** (`C.Choice`): what a trip of your time gives, farming time after the trip there (unknown travel is assumed to be 20 minutes), skill-ups capped at your rank cap, × trust in the evidence (measured 1, partly measured 0.95, known yield 0.9, published data 0.85, assumption 0.8; unknown travel × 0.85). Modes:

| Mode | Asks the Finder for | Ranks by |
|---|---|---|
| Level fastest | leveling | trip value × trust |
| Most gold | profit | trip value × trust (no prices: materials an hour, said so) |
| A material | your open goals' items | materials |
| Balanced | balanced | trip value × trust |
| Lower risk | safest, "safer" risk mode | × (1 − risk)², and says what the safety costs |
| Short session | leveling (gold at 300) | what fits your time (30 minutes by default) |
| With my quests | balanced | only farms that serve a quest in your log, × 1.25 per objective (up to 3) |
| My proven farms | balanced | only farms you measured, by what you got |
| Explore | balanced | only unmeasured farms, by the optimistic end widened by how unsure it is, labelled a guess |

**When it looks again**: on events (skill or level, goals, guidance, session end, quest log, zone change; while farming at most every 30 seconds), never per frame. A search for a context that is gone is dropped from the job queue before it runs.

## Quest synergy (`Engine/Quests.lua`)

Only quests **in your log** count, read with `C_QuestLog` (WoW Forever's 12.x interface; the old globals as a fallback). Objective targets come from, best first: Forever-GPS's `API.QuestObjectiveTargets` (from Questie, 2.7 on `feature/public-api`), Questie's `GetQuest().ObjectiveData` or its database row through an adapter that checks every function first, and otherwise the objective text ("Gray Bear slain: 3/8") matched by name. Item objectives also match the creatures Questie says drop the item. Finished objectives and complete quests are left out. HME never accepts, tracks, completes or abandons a quest.

## Skinning Explorer (`Engine/Bestiary.lua`)

One profile per creature from the bundled spawns (QuestieDB, Forever build): levels, elite, spawn points per zone. **Skinnable** is "yes" or "no" only when the game said so; otherwise "not confirmed". The **journal** is your skins of it (from `obs.skins`: count, materials, per skin, zones, skill-ups within 5 seconds of a skin, last time); corpse loot is shown apart. **For you** is a rough per-creature rate: kill time (measured or modelled) + 6 s to skin + walking of 1800 / spawn points in its best zone (8–60 s), less 12% downtime, × the share of its levels you can skin; × 0.6 for elites, × 0.9 above your level. **Hunt it** asks the Farm Finder for circuits of that creature alone (`Skinning.Areas` takes an npc filter).

## Route Director (`Routes/Director.lua`)

**Timed loops**: lap = yards / speed × walk factor + stops × 4.5 s (herb and ore routes). Walk factor: walked / straight length when the legs were walked on Forever-GPS's grid, else 1.15 and "rough". The loop kept is the longest run of consecutive stops (the route's own order) whose ride and straight return to its first stop fits, ties broken by what those stops gave you, then by time. Band ×0.85–1.25 (×0.8–1.4 rough). It is a new route marked as a variant; the original never changes.

**Laps**: while you follow a route, a lap ends when the stop number wraps (guided) or Guidance counts one (adaptive); time, gathers, skins and skill-ups go into `route.lapLog` (30 kept). Every stop counts visits and yields (a gather within 52 yards). A stop with 4+ visits and nothing gathered is weak (gathering routes only).

## Bags (`Engine/Bags.lua`)

Measured: free slots against farming time this session, once a slot was used and 10 minutes farmed. Estimated before that: each material fills its partial stack, then a slot per stack size. A range ×0.7–1.4. Your characters' materials are snapshots of HME's known materials only (bags when they change, bank when open), with when they were seen; another character's are never shown as live.

## Notifications, review, search, economy

- `Engine/Notify.lua`: categories (goal, training, bags, farm, route, session, data) each to chat and the list, the list only, or off; repeats held 30 minutes; one chat line a minute (shared with Suggest); 40 kept; buttons work until /reload.
- `Engine/Review.lua`: a session of 10+ minutes ends: time, counts, skill-ups, value (prices, not money), against the prediction (counts) and your last 10 comparable sessions, laps, goals, deaths. Opens when you stop it yourself (Settings), else waits in the list.
- `Engine/Search.lua`: prefix (3), word start (2), anywhere (1); 5 a kind, 14 in all.
- `Engine/Economy.lua`: keep (goal or reserved) first; auction after the 5% cut with the deposit at risk (15% of the vendor price, a classic rule) and the price's age; vendor; processing from the client's recipes only when every other reagent has a price.

## Danger map (`Engine/Danger.lua`, 0.7.0)

| | |
|---|---|
| Seen | `NAME_PLATE_UNIT_ADDED`, `PLAYER_TARGET_CHANGED`, `UPDATE_MOUSEOVER_UNIT`: a player (not you, not your party), enemy by `UnitIsEnemy`; outside instances; once per GUID per 10 minutes; where you stood (zone map, a 4% spot) and the hour |
| Time | your time per zone outside instances, in 30-second steps (at most 60 s counted per step) |
| Deaths | Engine/Risk.lua's record, `pvp = true` when an enemy was seen in the 30 seconds before |
| Risk | `enemies` part = enemies an hour in the zone / 8, clamped to 1, only after half an hour there; weight 0.15; the total stays at most 1 |
| Kept | 60 zones × 150 spots, least recent first out; per account; Forget learned data clears it |

## Price trends (`Engine/Trends.lua`, 0.7.0)

One point a day per HME gathering material: the day's lowest listing and the latest typical figure (copper a unit, before the cut), when the provider's price is under a day old (or of unknown age) and not an outlier. 21 days, 300 materials. Forever-GPS's `PriceHistory.Of` comes first when it has three points. Trend: the newest typical against the median of the days before; ±10% is up or down. Advice is a sentence, never an action.

## Ready to go? (`Engine/Ready.lua`, 0.7.0)

For the Copilot's farm and your time: bags (skinning: the farm's materials an hour, stack sizes, your partial stacks; minutes until full by halving; 2 free slots or fewer stops), repairs (the lowest worn durability; under 25% warns, broken stops), the rank cap (at the cap stops; reached within the trip warns), risk (0.6 or more warns), unknown travel (warns). Farming minutes are the trip less travel (20 minutes when unknown).

## Session path (`Engine/Trail.lua`, 0.7.0)

Every 15 seconds while a session runs, a point when you moved 15 yards (zone map, x, y, the farming clock); each skin, herb, ore, catch, skill-up and death with its place. 480 points and 400 events at most; packed as text into the session summary when it ends; the 5 newest sessions keep theirs. The map draws the zone with most of the path: an open line, a label every 10 farming minutes, a dot per event.

## Sharing (`Core/DB.lua`, 0.7.0)

`CleanRoute` keeps `name, mapID, points, kinds, sight, color, recorded, loop, backforth, trimmed` and a planned route's description without its prediction, time, goal or key (so the Farm Finder never re-plans someone else's route). Everything else stays home. `Export({ gathers = true })` adds the recorded gathers (what and where). An import drops laps, lap log, stop stats, versions, recording times and predictions that an older export carried.

## Saved data (schema 4)

| Where | What |
|---|---|
| `HarvestMateEnhancedDB.chars[name-realm]` | `bags`, `bagsAt`, `bank`, `bankAt` (HME's materials only), `level`, `faction`, `class`, `t`; 30 characters |
| `HarvestMateEnhancedDB.sessions[].areas[].predicted.calib`, `.skillCalib` | the factor a prediction was made with |
| `HarvestMateEnhancedDB.obs.skins[npc].ups` | skill-ups right after a skin of it |
| `HarvestMateEnhancedCharDB.copilot` | `mode`, `minutes`, `prof`, `dismissed[id]`, `notInterested[type]`, `where` (the held farm) |
| `HarvestMateEnhancedCharDB.notices` | text, category, time, read; 40 |
| routes (`gp`) | `lapLog` (30), `stopStats[i] = { visits, yields }`, `variantOf`, `variant` |
| settings | `notify`, `sessionReview`, `calibrate`, `copilot`; 0.7.0: `mapLayers`, `hudCopilot`, `editorSnap` |
| `HarvestMateEnhancedDB.obs.players[mapID][spot]`, `obs.presence[mapID]` | 0.7.0: players seen (`e`, `f`, `t`, `h` by hour), seconds in the zone |
| `HarvestMateEnhancedDB.priceLog[itemID]` | 0.7.0: `"day:low:typical;..."` |
| routes | 0.7.0: `revisions = { { t, why, points, length } }` (6) |
| `chars[name-realm].profs` | 0.7.0: `{ [prof] = { rank, max } }` |
| `sessions[].trail` | 0.7.0: `{ p = "m:x:y:f;...", e = "km:x:y:f;..." }` (5 newest) |
