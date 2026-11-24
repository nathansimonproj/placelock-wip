#!/usr/bin/env bash
# Works through .night/queue.md unattended: one fresh headless Claude run per task, in a
# separate git worktree on a night/<date> branch, so your own checkout is never touched.
#
# Usage: PlaceLock/scripts/night.sh [--until HH:MM] [--runs N] [--hours H] [--final-minutes M]
#                                    [--fallback-model MODEL] [--base REF]
#   --until HH:MM      stop by this clock time, e.g. 07:30 (the final phase starts M minutes before)
#   --runs N           stop after N runs (default 30; use 1 for a dry run)
#   --hours H          stop starting new runs after H hours, plus up to 1 h for "(final)" tasks (default 8)
#   --final-minutes M  spend the last M minutes on tasks marked "(final)" (default 90)
#   --fallback-model M on an Opus-only usage limit, carry on with model M (e.g. sonnet) instead
#                      of pausing; off by default
#   --base REF         branch the night work from REF (default main)
#
# Checks and fallbacks:
#   - Before the first run, the branch must pass verify.sh --release. If it doesn't, nothing runs.
#   - After every run that changed code, this script runs verify.sh itself. If it fails, that
#     run's commits move to night/<date>-rejected-<n>, the branch goes back to where it was,
#     the task is parked and the night carries on.
#   - Leftover uncommitted files are stashed, not mixed into the next task.
#   - A run that times out (75 min) or ends without finishing has its task parked.
#   - Usage limit: pauses until the reset time in Claude's message (or checks every 15 min), then
#     retries the same task from a clean state. Paused time doesn't count against --hours. If the
#     reset is after --until or more than 6 h away (a weekly limit), the night ends with its report.
#   - verify.sh failing on Simulator trouble (not the code) restarts the night's Simulators and
#     checks once more. Night runs use their own "Spots Night" Simulator, created if missing.
#   - The night stops after 3 failed runs in a row, the run or time limit, or .night/STOP.
#   - At the end: verify.sh --release --screens, and a summary in .night/report.md.
#
# For testing this script: NIGHT_CLAUDE and NIGHT_VERIFY replace the claude and verify.sh
# commands, NIGHT_BRANCH and NIGHT_WORKTREE the branch and worktree, NIGHT_WAIT the 15 min check.
set -uo pipefail

runs=30 hours=8 final_minutes=90 base=main until="" fallback_model=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --runs) runs="$2"; shift ;;
    --hours) hours="$2"; shift ;;
    --final-minutes) final_minutes="$2"; shift ;;
    --base) base="$2"; shift ;;
    --until) until="$2"; shift ;;
    --fallback-model) fallback_model="$2"; shift ;;
    -h|--help) sed -n 2,31p "$0"; exit 0 ;;
    *) echo "Unknown option: $1" >&2; exit 2 ;;
  esac
  shift
done

repo="$(cd "$(dirname "$0")/../.." && pwd)"
state="$repo/.night"
here="$repo/PlaceLock/scripts/night"
wt="${NIGHT_WORKTREE:-$(dirname "$repo")/$(basename "$repo")-night}"
today="$(date +%F)"
branch="${NIGHT_BRANCH:-night/$today}"
claude_cmd="${NIGHT_CLAUDE:-claude}"
probe_wait="${NIGHT_WAIT:-900}"
sim="${VERIFY_SIM:-Spots Night}"
max_pause=$(( 6 * 3600 ))
model_args=()
queue="$state/queue.md"
mkdir -p "$state/runs"
touch "$state/log.md" "$state/needs-you.md"
[[ -f "$queue" ]] || { echo "No queue at $queue" >&2; exit 2; }
rm -f "$state/STOP"

say() { last_say="$*"; echo "[$(date +%H:%M)] $*" | tee -a "$state/runs/night-$today.log"; }
last_say=""
log() { echo "$(date '+%F %H:%M') | $*" >>"$state/log.md"; }
notify() { osascript -e "display notification \"$2\" with title \"$1\" sound name \"Glass\"" 2>/dev/null; }
count() { grep -c "^- \[$1\]" "$queue"; }

