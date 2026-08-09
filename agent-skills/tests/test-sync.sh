#!/usr/bin/env bash

set -euo pipefail

ROOT=$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
TEST_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/agent-skills-test.XXXXXX")
trap 'rm -rf "$TEST_ROOT"' EXIT

TEST_HOME="$TEST_ROOT/home"
MANAGER="$TEST_ROOT/manager"
REPOSITORIES="$TEST_ROOT/repositories"
INSTALL_DIR="$TEST_HOME/.agents/skills"
LEGACY_INSTALL_DIR="$TEST_HOME/.codex/skills"
mkdir -p "$MANAGER/sources" "$MANAGER/native" "$REPOSITORIES" \
  "$INSTALL_DIR/old-skill" "$LEGACY_INSTALL_DIR/.system" \
  "$LEGACY_INSTALL_DIR/matt-tdd" "$LEGACY_INSTALL_DIR/architect"
cp "$ROOT/lib.sh" "$ROOT/sync.sh" "$MANAGER/"
printf '%s\n' system-preserved > "$LEGACY_INSTALL_DIR/.system/marker"
printf '%s\n' legacy-matt > "$LEGACY_INSTALL_DIR/matt-tdd/SKILL.md"
printf '%s\n' legacy-company > "$LEGACY_INSTALL_DIR/architect/SKILL.md"
printf '%s\n' legacy-file > "$LEGACY_INSTALL_DIR/README.md"

write_skill() {
  local directory=$1 name=$2 body=${3:-}
  mkdir -p "$directory"
  {
    printf '%s\n' '---'
    printf 'name: %s\n' "$name"
    printf 'description: Test Skill %s\n' "$name"
    printf '%s\n\n' '---'
    printf '# %s\n\n%s\n' "$name" "$body"
  } > "$directory/SKILL.md"
}

commit_repository() {
  local repository=$1
  git -C "$repository" init -q
  git -C "$repository" add .
  git -C "$repository" -c user.name='Agent Skills Test' -c user.email='agent-skills@example.com' \
    commit -qm initial
}

configure_source() {
  local name=$1 repository=$2 required=${3:-true} installer_source=${4:-$1}
  local platforms=${5:-darwin,linux}
  mkdir -p "$MANAGER/sources/$name"
  cp "$ROOT/sources/$installer_source/install.sh" "$MANAGER/sources/$name/install.sh"
  chmod +x "$MANAGER/sources/$name/install.sh"
  printf "SOURCE_URL='%s'\nSOURCE_REQUIRED='%s'\nSOURCE_PLATFORMS='%s'\n" \
    "$repository" "$required" "$platforms" \
    > "$MANAGER/sources/$name/source.conf"
}

company_repo="$REPOSITORIES/company"
mkdir -p "$company_repo"
write_skill "$company_repo/skills/code-review" code-review 'Run /architect and $architect.'
write_skill "$company_repo/skills/architect" architect 'Architecture workflow.'
mkdir -p "$company_repo/skills/architect/agents"
printf '%s\n' 'display_name: "Architect"' 'short_description: "Architecture workflow"' \
  > "$company_repo/skills/architect/agents/openai.yaml"
write_skill "$company_repo/skills/already-prefixed" company-already-prefixed \
  'The source already includes its namespace.'
write_skill "$company_repo/skills/code-review/helper" helper \
  'Nested helper installed separately.'
printf '%s\n' '[Helper](helper/SKILL.md)' >> "$company_repo/skills/code-review/SKILL.md"
printf '%s\n' 'reference body' > "$company_repo/skills/code-review/reference.md"
ln -s reference.md "$company_repo/skills/code-review/reference-link.md"
commit_repository "$company_repo"

matt_repo="$REPOSITORIES/matt"
mkdir -p "$matt_repo"
write_skill "$matt_repo/skills/engineering/grill-with-docs" grill-with-docs \
  'Run /grilling with /domain-modeling.'
write_skill "$matt_repo/skills/engineering/grill-with-docs/grill-helper" grill-helper \
  'Nested Matt helper installed separately.'
