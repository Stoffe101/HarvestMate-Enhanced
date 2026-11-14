# In-game checklist (WoW Forever 1.60.1)

Nothing below has been done yet. Tick items as they are confirmed in the real client; note the client build and any error from `/hme diag` or BugSack.

## Load
1. [ ] Only HarvestMate Enhanced enabled: it loads with no Lua error; `/hme diag` says "data ok" and lists no missing events (or note which).
2. [ ] The minimap leaf button and the addon compartment entry open the window.
3. [ ] With HarvestMate, Gatherpedia and GatherPath also enabled: the chat note names them; their features run once (one banner, one Glimmer, one set of lines); Dashboard's **Import and turn off** then `/reload` leaves only HME, with their routes, counts and learned data present.

## Window
4. [ ] Every tab opens; nothing overlaps or runs past the edges at UI scale 1.0 and at the largest UI scale; at 1280×800.
5. [ ] Compact layout (Settings) shows icons only; window scale slider works; the window keeps its place.
6. [ ] Escape closes the window; it never takes keyboard input (typing in chat works with it open).

## Farm Finder
7. [ ] Skinning / Fastest leveling for your character: plausible zones, beasts you can skin, sensible numbers; details text fits.
8. [ ] Best gold with Auctionator or Forever-GPS prices present: source and age shown.
9. [ ] Material "Goldthorn": only zones that have it.
10. [ ] Preview on map: the map opens on the zone, pins sit on the right spots (compare with GatherMate2 if installed), hunting areas shaded, pins keep size when zooming.
11. [ ] Start farming route: a loop appears on the world map and minimap; arrow points along it; stops advance within ~30 yards.

## Navigation
12. [ ] With Forever-GPS: Navigate opens its journey panel on the farm; after Go and arrival, HME's arrow takes over; never two arrows.
13. [ ] Without Forever-GPS: HME's arrow points toward the farm across zones on the same continent.
14. [ ] `/reload` while following a farm: the arrow comes back.

## Gathering helpers
15. [ ] First login: the Soft Target popup explains and changes nothing until accepted.
16. [ ] Turning on one-key gathering shows the consent text naming what your key does now; after yes, the key gathers at a node and does its normal job elsewhere; entering combat at a node releases it (no "action blocked" message).
17. [ ] Nearby banner and tooltips show skill, requirement and drops.
18. [ ] Glimmer on: sparkles on soft-targeted herbs/ore; off restores your soft-target settings.

## Learning
19. [ ] Gathering a node: session starts; HUD shows counts; the node appears as confirmed in a preview.
20. [ ] Skinning a beast: skin counted; after a few, the beast's yield shows "measured".
21. [ ] Ending a session adds it to Profits & Stats with predicted vs actual.

## Routes pages (GatherPath)
22. [ ] New route from nodes, edit, rebuild, delete, colors, widths, arrows, range circle, avoid area drawing (click to add corners, Finish), skip list.

## Safety
23. [ ] No `ADDON_ACTION_BLOCKED` / `ADDON_ACTION_FORBIDDEN` during any of the above, especially in combat.
24. [ ] Minimap tooltips: HME does not try to read them.
