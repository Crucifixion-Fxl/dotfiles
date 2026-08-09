#!/usr/bin/env bash

set -euo pipefail

ROOT=$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
TEST_HOME=$(mktemp -d)
trap 'rm -rf "$TEST_HOME"' EXIT

# shellcheck source=../bootstrap.sh
source "$ROOT/bootstrap.sh"

# Migration removes only the Iris binary previously managed by dotfiles.
mkdir -p "$TEST_HOME/.local/bin"
printf '%s\n' '#!/bin/sh' 'exit 0' > "$TEST_HOME/.local/bin/iris"
chmod +x "$TEST_HOME/.local/bin/iris"
HOME=$TEST_HOME remove_legacy_iris
[[ ! -e "$TEST_HOME/.local/bin/iris" ]]

# Use a minimal Oh My Zsh loader to exercise the managed plugins array in a
# fresh login zsh without downloading anything during the test.
mkdir -p "$TEST_HOME/.oh-my-zsh/custom/plugins/zsh-autosuggestions"
cat > "$TEST_HOME/.oh-my-zsh/custom/plugins/zsh-autosuggestions/zsh-autosuggestions.plugin.zsh" <<'ZSH'
export ZSH_AUTOSUGGESTIONS_TEST_LOADED=1
ZSH
cat > "$TEST_HOME/.oh-my-zsh/oh-my-zsh.sh" <<'ZSH'
if (( ${plugins[(Ie)zsh-autosuggestions]} )); then
  source "$ZSH/custom/plugins/zsh-autosuggestions/zsh-autosuggestions.plugin.zsh"
fi
ZSH

# The managed zsh entrypoint must be linked before later network installs can
# fail, and a new login shell must load autosuggestions without invoking Iris.
HOME=$TEST_HOME ensure_shell_path
HOME=$TEST_HOME ensure_shell_locale
HOME=$TEST_HOME install_shell_links

[[ -L "$TEST_HOME/.zshrc" ]]
[[ $(readlink "$TEST_HOME/.zshrc") == "$ROOT/shell/zshrc" ]]
env HOME="$TEST_HOME" ZDOTDIR="$TEST_HOME" PATH=/usr/bin:/bin \
  "$(command -v zsh)" -lic '[[ ${ZSH_AUTOSUGGESTIONS_TEST_LOADED:-} == 1 ]]'

printf '%s\n' 'zsh-autosuggestions fresh-shell test passed'
