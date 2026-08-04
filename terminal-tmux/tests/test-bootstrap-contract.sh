#!/usr/bin/env bash

set -euo pipefail

ROOT=$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
README="$ROOT/../README.md"
BOOTSTRAP="$ROOT/bootstrap.sh"
WORKFLOW_IMAGE="$ROOT/assets/dotfiles-workflow.png"
ITERM_PROFILE="$ROOT/iterm2/dev.json"
GHOSTTY_CONFIG="$ROOT/ghostty/config.ghostty"
GHOSTTY_TERMINFO="$ROOT/terminfo/xterm-ghostty.terminfo"
GHOSTTY_LAUNCHER="$ROOT/bin/ghostty-dev"
GHOSTTY_APPLESCRIPT="$ROOT/ghostty/open-tab.applescript"
GHOSTTY_CLOSE_APPLESCRIPT="$ROOT/ghostty/close-tab.applescript"
TERMSCP_LAUNCHER="$ROOT/bin/termscp-mac"
TERMSCP_AUTHORIZER="$ROOT/bin/termscp-key-authorizer"
TODO_TUI="$ROOT/bin/todo"
TODO_AGENT="$ROOT/bin/todo-agent"
TODO_AGENT_SERVICE="$ROOT/systemd/todo-agent.service"
VERSIONS="$ROOT/versions.lock"
TMUX_CONFIG="$ROOT/tmux/tmux.conf"

bash -n "$BOOTSTRAP"
[[ -s "$WORKFLOW_IMAGE" ]]
grep -Fq '![dotfiles 整体工作流](terminal-tmux/assets/dotfiles-workflow.png)' "$README"
grep -q 'ncurses-base' "$BOOTSTRAP"
grep -q 'bubblewrap' "$BOOTSTRAP"
grep -q 'btop' "$BOOTSTRAP"
grep -q 'fonts-noto-cjk' "$BOOTSTRAP"
grep -q 'locales' "$BOOTSTRAP"
grep -q 'fd-find' "$BOOTSTRAP"
grep -q 'ffmpeg' "$BOOTSTRAP"
grep -q 'poppler-utils' "$BOOTSTRAP"
grep -q 'resvg' "$BOOTSTRAP"
grep -q 'unzip' "$BOOTSTRAP"
grep -q 'xz-utils' "$BOOTSTRAP"
grep -q 'python3 python3-venv ripgrep' "$BOOTSTRAP"
grep -q 'openssh-client' "$BOOTSTRAP"
grep -q 'passwd' "$BOOTSTRAP"
grep -q 'command -v ssh-keygen' "$BOOTSTRAP"
grep -q 'pkgconf python utf8proc' "$BOOTSTRAP"
grep -q 'vim zsh' "$BOOTSTRAP"
grep -q 'font-maple-mono-nf-cn' "$BOOTSTRAP"
grep -q '^ensure_tmux_terminfo()' "$BOOTSTRAP"
grep -q '^ensure_ghostty_terminfo()' "$BOOTSTRAP"
grep -q '^configure_locale()' "$BOOTSTRAP"
grep -q '^current_login_shell()' "$BOOTSTRAP"
grep -q '^configure_login_shell()' "$BOOTSTRAP"
grep -q '^ensure_linux_fd_command()' "$BOOTSTRAP"
grep -q '^install_fzf()' "$BOOTSTRAP"
grep -q '^install_zoxide()' "$BOOTSTRAP"
grep -q '^install_iris()' "$BOOTSTRAP"
grep -q '^install_glow()' "$BOOTSTRAP"
grep -q '^install_yazi()' "$BOOTSTRAP"
grep -q '^install_yazi_packages()' "$BOOTSTRAP"
grep -q '^install_pre_commit()' "$BOOTSTRAP"
grep -q '^install_termscp()' "$BOOTSTRAP"
grep -q '^uninstall_druk()' "$BOOTSTRAP"
grep -q '^install_fresh()' "$BOOTSTRAP"
grep -q '^install_ghostty()' "$BOOTSTRAP"
grep -q '^install_node_for_todoist()' "$BOOTSTRAP"
grep -q '^install_todoist_cli()' "$BOOTSTRAP"
grep -q '^remove_legacy_todo_bridge()' "$BOOTSTRAP"
grep -q '^configure_git_identity()' "$BOOTSTRAP"
grep -q '^remind_ssh_key()' "$BOOTSTRAP"
grep -Fq 'Configure the missing Git identity now? [y/N]:' "$BOOTSTRAP"
grep -Fq 'bootstrap will ask again next time' "$BOOTSTRAP"
grep -Fq 'backup_and_link "$DOTFILES_DIR/bin/todo" "$HOME/.local/bin/todo"' "$BOOTSTRAP"
grep -Fq 'backup_and_link "$DOTFILES_DIR/bin/todo-agent" "$HOME/.local/bin/todo-agent"' "$BOOTSTRAP"
grep -q '^install_todo_agent_service()' "$BOOTSTRAP"
grep -q '^todo_agent_systemd_available()' "$BOOTSTRAP"
grep -q '^todo_agent_pid_running()' "$BOOTSTRAP"
grep -q '^todo_agent_fallback_running()' "$BOOTSTRAP"
grep -q '^stop_todo_agent_fallback()' "$BOOTSTRAP"
grep -q '^start_todo_agent_fallback()' "$BOOTSTRAP"
grep -q '^restart_todo_agent_fallback()' "$BOOTSTRAP"
grep -q '^todo_agent_background_running()' "$BOOTSTRAP"
grep -Fq 'systemctl --user enable todo-agent.service' "$BOOTSTRAP"
grep -Fq 'systemctl --user restart todo-agent.service' "$BOOTSTRAP"
grep -Fq 'nohup "$HOME/.local/bin/todo-agent" watch --interval 10' "$BOOTSTRAP"
grep -Fq 'watch.add_argument("--interval", type=int, default=10' "$TODO_AGENT"
grep -Fq 'python3-venv' "$BOOTSTRAP"
grep -Fq '"@doist/todoist-cli@$TODOIST_CLI_VERSION"' "$BOOTSTRAP"
grep -Eq '^TODOIST_CLI_VERSION=[0-9]+\.[0-9]+\.[0-9]+$' "$VERSIONS"
grep -Eq '^NODE_VERSION=24\.[0-9]+\.[0-9]+$' "$VERSIONS"
python3 "$TODO_TUI" --help >/dev/null
python3 "$TODO_AGENT" --help >/dev/null
grep -Fq 'ExecStart=%h/.local/bin/todo-agent watch' "$TODO_AGENT_SERVICE"
grep -Fq 'Restart=always' "$TODO_AGENT_SERVICE"
[[ $(grep -Fc '  hash -r' "$BOOTSTRAP") -ge 2 ]]
[[ $(grep -Fc 'run_as_root env DEBIAN_FRONTEND=noninteractive apt-get install -y' "$BOOTSTRAP") -eq 2 ]]

