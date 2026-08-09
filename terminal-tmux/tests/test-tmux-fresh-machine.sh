#!/usr/bin/env bash

set -euo pipefail

ROOT=$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
TEST_HOME=$(mktemp -d)
TMUX_TMPDIR=$(mktemp -d /tmp/dotfiles-tmux.XXXXXX)
export TMUX_TMPDIR

cleanup() {
  HOME=$TEST_HOME tmux kill-server >/dev/null 2>&1 || true
  rm -rf "$TEST_HOME"
  rm -rf "$TMUX_TMPDIR"
}
trap cleanup EXIT

# shellcheck source=../bootstrap.sh
source "$ROOT/bootstrap.sh"

# Reproduce a fresh-machine tmux started before bootstrap has installed its
# managed links. The early local-link phase must reload that live server so a
# later network failure cannot leave it on tmux defaults (including mouse=off).
mkdir -p "$TEST_HOME/.local/bin"
HOME=$TEST_HOME tmux new-session -d -s fresh-machine 'sleep 30'
[[ $(HOME=$TEST_HOME tmux show-options -gqv mouse) == off ]]

reload_output=$(HOME=$TEST_HOME install_shell_links 2>&1)
grep -Fq 'Reloaded the managed config in the running tmux server' <<< "$reload_output" || {
  printf '%s\n' "$reload_output" >&2
  printf '%s\n' 'fresh-machine live tmux config did not reload cleanly' >&2
  exit 1
}

[[ $(HOME=$TEST_HOME tmux show-options -gqv mouse) == on ]] || {
  printf '%s\n' 'fresh-machine live tmux server did not enable managed mouse input' >&2
  exit 1
}
prefix_bindings=$(HOME=$TEST_HOME tmux list-keys -T prefix)
grep -E '^bind-key +(-r +)?-T prefix g +' <<< "$prefix_bindings" |
  grep -Fq 'lazygit-safe' || {
    printf '%s\n' 'fresh-machine tmux did not load the managed Prefix+g binding' >&2
    exit 1
  }

# Exercise the Ghostty-facing input path, not only the stored tmux option.
# Click the right pane with an SGR mouse event and verify tmux changes focus.
HOME=$TEST_HOME tmux split-window -h -t fresh-machine:0 'sleep 30'
HOME=$TEST_HOME tmux select-pane -t fresh-machine:0.0
mouse_log="$TMUX_TMPDIR/mouse-input.log"
send_mouse_click() {
  sleep 1
  printf '\033[<0;60;10M\033[<0;60;10m'
  sleep 1
  printf '\002d'
}
if script --version >/dev/null 2>&1; then
  send_mouse_click | script -q -c \
    "env HOME='$TEST_HOME' TERM=xterm-ghostty TMUX_TMPDIR='$TMUX_TMPDIR' tmux attach-session -t fresh-machine" \
    "$mouse_log" >/dev/null
else
  send_mouse_click | script -q "$mouse_log" env \
    HOME="$TEST_HOME" TERM=xterm-ghostty TMUX_TMPDIR="$TMUX_TMPDIR" \
    tmux attach-session -t fresh-machine >/dev/null
fi
[[ $(HOME=$TEST_HOME tmux display-message -p -t fresh-machine:0 '#{pane_index}') == 1 ]] || {
  printf '%s\n' 'Ghostty mouse click did not focus the right tmux pane' >&2
  exit 1
}
LC_ALL=C grep -aEq '\[\?100[026]h' "$mouse_log" || {
  printf '%s\n' 'tmux did not request terminal mouse tracking under TERM=xterm-ghostty' >&2
  exit 1
}

[[ -L "$TEST_HOME/.tmux.conf" ]]
[[ $(readlink "$TEST_HOME/.tmux.conf") == "$ROOT/tmux/tmux.conf" ]]
[[ -L "$TEST_HOME/.tmux/session-status-counts.sh" ]]
[[ -L "$TEST_HOME/.local/bin/tmux-zsh" ]]
[[ -L "$TEST_HOME/.local/bin/lazygit-safe" ]]

printf '%s\n' 'tmux fresh-machine shortcuts test passed'
