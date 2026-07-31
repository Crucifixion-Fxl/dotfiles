#!/usr/bin/env bash

set -euo pipefail

ROOT=$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
BRIDGE="$ROOT/bin/todo-bridge"
BACKEND="$ROOT/tests/fixtures/todo-fake-backend"
WORK=$(mktemp -d "${TMPDIR:-/tmp}/todo-bridge-test.XXXXXX")
READY="$WORK/ready"
LOG="$WORK/bridge.log"
TOKEN=test-todo-token
bridge_pid=

cleanup() {
  if [[ -n "$bridge_pid" ]]; then
    kill "$bridge_pid" 2>/dev/null || true
    wait "$bridge_pid" 2>/dev/null || true
  fi
  rm -rf "$WORK"
}
trap cleanup EXIT

python3 "$BRIDGE" serve \
  --listen-host 127.0.0.1 \
  --listen-port 0 \
  --token "$TOKEN" \
  --backend "$BACKEND" \
  --parent-pid "$$" \
  --ready-file "$READY" >"$LOG" 2>&1 &
bridge_pid=$!

for _ in $(seq 1 100); do
  [[ -s "$READY" ]] && break
  kill -0 "$bridge_pid" 2>/dev/null || break
  sleep 0.02
done
[[ -s "$READY" ]] || {
  cat "$LOG" >&2
  exit 1
}
read -r status port < "$READY"
[[ "$status" == READY ]]

python3 - "$port" "$TOKEN" <<'PY'
import json
import sys
import urllib.error
import urllib.request

port, token = sys.argv[1:]
url = f"http://127.0.0.1:{port}/api"

unauthorized = urllib.request.Request(
    url,
    data=b'{"action":"snapshot"}',
    headers={"Content-Type": "application/json"},
    method="POST",
)
try:
    urllib.request.urlopen(unauthorized)
except urllib.error.HTTPError as error:
    assert error.code == 401
else:
    raise AssertionError("request without token must be rejected")

authorized = urllib.request.Request(
    url,
    data=b'{"action":"snapshot"}',
    headers={
        "Authorization": f"Bearer {token}",
        "Content-Type": "application/json",
    },
    method="POST",
)
with urllib.request.urlopen(authorized) as response:
    payload = json.load(response)
assert payload["ok"] is True
assert payload["received_action"] == "snapshot"
assert payload["lists"] == [{"id": "work", "name": "工作"}]
PY

printf '%s\n' 'todo bridge tests passed'