# verify.sh in the worktree (or NIGHT_VERIFY). gate <log> [flags]
gate() {
  local out="$1"; shift
  if [[ -n "${NIGHT_VERIFY:-}" ]]; then
    ( cd "$wt" && "$NIGHT_VERIFY" "$@" ) >"$out" 2>&1; return
  fi
  ( cd "$wt" && VERIFY_SIM="$sim" PlaceLock/scripts/verify.sh "$@" ) >"$out" 2>&1 && return 0
  # Simulator trouble (verify.sh already retried once): cool down, restart, check once more.
  grep -qE 'before establishing connection|IS NOT still alive|Unable to boot|Failed to install or launch the test runner|CoreSimulatorService connection' \
    "$wt/PlaceLock/build/verify/test.log" 2>/dev/null || return 1
  say "verify.sh hit Simulator trouble, not a code failure; restarting the night's Simulators and checking again."
  mv "$out" "$out.first-try"
  xcrun simctl shutdown "$sim" 2>/dev/null; xcrun simctl shutdown "Spots Scenarios" 2>/dev/null
  sleep 60
  ( cd "$wt" && VERIFY_SIM="$sim" PlaceLock/scripts/verify.sh "$@" ) >"$out" 2>&1
}

# --- Usage limits.
# A limit message is short ("You've hit your session limit · resets 3:45pm"); a long report that
# mentions rate limits isn't one.
is_limit() {
  (( $(wc -l <"$1") < 15 )) && grep -qiE "hit your [a-z]+ limit|usage limit|limit reached|resets [0-9]|resets (mon|tue|wed|thu|fri|sat|sun)|rate.?limit|overloaded|try again later|(^|[^0-9])(429|529)([^0-9]|$)" "$1"
}

# The reset time in a limit message, as epoch seconds, or nothing if it can't be read.
reset_epoch() {
  python3 - "$1" <<'EOF'
import re, sys, datetime as dt
text = open(sys.argv[1], errors="replace").read()
m = re.search(r"\|(\d{10})\b", text)          # older format: "...limit reached|1700000000"
if m:
    print(m.group(1)); sys.exit()
m = re.search(r"resets\s+(?:at\s+)?(?:(mon|tue|wed|thu|fri|sat|sun)\w*\s+)?(\d{1,2})(?::(\d{2}))?\s*(am|pm)?(?:\s*\(([^)]+)\))?", text, re.I)
if not m:
    sys.exit()
day, hour, minute, ampm, zone = m.groups()
hour, minute = int(hour), int(minute or 0)
if ampm:
    hour = hour % 12 + (12 if ampm.lower() == "pm" else 0)
tz = None
if zone:
    try:
        from zoneinfo import ZoneInfo
        tz = ZoneInfo(zone)
    except Exception:
        tz = None
now = dt.datetime.now(tz) if tz else dt.datetime.now().astimezone()
t = now.replace(hour=hour, minute=minute, second=0, microsecond=0)
if day:
    days = ["mon", "tue", "wed", "thu", "fri", "sat", "sun"].index(day.lower()[:3])
    t += dt.timedelta(days=(days - t.weekday()) % 7)
if t <= now:
    t += dt.timedelta(days=7 if day else 1)
print(int(t.timestamp()))
EOF
}

# Sleep in short steps so .night/STOP still works. Fails if stopped.
nap() {
  local end=$(( $(date +%s) + $1 ))
  while (( $(date +%s) < end )); do
    [[ -f "$state/STOP" ]] && return 1
    local r=$(( end - $(date +%s) )); (( r > 30 )) && r=30; (( r < 1 )) && r=1
    sleep "$r"
  done
}

