#!/usr/bin/env bash
# Checks a change end to end: unit tests (free build, Simulator), the paid build still compiles,
# the database migrations (when supabase/ changed) and, optionally, Simulator screenshots.
#
# Usage: scripts/verify.sh [--quick] [--no-paid] [--release] [--db] [--screens] [--large-text] [--sim "iPhone 17"]
#   --quick     unit tests only
#   --no-paid   skip the paid (Screen Time) compile check
#   --release   also compile the paid build in Release (what ships to the App Store)
#   --db        run the migration checks even if supabase/ didn't change
#   --screens   install the free build in the Simulator and screenshot the main screens
#   --large-text  --screens, plus the same screens at the largest accessibility text size (large-*.png)
#   --sim NAME  Simulator to use (default $VERIFY_SIM, else "iPhone 17")
#
# XcodeGen rewrites the project, Info.plists and entitlements. When the script exits it
# regenerates whichever build (free or paid) was generated before, so that one stays open.
# Logs and screenshots go to build/verify/. Exit status is non-zero if any step failed.
set -uo pipefail
cd "$(dirname "$0")/.."   # PlaceLock/

quick=0 paid=1 release=0 db=auto screens=0 large=0 sim="${VERIFY_SIM:-iPhone 17}"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --quick) quick=1 paid=0 release=0 db=0 ;;
    --release) release=1 ;;
    --no-paid) paid=0 ;;
    --db) db=1 ;;
    --screens) screens=1 ;;
    --large-text) screens=1 large=1 ;;
    --sim) sim="$2"; shift ;;
    -h|--help) sed -n 2,16p "$0"; exit 0 ;;
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
run_tests() {
  xcodebuild -project PlaceLock.xcodeproj -scheme PlaceLock \
    -destination "id=$udid" -derivedDataPath build/free \
    test >"$out/test.log" 2>&1
}
# The Simulator sometimes dies before the tests start (most often with several Simulators
# running). That says nothing about the code, so restart this Simulator and try once more.
sim_broke() {
  grep -qE 'before establishing connection|IS NOT still alive|Unable to boot|Failed to install or launch the test runner|CoreSimulatorService connection (became invalid|interrupted)' "$out/test.log"
}
tests_ok=0
if run_tests; then
  tests_ok=1
elif sim_broke; then
  echo "    Simulator failed before the tests started; restarting it and trying again"
  cp "$out/test.log" "$out/test-first-try.log"
  xcrun simctl shutdown "$udid" 2>/dev/null
  xcrun simctl boot "$udid" 2>/dev/null
  xcrun simctl bootstatus "$udid" -b >/dev/null 2>&1
  run_tests && tests_ok=1
fi
if [[ $tests_ok == 1 ]]; then
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

# 2b. The paid build in Release, which is what ships: catches code that only compiles with DEBUG.
if [[ $release == 1 ]]; then
  echo "==> Paid Release build compiles"
  xcodegen generate --spec project-paid.yml --quiet
  if xcodebuild -project PlaceLock.xcodeproj -scheme PlaceLock -configuration Release \
       -destination 'generic/platform=iOS' -derivedDataPath build/release \
       CODE_SIGNING_ALLOWED=NO build >"$out/release.log" 2>&1; then
    pass "Paid Release build compiles"
    # Debug-only code (#if DEBUG) and the free build's stand-ins (#if !SCREEN_TIME) must not ship.
    # Swift names its types and members in the symbol table, so look for them there.
    bin=build/release/Build/Products/Release-iphoneos/PlaceLock.app/PlaceLock
    debug_only='DebugView|MockShieldView|SimulatedAppPicker|SimulatedApps|SimulatedSpot|simulatedSpot|skipDelays|Scenario'
    syms="$out/release-symbols.txt"
    if [[ ! -f "$bin" ]]; then
      fail "Release binary missing: $bin"
    elif ! nm -U "$bin" | xcrun swift-demangle >"$syms"; then
      fail "Debug-only check: couldn't list the symbols in $bin"
    elif leaked="$(grep 'PlaceLock\.' "$syms" | grep -oE "\b($debug_only)\b" | sort -u | tr '\n' ' ')"; [[ -n "$leaked" ]]; then
      fail "Debug-only code in the paid Release build: $leaked(see $syms)"
    elif ! grep -q 'PlaceLock\.AppModel' "$syms"; then
      fail "Debug-only check: no Swift symbols found in $bin, so it can't tell"
    else
      pass "No debug-only code in the paid Release build"
    fi
  else
    show_errors "$out/release.log"
    fail "Paid Release build (see $out/release.log)"
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
    # Home while unlocked needs a place to stand in. A geofence scenario's store (App/Scenario.swift)
    # gets one without touching the Simulator's own places, and -pretendAt stands there.
    fixture="$(python3 -c 'import base64, json; print(base64.b64encode(json.dumps([{
      "id": "5C0F5E1A-0000-4000-8000-000000000001", "name": "Library",
      "latitude": 37.7786, "longitude": -122.4159, "radius": 150}]).encode()).decode())')"
    # name | launch arguments. -onboarded YES skips first-run setup (it's read from UserDefaults).
    shots=(
      "home|-onboarded YES -demoHistory YES"
      "home-unlocked|-scenario screens -scenarioPlaces $fixture -pretendAt Library"
      "rules|-onboarded YES -tab rules"
      "about|-onboarded YES -tab rules -scrollTo about"
      "wait-info|-onboarded YES -tab rules -sheet wait"
      "backup|-onboarded YES -tab rules -push backup"
      "debug|-onboarded YES -tab rules -push debug"
      "add-place|-onboarded YES -sheet add"
      "setup-apps|-onboarded NO -onboardingStep apps"
    )
    empty=()
    take_shots() { # $1: file name prefix
      for shot in "${shots[@]}"; do
        name="$1${shot%%|*}"; args="${shot#*|}"
        xcrun simctl terminate "$udid" com.nsimon.PlaceLock 2>/dev/null
        # shellcheck disable=SC2086
        xcrun simctl launch "$udid" com.nsimon.PlaceLock $args >/dev/null
        sleep 4
        xcrun simctl io "$udid" screenshot "$out/$name.png" >/dev/null 2>&1
        # A Simulator that shut down mid-step leaves an empty or missing file.
        [[ -s "$out/$name.png" ]] || empty+=("$name")
      done
      xcrun simctl terminate "$udid" com.nsimon.PlaceLock 2>/dev/null
    }
    take_shots ""
    if [[ $large == 1 ]]; then
      # The largest accessibility text size, then back to what the Simulator had.
      size="$(xcrun simctl ui "$udid" content_size 2>/dev/null)"
      xcrun simctl ui "$udid" content_size accessibility-extra-extra-extra-large
      take_shots large-
      xcrun simctl ui "$udid" content_size "${size:-large}"
    fi
    if (( ${#empty[@]} > 0 )); then
      fail "Screenshots empty or missing: ${empty[*]} (did the Simulator shut down? run again)"
    else
      pass "Screenshots: $(cd "$out" && ls ./*.png | tr '\n' ' ')"
    fi
  fi
fi

echo
echo "==> Summary"
printf '%s\n' "${results[@]}"
exit $failed
