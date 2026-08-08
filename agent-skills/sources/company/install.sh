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

[[ -d "$INSTALLER_SOURCE/skills" ]] || agent_skills_fail "company skills/ directory is missing"
list_file=$(mktemp "${TMPDIR:-/tmp}/company-skills.XXXXXX")
trap 'rm -f "$list_file"' EXIT
find "$INSTALLER_SOURCE/skills" -name SKILL.md -type f -print | LC_ALL=C sort > "$list_file"
install_prefixed_skill_list "$INSTALLER_SOURCE" "$INSTALLER_TARGET" "$INSTALLER_PREFIX" "$list_file"
