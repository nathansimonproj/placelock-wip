# PlaceLock: iOS app that unblocks apps while you're at an allowed place

## Context
Today you block and unblock apps by hand. The idea (see **Original notes** at the end) is to let **where you are** decide instead. Distracting apps are blocked by default. When you arrive somewhere you've allowed and tap **Unlock**, the app checks two things:
1. **GPS:** are you inside one of your saved places?
2. **Video scan:** you hold up your phone and slowly pan around the area. Does the live video match that place? This runs on the phone with **MobileCLIP**. There are no photos to take, either here or when you set up a place. Both are the same "scan the area" gesture.

If both pass, the chosen apps **stay unblocked as long as you're there**. They **lock again automatically when you leave**.

GPS alone can't tell your desk from your bed in the same building, and a photo alone is easy to fake. Requiring both is the "extra layer of confidence" from your notes.

Platform: iPhone, Swift/SwiftUI. Greenfield. The project goes in `~/Desktop/wip/PlaceLock/`.

## Key platform facts (these shape the design)
- **Blocking on iOS has to use the Screen Time API.** It is made of `FamilyControls` (permission plus the app picker) and `ManagedSettings` (applies the "shield" that blocks apps). `DeviceActivity` is used only for a safety cap, described below.
  - These need the `com.apple.developer.family-controls` entitlement. Development builds work on your own iPhone with that entitlement. App Store release needs Apple to approve a separate distribution request, so file it early.
  - It must be tested on a **real device**. The simulator doesn't actually shield apps.
- **App choices are opaque tokens.** `FamilyActivityPicker` returns `ApplicationToken`s, never app names or bundle IDs. We store the encoded `FamilyActivitySelection` in a shared App Group so every target can read it.
- **Locking when you leave uses Core Location geofencing.** We use `CLMonitor` (iOS 17+) with a `CircularGeographicCondition` for the unlocked place. When you exit, iOS wakes the app in the background, even if it isn't running, and the app writes the shield back into `ManagedSettingsStore`.
  - This requires **"Always" location permission** and the `location` background mode.
  - **Exit timing is approximate.** iOS usually fires the exit event once you're about 100–200 m past the edge, and it can take a few minutes. That's fine for "left the library", but not instant. So the place radius has a 100 m minimum.
  - To keep the monitoring battery-friendly, only the place you're currently unlocked at is monitored, and it stops once it locks again.
- **A safety cap covers missed exit events.** These can happen if Location is turned off, permission is revoked, or the phone reboots. A `DeviceActivity` schedule with a max session length (default 8 h, configurable per place) re-locks from its monitor extension when the time runs out. If you're still there, you just scan again. Also:
  - If location permission drops below "Always", the app locks immediately.
  - On every launch, the app checks that you're still inside the place you unlocked at, and locks if you aren't.
- **The scan is video, processed live and never recorded.** `AVCaptureVideoDataOutput` sends camera frames straight into the encoder. At about 1.5 ms per frame, sampling 5–10 frames per second is easy, with plenty of headroom.
  - `CoreMotion` (`CMDeviceMotion` attitude) tracks how far you've panned. It drives the "keep turning" coverage ring and makes sure a scan actually covers the area rather than one view.
- **Which MobileCLIP model:** use the **MobileCLIP-S0 image encoder** Core ML model from `huggingface.co/apple/coreml-mobileclip`. It takes about 1.5 ms per image on an iPhone 12 Pro Max. It comes from Apple's `ml-mobileclip` repo, whose `ios_app/MobileCLIPExplore` sample already has pixel-buffer preprocessing, image-embedding code and `cosineSimilarity`. Port those pieces rather than writing them from scratch. The text encoder is left out of the MVP.