# Wait out a usage limit: sleep until the reset, then a tiny test prompt; repeat until it answers.
# Fails (the night should end) if the wait would pass --until or run longer than 6 h.
pause_for_limit() {
  local msg="$1" t0 now reset secs probe="$state/runs/$today-limit-check.log"
  t0=$(date +%s)
  while :; do
    now=$(date +%s); reset="$(reset_epoch "$msg")"
    if [[ -n "$reset" ]] && (( reset > now )); then secs=$(( reset - now + 180 )); else secs=$probe_wait; fi
    if [[ -n "$until_epoch" ]] && (( now + secs >= until_epoch )); then
      say "The limit resets at $(date -r $(( now + secs )) +%H:%M), after --until $until; ending the night."; return 1
    fi
    if (( now + secs - t0 > max_pause )); then
      say "The limit resets at $(date -r $(( now + secs )) '+%a %H:%M'), more than 6 h away; ending the night."; return 1
    fi
    say "Usage limit ($(grep -oiE "hit your [a-z]+ limit[^.]*|usage limit[^.]*" "$msg" | head -1 | cut -c1-80)). Pausing until $(date -r $(( now + secs )) +%H:%M)."
    nap "$secs" || { say "Found .night/STOP while paused."; return 1; }
    ( cd "$wt" && PLACELOCK_NIGHT=1 "$claude_cmd" -p "Reply with just the word OK." \
        ${model_args[@]+"${model_args[@]}"} --strict-mcp-config --mcp-config "$state/mcp.json" ) >"$probe" 2>&1
    if grep -q OK "$probe" && ! is_limit "$probe"; then break; fi
    msg="$probe"
  done
  paused=$(( paused + $(date +%s) - t0 ))
  say "Limit lifted after $(( ($(date +%s) - t0) / 60 )) min; carrying on."
  log "— | resumed | — | paused $(( ($(date +%s) - t0) / 60 )) min for a usage limit"
}

# The next open task line. In the final phase only "(final)" tasks; before it, everything else.
next_task() {
  if [[ $1 == final ]]; then grep -m1 '^- \[ \].*(final)' "$queue"
  else grep '^- \[ \]' "$queue" | grep -v -m1 '(final)'
  fi
}

# Status character of a task ("x", "?", " "), found by its text after the checkbox.
status_of() {
  python3 - "$queue" "$1" <<'EOF'
import sys
path, line = sys.argv[1:3]
title = line[6:]
for l in open(path).read().split("\n"):
    if l.startswith("- [") and l[6:] == title:
        print(l[3]); break
else:
    print("missing")
EOF
}

# Set a task's status and add an indented note under it.
mark() {
  python3 - "$queue" "$1" "$2" "$3" <<'EOF'
import sys
path, line, status, note = sys.argv[1:5]
title = line[6:]
lines = open(path).read().split("\n")
for i, l in enumerate(lines):
    if l.startswith("- [") and l[6:] == title:
        lines[i] = f"- [{status}] {title}"
        lines.insert(i + 1, f"  {note}")
        break
open(path, "w").write("\n".join(lines))
EOF
}

# A question for the user, in the format the prompt uses.
ask() {
  printf '\n## %s (%s)\n**Question:** %s\n**What happened:** %s\n**Left behind:** %s\n' \
    "$1" "$today" "$2" "$3" "${4:-nothing}" >>"$state/needs-you.md"
}

title_of() { sed -E 's/^- \[.\] \*\*([^*]*)\*\*.*/\1/' <<<"$1"; }

# --- Worktree: create it, or reuse it (clean) and rebase it onto $base.
if [[ -d "$wt" ]]; then
  if [[ -n "$(git -C "$wt" status --porcelain)" ]]; then
    echo "$wt has uncommitted changes from an earlier run. Look at them, then commit or discard." >&2
    exit 1
  fi
  if git -C "$repo" show-ref --quiet "refs/heads/$branch"; then
    git -C "$wt" switch --quiet "$branch"
    if ! git -C "$wt" rebase --quiet "$base"; then
      git -C "$wt" rebase --abort
      echo "$branch conflicts with $base. Rebase it by hand in $wt, then run again." >&2
      exit 1
    fi
  else
    git -C "$wt" switch --quiet -c "$branch" "$base"
  fi
