#!/usr/bin/env bash

set -euo pipefail

ROOT=$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
ENTRY="$ROOT/bin/remote-dev-entry"

# shellcheck source=../bin/remote-dev-entry
source "$ENTRY"

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
grep -Fq 'docker_environment=(-e "TERM=${TERM:-xterm-256color}")' "$ENTRY"
grep -Fq 'docker_environment+=(-e "TERM_PROGRAM=$TERM_PROGRAM")' "$ENTRY"
grep -Fq 'exec docker exec -it "${docker_environment[@]}"' "$ENTRY"
grep -Fq 'grep -Eim1 "^zh_CN\\.utf-?8$"' "$ENTRY"
grep -Fq 'grep -Eim1 "^C\\.utf-?8$"' "$ENTRY"
grep -Fq 'tmux set-environment -g LANG "$LANG"' "$ENTRY"
grep -Fq 'tmux set-environment -g LC_ALL "$LC_ALL"' "$ENTRY"
grep -Fq 'tmux source-file "$HOME/.tmux.conf"' "$ENTRY"
grep -Fq 'tmux has-session -t "=$tmux_session"' "$ENTRY"
grep -Fq '#{pane_current_command}' "$ENTRY"
grep -Fq 'tmux list-panes -s -t "=$tmux_session"' "$ENTRY"
grep -Fq 'if [ "$pane_command" = zsh ]' "$ENTRY"
grep -Fq 'attempt=$((attempt + 1))' "$ENTRY"
grep -Fq 'tmux new-window -d -P -F "#{pane_id}"' "$ENTRY"
grep -Fq 'tmux select-window -t "$zsh_window"' "$ENTRY"
grep -Fq 'tmux select-pane -t "$zsh_pane"' "$ENTRY"
grep -Fq 'exec zsh -lic' "$ENTRY"
grep -Fq 'tmux -f "$HOME/.tmux.conf" new-session -A -s "$1"' "$ENTRY"
grep -Fq 'size=$(stty size 2>/dev/null || true)' "$ENTRY"
grep -Fq "trap 'prompt_resized=1' WINCH" "$ENTRY"
grep -Fq "trap 'menu_resized=1' WINCH" "$ENTRY"
grep -Fq "\$'\\033')" "$ENTRY"
grep -Fq 'Enter：进入    Esc：进入宿主机' "$ENTRY"
grep -Fq 'menu_width=88' "$ENTRY"
grep -Fq 'menu_width=$terminal_columns' "$ENTRY"
grep -Fq 'field_width=$((menu_width - 8))' "$ENTRY"
grep -Fq 'available_rows=$((terminal_lines - 3))' "$ENTRY"
grep -Fq 'menu_row=$(((terminal_lines - menu_height) / 2 + 1))' "$ENTRY"
grep -Fq 'menu_column=$(((terminal_columns - menu_width) / 2 + 1))' "$ENTRY"
grep -Fq "printf '\\033[%d;%dH%s\\033[K'" "$ENTRY"
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
grep -Fq $'\033[15;40H是否进入 Docker 容器？' <<< "$prompt_output"
grep -Fq $'\033[17;36HEnter：进入    Esc：进入宿主机' <<< "$prompt_output"
