#!/usr/bin/env bash
set -eu

ROOT=$(cd "$(dirname "$0")/.." && pwd)
TMPDIR=${TMPDIR:-/tmp}
WORK=$(mktemp -d "$TMPDIR/bridge-phase-resume.XXXXXX")
trap 'rm -rf "$WORK"' EXIT INT TERM

mkdir -p "$WORK/bin" "$WORK/lib" "$WORK/templates" "$WORK/fakebin"
cp "$ROOT/bin/bridge-phase" "$WORK/bin/bridge-phase"
cp "$ROOT/lib/bridge-common.sh" "$WORK/lib/bridge-common.sh"
cp "$ROOT"/templates/*.md "$WORK/templates/"

cat > "$WORK/bin/bridge-start" <<'STUB'
#!/usr/bin/env bash
set -eu
printf 'START\n' >> "${BRIDGE_TEST_LOG:?}"
STUB
chmod +x "$WORK/bin/bridge-start"

cat > "$WORK/bin/bridge-nudge" <<'STUB'
#!/usr/bin/env bash
set -eu
role=""
while [ $# -gt 0 ]; do
  case "$1" in
    --role) role="$2"; shift 2 ;;
    *) shift ;;
  esac
done
printf 'NUDGE role=%s\n' "$role" >> "${BRIDGE_TEST_LOG:?}"
STUB
chmod +x "$WORK/bin/bridge-nudge"

cat > "$WORK/fakebin/gh" <<'STUB'
#!/usr/bin/env bash
set -eu

json_body() {
  body=$1
  printf '{"source":"pr_body","createdAt":"2026-05-03T00:00:00Z","body":%s}\n' "$(printf '%s' "$body" | jq -Rs .)"
}

body_with() {
  rid=$1
  status=$2
  phase=${3:-}
  printf 'BRIDGE_RUN_ID: %s\nBRIDGE_STATUS: %s\n' "$rid" "$status"
  [ -z "$phase" ] || printf 'BRIDGE_PHASE_STATUS: %s\n' "$phase"
}

issue_array_with() {
  created=$1
  body=$2
  jq -n --arg created "$created" --arg body "$body" '[{created_at:$created, body:$body}]'
}

review_array_with() {
  created=$1
  body=$2
  jq -n --arg created "$created" --arg body "$body" '[{submitted_at:$created, body:$body}]'
}

has_log() {
  grep -q "$1" "${BRIDGE_TEST_LOG:?}" 2>/dev/null
}

count_log() {
  grep -c "$1" "${BRIDGE_TEST_LOG:?}" 2>/dev/null || true
}

if [ "${1:-}" = "api" ]; then
  endpoint=${2:?}
  shift 2
  post_body=""
  wants_body_jq=0
  for arg in "$@"; do
    case "$arg" in
      body=*) post_body="${arg#body=}" ;;
      '.body // ""') wants_body_jq=1 ;;
      -f) ;;
    esac
  done
  if [ -n "$post_body" ]; then
    printf 'COMMENT %s\n' "$post_body" >> "${BRIDGE_TEST_LOG:?}"
    exit 0
  fi

  case "$endpoint" in
    repos/owner/repo/pulls/42)
      case "${GH_SCENARIO:?}" in
        one_runid|plan_ready|run_stale) body="$(body_with bridge-one plan_ready)" ;;
        implementation_ready) body="$(body_with bridge-one implementation_ready)" ;;
        fixes_pushed) body="$(body_with bridge-one fixes_pushed)" ;;
        changes_requested) body="$(body_with bridge-one changes_requested)" ;;
        approved_completed|merge_completed) body="$(body_with bridge-one approved completed)" ;;
        approved_only) body="$(body_with bridge-one approved)" ;;
        multiple) body="$(printf '%s\n%s' "$(body_with bridge-one plan_ready)" "$(body_with bridge-two implementation_ready)")" ;;
        markerless|zero) body="" ;;
        *) body="" ;;
      esac
      if [ "$wants_body_jq" -eq 1 ]; then
        printf '%s\n' "$body"
      else
        json_body "$body"
      fi
      ;;
    repos/owner/repo/issues/42/comments)
      case "${GH_SCENARIO:?}" in
        plan_ready)
          if has_log 'NUDGE role=implementer'; then
            issue_array_with "2026-05-03T00:01:00Z" "$(body_with bridge-one implementation_ready)"
          else
            printf '[]\n'
          fi
          ;;
        changes_requested)
          if has_log 'NUDGE role=implementer'; then
            issue_array_with "2026-05-03T00:01:00Z" "$(body_with bridge-one fixes_pushed)"
          else
            printf '[]\n'
          fi
          ;;
        run_stale)
          plan_review_count=$(count_log 'NUDGE role=plan_reviewer')
          implementer_count=$(count_log 'NUDGE role=implementer')
          if [ "$implementer_count" -ge 2 ]; then
            jq -n \
              --arg planapp "$(body_with bridge-one plan_approved)" \
              --arg oldfix "$(body_with bridge-one fixes_pushed)" \
              --arg impl "$(body_with bridge-one implementation_ready)" \
              --arg freshfix "$(body_with bridge-one fixes_pushed)" \
              '[
                {created_at:"2026-05-03T00:00:30Z", body:$planapp},
                {created_at:"2026-05-03T00:00:40Z", body:$oldfix},
                {created_at:"2026-05-03T00:01:00Z", body:$impl},
                {created_at:"2026-05-03T00:03:00Z", body:$freshfix}
              ]'
          elif [ "$implementer_count" -ge 1 ]; then
            jq -n \
              --arg planapp "$(body_with bridge-one plan_approved)" \
              --arg oldfix "$(body_with bridge-one fixes_pushed)" \
              --arg impl "$(body_with bridge-one implementation_ready)" \
              '[
                {created_at:"2026-05-03T00:00:30Z", body:$planapp},
                {created_at:"2026-05-03T00:00:40Z", body:$oldfix},
                {created_at:"2026-05-03T00:01:00Z", body:$impl}
              ]'
          elif [ "$plan_review_count" -ge 1 ]; then
            jq -n \
              --arg planapp "$(body_with bridge-one plan_approved)" \
              '[ {created_at:"2026-05-03T00:00:30Z", body:$planapp} ]'
          else
            printf '[]\n'
          fi
          ;;
        markerless)
          if has_log '^COMMENT '; then
            rid=$(sed -n 's/^COMMENT BRIDGE_RUN_ID: \([^[:space:]]*\).*/\1/p' "${BRIDGE_TEST_LOG:?}" | tail -1)
            issue_array_with "2026-05-03T00:01:00Z" "$(body_with "$rid" implementation_ready)"
          else
            printf '[]\n'
          fi
          ;;
        *) printf '[]\n' ;;
      esac
      ;;
    repos/owner/repo/pulls/42/reviews)
      case "${GH_SCENARIO:?}" in
        implementation_ready|fixes_pushed|plan_ready|changes_requested)
          if has_log 'NUDGE role=adversarial_reviewer'; then
            review_array_with "2026-05-03T00:02:00Z" "$(body_with bridge-one approved completed)"
          else
            printf '[]\n'
          fi
          ;;
        markerless)
          if has_log 'NUDGE role=adversarial_reviewer'; then
            rid=$(sed -n 's/^COMMENT BRIDGE_RUN_ID: \([^[:space:]]*\).*/\1/p' "${BRIDGE_TEST_LOG:?}" | tail -1)
            review_array_with "2099-05-03T00:02:00Z" "$(body_with "$rid" approved completed)"
          else
            printf '[]\n'
          fi
          ;;
        approved_completed|merge_completed)
          review_array_with "2026-05-03T00:02:00Z" "$(body_with bridge-one approved completed)"
          ;;
        approved_only)
          review_array_with "2026-05-03T00:02:00Z" "$(body_with bridge-one approved)"
          ;;
        run_stale)
          reviewer_count=$(count_log 'NUDGE role=adversarial_reviewer')
          if [ "$reviewer_count" -ge 2 ]; then
            jq -n \
              --arg oldreview "$(body_with bridge-one changes_requested)" \
              --arg approval "$(body_with bridge-one approved completed)" \
              '[
                {submitted_at:"2026-05-03T00:02:00Z", body:$oldreview},
                {submitted_at:"2026-05-03T00:04:00Z", body:$approval}
              ]'
          elif [ "$reviewer_count" -ge 1 ]; then
            review_array_with "2026-05-03T00:02:00Z" "$(body_with bridge-one changes_requested)"
          else
            printf '[]\n'
          fi
          ;;
        *) printf '[]\n' ;;
      esac
      ;;
    repos/owner/repo/pulls/42/comments)
      printf '[]\n'
      ;;
    *)
      printf 'unexpected gh api endpoint: %s\n' "$endpoint" >&2
      exit 9
      ;;
  esac
  exit 0
