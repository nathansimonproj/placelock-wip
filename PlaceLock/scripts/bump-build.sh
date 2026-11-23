#!/usr/bin/env bash
# Raises the build number in project.yml by one, and optionally sets a new version, then
# regenerates the project. Run it before every App Store Connect upload: each upload needs a
# higher build number than the last one for that version.
#
# Usage: scripts/bump-build.sh [--version X.Y.Z]
#   (no options)       build 7 -> 8, version unchanged
#   --version 1.1.0    version -> 1.1.0 and build 7 -> 8
#
# Both Info.plists read MARKETING_VERSION and CURRENT_PROJECT_VERSION from project.yml, so the
# app and the Shield extension always match. It regenerates the free project, or the paid one if
# that's the one generated right now, so the project you have open stays the same kind.
set -euo pipefail
cd "$(dirname "$0")/.."   # PlaceLock/

spec=project.yml
version=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --version)
      [[ $# -ge 2 ]] || { echo "--version needs a value like 1.1.0" >&2; exit 2; }
      version="$2"; shift ;;
    -h|--help) sed -n 2,11p "$0"; exit 0 ;;
    *) echo "Unknown option: $1" >&2; exit 2 ;;
  esac
  shift
done

# App Store Connect takes up to three dot-separated whole numbers for the version.
if [[ -n $version && ! $version =~ ^[0-9]+(\.[0-9]+){0,2}$ ]]; then
  echo "Version must look like 1.1.0 (up to three numbers), got \"$version\"" >&2
  exit 2
fi

# Reads `    KEY: "value"` (quotes optional) from the spec. Exactly one line must match.
read_setting() {
  local lines
  lines="$(grep -E "^[[:space:]]+$1:" "$spec" || true)"
  if [[ $(printf '%s' "$lines" | grep -c .) -ne 1 ]]; then
    echo "Expected exactly one $1 line in $spec" >&2
    exit 1
  fi
  printf '%s' "$lines" | sed -E "s/^[[:space:]]+$1:[[:space:]]*\"?([^\"#[:space:]]*)\"?.*/\1/"
}
write_setting() {
  sed -E -i '' "s/^([[:space:]]+$1:[[:space:]]*).*/\1\"$2\"/" "$spec"
}

old_build="$(read_setting CURRENT_PROJECT_VERSION)"
old_version="$(read_setting MARKETING_VERSION)"
if [[ ! $old_build =~ ^[0-9]+$ ]]; then
  echo "CURRENT_PROJECT_VERSION in $spec isn't a whole number: \"$old_build\"" >&2
  exit 1
fi
new_build=$((old_build + 1))
new_version="${version:-$old_version}"

write_setting CURRENT_PROJECT_VERSION "$new_build"
write_setting MARKETING_VERSION "$new_version"

# Check the edit landed before regenerating.
if [[ $(read_setting CURRENT_PROJECT_VERSION) != "$new_build" || $(read_setting MARKETING_VERSION) != "$new_version" ]]; then
  echo "Couldn't update $spec; check it by hand." >&2
  exit 1
fi

if grep -q PlaceLockShield PlaceLock.xcodeproj/project.pbxproj 2>/dev/null; then
  xcodegen generate --spec project-paid.yml --quiet
  kind=paid
else
  xcodegen generate --quiet
  kind=free
fi

echo "Version $old_version ($old_build) -> $new_version ($new_build). Regenerated the $kind project."
