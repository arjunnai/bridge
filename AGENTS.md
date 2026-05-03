# AGENTS.md

## Purpose

`codex-bridge` coordinates multiple local AI coding agents through durable GitHub PR state and persistent tmux sessions.

The bridge is designed for workflows where one agent implements and another agent reviews, validates, or orchestrates. The goal is to preserve context across handoffs while avoiding the failure mode where a single model plans, implements, reviews, and approves its own work.

Agents do not communicate directly with each other. They communicate through durable artifacts:

- GitHub PR bodies
- GitHub review comments
- GitHub issue comments
- commits
- branch state
- explicit bridge handoff markers

tmux is only the transport layer used to wake or prompt a local agent session.

GitHub is the shared context boundary.

---

## Supported Agents

The initial supported agents are:

- `codex`
- `claude`
- `kiro`

Support is profile-based. An agent profile defines:

- agent name
- tmux session name
- shell command used to start the agent
- default role
- review mode for reviewer profiles
- GitHub username or bot login
- prompt template

Example:

```toml
[agents.codex]
session = "codex"
command = "codex"
role = "reviewer"
review_mode = "adversarial"
prompt_template = "templates/reviewer-prompt.md"
github_login = "codex-bot"
````

The bridge should not assume that a specific agent always performs a specific role.

Codex can review, orchestrate, or implement.

Claude can implement, review, or validate.

Kiro can implement or validate.

Roles are assigned per run.

---

## Agent Roles

### Orchestrator

The orchestrator decides what needs to happen next.

Responsibilities:

* read the issue, task, or PR state
* decide the next bounded step
* assign an agent to perform that step
* create clear handoff instructions
* decide whether the loop is complete
* avoid doing implementation work unless explicitly assigned

The orchestrator should produce small, concrete tasks for other agents.

---

### Implementer

The implementer writes code.

Responsibilities:

* read the task and existing context
* make bounded code changes
* run relevant tests or checks
* commit changes
* open or update a PR
* respond to review comments
* explain what changed

The implementer must not approve its own work.

The implementer should not broaden scope without explicitly noting it in the PR.

---

### Adversarial Reviewer

The adversarial reviewer is the **default** reviewer role in
`codex-bridge`. It follows the adversarial-review model used by
`codex-plugin-cc`: the reviewer is trying to break confidence in the
change, not validate it. The review should challenge the implementation
approach, design choices, tradeoffs, and assumptions. It is not a generic
syntax or style review.

Core constraints:

* **Read-only.** The reviewer must not edit files, apply patches, push
  commits, or fix code. Its only job is to post review feedback.
* The reviewer must inspect the PR diff, commits, PR body, and relevant
  context before judging the change.
* The reviewer must challenge whether the current approach is the right
  one, what assumptions it depends on, and where the design could fail
  under real-world conditions.
* The reviewer must not approve because the implementation looks plausible
  or well-intentioned. If something only works on the happy path, treat
  that as a real weakness.

Adversarial review method:

* Default to skepticism.
* Look for the strongest reasons the PR should not ship yet.
* Try to disprove the change by tracing bad inputs, retries, concurrent
  actions, partial failure, stale state, re-entrancy, and degraded
  dependencies through the code.
* Pressure-test assumptions, tradeoffs, hidden failure modes, and whether
  a simpler or safer approach exists.
* If the handoff includes optional focus text in `TASK` or
  `EXPECTED_OUTPUT`, weight that focus heavily while still reporting any
  other material issue.

Attack surface:

* correctness against the stated task
* missing tests, weak assertions, and untested failure paths
* edge cases, empty states, nulls, timeouts, and degraded dependencies
* race conditions, ordering assumptions, stale state, and re-entrancy
* rollback safety, retries, partial failure, and idempotency gaps
* data loss, corruption, duplication, and irreversible state changes
* auth, permissions, tenant isolation, and trust boundaries
* security issues such as injection, secret handling, SSRF, unsafe parsing,
  or privilege escalation
* reliability, observability gaps, and recovery difficulty
* maintainability risks and hidden coupling
* scope creep beyond the requested task

Finding bar:

* Report only material findings that are grounded in the PR or repository
  context.
* Do not include style feedback, naming feedback, low-value cleanup, or
  speculative concerns without evidence.
* Each finding should explain what can go wrong, why the code path is
  vulnerable, the likely impact, and the concrete change that would reduce
  risk.

Output requirements:

* Post durable GitHub review comments as a PR review, not only tmux output.
* Anchor in-diff findings as inline review comments where possible.
* Include `BRIDGE_RUN_ID` in the review body.
* End the review body with exactly one status line; the final non-empty
  line must be one of:

  ```text
  BRIDGE_STATUS: changes_requested
  ```

  or:

  ```text
  BRIDGE_STATUS: approved
  ```

#### Review modes

Reviewer profiles support a `review_mode` field for future use:

```toml
[agents.codex]
role        = "reviewer"
review_mode = "adversarial"   # default in MVP
# review_mode = "normal"      # lighter review, not the MVP default
```

For the MVP, the default is `adversarial` regardless of whether the field
is set. A future release may change behavior for `review_mode = "normal"`
(lighter inspection, less pressure-testing) but the bridge will not weaken
the default.

---

### Validator

The validator checks whether requested changes were actually addressed.

Responsibilities:

* read prior review comments
* inspect follow-up commits
* determine whether each requested change was resolved
* identify unresolved or partially resolved comments
* optionally run tests or checks
* post a validation summary

The validator does not replace the reviewer. It verifies the state of the loop.

---

## Role Examples

### Flow A: Claude Implements, Codex Reviews

```text
Claude -> implementer
Codex  -> adversarial reviewer
```

Use this when Claude is already active in an editor or VSCode extension and Codex is available as a tmux-backed reviewer.

Expected flow:

1. Claude implements the task.
2. Claude opens a PR.
3. `codex-bridge` nudges Codex with the PR context.
4. Codex reviews the PR.
5. Claude wakes, reads Codex's comments, and applies fixes.
6. The loop repeats until Codex approves.

---

### Flow B: Kiro Implements, Codex Reviews

```text
Kiro  -> implementer
Codex -> adversarial reviewer
```

Use this when Kiro is good at driving implementation but Codex should provide an independent review.

Expected flow:

1. Codex or a human creates a scoped task.
2. Kiro implements the task and opens a PR.
3. Codex reviews the PR adversarially.
4. Kiro applies fixes.
5. Codex re-reviews until approval.

---

### Flow C: Codex Orchestrates, Claude Implements, Kiro Validates

```text
Codex  -> orchestrator
Claude -> implementer
Kiro   -> validator
Codex  -> final reviewer
```

Use this when the work is complex enough to benefit from separate planning, implementation, validation, and final review.

Expected flow:

1. Codex decomposes the work.
2. Claude implements the first bounded step.
3. Kiro validates that the implementation matches the task and review comments.
4. Codex performs final adversarial review.
5. Claude applies fixes as needed.
6. The loop continues until Codex posts an approval marker.

---

## Bridge Run IDs

Every bridge workflow must have a unique run ID.

Example:

```text
BRIDGE_RUN_ID: bridge-2026-05-02T14-05-31Z-a83f
```

The run ID must appear in:

* handoff prompts
* PR body or PR comments
* review summaries
* validation comments
* final approval or changes-requested markers

This prevents stale GitHub activity from being mistaken for current progress.

A review or comment should not be considered valid unless it matches the current run ID when a run ID is provided.

---

## Required Status Markers

Agents should use explicit status markers.

Reviewer statuses:

```text
BRIDGE_RUN_ID: <id>
BRIDGE_STATUS: changes_requested
```

or:

```text
BRIDGE_RUN_ID: <id>
BRIDGE_STATUS: approved
```

Implementer statuses:

```text
BRIDGE_RUN_ID: <id>
BRIDGE_STATUS: implementation_ready
```

or:

```text
BRIDGE_RUN_ID: <id>
BRIDGE_STATUS: fixes_pushed
```

Validator statuses:

```text
BRIDGE_RUN_ID: <id>
BRIDGE_STATUS: validated
```

or:

```text
BRIDGE_RUN_ID: <id>
BRIDGE_STATUS: validation_failed
```

These markers make automation reliable.

Do not rely on vague natural-language statements like “looks good” or “done.”

---

## Handoff Contract

Every handoff should include:

```text
BRIDGE_RUN_ID:
SOURCE_AGENT:
TARGET_AGENT:
ROLE:
REPO:
PR:
TASK:
EXPECTED_OUTPUT:
STATUS_MARKER:
```

Example:

```text
BRIDGE_RUN_ID: bridge-2026-05-02T14-05-31Z-a83f
SOURCE_AGENT: claude
TARGET_AGENT: codex
ROLE: adversarial_reviewer
REPO: owner/repo
PR: 42
TASK: Review the PR for correctness, missing tests, regressions, and edge cases.
EXPECTED_OUTPUT: A GitHub PR review with actionable comments.
STATUS_MARKER: BRIDGE_STATUS: approved or BRIDGE_STATUS: changes_requested
```

---

## Agent Behavior Rules

### All Agents

All agents must:

* preserve the current bridge run ID
* read the durable GitHub context before acting
* avoid relying only on tmux prompt history
* write durable updates back to GitHub
* use explicit status markers
* keep tasks bounded
* avoid silently changing scope

---

### Implementers

Implementers must:

* make code changes only within the task scope
* open or update a PR
* include the bridge run ID in the PR body or a PR comment
* respond to review comments after fixes
* avoid approving their own PR
* avoid dismissing unresolved review comments

---

### Reviewers

Reviewers must:

* stay read-only: do not edit files, apply patches, push commits, or fix code
* inspect the PR diff, commits, PR body, and relevant context
* challenge the implementation approach, design choices, tradeoffs, and assumptions
* pressure-test hidden failure modes and safer or simpler alternatives
* post durable GitHub review comments as a PR review
* include the bridge run ID in the review body
* use `BRIDGE_STATUS: changes_requested` when issues remain
* use `BRIDGE_STATUS: approved` only when satisfied
* be specific and actionable

---

### Validators

Validators must:

* compare requested changes against new commits
* identify unresolved comments
* post a validation summary
* include the bridge run ID
* avoid approving unless explicitly assigned reviewer authority

---

## Human Approval

Some local agent UIs require human approval for file access, shell commands, or edits.

The bridge should assume humans may need to approve:

* filesystem access
* shell commands
* GitHub operations
* dependency installation
* test execution
* commits or pushes

The bridge should not try to bypass these controls.

tmux keeps agent sessions alive so a human can approve permission prompts when needed.

---

## GitHub as Source of Truth

The PR is the shared artifact boundary.

If an agent needs context, it should read:

1. PR title and body
2. commits
3. changed files
4. review comments
5. issue comments
6. prior bridge status markers

tmux prompt history is not authoritative.

GitHub state is authoritative.

---

## Non-Goals

The bridge does not:

* replace GitHub
* merge PRs automatically by default
* bypass human permission prompts
* require agents to share private internal memory
* require all agents to support the same CLI interface
* assume one fixed agent workflow
* require direct agent-to-agent communication

---

## Adding a New Agent

To add a new agent, define a profile with:

```toml
[agents.example]
session = "example"
command = "example-agent-cli"
role = "implementer"
prompt_template = "templates/implementer-prompt.md"
github_login = "example-bot"
```

The agent must be able to:

* run inside tmux
* receive pasted prompts
* act on local repo context
* write durable state to GitHub manually or through available tools

No special SDK is required for MVP support.
