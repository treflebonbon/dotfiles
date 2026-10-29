#!/usr/bin/env bats

bats_require_minimum_version 1.5.0
setup() {
  PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  export PROJECT_ROOT
  export CODEX_ORCA="$PROJECT_ROOT/private_dot_local/bin/executable_codex-orca"
  export CODEX_CONTEXT="$PROJECT_ROOT/private_dot_local/bin/executable_codex-context"
  export CODEX_WORKTREE="$BATS_TEST_TMPDIR/runtime-bin/codex-worktree"
  export CODEX_MANAGED_CONFIG_SYNC="$PROJECT_ROOT/private_dot_local/bin/executable_sync-codex-managed-config"
  CODEX_SOURCE_GIT_COMMON_DIR="$(git -C "$PROJECT_ROOT" rev-parse --path-format=absolute --git-common-dir)"
  export CODEX_SOURCE_GIT_COMMON_DIR
  mkdir -p "$BATS_TEST_TMPDIR/runtime-bin"
  cat >"$BATS_TEST_TMPDIR/runtime-bin/sync-skills-plugin" <<'PY'
#!/usr/bin/env python3
import json
import os
from pathlib import Path
import sys

args = sys.argv[1:]
Path(os.environ["SKILLS_PLUGIN_SYNC_LOG"]).write_text(json.dumps(args))
homes = []
index = 0
while index < len(args):
    if args[index] == "--codex-home" and index + 1 < len(args):
        homes.append(Path(args[index + 1]).expanduser().resolve())
        index += 2
    else:
        index += 1
if not homes:
    print("DISPATCHED")
    sys.exit(0)
pin_path = Path(os.environ["PROJECT_ROOT"]) / "private_dot_config/nix-devshell/skills-plugin.json"
version = json.loads(pin_path.read_text())["version"]
plugin_root = Path("plugins/cache/treflebonbon/treflebonbon-skills")
if "--verify-only" in args:
    if os.environ.get("SKILLS_PLUGIN_VERIFY_FAIL") == "1":
        sys.exit(1)
    records = []
    for home in homes:
        installed = home / plugin_root / version
        skill = installed / "skills/fixture/SKILL.md"
        if not skill.is_file() or skill.read_text() != "fixture cache\n":
            print(f"unverified fixture cache: {installed}", file=sys.stderr)
            sys.exit(1)
        records.append({
            "runtime": "codex", "codex_home": str(home), "version": version,
            "install_path": str(installed),
        })
    print(json.dumps({
        "status": "verified", "pin": {"version": version},
        "codex_homes": [str(home) for home in homes],
        "results": {"codex": records},
    }))
    sys.exit(0)
for home in homes:
    installed = home / plugin_root / version
    skill = installed / "skills/fixture/SKILL.md"
    reference = installed / "skills/fixture/references/usage.md"
    skill.parent.mkdir(parents=True, exist_ok=True)
    reference.parent.mkdir(parents=True, exist_ok=True)
    skill.write_text("fixture cache\n")
    reference.write_text("fixture reference\n")
PY
  chmod +x "$BATS_TEST_TMPDIR/runtime-bin/sync-skills-plugin"
  export SKILLS_PLUGIN_SYNC_LOG="$BATS_TEST_TMPDIR/skills-plugin-sync.log"
  export PATH="$BATS_TEST_TMPDIR/runtime-bin:$PATH"
  cp "$PROJECT_ROOT/private_dot_local/bin/executable_codex-worktree" "$CODEX_WORKTREE"
  ln -s "$PROJECT_ROOT/private_dot_local/bin/executable_devshell-env" "$BATS_TEST_TMPDIR/runtime-bin/devshell-env"
  export PATH="$BATS_TEST_TMPDIR/runtime-bin:$PATH"
  export XDG_STATE_HOME="$BATS_TEST_TMPDIR/state"
  # Skip the ponytail plugin-sync step by default: an explicitly empty source
  # short-circuits it before any `codex plugin ...` call. Without this, every
  # one of this file's ~16 other call sites of $CODEX_MANAGED_CONFIG_SYNC
  # would attempt a real network fetch now that the script performs this step
  # unconditionally, and even a local fixture would still persist marketplace
  # state back into config.toml as a side effect, which not every test wants.
  # The dedicated ponytail tests below opt back in locally.
  export PONYTAIL_MARKETPLACE_SOURCE=""
}

# A minimal local marketplace so sync-codex-managed-config's ponytail install
# step never touches the real network in tests. --ref only works for actual
# git remote sources, so this fixture is deliberately left unpinned; the
# production default (dietrichgebert/ponytail pinned to v4.9.0) is asserted
# separately by grepping the managed sync script's literal defaults.
create_ponytail_marketplace_fixture() {
  local root="$1"
  local version="${2:-0.0.0-fixture}"
  mkdir -p "$root/.codex-plugin" "$root/.claude-plugin" "$root/skills/ponytail"
  cat >"$root/.codex-plugin/plugin.json" <<EOF
{
  "name": "ponytail",
  "version": "$version",
  "skills": "./skills/"
}
EOF
  cat >"$root/.claude-plugin/marketplace.json" <<'EOF'
{
  "name": "ponytail",
  "owner": { "name": "test" },
  "plugins": [
    { "name": "ponytail", "description": "fixture", "source": "./" }
  ]
}
EOF
  cat >"$root/skills/ponytail/SKILL.md" <<'EOF'
---
name: ponytail
description: fixture skill
---

# Ponytail Fixture
EOF
  git -C "$root" init -q
  git -C "$root" add -A
  git -C "$root" -c user.email=test@example.com -c user.name=Test commit -qm init
}

install_codex_package_test_commands() {
  local bin="$1"
  mkdir -p "$bin"
  ln -s "$CODEX_CONTEXT" "$bin/codex-context"
  ln -s "$CODEX_ORCA" "$bin/codex-orca"
  cp "$CODEX_WORKTREE" "$bin/codex-worktree"
  cp "$BATS_TEST_TMPDIR/runtime-bin/sync-skills-plugin" "$bin/sync-skills-plugin"
  ln -s "$PROJECT_ROOT/private_dot_local/bin/executable_devshell-env" "$bin/devshell-env"
}

stage_codex_package_launcher() {
  local workspace="$1"
  local bin="$2"
  cp "$PROJECT_ROOT/package.json" "$workspace/package.json"
  cp "$PROJECT_ROOT/codex" "$workspace/codex"
  install_codex_package_test_commands "$bin"
}

install_codex_launch_sentinel() {
  local bin="$1"
  mkdir -p "$bin"
  cat >"$bin/codex" <<'EOF'
#!/usr/bin/env bash
touch "$CODEX_LAUNCHED"
EOF
  chmod +x "$bin/codex"
}

create_linked_worktree() {
  local repo="$1"
  local worktree="$2"
  local relative_paths="${3:-}"
  local worktree_args=()
  mkdir -p "$repo"
  git -C "$repo" init -q
  git -C "$repo" config user.email test@example.com
  git -C "$repo" config user.name Test
  printf 'base\n' >"$repo/base.txt"
  git -C "$repo" add base.txt
  git -C "$repo" commit -qm 'test: initialize repository'
  if [ "$relative_paths" = "relative" ]; then
    worktree_args+=(--relative-paths)
  fi
  git -C "$repo" worktree add "${worktree_args[@]}" -qb linked "$worktree"
}

assert_codex_worktree_rejects_boundary_argument() {
  local worktree="$1"
  local bin="$2"
  local launched="$3"
  shift 3

  run env PATH="$bin:$PATH" CODEX_LAUNCHED="$launched" bash -c \
    'cd "$1"; shift; adapter="$1"; shift; exec "$adapter" "$@"' \
    _ "$worktree" "$CODEX_WORKTREE" "$@"

  [ "$status" -ne 0 ]
  [ ! -e "$launched" ]
}

assert_codex_managed_values() {
  python3 - "$@" <<'PY'
import sys
import tomllib

for path in sys.argv[1:]:
    with open(path, "rb") as f:
        config = tomllib.load(f)

    assert config["model"] == "gpt-6.1-sol"
    assert config["model_reasoning_effort"] == "xhigh"
    assert config["model_reasoning_summary"] == "concise"
    assert config["model_verbosity"] == "medium"
    assert config["personality"] == "pragmatic"
    assert config["agents"] == {
        "default_subagent_model": "gpt-6-luna",
        "default_subagent_reasoning_effort": "xhigh",
        "max_concurrent_threads_per_session": 3,
    }
    assert "service_tier" not in config
    assert "developer_instructions" not in config
    assert config["features"]["network_proxy"] is True
    assert config["features"]["daemon_auto_start"] is False
    assert "context_management" not in config["features"]
    assert config["apps"]["github"]["default_tools_approval_mode"] == "approve"
    assert config["apps"]["github"]["destructive_enabled"] is False
    assert config["plugins"]["github@openai-curated"]["enabled"] is True
    assert config["plugins"]["chrome@openai-bundled"]["enabled"] is True
    assert config["plugins"]["ponytail@ponytail"]["enabled"] is True
PY
}

assert_dotfiles_permission_profile() {
  python3 - "$@" <<'PY'
import os
import json
import sys
import tomllib
from pathlib import Path

expected_domains = {
    "registry.npmjs.org": "allow",
    "**.github.com": "allow",
    "**.githubusercontent.com": "allow",
    "**.context7.com": "allow",
    "**.pypi.org": "allow",
    "files.pythonhosted.org": "allow",
    "**.python.org": "allow",
    "cache.nixos.org": "allow",
    "nodejs.org": "allow",
    "proxy.golang.org": "allow",
    "sum.golang.org": "allow",
    "**.crates.io": "allow",
    "static.rust-lang.org": "allow",
    "**.hex.pm": "allow",
    "cpan.metacpan.org": "allow",
}

for path in sys.argv[1:]:
    with open(path, "rb") as f:
        config = tomllib.load(f)

    assert "sandbox_mode" not in config
    assert "sandbox_workspace_write" not in config
    assert config["default_permissions"] == "dotfiles-secure"

    profile = config["permissions"]["dotfiles-secure"]
    assert profile["extends"] == ":workspace"
    assert profile["network"]["enabled"] is True
    assert profile["network"]["domains"] == expected_domains

    filesystem = profile["filesystem"]
    plugin_source = Path(config["marketplaces"]["treflebonbon"]["source"])
    plugin_pin = json.loads((Path(os.environ["PROJECT_ROOT"]) / "private_dot_config/nix-devshell/skills-plugin.json").read_text())
    plugin_home = plugin_source.parents[3]
    state_home = Path(os.environ["XDG_STATE_HOME"])
    legacy_revision = json.loads((Path(os.environ["PROJECT_ROOT"]) / ".chezmoitemplates/local-skills-legacy.json").read_text())["revision"]
    assert filesystem["~/.config/nix-devshell/skills-plugin.json"] == "read"
    assert filesystem[str(plugin_source)] == "read"
    assert filesystem[str(plugin_source.parents[1] / "checkouts" / plugin_pin["rev"])] == "read"
    assert filesystem[str(state_home / "treflebonbon-skills/plugin-sync/receipt.json")] == "read"
    assert filesystem[str(state_home / "treflebonbon-skills/legacy" / legacy_revision)] == "read"
    assert str(state_home) not in filesystem
    assert str(state_home / "treflebonbon-skills") not in filesystem
    assert filesystem[":workspace_roots"]["."] == "write"
    assert ".git" not in filesystem[":workspace_roots"]
    assert os.environ["CODEX_SOURCE_GIT_COMMON_DIR"] not in filesystem
    assert filesystem[":root"] == "deny"
    assert filesystem[":minimal"] == "read"
    assert filesystem[":slash_tmp"] == "deny"
    assert filesystem["glob_scan_max_depth"] == 16
    assert filesystem["/tmp/codex"]["."] == "write"
    assert filesystem["/tmp/codex"]["**/.env"] == "deny"
    assert filesystem["/tmp/codex"]["**/*.key"] == "deny"
    assert filesystem["/tmp/codex"]["**/credentials.json"] == "deny"
    assert filesystem[":workspace_roots"][".env"] == "deny"
    assert filesystem[":workspace_roots"]["*/**/.env"] == "deny"
    assert filesystem[":workspace_roots"]["**/.env[!.r]*"] == "deny"
    assert filesystem[":workspace_roots"]["**/.envr"] == "deny"
    assert filesystem[":workspace_roots"]["**/.envr[!c]*"] == "deny"
    assert filesystem[":workspace_roots"]["**/.envrc?*"] == "deny"
    assert filesystem[":workspace_roots"]["**/.env.example?*"] == "deny"
    assert "**/.env*" not in filesystem[":workspace_roots"]
    assert "**/.envrc" not in filesystem[":workspace_roots"]
    assert "**/.env.example" not in filesystem[":workspace_roots"]
    assert "~/.ssh" not in filesystem
    assert "~/.aws" not in filesystem
    assert "~/.config/gcloud" not in filesystem
PY
}

