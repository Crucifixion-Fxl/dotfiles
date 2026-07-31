#!/usr/bin/env bash

set -euo pipefail

ROOT=$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
AUTHORIZER="$ROOT/bin/termscp-key-authorizer"
TEST_DIRECTORY=$(mktemp -d)
server_pid=

cleanup() {
  [[ -z "$server_pid" ]] || kill "$server_pid" 2>/dev/null || true
  rm -rf "$TEST_DIRECTORY"
}
trap cleanup EXIT

file_mode() {
  stat -f '%Lp' "$1" 2>/dev/null || stat -c '%a' "$1"
}

ssh_key="$TEST_DIRECTORY/id_ed25519"
authorized_keys="$TEST_DIRECTORY/.ssh/authorized_keys"
ready_file="$TEST_DIRECTORY/authorizer.ready"
server_log="$TEST_DIRECTORY/authorizer.log"
token=test-token-0123456789

ssh-keygen -q -t ed25519 -N '' -f "$ssh_key"
public_key=$(<"$ssh_key.pub")

python3 "$AUTHORIZER" serve \
  --listen-host 127.0.0.1 \
  --listen-port 0 \
  --token "$token" \
  --parent-pid $$ \
  --ready-file "$ready_file" \
  --authorized-keys "$authorized_keys" \
  --forced-command /usr/libexec/sftp-server >"$server_log" 2>&1 &
server_pid=$!

for _ in {1..100}; do
  [[ -s "$ready_file" ]] && break
  kill -0 "$server_pid" 2>/dev/null || break
  sleep 0.02
done
[[ -s "$ready_file" ]] || {
  cat "$server_log" >&2
  exit 1
}
read -r status server_port < "$ready_file"
[[ $status == READY ]]

if python3 "$AUTHORIZER" request \
  --host 127.0.0.1 \
  --port "$server_port" \
  --token wrong-token \
  --public-key "$public_key" \
  --label test-container >/dev/null 2>&1; then
  printf '%s\n' 'authorizer must reject an invalid token' >&2
  exit 1
fi
[[ ! -e "$authorized_keys" ]]

response=$(python3 "$AUTHORIZER" request \
  --host 127.0.0.1 \
  --port "$server_port" \
  --token "$token" \
  --public-key "$public_key" \
  --label test-container)
grep -Eq '^AUTHORIZED SHA256:.* added$' <<< "$response"
[[ $(file_mode "$TEST_DIRECTORY/.ssh") == 700 ]]
[[ $(file_mode "$authorized_keys") == 600 ]]
grep -Eq '^from="127\.0\.0\.1,::1",restrict,command="/usr/libexec/sftp-server" ssh-ed25519 [A-Za-z0-9+/=]+ termscp-test-container$' \
  "$authorized_keys"

response=$(python3 "$AUTHORIZER" request \
  --host 127.0.0.1 \
  --port "$server_port" \
  --token "$token" \
  --public-key "$public_key" \
  --label test-container)
grep -Eq '^AUTHORIZED SHA256:.* existing$' <<< "$response"
[[ $(wc -l < "$authorized_keys" | tr -d ' ') == 1 ]]

printf '%s\n' "$public_key unrestricted-test" > "$authorized_keys"
if python3 "$AUTHORIZER" request \
  --host 127.0.0.1 \
  --port "$server_port" \
  --token "$token" \
  --public-key "$public_key" \
  --label test-container >/dev/null 2>&1; then
  printf '%s\n' 'authorizer must not silently accept an unrestricted existing key' >&2
  exit 1
fi
grep -Fq 'unrestricted-test' "$authorized_keys"
