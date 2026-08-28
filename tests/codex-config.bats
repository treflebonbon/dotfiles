#!/usr/bin/env bats

setup() {
  PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  export CODEX_ORCA="$PROJECT_ROOT/private_dot_local/bin/executable_codex-orca"
  export CODEX_CONTEXT="$PROJECT_ROOT/private_dot_local/bin/executable_codex-context"
  export CODEX_WORKTREE="$PROJECT_ROOT/private_dot_local/bin/executable_codex-worktree"
  export CODEX_MANAGED_CONFIG_SYNC="$PROJECT_ROOT/private_dot_local/bin/executable_sync-codex-managed-config"
  CODEX_SOURCE_GIT_COMMON_DIR="$(git -C "$PROJECT_ROOT" rev-parse --path-format=absolute --git-common-dir)"
  export CODEX_SOURCE_GIT_COMMON_DIR
}

install_codex_package_test_commands() {
  local bin="$1"
  mkdir -p "$bin"
  ln -s "$CODEX_CONTEXT" "$bin/codex-context"
  ln -s "$CODEX_ORCA" "$bin/codex-orca"
  ln -s "$CODEX_WORKTREE" "$bin/codex-worktree"
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

@test "codex-worktree launches Codex at a linked worktree with only its active Git metadata boundary" {
  local repo="$BATS_TEST_TMPDIR/repo"
  local worktree="$BATS_TEST_TMPDIR/worktree"
  local bin="$BATS_TEST_TMPDIR/bin"
  local git_dir
  local git_common_dir
  mkdir -p "$bin"
  create_linked_worktree "$repo" "$worktree"
  git_dir="$(git -C "$worktree" rev-parse --path-format=absolute --git-dir)"
  git_common_dir="$(git -C "$worktree" rev-parse --path-format=absolute --git-common-dir)"

  cat >"$bin/codex" <<'EOF'
#!/usr/bin/env bash
printf 'TMPDIR=<%s>\n' "$TMPDIR"
printf 'GIT_DIR=<%s>\n' "${GIT_DIR-unset}"
printf 'GIT_COMMON_DIR=<%s>\n' "${GIT_COMMON_DIR-unset}"
printf 'GIT_WORK_TREE=<%s>\n' "${GIT_WORK_TREE-unset}"
printf 'CODEX_PERMISSION_PROFILE=<%s>\n' "${CODEX_PERMISSION_PROFILE-unset}"
printf 'arg=<%s>\n' "$@"
EOF
  chmod +x "$bin/codex"

  run env PATH="$bin:$PATH" TMPDIR="$BATS_TEST_TMPDIR/nested-tmp" \
    GIT_DIR="$repo/.git" GIT_COMMON_DIR="$repo/.git" GIT_WORK_TREE="$repo" \
    CODEX_PERMISSION_PROFILE=unrestricted \
    bash -c 'cd "$1" && exec "$2" --model "model with space" "prompt with space"' \
    _ "$worktree" "$CODEX_WORKTREE"

  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "TMPDIR=</tmp>" ]
  [ "${lines[1]}" = "GIT_DIR=<unset>" ]
  [ "${lines[2]}" = "GIT_COMMON_DIR=<unset>" ]
  [ "${lines[3]}" = "GIT_WORK_TREE=<unset>" ]
  [ "${lines[4]}" = "CODEX_PERMISSION_PROFILE=<unset>" ]
  [ "${lines[5]}" = "arg=<-C>" ]
  [ "${lines[6]}" = "arg=<$worktree>" ]
  [ "${lines[7]}" = "arg=<-c>" ]
  [ "${lines[8]}" = 'arg=<default_permissions="dotfiles-secure">' ]
  [ "${lines[9]}" = "arg=<-c>" ]
  [ "${lines[10]}" = \
    "arg=<permissions.dotfiles-secure.filesystem={\"$git_dir\"=\"write\",\"$git_common_dir\"=\"write\"}>" ]
  [ "${lines[11]}" = "arg=<--model>" ]
  [ "${lines[12]}" = "arg=<model with space>" ]
  [ "${lines[13]}" = "arg=<prompt with space>" ]
}

@test "codex-worktree launches Codex when linked-worktree metadata uses relative paths" {
  local repo="$BATS_TEST_TMPDIR/repo"
  local worktree="$BATS_TEST_TMPDIR/worktree"
  local bin="$BATS_TEST_TMPDIR/bin"
  local launched="$BATS_TEST_TMPDIR/codex-launched"
  create_linked_worktree "$repo" "$worktree" relative
  install_codex_launch_sentinel "$bin"
  grep -q '^gitdir: \.\.' "$worktree/.git"

  run env PATH="$bin:$PATH" CODEX_LAUNCHED="$launched" bash -c \
    'cd "$1" && exec "$2"' _ "$worktree" "$CODEX_WORKTREE"

  [ "$status" -eq 0 ]
  [ -e "$launched" ]
}

@test "codex-worktree rejects a primary checkout without launching Codex" {
  local repo="$BATS_TEST_TMPDIR/repo"
  local bin="$BATS_TEST_TMPDIR/bin"
  local launched="$BATS_TEST_TMPDIR/codex-launched"
  mkdir -p "$repo"
  git -C "$repo" init -q
  install_codex_launch_sentinel "$bin"

  run env PATH="$bin:$PATH" CODEX_LAUNCHED="$launched" bash -c \
    'cd "$1" && exec "$2"' _ "$repo" "$CODEX_WORKTREE"

  [ "$status" -ne 0 ]
  [ ! -e "$launched" ]
}

@test "codex-worktree rejects a non-Git directory without launching Codex" {
  local workspace="$BATS_TEST_TMPDIR/workspace"
  local bin="$BATS_TEST_TMPDIR/bin"
  local launched="$BATS_TEST_TMPDIR/codex-launched"
  mkdir -p "$workspace"
  install_codex_launch_sentinel "$bin"

  run env PATH="$bin:$PATH" CODEX_LAUNCHED="$launched" bash -c \
    'cd "$1" && exec "$2"' _ "$workspace" "$CODEX_WORKTREE"

  [ "$status" -ne 0 ]
  [ ! -e "$launched" ]
}

@test "codex-worktree rejects unresolved linked-worktree metadata without launching Codex" {
  local repo="$BATS_TEST_TMPDIR/repo"
  local worktree="$BATS_TEST_TMPDIR/worktree"
  local bin="$BATS_TEST_TMPDIR/bin"
  local launched="$BATS_TEST_TMPDIR/codex-launched"
  local git_dir
  create_linked_worktree "$repo" "$worktree"
  git_dir="$(git -C "$worktree" rev-parse --path-format=absolute --git-dir)"
  mv "$git_dir" "$git_dir.unresolved"
  install_codex_launch_sentinel "$bin"

  run env PATH="$bin:$PATH" CODEX_LAUNCHED="$launched" bash -c \
    'cd "$1" && exec "$2"' _ "$worktree" "$CODEX_WORKTREE"

  [ "$status" -ne 0 ]
  [ ! -e "$launched" ]
}

