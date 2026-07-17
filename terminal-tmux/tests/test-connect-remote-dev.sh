#!/usr/bin/env bash

set -euo pipefail

ROOT=$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
CONNECTOR="$ROOT/bin/connect-remote-dev"
ENTRY="$ROOT/bin/remote-dev-entry"

# shellcheck source=../bin/connect-remote-dev
source "$CONNECTOR"

run_ssh() {
  printf 'host=%s\n' "$1"
  printf '%s\n' "$2"
}

output=$(TERM_PROGRAM=iTerm.app main dev-4090)
grep -Fq 'host=dev-4090' <<< "$output"
grep -Fq 'directory="$HOME/.local/bin"' <<< "$output"
grep -Fq 'mv -f "$temporary" "$directory/remote-dev-entry"' <<< "$output"
grep -Fq 'TERM_PROGRAM=$(printf "%s" "$term_program_payload" | base64 -d)' <<< "$output"
grep -Fq 'export PATH TERM_PROGRAM' <<< "$output"
grep -Fq 'exec "$directory/remote-dev-entry"' <<< "$output"

payload=$(sed -n "s/^payload='\\(.*\\)'$/\\1/p" <<< "$output")
[[ -n "$payload" ]]
printf '%s' "$payload" | base64 -d | cmp - "$ENTRY"

term_program_payload=$(sed -n "s/^term_program_payload='\(.*\)'$/\1/p" <<< "$output")
[[ -n "$term_program_payload" ]]
[[ $(printf '%s' "$term_program_payload" | base64 -d) == iTerm.app ]]

if (main) >/dev/null 2>&1; then
  printf '%s\n' 'connector must require exactly one SSH host' >&2
  exit 1
fi
