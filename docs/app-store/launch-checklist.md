# Launch checklist

What's left before Cove goes on the App Store. Last updated 2026-11-23. See [Roadmap.md](../../Roadmap.md) for what's built, and `.night/needs-you.md` in your checkout for tonight's open questions.

## Ready

What's in place for submission, with where to find it. Everything here was checked in the Simulator or by a script; nothing was tried on the iPhone.

- **Version 1.0.0 (1), encryption exempt.** `PlaceLock/project.yml` sets the version and build; both Info.plists read them and say `ITSAppUsesNonExemptEncryption = NO`. `PlaceLock/scripts/bump-build.sh` raises the build number. (e93d26c)
- **Archive and export script.** `PlaceLock/scripts/archive.sh` with `PlaceLock/scripts/ExportOptions.plist` (App Store Connect, automatic signing, team `R6W24T35J6`). It never uploads. `archive.sh --check` (unsigned) passes. (829f375)
- **No debug code in the shipping build.** Launch arguments, the Debug screen, Pretend I'm at, scenario mode and the free build's stand-ins are kept out of the paid Release build, and `verify.sh --release` checks for them. (bac193d, 4a52129)
- **Damaged saved data doesn't crash or unblock.** `PlaceLock/PlaceLock/Models/SavedData.swift`, with tests. (ae0eb0c)
- **Privacy manifests** for the app and the Shield extension (`PrivacyInfo.xcprivacy`), matching `docs/app-store/data-inventory.md`. (242ef8a)
- **Private logs and a list of what leaves the phone:** `docs/app-store/data-inventory.md`. No Screen Time data is synced or logged. (e09708d)
- **About section** in the Coves tab with the version, and privacy policy and support rows that appear once `PlaceLock/PlaceLock/Shared/Brand.swift` has addresses. (f839cca)
- **Location purpose strings** name every use of location. (4a52129)
- **Permission problems** say what's wrong and link to Settings; apps stay blocked. (72162df)
- **Place search fallback** when suggestions don't arrive. (642cbd0)
- **Large text** fits on every screen the Simulator can show. (63c0aa2, 206579c)
- **VoiceOver labels** on icons, the lock and countdowns. (5d90c80)
- **Geofence scenarios:** all 6 pass in the Simulator. (b6fa9fc)
- **App icon:** `PlaceLock/PlaceLock/Assets.xcassets/AppIcon.appiconset/AppIcon.png`, 1024 px, no alpha (Roadmap Phase 3, 2026-11-19).
- **App Review audit:** `docs/app-store/review-audit.md`. (4a52129)
- **Privacy policy draft:** `docs/app-store/privacy-policy.md` and the page `docs/privacy/index.html`. (97c428d)
- **Listing, App Privacy, age rating and review notes drafts:** `docs/app-store/listing.md`, `app-privacy.md`, `age-rating.md`, `review-notes.md`. (c2ef3e8)
- **Draft screenshots** at 1320 × 2868: `.night/app-store-screens/` in your checkout, not in the repo. (fc2d747)
- **Backend:** Supabase project with row-level security and the 50 m radius migration applied; Delete account in Coves › Backup (Roadmap › Backend).
- **README and Plan** match the code. (8f6f787, e681169)

## Your steps

Things only you can do, in order. One line each.

### 0. Answer tonight's questions first

Some of these change setup's wording, the privacy policy and the listing, so answer them before you finish those. All are in `.night/needs-you.md`. Nothing was parked tonight; these are follow-ups from tasks that finished.

- ~~**Backup on by default?**~~ Decided 2026-11-23: it stays on, and setup's first step now says so.
- ~~**Setup's "Your location stays on this phone."**~~ Replaced 2026-11-23 with a sentence about backup and where to delete it.
- **Unreadable Screen Time app list:** show a one-time "Choose them again" message on Home (recommended), or leave it. ("No crashes from bad saved data")
- **Simulator demo data in the live Supabase project:** delete that account with Coves › Backup › Delete account in the "iPhone 17 Pro Max" Simulator (recommended). ("Draft App Store screenshots")

### 1. Build the paid app to the iPhone

- **Switch to the paid build:** `cd PlaceLock && xcodegen generate --spec project-paid.yml`, open `PlaceLock.xcodeproj`, check Signing & Capabilities shows team `R6W24T35J6` for PlaceLock and PlaceLockShield, pick the iPhone and press Run. This registers `com.nsimon.PlaceLock`, `com.nsimon.PlaceLock.Shield` and the App Group. Run plain `xcodegen generate` before committing anything.

### 2. Test on the iPhone

From Roadmap.md. Use the paid build, and keep Console on the Mac open (pick the iPhone, filter on `com.nsimon.PlaceLock`) for the log checks.

