#!/usr/bin/env bash
set -euo pipefail

usage() {
  printf 'Usage: %s --source SOURCE_DIR [--candidate-manifest MANIFEST]\n' "$0" >&2
}

SOURCE_DIR=
CANDIDATE_MANIFEST=
while (($# > 0)); do
  case "$1" in
  --source)
    [[ $# -ge 2 ]] || {
      usage
      exit 2
    }
    SOURCE_DIR=$2
    shift 2
    ;;
  --candidate-manifest)
    [[ $# -ge 2 ]] || {
      usage
      exit 2
    }
    CANDIDATE_MANIFEST=$2
    shift 2
    ;;
  -h | --help)
    usage
    exit 0
    ;;
  *)
    usage
    exit 2
    ;;
  esac
done

[[ -n "$SOURCE_DIR" ]] || {
  usage
  exit 2
}
SOURCE_DIR=$(cd -- "$SOURCE_DIR" && pwd)
CANDIDATE_MANIFEST=${CANDIDATE_MANIFEST:-$SOURCE_DIR/apm.yml}
ORIGINAL_HOME=${HOME:-}
ORIGINAL_PLAYWRIGHT_BROWSERS_PATH=${PLAYWRIGHT_BROWSERS_PATH:-}
ORIGINAL_PLAYWRIGHT_BROWSERS_PATH_SET=${PLAYWRIGHT_BROWSERS_PATH+x}

SOURCE_LOCK="$SOURCE_DIR/apm.lock.yaml"
CLEANUP_SCRIPT="$SOURCE_DIR/run_onchange_before_remove-orphan-claude-skills.sh.tmpl"
for required in "$SOURCE_DIR/apm.yml" "$SOURCE_LOCK" "$CLEANUP_SCRIPT" "$CANDIDATE_MANIFEST"; do
  [[ -f "$required" ]] || {
    printf 'REJECT: required file is missing: %s\n' "$required" >&2
    exit 1
  }
done

reject() {
  printf 'REJECT: %s\n' "$*" >&2
  exit 1
}

matt_lines=()
while IFS= read -r matt_line; do
  matt_lines+=("$matt_line")
