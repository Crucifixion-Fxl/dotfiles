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

skill_md="$INSTALLER_SOURCE/human-writing/SKILL.md"
[[ -f "$skill_md" ]] || agent_skills_fail "human-writing/SKILL.md is missing"
list_file=$(mktemp "${TMPDIR:-/tmp}/kkkkhazix-skills.XXXXXX")
trap 'rm -f "$list_file"' EXIT
printf '%s\n' "$skill_md" > "$list_file"
install_prefixed_skill_list "$INSTALLER_SOURCE" "$INSTALLER_TARGET" "$INSTALLER_PREFIX" "$list_file"
