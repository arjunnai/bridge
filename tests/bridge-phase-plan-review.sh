#!/usr/bin/env bash
set -eu

ROOT=$(cd "$(dirname "$0")/.." && pwd)
TMPDIR=${TMPDIR:-/tmp}
WORK=$(mktemp -d "$TMPDIR/bridge-phase-plan-review.XXXXXX")
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
agent=""
role=""
plan_file=""
while [ $# -gt 0 ]; do
  case "$1" in
    --role) role="$2"; shift 2 ;;
    --plan-file) plan_file="$2"; shift 2 ;;
    --repo|--pr|--source-agent|--template|--task|--expected-output|--status-marker|--run-id|--session|--agent)
      [ "$1" = "--agent" ] && agent="$2"
      shift 2
      ;;
    --header|--no-header|--strict-template|-h|--help) shift ;;
    --) shift; break ;;
    *)
      [ -z "$agent" ] && agent="$1"
      shift
      ;;
  esac
done
printf 'NUDGE role=%s agent=%s plan_file=%s\n' "$role" "$agent" "$plan_file" >> "${BRIDGE_TEST_LOG:?}"
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

review_array_with() {
  created=$1
  body=$2
  jq -n --arg created "$created" --arg body "$body" '[{submitted_at:$created, body:$body}]'
}

count_log() {
  grep -c "$1" "${BRIDGE_TEST_LOG:?}" 2>/dev/null || true
}

has_log() {
  grep -q "$1" "${BRIDGE_TEST_LOG:?}" 2>/dev/null
}

# Build a JSON comments array progressively from the event log so the fake
# can simulate fresh markers appearing in response to nudges.
emit_comments_for_plan_changes_loop() {
  pr_count=$(count_log 'NUDGE role=plan_reviewer')
  fix_count=$(count_log 'NUDGE role=plan_fixer')
  impl_count=$(count_log 'NUDGE role=implementer')
  events='[]'
  if [ "$pr_count" -ge 1 ]; then
    events=$(printf '%s' "$events" | jq --arg b "$(body_with bridge-one plan_changes_requested)" \
      '. + [{created_at:"2026-05-03T00:00:30Z", body:$b}]')
  fi
  if [ "$fix_count" -ge 1 ]; then
    events=$(printf '%s' "$events" | jq --arg b "$(body_with bridge-one plan_ready)" \
      '. + [{created_at:"2026-05-03T00:01:00Z", body:$b}]')
  fi
  if [ "$pr_count" -ge 2 ]; then
    events=$(printf '%s' "$events" | jq --arg b "$(body_with bridge-one plan_approved)" \
      '. + [{created_at:"2026-05-03T00:01:30Z", body:$b}]')
  fi
  if [ "$impl_count" -ge 1 ]; then
    events=$(printf '%s' "$events" | jq --arg b "$(body_with bridge-one implementation_ready)" \
      '. + [{created_at:"2026-05-03T00:02:00Z", body:$b}]')
  fi
  printf '%s\n' "$events"
}

emit_comments_review_plan_resume() {
  pr_count=$(count_log 'NUDGE role=plan_reviewer')
  impl_count=$(count_log 'NUDGE role=implementer')
  events='[]'
  if [ "$pr_count" -ge 1 ]; then
    events=$(printf '%s' "$events" | jq --arg b "$(body_with bridge-one plan_approved)" \
      '. + [{created_at:"2026-05-03T00:00:30Z", body:$b}]')
  fi
  if [ "$impl_count" -ge 1 ]; then
    events=$(printf '%s' "$events" | jq --arg b "$(body_with bridge-one implementation_ready)" \
      '. + [{created_at:"2026-05-03T00:01:00Z", body:$b}]')
  fi
  printf '%s\n' "$events"
}

emit_comments_legacy_resume_plan_ready() {
  impl_count=$(count_log 'NUDGE role=implementer')
  if [ "$impl_count" -ge 1 ]; then
    jq -n --arg b "$(body_with bridge-one implementation_ready)" \
      '[{created_at:"2026-05-03T00:01:00Z", body:$b}]'
  else
    printf '[]\n'
  fi
}

emit_comments_plan_approved_resume() {
  impl_count=$(count_log 'NUDGE role=implementer')
  if [ "$impl_count" -ge 1 ]; then
    jq -n --arg b "$(body_with bridge-one implementation_ready)" \
      '[{created_at:"2026-05-03T00:01:00Z", body:$b}]'
  else
    printf '[]\n'
  fi
}

emit_comments_plan_approved_no_merge() {
  printf '[]\n'
}

