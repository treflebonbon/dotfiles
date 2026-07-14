#!/usr/bin/env bats

setup() {
  PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
}

@test "Codex config managed fragment exists without local state tables" {
  local config="$PROJECT_ROOT/private_dot_config/codex/config.toml"

  [ -f "$config" ]
  grep -q '^model = "gpt-5.6-terra"$' "$config"
  grep -q '^model_reasoning_effort = ' "$config"
  grep -q '^personality = ' "$config"
  grep -q '^approval_policy = "on-request"$' "$config"
  grep -q '^approvals_reviewer = "auto_review"$' "$config"
  grep -q '^sandbox_mode = "workspace-write"$' "$config"
  grep -q '^default_permissions = "dotfiles-secure"$' "$config"
  grep -q '^\[features\]' "$config"
  grep -q '^hooks = true$' "$config"
  grep -q '^goals = true$' "$config"
  grep -q '^\[mcp_servers\.context7\]$' "$config"
  grep -q '^command = "bunx"$' "$config"
  grep -q '^args = \["-y", "@upstash/context7-mcp"\]$' "$config"
  grep -q '^\[mcp_servers\.serena\]$' "$config"
  grep -q '^command = "uvx"$' "$config"
  grep -q 'git+https://github.com/oraios/serena' "$config"
  grep -q '^\[permissions\."dotfiles-secure"\.filesystem\]' "$config"
  grep -q '^":workspace_roots" = .*"\*\*/\.env\*" = "none"' "$config"
  grep -q '^":workspace_roots" = .*"\*\*/\*\.pem" = "none"' "$config"
  grep -q '^"~/\.ssh/\*\*" = "none"$' "$config"
  grep -q '^"~/\.aws/\*\*" = "none"$' "$config"
  grep -q '^"~/\.config/gcloud/\*\*" = "none"$' "$config"
  ! grep -q '^codex_hooks = ' "$config"
  grep -q '^\[plugins\."github@openai-curated"\]' "$config"
  ! grep -q '^\[plugins\."superpowers@openai-curated"\]' "$config"
  ! grep -q '^\[projects\.' "$config"
  ! grep -q '^\[notice\.' "$config"
  ! grep -q '^\[tui\.' "$config"
}

