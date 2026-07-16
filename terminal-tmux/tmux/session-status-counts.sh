#!/usr/bin/env bash

set -euo pipefail

# choose-tree 的输出辅助脚本。唯一参数是 session target（通常是 $N），
# 脚本遍历该 session 的 window 名，按 Codex 状态 emoji 前缀计数。
# 输出是单行文本，会直接嵌入 tmux.conf 的 Prefix+s session 行。

running=0
input_required=0
done_count=0

while IFS= read -r window_name; do
  case "$window_name" in
    🔄*) ((running += 1)) ;;
    ❓*) ((input_required += 1)) ;;
    ✅*) ((done_count += 1)) ;;
  esac
done < <(tmux list-windows -t "${1:?missing session target}" -F '#{window_name}' 2>/dev/null)

printf '🔄 %d  ❓ %d  ✅ %d' "$running" "$input_required" "$done_count"
