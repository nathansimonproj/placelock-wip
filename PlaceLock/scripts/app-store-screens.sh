#!/bin/zsh
# Draft App Store screenshots: builds the free Debug app and screenshots it on the
# "iPhone 17 Pro Max" Simulator, whose 1320 x 2868 shots are Apple's 6.9" size. It runs in scenario
# mode (App/Scenario.swift): its own settings store and backup off, so nothing reaches Supabase.
# Demo data goes in as launch arguments, which scenario mode copies into that store.
# Notes on using the shots: docs/app-store/screenshots.md.
#
# Usage: scripts/app-store-screens.sh [out dir]   (default build/app-store-screens)
# It reinstalls Cove on that Simulator, so anything saved there is wiped.
set -u
cd "$(dirname "$0")/.."   # PlaceLock/
out=${1:-build/app-store-screens}
sim="iPhone 17 Pro Max"
app=build/screens/Build/Products/Debug-iphonesimulator/PlaceLock.app
mkdir -p "$out"

if grep -q PlaceLockShield PlaceLock.xcodeproj/project.pbxproj 2>/dev/null; then
  echo "The paid project is generated; run plain xcodegen generate first." >&2; exit 1
fi
# The newest-iOS Simulator with that name, as verify.sh picks.
udid="$(xcrun simctl list devices available -j | python3 -c '
import json, re, sys
devices = json.load(sys.stdin)["devices"]
version = lambda rt: [int(x) for x in re.findall(r"\d+", rt.rsplit(".", 1)[-1])]
for rt in sorted(devices, key=version, reverse=True):
    for d in devices[rt]:
        if d["name"] == sys.argv[1]:
            print(d["udid"]); sys.exit()
' "$sim")"
[[ -n "$udid" ]] || { echo "No available Simulator named \"$sim\"" >&2; exit 1; }

echo "==> Building the free Debug app"
xcodebuild -project PlaceLock.xcodeproj -scheme PlaceLock -destination "id=$udid" \
  -derivedDataPath build/screens build >build/screens.log 2>&1 \
  || { grep -E "error:" build/screens.log | sort -u | head -20; echo "Build failed (see build/screens.log)" >&2; exit 1; }

echo "==> Screenshots ($sim) into $out"
xcrun simctl boot "$udid" 2>/dev/null
xcrun simctl bootstatus "$udid" -b >/dev/null
# A fresh install, so nothing saved by an earlier run (an unlock, say) carries over.
xcrun simctl uninstall "$udid" com.nsimon.PlaceLock 2>/dev/null
xcrun simctl install "$udid" "$app"
xcrun simctl privacy "$udid" grant location-always com.nsimon.PlaceLock
xcrun simctl status_bar "$udid" override --time "9:41" --batteryState charged --batteryLevel 100 \
  --cellularMode active --cellularBars 4 --wifiBars 3 --dataNetwork wifi
# Stand in San Francisco, outside every demo place (about 800 m from the nearest), so apps stay
# blocked; -pretendAt stands in a place for the unlocked shot.
xcrun simctl location "$udid" set 37.7840,-122.4075

# Demo data as plist <hex> data literals: the JSON AppModel would have saved.
eval "$(python3 - <<'EOF'
import json, time
ref = time.time() - 978307200          # JSONEncoder's default Date: seconds since 2001
hexd = lambda v: "<" + json.dumps(v).encode().hex() + ">"
places = [
    {"id": "5C0F5E1A-0000-4000-8000-000000000001", "name": "Home",
     "latitude": 37.7765, "longitude": -122.4241, "radius": 100},
    {"id": "5C0F5E1A-0000-4000-8000-000000000002", "name": "Library", "address": "100 Larkin St",
     "latitude": 37.7790, "longitude": -122.4158, "radius": 150},
    {"id": "5C0F5E1A-0000-4000-8000-000000000003", "name": "Gym",
     "latitude": 37.7740, "longitude": -122.4194, "radius": 100},
]
# Two visits ending before now, so "locked for" and today's count read naturally at any hour.
visits = [
    {"placeID": places[1]["id"], "start": ref - 5.2 * 3600, "end": ref - 3.9 * 3600},
    {"placeID": places[2]["id"], "start": ref - 2.4 * 3600, "end": ref - 1.6 * 3600},
]
apps = {"simulatedApps": ["Instagram", "TikTok", "YouTube", "Reddit"]}
# Unlocked at the library for the last 42 minutes (only passed to the unlocked shot).
session = {"placeID": places[1]["id"], "startedAt": ref - 42 * 60,
           "id": "5C0F5E1A-0000-4000-8000-0000000000AA", "visitStartedAt": ref - 42 * 60}
print(f"P='{hexd(places)}'")
print(f"V='{hexd(visits)}'")
print(f"B='{hexd(apps)}'")
print(f"U='{hexd(session)}'")
print(f"S='{hexd(ref - 3 * 86400)}'")   # setup window ended 3 days ago
import base64
# -scenarioPlaces on every launch wipes the scenario store first, so nothing carries between shots.
print(f"F='{base64.b64encode(json.dumps(places).encode()).decode()}'")
EOF
)"
demo=(-scenario app-store -scenarioPlaces "$F" -onboarded YES -places "$P" -visits "$V" -blockList "$B" -setupEndsAt "$S")

shoot() { # name, launch arguments...
  local name=$1; shift
  xcrun simctl terminate "$udid" com.nsimon.PlaceLock 2>/dev/null
  xcrun simctl launch "$udid" com.nsimon.PlaceLock "$@" >/dev/null
  sleep 5
  xcrun simctl io "$udid" screenshot "$out/$name.png" >/dev/null 2>&1
  echo "$name: $(sips -g pixelWidth -g pixelHeight "$out/$name.png" | awk '/pixel/ {printf "%s ", $2}')"
}
# The first launch after a fresh install sometimes opens on setup; launch once before shooting.
shoot warm-up "${demo[@]}"; rm -f "$out/warm-up.png"
shoot 1-home-locked "${demo[@]}"
shoot 2-home-unlocked "${demo[@]}" -pretendAt Library -session "$U"
shoot 3-settings "${demo[@]}" -tab rules
shoot 4-add-place "${demo[@]}" -sheet add
shoot 5-wait-info "${demo[@]}" -tab rules -sheet wait
for step in location apps places; do
  shoot "6-setup-$step" -scenario app-store -scenarioPlaces "$F" -onboarded NO -onboardingStep $step -blockList "$B"
done
xcrun simctl terminate "$udid" com.nsimon.PlaceLock 2>/dev/null
xcrun simctl status_bar "$udid" clear
