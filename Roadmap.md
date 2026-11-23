# PlaceLock Roadmap

Last updated: 2026-11-22. The full design is in [Plan.md](Plan.md). This file tracks the ship plan, what's built, temporary workarounds, and what's next.

## Ship plan (written 2026-11-10)
The critical path is Apple, not code. Real blocking needs the paid account, and the App Store needs Apple to approve a separate Family Controls **distribution** entitlement, which can take days to weeks. Request it first and do everything else while waiting.

### Free-account plan (written 2026-11-12)
Until the paid account, these can't be done: real shields, Apple's app picker, the two extensions, the App Group, Sign in with Apple, push notifications, TestFlight, and filing the distribution request. Everything else can. Work in this order:

1. **Keep both builds compiling.** After any blocking change, run `xcodegen generate --spec project-paid.yml`, build with `CODE_SIGNING_ALLOWED=NO`, then run plain `xcodegen generate` to go back. Last checked 2026-11-22, after the geofence keys and sync-in-reconcile change: paid build succeeds, free build passes all 96 tests. The tests use Swift Testing, so look for "Test run with 96 tests"; xcodebuild's XCTest line always says "Executed 0 tests".
2. **Test location on the iPhone (Phase 2).** This is the riskiest part, and it works fully on the free account.
   - Real walks, plus Xcode `.gpx` routes for repeatable tests.
   - With the app force-quit, after a restart, in Low Power Mode, and with location briefly off.
   - Battery use and radius sizes.
   - The `sessions` rows in Supabase (Backend).
   - The place-search spinner (Known issues).
3. **Shippable to strangers (Phase 3).**
   - Build the "Allow Screen Time access" setup step now, behind `#if SCREEN_TIME`. Done 2026-11-12, along with first-run setup and Release-only starter places. Still to do: app icon, Rules tab name, notification wording, dark mode and large text (large text checked 2026-11-22), and the Plan.md rewrite.
   - Any new UI that shows blocked apps goes through one small view: names in the free build, `Label(token)` in the paid build. Real tokens have no names.
4. **Backend leftovers.**
   - "Delete account". Done 2026-11-12, along with the `SyncEngine` tests. The rate limit is a dashboard setting (see Backend).
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
- [x] Join the Apple Developer Program ($99/yr) (done by 2026-11-19; team `R6W24T35J6` in `project-paid.yml`).
- [x] Request the Family Controls distribution entitlement (submitted 2026-11-19). Apple reportedly approves per team, covering the app and both extensions. No confirmation email comes: check each App ID in Certificates, Identifiers & Profiles for "Family Controls (Distribution)". Waits of weeks are common.
- [ ] Check that the name "Spots" is available in App Store Connect (renamed from PlaceLock 2026-11-19).

### Phase 1: Real blocking (code done 2026-11-12, waiting on the paid team to test)
All of this is written and compiles in the paid build (`CODE_SIGNING_ALLOWED=NO`). None of it has run on a phone yet.
- [x] **Paid build switch.** `project-paid.yml` includes `project.yml` and adds the paid team, `SCREEN_TIME`, the entitlements, the App Group and both extensions. `xcodegen generate` still makes the free build. See "Switching to real blocking" below.
- [x] **App Group storage.** `Shared/SharedStore.swift` (compiled into the app and both extensions) and `App/Storage.swift`.
  - Paid builds save to `group.com.nsimon.PlaceLock`. The first paid launch copies everything from `UserDefaults.standard` into the group, and the old copy stays.
  - Free builds keep using `UserDefaults.standard`, since the free team has no App Group.
  - The app shares the active place names and the block selection for the extensions.
