#!/usr/bin/env bash
# Smoke test for the dragon self-hosted Sentry deployment.
# Safe to run any time; read-only. Exit 0 = all checks green.
#
# Usage: ./scripts/vc-smoke.sh [--no-public]
#   --no-public  skip the https://sentry.vistavet.app check (e.g. offline)
#
# 𝚅𝚒𝚋𝚎𝚌𝚛𝚊𝚏𝚝𝚎𝚍. with AI Agents by Vetcoders (c)2024-2026 LibraxisAI

set -u
cd "$(dirname "$0")/.."

CHECK_PUBLIC=1
[ "${1:-}" = "--no-public" ] && CHECK_PUBLIC=0

FAIL=0
pass() { printf 'ok   %s\n' "$1"; }
fail() { printf 'FAIL %s\n' "$1"; FAIL=1; }
warn() { printf 'warn %s\n' "$1"; }

# 1. All compose services up, none unhealthy
expected=$(docker compose config --services 2>/dev/null | wc -l | tr -d ' ')
up=$(docker compose ps --format '{{.Status}}' 2>/dev/null | { command grep -c '^Up' || true; })
unhealthy=$(docker compose ps --format '{{.Name}} {{.Status}}' 2>/dev/null | { command grep -i 'unhealthy\|restarting\|exited' || true; })
if [ "$up" -ge "$expected" ] && [ -z "$unhealthy" ]; then
  pass "containers: $up/$expected up, none unhealthy"
else
  fail "containers: $up/$expected up; problems: ${unhealthy:-none}"
fi

# 2. Local health endpoint
body=$(curl -sS -m 10 http://127.0.0.1:9000/_health/ 2>/dev/null)
[ "$body" = "ok" ] && pass "local http://127.0.0.1:9000/_health/ -> ok" \
                   || fail "local /_health/ returned '${body:-<no response>}'"

# 3. Public ingress (Caddy/proxy chain -> nginx)
if [ "$CHECK_PUBLIC" = 1 ]; then
  pbody=$(curl -sS -m 15 https://sentry.vistavet.app/_health/ 2>/dev/null)
  [ "$pbody" = "ok" ] && pass "public https://sentry.vistavet.app/_health/ -> ok" \
                      || fail "public /_health/ returned '${pbody:-<no response>}'"
fi

# 4. Postgres reachable and has data
users=$(docker compose exec -T postgres psql -U postgres -d postgres -tAc \
  'select count(*) from auth_user;' 2>/dev/null | tr -d ' ')
if [ -n "$users" ] && [ "$users" -ge 1 ] 2>/dev/null; then
  pass "postgres: reachable, $users user(s)"
else
  fail "postgres: query failed or zero users"
fi

# 5. Docker VM disk pressure (colima)
pct=$(colima ssh -- df /var/lib/docker 2>/dev/null | awk 'END {gsub("%","",$5); print $5}')
if [ -n "$pct" ]; then
  if [ "$pct" -ge 90 ]; then fail "colima disk: ${pct}% used (>=90%)"
  elif [ "$pct" -ge 80 ]; then warn "colima disk: ${pct}% used (>=80%)"
  else pass "colima disk: ${pct}% used"
  fi
else
  warn "colima disk: could not measure"
fi

exit "$FAIL"
