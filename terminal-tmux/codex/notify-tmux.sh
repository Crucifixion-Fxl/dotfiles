#!/usr/bin/env bash

set -euo pipefail

# Codex 会向每个 command hook 的 stdin 写入一个 JSON 对象。即使这里不使用
# 事件内容，也要先把它完整读完，避免脚本提前退出导致 Codex 写入 Broken pipe。
cat >/dev/null

# Codex lifecycle hook 的 tmux 适配器。hooks.json 把 Codex 事件映射为三种状态：
#   running        -> 🔄 codex
#   input-required -> ❓ codex
#   done           -> ✅ codex
#
# 不在 tmux 中运行时直接退出。自定义 option 分为 pane 级状态和 window 级
# owner，让多 pane window 只有一个 Codex 状态能控制 window 名。

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

# 清理旧版 PID/基础名实现留下的 option，避免升级后的 session 受旧状态干扰。
tmux set-option -wuq -t "$window_id" @codex_owner_pid 2>/dev/null || true
tmux set-option -wuq -t "$window_id" @codex_watcher_pid 2>/dev/null || true
tmux set-option -wuq -t "$window_id" @codex_base_name 2>/dev/null || true
tmux set-option -wuq -t "$window_id" @codex_original_automatic_rename 2>/dev/null || true
