<p align="center">
  <strong>codex-bridge</strong>
</p>

<h1 align="center">Local agents. Durable PR state.</h1>

<p align="center">
  <strong>Coordinate Codex, Claude, Kiro, and other local coding agents through tmux and GitHub.</strong>
</p>

<p align="center">
  <img src="https://img.shields.io/badge/status-production%20MVP-2ea44f?style=flat" alt="Status">
  <img src="https://img.shields.io/badge/bash-3.2%2B-4eaa25?style=flat" alt="Bash 3.2+">
  <img src="https://img.shields.io/badge/deps-tmux%20%7C%20gh%20%7C%20jq-blue?style=flat" alt="Dependencies">
  <img src="https://img.shields.io/badge/no-daemon-lightgrey?style=flat" alt="No daemon">
</p>

<p align="center">
  <a href="#why">Why</a> -
  <a href="#install">Install</a> -
  <a href="#quickstart">Quickstart</a> -
  <a href="#workflow">Workflow</a> -
  <a href="#commands">Commands</a> -
  <a href="#configuration">Configuration</a> -
  <a href="#security">Security</a>
</p>

---

`codex-bridge` is a lightweight, GitHub-installable bridge for local AI
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
plan, implement, review, and approve its own work. `codex-bridge` makes the
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
| `scripts/install.sh` | Symlink commands into `$HOME/.local/bin`. |
| `scripts/install.sh --copy --force` | Copy commands and overwrite existing files. |
| `INSTALL_DIR=/usr/local/bin scripts/install.sh` | Install commands into a specific directory. |
| `PREFIX=/opt/bridge scripts/install.sh` | Install commands into `/opt/bridge/bin`. |

The installer never edits shell rc files. If the target directory is not on
`PATH`, it prints a note.

## Quickstart

```bash
# 1. Check local tools, GitHub auth, repo detection, config, and sessions.
bridge-doctor

# 2. Optional: configure explicit profiles.
cp config.example.toml config.toml
$EDITOR config.toml

# 3. Start all configured or built-in sessions.
bridge-start

# 4. Nudge an implementer.
bridge-nudge claude "Implement X. Open or update a PR. Include BRIDGE_STATUS."

# 5. Wait for Codex review approval.
bridge-watch 42 --agent codex --status approved
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

Phase-based orchestration is the next product step. The MVP already includes
the role and template surfaces needed for planner, implementer, reviewer, and
validator workflows.

## Commands

### `bridge-start`

Start one or more agent sessions:

```bash
bridge-start
bridge-start codex claude
```

Existing sessions are left running. Command strings with arguments are
preserved with `tmux new-session -d -s "$session" "$command"`.

### `bridge-nudge`

Paste a prompt into an agent session through a named tmux buffer:

```bash
bridge-nudge codex "Review PR 42"
echo "Implement task" | bridge-nudge kiro
bridge-nudge claude --template templates/implementer-prompt.md \
                    --pr 42 \
                    --task "Add retry to fetch()" \
                    --source-agent codex
```

Supported template placeholders:

| Placeholder | Meaning |
| --- | --- |
| `{{BRIDGE_RUN_ID}}` | Unique run ID, generated if absent. |
| `{{REPO}}` | GitHub repo. |
| `{{PR}}` | Pull request number. |
| `{{SOURCE_AGENT}}` | Agent handing off work. |
| `{{TARGET_AGENT}}` | Agent being nudged. |
| `{{TARGET_LOGIN}}` | Target agent GitHub login from config. |
| `{{ROLE}}` | Target role. |
| `{{TASK}}` | Task text. |
| `{{EXPECTED_OUTPUT}}` | Expected durable result. |
| `{{STATUS_MARKER}}` | Required status marker. |

Use `--strict-template` to fail if placeholders remain unfilled.

### `bridge-watch`

Wait for explicit status markers on a PR:

```bash
bridge-watch 42
bridge-watch 42 --agent codex
bridge-watch 42 --author codex-bot --run-id bridge-2026-05-03T12-00-00Z-ab12
bridge-watch 42 --status approved --timeout 600 --poll 5
```

Channels:

| Channel | Completes watch? | Notes |
| --- | --- | --- |
| Issue comments | Yes | Precise `created_at`. Preferred. |
| PR reviews | Yes | Precise `submitted_at`; body must be non-empty. Preferred. |
| Inline review comments | Yes | Waits `--quiet` seconds after the last inline match. |
| PR body | Yes | Coarse `updated_at`; less precise than comments and reviews. |
| Commits | No | Logged only. Re-post commit markers in a comment or review. |

Filters:

| Flag | Effect |
| --- | --- |
| `--agent codex` | Match author to configured `github_login`; fails if missing. |
| `--author LOGIN` | Match exact GitHub login. |
| `--run-id ID` | Require exact `BRIDGE_RUN_ID:` line. |
| `--status VALUE` | Require exact `BRIDGE_STATUS:` value. |

Hard GitHub failures such as auth errors, permission errors, missing repos,
and missing PRs exit immediately. HTTP 5xx and network blips retry until
timeout.

### `bridge-doctor`

Diagnose the local bridge environment:

```bash
bridge-doctor
```

Checks required tools, `gh` auth, repo detection, config health, agent command
availability, and tmux session status. Exits non-zero only on hard failures.

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
command         = "codex"
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

Accepted MVP statuses:

| Status | Typical source |
| --- | --- |
| `implementation_ready` | Implementer says PR is ready for review. |
| `fixes_pushed` | Implementer says requested fixes are pushed. |
| `changes_requested` | Reviewer found material issues. |
| `approved` | Reviewer approves current PR state. |
| `validated` | Validator confirms requested state. |
| `validation_failed` | Validator found unresolved work. |

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
                --status approved
```

## Troubleshooting

| Symptom | Fix |
| --- | --- |
| `tmux session not found` | Run `bridge-start <agent>`. |
| `gh not authenticated` | Run `gh auth login`. |
| `could not resolve GitHub repo` | Set `BRIDGE_REPO=OWNER/REPO` or pass `--repo`. |
| Watch times out after agent posted output | Ensure the comment has `BRIDGE_STATUS:` and, when filtered, exact `BRIDGE_RUN_ID:`. |
| Prompt stays as a draft | Use `bridge-nudge`; direct `tmux send-keys "$prompt" Enter` can race terminal UIs. |

## Security

- The bridge does not bypass local agent permission systems.
- Human approval prompts remain visible in tmux.
- Reviewers do not need push access.
- Implementers need only the repo permissions required to push their branch.
- Auto-merge is intentionally out of scope for the MVP.

## Project layout

```text
bin/             bridge-start, bridge-nudge, bridge-watch, bridge-doctor
lib/             shared Bash helpers
templates/       handoff, implementer, and reviewer prompts
scripts/         installer
config.example.toml
AGENTS.md
README.md
```

## Roadmap

- First-class phase orchestration
- Planner prompt and phase-plan template
- Kiro CLI profile using Claude Opus for implementation
- More end-to-end GitHub PR smoke tests

## License

License file pending before public release.
