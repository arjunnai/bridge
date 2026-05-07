#!/usr/bin/env bash
# install.sh — symlink (or copy) bridge commands and install Codex skills.
# Default target: $HOME/.local/bin. Honors INSTALL_DIR and PREFIX.
# Does NOT mutate shell rc files.
#
# --copy mode also copies lib/bridge-common.sh into <target>/../lib so the
# copied bin/bridge-* commands can resolve the helper relative to their own
# install location (each command sources "$(dirname $0)/../lib/bridge-common.sh").
set -eu

usage() {
  cat <<EOF
usage: scripts/install.sh [options]

Installs the bridge command and bridge-* commands into a user bin directory by symlinking
(default) or copying. Also installs bundled Codex and Claude Code skills into
detected ~/.codex* and ~/.claude* profiles. Does not modify shell rc files.

Target directory resolution:
  --install-dir DIR     install into DIR
  --prefix DIR          install into DIR/bin (overrides PREFIX env)
  \$INSTALL_DIR         env: target directory
  \$PREFIX              env: target = \$PREFIX/bin
  default               \$HOME/.local/bin

Options:
  --copy                copy files (default: symlink). Also copies
                        lib/bridge-common.sh into <target>/../lib so the
                        copied commands work outside the source tree.
  --force               overwrite existing files / symlinks
  --no-skills           do not install bundled Codex or Claude Code skills
  --codex-home DIR      install Codex skills into DIR too (repeatable)
  --claude-home DIR     install Claude Code skills into DIR too (repeatable)
  -h, --help            show this help
EOF
}

copy=0
force=0
install_skills="${BRIDGE_INSTALL_SKILLS:-1}"
codex_homes=""
claude_homes=""
install_dir="${INSTALL_DIR:-}"
if [ -z "$install_dir" ] && [ -n "${PREFIX:-}" ]; then
  install_dir="$PREFIX/bin"
fi

while [ $# -gt 0 ]; do
  case "$1" in
    -h|--help)      usage; exit 0 ;;
    --copy)         copy=1; shift ;;
    --force)        force=1; shift ;;
    --no-skills)    install_skills=0; shift ;;
    --codex-home)   codex_homes="${codex_homes}${codex_homes:+
}${2:?--codex-home requires value}"; shift 2 ;;
    --claude-home)  claude_homes="${claude_homes}${claude_homes:+
}${2:?--claude-home requires value}"; shift 2 ;;
    --install-dir)  install_dir="${2:?--install-dir requires value}"; shift 2 ;;
    --prefix)       install_dir="${2:?--prefix requires value}/bin"; shift 2 ;;
    *) echo "unknown flag: $1" >&2; usage >&2; exit 2 ;;
  esac
done

[ -n "$install_dir" ] || install_dir="$HOME/.local/bin"

src=$(cd "$(dirname "$0")/.." && pwd)
[ -d "$src/bin" ] || { echo "no bin/ directory at $src" >&2; exit 1; }
[ -f "$src/lib/bridge-common.sh" ] || { echo "no lib/bridge-common.sh at $src/lib" >&2; exit 1; }

mkdir -p "$install_dir"

# When copying, also place lib/bridge-common.sh next to the install dir so
# each copied bin/bridge-* can source ../lib/bridge-common.sh from its own
# install location. parent_dir is "$install_dir/.." resolved.
if [ "$copy" -eq 1 ]; then
  parent_dir=$(cd "$install_dir" && cd .. && pwd)
  lib_dest_dir="$parent_dir/lib"
  mkdir -p "$lib_dest_dir"
  lib_dest="$lib_dest_dir/bridge-common.sh"
  if [ -e "$lib_dest" ] && [ "$force" -ne 1 ]; then
    echo "skip: $lib_dest exists (use --force to overwrite)" >&2
  else
    cp "$src/lib/bridge-common.sh" "$lib_dest"
    chmod 644 "$lib_dest"
    echo "copied lib/bridge-common.sh -> $lib_dest"
  fi
fi