## Architecture
```
PlaceLock/
  project.yml                        # XcodeGen spec (xcodegen 2.x is installed)
  PlaceLock/                         # main app target (background mode: location)
    App/PlaceLockApp.swift           # on launch: restart CLMonitor, verify session still valid
    Models/Place.swift               # id, name, lat/lon, radius (>=100m), [ref embeddings], threshold, maxSessionHours
    Models/UnlockSession.swift       # active placeID + startedAt (persisted in App Group)
    Store/SharedStore.swift          # App Group JSON: places, FamilyActivitySelection, active session
    Blocking/ShieldManager.swift     # ManagedSettingsStore: lock() / unlock(), auth request
    Location/LocationService.swift   # one-shot fix + accuracy check, Always-auth handling
    Location/GeofenceMonitor.swift   # CLMonitor: watch active place; on .unsatisfied -> lock + end session
    Blocking/SessionCap.swift        # DeviceActivityCenter schedule = max session length (safety net)
    Vision/CLIPEncoder.swift         # Core ML MobileCLIP image encoder -> normalized [Float]
    Vision/PlaceMatcher.swift        # per-frame max cosine sim vs place references
    Vision/KeyframeSelector.swift    # enrollment: keep only frames that add new visual info
    Camera/VideoScanner.swift        # AVCaptureSession + VideoDataOutput -> throttled frame stream (~8 fps)
    Camera/MotionTracker.swift       # CoreMotion yaw/pitch -> sweep coverage (degrees covered)
    Scan/ScanSession.swift           # shared sweep engine: frames + motion -> enroll result or match verdict
    Unlock/UnlockCoordinator.swift   # fuse GPS + video scan -> start session
    Views/ OnboardingView (Screen Time + Always location), PlacesListView,
           AddPlaceView (map + enrollment sweep), AppPickerView,
           ScanView (full-screen camera + coverage ring + match meter),
           StatusView ("Unlocked at Library, locks when you leave"), DebugScoresView
    Resources/mobileclip_s0_image.mlpackage
  DeviceActivityMonitorExt/          # intervalDidEnd -> lock (safety cap only)
  ShieldConfigurationExt/            # custom shield screen ("Go to an allowed place and scan to unlock")
```
All three targets get the Family Controls entitlement and the same App Group.

## Unlock flow
1. Apps are **locked by default**. On first launch and whenever there's no active session, `ShieldManager.lock()` applies the shield from the stored selection.
2. The user taps **Unlock** in the app, or opens it from the shield screen.
3. `LocationService` gets one location fix. It is rejected if `horizontalAccuracy` is worse than 100 m. Then we find saved places where the distance is less than or equal to radius + accuracy.
   - No candidate place: deny with the message "Not at an allowed place".
4. **Video scan.** `ScanView` opens the camera full-screen and asks you to "Slowly pan around the room".
   - Each sampled frame (about 8 fps) is encoded. `PlaceMatcher` scores it as the best similarity against the place's reference embeddings.
   - A frame counts as a **match** if its score is at or above the place's threshold.
   - Each match is tagged with the current yaw angle from `MotionTracker`.
   - On screen, a **coverage ring** fills as you turn, and a **match meter** fills as matching frames pile up.
5. **Decision:** the scan **passes** when, within a 15 s timeout, all three of these hold:
   - At least about 60% of the sampled frames match.
   - The matching frames cover a pan of at least about 90° (configurable).
   - At least about 12 frames match.

   It **fails** on timeout, or if too many frames in a row clearly don't match. Unlock only if the GPS check passed **and** the video scan passed.
   - Requiring matches across a real pan also makes it hard to fool with a single photo held up to the camera.
   - The default per-frame threshold is around 0.75. We tune it and the pass rules with `DebugScoresView`, which shows a live per-frame score graph, because MobileCLIP frame-to-frame cosine scores for "same room" versus "different room" need real-world calibration.
6. **On success:**
   - `ShieldManager.unlock()` clears the shields and an `UnlockSession` is saved.
   - `GeofenceMonitor` starts watching that place's circle.
   - `SessionCap` starts the max-length safety schedule.
7. **You stay unlocked while you're there.** There's no timer and no re-scan during the visit.
8. **When you leave:**
   - The `CLMonitor` exit event fires.
   - `ShieldManager.lock()` blocks the apps again.
   - The session is cleared, and the monitor and cap are stopped.
   - A local notification says "Left Library, apps locked".
9. **When you come back,** you need to scan once again for that visit. This stops someone from unlocking by passing near the place without actually being in it.

## Enrolling a place
In `AddPlaceView` you:
- Drop a pin, which defaults to your current location, and set a radius (100–500 m).
- Name the place and set its max session length.
- **Do an enrollment sweep.** Hold up the phone and slowly pan around the space for about 10–20 s. The coverage ring guides you to about 270–360° and prompts you to tilt up and down a bit.
  - Frames stream through the encoder at about 8 fps.
  - `KeyframeSelector` keeps a frame's embedding only if it's different enough from the ones already kept (cosine below about 0.92 against all of them). That leaves roughly 20–60 varied embeddings, stored as `[Float]` (512-d).
  - **No images or video are ever saved.** Only the embeddings are stored.