prepare_codex_permission_roots() {
  local home="$1"
  local state_home="${XDG_STATE_HOME:-$home/.local/state}"
  local plugin_rev legacy_revision source_root legacy_root
  plugin_rev="$(jq -r '.rev' "$PROJECT_ROOT/private_dot_config/nix-devshell/skills-plugin.json")"
  legacy_revision="$(jq -r '.revision' "$PROJECT_ROOT/.chezmoitemplates/local-skills-legacy.json")"
  source_root="$home/.cache/treflebonbon-skills/marketplaces/$plugin_rev"
  legacy_root="$state_home/treflebonbon-skills/legacy/$legacy_revision"
  mkdir -p \
    "$home/.cache/treflebonbon-skills/checkouts/$plugin_rev" \
    "$source_root" \
    "$home/.config/nix-devshell" "$home/.config/gh" "$home/.config/git" \
    "$home/.local/bin" \
    "$state_home/treflebonbon-skills/plugin-sync" "$legacy_root"
  cp "$PROJECT_ROOT/private_dot_config/nix-devshell/skills-plugin.json" \
    "$home/.config/nix-devshell/skills-plugin.json"
  printf 'PUBLIC_SOURCE_READABLE\n' >"$source_root/README.md"
  printf '{"status":"verified"}\n' \
    >"$state_home/treflebonbon-skills/plugin-sync/receipt.json"
  printf '{"revision":"%s"}\n' "$legacy_revision" \
    >"$legacy_root/baseline.json"
  printf 'dummy-gh-config\n' >"$home/.config/gh/.env"
  printf 'dummy-git-config\n' >"$home/.config/git/.env"
  printf 'dummy-bin-entry\n' >"$home/.local/bin/.env"
  : >"$home/.gitconfig"
}

run_codex_with_virtual_home() {
  local home="$1"
  local workspace="$2"
  local codex bwrap store_path
  shift 2
  codex="$(command -v codex)"
  bwrap="$(command -v bwrap)"
  store_path="$(python3 -c 'import os; print(":".join(path for path in os.environ["PATH"].split(":") if path.startswith("/nix/store/")))')"
  run "$bwrap" \
    --unshare-all --die-with-parent --new-session \
    --tmpfs / --dev /dev --proc /proc \
    --dir /nix --dir /nix/store --ro-bind /nix/store /nix/store \
    --dir /tmp --dir /tmp/codex --bind /tmp/codex /tmp/codex \
    --dir /home --dir /home/probe --bind "$home" /home/probe \
    --setenv PATH "$store_path" \
    --setenv HOME /home/probe \
    --setenv CODEX_HOME /home/probe/.codex \
    --setenv XDG_CONFIG_HOME /home/probe/.config \
    --setenv XDG_CACHE_HOME /home/probe/.cache \
    --setenv XDG_DATA_HOME /home/probe/.local/share \
    --setenv XDG_STATE_HOME "$XDG_STATE_HOME" \
    --setenv TMPDIR /tmp \
    --chdir "$workspace" \
    "$codex" "$@"
}

stage_codex_managed_config() {
  local home="$1"
  prepare_codex_permission_roots "$home"
  mkdir -p "$home/.config/codex/environments" "$home/.config/codex/rules"
  render_codex_managed_config "$PROJECT_ROOT" "$home/.config/codex/config.toml" "$home"
  cp "$PROJECT_ROOT/private_dot_config/codex/hooks.json" "$home/.config/codex/hooks.json"
  cp "$PROJECT_ROOT/private_dot_config/codex/rules/default.rules" "$home/.config/codex/rules/default.rules"
  cp "$PROJECT_ROOT/private_dot_config/codex/environments/environment.toml" "$home/.config/codex/environments/environment.toml"
  cp "$PROJECT_ROOT/private_dot_config/codex/AGENTS.md" "$home/.config/codex/AGENTS.md"
}

omit_skills_marketplace_from_fixture() {
  local config="$1/.config/codex/config.toml"
  python3 - "$config" <<'PY'
import sys

path = sys.argv[1]
kept = []
skip = False
for line in open(path, encoding="utf-8"):
    if line.strip() == "[marketplaces.treflebonbon]":
        skip = True
        continue
    if skip and line.startswith("["):
        skip = False
    if not skip:
        kept.append(line)
with open(path, "w", encoding="utf-8") as stream:
    stream.writelines(kept)
PY
}

install_codex_managed_config_sync() {
  local home="$1"
  mkdir -p "$home/.local/bin"
  cp "$PROJECT_ROOT/private_dot_local/bin/executable_sync-codex-managed-config" \
    "$home/.local/bin/sync-codex-managed-config"
  chmod +x "$home/.local/bin/sync-codex-managed-config"
}

prepare_codex_chezmoi_source() {
  local source="$1"
  mkdir -p "$source/.chezmoitemplates" "$source/private_dot_config/nix-devshell" "$source/private_dot_config" "$source/private_dot_local/bin"
  cp "$PROJECT_ROOT/.chezmoitemplates/local-skills-legacy.json" \
    "$source/.chezmoitemplates/local-skills-legacy.json"
  cp -R "$PROJECT_ROOT/private_dot_config/codex" "$source/private_dot_config/codex"
  cp "$PROJECT_ROOT/private_dot_config/nix-devshell/skills-plugin.json" \
    "$source/private_dot_config/nix-devshell/skills-plugin.json"
  cp "$PROJECT_ROOT/private_dot_local/bin/executable_sync-codex-managed-config" \
    "$source/private_dot_local/bin/executable_sync-codex-managed-config"
  cat >"$source/private_dot_local/bin/executable_sync-skills-plugin" <<'SH'
#!/usr/bin/env bash
exit 0
SH
  chmod +x "$source/private_dot_local/bin/executable_sync-skills-plugin"
  cp "$PROJECT_ROOT/dot_bash_profile.tmpl" "$source/dot_bash_profile.tmpl"
  cp "$PROJECT_ROOT"/run_onchange_after_codex-*.sh.tmpl "$source/"
  git -C "$source" init -q
}

render_codex_managed_config() {
  local source="$1"
  local destination="$2"
  local home="${3:-$BATS_TEST_TMPDIR/chezmoi-render-home}"
  mkdir -p "$home"
  env HOME="$home" chezmoi --source "$source" --destination "$home" execute-template \
    -f "$PROJECT_ROOT/private_dot_config/codex/config.toml.tmpl" \
    >"$destination"
}

render_claude_settings() {
  local destination="$1"
  local home="$BATS_TEST_TMPDIR/claude-template-home"
  local config="$BATS_TEST_TMPDIR/claude-template-chezmoi.yaml"
  mkdir -p "$home"
  printf '{}\n' >"$config"
  env HOME="$home" chezmoi --source "$PROJECT_ROOT" --destination "$home" --config "$config" \
    execute-template <"$PROJECT_ROOT/private_dot_claude/settings.json.tmpl" >"$destination"
}

assert_codex_strict_config() {
  local codex_home="$1"

  run env HOME="$BATS_TEST_TMPDIR/strict-doctor-home" CODEX_HOME="$codex_home" TMPDIR=/tmp \
    codex --strict-config doctor --json

  if [[ "$output" != *'"config.toml parse": "ok"'* ]]; then
    printf 'Codex strict config check failed for %s:\n%s\n' "$codex_home" "$output" >&3
  fi
  [[ "$output" == *'"config.toml parse": "ok"'* ]]
}

@test "Codex config managed fragment exists without local state tables" {
  local config="$BATS_TEST_TMPDIR/config.toml"
  render_codex_managed_config "$PROJECT_ROOT" "$config"

  [ -f "$config" ]
  grep -q '^model = "gpt-6.1-sol"$' "$config"
  grep -q '^model_reasoning_effort = ' "$config"
  grep -q '^personality = ' "$config"
  grep -q '^approval_policy = "on-request"$' "$config"
  grep -q '^approvals_reviewer = "auto_review"$' "$config"
  grep -q '^\[apps\.github\]$' "$config"
  grep -q '^default_tools_approval_mode = "approve"$' "$config"
  grep -q '^destructive_enabled = false$' "$config"
  ! grep -q '^sandbox_mode = ' "$config"
  grep -q '^default_permissions = "dotfiles-secure"$' "$config"
  grep -q '^\[features\]' "$config"
  grep -q '^hooks = true$' "$config"
  grep -q '^goals = true$' "$config"
  grep -q '^network_proxy = true$' "$config"
  ! grep -q '^context_management' "$config"
  grep -q '^\[mcp_servers\.context7\]$' "$config"
  grep -q '^command = "bunx"$' "$config"
  grep -q '^args = \["-y", "@upstash/context7-mcp"\]$' "$config"
  grep -q '^\[mcp_servers\.serena\]$' "$config"
  grep -q '^command = "uvx"$' "$config"
  grep -q 'git+https://github.com/oraios/serena' "$config"
  grep -q '^\[permissions\."dotfiles-secure"\]$' "$config"
  grep -q '^extends = ":workspace"$' "$config"
  grep -q '^\[permissions\."dotfiles-secure"\.filesystem\]' "$config"
  grep -q '^\[permissions\."dotfiles-secure"\.filesystem\.":workspace_roots"\]$' "$config"
  grep -q '^"\.env" = "deny"$' "$config"
  grep -q '^"\*/\*\*/\.env" = "deny"$' "$config"
  grep -q '^"\*\*/\*\.pem" = "deny"$' "$config"
  grep -q '^":root" = "deny"$' "$config"
  grep -q '^":minimal" = "read"$' "$config"
  grep -q '^":slash_tmp" = "deny"$' "$config"
  ! grep -q '^codex_hooks = ' "$config"
  grep -q '^\[plugins\."github@openai-curated"\]' "$config"
  ! grep -q '^\[plugins\."superpowers@openai-curated"\]' "$config"
  ! grep -q '^\[projects\.' "$config"
  ! grep -q '^\[notice\.' "$config"
  ! grep -q '^\[tui\.' "$config"
  assert_codex_managed_values "$config"
  assert_dotfiles_permission_profile "$config"
}

@test "Codex config refuses relative XDG state instead of granting the wrong path" {
  local home="$BATS_TEST_TMPDIR/relative-state-home"
  local config="$BATS_TEST_TMPDIR/relative-state.toml"
  local error="$BATS_TEST_TMPDIR/relative-state.stderr"
  local chezmoi_config="$BATS_TEST_TMPDIR/relative-state-chezmoi.yaml"
  mkdir -p "$home"
  printf '{}\n' >"$chezmoi_config"

  if env HOME="$home" XDG_STATE_HOME=relative-state chezmoi \
    --source "$PROJECT_ROOT" --destination "$home" --config "$chezmoi_config" \
    execute-template --file "$PROJECT_ROOT/private_dot_config/codex/config.toml.tmpl" \
    >"$config" 2>"$error"; then
    return 1
  fi

  grep -q 'XDG_STATE_HOME must be absolute' "$error"
  ! grep -q 'relative-state/treflebonbon-skills' "$config"
}