- **Block screen:** open a blocked app; it should say it's blocked, show "Estimated @ …" and name the places that unblock it. (Phase 1, Phase 3 "Estimated @")
- **Screen Time turned off:** Settings › Screen Time › turn off access for Cove; Cove should show "Blocking is off" and send a notification. (Phase 1)
- **Places survive the paid build:** places from the free build are still there after the first paid launch. (Phase 1)
- **Arrive with Cove closed:** close Cove, walk to a saved place, and apps unblock without opening it (can take a minute or two). (Phase 2)
- **Leave:** walk about 300 m away and apps block again within a few minutes. (Next, item 1)
- **Leave after a force-quit:** swipe Cove away, walk out of a place, and check apps block without opening it. (Known issues)
- **Location off while open:** with Cove open and unlocked, set Location to Never in Settings and come back; apps block. (Phase 2 on-iPhone checks)
- **Restart:** restart the phone, don't unlock it, walk more than 500 m, then unlock; the log shows "Launched before first unlock; waiting for protected data" and the places are still there. (Phase 2 on-iPhone checks)
- **Geofence log lines:** a plain relaunch logs no "Geofence … added" or "removed"; the first launch of the new build logs one "removed (old identifier)" and one "added" per place; renaming a place logs neither. (Phase 2 on-iPhone checks)
- **Battery and notices:** after a day of normal use, check Settings › Battery for Cove, and that Notification Center has at most one recent Cove notice. (Phase 2)
- **Permission fixes:** Home's Fix and setup's Open Settings land on Cove's page in Settings; Precise Location and notification switches show the right banner. (Phase 3)
- **Links in About:** once `Brand.swift` is filled in, Coves › About › Privacy policy opens Safari and Contact support opens Mail. (Phase 4)
- **Private logs:** with no Xcode debugger attached, add a place and walk out of one; place names, search text and coordinates show as `<private>` in Console. (Phase 4)
- **Sync:** an unlock then leave writes a `sessions` row; check it in Supabase dashboard › Table Editor › `sessions`. (Backend)
- **Delete account on the live project:** Coves › Backup › Delete account › Delete account; no "Couldn't delete your account" alert, and no `places` or `sessions` rows left for that account in the Table Editor. App Review checks this (5.1.1(v)).
- **VoiceOver:** Settings › Accessibility › VoiceOver on; Home's lock says blocked or unblocked and countdowns read as words. (Phase 3)
- **Location prompts:** the two iOS location prompts show the new purpose wording. (Phase 4, App Review audit)
- **Place search:** search works on normal Wi-Fi; if it ever spins, press Search and send the log. (Known issues)
- **50-website cap (optional):** Coves › Blocked apps › Add or remove apps, pick more than 50 websites; Cove says "Kept 50 of each" and a kept site shows the block screen in Safari. (Known issues, question 3)

### 3. App Store Connect app record

- **Check the name and create the app:** App Store Connect › Apps › + › New App: iOS, name "Cove", your primary language, bundle ID `com.nsimon.PlaceLock`, any SKU (e.g. `cove-ios`), Full Access. If "Cove" is taken it says so here; pick a fallback from `docs/app-store/listing.md` (the home screen name stays Cove). Tick Roadmap Phase 0's name item.

### 4. Family Controls distribution entitlement

- ~~**Check both App IDs are approved.**~~ Done 2026-11-23: Identifiers › `com.nsimon.PlaceLock` and `com.nsimon.PlaceLock.Shield` both show "Family Controls (Distribution)" as Assigned.

### 5. Supabase

- **Rate-limit anonymous sign-ins:** Supabase dashboard › the project › Authentication › Rate Limits › anonymous sign-ins per hour. Supabase's default is 30 per IP address per hour; keep about 30 rather than 10, because friends on the same campus Wi-Fi share one address. Leave CAPTCHA off (the app doesn't send a token). Tick the Roadmap Backend item.
- **Check what Supabase keeps about each request:** Logs (API Gateway and Auth) and Project Settings › General (region): note whether IP addresses and user agents are kept and for how long, and add it to `docs/app-store/data-inventory.md` ("Not checked") and the privacy policy. Also Database › Backups: how long backups keep a deleted account.

### 6. Privacy policy, support page and links in the app