done < <(grep -E '^[[:space:]]*-[[:space:]]+mattpocock/skills([#/]|[[:space:]]*$)' "$CANDIDATE_MANIFEST" || true)
[[ ${#matt_lines[@]} -eq 1 ]] || reject "candidate must contain exactly one Matt Pocock collection dependency"

candidate_matt_spec=$(sed -E 's/^[[:space:]]*-[[:space:]]*//' <<<"${matt_lines[0]}")
[[ "$candidate_matt_spec" =~ ^mattpocock/skills#([[:xdigit:]]{40})$ ]] ||
  reject "candidate must pin mattpocock/skills to one exact 40-hex commit"
CANDIDATE_REVISION=${BASH_REMATCH[1]}

normalize_manifest() {
  awk '!/^[[:space:]]*-[[:space:]]+mattpocock\/skills([#\/]|$)/' "$1"
}

cmp <(normalize_manifest "$SOURCE_DIR/apm.yml") <(normalize_manifest "$CANDIDATE_MANIFEST") ||
  reject "candidate changes dependencies outside mattpocock/skills"

native_managed_route_present() {
  local root file compact
  for root in "$SOURCE_DIR/private_dot_claude" "$SOURCE_DIR/private_dot_config"; do
    [[ -d "$root" ]] || continue
    while IFS= read -r file; do
      compact=$(tr -d '[:space:]' <"$file")
      if grep -Eiq 'npxskills|enabledPlugins.*mattpocock|mattpocock.*enabledPlugins' <<<"$compact"; then
        return 0
      fi
    done < <(find "$root" -type f -print)
  done
  return 1
}

if native_managed_route_present; then
  reject "native Claude plugin or universal npx skills route is enabled"
fi

lock_pin_for() {
  local dependency=$1
  awk -v target="$dependency" '
    function flush() {
      if (repo != "" && virtual != "" &&
          (repo "/" virtual == target || materialization_repo "/" virtual == target)) print commit
    }
    /^- repo_url: / {
      flush()
      repo = $0
      sub(/^- repo_url: /, "", repo)
      materialization_repo = ""
      virtual = ""
      commit = ""
      next
    }
    /^  materialization_repo_url: / { materialization_repo = $2; next }
    /^  virtual_path: / { virtual = $2; next }
    /^  resolved_commit: / { commit = $2; next }
    END { flush() }
  ' "$SOURCE_LOCK"
}

pin_baseline_dependencies() {
  local line dependency pin prefix
  local in_apm=0

  while IFS= read -r line || [[ -n "$line" ]]; do
    [[ "$line" == "  apm:" ]] && in_apm=1
    if ((in_apm)) && [[ "$line" =~ ^[[:space:]]{4}-[[:space:]]+([^#[:space:]]+)(#[^[:space:]]+)?[[:space:]]*$ ]]; then
      dependency=${BASH_REMATCH[1]}
      if [[ -n "${BASH_REMATCH[2]:-}" || "$dependency" == mattpocock/skills ]]; then
        printf '%s\n' "$line"
        continue
      fi

      pin=$(lock_pin_for "$dependency")
      [[ "$pin" =~ ^[[:xdigit:]]{40}$ ]] ||
        reject "accepted lock has no exact pin for non-candidate dependency: $dependency"
      prefix=${line%"$dependency"}
      printf '%s%s#%s\n' "$prefix" "$dependency" "$pin"
      continue
    fi
    printf '%s\n' "$line"
  done <"$CANDIDATE_MANIFEST"
}

normalize_lock() {
  awk '
    /^generated_at:/ { next }
    /^  resolved_ref:/ { next }
    /^- repo_url: mattpocock\/skills$/ { skip = 1; next }
    skip && /^- repo_url:/ { skip = 0 }
    !skip { print }
  ' "$1"
}

validate_lock_refs() {
  awk '
    /^  resolved_commit: / { commit = $2; next }
    /^  resolved_ref: / && $2 != commit {
      printf "resolved_ref differs from resolved_commit: %s != %s\n", $2, commit > "/dev/stderr"
      invalid = 1
    }
    END { exit invalid }
  ' "$1"
}

lock_managed_skills() {
  local path=$1
  awk -v path="$path" '
    /^- repo_url: mattpocock\/skills$/ { active = 1; next }
    active && /^- repo_url:/ { exit }
    active && $0 ~ "^  - " path "/[^/]+$" {
      skill = $0
      sub("^  - " path "/", "", skill)
      print skill
    }
  ' "$2" | sort
}

lock_target_skills() {
  local path=$1
  awk -v path="$path" '
    {
      prefix = "  - " path "/"
      if (index($0, prefix) == 1) {
        skill = substr($0, length(prefix) + 1)
        if (skill !~ /\//) print skill
      }
    }
  ' "$2" | sort -u
}

cleanup_managed_skills() {
  awk '
    /^managed_apm_skills=\(/ { active = 1; next }
    active && /^\)/ { exit }
    active && /^  [a-z0-9-]+$/ { print $1 }
  ' "$1" | sort
}

official_matt_skills() {
  printf '%s\n' \
    ask-matt \
    code-review \
    codebase-design \
    diagnosing-bugs \
    domain-modeling \
    grill-me \
    grill-with-docs \
    grilling \
    handoff \
    implement \
    improve-codebase-architecture \
    prototype \
    research \
    resolving-merge-conflicts \
    setup-matt-pocock-skills \
    tdd \
    teach \
    to-questionnaire \
    to-spec \
    to-tickets \
    triage \
    wait-what \
    wayfinder \
    wizard \
    writing-for-agents
}

sha256_file() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | awk '{print $1}'
  elif command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$1" | awk '{print $1}'
  else
    reject "sha256sum or shasum is required"
  fi
}

list_installed_skills() {
  local root=$1 skill_path
  local -a skill_paths=("$root"/*)
  for skill_path in "${skill_paths[@]}"; do
    [[ -d "$skill_path" || -L "$skill_path" ]] || continue
    [[ -f "$skill_path/SKILL.md" ]] || return 1
  done
  for skill_path in "${skill_paths[@]}"; do
    [[ -d "$skill_path" || -L "$skill_path" ]] || continue
    basename "$skill_path"
  done | sort
}

discover_skills() {
  local root=$1 expected=$2 skill_file line has_name has_description closed
  local -a skill_files=("$root"/*/SKILL.md)
  for skill_file in "${skill_files[@]}"; do
    [[ -f "$skill_file" ]] || continue
    has_name=0
    has_description=0
    closed=0
    while IFS= read -r line || [[ -n "$line" ]]; do
      if [[ -z "${frontmatter_open:-}" ]]; then
        [[ "$line" == '---' ]] || return 1
        frontmatter_open=1
        continue
      fi
      if [[ "$line" == '---' ]]; then
        closed=1
        break
      fi
      [[ "$line" =~ ^name:[[:space:]]+ ]] && has_name=1
      [[ "$line" =~ ^description: ]] && has_description=1
    done <"$skill_file"
    unset frontmatter_open
    ((closed == 1 && has_name == 1 && has_description == 1)) || return 1
  done
  while IFS= read -r skill; do
    [[ -n "$skill" ]] || continue
    skill_file="$root/$skill/SKILL.md"
    [[ -f "$skill_file" ]] || return 1
  done <"$expected"
  for skill_file in "${skill_files[@]}"; do
    [[ -f "$skill_file" ]] || continue
    basename "$(dirname "$skill_file")"
  done | sort
}

snapshot_home_paths() {
  local path relative
  while IFS= read -r path; do
    if [[ "$path" == "$HOME" ]]; then
      relative=.
    else
      relative=${path#"$HOME"/}
    fi
    if [[ -L "$path" ]]; then
      printf 'symlink\t%s\t%s\n' "$relative" "$(readlink "$path")"
    elif [[ -f "$path" ]]; then
      printf 'file\t%s\t%s\n' "$relative" "$(sha256_file "$path")"
    elif [[ -d "$path" ]]; then
      printf 'directory\t%s\n' "$relative"
    else
      printf 'other\t%s\n' "$relative"
    fi
  done < <(find "$HOME" -print | sort)
}

runtime=$(mktemp -d "${TMPDIR:-/tmp}/mattpocock-update-gate.XXXXXX")
phase_log=${MATTPOCOCK_GATE_LOG:-$runtime/gate.log}
mkdir -p "$(dirname "$phase_log")"
: >"$phase_log"

cleanup_runtime() {
  if [[ -n "${MATTPOCOCK_GATE_KEEP_RUNTIME:-}" ]]; then
    printf 'Runtime retained at %s\n' "$runtime" >&2
  else
    rm -rf "$runtime"
  fi
}
trap cleanup_runtime EXIT

mkdir -p "$runtime/home" "$runtime/config" "$runtime/data"
cp "$SOURCE_LOCK" "$runtime/apm.lock.yaml"
pin_baseline_dependencies >"$runtime/apm.yml"

export HOME="$runtime/home"
export XDG_CONFIG_HOME="$runtime/config"
export XDG_DATA_HOME="$runtime/data"
export MATTPOCOCK_GATE_SOURCE_DIR="$SOURCE_DIR"
unset CODEX_HOME CLAUDE_CONFIG_DIR
cd -- "$runtime"

record_phase() {
  printf '%s\n' "$1" >>"$phase_log"
}

record_phase lock-generation
apm install --update --target claude,codex --https
validate_lock_refs "$runtime/apm.lock.yaml" || reject "generated lock contains a ref different from its resolved commit"
cmp <(normalize_lock "$SOURCE_LOCK") <(normalize_lock "$runtime/apm.lock.yaml") ||
  reject "lock generation changed non-Matt dependency fields"

matt_lock_revision=$(awk '
  /^- repo_url: mattpocock\/skills$/ { active = 1; next }
  active && /^- repo_url:/ { exit }
  active && /^  resolved_commit: / { print $2; exit }
' "$runtime/apm.lock.yaml")
[[ "$matt_lock_revision" == "$CANDIDATE_REVISION" ]] ||
  reject "generated lock does not resolve the candidate Matt revision"

lock_before=$(sha256_file "$runtime/apm.lock.yaml")
record_phase frozen-install
apm install --frozen --target claude,codex --https
lock_after=$(sha256_file "$runtime/apm.lock.yaml")
[[ "$lock_before" == "$lock_after" ]] || reject "frozen install rewrote apm.lock.yaml"

record_phase audit
apm audit --ci

record_phase skill-discovery
expected_managed_agents=$(mktemp "$runtime/expected-managed-agents.XXXXXX")
expected_managed_claude=$(mktemp "$runtime/expected-managed-claude.XXXXXX")
expected_official_matt=$(mktemp "$runtime/expected-official-matt.XXXXXX")
expected_target_agents=$(mktemp "$runtime/expected-target-agents.XXXXXX")
expected_target_claude=$(mktemp "$runtime/expected-target-claude.XXXXXX")
lock_managed_skills '.agents/skills' "$runtime/apm.lock.yaml" >"$expected_managed_agents"
lock_managed_skills '.claude/skills' "$runtime/apm.lock.yaml" >"$expected_managed_claude"
official_matt_skills >"$expected_official_matt"
lock_target_skills '.agents/skills' "$runtime/apm.lock.yaml" >"$expected_target_agents"
lock_target_skills '.claude/skills' "$runtime/apm.lock.yaml" >"$expected_target_claude"
cmp "$expected_official_matt" "$expected_managed_agents" || {
  diff -u "$expected_official_matt" "$expected_managed_agents" >&2 || true
  reject "candidate does not contain the exact official Matt Pocock v1.2.3 full set"
}
cmp "$expected_official_matt" "$expected_managed_claude" ||
  reject "Claude lock target does not contain the exact official Matt full set"
cmp "$expected_managed_agents" "$expected_managed_claude" ||
  reject "lock targets do not expose the same managed full set"
cmp "$expected_target_agents" "$expected_target_claude" ||
  reject "lock targets do not expose the same complete skill set"

actual_agents=$(mktemp "$runtime/actual-agents.XXXXXX")
actual_claude=$(mktemp "$runtime/actual-claude.XXXXXX")
discovered_agents=$(mktemp "$runtime/discovered-agents.XXXXXX")
discovered_claude=$(mktemp "$runtime/discovered-claude.XXXXXX")
for target in .agents/skills .claude/skills; do
  actual=$(mktemp "$runtime/actual-skills.XXXXXX")
  list_installed_skills "$runtime/$target" >"$actual" ||
    reject "discovery target contains a skill without SKILL.md: $target"
  if [[ "$target" == ".agents/skills" ]]; then
    cp "$actual" "$actual_agents"
  else
    cp "$actual" "$actual_claude"
  fi
done
cmp "$actual_agents" "$actual_claude" || {
  diff -u "$actual_agents" "$actual_claude" >&2 || true
  reject "Claude and Codex discovery targets differ"
}
cmp "$expected_target_agents" "$actual_agents" || {
  diff -u "$expected_target_agents" "$actual_agents" >&2 || true
  reject "discovery does not expose exactly the generated lock target set"
}
discover_skills "$runtime/.agents/skills" "$expected_target_agents" >"$discovered_agents" ||
  reject "Codex discovery target contains an invalid skill payload"
discover_skills "$runtime/.claude/skills" "$expected_target_claude" >"$discovered_claude" ||
  reject "Claude discovery target contains an invalid skill payload"
cmp "$actual_agents" "$discovered_agents" || reject "Codex discovery does not match deployed skill directories"
cmp "$actual_claude" "$discovered_claude" || reject "Claude discovery does not match deployed skill directories"

cleanup_skills=$(mktemp "$runtime/cleanup-skills.XXXXXX")
cleanup_managed_skills "$CLEANUP_SCRIPT" >"$cleanup_skills"
cmp "$expected_managed_agents" "$cleanup_skills" || reject "orphan cleanup does not own the generated full set"

record_phase workflow-contract-tests
bats \
  "$SOURCE_DIR/tests/apm-runtime.bats" \
  "$SOURCE_DIR/tests/run_onchange_before_remove-orphan-claude-skills.bats" \
  "$SOURCE_DIR/tests/workflow-contract.bats"
full_suite_home="$runtime/full-suite-home"
full_suite_config="$runtime/full-suite-config"
full_suite_data="$runtime/full-suite-data"
mkdir -p "$full_suite_home" "$full_suite_config" "$full_suite_data"
export HOME="$full_suite_home" XDG_CONFIG_HOME="$full_suite_config" XDG_DATA_HOME="$full_suite_data"
unset CODEX_HOME CLAUDE_CONFIG_DIR
if [[ -n "$ORIGINAL_PLAYWRIGHT_BROWSERS_PATH_SET" ]]; then
  export PLAYWRIGHT_BROWSERS_PATH="$ORIGINAL_PLAYWRIGHT_BROWSERS_PATH"
elif [[ -d "$ORIGINAL_HOME/.cache/ms-playwright" ]]; then
  export PLAYWRIGHT_BROWSERS_PATH="$ORIGINAL_HOME/.cache/ms-playwright"
else
  unset PLAYWRIGHT_BROWSERS_PATH
fi
bats "$SOURCE_DIR/tests"
export HOME="$runtime/home" XDG_CONFIG_HOME="$runtime/config" XDG_DATA_HOME="$runtime/data"
unset CODEX_HOME CLAUDE_CONFIG_DIR

printf 'unchanged\n' >"$HOME/.mattpocock-gate-sentinel"
ln -s "$HOME/.mattpocock-gate-sentinel" "$HOME/.mattpocock-gate-link"

record_phase chezmoi-dry-run
chezmoi --source "$SOURCE_DIR" init --no-tty --guess-repo-url=false
chezmoi_home_before=$(mktemp "$runtime/chezmoi-home-before.XXXXXX")
chezmoi_home_after=$(mktemp "$runtime/chezmoi-home-after.XXXXXX")
snapshot_home_paths >"$chezmoi_home_before"
chezmoi --source "$SOURCE_DIR" apply --dry-run --no-tty
snapshot_home_paths >"$chezmoi_home_after"
cmp "$chezmoi_home_before" "$chezmoi_home_after" ||
  reject "chezmoi dry-run changed the isolated HOME"

expected_phases=$(printf '%s\n' \
  lock-generation frozen-install audit skill-discovery workflow-contract-tests chezmoi-dry-run)
[[ "$(cat "$phase_log")" == "$expected_phases" ]] || reject "verification phases ran out of order"

printf 'PASS: Matt Pocock managed-set update gate completed for %s\n' "$CANDIDATE_REVISION"
