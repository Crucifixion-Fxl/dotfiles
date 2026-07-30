#!/usr/bin/env bash

set -euo pipefail

ROOT=$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
LAUNCHER="$ROOT/bin/ghostty-dev"
WRAPPER="$ROOT/bin/ghostty-tab-command"
APPLE_SCRIPT="$ROOT/ghostty/open-tab.applescript"
CLOSE_SCRIPT="$ROOT/ghostty/close-tab.applescript"
TEST_HOME=$(mktemp -d)
trap 'rm -rf "$TEST_HOME"' EXIT

# shellcheck source=../bin/ghostty-dev
source "$LAUNCHER"

# AppleScript 的 command 字段直接接收 shell 命令；shell:/direct: 是 config
# parser 的前缀，在此处会被 Ghostty 当成可执行文件名。
grep -Fq 'set surfaceCommand to quoted form of wrapperPath' "$APPLE_SCRIPT"
grep -Fq 'set wait after command of surfaceConfig to false' "$APPLE_SCRIPT"
grep -Fq 'set targetTabID to id of targetTab as text' "$APPLE_SCRIPT"
grep -Fq 'close tab candidateTab' "$CLOSE_SCRIPT"
if grep -Fq 'shell:exec' "$APPLE_SCRIPT"; then
  printf '%s\n' 'Ghostty AppleScript command must not contain the config-only shell: prefix' >&2
  exit 1
fi

mkdir -p "$TEST_HOME/Applications/Ghostty.app"
mkdir -p "$TEST_HOME/.local/bin"
mkdir -p "$TEST_HOME/.ssh"
mkdir -p "$TEST_HOME/tmp"
ln -s "$LAUNCHER" "$TEST_HOME/.local/bin/ghostty-dev"
[[ $(resolve_script_dir "$TEST_HOME/.local/bin/ghostty-dev") == "$ROOT/bin" ]]
printf '%s\n' \
  'Host *' \
  '  ServerAliveInterval 30' \
  'Host dev-2080Ti' \
  'Host dev-4090 dev-data' \
  'Host dev-*' \
  'Host !blocked' > "$TEST_HOME/.ssh/config"

osascript() {
  printf '<%s>\n' "$@"
}

default_output=$(HOME=$TEST_HOME TMPDIR=$TEST_HOME/tmp main)
grep -Fq "<$ROOT/ghostty/open-tab.applescript>" <<< "$default_output"
grep -Fq "<$ROOT/bin/ghostty-tab-command>" <<< "$default_output"
grep -Fq "<$ROOT/ghostty/close-tab.applescript>" <<< "$default_output"
grep -Fq "<$ROOT/bin/ghostty-dev>" <<< "$default_output"
grep -Fq '<--select-host>' <<< "$default_output"

custom_output=$(HOME=$TEST_HOME TMPDIR=$TEST_HOME/tmp main staging)
grep -Fq "<$ROOT/ghostty/open-tab.applescript>" <<< "$custom_output"
grep -Fq "<$ROOT/bin/ghostty-tab-command>" <<< "$custom_output"
grep -Fq "<$ROOT/ghostty/close-tab.applescript>" <<< "$custom_output"
grep -Fq "<$ROOT/bin/connect-remote-dev>" <<< "$custom_output"
grep -Fq '<staging>' <<< "$custom_output"

# wrapper 必须保留远端入口退出码、精确传递 tab ID，并在关闭前清理临时目录。
wrapper_state=$(mktemp -d "$TEST_HOME/tmp/ghostty-dev.XXXXXX")
printf '%s\n' 'tab-test-id' > "$wrapper_state/tab-id"
printf '%s\n' '#!/usr/bin/env bash' 'exit 7' > "$TEST_HOME/fake-connector"
printf '%s\n' '#!/usr/bin/env bash' 'printf "<%s>\\n" "$@" > "$GHOSTTY_CLOSE_LOG"' \
  > "$TEST_HOME/fake-osascript"
chmod +x "$TEST_HOME/fake-connector" "$TEST_HOME/fake-osascript"
set +e
GHOSTTY_OSASCRIPT_BIN="$TEST_HOME/fake-osascript" \
  GHOSTTY_CLOSE_LOG="$TEST_HOME/close.log" \
  "$WRAPPER" "$wrapper_state" "$CLOSE_SCRIPT" "$TEST_HOME/fake-connector" staging
wrapper_status=$?
set -e
[[ $wrapper_status -eq 7 ]]
[[ ! -e "$wrapper_state" ]]
grep -Fq "<$CLOSE_SCRIPT>" "$TEST_HOME/close.log"
grep -Fq '<tab-test-id>' "$TEST_HOME/close.log"

mapfile_output=$(HOME=$TEST_HOME list_ssh_hosts)
[[ $mapfile_output == $'dev-2080Ti\ndev-4090\ndev-data' ]]

launch_connector() {
  printf 'connector=%s\nhost=%s\n' "$1" "$2"
}

selected_output=$(printf '\033[A\n' | HOME=$TEST_HOME run_server_selector 2>>"$TEST_HOME/menu.log")
grep -Fq "connector=$ROOT/bin/connect-remote-dev" <<< "$selected_output"
grep -Fq 'host=dev-2080Ti' <<< "$selected_output"

default_selected_output=$(printf '\n' | HOME=$TEST_HOME run_server_selector 2>>"$TEST_HOME/menu.log")
grep -Fq 'host=dev-4090' <<< "$default_selected_output"

down_output=$(printf '\033[B\n' | HOME=$TEST_HOME run_server_selector 2>>"$TEST_HOME/menu.log")
grep -Fq 'host=dev-data' <<< "$down_output"
grep -Fq 'dev-2080Ti' "$TEST_HOME/menu.log"
grep -Fq 'dev-4090' "$TEST_HOME/menu.log"
grep -Fq 'dev-data' "$TEST_HOME/menu.log"
grep -Fq '↑/↓ 选择  Enter 确认  q/Esc 取消' "$TEST_HOME/menu.log"

printf '\n' | HOME=$TEST_HOME LINES=20 COLUMNS=100 \
  run_server_selector 2>"$TEST_HOME/menu-large.log" >/dev/null
grep -Fq $'\033[7;33H请选择 Ghostty 要连接的 SSH 服务器：' "$TEST_HOME/menu-large.log"
grep -Fq $'\033[13;33H↑/↓ 选择  Enter 确认  q/Esc 取消' "$TEST_HOME/menu-large.log"

printf '\n' | HOME=$TEST_HOME LINES=11 COLUMNS=60 \
  run_server_selector 2>"$TEST_HOME/menu-small.log" >/dev/null
grep -Fq $'\033[3;13H请选择 Ghostty 要连接的 SSH 服务器：' "$TEST_HOME/menu-small.log"
grep -Fq $'\033[9;13H↑/↓ 选择  Enter 确认  q/Esc 取消' "$TEST_HOME/menu-small.log"

if (HOME=$TEST_HOME TMPDIR=$TEST_HOME/tmp main one two) >/dev/null 2>&1; then
  printf '%s\n' 'ghostty-dev must accept at most one SSH host' >&2
  exit 1
fi
