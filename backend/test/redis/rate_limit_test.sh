#!/usr/bin/env bash
# Verifies the rate-limit Lua script used by RateLimiter (src/common/infra.ts) against a real Redis.
set -uo pipefail
R="redis-cli ${REDIS_CLI_ARGS:-}"
LUA=$(sed -n '/^const RATE_LUA = `/,/^`;/p' "$(dirname "$0")/../../src/common/infra.ts" | sed '1d;$d')
pass=0; fail=0
check(){ if [ "$2" == "$3" ]; then echo "  ✓ $1"; pass=$((pass+1)); else echo "  ✗ $1 (expected '$3', got '$2')"; fail=$((fail+1)); fi; }
K="rl:test:$$"; $R del "$K" >/dev/null
echo "rate limiter (redis)"
first=$($R eval "$LUA" 1 "$K" 600 | head -1)
check "first hit counts 1" "$first" "1"
check "window TTL is set on first hit" "$($R ttl "$K")" "600"
for i in $(seq 1 49); do $R eval "$LUA" 1 "$K" 600 >/dev/null & done; wait
check "50 concurrent hits are all counted (atomic)" "$($R get "$K")" "50"
$R del "$K" >/dev/null
echo; echo "redis tests: $pass passed, $fail failed"; [ "$fail" -eq 0 ]
