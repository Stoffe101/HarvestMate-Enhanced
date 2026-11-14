# Record My Route

Ride round a farm the way you like; HME writes your path down and saves it as a route.

## Use

- **Routes page → Record my route** (the button turns into **Stop & save**), or `/hme rec start [name]`.
- `/hme rec pause`, `/hme rec resume`, `/hme rec stop`, `/hme rec cancel`.
- The path being recorded is drawn on the world map and minimap in red.

## What is written down

- Your position once a second, only when you moved at least 6 yards; a point is kept at once on a turn of 25 degrees or more, otherwise every 40 yards. Standing still writes nothing.
- Time (paused time excluded) and distance.
- What you gather, skin or catch on the way, with the place ("seen here"). These are your observations along the path, not live nodes, and the path is not taken as proof that the ground around it is walkable.
- Leaving the zone pauses the recording; coming back resumes it. It survives `/reload`.

## Saving

- The path is pulled straight to within 4 yards (Douglas-Peucker), keeping the turns that matter, and to at most 300 points.
- An end within 60 yards of the start makes a loop; otherwise it is a there-and-back route, followed out and back and drawn along the way out.
- Saved as a recorded route (`recordedBy = "you"`): never rebuilt, never reordered, never walked on the grid (it already is the way you rode).

## Editing

- The route editor (Routes → Waypoints) adds and removes waypoints, reverses and undoes; `HME.Recorder.Trim(route, first, last)` cuts a start or an end.
- Export and import carry the points and the gathers seen; someone else's recording is labelled imported.

## Recordings help generated routes

A planned loop whose leg starts and ends near your recorded path (25 yards) follows the recording for that leg ("corridor"), ahead of Forever-GPS's grid. Deleting the recording removes the corridor.

## Bounds

At most 3000 raw points while recording (about an hour of riding; the recording then stops and saves), 300 saved points, 300 gathers per route.