else
  if git -C "$repo" show-ref --quiet "refs/heads/$branch"; then
    git -C "$repo" worktree add --quiet "$wt" "$branch"
  else
    git -C "$repo" worktree add --quiet -b "$branch" "$wt" "$base"
  fi
fi
[[ -n "${NIGHT_VERIFY:-}" || -x "$wt/PlaceLock/scripts/verify.sh" ]] || { echo "$base has no PlaceLock/scripts/verify.sh; commit the tooling first." >&2; exit 1; }

dirty="$(git -C "$repo" status --porcelain --untracked-files=no | wc -l | tr -d ' ')"
(( dirty > 0 )) && say "Note: $dirty uncommitted changes in $repo are not in tonight's run (it starts from $base)."

# The night's own Simulator, so it never shares one with you or the scenario runner.
if [[ -z "${NIGHT_VERIFY:-}" ]] && ! xcrun simctl list devices available | grep -qF "    $sim ("; then
  runtime="$(xcrun simctl list runtimes available -j | python3 -c '
import json, sys
rts = [r for r in json.load(sys.stdin)["runtimes"] if r["platform"] == "iOS"]
print(max(rts, key=lambda r: [int(x) for x in r["version"].split(".")])["identifier"])')"
  xcrun simctl create "$sim" "iPhone 17 Pro" "$runtime" >/dev/null && say "Created the \"$sim\" Simulator (iPhone 17 Pro)."
fi

# --until HH:MM: today, or tomorrow if that time has passed.
until_epoch=""
if [[ -n "$until" ]]; then
  until_epoch=$(date -j -f "%Y-%m-%d %H:%M" "$today $until" +%s) || { echo "Bad --until: $until (use HH:MM)" >&2; exit 2; }
  (( until_epoch <= $(date +%s) )) && until_epoch=$(( until_epoch + 86400 ))
fi

# Only Context7 for night runs: no Supabase (live project), Gmail, Drive or other connectors.
# Built here from ~/.claude.json so its API key stays out of the repo.
python3 - "$state/mcp.json" <<'EOF'
import json, os, sys
servers = json.load(open(os.path.expanduser("~/.claude.json"))).get("mcpServers", {})
json.dump({"mcpServers": {k: v for k, v in servers.items() if k == "context7"}}, open(sys.argv[1], "w"))
EOF
chmod 600 "$state/mcp.json"

# Keep the Mac awake while this script runs (it still sleeps if the lid is closed on battery).
caffeinate -i -w $$ &

start=$(date +%s)
start_head=$(git -C "$wt" rev-parse HEAD)
asked_before=$(grep -c '^## ' "$state/needs-you.md")
done_n=0 parked_n=0 rejected_n=0 failed_row=0 paused=0 phase=main
rejected=() stashes=()

# --- Baseline: don't build on a broken branch.
say "Worktree $wt on $branch. $(count ' ') open tasks. Checking the starting point (verify.sh --release)..."
if ! gate "$state/runs/$today-baseline.log" --release; then
  say "The starting point fails verify.sh --release; nothing was run. See $state/runs/$today-baseline.log"
  log "— | baseline | failed verify --release | $(git -C "$wt" rev-parse --short HEAD) | see runs/$today-baseline.log"
  notify "Cove night run didn't start" "The starting branch fails verify. See .night/runs."
  exit 1
fi
say "Starting point passes."

