#!/usr/bin/env bash

set -euo pipefail

# Skills are owned by Skills Manager. This wrapper keeps the dotfiles bootstrap
# contract stable while making the manager CLI the only sync/deployment path.
# The central repository is cloned once, then pulled on later runs. Set
# SKILLS_MANAGER_GIT_REMOTE only when overriding the default remote; the remote
# is persisted in the manager repository after that.

DEFAULT_SKILLS_MANAGER_GIT_REMOTE='https://github.com/Crucifixion-Fxl/skills-manager-backup.git'

log() {
  printf 'agent-skills: %s\n' "$*"
}

fail() {
  printf 'agent-skills: %s\n' "$*" >&2
  exit 1
}

resolve_cli() {
  local bundled="$HOME/.skills-manager/bin/skills-manager-cli"
  local path_cli configured_cli=${SKILLS_MANAGER_CLI:-}

  if [[ -n "$configured_cli" ]]; then
    [[ -x "$configured_cli" ]] || fail "SKILLS_MANAGER_CLI is not executable: $configured_cli"
    printf '%s\n' "$configured_cli"
    return 0
  fi

  if [[ -s "$HOME/.skills-manager/bin/.version" && -x "$bundled" ]]; then
    printf '%s\n' "$bundled"
    return 0
  fi
  if [[ -e "$bundled" || -s "$HOME/.skills-manager/bin/.version" ]]; then
    fail "Skills Manager CLI bridge is incomplete; open Skills Manager once to republish it"
  fi

  path_cli=$(command -v skills-manager-cli 2>/dev/null || true)
  [[ -n "$path_cli" && -x "$path_cli" ]] ||
    fail "skills-manager-cli is not installed; run bootstrap again or install the standalone CLI"
  printf '%s\n' "$path_cli"
}

require_json_tools() {
  command -v python3 >/dev/null 2>&1 ||
    fail "python3 is required to read Skills Manager JSON output"
}

repo_status_json() {
  "$SKILLS_MANAGER_CLI" --json git status
}

status_field() {
  local field=$1 json=$2
  python3 -c '
import json, sys
value = json.load(sys.stdin).get(sys.argv[1])
if isinstance(value, bool):
    print(str(value).lower())
else:
    print(value or "")
' "$field" <<<"$json"
}

ensure_manager_repository() {
  local status remote configured_remote
  MANAGER_REPOSITORY_WAS_CLONED=0
  status=$(repo_status_json)
  if [[ "$(status_field is_repo "$status")" != true ]]; then
    configured_remote=${SKILLS_MANAGER_GIT_REMOTE:-$DEFAULT_SKILLS_MANAGER_GIT_REMOTE}
    [[ -n "$configured_remote" ]] ||
      fail "Skills Manager has no repository; set SKILLS_MANAGER_GIT_REMOTE for the first sync"
    log "Cloning Skills Manager repository"
    "$SKILLS_MANAGER_CLI" git clone "$configured_remote"
    MANAGER_REPOSITORY_WAS_CLONED=1
    return 0
  fi

  remote=$(status_field remote_url "$status")
  if [[ -z "$remote" ]]; then
    configured_remote=${SKILLS_MANAGER_GIT_REMOTE:-$DEFAULT_SKILLS_MANAGER_GIT_REMOTE}
    [[ -n "$configured_remote" ]] ||
      fail "Skills Manager repository has no remote; set SKILLS_MANAGER_GIT_REMOTE"
    "$SKILLS_MANAGER_CLI" git set-remote "$configured_remote"
  fi
}

preset_names() {
  "$SKILLS_MANAGER_CLI" --json presets list |
    python3 -c '
import json, sys
for preset in json.load(sys.stdin):
    name = preset.get("name")
    if name:
        print(name)
'
}

deploy_presets() {
  local preset count=0
  while IFS= read -r preset; do
    [[ -n "$preset" ]] || continue
    log "Syncing preset: $preset"
    "$SKILLS_MANAGER_CLI" skills sync --preset "$preset"
    count=$((count + 1))
  done < <(preset_names)
  (( count > 0 )) || fail "Skills Manager repository contains no presets"
}

sync_skills() {
  require_json_tools
  SKILLS_MANAGER_CLI=$(resolve_cli)
  ensure_manager_repository
  if (( MANAGER_REPOSITORY_WAS_CLONED == 0 )); then
    log "Pulling Skills Manager repository"
    "$SKILLS_MANAGER_CLI" git pull
  else
    log "Using freshly cloned Skills Manager repository"
  fi
  deploy_presets
  log "Skills Manager sync completed"
}

check_skills() {
  local status skill_count agent_json
  require_json_tools
  SKILLS_MANAGER_CLI=$(resolve_cli)
  status=$(repo_status_json)
  [[ "$(status_field is_repo "$status")" == true ]] ||
    fail "Skills Manager repository is not initialized"
  skill_count=$(
    "$SKILLS_MANAGER_CLI" --json skills list |
      python3 -c 'import json, sys; print(len(json.load(sys.stdin)))'
  )
  [[ "$skill_count" =~ ^[0-9]+$ && "$skill_count" -gt 0 ]] ||
    fail "Skills Manager central library is empty"
  agent_json=$("$SKILLS_MANAGER_CLI" --json agents list)
  python3 -c 'import json, sys; agents=json.load(sys.stdin); print(sum(1 for a in agents if a.get("installed") and a.get("enabled")))' <<<"$agent_json" |
    grep -Eq '^[1-9][0-9]*$' || fail "no installed and enabled Agent is available"
  log "Skills Manager validation passed ($skill_count Skills)"
}

main() {
  case "${1:-sync}" in
    sync) sync_skills ;;
    check) check_skills ;;
    *) fail "usage: sync.sh [sync|check]" ;;
  esac
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  main "$@"
fi
