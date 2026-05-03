#!/usr/bin/env bash
# bridge-common.sh — shared helpers for bridge-* commands.
# Targets macOS Bash 3.2+ and Linux. No associative arrays. No external deps
# beyond POSIX coreutils, awk, tr, and (for repo discovery) gh.

# Sourced by bin/bridge-* via:
#   _BRIDGE_BIN_DIR=$(cd "$(dirname "$0")" && pwd)
#   _BRIDGE_LIB_DIR="$_BRIDGE_BIN_DIR/../lib"
#   . "$_BRIDGE_LIB_DIR/bridge-common.sh"

# shellcheck disable=SC2034
BRIDGE_VERSION="0.1.0"

# ---------- logging ---------------------------------------------------------

if [ -t 2 ]; then
  _BRIDGE_C_RED=$'\033[31m'
  _BRIDGE_C_YELLOW=$'\033[33m'
  _BRIDGE_C_GREEN=$'\033[32m'
  _BRIDGE_C_BLUE=$'\033[34m'
  _BRIDGE_C_RESET=$'\033[0m'
else
  _BRIDGE_C_RED=""; _BRIDGE_C_YELLOW=""; _BRIDGE_C_GREEN=""
  _BRIDGE_C_BLUE=""; _BRIDGE_C_RESET=""
fi

log_info() { printf "%sINFO%s %s\n" "$_BRIDGE_C_BLUE"   "$_BRIDGE_C_RESET" "$*" >&2; }
log_ok()   { printf "%sPASS%s %s\n" "$_BRIDGE_C_GREEN"  "$_BRIDGE_C_RESET" "$*" >&2; }
log_warn() { printf "%sWARN%s %s\n" "$_BRIDGE_C_YELLOW" "$_BRIDGE_C_RESET" "$*" >&2; }
log_err()  { printf "%sFAIL%s %s\n" "$_BRIDGE_C_RED"    "$_BRIDGE_C_RESET" "$*" >&2; }
die()      { log_err "$*"; exit 1; }

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "required command not found: $1"
}

# ---------- agent registry --------------------------------------------------
# Bash 3.2 lacks associative arrays. Store fields as namespaced scalars and
# track the agent list as a space-separated string.

BRIDGE_AGENTS="${BRIDGE_AGENTS:-}"

_bridge_sanitize() {
  # Map agent name to a safe identifier suffix (uppercase, _ for non-alnum).
  # ASCII-only on purpose: produces stable shell variable suffixes.
  printf "%s" "$1" | LC_ALL=C tr -c 'A-Za-z0-9_' '_' | LC_ALL=C tr '[:lower:]' '[:upper:]'
}

_bridge_agent_var() {
  local a; a=$(_bridge_sanitize "$1")
  printf "_BRIDGE_AGENT_%s_%s" "$a" "$2"
}

agent_set() {
  # agent_set <agent> <KEY> <value>
  local var; var=$(_bridge_agent_var "$1" "$2")
  eval "$var=\${3-}"
  case " $BRIDGE_AGENTS " in
    *" $1 "*) ;;
    *) BRIDGE_AGENTS="${BRIDGE_AGENTS:+$BRIDGE_AGENTS }$1" ;;
  esac
}

agent_get() {
  # agent_get <agent> <KEY> -> stdout
  local var; var=$(_bridge_agent_var "$1" "$2")
  eval "printf '%s' \"\${$var-}\""
}

agent_exists() {
  case " ${BRIDGE_AGENTS:-} " in
    *" $1 "*) return 0 ;;
    *) return 1 ;;
  esac
}

# ---------- TOML config parser ---------------------------------------------
# Supports the documented schema only:
#   [github]            repo
#   [watch]             timeout_secs, poll_secs, quiet_secs
#   [agents.<name>]     session, command, role, review_mode,
#                       prompt_template, github_login
# Values may be quoted strings or bare numbers. Comments start with #.

