#!/usr/bin/env bash

set -euo pipefail

ROOT=$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
ENTRY="$ROOT/bin/remote-dev-entry"

# shellcheck source=../bin/remote-dev-entry
source "$ENTRY"

# xterm-ghostty 只在远端缺少对应 terminfo 时降级；iTerm2 等已有 TERM 不变。
infocmp() {
  [[ ${TERMINFO_TEST_MODE:-missing} == present ]]
}
TERM=xterm-ghostty
TERMINFO_TEST_MODE=missing fallback_ghostty_term
[[ $TERM == xterm-256color ]]
TERM=xterm-ghostty
TERMINFO_TEST_MODE=present fallback_ghostty_term
[[ $TERM == xterm-ghostty ]]
TERM=xterm-256color
TERMINFO_TEST_MODE=missing fallback_ghostty_term
[[ $TERM == xterm-256color ]]
unset -f infocmp
TERM=xterm-256color

docker() {
  if [[ $1 == ps ]]; then
    case "${DOCKER_TEST_MODE:-running}" in
      running)
        printf 'abc123\tapi-dev\tcompany/api:dev\tUp 2 hours\n'
        ;;
      multiple)
        printf 'abc123\tapi-dev\tcompany/api:dev\tUp 2 hours\n'
        printf 'def456\tweb-dev\tcompany/web:dev\tUp 30 minutes\n'
        ;;
      many)
        local index
        for ((index = 1; index <= 13; index++)); do
          printf 'id%02d\tcontainer-%02d\tcompany/image-%02d:dev\tUp %d hours\n' \
            "$index" "$index" "$index" "$index"
        done
        ;;
      empty)
        return 0
        ;;
      denied)
        return 1
        ;;
    esac
  fi
}

# 成功授权和容器进入都应保持静默；这里只保留 fake exec 的测试标记。
silent_entry_output=$(
  TERMSCP_MAC_USER=mac-user
  authorize_termscp_container_key() {
    printf '%s\n' 'AUTHORIZED SHA256:test added'
  }
  start_termscp_container_relay() {
    termscp_mac_host=127.0.0.1
  }
  exec() {
    printf '%s\n' 'container-exec-called'
  }
  enter_container_tmux abc123 api-dev
)
[[ $silent_entry_output == 'container-exec-called' ]]

enter_host_tmux() {
  printf 'selected:host:%s\n' "$HOST_TMUX_SESSION"
}

enter_container_tmux() {
  printf 'selected:container:%s:%s:%s\n' "$1" "$2" "$CONTAINER_TMUX_SESSION"
}

host_output=$(printf '\033' | main)
grep -Fq 'selected:host:dev' <<< "$host_output"
if grep -Fq 'selected:container:' <<< "$host_output"; then
  printf '%s\n' 'host selection must not enter a container' >&2
  exit 1
fi

container_output=$(printf '\n\n' | main)
grep -Fq 'selected:container:abc123:api-dev:dev' <<< "$container_output"
if grep -Fq 'selected:host:' <<< "$container_output"; then
  printf '%s\n' 'container selection must not start host tmux' >&2
  exit 1
fi

arrow_output=$(printf '\n\033[B\n' | DOCKER_TEST_MODE=multiple main)
grep -Fq 'selected:container:def456:web-dev:dev' <<< "$arrow_output"
if grep -Fq 'selected:host:' <<< "$arrow_output"; then
  printf '%s\n' 'arrow-key container selection must not start host tmux' >&2
  exit 1
fi

host_from_menu_output=$(printf '\nh' | main)
grep -Fq 'selected:host:dev' <<< "$host_from_menu_output"

many_input=$'\n'
for ((index = 0; index < 12; index++)); do
  many_input+=$'\033[B'
done
many_input+=$'\n'
many_output=$(printf '%s' "$many_input" | DOCKER_TEST_MODE=many main)
grep -Fq 'Docker 容器（13 个正在运行，显示 13-13）' <<< "$many_output"
grep -Fq 'selected:container:id13:container-13:dev' <<< "$many_output"

empty_output=$(printf '\n' | DOCKER_TEST_MODE=empty main)
grep -Fq 'selected:host:dev' <<< "$empty_output"

if printf '\n' | DOCKER_TEST_MODE=denied main >/dev/null 2>&1; then
  printf '%s\n' 'Docker permission failure must stop the entry flow' >&2
  exit 1
fi

grep -Fq 'exec docker exec -it' "$ENTRY"
grep -Fq 'fallback_ghostty_term' "$ENTRY"
grep -Fq 'infocmp xterm-ghostty' "$ENTRY"
grep -Fq 'export TERM=xterm-256color' "$ENTRY"
grep -Fq 'grep -Eim1 "^zh_CN\\.utf-?8$"' "$ENTRY"
grep -Fq 'grep -Eim1 "^C\\.utf-?8$"' "$ENTRY"
grep -Fq 'tmux set-environment -g LANG "$LANG"' "$ENTRY"
grep -Fq 'tmux set-environment -g LC_ALL "$LC_ALL"' "$ENTRY"
grep -Fq 'tmux set-environment -g "$variable" "$value"' "$ENTRY"
grep -Fq 'TERMSCP_MAC_USER TERMSCP_REVERSE_PORT TERMSCP_MAC_HOST' "$ENTRY"
grep -Fq 'start_termscp_container_relay "$container_id"' "$ENTRY"
grep -Fq 'start_todo_container_relay "$container_id"' "$ENTRY"
grep -Fq 'authorize_termscp_container_key \' "$ENTRY"
grep -Fq '"$container_id" "$container_name" 2>&1' "$ENTRY"
grep -Fq 'public_key=$(docker exec "$container_id" sh -c' "$ENTRY"
grep -Fq 'ssh-keygen -y -f "$key_path"' "$ENTRY"
grep -Fq 'termscp-key-authorizer request' "$ENTRY"
if grep -Fq 'Mac SFTP 公钥授权：' "$ENTRY"; then
  printf '%s\n' 'successful container key authorization must stay silent' >&2
  exit 1
