# PlaceLock Roadmap

Last updated: 2026-11-12. The full design is in [Plan.md](Plan.md). This file tracks the ship plan, what's built, temporary workarounds, and what's next.

## Ship plan (written 2026-11-10)
The critical path is Apple, not code. Real blocking needs the paid account, and the App Store needs Apple to approve a separate Family Controls **distribution** entitlement, which can take days to weeks. Request it first and do everything else while waiting.

### Free-account plan (written 2026-11-12)
Until the paid account, these can't be done: real shields, Apple's app picker, the two extensions, the App Group, Sign in with Apple, push notifications, TestFlight, and filing the distribution request. Everything else can. Work in this order:

1. **Keep both builds compiling.** After any blocking change, run `xcodegen generate --spec project-paid.yml`, build with `CODE_SIGNING_ALLOWED=NO`, then run plain `xcodegen generate` to go back. Last checked 2026-11-12: paid build succeeds, free build passes all 63 tests.
2. **Test location on the iPhone (Phase 2).** This is the riskiest part, and it works fully on the free account.
   - Real walks, plus Xcode `.gpx` routes for repeatable tests.
   - With the app force-quit, after a restart, in Low Power Mode, and with location briefly off.
   - Battery use and radius sizes.
   - The `sessions` rows in Supabase (Backend).
   - The place-search spinner (Known issues).
3. **Shippable to strangers (Phase 3).**
   - Build the "Allow Screen Time access" setup step now, behind `#if SCREEN_TIME`.
   - Any new UI that shows blocked apps goes through one small view: names in the free build, `Label(token)` in the paid build. Real tokens have no names.
4. **Backend leftovers.**
   - "Delete account".
   - CAPTCHA or rate limits for anonymous sign-ins.
   - Tests for `SyncEngine`'s I/O with a mocked client.
   - Optional: restoring on a new phone by linking an email with a 6-digit Supabase code. It works on the free team, needs no universal links, and doesn't trigger Apple's rule that Google login also requires Sign in with Apple. Sign in with Apple can come later.
5. **Features that don't need Screen Time.**
   - Study Spots and Lock In, with GPS-only Verified rules while the scan is on hold.
   - `StatsStore` and streaks, unit-tested like `Rules.swift`.
   - The share card.
   - The MobileCLIP webcam check.
   - The social backend (friendships, row-level security, the "locked in now" board over Realtime). It works only while the app is open, since there's no push yet.
   - Skip the shield-tap counter. It's an extension.
6. **App Store prep (Phase 4), minus submitting.**
   - Privacy policy and privacy label.
   - Listing copy.
   - Review notes and the Always-location recording.
   - Draft screenshots in the Simulator. Redo the ones showing blocking later.

**When to pay:** once step 2 shows location unlocking is reliable. Don't wait for steps 3–6 to finish. Apple's distribution approval only starts after joining, and steps 3–6 (about 2 weeks) fill that wait.

### Phase 0: Start Apple's clocks (about an hour)
- [ ] Join the Apple Developer Program ($99/yr). Check whether UW covers it first.
- [ ] Request the Family Controls distribution entitlement for the app and every extension.
- [ ] Check that the name "PlaceLock" is available in App Store Connect.

### Phase 1: Real blocking (code done 2026-11-12, waiting on the paid team to test)
All of this is written and compiles in the paid build (`CODE_SIGNING_ALLOWED=NO`). None of it has run on a phone yet.
- [x] **Paid build switch.** `project-paid.yml` includes `project.yml` and adds the paid team, `SCREEN_TIME`, the entitlements, the App Group and both extensions. `xcodegen generate` still makes the free build. See "Switching to real blocking" below.
- [x] **App Group storage.** `Shared/SharedStore.swift` (compiled into the app and both extensions) and `App/Storage.swift`.
  - Paid builds save to `group.com.nsimon.PlaceLock`. The first paid launch copies everything from `UserDefaults.standard` into the group, and the old copy stays.
  - Free builds keep using `UserDefaults.standard`, since the free team has no App Group.
  - The app shares the active place names and the block selection for the extensions.
