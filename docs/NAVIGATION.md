# Navigation ownership

HME separates two things that 0.2.0 still mixed up: **the journey** (where someone is taking you) and **the arrow** (what points on screen).

## Journeys: request tokens (since 0.2.0)

Every time HME asks Forever-GPS for a journey it keeps a request (`HarvestMateEnhancedCharDB.fgpsRequest`): a token, the destination, and a state.

| State | Meaning |
|---|---|
| pending | HME asked; nothing has started yet |
| active | a journey started whose destination matches the request (same map, within 80 yards) |
| arrived | that journey arrived; Forever-GPS's later clear is ignored |
| cancelled | it was cleared before arriving: you stopped it |
| superseded | a journey to somewhere else started: it is yours, not HME's |
| released | HME stopped its own journey (you walked in) |
| stale | after a reload nothing matching the request is running |

HME stops a journey only when it is `active` **and** its destination still matches. It never stops a journey you started.

## The arrow: one place decides (0.3.0)

`Map/Guidance.lua` `G.Present()` is the only code that decides who points. It runs on every change of phase, mode, your choice, and of what Forever-GPS is doing (events, plus a check once a second for older Forever-GPS versions).

| `present` | Who points |
|---|---|
| `hme` | HME's arrow (to the farm, or round the loop) |
| `external` | Forever-GPS (or TomTom) for a journey; HME waits |
| `map` | HME guides on the map and HUD only, because the other journey's arrow cannot be paused |
| `none` | free farming: the area stays highlighted, nothing points |

### Guide me here (scenario G)

You are at the farm and Forever-GPS is taking you somewhere else. HME waits (`external`) and offers **Guide me here** (Dashboard button, `/hme here`).

- With Forever-GPS API v2, HME asks it to **hold its arrow** (`ForeverGPS.API.HoldArrow`). Forever-GPS's HUD arrow, EasyFind's character arrow, the TomTom mirror and the beacon's edge arrow stand down. The journey itself keeps running, untouched, and the HUD keeps showing its steps. HME's arrow leads the loop.
- Without API v2 (Forever-GPS 2.7 as released) Forever-GPS's arrow cannot be paused, so HME does **not** show a second arrow: it guides on the map and HUD (`map`) and says how to get its arrow (stop that journey in Forever-GPS).

The hold ends, and Forever-GPS's arrow comes back as you set it, when:

- you press **Give arrow back** or `/hme giveback`,
- HME's guidance stops,
- the other journey ends (HME's arrow then simply takes over: there is nothing else to follow),
- you start a new journey in Forever-GPS (your newest choice leads; Forever-GPS drops every hold by itself).

Holds are not kept over `/reload` on Forever-GPS's side; HME asks again after a reload if you had chosen it.

### What 0.2.0 got wrong

0.2.0's "Guide me here" (`G.TakeOver`) set a flag and showed HME's arrow while Forever-GPS's arrow for the other journey stayed up: two arrows. Its chat hint also pointed at `/hme guide`, which opens the Guides page, and no "Guide me here" button existed. The regression tests are in `tests/test_navigation.lua` (Forever-GPS 2.7 behaviour) and `tests/test_fgps_api_live.lua` (Forever-GPS's real API v2 code).

## Trips that are not farms

- **Trainers, vendors, mailboxes**: `HME.FGPS.GoToService(kind)` asks Forever-GPS (API v2 `NavigateToService`) for the nearest one, passing over enemy ground, and opens the journey for you to start with Go. HME's loop steps aside and comes back after. HME has no vendor or mailbox data of its own and says so without Forever-GPS.
- **Expeditions**: each stage starts like the Farm Finder does (Forever-GPS to the farm, HME's loop there).

## Travel estimates

Forever-GPS's `EstimateSeconds` measures from where you stand. HME uses it only for trips that start there; legs between two other places (expedition stages) use HME's own estimate. (0.2.0 used it for any leg, which was wrong for other starting points.)
