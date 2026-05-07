---
name: bridge-phase
description: Orchestrate bridge phases end-to-end. Runs doctor, starts tmux agents, dispatches `bridge phase run|resume`, and watches PR state. Use when the user wants to drive a bridge phase by natural-language task instead of memorising bridge subcommands.
---

# Bridge Phase

Use this skill to run bridge orchestration for the user. Do not hand raw
`export BRIDGE_RUN_ID=...` recipes or manual `tmux send-keys` commands when
you can drive the bridge CLI yourself.

## Pre-flight

```bash
bridge doctor
```

If any line starts with `FAIL`, print it verbatim and stop — the environment
is broken. Lines starting with `WARN` are advisory; continue.

## Sessions

```bash
bridge start
```

Idempotent — existing sessions are left alone. Always run before nudging.

## Decide which subcommand to run

**User gave a PR number (with or without a task description):**

```bash
bridge phase resume --pr <number>
# or, when a task description is also given:
bridge phase resume --pr <number> --task "<verbatim task>"
```

**User gave a task and no PR number:**

```bash
bridge phase run --task "<verbatim task>"
```

This opens a PR, drives plan → implement → review, and waits for
`BRIDGE_STATUS: approved` + `BRIDGE_PHASE_STATUS: completed`.

**User only wants to watch / check state (PR + run-id both known):**

```bash
bridge phase watch --state complete --pr <number> --run-id <id>
```

If either value is missing, ask the user — do not invent them.

## After running

Report the last few lines of output, especially any line starting with
`BRIDGE_STATUS:` or `BRIDGE_PHASE_STATUS:`.

## Refusals

- Never paste `export BRIDGE_RUN_ID=...` shell recipes at the user.
- Never invent a PR number. If unknown, ask.
- Never pass `--merge` unless the user explicitly says they want the PR
  merged right now.
- Never edit files, commit, or push as part of this skill — those actions
  belong to the bridge agents, not to this orchestration step.

## Manual subcommands (debug only)

Use these only when the user is debugging a specific phase transition:

```bash
# Plan only:
bridge phase plan --task "<objective>"

# Watch planning:
bridge phase watch --state plan --pr <n> --run-id <id>

# Nudge implementation:
bridge phase implement --pr <n> --run-id <id>

# Watch implementation:
bridge phase watch --state implementation --pr <n> --run-id <id>

# Nudge review:
bridge phase review --pr <n> --run-id <id>
```

## Edge cases

### Empty repo

If the target GitHub repo has no default branch yet, tell the user to ask
their orchestrator to push a safe baseline branch first. Bridge needs a base
branch before it can open any PR.

### Claude launched via fish alias

If `bridge doctor` warns that the Claude session is not reachable, the agent
command may need to go through a fish profile:

```toml
command = "fish -lc 'claude-eparts --dangerously-skip-permissions'"
```

Even with `--dangerously-skip-permissions`, Claude may show a one-time
workspace trust screen. Accept it or ask the user to accept it before
proceeding.
