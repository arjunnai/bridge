# Phase Orchestration

`bridge phase` drives the full plan → review → implement → approve lifecycle
without a daemon. All state is durable in GitHub PR markers.

## How it works

```text
orchestrator → BRIDGE_PHASE_PLAN.md → Codex plan-review loop → plan_approved
                                                                      │
                                              [optional sidecar] context_maintainer
                                                                      │
                                     implementer → PR → Codex code review → fixes → approved + completed
```

**Roles:**

| Role | Default agent | Responsibility |
| --- | --- | --- |
| Orchestrator | Claude | Writes `BRIDGE_PHASE_PLAN.md`, posts `plan_ready` |
| Plan reviewer | Codex | Pressure-tests the plan; posts `plan_approved` or `plan_changes_requested` |
| Context maintainer | (none, opt-in) | Updates `CLAUDE.md` / `AGENTS.md` after plan approval; posts `context_updated` or `context_noop` |
| Implementer | Kiro or Claude | Implements the plan, posts `implementation_ready` |
| Code reviewer | Codex | Adversarially reviews PR; posts `approved` + `BRIDGE_PHASE_STATUS: completed` or `changes_requested` |

**Plan-review loop:** On `plan_changes_requested` the orchestrator revises the plan file in place and re-posts `plan_ready`. The loop caps at `--max-plan-cycles` (default 20). `plan_approved` is intermediate — it never permits a merge and never carries `BRIDGE_PHASE_STATUS: completed`.

**Context maintainer:** Soft-gated sidecar. Fires once after `plan_approved`, before implementation. May commit docs-only changes to the PR branch. Timeout or failure logs a warning; the run continues regardless.

**Code review loop:** On `changes_requested` the implementer fixes and re-posts `fixes_pushed`. Caps at `--max-cycles` (default 5). Phase ends only after Codex posts **both** `BRIDGE_STATUS: approved` and `BRIDGE_PHASE_STATUS: completed`.

**Kiro rule:** Kiro is implementer/validator only. Never set Kiro as orchestrator or reviewer.

## Config

```toml
[orchestration]
orchestrator       = "claude"
implementer        = "kiro"
reviewer           = "codex"
phase_plan_file    = "BRIDGE_PHASE_PLAN.md"
# context_maintainer = "context"  # optional sidecar

[agents.claude]
session         = "claude"
command         = "claude"
role            = "orchestrator"

[agents.kiro]
session         = "kiro"
command         = "kiro-cli chat --trust-all-tools --model claude-opus-4.7"
role            = "implementer"

[agents.codex]
session         = "codex"
command         = "codex --yolo"
role            = "reviewer"
review_mode     = "adversarial"
github_login    = "codex-bot"
```

Invalid orchestration config is a hard failure in `bridge doctor`.

## Common flows

### Fresh task (full lifecycle)

```bash
bridge start
bridge phase run --task "Phase 0: inspect live DB prerequisites"
```

`bridge phase run` handles the entire lifecycle automatically. When Codex posts
`BRIDGE_STATUS: approved` + `BRIDGE_PHASE_STATUS: completed`, the driver exits
(use `--merge` to also merge the PR).

### Resume an existing PR

```bash
bridge phase resume --pr 42
```

Reads the latest `BRIDGE_STATUS` marker, infers next action, nudges the right
agent. Use `--dry-run` to inspect without acting.

To opt into the plan-review gate on an existing PR:

```bash
bridge phase resume --pr 42 --review-plan
```

### Adopt a PR with no bridge markers

```bash
bridge phase resume --pr 42 --task "Review existing implementation for phase 1"
```

Posts a durable adoption comment, treats current head as `implementation_ready`, nudges Codex to review first.

### Review an existing plan file before implementation

For when you have a plan file on disk and want Codex to pressure-test it before
any code is written:

```bash
bridge phase review-plan-file --pr 42 --plan-file docs/architecture/phase1.md
```

Runs the plan-review/fix loop. Exits at `plan_approved`. Does not implement,
does not merge. To implement after approval:

```bash
bridge phase resume --pr 42
```

### Manual step-through (debug)

```bash
bridge phase plan --task "Phase 0: inspect live DB prerequisites"
# wait for plan_ready, then:
bridge phase plan-review --pr 42 --run-id bridge-...
# wait for plan_approved, then:
bridge phase implement --pr 42 --run-id bridge-...
# wait for implementation_ready, then:
bridge phase review --pr 42 --run-id bridge-...
# wait for approved + completed
bridge phase watch --state complete --pr 42 --run-id bridge-...
```

## Claude profile aliases

If a Claude profile is a shell alias, launch through the shell:

```toml
[agents.claude]
session = "claude"
command = "fish -lc 'claude-eparts --dangerously-skip-permissions'"
role    = "orchestrator"
```

Claude may still show a one-time workspace trust screen; accept it before running.

## Example B: Codex orchestrates, Claude implements

```toml
[orchestration]
orchestrator = "codex"
implementer  = "claude"
reviewer     = "codex"
```

Codex may plan and later review the same phase. Codex must not implement.
Codex must not approve code it implemented itself.

## Status markers

| Status | Meaning |
| --- | --- |
| `plan_ready` | Orchestrator finished writing the phase plan |
| `plan_changes_requested` | Plan reviewer found material gaps |
| `plan_approved` | Plan reviewer accepted — intermediate, never permits merge |
| `implementation_ready` | Implementer says PR is ready for review |
| `fixes_pushed` | Implementer says requested fixes are pushed |
| `changes_requested` | Reviewer found material issues |
| `approved` | Reviewer approves current PR state |
| `context_updated` | Context maintainer posted/committed docs updates |
| `context_noop` | Context maintainer found no updates needed |

Phase completion requires both markers in the same comment or review body:

```text
BRIDGE_STATUS: approved
BRIDGE_PHASE_STATUS: completed
```