installed=0
skipped=0
for f in "$src"/bin/bridge "$src"/bin/bridge-*; do
  [ -e "$f" ] || continue
  name=$(basename "$f")
  dest="$install_dir/$name"
  if [ -e "$dest" ] || [ -L "$dest" ]; then
    if [ "$force" -eq 1 ]; then
      rm -f "$dest"
    else
      echo "skip: $dest exists (use --force to overwrite)" >&2
      skipped=$((skipped + 1))
      continue
    fi
  fi
  if [ "$copy" -eq 1 ]; then
    cp "$f" "$dest"
    chmod +x "$dest"
    echo "copied $name -> $dest"
  else
    ln -s "$f" "$dest"
    echo "linked $name -> $dest"
  fi
  installed=$((installed + 1))
done

echo "installed=$installed skipped=$skipped target=$install_dir"

# install_skills_from SKILL_SRC_ROOT ENV_VAR_NAME HOME_GLOB EXTRA_HOMES LABEL
# Copies every skill directory under SKILL_SRC_ROOT into each detected home's
# skills/ subdirectory. Prints a summary line using LABEL (e.g. "codex" or
# "claude"). Respects $force.
install_skills_from() {
  _skill_src_root="$1"
  _env_var_name="$2"
  _home_glob="$3"
  _extra_homes="$4"
  _label="$5"

  [ -d "$_skill_src_root" ] || return 0

  _detected=""
  _env_val=$(eval "printf '%s' \"\${${_env_var_name}:-}\"")
  if [ -n "$_env_val" ]; then
    _detected="$_env_val"
  fi
  if [ -d "$HOME" ]; then
    while IFS= read -r d; do
      _detected="${_detected}${_detected:+
}$d"
    done <<EOF
$(find "$HOME" -maxdepth 1 -type d -name "$_home_glob" -print | sort)
EOF
  fi
  if [ -n "$_extra_homes" ]; then
    _detected="${_detected}${_detected:+
}$_extra_homes"
  fi

  [ -n "$_detected" ] || { echo "${_label}_skills_installed_or_present=0 ${_label}_skills_missing=0"; return 0; }

  for _skill_src in "$_skill_src_root"/*; do
    [ -d "$_skill_src" ] || continue
    _skill_name=$(basename "$_skill_src")
    printf "%s\n" "$_detected" | while IFS= read -r _home_dir; do
      [ -n "$_home_dir" ] || continue
      _skill_dest="$_home_dir/skills/$_skill_name"
      mkdir -p "$_home_dir/skills"
      if [ -e "$_skill_dest" ]; then
        if [ "$force" -eq 1 ]; then
          rm -rf "$_skill_dest"
        else
          echo "skip: $_skill_dest exists (use --force to overwrite)" >&2
          continue
        fi
      fi
      cp -R "$_skill_src" "$_skill_dest"
      echo "installed ${_label} skill $_skill_name -> $_skill_dest"
    done
  done

  # Count after install in the parent shell (the while above runs in a subshell).
  _inst=0; _skip=0
  for _skill_src in "$_skill_src_root"/*; do
    [ -d "$_skill_src" ] || continue
    _skill_name=$(basename "$_skill_src")
    while IFS= read -r _home_dir; do
      [ -n "$_home_dir" ] || continue
      if [ -d "$_home_dir/skills/$_skill_name" ]; then
        _inst=$((_inst + 1))
      else
        _skip=$((_skip + 1))
      fi
    done <<EOF
$_detected
EOF
  done
  echo "${_label}_skills_installed_or_present=${_inst} ${_label}_skills_missing=${_skip}"
}

if [ "$install_skills" -ne 0 ]; then
  install_skills_from "$src/.codex/skills" "CODEX_HOME" ".codex*" "$codex_homes" "codex"
  install_skills_from "$src/.claude/skills" "CLAUDE_HOME" ".claude*" "$claude_homes" "claude"
fi

case ":${PATH:-}:" in
  *":$install_dir:"*) ;;
  *) echo "note: $install_dir is not on PATH; add it to use bridge-* directly" >&2 ;;
esac
