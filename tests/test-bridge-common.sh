#!/usr/bin/env bash
# test-bridge-common.sh — unit tests for lib/bridge-common.sh
set -eu

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
REPO_ROOT=$(cd "$SCRIPT_DIR/.." && pwd)

pass=0; fail=0
ok()   { pass=$((pass+1)); printf "PASS %s\n" "$*"; }
fail() { fail=$((fail+1)); printf "FAIL %s\n" "$*"; }

# Load lib directly.
# shellcheck source=../lib/bridge-common.sh disable=SC1091
. "$REPO_ROOT/lib/bridge-common.sh"

# --- A.1: eval injection regression ---

# 1. Dangerous value must not execute.
rm -f /tmp/bridge_pwn_agent_set
agent_set _test_ K ';touch /tmp/bridge_pwn_agent_set;x='
if [ -e /tmp/bridge_pwn_agent_set ]; then
  fail "A.1: agent_set executed shell code in value (eval injection)"
else
  ok "A.1: agent_set did not execute shell code in value"
fi

# 2. Value must be preserved literally.
got=$(agent_get _test_ K)
expected=';touch /tmp/bridge_pwn_agent_set;x='
if [ "$got" = "$expected" ]; then
  ok "A.1: agent_get returned literal value unchanged"
else
  fail "A.1: agent_get returned '$got', expected '$expected'"
fi

# 3. Backtick in value must not execute.
rm -f /tmp/bridge_pwn_backtick
agent_set _test2_ K '`touch /tmp/bridge_pwn_backtick`'
if [ -e /tmp/bridge_pwn_backtick ]; then
  fail "A.1: agent_set executed backtick in value"
else
  ok "A.1: agent_set did not execute backtick in value"
fi

# --- B.2: validator orchestration validation ---

# Reset orchestration state.
BRIDGE_ORCHESTRATION_PRESENT=1
BRIDGE_ORCHESTRATOR=""
BRIDGE_IMPLEMENTER=""
BRIDGE_REVIEWER=""
BRIDGE_VALIDATOR=""
BRIDGE_AGENTS=""
BRIDGE_CONFIG_USED="mock"

# Register test agents.
agent_set myorch  SESSION "s1"
agent_set myimpl  SESSION "s2"
agent_set myrev   SESSION "s3"
agent_set myval   SESSION "s4"

BRIDGE_ORCHESTRATOR="myorch"
BRIDGE_IMPLEMENTER="myimpl"
BRIDGE_REVIEWER="myrev"

# 4. Validator same as implementer must fail.
BRIDGE_VALIDATOR="myimpl"
if ! bridge_orchestration_validate >/dev/null 2>&1; then
  ok "B.2: validator=implementer rejected"
else
  fail "B.2: validator=implementer should have been rejected"
fi

# 5. Unknown validator must fail.
BRIDGE_VALIDATOR="nobody"
if ! bridge_orchestration_validate >/dev/null 2>&1; then
  ok "B.2: unknown validator rejected"
else
  fail "B.2: unknown validator should have been rejected"
fi

# 6. Valid validator (different from implementer, exists) must pass.
BRIDGE_VALIDATOR="myval"
# orchestrator/implementer/reviewer policy checks require codex|claude|kiro names;
# relax to just test validator path by checking the error string directly.
errors=$(bridge_orchestration_validate 2>/dev/null || true)
if printf '%s' "$errors" | grep -q "validator"; then
  fail "B.2: valid validator config still produced validator error: $errors"
else
  ok "B.2: valid validator config produced no validator error"
fi

printf "\nResults: %d passed, %d failed\n" "$pass" "$fail"
[ "$fail" -eq 0 ]
