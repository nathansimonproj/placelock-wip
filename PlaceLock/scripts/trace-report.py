#!/usr/bin/env python3
"""Summarize a location trace exported from Debug › Location engine (location-trace.jsonl).

Usage: scripts/trace-report.py TRACE.jsonl [--truth NOTES.txt] [--since "YYYY-MM-DD HH:MM"] [--until …]

Prints:
  - when the new engine (shadow) and the current logic unblocked and blocked, paired up, with
    how much earlier or later the engine was
  - time spent in each tracking mode, bursts, and whether tracking started in the background
  - fix accuracy, and GPS-grade fixes that would have counted toward a block while inside
  - battery drain per hour, overall and by tracking mode (charging time left out)
  - with --truth, each noted arrival and departure against both engines

Truth notes, one per line (times are local, on the trace's days):
  2026-11-24 17:10 Gym arrive
  2026-11-24 18:25 Gym leave

The trace holds real coordinates. This script only reads it and prints distances and times;
nothing leaves the machine.
"""
import datetime as dt
import json
import math
import sys
from collections import Counter, defaultdict

PAIR_WINDOW = 30 * 60      # a current and a shadow decision this close count as the same event
TRUTH_WINDOW = 30 * 60
M_PER_DEG = 111_320.0


def load(path):
    rows = []
    with open(path) as f:
        for n, line in enumerate(f, 1):
            line = line.strip()
            if not line:
                continue
            try:
                rows.append(json.loads(line))
            except json.JSONDecodeError:
                print(f"  (skipped unreadable line {n})", file=sys.stderr)
    rows.sort(key=lambda r: r.get("at", 0))
    return rows


def distance(lat1, lon1, lat2, lon2):
    """Meters, haversine."""
    r = 6_371_000.0
    p1, p2 = math.radians(lat1), math.radians(lat2)
    dp, dl = p2 - p1, math.radians(lon2 - lon1)
    a = math.sin(dp / 2) ** 2 + math.cos(p1) * math.cos(p2) * math.sin(dl / 2) ** 2
    return 2 * r * math.asin(math.sqrt(a))


def when(ts):
    return dt.datetime.fromtimestamp(ts).strftime("%a %H:%M:%S")


def secs(s):
    s = abs(s)
    if s < 120:
        return f"{s:.0f} s"
    if s < 7200:
        return f"{s / 60:.1f} min"
    return f"{s / 3600:.1f} h"


def section(title):
    print(f"\n== {title}")


def report(rows, truth_path=None):
    if not rows:
        print("Empty trace.")
        return
    start, end = rows[0]["at"], rows[-1]["at"]
    print(f"Trace: {len(rows)} records, {when(start)} to {when(end)} ({secs(end - start)})")

    places = {}
    for r in rows:
        if r["kind"] == "places":
            for p in r["places"]:
                places[p["id"]] = p
    section("Places")
    if not places:
        print("  No places record (traces from before 2026-11-23 evening). Distances are skipped.")
    for p in places.values():
        wait = f", waiting until {when(p['activeAfter'])}" if p.get("activeAfter") else ""
        print(f"  {p['name']}: {p['radius']:.0f} m{wait}")

    decisions(rows)
    if truth_path:
        truth(rows, truth_path)
    modes(rows, end)
    fixes(rows, places)
    battery(rows)
    notes(rows)


def same_place(a, b):
    """By ID when both have one (traces from 2026-11-23 evening on), else by name."""
    if a.get("placeID") and b.get("placeID"):
        return a["placeID"] == b["placeID"]
    return a.get("place") == b.get("place")