_bridge_trim() {
  local s="$1"
  local tab
  tab=$(printf '\t')
  # leading whitespace
  while :; do
    case "$s" in
      ' '*)        s="${s# }" ;;
      "$tab"*)     s="${s#"$tab"}" ;;
      *) break ;;
    esac
  done
  # trailing whitespace
  while :; do
    case "$s" in
      *' ')        s="${s% }" ;;
      *"$tab")     s="${s%"$tab"}" ;;
      *) break ;;
    esac
  done
  printf "%s" "$s"
}

bridge_parse_toml() {
  local file="$1"
  local section="" agent="" line key val
  while IFS= read -r line || [ -n "$line" ]; do
    line="${line%$'\r'}"
    line=$(_bridge_trim "$line")
    case "$line" in
      ''|'#'*) continue ;;
    esac
    case "$line" in
      '['*']')
        section="${line#[}"; section="${section%]}"
        section=$(_bridge_trim "$section")
        case "$section" in
          agents.*) agent="${section#agents.}" ;;
          *)        agent="" ;;
        esac
        continue
        ;;
    esac
    case "$line" in
      *=*) ;;
      *) continue ;;
    esac
    key=$(_bridge_trim "${line%%=*}")
    val=$(_bridge_trim "${line#*=}")
    # strip a trailing inline comment outside of quotes (best-effort)
    case "$val" in
      \"*\"*) ;;
      *' #'*) val=$(_bridge_trim "${val%% #*}") ;;
    esac
    # strip surrounding quotes
    case "$val" in
      \"*\") val="${val#\"}"; val="${val%\"}" ;;
      \'*\') val="${val#\'}"; val="${val%\'}" ;;
    esac
    case "$section" in
      github)
        case "$key" in
          repo) BRIDGE_GITHUB_REPO="$val" ;;
        esac
        ;;
      watch)
        case "$key" in
          timeout_secs) BRIDGE_WATCH_TIMEOUT="$val" ;;
          poll_secs)    BRIDGE_WATCH_POLL="$val" ;;
          quiet_secs)   BRIDGE_WATCH_QUIET="$val" ;;
        esac
        ;;
      agents.*)
        case "$key" in
          session)         agent_set "$agent" SESSION         "$val" ;;
          command)         agent_set "$agent" COMMAND         "$val" ;;
          role)            agent_set "$agent" ROLE            "$val" ;;
          review_mode)     agent_set "$agent" REVIEW_MODE     "$val" ;;
          prompt_template) agent_set "$agent" PROMPT_TEMPLATE "$val" ;;
          github_login)    agent_set "$agent" GITHUB_LOGIN    "$val" ;;
        esac
        ;;
    esac
  done < "$file"
}

bridge_apply_defaults() {
  # Built-in profiles (codex, claude, kiro) are added ONLY when no config
  # was loaded. When a config is present, BRIDGE_AGENTS contains exactly
  # the agents the user declared — adding built-ins on top of that would
  # surface unconfigured agents in bridge-start / bridge-doctor and pull
  # users into managing tools they did not opt into.
  local a
  if [ -z "${BRIDGE_CONFIG_USED:-}" ]; then
    for a in codex claude kiro; do
      [ -z "$(agent_get "$a" SESSION)" ] && agent_set "$a" SESSION "$a"
      [ -z "$(agent_get "$a" COMMAND)" ] && agent_set "$a" COMMAND "$a"
    done
  fi
  # For every configured agent, fill any missing per-agent defaults (session
  # and command default to the agent name) and adversarial review_mode for
  # reviewer profiles.
  for a in $BRIDGE_AGENTS; do
    [ -z "$(agent_get "$a" SESSION)" ] && agent_set "$a" SESSION "$a"
    [ -z "$(agent_get "$a" COMMAND)" ] && agent_set "$a" COMMAND "$a"
    if [ "$(agent_get "$a" ROLE)" = "reviewer" ] && [ -z "$(agent_get "$a" REVIEW_MODE)" ]; then
      agent_set "$a" REVIEW_MODE "adversarial"
    fi
  done
  : "${BRIDGE_WATCH_TIMEOUT:=1200}"
  : "${BRIDGE_WATCH_POLL:=10}"
  : "${BRIDGE_WATCH_QUIET:=90}"
  return 0
}

