#!/usr/bin/env python3
"""Play a scripted walk through saved places in the Simulator and check that apps lock and unlock.

Usage: scripts/geofence-scenario.py SCENARIO... [--build] [--sim NAME]
       scripts/geofence-scenario.py --all

  SCENARIO  a file, or a name in scripts/scenarios/ (".txt" optional)
  --all     run every scenario in scripts/scenarios/
  --build   build the free app first (scripts/verify.sh --quick), then install it
  --sim     Simulator to use (default "Spots Scenarios", created on first use as an iPhone 17
            on the newest iOS). Keep it to itself: anything else that launches the app on it
            (xcodebuild test, you in Xcode) restarts the app outside scenario mode mid-run.

The app runs in scenario mode (`-scenario`, App/Scenario.swift): its own settings store loaded
with the scenario's places, and backup off, so no Supabase traffic. Output (app log,
screenshots) goes to build/scenarios/<name>/.

Scenario file, one step per line (# starts a comment):

  place NAME LAT LON RADIUS [inactive]   a saved place; "inactive" = still waiting out its 24 h
  at NAME [+M|-M]          stand at a place's center, or M meters north of its edge (+ outside, - inside)
  at LAT LON               stand at a coordinate
  walk NAME [+M|-M] [speed S]   walk there in a straight line from the current spot (default 1.4 m/s)
  launch                   start the app (the first launch loads the places)
  relaunch                 quit and start the app again; its state is kept
  kill                     quit the app (like a force-quit)
  background               send the app to the background (opens Settings)
  foreground               bring the app back to the front
  wait SECONDS
  expect EVENT [within SECONDS]       wait for EVENT after the last action (default 60 s)
  expect-no EVENT [for SECONDS]       EVENT must not happen for SECONDS (default 30 s)
  screenshot NAME

  EVENT:  unlock NAME | lock ["reason text"] | move | locked | unlocked [NAME] | log /REGEX/
          "locked" / "unlocked" are the app's current state, followed from its log.
"""
import base64
import json
import math
import os
import re
import shlex
import subprocess
import sys
import threading
import time
import uuid

BUNDLE = "com.nsimon.PlaceLock"
HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)  # PlaceLock/
APP = os.path.join(ROOT, "build/free/Build/Products/Debug-iphonesimulator/PlaceLock.app")
OUT = os.path.join(ROOT, "build/scenarios")
REF_EPOCH = 978307200  # Foundation dates are seconds since 2001-01-01
M_PER_DEG_LAT = 111_320


class ScenarioError(Exception):
    pass


def run(*args, check=True):
    r = subprocess.run(args, capture_output=True, text=True)
    if check and r.returncode != 0:
        raise ScenarioError(f"{' '.join(args)} failed: {(r.stderr or r.stdout).strip()}")
    return r.stdout


def simctl(*args, **kw):
    return run("xcrun", "simctl", *args, **kw)


DEFAULT_SIM = "Spots Scenarios"


def find_sim(name):
    """The Simulator named `name` on the newest iOS. The default one is created if missing."""
    devices = json.loads(simctl("list", "devices", "available", "-j"))["devices"]
    version = lambda rt: [int(x) for x in re.findall(r"\d+", rt.rsplit(".", 1)[-1])]
    for runtime in sorted(devices, key=version, reverse=True):
        for d in devices[runtime]:
            if d["name"] == name:
                return d["udid"]
    if name != DEFAULT_SIM:
        raise ScenarioError(f'No available Simulator named "{name}"')
    runtimes = [r for r in json.loads(simctl("list", "runtimes", "available", "-j"))["runtimes"]
                if r["platform"] == "iOS"]
    if not runtimes:
        raise ScenarioError("No iOS Simulator runtime installed")
    newest = max(runtimes, key=lambda r: [int(x) for x in r["version"].split(".")])
    print(f'Creating the "{name}" Simulator (iPhone 17, iOS {newest["version"]})')
    return simctl("create", name, "iPhone 17", newest["identifier"]).strip()


