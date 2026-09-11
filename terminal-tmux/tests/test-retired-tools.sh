#!/usr/bin/env bash
set -euo pipefail
ROOT=$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
TEST_ROOT=$(mktemp -d)
trap 'rm -rf "$TEST_ROOT"' EXIT
source "$ROOT/bootstrap.sh"
export HOME="$TEST_ROOT/home"
mkdir -p "$HOME/.local/bin" "$HOME/.local/state/todoist-codex" \
  "$HOME/.config/systemd/user/default.target.wants" \
  "$HOME/.local/lib/node_modules/@doist/todoist-cli" \
  "$HOME/.local/share/todoist-codex/worktrees"
for name in todo todo-agent; do
  ln -s "$ROOT/bin/$name" "$HOME/.local/bin/$name"
done
printf '%s\n' '{"name":"@doist/todoist-cli"}' > "$HOME/.local/lib/node_modules/@doist/todoist-cli/package.json"
ln -s ../lib/node_modules/@doist/todoist-cli/dist/index.js "$HOME/.local/bin/td"
ln -s "$ROOT/systemd/todo-agent.service" "$HOME/.config/systemd/user/todo-agent.service"
ln -s ../todo-agent.service "$HOME/.config/systemd/user/default.target.wants/todo-agent.service"
printf 'keep history\n' > "$HOME/.local/state/todoist-codex/runs.json"
printf 'keep work\n' > "$HOME/.local/share/todoist-codex/worktrees/work.txt"
SYSTEMD_LOG="$TEST_ROOT/systemd.log"
systemctl() {
  printf '%s\n' "$*" >> "$SYSTEMD_LOG"
  if [[ $2 == show ]]; then printf 'loaded\n'; fi
}
remove_legacy_todoist
for name in todo todo-agent td; do [[ ! -L "$HOME/.local/bin/$name" ]]; done
[[ ! -d "$HOME/.local/lib/node_modules/@doist/todoist-cli" ]]
[[ ! -L "$HOME/.config/systemd/user/todo-agent.service" ]]
[[ ! -L "$HOME/.config/systemd/user/default.target.wants/todo-agent.service" ]]
grep -Fxq -- '--user stop todo-agent.service' "$SYSTEMD_LOG"
grep -Fxq -- '--user daemon-reload' "$SYSTEMD_LOG"
[[ $(cat "$HOME/.local/state/todoist-codex/runs.json") == 'keep history' ]]
[[ $(cat "$HOME/.local/share/todoist-codex/worktrees/work.txt") == 'keep work' ]]
remove_legacy_todoist

# Independently installed commands/units are outside the retired install.
printf 'custom\n' > "$HOME/.local/bin/todo"
ln -s /another/install/td "$HOME/.local/bin/td"
ln -s /another/install/todo-agent.service "$HOME/.config/systemd/user/todo-agent.service"
remove_legacy_todoist
[[ $(cat "$HOME/.local/bin/todo") == custom ]]
[[ $(readlink "$HOME/.local/bin/td") == /another/install/td ]]
[[ $(readlink "$HOME/.config/systemd/user/todo-agent.service") == /another/install/todo-agent.service ]]

# Model Linux without user systemd. Only a PID with our watcher command may
# receive TERM; a stale PID pointing at an unrelated process must survive.
(
  systemctl() { return 1; }
  command_line="python3 $HOME/.local/bin/todo-agent watch --interval 10"
  stopped=0
  kill() {
    if [[ $1 == -0 ]]; then [[ $stopped == 0 ]]; else stopped=1; fi
  }
  ps() {
    if [[ $* == *stat=* ]]; then printf 'S\n'; else printf '%s\n' "$command_line"; fi
  }
  printf '99999999\n' > "$HOME/.local/state/todoist-codex/watcher.pid"
  remove_legacy_todoist
  [[ $stopped == 1 ]]
  [[ ! -e "$HOME/.local/state/todoist-codex/watcher.pid" ]]
  stopped=0
  command_line='python3 unrelated-worker.py'
  printf '99999999\n' > "$HOME/.local/state/todoist-codex/watcher.pid"
  remove_legacy_todoist
  [[ $stopped == 0 ]]
  # Zombies no longer hold the dispatcher lock.
  ps() { printf 'Z\n'; }
  printf '99999999\n' > "$HOME/.local/state/todoist-codex/watcher.pid"
  remove_legacy_todoist
  [[ $stopped == 0 ]]
)
printf '%s\n' 'retired tools migration tests passed'
