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
   - Build the "Allow Screen Time access" setup step now, behind `#if SCREEN_TIME`. Done 2026-11-12, along with first-run setup and Release-only starter places. Still to do: app icon, Rules tab name, notification wording, dark mode and large text (large text checked 2026-11-22 and 2026-11-23), and ~~the Plan.md rewrite~~ (done 2026-11-23).
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
- [x] **Paid build switch.** `project-paid.yml` includes `project.yml` and adds the paid team, `SCREEN_TIME`, the entitlements, the App Group and the Shield extension. `xcodegen generate` still makes the free build. See "Switching to real blocking" below.
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
  - 2026-11-23: the rest checked in the Simulator at the largest accessibility text size: Home while unlocked, Backup, Debug, the 24-hour info sheet, About and the setup row on Spots. `verify.sh --large-text` now takes every `--screens` shot again at that size (`large-*.png`), and `-push debug` (with `-tab rules`) opens Debug for its shot. Fixes:
    - The 24-hour info sheet cut every line short ("Some chan…", "Removing…"). At accessibility sizes it now opens full height and scrolls. At normal sizes it looks the same.
    - The setup row broke "21 h" across two lines. Countdowns ("21 h", "45 min") now keep the number and unit together everywhere.
    - The Backup row on Spots cut its status to "Backed up…". At accessibility sizes it gets up to three lines.
    - Fine as they were: Home while unlocked (it scrolls), the Backup screen and About. Debug breaks "Some-where else" inside the word; it's only in Debug builds, so left alone.
    - Not checked: the block screen, which needs the paid build and a real Screen Time block, so it can't be screenshotted in the Simulator. Nothing here was tried on the iPhone.
- [x] **Recovery when permissions are denied (2026-11-23).** Checked in the Simulator (free build) with `xcrun simctl privacy`: location never asked, denied, While Using only, and Always, standing inside a saved place. With Always it unlocked; denied and Precise off showed Locked. In the never-asked and While Using shots iOS's own location prompt covers the lock, and `LockRules` keeps apps locked without Always (tested).
  - Home's banner now names the problem: "Location access needed" (never asked; Fix shows iOS's prompt), "Location access is off" (denied; Fix opens Settings), "Location isn't set to Always" and "Precise Location is off" (Fix opens Settings). Before, denied and never asked both said "Location isn't set to Always". The wording and the button's action come from `PermissionRules`, tested in `PermissionRulesTests`.
  - First-run setup's location step says "Location access is off" when it was denied, next to its Open Settings button. Before, it showed only the button.
  - Notifications turned off in Settings: the Spots tab shows "Notifications are off" under Settings, with Open Settings, and setup's notifications step shows Open Settings instead of a button that did nothing. Blocking doesn't need them, so Home doesn't nag. "Not now" during setup isn't flagged.
  - `simctl privacy` can't turn off Precise Location or notifications, so those two were checked with new Debug launch arguments, `-preciseOff YES` and `-notificationsOff YES`, which make the app read them as off.
  - Screen Time access denied (paid build only) was checked by reading the code, not run: `refreshScreenTimeAccess` notices on every reconcile, sends "Screen Time access is off…", and Home's banner says "Blocking is off" with Fix asking for access again. iOS removes every block when access is turned off, so apps can't stay blocked then; the warning is all Spots can do.
  - Not checked on the iPhone: that Fix and Open Settings land on Spots' page in Settings, real Precise Location and notification switches, and that asking for Screen Time again after turning it off shows Apple's prompt.
- [x] **VoiceOver labels (2026-11-23).** Every icon-only button and meaningful picture under `Views/` has a VoiceOver label, and decorative ones are hidden. Nothing on screen changed.
  - The big lock on Home reads "Apps blocked", "Apps unblocked" or, with no apps picked, "No apps blocked yet". "Locked" and "Unlocked" are read as a heading.
  - Countdowns and times read as words: "Starts in 23 hours, 4 minutes" instead of "23 h", "for 2 hours, 14 minutes" instead of "2h 14m", and "Setup, 21 hours left". Radii read as "150 meters", not "150 m". The wording is in `SpokenRules` (`Models/SpokenRules.swift`, tested in `SpokenRulesTests`).
  - Hidden as decoration: place and step symbols, row arrows, the search glass, the map's center pin, the warning icon on Home's banner, the pictures on the simulated block screen, and the row of app icons on Home (VoiceOver reads the count under it, and Spots lists every blocked app by name).
  - The radius slider in Add place reads "Radius, 150 meters". The stand-in app picker and Debug's Pretend I'm at say which rows are selected. First-run setup's titles are headings, and its hidden Back button on the first step is skipped.
  - Not tried with VoiceOver on the iPhone, and nothing was listened to in the Simulator: only the labels in code were checked, and the screenshots look the same. Also not checked: the real Screen Time block screen and Apple's app picker, which Spots doesn't draw.
