<p align="center">
  <img src="assets/bridge-banner.jpg" alt="bridge" width="100%">
</p>

<h1 align="center">No agent reviews its own code.</h1>

<p align="center">
  <strong>bridge keeps Codex, Claude, and Kiro honest — separate sessions, GitHub as the source of truth, adversarial review by default.</strong>
</p>

<p align="center">
  <img src="https://img.shields.io/badge/status-production%20MVP-2ea44f?style=flat" alt="Status">
  <img src="https://img.shields.io/badge/bash-3.2%2B-4eaa25?style=flat" alt="Bash 3.2+">
  <img src="https://img.shields.io/badge/deps-tmux%20%7C%20gh%20%7C%20jq-blue?style=flat" alt="Dependencies">
  <img src="https://img.shields.io/badge/no-daemon-lightgrey?style=flat" alt="No daemon">
</p>

<p align="center">
  <a href="#why">Why</a> ·
  <a href="#install">Install</a> ·
  <a href="#skills">Skills</a> ·
  <a href="#quickstart">Quickstart</a> ·
  <a href="#workflow">Workflow</a> ·
  <a href="#commands">Commands</a> ·
  <a href="#configuration">Configuration</a> ·
  <a href="#security">Security</a> ·
  <a href="docs/commands.md">Full command reference</a> ·
  <a href="docs/phase-orchestration.md">Phase orchestration</a>
</p>

---

`bridge` is a lightweight, GitHub-installable bridge for local AI
coding agents. It keeps agent sessions alive in `tmux`, wakes them with
`bridge-nudge`, and treats GitHub PR state as the durable source of truth.

Agents do not share private memory or direct messages. They coordinate through
PR bodies, reviews, inline review comments, issue comments, commits, and
explicit bridge markers:

```text
BRIDGE_RUN_ID: bridge-2026-05-03T12-00-00Z-ab12
BRIDGE_STATUS: approved
```

## Why

Single-agent loops are easy to start and hard to trust. The same model can
plan, implement, review, and approve its own work. `bridge` makes the
handoff explicit and auditable.

<table>
<tr>
<td width="50%">

### Without bridge

- prompt history becomes source of truth
- reviewer can approve its own work
- stale comments can wake wrong loop
- failures disappear inside terminal state
- humans reconstruct what happened later

</td>
<td width="50%">

### With bridge

- GitHub PR state is source of truth
- implementer and reviewer stay separate
- `BRIDGE_RUN_ID` rejects stale activity
- `BRIDGE_STATUS` drives waits
- every handoff is durable and inspectable

</td>
</tr>
</table>

## What you get

| Feature | What it does |
| --- | --- |
| Persistent local agents | Starts and reuses `tmux` sessions for configured agent CLIs. |
| Durable handoffs | Pastes structured prompts with run IDs, roles, repo, PR, task, and expected output. |
| GitHub-backed waits | Watches PR body, comments, reviews, inline comments, and commits for explicit markers. |
| Adversarial Codex review | Reviewer prompt is read-only and codex-plugin-cc-style adversarial by default. |
| Minimal install | Bash scripts only. No daemon, hosted service, Node package, Python package, or GitHub App. |
| Configurable profiles | Agents are profiles, not hardcoded roles. Built-ins cover `codex`, `claude`, and `kiro`. |

## Install

Requirements:

- bash 3.2+
- `tmux`
- `gh` authenticated with `gh auth login`
- `jq`
- local agent CLIs for the profiles you use

Clone, then symlink commands into a user bin directory:

```bash
git clone https://github.com/arjunnai/bridge.git
cd bridge
scripts/install.sh
```

Install options:

| Command | Effect |
| --- | --- |
| `scripts/install.sh` | Symlink commands into `$HOME/.local/bin`. Also installs skills into all detected `~/.codex*` and `~/.claude*` profiles. |
| `scripts/install.sh --copy --force` | Copy commands and overwrite existing files. |
| `INSTALL_DIR=/usr/local/bin scripts/install.sh` | Install commands into a specific directory. |
| `PREFIX=/opt/bridge scripts/install.sh` | Install commands into `/opt/bridge/bin`. |
| `scripts/install.sh --no-skills` | Skip skill installation. |
| `scripts/install.sh --claude-home ~/.claude-work` | Also install Claude Code skills into a non-standard profile dir. |
| `scripts/install.sh --codex-home ~/.codex-work` | Also install Codex skills into a non-standard profile dir. |

The installer never edits shell rc files. If the target directory is not on
`PATH`, it prints a note.

## Skills

Skills let you drive bridge with natural language instead of memorising subcommands. The installer drops them into every detected agent profile automatically.

| Skill | Agent | Trigger | What it does |
| --- | --- | --- | --- |
| `bridge` | Claude Code | `/bridge <task>` | Runs doctor, starts sessions, dispatches the right `bridge phase` command, watches PR state. |
| `bridge-phase` | Codex | `$bridge-phase <task>` | Same as above — identical workflow, Codex syntax. |

### `/bridge` (Claude Code)

```
/bridge add dark mode to the settings page
/bridge resume PR 42
/bridge watch PR 42
```

