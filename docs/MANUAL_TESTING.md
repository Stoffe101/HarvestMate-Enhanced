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
57. [ ] Skinning levels: `/hme sl` (or Settings, Map and guidance, "Skinning levels"). The box shows your Skinning, the levels to kill (orange: a point every skin; yellow: most), the grey levels, the next level you can skin and how far away, this zone's beasts in those levels or the closest zones that have them, and your target's level and colour. Skin until a point: the box changes at once; when a new level unlocks, chat says "you can now skin level N beasts". Target beasts of different levels. Drag it; right-click hides it; it stays where you put it after /reload.

### The look (0.3.0 redesign)
58. [ ] The window opens in the new look: Inter text, dark charcoal panels with rounded corners, a slim header with an × button, a quiet sidebar with a green bar on the selected tab, and which addons are used on the status line. If the text shows as boxes or is missing, set Settings, General, "Interface font" to "Game font", /reload, and tell me. If corners look stretched or blotchy, set "Corners" to "Square" and tell me.
59. [ ] Dashboard: the green "Next step" card names one thing to do, and its button does it. The profession cards show skill, cap and the next milestone.
60. [ ] Farm Finder: the details show three tiles (skill-ups or materials an hour, gold an hour, travel) above the detail text. A long summary does not overlap them. "Start farming" is the green button.
61. [ ] Skinning levels opens from the green **Levels** button on the Dashboard's Skinning card, the **Skinning levels** button in Leveling Guides (Skinning), Shift-click on the minimap button, the key binding (Key Bindings, AddOns, "Show or hide Skinning levels"), or `/hme sl`; its x closes it. MAX LEVEL is the highest level you can skin and goes up as you skin.
62. [ ] (0.3.0) HUD during a session: three large numbers (gold, skill-ups an hour, time farmed). Skinning levels box (`/hme sl`): the kill range is large in its skill-up colour, the level strip runs from grey to red, and the next unlock has a small bar. Both stay readable over bright ground, at your UI scale.

### 0.4.0: the field-atlas look and the fixes from the first real-client screenshots
63. [ ] **Skins are counted.** Start a session (Farm Finder, Start farming, or just skin something). Skin five beasts. The Dashboard's farming panel and the HUD show 5 skins, and skill-ups as they come. `/hme diag` says "Skin detection: 5 skins counted (0 by the backstop), HarvestMate saw 5 skinning loots". If the backstop count is above 0, send me the diag: it means the cast was not recognised by its name.
64. [ ] **No quiet zeros.** Fight for ten minutes without skinning: the Dashboard and the HUD say "No skins recognised in ... of farming" in orange, instead of plain zeros.
65. [ ] **Money is short text.** Farm Finder, goal "Best gold per hour": the first tile and each row read like "3g 13s" (no coin icons), and nothing ends in "...".
66. [ ] **Nothing is cut.** Walk every page at your usual UI scale: no label, button or number ends in "..." (a long creature list ends in "+N" instead, by design). Try once at the largest UI scale: the window shrinks to fit the screen and keeps its shape.
67. [ ] **Dashboard while not farming**: the next-step card at the top; one large Skinning card with bar, training tick (Artisan at 200) and the next milestone; one line "Not learned: Herbalism, Mining, Fishing" with Where to train; Goals and Last session underneath.
68. [ ] **Dashboard while farming**: the green farming panel shows active time "of N since it began", skins, skill-ups and gold an hour; Pause turns into Resume; Stop farming ends the route and the session.
69. [ ] **Farm Finder rows** lead with one number in colour (skill-ups/h, gold/h or materials/h), four diamonds for how sure, risk and travel. **Filters** opens a panel with risk, play time, region, confidence, Save search and Plan ahead; the button counts what is set.
70. [ ] **Farm Finder details**: three tiles with ranges, "Estimate: not measured yet · ... confidence" under them, tabs Overview / Find / Risk / Evidence, and one green Start farming. In Overview, Skinning farms say what a real session gets and, apart, what a perfect circuit would reach.
71. [ ] **Are the numbers believable?** For your character the top Skinning farms should show roughly 60-110 skill-ups an hour, not 150+. After two sessions on one farm, its row says "measured" and its numbers are yours.
72. [ ] **HUD sizes**: the chevron in the HUD's title cycles compact, normal and detailed; the first open goal shows with a bar in every size. The HUD and the Skinning levels box open side by side, not on top of each other (if you moved them before, they stay where you put them).
73. [ ] **Skinning target**: target a beast you have skinned: "skinnable: you skinned it". A beast not in the list (e.g. a non-beast humanoid): "not in the beast list: may give no skin". A beast five levels above you: "too strong for you"; an elite: "elite: bring help".
74. [ ] **Goals**: add several materials: one calm row each (icon, name, bags and gathered, count and bar, Best farm, x).
75. [ ] **Leveling Guides** open on Skinning; the bar under the ranges is filled to your skill with a white diamond where you are and brass ticks at 50, 125 and 200.
76. [ ] **Look**: header with faint contour lines and a brass rule, "HarvestMate" white and "Enhanced" in brass, medallions round profession icons. Readable over a bright zone. If text shows as boxes: Settings, General, Interface font: Game font, and tell me.

