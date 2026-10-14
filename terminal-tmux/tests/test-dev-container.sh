#!/usr/bin/env bash

set -euo pipefail

ROOT=$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
COMMAND="$ROOT/bin/dev-container"

# shellcheck source=../bin/dev-container
source "$COMMAND"

selection_state=$(mktemp -d)
export XDG_STATE_HOME="$selection_state"
trap 'rm -rf "$selection_state"' EXIT

# 先加载真实入口再注入桩；load_remote_dev_entry 的幂等保护保证 main 运行时
# 不会重新 source 覆盖这些桩。
load_remote_dev_entry "$ROOT/bin"

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
      empty)
        return 0
        ;;
    esac
  fi
}

enter_host_tmux() {
  printf 'selected:host:%s\n' "$HOST_TMUX_SESSION"
}

enter_container_tmux() {
  printf 'selected:container:%s:%s\n' "$1" "$2"
}

# 直接回车：不经任何询问就进入容器菜单并选中首位容器。
container_output=$(printf '\n' | run_dev_container)
grep -Fq 'selected:container:abc123:api-dev' <<< "$container_output"
if grep -Fq '是否进入 Docker 容器' <<< "$container_output"; then
  printf '%s\n' 'dev-container must skip the host/container prompt' >&2
  exit 1
fi

# 菜单内按 h 仍可进入宿主机 tmux；j 移动后 Enter 选择第二项。
host_output=$(printf 'h' | run_dev_container)
grep -Fq 'selected:host:dev' <<< "$host_output"
arrow_output=$(printf 'j\n' | DOCKER_TEST_MODE=multiple run_dev_container)
grep -Fq 'selected:container:def456:web-dev' <<< "$arrow_output"

# 没有运行中的容器时回退宿主机 tmux，与 ghostty-dev 容器分支一致。
empty_output=$(printf '\n' | DOCKER_TEST_MODE=empty run_dev_container)
grep -Fq 'selected:host:dev' <<< "$empty_output"

# 实现必须复用 remote-dev-entry 的菜单，而不是复制一份。
grep -Fq 'remote-dev-entry' "$COMMAND"
grep -Fq 'choose_container' "$COMMAND"

# 找不到 remote-dev-entry 时给出可行动的提示。
missing_message=$(
  PATH=/usr/bin:/bin bash -c 'source "$1"; load_remote_dev_entry "$2"' \
    dev-container-test "$COMMAND" "$selection_state/missing" 2>&1 >/dev/null || true
)
grep -Fq 'dev-container：找不到 remote-dev-entry' <<< "$missing_message"
grep -Fq 'ghostty-dev' <<< "$missing_message"

# 同目录没有入口时回退到 PATH 中的 remote-dev-entry。
fallback_directory="$selection_state/path-fallback"
mkdir -p "$fallback_directory"
printf '%s\n' '#!/usr/bin/env bash' \
  'fail() { printf "%s\n" "stub-fail" >&2; exit 1; }' \
  'set_terminal_title() { :; }' \
  'DISPLAY_LABEL=stub' \
  'choose_container() { printf "%s\n" "fallback-entry-loaded"; }' \
  > "$fallback_directory/remote-dev-entry"
fallback_output=$(
  PATH="$fallback_directory:/usr/bin:/bin" bash -c \
    'source "$1"; load_remote_dev_entry "$2"; run_dev_container' \
    dev-container-fallback-test "$COMMAND" "$selection_state/no-entry-here" 2>&1
)
grep -Fq 'fallback-entry-loaded' <<< "$fallback_output"

printf '%s\n' 'dev-container tests passed'