@test "Codex strict parser accepts rendered and merged managed config" {
  local home="$BATS_TEST_TMPDIR/home"
  local codex_home="$BATS_TEST_TMPDIR/codex-home"
  mkdir -p "$home/.config/codex" "$home/.codex-app" "$codex_home"
  stage_codex_managed_config "$home"

  assert_codex_strict_config "$home/.config/codex"

  HOME="$home" CODEX_HOME="$codex_home" bash "$CODEX_MANAGED_CONFIG_SYNC"

  assert_codex_strict_config "$home/.codex"
  assert_codex_strict_config "$home/.codex-app"
  assert_codex_strict_config "$codex_home"
}

@test "dotfiles-peer is dotfiles-secure without the writable gh credential and leaves the default profile alone" {
  local rendered="$BATS_TEST_TMPDIR/config.toml" secure peer
  render_codex_managed_config "$PROJECT_ROOT" "$rendered"

  # The default stays dotfiles-secure; a peer opts in with -c default_permissions.
  grep -Fq 'default_permissions = "dotfiles-secure"' "$rendered"
  secure="$(sed -n '/^\[permissions\."dotfiles-secure"\]/,/^\[permissions\."dotfiles-peer"\]/p' "$rendered" | sed '$d')"
  peer="$(sed -n '/^\[permissions\."dotfiles-peer"\]/,/^\[plugins\./p' "$rendered" | sed '$d')"

  # dotfiles-secure still reads ~/.config/gh; dotfiles-peer reads only its own gh config dir.
  grep -Fq '[permissions."dotfiles-secure".filesystem."~/.config/gh"]' <<<"$secure"
  grep -Fq '[permissions."dotfiles-peer".filesystem."~/.codex-peer/gh"]' <<<"$peer"
  run grep -F '~/.config/gh' <<<"$peer"
  [ "$status" -eq 1 ]

  # Apart from the gh root, the two profiles are the same, so a change to one reaches the other.
  diff <(sed 's/dotfiles-secure/PROFILE/; s#~/\.config/gh#GH_ROOT#' <<<"$secure") \
    <(sed 's/dotfiles-peer/PROFILE/; s#~/\.codex-peer/gh#GH_ROOT#' <<<"$peer")
}

assert_ponytail_plugin_installed_and_enabled() {
  local plugin_list_json="$1"
  python3 - "$plugin_list_json" <<'PY'
import json
import sys

data = json.loads(sys.argv[1])
matches = [p for p in data["installed"] if p["pluginId"] == "ponytail@ponytail"]
assert len(matches) == 1, f"expected exactly one installed ponytail@ponytail entry, got {matches}"
assert matches[0]["installed"] is True
assert matches[0]["enabled"] is True
PY
}

@test "Codex managed sync installs and enables the ponytail plugin" {
  local home="$BATS_TEST_TMPDIR/home"
  local codex_home="$home/.codex"
  mkdir -p "$home/.config/codex" "$codex_home" "$home/tmp"
  stage_codex_managed_config "$home"
  # This test exercises Ponytail's marketplace switching; the skills marketplace
  # is not materialized in this isolated fixture and is intentionally omitted.
  omit_skills_marketplace_from_fixture "$home"
  create_ponytail_marketplace_fixture "$BATS_TEST_TMPDIR/ponytail-marketplace-fixture"
  export PONYTAIL_MARKETPLACE_SOURCE="$BATS_TEST_TMPDIR/ponytail-marketplace-fixture"
  export PONYTAIL_MARKETPLACE_REF=""

  HOME="$home" CODEX_HOME="$codex_home" TMPDIR="$home/tmp" bash "$CODEX_MANAGED_CONFIG_SYNC"

  run --separate-stderr env HOME="$home" CODEX_HOME="$codex_home" TMPDIR="$home/tmp" codex plugin list --json
  [ "$status" -eq 0 ]
  assert_ponytail_plugin_installed_and_enabled "$output"

  # idempotent: a second sync must not error or change the outcome
  run env HOME="$home" CODEX_HOME="$codex_home" TMPDIR="$home/tmp" bash "$CODEX_MANAGED_CONFIG_SYNC"
  [ "$status" -eq 0 ]

  run --separate-stderr env HOME="$home" CODEX_HOME="$codex_home" TMPDIR="$home/tmp" codex plugin list --json
  [ "$status" -eq 0 ]
  assert_ponytail_plugin_installed_and_enabled "$output"
}

@test "Codex managed sync re-registers the ponytail marketplace when its pinned source changes" {
  local home="$BATS_TEST_TMPDIR/home"
  local codex_home="$home/.codex"
  mkdir -p "$home/.config/codex" "$codex_home" "$home/tmp"
  stage_codex_managed_config "$home"
  omit_skills_marketplace_from_fixture "$home"
  create_ponytail_marketplace_fixture "$BATS_TEST_TMPDIR/ponytail-v1" "1.0.0-fixture"
  create_ponytail_marketplace_fixture "$BATS_TEST_TMPDIR/ponytail-v2" "2.0.0-fixture"

  PONYTAIL_MARKETPLACE_REF="" PONYTAIL_MARKETPLACE_SOURCE="$BATS_TEST_TMPDIR/ponytail-v1" \
    HOME="$home" CODEX_HOME="$codex_home" TMPDIR="$home/tmp" bash "$CODEX_MANAGED_CONFIG_SYNC"

  run --separate-stderr env HOME="$home" CODEX_HOME="$codex_home" TMPDIR="$home/tmp" codex plugin list --json
  [ "$status" -eq 0 ]
  [[ "$output" == *'"version": "1.0.0-fixture"'* ]]

  # codex refuses to re-add an already-registered marketplace name from a
  # different source; the sync must recover from this by re-registering
  # rather than silently keeping the stale pin (fail-open must not mean
  # "never update").
  PONYTAIL_MARKETPLACE_REF="" PONYTAIL_MARKETPLACE_SOURCE="$BATS_TEST_TMPDIR/ponytail-v2" \
    HOME="$home" CODEX_HOME="$codex_home" TMPDIR="$home/tmp" bash "$CODEX_MANAGED_CONFIG_SYNC"

  run --separate-stderr env HOME="$home" CODEX_HOME="$codex_home" TMPDIR="$home/tmp" codex plugin list --json
  [ "$status" -eq 0 ]
  [[ "$output" == *'"version": "2.0.0-fixture"'* ]]
}

@test "Codex managed sync pins the ponytail marketplace to the production default" {
  grep -q 'PONYTAIL_MARKETPLACE_SOURCE-dietrichgebert/ponytail' "$CODEX_MANAGED_CONFIG_SYNC"
  grep -q 'PONYTAIL_MARKETPLACE_REF-v4.9.0' "$CODEX_MANAGED_CONFIG_SYNC"
}

@test "Codex managed sync skips the ponytail plugin step without failing when codex is absent" {
  local home="$BATS_TEST_TMPDIR/home"
  local codex_home="$home/.codex"
  local bin="$BATS_TEST_TMPDIR/no-codex-bin"
  mkdir -p "$home/.config/codex" "$codex_home" "$bin"
  stage_codex_managed_config "$home"
  # Exercise the "codex absent" guard specifically, not the "source skipped"
  # guard: no network call follows since command -v codex is checked first.
  export PONYTAIL_MARKETPLACE_SOURCE="dietrichgebert/ponytail"

  # A PATH with every other runtime tool but no codex executable.
  local filtered_path
  filtered_path=$(printf '%s' "$PATH" | tr ':' '\n' | while IFS= read -r dir; do
    [ -x "$dir/codex" ] || printf '%s\n' "$dir"
  done | paste -sd: -)

  run env HOME="$home" CODEX_HOME="$codex_home" PATH="$bin:$filtered_path" bash "$CODEX_MANAGED_CONFIG_SYNC"
  [ "$status" -eq 0 ]
  grep -q '^model = "gpt-6.1-sol"$' "$codex_home/config.toml"
}

@test "Codex managed sync fails open when an existing codex_home config cannot be loaded" {
  local home="$BATS_TEST_TMPDIR/home"
  mkdir -p "$home/.codex"
  stage_codex_managed_config "$home"
  create_ponytail_marketplace_fixture "$BATS_TEST_TMPDIR/ponytail-marketplace-fixture"
  export PONYTAIL_MARKETPLACE_SOURCE="$BATS_TEST_TMPDIR/ponytail-marketplace-fixture"
  export PONYTAIL_MARKETPLACE_REF=""
  # Deliberately incomplete managed config (mirrors the migration fixture
  # above): missing default_permissions makes the merged result something
  # the codex binary itself rejects, independent of the ponytail logic.
  cat >"$home/.config/codex/config.toml" <<'EOF'
[permissions.dotfiles-secure.filesystem.":workspace_roots"]
"**/.env*" = "deny"
EOF
  cp "$home/.config/codex/config.toml" "$home/.codex/config.toml"

  run env -u CODEX_HOME HOME="$home" bash "$CODEX_MANAGED_CONFIG_SYNC"
  [ "$status" -eq 0 ]
  [[ "$output" == *"WARNING: ponytail plugin sync failed for $home/.codex"* ]]
  grep -Fq '"**/.env*" = "deny"' "$home/.codex/config.toml"
}

@test "dotfiles-secure sandbox starts without declaring protected home-tree access" {
  local home="$BATS_TEST_TMPDIR/home"
  local workspace="$BATS_TEST_TMPDIR/workspace"
  local codex_home="$home/.codex"
  mkdir -p "$workspace" "$codex_home" "$home/.ssh"
  prepare_codex_permission_roots "$home"
  printf 'protected\n' >"$home/.ssh/config"
  render_codex_managed_config "$PROJECT_ROOT" "$codex_home/config.toml" "$home"
  assert_dotfiles_permission_profile "$codex_home/config.toml"

  run_codex_with_virtual_home "$home" "$workspace" \
    sandbox -P dotfiles-secure -C "$workspace" -- true

  [ "$status" -eq 0 ]

  run_codex_with_virtual_home "$home" "$workspace" \
    sandbox -P dotfiles-secure -C "$workspace" -- \
    sh -c 'printf "workspace write allowed\\n" >"$1"' _ "$workspace/allowed.txt"

  [ "$status" -eq 0 ]
  [ "$(cat "$workspace/allowed.txt")" = "workspace write allowed" ]

  run_codex_with_virtual_home "$home" "$workspace" \
    sandbox -P dotfiles-secure -C "$workspace" -- \
    sh -c 'printf "overwritten\\n" >"$HOME/.ssh/config"'

  [ "$status" -ne 0 ]
  [ "$(cat "$home/.ssh/config")" = "protected" ]
}

@test "managed dependency policy permits official Node.js downloads and rejects lookalike hosts" {
  render_codex_managed_config "$PROJECT_ROOT" "$BATS_TEST_TMPDIR/config.toml"
  run python3 - "$BATS_TEST_TMPDIR/config.toml" <<'PY'
import sys, tomllib
from pathlib import Path
config = tomllib.loads(Path(sys.argv[1]).read_text())
for profile in ("dotfiles-secure", "dotfiles-peer"):
    policy = config["permissions"][profile]["network"]["domains"]
    assert policy["nodejs.org"] == "allow", profile
    assert all(
        host not in policy
        for host in ("nodejs.org.evil.example", "evilnodejs.org", "www.nodejs.org", "**.nodejs.org")
    ), profile
PY
  [ "$status" -eq 0 ]
}

@test "dotfiles-secure denies files outside the workspace while Nix store tools remain executable" {
  local home="$BATS_TEST_TMPDIR/home"
  local codex_home="$home/.codex"
  local workspace="$BATS_TEST_TMPDIR/workspace"
  mkdir -p "$codex_home" "$workspace" "$home/other-repo"
  prepare_codex_permission_roots "$home"
  printf 'protected\n' >"$home/other-repo/.env"
  render_codex_managed_config "$PROJECT_ROOT" "$codex_home/config.toml" "$home"
  run env HOME="$home" CODEX_HOME="$codex_home" TMPDIR=/tmp \
    codex sandbox -P dotfiles-secure -C "$workspace" -- cat "$home/other-repo/.env"
  [ "$status" -ne 0 ]
  run env HOME="$home" CODEX_HOME="$codex_home" TMPDIR=/tmp \
    codex sandbox -P dotfiles-secure -C "$workspace" -- python3 -c 'print("runtime available")'
  [ "$status" -eq 0 ]
  [[ "$output" == *'runtime available'* ]]
}