prerequisite_function=$(sed -n '/^install_prerequisites()/,/^}/p' "$BOOTSTRAP")
[[ $(grep -Eoc '(^|[[:space:]])btop($|[[:space:]])' <<< "$prerequisite_function") -eq 2 ]]
grep -Fq 'command -v btop >/dev/null 2>&1 || fail "btop is required"' "$BOOTSTRAP"
if grep -Eq '(^|[[:space:]])(fzf|zoxide)($|[[:space:]])' <<< "$prerequisite_function"; then
  printf '%s\n' 'fzf and zoxide must come from pinned official releases, not apt or Homebrew' >&2
  exit 1
fi

if grep -Eq '(^|[[:space:]])(nodejs|npm)($|[[:space:]])' <<< "$prerequisite_function"; then
  printf '%s\n' 'Linux Node and npm must come from the pinned user-level runtime, not apt' >&2
  exit 1
fi

if grep -q 'run_as_root apt-get install' "$BOOTSTRAP"; then
  printf '%s\n' 'all apt package installs must use the noninteractive debconf frontend' >&2
  exit 1
fi

if grep -q 'tmux\.terminfo' "$BOOTSTRAP"; then
  printf '%s\n' 'bootstrap must not expect tmux.terminfo in the tmux release tarball' >&2
  exit 1
fi

# Direct Ghostty SSH sessions keep TERM=xterm-ghostty, so bootstrap must install
# the matching entry without requiring root access.
[[ -s "$GHOSTTY_TERMINFO" ]]
grep -Eq '^xterm-ghostty\|ghostty\|Ghostty terminal emulator,' "$GHOSTTY_TERMINFO"
grep -Fq 'tic -x -o "$HOME/.terminfo" "$source_file"' "$BOOTSTRAP"
(
  ghostty_terminfo_home=$(mktemp -d)
  trap 'rm -rf "$ghostty_terminfo_home"' EXIT
  TERMINFO="$ghostty_terminfo_home" tic -x -o "$ghostty_terminfo_home" "$GHOSTTY_TERMINFO"
  TERMINFO="$ghostty_terminfo_home" infocmp xterm-ghostty >/dev/null
)

# Exercise install_plugin under set -u. Bash expands a whole `local` command
# before applying its assignments, so dependent values must be assigned on a
# later line.
TEST_HOME=$(mktemp -d)
FALLBACK_HOME=$(mktemp -d)
trap 'rm -rf "$TEST_HOME" "$FALLBACK_HOME"' EXIT
TEST_PLUGIN_COMMIT=0123456789abcdef

# shellcheck source=../bootstrap.sh
source "$BOOTSTRAP"

# Linux containers without a user systemd manager receive one persistent nohup
# watcher. Starting is idempotent, while restarting replaces the old process so
# a repeated bootstrap loads the current dispatcher code.
mkdir -p "$FALLBACK_HOME/.local/bin"
printf '%s\n' \
  '#!/usr/bin/env bash' \
  'while :; do sleep 60; done' \
  > "$FALLBACK_HOME/.local/bin/todo-agent"
chmod +x "$FALLBACK_HOME/.local/bin/todo-agent"
(
  HOME=$FALLBACK_HOME
  TODO_AGENT_SKIP_CMDLINE_CHECK=1
  export TODO_AGENT_SKIP_CMDLINE_CHECK
  start_todo_agent_fallback
  todo_agent_fallback_running
  first_pid=$(sed -n '1p' "$FALLBACK_HOME/.local/state/todoist-codex/watcher.pid")
  start_todo_agent_fallback
  second_pid=$(sed -n '1p' "$FALLBACK_HOME/.local/state/todoist-codex/watcher.pid")
  [[ "$first_pid" == "$second_pid" ]]
  restart_todo_agent_fallback
  third_pid=$(sed -n '1p' "$FALLBACK_HOME/.local/state/todoist-codex/watcher.pid")
  [[ "$third_pid" != "$first_pid" ]]
  stop_todo_agent_fallback
  [[ ! -e "$FALLBACK_HOME/.local/state/todoist-codex/watcher.pid" ]]
)