fi

if [ "${1:-}" = "pr" ] && [ "${2:-}" = "view" ]; then
  printf 'false\n'
  exit 0
fi

if [ "${1:-}" = "pr" ] && [ "${2:-}" = "ready" ]; then
  printf 'READY\n' >> "${BRIDGE_TEST_LOG:?}"
  exit 0
fi

if [ "${1:-}" = "pr" ] && [ "${2:-}" = "merge" ]; then
  printf 'MERGE %s\n' "$*" >> "${BRIDGE_TEST_LOG:?}"
  exit 0
fi

printf 'unexpected gh invocation: %s\n' "$*" >&2
exit 9
STUB
chmod +x "$WORK/fakebin/gh"

export PATH="$WORK/fakebin:$PATH"
export BRIDGE_REPO="owner/repo"
export BRIDGE_TEST_LOG="$WORK/events.log"

run_case() {
  name=$1
  shift
  : > "$BRIDGE_TEST_LOG"
  printf 'case %s\n' "$name"
  export GH_SCENARIO
  (cd "$WORK" && "$WORK/bin/bridge-phase" "$@")
}

expect_log() {
  pattern=$1
  grep -q "$pattern" "$BRIDGE_TEST_LOG" || {
    printf 'missing log pattern: %s\n' "$pattern" >&2
    cat "$BRIDGE_TEST_LOG" >&2
    exit 1
  }
}