@test "dotfiles-secure permits Environment Contract Files while preserving secret denies" {
  local home="$BATS_TEST_TMPDIR/home"
  local workspace="$BATS_TEST_TMPDIR/workspace"
  local codex_home="$home/.codex"
  local path
  mkdir -p "$workspace/one/two/three" "$codex_home"
  prepare_codex_permission_roots "$home"
  render_codex_managed_config "$PROJECT_ROOT" "$codex_home/config.toml" "$home"

  assert_dotfiles_permission_profile "$codex_home/config.toml"
  grep -q '^\*\*Environment Contract File\*\*:' "$PROJECT_ROOT/GLOSSARY.md"

  for path in .envrc .env.example one/two/three/.envrc one/two/three/.env.example; do
    printf 'original\n' >"$workspace/$path"
    run env HOME="$home" CODEX_HOME="$codex_home" TMPDIR=/tmp \
      codex sandbox -P dotfiles-secure -C "$workspace" -- \
      sh -c 'printf "updated\n" >"$1"' _ "$path"

    if [ "$status" -ne 0 ]; then
      printf '%s\n' "$output" >&3
    fi
    [ "$status" -eq 0 ]
    [ "$(cat "$workspace/$path")" = "updated" ]
  done

  for path in \
    .env .env. .env.local .env.e .env.experimental .env.example.local \
    .envrc.local .env-secret .environment \
    one/two/three/.env.production one/two/three/.envrc.local \
    one/two/three/.env-secret one/two/three/.environment \
    private.key credentials.json; do
    printf 'protected\n' >"$workspace/$path"
    run env HOME="$home" CODEX_HOME="$codex_home" TMPDIR=/tmp \
      codex sandbox -P dotfiles-secure -C "$workspace" -- \
      sh -c 'printf "overwritten\n" >"$1"' _ "$path"

    if [ "$status" -eq 0 ]; then
      printf 'unexpected write allowed: %s\n%s\n' "$path" "$output" >&3
    fi
    [ "$status" -ne 0 ]
    [ "$(cat "$workspace/$path")" = "protected" ]
  done
}

@test "dotfiles-secure command network proxy enforces the managed domain allowlist" {
  local home="$BATS_TEST_TMPDIR/home"
  local workspace="$BATS_TEST_TMPDIR/workspace"
  local codex_home="$home/.codex"
  local proxy_denied='CONNECT tunnel failed, response 403|Received HTTP code 403 from proxy after CONNECT'
  mkdir -p "$workspace" "$codex_home"
  prepare_codex_permission_roots "$home"
  render_codex_managed_config "$PROJECT_ROOT" "$codex_home/config.toml" "$home"
  assert_codex_managed_values "$codex_home/config.toml"
  assert_dotfiles_permission_profile "$codex_home/config.toml"

  run env HOME="$home" CODEX_HOME="$codex_home" TMPDIR=/tmp \
    codex sandbox -P dotfiles-secure -C "$workspace" -- \
    sh -c 'test -n "$CODEX_NETWORK_PROXY_ACTIVE" && curl --silent --show-error --fail --max-time 20 https://registry.npmjs.org/-/ping >/dev/null'

  if [ "$status" -ne 0 ]; then
    printf 'allowlisted command network request failed:\n%s\n' "$output" >&3
  fi
  [ "$status" -eq 0 ]

  run env HOME="$home" CODEX_HOME="$codex_home" TMPDIR=/tmp \
    codex sandbox -P dotfiles-secure -C "$workspace" -- \
    curl --silent --show-error --output /dev/null --max-time 20 https://example.com/

  if [[ ! "$output" =~ $proxy_denied ]]; then
    printf 'non-allowlisted command network request had an unexpected failure:\n%s\n' "$output" >&3
  fi
  [ "$status" -eq 56 ]
  [[ "$output" =~ $proxy_denied ]]
}

@test "bun codex launches plain Codex from a primary checkout without overriding managed settings" {
  local repo="$BATS_TEST_TMPDIR/repo"
  local bin="$BATS_TEST_TMPDIR/bin"
  mkdir -p "$repo"
  git -C "$repo" init -q
  stage_codex_package_launcher "$repo" "$bin"

  cat >"$bin/codex" <<'EOF'
#!/usr/bin/env bash
printf 'target=<plain>\n'
printf 'arg=<%s>\n' "$@"
EOF
  chmod +x "$bin/codex"

  run env PATH="$bin:$PATH" bash -c \
    'cd "$1" && exec bun --silent codex --model "model with space" "" "prompt with space"' \
    _ "$repo"

  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "target=<plain>" ]
  [ "${lines[1]}" = "arg=<--model>" ]
  [ "${lines[2]}" = "arg=<model with space>" ]
  [ "${lines[3]}" = "arg=<>" ]
  [ "${lines[4]}" = "arg=<prompt with space>" ]
  [ "${#lines[@]}" -eq 5 ]
}

@test "bun codex launches plain Codex from a primary checkout with a separate Git directory" {
  local repo="$BATS_TEST_TMPDIR/repo"
  local separate_git_dir="$BATS_TEST_TMPDIR/separate.git"
  local bin="$BATS_TEST_TMPDIR/bin"
  git init -q --separate-git-dir "$separate_git_dir" "$repo"
  stage_codex_package_launcher "$repo" "$bin"

  cat >"$bin/codex" <<'EOF'
#!/usr/bin/env bash
printf 'target=<plain>\n'
printf 'arg=<%s>\n' "$@"
EOF
  chmod +x "$bin/codex"

  run env PATH="$bin:$PATH" bash -c \
    'cd "$1" && exec bun --silent codex prompt' _ "$repo"

  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "target=<plain>" ]
  [ "${lines[1]}" = "arg=<prompt>" ]
  [ "${#lines[@]}" -eq 2 ]
}

@test "bun codex routes linked worktrees through the fixed raw dispatcher with arguments intact" {
  local repo="$BATS_TEST_TMPDIR/repo"
  local worktree="$BATS_TEST_TMPDIR/worktree"
  local bin="$BATS_TEST_TMPDIR/bin"
  create_linked_worktree "$repo" "$worktree"
  cp "$PROJECT_ROOT/package.json" "$worktree/package.json"
  cp "$PROJECT_ROOT/codex" "$worktree/codex"
  stage_codex_package_launcher "$worktree" "$bin"

  run env PATH="$bin:$PATH" SKILLS_PLUGIN_SYNC_LOG="$SKILLS_PLUGIN_SYNC_LOG" bash -c \
    'cd "$1" && exec bun --silent codex sandbox -c '\''model_reasoning_effort="xhigh"'\'' -- printf "arg=<%s>\\n" "model with space" "" "prompt with space"' \
    _ "$worktree"

  [ "$status" -eq 0 ]
  [[ "$output" == *DISPATCHED* ]]
  python3 - "$SKILLS_PLUGIN_SYNC_LOG" <<'PY'
import json
import sys
from pathlib import Path

arguments = json.loads(Path(sys.argv[1]).read_text())
assert arguments == [
    "--run-raw",
    "codex-worktree",
    "--",
    "sandbox",
    "-c",
    'model_reasoning_effort="xhigh"',
    "--",
    "printf",
    "arg=<%s>\\n",
    "model with space",
    "",
    "prompt with space",
]
PY
}

@test "bun codex fails closed outside Git without launching Codex" {
  local workspace="$BATS_TEST_TMPDIR/workspace"
  local bin="$BATS_TEST_TMPDIR/bin"
  local launched="$BATS_TEST_TMPDIR/codex-launched"
  mkdir -p "$workspace"
  stage_codex_package_launcher "$workspace" "$bin"
  install_codex_launch_sentinel "$bin"

  run env PATH="$bin:$PATH" CODEX_LAUNCHED="$launched" bash -c \
    'cd "$1" && exec bun --silent codex prompt' _ "$workspace"

  [ "$status" -ne 0 ]
  [[ "$output" == *"codex-context: current directory is not a Git checkout"* ]]
  [ ! -e "$launched" ]
}

@test "Codex runtime directory remains unmanaged by chezmoi" {
  local ignore="$PROJECT_ROOT/.chezmoiignore"

  grep -q '^\.codex$' "$ignore"
  grep -q '^codex$' "$ignore"
  grep -q '^apm_modules/\*\*$' "$ignore"
  grep -q '^\.agents/\*\*$' "$ignore"
  grep -q '^\.claude/agents/\*\*$' "$ignore"
  grep -q '^\.claude/hooks/\*\*$' "$ignore"
  grep -q '^\.claude/skills/\*\*$' "$ignore"
  grep -q '^\.claude/worktrees/\*\*$' "$ignore"
  ! grep -q '^!\.claude/worktrees/' "$ignore"
}

@test "Codex AGENTS managed guidance exists" {
  local agents="$PROJECT_ROOT/private_dot_config/codex/AGENTS.md"

  [ -f "$agents" ]
  grep -q '^# Guidelines$' "$agents"
  grep -q 'Think in English, respond in Japanese\.' "$agents"
  grep -q '^## Behavior$' "$agents"
  grep -q '^## Investigation before answering$' "$agents"
  grep -q '^## Parallel tool calls$' "$agents"
}

@test "Global runtime guidance preauthorizes routine GitHub collaboration writes" {
  local guidance
  for guidance in \
    "$PROJECT_ROOT/private_dot_config/codex/AGENTS.md" \
    "$PROJECT_ROOT/private_dot_claude/CLAUDE.md" \
    "$PROJECT_ROOT/private_dot_gemini/AGENTS.md"; do
    grep -Fq 'Routine GitHub collaboration writes do not need a second confirmation' "$guidance"
    grep -Fq 'pushes from the current topic branch using `git-push-topic`' "$guidance"
    grep -Fq 'Force pushes are prohibited by policy' "$guidance"
    grep -Fq 'Direct raw `git push` commands and common wrapper or global-option variants are blocked by runtime rules' "$guidance"
    grep -Fq 'Use `git-push-reviewed` for a default-branch push only after explicit approval' "$guidance"
    grep -Fq 'direct pushes to a default branch' "$guidance"
    ! grep -Fq 'Visible to others: pushing code, commenting on PRs/issues' "$guidance"
  done
}

@test "Codex managed Hook adds the quiet global Impeccable Design Hook" {
  local hooks="$PROJECT_ROOT/private_dot_config/codex/hooks.json"

  [ -f "$hooks" ]
  python3 -m json.tool "$hooks" >/dev/null
  python3 - "$hooks" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as f:
    data = json.load(f)

assert data["hooks"].pop("SessionStart")
command = data["hooks"]["PostToolUse"][0]["hooks"][0]["command"]
assert isinstance(command, str) and command

# Stop carries no matcher (it is not a tool event) and gets the upstream deep-pass
# budget of 30s instead of the per-edit 5s. Impeccable recognizes Codex's turn_id
# and emits the native top-level decision/reason schema itself, so both events use
# the same fail-open pass-through command.
assert data == {
    "hooks": {
        "PreToolUse": [
            {
                "matcher": "Bash",
                "hooks": [
                    {
                        "type": "command",
                        "command": "\"$HOME/.local/bin/gcloud-inspect-hook\"",
                        "timeout": 5,
                    }
                ],
            }
        ],
        "PostToolUse": [
            {
                "matcher": "Edit|Write|apply_patch",
                "hooks": [{"type": "command", "command": command, "timeout": 5}],
            }
        ],
        "Stop": [
            {"hooks": [{"type": "command", "command": command, "timeout": 30}]}
        ],
    }
}
PY
  ! grep -q 'security-guidance' "$hooks"
}