- After the sweep, a quick **self-check** runs a second short pan to confirm the place matches itself well, then saves.
- **"Add another sweep"** later (at night, or with the lights on) adds more embeddings to the same place. This makes it hold up better to lighting changes.

## Build order (each step can be tested on its own)
1. **Scaffold.** Write `project.yml` with 3 targets, the App Group, entitlements and the location background mode. Run `xcodegen`, then build.
2. **Blocking only.** Add the authorization request, `FamilyActivityPicker` and manual Lock/Unlock buttons. Check on the device that shields appear and disappear.
3. **Places + geofence lock.** Add place CRUD with a MapKit pin and an unlock gated on GPS only. Add `GeofenceMonitor`, then walk out of the radius and confirm the apps lock again in the background.
4. **Safety cap.** Add the DeviceActivity monitor extension, the auth-revoked lock and the on-launch check that the session is still valid.
5. **MobileCLIP + video pipeline.** Add the model, port preprocessing and embedding from MobileCLIPExplore, and build `VideoScanner` and `MotionTracker`. Build the debug screen that shows a live per-frame similarity graph against a place.
6. **Sweeps.** Build the `ScanSession` engine for both enrollment (keyframe selection) and unlock (pass/fail rules), plus the `ScanView` UI with the coverage ring and match meter.
7. **Fusion.** Write `UnlockCoordinator` combining GPS and the video scan, then calibrate the threshold and pass rules in real rooms.
8. **Polish.** Add the custom shield screen, onboarding, the "locked because you left" notification, and history/stats (optional).

## Stretch goal: verified lock-ins + share cards
Students like to show they're locked in. Most focus apps just take your word for it. PlaceLock can **prove** you were at the library, because it already has GPS plus a video scan. This stretch goal turns that proof into a stat worth sharing. It runs **fully on the device**, with no backend or accounts. Build it after the MVP (build step 9).

**Study Spots (new place type).** `Place` gets a `kind` field:
- `.unlock`: the existing behavior.
- `.study`: an always-blocked place, like Smith Hall or Gates Hall from the original notes.

Study spots are enrolled the same way as unlock places: a pin, a radius and a sweep. Tapping Unlock inside a study spot is denied with "You're at a study spot." If a study spot and an unlock place overlap, the study spot wins.

**Lock In flow.**
1. At a study spot, tap **Lock In**.
2. The app runs the same GPS check and pan scan as an unlock. If both pass, a `LockInSession` starts. Apps stay shielded, and nothing is unlocked.
3. `GeofenceMonitor` watches the study spot, reusing the exit path. Leaving the spot or tapping **End** closes the session.

**What makes a session "Verified".** The badge is computed when the session ends. A session is **Verified** only if all of these hold:
- It started with a passing GPS check and a passing scan.
- It ended by a geofence exit or by tapping End, not by a crash recovery or a revoked permission.
- Location authorization stayed "Always" the whole time.
- It lasted at least 25 minutes.

Two more rules:
- **Unverified sessions** still count toward history, but get no badge.
- **Missed exit events** are covered by the existing on-launch check. If you're no longer inside the spot, the session is ended at the last time you were known to be inside, and it is not Verified.

**Stats (local only).** Completed sessions are stored in the App Group. From them the app computes:
- Total verified hours for today, this week and all time.
- Per-spot totals.
- A **streak**: consecutive days with at least one verified session.
- **Optional:** add a `ShieldActionExtension` that counts taps on the shield during a session, for "Resisted Instagram 14×".
  - First check on a device that this extension can write to the App Group.
  - Don't rely on `DeviceActivityReport` data. It can't leave its extension.

