# App Privacy answers

> **DRAFT (2026-11-23).** The answers to App Store Connect › the app › App Privacy, ready to click through. They match the app's privacy manifest (`PlaceLock/PlaceLock/PrivacyInfo.xcprivacy`), the Shield extension's (collects nothing) and [data-inventory.md](data-inventory.md). If any of those change, change all of them together. Not entered in App Store Connect yet.

## Before you start

- **Privacy Policy URL:** https://nathansimonproj.github.io/cove/privacy/ (same address as `Brand.privacyPolicyURL`). Required.
- **User Privacy Choices URL:** leave empty (optional). Cove's choices are in the app: Settings › Backup › Delete account.

## Step 1: Data collection

> Do you or your third-party partners collect data from this app?

**Yes, we collect data from this app.**

Why: backup sends places and unlock history to Supabase and keeps them, under an anonymous account. Apple counts data as collected when it leaves the device and is kept "for a period longer than what is necessary to service the transmitted request in real time". It also says "data collected on an ongoing basis after an initial request for permission must be disclosed", so backup can't use the optional-disclosure exception, even if it becomes opt-in.

## Step 2: Data types

Tick exactly these four:

| Section in App Store Connect | Data type | What it covers in Cove |
| --- | --- | --- |
| Location | **Precise Location** | Each saved place's center and radius, and moves waiting out their 24 h (`places` table, full precision) |
| Identifiers | **User ID** | The anonymous account ID that owns every row |
| User Content | **Other User Content** | Each place's name (typed or picked from search) and its address |
| Usage Data | **Product Interaction** | Unlock history: when apps unblocked at each place, when they blocked again and why (`sessions`); when the setup window ends (`profiles`) |

The Roadmap's earlier list said "Usage history" for sessions; App Store Connect has no type by that name. Product Interaction is the one that matches the manifest.

### Leave these unticked

| Data type | Why not |
| --- | --- |
| Coarse Location | Cove keeps no rough location. The "Estimated @" lookup sends a location (about 200 m) to Apple's geocoder, not to Cove's server. Apple's page: "You are not responsible for disclosing data collected by Apple." |
| Search History | Place search text goes to Apple (MapKit), not to Cove's server, and isn't kept by Cove |
| Device ID | No advertising ID, no vendor ID, no device ID is sent |
| Contact Info (name, email, phone…) | Not asked for. The account is anonymous. A support email the user writes is outside the app |
| Health, Fitness, Financial, Sensitive Info, Contacts, Browsing History, Purchases | Not collected |
| Other Usage Data, Advertising Data | Not collected |
| Diagnostics (Crash Data, Performance Data, Other Diagnostic Data) | No crash or analytics SDK. Crash reports users share through Apple go to Apple (App Analytics), which Apple covers |
| Other Data | Nothing else |

**Your call: IP addresses in Supabase's logs.** Every backup request reaches Supabase with the phone's IP address, and Supabase's API and Auth logs may keep it for a while ([data-inventory.md](data-inventory.md) › Not checked). Apple says an IP address that's "sent on a server call and not retained" needn't be declared, and otherwise to declare it "based on how you use IP address". Cove doesn't use it for anything. Recommended: don't declare it, and say in the privacy policy that Supabase's logs keep it for a short time. If the dashboard shows Supabase keeps it for a long time, consider adding Coarse Location (App Functionality, linked, not tracking). Checked 2026-11-23: on the Free plan Supabase keeps logs 1 day, with the IP address next to the account ID, and Cove doesn't use them, so not declaring it still fits. The privacy policy says the logs keep it for 1 day.

## Step 3: For each of the four types

App Store Connect asks the same three things for each ticked type. The answers are the same for all four:

| Question | Answer | Why |
| --- | --- | --- |
| How is this data used? (purposes) | **App Functionality** only | Used only to restore places, the 24 h delays and unlock history after a reinstall. Apple's definition includes "enable features". Not Analytics, Product Personalization, Developer's Advertising or Marketing, Third-Party Advertising or Other Purposes |
| Is this data linked to the user's identity? | **Yes** | Every row carries the anonymous account ID. Apple counts data as linked unless identifiers are stripped before collection, which they aren't |
| Is this data used for tracking? | **No** | Not combined with other companies' data for ads or ad measurement, not shared with data brokers. No ads, no analytics, no App Tracking Transparency prompt |

## Step 4: What the label should show

After Publish, the product page preview should show one section, the "Data Linked to You" kind, with:

- Location
- Identifiers
- User Content
- Usage Data

and nothing under data used to track you or data not linked to you. (The exact section titles on the label weren't on the pages read tonight; compare with the preview App Store Connect shows.)

## If things change

- **Backup becomes opt-in:** same answers. Data collected while backup is on is still collected.
- **Backup stops sending `address`** (needs-you option 3): same answers. Place names are still Other User Content.
- **Backup removed entirely, or the Supabase URL taken out of the build:** then "No, we do not collect data from this app", and the manifest's `NSPrivacyCollectedDataTypes` becomes empty.
- **Anything new sent off the phone** (crash reporting, analytics, a social feature): update the manifest, [data-inventory.md](data-inventory.md), the privacy policy and this page together.

## Sources and what's unverified

From Apple's "App privacy details on the App Store" page (https://developer.apple.com/app-store/app-privacy-details/) and App Store Connect Help "Manage app privacy", both read 2026-11-23: the definition of "collect", the optional-disclosure rules, the data type and purpose definitions, linked and tracking, Apple frameworks, IP addresses.

Not verified:

- The exact on-screen wording and order of the per-type questions in App Store Connect. The help page only says to "answer the questions that follow".
- The label's section titles, as above.
- Whether App Review expects Coarse Location for the geocoder lookup. Apple's page says Apple's own collection isn't the developer's to declare, and Cove doesn't keep the result off the phone.