@test "codex-worktree rejects linked-worktree metadata owned by another repository without launching Codex" {
  local repo="$BATS_TEST_TMPDIR/repo"
  local foreign_repo="$BATS_TEST_TMPDIR/foreign-repo"
  local worktree="$BATS_TEST_TMPDIR/worktree"
  local bin="$BATS_TEST_TMPDIR/bin"
  local launched="$BATS_TEST_TMPDIR/codex-launched"
  local git_dir
  local foreign_common_dir
  create_linked_worktree "$repo" "$worktree"
  git_dir="$(git -C "$worktree" rev-parse --path-format=absolute --git-dir)"
  git -C "$BATS_TEST_TMPDIR" init -q "$foreign_repo"
  foreign_common_dir="$(git -C "$foreign_repo" rev-parse --path-format=absolute --git-common-dir)"
  printf '%s\n' "$foreign_common_dir" >"$git_dir/commondir"
  install_codex_launch_sentinel "$bin"

  run env PATH="$bin:$PATH" CODEX_LAUNCHED="$launched" bash -c \
    'cd "$1" && exec "$2"' _ "$worktree" "$CODEX_WORKTREE"

  [ "$status" -ne 0 ]
  [ ! -e "$launched" ]
}

@test "codex-worktree rejects arguments that can replace its working, permission, or trust boundary" {
  local repo="$BATS_TEST_TMPDIR/repo"
  local worktree="$BATS_TEST_TMPDIR/worktree"
  local bin="$BATS_TEST_TMPDIR/bin"
  local launched="$BATS_TEST_TMPDIR/codex-launched"
  create_linked_worktree "$repo" "$worktree"
  install_codex_launch_sentinel "$bin"

  assert_codex_worktree_rejects_boundary_argument "$worktree" "$bin" "$launched" \
    -C "$BATS_TEST_TMPDIR/elsewhere"
  assert_codex_worktree_rejects_boundary_argument "$worktree" "$bin" "$launched" \
    --cd="$BATS_TEST_TMPDIR/elsewhere"
  assert_codex_worktree_rejects_boundary_argument "$worktree" "$bin" "$launched" \
    --add-dir "$BATS_TEST_TMPDIR/elsewhere"
  assert_codex_worktree_rejects_boundary_argument "$worktree" "$bin" "$launched" \
    -c 'permissions.dotfiles-secure.filesystem={"/"="write"}'
  assert_codex_worktree_rejects_boundary_argument "$worktree" "$bin" "$launched" \
    --config='default_permissions="danger-full-access"'
  assert_codex_worktree_rejects_boundary_argument "$worktree" "$bin" "$launched" \
    --disable network_proxy
  assert_codex_worktree_rejects_boundary_argument "$worktree" "$bin" "$launched" \
    --disable=network_proxy
  assert_codex_worktree_rejects_boundary_argument "$worktree" "$bin" "$launched" \
    --enable network_proxy
  assert_codex_worktree_rejects_boundary_argument "$worktree" "$bin" "$launched" \
    --enable=network_proxy
  assert_codex_worktree_rejects_boundary_argument "$worktree" "$bin" "$launched" \
    features disable network_proxy
  assert_codex_worktree_rejects_boundary_argument "$worktree" "$bin" "$launched" \
    features enable network_proxy
  assert_codex_worktree_rejects_boundary_argument "$worktree" "$bin" "$launched" \
    exec --sandbox danger-full-access prompt
  assert_codex_worktree_rejects_boundary_argument "$worktree" "$bin" "$launched" \
    --dangerously-bypass-approvals-and-sandbox
  assert_codex_worktree_rejects_boundary_argument "$worktree" "$bin" "$launched" \
    --yolo
  assert_codex_worktree_rejects_boundary_argument "$worktree" "$bin" "$launched" \
    --dangerously-bypass-hook-trust
  assert_codex_worktree_rejects_boundary_argument "$worktree" "$bin" "$launched" \
    --profile unrestricted
  assert_codex_worktree_rejects_boundary_argument "$worktree" "$bin" "$launched" \
    --approve-for-me
  assert_codex_worktree_rejects_boundary_argument "$worktree" "$bin" "$launched" \
    exec --ignore-user-config prompt
  assert_codex_worktree_rejects_boundary_argument "$worktree" "$bin" "$launched" \
    exec --ignore-rules prompt
  assert_codex_worktree_rejects_boundary_argument "$worktree" "$bin" "$launched" \
    sandbox --permission-profile unrestricted -- true
  assert_codex_worktree_rejects_boundary_argument "$worktree" "$bin" "$launched" \
    sandbox --permissions-profile=unrestricted -- true
  assert_codex_worktree_rejects_boundary_argument "$worktree" "$bin" "$launched" \
    sandbox --sandbox-state-json '{}' -- true
}

@test "codex-orca preserves every argument when forwarding to codex-worktree" {
  local bin="$BATS_TEST_TMPDIR/bin"
  mkdir -p "$bin"
  cat >"$bin/codex-worktree" <<'EOF'
#!/usr/bin/env bash
printf 'forwarded=<%s>\n' "$@"
EOF
  cat >"$bin/codex" <<'EOF'
#!/usr/bin/env bash
printf 'wrong-entrypoint\n'
EOF
  chmod +x "$bin/codex-worktree" "$bin/codex"

  run env PATH="$bin:$PATH" "$CODEX_ORCA" --model "model with space" "" "prompt with space"

  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "forwarded=<--model>" ]
  [ "${lines[1]}" = "forwarded=<model with space>" ]
  [ "${lines[2]}" = "forwarded=<>" ]
  [ "${lines[3]}" = "forwarded=<prompt with space>" ]
  [ "${#lines[@]}" -eq 4 ]
}

assert_codex_managed_values() {
  python3 - "$@" <<'PY'
import sys
import tomllib

for path in sys.argv[1:]:
    with open(path, "rb") as f:
        config = tomllib.load(f)

    assert config["model"] == "gpt-5.6-sol"
    assert config["model_reasoning_effort"] == "xhigh"
    assert config["model_reasoning_summary"] == "concise"
    assert config["model_verbosity"] == "medium"
    assert config["personality"] == "pragmatic"
    assert config["agents"] == {
        "default_subagent_model": "gpt-5.6-luna",
        "default_subagent_reasoning_effort": "high",
        "max_concurrent_threads_per_session": 3,
    }
    assert "service_tier" not in config
    assert "developer_instructions" not in config
    assert config["features"]["network_proxy"] is True
    assert config["apps"]["github"]["default_tools_approval_mode"] == "approve"
    assert config["apps"]["github"]["destructive_enabled"] is False
    assert config["plugins"]["github@openai-curated"]["enabled"] is True
    assert config["plugins"]["chrome@openai-bundled"]["enabled"] is True
PY
}