class LogWatcher:
    """Collects the app's log lines (subsystem com.nsimon.PlaceLock) with arrival times."""

    def __init__(self, udid, path):
        self.lines = []  # (monotonic time, message)
        self.lock = threading.Lock()
        self.file = open(path, "w")
        self.proc = subprocess.Popen(
            ["xcrun", "simctl", "spawn", udid, "log", "stream", "--level", "info", "--style", "ndjson",
             "--predicate", f'subsystem == "{BUNDLE}"'],
            stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, text=True)
        self.attached = threading.Event()
        threading.Thread(target=self._read, daemon=True).start()
        # `log stream` prints a "Filtering the log data…" line once it's listening. Until then
        # app lines are lost, and on a freshly booted Simulator that takes several seconds.
        if not self.attached.wait(30):
            raise ScenarioError("The Simulator's log stream didn't start within 30 s")
        time.sleep(0.5)

    def _read(self):
        for raw in self.proc.stdout:
            self.attached.set()
            try:
                msg = json.loads(raw).get("eventMessage")
            except json.JSONDecodeError:
                continue
            if msg is None:
                continue
            with self.lock:
                self.lines.append((time.monotonic(), msg))
            self.file.write(f"{time.strftime('%H:%M:%S')}  {msg}\n")
            self.file.flush()

    def since(self, t):
        with self.lock:
            return [(ts, m) for ts, m in self.lines if ts >= t]

    def stop(self):
        self.proc.terminate()
        self.file.close()


# --- Scenario files --------------------------------------------------------------------------

def strip_comment(line):
    """Drops a whole-line "# ..." or a trailing " # ...", keeping "#" inside a /regex/."""
    line = line.strip()
    if line.startswith("#"):
        return ""
    m = re.search(r"\s#\s", line)
    return (line[:m.start()] if m else line).strip()


def parse(path):
    places, steps = {}, []
    with open(path) as f:
        for n, line in enumerate(f, 1):
            line = strip_comment(line)
            if not line:
                continue
            cmd, *args = shlex.split(line)
            if cmd == "place":
                if len(args) not in (4, 5) or (len(args) == 5 and args[4] != "inactive"):
                    raise ScenarioError(f"{path}:{n}: place NAME LAT LON RADIUS [inactive]")
                places[args[0]] = {
                    # New IDs every run: iOS keeps a geofence's last reading per ID, so reusing
                    # one carries "inside" over from the previous scenario (seen 2026-11-22).
                    "id": str(uuid.uuid4()).upper(),
                    "name": args[0], "latitude": float(args[1]), "longitude": float(args[2]),
                    "radius": float(args[3]), "inactive": len(args) == 5}
            else:
                steps.append((n, cmd, args))
    if not places:
        raise ScenarioError(f"{path}: no places")
    return places, steps


def point(places, args, n):
    """at/walk target -> (lat, lon, remaining args). Accepts NAME [+M|-M] or LAT LON."""
    if args and args[0] in places:
        p = places[args[0]]
        lat, lon, rest = p["latitude"], p["longitude"], args[1:]
        if rest and re.fullmatch(r"[+-]\d+(\.\d+)?", rest[0]):
            lat += (p["radius"] + float(rest[0])) / M_PER_DEG_LAT  # north of the edge
            rest = rest[1:]
        return lat, lon, rest
    try:
        return float(args[0]), float(args[1]), args[2:]
    except (IndexError, ValueError):
        raise ScenarioError(f"line {n}: expected a place name or LAT LON, got '{' '.join(args)}'")


def distance(a, b):
    dlat = (b[0] - a[0]) * M_PER_DEG_LAT
    dlon = (b[1] - a[1]) * M_PER_DEG_LAT * math.cos(math.radians(a[0]))
    return math.hypot(dlat, dlon)


# --- Running ---------------------------------------------------------------------------------

