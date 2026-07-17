#!/usr/bin/env bash

set -euo pipefail

ROOT=$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
BOOTSTRAP="$ROOT/bootstrap.sh"
ITERM_PROFILE="$ROOT/iterm2/dev.json"

bash -n "$BOOTSTRAP"
grep -q 'ncurses-base' "$BOOTSTRAP"
grep -q 'fonts-noto-cjk' "$BOOTSTRAP"
grep -q 'locales' "$BOOTSTRAP"
grep -q 'fd-find' "$BOOTSTRAP"
grep -q 'ffmpeg' "$BOOTSTRAP"
grep -q 'poppler-utils' "$BOOTSTRAP"
grep -q 'resvg' "$BOOTSTRAP"
grep -q 'unzip' "$BOOTSTRAP"
grep -q 'font-maple-mono-nf-cn' "$BOOTSTRAP"
grep -q '^ensure_tmux_terminfo()' "$BOOTSTRAP"
grep -q '^configure_locale()' "$BOOTSTRAP"
grep -q '^ensure_linux_fd_command()' "$BOOTSTRAP"
grep -q '^install_fzf()' "$BOOTSTRAP"
grep -q '^install_zoxide()' "$BOOTSTRAP"
grep -q '^install_yazi()' "$BOOTSTRAP"
[[ $(grep -Fc '  hash -r' "$BOOTSTRAP") -ge 2 ]]
[[ $(grep -Fc 'run_as_root env DEBIAN_FRONTEND=noninteractive apt-get install -y' "$BOOTSTRAP") -eq 2 ]]

prerequisite_function=$(sed -n '/^install_prerequisites()/,/^}/p' "$BOOTSTRAP")
if grep -Eq '(^|[[:space:]])(fzf|zoxide)($|[[:space:]])' <<< "$prerequisite_function"; then
  printf '%s\n' 'fzf and zoxide must come from pinned official releases, not apt or Homebrew' >&2
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

# Exercise install_plugin under set -u. Bash expands a whole `local` command
# before applying its assignments, so dependent values must be assigned on a
# later line.
TEST_HOME=$(mktemp -d)
trap 'rm -rf "$TEST_HOME"' EXIT
TEST_PLUGIN_COMMIT=0123456789abcdef

# shellcheck source=../bootstrap.sh
source "$BOOTSTRAP"

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
  PLATFORM_OS=darwin HOME=$TEST_HOME install_iterm2_profile
  ITERM_DESTINATION="$TEST_HOME/Library/Application Support/iTerm2/DynamicProfiles/dev.json"
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

# Yazi is pinned and installed from official Release ZIP assets on macOS and
# Debian/Ubuntu. The yazi and ya versions must always match.
fzf() {
  printf '%s (test)\n' "$FZF_VERSION"
}
zoxide() {
  printf 'zoxide %s\n' "$ZOXIDE_VERSION"
}
fzf_is_locked_version
zoxide_is_locked_version
unset -f fzf zoxide

yazi() {
  printf 'Yazi %s (test)\n' "$YAZI_VERSION"
}
ya() {
  printf 'Ya %s (test)\n' "$YAZI_VERSION"
}
yazi_is_locked_version

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
  YAZI_VERSION \
  YAZI_SHA256_DARWIN_ARM64 \
  YAZI_SHA256_DARWIN_X86_64 \
  YAZI_SHA256_LINUX_ARM64 \
  YAZI_SHA256_LINUX_X86_64; do
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

path_setup_line=$(grep -n '^  ensure_shell_path$' "$BOOTSTRAP" | cut -d: -f1)
prerequisite_line=$(grep -n '^  install_prerequisites$' "$BOOTSTRAP" | cut -d: -f1)
[[ $path_setup_line -lt $prerequisite_line ]]
locale_setup_line=$(grep -n '^  ensure_shell_locale$' "$BOOTSTRAP" | cut -d: -f1)
locale_generation_line=$(grep -n '^  configure_locale$' "$BOOTSTRAP" | cut -d: -f1)
[[ $locale_setup_line -lt $prerequisite_line ]]
[[ $prerequisite_line -lt $locale_generation_line ]]

# Codex intentionally follows the latest official npm release instead of the
# versions.lock policy used by the other tools.
NPM_ARGS=
npm() {
  NPM_ARGS="$*"
}
codex() {
  printf '%s\n' 'codex-cli 999.0.0'
}

HOME=$TEST_HOME install_codex
[[ $NPM_ARGS == "install --global --prefix $TEST_HOME/.local @openai/codex@latest" ]]
if grep -q '^CODEX_VERSION=' "$ROOT/versions.lock"; then
  printf '%s\n' 'Codex must track latest and must not be pinned in versions.lock' >&2
  exit 1
fi

for version_variable in OH_MY_ZSH_COMMIT ZSH_AUTOSUGGESTIONS_COMMIT ZSH_SYNTAX_HIGHLIGHTING_COMMIT; do
  grep -q "^${version_variable}=" "$ROOT/versions.lock"
done

grep -Fq 'backup_and_link "$DOTFILES_DIR/shell/zshrc" "$HOME/.zshrc"' "$BOOTSTRAP"
grep -Fq 'backup_and_link "$DOTFILES_DIR/bin/remote-dev-entry" "$HOME/.local/bin/remote-dev-entry"' "$BOOTSTRAP"
grep -Fq 'backup_and_link "$DOTFILES_DIR/bin/connect-remote-dev" "$HOME/.local/bin/connect-remote-dev"' "$BOOTSTRAP"
grep -Fq 'backup_and_link "$DOTFILES_DIR/bin/lazygit-safe" "$HOME/.local/bin/lazygit-safe"' "$BOOTSTRAP"
grep -Fq 'backup_and_link "$DOTFILES_DIR/yazi/init.lua" "$HOME/.config/yazi/init.lua"' "$BOOTSTRAP"
grep -Fq 'update_db = true' "$ROOT/yazi/init.lua"
grep -Fq 'eval "$(zoxide init zsh)"' "$ROOT/shell/zshrc"
grep -Fq '  seed_zoxide_history' "$BOOTSTRAP"
grep -Fq 'install_oh_my_zsh' "$BOOTSTRAP"
grep -Fq '  install_iterm2_profile' "$BOOTSTRAP"
grep -Fq '  install_fzf' "$BOOTSTRAP"
grep -Fq '  install_zoxide' "$BOOTSTRAP"
grep -Fq '  install_yazi' "$BOOTSTRAP"
grep -Fq 'function y()' "$ROOT/shell/zshrc"
grep -Fq 'command yazi "$@" --cwd-file="$tmp"' "$ROOT/shell/zshrc"
zsh -n "$ROOT/shell/zshrc"
bash -n "$ROOT/bin/remote-dev-entry"
bash -n "$ROOT/bin/connect-remote-dev"
sh -n "$ROOT/bin/lazygit-safe"
