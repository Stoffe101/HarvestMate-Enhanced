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

## 0.3.0 additions
Install Forever-GPS from the branch `feature/public-api` for 37-44 and 54-56 (README, Install). Before starting: `/hme diag` should say `(API v2)`, `walking grid API yes` and `arrow hold yes`. After each session, copy `/hme diag` and BugSack's errors into your notes.

37. [ ] Two arrows (scenario G): Forever-GPS takes you somewhere; walk to an HME farm; HME waits. Guide me here: Forever-GPS's arrow disappears, its HUD steps stay, the journey keeps running; HME's arrow leads. Give arrow back, stop farming, or start a new journey in Forever-GPS: its arrow comes back. Never two arrows.
38. [ ] The same with Forever-GPS 2.7 (released): Guide me here guides on the map/HUD only; no second arrow.
39. [ ] During a farm, send Forever-GPS to a trainer: HME's arrow steps aside; when that journey ends, HME's arrow resumes.
40. [ ] Terrain: plan a Mining loop in a hilly zone (Redridge, Arathi): within a minute the map lines bend round hills; Routes page says terrain-aware or partly; no stutter while it walks the legs (watch FPS).
41. [ ] The arrow follows the bends of a walked leg, then the stop.
42. [ ] Bags nearly full: the suggestion's Do it opens Forever-GPS's journey to the nearest vendor; you press Go; HME's loop resumes after.
43. [ ] `/hme recipe 1` with an item link of a leather recipe's product: a shopping list appears on the Goals page.
44. [ ] Expedition: a shopping list with two professions; Expedition plans stages; Go starts stage 1 (Forever-GPS journey); gathering counts; "stage 1 done" says what is next.
45. [ ] Record My Route: record a short loop (Routes page), stand still for a minute (nothing written), stop: a recorded route on the map; follow it; Waypoints edit works; export and import it.
46. [ ] Caves: stand at a cave mouth, Shift+right-click a node inside on the map: "cave marked"; a planned loop's leg into it goes through the mouth.
47. [ ] Skinning: skin a beast, then loot a second corpse right away: one skin, one loot (`/hme diag` shows the decisions).
48. [ ] HUD detailed while skinning: material and expected rate; after 10 minutes, the observed vs predicted line.
49. [ ] Heatmap views (Settings): each labelled "not live nodes".
50. [ ] `/hme diag` opens a selectable report with no character or realm name; it closes when combat starts.
51. [ ] `/hme setup` lists what was found; one-key gathering and soft target buttons only open their consent popups.
52. [ ] After upgrading from 0.2.0: routes, goals, profiles and measured areas are all there; old wrong-beast marks appear in `/hme corrections`.

### Added after the first 0.3.0 push
53. [ ] Farm Finder, Skinning, goal "A material", type `Medium Leather`, search, press **Best beasts** (top right of Details): one row per beast with its levels, the Skinning it needs (and for its highest level), yield per skin with "estimate" or "N seen in M skins", an hour's worth, a confidence badge and the best hunting area. Hover: the other areas. Click: that area opens in Details and is selected in the list. **Back** returns. Two materials (`Medium Leather, Medium Hide`): each row names its material.
54. [ ] Terrain with a long loop: plan a loop of about 100 stops (Mining, a large hilly zone). Watch the frame rate for the half minute to few minutes the legs are walked: no visible hitch when the route is built, at most a small steady dip while walking. Fight something meanwhile: walking stops for the fight and carries on after (the Routes page count keeps going up).
55. [ ] Rebuild or delete that route while its legs are being walked: no errors; a rebuilt route keeps its new stops (the reorder pass never puts back an old order).
56. [ ] Item names: a shopping list or `/hme recipe` with an item HME's field guide does not know shows its real name, not "item 12345" (the client has C_Item.GetItemInfo and no global GetItemInfo).
