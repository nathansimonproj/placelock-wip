#!/usr/bin/env bash
# Checks a change end to end: unit tests (free build, Simulator), the paid build still compiles,
# the database migrations (when supabase/ changed) and, optionally, Simulator screenshots.
#
# Usage: scripts/verify.sh [--quick] [--no-paid] [--db] [--screens] [--sim "iPhone 17"]
#   --quick     unit tests only
#   --no-paid   skip the paid (Screen Time) compile check
#   --db        run the migration checks even if supabase/ didn't change
#   --screens   install the free build in the Simulator and screenshot the main screens
#   --sim NAME  Simulator to use (default $VERIFY_SIM, else "iPhone 17")
#
# XcodeGen rewrites the project, Info.plists and entitlements. When the script exits it
# regenerates whichever build (free or paid) was generated before, so that one stays open.
# Logs and screenshots go to build/verify/. Exit status is non-zero if any step failed.
set -uo pipefail
cd "$(dirname "$0")/.."   # PlaceLock/

quick=0 paid=1 db=auto screens=0 sim="${VERIFY_SIM:-iPhone 17}"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --quick) quick=1 paid=0 db=0 ;;
    --no-paid) paid=0 ;;
    --db) db=1 ;;
    --screens) screens=1 ;;
    --sim) sim="$2"; shift ;;
    -h|--help) sed -n 2,14p "$0"; exit 0 ;;
    *) echo "Unknown option: $1" >&2; exit 2 ;;
  esac
  shift
done

out=build/verify
mkdir -p "$out"
rm -f "$out"/*.log "$out"/*.png

# On exit (including Ctrl-C), regenerate whichever build was generated before, so the project
# you have open stays free or paid. Regenerating (rather than copying the old project back)
# also picks up source files added since.
if grep -q PlaceLockShield PlaceLock.xcodeproj/project.pbxproj 2>/dev/null; then was=paid; else was=free; fi
restore() {
  if [[ $was == paid ]]; then xcodegen generate --spec project-paid.yml --quiet; else xcodegen generate --quiet; fi
  echo "Project regenerated as the $was build."
}
trap restore EXIT

results=()
failed=0
pass() { results+=("PASS  $1"); }
fail() { results+=("FAIL  $1"); failed=1; }

# Lines worth showing from an xcodebuild log: compiler errors and Swift Testing results.
show_errors() {
  grep -E '(error|warning: .*deprecated):|✘|Test run with|\*\* (BUILD|TEST) FAILED' "$1" | sort -u | head -40
}

# The Simulator named $sim on the newest iOS. scripts/geofence-scenario.py picks the same way, so
# tests, screenshots and scenarios all use one device even when several share the name.
udid="$(xcrun simctl list devices available -j | python3 -c '
import json, re, sys
devices = json.load(sys.stdin)["devices"]
version = lambda rt: [int(x) for x in re.findall(r"\d+", rt.rsplit(".", 1)[-1])]
for rt in sorted(devices, key=version, reverse=True):
    for d in devices[rt]:
        if d["name"] == sys.argv[1]:
            print(d["udid"]); sys.exit()
' "$sim")"
if [[ -z "$udid" ]]; then echo "No available Simulator named \"$sim\"" >&2; exit 2; fi

# 1. Unit tests on the free build.
echo "==> Unit tests (free build, $sim)"
xcodegen generate --quiet
if xcodebuild -project PlaceLock.xcodeproj -scheme PlaceLock \
     -destination "id=$udid" -derivedDataPath build/free \
     test >"$out/test.log" 2>&1; then
  summary="$(grep -E 'Test run with' "$out/test.log" | tail -1)"
  pass "Unit tests: ${summary:-passed (no Swift Testing summary found)}"
else
  show_errors "$out/test.log"
  fail "Unit tests (see $out/test.log)"
fi

# 2. The paid build still compiles (no signing: it can't be signed without the paid team here).
if [[ $paid == 1 ]]; then
  echo "==> Paid build compiles (SCREEN_TIME, extensions)"
  xcodegen generate --spec project-paid.yml --quiet
  if xcodebuild -project PlaceLock.xcodeproj -scheme PlaceLock \
       -destination 'generic/platform=iOS' -derivedDataPath build/paid \
       CODE_SIGNING_ALLOWED=NO build >"$out/paid.log" 2>&1; then
    pass "Paid build compiles"
  else
    show_errors "$out/paid.log"
    fail "Paid build (see $out/paid.log)"
  fi
fi

# 3. Migration checks, when supabase/ has uncommitted changes or differs from main.
if [[ $db == auto ]]; then
  if [[ -n "$(git status --porcelain -- supabase)" ]] \
     || ! git diff --quiet main...HEAD -- supabase 2>/dev/null; then db=1; else db=0; fi
fi
if [[ $db == 1 ]]; then
  echo "==> Migration checks (local Postgres)"
  export PATH="/opt/homebrew/opt/postgresql@16/bin:$PATH"
  if supabase/local-check/run.sh >"$out/db.log" 2>&1; then
    pass "Migration checks"
  else
    tail -20 "$out/db.log"
    fail "Migration checks (see $out/db.log)"
  fi
fi

# 4. Screenshots of the free build in the Simulator.
if [[ $screens == 1 ]]; then
  echo "==> Screenshots ($sim)"
  app=build/free/Build/Products/Debug-iphonesimulator/PlaceLock.app
  if [[ ! -d "$app" ]]; then
    fail "Screenshots: $app missing (did the unit tests build?)"
  else
    xcrun simctl boot "$udid" 2>/dev/null
    xcrun simctl bootstatus "$udid" -b >/dev/null
    xcrun simctl install "$udid" "$app"
    xcrun simctl privacy "$udid" grant location-always com.nsimon.PlaceLock 2>/dev/null
    # name | launch arguments. -onboarded YES skips first-run setup (it's read from UserDefaults).
    shots=(
      "home|-onboarded YES -demoHistory YES"
      "rules|-onboarded YES -tab rules"
      "add-place|-onboarded YES -sheet add"
      "setup-apps|-onboarded NO -onboardingStep apps"
    )
    for shot in "${shots[@]}"; do
      name="${shot%%|*}"; args="${shot#*|}"
      xcrun simctl terminate "$udid" com.nsimon.PlaceLock 2>/dev/null
      # shellcheck disable=SC2086
      xcrun simctl launch "$udid" com.nsimon.PlaceLock $args >/dev/null
      sleep 4
      xcrun simctl io "$udid" screenshot "$out/$name.png" >/dev/null 2>&1
    done
    xcrun simctl terminate "$udid" com.nsimon.PlaceLock 2>/dev/null
    pass "Screenshots: $(cd "$out" && ls ./*.png | tr '\n' ' ')"
  fi
fi

echo
echo "==> Summary"
printf '%s\n' "${results[@]}"
exit $failed