# Some containers do not reap orphaned children. After bootstrap sends TERM,
# the old watcher can therefore remain as a zombie: kill -0 still succeeds,
# but the process no longer owns the dispatcher lock and must not block the
# replacement watcher from starting.
(
  HOME=$FALLBACK_HOME
  TODO_AGENT_SKIP_CMDLINE_CHECK=1
  export TODO_AGENT_SKIP_CMDLINE_CHECK
  zombie_pid=424242
  kill() {
    return 0
  }
  ps() {
    printf '%s\n' Z
  }
  printf '%s\n' "$zombie_pid" \
    > "$FALLBACK_HOME/.local/state/todoist-codex/watcher.pid"
  stop_todo_agent_fallback
  [[ ! -e "$FALLBACK_HOME/.local/state/todoist-codex/watcher.pid" ]]
)

git() {
  if [[ $1 == clone ]]; then
    mkdir -p "$3/.git"
    return 0
  fi

  if [[ $1 == -C && $3 == status ]]; then
    return 0
  fi

  if [[ $1 == -C && $3 == rev-parse ]]; then
    printf '%s\n' "$TEST_PLUGIN_COMMIT"
    return 0
  fi

  return 0
}

HOME=$TEST_HOME install_plugin test-plugin https://example.invalid/test.git "$TEST_PLUGIN_COMMIT"
HOME=$TEST_HOME install_git_checkout test-checkout https://example.invalid/test.git \
  "$TEST_PLUGIN_COMMIT" "$TEST_HOME/.test-checkout"

# A fresh bootstrap changes an existing Bash login shell to zsh, while an
# account that already uses zsh remains untouched.
login_shell_change=$(
  (
    PLATFORM_OS=linux
    current_login_shell() { printf '%s\n' /bin/bash; }
    run_as_root() { printf 'run-as-root:%s\n' "$*"; }
    configure_login_shell
  )
)
grep -Fq "Setting the login shell for $(id -un) to $(command -v zsh)" <<< "$login_shell_change"
grep -Fq "run-as-root:chsh -s $(command -v zsh) $(id -un)" <<< "$login_shell_change"

login_shell_noop=$(
  (
    PLATFORM_OS=linux
    current_login_shell() { command -v zsh; }
    run_as_root() { printf '%s\n' 'unexpected root call'; return 1; }
    configure_login_shell
  )
)
[[ -z "$login_shell_noop" ]]

# A fresh zoxide database receives useful initial entries exactly once. This
# prevents Yazi's zoxide picker from starting with an empty-history error while
# avoiding rank inflation on repeated bootstrap runs.
ZOXIDE_HISTORY=
ZOXIDE_ADDS=
zoxide() {
  if [[ $1 == query && $2 == --list ]]; then
    printf '%s' "$ZOXIDE_HISTORY"
  elif [[ $1 == add ]]; then
    ZOXIDE_ADDS+="$2"$'\n'
  fi
}
mkdir -p "$TEST_HOME/Documents" "$TEST_HOME/.dotfiles"
HOME=$TEST_HOME seed_zoxide_history
[[ $ZOXIDE_ADDS == *"$TEST_HOME/Documents"* ]]
[[ $ZOXIDE_ADDS == *"$TEST_HOME/.dotfiles"* ]]

ZOXIDE_HISTORY=$TEST_HOME/Documents
ZOXIDE_ADDS=
HOME=$TEST_HOME seed_zoxide_history
[[ -z $ZOXIDE_ADDS ]]
unset -f zoxide

# iTerm2 profiles are macOS-only dynamic profiles. Linux must skip the link;
# macOS links the validated repository file into iTerm2's watched directory.
PLATFORM_OS=linux HOME=$TEST_HOME install_iterm2_profile
[[ ! -e "$TEST_HOME/Library/Application Support/iTerm2/DynamicProfiles/dev.json" ]]
if command -v plutil >/dev/null 2>&1; then
  ITERM_DIRECTORY="$TEST_HOME/Library/Application Support/iTerm2/DynamicProfiles"
  mkdir -p "$ITERM_DIRECTORY"
  ln -s "$ROOT/iterm2/dev-4090.json" "$ITERM_DIRECTORY/dev-4090.json"
  PLATFORM_OS=darwin HOME=$TEST_HOME install_iterm2_profile
  ITERM_DESTINATION="$TEST_HOME/Library/Application Support/iTerm2/DynamicProfiles/dev.json"
  [[ ! -L "$ITERM_DIRECTORY/dev-4090.json" ]]
  [[ -L "$ITERM_DESTINATION" ]]
  [[ $(readlink "$ITERM_DESTINATION") == "$ITERM_PROFILE" ]]
fi
grep -Fq '"Name": "dev"' "$ITERM_PROFILE"
grep -Fq '"Guid": "8485C550-40AA-4993-9F56-A7F3E3A1F35B"' "$ITERM_PROFILE"
grep -Fq '"Custom Command": "Yes"' "$ITERM_PROFILE"
grep -Fq 'connect-remote-dev\" dev-4090' "$ITERM_PROFILE"
grep -Fq '"Normal Font": "MapleMono-NF-CN-Regular 16"' "$ITERM_PROFILE"
if grep -Fq '9943041F-8D80-4EC9-B604-20F6DAFFD4ED' "$ITERM_PROFILE"; then
  printf '%s\n' 'dynamic profile must not reuse the legacy regular profile GUID' >&2
  exit 1
