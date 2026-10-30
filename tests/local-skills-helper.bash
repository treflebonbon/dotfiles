setup_local_skills_fixture() {
  PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  SKILL_SOURCE="$BATS_TEST_TMPDIR/source"
  SKILL_HOME="$BATS_TEST_TMPDIR/home"
  SKILL_CONFIG="$BATS_TEST_TMPDIR/chezmoi.yaml"
  mkdir -p "$SKILL_SOURCE" "$SKILL_HOME"
  printf '{}\n' >"$SKILL_CONFIG"
  cp "$PROJECT_ROOT"/run_onchange_{before_remove-orphan-claude-skills,after_apm-install,after_codex-managed-sync}.sh.tmpl "$SKILL_SOURCE/"
  mkdir -p "$SKILL_SOURCE/private_dot_local/bin"
  cp "$PROJECT_ROOT"/private_dot_local/bin/executable_{git-push-topic,git-push-reviewed,gh-review-thread,orca-send,codex-reviewer}.tmpl \
    "$SKILL_SOURCE/private_dot_local/bin/"
  local dir
  for dir in .chezmoitemplates .chezmoidata; do
    if [ -d "$PROJECT_ROOT/$dir" ]; then
      cp -a "$PROJECT_ROOT/$dir" "$SKILL_SOURCE/"
    fi
  done
  mkdir -p "$SKILL_SOURCE/private_dot_config/nix-devshell"
  cp "$PROJECT_ROOT/private_dot_config/nix-devshell/skills-plugin.json" \
    "$SKILL_SOURCE/private_dot_config/nix-devshell/"
  for dir in private_dot_config/codex private_dot_local/bin; do
    mkdir -p "$SKILL_SOURCE/$dir"
  done
  cp "$PROJECT_ROOT/private_dot_config/codex/config.toml.tmpl" \
    "$PROJECT_ROOT/private_dot_config/codex/AGENTS.md" \
    "$PROJECT_ROOT/private_dot_config/codex/hooks.json" \
    "$SKILL_SOURCE/private_dot_config/codex/"
  mkdir -p "$SKILL_SOURCE/private_dot_config/codex/environments" \
    "$SKILL_SOURCE/private_dot_config/codex/rules"
  cp "$PROJECT_ROOT/private_dot_config/codex/environments/environment.toml" \
    "$SKILL_SOURCE/private_dot_config/codex/environments/"
  cp "$PROJECT_ROOT/private_dot_config/codex/rules/default.rules" \
    "$SKILL_SOURCE/private_dot_config/codex/rules/"
  cp "$PROJECT_ROOT/private_dot_local/bin/executable_sync-codex-managed-config" \
    "$PROJECT_ROOT/private_dot_local/bin/executable_sync-skills-plugin" \
    "$SKILL_SOURCE/private_dot_local/bin/"
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

run_skill_retirement() {
  run_skill_phase after_codex-managed-sync
}

setup_retirement_verifier_mocks() {
  RETIREMENT_SOURCE="$BATS_TEST_TMPDIR/plugin-source"
  PLUGIN_VERIFICATION="$BATS_TEST_TMPDIR/plugin-verification.json"
  MANAGED_VERIFICATION="$BATS_TEST_TMPDIR/managed-verification.json"
  SYNC_LOG="$BATS_TEST_TMPDIR/sync.log"
  mkdir -p \
    "$RETIREMENT_SOURCE/bin" \
    "$RETIREMENT_SOURCE/lib/python/treflebonbon_skills" \
    "$SKILL_HOME/.codex" \
    "$BATS_TEST_TMPDIR/custom-codex" \
    "$BATS_TEST_TMPDIR/bin"
  local name
  for name in git-push-topic git-push-reviewed gh-review-thread orca-send codex-reviewer; do
    printf '#!/usr/bin/env bash\nexit 0\n' >"$RETIREMENT_SOURCE/bin/$name"
    chmod 755 "$RETIREMENT_SOURCE/bin/$name"
  done
  printf 'verified module\n' >"$RETIREMENT_SOURCE/lib/python/treflebonbon_skills/devshell_environment.py"
  chmod 644 "$RETIREMENT_SOURCE/lib/python/treflebonbon_skills/devshell_environment.py"
  export CODEX_HOME="$BATS_TEST_TMPDIR/custom-codex"
  python3 - "$PROJECT_ROOT/private_dot_config/nix-devshell/skills-plugin.json" \
    "$RETIREMENT_SOURCE" "$SKILL_HOME/.codex" "$CODEX_HOME" \
    >"$PLUGIN_VERIFICATION" <<'PY'
import json
import sys
from pathlib import Path

pin = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
source = Path(sys.argv[2]).resolve()
homes = [str(Path(path).resolve()) for path in sys.argv[3:]]
print(json.dumps({"status": "verified", "pin": pin, "source": str(source), "checkout": str(source.parent), "codex_homes": homes}))
PY
  python3 - "$PROJECT_ROOT/private_dot_config/nix-devshell/skills-plugin.json" \
    "$SKILL_HOME/.codex" "$CODEX_HOME" >"$MANAGED_VERIFICATION" <<'PY'
import json
import sys
from pathlib import Path

pin = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
homes = [str(Path(path).resolve()) for path in sys.argv[2:]]
records = [
    {"codex_home": home, "install_path": f"{home}/plugins/cache/treflebonbon/treflebonbon-skills/{pin['version']}",
     "profiles": [{"profile": "dotfiles-secure"}, {"profile": "dotfiles-peer"}]}
    for home in homes
]
print(json.dumps({"status": "verified", "pin": pin, "codex_homes": homes, "results": {"codex": records}}))
PY
  cat >"$BATS_TEST_TMPDIR/bin/sync-codex-managed-config" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
if [ "${1:-}" = "--verify-only" ]; then
  printf 'codex:verify-only\n' >>"$SYNC_LOG"
  if [ "${VERIFY_CODEX_FAIL:-0}" = 1 ]; then
    echo 'verification failed' >&2
    exit 1
  fi
  cat "$MANAGED_VERIFICATION"
else
  printf 'codex:sync\n' >>"$SYNC_LOG"
fi
SH
  cat >"$BATS_TEST_TMPDIR/bin/sync-skills-plugin" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
[ "${1:-}" = "--verify-only" ] || exit 2
printf 'plugin:verify-only\n' >>"$SYNC_LOG"
if [ "${VERIFY_PLUGIN_FAIL:-0}" = 1 ]; then
  echo 'verification failed' >&2
  exit 1
fi
cat "$PLUGIN_VERIFICATION"
SH
  chmod 755 "$BATS_TEST_TMPDIR/bin/sync-codex-managed-config" \
    "$BATS_TEST_TMPDIR/bin/sync-skills-plugin"
  export SYNC_LOG PLUGIN_VERIFICATION MANAGED_VERIFICATION
  export CODEX_MANAGED_CONFIG_SYNC="$BATS_TEST_TMPDIR/bin/sync-codex-managed-config"
  export SKILLS_PLUGIN_SYNC="$BATS_TEST_TMPDIR/bin/sync-skills-plugin"
  : >"$SYNC_LOG"
}

global_cli_source_body() {
  local name="$1"
  sed '1d' "$PROJECT_ROOT/private_dot_local/bin/executable_${name}.tmpl"
}

mock_global_cli_dispatcher() {
  local home="$1"
  mkdir -p "$home/.local/bin"
  cat >"$home/.local/bin/sync-skills-plugin" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$@" >"$DISPATCH_LOG"
SH
  chmod +x "$home/.local/bin/sync-skills-plugin"
}

assert_global_cli_dispatch() {
  local name="$1" log="$2"
  run env HOME="$SKILL_HOME" DISPATCH_LOG="$log" \
    "$SKILL_HOME/.local/bin/$name" --probe
  [ "$status" -eq 0 ]
  printf '%s\n' --run-cli "$name" -- --probe >"$BATS_TEST_TMPDIR/expected-dispatch.log"
  cmp "$BATS_TEST_TMPDIR/expected-dispatch.log" "$log"
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
  mkdir -p "$HOME/.claude/skills/pdf"
  printf 'APM payload\n' >"$HOME/.claude/skills/pdf/SKILL.md"
fi
EOF
  chmod +x "$BATS_TEST_TMPDIR/bin/apm"
  export PATH="$BATS_TEST_TMPDIR/bin:$PATH"
  setup_retirement_verifier_mocks
}
