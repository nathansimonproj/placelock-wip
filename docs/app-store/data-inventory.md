# Data inventory

What Spots sends off the phone, what it logs, and which "required reason" APIs it uses. Checked against the code on 2026-11-23 (after commit 829f375 plus the log fixes in the same commit as this file). The privacy manifests, the App Privacy answers and the privacy policy should match this page.

Blocking decisions never use the network. Everything below is either backup, or Apple's own services that the app asks for a name or a map.

## What leaves the phone

### Supabase (backup)

Sent to the project in `project.yml` (`SupabaseURL`) over HTTPS, under an anonymous account the app creates on first launch with no sign-in screen. Backup is on by default whenever the URL and key are in the build. Spots › Backup › Delete account removes the account and every row (`delete_my_account()`), and turns backup off. Row-level security lets each account read and write only its own rows.

"Linked to the user" below means linked to the anonymous account's ID. The app sends no name, email, phone number, contacts or device ID. The account ID still ties the rows together, so for Apple's purposes this is data linked to the user.

| Table | Column | What the app sends | Why | Linked to the user |
| --- | --- | --- | --- | --- |
| `auth.users` (Supabase Auth) | `id` and Supabase's own fields | Created by `signInAnonymously()`. No email or phone. | One account per install, so places and history restore after a reinstall | Yes (it is the user ID) |
| `profiles` | `id` | The account ID (set by the server's `handle_new_user` trigger) | Row owner | Yes |
| `profiles` | `setup_ends_at` | When the first 24 h setup window ends | Reinstalling mustn't give a fresh window with no delays | Yes |
| `profiles` | `updated_at` | Time of the last edit on the phone | Newest edit wins | Yes |
| `profiles` | `username`, `display_name`, `avatar_url`, `school` | Nothing. The app never writes these (reserved for later social features) | — | — |
| `preferences` | all | Nothing. The server makes a row of defaults; the app never reads or writes it | — | — |
| `places` | `id`, `user_id` | The place's ID; the account ID (server default `auth.uid()`) | Matching rows across phones | Yes |
| `places` | `name` | The name the user typed or picked from search, up to 60 characters | Restore places | Yes |
| `places` | `address` | The address from Apple's place search, up to 200 characters, or empty for a dropped pin | Restore places (shown under the name) | Yes |
| `places` | `latitude`, `longitude`, `radius_m` | The circle's exact center and size | Restore places | Yes. Precise location |
| `places` | `pending_latitude`, `pending_longitude`, `pending_radius_m`, `pending_applies_at` | A move or enlargement waiting out its 24 h | The delay survives a reinstall | Yes. Precise location |
| `places` | `kind`, `active_after`, `deleted_at`, `updated_at` | Always `unlock`; when a new place starts working; when it was deleted; edit time | Delays and deletes sync | Yes |
| `sessions` | `id`, `user_id`, `place_id`, `kind` | One row per unlock: its ID, the account, which place, always `unlock` | Unlock history restores after a reinstall | Yes |
| `sessions` | `started_at`, `ended_at`, `end_reason` | When apps unblocked at that place, when they blocked again, and why (`left`, `moved`, `place_deleted`, `lost_always`, `manual`, `launch_check`) | Same | Yes. Together with `places` this says when the user was at each saved place |
| `sessions` | `verified`, `shield_attempts`, `deleted_at` | Nothing (stretch-goal lock-ins; history clearing isn't built) | — | — |

Also sent with every request: the publishable key and the account's access token (headers), and the SDK's `X-Client-Info` header (SDK name and version, e.g. `postgrest-swift/2.55.6`). The phone's IP address reaches Supabase like any HTTPS request.

The account's session token is saved on the phone in the Keychain by the Supabase SDK (its default `KeychainLocalStorage`), not sent anywhere else.

**Never sent:** the app's live location, the blocked-app list or anything from Screen Time, the "Estimated @" guess, the local visit list, notification settings, and the app's logs.

### Apple Maps: reverse geocoding (`CLGeocoder`)

- **What:** the phone's location (accurate to about 200 m), from `Location/Estimate.swift`.
- **When:** after a lock or unlock check, at most once a minute with the app open and every 5 minutes in the background, only while apps are blocked and only when the last answer was more than 100 m away. Not in Low Power Mode unless a recent location is already on hand.
- **Why:** to name where you are on the block screen ("Estimated @ Suzzallo Library").
- **Linked to the user:** Apple's service; Spots sends no account ID with it. Apple's own privacy terms apply.

### Apple Maps: place search (`MKLocalSearchCompleter`, `MKLocalSearch`)

- **What:** the text typed in Add place's search field, as it's typed, and a 20 km region around the phone's location to rank nearby results first. Picking a result sends that result back to Apple to get its coordinates.
- **Why:** to find a place by name.
- **Linked to the user:** Apple's service; no account ID.

### Apple Maps: the map (SwiftUI `Map`)

- **What:** map tiles for the area shown in Add place (Apple's servers see which area is being viewed).
- **Why:** to show and drop a pin.
- **Linked to the user:** Apple's service; no account ID.

### Notifications

All local (`UNUserNotificationCenter` with no trigger or a time trigger). The app has no push entitlement (`aps-environment`), never registers for remote notifications and sends nothing to Apple's push service. The text ("At Gym, apps unblocked.") stays on the phone.

### Location and Screen Time themselves

- Geofences (`CLMonitor`) and location updates are handled by iOS on the phone. The app doesn't send them anywhere, except as listed above.
- Screen Time: the app keeps Apple's app, category and website tokens (`FamilyActivitySelection`) in its own storage (`BlockList`, saved with `Storage`) and hands them to `ManagedSettingsStore`. They aren't synced: `SyncChange` only has places and sessions, and `PlaceRecord` / `SessionRecord` have no selection field. The migration comment says so too ("Never stored here: the blocked-app selection").
- The block screen extension reads two values the app shares in the App Group: the "Estimated @" label and the names of the places that can unblock. It writes nothing and sends nothing.

## Logs

Every `Log.app` and `Log.sync` line (plus any `print`, `NSLog` or `os_log`: there are none) was checked on 2026-11-23. Unified logging redacts `privacy: .private` values as `<private>` unless a debugger or a configuration profile is attached, so private values don't show up in sysdiagnose files or device logs someone shares.

The Simulator and Xcode's debugger show private values in full. `scripts/geofence-scenario.py` relies on that: it reads place names from "Auto-unlock at Gym" and "Lock (was unlocked: true): Left Gym, apps blocked. [left]".

Rule: place names, addresses, coordinates, search text, the "Estimated @" label and server error text are `.private` or not logged. IDs (UUIDs), counts, radii, accuracy, flags, error codes and Apple's error descriptions are public.

Fixed on 2026-11-23 (were public):

| Where | What |
| --- | --- |
| `App/AppModel.swift` `startUp` | The running session's place name at launch |
| `App/AppModel.swift` `unlock(at:)` | "Auto-unlock at <place>" |
| `App/AppModel.swift` `lockNow` | The lock reason, which names the place ("Left Gym, apps blocked."). The end reason code (`left`, `lost_always`…) is now logged publicly instead |
| `App/AppModel.swift` `addPlace` | The new place's name |
| `Location/PlaceSearch.swift` | The search text, in "Search slow" and "Search results" |
| `Views/AddPlaceView.swift` | The picked search result's name, and the name in "Added place" and "Edited place" (coordinates there were already private) |
| `Sync/SyncEngine.swift` | Sync errors: `String(describing:)` of a `PostgrestError` includes its `details`, which for a rejected row is the whole row ("Failing row contains (…)") with name, address and coordinates. Now the public part is only the type and code (`SyncEngine.logLabel`, e.g. "PostgrestError 23514", tested in `SyncEngineTests`) and the full text is private. Same for "Session unusable" and "Dropped a row the server rejects" |

Already fine: geofence lines log only the place's UUID (`GeofenceMonitor.logID` strips the coordinates from the identifier) and the radius; "Moved (significant change…)" logs accuracy and age publicly and the place name privately; "Estimated @" is private; "Signed in anonymously as <id>" logs the anonymous account ID publicly (useful for support, not a name or location); Screen Time lines log only whether access is on and counts ("dropped 3"). The free build's stand-in block log lists the stand-in app names, which are made up; the paid build has no such line. Debug-only lines (`-scenario`, Pretend I'm at) aren't in Release builds.

Nothing logs the blocked-app selection or its tokens. The Shield extension doesn't log.

## Required-reason APIs

From Apple's "Describing use of required reason API" and `NSPrivacyAccessedAPITypeReasons` pages, fetched 2026-11-23.

| API category | Used where | Reason code |
| --- | --- | --- |
| User defaults (`NSPrivacyAccessedAPICategoryUserDefaults`) | App: `UserDefaults.standard` (all saved data in the free build; in the paid build, the one-time copy of older saved data into the App Group; Debug-only launch arguments) | `CA92.1`: read and write information only the app itself can access |
| User defaults | App and Shield extension, paid build only: `UserDefaults(suiteName: "group.com.nsimon.PlaceLock")` (`SharedStore`, `Storage`) | `1C8F.1`: read and write information only the apps, extensions and App Clips in the same App Group can access |
| File timestamps | Not used. No `creationDate`, `modificationDate`, `contentModificationDateKey`, `stat`, `getattrlist` and so on | — |
| System boot time | Not used. No `systemUptime` or `mach_absolute_time` (`ProcessInfo.isLowPowerModeEnabled` isn't on the list) | — |
| Disk space | Not used. No `volumeAvailableCapacity*Key`, `systemFreeSize`, `statfs` and so on | — |
| Active keyboards | Not used | — |

So the app's manifest needs `CA92.1` (free and paid) and `1C8F.1` (paid), and the Shield extension's needs `1C8F.1`.

The Shield extension reads the App Group through `SharedStore.defaults`. Its fallback to `UserDefaults.standard` only runs if iOS refuses the suite name, which it doesn't for a valid group name, so the extension's manifest lists `1C8F.1` only.

Packages (Supabase 2.55.6 and what it pulls in: swift-crypto, swift-asn1, swift-clocks, swift-concurrency-extras, swift-http-types, xctest-dynamic-overlay), searched in `build/free/SourcePackages/checkouts`:

- None of them calls a boot-time, disk-space or file-timestamp API, or `UserDefaults`. The only near miss is Supabase Storage's `MultipartFormData`, which reads a file's size with `FileManager.attributesOfItem` for uploads. That method isn't on Apple's list, and Spots never uploads files.
- swift-crypto ships its own `PrivacyInfo.xcprivacy` (empty: no tracking, no data, no APIs), and it ends up in the app as `swift-crypto_Crypto.bundle`. supabase-swift ships none. That fits what it does: it collects nothing for itself, and what it sends is the app's data, declared in the app's manifest.

## Privacy manifests

Added 2026-11-23. Both are listed in the specs as resources, so they're in every build:

- App: `PlaceLock/PlaceLock/PrivacyInfo.xcprivacy` (in `project.yml`).
- Shield extension: `PlaceLock/Extensions/Shield/PrivacyInfo.xcprivacy` (in `project-paid.yml`).

| | App | Shield extension |
| --- | --- | --- |
| Tracking (`NSPrivacyTracking`) | No | No |
| Tracking domains | None | None |
| Collected data | See below | None |
| Required-reason APIs | User defaults: `CA92.1`, `1C8F.1` | User defaults: `1C8F.1` |

The app's collected data is what the backup sends to Supabase (the tables above). Each type is linked to the user, not used for tracking, and used only for app functionality (`NSPrivacyCollectedDataTypePurposeAppFunctionality`):

| Data type | What it covers |
| --- | --- |
| `NSPrivacyCollectedDataTypePreciseLocation` | `places`: latitude, longitude and radius, and pending moves (stored with full precision) |
| `NSPrivacyCollectedDataTypeUserID` | The anonymous account ID that owns every row |
| `NSPrivacyCollectedDataTypeOtherUserContent` | `places`: the name the user typed or picked, and its address |
| `NSPrivacyCollectedDataTypeProductInteraction` | `sessions`: when apps unblocked at each place, when they blocked again and why; `profiles.setup_ends_at` |

The app's manifest has one file for both builds, so it lists `1C8F.1` in the free build too, which doesn't use the App Group. The free build can't go on the App Store, so that only matters for the paid build, where both reasons are true.

Apple's own services (the geocoder, place search, map tiles) aren't declared: Spots sends them nothing tied to the account, and Apple handles that data under its own terms. The App Privacy answers should list the same four types, so the label and the manifest agree.

Packages: supabase-swift 2.55.6 ships no privacy manifest (none in its checkout, none in the built app). swift-crypto ships empty ones; one ends up in the app as `swift-crypto_Crypto.bundle/PrivacyInfo.xcprivacy`. Checked in the paid Release build (`build/release/Build/Products/Release-iphoneos/PlaceLock.app`): `PrivacyInfo.xcprivacy` in the app, in `PlugIns/PlaceLockShield.appex`, and in the swift-crypto bundle. The free Simulator build has the app's.

Sources (fetched 2026-11-23): Apple's "Describing data use in privacy manifests" and the `NSPrivacyCollectedDataType` and `NSPrivacyCollectedDataTypePurposes` reference pages (the data type names and their definitions), TN3184 "Adding data collection details to your privacy manifest" (the four keys in each entry), and the required-reason pages listed above.

## Not checked

- What Supabase keeps on its side: the IP address and user agent in its API and Auth logs, and how long. Look in the Supabase dashboard (Logs, and the project's region) before writing the privacy policy. Listed in the launch checklist.
- Whether Apple counts the MapKit and geocoder requests as data the app "collects" for App Privacy. Most apps don't declare Apple's own services; decide in the App Privacy task.
- Xcode's privacy report for a signed archive (Organizer › right-click the archive › Generate Privacy Report). It merges the app's, the extension's and the packages' manifests the way App Store Connect will. Needs a signed archive; listed in the launch checklist.
- Whether App Review agrees that unlock history is product interaction rather than only location. It's declared both ways (sessions name a place and a time), which is the safer side.
- Logs on the iPhone: that the private values really show as `<private>` in Console with no debugger attached. Simulator and Xcode show them in full.