printf '%s\n' '[Helper](grill-helper/SKILL.md)' \
  >> "$matt_repo/skills/engineering/grill-with-docs/SKILL.md"
mkdir -p "$matt_repo/skills/engineering/grill-with-docs/agents"
printf '%s\n' 'interface:' '  display_name: "Grill with Docs"' \
  > "$matt_repo/skills/engineering/grill-with-docs/agents/openai.yaml"
write_skill "$matt_repo/skills/engineering/domain-modeling" domain-modeling 'Domain workflow.'
for dependency in grilling grill-me handoff teach to-questionnaire writing-for-agents; do
  write_skill "$matt_repo/skills/productivity/$dependency" "$dependency" 'Productivity dependency.'
done
write_skill "$matt_repo/skills/in-progress/not-installed" not-installed 'Must stay excluded.'
commit_repository "$matt_repo"

kkkkhazix_repo="$REPOSITORIES/kkkkhazix"
mkdir -p "$kkkkhazix_repo"
write_skill "$kkkkhazix_repo/human-writing" human-writing 'Human writing workflow.'
commit_repository "$kkkkhazix_repo"

agents365_repo="$REPOSITORIES/agents365"
mkdir -p "$agents365_repo"
write_skill "$agents365_repo/skills/drawio-skill" drawio-skill 'Draw.io workflow.'
commit_repository "$agents365_repo"

# Simulate a source added in the future. Its directory name must automatically
# become the namespace without any source-specific change in lib.sh.
future_repo="$REPOSITORIES/future"
mkdir -p "$future_repo"
write_skill "$future_repo/skills/tool" future-tool 'Future workflow.'
commit_repository "$future_repo"

write_skill "$MANAGER/native/native-example" native-example 'Native workflow.'
printf '%s\n' stale > "$INSTALL_DIR/old-skill/SKILL.md"

configure_source company "$company_repo" false company linux
configure_source matt "$matt_repo"
configure_source kkkkhazix "$kkkkhazix_repo"
configure_source agents365 "$agents365_repo"
configure_source future "$future_repo" true company

# A future source may use its own installer instead of the shared helper. The
# sync layer must still add the explicit prefixed Codex UI metadata centrally.
{
  printf '%s\n' '#!/usr/bin/env bash' '' 'set -euo pipefail' ''
  printf '%s\n' 'SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)'
  printf '%s\n' 'source "$SCRIPT_DIR/../../lib.sh"' 'installer_parse_args "$@"' ''
  printf '%s\n' 'if [[ "$INSTALLER_ACTION" == check ]]; then'
  printf '%s\n' '  check_installed_prefix "$INSTALLER_TARGET" "$INSTALLER_PREFIX"' '  exit' 'fi' ''
  printf '%s\n' 'mkdir -p "$INSTALLER_TARGET"'
  printf '%s\n' 'cp -R "$INSTALLER_SOURCE/skills/tool" "$INSTALLER_TARGET/$INSTALLER_PREFIX-tool"'
} > "$MANAGER/sources/future/install.sh"
chmod +x "$MANAGER/sources/future/install.sh"

grep -Fqx "SOURCE_REQUIRED='false'" "$ROOT/sources/company/source.conf"
grep -Fqx "SOURCE_PLATFORMS='linux'" "$ROOT/sources/company/source.conf"
for required_source in matt kkkkhazix agents365; do
  grep -Fqx "SOURCE_REQUIRED='true'" "$ROOT/sources/$required_source/source.conf"
done

run_sync() {
  HOME=$TEST_HOME \
    AGENT_SKILLS_PLATFORM=${TEST_PLATFORM:-linux} \
    AGENT_SKILLS_SOURCES_DIR="$MANAGER/sources" \
    AGENT_SKILLS_NATIVE_DIR="$MANAGER/native" \
    AGENT_SKILLS_INSTALL_DIR="$INSTALL_DIR" \
    AGENT_SKILLS_LEGACY_INSTALL_DIR="$LEGACY_INSTALL_DIR" \
    bash "$MANAGER/sync.sh" "$@"
}

