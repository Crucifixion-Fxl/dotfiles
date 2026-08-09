#!/usr/bin/env bash

set -euo pipefail

ROOT=$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
TEST_HOME=$(mktemp -d)
trap 'rm -rf "$TEST_HOME"' EXIT

# shellcheck source=../bootstrap.sh
source "$ROOT/bootstrap.sh"

mkdir -p "$TEST_HOME/.local/bin"
cat > "$TEST_HOME/.local/bin/iris" <<'SH'
#!/usr/bin/env bash
case "${1:-}" in
  init)
    [[ ${2:-} == zsh ]]
    printf '%s\n' 'export IRIS_AUTOSTART_TEST=1'
    ;;
  version)
    printf '%s\n' 'iris 999.0.0'
    ;;
esac
SH
chmod +x "$TEST_HOME/.local/bin/iris"

# Reproduce the fresh-machine order. The managed zsh entrypoint must already
# be linked before later network installs can fail or be interrupted.
HOME=$TEST_HOME ensure_shell_path
HOME=$TEST_HOME ensure_shell_locale
HOME=$TEST_HOME install_shell_links

[[ -L "$TEST_HOME/.zshrc" ]]
[[ $(readlink "$TEST_HOME/.zshrc") == "$ROOT/shell/zshrc" ]]
[[ -L "$TEST_HOME/.config/tmux/window-name.zsh" ]]
[[ $(readlink "$TEST_HOME/.config/tmux/window-name.zsh") == "$ROOT/shell/tmux-window-name.zsh" ]]

env \
  -u IRIS_PID \
  -u IRIS_IS_CHILD \
  -u IRIS_FD \
  -u IRIS_TTY \
  -u IRIS_RESCUE \
  -u IRIS_ACTIVE_SHELL \
  HOME="$TEST_HOME" \
  ZDOTDIR="$TEST_HOME" \
  PATH=/usr/bin:/bin \
  /bin/zsh -lic '[[ ${IRIS_AUTOSTART_TEST:-} == 1 ]]'

printf '%s\n' 'iris fresh-shell autostart test passed'
