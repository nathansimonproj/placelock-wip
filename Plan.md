# Cove (PlaceLock): apps stay blocked except at the places you choose

Rewritten 2026-11-23 to match what's built. [Roadmap.md](Roadmap.md) has the dated record of each change, what's untested and what's next. [README.md](README.md) has build steps.

## The idea
Today you block and unblock apps by hand. The idea (see **Original notes** at the end) is to let **where you are** decide instead.

- You pick the apps that distract you and the places where they're allowed, like the gym or home.
- The apps are **blocked by default**, everywhere.
- When you **arrive** at one of your places, they unblock on their own. When you **leave**, they block again. Both happen in the background, even with Cove closed.
- There's **no unlock button**, and no timer. You stay unlocked until iOS says you've left.
- After the first day, anything that loosens the rules **waits 24 h**, so you can't add a place where you're standing to get around a block.

The first design (2026-11-10) unlocked only when you tapped Unlock, passed a GPS check and panned the camera around the room. Unlocking became automatic the same day, and the camera scan is on hold (see **On hold: camera scan**).

Platform: iPhone, Swift/SwiftUI, iOS 17+. The app is called Cove; the code, Xcode project, bundle IDs (`com.nsimon.PlaceLock`, `.Shield`) and App Group (`group.com.nsimon.PlaceLock`) keep the PlaceLock name, because renaming them would make iOS treat it as a new app.

## Key platform facts (these shape the design)
- **Blocking has to use the Screen Time API.** `FamilyControls` gives the permission and Apple's app picker. `ManagedSettings` applies the "shield" that blocks apps.
  - It needs the `com.apple.developer.family-controls` entitlement. Free Personal Teams can't have it, so the free build simulates blocking (see **Two builds**).
  - The App Store needs Apple to approve a separate Family Controls **distribution** request. It was filed 2026-11-19.
  - The real block screen only shows on a real iPhone.