reject_log() {
  pattern=$1
  if grep -q "$pattern" "$BRIDGE_TEST_LOG"; then
    printf 'unexpected log pattern: %s\n' "$pattern" >&2
    cat "$BRIDGE_TEST_LOG" >&2
    exit 1
  fi
}

GH_SCENARIO=one_runid run_case one_runid resume --repo owner/repo --pr 42 --dry-run | grep -q 'run_id=bridge-one'

if GH_SCENARIO=zero run_case zero_runid_fails resume --repo owner/repo --pr 42 --dry-run >"$WORK/out" 2>"$WORK/err"; then
  printf 'zero_runid_fails unexpectedly passed\n' >&2
  exit 1
fi
grep -q 'has no BRIDGE_RUN_ID markers' "$WORK/err"

if GH_SCENARIO=multiple run_case multiple_runids_fail resume --repo owner/repo --pr 42 --dry-run >"$WORK/out" 2>"$WORK/err"; then
  printf 'multiple_runids_fail unexpectedly passed\n' >&2
  exit 1
fi
grep -q 'multiple BRIDGE_RUN_ID markers' "$WORK/err"

GH_SCENARIO=markerless run_case markerless_adoption resume --repo owner/repo --pr 42 --task "Adopt existing PR" --poll 0 --timeout 5
expect_log '^COMMENT BRIDGE_RUN_ID: bridge-'
expect_log 'NUDGE role=adversarial_reviewer'

GH_SCENARIO=plan_ready run_case plan_ready resume --repo owner/repo --pr 42 --poll 0 --timeout 5
expect_log 'NUDGE role=implementer'
expect_log 'NUDGE role=adversarial_reviewer'

GH_SCENARIO=implementation_ready run_case implementation_ready resume --repo owner/repo --pr 42 --poll 0 --timeout 5
expect_log 'NUDGE role=adversarial_reviewer'
reject_log 'NUDGE role=implementer'

GH_SCENARIO=fixes_pushed run_case fixes_pushed resume --repo owner/repo --pr 42 --poll 0 --timeout 5
expect_log 'NUDGE role=adversarial_reviewer'

GH_SCENARIO=changes_requested run_case changes_requested resume --repo owner/repo --pr 42 --poll 0 --timeout 5
expect_log 'NUDGE role=implementer'
expect_log 'NUDGE role=adversarial_reviewer'

GH_SCENARIO=run_stale run_case run_stale_ignores_old_markers run --repo owner/repo --pr 42 --run-id bridge-one --task "Phase" --poll 0 --timeout 5 --no-merge
if [ "$(grep -c 'NUDGE role=plan_reviewer' "$BRIDGE_TEST_LOG")" -ne 1 ]; then
  printf 'expected exactly one plan_reviewer nudge for stale run case\n' >&2
  cat "$BRIDGE_TEST_LOG" >&2
  exit 1
fi
if [ "$(grep -c 'NUDGE role=implementer' "$BRIDGE_TEST_LOG")" -ne 2 ]; then
  printf 'expected exactly two implementer nudges for stale run case\n' >&2
  cat "$BRIDGE_TEST_LOG" >&2
  exit 1
fi
if [ "$(grep -c 'NUDGE role=adversarial_reviewer' "$BRIDGE_TEST_LOG")" -ne 2 ]; then
  printf 'expected exactly two reviewer nudges for stale run case\n' >&2
  cat "$BRIDGE_TEST_LOG" >&2
  exit 1
fi

GH_SCENARIO=approved_completed run_case approved_completed resume --repo owner/repo --pr 42
reject_log 'NUDGE role='
reject_log '^MERGE '

GH_SCENARIO=merge_completed run_case merge_completed resume --repo owner/repo --pr 42 --merge
expect_log '^MERGE '

GH_SCENARIO=implementation_ready run_case dry_run_no_side_effects resume --repo owner/repo --pr 42 --dry-run >/dev/null
reject_log 'NUDGE role='
reject_log '^COMMENT '
reject_log '^MERGE '

if GH_SCENARIO=approved_only run_case approved_only_invalid resume --repo owner/repo --pr 42 >"$WORK/out" 2>"$WORK/err"; then
  printf 'approved_only_invalid unexpectedly passed\n' >&2
  exit 1
fi
grep -q 'missing BRIDGE_PHASE_STATUS: completed' "$WORK/err"

printf 'bridge phase resume fixture tests passed\n'
