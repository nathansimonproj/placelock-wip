#!/usr/bin/env bash
# Works through .night/queue.md unattended: one fresh headless Claude run per task, in a
# separate git worktree on a night/<date> branch, so your own checkout is never touched.
#
# Usage: PlaceLock/scripts/night.sh [--runs N] [--hours H] [--base REF]
#   --runs N    stop after N runs (default 12; use 1 for a dry run)
#   --hours H   stop starting new runs after H hours (default 8)
#   --base REF  branch the night work from REF (default main)
#
# Each run takes the first open task, does it, runs verify.sh, commits and ticks it off,
# or writes a question to .night/needs-you.md and moves on. The loop stops when the queue
# has no open tasks, after 2 runs in a row that change nothing, when a run hits the 75 min
# limit twice, or when you create .night/STOP. Logs: .night/log.md and .night/runs/.
set -uo pipefail

runs=12 hours=8 base=main
while [[ $# -gt 0 ]]; do
  case "$1" in
    --runs) runs="$2"; shift ;;
    --hours) hours="$2"; shift ;;
    --base) base="$2"; shift ;;
    -h|--help) sed -n 2,14p "$0"; exit 0 ;;
    *) echo "Unknown option: $1" >&2; exit 2 ;;
  esac
  shift
done

repo="$(cd "$(dirname "$0")/../.." && pwd)"
state="$repo/.night"
wt="${NIGHT_WORKTREE:-$(dirname "$repo")/$(basename "$repo")-night}"
branch="night/$(date +%F)"
here="$repo/PlaceLock/scripts/night"
mkdir -p "$state/runs"
touch "$state/log.md" "$state/needs-you.md"
[[ -f "$state/queue.md" ]] || { echo "No queue at $state/queue.md" >&2; exit 2; }
rm -f "$state/STOP"

say() { echo "[$(date +%H:%M)] $*"; }
open_tasks() { grep -c '^- \[ \]' "$state/queue.md"; }
notify() {
  osascript -e "display notification \"$2\" with title \"$1\" sound name \"Glass\"" 2>/dev/null
}

# The worktree: create it, or reuse it if it's clean.
if [[ -d "$wt" ]]; then
  if [[ -n "$(git -C "$wt" status --porcelain)" ]]; then
    echo "$wt has uncommitted changes from an earlier run. Look at them, then commit or discard." >&2
    exit 1
  fi
  if git -C "$repo" show-ref --quiet "refs/heads/$branch"; then
    git -C "$wt" switch --quiet "$branch"
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
[[ -x "$wt/PlaceLock/scripts/verify.sh" ]] || { echo "$base has no PlaceLock/scripts/verify.sh; commit the tooling first." >&2; exit 1; }

dirty="$(git -C "$repo" status --porcelain --untracked-files=no | wc -l | tr -d ' ')"
(( dirty > 0 )) && say "Note: $dirty uncommitted changes in $repo are not in tonight's run (it starts from $base)."

# Only Context7 for night runs: no Supabase (live project), Gmail, Drive or other connectors.
# Built here from ~/.claude.json so its API key stays out of the repo.
python3 - "$state/mcp.json" <<'EOF'
import json, os, sys
servers = json.load(open(os.path.expanduser("~/.claude.json"))).get("mcpServers", {})
keep = {k: v for k, v in servers.items() if k == "context7"}
json.dump({"mcpServers": keep}, open(sys.argv[1], "w"))
EOF
chmod 600 "$state/mcp.json"

# Keep the Mac awake while this script runs (it still sleeps if the lid is closed on battery).
caffeinate -i -w $$ &

start=$(date +%s) idle=0 timeouts=0 done_count=0 parked_count=0
asked_before=$(grep -c '^## ' "$state/needs-you.md")
say "Worktree $wt on $branch. $(open_tasks) open tasks, up to $runs runs."

for (( n = 1; n <= runs; n++ )); do
  [[ -f "$state/STOP" ]] && { say "Found .night/STOP, stopping."; break; }
  (( $(date +%s) - start > hours * 3600 )) && { say "Hit the $hours h limit."; break; }
  (( $(open_tasks) == 0 )) && { say "Queue empty."; break; }

  before="$(md5 -q "$state/queue.md")$(git -C "$wt" rev-parse HEAD)"
  prompt="$(sed -e "s|{{BRANCH}}|$branch|g" -e "s|{{REPO}}|$repo|g" -e "s|{{STATE}}|$state|g" \
                -e "s|{{TODAY}}|$(date +%F)|g" -e "s|{{NOW}}|$(date '+%F %H:%M')|g" "$here/prompt.md")"
  out="$state/runs/$(date +%F-%H%M)-$n.log"
  say "Run $n: $(grep -m1 '^- \[ \]' "$state/queue.md" | cut -c1-90)"

  # PLACELOCK_NIGHT silences ~/.claude/hooks/notify.sh, so you get one notification at the end.
  ( cd "$wt" && PLACELOCK_NIGHT=1 VERIFY_SIM="iPhone 17 Pro" claude -p "$prompt" \
      --permission-mode auto \
      --settings "$here/settings.json" \
      --strict-mcp-config --mcp-config "$state/mcp.json" \
      --add-dir "$state" \
      >"$out" 2>&1 ) &
  pid=$!
  # 75 min limit per run.
  for (( s = 0; s < 4500; s += 15 )); do kill -0 $pid 2>/dev/null || break; sleep 15; done
  if kill -0 $pid 2>/dev/null; then
    pkill -P $pid 2>/dev/null; kill $pid 2>/dev/null
    echo "$(date '+%F %H:%M') | run $n | killed after 75 min | — |" >>"$state/log.md"
    say "Run $n hit 75 min and was stopped."
    (( ++timeouts >= 2 )) && break
  fi
  wait $pid 2>/dev/null

  result="$(grep -o 'RESULT: [a-z]*' "$out" | tail -1)"
  say "Run $n finished: ${result:-no RESULT line} (log: $out)"
  case "$result" in
    "RESULT: done") (( done_count++ )) ;;
    "RESULT: parked") (( parked_count++ )) ;;
  esac

  if [[ "$(md5 -q "$state/queue.md")$(git -C "$wt" rev-parse HEAD)" == "$before" ]]; then
    (( ++idle >= 2 )) && { say "Two runs in a row changed nothing, stopping."; break; }
  else
    idle=0
  fi
  if [[ -n "$(git -C "$wt" status --porcelain)" ]]; then
    say "Run $n left uncommitted changes in $wt; stopping so they aren't mixed into the next task."
    break
  fi
done

asked=$(( $(grep -c '^## ' "$state/needs-you.md") - asked_before ))
summary="$done_count done, $parked_count parked, $asked new questions, $(open_tasks) still open."
say "$summary"
say "Review: git log $base..$branch, and $state/needs-you.md"
notify "Spots night run finished" "$summary"
