# App Store listing

> **DRAFT (2026-11-23).** Not entered in App Store Connect yet. Fill in each `TODO(user)`, read it against the app once more, then paste each field into App Store Connect › the app › App Information and the 1.0 version page. Character counts were checked with a script on 2026-11-23 (App Store Connect counts characters; keywords are limited to 100 bytes, which is the same as characters here because the keywords are plain ASCII).

The wording follows the app's own: "blocked", "unblock", "your places", "Cove" for the app and the tab. Things App Review flagged to keep out of the listing ([review-audit.md](review-audit.md) › 2.3):

- No competitor names (for example Opal) and no other companies' app names (Instagram, TikTok…) in the name, subtitle or keywords.
- No other platforms (Android, iPad-native, Mac).
- Don't promise anything the app doesn't do yet: no exact battery numbers, no "works in every browser", no "location never leaves your phone" (backup sends saved places; see the backup question in `.night/needs-you.md`).

## App Information

| Field | Limit | Draft | Length |
| --- | --- | --- | --- |
| Name | 30 | Cove: Block Apps by Location | 28 |
| Subtitle | 30 | Apps unblock where you choose | 29 |
| Primary category | | Productivity | |
| Secondary category | | None (optional; Lifestyle would also fit; your call) | |
| Privacy Policy URL | | https://nathansimonproj.github.io/cove/privacy/ | |
| Content rights | | No, Cove doesn't contain, show or access third-party content | |
| Age rating | | 4+ (answers in [age-rating.md](age-rating.md)) | |

The subtitle is first-run setup's first heading.

**App Store name (2026-11-23):** the app record is "Cove: Block Apps by Location". The home screen name (`CFBundleDisplayName`) stays Cove.

## Version 1.0 page

### Promotional text (170)

Can be changed at any time without a new build.

> Distracting apps stay blocked everywhere except the places you choose, like the gym or home. Arrive and they unblock on their own. Leave and they block again.

158 characters.

### Description (4000)

> Cove keeps distracting apps blocked everywhere except the places you pick, like the gym or home.
>
> Choose the apps that distract you and the places where they're allowed. Apps stay blocked by default. When you arrive at one of your places, they unblock on their own. When you leave, they block again. There's no unlock button.
>
> HOW IT WORKS
>
> • Blocked by default. Your chosen apps and websites stay blocked until you're at one of your places.
> • Places you choose. Search for a place by name, or drag the map so the pin sits on your spot, then set its size from 50 to 500 m.
> • Works with Cove closed. iOS tells Cove when you arrive and when you leave, so you never have to open it.
> • No quick loopholes. In your first 24 hours, every change applies right away, so you can set things up. After that, adding a place, moving or enlarging one, or removing a blocked app takes 24 hours. Changes that only make things stricter apply right away.
> • A calm block screen. Open a blocked app and Cove shows roughly where you are and where the app opens: "Opens at Gym or Home."
> • A heads-up when you arrive and apps unblock, and when you leave and they block again.
>
> BUILT ON SCREEN TIME
>
> Cove blocks apps through Screen Time, the same way iOS's own limits work. You pick apps and websites with Apple's own picker, and that list stays on your iPhone.
>
> WHAT IT NEEDS
>
> • Location set to Always, with Precise Location on, so Cove notices when you arrive and leave.
> • Screen Time access, which Apple asks you to confirm with Face ID or your passcode.
> • Leaving a place can take a few minutes and 100–200 m to register.
>
> BACKUP
>
> Your places and unlock history are backed up under an anonymous account, with no sign-in, so they come back after a reinstall. Delete account in Cove's Settings › Backup removes them.

1,790 characters (counting line breaks).

The BACKUP paragraph describes backup as it works today: on from first launch, which was kept on 2026-11-23.

### Keywords (100)

Comma-separated, no spaces after commas. The name and category are already indexed, so "cove" and "productivity" are left out. No trademarks ("Screen Time" is Apple's feature name, so it's in the description, not here).

```
focus,app blocker,block apps,distraction,location,geofence,study,library,gym,detox,habit,phone,limit
```

100 characters (the limit). Swap words freely; the script below re-checks the count.

### URLs

| Field | Required | Draft |
| --- | --- | --- |
| Support URL | Yes | https://nathansimonproj.github.io/cove/ (same as `Brand.supportURL`) |
| Marketing URL | No | Leave empty |

### Other version fields

| Field | Draft |
| --- | --- |
| Copyright | 2026 Nathanael Simon |
| Version | 1.0.0 (from `project.yml`) |
| Screenshots | 6.9" iPhone shots. Drafts are a separate queue task ("Draft App Store screenshots"). Don't use free-build shots of the app picker or the simulated block screen ([review-audit.md](review-audit.md) › 2.3.3) |
| App Review information | See [review-notes.md](review-notes.md) |
| App Privacy | See [app-privacy.md](app-privacy.md) |

## Checking the lengths

The counts above came from this (run from the repo root after editing):

```sh
python3 - <<'EOF'
import re
text = open("docs/app-store/listing.md").read()
quote = lambda h: "\n".join(l[2:] if l.startswith("> ") else "" for l in
    text.split(h, 1)[1].split("\n### ", 1)[0].split("\n") if l.startswith(">")).strip()
print("subtitle", len("Apps unblock where you choose"), "/ 30")
print("promo", len(quote("### Promotional text")), "/ 170")
print("description", len(quote("### Description")), "/ 4000")
kw = re.search(r"```\n(focus[^\n]*)\n```", text).group(1)
print("keywords", len(kw.encode()), "/ 100 bytes")
EOF
```
