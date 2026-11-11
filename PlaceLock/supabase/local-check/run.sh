#!/usr/bin/env bash
# Checks the migrations against a throwaway local Postgres (no Docker or Supabase CLI needed).
# Usage: supabase/local-check/run.sh   (needs initdb/pg_ctl/psql on PATH, e.g. Homebrew postgresql@16)
set -euo pipefail
export LC_ALL=C  # macOS: Postgres refuses to start without a valid locale

here="$(cd "$(dirname "$0")" && pwd)"
tmp="$(mktemp -d)"
port=54329
trap 'pg_ctl -D "$tmp/data" -m immediate stop >/dev/null 2>&1 || true; rm -rf "$tmp"' EXIT

initdb -D "$tmp/data" -U postgres --auth=trust >/dev/null
pg_ctl -D "$tmp/data" -o "-p $port -k $tmp -c listen_addresses=''" -l "$tmp/log" -w start >/dev/null

run() { psql -h "$tmp" -p "$port" -U postgres -d postgres -v ON_ERROR_STOP=1 -q -f "$1"; }
run "$here/auth_stub.sql"
for migration in "$here"/../migrations/*.sql; do run "$migration"; done
run "$here/checks.sql"
