#!/usr/bin/env bash
# Builds the App Store version of Cove: generates the paid project (Screen Time, Shield
# extension, App Group), archives the Release build and exports a signed .ipa for App Store
# Connect. It never uploads; it prints the upload command at the end.
#
# Usage: scripts/archive.sh [--check]
#   (no options)  archive with automatic signing (paid team) and export the .ipa.
#                 Needs Xcode signed in to the paid team (Xcode > Settings > Accounts).
#   --check       archive without signing and check what's inside, then stop. Needs no account.
#
# Before each upload, raise the build number with scripts/bump-build.sh: App Store Connect
# rejects a build number it has already seen for that version.
# Output goes to build/archive/. Signing and export options: scripts/ExportOptions.plist.
# When it exits it regenerates whichever build (free or paid) was generated before.
set -euo pipefail
cd "$(dirname "$0")/.."   # PlaceLock/

check=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --check) check=1 ;;
    -h|--help) sed -n 2,14p "$0"; exit 0 ;;
    *) echo "Unknown option: $1" >&2; exit 2 ;;
  esac
  shift
done

die() { echo "archive.sh: $*" >&2; exit 1; }
plist() { /usr/libexec/PlistBuddy -c "Print :$2" "$1" 2>/dev/null; }

# Reads `    KEY: value` from a spec (quotes and trailing comments dropped). Exactly one line.
read_setting() {
  local lines
  lines="$(grep -E "^[[:space:]]+$2:" "$1" || true)"
  [[ $(printf '%s' "$lines" | grep -c .) -eq 1 ]] || die "expected exactly one $2 line in $1"
  printf '%s' "$lines" | sed -E "s/^[[:space:]]+$2:[[:space:]]*\"?([^\"#[:space:]]*)\"?.*/\1/"
}

version="$(read_setting project.yml MARKETING_VERSION)"
build="$(read_setting project.yml CURRENT_PROJECT_VERSION)"
team="$(read_setting project-paid.yml DEVELOPMENT_TEAM)"
options=scripts/ExportOptions.plist

# The export options must match the paid spec, and must never upload by themselves.
plutil -lint -s "$options" || die "$options isn't a valid plist"
[[ "$(plist "$options" method)" == app-store-connect ]] || die "$options: method must be app-store-connect"
[[ "$(plist "$options" destination)" == export ]] || die "$options: destination must be export (this script never uploads)"
[[ "$(plist "$options" signingStyle)" == automatic ]] || die "$options: signingStyle must be automatic"
[[ "$(plist "$options" teamID)" == "$team" ]] \
  || die "$options: teamID $(plist "$options" teamID) doesn't match DEVELOPMENT_TEAM $team in project-paid.yml"

if grep -q PlaceLockShield PlaceLock.xcodeproj/project.pbxproj 2>/dev/null; then was=paid; else was=free; fi
restore() {
  if [[ $was == paid ]]; then xcodegen generate --spec project-paid.yml --quiet; else xcodegen generate --quiet; fi
  echo "Project regenerated as the $was build."
}
trap restore EXIT

out=build/archive
mkdir -p "$out"
if [[ $check == 1 ]]; then name="Cove-$version-$build-unsigned"; else name="Cove-$version-$build"; fi
archive="$out/$name.xcarchive"
export_dir="$out/$name-export"
log="$out/$name.log"
rm -rf "$archive" "$export_dir"

echo "==> Archiving Cove $version ($build), paid Release build, team $team"
xcodegen generate --spec project-paid.yml --quiet
if [[ $check == 1 ]]; then signing=(CODE_SIGNING_ALLOWED=NO); else signing=(-allowProvisioningUpdates); fi
if ! xcodebuild -project PlaceLock.xcodeproj -scheme PlaceLock -configuration Release \
     -destination 'generic/platform=iOS' -derivedDataPath build/archive-derived \
     -archivePath "$archive" "${signing[@]}" archive >"$log" 2>&1; then
  grep -E 'error:|\*\* ARCHIVE FAILED' "$log" | sort -u | head -40
  die "archive failed (see $log)"
fi

# What's inside: an app archive (not a "Generic Xcode Archive", which Organizer can't upload),
# the Shield extension, matching version and build, and the export-compliance key.
app="$archive/Products/$(plist "$archive/Info.plist" ApplicationProperties:ApplicationPath)"
[[ -n "$(plist "$archive/Info.plist" ApplicationProperties:ApplicationPath)" && -d "$app" ]] \
  || die "$archive is not an app archive (no ApplicationProperties); Organizer couldn't upload it"
shield="$app/PlugIns/PlaceLockShield.appex"
[[ -d "$shield" ]] || die "the Shield extension is missing from $app"
for bundle in "$app" "$shield"; do
  info="$bundle/Info.plist"
  got="$(plist "$info" CFBundleShortVersionString) ($(plist "$info" CFBundleVersion))"
  [[ "$got" == "$version ($build)" ]] || die "$(basename "$bundle") is $got, expected $version ($build)"
  [[ "$(plist "$info" ITSAppUsesNonExemptEncryption)" == false ]] \
    || die "$(basename "$bundle") doesn't set ITSAppUsesNonExemptEncryption to NO"
done
[[ "$(plist "$app/Info.plist" CFBundleIdentifier)" == com.nsimon.PlaceLock ]] || die "unexpected app bundle ID"
[[ "$(plist "$shield/Info.plist" CFBundleIdentifier)" == com.nsimon.PlaceLock.Shield ]] || die "unexpected Shield bundle ID"
echo "    Archive OK: $archive"
echo "    PlaceLock.app and PlaceLockShield.appex are both $version ($build), encryption exempt."

if [[ $check == 1 ]]; then
  echo "==> Check passed. Unsigned, so not exported. Run without --check to export for App Store Connect."
  exit 0
fi

echo "==> Exporting for App Store Connect (automatic signing)"
if ! xcodebuild -exportArchive -archivePath "$archive" -exportPath "$export_dir" \
     -exportOptionsPlist "$options" -allowProvisioningUpdates >>"$log" 2>&1; then
  grep -E 'error:|\*\* EXPORT FAILED' "$log" | sort -u | head -40
  die "export failed (see $log)"
fi
ipa="$(find "$export_dir" -maxdepth 1 -name '*.ipa' | head -1)"
[[ -n "$ipa" ]] || die "export finished but no .ipa in $export_dir"

echo "==> Exported: $ipa"
echo
echo "Not uploaded. To upload, either open the archive in Xcode's Organizer and click Distribute App:"
echo "  open \"$PWD/$archive\""
echo "or check and upload the .ipa with an app-specific password saved in the keychain as SPOTS_ASC"
echo "(xcrun altool --store-password-in-keychain-item SPOTS_ASC -u <Apple ID> -p <app-specific password>):"
echo "  xcrun altool --validate-app -f \"$PWD/$ipa\" -t ios -p @keychain:SPOTS_ASC"
echo "  xcrun altool --upload-app -f \"$PWD/$ipa\" -t ios -p @keychain:SPOTS_ASC"