### 0.5.0
77. [ ] **The HUD title stays inside.** Follow a farm from the Farm Finder (Start farming) and do not gather yet. The HUD shows "Hillsbrad Foothills" (or your zone) on one line and "Skinning leveling · stop 1/12" under it, both inside the panel, in compact, normal and detailed (the chevron in the HUD's title). Hover the HUD: the full route name. Screenshot it for me either way.
78. [ ] `/hme hud reset` puts the HUD back at the top right; dragging it, then /reload, keeps it where you put it.
79. [ ] **Skins, case by case.** Skin five beasts: five. Start a skin and move to interrupt it, then loot a corpse: no skin. Pause the session (right-click the HUD), skin one: the session does not count it. `/hme diag` "Skin detection" shows the counts, including failed casts and uncertain skins.
80. [ ] **Skinning levels compact.** The chevron beside its × switches to compact (no strip, no zone list); target a beast in both modes.
81. [ ] **Route Inspector.** Routes, Inspect on a route: length, a lap, how much follows the terrain, legs to check, your sessions, the stop nearest you. Escape closes it; so does closing the window.
82. [ ] **New route without GatherMate2** never asks you to install it; it lists herbs and ores from HME's own data.
83. [ ] **Routes rows** fit the page: Edit, Rebuild, Delete, Waypoints, Follow and Inspect all inside the row.
84. [ ] **Farm Finder alternatives.** Pick a farm with Moderate or higher risk: Overview names a lower-risk farm with its share of the skill-ups; a far farm names a closer one.
85. [ ] **Materials** opens on Skinning with a material selected; the tiles show skill needed and your colour, a price and what you gathered.
86. [ ] **Profits & Stats**: the three totals and the trend bars match your sessions; hover the bars.
87. [ ] `/hme diag` has an **Interface** line; "font Inter" means the bundled font loaded.
88. [ ] Everything at the largest UI scale and at your usual one: nothing outside its panel, nothing cut.

### 0.6.0
89. [ ] **Copilot, first look.** Open HME: the Dashboard's top card says "Copilot suggests" with a farm, a number and its distance. Why? opens the Copilot page: reasons, a range, confidence, "Rests on". Screenshot the page for me.
90. [ ] **Modes and time.** On the Copilot page try 15 min, 30 min and No limit, and the modes. A short time prefers a closer farm and says why; Lower risk says what it costs; Explore says it is a guess.
91. [ ] **Start farming from the Copilot**: the route is planned and Forever-GPS (or the arrow) takes you there, as from the Farm Finder.
92. [ ] **Not now** replaces the farm with the next one; **Not interested** removes farm cards; Settings, Copilot and notifications, brings them back.
93. [ ] **At the cap**: with Skinning at its cap the first card is "Train ..." with Go to trainer.
94. [ ] **Ledger.** After two sessions of 10+ minutes on farms started from HME, the Copilot page's right card shows predicted against what you got, and a "estimates run ...% high/low" line.
95. [ ] **Skinning Explorer**: search "medium leather", "hillsbrad" and "35"; pick a creature you skinned: the journal counts match /hme diag; corpse loot is apart. Hunt it plans a circuit for that creature.
96. [ ] **Quests**: with a kill quest for a skinnable beast in your log, the Farm Finder row says "quest" and the Copilot names the quest. With Questie and without.
97. [ ] **Timed loop**: Route Inspector, Make a loop of 15 min: a new route "... · 15 min" appears; the original is unchanged. Ride it once: the lap time is written down.
98. [ ] **Laps**: follow a route for two laps; the Inspector shows lap times. A stop that never gave anything after 4 laps is listed as weak.
99. [ ] **The bell**: notices collect there; the count turns gold; opening it clears the count. Training and goals also say themselves in chat, farming hints do not (by default).
100. [ ] **Session review**: Stop farming after 10+ minutes: the review opens with time, counts, skill-ups, value as an estimate, against the prediction. An idle ending only adds it to the bell.
101. [ ] **Search everything**: type "leather", "bloodwing", "artisan skin", a route's name; Enter opens the first.
102. [ ] **Materials** shows "Sell, process or keep" with the auction cut and deposit, and "Your characters" after logging in on a second character.
103. [ ] **Bags**: farm with few free slots: a "Bags full in about N minutes" card or notice, with Nearest vendor through Forever-GPS (you press Go).
104. [ ] `/hme diag` has Copilot, Prediction ledger, Quests and Notices lines; nothing in it names characters or places beyond zone ids.

### 0.7.0
105. [ ] **Editor: move and redo.** Routes, Waypoints on a route: shift-click a waypoint, then click elsewhere: it moves there. Undo, then Redo. Right-click while one is picked up keeps it where it was.
106. [ ] **Snap.** On a herb or ore route, click near a known node: the bar says "Snapped to ...". Snap: off on the bar stops it (and stays off next time).
107. [ ] **Versions.** Change a route and press Done; Inspect it: "Versions 1 kept"; the Versions menu puts the old waypoints back after asking; Versions now lists the edited ones.
108. [ ] **Share.** Inspector, Share: the box says what it leaves out; Ctrl+C, then paste in Settings, Your data, Import on another character: the route arrives as "imported", without laps.
109. [ ] **Map layers.** Open the world map: an "HME layers" button at the top left of the map. Is it clear of other addons' buttons (Questie, Forever-GPS)? Turn on "Your deaths and enemy players seen": the legend appears; your deaths show as red pins.
110. [ ] **Players seen.** With enemy player nameplates on, ride where Horde players are: `/hme danger` counts them after a while; your party is not counted. Inside a dungeon nothing changes.
111. [ ] **Enemy in sight.** If you die with a Horde player nearby, the death pin's tooltip says "an enemy player was in sight just before".
112. [ ] **Risk and the Copilot.** After half an hour in a zone where you met 4+ enemies an hour, the Copilot shows "Enemies common here" with Lower-risk farms.
113. [ ] **Price trends.** With Auctionator or Forever-GPS prices, open Materials on three different days: the Trend line appears from the third day, saying listings, not sales.
114. [ ] **Ready?** Fill your bags to 2 free slots: the Copilot shows "Ready?" with Nearest vendor. `/hme ready` lists bags, repairs, rank cap, risk.
115. [ ] **Characters.** Log in on a second character, then back: Profits & Stats, Characters lists both with professions and "playing now" for yours.
116. [ ] **Session path.** Farm 10+ minutes, Stop farming: the review has Show the path; the map shows your path with "10 min" marks and a dot per skin.
117. [ ] **HUD Copilot line.** Settings, Copilot on the HUD: one "Copilot: ..." line on the HUD; off again: the HUD is as before (0.5.0's layout).
118. [ ] `/hme diag` has Danger map, Price history, Characters and Map layers lines with counts only.

### 0.7.1
119. [ ] **The corpse tooltip.** Kill and skin a beast with Soft Target Interact on: the tooltip over the corpse is short (name with your numbers, "N more to the next color") and in the bottom right corner, not the middle. Try Settings, Node and corpse tooltips: "Where the game puts it" and "Off".
120. [ ] **Start farming → Forever-GPS.** Start a farm from the Copilot or the Farm Finder: Forever-GPS starts the journey within a second or two (before: several seconds).
121. [ ] **Flights.** Settings, Take flights automatically, on. Start a farm in another zone with a flight on the way, walk to the flight master and talk to it: you take off, and only then HME says "flying to ...". If the game refuses, HME says so and a "Fly to ..." button appears on the flight map: press it, and tell me. (0.7.2: at a different flight master than Forever-GPS planned, HME picks its own flight instead.)
122. [ ] **Shift at the flight master**: nothing is taken; you choose.
123. [ ] **Stopped routes leave the map**: follow a farm, Stop farming, follow another: only the new one is drawn on the world map and minimap.
124. [ ] **The bell**: open the notifications, close them with ×, and with the bell again.
125. [ ] **Copilot after a skill-up**: with the Dashboard open, skin until your skill crosses a multiple of 5: within a few seconds the "Copilot suggests" card is from the new skill (Herbalism and Mining too, if you have them).
126. [ ] **The levels box** (`/hme sl`): the zone line with its beast levels, "Highest here:", and for a herbalist or miner "Herbs:" or "Ore:" with "next ... at N". Compact (the chevron): the zone in one line.
127. [ ] Everything at your UI scale: the levels box and the notifications list inside the screen, nothing cut.
