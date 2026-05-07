#!/usr/bin/env bash
# test-bridge-nudge.sh — unit tests for _render in bin/bridge-nudge (A.2 regression)
set -eu

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
REPO_ROOT=$(cd "$SCRIPT_DIR/.." && pwd)

pass=0; fail=0
ok()   { pass=$((pass+1)); printf "PASS %s\n" "$*"; }
fail() { fail=$((fail+1)); printf "FAIL %s\n" "$*"; }

# Extract just the _render function from bridge-nudge and source it.
# We do this by sourcing the file with a fake bridge_load that is a no-op
# so the arg-parsing and execution sections do not trigger.
bridge_load()         { :; }
require_cmd()         { :; }
agent_exists()        { return 0; }
agent_get()           { printf ""; }
bridge_generate_run_id() { printf "bridge-test-id"; }
bridge_phase_plan_file() { printf "BRIDGE_PHASE_PLAN.md"; }
log_ok()              { :; }
log_warn()            { :; }
die()                 { printf "die: %s\n" "$*" >&2; exit 1; }
BRIDGE_GITHUB_REPO=""
BRIDGE_ORCHESTRATOR=""
BRIDGE_IMPLEMENTER=""
BRIDGE_REVIEWER=""

# Source only up to the _render definition (stop before arg parsing executes).
# We do this by overriding set and unsetting -e temporarily, sourcing selectively.
_render_src=$(awk '/^_render\(\)/{found=1} found{print} /^}$/{if(found){exit}}' \
  "$REPO_ROOT/bin/bridge-nudge")
eval "$_render_src"

# 1. Command substitution must not execute.
rm -f /tmp/bridge_pwn_render
body='prefix $(touch /tmp/bridge_pwn_render) suffix'
result=$(_render IGNORE "" "$body")
if [ -e /tmp/bridge_pwn_render ]; then
  fail "A.2: _render executed \$(command) in body"
else
  ok "A.2: _render did not execute \$(command) in body"
fi

# 2. The literal string must survive unchanged.
if printf '%s' "$result" | grep -qF '$(touch /tmp/bridge_pwn_render)'; then
  ok "A.2: literal \$(touch...) preserved in output"
else
  fail "A.2: literal \$(touch...) missing from output — got: $result"
fi

# 3. Placeholder substitution still works.
body2='hello {{NAME}} world'
result2=$(_render NAME "Alice" "$body2")
if [ "$result2" = "hello Alice world" ]; then
  ok "A.2: placeholder substitution works correctly"
else
  fail "A.2: placeholder substitution failed — got: $result2"
fi

# 4. Backtick must not execute.
rm -f /tmp/bridge_pwn_backtick_render
body3='value \`touch /tmp/bridge_pwn_backtick_render\` end'
_render IGNORE "" "$body3" >/dev/null
if [ -e /tmp/bridge_pwn_backtick_render ]; then
  fail "A.2: _render executed backtick in body"
else
  ok "A.2: _render did not execute backtick in body"
fi

printf "\nResults: %d passed, %d failed\n" "$pass" "$fail"
[ "$fail" -eq 0 ]