def decisions(rows):
    section("Unblock and block: new engine (shadow) vs current logic")
    events = [r for r in rows if r["kind"] == "decision"]
    current = [r for r in events if r["engine"] == "current"]
    shadow = [r for r in events if r["engine"] == "shadow"]
    live = [r for r in events if r["engine"] == "live"]
    if not events:
        print("  No decisions recorded.")
        return
    if live:
        print(f"  {len(live)} decisions with the new engine deciding (nothing to compare them with):")
        for r in live:
            print(f"    {when(r['at'])}  {r['what']:6} {r.get('place', '')}")
        if not current:
            return
    used = set()
    lags = defaultdict(list)
    for c in current:
        what = c["what"]
        match = None
        for i, s in enumerate(shadow):
            if i in used or s["what"] != what or not same_place(s, c):
                continue
            if abs(s["at"] - c["at"]) <= PAIR_WINDOW and (match is None or abs(s["at"] - c["at"]) < abs(shadow[match]["at"] - c["at"])):
                match = i
        if match is None:
            print(f"  {when(c['at'])}  {what:6} {c.get('place', ''):16} current only (engine didn't, within {secs(PAIR_WINDOW)})")
            continue
        used.add(match)
        lag = shadow[match]["at"] - c["at"]
        lags[what].append(lag)
        side = "earlier" if lag < 0 else "later"
        print(f"  {when(c['at'])}  {what:6} {c.get('place', ''):16} engine {secs(lag)} {side}")
    for i, s in enumerate(shadow):
        if i not in used:
            print(f"  {when(s['at'])}  {s['what']:6} {s.get('place', ''):16} engine only (current didn't)")
    for what, ls in lags.items():
        ls.sort()
        print(f"  {what}: {len(ls)} paired, median engine {secs(ls[len(ls) // 2])} "
              f"{'earlier' if ls[len(ls) // 2] < 0 else 'later'}")


def truth(rows, path):
    section("Against your notes")
    marks = []
    with open(path) as f:
        for line in f:
            parts = line.split()
            if len(parts) < 4 or parts[-1] not in ("arrive", "leave"):
                continue
            stamp = dt.datetime.strptime(" ".join(parts[:2]), "%Y-%m-%d %H:%M").timestamp()
            marks.append((stamp, " ".join(parts[2:-1]), parts[-1]))
    events = [r for r in rows if r["kind"] == "decision"]
    for stamp, place, kind in marks:
        want = "unlock" if kind == "arrive" else "lock"
        line = f"  {when(stamp)}  {place:16} {kind:6}"
        for engine in ("current", "shadow"):
            hits = [r for r in events if (r["engine"] == engine or (engine == "current" and r["engine"] == "live"))
                    and r["what"] in (want, "move") and r.get("place") in (place, "")
                    and -120 <= r["at"] - stamp <= TRUTH_WINDOW]
            label = "deciding" if engine == "current" else "shadow"
            line += f"  {label}: " + (f"{secs(hits[0]['at'] - stamp)} after" if hits else "none")
        print(line)


def modes(rows, end):
    section("Tracking")
    changes = [r for r in rows if r["kind"] == "mode"]
    totals = Counter()
    bursts = 0
    for a, b in zip(changes, changes[1:] + [{"at": end, "mode": None}]):
        totals[a["mode"]] += b["at"] - a["at"]
        if a["mode"] == "burst":
            bursts += 1
    span = sum(totals.values()) or 1
    for mode in ("dormant", "approach", "edge", "inside", "burst"):
        if totals[mode]:
            print(f"  {mode:9} {secs(totals[mode]):>9}  {100 * totals[mode] / span:5.1f}%")
    inside_hours = (totals["inside"] + totals["burst"]) / 3600
    print(f"  bursts: {bursts}" + (f" ({bursts / inside_hours:.1f} per hour inside a place)" if inside_hours > 0.1 else ""))
    starts = [r for r in rows if r["kind"] == "note" and r["text"].startswith("updates started")]
    back = [r for r in starts if "(back)" in r["text"]]
    worked = 0
    for s in back:
        if any(r["kind"] == "fix" and r.get("source") == "tracking" and 0 < r["at"] - s["at"] <= 60 for r in rows):
            worked += 1
    print(f"  tracking started {len(starts)} times, {len(back)} from the background; "
          f"{worked} of those got a fix within 60 s")


