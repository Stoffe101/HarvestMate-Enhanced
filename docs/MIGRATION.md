# Moving from HarvestMate, Gatherpedia or GatherPath Forever

1. Install HarvestMate Enhanced next to the old addon(s) and keep them enabled for **one** login. The game only loads an addon's saved data while it is enabled.
2. On that login HME copies what it can use (and says so in chat):
   - HarvestMate: learned requirements, drops, objects, skinnable beasts, achievements, records and display choices. One-key gathering and announcements are **not** switched on for you: HME asks again.
   - Gatherpedia: counts, discoveries, zone maps, Glimmer settings, skinnable beasts, per-character order.
   - GatherPath Forever: routes (marked "GatherPath"), avoid areas, skip list and display settings.
   The old addons' own saved data is never changed or deleted.
3. While the old addons run, HME pauses its copy of their features (no double banners, Glimmer or lines).
4. On the Dashboard press **Import and turn off**, then `/reload`. To go back, enable the old addon again: its data is as it was.

`/hme import` repeats the copy (it only adds what is missing; counts are never doubled). Commands `/hm`, `/gp` and `/gpf` work in HME while the old addons are not installed.
