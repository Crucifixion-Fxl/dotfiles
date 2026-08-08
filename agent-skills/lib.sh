#!/usr/bin/env bash

set -euo pipefail

agent_skills_fail() {
  printf 'agent-skills: %s\n' "$*" >&2
  exit 1
}

agent_skills_log() {
  printf '==> %s\n' "$*"
}

require_command() {
  command -v "$1" >/dev/null 2>&1 || agent_skills_fail "$1 is required"
}

skill_frontmatter_value() {
  local skill_md=$1 field=$2
  awk -v field="$field" '
    NR == 1 {
      if ($0 !~ /^---[[:space:]]*$/) exit 2
      frontmatter = 1
      next
    }
    frontmatter && /^---[[:space:]]*$/ { exit }
    frontmatter && index($0, field ":") == 1 {
      value = substr($0, length(field) + 2)
      sub(/^[[:space:]]*/, "", value)
      sub(/[[:space:]]*$/, "", value)
      if (value ~ /^".*"$/ || value ~ /^'"'"'.*'"'"'$/) {
        value = substr(value, 2, length(value) - 2)
      }
      print value
      exit
    }
  ' "$skill_md"
}

openai_display_name() {
  local metadata=$1
  awk '
    /^[[:space:]]*display_name:[[:space:]]*/ {
      value = $0
      sub(/^[[:space:]]*display_name:[[:space:]]*/, "", value)
      sub(/[[:space:]]*$/, "", value)
      if (value ~ /^".*"$/ || value ~ /^'"'"'.*'"'"'$/) {
        value = substr(value, 2, length(value) - 2)
      }
      print value
      exit
    }
  ' "$metadata"
}