- [x] **Plan.md rewritten (2026-11-23).** It now describes what's built: automatic unlock and lock at saved places, the 24 h wait on loosening, permissions, the two builds, the code layout and backup as records only. The tap-and-scan design is gone; the camera scan is kept as an on-hold idea, and the 8 h cap, Lock until I leave and the Shortcuts approach are listed under "Tried and dropped". Docs only.

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
- [x] Debug-only code stays out of Release (2026-11-23). Behind `#if DEBUG`: the launch arguments `-tab`, `-sheet`, `-push`, `-scrollTo`, `-pretendAt`, `-onboardingStep`, `-demoHistory` and `-scenario`, the Debug screen and its link in Spots › Settings, Pretend I'm at, Skip 24 h wait, sample visits, scenario mode and the check for running under unit tests. The free build's stand-ins (the stand-in app list and picker, the simulated block screen) aren't compiled into the paid build at all. `-onboarded` stays: it's the real saved setting. `verify.sh --release` now fails if any of these show up in the paid Release binary's symbols. Debug builds behave as before; free Release builds no longer have the Debug screen. Not tried on the iPhone: a Release build there.
- [x] More screens in `verify.sh --screens` (2026-11-23). It now also takes Home while unlocked (`home-unlocked.png`), Spots scrolled to About (`about.png`), the 24-hour wait sheet (`wait-info.png`) and Backup (`backup.png`). New Debug-only launch arguments open them: `-sheet wait`, `-push backup` and `-scrollTo about` (with `-tab rules`), and `-pretendAt <place name>`, which starts as if Debug's Pretend I'm at had picked that place. The unlocked shot uses a scenario store with one place, Library, so the Simulator's own places don't matter. The screens look the same as before. Test plumbing only, so nothing to try on the iPhone.
- [x] No crashes from bad saved data (2026-11-23). Saved places, visits, the session, the block list, settings and backup state now load through `SavedData` (`Models/SavedData.swift`, with tests). A damaged place or visit is dropped on its own and the rest still load. A damaged session means locked. A damaged setup-window date ends the first day's instant changes instead of starting a new one. Anything that can't be read is logged and copied to `unreadable.<key>` before the app saves over it. A failed save keeps the last good one instead of erasing it. The app code has no `try!`, `as!`, force unwraps or `fatalError` left. Not tried on the iPhone: a real Screen Time app list that can't be read (see Known issues).
- [x] Version numbers and export compliance (2026-11-23). `project.yml` sets the version (`MARKETING_VERSION`, 1.0.0) and build number (`CURRENT_PROJECT_VERSION`, 1). The app's and the Shield extension's Info.plists both read them, so the two always match. Both also say `ITSAppUsesNonExemptEncryption = NO`: the only encryption is HTTPS, so App Store Connect won't ask the encryption question on each upload. `scripts/bump-build.sh` raises the build number (and sets the version with `--version 1.1.0`) and regenerates the project. Checked in the paid Release build: app and extension both show 1.0.0 (1). Not tried yet: an actual upload to App Store Connect.
- [x] Archive script (2026-11-23). `scripts/archive.sh` generates the paid project, archives the Release build and exports it for App Store Connect with `scripts/ExportOptions.plist` (method `app-store-connect`, automatic signing, the team from `project-paid.yml`). Then it regenerates whichever project was open before. It refuses to run if the export options would upload, or if their team doesn't match `project-paid.yml`. It never uploads: it prints the Organizer and `xcrun altool` commands instead (see `docs/app-store/launch-checklist.md`). `archive.sh --check` archives without signing and checks the archive: an app archive (not a "Generic Xcode Archive"), the Shield extension inside, both 1.0.0 (1), both encryption exempt. The check passes. Not tried yet: a signed archive and export with the paid team, and the upload itself.
- [x] Privacy audit of logs and what leaves the phone (2026-11-23). Every log line was checked. Place names, search text, the lock reason ("Left Gym…") and sync errors were logged in the clear; they're now private, so a shared device log shows `<private>`. Sync errors log their type and code publicly (`SyncEngine.logLabel`), because Postgres repeats a rejected row, with its name and coordinates, in the error. `docs/app-store/data-inventory.md` lists everything that leaves the phone (each Supabase column, Apple's geocoder, place search and map tiles; notifications are local only), whether it's linked to the account, and the required-reason APIs: only `UserDefaults` (`CA92.1`, plus `1C8F.1` for the App Group in the paid build). No Screen Time data is synced or logged. All 6 geofence scenarios still pass (they read place names from the log, which the Simulator shows in full). Not checked on the iPhone: that Console really shows `<private>` without a debugger attached.
- [x] Privacy manifests (2026-11-23). The app and the Shield extension each have a `PrivacyInfo.xcprivacy`, listed in `project.yml` and `project-paid.yml` as resources. Both say no tracking and no tracking domains. The app declares what the backup sends, all linked to the account and only for the app's own features: precise location (places), user ID (the anonymous account), other user content (place names and addresses) and product interaction (unlock history). Its required reasons are `UserDefaults` `CA92.1` and `1C8F.1`; the extension collects nothing and lists `1C8F.1`. Checked in the built app and extension, Debug and Release. supabase-swift ships no manifest of its own; swift-crypto's empty one is in the app. Details in `docs/app-store/data-inventory.md`. Not checked yet: Xcode's privacy report for a signed archive, and App Store Connect's own checks on upload.
- [x] About section with privacy policy and support links (2026-11-23). Spots › About shows the version and build ("1.0.0 (1)"), a "Privacy policy" link and a "Contact support" link. The addresses live in one place, `Shared/Brand.swift` (`privacyPolicyURL`, `supportURL`, `supportEmail`), and are empty for now, so only the version shows. A link row appears once its address is set and is a real `https` address (or, for support, a plain email). Contact support opens the email if one is set, otherwise the support page. The rules are in `AboutRules` (`Models/AboutRules.swift`, with tests). Apple requires the privacy policy to be reachable in the app, so the real addresses must be filled in before submitting (see `docs/app-store/launch-checklist.md`). Checked in the Simulator with temporary example addresses. Not tried on the iPhone: the links opening Safari and Mail.
- [x] App Review guideline audit (2026-11-23). `docs/app-store/review-audit.md` goes through guidelines 2.1, 2.3, 2.5, 4.0, 5.1.1, 5.1.2 and 5.1.5, and the license agreement's Family Controls clause (3.3.3(P)). Each is marked OK, fixed or your call. Fixed:
  - The location purpose strings, which left out unblocking on arrival, place search near you and the block screen's "Estimated @" line, and said "allowed place". iOS's location prompts now read "Spots checks whether you're at one of your places to decide if apps unblock, and finds places near you when you add one." and "With Always, Spots notices when you arrive at or leave one of your places, even when it's closed, so apps unblock while you're there and block again when you go. The block screen also shows roughly where you are."
  - `verify.sh --release` now also fails if the Release binary contains the stand-in or Debug wording ("Stand-in list", "Pretend I'm at" and so on).

  Left for you: backup starts without asking, and setup's "Your location stays on this phone." isn't quite true (both in `.night/needs-you.md`). Also left: the privacy policy link, keeping Supabase from pausing during review, and on-device testing. Not seen on the iPhone: the new wording in iOS's location prompts.
