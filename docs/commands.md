# Bridge Command Reference

Full option reference for every `bridge` command.

---

## `bridge init`

Create `config.toml` from `config.example.toml`.

```bash
bridge init             # create config.toml in current directory
bridge init --force     # overwrite existing config.toml
bridge init --dir /path # create in a specific directory
```

Prints next-step instructions on where to fill in `github_login`, `[github].repo`, and `[orchestration]`.

---

## `bridge doctor`

Diagnose the local bridge environment.

```bash
bridge doctor
```

Checks: required tools (`bash`, `tmux`, `gh`, `jq`), `gh` auth, git repo, GitHub repo detection, config health, orchestration config validity, agent command availability, tmux session status.

Exits non-zero on hard failures. Lines starting with `FAIL` must be resolved before running.

---

## `bridge start`

Start tmux sessions for configured agents.

```bash
bridge start
bridge start codex claude
```

Idempotent — existing sessions are left running.

---

## `bridge nudge`

Paste a prompt into an agent session through a named tmux buffer.

```bash
bridge nudge codex "Review PR 42"
echo "Implement task" | bridge nudge kiro
bridge nudge claude --template templates/implementer-prompt.md \
                    --pr 42 \
                    --task "Add retry to fetch()" \
                    --source-agent codex
```

**Options:**

| Flag | Meaning |
| --- | --- |
| `--repo OWNER/REPO` | Repo override |
| `--pr NUMBER` | PR number |
| `--run-id ID` | Bridge run ID; auto-generated if absent |
| `--role ROLE` | Handoff role |
| `--source-agent AGENT` | Source agent label |
| `--template FILE` | Render this template file |
| `--task TEXT` | Task description |
| `--expected-output TEXT` | Expected output hint |
| `--status-marker TEXT` | Required reply marker |
| `--plan-file PATH` | Override `{{PHASE_PLAN_FILE}}` in the template |
| `--no-header` | Never prepend the handoff header |
| `--header` | Force-prepend the handoff header |
| `--strict-template` | Fail if any `{{PLACEHOLDER}}` remains unfilled |
| `--dry-run` | Render prompt and print to stdout; do not paste into tmux |

**Template placeholders:**

| Placeholder | Meaning |
| --- | --- |
| `{{BRIDGE_RUN_ID}}` | Unique run ID |
| `{{REPO}}` | GitHub repo |
| `{{PR}}` | PR number |
| `{{SOURCE_AGENT}}` | Agent handing off |
| `{{TARGET_AGENT}}` | Agent being nudged |
| `{{TARGET_LOGIN}}` | Target GitHub login from config |
| `{{ROLE}}` | Target role |
| `{{TASK}}` | Task text |
| `{{EXPECTED_OUTPUT}}` | Expected durable result |
| `{{STATUS_MARKER}}` | Required status marker |
| `{{PHASE_PLAN_FILE}}` | Phase plan file path |
| `{{ORCHESTRATOR}}` | Configured orchestrator name |
| `{{IMPLEMENTER}}` | Configured implementer name |
| `{{REVIEWER}}` | Configured reviewer name |

---

## `bridge watch`

Wait for explicit status markers on a PR.

```bash
bridge watch 42
bridge watch 42 --status approved
bridge watch 42 --agent codex --status approved --phase-status completed
bridge watch 42 --run-id bridge-... --timeout 600 --poll 5
```

**Options:**

| Flag | Meaning |
| --- | --- |
| `--repo OWNER/REPO` | Repo override |
| `--agent AGENT` | Match author to agent's configured `github_login` |
| `--author LOGIN` | Match exact GitHub login |
| `--run-id ID` | Require exact `BRIDGE_RUN_ID:` line |
| `--status VALUE` | Require exact `BRIDGE_STATUS:` value |
| `--phase-status VALUE` | Also require `BRIDGE_PHASE_STATUS:` in same body; requires `--status approved` |
| `--timeout SECONDS` | Overall timeout (default: 1200) |
| `--poll SECONDS` | Poll interval (default: 10) |
| `--quiet SECONDS` | Inline-only quiet window (default: 90) |

**Channels:**

| Channel | Completes watch? |
| --- | --- |
| Issue comments | Yes — preferred |
| PR reviews | Yes — preferred |
| Inline review comments | Yes — after `--quiet` seconds |
| PR body | Yes — coarse `updated_at` |
| Commits | No — logged only |

Hard GitHub failures (401, 403, 404) exit immediately. HTTP 5xx retries until timeout.

---

## `bridge phase`

Drive or resume phase plan/implement/review loops.

```bash
bridge phase <command> --help   # per-command help
```

See **[Phase Orchestration](phase-orchestration.md)** for the full workflow.

### `bridge phase run`

Full lifecycle: plan → plan-review loop → context sidecar → implement → code review → fix cycles.

```bash
bridge phase run --task "Phase 0: inspect live DB prerequisites"
bridge phase run --task "Add retry logic" --no-merge
```

| Flag | Default | Meaning |
| --- | --- | --- |
| `--task TEXT` | required | What to build |
| `--pr NUMBER` | — | Attach to existing PR |
| `--max-cycles N` | 5 | Implementation review/fix cycles |
| `--max-plan-cycles N` | 20 | Plan-review cycles before bailing |
| `--merge` | off | Merge after completion |
| `--no-merge` | — | Do not merge |
| `--merge-method` | squash | `merge`, `squash`, or `rebase` |

### `bridge phase resume`

Adopt or continue an existing PR from its latest bridge marker.

```bash
bridge phase resume --pr 42
bridge phase resume --pr 42 --review-plan
bridge phase resume --pr 42 --task "Adopt for review"   # adoption
bridge phase resume --pr 42 --dry-run                   # inspect only
```

