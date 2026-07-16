#!/usr/bin/env sh

set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
ENTRY="$ROOT/bin/lazygit-safe"
TEST_HOME=$(mktemp -d)
trap 'rm -rf "$TEST_HOME"' 0 HUP INT TERM

mkdir -p "$TEST_HOME/repository/.git" "$TEST_HOME/repository/nested/path"

# shellcheck source=../bin/lazygit-safe
. "$ENTRY"

launch_lazygit() {
  printf 'launched:%s\n' "$*"
}

repository_root=$(CDPATH= cd -- "$TEST_HOME/repository" && pwd -P)
output=$(
  cd "$TEST_HOME/repository/nested/path"
  HOME=$TEST_HOME main --use-config-file=test.yml
  HOME=$TEST_HOME main --use-config-file=test.yml
)

[ "$(printf '%s\n' "$output" | grep -Fc 'launched:--use-config-file=test.yml')" -eq 2 ]
[ "$(HOME=$TEST_HOME git config --global --get-all safe.directory | grep -Fxc "$repository_root")" -eq 1 ]

mkdir -p "$TEST_HOME/not-a-repository"
(
  cd "$TEST_HOME/not-a-repository"
  HOME=$TEST_HOME main >/dev/null
)
[ "$(HOME=$TEST_HOME git config --global --get-all safe.directory | wc -l | tr -d ' ')" -eq 1 ]
