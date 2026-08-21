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
ORIGINAL_XDG_CONFIG_HOME=${XDG_CONFIG_HOME:-}
ORIGINAL_XDG_CONFIG_HOME_SET=${XDG_CONFIG_HOME+x}
ORIGINAL_XDG_DATA_HOME=${XDG_DATA_HOME:-}
ORIGINAL_XDG_DATA_HOME_SET=${XDG_DATA_HOME+x}
ORIGINAL_CODEX_HOME=${CODEX_HOME:-}
ORIGINAL_CODEX_HOME_SET=${CODEX_HOME+x}
ORIGINAL_CLAUDE_CONFIG_DIR=${CLAUDE_CONFIG_DIR:-}
ORIGINAL_CLAUDE_CONFIG_DIR_SET=${CLAUDE_CONFIG_DIR+x}

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

cleanup_managed_skills() {
  awk '
    /^managed_apm_skills=\(/ { active = 1; next }
    active && /^\)/ { exit }
    active && /^  [a-z0-9-]+$/ { print $1 }
  ' "$1" | sort
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
    basename "$skill_path"
  done | sort
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
expected_agents=$(mktemp "$runtime/expected-agents.XXXXXX")
expected_claude=$(mktemp "$runtime/expected-claude.XXXXXX")
lock_managed_skills '.agents/skills' "$runtime/apm.lock.yaml" >"$expected_agents"
lock_managed_skills '.claude/skills' "$runtime/apm.lock.yaml" >"$expected_claude"
[[ $(wc -l <"$expected_agents") -eq 25 ]] || reject "generated lock does not contain 25 managed skills"
cmp "$expected_agents" "$expected_claude" || reject "lock targets do not expose the same managed full set"

actual_agents=$(mktemp "$runtime/actual-agents.XXXXXX")
actual_claude=$(mktemp "$runtime/actual-claude.XXXXXX")
for target in .agents/skills .claude/skills; do
  actual=$(mktemp "$runtime/actual-skills.XXXXXX")
  list_installed_skills "$runtime/$target" >"$actual"
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
missing_skills=$(comm -23 "$expected_agents" "$actual_agents")
if [[ -n "$missing_skills" ]]; then
  printf 'Missing managed Matt skills:\n%s\n' "$missing_skills" >&2
  reject "discovery is missing a managed Matt skill"
fi

cleanup_skills=$(mktemp "$runtime/cleanup-skills.XXXXXX")
cleanup_managed_skills "$CLEANUP_SCRIPT" >"$cleanup_skills"
cmp "$expected_agents" "$cleanup_skills" || reject "orphan cleanup does not own the generated full set"

record_phase workflow-contract-tests
bats \
  "$SOURCE_DIR/tests/apm-runtime.bats" \
  "$SOURCE_DIR/tests/run_onchange_before_remove-orphan-claude-skills.bats" \
  "$SOURCE_DIR/tests/workflow-contract.bats"
if [[ -z "${MATTPOCOCK_GATE_SKIP_FULL_TESTS:-}" ]]; then
  export HOME="$ORIGINAL_HOME"
  if [[ -n "$ORIGINAL_XDG_CONFIG_HOME_SET" ]]; then
    export XDG_CONFIG_HOME="$ORIGINAL_XDG_CONFIG_HOME"
  else
    unset XDG_CONFIG_HOME
  fi
  if [[ -n "$ORIGINAL_XDG_DATA_HOME_SET" ]]; then
    export XDG_DATA_HOME="$ORIGINAL_XDG_DATA_HOME"
  else
    unset XDG_DATA_HOME
  fi
  if [[ -n "$ORIGINAL_CODEX_HOME_SET" ]]; then
    export CODEX_HOME="$ORIGINAL_CODEX_HOME"
  else
    unset CODEX_HOME
  fi
  if [[ -n "$ORIGINAL_CLAUDE_CONFIG_DIR_SET" ]]; then
    export CLAUDE_CONFIG_DIR="$ORIGINAL_CLAUDE_CONFIG_DIR"
  else
    unset CLAUDE_CONFIG_DIR
  fi
  export MATTPOCOCK_GATE_RUNNING=1
  bats "$SOURCE_DIR/tests"
  unset MATTPOCOCK_GATE_RUNNING
  export HOME="$runtime/home" XDG_CONFIG_HOME="$runtime/config" XDG_DATA_HOME="$runtime/data"
  unset CODEX_HOME CLAUDE_CONFIG_DIR
fi

record_phase chezmoi-dry-run
chezmoi --source "$SOURCE_DIR" init --no-tty --guess-repo-url=false
chezmoi --source "$SOURCE_DIR" apply --dry-run --no-tty

expected_phases=$(printf '%s\n' \
  lock-generation frozen-install audit skill-discovery workflow-contract-tests chezmoi-dry-run)
[[ "$(cat "$phase_log")" == "$expected_phases" ]] || reject "verification phases ran out of order"

printf 'PASS: Matt Pocock managed-set update gate completed for %s\n' "$CANDIDATE_REVISION"