- [x] Privacy policy draft (2026-11-23). `docs/app-store/privacy-policy.md` is a plain-language draft that follows `docs/app-store/data-inventory.md`. It covers what stays on the phone (live location, blocked apps, notifications), what backup sends to Supabase and why, Apple's place search, map and "Estimated @" lookups, how long backups are kept and Delete account. `docs/privacy/index.html` has the same text as one static page with no scripts or fonts, ready to host. Both are marked DRAFT. Left for you (`TODO(user)`): the effective date, your name, the support email, the Supabase region, how long Supabase keeps request logs and backups, and what to say about children. The draft describes backup as on from first launch, so it changes if the backup consent question in `.night/needs-you.md` does. Not published or linked in the app yet.
- [x] Draft App Store screenshots (2026-11-23). Taken in the "iPhone 17 Pro Max" Simulator at 1320 × 2868, Apple's 6.9" size: Home locked and unlocked, Spots, Add place, the 24-hour sheet and three setup steps, with three tidy demo places (Home, Library, Gym). They're drafts and aren't in the repo: they're in `.night/app-store-screens/` in your checkout, with the script that retakes them and notes. The free build shows stand-in symbols instead of real app icons, so Home and Spots should be retaken from the paid build. Shots of the block screen need the paid build on the iPhone. No app code changed: the demo data goes in through launch arguments in scenario mode, so nothing is backed up.
- [x] README checked against the code (2026-11-23). The limits (20 places, 50–500 m with a warning below 100 m, the 500 m movement wakes), the block screen text, the launch arguments, the build steps and the scripts all match. Fixed: the paid build adds one extension (Shield), not two. Added `-scenario` to the launch arguments, `verify.sh` and `geofence-scenario.py` to Tests, the newer tests, `scripts/` and `docs/` to the project layout, and the launch checklist to Docs. Docs only.
- [x] Launch checklist (2026-11-23). `docs/app-store/launch-checklist.md` now has two parts. "Ready" lists what's in place, each with its file or commit. "Your steps" lists, in order, what only you can do: tonight's open questions, the paid build on the iPhone, the on-iPhone test list gathered from this file, the app record, the Family Controls distribution check for the app and the Shield, Supabase's rate limit (keep about 30 an hour, the default, since friends on campus Wi-Fi share one address), the privacy policy and links, archive and upload, TestFlight, App Privacy and age rating, the listing and screenshots, and submitting. Docs only; none of the steps has been done yet.
- [x] Review of the night's commits (2026-11-23). Every commit on `night/2026-11-22` since `main` was reviewed for bugs and broken CLAUDE.md rules. Fixed:
  - Add place: a plain search (pressing Search before suggestions arrive) that found nothing left the spinner going, then swapped "No matches" for the slow-connection message (see Known issues, place search).
  - Spots: a place's "Here" or "Starts in" status floated mid-row at normal text sizes, instead of sitting by the arrow. Checked in the Simulator.
  - A saved block list whose waiting removals (or the free build's stand-in apps) can't be read is now logged instead of reset silently. Unreadable backup state now logs under `sync`, not `app`.
  - Smaller points that change what people see are questions in `.night/needs-you.md`. Not tried on the iPhone.
- [ ] App Store Connect listing:
  - Screenshots, description, Productivity category, support URL.
  - Privacy policy URL (also goes in `Shared/Brand.swift` for the in-app link).
  - Privacy label: **no longer "Data Not Collected"** once sync ships. Declare as linked to the user and not used for tracking:
    - Precise location: saved places.
    - User ID: the account.
    - Product interaction: sessions (App Store Connect's name for it; this said "usage history" before 2026-11-23).
    - Other user content: place names and addresses (added 2026-11-23 with the privacy manifests).

    Update the privacy policy to match.
  - ~~Encryption question: none (`ITSAppUsesNonExemptEncryption = NO`).~~ Set in both Info.plists 2026-11-23.
  - Drafted 2026-11-23, ready to paste: `docs/app-store/listing.md` (name, subtitle "Apps unblock where you choose", promotional text, description, keywords, all within Apple's limits), `docs/app-store/app-privacy.md` (the four data types above, each App Functionality, linked, not tracking) and `docs/app-store/age-rating.md` (everything No or None, so 4+, including the Shared Location question Apple added 2026-11-16). Left for you: the support, marketing and privacy policy URLs, the copyright name, whether Supabase's logs keep IP addresses long enough to declare, and the "Health or Wellness Topics" answer. Not entered in App Store Connect.
- [ ] Review notes:
  - Explain why the app needs "Always" location, with a short screen recording.
  - Explain that a place added in the first 24 h (the setup window) works right away, so the reviewer can test where they are.
  - Drafted 2026-11-23 in `docs/app-store/review-notes.md`: why Spots needs Always, steps to try it at a desk in the setup window (add a place where you are, see apps unblock, delete the place to see them block again and the block screen), that the block screen needs a real iPhone, and a 13-step script for the screen recording. Left for you: contact details and the recording. None of the steps has been tried on the iPhone yet.
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
- **"Blocking 1 apps" (seen 2026-11-23, reading the code).** With one app, category or website picked, setup's apps step says "Blocking 1 apps" ("1 categories", "1 websites"): `BlockList.summary` always uses the plural. Fix before the App Store screenshots and the review recording; the review notes pick two apps to avoid it for now.
- **`-sheet add` doesn't open Add place (seen 2026-11-23).** In the Simulator, launching with `-onboarded YES -sheet add` shows Home without the sheet, so `verify.sh --screens` saves Home as `add-place.png`. It happens on the commit before the VoiceOver labels too, so it's older than them. Not looked into yet.
- **An unreadable app list starts empty (2026-11-23).** If the saved Screen Time selection can't be read (for example after an iOS update changes its format), Spots can't get the apps back: nothing is blocked from the next check of where you are (at launch), Spots shows no blocked apps and Home asks you to choose apps again. The original is kept as `unreadable.blockList`. Spots doesn't say why the list is empty; a message saying so is an open question.
- **Turning off location while unlocked keeps apps unblocked (accepted for now, 2026-11-22).** With Location set to Never or While Using, or Precise Location off, iOS stops waking Spots. If you're unlocked at the time and Spots isn't open, nothing locks until you open it. The removed 8 h cap was the backstop for this. A Device Activity backstop could bring it back; the decision is open. Options written up 2026-11-23 from Apple's docs and forums, nothing built:
  - **What Device Activity can do.** A Device Activity monitor is an app extension that iOS runs on a schedule Spots sets, even when Spots is closed or force-quit. It can block apps: Apple's `DeviceActivityMonitor` page shows one setting `store.shield.applications`. Through the App Group it can read the picked apps and whether Spots thinks it's unlocked. It can't tell where you are: it gets no geofence events and no location.
  - **When it runs.** Only while the phone is in use. Apple: an interval starts "when someone first uses the device within the activity's scheduled time interval", and ends when someone first uses it after. That's fine here, because unblocked apps only matter while the phone is in use. Intervals must be at least 15 minutes and at most a week (developers on Apple's forums quoting Apple's docs; Apple's pages I read name the errors without numbers). Apple also has usage events (`DeviceActivityEvent`): a callback once picked apps have been on screen for a set time within an interval.
  - **Option A: check the permission on a schedule (recommended if it works).** A repeating daily schedule split into a few intervals (say 6 of 4 hours), plus a usage event on the picked apps (say 15 minutes) in each. Each callback checks: if Spots is unlocked and Location isn't Always with Precise on, block and notify ("Location is off, so apps are blocked. Open Spots to fix it."). It catches Never, While Using, Precise off and Location Services off. It can't catch anything else, like a missed exit. A long stay at home doesn't trip it, because it checks the permission, not the time. With the usage event, someone using the loophole is blocked after about 15 minutes in the picked apps. Without it, the wait is up to one interval of phone use. **Unknown:** whether the extension can read Spots' location permission (`CLLocationManager().authorizationStatus` and `accuracyAuthorization`). Apple doesn't say for this kind of extension, and I found nothing either way. This has to be tested first.
  - **Option B: a check-in deadline.** Each time Spots runs, it pushes a one-off schedule's end N hours later. If the schedule runs out, Spots hasn't run, so the extension blocks. It doesn't need to read the permission, and it catches anything that stops Spots running. But iOS doesn't wake Spots while you sit still at a place, so a long stay at home trips it, like the 8 h cap did. Opening Spots would unblock again (see the app change below), but at home that's a daily chore. Only worth it with a long N (24 h), or as a fallback if A can't read the permission.
  - **Option C: keep accepting it.** No code. Turning Location to While Using stays the easiest way around Spots while you're at a place.
  - **How this differs from the removed 8 h cap.** The cap counted 8 h from every unlock, whatever the reason. Opening Spots then ran a fresh GPS fix, which could fail indoors and lock you out at home. A checks the permission, not the time. B is close to the cap, but counts from Spots' last run, and opening Spots now re-reads iOS's inside/outside reading instead of taking a GPS fix.
  - **What it costs (A or B):**
    - A second extension in `project-paid.yml` (a Device Activity monitor) with the Family Controls and App Group entitlements, the same kinds the Shield extension has. No new kind of entitlement. It needs its own bundle ID. The old `com.nsimon.PlaceLock.SessionCap` App ID may still exist, and the distribution request (2026-11-19) was filed while that extension existed, so reusing it might already be covered. Check its "Family Controls (Distribution)" in Certificates, Identifiers & Profiles. A new ID might mean another approval wait.
    - App changes. `ShieldManager.stopLegacySessionCap` stops every schedule at launch (`stopMonitoring()` with no names), so it would cancel the new one: it should stop only the old cap's name. And `AppModel.reconcileNow` does nothing on `.stayUnlocked`, so if the extension blocked and you're still at the place with location back on, opening Spots would leave apps blocked while Home says unlocked. Spots would need to clear the block again. The check itself ("unlocked and missing Always or Precise") would go in a rules type with tests, shared by the app and the extension.
    - The product rule "Losing Always or Precise Location access locks as soon as Spots runs" would get stricter (it would lock without Spots running), so CLAUDE.md's wording changes too.
    - Memory: forum threads report a 6 MB limit for these extensions (735454, 745035), so it must stay tiny, with no sync code. The old SessionCap extension was about 25 lines.
    - Battery: iOS runs the schedule itself, and the extension runs for a moment a few times a day. I found no figures; expected to be small, not measured.
    - Reliability: forum threads report callbacks that sometimes never come, or an extension that fails to launch (773228, 751597, 745035). In 751597 an Apple reply calls it "a known issue". It's a backstop, not a guarantee.
  - **Recommendation:** A, if a quick test shows the extension can read the permission. Test build: a 15-minute repeating schedule whose extension logs `authorizationStatus` and `accuracyAuthorization`; then, with Spots closed, set Location to While Using and check the log. If it can't read them, stay with C rather than build B, since B brings back the lockouts at home that removed the cap. Build A before release only if the old SessionCap ID turns out to be approved; otherwise make it the first update.
  - Sources: [DeviceActivityMonitor](https://developer.apple.com/documentation/deviceactivity/deviceactivitymonitor), [intervalDidStart(for:)](https://developer.apple.com/documentation/deviceactivity/deviceactivitymonitor/intervaldidstart(for:)), [intervalDidEnd(for:)](https://developer.apple.com/documentation/deviceactivity/deviceactivitymonitor/intervaldidend(for:)), [DeviceActivitySchedule](https://developer.apple.com/documentation/deviceactivity/deviceactivityschedule), [DeviceActivityCenter.MonitoringError](https://developer.apple.com/documentation/deviceactivity/deviceactivitycenter/monitoringerror), [DeviceActivityEvent](https://developer.apple.com/documentation/deviceactivity/deviceactivityevent), forum threads [747557](https://developer.apple.com/forums/thread/747557) and [729841](https://developer.apple.com/forums/thread/729841) (15 minutes to a week), [735454](https://developer.apple.com/forums/thread/735454) and [745035](https://developer.apple.com/forums/thread/745035) (6 MB), [773228](https://developer.apple.com/forums/thread/773228) and [751597](https://developer.apple.com/forums/thread/751597) (missing callbacks). Context7 had only third-party wrappers, not Apple's pages.
  - Not checked: everything on the iPhone; whether the extension can read the location permission; how many activities Spots may run at once (Apple only says "too many"); battery; whether the SessionCap ID is approved.
- **The app picker is crowded with websites (seen 2026-11-19, first paid build on the iPhone).** Partly settled 2026-11-19: categories now block their websites too, and selections are capped at 50 of each kind (see Phase 3). Still open: pairing an app with its website. How Opal handles it (researched 2026-11-19, from Opal's help pages): same Screen Time picker, so only sites visited in Safari appear and domains can't be typed in (their workaround: open the site in Safari for ~10 min); blocking is reliable in Safari only, not Chrome/Firefox/Brave/Arc; their fix is an Allow List mode (block everything except picked apps). Ideas for Spots: tell people to block other browser apps too; check whether Screen Time's web content filter (`WebContentSettings`) accepts plain domain names, which could block youtube.com automatically when YouTube is picked (answered 2026-11-23 under question 5 below: it does, but it turns off Safari private browsing and may not cover Safari). Apple's `FamilyActivityPicker` lists many websites next to the apps, which makes it hard to pick just the few things you want. Blocking sites matters (youtube.com is the obvious way around a blocked YouTube app), but how many should we block, and how?
  - **What the code does now:** `SharedStore.shield` blocks the apps, app categories and individual websites you pick. Picking a category blocks its apps only. Its websites stay open, because `shield.webDomainCategories` isn't set.
  - **Questions to settle:**
    1. Should picking an app also block its main website (YouTube → youtube.com)? Tokens don't carry names, so we can't pair them automatically. The user would have to pick both, or we'd prompt them to.
    2. Should picking a category also block that category's websites (`shield.webDomainCategories`)? That's broader and catches more ways around the block, but could also block sites people need.
    3. ~~Is there a cap on how many websites a shield can hold?~~ Answered 2026-11-23 from Apple's docs: yes, 50. Spots already keeps 50 of each kind (`BlockRules.maxPerKind`).
       - Apple's `ShieldSettings` pages say: "Your app can shield up to 50 web domain tokens at once" (`webDomains`), "up to 50 application tokens" (`applications`), and "up to 50 category tokens" for both `applicationCategories` and `webDomainCategories` (each also allows up to 50 exceptions, which Spots doesn't use). So a picked category counts once against the app-category cap and once against the website-category cap, and both are fine at 50.
       - Apple doesn't say what happens past 50. Developers on Apple's forums report that 51 or more blocks nothing of that kind and the property reads back as `nil` (iOS 16 and iOS 17.2, thread 733361). That's why Spots keeps 50 rather than letting the extra ones through.
       - One forum post (thread 733361) says the 50 counts across all of an app's stores, not per store. Spots uses only the default store, so this doesn't matter for now. An Apple engineer separately said an app can have at most 50 stores (thread 804684).
       - Sources: [webDomains](https://developer.apple.com/documentation/managedsettings/shieldsettings/webdomains-swift.property), [applications](https://developer.apple.com/documentation/managedsettings/shieldsettings/applications-swift.property), [applicationCategories](https://developer.apple.com/documentation/managedsettings/shieldsettings/applicationcategories-swift.property), [webDomainCategories](https://developer.apple.com/documentation/managedsettings/shieldsettings/webdomaincategories-swift.property), forum threads [733361](https://developer.apple.com/forums/thread/733361), [730444](https://developer.apple.com/forums/thread/730444) (the web content filter, said to stop at 49 on iOS 16.4) and [804684](https://developer.apple.com/forums/thread/804684). Context7 had nothing on the limit.
       - Not checked: what really happens past 50 on a current iOS (reports stop at 17.2), and whether the cap counts across stores. Both need the paid build on the iPhone. See the next known issue for a way Spots can go over 50 today.
    4. Can onboarding steer people to a short list? For example: "pick your 3–5 worst apps and their websites."
    5. ~~Does Screen Time's web content filter take plain domain names?~~ Answered 2026-11-23 from Apple's docs and forums: yes. `WebDomain(domain: "youtube.com")` makes a website from plain text, with no picker token, and `store.webContent.blockedByFilter = .specific(domains)` blocks it. Whether it's worth using is open, because of what it costs:
       - **What Apple's docs say.** `init(domain:)`: "Provide a high-level domain, such as `example.com`", but also "To protect a family's privacy, use init(token:) instead." The filter has four settings: `.none`, `.specific(domains)` (block these), `.auto(domains, except:)` (adult sites plus these) and `.all(except:)` (every site but these). iOS 15 and later. It takes up to 50 blocked sites and 50 exceptions. Apple lists this 50 separately from the shield's 50 websites; whether they share one count isn't said.
       - **It turns off Safari private browsing.** Apple's docs: "Setting any filter policy besides `.none` will disable Safari private browsing." An Apple engineer confirmed there's no workaround (thread 729808). People would notice this, so it's a product call.
       - **Which browsers: unclear, maybe not Safari.** Apple doesn't say. One developer (thread 805209, iOS 26, October 2025, no Apple reply) says `.specific` blocked sites in Chrome and Firefox but not in Safari, while `.all(except:)` did block in Safari. They also say a site already open in Safari kept loading, even after a refresh, until Safari was quit and reopened. So the earlier guess "likely Safari only" may be backwards. Not confirmed by anyone else.
       - **What a blocked site looks like.** Not Spots' shield. Reports describe the browser's own "restricted" or "blocked by a content filter" page. Apple doesn't document it, or say whether that page has any way to allow the site. That matters because Spots has no unlock button.
       - **Not documented:** whether `youtube.com` also covers `www.youtube.com` and `m.youtube.com`, and whether it needs anything beyond the Family Controls entitlement and the individual (not child) authorization Spots already has.
       - **It still can't pair a site with a picked app.** Tokens don't carry names, so Spots can't tell YouTube was picked. It would need its own list (for example "Also block these sites: youtube.com, instagram.com, tiktok.com") that people tick. Those names stay on the phone.
       - **To try it in the paid build:** in `SharedStore.shield`, set `store.webContent.blockedByFilter` to `.specific` with the ticked domains (or `nil` when there are none). Unlocking already calls `store.clearAllSettings()` (`ShieldManager`), which should clear the filter too. The sites would count toward loosening rules like any other pick: adding one applies at once, removing one waits 24 h. Then on the iPhone, check: Safari, Chrome and Firefox; a site already open versus a new tab; `www.` and `m.` addresses; what the blocked page shows and whether it lets you in; that private browsing is gone; and that unlocking at a place opens the sites again.
       - **Recommendation:** not before launch. It's worth one test build afterwards, since Chrome and Firefox are the usual way around Safari-only blocking. Whether to give up private browsing, and which sites to list, is your call.
       - Sources: [WebContentSettings](https://developer.apple.com/documentation/managedsettings/webcontentsettings), [blockedByFilter](https://developer.apple.com/documentation/managedsettings/webcontentsettings/blockedbyfilter-swift.property), [FilterPolicy](https://developer.apple.com/documentation/managedsettings/webcontentsettings/filterpolicy), [WebDomain init(domain:)](https://developer.apple.com/documentation/managedsettings/webdomain/init(domain:)), forum threads [729808](https://developer.apple.com/forums/thread/729808) (private browsing, Apple engineer), [805209](https://developer.apple.com/forums/thread/805209) (Safari not blocked), [747783](https://developer.apple.com/forums/thread/747783) (blocking a typed-in domain) and [730444](https://developer.apple.com/forums/thread/730444) (said to stop at 49 on iOS 16.4). Context7 had nothing on `WebContentSettings`.
       - Not checked on the iPhone: everything above except what Apple's docs say.
- **Swapping picks at the cap can go over 50 (seen 2026-11-23, reading the code).** The picker keeps 50 of each kind, but after the first day removals wait 24 h (`BlockRules.holdingRemovals`), and that runs after the cap. So someone with 50 websites who swaps 10 for 10 new ones has 60 in the shield until the old 10 drop off. If the forum reports are right (51 or more blocks nothing of that kind), all their websites unblock for a day, which breaks "loosening waits 24 h". The same goes for apps and categories. Not tried on the iPhone. Options: cap the shield, not just the picker, keeping the 50 already blocked and holding back new picks until room frees up (recommended: nothing unblocks early, though new picks wait); or refuse a pick that would go over 50 while removals are waiting. Both change what people see, so the choice is yours.
- **Leaving with the app killed didn't lock in the Simulator (2026-11-19).** After `simctl terminate`, iOS didn't relaunch the app for the exit within 2 minutes; opening the app caught up and locked. Likely a Simulator limit, so test force-quit + walk out on the iPhone.
- **Place search loads forever (seen 2026-11-10, Simulator, on plane Wi-Fi).** Typing in Add place shows "Searching…" and never shows results.
  - Logs show the 8 s "slow connection" message firing. About 50 s later Apple's completer failed with `MKErrorDomain error 1` (`MKError.unknown`).
  - In that session the Simulator never got a single successful response (no "Search results" log line).
  - The same search from a Mac command-line script did work (Smith Hall in about 10 s), and plain HTTPS took about 2.3 s per request. So the network was slow but up.
  - **Cause not confirmed.** It's probably the plane network: the Simulator's maps service (`geod`) requests stalled until they timed out. It could also be specific to the Simulator or to `MKLocalSearchCompleter`.
  - **Next steps:**
    1. Retest on normal Wi-Fi, both in the Simulator and on the iPhone.
    2. ~~If it still fails, log the completer's lifecycle and try a plain `MKLocalSearch` request when the user submits.~~ Done 2026-11-23, without waiting for step 1.
       - Pressing Search on the keyboard now takes the top suggestion only if it's for exactly what's typed. If Apple's type-ahead hasn't answered yet, found nothing or failed, it runs one plain search for the text instead and moves the pin to the top match. If that fails too, the message under the field says why. The choice is in `PlaceSearchRules` (`Models/PlaceSearchRules.swift`, with tests).
       - A plain search that comes back after you've changed or cleared the text is ignored, and typing cancels it.
       - The log now shows each step with timings: "Search asked", "Search results: N after 1.2s", "Search failed after 50.3s: MKErrorDomain 1: …", "Search slow", "Search cleared while waiting" and "Search direct: …". The text stays private.
       - Untested on plane Wi-Fi or any slow network, so it's not known yet whether the plain search gets through when the type-ahead stalls. Not tried on the iPhone. Next time it happens, press Search and send the log.
       - Fixed 2026-11-23 (night review): when the plain search found nothing, "No matches" showed but the spinner kept going, and 8 s later the slow-connection message replaced it. Every answer from the plain search now stops the spinner (tested in `PlaceSearchTests`).
    3. ~~Either way, stop the spinner once the slow message shows, so the screen doesn't look stuck.~~ Done 2026-11-12. Results that arrive late still show.
    4. If Apple search stays unreliable, consider Google Places (see above).

## Next
1. **Test on the iPhone.** Walk into a saved place and confirm the apps unlock on their own (the arrival event can take a minute or two). Walk about 300 m away and confirm they lock within a few minutes. Also test with an Xcode `.gpx` route.
2. **Camera check (MobileCLIP): on hold (2026-11-10).** Unlocking is automatic now, so the scan only matters for "unlock with friends anywhere" and verified lock-ins. We'll revisit after real blocking works. The earlier plan is under "On hold: camera scan" in Plan.md.
   - Validate it first with a Mac webcam script.
   - Then build video scan enrollment and unlock on the phone.
   - Unlocking is now automatic, so the scan would be an opt-in per place ("Scan" places get an arrival notification that opens the camera). Auto places stay zero-tap.
3. **Modes from the original notes:**
   - ~~GPS-only unlock places~~ done, this is now the default. Not built yet: always-blocked study spots (Smith Hall, Gates Hall). Apps are already blocked everywhere else, so these only matter for the Lock In stretch goal.
   - Scan-only unlocks anywhere, e.g. "with friends" unlocks, while notes or a class setting keeps apps blocked.
4. **Paid program → real Screen Time blocking** (steps above).