fi
if grep -Fq '正在进入容器' "$ENTRY"; then
  printf '%s\n' 'container entry must not print a transition log' >&2
  exit 1
fi
grep -Fq '无法自动授权容器公钥' "$ENTRY"
grep -Fq -- '-e "TERMSCP_MAC_USER=$TERMSCP_MAC_USER"' "$ENTRY"
grep -Fq -- '-e "TERMSCP_REVERSE_PORT=${TERMSCP_REVERSE_PORT:-6022}"' "$ENTRY"
grep -Fq -- '-e "TERMSCP_MAC_HOST=$termscp_mac_host"' "$ENTRY"
grep -Fq -- '-e "TODO_BRIDGE_TOKEN=$TODO_BRIDGE_TOKEN"' "$ENTRY"
grep -Fq -- '-e "TODO_BRIDGE_PORT=${TODO_BRIDGE_PORT:-6024}"' "$ENTRY"
grep -Fq -- '-e "TODO_BRIDGE_HOST=$todo_bridge_host"' "$ENTRY"
grep -Fq 'tmux source-file "$HOME/.tmux.conf"' "$ENTRY"
grep -Fq 'tmux has-session -t "=$tmux_session"' "$ENTRY"
grep -Fq '#{pane_current_command}' "$ENTRY"
grep -Fq 'tmux list-panes -s -t "=$tmux_session"' "$ENTRY"
grep -Fq 'zsh|iris)' "$ENTRY"
grep -Fq 'attempt=$((attempt + 1))' "$ENTRY"
grep -Fq 'tmux new-window -d -P -F "#{pane_id}"' "$ENTRY"
grep -Fq 'tmux select-window -t "$zsh_window"' "$ENTRY"
grep -Fq 'tmux select-pane -t "$zsh_pane"' "$ENTRY"
grep -Fq 'exec tmux -f "$HOME/.tmux.conf" new-session -A -s "$tmux_session"' "$ENTRY"
if grep -Fq 'exec zsh -lic' "$ENTRY"; then
  printf '%s\n' 'container entry must not start interactive zsh outside tmux' >&2
  exit 1
fi
grep -Fq 'size=$(stty size 2>/dev/null || true)' "$ENTRY"
grep -Fq "trap 'prompt_resized=1' WINCH" "$ENTRY"
grep -Fq "trap 'menu_resized=1' WINCH" "$ENTRY"
grep -Fq "\$'\\033')" "$ENTRY"
grep -Fq "local hint='Enter  进入容器    Esc  进入宿主机'" "$ENTRY"
grep -Fq 'panel_width=92' "$ENTRY"
grep -Fq 'panel_width=$terminal_columns' "$ENTRY"
grep -Fq 'content_width=$((panel_width - 4))' "$ENTRY"
grep -Fq 'field_width=$((content_width - 8))' "$ENTRY"
grep -Fq 'available_rows=$((terminal_lines - 5))' "$ENTRY"
grep -Fq 'panel_row=$(((terminal_lines - panel_height) / 2 + 1))' "$ENTRY"
grep -Fq 'panel_column=$(((terminal_columns - panel_width) / 2 + 1))' "$ENTRY"
grep -Fq "local purple=\$'\\033[38;5;141m'" "$ENTRY"
grep -Fq "local selected_style=\$'\\033[1;38;5;231;48;5;55m'" "$ENTRY"
grep -Fq "panel_title=' DOCKER CONTAINERS '" "$ENTRY"
grep -Fq 'top_border="╭─${panel_title}' "$ENTRY"
grep -Fq 'bottom_border="╰$(repeat_panel_character' "$ENTRY"
grep -Fq '↑/↓ Enter进入 h宿主机 q退出' "$ENTRY"
if grep -Fq 'rendered_lines' "$ENTRY"; then
  printf '%s\n' 'container menu must not clear by counting wrapped lines' >&2
  exit 1
fi

stty() {
  if [[ ${1:-} == size ]]; then
    printf '30 100\n'
  fi
}
[[ $(terminal_size) == '30 100' ]]
prompt_output=$(render_docker_prompt)
grep -Fq $'\033[13;24H\033[38;5;141m╭─ REMOTE TARGET ' <<< "$prompt_output"
grep -Fq $'\033[14;40H\033[38;5;141m是否进入 Docker 容器？' <<< "$prompt_output"
grep -Fq $'\033[16;34H\033[38;5;245mEnter  进入容器    Esc  进入宿主机' \
  <<< "$prompt_output"
grep -Fq $'\033[17;24H\033[38;5;141m╰' <<< "$prompt_output"
