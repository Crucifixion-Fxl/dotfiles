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
