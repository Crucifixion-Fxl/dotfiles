#!/usr/bin/env bash

set -euo pipefail

AGENT_SKILLS_DIR=$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=lib.sh
source "$AGENT_SKILLS_DIR/lib.sh"

SOURCES_DIR=${AGENT_SKILLS_SOURCES_DIR:-$AGENT_SKILLS_DIR/sources}
NATIVE_DIR=${AGENT_SKILLS_NATIVE_DIR:-$AGENT_SKILLS_DIR/native}
INSTALL_DIR=${AGENT_SKILLS_INSTALL_DIR:-$HOME/.agents/skills}

SOURCE_URL=
SOURCE_REQUIRED=true

read_source_config() {
  local config=$1 line url_seen=0 required_seen=0
  local url_pattern="^SOURCE_URL='([^']+)'$"
  local required_pattern="^SOURCE_REQUIRED='(true|false)'$"
  SOURCE_URL=
  SOURCE_REQUIRED=true

  while IFS= read -r line || [[ -n "$line" ]]; do
    case "$line" in
      ''|'#'*) continue ;;
    esac
    if [[ "$line" =~ $url_pattern ]]; then
      (( url_seen == 0 )) || agent_skills_fail "SOURCE_URL is duplicated: $config"
      SOURCE_URL=${BASH_REMATCH[1]}
      url_seen=1
    elif [[ "$line" =~ $required_pattern ]]; then
      (( required_seen == 0 )) || agent_skills_fail "SOURCE_REQUIRED is duplicated: $config"
      SOURCE_REQUIRED=${BASH_REMATCH[1]}
      required_seen=1
    else
      agent_skills_fail "unsupported source.conf line in $config: $line"
    fi
  done < "$config"
  [[ -n "$SOURCE_URL" ]] || agent_skills_fail "SOURCE_URL is missing: $config"
}

