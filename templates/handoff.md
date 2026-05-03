BRIDGE_RUN_ID: {{BRIDGE_RUN_ID}}
SOURCE_AGENT: {{SOURCE_AGENT}}
TARGET_AGENT: {{TARGET_AGENT}}
ROLE: {{ROLE}}
REPO: {{REPO}}
PR: {{PR}}
TASK: {{TASK}}
EXPECTED_OUTPUT: {{EXPECTED_OUTPUT}}
STATUS_MARKER: {{STATUS_MARKER}}

You are receiving a handoff from the codex-bridge.

Read the durable GitHub state for {{REPO}} PR #{{PR}} before acting:
  - PR title and body
  - commits
  - changed files
  - prior reviews and inline review comments
  - prior issue comments and bridge status markers

Do the work described in TASK and post the result to GitHub.

To signal completion, you MUST post the BRIDGE_RUN_ID and a STATUS_MARKER
line in a GitHub PR review or a PR/issue comment. The bridge does NOT
treat commit messages as completion — markers in commit messages are
inspected for visibility but never end the watcher loop. If you have only
put the marker in a commit message, re-post it as a comment or review.