fi
if grep -Fq '/Users/a4x' "$ITERM_PROFILE"; then
  printf '%s\n' 'iTerm2 profile must not contain a machine-specific home path' >&2
  exit 1
fi

# Ghostty uses its own text config and a separate launcher, while sharing the
# same connect-remote-dev and remote-dev-entry implementation with iTerm2.
(
  BREW_ARGS=
  GHOSTTY_PRESENT=0
  ghostty_binary() {
    ((GHOSTTY_PRESENT)) && printf '%s\n' "$TEST_HOME/fake-ghostty"
  }
  brew() {
    BREW_ARGS="$*"
    GHOSTTY_PRESENT=1
  }

  PLATFORM_OS=linux
  install_ghostty
  [[ -z $BREW_ARGS ]]
  PLATFORM_OS=darwin
  install_ghostty
  [[ $BREW_ARGS == 'install --cask ghostty' ]]
  BREW_ARGS=
  install_ghostty
  [[ -z $BREW_ARGS ]]
)
(
  # Contract tests validate managed paths without launching the real macOS app
  # binary, which may initialize GUI/crash-reporting services in a sandbox.
  ghostty_binary() {
    return 1
  }

  PLATFORM_OS=linux HOME=$TEST_HOME install_ghostty_config
  [[ ! -e "$TEST_HOME/Library/Application Support/com.mitchellh.ghostty/config.ghostty" ]]
  [[ ! -e "$TEST_HOME/.local/bin/ghostty-dev" ]]
  PLATFORM_OS=darwin HOME=$TEST_HOME install_ghostty_config
)
GHOSTTY_DESTINATION="$TEST_HOME/Library/Application Support/com.mitchellh.ghostty/config.ghostty"
GHOSTTY_LAUNCHER_DESTINATION="$TEST_HOME/.local/bin/ghostty-dev"
[[ -L "$GHOSTTY_DESTINATION" ]]
[[ $(readlink "$GHOSTTY_DESTINATION") == "$GHOSTTY_CONFIG" ]]
[[ -L "$GHOSTTY_LAUNCHER_DESTINATION" ]]
[[ $(readlink "$GHOSTTY_LAUNCHER_DESTINATION") == "$GHOSTTY_LAUNCHER" ]]
grep -Fq 'font-family = "Maple Mono NF CN"' "$GHOSTTY_CONFIG"
grep -Fq 'font-size = 16' "$GHOSTTY_CONFIG"
grep -Fq 'theme = "light:Catppuccin Latte,dark:Catppuccin Mocha"' "$GHOSTTY_CONFIG"
grep -Fq 'background-opacity = 0.75' "$GHOSTTY_CONFIG"
grep -Fq 'background-blur-radius = 30' "$GHOSTTY_CONFIG"
grep -Fq 'macos-titlebar-style = tabs' "$GHOSTTY_CONFIG"
grep -Fq 'window-new-tab-position = current' "$GHOSTTY_CONFIG"
grep -Fq 'wait-after-command = false' "$GHOSTTY_CONFIG"
grep -Fq 'shell-integration = zsh' "$GHOSTTY_CONFIG"
grep -Fq 'keybind = super+shift+r=prompt_tab_title' "$GHOSTTY_CONFIG"
grep -Fq 'keybind = super+shift+alt+left=move_tab:-1' "$GHOSTTY_CONFIG"
grep -Fq 'keybind = super+shift+comma=reload_config' "$GHOSTTY_CONFIG"
grep -Fq 'new tab in targetWindow with configuration surfaceConfig' "$GHOSTTY_APPLESCRIPT"
grep -Fq 'if (count of windows) is 0' "$GHOSTTY_APPLESCRIPT"
grep -Fq 'set wait after command of surfaceConfig to false' "$GHOSTTY_APPLESCRIPT"
grep -Fq 'set targetTabID to id of targetTab as text' "$GHOSTTY_APPLESCRIPT"
grep -Fq 'close tab candidateTab' "$GHOSTTY_CLOSE_APPLESCRIPT"
if grep -Fq '/Users/a4x' "$GHOSTTY_CONFIG"; then
  printf '%s\n' 'Ghostty config must not contain a machine-specific home path' >&2
  exit 1
fi

# Yazi is pinned and installed from official Release ZIP assets on macOS and
# Debian/Ubuntu. The yazi and ya versions must always match.
fzf() {
  printf '%s (test)\n' "$FZF_VERSION"
}
zoxide() {
  printf 'zoxide %s\n' "$ZOXIDE_VERSION"
}
glow() {
  printf 'glow version %s\n' "$GLOW_VERSION"
}
iris() {
  printf 'iris v%s\n' "$IRIS_VERSION"
}
fzf_is_locked_version
zoxide_is_locked_version
iris_is_locked_version
glow_is_locked_version
unset -f fzf zoxide iris glow

yazi() {
  printf 'Yazi %s (test)\n' "$YAZI_VERSION"
}
ya() {
  printf 'Ya %s (test)\n' "$YAZI_VERSION"
}
yazi_is_locked_version

# pre-commit uses the same checked zipapp on macOS and Linux. Its launcher
# selects Python 3.10+ explicitly, which avoids an older /usr/bin/python3 on
# macOS shadowing Homebrew Python.
TEST_PRE_COMMIT_SOURCE="$TEST_HOME/pre-commit-test.pyz"
cat > "$TEST_PRE_COMMIT_SOURCE" <<'PY'
import sys