for (( n = 1; n <= runs; n++ )); do
  [[ -f "$state/STOP" ]] && { say "Found .night/STOP, stopping."; break; }
  elapsed=$(( $(date +%s) - start - paused ))   # time spent paused for a usage limit doesn't count
  # (final) tasks may run up to an hour past --hours, so a long last run can't crowd them out.
  (( elapsed > hours * 3600 + 3600 )) && { say "Hit the $hours h limit (plus an hour for final tasks)."; break; }
  if [[ -n "$until_epoch" ]] && (( $(date +%s) >= until_epoch )); then say "Reached --until $until."; break; fi
  left=$(( hours * 3600 - elapsed ))
  [[ -n "$until_epoch" ]] && (( until_epoch - $(date +%s) < left )) && left=$(( until_epoch - $(date +%s) ))
  if [[ $phase == main ]] && (( left < final_minutes * 60 )); then
    phase=final; say "Final $final_minutes minutes: only (final) tasks from now on."
  fi
  task="$(next_task $phase)"
  if [[ -z "$task" && $phase == main ]]; then phase=final; task="$(next_task final)"; fi
  [[ -z "$task" ]] && { say "No more tasks to run ($(count " ") still open)."; break; }
  title="$(title_of "$task")"

  before_head=$(git -C "$wt" rev-parse HEAD)
  prompt="$(sed -e "s|{{BRANCH}}|$branch|g" -e "s|{{REPO}}|$repo|g" -e "s|{{STATE}}|$state|g" \
                -e "s|{{TODAY}}|$today|g" -e "s|{{NOW}}|$(date '+%F %H:%M')|g" "$here/prompt.md")"
  prompt="${prompt//\{\{TASK\}\}/$title}"
  out="$state/runs/$(date +%F-%H%M)-$n.log"
  say "Run $n: $title"

  # PLACELOCK_NIGHT silences ~/.claude/hooks/notify.sh, so you get one notification at the end.
  ( cd "$wt" && PLACELOCK_NIGHT=1 VERIFY_SIM="$sim" "$claude_cmd" -p "$prompt" \
      ${model_args[@]+"${model_args[@]}"} --permission-mode auto \
      --settings "$here/settings.json" \
      --strict-mcp-config --mcp-config "$state/mcp.json" \
      --add-dir "$state" \
      >"$out" 2>&1 ) &
  pid=$!
  timed_out=0
  for (( s = 0; s < 4500; s += 5 )); do kill -0 $pid 2>/dev/null || break; sleep 5; done
  if kill -0 $pid 2>/dev/null; then
    pkill -P $pid 2>/dev/null; kill $pid 2>/dev/null; timed_out=1
  fi
  wait $pid 2>/dev/null
  result="$(grep -o 'RESULT: [a-z]*' "$out" | tail -1)"

  # Usage limit or outage: undo the partial run, wait for the reset, retry the same task.
  # It doesn't count as a failure or a run.
  if [[ -z "$result" && $timed_out == 0 ]] && is_limit "$out"; then
    git -C "$wt" reset --quiet --hard "$before_head"; git -C "$wt" clean -fdq
    log "$title | limit | — | $(head -c 160 "$out" | tr '\n' ' ')"
    if [[ -n "$fallback_model" && ${#model_args[@]} -eq 0 ]] && grep -qi 'opus limit' "$out"; then
      model_args=(--model "$fallback_model")
      say "Opus limit; carrying on with $fallback_model (--fallback-model)."
      (( n-- )); continue
    fi
    pause_for_limit "$out" || break
    (( n-- )); continue
  fi

  # Leftover files: stash them so the next task starts clean.
  if [[ -n "$(git -C "$wt" status --porcelain)" ]]; then
    git -C "$wt" stash push --quiet -u -m "night $today run $n leftovers: $title"
    stashes+=("run $n: $title")
    say "Run $n left uncommitted files; stashed them (git stash list in $wt)."
  fi

  status="$(status_of "$task")"
  after_head=$(git -C "$wt" rev-parse HEAD)

  # Independent check of any code change: verify.sh again. Doc-only changes skip it.
  # (Output captured first: with pipefail, grep -q exiting early would fail the pipeline.)
  changed="$(git -C "$wt" diff --name-only "$before_head" "$after_head")"
  if [[ "$after_head" != "$before_head" && -n "$(grep -vE '\.md$|^docs/' <<<"$changed")" ]]; then
    if ! gate "$out.verify" ; then
      rb="$branch-rejected-$n"
      git -C "$wt" branch --quiet -f "$rb" "$after_head"
      git -C "$wt" reset --quiet --hard "$before_head"
      rejected+=("$rb: $title")
      mark "$task" "?" "Rejected $today: verify.sh failed after this run's commits. They're on $rb; the branch went back to $(git -C "$wt" rev-parse --short "$before_head")."
      ask "$title" "Fix or drop the work on $rb?" "verify.sh failed after the run committed (log: runs/$(basename "$out").verify)." "$rb"
      log "$title | rejected | $rb | verify failed after the run"
      say "Run $n: verify failed after its commits; moved them to $rb and reset."
      (( rejected_n++, failed_row++ ))
      (( failed_row >= 3 )) && { say "3 failed runs in a row; stopping."; break; }
      continue
    fi
  fi

  # "Done" with nothing committed and files left behind means the work never landed.
  if [[ $status == x && "$after_head" == "$before_head" && ${#stashes[@]} -gt 0 && "${stashes[${#stashes[@]}-1]}" == "run $n: $title" ]]; then
    status=" " result="marked done but committed nothing; its files are stashed"
  fi

  case "$status" in
    x) (( done_n++ )); failed_row=0; say "Run $n done ($(git -C "$wt" rev-parse --short HEAD))." ;;
    "?") (( parked_n++ )); failed_row=0; say "Run $n parked its task." ;;
    *)
      why="timed out after 75 min"; (( timed_out )) || why="ended without finishing (${result:-no RESULT line})"
      mark "$task" "?" "Parked $today by night.sh: the run $why. Log: runs/$(basename "$out")"
      left="$(git -C "$wt" log --format=%h "$before_head..HEAD" | tr '\n' ' ')"
      [[ "$(git -C "$wt" stash list)" == *"night $today run $n leftovers: $title"* ]] && left+="stash \"night $today run $n leftovers\""
      ask "$title" "Retry this task, change it, or drop it?" "The run $why." "$left"
      log "$title | failed | — | run $why"
      say "Run $n $why; parked the task."
      (( failed_row++ ))
      (( failed_row >= 3 )) && { say "3 failed runs in a row; stopping."; break; }
      ;;
  esac
done

ended="$last_say"   # why the loop stopped

# --- Final check of the whole night's work, with screenshots.
final="not run"
if [[ "$(git -C "$wt" rev-parse HEAD)" != "$start_head" ]]; then
  say "Final check: verify.sh --release --screens"
  if gate "$state/runs/$today-final.log" --release --screens; then final="passed"; else final="FAILED (runs/$today-final.log)"; fi
fi

asked=$(( $(grep -c '^## ' "$state/needs-you.md") - asked_before ))
{
  echo "# Night of $today"
  echo
  echo "- Branch: \`$branch\` ($(git -C "$wt" rev-list --count "$start_head..HEAD") commits). Review with \`git log $(git -C "$wt" rev-parse --short "$start_head")..$branch\`."
  echo "- Ended: $ended"
  echo "- Tasks: $done_n done, $parked_n parked, $rejected_n rejected, $(count ' ') still open."
  echo "- Final verify.sh --release --screens: $final"
  echo "- Paused for usage limits: $(( paused / 60 )) min"
  echo "- New questions in needs-you.md: $asked"
  for r in "${rejected[@]+"${rejected[@]}"}"; do echo "- Rejected: $r"; done
  for s in "${stashes[@]+"${stashes[@]}"}"; do echo "- Stashed leftovers: $s"; done
  echo
  echo "## Commits"
  git -C "$wt" log --format='- %h %s' "$start_head..HEAD"
  echo
} >"$state/report.md"
summary="$done_n done, $parked_n parked, $rejected_n rejected, $asked questions. Final check $final."
say "$summary Report: $state/report.md"
notify "Cove night run finished" "$summary"