- [x] **Block screen** (`Extensions/Shield`): "Instagram is blocked" with "Unblocks at Gym, Soccer Field or Home."
- [x] ~~**8 h safety cap** (`Extensions/SessionCap`, a Device Activity monitor).~~ **Removed 2026-11-19**, along with the 8 h GPS recheck: at home overnight the recheck could fail indoors and lock you out until you left and came back. ~~Missed exits are covered by significant-change wakes now.~~ Corrected 2026-11-22: significant-change wakes re-read what iOS has already decided about each place. A late exit still waits for iOS. The app clears any leftover cap schedule at launch (`ShieldManager.stopLegacySessionCap`). What it did:
  - Every unlock starts a one-off schedule ending 8 h 5 min later. Locking stops it, and moving to another place or passing the 8 h recheck restarts it.
  - If it runs out, the app never got to recheck. The extension blocks the apps again and sends "Open PlaceLock if you're still there". Opening the app runs the overdue recheck.
  - The app now also wakes itself for the 8 h recheck while it's running, so the extension is only a backstop.
- [x] **Screen Time access turned off.** Checked on every reconcile.
  - When access goes from approved to off: a notification, plus a "Blocking is off" card on Home with "Turn Screen Time access back on".
  - "Add or remove apps" is disabled until access is back.
- [ ] Test real blocking on the iPhone. Check:
  - the block screen text
  - that turning off access in Settings › Screen Time shows the warning
  - that existing places survive the switch to the paid build

### Phase 2: Make it trustworthy (about 1 week, mostly daily use)
- [x] 24 h delay on removing blocked apps (2026-11-11).
- [x] Unit tests: 41 tests in `PlaceLockTests/` for `LockRules`, `PlaceRules` and `BlockRules` (2026-11-11). Run with ⌘U or `xcodebuild test`.
- [ ] A few days of real use: arrival and departure timing, after a restart, battery, radius sizes.
- [x] **Arriving didn't unblock until the app was opened (seen 2026-11-19 on the iPhone, fix untested).** Apple's docs: Core Location treats `CLMonitor` events as When In Use unless the app holds a `CLServiceSession` asking for Always, which must be recreated right away on every launch, including background relaunches. `LocationService` now holds one (iOS 18+) and logs its diagnostics if iOS still limits it. Background wakes also ask for extra time (`AppModel.reconcileWhileAwake`), and significant-change updates (about every 500 m, even after a force-quit) re-check every place and refresh "Estimated @". **Test:** close the app, walk home, and check that apps unblock without opening PlaceLock.
- [x] **Battery and temporary notifications (2026-11-22, untested on the iPhone).**
  - "Estimated @" no longer turns on GPS when the significant-change location that woke the app is already within 200 m, never turns it on in Low Power Mode, and in the background runs at most every 5 min (moves and lock changes still estimate right away). Apple Maps names are reused within 100 m (`AppModel.lastGeocode`).
  - Arrive and leave notices share one ID, so each replaces the last. iOS has no expiry, so `clearOldNotices` removes notices older than 5 min (`AppModel.noticeLifetime`) on every wake, and all of them when the app opens. The Screen Time warning stays until access is back.
  - **Test:** a day of normal use, then check Settings › Battery for Spots, and that Notification Center holds at most one recent Spots notice.
