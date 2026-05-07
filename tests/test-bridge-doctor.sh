#!/usr/bin/env bash
# test-bridge-doctor.sh — smoke test for bridge-doctor with built-in defaults
set -eu

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
REPO_ROOT=$(cd "$SCRIPT_DIR/.." && pwd)

pass=0; fail=0
ok()   { pass=$((pass+1)); printf "PASS %s\n" "$*"; }
fail() { fail=$((fail+1)); printf "FAIL %s\n" "$*"; }

# Run doctor against built-in defaults (no config.toml, no real tmux/gh needed).
# We fake a minimal PATH so missing tools produce warns not fails.
FAKE_BIN=$(mktemp -d)
trap 'rm -rf "$FAKE_BIN"' EXIT

# Stub every required tool to make doctor pass cleanly.
for t in bash tmux gh jq git shellcheck; do
  printf '#!/bin/sh\n' > "$FAKE_BIN/$t"
  # gh auth status needs to succeed; gh repo view may return empty.
  if [ "$t" = "gh" ]; then
    cat > "$FAKE_BIN/gh" <<'SH'
#!/bin/sh
case "$*" in
  *"auth status"*)  exit 0 ;;
  *"repo view"*)    exit 1 ;;
  *)                exit 0 ;;
esac
SH
  fi
  chmod +x "$FAKE_BIN/$t"
done

# Remove real bash stub so we use the real bash.
rm "$FAKE_BIN/bash"

output=$(PATH="$FAKE_BIN:$PATH" BRIDGE_REPO="" \
  bash "$REPO_ROOT/bin/bridge-doctor" 2>&1) || true

if printf '%s' "$output" | grep -q "PASS\|FAIL\|WARN\|INFO"; then
  ok "doctor produced structured output"
else
  fail "doctor produced no structured output: $output"
fi

# Doctor must not error with 'unbound variable' or similar under set -u.
if printf '%s' "$output" | grep -qi "unbound\|bad substitution\|syntax error"; then
  fail "doctor hit a shell error: $output"
else
  ok "doctor ran without shell errors"
fi

printf "\nResults: %d passed, %d failed\n" "$pass" "$fail"
[ "$fail" -eq 0 ]