if sys.argv[1:] == ['--version']:
    print('pre-commit test')
PY
TEST_PRE_COMMIT_SHA=$(sha256_file "$TEST_PRE_COMMIT_SOURCE")
ORIGINAL_PRE_COMMIT_VERSION=$PRE_COMMIT_VERSION
ORIGINAL_PRE_COMMIT_SHA256=$PRE_COMMIT_SHA256
PRE_COMMIT_VERSION=test
PRE_COMMIT_SHA256=$TEST_PRE_COMMIT_SHA
download() {
  cp "$TEST_PRE_COMMIT_SOURCE" "$2"
}
PATH="$TEST_HOME/.local/bin:$PATH" HOME=$TEST_HOME install_pre_commit
PATH="$TEST_HOME/.local/bin:$PATH" HOME=$TEST_HOME pre_commit_is_locked_version
[[ -L "$TEST_HOME/.local/bin/pre-commit" ]]
[[ $(readlink "$TEST_HOME/.local/bin/pre-commit") == "$ROOT/bin/pre-commit" ]]
PRE_COMMIT_VERSION=$ORIGINAL_PRE_COMMIT_VERSION
PRE_COMMIT_SHA256=$ORIGINAL_PRE_COMMIT_SHA256

for version_variable in \
  FZF_VERSION \
  FZF_SHA256_DARWIN_ARM64 \
  FZF_SHA256_DARWIN_X86_64 \
  FZF_SHA256_LINUX_ARM64 \
  FZF_SHA256_LINUX_X86_64 \
  ZOXIDE_VERSION \
  ZOXIDE_SHA256_DARWIN_ARM64 \
  ZOXIDE_SHA256_DARWIN_X86_64 \
  ZOXIDE_SHA256_LINUX_ARM64 \
  ZOXIDE_SHA256_LINUX_X86_64 \
  IRIS_VERSION \
  IRIS_SHA256_DARWIN_ARM64 \
  IRIS_SHA256_DARWIN_X86_64 \
  IRIS_SHA256_LINUX_ARM64 \
  IRIS_SHA256_LINUX_X86_64 \
  GLOW_VERSION \
  GLOW_SHA256_DARWIN_ARM64 \
  GLOW_SHA256_DARWIN_X86_64 \
  GLOW_SHA256_LINUX_ARM64 \
  GLOW_SHA256_LINUX_X86_64 \
  YAZI_VERSION \
  YAZI_SHA256_DARWIN_ARM64 \
  YAZI_SHA256_DARWIN_X86_64 \
  YAZI_SHA256_LINUX_ARM64 \
  YAZI_SHA256_LINUX_X86_64 \
  PRE_COMMIT_VERSION \
  PRE_COMMIT_SHA256; do
  grep -q "^${version_variable}=" "$ROOT/versions.lock"
done

PLATFORM_OS=darwin PLATFORM_ARCH=arm64 fzf_asset
[[ $ASSET == "fzf-${FZF_VERSION}-darwin_arm64.tar.gz" ]]
PLATFORM_OS=darwin PLATFORM_ARCH=x86_64 fzf_asset
[[ $ASSET == "fzf-${FZF_VERSION}-darwin_amd64.tar.gz" ]]
PLATFORM_OS=linux PLATFORM_ARCH=arm64 fzf_asset
[[ $ASSET == "fzf-${FZF_VERSION}-linux_arm64.tar.gz" ]]
PLATFORM_OS=linux PLATFORM_ARCH=x86_64 fzf_asset
[[ $ASSET == "fzf-${FZF_VERSION}-linux_amd64.tar.gz" ]]

PLATFORM_OS=darwin PLATFORM_ARCH=arm64 zoxide_asset
[[ $ASSET == "zoxide-${ZOXIDE_VERSION}-aarch64-apple-darwin.tar.gz" ]]
PLATFORM_OS=darwin PLATFORM_ARCH=x86_64 zoxide_asset
[[ $ASSET == "zoxide-${ZOXIDE_VERSION}-x86_64-apple-darwin.tar.gz" ]]
PLATFORM_OS=linux PLATFORM_ARCH=arm64 zoxide_asset
[[ $ASSET == "zoxide-${ZOXIDE_VERSION}-aarch64-unknown-linux-musl.tar.gz" ]]
PLATFORM_OS=linux PLATFORM_ARCH=x86_64 zoxide_asset
[[ $ASSET == "zoxide-${ZOXIDE_VERSION}-x86_64-unknown-linux-musl.tar.gz" ]]

PLATFORM_OS=darwin PLATFORM_ARCH=arm64 iris_asset
[[ $ASSET == iris_darwin_arm64.tar.gz ]]
PLATFORM_OS=darwin PLATFORM_ARCH=x86_64 iris_asset
[[ $ASSET == iris_darwin_amd64.tar.gz ]]
PLATFORM_OS=linux PLATFORM_ARCH=arm64 iris_asset
[[ $ASSET == iris_linux_arm64.tar.gz ]]
PLATFORM_OS=linux PLATFORM_ARCH=x86_64 iris_asset
[[ $ASSET == iris_linux_amd64.tar.gz ]]