- [x] **Removed "Lock until I leave" (2026-11-22)** to get automatic unlock and lock solid first. It also had two bugs: an unknown reading cancelled the pause, and an overlapping place unlocked again right away. `LockRules.decide` no longer takes a paused set, Home shows "Apps block again when you leave." when unlocked, and the saved `pausedPlaces` is cleared at launch. `lock_until_leave` stays in `SessionEnd` and the database for older history.
- [x] **Geofence fixes (2026-11-22, untested on the iPhone).**
  - Each watched circle's identifier now carries its center and radius (`GeofenceKeys` in `Models/Rules.swift`). Syncing is a plain set difference: a circle that didn't change is never removed and re-added. Before, the app compared iOS's stored copy with exact numbers, and a tiny mismatch would have reset every place to "unknown" on every launch and dropped the exit that woke it.
  - Circles are synced only inside `reconcile`, one pass at a time, right before reading iOS's states. Before, a places change and a launch could sync at the same time and undo each other.
  - Logs: every circle added or removed, CLMonitor's iOS 18 warning flags (like `conditionLimitExceeded`), and, on each ~500 m move while unlocked, how far the fix is from the place's edge next to iOS's reading. Logs show the place's ID, never its coordinates.
  - Turning off Always or Precise Location while the app is running now locks at once, instead of at the next wake.
  - After a restart, the app waits for the first unlock before loading anything. Launched earlier, it would have read nothing and saved that over your places, setup window and blocked apps.
  - Renaming a place keeps its exact circle. The edit screen's map could move the center by a hair, which re-added the circle or started a 24 h change.
  - **One time after this update** every place reads "unknown" until iOS checks again, because each circle is re-added under its new identifier. An unlock already running stays on.
  - Considered and not built: using the ~500 m fix to override iOS's "inside". An indoor Wi-Fi fix can be kilometers off, which is why the 8 h recheck was removed. The new log line will show whether iOS ever misses an exit.
  - **Simulator scenarios (2026-11-23): all 6 pass** (`geofence-scenario.py --all --build`, 96 unit tests passing). No app bugs found.
    - `arrive-leave`: 6/6. Stays locked 400 m outside, unlocks on arriving at Gym, locks 300 m past the edge.
    - `background`: 4/4. Unlocks and locks while Spots is in the background, and is still locked when brought back.
    - `move-between-places`: 7/7. Walking Library to Quad moves the unlock to Quad after 33 s (about 232 m past Library's edge), with no lock in between. Locks on leaving Quad.
    - `relaunch-inside`: 6/6. Relaunching inside Home keeps the unlock, with no lock and no second unlock.
    - `waiting-place`: 4/4. A place still waiting out its 24 h sees the entry but doesn't unlock.
    - `walk-out`: 2/2. Walking out of Gym at 4 m/s locks after 84 s, about 237 m past the edge.
    - In `waiting-place` and `walk-out` the first launch didn't start in scenario mode and the runner relaunched once, as designed.
    - The Simulator can't show real exit timing or distance, indoor GPS drift, iOS relaunching Spots after a force-quit, or the Screen Time block screen. Those are still untested on the iPhone.
  - **Test:** see "On-iPhone checks for the geofence fixes" below.
- [ ] **On-iPhone checks for the geofence fixes (2026-11-22).**
  - A plain relaunch logs no "Geofence … added" or "removed" lines.
  - The first launch of the new build logs one "removed (old identifier)" and one "added" per place, once.
  - Renaming a place logs no add or remove.
  - With Spots open and unlocked, set Location to Never in Settings and come back: apps lock.
  - Restart the phone, don't unlock it, walk more than 500 m, then unlock: the log shows "Launched before first unlock; waiting for protected data" and the places are all still there.
- [ ] Fix the place-search spinner (Known issues). The spinner now stops when the "slow connection" message shows (2026-11-12). The cause is still unconfirmed.

### Phase 3: Make it shippable to strangers (about 3–4 days)
- [x] **No starter places (2026-11-12).** New installs start with an empty allowlist in every build, and people add their own places during first-run setup. `Models/DefaultPlaces.swift` is empty, and the seeding code stays in case starters come back. Existing installs keep their places.
- [x] **First-run setup (2026-11-12).** `Views/OnboardingView.swift`, shown full screen once on a new install. Installs from before it existed skip it.
  - Steps: location (Always), Screen Time access (paid build only), pick apps, places, notifications. Each step explains why before iOS asks, and each can be skipped. Home's setup card catches whatever is left.
  - Notifications are no longer requested at launch.
  - **The location prompt no longer appears at launch.** Watching places (`CLMonitor`) made iOS show it immediately, before any explanation. On a new install, `startUp` now waits until the prompt is answered.
  - Debug builds: launch with `-onboardingStep apps` (or `location`, `screenTime`, `places`, `notifications`) to open on a step.
- [x] **One dark look, iOS tab bar (2026-11-19).** The app is always the dark green: one gradient (`Theme.gradient`) and dark mode on every screen, whether apps are locked or not. Unlocking only changes the words and the lock icon, not any colors. Accent is a darker sage (#3E5F51 light, #95B0A2 dark).
  - iOS's own tab bar, forced dark by `calmBackground()`. Left to pick its own colors on the gradient it drew dark icons on a dark pill.
  - Home sits in a `NavigationStack` (bar hidden) like Rules. Without it the tab bar's glass came out pale on Home only.
  - Tried and dropped: a custom tab bar (iOS's bar showed through under it on Rules), and a light unlocked look.
- [x] **Block screen "Estimated @" (2026-11-19).** "Instagram is locked / Estimated @ Suzzallo Library · 2 min ago / Opens at Gym, Field or Home." The app saves its last guess in `SharedStore.estimate` after each reconcile (at most once a minute, right away when the lock state changes), since the block screen can't read location. Name order: the saved place you're inside, Apple Maps' name for the spot (`CLGeocoder`, sends the location to Apple), then "400 m from Gym". Hidden after a day. Logic in `Location/Estimate.swift`, tests in `EstimateTests`. Check on the iPhone that background wakes get a fix in time.
- [x] **Precise Location check (2026-11-19).** With Precise Location off, iOS won't watch places at all, so nothing unlocks. `LocationService.canWatchPlaces` needs Always and Precise. Without Precise the app locks like losing Always, Home's banner says "Precise Location is off", and onboarding asks for it.
- [x] **Tab name, notification wording, picker limits (2026-11-19).**
  - The second tab is **Spots** (still `RulesView` in code, and `-tab rules` to open on it).
  - Notifications: "At Gym, apps unblocked." and "Left Gym, apps blocked." Every lock message now says "blocked".
  - Picking a category blocks its websites too (`shield.webDomainCategories`), not just its apps.
  - iOS shields at most 50 apps, 50 categories and 50 websites, and reportedly blocks nothing past that. `AppModel.setSelection` keeps 50 of each and says so (`BlockRules.capped`).
- [x] **Renamed to Spots (2026-11-19).** The home screen name, permission prompts, notifications, onboarding and block screen say Spots. Bundle IDs (`com.nsimon.PlaceLock`), the App Group, the CLMonitor name (`PlaceLockMonitor`), code and folders keep PlaceLock: changing them would make iOS treat it as a new app, drop its watched places, and not match the Family Controls request. Check that "Spots" is free in App Store Connect; the App Store name can differ from the home screen name if not.
- [x] App icon (2026-11-19): sage green, the two breathing rings and a white lock (`Assets.xcassets/AppIcon.appiconset/AppIcon.png`, 1024 px, no alpha).
- [x] **Large-text check (2026-11-22).** Home, Spots, Add place and first-run setup, checked in the Simulator at the largest accessibility text size. Layout fixes only; at normal sizes the screens look the same.
  - Home scrolls when it doesn't fit, instead of squeezing. "Choose apps to block" was cut to "Choose apps…".
  - The lock and its rings are smaller at accessibility sizes, to leave room for the words.
  - Place cards on Home grow with the text (up to 240 pt wide), so names wrap between words. Before, they broke inside them ("Soc-cer", "Open-s here").
  - On Spots, a place's countdown or "Here" goes under its name at accessibility sizes, and the address gets two lines. The setup row puts Finish under its label.
  - First-run setup: the buttons stop growing at the second accessibility size, so the explanation keeps most of the screen. The scroll bar flashes when a step opens, to show there's more text below.
  - Add place: the "go to my location" arrow no longer spills out of its circle.
  - Not checked on the iPhone, and not checked: the block screen, the Backup and Debug screens, the 24-hour info sheet, and Home while unlocked.
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
- [x] **50 m minimum radius (2026-11-19).** `20261119000000_min_radius_50.sql` relaxes both radius checks to 50–500 m. Applied to the live project through the Supabase MCP server, and checked. Supabase's migration history lists only this one: the first migration was run by hand in the SQL editor, so record it (`supabase migration repair`) before ever using `supabase db push`.
- [ ] Rate-limit anonymous sign-ins before TestFlight. This is a dashboard setting, not code: Supabase › Authentication › Rate Limits › anonymous sign-ins per hour (per IP). Something like 10 is plenty. CAPTCHA (Authentication › Attack Protection) would also need the app to send a captcha token with `signInAnonymously`, so leave it off unless abuse shows up.
- [x] **Phone side (2026-11-11).** `PlaceLock/Sync/`, using supabase-swift 2.55.6, pinned to 2.x.
  - `SyncEngine` signs in anonymously on first launch. Each pass pulls places, merges them, syncs the setup-window end (earliest wins), then flushes the outbox.
  - Passes run on launch, on foreground, when the network returns, and after any local change. Failures retry with backoff, from 5 s up to 5 min.
  - **Recorded history:** every unlock writes a `sessions` row, closed with a reason (`left`, `moved`, `lock_until_leave`, `place_deleted`, `lost_always`, `recheck_failed`). An 8 h recheck stays the same visit.
  - **First sync:** uploads existing places. After a reinstall, the server's places replace re-seeded starter places that have the same name.
  - **Status:** Rules has a "Backup" section showing it.
  - **When it's off:** with no URL or key in Info.plist, or under unit tests, sync does nothing.
  - **Tested:** 22 tests in `SyncRulesTests`. On the Simulator against the live project, the first sync uploaded the 3 starter places. Session upserts were checked against the live server with a temporary account, which was then deleted.
- [x] **Server calls behind `SyncBackend` (2026-11-12).** `Sync/SyncBackend.swift` holds every Supabase call. `SyncEngine` takes a backend and the phone's data (`SyncLocal`, which is `AppModel`), so tests use fakes. `SyncEngineTests` (14 tests, 77 total, all passing) cover:
  - first sync, restore and incremental pulls
  - places upload before sessions
  - offline retries, rejected rows, and the queue surviving a relaunch
  - unusable sessions, the setup window
  - account deletion and turning backup back on
- [x] **Fixed: reinstalls duplicated the starter places on the server (2026-11-12).** iOS keeps the Supabase sign-in in the Keychain when the app is deleted, so a reinstall restores the same account. Seeding ran the `places` observer (Swift runs observers in methods called from `init`), which queued the starter places as edits. So the first sync uploaded them as new places instead of dropping them as duplicates.
  - Seeding no longer queues anything.
  - The Simulator's test account still has 15 places from repeated reinstalls. Clear it with Delete account.
  - If you've reinstalled on the iPhone before, check its places for copies too.
- [x] **Fixed: every sync re-downloaded the newest place (2026-11-19).** The pull cursor was a `Date`, and Postgres's microseconds didn't survive the round trip, so `synced_at > cursor` matched the newest row again on every pass. The cursor is now the server's own `synced_at` text, read from the raw response (`PlacePage.cursor`, `SyncEngine.State.pullCursor`). State saved before this pulls everything once. Checked against the live project: foreground passes now pull nothing.
- [x] **Fixed: every launch re-uploaded all places and re-blocked apps (2026-11-19).** Swift runs `didSet` on `@Published` properties even in `AppModel.init`, so loading saved data counted as edits. `places` queued every place as "edited now" on each launch, which could overwrite newer edits from the server. `blockList` blocked apps because `session` wasn't loaded yet, so in the paid build a cold launch (including a background relaunch) while unlocked would re-block apps until you left and came back. `init` now loads into the `@Published` storage directly (`_places = Published(initialValue:)`). Checked in the Simulator: relaunching while unlocked no longer uploads or blocks, and relaunching while away still blocks.
- [ ] Test an unlock → leave cycle on the iPhone and confirm the `sessions` row in the Supabase table editor.
- [x] **Delete account (2026-11-12).** Rules › Backup › "Delete account", after a confirmation.
  - It calls `delete_my_account()`, which deletes every row, then signs out and turns backup off.
  - Places and blocked apps stay on the phone, and blocking keeps working.
  - "Turn backup back on" starts a new account.
  - If the server can't be reached, nothing changes and an alert says so.
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

Everything else is real in both versions: places, GPS unlock, lock on leaving and notifications.

All the switching happens in `PlaceLock/PlaceLock/Blocking/ShieldManager.swift` (`#if SCREEN_TIME`) and the picker modifier in `Views/RootView.swift`. Storage switches in `Shared/SharedStore.swift`.

### Switching to real blocking (once on the paid program)
1. In `PlaceLock/project-paid.yml`, replace `PAID_TEAM_ID` with the paid team ID (developer.apple.com › Membership details).
2. Run `xcodegen generate --spec project-paid.yml` in `PlaceLock/`, then build to the iPhone. Automatic signing registers the App Group and the extension's bundle ID (`com.nsimon.PlaceLock.Shield`). A `com.nsimon.PlaceLock.SessionCap` App ID may exist from before 2026-11-19; it's unused now.
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
- [x] Save allowed places: search by name with Apple Maps suggestions as you type (`Location/PlaceSearch.swift`), or drag the map to drop a pin. Radius 50–500 m (100 m minimum until 2026-11-19; below 100 m Add place warns that small circles can miss arrivals indoors).
  - Apple search is free and needs no API key. It missed "Gates Center" in a quick test (found one in New York). If campus buildings keep missing, swap in Google Places inside `PlaceSearch`. That needs a Google Cloud project with billing turned on and an API key.
- [x] **Blocked by default, automatic unlock at allowed places (2026-11-10).** There's no Unlock button. `CLMonitor` watches every saved place (20 at most). When iOS sees you arrive, apps unlock and you get an "Unlocked at X" notification. When you leave, they lock again with an "apps locked" notification. All of this happens in the background, even when the app is closed.
  - One function, `AppModel.reconcile()`, decides the lock state from iOS's reading for each place. It runs after every geofence event, on launch, when the app comes to the front, and when places change.
  - ~~**Lock until I leave:** locks now and doesn't unlock at that place again until iOS sees you leave it.~~ **Removed 2026-11-22** to focus on the core unlock and lock (see Phase 2).
  - **Overlapping places:** leaving one place while still inside another moves the session over instead of locking.
- [x] **Starter allowlist (2026-11-10, removed for new installs 2026-11-12, see Phase 3).** Installs from before 2026-11-12 got these once, from `Models/DefaultPlaces.swift`:
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
- [x] **Calm UI refresh (2026-11-12).** Replaced the card-heavy Home above.
  - **Home:** a deep evening gradient with rings that breathe over 8 s (held still under Reduce Motion). Since 2026-11-19 it looks the same unlocked. Blocked apps show dimmed as "resting", and places are glass cards. No streaks or scores.
  - **Everywhere else:** `calmBackground()` in `Views/Theme.swift` puts the same gradient behind Rules, Backup (`Views/BackupView.swift`) and Debug (`Views/DebugView.swift`), with glass list rows and dark bars. Accent color and theme tokens are in `Shared/Brand.swift` and `Views/Theme.swift`.
  - The block screen (`Extensions/Shield`) uses the calmer wording too.
- [x] **Visit log (2026-11-12).** `AppModel.visits` (`Models/Visit.swift`) keeps finished unlock visits from the last two weeks, on the phone only. Home uses it for "locked since". `unlocksToday` and `lockedShareToday` are written but unused, ready for `StatsStore` and streaks. Launch with `-demoHistory YES` to fill today with two sample visits for screenshots. The server keeps its own history in `sessions`.
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
- [x] ~~**After 8 h unlocked**, a fresh GPS fix checks you're still there.~~ Removed 2026-11-19 (see the 8 h cap in Phase 1).
- [x] App's own log lines (`com.nsimon.PlaceLock`) for debugging. See `App/Log.swift`.

## Known issues (to fix)
- **Turning off location while unlocked keeps apps unblocked (accepted for now, 2026-11-22).** With Location set to Never or While Using, or Precise Location off, iOS stops waking Spots. If you're unlocked at the time and Spots isn't open, nothing locks until you open it. The removed 8 h cap was the backstop for this. A Device Activity backstop could bring it back; the decision is open.
- **The app picker is crowded with websites (seen 2026-11-19, first paid build on the iPhone).** Partly settled 2026-11-19: categories now block their websites too, and selections are capped at 50 of each kind (see Phase 3). Still open: pairing an app with its website. How Opal handles it (researched 2026-11-19, from Opal's help pages): same Screen Time picker, so only sites visited in Safari appear and domains can't be typed in (their workaround: open the site in Safari for ~10 min); blocking is reliable in Safari only, not Chrome/Firefox/Brave/Arc; their fix is an Allow List mode (block everything except picked apps). Ideas for Spots: tell people to block other browser apps too; check whether Screen Time's web content filter (`WebContentSettings`) accepts plain domain names, which could block youtube.com automatically when YouTube is picked (unverified, likely Safari only). Apple's `FamilyActivityPicker` lists many websites next to the apps, which makes it hard to pick just the few things you want. Blocking sites matters (youtube.com is the obvious way around a blocked YouTube app), but how many should we block, and how?
  - **What the code does now:** `SharedStore.shield` blocks the apps, app categories and individual websites you pick. Picking a category blocks its apps only. Its websites stay open, because `shield.webDomainCategories` isn't set.
  - **Questions to settle:**
    1. Should picking an app also block its main website (YouTube → youtube.com)? Tokens don't carry names, so we can't pair them automatically. The user would have to pick both, or we'd prompt them to.
    2. Should picking a category also block that category's websites (`shield.webDomainCategories`)? That's broader and catches more ways around the block, but could also block sites people need.
    3. Is there a cap on how many websites a shield can hold? Check Apple's `ShieldSettings` docs, then test on the phone with a big selection.
    4. Can onboarding steer people to a short list? For example: "pick your 3–5 worst apps and their websites."
- **Leaving with the app killed didn't lock in the Simulator (2026-11-19).** After `simctl terminate`, iOS didn't relaunch the app for the exit within 2 minutes; opening the app caught up and locked. Likely a Simulator limit, so test force-quit + walk out on the iPhone.
- **Place search loads forever (seen 2026-11-10, Simulator, on plane Wi-Fi).** Typing in Add place shows "Searching…" and never shows results.
  - Logs show the 8 s "slow connection" message firing. About 50 s later Apple's completer failed with `MKErrorDomain error 1` (`MKError.unknown`).
  - In that session the Simulator never got a single successful response (no "Search results" log line).
  - The same search from a Mac command-line script did work (Smith Hall in about 10 s), and plain HTTPS took about 2.3 s per request. So the network was slow but up.
  - **Cause not confirmed.** It's probably the plane network: the Simulator's maps service (`geod`) requests stalled until they timed out. It could also be specific to the Simulator or to `MKLocalSearchCompleter`.
  - **Next steps:**
    1. Retest on normal Wi-Fi, both in the Simulator and on the iPhone.
    2. If it still fails, log the completer's lifecycle and try a plain `MKLocalSearch` request when the user submits.
    3. ~~Either way, stop the spinner once the slow message shows, so the screen doesn't look stuck.~~ Done 2026-11-12. Results that arrive late still show.
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
