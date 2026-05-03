#!/usr/bin/env bash
# install.sh — symlink (or copy) bin/bridge-* into a user bin directory.
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

Installs the bridge-* commands into a user bin directory by symlinking
(default) or copying. Does not modify shell rc files.

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
  -h, --help            show this help
EOF
}

copy=0
force=0
install_dir="${INSTALL_DIR:-}"
if [ -z "$install_dir" ] && [ -n "${PREFIX:-}" ]; then
  install_dir="$PREFIX/bin"
fi

while [ $# -gt 0 ]; do
  case "$1" in
    -h|--help)     usage; exit 0 ;;
    --copy)        copy=1; shift ;;
    --force)       force=1; shift ;;
    --install-dir) install_dir="${2:?--install-dir requires value}"; shift 2 ;;
    --prefix)      install_dir="${2:?--prefix requires value}/bin"; shift 2 ;;
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
for f in "$src"/bin/bridge-*; do
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

case ":${PATH:-}:" in
  *":$install_dir:"*) ;;
  *) echo "note: $install_dir is not on PATH; add it to use bridge-* directly" >&2 ;;
esac