PLATFORM_OS=darwin PLATFORM_ARCH=arm64 glow_asset
[[ $ASSET == "glow_${GLOW_VERSION}_Darwin_arm64.tar.gz" ]]
PLATFORM_OS=darwin PLATFORM_ARCH=x86_64 glow_asset
[[ $ASSET == "glow_${GLOW_VERSION}_Darwin_x86_64.tar.gz" ]]
PLATFORM_OS=linux PLATFORM_ARCH=arm64 glow_asset
[[ $ASSET == "glow_${GLOW_VERSION}_Linux_arm64.tar.gz" ]]
PLATFORM_OS=linux PLATFORM_ARCH=x86_64 glow_asset
[[ $ASSET == "glow_${GLOW_VERSION}_Linux_x86_64.tar.gz" ]]

PLATFORM_OS=darwin PLATFORM_ARCH=arm64 yazi_asset
[[ $ASSET == yazi-aarch64-apple-darwin.zip ]]
PLATFORM_OS=darwin PLATFORM_ARCH=x86_64 yazi_asset
[[ $ASSET == yazi-x86_64-apple-darwin.zip ]]
PLATFORM_OS=linux PLATFORM_ARCH=arm64 yazi_asset
[[ $ASSET == yazi-aarch64-unknown-linux-gnu.zip ]]
PLATFORM_OS=linux PLATFORM_ARCH=x86_64 yazi_asset
[[ $ASSET == yazi-x86_64-unknown-linux-gnu.zip ]]

# PATH setup must happen before fallible installation steps and cover both
# supported interactive shells. Repeated runs must not duplicate entries.
PATH_LINE='export PATH="$HOME/.local/bin:$PATH"'
touch "$TEST_HOME/.bash_profile"
HOME=$TEST_HOME ensure_shell_path
HOME=$TEST_HOME ensure_shell_path
for startup_file in .profile .bashrc .bash_profile .zshrc; do
  [[ $(grep -Fxc "$PATH_LINE" "$TEST_HOME/$startup_file") -eq 1 ]]
done

LANG_LINE='export LANG=zh_CN.UTF-8'
LC_ALL_LINE='export LC_ALL=zh_CN.UTF-8'
HOME=$TEST_HOME ensure_shell_locale
HOME=$TEST_HOME ensure_shell_locale
for startup_file in .bashrc .zshrc; do
  [[ $(grep -Fxc "$LANG_LINE" "$TEST_HOME/$startup_file") -eq 1 ]]
  [[ $(grep -Fxc "$LC_ALL_LINE" "$TEST_HOME/$startup_file") -eq 1 ]]
done
grep -Fqx "$LANG_LINE" "$ROOT/shell/zshrc"
grep -Fqx "$LC_ALL_LINE" "$ROOT/shell/zshrc"
grep -Fqx 'export YAZI_ZOXIDE_OPTS="--no-scrollbar"' "$ROOT/shell/zshrc"
grep -Fqx 'bind-key < swap-window -d -t -1' "$TMUX_CONFIG"
grep -Fqx 'bind-key > swap-window -d -t +1' "$TMUX_CONFIG"
grep -Fqx "set -g @plugin 'tmux-plugins/tpm'" "$TMUX_CONFIG"
grep -Fqx "set -g @plugin 'tmux-plugins/tmux-resurrect'" "$TMUX_CONFIG"
grep -Fqx "set -g @plugin 'tmux-plugins/tmux-continuum'" "$TMUX_CONFIG"
grep -Fqx "run '~/.tmux/plugins/tpm/tpm'" "$TMUX_CONFIG"

path_setup_line=$(grep -n '^  ensure_shell_path$' "$BOOTSTRAP" | cut -d: -f1)
prerequisite_line=$(grep -n '^  install_prerequisites$' "$BOOTSTRAP" | cut -d: -f1)
[[ $path_setup_line -lt $prerequisite_line ]]
login_shell_line=$(grep -n '^  configure_login_shell$' "$BOOTSTRAP" | cut -d: -f1)
[[ $prerequisite_line -lt $login_shell_line ]]
locale_setup_line=$(grep -n '^  ensure_shell_locale$' "$BOOTSTRAP" | cut -d: -f1)
locale_generation_line=$(grep -n '^  configure_locale$' "$BOOTSTRAP" | cut -d: -f1)
[[ $locale_setup_line -lt $prerequisite_line ]]
[[ $prerequisite_line -lt $locale_generation_line ]]
install_links_line=$(grep -n '^  install_links$' "$BOOTSTRAP" | cut -d: -f1)
yazi_packages_line=$(grep -n '^  install_yazi_packages$' "$BOOTSTRAP" | cut -d: -f1)
[[ $install_links_line -lt $yazi_packages_line ]]
ghostty_install_line=$(grep -n '^  install_ghostty$' "$BOOTSTRAP" | cut -d: -f1)
ghostty_config_line=$(grep -n '^  install_ghostty_config$' "$BOOTSTRAP" | cut -d: -f1)
[[ $ghostty_install_line -lt $ghostty_config_line ]]

# Codex intentionally follows the latest official npm release instead of the
# versions.lock policy used by the other tools.
NPM_ARGS=
TD_VERSION=
npm() {
  NPM_ARGS="$*"
  if [[ $1 == --version ]]; then
    printf '%s\n' '11.0.0'
    return 0
  fi
  if [[ $* == *'@doist/todoist-cli@'* ]]; then
    TD_VERSION=$TODOIST_CLI_VERSION
  fi
  if [[ $1 == uninstall ]]; then
    rm -rf "$HOME/.local/lib/node_modules/druk"
    rm -f "$HOME/.local/bin/druk"
  fi
}
codex() {
  printf '%s\n' 'codex-cli 999.0.0'
}
td() {
  printf '%s\n' "${TD_VERSION:-not-installed}"
}