**Share card.** When a session ends, offer a story-sized (9:16) card, for example: "Locked in 3h 41m · Suzzallo · ✓ Verified · 🔥 9-day streak."
- The card is rendered from a SwiftUI view with `ImageRenderer`.
- It is shared through `ShareLink`, which reaches Instagram, Messages and Snapchat.
- A one-tap "Share to Instagram Stories" button is optional. It needs a Meta App ID for the `instagram-stories://` deep link.
- The card shows the **spot name only**, never coordinates or a map.
- Users can hide the spot name, and can pick from a few card styles.
- **Limitation:** the card is just an image, so the badge can't be proven to anyone else yet. Making it checkable needs a backend; see Later.

**New files.**
```
PlaceLock/
  Models/LockInSession.swift       # placeID, start, end, endReason, verified, shieldAttempts
  LockIn/LockInCoordinator.swift   # GPS + scan -> start session; end + compute verified
  Stats/StatsStore.swift           # totals, per-spot hours, streak
  Views/LockInView.swift           # live timer ("Locked in at Suzzallo · 1h 12m")
  Views/ShareCardView.swift        # card layout(s), rendered via ImageRenderer
  Views/StatsView.swift            # history, streak, per-spot totals
ShieldActionExt/                   # optional: count shield taps during a session
```

**Build step 9.**
1. Add `Place.kind` and the Lock In flow, reusing `UnlockCoordinator`'s checks.
2. Add the verified rules and `StatsStore`.
3. Add the share card.
4. Last and optional: add the shield-tap counter.

## Backend (Supabase)
**The rule: the phone decides blocking, the server keeps records.**
- **Phone:** keeps a local copy of everything enforcement needs and works fully offline. A missing network connection must never stop a lock.
- **Server:** owns identity, history and (later) social. It stores profiles, preferences, places and sessions, restores them on a new phone, and will power friends and leaderboards.
- **Sync:** the two sync through an **outbox**. Local changes queue up and upload when the phone is online, and the newest edit wins.

The schema is in `PlaceLock/supabase/migrations/20261111000000_init.sql`. Checks run against a throwaway local Postgres with `PlaceLock/supabase/local-check/run.sh`.

**Accounts: anonymous first, Apple later.**
- **First launch:** the app quietly calls `signInAnonymously()`. There's no sign-in screen, and it works on the free Personal Team.
- **Linking Apple:** later, the user can link Sign in with Apple with `linkIdentityWithIdToken`. The `auth.users` id stays the same, so nothing has to migrate. Sign in with Apple needs the paid team, the same as Screen Time.
- **Until Apple is linked:** a reinstall on the same phone usually keeps the account, because the session is stored in the Keychain. A new phone can only restore once Apple is linked.
- **Deleting the account:** `delete_my_account()` deletes the account and every row that hangs off it. The App Store requires this once accounts exist.

**What lives where.**
| Data | Server | Phone | Notes |
|---|---|---|---|
| Profile (username, display name, avatar, school) | ✅ owns it | cache | `profiles`. Username stays empty until social features ship. |
| Setup window end (`setupEndsAt`) | ✅ | ✅ | On `profiles`, so a reinstall doesn't reopen the 24 h no-delay window. |
| Preferences (notifications, ghost mode, card style) | ✅ owns it | cache | `preferences` |
| Places, with `activeAfter` and `pendingChange` | ✅ | ✅ enforcement copy | `places`. The 24 h delays sync along with the place. |
| Unlock and lock-in history | ✅ | written here first | `sessions`, with `kind` = `unlock` or `lock_in` |
| Blocked-app selection | ❌ | ✅ only | Apple's tokens only work on the device that made them. Pick apps again on a new phone. |
| Place embeddings (stretch) | ❌ | ✅ only | Privacy. Restored places come back as "needs a sweep". |
| Active unlock, paused places | ❌ | ✅ only | Background enforcement can't wait on the network. |

**Sync rules.** The schema enforces these:
- **IDs:** rows are created on the phone with their own UUIDs (`Place.id` already is one). Uploads are idempotent upserts.
- **Newest edit wins:** each row carries `updated_at`, the time of the edit on the phone. A trigger skips any upsert older than the row already stored, so the order uploads arrive in doesn't matter.
- **Deletes:** they set `deleted_at` (a tombstone) instead of removing the row, so they sync like any other edit. Hard deletes aren't granted.
- **Pulling:** `synced_at` is server time, stamped on every applied write. A phone catches up with "rows where `synced_at` > my last pull".
- **Access:** row-level security means each user reads and writes only their own rows. A session can only point at one of its own user's places. Logged-out clients get nothing.

