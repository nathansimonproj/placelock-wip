---
name: release
description: Send a new Cove build to TestFlight. Checks the change, raises the build number (or the version with an argument like 1.0.1), archives and signs the paid build, uploads it to App Store Connect, logs it in docs/app-store/builds.md and pushes. Use only when the user runs /release or asks to upload a new build.
disable-model-invocation: true
---

# Release a TestFlight build

Typing `/release` is the go-ahead to upload. It never adds the build to the Pilot group or submits it for App Store review; the user does those in App Store Connect.

Arguments: none for a new build of the same version (1.0.0 (2) → (3)), or a version like `1.0.1` (fixes) or `1.1.0` (new features) once the current version is on the App Store. After App Store Connect has a version approved or in review, the next upload needs a new version.

Run everything from the repo root, with a 10-minute Bash timeout per step. Stop at the first failure and report it; don't retry an upload blindly.

## 1. Check it's ready

- `git status --short` must be empty and the branch `main`. If not, stop and say what's uncommitted; don't commit someone else's work.
- The free project must be the one generated: `grep -q PlaceLockShield PlaceLock/PlaceLock.xcodeproj/project.pbxproj` must not match. If it does, run `cd PlaceLock && xcodegen generate` and check `git status` is clean again.
- Note the previous build's commit from the top row of `docs/app-store/builds.md`, and run `git log --oneline <that commit>..HEAD`. If nothing user-facing changed since, ask before uploading.
- Run `PlaceLock/scripts/verify.sh --release`. Every step must PASS.

## 2. Raise the number and commit

```sh
PlaceLock/scripts/bump-build.sh                    # or: --version 1.0.1
```

Commit `PlaceLock/project.yml` and `PlaceLock/PlaceLock.xcodeproj/project.pbxproj` as "Raise the build to X.Y.Z (N)", with a few words on what's in it. Note the commit hash.

## 3. Archive and upload

```sh
PlaceLock/scripts/archive.sh     # paid Release build, signed with the Cove App Store profiles
PlaceLock/scripts/upload.sh      # uploads the archive for project.yml's version and build
```

- `archive.sh` fails on signing: read `PlaceLock/build/archive/Cove-*.log`. Usual causes are an expired Apple Distribution certificate or profile, or Xcode signed out of the paid team. Tell the user what to renew; don't edit `ExportOptions.plist` to get around it.
- `upload.sh` says the build number was already used: bump again (step 2) and re-archive.
- Pass along any App Store Connect warning it prints (for example the SDK deadline).

## 4. Log it and push

Add a row at the top of `docs/app-store/builds.md`: the build, today's date, the step 2 commit, what changed in one plain sentence (from the git log), and "Self" under Where. Commit as "Log 1.0.0 (N) in builds.md" and `git push origin main`.

## 5. Report

- What went up and the commit it came from.
- A short **What to Test** note (2–4 lines, plain words) for the user to paste into TestFlight when they add the build to Pilot.
- Next steps for the user:
  - Install it from TestFlight on the iPhone once processing finishes (10–30 min); Settings › About shows the version.
  - Live with it for a day or two, then add it to Pilot.
  - Expire older builds nobody needs.
- If the changes touch the block screen, arrive and leave timing, or relaunch after a force-quit, add a short on-iPhone check list.