emit_comments_rpf_markerless() {
  pr_count=$(count_log 'NUDGE role=plan_reviewer')
  if [ "$pr_count" -ge 1 ]; then
    rid=$(sed -n 's/^COMMENT BRIDGE_RUN_ID: \([^[:space:]]*\).*/\1/p' "${BRIDGE_TEST_LOG:?}" | tail -1)
    jq -n --arg b "$(body_with "$rid" plan_approved)" \
      '[{created_at:"2099-01-01T00:00:00Z", body:$b}]'
  else
    printf '[]\n'
  fi
}

emit_comments_rpf_changes() {
  pr_count=$(count_log 'NUDGE role=plan_reviewer')
  fix_count=$(count_log 'NUDGE role=plan_fixer')
  events='[]'
  if [ "$pr_count" -ge 1 ]; then
    events=$(printf '%s' "$events" | jq --arg b "$(body_with bridge-rpf plan_changes_requested)" \
      '. + [{created_at:"2099-01-01T00:00:00Z", body:$b}]')
  fi
  if [ "$fix_count" -ge 1 ]; then
    events=$(printf '%s' "$events" | jq --arg b "$(body_with bridge-rpf plan_ready)" \
      '. + [{created_at:"2099-01-02T00:00:00Z", body:$b}]')
  fi
  if [ "$pr_count" -ge 2 ]; then
    events=$(printf '%s' "$events" | jq --arg b "$(body_with bridge-rpf plan_approved)" \
      '. + [{created_at:"2099-01-03T00:00:00Z", body:$b}]')
  fi
  printf '%s\n' "$events"
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
        plan_changes_loop|legacy_resume_plan_ready|review_plan_resume|reviewer_override)
          body="$(body_with bridge-one plan_ready)"
          ;;
        plan_approved_resume|plan_approved_no_merge)
          body="$(body_with bridge-one plan_approved)"
          ;;
        rpf_markerless|rpf_changes)
          body=""
          ;;
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
        plan_changes_loop)        emit_comments_for_plan_changes_loop ;;
        review_plan_resume)       emit_comments_review_plan_resume ;;
        reviewer_override)        emit_comments_review_plan_resume ;;
        legacy_resume_plan_ready) emit_comments_legacy_resume_plan_ready ;;
        plan_approved_resume)     emit_comments_plan_approved_resume ;;
        plan_approved_no_merge)   emit_comments_plan_approved_no_merge ;;
        rpf_markerless)           emit_comments_rpf_markerless ;;
        rpf_changes)              emit_comments_rpf_changes ;;
        *)                        printf '[]\n' ;;
      esac
      ;;
    repos/owner/repo/pulls/42/reviews)
      case "${GH_SCENARIO:?}" in
        plan_changes_loop|review_plan_resume|legacy_resume_plan_ready|plan_approved_resume|reviewer_override)
          if has_log 'NUDGE role=adversarial_reviewer'; then
            review_array_with "2026-05-03T00:03:00Z" "$(body_with bridge-one approved completed)"
          else
            printf '[]\n'
          fi
          ;;
        plan_approved_no_merge)
          printf '[]\n'
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

expect_count() {
  pattern=$1
  expected=$2
  actual=$(grep -c "$pattern" "$BRIDGE_TEST_LOG" 2>/dev/null || true)
  [ "$actual" = "$expected" ] || {
    printf 'expected %s occurrences of %s, got %s\n' "$expected" "$pattern" "$actual" >&2
    cat "$BRIDGE_TEST_LOG" >&2
    exit 1
  }
}

# Fresh run with plan_changes_requested -> plan_fix -> plan_ready -> plan_approved.
GH_SCENARIO=plan_changes_loop run_case plan_changes_loop run \
  --repo owner/repo --pr 42 --run-id bridge-one --task "Phase" \
  --poll 0 --timeout 5 --no-merge
expect_log 'NUDGE role=plan_reviewer'
expect_log 'NUDGE role=plan_fixer'
expect_log 'NUDGE role=implementer'
expect_log 'NUDGE role=adversarial_reviewer'
expect_count 'NUDGE role=plan_reviewer' 2
expect_count 'NUDGE role=plan_fixer' 1
expect_count 'NUDGE role=implementer' 1
expect_count 'NUDGE role=adversarial_reviewer' 1

# Default resume on plan_ready stays on the legacy implement path (no plan_reviewer).
GH_SCENARIO=legacy_resume_plan_ready run_case legacy_resume_plan_ready resume \
  --repo owner/repo --pr 42 --poll 0 --timeout 5
expect_log 'NUDGE role=implementer'
expect_log 'NUDGE role=adversarial_reviewer'
reject_log 'NUDGE role=plan_reviewer'
reject_log 'NUDGE role=plan_fixer'

# Resume --review-plan on plan_ready runs the plan-review gate before implement.
GH_SCENARIO=review_plan_resume run_case review_plan_resume resume \
  --repo owner/repo --pr 42 --review-plan --poll 0 --timeout 5
