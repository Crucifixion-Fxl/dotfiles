#!/usr/bin/env bash

set -euo pipefail

ROOT=$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
BOOTSTRAP="$ROOT/bootstrap.sh"

bash -n "$BOOTSTRAP"
grep -q 'ncurses-base' "$BOOTSTRAP"
grep -q '^ensure_tmux_terminfo()' "$BOOTSTRAP"

if grep -q 'tmux\.terminfo' "$BOOTSTRAP"; then
  printf '%s\n' 'bootstrap must not expect tmux.terminfo in the tmux release tarball' >&2
  exit 1
fi

# Exercise install_plugin under set -u. Bash expands a whole `local` command
# before applying its assignments, so dependent values must be assigned on a
# later line.
TEST_HOME=$(mktemp -d)
trap 'rm -rf "$TEST_HOME"' EXIT
TEST_PLUGIN_COMMIT=0123456789abcdef

# shellcheck source=../bootstrap.sh
source "$BOOTSTRAP"

git() {
  if [[ $1 == clone ]]; then
    mkdir -p "$3/.git"
    return 0
  fi

  if [[ $1 == -C && $3 == status ]]; then
    return 0
  fi

  if [[ $1 == -C && $3 == rev-parse ]]; then
    printf '%s\n' "$TEST_PLUGIN_COMMIT"
    return 0
  fi

  return 0
}

HOME=$TEST_HOME install_plugin test-plugin https://example.invalid/test.git "$TEST_PLUGIN_COMMIT"