for_each_source() {
  local callback=$1 source_directory
  [[ -d "$SOURCES_DIR" ]] || agent_skills_fail "sources directory is missing: $SOURCES_DIR"
  for source_directory in "$SOURCES_DIR"/*; do
    [[ -d "$source_directory" ]] || continue
    "$callback" "$source_directory"
  done
}

validate_source_definition() {
  local source_directory=$1 source_name config installer
  source_name=$(basename "$source_directory")
  config="$source_directory/source.conf"
  installer="$source_directory/install.sh"
  [[ "$source_name" =~ ^[a-z0-9]+(-[a-z0-9]+)*$ ]] || \
    agent_skills_fail "invalid source directory name: $source_name"
  [[ -f "$config" ]] || agent_skills_fail "source.conf is missing: $source_directory"
  [[ -x "$installer" ]] || agent_skills_fail "install.sh is not executable: $source_directory"
  read_source_config "$config"
  bash -n "$installer"
}

count_sources() {
  SOURCE_COUNT=$((SOURCE_COUNT + 1))
}

validate_definitions() {
  SOURCE_COUNT=0
  for_each_source validate_source_definition
  for_each_source count_sources
  (( SOURCE_COUNT > 0 )) || agent_skills_fail "no external skill sources are configured"
  bash -n "$AGENT_SKILLS_DIR/lib.sh"
  bash -n "$AGENT_SKILLS_DIR/sync.sh"
}

clone_repository() {
  local repository=$1 destination=$2
  if [[ -t 0 && -t 1 ]]; then
    git clone --depth 1 -- "$repository" "$destination"
  else
    GIT_TERMINAL_PROMPT=0 GIT_SSH_COMMAND='ssh -o BatchMode=yes' \
      git clone --depth 1 -- "$repository" "$destination"
  fi
}

merge_staged_source() {
  local source_stage=$1 final_stage=$2 skill_dir destination
  for skill_dir in "$source_stage"/*; do
    [[ -d "$skill_dir" ]] || continue
    destination="$final_stage/$(basename "$skill_dir")"
    [[ ! -e "$destination" && ! -L "$destination" ]] || \
      agent_skills_fail "duplicate final skill name: $(basename "$skill_dir")"
    mv "$skill_dir" "$destination"
  done
}

preserve_installed_prefix() {
  local prefix=$1 final_stage=$2 skill_dir count=0 destination
  for skill_dir in "$INSTALL_DIR/$prefix-"*; do
    [[ -d "$skill_dir" ]] || continue
    destination="$final_stage/$(basename "$skill_dir")"
    [[ ! -e "$destination" && ! -L "$destination" ]] || \
      agent_skills_fail "duplicate preserved skill name: $(basename "$skill_dir")"
    cp -R "$skill_dir" "$destination"
    ensure_openai_display_name "$destination/agents/openai.yaml" "$(basename "$destination")"
    count=$((count + 1))
  done
  if (( count > 0 )); then
    agent_skills_log "Preserved $count previously installed $prefix Skills"
  else
    agent_skills_log "Optional source $prefix has no previous installation; skipping"
  fi
}

sync_external_source() {
  local source_directory=$1 source_name config installer clone_dir source_stage
  source_name=$(basename "$source_directory")
  config="$source_directory/source.conf"
  installer="$source_directory/install.sh"
  clone_dir="$WORK_ROOT/repositories/$source_name"
  source_stage="$WORK_ROOT/source-stages/$source_name"
  read_source_config "$config"
  mkdir -p "$source_stage"

  agent_skills_log "Cloning latest $source_name Skills"
  if ! clone_repository "$SOURCE_URL" "$clone_dir"; then
    if [[ "$SOURCE_REQUIRED" == true ]]; then
      agent_skills_fail "required source $source_name could not be cloned"
    fi
    printf 'agent-skills: warning: optional source %s could not be cloned\n' "$source_name" >&2
    preserve_installed_prefix "$source_name" "$FINAL_STAGE"
    return
  fi

  bash "$installer" sync \
    --source "$clone_dir" \
    --target "$source_stage" \
    --prefix "$source_name"
  # Enforce the Codex UI namespace centrally as well as in the shared installer
  # helper, so a future source-specific installer cannot accidentally omit it.
  ensure_prefixed_skill_display_names "$source_stage" "$source_name"
  validate_flat_skill_root "$source_stage" "$source_name"
  merge_staged_source "$source_stage" "$FINAL_STAGE"
}

sync_native_skills() {
  local native_skill destination
  [[ -d "$NATIVE_DIR" ]] || return 0
  for native_skill in "$NATIVE_DIR"/*; do
    [[ -d "$native_skill" ]] || continue
    destination="$FINAL_STAGE/$(basename "$native_skill")"
    [[ ! -e "$destination" && ! -L "$destination" ]] || \
      agent_skills_fail "native Skill conflicts with another source: $(basename "$native_skill")"
    validate_source_symlinks "$NATIVE_DIR" "$native_skill"
    cp -RL "$native_skill" "$destination"
  done
}

replace_installation() {
  local previous="$WORK_ROOT/previous-skills"
  mkdir -p "$(dirname "$INSTALL_DIR")"
  if [[ -e "$INSTALL_DIR" || -L "$INSTALL_DIR" ]]; then
    mv "$INSTALL_DIR" "$previous"
  fi
  if mv "$FINAL_STAGE" "$INSTALL_DIR"; then
    rm -rf "$previous"
    return
  fi
  if [[ -e "$previous" || -L "$previous" ]]; then
    mv "$previous" "$INSTALL_DIR"
  fi
  agent_skills_fail "unable to replace $INSTALL_DIR"
}

sync_skills() {
  require_command awk
  require_command bash
  require_command cp
  require_command find
  require_command git
  require_command grep
  require_command mktemp
  require_command mv
  validate_definitions

  mkdir -p "$(dirname "$INSTALL_DIR")"
  WORK_ROOT=$(mktemp -d "$(dirname "$INSTALL_DIR")/.skills-sync.XXXXXX")
  trap 'rm -rf "$WORK_ROOT"' EXIT
  FINAL_STAGE="$WORK_ROOT/final-skills"
  mkdir -p "$WORK_ROOT/repositories" "$WORK_ROOT/source-stages" "$FINAL_STAGE"

  for_each_source sync_external_source
  sync_native_skills
  validate_flat_skill_root "$FINAL_STAGE"
  replace_installation
  trap - EXIT
  rm -rf "$WORK_ROOT"
  agent_skills_log "Installed Agent Skills into $INSTALL_DIR"
  agent_skills_log "Start a new Agent session to load the refreshed Skills"
}

check_source_installation() {
  local source_directory=$1 source_name config installer installed found=0
  source_name=$(basename "$source_directory")
  config="$source_directory/source.conf"
  installer="$source_directory/install.sh"
  read_source_config "$config"
  if [[ "$SOURCE_REQUIRED" == false ]]; then
    for installed in "$INSTALL_DIR/$source_name-"*; do
      [[ -d "$installed" ]] || continue
      found=1
      break
    done
    if (( found == 0 )); then
      agent_skills_log "Optional source $source_name has no installed Skills; skipping check"
      return 0
    fi
  fi
  bash "$installer" check --target "$INSTALL_DIR" --prefix "$source_name"
}

check_native_skills() {
  local native_skill installed
  [[ -d "$NATIVE_DIR" ]] || return 0
  for native_skill in "$NATIVE_DIR"/*; do
    [[ -d "$native_skill" ]] || continue
    installed="$INSTALL_DIR/$(basename "$native_skill")"
    [[ -d "$installed" ]] || agent_skills_fail "native Skill is not installed: $(basename "$native_skill")"
    diff -qr "$native_skill" "$installed" >/dev/null || \
      agent_skills_fail "native Skill differs from dotfiles: $(basename "$native_skill")"
  done
}

check_known_namespaces() {
  local installed source_directory source_name known native_skill
  for installed in "$INSTALL_DIR"/*; do
    [[ -d "$installed" ]] || continue
    known=0
    for source_directory in "$SOURCES_DIR"/*; do
      [[ -d "$source_directory" ]] || continue
      source_name=$(basename "$source_directory")
      if [[ $(basename "$installed") == "$source_name-"* ]]; then
        known=1
        break
      fi
    done
    if (( known == 0 )) && [[ -d "$NATIVE_DIR" ]]; then
      for native_skill in "$NATIVE_DIR"/*; do
        [[ -d "$native_skill" ]] || continue
        if [[ $(basename "$installed") == "$(basename "$native_skill")" ]]; then
          known=1
          break
        fi
      done
    fi
    (( known == 1 )) || agent_skills_fail "installed Skill has no configured source: $(basename "$installed")"
  done
}

check_skills() {
  require_command awk
  require_command bash
  require_command diff
  require_command find
  require_command grep
  validate_definitions
  validate_flat_skill_root "$INSTALL_DIR"
  for_each_source check_source_installation
  check_native_skills
  check_known_namespaces
  agent_skills_log "Agent Skills validation passed"
}

main() {
  case "${1:-sync}" in
    sync) sync_skills ;;
    check) check_skills ;;
    *) agent_skills_fail "usage: sync.sh [sync|check]" ;;
  esac
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  main "$@"
fi