The skill picks the right subcommand automatically:

| You say | What runs |
| --- | --- |
| A task description | `bridge phase run --task "<your task>"` |
| A PR number + optional task | `bridge phase resume --pr <n> [--task "..."]` |
| "watch" or "check" + PR number | `bridge phase watch --state complete --pr <n>` |

It will never invent a PR number, never merge without you asking, never paste raw `BRIDGE_RUN_ID` recipes.

### `$bridge-phase` (Codex)

Same three branches as above. Invoke with `$bridge-phase` inside any Codex session in the project repo.

### Manual install into a non-standard profile

```bash
scripts/install.sh --claude-home ~/.claude-work   # extra Claude Code profile
scripts/install.sh --codex-home ~/.codex-work     # extra Codex profile
scripts/install.sh --no-skills                    # skip skills entirely
```

## Quickstart

```bash
# 1. Check local tools, GitHub auth, repo detection, config, and sessions.
bridge doctor

# 2. Optional: configure explicit profiles.
cp config.example.toml config.toml
$EDITOR config.toml

# 3. Start all configured or built-in sessions.
bridge start

# 4. Nudge an implementer.
bridge nudge claude "Implement X. Open or update a PR. Include BRIDGE_STATUS."

# 5. Wait for Codex review approval.
bridge watch 42 --agent codex --status approved
```

## Workflow

```text
Claude implements -> Codex adversarially reviews -> Claude fixes -> Codex approves
Kiro implements   -> Codex adversarially reviews -> Kiro fixes   -> Codex approves
Codex plans       -> Claude/Kiro implements      -> Codex reviews
```

The MVP does not merge PRs, run a daemon, or install a GitHub App. It gives
you small, inspectable primitives:

```text
bridge-start  -> keep agent CLIs alive
bridge-nudge  -> wake one agent with a structured prompt
bridge-watch  -> wait for explicit PR markers
bridge-doctor -> diagnose local setup
```

The `bridge` dispatcher is equivalent:

```text
bridge start   -> bridge-start
bridge nudge   -> bridge-nudge
bridge watch   -> bridge-watch
bridge doctor  -> bridge-doctor
```

Phase-based orchestration is the next product step. The MVP already includes
the role and template surfaces needed for planner, implementer, reviewer, and
validator workflows.

## Commands

| Command | What it does |
| --- | --- |
| `bridge init` | Create `config.toml` from `config.example.toml` with next-step guidance. |
| `bridge doctor` | Diagnose tools, auth, config, sessions, gh scopes, templates. |
| `bridge start` | Start tmux sessions for configured agents (idempotent). |
| `bridge attach` | Attach to an agent's tmux session; `--pr` infers the active agent. |
| `bridge nudge` | Paste a structured prompt into an agent session; `--dry-run` previews. |
| `bridge watch` | Wait for explicit `BRIDGE_STATUS` markers on a PR. |
| `bridge phase` | Drive or resume the full plan → review → implement → approve lifecycle. |
| `bridge ps` | List active bridge runs across open PRs; `--watch` polls for changes. |
| `bridge logs` | Replay the run journal for a bridge run (`--last`, `--pr`, `--run-id`). |
| `bridge skills` | Show installed skill files and sync status across agent homes. |
| `bridge templates` | List or show prompt templates (`list`, `show <name>`). |

**→ [Full command reference](docs/commands.md)** — all flags, options, and template placeholders.

### Quick examples

```bash
bridge init                                        # first-time setup
bridge doctor
bridge start
bridge attach codex                                # open agent pane
bridge attach --pr 42                              # infer active agent
bridge phase run --task "Phase 0: inspect DB"
bridge phase resume --pr 42
bridge phase resume --pr 42 --dry-run              # inspect state only
bridge phase plan-edit --pr 42                     # hand-edit plan
bridge phase review-plan-file --pr 42 --plan-file docs/plan.md
bridge phase correct --pr 42 --run-id bridge-... --agent kiro --message "fix assumption"
bridge nudge claude "Do X" --dry-run               # preview prompt
bridge ps                                          # what runs are alive?
bridge ps --watch                                  # live status changes
bridge logs                                        # replay last run journal
bridge logs --pr 42
bridge watch 42 --status approved
bridge watch 42 --status approved --json           # machine-readable output
bridge skills                                      # check skill install status
bridge templates list
bridge templates show implementer
```

---

## Phase Orchestration

```text
orchestrator → plan → Codex plan-review loop → plan_approved
                                                     │
                                   [optional] context_maintainer
                                                     │
                         implementer → PR → Codex review → fixes → approved + completed
```

`bridge phase run` drives the full lifecycle automatically. `bridge phase resume` picks up any existing PR from its current marker. `bridge phase review-plan-file` pressure-tests a plan file before any code is written.

**→ [Phase orchestration guide](docs/phase-orchestration.md)** — config, all subcommands, examples, and status markers.

---

## Configuration

Discovery order:

1. `$BRIDGE_CONFIG`
2. `./config.toml`
3. built-in defaults

`config.example.toml` is documentation only. The bridge refuses to load it at
runtime; copy it first.

