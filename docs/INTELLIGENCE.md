# Farming intelligence, learning and confidence

## Evidence and confidence

Every Farm Finder result says what its numbers rest on (evidence level) and gives a range, as in 0.2.0. Since 0.3.0 it also keeps five confidence dimensions apart, because one number would hide that a farm can have well-known spawn points and unknown prices at the same time:

| Dimension | High when | Low when |
|---|---|---|
| Spawns | sites confirmed by your gathering or GatherMate2; beasts you skinned in that zone | predicted from bundled data; fishing pool spots (pools move: historical places, never live) |
| Route | recorded, or every leg walked on the grid | straight lines between stops |
| Yield | 60+ of your gathers or skins | estimated yields |
| Profit | fresh auction prices for the items | vendor values only; "unknown" without prices or when leveling |
| Fits you | measured kill pace, within level and skill | high risk, elites, mostly grey nodes |

"Measured" means **this character's own** sessions.

## Learning, per character

Each character keeps its own totals per farming area (`HarvestMateEnhancedCharDB.stats`). Estimates blend measured rates with the model by hours (one hour of the model's weight), so a short session moves a farm a little, not all the way. Other characters' hours in the same area count for less: a quarter for beasts and skins (pace depends on the character), 0.6 otherwise. A farm that is slow for one character is not written off for all.

Upgrading from 0.2.0: with one character in the journal, its measured areas become that character's in full; with several, each character's share is rebuilt from its own sessions.

**Area reputation** labels come from evidence only: consistently productive (10%+ above the estimate over 1.5 h and 2 sessions), often underperforming (20%+ below), good for leveling, good for profit, high travel overhead (30%+ of trips travelling), frequently interrupted, needs more observations. Reset per area: `HME.Learning.ResetArea(key[, everyone])`.

## Skinning attribution

- One skinning cast is one skin; a corpse looted right after is that corpse's loot.
- A repeated loot window of a corpse already skinned is ignored.
- Loot without a creature source (a node, a chest) is not attributed to a beast.
- Kill time is learned only from fights that ended with exactly one beast looted (2-180 s); anything else counts as unclear, never as a sample.
- `/hme diag` shows the last loot decisions (creature IDs only) to check this in game.

## While farming

The HUD (normal and detailed) shows the material you got most of with its rate and the expected rate, kills, skins, average kill time and time between skins. A verdict on observed vs predicted appears only after 10 farming minutes and 8 events; before that it says "too early to judge". The rolling rate covers the last 20 farming minutes. The new numbers feed the farm's estimate for you when the session ends. With two or more earlier sessions of 15+ minutes in the same area, the detailed HUD compares this one with them over the same farming time.

## Rankings

On top of 0.2.0's scoring: your corrections (below), a small boost and a reason when a farm gives something an open goal needs, a reason when your earlier sessions here did better or worse than estimated, "less travel than the top earner" when that is the trade-off, terrain and cave warnings, and gold per skin, per kill and per trip (nil, never zero, without prices).

## Corrections

Marks with a scope that fits the mistake, always reversible (`/hme corrections` lists them, `/hme uncorrect <n>` undoes one):

| Mark | Scope | Effect |
|---|---|---|
| beast does not spawn here | that spot, 40 yards (right-click a beast pin) | its spawn points there are left out |
| beast is not skinnable | that zone (or everywhere, if you choose) | left out of skinning there |
| inaccessible | the area, 150 yards | farms centred there are left out, saying why |
| dangerous | the area | risk +0.3 |
| overcrowded | the area | ranked x0.7, fading out over 7 days |
| inefficient | the area | ranked x0.8 |
| needs more observation | the area | shown, no penalty |

0.2.0's "wrong beast" marks (left out everywhere, for good) became "not skinnable, everywhere" corrections, so they can now be undone; the old data is kept.

## Herbs, ore and fishing

- **Adaptive loops**: a stop where you gathered a node a few minutes ago (5) is skipped on the next pass. Only your own observation; HME never claims to know which nodes are up at a distance, and never skips all stops.
- **Adaptive circuit** (guidance mode): the next stop is the nearest one not visited this lap.
- **Herbs + Ore priorities**: equal, herbs first, ore first, lower skill first, proven spots, short loop, most gold. The top results say whether one combined loop gives more than two separate loops, and that the game tracks only one of Find Herbs / Find Minerals at a time.
- **Fishing** pool spots are where pools have been seen; they are shown as historical places with low spawn confidence.

## Goals, shopping lists and expeditions

- Shopping lists are typed in one line ("50 Heavy Leather, 30 Iron Ore, 20 Goldthorn"); what could not be read is said.
- **Expedition** (Goals page, `/hme exp`): the materials are grouped by profession, each profession searched once, and stages chosen greedily by what they cover per hour of farming plus travel from the previous stage, so the plan does not zig-zag. Each stage lasts until its items are expected to be done (at most 2 hours, at most 6 stages). Items no profession of yours gathers, or with no farm in reach, are listed with the reason. Progress counts what you gather after starting; a finished stage says what comes next. Go, Next, Skip, reorder and Replan; nothing moves you.
- **Best beasts for a material**: `HME.Skinning.BestBeasts(results, itemID)` ranks beast populations by the material an hour (the beast's share of the area's kills), with levels, the Skinning needed (and for its highest level), the skill-up colour, yield per skin (observed with sample sizes, or the estimate, said so), confidence and up to three hunting areas. The Farm Finder shows it: Skinning, goal "A material", **Best beasts** at the top right of Details; a click opens the beast's best area.
- **Recipes** (optional, Forever-GPS's copy of the client's own recipe tables): `/hme recipe [n] <item>` turns a recipe's missing gathered materials into a shopping list; the sell/keep advisor says what a material is used for.
- **Vendors and mailboxes** when bags fill: the suggestion's Do it asks Forever-GPS for the nearest one, on your click only.

## Records

Best Skinning and Mining sessions (gold an hour, estimated), most efficient herb session, most skill-ups an hour, most leather in one session, most valuable session, longest session, most productive farm and longest route ridden round. Rates count sessions of 30 minutes or more only, so a lucky five minutes never sets them; the most productive farm needs 1.5 hours of yours.

## Planning for another level or skill

"Plan for" in the Farm Finder (and staged plans) use simulated level and skills only for that search. Measured statistics come only from real sessions, so a hypothetical plan never changes them.
