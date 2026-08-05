#!/usr/bin/env bash

set -euo pipefail

ROOT=$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
TEST_HOME=$(mktemp -d)
trap 'rm -rf "$TEST_HOME"' EXIT

# shellcheck source=../bootstrap.sh
source "$ROOT/bootstrap.sh"

write_fake_iris() {
  local destination=$1 version=$2
  mkdir -p "$(dirname "$destination")"
  printf '%s\n' \
    '#!/bin/sh' \
    'case "${1:-}" in' \
    "  version) printf \"%s\\\\n\" \"iris $version\" ;;" \
    '  setup) exit 99 ;;' \
    'esac' \
    > "$destination"
  chmod +x "$destination"
}

make_iris_archive() {
  local destination=$1 version=$2 work
  work=$(mktemp -d)
  write_fake_iris "$work/iris" "$version"
  tar -czf "$destination" -C "$work" iris
  rm -rf "$work"
}

download() {
  make_iris_archive "$2" "${IRIS_TEST_VERSION:-0.4.22}"
}

# An older usable Iris is upgraded to the stable candidate without invoking
# the candidate's deliberately failing `setup` subcommand.
existing_home="$TEST_HOME/existing"
write_fake_iris "$existing_home/bin/iris" 0.4.21
PLATFORM_OS=darwin PLATFORM_ARCH=arm64 \
  PATH="$existing_home/.local/bin:$existing_home/bin:/usr/bin:/bin" \
  HOME=$existing_home install_iris >/dev/null
PATH="$existing_home/.local/bin:$existing_home/bin:/usr/bin:/bin" \
  iris version | grep -Fqx 'iris 0.4.22'

# A newer local version is never downgraded to the latest stable candidate.
newer_home="$TEST_HOME/newer"
write_fake_iris "$newer_home/bin/iris" 0.5.0
IRIS_TEST_VERSION=0.4.22 PLATFORM_OS=darwin PLATFORM_ARCH=arm64 \
  PATH="$newer_home/.local/bin:$newer_home/bin:/usr/bin:/bin" \
  HOME=$newer_home install_iris >/dev/null
[[ ! -e "$newer_home/.local/bin/iris" ]]

# A temporary download failure keeps an existing usable binary.
download() {
  return 1
}
failure_home="$TEST_HOME/failure"
write_fake_iris "$failure_home/bin/iris" 0.4.21
warning=$(PLATFORM_OS=darwin PLATFORM_ARCH=arm64 \
  PATH="$failure_home/.local/bin:$failure_home/bin:/usr/bin:/bin" \
  HOME=$failure_home install_iris 2>&1)
grep -Fq 'Iris stable update check failed; keeping the usable installed version: 0.4.21' \
  <<< "$warning"
PATH="$failure_home/.local/bin:$failure_home/bin:/usr/bin:/bin" \
  iris version | grep -Fqx 'iris 0.4.21'

# Without any usable Iris, the same download failure is fatal.
missing_failure_home="$TEST_HOME/missing-failure"
mkdir -p "$missing_failure_home/.local/bin"
if (PLATFORM_OS=darwin PLATFORM_ARCH=arm64 \
  PATH="$missing_failure_home/.local/bin:/usr/bin:/bin" \
  HOME=$missing_failure_home install_iris) >/dev/null 2>&1; then
  printf '%s\n' 'a first-time Iris installation failure must stop bootstrap' >&2
  exit 1
fi

# A missing Iris is installed from the latest stable asset without invoking
# `iris setup`, so the repository-managed zshrc remains the sole integration.
download() {
  make_iris_archive "$2" 9.9.9
}
missing_home="$TEST_HOME/missing"
mkdir -p "$missing_home/.local/bin"
PLATFORM_OS=darwin PLATFORM_ARCH=arm64 \
  PATH="$missing_home/.local/bin:/usr/bin:/bin" HOME=$missing_home install_iris >/dev/null
PATH="$missing_home/.local/bin:/usr/bin:/bin" iris version | grep -Fqx 'iris 9.9.9'

if grep -Eq '^[[:space:]]*iris (update|setup)([[:space:]]|$)' "$ROOT/bootstrap.sh"; then
  printf '%s\n' 'bootstrap must not delegate to Iris commands that can select nightly or rewrite zshrc' >&2
  exit 1
fi