Resumable statuses: `plan_ready`, `plan_approved`, `plan_changes_requested`, `implementation_ready`, `fixes_pushed`, `changes_requested`, `approved+completed`.

| Flag | Meaning |
| --- | --- |
| `--pr NUMBER` | PR to resume (required) |
| `--task TEXT` | Required if PR has no `BRIDGE_RUN_ID` yet |
| `--run-id ID` | Required if PR has multiple `BRIDGE_RUN_ID` markers |
| `--review-plan` | Run the plan-review gate before implementation |
| `--implementer AGENT` | Override implementer |
| `--reviewer AGENT` | Override reviewer |
| `--merge` | Merge after completion (opt-in) |
| `--dry-run` | Print detected state and next action, do not act |

### `bridge phase review-plan-file`

Run the plan-review/fix loop on an existing plan file on disk. Stops at `plan_approved` — does not trigger implementation or merge.

```bash
bridge phase review-plan-file --pr 42 --plan-file docs/architecture/phase1.md
```

To implement after approval:

```bash
bridge phase resume --pr 42
```

| Flag | Meaning |
| --- | --- |
| `--pr NUMBER` | Required |
| `--plan-file PATH` | Path to plan file on disk (required) |
| `--run-id ID` | Explicit run ID; auto-detected or generated if absent |
| `--reviewer AGENT` | Override reviewer |
| `--fixer AGENT` | Override plan-fix agent |
| `--max-plan-cycles N` | Cycles before bailing (default: 20) |
| `--dry-run` | Print config without acting |

### `bridge phase plan`

Nudge the orchestrator to write the phase plan.

```bash
bridge phase plan --task "Phase 0: inspect live DB prerequisites"
```

### `bridge phase plan-review`

Nudge the reviewer to adversarially review the plan (manual / debug).

```bash
bridge phase plan-review --pr 42 --run-id bridge-...
bridge phase plan-review --pr 42 --run-id bridge-... --plan-file docs/foo.md
```

### `bridge phase plan-fix`

Nudge the orchestrator to revise the plan after `plan_changes_requested`.

```bash
bridge phase plan-fix --pr 42 --run-id bridge-...
```

### `bridge phase plan-edit`

Open the phase plan file in `$EDITOR`. Useful after `plan_changes_requested`
to hand-edit the plan before re-submitting to the plan-review loop.

```bash
bridge phase plan-edit                          # opens BRIDGE_PHASE_PLAN.md
bridge phase plan-edit --plan-file docs/plan.md
bridge phase plan-edit --pr 42                  # infers plan file from PR adoption comment
```

Uses `$VISUAL` then `$EDITOR` then `vi` as fallback. Creates the file on save if it doesn't exist yet.

### `bridge phase implement`

Nudge the implementer (manual / debug).

```bash
bridge phase implement --pr 42 --run-id bridge-...
```

### `bridge phase review`

Nudge the code reviewer (manual / debug).

```bash
bridge phase review --pr 42 --run-id bridge-...
```

### `bridge phase context`

Nudge the context maintainer to update durable docs (manual / debug).

```bash
bridge phase context --pr 42 --run-id bridge-...
```

### `bridge phase watch`

Wait for a phase marker.

```bash
bridge phase watch --pr 42 --state complete --run-id bridge-...
```

`--state` values: `plan`, `implementation`, `approved`, `complete` (default).

---

## `bridge attach`

Attach to an agent's tmux session.

```bash
bridge attach codex           # attach to codex session directly
bridge attach --pr 42         # infer active agent from latest PR status
bridge attach --list          # list all configured agents and session state
```

With `--pr`, reads the latest `BRIDGE_STATUS` and picks the agent most likely
active for the next step (e.g. `implementation_ready` → reviewer, `changes_requested` → implementer).

| Flag | Meaning |
| --- | --- |
| `--pr NUMBER` | Infer active agent from latest BRIDGE_STATUS |
| `--repo OWNER/REPO` | Repo override (needed for `--pr`) |
| `--list` | List all agents with session running/stopped status |

---

## `bridge ps`

List active bridge runs across open GitHub PRs.

```bash
bridge ps
bridge ps --all      # include closed PRs
bridge ps --json     # machine-readable output
```

Scans PR bodies and issue comments for `BRIDGE_RUN_ID` / `BRIDGE_STATUS` markers and prints a one-line-per-run table:

```
PR     RUN_ID                            STATUS                       UPDATED
------  --------------------------------  ----------------------------  -------
#42    bridge-2026-05-03T12-00-00Z-ab12  fixes_pushed                  4m ago
#51    bridge-2026-05-03T11-30-00Z-ef34  plan_changes_requested        22m ago
```

| Flag | Meaning |
| --- | --- |
| `--repo OWNER/REPO` | Repo override |
| `--all` | Include closed PRs (slower) |
| `--json` | Output as JSON array |
| `--watch` | Poll continuously; print lines when status changes |
| `--poll SECONDS` | Poll interval for `--watch` (default: 15) |

---

## `bridge logs`

Replay the run journal from `.bridge/runs/<run-id>/journal.log`.

```bash
bridge logs                  # last run (reads .bridge/last-run)
bridge logs --pr 42          # resolve run ID from PR markers
bridge logs --run-id bridge-...
bridge logs --tail 20        # last 20 lines only
```

The journal records every nudge and state transition with a UTC timestamp.
`.bridge/last-run` is written automatically by `bridge phase run`.

| Flag | Meaning |
| --- | --- |
| `--run-id ID` | Explicit run ID |
| `--pr NUMBER` | Resolve run ID from GitHub PR markers |
| `--last` | Use `.bridge/last-run` (default) |
| `--repo OWNER/REPO` | Repo override (needed for `--pr`) |
| `--tail N` | Show only last N lines |