assert_dotfiles_permission_profile() {
  python3 - "$@" <<'PY'
import os
import sys
import tomllib

expected_domains = {
    "registry.npmjs.org": "allow",
    "**.github.com": "allow",
    "**.githubusercontent.com": "allow",
    "**.context7.com": "allow",
    "**.pypi.org": "allow",
    "files.pythonhosted.org": "allow",
    "**.python.org": "allow",
    "cache.nixos.org": "allow",
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
    assert filesystem[":workspace_roots"]["."] == "write"
    assert ".git" not in filesystem[":workspace_roots"]
    assert os.environ["CODEX_SOURCE_GIT_COMMON_DIR"] not in filesystem
    assert filesystem[":workspace_roots"]["**/.env"] == "deny"
    assert filesystem[":workspace_roots"]["**/.env[!.r]*"] == "deny"
    assert filesystem[":workspace_roots"]["**/.envr"] == "deny"
    assert filesystem[":workspace_roots"]["**/.envr[!c]*"] == "deny"
    assert filesystem[":workspace_roots"]["**/.envrc?*"] == "deny"
    assert filesystem[":workspace_roots"]["**/.env.example?*"] == "deny"
    assert "**/.env*" not in filesystem[":workspace_roots"]
    assert "**/.envrc" not in filesystem[":workspace_roots"]
    assert "**/.env.example" not in filesystem[":workspace_roots"]
    assert filesystem["~/.ssh"] == "deny"
    assert filesystem["~/.aws"] == "deny"
    assert filesystem["~/.config/gcloud"] == "deny"
PY
}

stage_codex_managed_config() {
  local home="$1"
  mkdir -p "$home/.config/codex/environments" "$home/.config/codex/rules"
  render_codex_managed_config "$PROJECT_ROOT" "$home/.config/codex/config.toml"
  cp "$PROJECT_ROOT/private_dot_config/codex/hooks.json" "$home/.config/codex/hooks.json"
  cp "$PROJECT_ROOT/private_dot_config/codex/rules/default.rules" "$home/.config/codex/rules/default.rules"
  cp "$PROJECT_ROOT/private_dot_config/codex/environments/environment.toml" "$home/.config/codex/environments/environment.toml"
  cp "$PROJECT_ROOT/private_dot_config/codex/AGENTS.md" "$home/.config/codex/AGENTS.md"
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
  mkdir -p "$source/private_dot_config" "$source/private_dot_local/bin"
  cp -R "$PROJECT_ROOT/private_dot_config/codex" "$source/private_dot_config/codex"
  cp "$PROJECT_ROOT/private_dot_local/bin/executable_sync-codex-managed-config" \
    "$source/private_dot_local/bin/executable_sync-codex-managed-config"
  cp "$PROJECT_ROOT/dot_bash_profile.tmpl" "$source/dot_bash_profile.tmpl"
  cp "$PROJECT_ROOT"/run_onchange_after_codex-*.sh.tmpl "$source/"
  git -C "$source" init -q
}

render_codex_managed_config() {
  local source="$1"
  local destination="$2"
  chezmoi --source "$source" execute-template \
    -f "$PROJECT_ROOT/private_dot_config/codex/config.toml.tmpl" \
    >"$destination"
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
  grep -q '^model = "gpt-5.6-sol"$' "$config"
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
  grep -q '^"\*\*/\.env" = "deny"$' "$config"
  grep -q '^"\*\*/\*\.pem" = "deny"$' "$config"
  grep -q '^"~/\.ssh" = "deny"$' "$config"
  grep -q '^"~/\.aws" = "deny"$' "$config"
  grep -q '^"~/\.config/gcloud" = "deny"$' "$config"
  ! grep -q '^codex_hooks = ' "$config"
  grep -q '^\[plugins\."github@openai-curated"\]' "$config"
  ! grep -q '^\[plugins\."superpowers@openai-curated"\]' "$config"
  ! grep -q '^\[projects\.' "$config"
  ! grep -q '^\[notice\.' "$config"
  ! grep -q '^\[tui\.' "$config"
  assert_codex_managed_values "$config"
  assert_dotfiles_permission_profile "$config"
}

@test "Codex strict parser accepts rendered and merged managed config" {
  local home="$BATS_TEST_TMPDIR/home"
  local codex_home="$BATS_TEST_TMPDIR/codex-home"
  mkdir -p "$home/.config/codex" "$home/.codex-app" "$codex_home"
  render_codex_managed_config "$PROJECT_ROOT" "$home/.config/codex/config.toml"

  assert_codex_strict_config "$home/.config/codex"

  HOME="$home" CODEX_HOME="$codex_home" bash "$PROJECT_ROOT/run_onchange_after_codex-config.sh.tmpl"

  assert_codex_strict_config "$home/.codex"
  assert_codex_strict_config "$home/.codex-app"
  assert_codex_strict_config "$codex_home"
}

@test "dotfiles-secure sandbox starts without expanding protected home trees" {
  local home="$BATS_TEST_TMPDIR/home"
  local workspace="$BATS_TEST_TMPDIR/workspace"
  local codex_home="$home/.codex"
  mkdir -p "$workspace" "$codex_home" "$home/.ssh"
  printf 'protected\n' >"$home/.ssh/config"
  render_codex_managed_config "$PROJECT_ROOT" "$codex_home/config.toml"

  run env HOME="$home" CODEX_HOME="$codex_home" TMPDIR=/tmp \
    codex sandbox -P dotfiles-secure -C "$workspace" -- true

  [ "$status" -eq 0 ]

  run env HOME="$home" CODEX_HOME="$codex_home" TMPDIR=/tmp \
    codex sandbox -P dotfiles-secure -C "$workspace" -- \
    sh -c 'printf "overwritten\\n" >"$HOME/.ssh/config"'

  [ "$status" -ne 0 ]
  [ "$(cat "$home/.ssh/config")" = "protected" ]
}

@test "dotfiles-secure permits Environment Contract Files while preserving secret denies" {
  local home="$BATS_TEST_TMPDIR/home"
  local workspace="$BATS_TEST_TMPDIR/workspace"
  local codex_home="$home/.codex"
  local path
  mkdir -p "$workspace/one/two/three" "$codex_home"
  render_codex_managed_config "$PROJECT_ROOT" "$codex_home/config.toml"

  assert_dotfiles_permission_profile "$codex_home/config.toml"
  grep -q '^\*\*Environment Contract File\*\*:' "$PROJECT_ROOT/CONTEXT.md"

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
  mkdir -p "$workspace" "$codex_home"
  render_codex_managed_config "$PROJECT_ROOT" "$codex_home/config.toml"
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

  if [[ "$output" != *"CONNECT tunnel failed, response 403"* ]]; then
    printf 'non-allowlisted command network request had an unexpected failure:\n%s\n' "$output" >&3
  fi
  [ "$status" -ne 0 ]
  [[ "$output" == *"CONNECT tunnel failed, response 403"* ]]
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

@test "bun codex routes a valid linked worktree through the canonical adapter without losing arguments" {
  local repo="$BATS_TEST_TMPDIR/repo"
  local worktree="$BATS_TEST_TMPDIR/worktree"
  local bin="$BATS_TEST_TMPDIR/bin"
  local git_dir
  local git_common_dir
  create_linked_worktree "$repo" "$worktree"
  stage_codex_package_launcher "$worktree" "$bin"
  git_dir="$(git -C "$worktree" rev-parse --path-format=absolute --git-dir)"
  git_common_dir="$(git -C "$worktree" rev-parse --path-format=absolute --git-common-dir)"

  cat >"$bin/codex" <<'EOF'
#!/usr/bin/env bash
printf 'arg=<%s>\n' "$@"
EOF
  chmod +x "$bin/codex"

  run env PATH="$bin:$PATH" bash -c \
    'cd "$1" && exec bun --silent codex --model "model with space" "" "prompt with space"' \
    _ "$worktree"

  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "arg=<-C>" ]
  [ "${lines[1]}" = "arg=<$worktree>" ]
  [ "${lines[2]}" = "arg=<-c>" ]
  [ "${lines[3]}" = 'arg=<default_permissions="dotfiles-secure">' ]
  [ "${lines[4]}" = "arg=<-c>" ]
  [ "${lines[5]}" = \
    "arg=<permissions.dotfiles-secure.filesystem={\"$git_dir\"=\"write\",\"$git_common_dir\"=\"write\"}>" ]
  [ "${lines[6]}" = "arg=<--model>" ]
  [ "${lines[7]}" = "arg=<model with space>" ]
  [ "${lines[8]}" = "arg=<>" ]
  [ "${lines[9]}" = "arg=<prompt with space>" ]
  [ "${#lines[@]}" -eq 10 ]
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

@test "bun codex fails closed for unresolved linked-worktree metadata without launching Codex" {
  local repo="$BATS_TEST_TMPDIR/repo"
  local worktree="$BATS_TEST_TMPDIR/worktree"
  local bin="$BATS_TEST_TMPDIR/bin"
  local launched="$BATS_TEST_TMPDIR/codex-launched"
  local git_dir
  create_linked_worktree "$repo" "$worktree"
  stage_codex_package_launcher "$worktree" "$bin"
  install_codex_launch_sentinel "$bin"
  git_dir="$(git -C "$worktree" rev-parse --path-format=absolute --git-dir)"
  printf '%s\n' "$BATS_TEST_TMPDIR/missing/.git" >"$git_dir/gitdir"

  run env PATH="$bin:$PATH" CODEX_LAUNCHED="$launched" bash -c \
    'cd "$1" && exec bun --silent codex prompt' _ "$worktree"

  [ "$status" -ne 0 ]
  [[ "$output" == *"codex-worktree: linked worktree metadata ownership does not match"* ]]
  [ ! -e "$launched" ]
}

@test "codex-worktree permits linked-worktree Git writes while protected paths stay denied" {
  local home="$BATS_TEST_TMPDIR/home"
  local repo_a="$BATS_TEST_TMPDIR/repo-a"
  local repo_b="$BATS_TEST_TMPDIR/repo-b"
  local worktree_b="$BATS_TEST_TMPDIR/worktree-b"
  local remote="$worktree_b/remote"
  local bin="$BATS_TEST_TMPDIR/bin"
  local codex_home="$home/.codex"
  local base_head
  local topic_head
  mkdir -p "$repo_a" "$codex_home" "$bin"

  git -C "$repo_a" init -q
  create_linked_worktree "$repo_b" "$worktree_b"
  git init -q --bare "$remote"
  git --git-dir "$remote" symbolic-ref HEAD refs/heads/main
  git -C "$repo_b" remote add origin "$remote"
  git -C "$repo_b" push -q origin HEAD:main
  cp "$PROJECT_ROOT/private_dot_local/bin/executable_git-push-topic" "$bin/git-push-topic"
  chmod +x "$bin/git-push-topic"
  render_codex_managed_config "$repo_a" "$codex_home/config.toml"
  base_head="$(git -C "$worktree_b" rev-parse HEAD)"

  printf 'linked\n' >"$worktree_b/linked.txt"
  run env HOME="$home" CODEX_HOME="$codex_home" TMPDIR=/tmp codex sandbox -P dotfiles-secure \
    -C "$worktree_b" -- git add linked.txt

  [ "$status" -ne 0 ]
  [ -z "$(git -C "$worktree_b" diff --cached --name-only)" ]

  run env HOME="$home" CODEX_HOME="$codex_home" \
    TMPDIR="$BATS_TEST_TMPDIR/nested-tmp" \
    GIT_DIR="$repo_a/.git" GIT_COMMON_DIR="$repo_a/.git" bash -c \
    'cd "$1" && exec "$2" sandbox -P dotfiles-secure -- git add linked.txt' \
    _ "$worktree_b" "$CODEX_WORKTREE"

  [ "$status" -eq 0 ]
  [ "$(git -C "$worktree_b" diff --cached --name-only)" = "linked.txt" ]

  run env HOME="$home" CODEX_HOME="$codex_home" TMPDIR=/tmp bash -c \
    'cd "$1" && exec "$2" sandbox -P dotfiles-secure -- git commit -qm "test: linked worktree write"' \
    _ "$worktree_b" "$CODEX_WORKTREE"

  [ "$status" -eq 0 ]
  topic_head="$(git -C "$worktree_b" rev-parse HEAD)"
  [ "$topic_head" != "$base_head" ]

  run env HOME="$home" CODEX_HOME="$codex_home" PATH="$bin:$PATH" TMPDIR=/tmp bash -c \
    'cd "$1" && exec "$2" sandbox -P dotfiles-secure -- git-push-topic' \
    _ "$worktree_b" "$CODEX_WORKTREE"

  [ "$status" -eq 0 ]
  [ "$(git --git-dir "$remote" rev-parse refs/heads/linked)" = "$topic_head" ]
  [ "$(git -C "$worktree_b" config branch.linked.remote)" = "origin" ]

  printf 'protected\n' >"$worktree_b/.env"
  run env HOME="$home" CODEX_HOME="$codex_home" TMPDIR=/tmp bash -c \
    'cd "$1" && exec "$2" sandbox -P dotfiles-secure -- sh -c "printf '\''overwritten\\n'\'' >.env"' \
    _ "$worktree_b" "$CODEX_WORKTREE"

  [ "$status" -ne 0 ]
  [ "$(cat "$worktree_b/.env")" = "protected" ]
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

command = "test -f \"$HOME/.agents/skills/impeccable/scripts/hook.mjs\" || exit 0; output=\"$(IMPECCABLE_HOOK_QUIET=1 node \"$HOME/.agents/skills/impeccable/scripts/hook.mjs\" 2>/dev/null)\" || exit 0; printf '%s' \"$output\""

# Stop carries no matcher (it is not a tool event) and gets the upstream deep-pass
# budget of 30s instead of the per-edit 5s. Impeccable recognizes Codex's turn_id
# and emits the native top-level decision/reason schema itself, so both events use
# the same fail-open pass-through command.
assert data == {
    "hooks": {
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

@test "Claude settings keep the existing hook and add the quiet global Impeccable Design Hook" {
  local settings="$PROJECT_ROOT/private_dot_claude/settings.json.tmpl"

  python3 -m json.tool "$settings" >/dev/null
  python3 - "$settings" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as f:
    data = json.load(f)

assert data["editorMode"] == "normal"
assert data["hooks"]["PreToolUse"] == [
    {
        "matcher": "Bash",
        "hooks": [{"type": "command", "command": "rtk hook claude"}],
    }
]
command = "test -f \"$HOME/.claude/skills/impeccable/scripts/hook.mjs\" || exit 0; output=\"$(IMPECCABLE_HOOK_QUIET=1 node \"$HOME/.claude/skills/impeccable/scripts/hook.mjs\" 2>/dev/null)\" || exit 0; printf '%s' \"$output\""

assert data["hooks"]["PostToolUse"] == [
    {
        "matcher": "Edit|Write|MultiEdit",
        "hooks": [{"type": "command", "command": command, "timeout": 5}],
    }
]
# Stop carries no matcher (it is not a tool event) and gets the upstream deep-pass
# budget of 30s instead of the per-edit 5s.
assert data["hooks"]["Stop"] == [
    {"hooks": [{"type": "command", "command": command, "timeout": 30}]}
]
assert "Bash(git-push-topic:*)" in data["permissions"]["allow"]
for rule in [
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

@test "Claude auto mode is managed in user settings without a package launcher alias" {
  python3 - \
    "$PROJECT_ROOT/private_dot_claude/settings.json.tmpl" \
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
  printf 'process.stdout.write("partial"); process.stderr.write("runtime failed\\n"); process.exit(42);\n' \
    >"$home/.agents/skills/impeccable/scripts/hook.mjs"
  printf 'process.stdout.write("partial"); process.stderr.write("runtime failed\\n"); process.exit(42);\n' \
    >"$home/.claude/skills/impeccable/scripts/hook.mjs"

  mapfile -t commands < <(
    python3 - \
      "$PROJECT_ROOT/private_dot_claude/settings.json.tmpl" \
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
    run env HOME="$home" bash -c "$command"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
  done

  # The synthetic candidate runtime distinguishes Codex by turn_id and owns the
  # native Stop schema. Managed commands only preserve its stdout byte-for-byte.
  local hook_runtime_fixture='let input="";process.stdin.on("data",chunk=>input+=chunk);process.stdin.on("end",()=>{const event=JSON.parse(input);const codexStop=event.turn_id&&event.hook_event_name==="Stop";process.stdout.write(JSON.stringify(codexStop?{decision:"block",reason:"finding"}:{hookSpecificOutput:{hookEventName:event.hook_event_name,additionalContext:"finding"}}))});'
  printf '%s\n' "$hook_runtime_fixture" >"$home/.agents/skills/impeccable/scripts/hook.mjs"
  printf '%s\n' "$hook_runtime_fixture" >"$home/.claude/skills/impeccable/scripts/hook.mjs"

  local post_tool_use='{"session_id":"fixture","hook_event_name":"PostToolUse"}'
  local claude_stop='{"session_id":"fixture","hook_event_name":"Stop"}'
  local codex_post_tool_use='{"session_id":"fixture","turn_id":"turn-1","hook_event_name":"PostToolUse"}'
  local codex_stop='{"session_id":"fixture","turn_id":"turn-1","hook_event_name":"Stop"}'
  local passthrough_post_tool_use='{"hookSpecificOutput":{"hookEventName":"PostToolUse","additionalContext":"finding"}}'
  local passthrough_stop='{"hookSpecificOutput":{"hookEventName":"Stop","additionalContext":"finding"}}'
  local codex_stop_expected='{"decision":"block","reason":"finding"}'

  run env HOME="$home" bash -c "${commands[0]}" <<<"$post_tool_use"
  [ "$status" -eq 0 ]
  [ "$output" = "$passthrough_post_tool_use" ]

  run env HOME="$home" bash -c "${commands[1]}" <<<"$claude_stop"
  [ "$status" -eq 0 ]
  [ "$output" = "$passthrough_stop" ]

  run env HOME="$home" bash -c "${commands[2]}" <<<"$codex_post_tool_use"
  [ "$status" -eq 0 ]
  [ "$output" = "$passthrough_post_tool_use" ]

  run env HOME="$home" bash -c "${commands[3]}" <<<"$codex_stop"
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

  grep -q '^model = "gpt-5.6-sol"$' "$home/.codex-app/config.toml"
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

  grep -q '^model = "gpt-5.6-sol"$' "$home/.codex-app/config.toml"
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

@test "Codex AGENTS deploy script writes to native Codex home" {
  local home="$BATS_TEST_TMPDIR/home"
  mkdir -p "$home/.config/codex"
  cp "$PROJECT_ROOT/private_dot_config/codex/AGENTS.md" \
    "$home/.config/codex/AGENTS.md"

  env -u CODEX_HOME HOME="$home" bash "$PROJECT_ROOT/run_onchange_after_codex-agents.sh.tmpl"

  [ -f "$home/.codex/AGENTS.md" ]
  grep -q '^# Guidelines$' "$home/.codex/AGENTS.md"
  grep -q 'Think in English, respond in Japanese\.' "$home/.codex/AGENTS.md"
}

@test "Codex AGENTS deploy script also updates existing Codex Desktop home" {
  local home="$BATS_TEST_TMPDIR/home"
  mkdir -p "$home/.config/codex" "$home/.codex-app"
  cp "$PROJECT_ROOT/private_dot_config/codex/AGENTS.md" \
    "$home/.config/codex/AGENTS.md"

  env -u CODEX_HOME HOME="$home" bash "$PROJECT_ROOT/run_onchange_after_codex-agents.sh.tmpl"

  cmp "$home/.config/codex/AGENTS.md" "$home/.codex/AGENTS.md"
  cmp "$home/.config/codex/AGENTS.md" "$home/.codex-app/AGENTS.md"
}

@test "Codex AGENTS deploy script writes to native and CODEX_HOME when set" {
  local home="$BATS_TEST_TMPDIR/home"
  local codex_home="$BATS_TEST_TMPDIR/codex-home"
  mkdir -p "$home/.config/codex" "$codex_home"
  cp "$PROJECT_ROOT/private_dot_config/codex/AGENTS.md" \
    "$home/.config/codex/AGENTS.md"

  HOME="$home" CODEX_HOME="$codex_home" bash "$PROJECT_ROOT/run_onchange_after_codex-agents.sh.tmpl"

  cmp "$home/.config/codex/AGENTS.md" "$home/.codex/AGENTS.md"
  cmp "$home/.config/codex/AGENTS.md" "$codex_home/AGENTS.md"
  grep -q '^# Guidelines$' "$codex_home/AGENTS.md"
}

@test "Codex AGENTS deploy script writes to native and WSL CODEX_HOME" {
  local home="$BATS_TEST_TMPDIR/home"
  local codex_home="$BATS_TEST_TMPDIR/wsl-codex-home"
  mkdir -p "$home/.config/codex" "$codex_home"
  cp "$PROJECT_ROOT/private_dot_config/codex/AGENTS.md" \
    "$home/.config/codex/AGENTS.md"

  HOME="$home" WSL_DISTRO_NAME="Ubuntu-24.04" CODEX_HOME="$codex_home" \
    bash "$PROJECT_ROOT/run_onchange_after_codex-agents.sh.tmpl"

  cmp "$home/.config/codex/AGENTS.md" "$home/.codex/AGENTS.md"
  cmp "$home/.config/codex/AGENTS.md" "$codex_home/AGENTS.md"
  grep -q '^# Guidelines$' "$codex_home/AGENTS.md"
}

@test "Codex hooks deploy script writes to native Codex home" {
  local home="$BATS_TEST_TMPDIR/home"
  mkdir -p "$home/.config/codex"
  cp "$PROJECT_ROOT/private_dot_config/codex/hooks.json" \
    "$home/.config/codex/hooks.json"

  env -u CODEX_HOME HOME="$home" bash "$PROJECT_ROOT/run_onchange_after_codex-hooks.sh.tmpl"

  [ -f "$home/.codex/hooks.json" ]
  cmp "$home/.config/codex/hooks.json" "$home/.codex/hooks.json"
}

@test "Codex hooks deploy script also updates existing Codex Desktop home" {
  local home="$BATS_TEST_TMPDIR/home"
  mkdir -p "$home/.config/codex" "$home/.codex-app"
  cp "$PROJECT_ROOT/private_dot_config/codex/hooks.json" \
    "$home/.config/codex/hooks.json"

  env -u CODEX_HOME HOME="$home" bash "$PROJECT_ROOT/run_onchange_after_codex-hooks.sh.tmpl"

  cmp "$home/.config/codex/hooks.json" "$home/.codex/hooks.json"
  cmp "$home/.config/codex/hooks.json" "$home/.codex-app/hooks.json"
}

@test "Codex hooks deploy script writes to native and CODEX_HOME when set" {
  local home="$BATS_TEST_TMPDIR/home"
  local codex_home="$BATS_TEST_TMPDIR/codex-home"
  mkdir -p "$home/.config/codex" "$codex_home"
  cp "$PROJECT_ROOT/private_dot_config/codex/hooks.json" \
    "$home/.config/codex/hooks.json"

  HOME="$home" CODEX_HOME="$codex_home" bash "$PROJECT_ROOT/run_onchange_after_codex-hooks.sh.tmpl"

  cmp "$home/.config/codex/hooks.json" "$home/.codex/hooks.json"
  cmp "$home/.config/codex/hooks.json" "$codex_home/hooks.json"
}

@test "Codex hooks deploy script writes to native and WSL CODEX_HOME" {
  local home="$BATS_TEST_TMPDIR/home"
  local codex_home="$BATS_TEST_TMPDIR/wsl-codex-home"
  mkdir -p "$home/.config/codex" "$codex_home"
  cp "$PROJECT_ROOT/private_dot_config/codex/hooks.json" \
    "$home/.config/codex/hooks.json"

  HOME="$home" WSL_DISTRO_NAME="Ubuntu-24.04" CODEX_HOME="$codex_home" \
    bash "$PROJECT_ROOT/run_onchange_after_codex-hooks.sh.tmpl"

  cmp "$home/.config/codex/hooks.json" "$home/.codex/hooks.json"
  cmp "$home/.config/codex/hooks.json" "$codex_home/hooks.json"
}

@test "Codex rules deploy script writes to native Codex home" {
  local home="$BATS_TEST_TMPDIR/home"
  mkdir -p "$home/.config/codex/rules"
  cp "$PROJECT_ROOT/private_dot_config/codex/rules/default.rules" \
    "$home/.config/codex/rules/default.rules"

  env -u CODEX_HOME HOME="$home" bash "$PROJECT_ROOT/run_onchange_after_codex-rules.sh.tmpl"

  [ -f "$home/.codex/rules/default.rules" ]
  grep -q 'pattern = \["rm", \["-r", "-R", "-rf", "-fr"\]\]' "$home/.codex/rules/default.rules"
  [ "$(stat -c %a "$home/.codex/rules/default.rules")" = "600" ]
}

@test "Codex rules deploy script also updates existing Codex Desktop home" {
  local home="$BATS_TEST_TMPDIR/home"
  mkdir -p "$home/.config/codex/rules" "$home/.codex-app"
  cp "$PROJECT_ROOT/private_dot_config/codex/rules/default.rules" \
    "$home/.config/codex/rules/default.rules"

  env -u CODEX_HOME HOME="$home" bash "$PROJECT_ROOT/run_onchange_after_codex-rules.sh.tmpl"

  cmp "$home/.config/codex/rules/default.rules" "$home/.codex/rules/default.rules"
  cmp "$home/.config/codex/rules/default.rules" "$home/.codex-app/rules/default.rules"
  [ "$(stat -c %a "$home/.codex-app/rules/default.rules")" = "600" ]
}

@test "Codex rules deploy script writes to native and CODEX_HOME when set" {
  local home="$BATS_TEST_TMPDIR/home"
  local codex_home="$BATS_TEST_TMPDIR/codex-home"
  mkdir -p "$home/.config/codex/rules" "$codex_home"
  cp "$PROJECT_ROOT/private_dot_config/codex/rules/default.rules" \
    "$home/.config/codex/rules/default.rules"

  HOME="$home" CODEX_HOME="$codex_home" bash "$PROJECT_ROOT/run_onchange_after_codex-rules.sh.tmpl"

  cmp "$home/.config/codex/rules/default.rules" "$home/.codex/rules/default.rules"
  cmp "$home/.config/codex/rules/default.rules" "$codex_home/rules/default.rules"
  grep -q 'pattern = \["git", "push"\]' "$codex_home/rules/default.rules"
  [ "$(stat -c %a "$home/.codex/rules/default.rules")" = "600" ]
  [ "$(stat -c %a "$codex_home/rules/default.rules")" = "600" ]
}

@test "Codex rules deploy script writes to native and WSL CODEX_HOME" {
  local home="$BATS_TEST_TMPDIR/home"
  local codex_home="$BATS_TEST_TMPDIR/wsl-codex-home"
  mkdir -p "$home/.config/codex/rules" "$codex_home"
  cp "$PROJECT_ROOT/private_dot_config/codex/rules/default.rules" \
    "$home/.config/codex/rules/default.rules"

  HOME="$home" WSL_DISTRO_NAME="Ubuntu-24.04" CODEX_HOME="$codex_home" \
    bash "$PROJECT_ROOT/run_onchange_after_codex-rules.sh.tmpl"

  cmp "$home/.config/codex/rules/default.rules" "$home/.codex/rules/default.rules"
  cmp "$home/.config/codex/rules/default.rules" "$codex_home/rules/default.rules"
  grep -q 'pattern = \[\["sudo", "su"\]\]' "$codex_home/rules/default.rules"
  [ "$(stat -c %a "$home/.codex/rules/default.rules")" = "600" ]
  [ "$(stat -c %a "$codex_home/rules/default.rules")" = "600" ]
}

@test "Codex environment managed fragment is repo-agnostic" {
  local environment="$PROJECT_ROOT/private_dot_config/codex/environments/environment.toml"

  [ -f "$environment" ]
  grep -q '^name = "default"$' "$environment"
  grep -q "bash -ilc" "$environment"
  grep -q "direnv allow ." "$environment"
  ! grep -q "/home/ubuntu/ghq/" "$environment"
  ! grep -q "devpod status dap" "$environment"
}

@test "Codex environment deploy script writes to native Codex home" {
  local home="$BATS_TEST_TMPDIR/home"
  mkdir -p "$home/.config/codex/environments"
  cp "$PROJECT_ROOT/private_dot_config/codex/environments/environment.toml" \
    "$home/.config/codex/environments/environment.toml"

  env -u CODEX_HOME HOME="$home" bash "$PROJECT_ROOT/run_onchange_after_codex-environment.sh.tmpl"

  [ -f "$home/.codex/environments/environment.toml" ]
  grep -q '^name = "default"$' "$home/.codex/environments/environment.toml"
  grep -q "direnv allow ." "$home/.codex/environments/environment.toml"
}

@test "Codex environment deploy script also updates existing Codex Desktop home" {
  local home="$BATS_TEST_TMPDIR/home"
  mkdir -p "$home/.config/codex/environments" "$home/.codex-app"
  cp "$PROJECT_ROOT/private_dot_config/codex/environments/environment.toml" \
    "$home/.config/codex/environments/environment.toml"

  env -u CODEX_HOME HOME="$home" bash "$PROJECT_ROOT/run_onchange_after_codex-environment.sh.tmpl"

  cmp "$home/.config/codex/environments/environment.toml" "$home/.codex/environments/environment.toml"
  cmp "$home/.config/codex/environments/environment.toml" "$home/.codex-app/environments/environment.toml"
}

@test "Codex environment deploy script writes to native and CODEX_HOME when set" {
  local home="$BATS_TEST_TMPDIR/home"
  local codex_home="$BATS_TEST_TMPDIR/codex-home"
  mkdir -p "$home/.config/codex/environments" "$codex_home"
  cp "$PROJECT_ROOT/private_dot_config/codex/environments/environment.toml" \
    "$home/.config/codex/environments/environment.toml"

  HOME="$home" CODEX_HOME="$codex_home" bash "$PROJECT_ROOT/run_onchange_after_codex-environment.sh.tmpl"

  cmp "$home/.config/codex/environments/environment.toml" "$home/.codex/environments/environment.toml"
  cmp "$home/.config/codex/environments/environment.toml" "$codex_home/environments/environment.toml"
  grep -q '^name = "default"$' "$codex_home/environments/environment.toml"
}

@test "Codex environment deploy script writes to native and WSL CODEX_HOME" {
  local home="$BATS_TEST_TMPDIR/home"
  local codex_home="$BATS_TEST_TMPDIR/wsl-codex-home"
  mkdir -p "$home/.config/codex/environments" "$codex_home"
  cp "$PROJECT_ROOT/private_dot_config/codex/environments/environment.toml" \
    "$home/.config/codex/environments/environment.toml"

  HOME="$home" WSL_DISTRO_NAME="Ubuntu-24.04" CODEX_HOME="$codex_home" \
    bash "$PROJECT_ROOT/run_onchange_after_codex-environment.sh.tmpl"

  cmp "$home/.config/codex/environments/environment.toml" "$home/.codex/environments/environment.toml"
  cmp "$home/.config/codex/environments/environment.toml" "$codex_home/environments/environment.toml"
  grep -q '^name = "default"$' "$codex_home/environments/environment.toml"
}

@test "Codex config merge script writes managed permission profile" {
  local home="$BATS_TEST_TMPDIR/home"
  mkdir -p "$home/.config/codex" "$home/.codex"
  render_codex_managed_config "$PROJECT_ROOT" "$home/.config/codex/config.toml"

  cat >"$home/.codex/config.toml" <<'EOF'
sandbox_mode = "workspace-write"

[sandbox_workspace_write]
network_access = false

[permissions.dotfiles-secure.network.domains]
"pypi.org" = "allow"
"retired.example.com" = "allow"
EOF

  env -u CODEX_HOME HOME="$home" bash "$PROJECT_ROOT/run_onchange_after_codex-config.sh.tmpl"

  grep -q '^approval_policy = "on-request"$' "$home/.codex/config.toml"
  grep -q '^approvals_reviewer = "auto_review"$' "$home/.codex/config.toml"
  assert_dotfiles_permission_profile "$home/.codex/config.toml"
  grep -q '^\[permissions\.dotfiles-secure\.filesystem\]$' "$home/.codex/config.toml"
  grep -q '^glob_scan_max_depth = 4$' "$home/.codex/config.toml"
  grep -q '^\[permissions\.dotfiles-secure\.filesystem\.":workspace_roots"\]$' "$home/.codex/config.toml"
  grep -q '^"\*\*/\.env" = "deny"$' "$home/.codex/config.toml"
  grep -q '^"\*\*/\.env\.example?\*" = "deny"$' "$home/.codex/config.toml"
  grep -q '^"~/\.ssh" = "deny"$' "$home/.codex/config.toml"
  grep -q '^\[mcp_servers\.context7\]$' "$home/.codex/config.toml"
  grep -q '^args = \["-y", "@upstash/context7-mcp"\]$' "$home/.codex/config.toml"
  grep -q '^\[mcp_servers\.serena\]$' "$home/.codex/config.toml"
  grep -q 'git+https://github.com/oraios/serena' "$home/.codex/config.toml"
}

@test "Codex config merge script preserves local project trust and app state" {
  local home="$BATS_TEST_TMPDIR/home"
  mkdir -p "$home/.config/codex" "$home/.codex"

  cat >"$home/.config/codex/config.toml" <<'EOF'
model = "gpt-5.6-sol"
model_reasoning_effort = "xhigh"
model_reasoning_summary = "concise"
model_verbosity = "medium"
personality = "pragmatic"

[agents]
default_subagent_model = "gpt-5.6-luna"
default_subagent_reasoning_effort = "high"
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
model_reasoning_effort = "low"

[projects."/home/ubuntu/workspace/example"]
trust_level = "trusted"

[notice.model_migrations]
"gpt-5.4" = "gpt-5.5"

[tui.model_availability_nux]
"gpt-5.5" = 4
EOF

  env -u CODEX_HOME HOME="$home" bash "$PROJECT_ROOT/run_onchange_after_codex-config.sh.tmpl"

  grep -q '^model = "gpt-5.6-sol"$' "$home/.codex/config.toml"
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
  render_codex_managed_config "$PROJECT_ROOT" "$home/.config/codex/config.toml"

  cat >"$home/.codex/config.toml" <<'EOF'
[plugins."superpowers@openai-curated"]
enabled = true

[plugins."user-plugin@somewhere"]
enabled = true
EOF

  env -u CODEX_HOME HOME="$home" bash "$PROJECT_ROOT/run_onchange_after_codex-config.sh.tmpl"

  ! grep -q 'superpowers@openai-curated' "$home/.codex/config.toml"
  grep -q '^\[plugins\."user-plugin@somewhere"\]$' "$home/.codex/config.toml"
  grep -q '^\[plugins\."github@openai-curated"\]$' "$home/.codex/config.toml"
}

@test "Codex config merge script preserves local MCP servers while adding managed ones" {
  local home="$BATS_TEST_TMPDIR/home"
  mkdir -p "$home/.config/codex" "$home/.codex"
  render_codex_managed_config "$PROJECT_ROOT" "$home/.config/codex/config.toml"

  cat >"$home/.codex/config.toml" <<'EOF'
[mcp_servers.github]
url = "https://api.githubcopilot.com/mcp/"
bearer_token_env_var = "GITHUB_PAT_TOKEN"
EOF

  env -u CODEX_HOME HOME="$home" bash "$PROJECT_ROOT/run_onchange_after_codex-config.sh.tmpl"

  grep -q '^\[mcp_servers\.github\]$' "$home/.codex/config.toml"
  grep -q '^url = "https://api.githubcopilot.com/mcp/"$' "$home/.codex/config.toml"
  grep -q '^\[mcp_servers\.context7\]$' "$home/.codex/config.toml"
  grep -q '^\[mcp_servers\.serena\]$' "$home/.codex/config.toml"
}

@test "Codex config merge script also updates existing Codex Desktop home" {
  local home="$BATS_TEST_TMPDIR/home"
  mkdir -p "$home/.config/codex" "$home/.codex" "$home/.codex-app"
  render_codex_managed_config "$PROJECT_ROOT" "$home/.config/codex/config.toml"

  cat >"$home/.codex-app/config.toml" <<'EOF'
[projects."/home/ubuntu/workspace/desktop"]
trust_level = "trusted"
EOF

  env -u CODEX_HOME HOME="$home" bash "$PROJECT_ROOT/run_onchange_after_codex-config.sh.tmpl"

  assert_codex_managed_values "$home/.codex/config.toml" "$home/.codex-app/config.toml"
  grep -q '^\[mcp_servers\.context7\]$' "$home/.codex/config.toml"
  grep -q '^\[mcp_servers\.serena\]$' "$home/.codex/config.toml"
  grep -q '^\[mcp_servers\.context7\]$' "$home/.codex-app/config.toml"
  grep -q '^\[mcp_servers\.serena\]$' "$home/.codex-app/config.toml"
  grep -q '^\[projects\."/home/ubuntu/workspace/desktop"\]$' "$home/.codex-app/config.toml"
}

@test "Codex config merge script writes to native and CODEX_HOME when set" {
  local home="$BATS_TEST_TMPDIR/home"
  local codex_home="$BATS_TEST_TMPDIR/codex-home"
  mkdir -p "$home/.config/codex" "$codex_home"

  cat >"$home/.config/codex/config.toml" <<'EOF'
model = "gpt-5.6-sol"
model_reasoning_effort = "xhigh"
model_reasoning_summary = "concise"
model_verbosity = "medium"
personality = "pragmatic"

[agents]
default_subagent_model = "gpt-5.6-luna"
default_subagent_reasoning_effort = "high"
max_concurrent_threads_per_session = 3

[features]
network_proxy = true

[apps.github]
default_tools_approval_mode = "approve"
destructive_enabled = false

[plugins."github@openai-curated"]
enabled = true

[plugins."chrome@openai-bundled"]
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

  HOME="$home" CODEX_HOME="$codex_home" bash "$PROJECT_ROOT/run_onchange_after_codex-config.sh.tmpl"

  assert_codex_managed_values "$home/.codex/config.toml" "$codex_home/config.toml"
  grep -q '^\[plugins\."example-curated@openai-curated"\]$' "$codex_home/config.toml"
  grep -q '^\[plugins\."example-local-plugin@example-marketplace"\]$' "$codex_home/config.toml"
  grep -q '^\[projects\."/home/ubuntu/workspace/example"\]$' "$codex_home/config.toml"
}

@test "Codex config merge script writes to native and WSL CODEX_HOME" {
  local home="$BATS_TEST_TMPDIR/home"
  local codex_home="$BATS_TEST_TMPDIR/wsl-codex-home"
  mkdir -p "$home/.config/codex" "$codex_home"

  render_codex_managed_config "$PROJECT_ROOT" "$home/.config/codex/config.toml"

  HOME="$home" WSL_DISTRO_NAME="Ubuntu-24.04" CODEX_HOME="$codex_home" \
    bash "$PROJECT_ROOT/run_onchange_after_codex-config.sh.tmpl"

  assert_codex_managed_values "$home/.codex/config.toml" "$codex_home/config.toml"
}

@test "Codex config merge script removes deprecated codex_hooks feature flag" {
  local home="$BATS_TEST_TMPDIR/home"
  mkdir -p "$home/.config/codex" "$home/.codex"

  cat >"$home/.config/codex/config.toml" <<'EOF'
[features]
hooks = true
EOF

  cat >"$home/.codex/config.toml" <<'EOF'
[features]
codex_hooks = true
EOF

  env -u CODEX_HOME HOME="$home" bash "$PROJECT_ROOT/run_onchange_after_codex-config.sh.tmpl"

  grep -q '^\[features\]$' "$home/.codex/config.toml"
  grep -q '^hooks = true$' "$home/.codex/config.toml"
  ! grep -q '^codex_hooks = ' "$home/.codex/config.toml"
}

@test "Codex config merge script migrates legacy :project_roots filesystem key" {
  local home="$BATS_TEST_TMPDIR/home"
  mkdir -p "$home/.config/codex" "$home/.codex"
  render_codex_managed_config "$PROJECT_ROOT" "$home/.config/codex/config.toml"

  cat >"$home/.codex/config.toml" <<'EOF'
[permissions.dotfiles-secure.filesystem.":project_roots"]
"**/*.key" = "none"
EOF

  env -u CODEX_HOME HOME="$home" bash "$PROJECT_ROOT/run_onchange_after_codex-config.sh.tmpl"

  ! grep -q '^\[permissions\.dotfiles-secure\.filesystem\.":project_roots"\]$' "$home/.codex/config.toml"
  grep -q '^\[permissions\.dotfiles-secure\.filesystem\.":workspace_roots"\]$' "$home/.codex/config.toml"
}

@test "Codex config merge script strips stale managed filesystem rules" {
  local home="$BATS_TEST_TMPDIR/home"
  local codex_home="$BATS_TEST_TMPDIR/orca-codex-home"
  mkdir -p "$home/.config/codex" "$home/.codex" "$codex_home"
  render_codex_managed_config "$PROJECT_ROOT" "$home/.config/codex/config.toml"

  # Codex self-expands :workspace_roots into a concrete-path table and writes it
  # back. Older managed config also wrote static .git rules and protected-home
  # deny globs. The merge must drop them while keeping baselines like :minimal.
  cat >"$home/.codex/config.toml" <<'EOF'
[permissions.dotfiles-secure.filesystem]
":minimal" = "read"
"/home/ubuntu/ghq/github.com/treflebonbon/dotfiles/.git" = "write"
"~/.ssh/**" = "deny"
"~/.aws/**" = "deny"
"~/.config/gcloud/**" = "deny"

[permissions.dotfiles-secure.filesystem.":workspace_roots"]
".git" = "write"

[permissions.dotfiles-secure.filesystem."/home/ubuntu/.local/share/chezmoi"]
"." = "write"
"**/*.key" = "none"

[permissions.dotfiles-secure.filesystem."/home/ubuntu/.config/protected"]
"**/credentials.json" = "deny"
EOF
  cp "$home/.codex/config.toml" "$codex_home/config.toml"

  HOME="$home" CODEX_HOME="$codex_home" bash "$PROJECT_ROOT/run_onchange_after_codex-config.sh.tmpl"

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
    assert filesystem["~/.ssh"] == "deny"
    assert filesystem["~/.aws"] == "deny"
    assert filesystem["~/.config/gcloud"] == "deny"
    assert filesystem["/home/ubuntu/.config/protected"] == {
        "**/credentials.json": "deny"
    }
    assert ".git" not in filesystem[":workspace_roots"]
PY
}

@test "Codex config merge script keeps path rules in user-defined profiles" {
  local home="$BATS_TEST_TMPDIR/home"
  mkdir -p "$home/.config/codex" "$home/.codex"
  render_codex_managed_config "$PROJECT_ROOT" "$home/.config/codex/config.toml"

  # A profile the dotfiles do not manage may carry legitimate path-scoped rules.
  # Cleanup must be restricted to managed profiles and leave these untouched.
  cat >"$home/.codex/config.toml" <<'EOF'
[permissions.project-edit.filesystem."/opt/sdk"]
"." = "read"
"build/**" = "write"
EOF

  env -u CODEX_HOME HOME="$home" bash "$PROJECT_ROOT/run_onchange_after_codex-config.sh.tmpl"

  grep -q '^\[permissions\.project-edit\.filesystem\."/opt/sdk"\]$' "$home/.codex/config.toml"
  grep -q '^"\." = "read"$' "$home/.codex/config.toml"
  grep -q '^"build/\*\*" = "write"$' "$home/.codex/config.toml"
}

@test "Codex config merge script does not overwrite invalid existing config" {
  local home="$BATS_TEST_TMPDIR/home"
  mkdir -p "$home/.config/codex" "$home/.codex"

  cat >"$home/.config/codex/config.toml" <<'EOF'
model = "gpt-5.6-sol"
EOF
  printf 'model = \n' >"$home/.codex/config.toml"

  run env -u CODEX_HOME HOME="$home" bash "$PROJECT_ROOT/run_onchange_after_codex-config.sh.tmpl"

  [ "$status" -ne 0 ]
  [ "$(cat "$home/.codex/config.toml")" = "model = " ]
}

@test "Claude settings remain direct-managed instead of merge-managed" {
  [ -f "$PROJECT_ROOT/private_dot_claude/settings.json.tmpl" ]
  [ ! -f "$PROJECT_ROOT/run_onchange_after_claude-settings.sh.tmpl" ]
  ! grep -R "settings.local.json" "$PROJECT_ROOT"/run_onchange_after_*.sh.tmpl 2>/dev/null
}
