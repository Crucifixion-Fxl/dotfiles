#!/usr/bin/env bash

set -euo pipefail

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