**Phone side (built 2026-11-11, `PlaceLock/Sync/`).**
- `SyncRecords.swift`: the server's row shapes. Nullable columns are always sent, so an upsert can clear them.
- `SyncRules.swift`: the pure logic, unit tested in `SyncRulesTests`.
  - The `Outbox`. The newest version of each row wins, and places upload before sessions.
  - The place diff.
  - The merge: newest edit wins. On the first sync it uploads existing places, and after a reinstall it drops starter places that were seeded again.
  - The setup-window rule: earliest end wins.
  - Error classification.
- `SyncEngine.swift`: the I/O, with each pass running sign-in → pull → setup window → flush.
  - It never sits on the lock path. A failure only retries later.
  - A row the server rejects for good is dropped and logged, so it can't block the queue.
- `AppModel` hooks in at three points:
  - Place edits go to the outbox. Places restored from the server don't, so they aren't uploaded again.
  - Every unlock, move and lock writes a `sessions` row.
  - "Finish setup" triggers a sync.
- Config is `SupabaseURL` and `SupabaseKey` in Info.plist, set in `project.yml`. Remove them and sync is off.

**Trust.** The server only knows what the phone tells it. That's fine for personal history and for friend leaderboards. Anything public would need server-side checks.

## Later (not in MVP)
- **Social layer (builds on the Backend section).** It adds a `friendships` table and friend-visible policies. The plan for that layer:
  - **"Locked in now" board:** friends in active sessions and where they are.
  - **Streaks and leaderboards:** weekly, for small groups like friends, dorm floors and classes.
  - **Checkable share cards:** a short link or QR code to a server-side record of the session.
  - **What gets uploaded:** only session start and end, the spot ID and the verified flag.
  - **Privacy:** location is shown at building level only, it's opt-in and friends-only, and there's a ghost mode.
- **Zero-shot labels with the text encoder.** Rules like "any place that looks like *a library*" could work with no per-place enrollment.
- **Stronger anti-spoofing.** The pan-coverage rule already blocks a single held-up photo. A future step could also check that the visual change between frames matches the gyro motion, which would also beat a pre-recorded video played on another screen.

## Verification
- `xcodebuild -scheme PlaceLock -destination 'generic/platform=iOS' build` succeeds for all targets.
- Unit tests:
  - `PlaceMatcher`: cosine math, max over references.
  - `KeyframeSelector`: near-duplicate frames are dropped.
  - `ScanSession` pass/fail rules, using synthetic score and yaw streams: pass, timeout, too little coverage, and a single static view.
  - Geofence distance plus accuracy logic.
  - `UnlockCoordinator` decision table, using mocked location and encoder.
  - Session state machine: locked → unlocked → exit → locked, plus cap expiry and auth revoked.
  - *(Stretch)* Verified rules: geofence exit gives Verified, auth revoked gives not Verified, under 25 min gives not Verified, and a session closed by the launch check gives not Verified.
  - *(Stretch)* Streak math across day boundaries and time zones, and per-spot totals.
- On a real iPhone:
  1. Pick Instagram (for example) as a blocked app and confirm it is shielded.
  2. Enroll "Desk" with a sweep, then pan-scan at the desk: it unlocks, and the debug graph shows most frames above the threshold.
  3. Pan-scan a different room in the same building: denied by the video check.
  4. Point the phone at a printed or on-screen photo of the desk without panning: denied for too little coverage.
  5. Scan at the desk with GPS mocked elsewhere using an Xcode `.gpx` file: denied by the GPS check.
  6. While unlocked, simulate walking out of the radius with a `.gpx` route. The apps lock with the app in the background and a notification appears.
  7. In real life, unlock at a place, put the phone away, walk about 300 m off, and confirm it locks within a few minutes.

## Not yet covered (from the original notes)
The plan above always requires GPS **and** a video scan. The original notes also described two modes it doesn't handle yet:
- **GPS-only rules, no scan.** Some places unblock on location alone (e.g. gym, home). Others are always blocked with no CV check (e.g. Smith Hall, Gates Hall). The stretch goal's Study Spots cover these always-blocked places.
- **Scan-only unlocks, anywhere.** CV confirms a social setting (e.g. chilling with friends) and unblocks. If it sees notes or a class setting, apps stay blocked.

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
