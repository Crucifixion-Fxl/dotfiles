#!/usr/bin/env bash

set -euo pipefail

ROOT=$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
TEST_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/agent-skills-manager-test.XXXXXX")
trap 'rm -rf "$TEST_ROOT"' EXIT

TEST_HOME="$TEST_ROOT/home"
FAKE_BIN="$TEST_ROOT/bin"
LOG_FILE="$TEST_ROOT/commands.log"
mkdir -p "$TEST_HOME" "$FAKE_BIN"

cat > "$FAKE_BIN/skills-manager-cli" <<'FAKE_CLI'
#!/usr/bin/env bash
set -euo pipefail

log_file=${FAKE_CLI_LOG:?}
printf '%s\n' "$*" >> "$log_file"

json=0
if [[ ${1:-} == --json ]]; then
  json=1
  shift
fi

case "${1:-}" in
  git)
    if [[ ${2:-} == status ]]; then
      if [[ -f ${FAKE_CLI_REPO_READY:?} ]]; then
        printf '%s\n' '{"is_repo":true,"remote_url":"https://example.invalid/skills.git"}'
      else
        printf '%s\n' '{"is_repo":false,"remote_url":null}'
      fi
    fi
    case "${2:-}" in
      clone)
        : > "$FAKE_CLI_REPO_READY"
        ;;
      pull|set-remote)
        : > "$FAKE_CLI_REPO_READY"
        ;;
    esac
    ;;
  repo)
    if [[ ${2:-} == status ]]; then
      printf '%s\n' '{"base_dir":"/tmp/skills-manager"}'
    fi
    ;;
  presets)
    case "${2:-}" in
      list)
        printf '%s\n' '[{"name":"Web Dev"},{"name":"Ops"}]'
        ;;
      deploy)
        ;;
    esac
    ;;
  skills)
    case "${2:-}" in
      sync)
        ;;
      list)
        printf '%s\n' '[{"name":"code-review"}]'
        ;;
    esac
    ;;
  agents)
    printf '%s\n' '[{"installed":true,"enabled":true}]'
    ;;
  *)
    printf 'unexpected fake CLI invocation: %s\n' "$*" >&2
    exit 1
    ;;
esac
FAKE_CLI
chmod +x "$FAKE_BIN/skills-manager-cli"

export HOME="$TEST_HOME"
export PATH="$FAKE_BIN:$PATH"
export FAKE_CLI_LOG="$LOG_FILE"
export FAKE_CLI_REPO_READY="$TEST_ROOT/repo-ready"
export SKILLS_MANAGER_GIT_REMOTE='https://example.invalid/skills.git'

bash "$ROOT/sync.sh" sync
grep -Fqx 'git clone https://example.invalid/skills.git' "$LOG_FILE"
grep -Fqx 'skills sync --preset Web Dev' "$LOG_FILE"
grep -Fqx 'skills sync --preset Ops' "$LOG_FILE"

bash "$ROOT/sync.sh" sync
grep -Fqx 'git pull' "$LOG_FILE"

bash "$ROOT/sync.sh" check

unset SKILLS_MANAGER_GIT_REMOTE
rm -f "$FAKE_CLI_REPO_READY"
bash "$ROOT/sync.sh" sync
grep -Fqx 'git clone https://github.com/Crucifixion-Fxl/skills-manager-backup.git' "$LOG_FILE"

printf '%s\n' 'skills-manager sync tests passed'
