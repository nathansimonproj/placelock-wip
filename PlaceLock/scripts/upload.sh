#!/usr/bin/env bash
# Uploads an archive made by scripts/archive.sh to App Store Connect, signed the same way as the
# export (ExportOptions.plist, with destination switched to upload). Uses Xcode's sign-in, so
# Xcode must be signed in to the paid team. It only uploads: adding the build to the Pilot group
# and submitting for review stay in App Store Connect.
#
# Usage: scripts/upload.sh [path/to/Cove-X.Y.Z-N.xcarchive]
#   (no argument)  the archive for the version and build in project.yml
#
# App Store Connect rejects a build number it has already seen for that version, so run
# scripts/bump-build.sh and scripts/archive.sh first. The log goes next to the archive.
set -euo pipefail
cd "$(dirname "$0")/.."   # PlaceLock/

die() { echo "upload.sh: $*" >&2; exit 1; }
plist() { /usr/libexec/PlistBuddy -c "Print :$2" "$1" 2>/dev/null; }
read_setting() {
  local lines
  lines="$(grep -E "^[[:space:]]+$1:" project.yml || true)"
  [[ $(printf '%s' "$lines" | grep -c .) -eq 1 ]] || die "expected exactly one $1 line in project.yml"
  printf '%s' "$lines" | sed -E "s/^[[:space:]]+$1:[[:space:]]*\"?([^\"#[:space:]]*)\"?.*/\1/"
}

case "${1:-}" in -h|--help) sed -n 2,11p "$0"; exit 0 ;; esac

version="$(read_setting MARKETING_VERSION)"
build="$(read_setting CURRENT_PROJECT_VERSION)"
archive="${1:-build/archive/Cove-$version-$build.xcarchive}"
archive="${archive%/}"
[[ -d "$archive" ]] || die "no archive at $archive (run scripts/archive.sh first)"
[[ "$archive" != *-unsigned.xcarchive ]] || die "$archive is from archive.sh --check and can't be uploaded"

# Say what's going up, from the archive itself.
app="$archive/Products/$(plist "$archive/Info.plist" ApplicationProperties:ApplicationPath)"
[[ -d "$app" ]] || die "$archive is not an app archive"
got="$(plist "$app/Info.plist" CFBundleShortVersionString) ($(plist "$app/Info.plist" CFBundleVersion))"

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
cp scripts/ExportOptions.plist "$work/ExportOptions.plist"
/usr/libexec/PlistBuddy -c "Set :destination upload" "$work/ExportOptions.plist"

log="${archive%.xcarchive}-upload.log"
echo "==> Uploading Cove $got to App Store Connect"
if ! xcodebuild -exportArchive -archivePath "$archive" -exportPath "$work/out" \
     -exportOptionsPlist "$work/ExportOptions.plist" -allowProvisioningUpdates >"$log" 2>&1; then
  grep -E 'error:|\*\* EXPORT FAILED' "$log" | sort -u | head -40
  die "upload failed (see $log)"
fi
grep -q "Upload succeeded" "$log" || die "xcodebuild finished but didn't say \"Upload succeeded\" (see $log)"
grep -E '^warning:' "$log" | sort -u || true
echo "==> Uploaded Cove $got. App Store Connect is processing it (usually 10–30 min). Log: $log"