- [x] **Block screen** (`Extensions/Shield`): "Instagram is blocked" with "Unblocks at Gym, Soccer Field or Home."
- [x] **8 h safety cap** (`Extensions/SessionCap`, a Device Activity monitor).
  - Every unlock starts a one-off schedule ending 8 h 5 min later. Locking stops it, and moving to another place or passing the 8 h recheck restarts it.
  - If it runs out, the app never got to recheck. The extension blocks the apps again and sends "Open PlaceLock if you're still there". Opening the app runs the overdue recheck.
  - The app now also wakes itself for the 8 h recheck while it's running, so the extension is only a backstop.
- [x] **Screen Time access turned off.** Checked on every reconcile.
  - When access goes from approved to off: a notification, plus a "Blocking is off" card on Home with "Turn Screen Time access back on".
  - "Add or remove apps" is disabled until access is back.
- [ ] Test real blocking on the iPhone. Check:
  - the block screen text
  - that the cap fires (temporarily set `LockRules.maxSession` to 15 min, the shortest Device Activity schedule)
  - that turning off access in Settings › Screen Time shows the warning
  - that existing places survive the switch to the paid build

### Phase 2: Make it trustworthy (about 1 week, mostly daily use)
- [x] 24 h delay on removing blocked apps (2026-11-11).
- [x] Unit tests: 41 tests in `PlaceLockTests/` for `LockRules`, `PlaceRules` and `BlockRules` (2026-11-11). Run with ⌘U or `xcodebuild test`.
- [ ] A few days of real use: arrival and departure timing, after a restart, battery, radius sizes.
- [ ] Fix the place-search spinner (Known issues).

### Phase 3: Make it shippable to strangers (about 3–4 days)
- [ ] **Starter places.** Release builds must not seed your apartment (The M) or the IMA. Ship empty "Set location" slots (Home, Gym, Library), and keep your real places for your own builds only.
- [ ] First-run setup in about 3 screens: why location, pick apps, set places. Ask for notifications in context, not at launch.
- [ ] App icon, final tab name for "Rules", notification wording to match ("Left Gym, apps blocked"), dark mode and large text checks.
- [ ] Rewrite Plan.md to match the automatic-unlock design. It still describes tap-and-scan.

### Backend: Supabase sync (started 2026-11-11)
Design is in Plan.md under "Backend". In short: the phone decides blocking, the server keeps records, and an outbox syncs them with newest edit wins.
- [x] Schema, row-level security, newest-edit-wins trigger, tombstones and account deletion: `PlaceLock/supabase/migrations/20261111000000_init.sql`.
- [x] Local checks pass (`PlaceLock/supabase/local-check/run.sh`, against a throwaway Postgres 16). They cover:
  - users can't see each other's rows
  - an older edit doesn't overwrite a newer one
  - hard deletes are blocked
  - the constraints
  - logged-out access is denied
  - account deletion cascades to every row
- [x] Supabase project `bdbyvdfugetapjysoiml` created, migration applied, anonymous sign-ins on (2026-11-11).
- [ ] Turn on CAPTCHA or rate limits for anonymous sign-ins before TestFlight.
- [x] **Phone side (2026-11-11).** `PlaceLock/Sync/`, using supabase-swift 2.55.6, pinned to 2.x.
  - `SyncEngine` signs in anonymously on first launch. Each pass pulls places, merges them, syncs the setup-window end (earliest wins), then flushes the outbox.
  - Passes run on launch, on foreground, when the network returns, and after any local change. Failures retry with backoff, from 5 s up to 5 min.
  - **Recorded history:** every unlock writes a `sessions` row, closed with a reason (`left`, `moved`, `lock_until_leave`, `place_deleted`, `lost_always`, `recheck_failed`). An 8 h recheck stays the same visit.
  - **First sync:** uploads existing places. After a reinstall, the server's places replace re-seeded starter places that have the same name.
  - **Status:** Rules has a "Backup" section showing it.
  - **When it's off:** with no URL or key in Info.plist, or under unit tests, sync does nothing.
  - **Tested:** 22 tests in `SyncRulesTests` (63 total, all passing). On the Simulator against the live project, the first sync uploaded the 3 starter places. Session upserts were checked against the live server with a temporary account, which was then deleted.
