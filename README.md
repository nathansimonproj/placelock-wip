# Spots

*Formerly PlaceLock. The app is called Spots; the code, Xcode project, bundle IDs (`com.nsimon.PlaceLock`) and App Group still say PlaceLock, because changing them would make iOS treat it as a new app.*

An iPhone app that keeps distracting apps blocked everywhere except the places you choose.

Pick the apps that distract you and the places where they're allowed, like the gym or home. The apps stay blocked by default. When you arrive at one of your places they unblock on their own, and when you leave they block again. There's no unlock button.

> **Work in progress.** Spots isn't on the App Store. The default build only *simulates* blocking. Real blocking uses Apple's Screen Time API, which needs a paid Apple Developer account. That code is written and compiles but hasn't run on a phone yet. See [Roadmap.md](Roadmap.md) for what works and what's next.

## How it works

- **Blocked by default.** Your chosen apps are blocked unless you're inside one of your saved places.
- **Automatic unlock and lock.** iOS watches each saved place (`CLMonitor` geofences, up to 20). It wakes the app when you arrive or leave, even if the app is closed. Leaving can take a few minutes and 100–200 m to register. Places can be 50–500 m across, and Add place warns below 100 m, where indoor location fuzz can miss you arriving.
- **No quick loopholes.** After the first 24 hours, a new place takes 24 h to start working, and so does moving or enlarging one. Removing an app from the block list also takes 24 h. Changes that only make things stricter apply right away.
- **Safety net.** iOS also wakes the app every time you move about 500 m, even after a force-quit, and the app re-reads iOS's state for every place. That catches an exit iOS noticed but didn't deliver; a late exit still waits for iOS. Losing Always or Precise Location access locks right away while Spots is running, and otherwise the next time it runs. If you turn location off while unlocked and never open Spots, apps stay unblocked (a known issue). There's no time limit: you stay unlocked until iOS reports you've left.
- **Block screen.** Opening a blocked app shows where the app last estimated you were and where the app opens: "Estimated @ Suzzallo Library · 2 min ago" and "Opens at Gym or Home."
- **Backup.** Places and unlock history sync to Supabase under an anonymous account, so a reinstall can restore them. Blocking decisions are made on the phone and never wait on the network.

## Requirements

- Xcode 26 and an iPhone or Simulator on iOS 17 or later
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`). The Xcode project is generated from `project.yml`.
- An Apple developer team. A free Personal Team runs the simulated build. Real blocking needs a paid team plus Apple's Family Controls entitlement.

## Build and run

```sh
cd PlaceLock
xcodegen generate          # free build: blocking is simulated
open PlaceLock.xcodeproj
```

Set your own team in `project.yml` (`DEVELOPMENT_TEAM`), then run the `PlaceLock` scheme.

In the free build, blocking is a stand-in: you pick from a list of app names, and opening a "blocked" app shows a mock block screen. Location, geofences, the 24 h delays and sync are all real.

**Real Screen Time blocking (paid team):**

```sh
cd PlaceLock
xcodegen generate --spec project-paid.yml   # adds SCREEN_TIME, entitlements, App Group, both extensions
```

Put your paid team ID in `project-paid.yml` first. Run plain `xcodegen generate` to switch back. The block screen only works on a real device.

**Debug launch arguments** (Debug builds):

| Argument | Effect |
| --- | --- |
| `-tab rules` | Open on the Spots tab |
| `-sheet add` | Open Add place |
| `-onboardingStep apps` | Open first-run setup on a step (`location`, `screenTime`, `apps`, `places`, `notifications`) |
| `-demoHistory YES` | Fill today with two sample visits, for screenshots |

Home also has a **Pretend I'm at…** card in Debug builds. It feeds fake inside and outside readings through the same logic the real geofences use.

## Tests

```sh
cd PlaceLock
xcodebuild -project PlaceLock.xcodeproj -scheme PlaceLock \
  -destination 'platform=iOS Simulator,name=iPhone 17' test
```

Or press ⌘U in Xcode. The tests use Swift Testing, so look for "Test run with N tests". xcodebuild's XCTest summary line always says "Executed 0 tests". They cover the lock rules, the 24 h delays, sync merging, the sync engine (against an in-memory fake server) and the block screen text.

The database migration has its own checks, run against a throwaway local Postgres (needs `postgresql@16` from Homebrew):

```sh
PlaceLock/supabase/local-check/run.sh
```

## Project layout

```
PlaceLock/
  project.yml              Free build (XcodeGen)
  project-paid.yml         Paid build: adds Screen Time, the App Group and the extensions
  PlaceLock/
    App/                   AppModel (state and the reconcile loop), app entry, storage, logging
    Models/                Place, Visit, and the decision rules as pure functions (Rules.swift)
    Location/              Permissions, geofences, place search, the block screen estimate
    Blocking/              The block list and ShieldManager (Screen Time, or simulated)
    Sync/                  Supabase backup: engine, merge rules, records, server calls
    Shared/                Code shared with the extensions: brand colors and text, SharedStore
    Views/                 SwiftUI screens: Home, Spots (`RulesView`), Add place, first-run setup, Backup, Debug
  Extensions/
    Shield/                The block screen shown over a blocked app
  PlaceLockTests/          Unit tests
  supabase/
    migrations/            Schema, row-level security, newest-edit-wins trigger, account deletion
    local-check/           Migration checks against a local Postgres
```

Decisions live in pure functions (`LockRules`, `PlaceRules`, `BlockRules`, `SyncRules`) with unit tests. `AppModel` only gathers their inputs and applies the results.

## Backup and privacy

- Your location stays on the phone. The server stores your saved places (with coordinates), your unlock history and your setup window, under an anonymous account.
- The Supabase URL and publishable key are in `project.yml` on purpose: publishable keys are meant to ship inside apps. Row-level security protects the data, so each account can only read and write its own rows.
- Remove `SupabaseURL` and `SupabaseKey` from `project.yml` to turn sync off.
- Spots › Backup › **Delete account** removes every row on the server. Places and blocking keep working on the phone.
- To name your location on the block screen, the app looks up its coordinates with Apple Maps (`CLGeocoder`).

## Docs

- [Roadmap.md](Roadmap.md): the ship plan, what's built, known issues and next steps. Most up to date.
- [Plan.md](Plan.md): the original design. Parts are out of date: it describes unlocking by tapping and scanning the room with the camera, but unlocking is now automatic and the camera check is on hold.
