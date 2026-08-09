#!/usr/bin/env bash

set -euo pipefail

ROOT=$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
TEST_HOME=$(mktemp -d)
TMUX_SOCKET="terminal-tmux-fresh-$$"
TMUX_TMPDIR=$(mktemp -d /tmp/dotfiles-tmux.XXXXXX)
export TMUX_TMPDIR

cleanup() {
  tmux -L "$TMUX_SOCKET" kill-server >/dev/null 2>&1 || true
  rm -rf "$TEST_HOME"
  rm -rf "$TMUX_TMPDIR"
}
trap cleanup EXIT

# shellcheck source=../bootstrap.sh
source "$ROOT/bootstrap.sh"

# Reproduce a fresh-machine bootstrap interrupted by a later network install.
# Any tmux started after the early local-link phase must already load the
# managed shortcuts and their repository-owned helper commands.
mkdir -p "$TEST_HOME/.local/bin"
HOME=$TEST_HOME install_shell_links

HOME=$TEST_HOME tmux -L "$TMUX_SOCKET" new-session -d -s fresh-machine 'sleep 30'
prefix_bindings=$(HOME=$TEST_HOME tmux -L "$TMUX_SOCKET" list-keys -T prefix)
grep -E '^bind-key +(-r +)?-T prefix g +' <<< "$prefix_bindings" |
  grep -Fq 'lazygit-safe' || {
    printf '%s\n' 'fresh-machine tmux did not load the managed Prefix+g binding' >&2
    exit 1
  }

[[ -L "$TEST_HOME/.tmux.conf" ]]
[[ $(readlink "$TEST_HOME/.tmux.conf") == "$ROOT/tmux/tmux.conf" ]]
[[ -L "$TEST_HOME/.tmux/session-status-counts.sh" ]]
[[ -L "$TEST_HOME/.local/bin/tmux-zsh" ]]
[[ -L "$TEST_HOME/.local/bin/lazygit-safe" ]]

printf '%s\n' 'tmux fresh-machine shortcuts test passed'
