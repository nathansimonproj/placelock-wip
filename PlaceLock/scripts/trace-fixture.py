#!/usr/bin/env python3
"""Turn a location trace into a replay fixture for PlaceLockTests/Traces/ (TraceReplayTests).

Usage: scripts/trace-fixture.py TRACE.jsonl OUT.jsonl [--since "YYYY-MM-DD HH:MM"] [--until …]
                                [--truth NOTES.txt] [--truth-from-fixes]

Privacy: the fixture keeps distances and timing but nothing that says where or when.
  - Every coordinate is moved so the first place sits in Golden Gate Park (where the
    Simulator scenarios are), keeping east/north offsets in meters.
  - Places are renamed "Place 1", "Place 2", … in the order they first appear.
  - Times become seconds from the start of the window.
  - Only places, fixes and iOS geofence readings are kept, plus truth.

Truth (what really happened) comes from your notes (same format as trace-report.py):
  2026-11-24 17:10 Gym arrive
or, for Simulator traces where every fix is exact, from the fixes themselves
(--truth-from-fixes: the first fix inside, and the first fix outside, of each place).
"""
import datetime as dt
import json
import math
import sys

ORIGIN = (37.7694, -122.4862)
M_PER_DEG = 111_320.0


def parse_args(argv):
    opts, rest = {}, []
    i = 0
    while i < len(argv):
        if argv[i] in ("--since", "--until", "--truth"):
            opts[argv[i]] = argv[i + 1]
            i += 2
        elif argv[i] == "--truth-from-fixes":
            opts[argv[i]] = True
            i += 1
        else:
            rest.append(argv[i])
            i += 1
    return opts, rest


def stamp(text):
    return dt.datetime.strptime(text, "%Y-%m-%d %H:%M").timestamp()


def main(argv):
    opts, rest = parse_args(argv)
    if len(rest) != 2:
        print(__doc__)
        return 2
    src, out = rest
    rows = [json.loads(l) for l in open(src) if l.strip()]
    rows.sort(key=lambda r: r["at"])
    since = stamp(opts["--since"]) if "--since" in opts else rows[0]["at"]
    until = stamp(opts["--until"]) if "--until" in opts else rows[-1]["at"]

    # The latest places record at or before the window's start, plus any inside it.
    places_rows = [r for r in rows if r["kind"] == "places"]
    if not places_rows:
        print("This trace has no places record (it's from before 2026-11-23 evening).", file=sys.stderr)
        return 1
    first_places = [r for r in places_rows if r["at"] <= since][-1:] or places_rows[:1]
    window = [r for r in rows if since <= r["at"] <= until]

    names, ids = {}, {}
    origin_src = None

    def move(lat, lon):
        nonlocal origin_src
        if origin_src is None:
            origin_src = (lat, lon)
        north = (lat - origin_src[0]) * M_PER_DEG
        east = (lon - origin_src[1]) * M_PER_DEG * math.cos(math.radians(origin_src[0]))
        return (round(ORIGIN[0] + north / M_PER_DEG, 7),
                round(ORIGIN[1] + east / (M_PER_DEG * math.cos(math.radians(ORIGIN[0]))), 7))

    def name(pid, real):
        if pid not in names:
            names[pid] = f"Place {len(names) + 1}"
            ids[real] = names[pid]
        return names[pid]

    t = lambda at: round(at - since, 3)
    lines = []
    for r in first_places + [r for r in window if r["kind"] == "places" and r not in first_places]:
        ps = []
        for p in r["places"]:
            lat, lon = move(p["lat"], p["lon"])
            entry = {"id": p["id"], "name": name(p["id"], p["name"]), "lat": lat, "lon": lon, "radius": p["radius"]}
            if p.get("activeAfter"):
                entry["activeAfter"] = t(p["activeAfter"])
            ps.append(entry)
        lines.append({"kind": "places", "t": max(0, t(r["at"])), "places": ps})
    for r in window:
        if r["kind"] == "fix":
            lat, lon = move(r["lat"], r["lon"])
            lines.append({"kind": "fix", "t": t(r["at"]), "fixT": t(r["fixAt"]), "lat": lat, "lon": lon,
                          "acc": r["acc"], "speed": r.get("speed", -1), "source": r.get("source", "")})
        elif r["kind"] == "geofence" and not r.get("ring") and r.get("place") in names:
            lines.append({"kind": "geofence", "t": t(r["at"]), "place": r["place"], "presence": r["presence"],
                          "eventT": t(r["eventAt"])})

    if "--truth" in opts:
        for line in open(opts["--truth"]):
            parts = line.split()
            if len(parts) < 4 or parts[-1] not in ("arrive", "leave"):
                continue
            at = stamp(" ".join(parts[:2]))
            real = " ".join(parts[2:-1])
            if since <= at <= until and real in ids:
                lines.append({"kind": "truth", "t": t(at), "place": ids[real], "event": parts[-1]})
            elif real not in ids:
                print(f"  truth for unknown place '{real}' skipped", file=sys.stderr)
    if opts.get("--truth-from-fixes"):
        lines += truth_from_fixes(lines)

    lines.sort(key=lambda l: (l["t"], l["kind"] != "places"))
    with open(out, "w") as f:
        for l in lines:
            f.write(json.dumps(l, sort_keys=True) + "\n")
    print(f"Wrote {len(lines)} lines ({sum(1 for l in lines if l['kind'] == 'fix')} fixes, "
          f"{sum(1 for l in lines if l['kind'] == 'truth')} truth) for {len(names)} places to {out}")
    return 0


def truth_from_fixes(lines):
    """Simulator traces: fixes are exact, so crossings are the truth."""
    places = {}
    for l in lines:
        if l["kind"] == "places":
            for p in l["places"]:
                places[p["id"]] = p
    inside = {pid: None for pid in places}
    out = []
    for l in lines:
        if l["kind"] != "fix":
            continue
        for pid, p in places.items():
            north = (l["lat"] - p["lat"]) * M_PER_DEG
            east = (l["lon"] - p["lon"]) * M_PER_DEG * math.cos(math.radians(p["lat"]))
            now = math.hypot(north, east) <= p["radius"]
            if inside[pid] is not None and now != inside[pid]:
                out.append({"kind": "truth", "t": l["fixT"], "place": p["name"], "event": "arrive" if now else "leave"})
            inside[pid] = now
    return out


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
