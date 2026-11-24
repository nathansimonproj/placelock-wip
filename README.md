# Cove

*Formerly PlaceLock. The app is called Cove; the code, Xcode project, bundle IDs (`com.nsimon.PlaceLock`) and App Group still say PlaceLock, because changing them would make iOS treat it as a new app.*

An iPhone app that keeps distracting apps blocked everywhere except the places you choose.

Pick the apps that distract you and the places where they're allowed, like the gym or home. The apps stay blocked by default. When you arrive at one of your places they unblock on their own, and when you leave they block again. There's no unlock button.

> **Work in progress.** Cove isn't on the App Store. The default build only *simulates* blocking. Real blocking uses Apple's Screen Time API, which needs a paid Apple Developer account. That code is written and compiles but hasn't run on a phone yet. See [Roadmap.md](Roadmap.md) for what works and what's next.

## How it works

- **Blocked by default.** Your chosen apps are blocked unless you're inside one of your saved places.
- **Automatic unlock and lock.** iOS watches each saved place (`CLMonitor` geofences, up to 20). It wakes the app when you arrive or leave, even if the app is closed. Leaving can take a few minutes and 100–200 m to register. Places can be 50–500 m across, and Add place warns below 100 m, where indoor location fuzz can miss you arriving.
- **No quick loopholes.** After the first 24 hours, a new place takes 24 h to start working, and so does moving or enlarging one. Removing an app from the block list also takes 24 h. Changes that only make things stricter apply right away.
- **Safety net.** iOS also wakes the app every time you move about 500 m, even after a force-quit, and the app re-reads iOS's state for every place. That catches an exit iOS noticed but didn't deliver; a late exit still waits for iOS. Losing Always or Precise Location access locks right away while Cove is running, and otherwise the next time it runs. If you turn location off while unlocked and never open Cove, apps stay unblocked (a known issue). There's no time limit: you stay unlocked until iOS reports you've left.
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
xcodegen generate --spec project-paid.yml   # adds SCREEN_TIME, entitlements, App Group, the Shield extension
```

Put your paid team ID in `project-paid.yml` first. Run plain `xcodegen generate` to switch back. The block screen only works on a real device.

**Version and build number.** Both live in `project.yml` (`MARKETING_VERSION`, `CURRENT_PROJECT_VERSION`), and the app and the Shield extension both read them. Before each App Store Connect upload, raise the build number:

```sh
PlaceLock/scripts/bump-build.sh                    # 1.0.0 (1) -> 1.0.0 (2)
PlaceLock/scripts/bump-build.sh --version 1.1.0    # -> 1.1.0 (3)
```

It regenerates whichever project (free or paid) is open now.

**App Store build.** `archive.sh` generates the paid project, archives the Release build and exports a signed `.ipa` for App Store Connect into `PlaceLock/build/archive/`. Then it regenerates whichever project was open before. It never uploads; it prints the upload commands at the end. The archive is signed automatically with the paid team, so Xcode must be signed in to it (Xcode › Settings › Accounts). The export signs by hand: it needs an Apple Distribution certificate and two App Store profiles made in Certificates, Identifiers & Profiles with Family Controls (Distribution) added, "Cove App Store" and "Cove Shield App Store", because Xcode's automatic App Store profiles leave that entitlement out. The script checks both before exporting. Export settings are in `scripts/ExportOptions.plist`.

```sh
PlaceLock/scripts/archive.sh            # archive and export the .ipa
PlaceLock/scripts/archive.sh --check    # archive without signing and check what's inside; needs no account
```

`--check` makes sure the archive is an app archive with the Shield extension inside, that both have the version and build from `project.yml`, and that both declare the encryption exemption.

**Debug launch arguments** (Debug builds):

| Argument | Effect |
| --- | --- |
| `-tab rules` | Open on the Settings tab |
| `-sheet add` | Open Add place |
| `-tab rules -sheet wait` | Open the "How the 24-hour wait works" sheet |
| `-tab rules -push backup` | Open Backup, even when backup is off |
| `-tab rules -push debug` | Open Debug |
| `-tab rules -scrollTo about` | Scroll Cove down to About |
| `-pretendAt Library` | Start as if Debug's Pretend I'm at had picked the place with that name |
| `-onboardingStep apps` | Open first-run setup on a step (`location`, `screenTime`, `apps`, `places`, `notifications`) |
| `-demoHistory YES` | Fill today with two sample visits, for screenshots |
| `-preciseOff YES` | Read Precise Location as off, which `simctl privacy` can't set |
| `-notificationsOff YES` | Read notifications as turned off in Settings, which `simctl privacy` can't set |
| `-scenario <name>` | Scenario mode (free build only): its own settings store and no backup. `geofence-scenario.py` uses it |

Debug builds also have a **Debug** screen under Settings › General. Its **Pretend I'm at** list feeds fake inside and outside readings through the same logic the real geofences use, and **Skip 24 h wait** applies waiting changes at once. `-onboarded YES` is different: it sets the real saved setting.

None of this is in Release builds: the launch arguments, the Debug screen, sample visits and scenario mode (`-scenario`) are behind `#if DEBUG`, and the free build's stand-ins for Screen Time aren't compiled into the paid build. `scripts/verify.sh --release` checks the paid Release build for them.

