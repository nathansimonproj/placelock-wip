---
name: geofence-scenario
description: Drive the Spots/PlaceLock app through scripted location walks in the Simulator (arrive at a place, leave, move between places, background, relaunch) and check that apps unlock and lock when they should. Use after changing geofencing, lock rules, places, the 24 h delays or launch/relaunch code, when asked to test arriving or leaving, or to reproduce a location bug.
---

# Geofence scenarios

`PlaceLock/scripts/geofence-scenario.py` moves the Simulator's location with `simctl location`, runs the real app with real iOS geofences (`CLMonitor`), and checks the app's log for `Auto-unlock at …`, `Lock (was unlocked: true): …` and `Moved session …`. The scenarios live in `PlaceLock/scripts/scenarios/*.txt`, and `--help` lists the step language.

```sh
PlaceLock/scripts/geofence-scenario.py --all --build    # build the app, then run every scenario (~5 min)
PlaceLock/scripts/geofence-scenario.py arrive-leave     # one scenario, using the app already built
```

Use a 10-minute Bash timeout. `--build` runs `verify.sh --quick` first. Without it, the runner installs whatever is in `PlaceLock/build/free`, so build first if the app code changed.

## How it stays isolated

- **Its own Simulator.** It runs on a Simulator called "Spots Scenarios", created on first use. Don't run tests, `/verify` or Xcode on that device: anything else that launches the app there restarts it outside scenario mode, and the runner stops with "didn't start in scenario mode".
- **Scenario mode** (Debug, free build: `-scenario <name>`, see `PlaceLock/PlaceLock/App/Scenario.swift`). The app uses its own settings store loaded with the scenario's places, and backup is off, so nothing reaches Supabase. The runner checks for `Launch: N places, session=none` with the scenario's place count and stops if it doesn't see it.
- Scenario places are in Golden Gate Park, San Francisco, far from any real saved place. Keep new ones there.

## Writing a scenario

Add a `.txt` file to `PlaceLock/scripts/scenarios/`. Start with a comment saying what promise it checks. For example:

```
# A place still waiting out its 24 h must not unblock anything.
place NewSpot 37.7694 -122.4862 100 inactive
at NewSpot +400        # 400 m north of the edge
launch
at NewSpot
expect-no unlock NewSpot for 20
expect locked
```

Things the Simulator taught us (2026-11-22):
- **Leaving is reported some way past the edge.** 50 m past wasn't enough, and 300 m was right away. On a walk at 4 m/s, the lock came about 240 m past the edge. Step out with `+300` or more, or `walk`, and allow time.
- **Jumps reorder events.** Teleporting with `at` between overlapping places can deliver "left A" before "entered B". Use `walk` when the order matters.
- `at NAME +M` always goes north. When another place lies north, start from an explicit `at LAT LON` to the south.

## Reading results

Each check prints PASS/FAIL with timing. After a `walk`, it also says how far past the edge the event fired. The app's full log is in `PlaceLock/build/scenarios/<name>/app.log`, and screenshots taken with `screenshot NAME` are saved next to it. Open them with Read.

On a FAIL, read `app.log` before touching code. Every geofence event (`CLMonitoringState(rawValue: 1)` = inside, `2` = outside) and every lock decision is logged. Work out whether it's an app bug, a scenario mistake (wrong geometry, too little time) or Simulator behaviour, and say which. Don't loosen an `expect` just to get it passing.

## What it can't show

These need the iPhone; list them as on-device checks when a change touches them:
- iOS relaunching the app for an event after a force-quit. The Simulator doesn't do it (Roadmap, 2026-11-19), and a background relaunch wouldn't be in scenario mode anyway, so there's no `kill`-then-move scenario.
- Real exit timing and distance, indoor GPS drift and coarse fixes.
- The Screen Time block screen.