def fixes(rows, places):
    section("Fixes")
    fx = [r for r in rows if r["kind"] == "fix"]
    print("  by source: " + ", ".join(f"{k} {v}" for k, v in Counter(r.get("source") for r in fx).most_common()))
    buckets = Counter()
    for r in fx:
        a = r["acc"]
        buckets["invalid" if a < 0 else "<=10 m" if a <= 10 else "<=30 m" if a <= 30 else "<=65 m" if a <= 65
                else "<=100 m" if a <= 100 else ">100 m"] += 1
    print("  accuracy: " + ", ".join(f"{k} {buckets[k]}" for k in ("<=10 m", "<=30 m", "<=65 m", "<=100 m", ">100 m", "invalid") if buckets[k]))
    if not places:
        return
    # Presence over time, per place, from the engine's own records.
    inside = {}
    risky = []
    current = {}  # the places that exist at this point in the trace
    for r in rows:
        if r["kind"] == "places":
            current = {p["id"]: p for p in r["places"]}
            inside = {pid: v for pid, v in inside.items() if pid in current}
        elif r["kind"] == "presence":
            inside[r["place"]] = r["presence"] == "inside"
        elif r["kind"] == "fix" and 0 <= r["acc"] <= 30 and r["at"] - r.get("fixAt", r["at"]) <= 15:  # fresh only, like the engine
            for pid, p in (current or places).items():
                if not inside.get(pid):
                    continue
                past = distance(r["lat"], r["lon"], p["lat"], p["lon"]) - p["radius"]
                if past > r["acc"] + 25:
                    risky.append((r["at"], p["name"], past, r["acc"]))
    print(f"  GPS-grade fixes clearly outside a place the engine had you inside: {len(risky)}")
    for at, name, past, acc in risky[:15]:
        print(f"    {when(at)}  {name:16} {past:.0f} m past the edge, ±{acc:.0f} m")
    if len(risky) > 15:
        print(f"    … and {len(risky) - 15} more")


def battery(rows):
    section("Battery")
    samples = [(r["at"], r["battery"]) for r in rows if "battery" in r and r["battery"] >= 0]
    if len(samples) < 2:
        print("  Not enough battery readings (the Simulator reports none).")
        return
    mode_at = []
    for r in rows:
        if r["kind"] == "mode":
            mode_at.append((r["at"], r["mode"]))
    drain = Counter()
    hours = Counter()
    for (t1, b1), (t2, b2) in zip(samples, samples[1:]):
        if b2 > b1:  # charging
            continue
        mode = next((m for t, m in reversed(mode_at) if t <= t1), "dormant")
        drain[mode] += (b1 - b2) * 100
        hours[mode] += (t2 - t1) / 3600
    total_h = sum(hours.values())
    if total_h:
        print(f"  overall: {sum(drain.values()) / total_h:.1f}% per hour over {total_h:.1f} h on battery (whole phone)")
    for mode in ("dormant", "approach", "edge", "inside", "burst"):
        if hours[mode] > 0.05:
            print(f"  {mode:9} {drain[mode] / hours[mode]:5.1f}% per hour over {hours[mode]:.1f} h")
    print("  The phone's whole drain, not just Cove's: compare with Settings › Battery.")


def notes(rows):
    section("Checks and errors")
    checks = Counter(r["text"][len("check: "):] for r in rows if r["kind"] == "note" and r["text"].startswith("check: "))
    print("  checks: " + (", ".join(f"{k} {v}" for k, v in checks.most_common()) or "none"))
    errors = [r for r in rows if r["kind"] == "note" and r["text"].startswith("tracking error")]
    print(f"  tracking errors: {len(errors)}")
    for r in errors[:5]:
        print(f"    {when(r['at'])}  {r['text']}")
    visits = [r for r in rows if r["kind"] == "visit"]
    print(f"  visits: {len(visits)}, iOS geofence events: {sum(1 for r in rows if r['kind'] == 'geofence')}")


def main(argv):
    if not argv or argv[0] in ("-h", "--help"):
        print(__doc__)
        return 0 if argv else 2
    opts = {}
    for flag in ("--truth", "--since", "--until"):
        if flag in argv:
            i = argv.index(flag)
            opts[flag] = argv[i + 1]
            argv = argv[:i] + argv[i + 2:]
    rows = load(argv[0])
    for flag, keep in (("--since", lambda at, t: at >= t), ("--until", lambda at, t: at <= t)):
        if flag in opts:
            t = dt.datetime.strptime(opts[flag], "%Y-%m-%d %H:%M").timestamp()
            # Keep the latest places record from before the window, so distances still work.
            before = [r for r in rows if r["kind"] == "places" and not keep(r["at"], t)] if flag == "--since" else []
            rows = before[-1:] + [r for r in rows if keep(r["at"], t)]
    report(rows, opts.get("--truth"))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