```toml
[github]
repo = "OWNER/REPO"

[watch]
timeout_secs = 1200
quiet_secs   = 90
poll_secs    = 10

[agents.codex]
session         = "codex"
command         = "codex --yolo"
role            = "reviewer"
review_mode     = "adversarial"
prompt_template = "templates/reviewer-prompt.md"
github_login    = "codex-bot"
```

Environment overrides:

| Variable | Effect |
| --- | --- |
| `BRIDGE_CONFIG` | Explicit config path. |
| `BRIDGE_REPO` | Override `[github].repo`. |
| `BRIDGE_TIMEOUT` | Override `[watch].timeout_secs`. |
| `BRIDGE_POLL` | Override `[watch].poll_secs`. |
| `BRIDGE_QUIET` | Override `[watch].quiet_secs`. |
| `BRIDGE_<AGENT>_SESSION` | Override tmux session name. |
| `BRIDGE_<AGENT>_COMMAND` | Override start command. |
| `BRIDGE_<AGENT>_LOGIN` | Override GitHub login. |

## Adversarial review

Codex reviewer mode is adversarial by default. The reviewer is read-only:

- no file edits
- no patches
- no commits
- no pushes
- no implementation fixes

The reviewer must inspect the PR body, commits, diff, relevant comments, and
tests. It should challenge the design, pressure-test assumptions, look for
edge cases and missing tests, and post durable GitHub review comments.

Every review must end with exactly one status:

```text
BRIDGE_STATUS: changes_requested
```

or:

```text
BRIDGE_STATUS: approved
```

## Status markers

| Status | Typical source |
| --- | --- |
| `plan_ready` | Orchestrator finished writing the phase plan. |
| `plan_changes_requested` | Plan reviewer found material gaps in the plan. |
| `plan_approved` | Plan reviewer accepted the plan. Intermediate; never permits merge. |
| `implementation_ready` | Implementer says PR is ready for review. |
| `fixes_pushed` | Implementer says requested fixes are pushed. |
| `changes_requested` | Reviewer found material issues. |
| `approved` | Reviewer approves current PR state. |
| `validated` | Validator confirms requested state. |
| `validation_failed` | Validator found unresolved work. |
| `context_updated` | Context maintainer posted or committed docs updates after `plan_approved`. |
| `context_noop` | Context maintainer found no durable updates needed. |

Phase completion requires both:

```text
BRIDGE_STATUS: approved
BRIDGE_PHASE_STATUS: completed
```

Only Codex posts `BRIDGE_PHASE_STATUS: completed`. Do not include it in changes-requested reviews.

Automation ignores vague text such as `done`, `looks good`, or `LGTM`.

## Example: Claude implements, Codex reviews

```bash
bridge-start
RUN_ID=$(date -u +bridge-%Y-%m-%dT%H-%M-%SZ-$$)

bridge-nudge claude --template templates/implementer-prompt.md \
                    --run-id "$RUN_ID" \
                    --task "Implement X" \
                    --pr 42

bridge-watch 42 --author claude-bot \
                --run-id "$RUN_ID" \
                --status implementation_ready

bridge-nudge codex --template templates/reviewer-prompt.md \
                   --run-id "$RUN_ID" \
                   --pr 42 \
                   --source-agent claude

bridge-watch 42 --agent codex \
                --run-id "$RUN_ID" \
                --status approved \
                --phase-status completed
```

## Troubleshooting

| Symptom | Fix |
| --- | --- |
| `tmux session not found` | Run `bridge start <agent>`. |
| `gh not authenticated` | Run `gh auth login`. |
| `could not resolve GitHub repo` | Set `BRIDGE_REPO=OWNER/REPO` or pass `--repo`. |
| Watch times out after agent posted output | Ensure the comment has `BRIDGE_STATUS:` and, when filtered, exact `BRIDGE_RUN_ID:`. |
| Prompt stays as a draft | Use `bridge-nudge`; direct `tmux send-keys "$prompt" Enter` can race terminal UIs. |

## Security

- The bridge does not bypass local agent permission systems.
- Human approval prompts remain visible in tmux.
- Reviewers do not need push access.
- Implementers need only the repo permissions required to push their branch.
- Auto-merge is opt-in for resume and remains gated on explicit Codex approval
  plus `BRIDGE_PHASE_STATUS: completed`.

## Project layout

```text
bin/             bridge-init, bridge-start, bridge-attach, bridge-nudge,
                 bridge-watch, bridge-phase, bridge-doctor, bridge-ps, bridge-logs
lib/             shared Bash helpers
templates/       handoff, implementer, reviewer, plan-reviewer, context-maintainer prompts
docs/            commands.md, phase-orchestration.md
scripts/         installer
config.example.toml
AGENTS.md
README.md
```

## Roadmap

- `bridge phase correct` — mid-loop agent correction with stale-state evidence packet
- Evidence ledger (`.bridge/runs/<id>/evidence.log`) for verified smoke/test results
- `bridge ps --watch` — live multi-PR status view
- `bridge attach --pr N` — open the active tmux pane for a run
- More end-to-end GitHub PR smoke tests

## License

License file pending before public release.