@test "Codex runtime directory remains unmanaged by chezmoi" {
  local ignore="$PROJECT_ROOT/.chezmoiignore"

  grep -q '^\.codex$' "$ignore"
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
  grep -q '<default_to_action>' "$agents"
  grep -q '<investigate_before_answering>' "$agents"
  grep -q '<use_parallel_tool_calls>' "$agents"
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

assert data == {
    "hooks": {
        "PostToolUse": [
            {
                "matcher": "Edit|Write|apply_patch",
                "hooks": [
                    {
                        "type": "command",
                        "command": "test -f \"$HOME/.agents/skills/impeccable/scripts/hook.mjs\" || exit 0; output=\"$(IMPECCABLE_HOOK_QUIET=1 node \"$HOME/.agents/skills/impeccable/scripts/hook.mjs\" 2>/dev/null)\" || exit 0; printf '%s' \"$output\"",
                        "timeout": 5,
                    }
                ],
            }
        ]
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

assert data["hooks"]["PreToolUse"] == [
    {
        "matcher": "Bash",
        "hooks": [{"type": "command", "command": "rtk hook claude"}],
    }
]
assert data["hooks"]["PostToolUse"] == [
    {
        "matcher": "Edit|Write|MultiEdit",
        "hooks": [
            {
                "type": "command",
                "command": "test -f \"$HOME/.claude/skills/impeccable/scripts/hook.mjs\" || exit 0; output=\"$(IMPECCABLE_HOOK_QUIET=1 node \"$HOME/.claude/skills/impeccable/scripts/hook.mjs\" 2>/dev/null)\" || exit 0; printf '%s' \"$output\"",
                "timeout": 5,
            }
        ],
    }
]
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

for path in sys.argv[1:]:
    with open(path, encoding="utf-8") as f:
        data = json.load(f)
    print(data["hooks"]["PostToolUse"][0]["hooks"][0]["command"])
PY
  )

  [ "${#commands[@]}" -eq 2 ]
  local command
  for command in "${commands[@]}"; do
    run env HOME="$home" bash -c "$command"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
  done

  printf 'process.stdout.write("finding");\n' >"$home/.agents/skills/impeccable/scripts/hook.mjs"
  printf 'process.stdout.write("finding");\n' >"$home/.claude/skills/impeccable/scripts/hook.mjs"
  for command in "${commands[@]}"; do
    run env HOME="$home" bash -c "$command"
    [ "$status" -eq 0 ]
    [ "$output" = "finding" ]
  done
}

@test "Codex rules managed file blocks destructive commands" {
  local rules="$PROJECT_ROOT/private_dot_config/codex/rules/default.rules"

  [ -f "$rules" ]
  grep -q 'pattern = \[\["sudo", "su"\]\]' "$rules"
  grep -q 'pattern = \["chmod", "777"\]' "$rules"
  grep -q 'pattern = \["terraform", \["apply", "destroy"\]\]' "$rules"
  grep -q 'pattern = \["kubectl", "delete"\]' "$rules"
  grep -q 'pattern = \["gh", "repo", "delete"\]' "$rules"
  grep -q 'pattern = \["git", "push", \["-f", "--force", "--force-with-lease"\]\]' "$rules"
  grep -q 'pattern = \["rm", \["-r", "-R", "-rf", "-fr"\]\]' "$rules"
  grep -q 'decision = "forbidden"' "$rules"
  grep -q 'decision = "prompt"' "$rules"
  grep -q 'match = \[' "$rules"
  grep -q 'not_match = \[' "$rules"
}


@test "bash_profile routes Codex Desktop sessions to .codex-app" {
  local profile="$PROJECT_ROOT/dot_bash_profile.tmpl"

  grep -q 'CODEX_INTERNAL_ORIGINATOR_OVERRIDE' "$profile"
  grep -q 'CODEX_HOME="$HOME/.codex-app"' "$profile"
  grep -q 'mkdir -p "$CODEX_HOME/sessions" "$CODEX_HOME/worktrees"' "$profile"
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

@test "Codex AGENTS deploy script writes to CODEX_HOME when set" {
  local home="$BATS_TEST_TMPDIR/home"
  local codex_home="$BATS_TEST_TMPDIR/codex-home"
  mkdir -p "$home/.config/codex" "$codex_home"
  cp "$PROJECT_ROOT/private_dot_config/codex/AGENTS.md" \
    "$home/.config/codex/AGENTS.md"

  HOME="$home" CODEX_HOME="$codex_home" bash "$PROJECT_ROOT/run_onchange_after_codex-agents.sh.tmpl"

  [ ! -f "$home/.codex/AGENTS.md" ]
  [ -f "$codex_home/AGENTS.md" ]
  grep -q '^# Guidelines$' "$codex_home/AGENTS.md"
}

@test "Codex AGENTS deploy script respects WSL CODEX_HOME" {
  local home="$BATS_TEST_TMPDIR/home"
  local codex_home="$BATS_TEST_TMPDIR/wsl-codex-home"
  mkdir -p "$home/.config/codex" "$codex_home"
  cp "$PROJECT_ROOT/private_dot_config/codex/AGENTS.md" \
    "$home/.config/codex/AGENTS.md"

  HOME="$home" WSL_DISTRO_NAME="Ubuntu-24.04" CODEX_HOME="$codex_home" \
    bash "$PROJECT_ROOT/run_onchange_after_codex-agents.sh.tmpl"

  [ ! -f "$home/.codex/AGENTS.md" ]
  [ -f "$codex_home/AGENTS.md" ]
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

@test "Codex hooks deploy script writes to CODEX_HOME when set" {
  local home="$BATS_TEST_TMPDIR/home"
  local codex_home="$BATS_TEST_TMPDIR/codex-home"
  mkdir -p "$home/.config/codex" "$codex_home"
  cp "$PROJECT_ROOT/private_dot_config/codex/hooks.json" \
    "$home/.config/codex/hooks.json"

  HOME="$home" CODEX_HOME="$codex_home" bash "$PROJECT_ROOT/run_onchange_after_codex-hooks.sh.tmpl"

  [ ! -f "$home/.codex/hooks.json" ]
  [ -f "$codex_home/hooks.json" ]
  cmp "$home/.config/codex/hooks.json" "$codex_home/hooks.json"
}

@test "Codex hooks deploy script respects WSL CODEX_HOME" {
  local home="$BATS_TEST_TMPDIR/home"
  local codex_home="$BATS_TEST_TMPDIR/wsl-codex-home"
  mkdir -p "$home/.config/codex" "$codex_home"
  cp "$PROJECT_ROOT/private_dot_config/codex/hooks.json" \
    "$home/.config/codex/hooks.json"

  HOME="$home" WSL_DISTRO_NAME="Ubuntu-24.04" CODEX_HOME="$codex_home" \
    bash "$PROJECT_ROOT/run_onchange_after_codex-hooks.sh.tmpl"

  [ ! -f "$home/.codex/hooks.json" ]
  [ -f "$codex_home/hooks.json" ]
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

@test "Codex rules deploy script writes to CODEX_HOME when set" {
  local home="$BATS_TEST_TMPDIR/home"
  local codex_home="$BATS_TEST_TMPDIR/codex-home"
  mkdir -p "$home/.config/codex/rules" "$codex_home"
  cp "$PROJECT_ROOT/private_dot_config/codex/rules/default.rules" \
    "$home/.config/codex/rules/default.rules"

  HOME="$home" CODEX_HOME="$codex_home" bash "$PROJECT_ROOT/run_onchange_after_codex-rules.sh.tmpl"

  [ ! -f "$home/.codex/rules/default.rules" ]
  [ -f "$codex_home/rules/default.rules" ]
  grep -q 'pattern = \["git", "push", \["-f", "--force", "--force-with-lease"\]\]' "$codex_home/rules/default.rules"
  [ "$(stat -c %a "$codex_home/rules/default.rules")" = "600" ]
}

@test "Codex rules deploy script respects WSL CODEX_HOME" {
  local home="$BATS_TEST_TMPDIR/home"
  local codex_home="$BATS_TEST_TMPDIR/wsl-codex-home"
  mkdir -p "$home/.config/codex/rules" "$codex_home"
  cp "$PROJECT_ROOT/private_dot_config/codex/rules/default.rules" \
    "$home/.config/codex/rules/default.rules"

  HOME="$home" WSL_DISTRO_NAME="Ubuntu-24.04" CODEX_HOME="$codex_home" \
    bash "$PROJECT_ROOT/run_onchange_after_codex-rules.sh.tmpl"

  [ ! -f "$home/.codex/rules/default.rules" ]
  [ -f "$codex_home/rules/default.rules" ]
  grep -q 'pattern = \[\["sudo", "su"\]\]' "$codex_home/rules/default.rules"
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

@test "Codex environment deploy script writes to CODEX_HOME when set" {
  local home="$BATS_TEST_TMPDIR/home"
  local codex_home="$BATS_TEST_TMPDIR/codex-home"
  mkdir -p "$home/.config/codex/environments" "$codex_home"
  cp "$PROJECT_ROOT/private_dot_config/codex/environments/environment.toml" \
    "$home/.config/codex/environments/environment.toml"

  HOME="$home" CODEX_HOME="$codex_home" bash "$PROJECT_ROOT/run_onchange_after_codex-environment.sh.tmpl"

  [ ! -f "$home/.codex/environments/environment.toml" ]
  [ -f "$codex_home/environments/environment.toml" ]
  grep -q '^name = "default"$' "$codex_home/environments/environment.toml"
}

@test "Codex environment deploy script respects WSL CODEX_HOME" {
  local home="$BATS_TEST_TMPDIR/home"
  local codex_home="$BATS_TEST_TMPDIR/wsl-codex-home"
  mkdir -p "$home/.config/codex/environments" "$codex_home"
  cp "$PROJECT_ROOT/private_dot_config/codex/environments/environment.toml" \
    "$home/.config/codex/environments/environment.toml"

  HOME="$home" WSL_DISTRO_NAME="Ubuntu-24.04" CODEX_HOME="$codex_home" \
    bash "$PROJECT_ROOT/run_onchange_after_codex-environment.sh.tmpl"

  [ ! -f "$home/.codex/environments/environment.toml" ]
  [ -f "$codex_home/environments/environment.toml" ]
  grep -q '^name = "default"$' "$codex_home/environments/environment.toml"
}

@test "Codex config merge script writes managed permission profile" {
  local home="$BATS_TEST_TMPDIR/home"
  mkdir -p "$home/.config/codex" "$home/.codex"
  cp "$PROJECT_ROOT/private_dot_config/codex/config.toml" \
    "$home/.config/codex/config.toml"

  env -u CODEX_HOME HOME="$home" bash "$PROJECT_ROOT/run_onchange_after_codex-config.sh.tmpl"

  grep -q '^approval_policy = "on-request"$' "$home/.codex/config.toml"
  grep -q '^approvals_reviewer = "auto_review"$' "$home/.codex/config.toml"
  grep -q '^sandbox_mode = "workspace-write"$' "$home/.codex/config.toml"
  grep -q '^default_permissions = "dotfiles-secure"$' "$home/.codex/config.toml"
  grep -q '^\[permissions\.dotfiles-secure\.filesystem\]$' "$home/.codex/config.toml"
  grep -q '^glob_scan_max_depth = 4$' "$home/.codex/config.toml"
  grep -q '^\[permissions\.dotfiles-secure\.filesystem\.":workspace_roots"\]$' "$home/.codex/config.toml"
  grep -q '^"\*\*/\.env\*" = "none"$' "$home/.codex/config.toml"
  grep -q '^"~/\.ssh/\*\*" = "none"$' "$home/.codex/config.toml"
  grep -q '^\[mcp_servers\.context7\]$' "$home/.codex/config.toml"
  grep -q '^args = \["-y", "@upstash/context7-mcp"\]$' "$home/.codex/config.toml"
  grep -q '^\[mcp_servers\.serena\]$' "$home/.codex/config.toml"
  grep -q 'git+https://github.com/oraios/serena' "$home/.codex/config.toml"
}

@test "Codex config merge script preserves local project trust and app state" {
  local home="$BATS_TEST_TMPDIR/home"
  mkdir -p "$home/.config/codex" "$home/.codex"

  cat >"$home/.config/codex/config.toml" <<'EOF'
model = "gpt-5.6-terra"
model_reasoning_effort = "medium"
personality = "pragmatic"

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

  grep -q '^model = "gpt-5.6-terra"$' "$home/.codex/config.toml"
  grep -q '^model_reasoning_effort = "medium"$' "$home/.codex/config.toml"
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
  cp "$PROJECT_ROOT/private_dot_config/codex/config.toml" \
    "$home/.config/codex/config.toml"

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
  cp "$PROJECT_ROOT/private_dot_config/codex/config.toml" \
    "$home/.config/codex/config.toml"

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
  cp "$PROJECT_ROOT/private_dot_config/codex/config.toml" \
    "$home/.config/codex/config.toml"

  cat >"$home/.codex-app/config.toml" <<'EOF'
[projects."/home/ubuntu/workspace/desktop"]
trust_level = "trusted"
EOF

  env -u CODEX_HOME HOME="$home" bash "$PROJECT_ROOT/run_onchange_after_codex-config.sh.tmpl"

  grep -q '^\[mcp_servers\.context7\]$' "$home/.codex/config.toml"
  grep -q '^\[mcp_servers\.serena\]$' "$home/.codex/config.toml"
  grep -q '^\[mcp_servers\.context7\]$' "$home/.codex-app/config.toml"
  grep -q '^\[mcp_servers\.serena\]$' "$home/.codex-app/config.toml"
  grep -q '^\[projects\."/home/ubuntu/workspace/desktop"\]$' "$home/.codex-app/config.toml"
}

@test "Codex config merge script writes to CODEX_HOME when set" {
  local home="$BATS_TEST_TMPDIR/home"
  local codex_home="$BATS_TEST_TMPDIR/codex-home"
  mkdir -p "$home/.config/codex" "$codex_home"

  cat >"$home/.config/codex/config.toml" <<'EOF'
model = "gpt-5.6-terra"
model_reasoning_effort = "medium"
personality = "pragmatic"

[plugins."github@openai-curated"]
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

  [ ! -f "$home/.codex/config.toml" ]
  grep -q '^model = "gpt-5.6-terra"$' "$codex_home/config.toml"
  grep -q '^\[plugins\."example-curated@openai-curated"\]$' "$codex_home/config.toml"
  grep -q '^\[plugins\."example-local-plugin@example-marketplace"\]$' "$codex_home/config.toml"
  grep -q '^\[projects\."/home/ubuntu/workspace/example"\]$' "$codex_home/config.toml"
}

@test "Codex config merge script respects WSL CODEX_HOME" {
  local home="$BATS_TEST_TMPDIR/home"
  local codex_home="$BATS_TEST_TMPDIR/wsl-codex-home"
  mkdir -p "$home/.config/codex" "$codex_home"

  cat >"$home/.config/codex/config.toml" <<'EOF'
model = "gpt-5.6-terra"

[plugins."example-local-plugin@example-marketplace"]
enabled = true
EOF

  HOME="$home" WSL_DISTRO_NAME="Ubuntu-24.04" CODEX_HOME="$codex_home" \
    bash "$PROJECT_ROOT/run_onchange_after_codex-config.sh.tmpl"

  [ ! -f "$home/.codex/config.toml" ]
  [ -f "$codex_home/config.toml" ]
  grep -q '^model = "gpt-5.6-terra"$' "$codex_home/config.toml"
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
  cp "$PROJECT_ROOT/private_dot_config/codex/config.toml" \
    "$home/.config/codex/config.toml"

  cat >"$home/.codex/config.toml" <<'EOF'
[permissions.dotfiles-secure.filesystem.":project_roots"]
"**/*.key" = "none"
EOF

  env -u CODEX_HOME HOME="$home" bash "$PROJECT_ROOT/run_onchange_after_codex-config.sh.tmpl"

  ! grep -q '^\[permissions\.dotfiles-secure\.filesystem\.":project_roots"\]$' "$home/.codex/config.toml"
  grep -q '^\[permissions\.dotfiles-secure\.filesystem\.":workspace_roots"\]$' "$home/.codex/config.toml"
}

@test "Codex config merge script strips stale concrete-path filesystem roots" {
  local home="$BATS_TEST_TMPDIR/home"
  mkdir -p "$home/.config/codex" "$home/.codex"
  cp "$PROJECT_ROOT/private_dot_config/codex/config.toml" \
    "$home/.config/codex/config.toml"

  # Codex self-expands :workspace_roots into a concrete-path table and writes it
  # back. Newer Codex then rejects its suffix-glob denies on load. The merge must
  # drop it while keeping scalar/glob baselines like :minimal.
  cat >"$home/.codex/config.toml" <<'EOF'
[permissions.dotfiles-secure.filesystem]
":minimal" = "read"

[permissions.dotfiles-secure.filesystem."/home/ubuntu/.local/share/chezmoi"]
"." = "write"
"**/*.key" = "none"
EOF

  env -u CODEX_HOME HOME="$home" bash "$PROJECT_ROOT/run_onchange_after_codex-config.sh.tmpl"

  ! grep -q '^\[permissions\.dotfiles-secure\.filesystem\."/home/ubuntu/\.local/share/chezmoi"\]$' "$home/.codex/config.toml"
  grep -q '^\[permissions\.dotfiles-secure\.filesystem\.":workspace_roots"\]$' "$home/.codex/config.toml"
  grep -q '^":minimal" = "read"$' "$home/.codex/config.toml"
}

@test "Codex config merge script keeps path rules in user-defined profiles" {
  local home="$BATS_TEST_TMPDIR/home"
  mkdir -p "$home/.config/codex" "$home/.codex"
  cp "$PROJECT_ROOT/private_dot_config/codex/config.toml" \
    "$home/.config/codex/config.toml"

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
model = "gpt-5.6-terra"
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
