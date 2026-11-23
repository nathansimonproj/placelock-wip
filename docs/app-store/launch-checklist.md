# Launch checklist

What's left before Spots goes on the App Store. See [Roadmap.md](../../Roadmap.md) for what's built.

## Your steps

Things only you can do (Apple account, App Store Connect, Supabase dashboard, hosting, the iPhone). One line each.

- **Host the privacy policy and a support page, then link them in the app:** put the privacy policy and a support page online (any `https` address, e.g. GitHub Pages), pick a support email, and fill in `privacyPolicyURL`, `supportURL` and `supportEmail` in `PlaceLock/PlaceLock/Shared/Brand.swift` (each is marked `TODO(user)`; leave one `nil` to hide its row). The privacy policy link is required by Apple. Run `PlaceLock/scripts/verify.sh --release --screens`, then open Spots › About and tap each link. Use the same privacy policy and support URLs in App Store Connect › App Information.
- **Archive and export a signed build:** with Xcode signed in to the paid team (Xcode › Settings › Accounts), run `PlaceLock/scripts/bump-build.sh` if this version's build number was already uploaded, then `PlaceLock/scripts/archive.sh`. It prints the `.ipa` path, e.g. `PlaceLock/build/archive/Spots-1.0.0-1-export/PlaceLock.ipa`.
- **Upload the build (pick one):** in Xcode, `open PlaceLock/build/archive/Spots-1.0.0-1.xcarchive`, then Organizer › Distribute App › App Store Connect › Upload; or save an app-specific password (appleid.apple.com › Sign-In and Security › App-Specific Passwords) with `xcrun altool --store-password-in-keychain-item SPOTS_ASC -u <your Apple ID> -p <app-specific password>`, then run `xcrun altool --validate-app -f PlaceLock/build/archive/Spots-1.0.0-1-export/PlaceLock.ipa -t ios -p @keychain:SPOTS_ASC` and `xcrun altool --upload-app -f PlaceLock/build/archive/Spots-1.0.0-1-export/PlaceLock.ipa -t ios -p @keychain:SPOTS_ASC`. The Transporter app (drag in the `.ipa`, click Deliver) works too.
- **Check what Supabase keeps about each request:** in the Supabase dashboard, open the project › Logs (API Gateway and Auth) and Project Settings › General (region). Note whether IP addresses and user agents are kept and for how long, and add that to `docs/app-store/data-inventory.md` ("Not checked") and the privacy policy.
- **Check the privacy report:** after `archive.sh` makes a signed archive, open it in Xcode's Organizer (Window › Organizer), right-click the archive › Generate Privacy Report, and check the PDF lists precise location, user ID, other user content and product interaction (linked, not tracking, app functionality) and `UserDefaults` with `CA92.1` and `1C8F.1`, matching `docs/app-store/data-inventory.md` › Privacy manifests.
- **Check that logs hide private values on the iPhone:** with the iPhone connected but no Xcode debugging, open Console on the Mac, pick the iPhone, filter on `com.nsimon.PlaceLock`, add a place and walk out of one. Place names, search text and coordinates should show as `<private>`.

## Not checked yet

- The signed archive and export: only the unsigned `archive.sh --check` has run (2026-11-23). The first signed run may ask Xcode to create a distribution certificate and an App Store profile for the app and the Shield extension.
- The `altool` commands come from `xcrun altool --help` (Xcode 26.1). They haven't been run against App Store Connect.
- The privacy manifests (2026-11-23) are in the built app and Shield extension, but Xcode's privacy report and App Store Connect's checks haven't seen them yet.