@test "Claude settings keep read-only Edit denies and global hooks" {
  local settings="$BATS_TEST_TMPDIR/settings.json"
  render_claude_settings "$settings"

  python3 -m json.tool "$settings" >/dev/null
  python3 - "$settings" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as f:
    data = json.load(f)

assert data["editorMode"] == "normal"
assert "Edit(**/.env*)" in data["permissions"]["deny"]
assert "Edit(~/.ssh/**)" in data["permissions"]["deny"]
assert "Edit(~/runtime/**)" in data["permissions"]["deny"]
assert "Read(~/runtime/**)" not in data["permissions"]["deny"]
assert "Edit(~/ghq/github.com/**)" not in data["permissions"]["deny"]
assert "Read(~/ghq/github.com/**)" not in data["permissions"]["deny"]
assert "Edit(~/.cache/nix-devshell-tmp/**)" not in data["permissions"]["deny"]
assert not any(
    rule.startswith("Write(") for rule in data["permissions"]["deny"]
)
assert data["hooks"]["PreToolUse"] == [
    {
        "matcher": "Bash",
        "hooks": [
            {
                "type": "command",
                "command": "\"$HOME/.local/bin/devshell-env\" claude-hook",
                "timeout": 120,
            },
            {
                "type": "command",
                "command": "\"$HOME/.local/bin/gcloud-inspect-hook\"",
                "timeout": 5,
            },
        ],
    }
]
command = data["hooks"]["PostToolUse"][0]["hooks"][0]["command"]
assert isinstance(command, str) and command

assert data["hooks"]["PostToolUse"] == [
    {
        "matcher": "Edit|Write|MultiEdit",
        "hooks": [{"type": "command", "command": command, "timeout": 5}],
    }
]
# Stop carries no matcher (it is not a tool event) and gets the upstream deep-pass
# budget of 30s instead of the per-edit 5s.
assert data["hooks"]["Stop"] == [
    {"hooks": [{"type": "command", "command": command, "timeout": 30}]},
    {
        "hooks": [
            {
                "type": "command",
                "command": "\"$HOME/.local/bin/claude-japanese-stop-hook\"",
                "timeout": 10,
            }
        ]
    },
]
assert "Bash(git-push-topic:*)" in data["permissions"]["allow"]
for rule in [
    "Bash(git worktree remove:*)",
    "Bash(herdr worktree remove:*)",
    "Bash(orca worktree rm:*)",
    "Bash(gh pr create:*)",
    "Bash(gh pr edit:*)",
    "Bash(gh pr comment:*)",
    "Bash(gh pr review:*)",
    "Bash(gh pr ready:*)",
    "Bash(gh issue create:*)",
    "Bash(gh issue edit:*)",
    "Bash(gh issue comment:*)",
    "Bash(gh label create:*)",
    "Bash(gh label edit:*)",
]:
    assert rule in data["permissions"]["allow"]
assert "Bash(git push:*)" in data["permissions"]["deny"]
for rule in [
    "Bash(/usr/bin/git push:*)",
    "Bash(git -C:*)",
    "Bash(git --git-dir:*)",
    "Bash(command git:*)",
    "Bash(env git:*)",
]:
    assert rule in data["permissions"]["deny"]
assert not any(
    rule.startswith("Bash(git push --force") for rule in data["permissions"]["deny"]
)
PY
}

@test "Project-level Claude settings deny rules actually match file permission checks" {
  local settings="$PROJECT_ROOT/.claude/settings.json"

  python3 -m json.tool "$settings" >/dev/null
  python3 - "$settings" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as f:
    data = json.load(f)

assert "Edit(**/.env*)" in data["permissions"]["deny"]
assert "Edit(~/.ssh/**)" in data["permissions"]["deny"]
assert not any(
    rule.startswith("Write(") for rule in data["permissions"]["deny"]
)
PY
}

@test "Claude auto mode is managed in user settings without a package launcher alias" {
  local settings="$BATS_TEST_TMPDIR/settings.json"
  render_claude_settings "$settings"
  python3 - \
    "$settings" \
    "$PROJECT_ROOT/package.json" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as f:
    settings = json.load(f)
with open(sys.argv[2], encoding="utf-8") as f:
    package = json.load(f)

assert settings["permissions"]["defaultMode"] == "auto"
assert "claude" not in package["scripts"]
PY
}

@test "managed Design Hook commands discard failed runtime output and fail open" {
  local home="$BATS_TEST_TMPDIR/home"
  mkdir -p \
    "$home/.agents/skills/impeccable/scripts" \
    "$home/.claude/skills/impeccable/scripts"
  local engine="$home/engine"
  local hub
  for hub in .agents .claude; do
    printf '#!/bin/sh\nprintf "invoked\\n" >>"$HOME/launcher-invocations"\nexec "$IMPECCABLE_BIN" "$@"\n' \
      >"$home/$hub/skills/impeccable/scripts/impeccable"
  done
  printf '#!/usr/bin/env node\nprocess.stdout.write("partial"); process.stderr.write("runtime failed\\n"); process.exit(42);\n' >"$engine"
  chmod +x "$engine"

  local settings="$BATS_TEST_TMPDIR/settings.json"
  render_claude_settings "$settings"
  mapfile -t commands < <(
    python3 - \
      "$settings" \
      "$PROJECT_ROOT/private_dot_config/codex/hooks.json" <<'PY'
import json
import sys

# Both wired events must fail open, not just the per-edit one: a Stop hook that
# leaked a non-zero exit or partial stdout would break the turn at its very end.
for path in sys.argv[1:]:
    with open(path, encoding="utf-8") as f:
        data = json.load(f)
    for event in ("PostToolUse", "Stop"):
        print(data["hooks"][event][0]["hooks"][0]["command"])
PY
  )

  [ "${#commands[@]}" -eq 4 ]
  local command
  for command in "${commands[@]}"; do
    run env HOME="$home" IMPECCABLE_BIN="$engine" bash -c "$command"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
    local invocations
    invocations="$(wc -l <"$home/launcher-invocations")"
    # Missing or non-executable engines must not enter the launcher's downloader.
    run env HOME="$home" IMPECCABLE_BIN= bash -c "$command"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
    run env HOME="$home" IMPECCABLE_BIN="$home/missing-engine" bash -c "$command"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
    run env HOME="$home" IMPECCABLE_BIN="$home/launcher-invocations" bash -c "$command"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
    [ "$(wc -l <"$home/launcher-invocations")" = "$invocations" ]
    run env HOME="$BATS_TEST_TMPDIR/empty-home" IMPECCABLE_BIN="$engine" bash -c "$command"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
  done

  # The synthetic candidate runtime distinguishes Codex by turn_id and owns the
  # native Stop schema. Managed commands only preserve its stdout byte-for-byte.
  local hook_runtime_fixture='let input="";process.stdin.on("data",chunk=>input+=chunk);process.stdin.on("end",()=>{const event=JSON.parse(input);const codexStop=event.turn_id&&event.hook_event_name==="Stop";process.stdout.write(JSON.stringify(codexStop?{decision:"block",reason:"finding"}:{hookSpecificOutput:{hookEventName:event.hook_event_name,additionalContext:"finding"}}))});'
  printf '#!/usr/bin/env node\n%s\n' "$hook_runtime_fixture" >"$engine"

  local post_tool_use='{"session_id":"fixture","hook_event_name":"PostToolUse"}'
  local claude_stop='{"session_id":"fixture","hook_event_name":"Stop"}'
  local codex_post_tool_use='{"session_id":"fixture","turn_id":"turn-1","hook_event_name":"PostToolUse"}'
  local codex_stop='{"session_id":"fixture","turn_id":"turn-1","hook_event_name":"Stop"}'
  local passthrough_post_tool_use='{"hookSpecificOutput":{"hookEventName":"PostToolUse","additionalContext":"finding"}}'
  local passthrough_stop='{"hookSpecificOutput":{"hookEventName":"Stop","additionalContext":"finding"}}'
  local codex_stop_expected='{"decision":"block","reason":"finding"}'

  run env HOME="$home" IMPECCABLE_BIN="$engine" bash -c "${commands[0]}" <<<"$post_tool_use"
  [ "$status" -eq 0 ]
  [ "$output" = "$passthrough_post_tool_use" ]

  run env HOME="$home" IMPECCABLE_BIN="$engine" bash -c "${commands[1]}" <<<"$claude_stop"
  [ "$status" -eq 0 ]
  [ "$output" = "$passthrough_stop" ]

  run env HOME="$home" IMPECCABLE_BIN="$engine" bash -c "${commands[2]}" <<<"$codex_post_tool_use"
  [ "$status" -eq 0 ]
  [ "$output" = "$passthrough_post_tool_use" ]

  run env HOME="$home" IMPECCABLE_BIN="$engine" bash -c "${commands[3]}" <<<"$codex_stop"
  [ "$status" -eq 0 ]
  [ "$output" = "$codex_stop_expected" ]
}

@test "Codex rules managed file blocks destructive commands" {
  local rules="$PROJECT_ROOT/private_dot_config/codex/rules/default.rules"

  [ -f "$rules" ]
  grep -q 'pattern = \[\["sudo", "su"\]\]' "$rules"
  grep -q 'pattern = \["chmod", "777"\]' "$rules"
  grep -q 'pattern = \["terraform", \["apply", "destroy"\]\]' "$rules"
  grep -q 'pattern = \["kubectl", "delete"\]' "$rules"
  grep -q 'pattern = \["gh", "repo", "delete"\]' "$rules"
  grep -q 'pattern = \["git", "push"\]' "$rules"
  grep -q 'pattern = \["git-push-topic"\]' "$rules"
  grep -q 'pattern = \["git-push-reviewed"\]' "$rules"
  grep -q 'pattern = \["rm", \["-r", "-R", "-rf", "-fr"\]\]' "$rules"
  grep -q 'decision = "forbidden"' "$rules"
  grep -q 'decision = "prompt"' "$rules"
  grep -q 'match = \[' "$rules"
  grep -q 'not_match = \[' "$rules"
}

@test "Codex execpolicy allows routine GitHub writes without widening destructive actions" {
  local rules="$PROJECT_ROOT/private_dot_config/codex/rules/default.rules"

  local command
  for command in \
    "git-push-topic" \
    "gh pr create --title test --body test" \
    "gh pr edit 123 --title test" \
    "gh pr comment 123 --body test" \
    "gh pr review 123 --approve" \
    "gh pr ready 123" \
    "gh issue create --title test --body test" \
    "gh issue edit 123 --add-label ready-for-agent" \
    "gh issue comment 123 --body test" \
    "gh label create test --color 000000" \
    "gh label edit test --color ffffff"; do
    run bash -c "codex execpolicy check --pretty --rules '$rules' -- $command"
    [ "$status" -eq 0 ]
    [[ "$output" == *'"decision": "allow"'* ]]
  done

  for command in \
    "git-push-reviewed" \
    "gh pr close 123" \
    "gh pr merge 123" \
    "gh pr reopen 123" \
    "gh issue close 123" \
    "gh issue reopen 123"; do
    run bash -c "codex execpolicy check --pretty --rules '$rules' -- $command"
    [ "$status" -eq 0 ]
    [[ "$output" == *'"decision": "prompt"'* ]]
  done

  for command in \
    "git push origin HEAD" \
    "git push -u origin HEAD" \
    "git push --set-upstream origin HEAD" \
    "git push origin main" \
    "git push -u origin master" \
    "git push origin HEAD --force" \
    "git push -u origin HEAD --force-with-lease" \
    "git push -u --force origin HEAD" \
    "git push origin +HEAD" \
    "git push upstream HEAD --force" \
    "/bin/git push origin HEAD" \
    "/usr/bin/git push origin HEAD --force" \
    "git -C . push origin HEAD" \
    "git -c core.hooksPath=/dev/null push origin HEAD --force" \
    "git --git-dir .git push origin HEAD" \
    "git --work-tree . push origin HEAD --force-with-lease" \
    "command git push origin HEAD" \
    "env git push origin +HEAD" \
    "gh repo delete owner/repo"; do
    run bash -c "codex execpolicy check --pretty --rules '$rules' -- $command"
    [ "$status" -eq 0 ]
    [[ "$output" == *'"decision": "forbidden"'* ]]
  done
}