expect_log 'NUDGE role=plan_reviewer'
expect_log 'NUDGE role=implementer'
expect_log 'NUDGE role=adversarial_reviewer'
reject_log 'NUDGE role=plan_fixer'

# Resume on plan_approved skips plan-review re-run, nudges implementer, and only
# merges after a final approved+completed.
GH_SCENARIO=plan_approved_resume run_case plan_approved_resume resume \
  --repo owner/repo --pr 42 --merge --poll 0 --timeout 5
expect_log 'NUDGE role=implementer'
expect_log 'NUDGE role=adversarial_reviewer'
expect_log '^MERGE '
reject_log 'NUDGE role=plan_reviewer'
reject_log 'NUDGE role=plan_fixer'

# resume --review-plan --reviewer altcodex routes the plan-review nudge to the
# overridden reviewer, not the configured default. Implementation review must
# also honor the override.
GH_SCENARIO=reviewer_override run_case reviewer_override resume \
  --repo owner/repo --pr 42 --review-plan --reviewer altcodex \
  --poll 0 --timeout 5
expect_log 'NUDGE role=plan_reviewer agent=altcodex'
expect_log 'NUDGE role=adversarial_reviewer agent=altcodex'

# plan_approved alone never merges. With no implementation/review markers the
# resume must time out waiting for implementation_ready, and the run must not
# have produced a MERGE event.
if GH_SCENARIO=plan_approved_no_merge run_case plan_approved_no_merge resume \
   --repo owner/repo --pr 42 --merge --poll 0 --timeout 1 \
   >"$WORK/out" 2>"$WORK/err"; then
  printf 'plan_approved_no_merge unexpectedly succeeded\n' >&2
  cat "$BRIDGE_TEST_LOG" >&2
  exit 1
fi
reject_log '^MERGE '
expect_log 'NUDGE role=implementer'

# review-plan-file: existing plan file on disk, markerless PR, no --run-id.
# Bridge auto-generates a run_id, posts an adoption comment, runs the
# plan-review loop, and exits at plan_approved without nudging an
# implementer or invoking the orchestrator/planner.
mkdir -p "$WORK/docs"
cat > "$WORK/docs/myplan.md" <<EOF
# Final pipeline plan

stub content for tests
EOF

GH_SCENARIO=rpf_markerless run_case rpf_markerless review-plan-file \
  --repo owner/repo --pr 42 --plan-file "$WORK/docs/myplan.md" \
  --poll 0 --timeout 5
expect_log '^COMMENT BRIDGE_RUN_ID: bridge-'
expect_log "NUDGE role=plan_reviewer"
expect_log "plan_file=$WORK/docs/myplan.md"
expect_count 'NUDGE role=plan_reviewer' 1
reject_log 'NUDGE role=orchestrator'
reject_log 'NUDGE role=plan_fixer'
reject_log 'NUDGE role=implementer'
reject_log 'NUDGE role=adversarial_reviewer'

# review-plan-file with plan_changes_requested: bridge routes the fix back
# to the configured fixer (Claude by default; here overridden via --fixer)
# on the SAME plan file path, then re-reviews until plan_approved. No
# implementer nudge.
GH_SCENARIO=rpf_changes run_case rpf_changes review-plan-file \
  --repo owner/repo --pr 42 --plan-file "$WORK/docs/myplan.md" \
  --run-id bridge-rpf --fixer claude \
  --poll 0 --timeout 10
expect_count 'NUDGE role=plan_reviewer' 2
expect_count 'NUDGE role=plan_fixer' 1
expect_log "NUDGE role=plan_fixer agent=claude plan_file=$WORK/docs/myplan.md"
expect_log "NUDGE role=plan_reviewer agent=codex plan_file=$WORK/docs/myplan.md"
reject_log 'NUDGE role=implementer'
reject_log 'NUDGE role=adversarial_reviewer'

# review-plan-file requires --plan-file. Missing path must error.
if GH_SCENARIO=rpf_markerless run_case rpf_no_plan_file review-plan-file \
   --repo owner/repo --pr 42 --poll 0 --timeout 5 \
   >"$WORK/out" 2>"$WORK/err"; then
  printf 'rpf_no_plan_file unexpectedly passed\n' >&2
  exit 1
fi
grep -q 'requires --plan-file' "$WORK/err"

# review-plan-file rejects a plan-file path that does not exist.
if GH_SCENARIO=rpf_markerless run_case rpf_missing_plan_file review-plan-file \
   --repo owner/repo --pr 42 --plan-file "$WORK/does-not-exist.md" \
   --poll 0 --timeout 5 \
   >"$WORK/out" 2>"$WORK/err"; then
  printf 'rpf_missing_plan_file unexpectedly passed\n' >&2
  exit 1
fi
grep -q 'plan file not found' "$WORK/err"

printf 'bridge phase plan-review fixture tests passed\n'
