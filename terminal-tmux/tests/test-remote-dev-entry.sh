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
grep -Fq 'grep -Eim1 "^zh_CN\\.utf-?8$"' "$ENTRY"
grep -Fq 'grep -Eim1 "^C\\.utf-?8$"' "$ENTRY"
grep -Fq 'tmux set-environment -g LANG "$LANG"' "$ENTRY"
grep -Fq 'tmux set-environment -g LC_ALL "$LC_ALL"' "$ENTRY"
grep -Fq 'tmux source-file "$HOME/.tmux.conf"' "$ENTRY"
grep -Fq 'exec zsh -lic' "$ENTRY"
grep -Fq 'tmux -f "$HOME/.tmux.conf" new-session -A -s "$1"' "$ENTRY"
grep -Fq "trap 'render_docker_prompt' WINCH" "$ENTRY"
grep -Fq "\$'\\033')" "$ENTRY"
grep -Fq 'Enter：进入    Esc：进入宿主机' "$ENTRY"
grep -Fq "printf '\\0337'" "$ENTRY"
grep -Fq "printf '\\0338\\033[J'" "$ENTRY"
if grep -Fq 'rendered_lines' "$ENTRY"; then
  printf '%s\n' 'container menu must not clear by counting wrapped lines' >&2
  exit 1
fi
