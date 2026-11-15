# Upstream sources

The original source of every project HME builds on is kept in `upstream/` (text files; binary media are listed by hash), so every change can be reviewed with a plain diff. `tests/test_static.lua` fails if a vendored file differs from its original by anything but the patches declared below.

## Baselines

| Project | Version | Obtained | Integrity |
|---|---|---|---|
| GatherPath Forever | 1.12.1 (commit `8f21853`; upstream `main` at `b1ff157` has only workflow changes since) | this repository's history, remote `upstream` = github.com/severd8/gatherpathforever | git |
| HarvestMate | 2.0.13 | official release ZIP `HarvestMate-2.0.13.zip` (no public repository found) | SHA-256 `d1d0902f8054eda5ae670f2c1a26193c5e2abd60b46242f97ec344485ed69d08` |
| Gatherpedia | 1.0.1 | official release ZIP `Gatherpedia-v1.0.1.zip` (no public repository found) | SHA-256 `e17d30ebb06df172d273c24d0aefea94bca63b3abb2056970608e8ece847e367` |
| Forever-GPS | 2.7.0 (`feature/forever-gps-v1`) | local checkout, reviewed only; nothing copied | — |

Newer versions: on 2026-11-14 web searches did not turn up newer CurseForge releases of HarvestMate or Gatherpedia than the supplied ZIPs, and GatherPath's upstream had no newer release. Re-check before each HME release.

## Declared patches to vendored files

Applied by `python tools/vendor_patch.py` (idempotent):

| Patch | Files | Change | Why |
|---|---|---|---|
| P1 | HarvestMate `Gather/*.lua`, `Gather/Locale/*.lua` | first line `local _, HG = ...` becomes `local _, ns = ... local HG = ns.HG` | share one private table; HarvestMate's namespace lives at `ns.HG` |
| P2 | Gatherpedia `Glimmer/Sparkles.lua`, `Glimmer/SparklesCloud.lua` | texture paths `AddOns\Gatherpedia\Media\X` become `AddOns\HarvestMateEnhanced\Media\GP_X` | the art ships in HME's folder |
| P3 | HarvestMate `Gather/Bind.lua` | key-capture frame name `HarvestMateKeyCapture` becomes `HarvestMateEnhancedKeyCapture` | no global clash when both are installed |

`Glimmer/SparklesCloud.lua` is lines 1-643 of Gatherpedia's `SparklesUI.lua` (the cloud renderer); the rest of that file was its settings page, replaced by HME's.

Unchanged: `Data/Gatherpedia/*.lua` (10 data files plus `Zones.lua`, `Trainers.lua`, `Guides.lua`), `Engine/Optimize.lua`.

## Adapted (not vendored) files

These started from upstream code and were changed; their headers list the changes.

| HME file | From | Main changes |
|---|---|---|
| `Routes/Routes.lua` | GatherPath `Core.lua` | nodes from HME's spawn layer (GatherMate2 optional); planned routes; settings in `HarvestMateEnhancedDB.routes`; own global/frame/template names; pause while GatherPath runs; no own minimap button or slash command except `/gpf` when GatherPath is absent |
| `Routes/RoutesUI.lua` | GatherPath `Options.lua` | pages hosted in HME's window; tab keys; wording |
| `Routes/Pin.xml` | GatherPath `Pin.xml` | template and mixin names |
| `UI/Theme.lua` | GatherPath `Theme.lua` | HME brand, wider window, lazy pages, sidebar headings, compact layout, scaling; redrawn in 0.3.0 as HME's own design system (docs/DESIGN.md), same functions |
| `Gather/HGCore.lua` | HarvestMate `Core.lua` | HME's event bus and saved data; safer defaults (see below); no own load handler or slash commands |
| `Core/GPCompat.lua` | Gatherpedia `Core.lua` helpers | profession scan replaced by HME's Player module |
| `tests/support/wow.lua`, `tests/test_gatherpath_routes.lua` | GatherPath tests | load the whole addon; portable random numbers; names; lines marked `HME:` |

## Behaviour changed on purpose

- HarvestMate defaults that touch controls or chat now start **off** and ask first: one-key gathering (override binding), temporary click-to-move and auto-loot, party/emote announcements. Its nameplate marker defers to Glimmer.
- HarvestMate's and Gatherpedia's own windows, minimap buttons and session boxes are replaced by HME's window, button, HUD and session engine (their data and functions are used).
- Gatherpedia's gather tracker is replaced by HME's learning and counting (same `counts` data).
- Gatherpedia's on-screen arrow logic is replaced by `Map/Arrow.lua` (its art and heading math are used) so that only one module owns navigation.

## Reviewing future upstream releases

1. `python tools/upstream_check.py harvestmate|gatherpedia|gatherpath <zip or checkout> -v` lists every changed file, how HME uses it (vendored / adapted / replaced / unused) and a diff excerpt. It changes nothing.
2. Vendored files: copy the new file, run `python tools/vendor_patch.py`, then `python tools/run_tests.py` (`test_static.lua` checks that only declared patches remain).
3. Adapted or replaced files: port the fix by hand where it applies, and note it here.
4. Update `upstream/<project>-<version>/` with the new snapshot and hash, and the baselines table above.

Checked on 2026-11-14: no newer HarvestMate or Gatherpedia release found; GatherPath upstream unchanged since 1.12.1.
