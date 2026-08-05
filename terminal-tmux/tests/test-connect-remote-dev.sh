#!/usr/bin/env bash

set -euo pipefail

ROOT=$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
CONNECTOR="$ROOT/bin/connect-remote-dev"
ENTRY="$ROOT/bin/remote-dev-entry"
RELAY="$ROOT/bin/termscp-bridge-relay"
AUTHORIZER="$ROOT/bin/termscp-key-authorizer"

# shellcheck source=../bin/connect-remote-dev
source "$CONNECTOR"

run_ssh() {
  printf 'host=%s\n' "$1"
  printf '%s\n' "$2"
  printf 'reverse_port=%s\n' "$3"
  printf 'mac_ssh_port=%s\n' "$4"
  printf 'authorization_reverse_port=%s\n' "$5"
  printf 'authorization_local_port=%s\n' "$6"
}

start_local_key_authorizer() {
  authorizer_token=test-token
  authorizer_local_port=49152
}

output=$(TERMSCP_MAC_USER=mac-user TERMSCP_REVERSE_PORT=16022 \
  TERMSCP_MAC_SSH_PORT=2222 TERMSCP_AUTH_REVERSE_PORT=16023 main dev-4090)
grep -Fq 'host=dev-4090' <<< "$output"
grep -Fq 'reverse_port=16022' <<< "$output"
grep -Fq 'mac_ssh_port=2222' <<< "$output"
grep -Fq 'authorization_reverse_port=16023' <<< "$output"
grep -Fq 'authorization_local_port=49152' <<< "$output"
grep -Fq 'directory="$HOME/.local/bin"' <<< "$output"
grep -Fq 'mv -f "$temporary" "$directory/remote-dev-entry"' <<< "$output"
grep -Fq 'mv -f "$relay_temporary" "$directory/termscp-bridge-relay"' <<< "$output"
grep -Fq 'mv -f "$authorizer_temporary" "$directory/termscp-key-authorizer"' <<< "$output"
grep -Fq 'TERMSCP_MAC_USER=mac-user' <<< "$output"
grep -Fq 'TERMSCP_REVERSE_PORT=16022' <<< "$output"
grep -Fq 'TERMSCP_MAC_HOST=127.0.0.1' <<< "$output"
grep -Fq 'TERMSCP_AUTH_TOKEN=test-token' <<< "$output"
grep -Fq 'TERMSCP_AUTH_REVERSE_PORT=16023' <<< "$output"
grep -Fq 'TERMSCP_REMOTE_HOST=dev-4090' <<< "$output"
grep -Fq 'exec "$directory/remote-dev-entry"' <<< "$output"

payload=$(sed -n "s/^payload='\\(.*\\)'$/\\1/p" <<< "$output")
[[ -n "$payload" ]]
printf '%s' "$payload" | base64 -d | cmp - "$ENTRY"

relay_payload=$(sed -n "s/^relay_payload='\\(.*\\)'$/\\1/p" <<< "$output")
[[ -n "$relay_payload" ]]
printf '%s' "$relay_payload" | base64 -d | cmp - "$RELAY"

authorizer_payload=$(sed -n "s/^authorizer_payload='\\(.*\\)'$/\\1/p" <<< "$output")
[[ -n "$authorizer_payload" ]]
printf '%s' "$authorizer_payload" | base64 -d | cmp - "$AUTHORIZER"

if (main) >/dev/null 2>&1; then
  printf '%s\n' 'connector must require exactly one SSH host' >&2
  exit 1
fi

if (TERMSCP_REVERSE_PORT=70000 main dev-4090) >/dev/null 2>&1; then
  printf '%s\n' 'connector must reject invalid reverse ports' >&2
  exit 1
fi

grep -Fq -- '-o ExitOnForwardFailure=yes' "$CONNECTOR"
grep -Fq -- '-R "$reverse_forward"' "$CONNECTOR"
grep -Fq -- '-R "$authorization_forward"' "$CONNECTOR"
if grep -Fq 'TODO_BRIDGE' "$CONNECTOR"; then
  printf '%s\n' 'connector must not depend on a Mac Todo bridge' >&2
  exit 1
fi