bridge_apply_env_overrides() {
  # Per-agent session/command env fallbacks: BRIDGE_<NAME>_SESSION / _COMMAND.
  local a sn v
  for a in $BRIDGE_AGENTS; do
    sn=$(_bridge_sanitize "$a")
    eval "v=\${BRIDGE_${sn}_SESSION-}"
    [ -n "$v" ] && agent_set "$a" SESSION "$v"
    eval "v=\${BRIDGE_${sn}_COMMAND-}"
    [ -n "$v" ] && agent_set "$a" COMMAND "$v"
    eval "v=\${BRIDGE_${sn}_LOGIN-}"
    [ -n "$v" ] && agent_set "$a" GITHUB_LOGIN "$v"
  done
  [ -n "${BRIDGE_REPO:-}" ]    && BRIDGE_GITHUB_REPO="$BRIDGE_REPO"
  [ -n "${BRIDGE_TIMEOUT:-}" ] && BRIDGE_WATCH_TIMEOUT="$BRIDGE_TIMEOUT"
  [ -n "${BRIDGE_POLL:-}" ]    && BRIDGE_WATCH_POLL="$BRIDGE_POLL"
  [ -n "${BRIDGE_QUIET:-}" ]   && BRIDGE_WATCH_QUIET="$BRIDGE_QUIET"
  return 0
}

bridge_load() {
  : "${BRIDGE_AGENTS:=}"
  : "${BRIDGE_GITHUB_REPO:=}"
  BRIDGE_CONFIG_USED=""
  local cfg=""
  if [ -n "${BRIDGE_CONFIG:-}" ]; then
    cfg="$BRIDGE_CONFIG"
  elif [ -f "./config.toml" ]; then
    cfg="./config.toml"
  fi
  if [ -n "$cfg" ]; then
    [ -f "$cfg" ] || die "config not found: $cfg"
    case "$cfg" in
      *config.example.toml)
        die "refusing to load config.example.toml — copy it to config.toml first"
        ;;
    esac
    bridge_parse_toml "$cfg"
    # shellcheck disable=SC2034
    BRIDGE_CONFIG_USED="$cfg"
  fi
  bridge_apply_defaults
  bridge_apply_env_overrides
  return 0
}

# ---------- repo discovery + run-id ----------------------------------------

bridge_resolve_repo() {
  if [ -n "${BRIDGE_GITHUB_REPO:-}" ]; then
    printf "%s\n" "$BRIDGE_GITHUB_REPO"
    return 0
  fi
  if command -v gh >/dev/null 2>&1; then
    local r
    r=$(gh repo view --json nameWithOwner -q .nameWithOwner 2>/dev/null) || r=""
    if [ -n "$r" ]; then
      printf "%s\n" "$r"
      return 0
    fi
  fi
  return 1
}

bridge_generate_run_id() {
  local ts rand
  ts=$(date -u +"%Y-%m-%dT%H-%M-%SZ")
  if [ -r /dev/urandom ]; then
    rand=$(LC_ALL=C tr -dc 'a-f0-9' < /dev/urandom | head -c 4)
  fi
  [ -z "${rand:-}" ] && rand=$(printf "%04x" $(( ${RANDOM:-0} & 0xffff )))
  printf "bridge-%s-%s\n" "$ts" "$rand"
}

# Convert an RFC3339 (Z) timestamp to epoch seconds. Works on macOS and Linux.
bridge_iso_to_epoch() {
  local s="$1"
  if date -u -j -f "%Y-%m-%dT%H:%M:%SZ" "$s" +%s >/dev/null 2>&1; then
    date -u -j -f "%Y-%m-%dT%H:%M:%SZ" "$s" +%s
  else
    date -u -d "$s" +%s
  fi
}

bridge_now_iso() {
  date -u +"%Y-%m-%dT%H:%M:%SZ"
}