@test "bash_profile routes Codex Desktop sessions to .codex-app" {
  local profile="$PROJECT_ROOT/dot_bash_profile.tmpl"

  grep -q 'CODEX_INTERNAL_ORIGINATOR_OVERRIDE' "$profile"
  grep -q 'CODEX_HOME="$HOME/.codex-app"' "$profile"
  grep -q 'mkdir -p "$CODEX_HOME/sessions" "$CODEX_HOME/worktrees"' "$profile"
}

@test "first Codex Desktop login seeds all managed config" {
  local home="$BATS_TEST_TMPDIR/home"
  local source="$BATS_TEST_TMPDIR/source"
  local config="$BATS_TEST_TMPDIR/chezmoi.yaml"
  prepare_codex_chezmoi_source "$source"
  mkdir -p "$home"
  printf '{}\n' >"$config"

  env -u CODEX_HOME HOME="$home" chezmoi \
    --source "$source" \
    --destination "$home" \
    --persistent-state "$BATS_TEST_TMPDIR/chezmoi-state.boltdb" \
    --config "$config" \
    apply

  [ -f "$home/.codex/config.toml" ]
  [ ! -d "$home/.codex-app" ]

  HOME="$home" CODEX_INTERNAL_ORIGINATOR_OVERRIDE="Codex Desktop" \
    bash -c '. "$1"' _ "$home/.bash_profile"

  grep -q '^model = "gpt-6.1-sol"$' "$home/.codex-app/config.toml"
  cmp "$home/.config/codex/hooks.json" "$home/.codex-app/hooks.json"
  cmp "$home/.config/codex/rules/default.rules" "$home/.codex-app/rules/default.rules"
  cmp "$home/.config/codex/environments/environment.toml" "$home/.codex-app/environments/environment.toml"
  cmp "$home/.config/codex/AGENTS.md" "$home/.codex-app/AGENTS.md"
  [ -f "$home/.codex-app/.managed-config-seeded" ]
  [ "$(stat -c %a "$home/.codex-app/config.toml")" = "600" ]
  [ "$(stat -c %a "$home/.codex-app/hooks.json")" = "600" ]
  [ "$(stat -c %a "$home/.codex-app/rules/default.rules")" = "600" ]
  [ "$(stat -c %a "$home/.codex-app/environments/environment.toml")" = "600" ]
  [ "$(stat -c %a "$home/.codex-app/AGENTS.md")" = "600" ]
}

@test "existing unsynced Codex Desktop home is backfilled on login" {
  local home="$BATS_TEST_TMPDIR/home"
  stage_codex_managed_config "$home"
  install_codex_managed_config_sync "$home"
  mkdir -p "$home/.codex-app"
  cat >"$home/.codex-app/config.toml" <<'EOF'
[projects."/home/ubuntu/workspace/desktop"]
trust_level = "trusted"
EOF

  HOME="$home" CODEX_INTERNAL_ORIGINATOR_OVERRIDE="Codex Desktop" \
    CODEX_MANAGED_CONFIG_SYNC="$home/.local/bin/sync-codex-managed-config" \
    bash -c '. "$1"' _ "$PROJECT_ROOT/dot_bash_profile.tmpl"

  grep -q '^model = "gpt-6.1-sol"$' "$home/.codex-app/config.toml"
  grep -q '^\[projects\."/home/ubuntu/workspace/desktop"\]$' "$home/.codex-app/config.toml"
  cmp "$home/.config/codex/hooks.json" "$home/.codex-app/hooks.json"
  cmp "$home/.config/codex/rules/default.rules" "$home/.codex-app/rules/default.rules"
  cmp "$home/.config/codex/environments/environment.toml" "$home/.codex-app/environments/environment.toml"
  cmp "$home/.config/codex/AGENTS.md" "$home/.codex-app/AGENTS.md"
  [ -f "$home/.codex-app/.managed-config-seeded" ]
}

@test "seeded Codex Desktop home is not rewritten on later logins" {
  local home="$BATS_TEST_TMPDIR/home"
  stage_codex_managed_config "$home"
  install_codex_managed_config_sync "$home"

  HOME="$home" CODEX_INTERNAL_ORIGINATOR_OVERRIDE="Codex Desktop" \
    CODEX_MANAGED_CONFIG_SYNC="$home/.local/bin/sync-codex-managed-config" \
    bash -c '. "$1"' _ "$PROJECT_ROOT/dot_bash_profile.tmpl"
  printf 'desktop-local\n' >"$home/.codex-app/hooks.json"

  HOME="$home" CODEX_INTERNAL_ORIGINATOR_OVERRIDE="Codex Desktop" \
    CODEX_MANAGED_CONFIG_SYNC="$home/.local/bin/sync-codex-managed-config" \
    bash -c '. "$1"' _ "$PROJECT_ROOT/dot_bash_profile.tmpl"

  [ "$(cat "$home/.codex-app/hooks.json")" = "desktop-local" ]
}

@test "failed Codex Desktop seed remains eligible for retry" {
  local home="$BATS_TEST_TMPDIR/home"
  stage_codex_managed_config "$home"
  install_codex_managed_config_sync "$home"
  rm "$home/.config/codex/AGENTS.md"

  run env HOME="$home" CODEX_INTERNAL_ORIGINATOR_OVERRIDE="Codex Desktop" \
    CODEX_MANAGED_CONFIG_SYNC="$home/.local/bin/sync-codex-managed-config" \
    bash -c '. "$1"' _ "$PROJECT_ROOT/dot_bash_profile.tmpl"

  [ "$status" -eq 0 ]
  [[ "$output" == *"failed to seed Codex Desktop managed config"* ]]
  [ ! -f "$home/.codex-app/.managed-config-seeded" ]
}

@test "Codex environment managed fragment is repo-agnostic" {
  local environment="$PROJECT_ROOT/private_dot_config/codex/environments/environment.toml"

  [ -f "$environment" ]
  grep -q '^name = "default"$' "$environment"
  python3 - "$environment" <<'PY'
import pathlib
import sys
import tomllib

config = tomllib.loads(pathlib.Path(sys.argv[1]).read_text())
assert config["setup"]["script"] == ""
PY
  ! grep -q "/home/ubuntu/ghq/" "$environment"
  ! grep -q "devpod status dap" "$environment"
}

@test "Codex config merge script writes managed permission profile" {
  local home="$BATS_TEST_TMPDIR/home"
  mkdir -p "$home/.config/codex" "$home/.codex"
  stage_codex_managed_config "$home"

  cat >"$home/.codex/config.toml" <<'EOF'
sandbox_mode = "workspace-write"

[sandbox_workspace_write]
network_access = false

[permissions.dotfiles-secure.network.domains]
"pypi.org" = "allow"
"retired.example.com" = "allow"
EOF

  env -u CODEX_HOME HOME="$home" bash "$CODEX_MANAGED_CONFIG_SYNC"

  grep -q '^approval_policy = "on-request"$' "$home/.codex/config.toml"
  grep -q '^approvals_reviewer = "auto_review"$' "$home/.codex/config.toml"
  assert_dotfiles_permission_profile "$home/.codex/config.toml"
  grep -q '^\[permissions\.dotfiles-secure\.filesystem\]$' "$home/.codex/config.toml"
  grep -q '^glob_scan_max_depth = 16$' "$home/.codex/config.toml"
  grep -q '^\[permissions\.dotfiles-secure\.filesystem\.":workspace_roots"\]$' "$home/.codex/config.toml"
  grep -q '^"\.env" = "deny"$' "$home/.codex/config.toml"
  grep -q '^"\*\*/\.env\.example?\*" = "deny"$' "$home/.codex/config.toml"
  grep -q '^":root" = "deny"$' "$home/.codex/config.toml"
  grep -q '^\[mcp_servers\.context7\]$' "$home/.codex/config.toml"
  grep -q '^args = \["-y", "@upstash/context7-mcp"\]$' "$home/.codex/config.toml"
  grep -q '^\[mcp_servers\.serena\]$' "$home/.codex/config.toml"
  grep -q 'git+https://github.com/oraios/serena' "$home/.codex/config.toml"
}

@test "Codex config merge script preserves local project trust and app state" {
  local home="$BATS_TEST_TMPDIR/home"
  stage_codex_managed_config "$home"
  mkdir -p "$home/.config/codex" "$home/.codex"

  cat >"$home/.config/codex/config.toml" <<'EOF'
model = "gpt-6.1-sol"
model_reasoning_effort = "xhigh"
model_reasoning_summary = "concise"
model_verbosity = "medium"
personality = "pragmatic"

[agents]
default_subagent_model = "gpt-6-luna"
default_subagent_reasoning_effort = "xhigh"
max_concurrent_threads_per_session = 3

[features]
network_proxy = true

[apps.github]
default_tools_approval_mode = "approve"
destructive_enabled = false

[plugins."github@openai-curated"]
enabled = true

[plugins."example-curated@openai-curated"]
enabled = true

[plugins."example-local-plugin@example-marketplace"]
enabled = true
EOF

  cat >"$home/.codex/config.toml" <<'EOF'
model = "gpt-5.4"
model_reasoning_effort = "high"

[projects."/home/ubuntu/workspace/example"]
trust_level = "trusted"

[notice.model_migrations]
"gpt-5.4" = "gpt-5.5"

[tui.model_availability_nux]
"gpt-5.5" = 4
EOF

  env -u CODEX_HOME HOME="$home" bash "$CODEX_MANAGED_CONFIG_SYNC"

  grep -q '^model = "gpt-6.1-sol"$' "$home/.codex/config.toml"
  grep -q '^model_reasoning_effort = "xhigh"$' "$home/.codex/config.toml"
  grep -q '^personality = "pragmatic"$' "$home/.codex/config.toml"
  grep -q '^\[plugins\."github@openai-curated"\]$' "$home/.codex/config.toml"
  grep -q '^enabled = true$' "$home/.codex/config.toml"
  grep -q '^\[plugins\."example-curated@openai-curated"\]$' "$home/.codex/config.toml"
  grep -q '^\[plugins\."example-local-plugin@example-marketplace"\]$' "$home/.codex/config.toml"
  grep -q '^\[projects\."/home/ubuntu/workspace/example"\]$' "$home/.codex/config.toml"
  grep -q '^trust_level = "trusted"$' "$home/.codex/config.toml"
  grep -q '^\[notice.model_migrations\]$' "$home/.codex/config.toml"
  grep -q '^"gpt-5.4" = "gpt-5.5"$' "$home/.codex/config.toml"
  grep -q '^\[tui.model_availability_nux\]$' "$home/.codex/config.toml"
  grep -q '^"gpt-5.5" = 4$' "$home/.codex/config.toml"
}

@test "Codex config merge script removes retired superpowers plugin block" {
  local home="$BATS_TEST_TMPDIR/home"
  mkdir -p "$home/.config/codex" "$home/.codex"
  stage_codex_managed_config "$home"

  cat >"$home/.codex/config.toml" <<'EOF'
[plugins."superpowers@openai-curated"]
enabled = true

[plugins."user-plugin@somewhere"]
enabled = true
EOF

  env -u CODEX_HOME HOME="$home" bash "$CODEX_MANAGED_CONFIG_SYNC"

  ! grep -q 'superpowers@openai-curated' "$home/.codex/config.toml"
  grep -q '^\[plugins\."user-plugin@somewhere"\]$' "$home/.codex/config.toml"
  grep -q '^\[plugins\."github@openai-curated"\]$' "$home/.codex/config.toml"
}

@test "Codex config merge script preserves local MCP servers while adding managed ones" {
  local home="$BATS_TEST_TMPDIR/home"
  mkdir -p "$home/.config/codex" "$home/.codex"
  stage_codex_managed_config "$home"

  cat >"$home/.codex/config.toml" <<'EOF'
[mcp_servers.github]
url = "https://api.githubcopilot.com/mcp/"
bearer_token_env_var = "GITHUB_PAT_TOKEN"
EOF

  env -u CODEX_HOME HOME="$home" bash "$CODEX_MANAGED_CONFIG_SYNC"

  grep -q '^\[mcp_servers\.github\]$' "$home/.codex/config.toml"
  grep -q '^url = "https://api.githubcopilot.com/mcp/"$' "$home/.codex/config.toml"
  grep -q '^\[mcp_servers\.context7\]$' "$home/.codex/config.toml"
  grep -q '^\[mcp_servers\.serena\]$' "$home/.codex/config.toml"
}

