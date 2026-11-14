# Third-party material

HarvestMate Enhanced (HME) is distributed under the **GNU GPL version 3 or later** (see `LICENSE`). It contains the following work by others. All original copyright notices are kept; the license texts ship in `HarvestMateEnhanced/Licenses/`.

| Component | Author | License | Where in HME | How it is used |
|---|---|---|---|---|
| GatherPath Forever 1.12.1 | severd8 | MIT | `Engine/Optimize.lua` (unchanged), `Routes/Routes.lua`, `Routes/RoutesUI.lua`, `Routes/Pin.xml`, `UI/Theme.lua` (adapted), `tests/support/wow.lua`, `tests/test_gatherpath_routes.lua` (adapted) | Route solver, routes, map lines, avoid areas, theme, tests |
| HarvestMate 2.0.13 | AndreiBerkut | MIT | `Gather/*.lua` (16 modules and 10 locales, one-line namespace patch), `Gather/HGCore.lua` (adapted from `Core.lua`) | One-key gathering, banner, tooltips, learning, achievements, reminders |
| HarvestMate locale names | via GatherSkillTooltip (as HarvestMate credits) | MIT | `Gather/Locale/*.lua` | Herb and ore names in non-English clients |
| Gatherpedia 1.0.1 | Curs3d221 | GPL-3.0-or-later | `Data/Gatherpedia/*.lua` (unchanged), `Glimmer/Sparkles.lua` (texture paths), `Glimmer/SparklesCloud.lua` (renderer part of `SparklesUI.lua`), `Core/GPCompat.lua` (helpers from `Core.lua`), `Media/GP_*.tga` (art) | Field guide data, guides and recorded routes, trainers, zones, Glimmer, arrow art |
| QuestieDB (Forever build) spawn data | the Questie team | GPL-3.0 | `Data/Gatherpedia/NodeSpawns.lua`, `Data/Gatherpedia/SkinningMobs.lua` (as redistributed by Gatherpedia) | Herb, ore, pool and beast spawn points |

## What HME wrote itself

Everything else: `Core/` (except `GPCompat.lua`'s Gatherpedia helpers), `Engine/` (except `Optimize.lua`), `Map/`, `Integrations/`, `UI/` (except `Theme.lua`), `Data/Zones.lua`, `Data/Leather.lua`, `Data/Index.lua`, the logo (`Media/Logo.tga`, drawn by `tools/make_art.py`), the tools and the tests beyond GatherPath's.

## Data and facts, not copied works

- `Data/Zones.lua`: zone sizes, typical level ranges, neighbouring zones, boat routes and guarded towns are general game facts written as approximate fallbacks; in game, the client's own values (C_Map) are preferred.
- `Data/Leather.lua`: deliberately plain assumptions, labelled as estimates everywhere they are shown, replaced by your own observations.
- No commercial guide, proprietary art or scraped database is included.

## Not included

- GatherMate2 and GatherMate2 Data: only called at run time when installed (their functions and messages), never copied.
- Forever-GPS: only called through its public table at run time (see `docs/FOREVERGPS_BRIDGE.md`), never copied.
- Auctionator, TradeSkillMaster, TomTom, Questie: only read through their published APIs when installed.
- Gatherpedia's optional fonts (Marcellus, Alegreya Sans): not bundled.