- [ ] Test an unlock → leave cycle on the iPhone and confirm the `sessions` row in the Supabase table editor.
- [ ] "Delete account" in settings, which calls `delete_my_account()`.
- [ ] Paid team: link Sign in with Apple so places restore on a new phone.

### Phase 4: TestFlight, then the App Store (about 1–2 weeks of calendar time)
- [ ] TestFlight with a few friends walking around campus.
- [ ] App Store Connect listing:
  - Screenshots, description, Productivity category, support URL.
  - Privacy policy URL.
  - Privacy label: **no longer "Data Not Collected"** once sync ships. Declare as linked to the user and not used for tracking:
    - Precise location: saved places.
    - User ID: the account.
    - Usage history: sessions.

    Update the privacy policy to match.
  - Encryption question: none (`ITSAppUsesNonExemptEncryption = NO`).
- [ ] Review notes:
  - Explain why the app needs "Always" location, with a short screen recording.
  - Explain that a place added in the first 24 h (the setup window) works right away, so the reviewer can test where they are.
- [ ] Submit once the distribution entitlement is approved.

| Week | Goal |
| --- | --- |
| 1 | Paid account and entitlement request filed. Real blocking working on the phone. |
| 2 | Delay on removing apps, tests, first-run setup, icon. Daily use. |
| 3 | TestFlight with friends. Fixes. |
| 4+ | Submit once Apple approves the entitlement. |

## Temporary: blocking is simulated until the paid developer account

**Why.** Real Screen Time blocking (`FamilyControls` + `ManagedSettings`, the same thing Opal uses for its "pick apps from a list" picker) needs the Family Controls entitlement. Apple doesn't give it to free accounts. Signing with the free Personal Team (R6W24T35J6) fails with:

> Personal development teams, including "Nathanael Simon", do not support the Family Controls (Development) capability.

The fix is the paid Apple Developer Program ($99/yr). UW may cover it through Apple's university program.

**Plan.** We're building as if we'll get the paid account. The real Screen Time code is already written. It's switched off by a build flag, and a stand-in takes its place:

| | Free team (now) | Paid team (`SCREEN_TIME` flag) |
| --- | --- | --- |
| App picker | Stand-in list of common apps (`SimulatedAppPicker`) | Apple's `FamilyActivityPicker` |
| Blocking | Logs "[simulated] would block: …" and shows "Would block: …" in the app | Real shields through `ManagedSettingsStore` |
| Opening a blocked app | "Try opening a blocked app" shows a mock block screen (`MockShieldView`) | The system block screen |
| Screen Time permission | Skipped | "Allow Screen Time access" setup step |

Everything else is real in both versions: places, GPS unlock, lock on leaving, the 8 h cap and notifications.

All the switching happens in `PlaceLock/PlaceLock/Blocking/ShieldManager.swift` (`#if SCREEN_TIME`) and the picker modifier in `Views/RootView.swift`. Storage switches in `Shared/SharedStore.swift`.

### Switching to real blocking (once on the paid program)
1. In `PlaceLock/project-paid.yml`, replace `PAID_TEAM_ID` with the paid team ID (developer.apple.com › Membership details).
2. Run `xcodegen generate --spec project-paid.yml` in `PlaceLock/`, then build to the iPhone. Automatic signing registers the App Group and the two extension bundle IDs (`com.nsimon.PlaceLock.Shield`, `com.nsimon.PlaceLock.SessionCap`).
3. On the phone: Home › "Allow Screen Time access", then pick apps in Rules.
4. To go back to the free build, run plain `xcodegen generate`. Commit the free project, not the paid one, until the paid team is the default.
5. Delete the "Test mode" stand-ins if you like: `SimulatedBlockingViews.swift` and `SimulatedApps`. They're unused in the paid version.
6. Before any App Store release, file Apple's separate Family Controls **distribution** request for the app **and both extensions**.