HOME=$TEST_HOME install_codex
[[ $NPM_ARGS == "install --global --prefix $TEST_HOME/.local @openai/codex@latest" ]]
if grep -q '^CODEX_VERSION=' "$ROOT/versions.lock"; then
  printf '%s\n' 'Codex must track latest and must not be pinned in versions.lock' >&2
  exit 1
fi

HOME=$TEST_HOME install_todoist_cli
[[ $NPM_ARGS == "install --global --prefix $TEST_HOME/.local @doist/todoist-cli@$TODOIST_CLI_VERSION" ]]
todoist_cli_is_locked_version

# termscp follows the latest official universal installer on both macOS and
# Debian/Ubuntu. The bootstrap passes --yes so containers/headless SSH hosts
# never block on the installer's confirmation prompt.
TERMSCP_CURL_ARGS_FILE="$TEST_HOME/termscp-curl-args"
curl() {
  printf '%s\n' "$*" > "$TERMSCP_CURL_ARGS_FILE"
  printf '%s\n' ':'
}
termscp() {
  printf '%s\n' 'termscp v999.0.0 - test build'
}
HOME=$TEST_HOME install_termscp
grep -Fq -- "--proto =https --tlsv1.2 -sSLf --retry 3 --connect-timeout 15 $TERMSCP_INSTALL_URL" \
  "$TERMSCP_CURL_ARGS_FILE"
grep -Fq '| sh -s -- --yes' "$BOOTSTRAP"
termscp_is_installed
unset -f curl termscp

mkdir -p \
  "$TEST_HOME/.druk/bin" \
  "$TEST_HOME/.local/lib/node_modules/druk" \
  "$TEST_HOME/.config/druk" \
  "$TEST_HOME/.cache/druk"
touch "$TEST_HOME/.druk/bin/druk" "$TEST_HOME/.local/bin/druk"
chmod +x "$TEST_HOME/.druk/bin/druk"
HOME=$TEST_HOME uninstall_druk
[[ $NPM_ARGS == "uninstall --global --prefix $TEST_HOME/.local druk" ]]
[[ ! -e "$TEST_HOME/.druk" ]]
[[ ! -e "$TEST_HOME/.local/bin/druk" ]]
[[ ! -e "$TEST_HOME/.local/lib/node_modules/druk" ]]
[[ ! -e "$TEST_HOME/.config/druk" ]]
[[ ! -e "$TEST_HOME/.cache/druk" ]]

FRESH_CURL_ARGS_FILE="$TEST_HOME/fresh-curl-args"
curl() {
  printf '%s\n' "$*" > "$FRESH_CURL_ARGS_FILE"
  printf '%s\n' ':'
}
fresh() {
  printf '%s\n' 'fresh 999.0.0'
}
HOME=$TEST_HOME install_fresh
grep -Fq -- '-fsSL --retry 3 --connect-timeout 15 https://raw.githubusercontent.com/sinelaw/fresh/refs/heads/master/scripts/install.sh' \
  "$FRESH_CURL_ARGS_FILE"
fresh_is_installed
unset -f curl fresh

for version_variable in OH_MY_ZSH_COMMIT ZSH_SYNTAX_HIGHLIGHTING_COMMIT; do
  grep -q "^${version_variable}=" "$ROOT/versions.lock"
done
plugins_block=$(sed -n '/^plugins=(/,/^)/p' "$ROOT/shell/zshrc")
if grep -Fq 'zsh-autosuggestions' <<< "$plugins_block" ||
  grep -Eq 'zsh-autosuggestions|ZSH_AUTOSUGGESTIONS' "$BOOTSTRAP" "$ROOT/versions.lock"; then
  printf '%s\n' 'zsh-autosuggestions must stay disabled and unmanaged when Iris is enabled' >&2
  exit 1
fi

