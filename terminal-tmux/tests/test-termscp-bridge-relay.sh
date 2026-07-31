#!/usr/bin/env bash

set -euo pipefail

ROOT=$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
RELAY="$ROOT/bin/termscp-bridge-relay"
TEST_DIRECTORY=$(mktemp -d)
target_pid=
relay_pid=

cleanup() {
  [[ -z "$relay_pid" ]] || kill "$relay_pid" 2>/dev/null || true
  [[ -z "$target_pid" ]] || kill "$target_pid" 2>/dev/null || true
  rm -rf "$TEST_DIRECTORY"
}
trap cleanup EXIT

target_ready="$TEST_DIRECTORY/target.ready"
relay_ready="$TEST_DIRECTORY/relay.ready"

python3 - "$target_ready" <<'PY' &
import socket
import sys

ready_file = sys.argv[1]
with socket.socket() as listener:
    listener.bind(("127.0.0.1", 0))
    listener.listen(1)
    with open(ready_file, "w", encoding="utf-8") as stream:
        stream.write(str(listener.getsockname()[1]))
    connection, _ = listener.accept()
    with connection:
        data = connection.recv(1024)
        connection.sendall(b"relay:" + data)
PY
target_pid=$!

for _ in {1..50}; do
  [[ -s "$target_ready" ]] && break
  sleep 0.02
done
[[ -s "$target_ready" ]]
target_port=$(<"$target_ready")

python3 "$RELAY" \
  --listen-host 127.0.0.1 \
  --listen-port 0 \
  --target-host 127.0.0.1 \
  --target-port "$target_port" \
  --parent-pid $$ \
  --ready-file "$relay_ready" &
relay_pid=$!

for _ in {1..50}; do
  [[ -s "$relay_ready" ]] && break
  kill -0 "$relay_pid" 2>/dev/null || break
  sleep 0.02
done
[[ -s "$relay_ready" ]]
read -r status relay_port < "$relay_ready"
[[ $status == READY ]]

response=$(python3 - "$relay_port" <<'PY'
import socket
import sys

with socket.create_connection(("127.0.0.1", int(sys.argv[1]))) as connection:
    connection.sendall(b"ok")
    connection.shutdown(socket.SHUT_WR)
    print(connection.recv(1024).decode("utf-8"))
PY
)
[[ $response == relay:ok ]]
