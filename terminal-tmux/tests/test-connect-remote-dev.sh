#!/usr/bin/env bash
set -euo pipefail
ROOT=$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
CONNECTOR="$ROOT/bin/connect-remote-dev"
ENTRY="$ROOT/bin/remote-dev-entry"
source "$CONNECTOR"
run_ssh() {
  [[ $# -eq 2 ]]
  printf 'host=%s\n' "$1"
  printf '%s\n' "$2"
}
output=$(main dev-4090)
grep -Fq 'host=dev-4090' <<< "$output"
grep -Fq 'mv -f "$temporary" "$directory/remote-dev-entry"' <<< "$output"
grep -Fq 'exec "$directory/remote-dev-entry"' <<< "$output"
payload=$(sed -n "s/^payload='\(.*\)'$/\1/p" <<< "$output")
[[ -n "$payload" ]]
printf '%s' "$payload" | base64 -d | cmp - "$ENTRY"
for invalid in '' '-oProxyCommand=unexpected'; do
  if (main "$invalid") >/dev/null 2>&1; then
    printf '%s\n' 'connector accepted an invalid host' >&2
    exit 1
  fi
done
if (main) >/dev/null 2>&1 || (main one two) >/dev/null 2>&1; then
  printf '%s\n' 'connector must require exactly one SSH host' >&2
  exit 1
fi
# Inspect the actual ssh argv. No reverse forwarding or helper daemon remains.
ssh_args=$(
  source "$CONNECTOR"
  exec() { printf '%s\n' "$@"; }
  run_ssh dev-4090 'remote command'
)
[[ $ssh_args == $'ssh\n-t\n--\ndev-4090\nremote command' ]]
if grep -Eiq 'termscp|sftp|authorized_keys|TODO_BRIDGE' "$CONNECTOR" "$ENTRY"; then
  printf '%s\n' 'remote entrypoints must not depend on retired file transfer' >&2
  exit 1
fi
printf '%s\n' 'SSH connector tests passed'
