#!/usr/bin/env bash

set -euo pipefail

ROOT=$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
TEST_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/agent-skills-test.XXXXXX")
trap 'rm -rf "$TEST_ROOT"' EXIT

TEST_HOME="$TEST_ROOT/home"
MANAGER="$TEST_ROOT/manager"
REPOSITORIES="$TEST_ROOT/repositories"
INSTALL_DIR="$TEST_HOME/.agents/skills"
mkdir -p "$MANAGER/sources" "$MANAGER/native" "$REPOSITORIES" "$INSTALL_DIR/old-skill"
cp "$ROOT/lib.sh" "$ROOT/sync.sh" "$MANAGER/"

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
  local name=$1 repository=$2
  mkdir -p "$MANAGER/sources/$name"
  cp "$ROOT/sources/$name/install.sh" "$MANAGER/sources/$name/install.sh"
  chmod +x "$MANAGER/sources/$name/install.sh"
  printf "SOURCE_URL='%s'\nSOURCE_REQUIRED='true'\n" "$repository" \
    > "$MANAGER/sources/$name/source.conf"
}

company_repo="$REPOSITORIES/company"
mkdir -p "$company_repo"
write_skill "$company_repo/skills/code-review" code-review 'Run /architect and $architect.'
write_skill "$company_repo/skills/architect" architect 'Architecture workflow.'
printf '%s\n' 'reference body' > "$company_repo/skills/code-review/reference.md"
ln -s reference.md "$company_repo/skills/code-review/reference-link.md"
commit_repository "$company_repo"

matt_repo="$REPOSITORIES/matt"
mkdir -p "$matt_repo"
write_skill "$matt_repo/skills/engineering/grill-with-docs" grill-with-docs \
  'Run /grilling with /domain-modeling.'
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

write_skill "$MANAGER/native/native-example" native-example 'Native workflow.'
printf '%s\n' stale > "$INSTALL_DIR/old-skill/SKILL.md"

configure_source company "$company_repo"
configure_source matt "$matt_repo"
configure_source kkkkhazix "$kkkkhazix_repo"
configure_source agents365 "$agents365_repo"

run_sync() {
  HOME=$TEST_HOME \
    AGENT_SKILLS_SOURCES_DIR="$MANAGER/sources" \
    AGENT_SKILLS_NATIVE_DIR="$MANAGER/native" \
    AGENT_SKILLS_INSTALL_DIR="$INSTALL_DIR" \
    bash "$MANAGER/sync.sh" "$@"
}

run_sync sync

[[ ! -e "$INSTALL_DIR/old-skill" ]]
[[ -d "$INSTALL_DIR/company-code-review" ]]
[[ -d "$INSTALL_DIR/company-architect" ]]
[[ -d "$INSTALL_DIR/matt-grill-with-docs" ]]
[[ -d "$INSTALL_DIR/matt-grilling" ]]
[[ ! -e "$INSTALL_DIR/matt-not-installed" ]]
[[ -d "$INSTALL_DIR/kkkkhazix-human-writing" ]]
[[ -d "$INSTALL_DIR/agents365-drawio-skill" ]]
[[ -d "$INSTALL_DIR/native-example" ]]
[[ $(find "$INSTALL_DIR" -mindepth 1 -maxdepth 1 -type d | wc -l | tr -d ' ') -eq 13 ]]
[[ -f "$INSTALL_DIR/company-code-review/reference-link.md" ]]
[[ ! -L "$INSTALL_DIR/company-code-review/reference-link.md" ]]
[[ -z $(find "$INSTALL_DIR" -type l -print -quit) ]]
grep -Fq 'name: company-code-review' "$INSTALL_DIR/company-code-review/SKILL.md"
grep -Fq '/company-architect' "$INSTALL_DIR/company-code-review/SKILL.md"
grep -Fq '$company-architect' "$INSTALL_DIR/company-code-review/SKILL.md"
grep -Fq 'name: matt-grill-with-docs' "$INSTALL_DIR/matt-grill-with-docs/SKILL.md"
grep -Fq '/matt-grilling' "$INSTALL_DIR/matt-grill-with-docs/SKILL.md"
grep -Fq '/matt-domain-modeling' "$INSTALL_DIR/matt-grill-with-docs/SKILL.md"
grep -Fq 'name: kkkkhazix-human-writing' "$INSTALL_DIR/kkkkhazix-human-writing/SKILL.md"
grep -Fq 'name: agents365-drawio-skill' "$INSTALL_DIR/agents365-drawio-skill/SKILL.md"
[[ -z $(find "$TEST_HOME/.agents" -mindepth 1 -maxdepth 1 -name '.skills-sync.*' -print -quit) ]]

run_sync check

printf '%s\n' preserve-on-failure > "$INSTALL_DIR/company-code-review/failure-marker"
printf "%s\n" "SOURCE_URL='$TEST_ROOT/missing-company'" "SOURCE_REQUIRED='true'" \
  > "$MANAGER/sources/company/source.conf"
if run_sync sync >/dev/null 2>&1; then
  printf '%s\n' 'required source failure unexpectedly succeeded' >&2
  exit 1
fi
[[ -f "$INSTALL_DIR/company-code-review/failure-marker" ]]

printf '%s\n' 'agent-skills sync tests passed'
