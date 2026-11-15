# Gatherpedia

A field guide for World of Warcraft: Forever (1.60.1) that covers Herbalism, Mining, Fishing and Skinning, colored by your skill and backed by your own gathering log. Click the minimap button or type `/gp`.

Every item page lists its **Known zones**. Your own gathering log is merged in, and a **This Session** box shows your rates. **Guides** walk you from 1 to 300 with recorded farm routes and an on-screen arrow, map pins show every herb, ore and beast spawn, and **Trainers** lists where to train and buy supplies.

## Install (Windows, Battle.net)
1. Close WoW Forever.
2. In the Battle.net app, select **World of Warcraft**, choose **World of Warcraft Forever** in the version menu, click the gear icon next to Play, and choose **Show in Explorer**.
3. Open the Forever folder (probably `_forever_`), then `Interface`, then `AddOns`. Create `Interface\AddOns` if it doesn't exist.
4. Unzip the Gatherpedia zip there so you end up with `...\Interface\AddOns\Gatherpedia\Gatherpedia_Forever.toc`. Don't nest it as `Gatherpedia\Gatherpedia\`.
5. Start the game. On the character screen, open **AddOns** and make sure Gatherpedia is ticked. If it shows "out of date", tick **Load out of date AddOns**.
6. In game, click the gold G button on the minimap or type `/gp`.
7. Optional: for the intended fonts, put Marcellus-Regular.ttf and AlegreyaSans-Regular, -Medium and -Bold .ttf files (free from fonts.google.com) in `Gatherpedia\Media\Fonts`. Without them the game fonts are used.

Once it's published, the CurseForge app can install and update it for you (choose the Forever game version).

## Use
- **Left sidebar:** your gathering professions, with skill. A dropdown at the top of the left sidebar switches between *My professions* (what this character has learned) and *All professions*. `/gp options` has the same setting, saved per character.
- **Finding items:** a search box, plus filters for All, Can gather, Skill-ups and This zone. Click an entry for details; Shift-click links it in chat. *Best spots for my skill* sits under the grid. Gems, stones, scarce extras, seeds and bonus herbs (for example Swiftthistle) are marked as a bonus drop and say which node they come from; they are not counted as nodes in the collection total.
- **Known zones** (item page): every zone the item comes from, in classic 1.12 order.
  - Order:
    - herbs and ores: most common first;
    - fish: by the zone's fishing level, with the water type (inland, coastal, open sea);
    - skins: by beast level, low to high.
  - Skinning rows carry a short mob hint (for example "lvl 30-36 · raptors, crocolisks, tigers").
  - On a Skinning item, click a zone to open the map with a pelt pin on every spawn of the beasts at that level. In the Skinning guide, "Show beasts" does the same for the range. The pin ring is your skill-up chance (orange, yellow, green, gray; red is too high). Hover a pin for the beast, its level and the skill it needs.
  - Herbalism and Mining work the same way: on an item page, click a zone to see that herb's or ore's nodes. In the guide, the "Nodes" button next to a route shows every node for the range, and the route keeps running. Fishing spots have a "Pools" button where pool data exists.
  - Your current zone is highlighted. Click any zone to open the world map on it.
  - Zones you've gathered in get a check and your count.
  - Zones only you have found it in are added and tagged *yours*.
  - Faction hints:
    - Alliance and Horde home zones are tagged;
    - zones that suit your faction are tinted;
    - a line names the best ones.
  - *Only list zones I've gathered in* (options) hides the rest.
- **This Session** (bottom left): hover it, or right-click, for:
  - Start a new session, or forget the current zone.
  - Pause or resume the timer. Paused, idle and AFK time doesn't count toward rates. *Pause when idle* stops the clock after 5 minutes without a gather.
  - Show: gathered per hour, skill-ups this session, skill-ups per hour, time to skill cap, session time, or several at once (pick which).
  - Profession filter.
  - Number style: 1,234 or 1.234.
  - Look: icons, labels, compact.
  - *Keep on screen*: a movable floating box that stays up when the window is closed, with *Lock its position*.
  - *Hide this box*.

  The per-zone breakdown is at the top of the menu. Every choice is saved.
