#!/usr/bin/env bash

set -euo pipefail

case "${1:-}" in
  running) emoji="🔄" ;;
  done) emoji="✅" ;;
  input-required) emoji="❓" ;;
  *) exit 0 ;;
esac

command -v tmux >/dev/null 2>&1 || exit 0
[[ -n "${TMUX:-}" ]] || exit 0

target="${TMUX_PANE:-}"
if [[ -z "$target" ]]; then
  target="$(tmux display-message -p '#{pane_id}' 2>/dev/null)" || exit 0
fi
window_id="$(tmux display-message -p -t "$target" '#{window_id}' 2>/dev/null)" || exit 0

tmux set-option -pq -t "$target" @tmux_activity_name codex >/dev/null 2>&1 || true
tmux set-option -pq -t "$target" @codex_status "$emoji" >/dev/null 2>&1 || true
tmux set-option -wq -t "$window_id" @codex_owner_pane "$target" >/dev/null 2>&1 || true
tmux rename-window -t "$window_id" "$emoji codex" >/dev/null 2>&1 || true

tmux set-option -wuq -t "$window_id" @codex_owner_pid 2>/dev/null || true
tmux set-option -wuq -t "$window_id" @codex_watcher_pid 2>/dev/null || true
tmux set-option -wuq -t "$window_id" @codex_base_name 2>/dev/null || true
tmux set-option -wuq -t "$window_id" @codex_original_automatic_rename 2>/dev/null || true