class Runner:
    def __init__(self, udid, name, places, out):
        self.udid, self.name, self.places, self.out = udid, name, places, out
        self.by_id = {p["id"]: p["name"] for p in places.values()}
        self.launched = False
        self.restart_next = False
        self.here = None
        self.walking = None  # (start time, from, to, speed) while a walk step plays
        self.mark = time.monotonic()  # time of the last action; expects look from here
        self.results = []
        self.log = LogWatcher(udid, os.path.join(out, "app.log"))

    def teardown(self):
        simctl("terminate", self.udid, BUNDLE, check=False)
        simctl("location", self.udid, "clear", check=False)
        self.log.stop()

    def act(self):
        self.mark = time.monotonic()

    def set_location(self, lat, lon):
        simctl("location", self.udid, "set", f"{lat:.6f},{lon:.6f}")
        self.here = (lat, lon)
        self.walking = None

    def launch(self):
        if self.here is None:
            raise ScenarioError("Set a location (at …) before launch")
        args = ["-scenario", self.name]
        first = not self.launched
        if first:
            now_ref = time.time() - REF_EPOCH
            fixture = []
            for p in self.places.values():
                entry = {k: p[k] for k in ("id", "name", "latitude", "longitude", "radius")}
                if p["inactive"]:
                    entry["activeAfter"] = now_ref + 24 * 3600
                fixture.append(entry)
            args += ["-scenarioPlaces", base64.b64encode(json.dumps(fixture).encode()).decode()]
        # iOS may have relaunched the app in the background for a geofence event (a leftover
        # scenario place, say), without launch arguments and so on your real places. Launching
        # without --terminate-running-process would only bring that copy to the front.
        restart = ["--terminate-running-process"] if first or self.restart_next else []
        self.restart_next = False
        start = time.monotonic()
        simctl("launch", *restart, self.udid, BUNDLE, *args)
        self.launched = True
        if not first:
            return
        # Never carry on unless the app is really running on the scenario's places.
        want = re.compile(rf"^Launch: {len(self.places)} places, session=none$")
        if self.wait_for(want, start, 20):
            return
        # A background relaunch can race the first launch: in an --all run, the previous
        # scenario's circles fire an exit when this one jumps away, and that copy (no launch
        # arguments) can win. Stop it and launch once more before giving up.
        first_try = "\n".join(f"    {m}" for _, m in self.log.since(start)[:8])
        print("    The app didn't start in scenario mode; stopping it and launching again", flush=True)
        simctl("terminate", self.udid, BUNDLE, check=False)
        time.sleep(2)
        start = time.monotonic()
        simctl("launch", "--terminate-running-process", self.udid, BUNDLE, *args)
        if not self.wait_for(want, start, 20):
            lines = "\n".join(f"    {m}" for _, m in self.log.since(start)[:8])
            raise ScenarioError(f"The app didn't start in scenario mode with {len(self.places)} places, "
                                f"twice. Is the installed build older than App/Scenario.swift?\n"
                                f"  First try's log:\n{first_try}\n  Second try's log:\n{lines}")

    def wait_for(self, pattern, since, seconds):
        deadline = time.monotonic() + seconds
        while True:
            hit = next(((ts, m) for ts, m in self.log.since(since) if pattern.search(m)), None)
            if hit or time.monotonic() >= deadline:
                return hit
            time.sleep(0.3)

    def session(self, until):
        """The unlocked place's name (or None when locked) as of time `until`, from the log."""
        state = None
        for ts, m in self.log.since(0):
            if ts > until:
                break
            if m.startswith("Auto-unlock at "):
                state = m[len("Auto-unlock at "):]
            elif m.startswith("Moved session from "):
                state = self.by_id.get(m.rsplit(" ", 1)[-1], "?")
            elif m.startswith("Lock (was unlocked"):
                state = None
            elif m.startswith("Launch: "):
                s = m.rsplit("session=", 1)[-1]
                state = None if s == "none" else s
        return state

    def where_on_walk(self, t, message):
        """During a walk: how far from the nearest place's edge (or the one named in message)
        the simulated phone was at time t, e.g. " (~140 m outside Gym's edge)"."""
        if not self.walking:
            return ""
        start_t, a, b, speed = self.walking
        total = distance(a, b)
        f = min(1.0, speed * (t - start_t) / total) if total else 1.0
        pos = (a[0] + (b[0] - a[0]) * f, a[1] + (b[1] - a[1]) * f)
        edge = lambda p: distance(pos, (p["latitude"], p["longitude"])) - p["radius"]
        # The place the line names first ("Left Gym", or the place a session moved from).
        named = sorted((p for p in self.places.values() if p["name"] in message or p["id"] in message),
                       key=lambda p: min(i for i in (message.find(p["name"]), message.find(p["id"])) if i >= 0))
        p = named[0] if named else min(self.places.values(), key=edge)
        return f" (~{abs(edge(p)):.0f} m {'outside' if edge(p) > 0 else 'inside'} {p['name']}'s edge)"

    def step(self, n, cmd, args):
        if cmd == "at":
            lat, lon, _ = point(self.places, args, n)
            self.set_location(lat, lon)
            self.act()
        elif cmd == "walk":
            lat, lon, rest = point(self.places, args, n)
            speed = float(rest[1]) if len(rest) == 2 and rest[0] == "speed" else 1.4
            if self.here is None:
                raise ScenarioError(f"line {n}: walk needs a starting spot (at …)")
            meters = distance(self.here, (lat, lon))
            simctl("location", self.udid, "start", f"--speed={speed}",
                   f"{self.here[0]:.6f},{self.here[1]:.6f}", f"{lat:.6f},{lon:.6f}")
            print(f"      walking {meters:.0f} m at {speed} m/s (~{meters / speed:.0f} s)")
            self.act()
            self.walking = (self.mark, self.here, (lat, lon), speed)
            self.here = (lat, lon)
        elif cmd == "launch":
            self.act()
            self.launch()
        elif cmd == "relaunch":
            simctl("terminate", self.udid, BUNDLE, check=False)
            time.sleep(1)
            self.act()
            self.launch()
        elif cmd == "kill":
            simctl("terminate", self.udid, BUNDLE, check=False)
            self.restart_next = True  # a background relaunch after this wouldn't be in scenario mode
            self.act()
        elif cmd == "background":
            simctl("launch", self.udid, "com.apple.Preferences")
            self.act()
        elif cmd == "foreground":
            self.act()
            self.launch()  # brings it to the front, or starts it (in scenario mode) after a kill
        elif cmd == "wait":
            time.sleep(float(args[0]))
        elif cmd == "screenshot":
            simctl("io", self.udid, "screenshot", os.path.join(self.out, f"{args[0]}.png"))
        elif cmd in ("expect", "expect-no"):
            self.expect(n, cmd == "expect-no", args)
        else:
            raise ScenarioError(f"line {n}: unknown step '{cmd}'")

    def event(self, words, n):
        """EVENT words -> (description, log pattern or None, state check or None)."""
        kind, rest = words[0], " ".join(words[1:])
        if kind == "unlock":
            return f"unlock at {rest}", re.compile(rf"^Auto-unlock at {re.escape(rest)}$"), None
        if kind == "lock":
            reason = rf".*{re.escape(rest)}" if rest else ""
            return f"lock{f' ({rest})' if rest else ''}", re.compile(rf"^Lock \(was unlocked: true\): {reason}"), None
        if kind == "move":
            return "session moved to another place", re.compile(r"^Moved session from"), None
        if kind == "log":
            return f"log /{rest.strip('/')}/", re.compile(rest.strip("/")), None
        if kind == "locked":
            return "locked", None, lambda t: self.session(t) is None
        if kind == "unlocked":
            if rest and rest not in self.places:
                raise ScenarioError(f"line {n}: unknown place '{rest}'")
            return (f"unlocked{f' at {rest}' if rest else ''}", None,
                    lambda t: self.session(t) is not None and (not rest or self.session(t) == rest))
        raise ScenarioError(f"line {n}: unknown event '{kind}'")

    def expect(self, n, negate, args):
        seconds = 30.0 if negate else 60.0
        if len(args) >= 2 and args[-2] in ("within", "for"):
            seconds, args = float(args[-1]), args[:-2]
        desc, pattern, check = self.event(args, n)
        start = time.monotonic()
        deadline = start + seconds
        while True:
            now = time.monotonic()
            if check:
                found = (now, "") if check(now) else None
            else:
                found = next(((ts, m) for ts, m in self.log.since(self.mark) if pattern.search(m)), None)
            if found or now >= deadline:
                break
            time.sleep(0.3)
        if negate:
            ok = found is None
            detail = f"no {desc} for {seconds:.0f} s" if ok else f"{desc} happened after {found[0] - self.mark:.1f} s"
        elif check:  # current state: report how long the check waited, not time since the action
            ok = found is not None
            waited = found[0] - start if ok else seconds
            actual = self.session(time.monotonic())
            detail = (f"{desc}{f' (after waiting {waited:.1f} s)' if waited >= 1 else ''}" if ok
                      else f"not {desc} after {seconds:.0f} s (now {'unlocked at ' + actual if actual else 'locked'})")
        else:
            ok = found is not None
            detail = (f"{desc} after {found[0] - self.mark:.1f} s{self.where_on_walk(*found)}" if ok
                      else f"no {desc} within {seconds:.0f} s")
        self.results.append((ok, n, detail))
        print(f"      {'PASS' if ok else 'FAIL'}  {detail}")


