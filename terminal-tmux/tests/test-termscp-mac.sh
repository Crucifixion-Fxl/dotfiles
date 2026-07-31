#!/usr/bin/env bash

set -euo pipefail

ROOT=$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
LAUNCHER="$ROOT/bin/termscp-mac"
TEST_HOME=$(mktemp -d)
trap 'rm -rf "$TEST_HOME"' EXIT
mkdir -p "$TEST_HOME/bin" "$TEST_HOME/server-workdir"

cat > "$TEST_HOME/bin/termscp" <<'SH'
#!/usr/bin/env sh
printf '%s\n' "$@"
SH
chmod +x "$TEST_HOME/bin/termscp"

output=$(PATH="$TEST_HOME/bin:$PATH" \
  TERMSCP_MAC_USER=mac-user TERMSCP_REVERSE_PORT=16022 \
  TERMSCP_MAC_HOST=172.17.0.1 \
  "$LAUNCHER" "$TEST_HOME/server-workdir")
grep -Fqx 'sftp://mac-user@172.17.0.1:16022' <<< "$output"
grep -Fqx "$TEST_HOME/server-workdir" <<< "$output"

cat > "$TEST_HOME/bin/tmux" <<'SH'
#!/usr/bin/env sh
case "$3" in
  TERMSCP_MAC_USER) printf '%s\n' 'TERMSCP_MAC_USER=tmux-user' ;;
  TERMSCP_REVERSE_PORT) printf '%s\n' 'TERMSCP_REVERSE_PORT=26022' ;;
  TERMSCP_MAC_HOST) printf '%s\n' 'TERMSCP_MAC_HOST=192.168.0.1' ;;
esac
SH
chmod +x "$TEST_HOME/bin/tmux"

output=$(cd "$TEST_HOME/server-workdir" && PATH="$TEST_HOME/bin:$PATH" "$LAUNCHER")
grep -Fqx 'sftp://tmux-user@192.168.0.1:26022' <<< "$output"
grep -Fqx "$TEST_HOME/server-workdir" <<< "$output"

if PATH="$TEST_HOME/bin:$PATH" TERMSCP_MAC_USER='bad user' "$LAUNCHER" >/dev/null 2>&1; then
  printf '%s\n' 'termscp-mac must reject invalid Mac usernames' >&2
  exit 1
fi

bash -n "$LAUNCHER"
