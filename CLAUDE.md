# Spots (code name PlaceLock)

iPhone app (SwiftUI, iOS 17+) that keeps chosen apps blocked everywhere except saved places. [README.md](README.md) explains what it does and how to build it. [Roadmap.md](Roadmap.md) is the most up-to-date record of what's built, known issues and what's next. [Plan.md](Plan.md) is the original design and partly out of date.

## Don't break these

- **Names.** The app is called Spots, but the code, Xcode project, bundle IDs (`com.nsimon.PlaceLock`, `.Shield`) and the App Group (`group.com.nsimon.PlaceLock`) stay PlaceLock. Renaming any of them makes iOS treat it as a new app.
- **The project is generated.** XcodeGen writes `PlaceLock.xcodeproj`, `PlaceLock/Info.plist`, the entitlements files and `Extensions/Shield/Info.plist` from `project.yml` and `project-paid.yml`. Edit the specs, never the generated files.
- **Two builds.**
  - Free (`xcodegen generate`): blocking is simulated, and it runs on the free Personal Team.
  - Paid (`xcodegen generate --spec project-paid.yml`): adds the `SCREEN_TIME` flag, the Shield extension and the App Group.
  - Code under `#if SCREEN_TIME` (in `ShieldManager`, `RootView`'s picker and `SharedStore`) only compiles in the paid build, so check both.
  - **Commit the free project, not the paid one.** If `grep -q PlaceLockShield PlaceLock/PlaceLock.xcodeproj/project.pbxproj` matches, the paid project is the one generated right now. Don't stage the generated files then, unless the user asks.
- **Supabase SDK stays on 2.x** (`from: 2.55.6`). v3 renames APIs.

## Product rules (the tests enforce these; keep them true)

- Apps are blocked by default and unblock only inside a saved place. There's no unlock button.
- After the first 24 h, anything that loosens the rules waits 24 h: adding a place, moving or enlarging one, removing an app. Changes that only make things stricter apply at once.
- Losing Always or Precise Location access locks as soon as Spots runs: right away if it's open, otherwise the next time it's opened. iOS doesn't wake the app for a permission change, so apps stay unblocked until then (accepted for now, 2026-11-22; see Roadmap Known issues).
- Blocking decisions are made on the phone and never wait on the network. Sync is backup only.

## Code layout

- Decisions are pure functions with unit tests: `LockRules`, `PlaceRules`, `BlockRules` and `SyncRules`, under `PlaceLock/PlaceLock/Models` and `Sync`. `AppModel` only gathers their inputs and applies the results. Put new decision logic in a rules type and test it there, not in `AppModel` or views.
- Logging: `Log.app` and `Log.sync` (subsystem `com.nsimon.PlaceLock`).
- Debug launch arguments: `-tab rules`, `-sheet add`, `-onboardingStep <step>`, `-demoHistory YES`, `-preciseOff YES` and `-notificationsOff YES` (permissions `simctl privacy` can't set), and `-onboarded YES` to skip first-run setup. `-scenario <name>` starts scenario mode (`App/Scenario.swift`): a separate settings store and no backup, used by `/geofence-scenario`.

## Checking a change

Run `/verify` (or `PlaceLock/scripts/verify.sh`) before calling a change done. It runs the unit tests, compiles the paid build, runs the migration checks when `supabase/` changed, and with `--screens` takes Simulator screenshots. Afterwards it puts back whichever build was generated before.

- The tests use Swift Testing. Read the "Test run with N tests" line. "Executed 0 tests" from xcodebuild is normal.
- For geofencing, lock rules, places or launch changes, also run `/geofence-scenario` (`PlaceLock/scripts/geofence-scenario.py --all --build`). It walks the Simulator in and out of places and checks unlock and lock.
- The Simulator can't show: the real Screen Time block screen, iOS relaunching the app after a force-quit, or real geofence exit timing (100–200 m, a few minutes). When a change touches those, end with a short on-iPhone test list instead of saying it works.
- The Supabase MCP server points at the **live** project. Check migrations locally (`supabase/local-check/run.sh`) and ask before applying anything remotely.

## Docs and commits

- When behaviour changes, update Roadmap.md and, if users would notice, README.md. Date entries with absolute dates (e.g. "2026-11-22"). Strike through finished items rather than deleting them.
- Match the docs' style: plain, short sentences that describe what the user sees.
- Commit messages: one short sentence-case summary, no `feat:`-style prefix (e.g. "Allow places down to 50 m, with a warning below 100 m").