def run_scenario(path, udid):
    name = os.path.splitext(os.path.basename(path))[0]
    out = os.path.join(OUT, name)
    os.makedirs(out, exist_ok=True)
    for f in os.listdir(out):
        os.remove(os.path.join(out, f))
    print(f"\n==> {name}")
    error, runner = None, None
    try:
        places, steps = parse(path)
        simctl("terminate", udid, BUNDLE, check=False)
        runner = Runner(udid, name, places, out)
        t0 = time.monotonic()
        for n, cmd, args in steps:
            print(f"  {time.monotonic() - t0:6.1f}s  {cmd} {' '.join(args)}")
            runner.step(n, cmd, args)
    except ScenarioError as e:
        error = str(e)
    except KeyboardInterrupt:
        error = "interrupted"
    finally:
        if runner:
            runner.teardown()
    if error:
        print(f"  ERROR  {error}")
    results = runner.results if runner else []
    failed = [r for r in results if not r[0]]
    ok = not error and not failed
    print(f"  {'PASS' if ok else 'FAIL'}  {name}: {len(results) - len(failed)}/{len(results)} checks"
          f"{' (stopped early)' if error else ''}. Log: {os.path.relpath(out, os.getcwd())}/app.log")
    return ok


def main(argv):
    sim, build, names = DEFAULT_SIM, False, []
    i = 0
    while i < len(argv):
        a = argv[i]
        if a == "--sim":
            sim, i = argv[i + 1], i + 1
        elif a == "--build":
            build = True
        elif a == "--all":
            folder = os.path.join(HERE, "scenarios")
            names += sorted(os.path.join(folder, f) for f in os.listdir(folder) if f.endswith(".txt"))
        elif a in ("-h", "--help"):
            print(__doc__)
            return 0
        else:
            names.append(a)
        i += 1
    if not names:
        print(__doc__)
        return 2
    paths = []
    for n in names:
        candidates = [n, os.path.join(HERE, "scenarios", n), os.path.join(HERE, "scenarios", n + ".txt")]
        found = next((c for c in candidates if os.path.isfile(c)), None)
        if not found:
            print(f"No scenario '{n}'", file=sys.stderr)
            return 2
        paths.append(found)

    if build:
        print("==> Building (scripts/verify.sh --quick)")
        if subprocess.run([os.path.join(HERE, "verify.sh"), "--quick"]).returncode != 0:
            return 1
    if not os.path.isdir(APP):
        print(f"{APP} is missing. Run with --build, or scripts/verify.sh first.", file=sys.stderr)
        return 1
    try:
        udid = find_sim(sim)
        simctl("boot", udid, check=False)
        simctl("bootstatus", udid, "-b")
        for attempt in range(3):  # right after a cold boot, CoreSimulator can drop the first try
            try:
                simctl("install", udid, APP)
                break
            except ScenarioError:
                if attempt == 2:
                    raise
                time.sleep(5)
        simctl("privacy", udid, "grant", "location-always", BUNDLE, check=False)
    except ScenarioError as e:
        print(e, file=sys.stderr)
        return 1
    print(f"Simulator: {sim} ({udid})")

    results = [run_scenario(p, udid) for p in paths]
    print(f"\n==> {sum(results)}/{len(results)} scenarios passed")
    return 0 if all(results) else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