@test "Codex config merge script also updates existing Codex Desktop home" {
  local home="$BATS_TEST_TMPDIR/home"
  mkdir -p "$home/.config/codex" "$home/.codex" "$home/.codex-app"
  stage_codex_managed_config "$home"

  cat >"$home/.codex-app/config.toml" <<'EOF'
[projects."/home/ubuntu/workspace/desktop"]
trust_level = "trusted"
EOF

  env -u CODEX_HOME HOME="$home" bash "$CODEX_MANAGED_CONFIG_SYNC"

  assert_codex_managed_values "$home/.codex/config.toml" "$home/.codex-app/config.toml"
  grep -q '^\[mcp_servers\.context7\]$' "$home/.codex/config.toml"
  grep -q '^\[mcp_servers\.serena\]$' "$home/.codex/config.toml"
  grep -q '^\[mcp_servers\.context7\]$' "$home/.codex-app/config.toml"
  grep -q '^\[mcp_servers\.serena\]$' "$home/.codex-app/config.toml"
  grep -q '^\[projects\."/home/ubuntu/workspace/desktop"\]$' "$home/.codex-app/config.toml"
}

@test "Codex config merge script writes to native and CODEX_HOME when set" {
  local home="$BATS_TEST_TMPDIR/home"
  stage_codex_managed_config "$home"
  local codex_home="$BATS_TEST_TMPDIR/codex-home"
  mkdir -p "$home/.config/codex" "$codex_home"

  cat >"$home/.config/codex/config.toml" <<'EOF'
model = "gpt-6.1-sol"
model_reasoning_effort = "xhigh"
model_reasoning_summary = "concise"
model_verbosity = "medium"
personality = "pragmatic"

[agents]
default_subagent_model = "gpt-6-luna"
default_subagent_reasoning_effort = "xhigh"
max_concurrent_threads_per_session = 3

[features]
daemon_auto_start = false
network_proxy = true

[apps.github]
default_tools_approval_mode = "approve"
destructive_enabled = false

[plugins."github@openai-curated"]
enabled = true

[plugins."chrome@openai-bundled"]
enabled = true

[plugins."ponytail@ponytail"]
enabled = true

[plugins."example-curated@openai-curated"]
enabled = true

[plugins."example-local-plugin@example-marketplace"]
enabled = true
EOF

  cat >"$codex_home/config.toml" <<'EOF'
[projects."/home/ubuntu/workspace/example"]
trust_level = "trusted"
EOF

  HOME="$home" CODEX_HOME="$codex_home" bash "$CODEX_MANAGED_CONFIG_SYNC"

  assert_codex_managed_values "$home/.codex/config.toml" "$codex_home/config.toml"
  grep -q '^\[plugins\."example-curated@openai-curated"\]$' "$codex_home/config.toml"
  grep -q '^\[plugins\."example-local-plugin@example-marketplace"\]$' "$codex_home/config.toml"
  grep -q '^\[projects\."/home/ubuntu/workspace/example"\]$' "$codex_home/config.toml"
}

@test "Codex config merge script writes to native and WSL CODEX_HOME" {
  local home="$BATS_TEST_TMPDIR/home"
  local codex_home="$BATS_TEST_TMPDIR/wsl-codex-home"
  mkdir -p "$home/.config/codex" "$codex_home"

  stage_codex_managed_config "$home"

  HOME="$home" WSL_DISTRO_NAME="Ubuntu-24.04" CODEX_HOME="$codex_home" \
    bash "$CODEX_MANAGED_CONFIG_SYNC"

  assert_codex_managed_values "$home/.codex/config.toml" "$codex_home/config.toml"
}

@test "Codex config merge script removes deprecated codex_hooks feature flag" {
  local home="$BATS_TEST_TMPDIR/home"
  stage_codex_managed_config "$home"
  mkdir -p "$home/.config/codex" "$home/.codex"

  cat >"$home/.config/codex/config.toml" <<'EOF'
[features]
hooks = true
EOF

  cat >"$home/.codex/config.toml" <<'EOF'
[features]
codex_hooks = true
EOF

  env -u CODEX_HOME HOME="$home" bash "$CODEX_MANAGED_CONFIG_SYNC"

  grep -q '^\[features\]$' "$home/.codex/config.toml"
  grep -q '^hooks = true$' "$home/.codex/config.toml"
  ! grep -q '^codex_hooks = ' "$home/.codex/config.toml"
}

@test "Codex config merge script migrates legacy :project_roots filesystem key" {
  local home="$BATS_TEST_TMPDIR/home"
  mkdir -p "$home/.config/codex" "$home/.codex"
  stage_codex_managed_config "$home"

  cat >"$home/.codex/config.toml" <<'EOF'
[permissions.dotfiles-secure.filesystem.":project_roots"]
"**/*.key" = "none"
EOF

  env -u CODEX_HOME HOME="$home" bash "$CODEX_MANAGED_CONFIG_SYNC"

  ! grep -q '^\[permissions\.dotfiles-secure\.filesystem\.":project_roots"\]$' "$home/.codex/config.toml"
  grep -q '^\[permissions\.dotfiles-secure\.filesystem\.":workspace_roots"\]$' "$home/.codex/config.toml"
}

@test "Codex config merge script strips stale managed filesystem rules" {
  local home="$BATS_TEST_TMPDIR/home"
  local codex_home="$BATS_TEST_TMPDIR/orca-codex-home"
  mkdir -p "$home/.config/codex" "$home/.codex" "$codex_home"
  stage_codex_managed_config "$home"

  # Codex self-expands :workspace_roots into a concrete-path table and writes it
  # back. Older managed config also wrote static .git rules and protected-home
  # deny globs. The merge must drop them while keeping baselines like :minimal.
  cat >"$home/.codex/config.toml" <<'EOF'
[permissions.dotfiles-secure.filesystem]
":minimal" = "read"
"/home/ubuntu/ghq/github.com/treflebonbon/dotfiles/.git" = "write"
"~/.ssh" = "deny"
"~/.aws" = "deny"
"~/.config/gcloud" = "deny"
"~/.ssh/**" = "deny"
"~/.aws/**" = "deny"
"~/.config/gcloud/**" = "deny"

[permissions.dotfiles-secure.filesystem.":workspace_roots"]
".git" = "write"
"**/.env*" = "deny"
"**/.env" = "deny"

[permissions.dotfiles-secure.filesystem."/home/ubuntu/.local/share/chezmoi"]
"." = "write"
"**/*.key" = "none"

[permissions.dotfiles-secure.filesystem."/home/ubuntu/.config/protected"]
"**/credentials.json" = "deny"

[permissions.dotfiles-secure.filesystem."/tmp/codex"]
"." = "write"
"**/private-fixture.txt" = "deny"
EOF
  cp "$home/.codex/config.toml" "$codex_home/config.toml"

  HOME="$home" CODEX_HOME="$codex_home" bash "$CODEX_MANAGED_CONFIG_SYNC"

  python3 - "$home/.codex/config.toml" "$codex_home/config.toml" <<'PY'
import sys
import tomllib

for path in sys.argv[1:]:
    with open(path, "rb") as f:
        config = tomllib.load(f)

    filesystem = config["permissions"]["dotfiles-secure"]["filesystem"]
    assert filesystem[":minimal"] == "read"
    assert "/home/ubuntu/ghq/github.com/treflebonbon/dotfiles/.git" not in filesystem
    assert "/home/ubuntu/.local/share/chezmoi" not in filesystem
    assert "~/.ssh/**" not in filesystem
    assert "~/.aws/**" not in filesystem
    assert "~/.config/gcloud/**" not in filesystem
    assert "~/.ssh" not in filesystem
    assert "~/.aws" not in filesystem
    assert "~/.config/gcloud" not in filesystem
    assert filesystem["/home/ubuntu/.config/protected"] == {
        "**/credentials.json": "deny"
    }
    assert filesystem["/tmp/codex"]["."] == "write"
    assert filesystem["/tmp/codex"]["**/private-fixture.txt"] == "deny"
    assert ".git" not in filesystem[":workspace_roots"]
    assert "**/.env*" not in filesystem[":workspace_roots"]
    assert "**/.env" not in filesystem[":workspace_roots"]
    assert filesystem[":workspace_roots"][".env"] == "deny"
    assert filesystem[":workspace_roots"]["*/**/.env"] == "deny"
    assert filesystem[":root"] == "deny"
PY
  cp "$home/.codex/config.toml" "$home/first-sync.toml"
  cp "$codex_home/config.toml" "$home/codex-home-first-sync.toml"
  HOME="$home" CODEX_HOME="$codex_home" bash "$CODEX_MANAGED_CONFIG_SYNC"
  cmp "$home/first-sync.toml" "$home/.codex/config.toml"
  cmp "$home/codex-home-first-sync.toml" "$codex_home/config.toml"
}

@test "Codex config merge script keeps path rules in user-defined profiles" {
  local home="$BATS_TEST_TMPDIR/home"
  mkdir -p "$home/.config/codex" "$home/.codex"
  stage_codex_managed_config "$home"

  # A profile the dotfiles do not manage may carry legitimate path-scoped rules.
  # Cleanup must be restricted to managed profiles and leave these untouched.
  cat >"$home/.codex/config.toml" <<'EOF'
[permissions.project-edit.filesystem."/opt/sdk"]
"." = "read"
"build/**" = "write"

[permissions.project-edit.filesystem.":workspace_roots"]
"**/.env*" = "deny"
EOF

  env -u CODEX_HOME HOME="$home" bash "$CODEX_MANAGED_CONFIG_SYNC"

  grep -q '^\[permissions\.project-edit\.filesystem\."/opt/sdk"\]$' "$home/.codex/config.toml"
  grep -q '^"\." = "read"$' "$home/.codex/config.toml"
  grep -q '^"build/\*\*" = "write"$' "$home/.codex/config.toml"
  grep -Fq '"**/.env*" = "deny"' "$home/.codex/config.toml"
}

@test "Codex sandbox keeps public files readable with two independent denied-file masks" {
  local fixture_home="$BATS_TEST_TMPDIR/home"
  local workspace="$BATS_TEST_TMPDIR/workspace"
  mkdir -p "$fixture_home/.codex" "$workspace"
  printf 'fixture\n' >"$workspace/.env.example"
  printf 'dummy\n' >"$workspace/first.key"
  printf 'dummy\n' >"$workspace/second.key"
  cat >"$fixture_home/.codex/config.toml" <<'EOF'
[permissions.test]
extends = ":workspace"
[permissions.test.filesystem.":workspace_roots"]
"first.key" = "deny"
"second.key" = "deny"
EOF

  run env HOME="$fixture_home" CODEX_HOME="$fixture_home/.codex" TMPDIR=/tmp \
    codex sandbox -P test -C "$workspace" -- \
    sh -c 'test "$(cat .env.example)" = fixture'
  [ "$status" -eq 0 ]
  local path
  for path in first.key second.key; do
    run env HOME="$fixture_home" CODEX_HOME="$fixture_home/.codex" TMPDIR=/tmp \
      codex sandbox -P test -C "$workspace" -- cat "$path"
    [ "$status" -ne 0 ]
    [[ "$output" == *'Permission denied'* ]]
  done
}

