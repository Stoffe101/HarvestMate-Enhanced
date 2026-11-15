# Diagnostics

After an in-game test, type `/hme diag`. A window opens with a short report already selected: press Ctrl+C to copy it and paste it wherever you like. Nothing is sent anywhere. `/hme diag chat` prints the short form in chat instead. The window closes when a fight starts and does not open during one.

## What it contains

- HME version, client build, interface and locale
- Forever-GPS version and API level, navigation mode, whether terrain walks and the arrow hold are available
- other known addons loaded (TomTom, GatherMate2, Auctionator, TSM, Questie, the replaced addons) with versions
- price sources
- character level, faction and gathering professions (no name)
- the map you are on, your position on it, and whether the zone size is known
- the route you follow: id, name, stops, length, quality label and terrain summary
- navigation: phase, travel owner, who owns the arrow, presentation, Guide me here and whether Forever-GPS's arrow is held; the Forever-GPS request token and state; the journey Forever-GPS follows now
- recording, expedition and session status
- the last loot decisions (creature IDs only): skins, loot, fishing, unattributed loot, kill-time samples and unclear fights
- the last 10 errors HME caught
- data problems, repaired saved entries, saved data counts, missing client events
- timings of the expensive parts (searches, route builds, terrain walks)

## What it never contains

Character, realm or account names (scrubbed even from error texts), GUIDs (replaced by `<guid>`), chat, other players, or anything from other addons' saved data.

## Code

`Core/Diagnostics.lua`: `D.Lines()`, `D.Text()`, `D.Show()`, `D.NoteError(err)` (every error HME's `HME.Try` catches, newest 10).
