#!/usr/bin/env bash

set -euo pipefail

ROOT=$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
BOOTSTRAP="$ROOT/bootstrap.sh"

bash -n "$BOOTSTRAP"
grep -q 'ncurses-base' "$BOOTSTRAP"
grep -q '^ensure_tmux_terminfo()' "$BOOTSTRAP"
[[ $(grep -Fc 'run_as_root env DEBIAN_FRONTEND=noninteractive apt-get install -y' "$BOOTSTRAP") -eq 2 ]]

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

# PATH setup must happen before fallible installation steps and cover both
# supported interactive shells. Repeated runs must not duplicate entries.
PATH_LINE='export PATH="$HOME/.local/bin:$PATH"'
touch "$TEST_HOME/.bash_profile"
HOME=$TEST_HOME ensure_shell_path
HOME=$TEST_HOME ensure_shell_path
for startup_file in .profile .bashrc .bash_profile .zshrc; do
  [[ $(grep -Fxc "$PATH_LINE" "$TEST_HOME/$startup_file") -eq 1 ]]
done

path_setup_line=$(grep -n '^  ensure_shell_path$' "$BOOTSTRAP" | cut -d: -f1)
prerequisite_line=$(grep -n '^  install_prerequisites$' "$BOOTSTRAP" | cut -d: -f1)
[[ $path_setup_line -lt $prerequisite_line ]]

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
grep -Fq 'install_oh_my_zsh' "$BOOTSTRAP"
zsh -n "$ROOT/shell/zshrc"
