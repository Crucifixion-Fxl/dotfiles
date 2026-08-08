#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=../../lib.sh
source "$SCRIPT_DIR/../../lib.sh"
installer_parse_args "$@"

if [[ "$INSTALLER_ACTION" == check ]]; then
  check_installed_prefix "$INSTALLER_TARGET" "$INSTALLER_PREFIX"
  exit
fi

engineering_root="$INSTALLER_SOURCE/skills/engineering"
productivity_root="$INSTALLER_SOURCE/skills/productivity"
[[ -d "$engineering_root" ]] || agent_skills_fail "Matt skills/engineering directory is missing"
[[ -d "$productivity_root" ]] || agent_skills_fail "Matt skills/productivity directory is missing"
list_file=$(mktemp "${TMPDIR:-/tmp}/matt-skills.XXXXXX")
trap 'rm -f "$list_file"' EXIT
find "$engineering_root" -name SKILL.md -type f -print | LC_ALL=C sort > "$list_file"
for dependency in grilling grill-me handoff teach to-questionnaire writing-for-agents; do
  skill_root="$productivity_root/$dependency"
  [[ -f "$skill_root/SKILL.md" ]] || agent_skills_fail "required Matt dependency is missing: $dependency"
  find "$skill_root" -name SKILL.md -type f -print >> "$list_file"
done
LC_ALL=C sort -u -o "$list_file" "$list_file"
install_prefixed_skill_list "$INSTALLER_SOURCE" "$INSTALLER_TARGET" "$INSTALLER_PREFIX" "$list_file"
