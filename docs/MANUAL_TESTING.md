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

## 0.2.0 additions
25. [ ] Forever-GPS 2.7: Start farming on a far farm, press Go, arrive: one arrow throughout; HME's loop starts on arrival.
26. [ ] Change the destination in Forever-GPS mid-trip: HME says it stepped back; arriving elsewhere does not start the loop; stopping the farm in HME leaves that journey running.
27. [ ] Cancel the journey in Forever-GPS: HME's arrow does not appear by itself.
28. [ ] Walk to the farm while another journey runs: HME offers "Guide me here" and changes nothing else.
29. [ ] /reload mid-trip and mid-farm: state comes back; a journey that ended meanwhile is not claimed.
30. [ ] Travel 5+ minutes then farm 10: HUD (detailed) and the journal show travel and farming apart, with both gold/hour figures.
31. [ ] Kill single beasts, then a pack: only single fights become kill-time samples.
32. [ ] Goals page: a material goal counts bags; opening the bank adds the bank count.
33. [ ] Route editor: Waypoints, click to add/remove, Undo, Reverse, Done; Rebuild then asks first.
34. [ ] Map: crowded pins show counts zoomed out; right-click a pin to exclude it; heatmap and simple modes are readable; hunting areas outlined, not covered.
35. [ ] Farm Finder comparison and filters; Herbs + Ore loops (you switch tracking yourself; nothing switches it for you).
36. [ ] HUD compact / normal / detailed do not cover action bars at 1280x800.
