# App Review audit

Cove checked against the App Review Guidelines that apply to it, on 2026-11-23, at commit 5d90c80 plus this audit's fixes. Guideline text is from Apple's page (https://developer.apple.com/app-store/review/guidelines/), which says "Last Updated: October 16, 2026".

Each item is marked:

- **OK**: nothing to do.
- **Fixed tonight**: changed in the same commit as this file.
- **Your call**: needs a decision or a step only you can take. The step is in [launch-checklist.md](launch-checklist.md) or the question is in `.night/needs-you.md`.

## Summary

| Guideline | Result |
| --- | --- |
| 2.1 App completeness | Your call: no privacy policy link yet, not tested on the iPhone, backend must be awake during review |
| 2.3 Accurate metadata | Your call: the listing isn't written yet; three things to keep out of it |
| 2.5.1 Public APIs | OK |
| 2.5.4 Background location | OK, with a purpose string fixed tonight |
| 4.0 Design | OK (iPad: your call) |
| 4.2 Minimum functionality | OK |
| 4.10 Screen Time APIs not monetized | OK |
| 5.1.1 Data collection and storage | Purpose strings fixed. Backup notice added to setup (2026-11-23). Your call: the privacy policy link |
| 5.1.2 Data use and sharing | OK, with the setup notice (2026-11-23) |
| 5.1.5 Location services | Fixed (purpose strings, and the setup notice on 2026-11-23) |
| Family Controls (license agreement 3.3.3(P)) | OK |

The biggest risk is backup. It starts on first launch and sends each place's exact coordinates, plus when you were at each one, to Supabase. No screen asks first, and setup says "Your location stays on this phone." Guidelines 5.1.1(ii), 5.1.2(i) and 5.1.5 all ask for consent before location data is sent. See the questions in `.night/needs-you.md` ("Privacy audit…" and "App Review guideline audit").

**Decided 2026-11-23:** backup stays on by default. Setup's first step, before any place is saved, now says: "Where you are is checked on this phone. Your saved places and unlock history are backed up under an anonymous account, with no sign-in. You can delete the backup anytime in Coves › Backup." Setup never asks a yes or no question about backup, so a reviewer could still want an explicit choice. If App Review rejects it under 5.1.1(ii) or 5.1.5, the fallback is to make backup opt-in.

## 2.1 App completeness

> "Submissions … should be final versions with all necessary metadata and fully functional URLs included; placeholder text, empty websites, and other temporary content should be scrubbed before submission. Make sure your app has been tested on-device … include demo account info (and turn on your back-end service!) if your app includes a login."

- **OK: no test-mode text in the paid Release build.** The Debug screen, Pretend I'm at, the launch arguments, scenario mode and the free build's stand-ins (the stand-in app list, the simulated block screen) aren't compiled into it (commit bac193d). **Fixed tonight:** `verify.sh --release` now also searches the Release binary's text for the stand-in and Debug wording ("Stand-in list", "Simulated block screen", "[simulated]", "Pretend I'm at", "Skip 24 h wait", "TODO(user)") and fails if any is there. It passes. The same words are in the free Debug build, so the check works.
- **OK: no starter places or sample data.** `DefaultPlaces` is empty. Sample visits (`-demoHistory`) are Debug-only.
- **OK: icon and launch screen.** 1024 × 1024 icon with no transparency; a system launch screen.
- **OK: no login.** The backup account is anonymous and made without a sign-in screen, so a reviewer needs no demo account.
- **OK: no in-app purchases** (2.1(b)).
- **Your call: the privacy policy link.** Coves › About hides the link while `Brand.privacyPolicyURL` is `nil`, so nothing made-up ships. Apple requires it, though (5.1.1(i)), so the app can't be submitted until it's filled in. Already in Your steps.
- **Your call: not tested on a device.** Apple asks for on-device testing. Real blocking, the block screen and a Release build have never run on the iPhone (Roadmap Phase 1). That's the "Launch checklist (final)" task's on-iPhone test list.
- **Your call: the backend must be awake during review.** Supabase pauses Free plan projects after 7 days of low activity (Supabase docs, "Free plan project pausing"). Blocking would still work, but Backup would show "Not backed up" and Delete account would fail with "Couldn't delete your account". A reviewer checking 5.1.1(v) would see that. Added to Your steps.
- **Your call: review notes.** 2.1 and 2.3.1 ask for "detailed explanations of non-obvious features". The first 24 h setup window, Always location and the block screen needing a real device all count. That's the "Draft the App Store listing, App Privacy answers and review notes" task.

## 2.3 Accurate metadata

> 2.3: "… make sure all your app metadata, including privacy information, your app description, screenshots, and previews accurately reflect the app's core experience …"

The listing, screenshots and App Privacy answers aren't written yet (later tasks in the queue). For those tasks:

- **2.3.3 Screenshots** must show the app in use. **Don't use free-build shots of the app picker**: they show the stand-in list ("Stand-in list. With the paid developer account…") and other companies' app names (Instagram, TikTok…). 2.3.7 rules out "popular app names" used to game search. The real picker needs the paid build on a device.
- **2.3.7 Name and keywords:** the name must be unique and 30 characters or fewer. The app record is "Cove: Block Apps by Location" (28 characters), created 2026-11-23. No competitor names (e.g. Opal) in keywords or subtitle.
- **2.3.8:** keep the metadata 4+.
- **2.3.10:** no other platforms in the metadata.
- **Privacy information:** the App Privacy answers must match the manifests and [data-inventory.md](data-inventory.md): precise location, user ID, other user content, product interaction.
- **Your call, small: the block screen's wording doesn't match the app.** The Shield says "Instagram is locked" and "Opens at Gym…", while the app says "blocked" and "unblock". Roadmap Phase 1 also still describes it as "is blocked" / "Unblocks at". This isn't a guideline problem, but screenshots and review notes should quote what the block screen really says. Not changed tonight: it's wording users see, and the task didn't call for it.

## 2.5 Software requirements

- **2.5.1 OK.** Public APIs only: Core Location (`CLMonitor`, `CLServiceSession`, significant-change, `CLLocationUpdate`), MapKit, FamilyControls, ManagedSettings, ManagedSettingsUI and UserNotifications. `DeviceActivity` is only called to clear a schedule older builds left behind (`ShieldManager.stopLegacySessionCap`), which is a no-op on a new install. 2.5.1 also asks apps to "indicate that integration in their app description", so the description should say Cove blocks apps through Screen Time.
- **2.5.4 OK** ("may only use background services for their intended purposes: … location …"). `UIBackgroundModes` is `location` only. In the background, Cove:
  - watches saved places with `CLMonitor`,
  - wakes on significant-change updates (cell and Wi-Fi, about every 500 m),
  - takes short one-off fixes for lock checks and for "Estimated @".

  It never streams GPS in the background. All of this serves unblocking at places, blocking on leaving, and the block screen's location line. **Fixed tonight:** the Always purpose string didn't mention unblocking on arrival or the block screen's location line (see 5.1.1). Review notes should explain the background mode (queued task).

## 4.0 Design

- **OK: basics.** Large text checked at the largest accessibility size (06b903e, 206579c). VoiceOver labels everywhere (5d90c80). Permission problems say what's wrong and link to Settings (72162df). Nothing crashes on damaged saved data (ae0eb0c).
- **OK, 4.2 Minimum functionality.** A real native utility, not a wrapped website.
- **OK, 4.10.** "You may not monetize … Screen Time APIs." Cove is free with no purchases.
- **Your call: iPad.** `TARGETED_DEVICE_FAMILY` is iPhone only, so iPads run Cove in iPhone compatibility mode, and App Review sometimes tests there. It hasn't been seen on an iPad or the iPad Simulator. Fine to leave, but worth one look before submitting.

## 5.1.1 Data collection and storage

- **(i) Privacy policy. Your call.** The link must be in App Store Connect and in the app. The in-app row is built and waits for the URL (see 2.1). The policy itself must name what's collected and every use, say that third parties (Supabase) protect it equally, and explain retention, deletion and how to withdraw consent. The "Draft the privacy policy" task covers it. Retention on Supabase's side is still unknown (data-inventory "Not checked").
- **(ii) Permission and purpose strings. Fixed tonight, with the rest your call.**
  - Apple: "Ensure your purpose strings clearly and completely describe your use of the data."
  - The old strings covered only part of what location is used for. "Cove checks that you're at one of your allowed places before unblocking apps." left out place search near you. "Cove needs Always access so it can lock your apps again when you leave an allowed place…" left out unblocking on arrival and the block screen's location line. Both also said "allowed place", which the app never says.
  - New strings in `project.yml` (checked in the Release build's Info.plist):
    - When In Use: "Cove checks whether you're at one of your places to decide if apps unblock, and finds places near you when you add one."
    - Always: "With Always, Cove notices when you arrive at or leave one of your places, even when it's closed, so apps unblock while you're there and block again when you go. The block screen also shows roughly where you are."
  - **Your call:** "Apps that collect user or usage data must secure user consent for the collection." Backup starts with no consent and needs a decision (needs-you, "Privacy audit…"). Withdrawing consent works: Coves › Backup › Delete account turns backup off and deletes the data.
- **(iii) Data minimisation. Your call.** Location, notifications and Screen Time are the only permissions, all core. The app picker is Apple's out-of-process picker. The one extra is `places.address`, which isn't needed to restore a place's circle (needs-you, "Privacy audit…" option 3).
- **(iv) Access. OK.** Every permission step in setup can be skipped. Without location, apps simply stay blocked: the safe fallback, and the app says what's missing and links to Settings.
- **(v) Account sign-in and deletion. OK.** No login. The anonymous account is account creation, so in-app deletion is required, and Cove has it: Coves › Backup › Delete account, with a confirmation, runs `delete_my_account()` and turns backup off. Not tried against the live project tonight (needs the live database). Needs the backend awake during review (see 2.1).
- **(vi)–(x) OK.** No passwords, no SafariViewController, no data from outside sources, not a regulated field, no contact info requested.

## 5.1.2 Data use and sharing

- **(i) Your call.**
  - Apple: "you may not use, transmit, or share someone's personal data without first obtaining their permission."
  - Backup transmits saved places' exact coordinates and unlock times without asking first (same backup consent question).
  - No tracking, no ads, no analytics, no third-party AI, so no App Tracking Transparency.
  - "Your app may not require users to enable system functionalities (such as … location services …) in order to … use the app". Location is the core feature, and the app still runs (and keeps apps blocked) without it.
- **(ii)–(iii) OK.** Data is used only to restore places and history. No profiling.
- **(iv) OK.** "don't collect information about which other apps are installed": the blocked-app selection and its tokens never leave the phone and aren't logged (data-inventory).
- **(v)–(vii) N/A.** No Contacts, Photos, HealthKit, HomeKit or Apple Pay.

## 5.1.5 Location services

> "Use Location Services in your app only when it is directly relevant … Ensure that you notify and obtain consent before collecting, transmitting, or using location data. If your app uses Location Services, be sure to explain the purpose in your app …"

- **OK: relevant and explained.** Location is the whole point. Setup's first step explains Always before iOS asks.
- **Fixed tonight:** the purpose strings (5.1.1(ii)).
- **Your call:** "obtain consent before … transmitting". Saved places' coordinates go to Supabase with no prompt. Setup also says "Your location stays on this phone.", which isn't true for:
  - saved places and unlock history (backup),
  - the "Estimated @" lookup, which sends a location accurate to about 200 m to Apple's geocoder.

  New question in needs-you ("App Review guideline audit").

## Family Controls and Screen Time

The App Review Guidelines don't mention Family Controls or Device Activity. Screen Time appears only in 4.10 (OK above). The rules are in the Apple Developer Program License Agreement, https://developer.apple.com/programs/apple-developer-program-license-agreement/ (read 2026-11-23; no date shown on the page). Its clause 3.3.3(P), "Family Controls Framework", paraphrased because only short quotes could be taken:

| Rule (3.3.3(P), paraphrased) | Cove | Result |
| --- | --- | --- |
| The app's primary purpose is parental controls through Family Sharing, or letting people manage their own device for focus, productivity, timers, task management or personal device use | Individual focus: blocks your own apps outside your places. Asks with `requestAuthorization(for: .individual)` (`Blocking/ShieldManager.swift`) | OK |
| Not for other uses such as ad blocking, organisations, or "managing the device of another adult individual" | None of these | OK |
| Data from the framework is used only to provide those controls | The selection is only handed to `ManagedSettingsStore` | OK |
| Not shared beyond the individual and their device | The selection and tokens stay on the phone: not in `PlaceRecord`/`SessionRecord`, not logged (data-inventory). The Shield gets the blocked app's name from iOS and only shows it | OK |
| Not used for advertising or given to data brokers | No ads, analytics or brokers | OK |

The App Group holds the "Estimated @" label and place names. These are Cove's own data, not Screen Time data, and they stay on the phone.

Also needed (already tracked): Apple's Family Controls (Distribution) approval for the app and the Shield extension (Roadmap Phase 0, requested 2026-11-19).

## Not checked

- Apple's own Family Controls documentation and the entitlement request form may add terms. Only the license agreement's 3.3.3(P) was read, as a paraphrase, and the date of that agreement version wasn't visible.
- Guidelines not listed in this task were skimmed, not audited (for example 1.x safety and 3.x business). Nothing in Cove touches user-generated content shared with others, payments or kids' content.
- Delete account against the live Supabase project, a Release build on the iPhone, the iPad compatibility mode, and how the new purpose strings look in iOS's location prompts (only checked in the Release Info.plist).
