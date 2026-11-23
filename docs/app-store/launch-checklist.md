# Launch checklist

What's left before Spots goes on the App Store. See [Roadmap.md](../../Roadmap.md) for what's built.

## Your steps

Things only you can do (Apple account, App Store Connect, Supabase dashboard, hosting, the iPhone). One line each.

- **Archive and export a signed build:** with Xcode signed in to the paid team (Xcode › Settings › Accounts), run `PlaceLock/scripts/bump-build.sh` if this version's build number was already uploaded, then `PlaceLock/scripts/archive.sh`. It prints the `.ipa` path, e.g. `PlaceLock/build/archive/Spots-1.0.0-1-export/PlaceLock.ipa`.
- **Upload the build (pick one):** in Xcode, `open PlaceLock/build/archive/Spots-1.0.0-1.xcarchive`, then Organizer › Distribute App › App Store Connect › Upload; or save an app-specific password (appleid.apple.com › Sign-In and Security › App-Specific Passwords) with `xcrun altool --store-password-in-keychain-item SPOTS_ASC -u <your Apple ID> -p <app-specific password>`, then run `xcrun altool --validate-app -f PlaceLock/build/archive/Spots-1.0.0-1-export/PlaceLock.ipa -t ios -p @keychain:SPOTS_ASC` and `xcrun altool --upload-app -f PlaceLock/build/archive/Spots-1.0.0-1-export/PlaceLock.ipa -t ios -p @keychain:SPOTS_ASC`. The Transporter app (drag in the `.ipa`, click Deliver) works too.

## Not checked yet

- The signed archive and export: only the unsigned `archive.sh --check` has run (2026-11-23). The first signed run may ask Xcode to create a distribution certificate and an App Store profile for the app and the Shield extension.
- The `altool` commands come from `xcrun altool --help` (Xcode 26.1). They haven't been run against App Store Connect.