- **App choices are opaque tokens.** `FamilyActivityPicker` returns tokens, never app names or bundle IDs. They only work on the phone that made them, so they're never synced.
- **iOS shields at most 50 apps, 50 categories and 50 websites.** Cove keeps 50 of each (`BlockRules.capped`).
- **Places are watched by Core Location geofencing.** `CLMonitor` (iOS 17+) watches a circle for every saved place, up to 20 (iOS's limit). iOS wakes Cove when you cross one, even if it isn't running.
  - This needs **Always** location and **Precise Location**. Without Precise, iOS doesn't watch circles at all.
  - On iOS 18+, Cove holds a `CLServiceSession` asking for Always, recreated on every launch, including background ones. Without it, iOS treats `CLMonitor` events as When In Use and arrivals wait until the app is opened.
  - **Leaving is slow.** iOS usually notices once you're 100–200 m past the edge, and it can take a few minutes. Places can be 50–500 m across; below 100 m Add place warns that indoor location fuzz can miss you arriving.
- **Significant-change wakes are the safety net.** iOS also wakes Cove every time you move about 500 m, even after a force-quit. Cove then re-reads iOS's state for every place, which catches an exit iOS noticed but didn't deliver. A late exit still waits for iOS.
- **iOS doesn't wake an app for a permission change.** If location is turned off while unlocked and Cove isn't opened, apps stay unblocked. This is accepted for now (Roadmap, Known issues).

## How locking works
**One decision, one function.** `LockRules.decide` (`Models/Rules.swift`) takes the places, the current unlock (if any), iOS's reading for each place (inside, outside or unknown), whether Cove has Always with Precise, and the time. It returns one of: stay locked, stay unlocked, unlock at a place, move to another place, or lock with a reason.

- Without Always and Precise, nothing may stay unlocked: iOS can't wake Cove when you leave.
- Locked: unlock if iOS says you're inside a place that's active (not still waiting out its 24 h).
- Unlocked: lock only on a definite "outside" for that place. Unknown readings are ignored.
  - If you're still inside another active place, the unlock moves there instead of locking.
  - If the place was deleted, lock.

**`AppModel.reconcile()` gathers the inputs and applies the result.** It runs after every geofence event, on launch, when the app comes to the front, on each significant-change wake, and when places change. Background wakes ask iOS for extra time so it can finish.
- It syncs the watched circles first, then reads iOS's states. Each circle's identifier carries its center and radius (`GeofenceKeys`), so keeping iOS in step is a plain set difference and an unchanged circle is never removed and re-added.
- After a restart, it waits for the first unlock of the phone before loading anything, so it can't save empty data over the real data.

**What you see.**
- Notifications: "At Gym, apps unblocked." and "Left Gym, apps blocked." Each replaces the last, and old ones are cleared after 5 minutes.
- Home shows Locked or Unlocked, the places where apps open, and "Apps block again when you leave." while unlocked.
- The block screen (the Shield extension): "Instagram is locked", "Estimated @ Suzzallo Library · 2 min ago" and "Opens at Gym, Soccer Field or Home." The block screen can't read location, so Cove saves its last guess for it after each check (`Location/Estimate.swift`). The guess is the saved place you're in, Apple Maps' name for the spot, or "400 m from Gym", and it's hidden after a day.
- Each unlock is kept as a visit on the phone for two weeks (`Models/Visit.swift`) and as a `sessions` row in the backup.

## Loosening waits 24 h
These keep a block from being undone on a whim. The logic is in `PlaceRules` and `BlockRules`, with tests.

- **Setup window.** The first 24 h after install (`setupEndsAt`) has no delays, so setup is instant. "Finish setup now" on the Settings tab ends it early. The end time is backed up, so a reinstall doesn't reopen it; if the phone and server disagree, the earlier end wins.
- **New places** start working 24 h after they're added (`Place.activeAfter`).
- **Moving or enlarging a place** waits 24 h (`Place.pendingChange`). The old circle keeps working until then.
- **Removing a blocked app** keeps it blocked for 24 h, with an "Unblocks in 23 h" badge. Tapping Keep blocked cancels it.
- **Stricter changes apply at once:** renaming, shrinking or deleting a place, and adding apps.
- When a wait ends, a notification says so ("Library is now on your allowlist"). Launches and geofence events apply anything that's come due.

## Permissions
First-run setup (`Views/OnboardingView.swift`) asks for each one after explaining why: location (Always), Screen Time access (paid build), apps, places, notifications. Each step can be skipped, and Home's setup card catches what's left.

- **Location.** Without Always and Precise, apps stay locked. Losing either locks as soon as Cove runs: right away if it's open, otherwise the next time it's opened. Home's banner names the problem and its Fix button shows iOS's prompt or opens Settings (`PermissionRules`).
- **Screen Time access.** iOS removes every block when it's turned off, so Cove can only warn: a notification and a "Blocking is off" banner on Home.
- **Notifications** are optional. Blocking works without them.

## Two builds
| | Free (`xcodegen generate`) | Paid (`xcodegen generate --spec project-paid.yml`) |
| --- | --- | --- |
| Team | Free Personal Team | Paid team |
| App picker | Stand-in list of common apps | Apple's `FamilyActivityPicker` |
| Blocking | Simulated: logged and shown in the app | Real shields through `ManagedSettingsStore` |
| Opening a blocked app | A mock block screen in the app | The Shield extension's block screen |
| Storage | `UserDefaults.standard` | The App Group, shared with the extension |
| Screen Time setup step | Skipped | Shown |

Everything else is real in both: places, geofences, the 24 h delays, notifications and backup. The switching lives behind `#if SCREEN_TIME` in `Blocking/ShieldManager.swift`, the picker in `Views/RootView.swift` and `Shared/SharedStore.swift`, so check both builds after any change there.

## Code layout
```
PlaceLock/
  project.yml, project-paid.yml       # XcodeGen specs. The project, Info.plists and entitlements are generated.
  PlaceLock/
    App/        PlaceLockApp, AppModel (gathers inputs, applies decisions), Storage, Log, Scenario (Debug only)
    Models/     Rules.swift (LockRules, GeofenceKeys, PlaceRules, BlockRules), Place, Visit, SavedData,
                PermissionRules, PlaceSearchRules, SpokenRules, AboutRules, DefaultPlaces (empty)
    Location/   LocationService (permission, CLServiceSession, significant changes), GeofenceMonitor (CLMonitor),
                PlaceSearch (Apple Maps search), Estimate (the block screen's "Estimated @")
    Blocking/   ShieldManager, BlockList
    Shared/     SharedStore (also compiled into the extension), Brand
    Sync/       SyncRules, SyncEngine, SyncBackend, SyncRecords
    Views/      Home, Settings tab (RulesView), Add place, Onboarding, Backup, Debug, Theme, stand-ins for the free build
  Extensions/Shield/                  # paid build only: the block screen
  PlaceLockTests/                     # Swift Testing, one file per rules type
  supabase/                           # migrations and the local check
  scripts/                            # verify.sh, geofence-scenario.py, archive.sh, bump-build.sh
```
Decisions are pure functions in a rules type with unit tests. `AppModel` and the views only gather inputs and apply results.

## Backend (Supabase)
**The rule: the phone decides blocking, the server keeps records.**
- **Phone:** keeps a local copy of everything enforcement needs and works fully offline. A missing network connection must never stop a lock.
- **Server:** stores profiles, places and history, restores them on a reinstall and, later, a new phone. Later it could power friends and leaderboards.
- **Sync:** local changes queue in an **outbox** and upload when the phone is online. The newest edit wins.

The schema is in `PlaceLock/supabase/migrations/`. Checks run against a throwaway local Postgres with `PlaceLock/supabase/local-check/run.sh`.

**Accounts: anonymous first, Apple later.**
- **First launch:** the app quietly calls `signInAnonymously()`. There's no sign-in screen, and it works on the free team.
- **Linking Apple (not built):** `linkIdentityWithIdToken` keeps the same `auth.users` id, so nothing has to migrate. It needs the paid team.
- **Until then:** a reinstall on the same phone usually keeps the account, because the session is stored in the Keychain. A new phone can't restore.
- **Delete account:** Settings tab › Backup › Delete account calls `delete_my_account()`, which deletes every row. Places and blocked apps stay on the phone, and blocking keeps working.

**What lives where.**
| Data | Server | Phone | Notes |
|---|---|---|---|
| Profile | ✅ | cache | `profiles`. Username stays empty until social features ship. |
| Setup window end (`setupEndsAt`) | ✅ | ✅ | On `profiles`, so a reinstall doesn't reopen the 24 h no-delay window. Earliest end wins. |
| Places, with `activeAfter` and `pendingChange` | ✅ | ✅ enforcement copy | `places`. The 24 h delays sync along with the place. |
| Unlock history | ✅ | written here first | `sessions`, `kind` = `unlock`. `lock_in` is reserved for Lock In (Later). |
| Blocked-app selection | ❌ | ✅ only | Apple's tokens only work on the phone that made them. Pick apps again on a new phone. |
| Active unlock | ❌ | ✅ only | Background enforcement can't wait on the network. |

**Sync rules.** The schema enforces these:
- **IDs:** rows are created on the phone with their own UUIDs. Uploads are idempotent upserts.
- **Newest edit wins:** each row carries `updated_at`, the time of the edit on the phone. A trigger skips any upsert older than the stored row, so the order uploads arrive in doesn't matter.
- **Deletes:** they set `deleted_at` (a tombstone) instead of removing the row. Hard deletes aren't granted.
- **Pulling:** `synced_at` is server time, stamped on every applied write. A phone asks for rows newer than its last pull.
- **Access:** row-level security means each user reads and writes only their own rows. Logged-out clients get nothing.

**Phone side (`PlaceLock/Sync/`).**
- `SyncRules`: the pure logic (outbox, place diff, merge, setup window, error kinds), tested in `SyncRulesTests`.
- `SyncEngine`: each pass runs sign-in → pull → setup window → flush. Passes run on launch, on foreground, when the network returns and after any local change, and retry with backoff from 5 s to 5 min. It's never on the lock path. A row the server rejects for good is dropped and logged, so it can't block the queue. Tested with a fake backend in `SyncEngineTests`.
- `SyncBackend`: every Supabase call, behind a protocol.
- Config is `SupabaseURL` and `SupabaseKey` in Info.plist, set in `project.yml`. Without them, and under unit tests, sync does nothing.

**Trust.** The server only knows what the phone tells it. That's fine for personal history and friend leaderboards. Anything public would need server-side checks.

## Tried and dropped
- **Tap Unlock and scan the room (2026-11-10).** Replaced by automatic unlock. The scan is on hold below.
- **Blocking through Shortcuts automations.** One automation per app was too much setup, the app could flash before the block, and turning off the automation got around it.
- **8 h safety cap and 8 h GPS recheck (removed 2026-11-19).** A Device Activity extension re-blocked apps 8 h after each unlock, and the app took a fresh GPS fix. At home overnight the fix could fail indoors and lock you out until you left and came back. Cove clears any leftover cap schedule at launch.
- **Lock until I leave (removed 2026-11-22).** A button to lock now and not unlock again until you left. Removed to get automatic unlock and lock solid first; it also had two bugs.
- **Starter places (2026-11-10 to 2026-11-12).** New installs start with no places and add their own during setup.

## Later
- **A backstop for turning location off while unlocked.** A Device Activity schedule that blocks if Cove is unlocked but has lost Always or Precise. Options and costs are in Roadmap, Known issues; the decision is open.
- **Websites.** Whether to block a picked app's website or a category's websites, and whether to use Screen Time's web content filter for plain domains. Questions and findings are in Roadmap, Known issues.
- **Sign in with Apple**, so places restore on a new phone.
- **Study Spots and Lock In.** A second kind of place that's always blocked (`places.kind` = `study` in the schema already), like Smith Hall or Gates Hall from the original notes. At one, tapping **Lock In** starts a session that ends when you leave or tap End.
  - **Verified:** a session counts as verified if it started inside the spot, ended by leaving or End (not by a crash or lost permission), kept Always the whole time and lasted at least 25 minutes. Without the camera scan, "started inside" is GPS only.
  - **Stats**, kept on the phone: verified hours today, this week and all time, per-spot totals, and a streak of days with a verified session. `AppModel.visits` already keeps two weeks of visits for this.
  - **Share card:** a 9:16 image ("Locked in 3h 41m · Suzzallo · ✓ Verified · 🔥 9-day streak") made with `ImageRenderer` and shared with `ShareLink`. Spot name only, never coordinates, and it can be hidden. It's just an image, so the badge can't be proven to anyone else without the server.
  - Optional: a shield action extension that counts taps on the block screen ("Resisted Instagram 14×"). Check first that it can write to the App Group. `DeviceActivityReport` data can't leave its extension, so don't rely on it.
- **Social.** A `friendships` table and friend-only policies: a "locked in now" board, weekly streaks and leaderboards for small groups, and share cards with a short link to a server record. Only session start and end, the spot ID and the verified flag would be uploaded. Location shown at building level only, opt-in and friends-only, with a ghost mode.

## On hold: camera scan
On hold since 2026-11-10. Unlocking is automatic now, so a scan would only matter for "unlock with friends anywhere" (from the original notes), as an extra check on Lock In, or as an opt-in per place ("Scan" places get an arrival notification that opens the camera; other places stay zero-tap). We'll revisit after real blocking works on the iPhone. Nothing here is built.

**The idea.** You hold up the phone and slowly pan around. The live video is compared with what the place looked like when you added it. GPS alone can't tell your desk from your bed in the same building, and a single photo is easy to fake; together they're harder to fool.

**The pieces.**
- **Model:** Apple's MobileCLIP-S0 image encoder as a Core ML model (`huggingface.co/apple/coreml-mobileclip`), about 1.5 ms per image on an iPhone 12 Pro Max. Apple's `ml-mobileclip` repo has a sample app (`ios_app/MobileCLIPExplore`) with the pixel-buffer preprocessing, embedding and cosine similarity code to port. The text encoder is left out.
- **Camera:** `AVCaptureVideoDataOutput` feeds frames straight to the encoder at about 8 per second. Nothing is recorded or saved.
- **Motion:** `CoreMotion` attitude tracks how far you've turned. It drives a "keep turning" ring and makes sure a scan covers the room, not one view.
- **Adding a place:** a 10–20 s sweep of about 270–360°. A frame's embedding is kept only if it's different enough from those already kept (cosine below about 0.92), leaving about 20–60 per place. Only embeddings are stored, on the phone only; restored places would come back as "needs a sweep". A short second pan checks the place matches itself. "Add another sweep" later (at night, lights on) helps with lighting.
- **Checking:** each frame scores its best match against the place's embeddings. A scan passes within 15 s if about 60% of frames match (starting threshold about 0.75), the matches cover at least about 90° of turning, and at least about 12 frames match. It fails on timeout or a run of clear misses. All of these numbers need tuning in real rooms with a live score graph.
- **Spoofing:** needing matches across a real pan already beats a photo held up to the camera. Later, checking that the picture changes the way the gyro says the phone moved would also beat a video played on another screen.

**Steps if it comes back.**
1. Check it with a Mac webcam script first.
2. Add the model and port the preprocessing and embedding code. Build the camera and motion pieces and a Debug screen with a live score graph against a place.
3. Build the sweep for adding a place and the pass/fail rules, as a rules type with tests using made-up score and angle streams: pass, timeout, too little turning, a single still view.
4. Hook it into arrivals for opt-in places, then tune the numbers in real rooms.
5. On the iPhone: the right room passes; another room in the same building fails; a photo of the room without panning fails; the right room with GPS somewhere else fails.

## Testing
- **Unit tests** (Swift Testing, `PlaceLock/PlaceLockTests/`) cover every rules type: lock decisions, geofence keys, the 24 h delays and setup window, blocked-app holds and the cap, permissions, place search, spoken text, saved-data loading, the block screen estimate, About links, and sync (rules and engine).
- **`PlaceLock/scripts/verify.sh`** runs the tests, compiles the paid build and checks migrations when `supabase/` changed. `--screens` takes Simulator screenshots, `--large-text` also at the largest text size, and `--release` checks no Debug code is in the paid Release build.
- **`PlaceLock/scripts/geofence-scenario.py --all --build`** walks the Simulator in and out of places (arrive and leave, background, moving between places, relaunching inside, a place still waiting, walking out) and checks unlock and lock from the app's log.
- **Debug builds** have Pretend I'm at (fake inside/outside readings fed into the same `reconcile()`), Skip 24 h wait, and launch arguments to open any screen (listed in README).
- **Only the iPhone can show** the real block screen, iOS relaunching Cove after a force-quit, real exit timing and indoor GPS drift, and battery use. Roadmap lists what's still to try there.

## Original notes
**Top level:** app blocking based on user location rather than manual block/unblock.

**Two paths:**
1. Query user location on app open → if not on the blocklist, unblock apps.
2. OpenCV pipeline → if at an allowlisted location, unblock apps.

Why not build both?

**Prototype:** driver script.

**App structure:**
- Open app → unblock button → calls the CV script.
- Auto-set unblocks/blocks: e.g. the user sets gym and home as unblock, and Smith Hall and Gates Hall as block. No CV pipeline there, just blocked.
- Additional CV unblocks: e.g. chilling with friends → unblock once CV confirms. If notes, a class setting, etc. are seen → stays blocked.

**Where these stand (2026-11-23):** location-only unblock places are built and are how Cove works. Always-blocked places (Smith Hall, Gates Hall) aren't needed for blocking, since apps are blocked everywhere else already; they'd come back as Study Spots for Lock In. Camera unlocks are on hold.