Both versions compile today. The paid version was checked with `xcodebuild -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO`.

### Ruled out: blocking through Shortcuts automations
Tried and dropped. It needed a Shortcuts "App Is Opened" automation for each app, which was too much setup friction. The blocked app could also flash before PlaceLock appeared, and turning off the automation got around the block.

## Free account limits (while on the Personal Team)
- **Weekly reinstall.** Apps installed this way stop opening after 7 days. Reinstall from Xcode about once a week. Saved places and settings survive the reinstall.
- **First install needs internet.** The phone has to be online to trust the developer profile (Settings › General › VPN & Device Management).

## MVP (built)
- [x] Choose apps to block (stand-in list for now).
- [x] Save allowed places: search by name with Apple Maps suggestions as you type (`Location/PlaceSearch.swift`), or drag the map to drop a pin. Radius 100–500 m.
  - Apple search is free and needs no API key. It missed "Gates Center" in a quick test (found one in New York). If campus buildings keep missing, swap in Google Places inside `PlaceSearch`. That needs a Google Cloud project with billing turned on and an API key.
- [x] **Blocked by default, automatic unlock at allowed places (2026-11-10).** There's no Unlock button. `CLMonitor` watches every saved place (20 at most). When iOS sees you arrive, apps unlock and you get an "Unlocked at X" notification. When you leave, they lock again with an "apps locked" notification. All of this happens in the background, even when the app is closed.
  - One function, `AppModel.reconcile()`, decides the lock state from iOS's reading for each place. It runs after every geofence event, on launch, when the app comes to the front, and when places change.
  - **Lock until I leave:** locks now and doesn't unlock at that place again until iOS sees you leave it.
  - **Overlapping places:** leaving one place while still inside another moves the session over instead of locking.
- [x] **Starter allowlist (2026-11-10).** Every install gets these once, from `Models/DefaultPlaces.swift`:
  - **Gym:** the IMA (47.6537, −122.3012).
  - **Soccer Field:** Husky Soccer Stadium (47.6556, −122.2982).
  - **Home:** The M (4700 Brooklyn Ave NE; 47.6634, −122.3139, from OpenStreetMap). It was a "Set location" slot until 2026-11-10, and the slot mechanism remains for future starter places.
  - Starter places you already have (matched by name) are skipped, and deleted ones don't come back.
- [x] **Two-tab UI (2026-11-10).** A bar along the bottom with two tabs:
  - **Home** (`Views/HomeView.swift`):
    - A big Locked / Unlocked card with "Lock until I leave".
    - "Unlocks at" chips. The current place is green, and empty slots are dashed.
    - Setup and test-mode cards, shown only when needed.
  - **Rules** (`Views/RulesView.swift`), with the tab name still open:
    - The blocked apps. Swipe to remove one, or add more.
    - The allowlist. Tap a place to edit it (`AddPlaceView(editing:)`), swipe to delete it.
  - Launch with `-tab rules` to open straight on Rules.
- [x] **"Pretend I'm at…" simulator (Debug builds only).** A card on Home lets you pick Real location, any place, or Somewhere else. It feeds fake inside/outside readings into the same `reconcile()` the real geofences use, so unlock, lock, "Lock until I leave" and the notifications all behave for real. It's kept in memory only, so a relaunch goes back to real location. `#if DEBUG` keeps it out of Release builds. (`SWIFT_ACTIVE_COMPILATION_CONDITIONS` moved to the app target in project.yml so `DEBUG` is defined again.)
- [x] **24 h delay on new places (2026-11-10).** Closes the "add a place where I'm standing" loophole.
  - **New places** (including filling a slot) start working 24 h after they're added (`Place.activeAfter`).
  - **Moving or enlarging a place** waits 24 h (`Place.pendingChange`), and the old circle keeps working until then. Renaming, shrinking or deleting apply right away, since they only make things stricter.
  - **Setup window:** the first 24 h after install (`setupEndsAt`) has no delay, so initial setup is instant. "Finish setup now" in Rules ends it early. Starter places are always active.
  - **When a wait ends:** a local notification ("Library is now on your allowlist"), plus an in-app timer. Launches and geofence events also apply anything that's come due.
  - **Debug builds:** a "Skip 24 h wait" chip in the "Pretend I'm at…" card.