## Tests

```sh
cd PlaceLock
xcodebuild -project PlaceLock.xcodeproj -scheme PlaceLock \
  -destination 'platform=iOS Simulator,name=iPhone 17' test
```

Or press ⌘U in Xcode. The tests use Swift Testing, so look for "Test run with N tests". xcodebuild's XCTest summary line always says "Executed 0 tests". They cover the lock rules, the 24 h delays, which places iOS watches, permissions, place search, loading damaged saved data, sync merging, the sync engine (against an in-memory fake server), the block screen text, the About links and what VoiceOver reads.

To check a change end to end, run `verify.sh`. It runs the unit tests, compiles the paid build, runs the migration checks when `supabase/` changed, and puts back whichever project was generated before. Logs and screenshots go to `PlaceLock/build/verify/`.

```sh
PlaceLock/scripts/verify.sh               # tests, paid build, migrations if changed
PlaceLock/scripts/verify.sh --release     # also the paid Release build, checked for Debug-only code
PlaceLock/scripts/verify.sh --screens     # also screenshots of the main screens in the Simulator
PlaceLock/scripts/verify.sh --large-text  # --screens, plus the largest accessibility text size
```

`geofence-scenario.py` walks the Simulator in and out of saved places and checks that apps unlock and lock. The walks are in `PlaceLock/scripts/scenarios/`, and the app runs in scenario mode, so your own places and the backup are left alone. It can't show real exit timing, a force-quit relaunch or the real block screen.

```sh
PlaceLock/scripts/geofence-scenario.py --all --build   # build the free app, then run every walk
PlaceLock/scripts/geofence-scenario.py arrive-leave    # one walk
```

The database migration has its own checks, run against a throwaway local Postgres (needs `postgresql@16` from Homebrew):

```sh
PlaceLock/supabase/local-check/run.sh
```

## Project layout

```
PlaceLock/
  project.yml              Free build (XcodeGen)
  project-paid.yml         Paid build: adds Screen Time, the App Group and the Shield extension
  PlaceLock/
    App/                   AppModel (state and the reconcile loop), app entry, storage, logging, scenario mode
    Models/                Place, Visit, saved data loading, and the decision rules as pure functions (Rules.swift and the *Rules files)
    Location/              Permissions, geofences, place search, the block screen estimate
    Blocking/              The block list and ShieldManager (Screen Time, or simulated)
    Sync/                  Supabase backup: engine, merge rules, records, server calls
    Shared/                Code shared with the Shield extension: brand colors and text, SharedStore
    Views/                 SwiftUI screens: Home, Settings (`RulesView`), Add place, first-run setup, Backup, Debug, the free build's stand-in block screen
  Extensions/
    Shield/                The block screen shown over a blocked app
  PlaceLockTests/          Unit tests
  scripts/                 verify.sh, geofence-scenario.py (walks in scenarios/), bump-build.sh, archive.sh, night.sh (overnight task runner)
  supabase/
    migrations/            Schema, row-level security, newest-edit-wins trigger, account deletion, 50 m minimum radius
    local-check/           Migration checks against a local Postgres
docs/
  app-store/               App Store listing, privacy answers, review notes, data inventory and the launch checklist
  privacy/                 The privacy policy as a static page
```

Decisions live in pure functions (`LockRules`, `PlaceRules`, `BlockRules`, `SyncRules` and the other `*Rules` types) with unit tests. `AppModel` only gathers their inputs and applies the results.

## Backup and privacy

- Your location stays on the phone. The server stores your saved places (with coordinates), your unlock history and your setup window, under an anonymous account.
- The Supabase URL and publishable key are in `project.yml` on purpose: publishable keys are meant to ship inside apps. Row-level security protects the data, so each account can only read and write its own rows.
- Remove `SupabaseURL` and `SupabaseKey` from `project.yml` to turn sync off.
- Settings › Backup › **Delete account** removes every row on the server. Places and blocking keep working on the phone.
- To name your location on the block screen, the app looks up its coordinates with Apple Maps (`CLGeocoder`).
- Settings › About shows the version and, once they're set in `Shared/Brand.swift`, links to the privacy policy and support.
- Logs never show place names, addresses, coordinates or search text: they're marked private. [docs/app-store/data-inventory.md](docs/app-store/data-inventory.md) lists everything that leaves the phone.

## Docs

- [Roadmap.md](Roadmap.md): the ship plan, what's built, known issues and next steps. Most up to date.
- [docs/app-store/launch-checklist.md](docs/app-store/launch-checklist.md): the steps before launch that only you can do (Apple account, App Store Connect, the iPhone).
- [Plan.md](Plan.md): the design as built (rewritten 2026-11-23): automatic unlock, the 24 h waits, the two builds, backup, and ideas for later, including the camera check that's on hold.