run_sync sync

# Codex still discovers the legacy ~/.codex/skills root. A successful sync must
# leave only its bundled .system directory so old and namespaced Skills cannot
# appear together in the UI.
[[ -f "$LEGACY_INSTALL_DIR/.system/marker" ]]
grep -Fqx system-preserved "$LEGACY_INSTALL_DIR/.system/marker"
legacy_remaining=$(find "$LEGACY_INSTALL_DIR" -mindepth 1 -maxdepth 1 \
  ! -name .system -print -quit)
if [[ -n "$legacy_remaining" ]]; then
  printf 'legacy Codex Skill remained after sync: %s\n' "$legacy_remaining" >&2
  exit 1
fi

# Every external Skill must provide an explicit source-prefixed Codex UI name.
# Upstream metadata may be absent or may use the legacy top-level shape.
for source_directory in "$MANAGER/sources"/*; do
  [[ -d "$source_directory" ]] || continue
  source_prefix=${source_directory##*/}
  for source_skill in "$INSTALL_DIR"/"$source_prefix"-*; do
    [[ -d "$source_skill" ]] || continue
    source_name=${source_skill##*/}
    source_metadata="$source_skill/agents/openai.yaml"
    [[ -f "$source_metadata" ]]
    source_display_name=$(awk '
      /^interface:[[:space:]]*$/ { in_interface = 1; next }
      in_interface && /^[^[:space:]]/ { in_interface = 0 }
      in_interface && /^[[:space:]]+display_name:[[:space:]]*/ {
        value = $0
        sub(/^[[:space:]]*display_name:[[:space:]]*/, "", value)
        gsub(/^"|"$/, "", value)
        print value
        exit
      }
    ' "$source_metadata")
    [[ "$source_display_name" == "$source_name" ]]
    if grep -E '^[[:space:]]*display_name:[[:space:]]*' "$source_metadata" |
      grep -Fvq "\"$source_name\""; then
      printf '%s\n' "external Skill contains an unprefixed display_name: $source_metadata" >&2
      exit 1
    fi
  done
done

[[ ! -e "$INSTALL_DIR/old-skill" ]]
[[ -d "$INSTALL_DIR/company-code-review" ]]
[[ -d "$INSTALL_DIR/company-architect" ]]
if [[ ! -d "$INSTALL_DIR/company-already-prefixed" ||
  -e "$INSTALL_DIR/company-company-already-prefixed" ]]; then
  printf '%s\n' 'an already-prefixed upstream Skill must not receive a duplicate prefix' >&2
  exit 1
fi
[[ -d "$INSTALL_DIR/company-helper" ]]
[[ -d "$INSTALL_DIR/matt-grill-with-docs" ]]
[[ -d "$INSTALL_DIR/matt-grill-helper" ]]
[[ -d "$INSTALL_DIR/matt-grilling" ]]
[[ ! -e "$INSTALL_DIR/matt-not-installed" ]]
[[ -d "$INSTALL_DIR/kkkkhazix-human-writing" ]]
[[ -d "$INSTALL_DIR/agents365-drawio-skill" ]]
[[ -d "$INSTALL_DIR/future-tool" ]]
[[ -d "$INSTALL_DIR/native-example" ]]
[[ $(find "$INSTALL_DIR" -mindepth 1 -maxdepth 1 -type d | wc -l | tr -d ' ') -eq 17 ]]
[[ -f "$INSTALL_DIR/company-code-review/reference-link.md" ]]
[[ ! -L "$INSTALL_DIR/company-code-review/reference-link.md" ]]
[[ ! -e "$INSTALL_DIR/company-code-review/helper" ]]
grep -Fq '../company-helper/SKILL.md' "$INSTALL_DIR/company-code-review/SKILL.md"
grep -Fq 'company-helper' "$INSTALL_DIR/company-code-review/SKILL.md"
[[ -z $(find "$INSTALL_DIR" -mindepth 3 -name SKILL.md -type f -print -quit) ]]
[[ -z $(find "$INSTALL_DIR" -type l -print -quit) ]]
grep -Fq 'name: company-code-review' "$INSTALL_DIR/company-code-review/SKILL.md"
grep -Fq '/company-architect' "$INSTALL_DIR/company-code-review/SKILL.md"
grep -Fq '$company-architect' "$INSTALL_DIR/company-code-review/SKILL.md"
grep -Fq 'name: matt-grill-with-docs' "$INSTALL_DIR/matt-grill-with-docs/SKILL.md"
[[ ! -e "$INSTALL_DIR/matt-grill-with-docs/grill-helper" ]]
grep -Fq '../matt-grill-helper/SKILL.md' "$INSTALL_DIR/matt-grill-with-docs/SKILL.md"
grep -Fq 'display_name: "matt-grill-with-docs"' \
  "$INSTALL_DIR/matt-grill-with-docs/agents/openai.yaml"
grep -Fq '/matt-grilling' "$INSTALL_DIR/matt-grill-with-docs/SKILL.md"
grep -Fq '/matt-domain-modeling' "$INSTALL_DIR/matt-grill-with-docs/SKILL.md"
grep -Fq 'name: kkkkhazix-human-writing' "$INSTALL_DIR/kkkkhazix-human-writing/SKILL.md"
grep -Fq 'name: agents365-drawio-skill' "$INSTALL_DIR/agents365-drawio-skill/SKILL.md"
[[ -z $(find "$TEST_HOME/.agents" -mindepth 1 -maxdepth 1 -name '.skills-sync.*' -print -quit) ]]

run_sync check

# macOS excludes the Linux-only company source from both synchronization and
# validation. The transactional projection naturally removes a previously
# installed company namespace without any source-specific cleanup migration.
MAC_INSTALL_DIR="$TEST_HOME/.agents/skills-macos"
MAC_LEGACY_INSTALL_DIR="$TEST_HOME/.codex/skills-macos"
mkdir -p "$MAC_INSTALL_DIR" "$MAC_LEGACY_INSTALL_DIR/.system"
cp -R "$INSTALL_DIR/." "$MAC_INSTALL_DIR/"
run_macos_sync() {
  HOME=$TEST_HOME \
    AGENT_SKILLS_PLATFORM=darwin \
    AGENT_SKILLS_SOURCES_DIR="$MANAGER/sources" \
    AGENT_SKILLS_NATIVE_DIR="$MANAGER/native" \
    AGENT_SKILLS_INSTALL_DIR="$MAC_INSTALL_DIR" \
    AGENT_SKILLS_LEGACY_INSTALL_DIR="$MAC_LEGACY_INSTALL_DIR" \
    bash "$MANAGER/sync.sh" "$@"
}
if run_macos_sync check >/dev/null 2>&1; then
  printf '%s\n' 'macOS unexpectedly accepted installed Linux-only company Skills' >&2
  exit 1
fi
MAC_SYNC_OUTPUT="$TEST_ROOT/macos-sync-output"
run_macos_sync sync > "$MAC_SYNC_OUTPUT"
grep -Fq 'Skipping company Skills on darwin' "$MAC_SYNC_OUTPUT"
if grep -Fq 'Cloning latest company Skills' "$MAC_SYNC_OUTPUT"; then
  printf '%s\n' 'macOS unexpectedly cloned the Linux-only company source' >&2
  exit 1
fi
[[ -z $(find "$MAC_INSTALL_DIR" -mindepth 1 -maxdepth 1 -type d -name 'company-*' -print -quit) ]]
[[ -d "$MAC_INSTALL_DIR/matt-grill-with-docs" ]]
[[ -d "$MAC_INSTALL_DIR/kkkkhazix-human-writing" ]]
[[ -d "$MAC_INSTALL_DIR/agents365-drawio-skill" ]]
run_macos_sync check

# Read-only validation must expose any legacy Skill that reappears after a
# successful migration instead of reporting a duplicate-prone setup as valid.
mkdir -p "$LEGACY_INSTALL_DIR/tdd"
printf '%s\n' legacy-reintroduced > "$LEGACY_INSTALL_DIR/tdd/SKILL.md"
if run_sync check >/dev/null 2>&1; then
  printf '%s\n' 'legacy ~/.codex/skills entry unexpectedly passed check' >&2
  exit 1
fi
rm -rf "$LEGACY_INSTALL_DIR/tdd"
run_sync check

# Read-only validation must reject a company installation whose explicit Codex
# UI metadata is later removed or damaged.
cp "$INSTALL_DIR/company-code-review/agents/openai.yaml" \
  "$TEST_ROOT/company-code-review-openai.yaml"
rm "$INSTALL_DIR/company-code-review/agents/openai.yaml"
if run_sync check >/dev/null 2>&1; then
  printf '%s\n' 'company Skill without explicit UI metadata unexpectedly passed check' >&2
  exit 1
fi
mkdir -p "$INSTALL_DIR/company-code-review/agents"
cp "$TEST_ROOT/company-code-review-openai.yaml" \
  "$INSTALL_DIR/company-code-review/agents/openai.yaml"
run_sync check

printf '%s\n' preserve-on-failure > "$INSTALL_DIR/company-code-review/failure-marker"
printf "%s\n" "SOURCE_URL='$TEST_ROOT/missing-company'" "SOURCE_REQUIRED='false'" \
  > "$MANAGER/sources/company/source.conf"
run_sync sync >/dev/null 2>&1
[[ -f "$INSTALL_DIR/company-code-review/failure-marker" ]]
run_sync check

# A fresh machine with no previous company installation must still install and
# validate every required/native source when the optional company clone fails.
find "$INSTALL_DIR" -mindepth 1 -maxdepth 1 -type d -name 'company-*' -exec rm -rf {} +
run_sync sync >/dev/null 2>&1
[[ -z $(find "$INSTALL_DIR" -mindepth 1 -maxdepth 1 -type d -name 'company-*' -print -quit) ]]
[[ -d "$INSTALL_DIR/matt-grill-with-docs" ]]
[[ -d "$INSTALL_DIR/kkkkhazix-human-writing" ]]
[[ -d "$INSTALL_DIR/agents365-drawio-skill" ]]
[[ -d "$INSTALL_DIR/native-example" ]]
run_sync check

# SOURCE_REQUIRED=false only tolerates a repository clone failure. Once the
# company repository is fetched, malformed source content must still abort the
# transaction instead of silently keeping stale Skills.
broken_company_repo="$REPOSITORIES/broken-company"
mkdir -p "$broken_company_repo"
printf '%s\n' 'missing required skills directory' > "$broken_company_repo/README.md"
commit_repository "$broken_company_repo"
printf "%s\n" "SOURCE_URL='$broken_company_repo'" "SOURCE_REQUIRED='false'" \
  > "$MANAGER/sources/company/source.conf"
printf '%s\n' preserve-malformed-company > "$INSTALL_DIR/matt-grill-with-docs/company-failure-marker"
if run_sync sync >/dev/null 2>&1; then
  printf '%s\n' 'malformed optional source unexpectedly succeeded after clone' >&2
  exit 1
fi
[[ -f "$INSTALL_DIR/matt-grill-with-docs/company-failure-marker" ]]

# Other sources remain required. Their failure must abort the transaction and
# preserve the complete installation that existed before the failed sync.
printf '%s\n' preserve-required-failure > "$INSTALL_DIR/matt-grill-with-docs/failure-marker"
printf "%s\n" "SOURCE_URL='$TEST_ROOT/missing-matt'" "SOURCE_REQUIRED='true'" \
  > "$MANAGER/sources/matt/source.conf"
if run_sync sync >/dev/null 2>&1; then
  printf '%s\n' 'required source failure unexpectedly succeeded' >&2
  exit 1
fi
[[ -f "$INSTALL_DIR/matt-grill-with-docs/failure-marker" ]]

printf '%s\n' 'agent-skills sync tests passed'
