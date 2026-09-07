setup_local_skills_fixture() {
  PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  SKILL_SOURCE="$BATS_TEST_TMPDIR/source"
  SKILL_HOME="$BATS_TEST_TMPDIR/home"
  SKILL_CONFIG="$BATS_TEST_TMPDIR/chezmoi.yaml"
  mkdir -p "$SKILL_SOURCE" "$SKILL_HOME"
  printf '{}\n' >"$SKILL_CONFIG"
  cp "$PROJECT_ROOT"/run_onchange_{before_remove-orphan-claude-skills,after_apm-install,after_deploy-local-skills}.sh.tmpl "$SKILL_SOURCE/"
  cp -a "$PROJECT_ROOT/local-skills" "$SKILL_SOURCE/"
  local dir
  for dir in .chezmoitemplates .chezmoidata; do
    if [ -d "$PROJECT_ROOT/$dir" ]; then
      cp -a "$PROJECT_ROOT/$dir" "$SKILL_SOURCE/"
    fi
  done
  cp "$PROJECT_ROOT/apm.lock.yaml" "$PROJECT_ROOT/apm.yml" "$SKILL_SOURCE/"
  printf 'local-skills\nlocal-skills/**\n' >"$SKILL_SOURCE/.chezmoiignore"
  export HOME="$SKILL_HOME"
  export XDG_CONFIG_HOME="$BATS_TEST_TMPDIR/config"
  export XDG_DATA_HOME="$BATS_TEST_TMPDIR/data"
  export XDG_CACHE_HOME="$BATS_TEST_TMPDIR/cache"
  export XDG_STATE_HOME="$BATS_TEST_TMPDIR/state"
  unset CODEX_HOME CHEZMOI_SOURCE_DIR
}

skill_chezmoi() {
  chezmoi --source "$SKILL_SOURCE" --destination "$SKILL_HOME" \
    --config "$SKILL_CONFIG" --persistent-state "$BATS_TEST_TMPDIR/chezmoi-state.boltdb" \
    --cache "$BATS_TEST_TMPDIR/chezmoi-cache" "$@"
}

run_skill_phase() {
  local phase="$1"
  local script="$BATS_TEST_TMPDIR/$phase.sh"
  skill_chezmoi execute-template --file "$SKILL_SOURCE/run_onchange_$phase.sh.tmpl" >"$script" || return
  CHEZMOI_SOURCE_DIR="$SKILL_SOURCE" bash "$script"
}

add_local_skill() {
  mkdir -p "$SKILL_SOURCE/local-skills/$1"
  printf -- '---\nname: %s\ndescription: Test skill\n---\n%s\n' "$1" "${2:-payload}" \
    >"$SKILL_SOURCE/local-skills/$1/SKILL.md"
}

setup_skill_apply() {
  mkdir -p "$SKILL_HOME/.config/nix-devshell/lib" "$BATS_TEST_TMPDIR/bin"
  printf 'refresh_nix_devshell_cache() { return 0; }\n' >"$SKILL_HOME/.config/nix-devshell/lib/refresh-cache.sh"
  printf 'ensure_nix_devshell_env() { return 0; }\n' >"$SKILL_HOME/.config/nix-devshell/lib/ensure-env.sh"
  export SKILL_APM_LOG="$BATS_TEST_TMPDIR/apm.log"
  : >"$SKILL_APM_LOG"
  cat >"$BATS_TEST_TMPDIR/bin/apm" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >>"$SKILL_APM_LOG"
if [ "$1" = install ]; then
  [ ! -e "$HOME/.claude/skills/orphan" ]
  mkdir -p "$HOME/.claude/skills/pdf"
  printf 'APM payload\n' >"$HOME/.claude/skills/pdf/SKILL.md"
fi
EOF
  chmod +x "$BATS_TEST_TMPDIR/bin/apm"
  export PATH="$BATS_TEST_TMPDIR/bin:$PATH"
}