grep -Fq 'backup_and_link "$DOTFILES_DIR/shell/zshrc" "$HOME/.zshrc"' "$BOOTSTRAP"
grep -Fq 'backup_and_link "$DOTFILES_DIR/vim/vimrc" "$HOME/.vimrc"' "$BOOTSTRAP"
grep -Fq 'backup_and_link "$DOTFILES_DIR/tmux/tmux.conf" "$HOME/.tmux.conf"' "$BOOTSTRAP"
grep -Eq '^[[:space:]]*set[[:space:]]+number([[:space:]]|$)' "$ROOT/vim/vimrc"
grep -Fq 'backup_and_link "$DOTFILES_DIR/bin/remote-dev-entry" "$HOME/.local/bin/remote-dev-entry"' "$BOOTSTRAP"
grep -Fq 'backup_and_link "$DOTFILES_DIR/bin/connect-remote-dev" "$HOME/.local/bin/connect-remote-dev"' "$BOOTSTRAP"
grep -Fq 'backup_and_link "$DOTFILES_DIR/bin/termscp-mac" "$HOME/.local/bin/termscp-mac"' "$BOOTSTRAP"
grep -Fq 'backup_and_link "$DOTFILES_DIR/bin/termscp-bridge-relay" "$HOME/.local/bin/termscp-bridge-relay"' "$BOOTSTRAP"
grep -Fq 'backup_and_link "$DOTFILES_DIR/bin/termscp-key-authorizer" "$HOME/.local/bin/termscp-key-authorizer"' "$BOOTSTRAP"
grep -Fq 'backup_and_link "$DOTFILES_DIR/bin/lazygit-safe" "$HOME/.local/bin/lazygit-safe"' "$BOOTSTRAP"
grep -Fq 'backup_and_link "$DOTFILES_DIR/bin/pre-commit" "$HOME/.local/bin/pre-commit"' "$BOOTSTRAP"
grep -Fq 'backup_and_link "$DOTFILES_DIR/yazi/yazi.toml" "$HOME/.config/yazi/yazi.toml"' "$BOOTSTRAP"
grep -Fq 'backup_and_link "$DOTFILES_DIR/yazi/init.lua" "$HOME/.config/yazi/init.lua"' "$BOOTSTRAP"
grep -Fq 'backup_and_link "$DOTFILES_DIR/yazi/package.toml" "$HOME/.config/yazi/package.toml"' "$BOOTSTRAP"
grep -Fq 'vim -c '\''set mouse=a autoread'\''' "$ROOT/yazi/yazi.toml"
grep -Fq 'timer_start(60000' "$ROOT/yazi/yazi.toml"
grep -Fq 'url = "*.md"' "$ROOT/yazi/yazi.toml"
grep -Fq 'piper -- CLICOLOR_FORCE=1 glow' "$ROOT/yazi/yazi.toml"
grep -Fq 'use = "yazi-rs/plugins:piper"' "$ROOT/yazi/package.toml"
grep -Fq 'rev = "bb758e2"' "$ROOT/yazi/package.toml"
grep -Fq 'update_db = true' "$ROOT/yazi/init.lua"
grep -Fq 'eval "$(iris init zsh)"' "$ROOT/shell/zshrc"
grep -Fq 'eval "$(zoxide init zsh)"' "$ROOT/shell/zshrc"
grep -Fq '  seed_zoxide_history' "$BOOTSTRAP"
grep -Fq 'install_oh_my_zsh' "$BOOTSTRAP"
grep -Fq '  install_iterm2_profile' "$BOOTSTRAP"
grep -Fq '  install_ghostty' "$BOOTSTRAP"
grep -Fq '  install_ghostty_config' "$BOOTSTRAP"
grep -Fq '  install_fzf' "$BOOTSTRAP"
grep -Fq '  install_zoxide' "$BOOTSTRAP"
grep -Fq '  install_iris' "$BOOTSTRAP"
grep -Fq '  install_glow' "$BOOTSTRAP"
grep -Fq '  install_yazi' "$BOOTSTRAP"
grep -Fq '  install_yazi_packages' "$BOOTSTRAP"
grep -Fq '  install_pre_commit' "$BOOTSTRAP"
grep -Fq '  install_termscp' "$BOOTSTRAP"
grep -Fq '  uninstall_druk' "$BOOTSTRAP"
grep -Fq '  install_fresh' "$BOOTSTRAP"
grep -Fq '  configure_git_identity' "$BOOTSTRAP"
grep -Fq '  remind_ssh_key' "$BOOTSTRAP"
grep -Fq 'function y()' "$ROOT/shell/zshrc"
grep -Fq 'command yazi "$@" --cwd-file="$tmp"' "$ROOT/shell/zshrc"
zsh -n "$ROOT/shell/zshrc"
bash -n "$ROOT/bin/remote-dev-entry"
bash -n "$ROOT/bin/connect-remote-dev"
bash -n "$TERMSCP_LAUNCHER"
python3 "$ROOT/bin/termscp-bridge-relay" --help >/dev/null
python3 "$TERMSCP_AUTHORIZER" --help >/dev/null
bash -n "$ROOT/bin/ghostty-dev"
bash -n "$ROOT/bin/ghostty-tab-command"
bash -n "$ROOT/bin/pre-commit"
sh -n "$ROOT/bin/lazygit-safe"
bash "$ROOT/tests/test-ghostty-dev.sh"
bash "$ROOT/tests/test-termscp-mac.sh"

# Git identity setup is machine-local: preserve existing values and never
# prompt or write placeholders when the bootstrap runs without a terminal.
unset -f git
TEST_GIT_CONFIG="$TEST_HOME/gitconfig"
export GIT_CONFIG_GLOBAL=$TEST_GIT_CONFIG
git config --global user.name 'Existing User'
git config --global user.email 'existing@example.com'
git_identity_output=$(HOME=$TEST_HOME configure_git_identity </dev/null)
grep -Fq 'Existing User <existing@example.com>' <<< "$git_identity_output"
[[ $(git config --global --get user.name) == 'Existing User' ]]
[[ $(git config --global --get user.email) == 'existing@example.com' ]]

rm -f "$TEST_GIT_CONFIG"
git_identity_output=$(HOME=$TEST_HOME configure_git_identity </dev/null)
grep -Fq 'git config --global user.name "Your Name"' <<< "$git_identity_output"
grep -Fq 'git config --global user.email "you@example.com"' <<< "$git_identity_output"
[[ ! -e "$TEST_GIT_CONFIG" ]]

mkdir -p "$TEST_HOME/.ssh"
touch "$TEST_HOME/.ssh/id_ed25519.pub"
ssh_key_output=$(HOME=$TEST_HOME remind_ssh_key)
grep -Fq "$TEST_HOME/.ssh/id_ed25519.pub" <<< "$ssh_key_output"
grep -Fq 'ssh -T git@github.com' <<< "$ssh_key_output"
unset GIT_CONFIG_GLOBAL