@test "Codex config migration keeps dotenv denied and public examples readable without a raw read grant" {
  local fixture_home="$BATS_TEST_TMPDIR/home"
  local workspace="$BATS_TEST_TMPDIR/workspace"
  local codex_home path plugin_rev source_root receipt legacy_backup
  local state_home="${XDG_STATE_HOME:-$fixture_home/.local/state}"
  mkdir -p "$fixture_home/.codex" "$fixture_home/.codex-app" "$workspace/nested" "$fixture_home/other-repo"
  stage_codex_managed_config "$fixture_home"
  plugin_rev="$(jq -r '.rev' "$PROJECT_ROOT/private_dot_config/nix-devshell/skills-plugin.json")"
  source_root="$fixture_home/.cache/treflebonbon-skills/marketplaces/$plugin_rev"
  receipt="$state_home/treflebonbon-skills/plugin-sync/receipt.json"
  legacy_backup="$state_home/treflebonbon-skills/legacy/$(jq -r '.revision' "$PROJECT_ROOT/.chezmoitemplates/local-skills-legacy.json")/baseline.json"
  for path in .env .envrc .env.example .env.local nested/.env private.key credentials.json; do
    printf 'fixture\n' >"$workspace/$path"
  done
  printf 'fixture\n' >"$fixture_home/other-repo/.env"

  for codex_home in "$fixture_home/.codex" "$fixture_home/.codex-app"; do
    cat >"$codex_home/config.toml" <<'EOF'
[permissions.dotfiles-secure.filesystem.":workspace_roots"]
"**/.env*" = "deny"
EOF
  done

  env -u CODEX_HOME HOME="$fixture_home" bash "$CODEX_MANAGED_CONFIG_SYNC"
  for codex_home in "$fixture_home/.codex" "$fixture_home/.codex-app"; do
    assert_dotfiles_permission_profile "$codex_home/config.toml"
    cp "$codex_home/config.toml" "$codex_home/first-sync.toml"

    for path in \
      "$fixture_home/.config/nix-devshell/skills-plugin.json" \
      "$source_root/README.md" "$receipt" "$legacy_backup"; do
      run env HOME="$fixture_home" CODEX_HOME="$codex_home" TMPDIR=/tmp \
        codex sandbox -P dotfiles-secure -C "$workspace" -- cat "$path"
      if [ "$status" -ne 0 ]; then
        printf 'sandbox read failed (exit %s): %s\n' "$status" "$output" >&3
        return 1
      fi
      case "$path" in
      */skills-plugin.json) [[ "$output" == *"$plugin_rev"* ]] ;;
      */README.md) [[ "$output" == *PUBLIC_SOURCE_READABLE* ]] ;;
      */receipt.json) [[ "$output" == *'"verified"'* ]] ;;
      */baseline.json) [[ "$output" == *'"revision"'* ]] ;;
      esac
    done

    run env HOME="$fixture_home" CODEX_HOME="$codex_home" TMPDIR=/tmp \
      codex sandbox -P dotfiles-secure -C "$workspace" -- cat .env
    [ "$status" -ne 0 ]

    for path in .envrc .env.example; do
      run env HOME="$fixture_home" CODEX_HOME="$codex_home" TMPDIR=/tmp \
        codex sandbox -P dotfiles-secure -C "$workspace" -- \
        sh -c 'test "$(cat "$1")" = fixture' _ "$path"
      [ "$status" -eq 0 ]
    done

    run env HOME="$fixture_home" CODEX_HOME="$codex_home" TMPDIR=/tmp \
      codex sandbox -P dotfiles-secure -C "$workspace" -- \
      sh -c 'printf overwritten >.env'
    [ "$status" -ne 0 ]
    [ "$(cat "$workspace/.env")" = fixture ]

    for path in \
      .env .env.local nested/.env private.key credentials.json \
      "$fixture_home/.config/gh/.env" "$fixture_home/.config/git/.env" \
      "$fixture_home/.local/bin/.env" "$fixture_home/other-repo/.env"; do
      run env HOME="$fixture_home" CODEX_HOME="$codex_home" TMPDIR=/tmp \
        codex sandbox -P dotfiles-secure -C "$workspace" -- cat "$path"
      if [ "$status" -eq 0 ]; then
        printf 'unexpectedly readable path: %s\n' "$path" >&3
      fi
      [ "$status" -ne 0 ]
    done
  done

  env -u CODEX_HOME HOME="$fixture_home" bash "$CODEX_MANAGED_CONFIG_SYNC"
  for codex_home in "$fixture_home/.codex" "$fixture_home/.codex-app"; do
    cmp "$codex_home/first-sync.toml" "$codex_home/config.toml"
  done
}

@test "Codex sandbox reads only the verified treflebonbon skill cache and keeps secret names denied" {
  local fixture_home="$BATS_TEST_TMPDIR/home"
  local workspace="$BATS_TEST_TMPDIR/workspace"
  local probe="$BATS_TEST_TMPDIR/plugin-cache-probe.sh"
  local bwrap bash_path store_path env_path
  unset XDG_STATE_HOME
  mkdir -p "$fixture_home" "$workspace"
  prepare_codex_permission_roots "$fixture_home"
  : >"$SKILLS_PLUGIN_SYNC_LOG"
  cat >"$probe" <<'SH'
#!/usr/bin/env bash
set -euo pipefail

mkdir -p "$HOME/.config/codex/environments" "$HOME/.config/codex/rules" \
  "$HOME/.codex-app" "$HOME/explicit-codex-home"
chezmoi --source /repo --destination "$HOME" execute-template \
  -f /repo/private_dot_config/codex/config.toml.tmpl >"$HOME/.config/codex/config.toml"
cp /repo/private_dot_config/codex/hooks.json "$HOME/.config/codex/hooks.json"
cp /repo/private_dot_config/codex/rules/default.rules "$HOME/.config/codex/rules/default.rules"
cp /repo/private_dot_config/codex/environments/environment.toml \
  "$HOME/.config/codex/environments/environment.toml"
cp /repo/private_dot_config/codex/AGENTS.md "$HOME/.config/codex/AGENTS.md"
CODEX_HOME="$HOME/explicit-codex-home" bash \
  /repo/private_dot_local/bin/executable_sync-codex-managed-config
version="$(python3 -c 'import json; print(json.load(open("/repo/private_dot_config/nix-devshell/skills-plugin.json"))["version"])')"

for codex_home in "$HOME/.codex" "$HOME/.codex-app" "$HOME/explicit-codex-home"; do
  install="$codex_home/plugins/cache/treflebonbon/treflebonbon-skills/$version"
  cache_root="$(dirname "$install")"
  printf 'dummy secret\n' >"$install/credentials.json"
  for secret_name in private.key identity.pem bundle.pfx bundle.p12 credentials.prod.json \
    secret.json secrets.json service-account-prod.json; do
    printf 'dummy secret\n' >"$install/$secret_name"
  done
  printf 'cache parent\n' >"$cache_root/parent.txt"
  mkdir -p "$cache_root/0.0.0-stale/skills/fixture" \
    "$codex_home/plugins/cache/unrelated/plugin"
  printf 'stale\n' >"$cache_root/0.0.0-stale/skills/fixture/SKILL.md"
  printf 'unrelated\n' >"$codex_home/plugins/cache/unrelated/plugin/SKILL.md"
  printf 'dummy secret\n' >"$codex_home/plugins/cache/unrelated/plugin/credentials.json"

  for path in "$install/skills/fixture/SKILL.md" \
    "$install/skills/fixture/references/usage.md"; do
    output="$(CODEX_HOME="$codex_home" codex sandbox -P dotfiles-secure \
      -C /work -- cat "$path" 2>&1)" || {
      printf 'sandbox read failed for %s: %s\n' "$path" "$output" >&2
      exit 1
    }
    [[ "$output" == *fixture* ]]
  done

  for path in "$cache_root/parent.txt" \
    "$cache_root/0.0.0-stale/skills/fixture/SKILL.md" \
    "$codex_home/plugins/cache/unrelated/plugin/SKILL.md" \
    "$install/credentials.json" "$install/private.key" "$install/identity.pem" \
    "$install/bundle.pfx" "$install/bundle.p12" "$install/credentials.prod.json" \
    "$install/secret.json" "$install/secrets.json" "$install/service-account-prod.json" \
    "$codex_home/plugins/cache/unrelated/plugin/credentials.json"; do
    if CODEX_HOME="$codex_home" codex sandbox -P dotfiles-secure \
      -C /work -- cat "$path" >/dev/null 2>&1; then
      printf 'unexpectedly readable cache path: %s\n' "$path" >&2
      exit 1
    fi
  done
done
printf 'CACHE_SANDBOX_PASS\n'
SH

  bwrap="$(command -v bwrap)"
  bash_path="$(command -v bash)"
  store_path="$(python3 -c 'import os; print(":".join(path for path in os.environ["PATH"].split(":") if path.startswith("/nix/store/")))')"
  env_path="$(python3 -c 'import os; print(next(path + "/env" for path in os.environ["PATH"].split(":") if path.startswith("/nix/store/") and os.access(path + "/env", os.X_OK)))')"

  run "$bwrap" --unshare-all --die-with-parent --new-session \
    --tmpfs / --dev /dev --proc /proc \
    --dir /nix --dir /nix/store --ro-bind /nix/store /nix/store \
    --dir /tmp --dir /tmp/codex \
    --dir /home --dir /home/probe --bind "$fixture_home" /home/probe \
    --dir /work --bind "$workspace" /work \
    --dir /repo --ro-bind "$PROJECT_ROOT" /repo \
    --dir /run --dir /run/bin \
    --ro-bind "$probe" /run/plugin-cache-probe.sh \
    --ro-bind "$BATS_TEST_TMPDIR/runtime-bin/sync-skills-plugin" /run/bin/sync-skills-plugin \
    --bind "$SKILLS_PLUGIN_SYNC_LOG" /run/plugin-sync.log \
    --dir /usr --dir /usr/bin --ro-bind "$env_path" /usr/bin/env \
    --setenv PATH "/run/bin:$store_path" \
    --setenv PROJECT_ROOT /repo \
    --setenv SKILLS_PLUGIN_SYNC_LOG /run/plugin-sync.log \
    --setenv HOME /home/probe \
    --setenv CODEX_HOME /home/probe/.codex \
    --setenv XDG_CONFIG_HOME /home/probe/.config \
    --setenv XDG_CACHE_HOME /home/probe/.cache \
    --setenv XDG_DATA_HOME /home/probe/.local/share \
    --setenv XDG_STATE_HOME /home/probe/.local/state \
    --setenv PONYTAIL_MARKETPLACE_SOURCE "" \
    --setenv TMPDIR /tmp \
    --chdir /work "$bash_path" /run/plugin-cache-probe.sh

  [ "$status" -eq 0 ] || printf '%s\n' "$output" >&3
  [[ "$output" == *CACHE_SANDBOX_PASS* ]]
}

@test "Codex config migration preserves an explicitly managed broad dotenv deny" {
  local fixture_home="$BATS_TEST_TMPDIR/home"
  mkdir -p "$fixture_home/.codex"
  stage_codex_managed_config "$fixture_home"
  cat >"$fixture_home/.config/codex/config.toml" <<'EOF'
[permissions.dotfiles-secure.filesystem.":workspace_roots"]
"**/.env*" = "deny"
EOF
  cp "$fixture_home/.config/codex/config.toml" "$fixture_home/.codex/config.toml"

  env -u CODEX_HOME HOME="$fixture_home" bash "$CODEX_MANAGED_CONFIG_SYNC"

  grep -Fq '"**/.env*" = "deny"' "$fixture_home/.codex/config.toml"
}

@test "Codex config merge script does not overwrite invalid existing config" {
  local home="$BATS_TEST_TMPDIR/home"
  stage_codex_managed_config "$home"
  mkdir -p "$home/.config/codex" "$home/.codex"

  cat >"$home/.config/codex/config.toml" <<'EOF'
model = "gpt-6.1-sol"
EOF
  printf 'model = \n' >"$home/.codex/config.toml"

  run env -u CODEX_HOME HOME="$home" bash "$CODEX_MANAGED_CONFIG_SYNC"

  [ "$status" -ne 0 ]
  [ "$(cat "$home/.codex/config.toml")" = "model = " ]
}

@test "Claude settings remain direct-managed instead of merge-managed" {
  [ -f "$PROJECT_ROOT/private_dot_claude/settings.json.tmpl" ]
  [ ! -f "$PROJECT_ROOT/run_onchange_after_claude-settings.sh.tmpl" ]
  ! grep -R "settings.local.json" "$PROJECT_ROOT"/run_onchange_after_*.sh.tmpl 2>/dev/null
}