validate_skill_directory() {
  local skill_dir=$1 expected_prefix=${2:-}
  local directory_name description display_name metadata name nested_skill

  [[ -d "$skill_dir" ]] || agent_skills_fail "skill is not a directory: $skill_dir"
  [[ -f "$skill_dir/SKILL.md" ]] || agent_skills_fail "SKILL.md is missing: $skill_dir"
  directory_name=$(basename "$skill_dir")
  name=$(skill_frontmatter_value "$skill_dir/SKILL.md" name) || \
    agent_skills_fail "invalid YAML frontmatter boundary: $skill_dir/SKILL.md"
  description=$(skill_frontmatter_value "$skill_dir/SKILL.md" description) || \
    agent_skills_fail "invalid YAML frontmatter boundary: $skill_dir/SKILL.md"

  [[ -n "$name" ]] || agent_skills_fail "frontmatter name is missing: $skill_dir/SKILL.md"
  [[ -n "$description" ]] || agent_skills_fail "frontmatter description is missing: $skill_dir/SKILL.md"
  [[ "$name" =~ ^[a-z0-9]+(-[a-z0-9]+)*$ ]] || \
    agent_skills_fail "skill name must use lowercase hyphen-case: $name"
  (( ${#name} <= 64 )) || agent_skills_fail "skill name exceeds 64 characters: $name"
  [[ "$name" == "$directory_name" ]] || \
    agent_skills_fail "skill directory $directory_name does not match frontmatter name $name"
  nested_skill=$(find "$skill_dir" -mindepth 2 -name SKILL.md -type f -print -quit)
  [[ -z "$nested_skill" ]] || \
    agent_skills_fail "installed Skill contains a nested Skill: $nested_skill"
  metadata="$skill_dir/agents/openai.yaml"
  if [[ -f "$metadata" ]] && grep -Eq '^[[:space:]]*display_name:[[:space:]]*' "$metadata"; then
    display_name=$(openai_display_name "$metadata")
    [[ "$display_name" == "$name" ]] || \
      agent_skills_fail "OpenAI display_name $display_name does not match skill name $name"
  fi
  if [[ -n "$expected_prefix" ]]; then
    [[ "$name" == "$expected_prefix-"* ]] || \
      agent_skills_fail "skill $name does not use required prefix $expected_prefix-"
  fi
}

validate_flat_skill_root() {
  local root=$1 expected_prefix=${2:-}
  local entry count=0 unexpected

  [[ -d "$root" ]] || agent_skills_fail "skill root is missing: $root"
  unexpected=$(find "$root" -mindepth 1 -maxdepth 1 ! -type d -print -quit)
  [[ -z "$unexpected" ]] || agent_skills_fail "skill root contains a non-directory entry: $unexpected"
  unexpected=$(find "$root" -type l -print -quit)
  [[ -z "$unexpected" ]] || agent_skills_fail "installed skills must not contain symlinks: $unexpected"

  for entry in "$root"/*; do
    [[ -d "$entry" ]] || continue
    validate_skill_directory "$entry" "$expected_prefix"
    count=$((count + 1))
  done
  (( count > 0 )) || agent_skills_fail "skill root is empty: $root"
}

resolve_existing_path() {
  local path=$1 target parent
  while [[ -L "$path" ]]; do
    target=$(readlink "$path") || return 1
    if [[ "$target" == /* ]]; then
      path=$target
    else
      path="$(dirname "$path")/$target"
    fi
  done
  [[ -e "$path" ]] || return 1
  parent=$(CDPATH= cd -- "$(dirname "$path")" && pwd -P) || return 1
  printf '%s/%s\n' "$parent" "$(basename "$path")"
}

validate_source_symlinks() {
  local allowed_root=$1 skill_dir=$2
  local allowed_real link resolved
  allowed_real=$(CDPATH= cd -- "$allowed_root" && pwd -P)
  while IFS= read -r link; do
    [[ -n "$link" ]] || continue
    resolved=$(resolve_existing_path "$link") || \
      agent_skills_fail "source skill contains a broken symlink: $link"
    case "$resolved" in
      "$allowed_real"|"$allowed_real"/*) ;;
      *) agent_skills_fail "source skill symlink escapes its repository: $link -> $resolved" ;;
    esac
  done < <(find "$skill_dir" -type l -print)
}

rewrite_frontmatter_name() {
  local skill_md=$1 new_name=$2 temporary
  temporary="$skill_md.tmp.$$"
  awk -v new_name="$new_name" '
    NR == 1 && /^---[[:space:]]*$/ { frontmatter = 1; print; next }
    frontmatter && !changed && /^name:[[:space:]]*/ {
      print "name: " new_name
      changed = 1
      next
    }
    frontmatter && /^---[[:space:]]*$/ { frontmatter = 0 }
    { print }
    END { if (!changed) exit 2 }
  ' "$skill_md" > "$temporary" || {
    rm -f "$temporary"
    agent_skills_fail "unable to rewrite frontmatter name: $skill_md"
  }
  mv "$temporary" "$skill_md"
}

rewrite_openai_display_name() {
  local metadata=$1 new_name=$2 temporary
  [[ -f "$metadata" ]] || return 0
  grep -Eq '^[[:space:]]*display_name:[[:space:]]*' "$metadata" || return 0
  temporary="$metadata.tmp.$$"
  awk -v new_name="$new_name" '
    !changed && /^[[:space:]]*display_name:[[:space:]]*/ {
      match($0, /^[[:space:]]*/)
      indentation = substr($0, 1, RLENGTH)
      print indentation "display_name: \"" new_name "\""
      changed = 1
      next
    }
    { print }
    END { if (!changed) exit 2 }
  ' "$metadata" > "$temporary" || {
    rm -f "$temporary"
    agent_skills_fail "unable to rewrite OpenAI display_name: $metadata"
  }
  mv "$temporary" "$metadata"
}

rewrite_exact_literal_mappings() {
  local file=$1 mappings=$2 temporary
  temporary="$file.tmp.$$"
  awk -v mappings="$mappings" '
    function replace_literal(value, needle, replacement, before, position) {
      before = ""
      while ((position = index(value, needle)) != 0) {
        before = before substr(value, 1, position - 1) replacement
        value = substr(value, position + length(needle))
      }
      return before value
    }
    BEGIN {
      while ((getline mapping < mappings) > 0) {
        split(mapping, fields, "\t")
        old_values[++mapping_count] = fields[1]
        new_values[mapping_count] = fields[2]
      }
      close(mappings)
    }
    {
      line = $0
      for (mapping_index = 1; mapping_index <= mapping_count; mapping_index++) {
        line = replace_literal(line, old_values[mapping_index], new_values[mapping_index])
      }
      print line
    }
  ' "$file" > "$temporary"
  mv "$temporary" "$file"
}

rewrite_exact_references() {
  local target=$1 mappings=$2 file
  while IFS= read -r file; do
    [[ -n "$file" ]] || continue
    [[ "$file" == "$mappings" ]] && continue
    if LC_ALL=C grep -Iq . "$file"; then
      rewrite_exact_literal_mappings "$file" "$mappings"
    fi
  done < <(find "$target" -type f -print)
}

rewrite_token_mappings() {
  local file=$1 mappings=$2 temporary
  temporary="$file.tmp.$$"
  awk -v mappings="$mappings" '
    function replace_token(value, old_value, new_value, pattern, matched, old_position, result) {
      result = ""
      pattern = "(^|[^a-z0-9-])" old_value "([^a-z0-9-]|$)"
      while (match(value, pattern)) {
        matched = substr(value, RSTART, RLENGTH)
        old_position = index(matched, old_value)
        result = result substr(value, 1, RSTART - 1) \
          substr(matched, 1, old_position - 1) new_value \
          substr(matched, old_position + length(old_value))
        value = substr(value, RSTART + RLENGTH)
      }
      return result value
    }
    BEGIN {
      while ((getline mapping < mappings) > 0) {
        split(mapping, fields, "\t")
        old_values[++mapping_count] = fields[1]
        new_values[mapping_count] = fields[2]
      }
      close(mappings)
    }
    {
      line = $0
      for (mapping_index = 1; mapping_index <= mapping_count; mapping_index++) {
        line = replace_token(line, old_values[mapping_index], new_values[mapping_index])
      }
      print line
    }
  ' "$file" > "$temporary"
  mv "$temporary" "$file"
}

rewrite_token_references() {
  local target=$1 mappings=$2 file
  while IFS= read -r file; do
    [[ -n "$file" ]] || continue
    [[ "$file" == "$mappings" ]] && continue
    if LC_ALL=C grep -Iq . "$file"; then
      rewrite_token_mappings "$file" "$mappings"
    fi
  done < <(find "$target" -type f -print)
}

flatten_nested_skills() {
  local target=$1 prefix=$2 source_skill_dir=$3 list_file=$4
  local path_mappings name_mappings removals
  local nested nested_dir old_name relative source_nested
  path_mappings=$(mktemp "${target%/}/.nested-paths.XXXXXX")
  name_mappings=$(mktemp "${target%/}/.nested-names.XXXXXX")
  removals=$(mktemp "${target%/}/.nested-removals.XXXXXX")
  while IFS= read -r nested; do
    [[ -n "$nested" ]] || continue
    relative=${nested#"$target/"}
    source_nested="$source_skill_dir/$relative"
    grep -Fqx -- "$source_nested" "$list_file" || \
      agent_skills_fail "nested Skill is not selected for flat installation: $source_nested"
    old_name=$(skill_frontmatter_value "$nested" name) || \
      agent_skills_fail "invalid nested Skill frontmatter: $nested"
    [[ "$old_name" =~ ^[a-z0-9]+(-[a-z0-9]+)*$ ]] || \
      agent_skills_fail "invalid nested Skill name: $old_name"
    nested_dir=${nested%/SKILL.md}
    case "$nested_dir" in
      "$target"/*) ;;
      *) agent_skills_fail "nested Skill escaped parent: $nested_dir" ;;
    esac
    printf '%s\t../%s-%s/SKILL.md\n' "$relative" "$prefix" "$old_name" \
      >> "$path_mappings"
    printf '%s\t%s-%s\n' "$old_name" "$prefix" "$old_name" >> "$name_mappings"
    printf '%s\n' "$nested_dir" >> "$removals"
  done < <(find "$target" -depth -mindepth 2 -name SKILL.md -type f -print)
  if [[ -s "$removals" ]]; then
    while IFS= read -r nested_dir; do
      [[ -n "$nested_dir" ]] || continue
      rm -rf -- "$nested_dir"
    done < "$removals"
    rewrite_exact_references "$target" "$path_mappings"
    rewrite_token_references "$target" "$name_mappings"
  fi
  rm -f "$path_mappings" "$name_mappings" "$removals"
}

rewrite_literal_references() {
  local file=$1 mappings=$2 temporary
  temporary="$file.tmp.$$"
  awk -v mappings="$mappings" '
    function replace_literal(value, needle, replacement, before, position) {
      while ((position = index(value, needle)) != 0) {
        before = before substr(value, 1, position - 1) replacement
        value = substr(value, position + length(needle))
      }
      return before value
    }
    BEGIN {
      while ((getline mapping < mappings) > 0) {
        split(mapping, fields, "\t")
        old_names[++mapping_count] = fields[1]
        new_names[mapping_count] = fields[2]
      }
      close(mappings)
    }
    {
      line = $0
      for (mapping_index = 1; mapping_index <= mapping_count; mapping_index++) {
        line = replace_literal(line, "/" old_names[mapping_index], "/" new_names[mapping_index])
        line = replace_literal(line, "$" old_names[mapping_index], "$" new_names[mapping_index])
      }
      print line
    }
  ' "$file" > "$temporary"
  mv "$temporary" "$file"
}

rewrite_skill_references() {
  local target=$1 mappings=$2 file
  while IFS= read -r file; do
    [[ -n "$file" ]] || continue
    if LC_ALL=C grep -Iq . "$file"; then
      rewrite_literal_references "$file" "$mappings"
    fi
  done < <(find "$target" -type f -print)
}

install_prefixed_skill_list() {
  local source_root=$1 target=$2 prefix=$3 list_file=$4
  local destination mappings new_name old_name skill_dir skill_md

  [[ "$prefix" =~ ^[a-z0-9]+(-[a-z0-9]+)*$ ]] || \
    agent_skills_fail "invalid source prefix: $prefix"
  [[ -s "$list_file" ]] || agent_skills_fail "source produced no SKILL.md files: $source_root"
  mkdir -p "$target"
  mappings=$(mktemp "${target%/}/.mappings.XXXXXX")
  trap 'rm -f "$mappings"' RETURN

  while IFS= read -r skill_md; do
    [[ -f "$skill_md" ]] || agent_skills_fail "listed SKILL.md is missing: $skill_md"
    skill_dir=${skill_md%/SKILL.md}
    old_name=$(skill_frontmatter_value "$skill_md" name) || \
      agent_skills_fail "invalid YAML frontmatter boundary: $skill_md"
    [[ "$old_name" =~ ^[a-z0-9]+(-[a-z0-9]+)*$ ]] || \
      agent_skills_fail "invalid upstream skill name: $old_name"
    new_name="$prefix-$old_name"
    destination="$target/$new_name"
    [[ ! -e "$destination" && ! -L "$destination" ]] || \
      agent_skills_fail "duplicate installed skill name: $new_name"
    validate_source_symlinks "$source_root" "$skill_dir"
    cp -RL "$skill_dir" "$destination"
    flatten_nested_skills "$destination" "$prefix" "$skill_dir" "$list_file"
    rewrite_frontmatter_name "$destination/SKILL.md" "$new_name"
    rewrite_openai_display_name "$destination/agents/openai.yaml" "$new_name"
    printf '%s\t%s\n' "$old_name" "$new_name" >> "$mappings"
  done < "$list_file"

  rewrite_skill_references "$target" "$mappings"
  rm -f "$mappings"
  trap - RETURN
  validate_flat_skill_root "$target" "$prefix"
}

check_installed_prefix() {
  local target=$1 prefix=$2 temporary count=0 skill_dir
  temporary=$(mktemp -d "${TMPDIR:-/tmp}/agent-skills-check.XXXXXX")
  trap 'rm -rf "$temporary"' RETURN
  for skill_dir in "$target/$prefix-"*; do
    [[ -d "$skill_dir" ]] || continue
    cp -R "$skill_dir" "$temporary/"
    count=$((count + 1))
  done
  (( count > 0 )) || agent_skills_fail "no installed skills use prefix $prefix-"
  validate_flat_skill_root "$temporary" "$prefix"
  rm -rf "$temporary"
  trap - RETURN
}

installer_parse_args() {
  INSTALLER_ACTION=${1:-}
  [[ -n "$INSTALLER_ACTION" ]] || agent_skills_fail "installer action must be sync or check"
  shift || true
  INSTALLER_SOURCE=
  INSTALLER_TARGET=
  INSTALLER_PREFIX=
  while (( $# > 0 )); do
    case "$1" in
      --source)
        (( $# >= 2 )) || agent_skills_fail "--source requires a path"
        INSTALLER_SOURCE=$2
        shift 2
        ;;
      --target)
        (( $# >= 2 )) || agent_skills_fail "--target requires a path"
        INSTALLER_TARGET=$2
        shift 2
        ;;
      --prefix)
        (( $# >= 2 )) || agent_skills_fail "--prefix requires a value"
        INSTALLER_PREFIX=$2
        shift 2
        ;;
      *) agent_skills_fail "unknown installer argument: $1" ;;
    esac
  done
  [[ "$INSTALLER_ACTION" == sync || "$INSTALLER_ACTION" == check ]] || \
    agent_skills_fail "installer action must be sync or check"
  [[ -n "$INSTALLER_TARGET" ]] || agent_skills_fail "--target is required"
  [[ -n "$INSTALLER_PREFIX" ]] || agent_skills_fail "--prefix is required"
  if [[ "$INSTALLER_ACTION" == sync ]]; then
    [[ -n "$INSTALLER_SOURCE" && -d "$INSTALLER_SOURCE" ]] || \
      agent_skills_fail "--source must be a repository directory for sync"
  fi
}