- **Guides** (sidebar tab): a 1-300 guide per profession, split into skill ranges. Each range lists where to go, what you'll find, the next rank to train and tips. *Start route* runs a recorded farm route with an on-screen 3D arrow that moves to the next stop within 30 yards and survives /reload; right-click the arrow for Stop and its size. The route is drawn on the world map and minimap. You can also bind a key to start or stop the best route in your zone (Key Bindings, AddOns, Gatherpedia), or right-click the minimap button.
- **Map pins:** *Show beasts* (Skinning), *Nodes* (Herbalism, Mining) and *Pools* (Fishing) put a small icon on every spawn point for the range. The key in the map's corner can be dragged anywhere on the map.
- **Window:** opens on the left side of the screen like the world map, and moves to the right of the map whenever the map is open. *Unlock the main window* in options lets you drag it.
- **Glimmer:** a Glimmer row in the sidebar (or `/gp glimmer`, also `/gp sparkle`) puts a glimmer cloud on the nearest herb, ore, fishing pool, skinnable beast, quest object, or other lootable the game soft-targets. The cloud sits on the object itself, not up on the nameplate. If a soft-target nameplate is used only as an anchor, its name and bar are hidden so names look like the default game. A soft, round item icon can float above herbs, ore, fishing pools and skinnable creatures (this can be turned off on the Glimmer Settings page). The cloud shows only while a soft-target or nameplate is available, and hides when that is gone. Brighter when you can reach it, dimmer when you can't, and grey if your skill is too low (herbs, ore, or a locked object when that can be read). Each kind has its own on/off switch and color on the Glimmer Settings page. Your previous soft-target settings are restored when Glimmer is turned off, and nothing is changed in combat. Avoid running another glimmer addon at the same time.
- **Trainers** (sidebar tab, or `/gp trainers`): every Herbalism, Mining, Fishing and Skinning trainer, plus fishing suppliers and the Expert / Artisan fishing stops. A switch at the top picks Alliance or Horde (one at a time; Neutral trainers appear in both). Click a name to open that zone on the map. A gold pin marks the exact spot when coordinates are known, and the coordinates are printed in chat.

## Slash commands
| Command | What |
|---|---|
| `/gp` | Open or close the window |
| `/gp show` | Open the window |
| `/gp herbs` / `mining` / `fishing` / `skinning` | Open a tab |
| `/gp trainers` | Open the Trainers list |
| `/gp minimap` | Show or hide the minimap button |
| `/gp options` | Options window |
| `/gp reset` | Clear all gathered counts and discoveries (asks first) |
| `/gp resetpos` | Move the window back to its default spot |
| `/gp session` | Show the This Session box again (`session float`, `session reset`, `session pause`) |
| `/gp debug` | Log unknown gathering spell IDs (for bug reports) |
| `/gp glimmer` or `/gp sparkle` | Turn Glimmer on or off |
| `/gp glimmer on` / `off` | Turn Glimmer on or off |
| `/gp glimmer preview` | Show a sample cloud in the middle of the screen for a few seconds |
| `/gp glimmer options` | Open Glimmer Settings in the main window |
| `/gp glimmer color herbs` (or `ore`, `fish`, `skin`, `quest`, `other`) `<color>` | Set a color (`gold`, `white`, `blue`, `green`, `purple`, `red`) |
| `/gp glimmer height <50-200>` | How far the stars rise (100% is the standard look) |
| `/gp glimmer count <3-32>` | How many stars in the column (16 is standard) |
| `/gp glimmer thickness <50-200>` | How big each glint is (100% is standard) |
| `/gp glimmer width <50-300>` | How far the column spreads left and right (100% is standard) |
| `/gp glimmer bright <50-200>` | Brightness (100% is standard; higher adds size and glow) |
| `/gp glimmer speed <slow|normal|fast>` | Animation speed |
| `/gp glimmer herbs` (or `ore`, `fish`, `skin`, `quest`, `other`) `on` / `off` | Turn one kind on or off |
| `/gp glimmer reset` | Restore Glimmer defaults |
| `/gp glimmer debug` | Print the current soft-target, category and anchor (for bug reports) |


## How counting works
A gather is counted when a loot window opens and its source matches one of these:
- fishing loot;
- a node (GameObject) containing a known herb or ore, or right after a gathering cast;
- a skinned creature: no coins, only skinning materials or right after a skinning cast, and only if you know Skinning.

Spell IDs are just hints. `/gp debug` prints unknown gathering spell IDs and saves them (in `GatherpediaDB.debugSpells`) so they can be reported.

## Saved data
- `GatherpediaDB` (account) keeps:
  - counts per item per zone, gathers per profession per zone, first-gathered dates and discoveries;
  - minimap and window position, and options;
  - `session`: This Session display settings and the floating box position.
- `GatherpediaCharDB` (character) keeps *Show all professions* and the order your professions were learned.

## Credits
Gatherpedia by Curs3d221. Farm routes were recorded in game by the author.

Beast, herb, ore and fishing pool spawn points for the map pins come from QuestieDB (Forever build) by the Questie team, https://github.com/Questie/Questie, licensed under the GNU GPL v3. They are redistributed in Data/SkinningMobs.lua and Data/NodeSpawns.lua under the same license.

## License
Gatherpedia is free software under the GNU General Public License, version 3 or later (see LICENSE). You may use, share and modify it; versions you share must stay under the GPL and keep the copyright notice. Gatherpedia bundles no third-party libraries.