- [x] **24 h delay on removing blocked apps (2026-11-11).**
  - Swiping an app off the list, or deselecting it in the picker, keeps it blocked for 24 h with an "Unblocks in 23 h" badge.
  - Swipe again and tap **Keep blocked** to cancel.
  - Adding apps is instant. Removals are instant during the setup window.
  - Logic is in `BlockRules`, and pending removals are stored in `BlockList.pendingRemovals`. Older saved lists still load.
- [x] **Decisions moved into pure functions with tests (2026-11-11).** `Models/Rules.swift` holds `LockRules.decide`, `PlaceRules` and `BlockRules`, and `AppModel` only gathers inputs and applies results. `PlaceLockTests/` covers:
  - arriving, leaving and unknown readings
  - Lock until I leave, overlapping places, deleted places, losing Always
  - the 8 h recheck
  - adding and editing places with the delay, and the setup window
  - removal holds, cancels and due removals
  - loading old saves
- [x] Locks if the place is deleted or location drops below Always.
- [x] **After 8 h unlocked**, a fresh GPS fix checks you're still there. If it can't confirm, the apps lock until you leave and come back.
- [x] App's own log lines (`com.nsimon.PlaceLock`) for debugging. See `App/Log.swift`.

## Known issues (to fix)
- **Place search loads forever (seen 2026-11-10, Simulator, on plane Wi-Fi).** Typing in Add place shows "Searching…" and never shows results.
  - Logs show the 8 s "slow connection" message firing. About 50 s later Apple's completer failed with `MKErrorDomain error 1` (`MKError.unknown`).
  - In that session the Simulator never got a single successful response (no "Search results" log line).
  - The same search from a Mac command-line script did work (Smith Hall in about 10 s), and plain HTTPS took about 2.3 s per request. So the network was slow but up.
  - **Cause not confirmed.** It's probably the plane network: the Simulator's maps service (`geod`) requests stalled until they timed out. It could also be specific to the Simulator or to `MKLocalSearchCompleter`.
  - **Next steps:**
    1. Retest on normal Wi-Fi, both in the Simulator and on the iPhone.
    2. If it still fails, log the completer's lifecycle and try a plain `MKLocalSearch` request when the user submits.
    3. Either way, stop the spinner once the slow message shows, so the screen doesn't look stuck.
    4. If Apple search stays unreliable, consider Google Places (see above).

## Next
1. **Test on the iPhone.** Walk into a saved place and confirm the apps unlock on their own (the arrival event can take a minute or two). Walk about 300 m away and confirm they lock within a few minutes. Also test with an Xcode `.gpx` route.
2. **Camera check (MobileCLIP): on hold (2026-11-10).** Unlocking is automatic now, so the scan only matters for "unlock with friends anywhere" and verified lock-ins. We'll revisit after real blocking works. The earlier plan was build-order steps 5–7 in Plan.md.
   - Validate it first with a Mac webcam script.
   - Then build video scan enrollment and unlock on the phone.
   - Unlocking is now automatic, so the scan would be an opt-in per place ("Scan" places get an arrival notification that opens the camera). Auto places stay zero-tap.
3. **Modes from the original notes:**
   - ~~GPS-only unlock places~~ done, this is now the default. Not built yet: always-blocked study spots (Smith Hall, Gates Hall). Apps are already blocked everywhere else, so these only matter for the Lock In stretch goal.
   - Scan-only unlocks anywhere, e.g. "with friends" unlocks, while notes or a class setting keeps apps blocked.
4. **Paid program → real Screen Time blocking** (steps above).