- **Finish the privacy policy:** in `docs/app-store/privacy-policy.md` fill in each `TODO(user)` (effective date, your name as on the App Store, Supabase region, log and backup retention, the Children section, support email), delete the DRAFT note, then rebuild `docs/privacy/index.html` from it (same text; also delete its DRAFT banner and the `noindex` line). Change the Backup section first if backup becomes opt-in.
- **Host it and a support page:** put `docs/privacy/index.html` and a support page at any `https` address (copy the one file to its own GitHub Pages repo or host; don't publish the whole `docs/` folder, which would also publish the drafts and review notes), and pick a support email.
- **Link them in the app:** fill in `privacyPolicyURL`, `supportURL` and `supportEmail` in `PlaceLock/PlaceLock/Shared/Brand.swift` (each marked `TODO(user)`; leave one `nil` to hide its row), run `PlaceLock/scripts/verify.sh --release --screens`, and commit. Apple requires the privacy policy link in the app.

### 7. Archive and upload

- **Archive and export a signed build:** with Xcode signed in to the paid team (Xcode › Settings › Accounts), run `PlaceLock/scripts/bump-build.sh` if this build number was already uploaded, then `PlaceLock/scripts/archive.sh`. It prints the `.ipa` path, e.g. `PlaceLock/build/archive/Cove-1.0.0-1-export/PlaceLock.ipa`. The first signed run may ask to create a distribution certificate and App Store profiles for the app and the Shield.
- **Check the privacy report:** Xcode › Window › Organizer › right-click the archive › Generate Privacy Report; it should list precise location, user ID, other user content and product interaction (linked, not tracking, app functionality) and `UserDefaults` with `CA92.1` and `1C8F.1`, as in `docs/app-store/data-inventory.md`.
- **Upload (pick one):** in Xcode, `open PlaceLock/build/archive/Cove-1.0.0-1.xcarchive`, then Organizer › Distribute App › App Store Connect › Upload; or save an app-specific password (appleid.apple.com › Sign-In and Security › App-Specific Passwords) with `xcrun altool --store-password-in-keychain-item SPOTS_ASC -u <your Apple ID> -p <app-specific password>`, then `xcrun altool --validate-app -f PlaceLock/build/archive/Cove-1.0.0-1-export/PlaceLock.ipa -t ios -p @keychain:SPOTS_ASC` and `xcrun altool --upload-app -f PlaceLock/build/archive/Cove-1.0.0-1-export/PlaceLock.ipa -t ios -p @keychain:SPOTS_ASC`. The Transporter app (drag in the `.ipa`, click Deliver) works too.

### 8. TestFlight with friends

- **Test it yourself first:** App Store Connect › the app › TestFlight › wait for the build to finish processing › Internal Testing › add yourself; install from the TestFlight app and repeat step 2's arrive, leave and block screen checks.
- **Invite friends:** TestFlight › External Testing › + (new group) › add the build › Test Information (what to test, feedback email) › Submit for Beta App Review, then add friends by email or turn on a public link. Ask them to walk in and out of a place around campus for a few days.
- **Record the review video:** on the iPhone with the TestFlight build, follow the script in `docs/app-store/review-notes.md` (Control Center › Screen Recording, about 60–90 s, pick two apps).

### 9. App Privacy and age rating

- **Answer App Privacy:** App Store Connect › the app › App Privacy › Get Started, then follow `docs/app-store/app-privacy.md` (Yes; Precise Location, User ID, Other User Content, Product Interaction; each App Functionality, linked, not tracking), then Publish. Decide the Supabase IP address question in that file first (step 5).
- **Answer the age rating:** App Information › Age Rating › Edit, answer as in `docs/app-store/age-rating.md` (all No or None) and check it comes out 4+. Confirm "Health or Wellness Topics: No".

### 10. Listing and screenshots

- **Fill in and enter the listing:** fill in each `TODO(user)` in `docs/app-store/listing.md` (support URL, marketing URL or empty, copyright name), then App Information: name, subtitle, Productivity category, privacy policy URL; and on the 1.0 version page: promotional text, description, keywords, support URL. Re-run the length check at the end of `listing.md` after any edit.
- **Pick and finish the screenshots:** read `.night/app-store-screens/README.md`, retake Home and Cove from the paid build on the iPhone so real app icons show (side button + volume up), then the 1.0 version page › Previews and Screenshots › iPhone 6.9" Display › drag in 3–10 shots, all 1320 × 2868.

### 11. Submit

- **Keep Supabase awake:** just before submitting, open the Supabase dashboard › the project; if it says Paused, click Resume project (Free plan projects pause after 7 days of low activity, and Delete account then fails for the reviewer). Then check Coves › Backup on the iPhone says "Backed up".
- **Fill in App Review Information:** 1.0 version page › App Review Information: untick sign-in required, add your name, phone and email, paste the notes from `docs/app-store/review-notes.md` (replace `Screen recording: TODO(user)`), and attach the video.
- **Submit:** only once step 4 shows Family Controls (Distribution) on both App IDs: 1.0 version page › Build › pick the build, choose manual or automatic release, Add for Review, then Submit to App Review.

## Not checked yet

- The signed archive and export: only the unsigned `archive.sh --check` has run (2026-11-23).
- The `altool` commands come from `xcrun altool --help` (Xcode 26.1). They haven't been run against App Store Connect.
- The privacy manifests (2026-11-23) are in the built app and Shield extension, but Xcode's privacy report and App Store Connect's checks haven't seen them yet.
- The listing, App Privacy, age rating and review notes drafts (2026-11-23) haven't been entered in App Store Connect, and the review notes' steps haven't been tried on the iPhone.
- The App Store Connect and TestFlight click paths are from memory of Apple's current pages, not checked tonight; the Supabase rate limit default (30 per hour per IP) is from Supabase's docs ([anonymous sign-ins](https://supabase.com/docs/guides/auth/auth-anonymous)).
