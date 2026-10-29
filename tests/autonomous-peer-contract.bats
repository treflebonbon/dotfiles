#!/usr/bin/env bats

bats_require_minimum_version 1.5.0

setup() {
  PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  CONTRACT="$PROJECT_ROOT/runtime/autonomous-peer-contract.md"
  AUTO_SESSION="$PROJECT_ROOT/local-skills/herdr-peer-refactor/references/auto-session.md"
}

@test "contract stays indexed and instruction layers point to the fixed plugin source" {
  [ -f "$CONTRACT" ]
  grep -Fq 'autonomous-peer-contract.md' "$PROJECT_ROOT/runtime/index.md"
  grep -Fq 'autonomous-peer-contract.md' "$PROJECT_ROOT/docs/conventions.md"
  grep -Fq 'autonomous-peer-contract.md' "$PROJECT_ROOT/runtime/skill-harness.md"
  local claude agents
  claude="$(grep -F '規範の正本は固定 plugin source' "$PROJECT_ROOT/private_dot_claude/CLAUDE.md")"
  agents="$(grep -F '規範の正本は固定 plugin source' "$PROJECT_ROOT/private_dot_config/codex/AGENTS.md")"
  [ -n "$claude" ]
  [ "$(printf '%s\n' "$claude" | wc -l)" -eq 1 ]
  [ "$claude" = "$agents" ]
}

@test "dotfiles contract resolves the fixed pin and delegates normative checks" {
  grep -Fq 'contracts/autonomous-peer-contract.md' "$CONTRACT"
  grep -Fq 'contracts/auto-peer-protection.md' "$CONTRACT"
  grep -Fq '~/.config/nix-devshell/skills-plugin.json' "$CONTRACT"
  grep -Fq 'marketplaces/<rev>/contracts/autonomous-peer-contract.md' "$CONTRACT"
  grep -Fq 'sync-skills-plugin --verify-only' "$CONTRACT"
  grep -Fq 'read-only 照合が失敗した場合は専用 auto を起動せず' "$CONTRACT"
  grep -Fq '資格情報の登録や人間の有効化は行いません' "$CONTRACT"
  for detail in 'Peer Decision' 'Held Candidate' 'topic push は `git-push-topic`'; do
    run grep -Fq "$detail" "$CONTRACT"
    [ "$status" -eq 1 ]
  done
}

@test "legacy auto-session reference keeps dedicated launch checks separate from normal invocation" {
  grep -Fq '専用起動前に配備済み' "$AUTO_SESSION"
  grep -Fq 'mock 起動テストはこの観測の検査' "$AUTO_SESSION"
  grep -Fq '実効性が確認不能なら保留' "$AUTO_SESSION"
  [ -f "$AUTO_SESSION" ]
  grep -Fq '通常の明示依頼からの peer 協働には、この起動ゲートを適用しない' "$AUTO_SESSION"
  grep -Fq 'auto-peer-deny.json' "$AUTO_SESSION"
  grep -Fq 'auto-peer.rules' "$AUTO_SESSION"
  grep -Fq '起動チェック' "$AUTO_SESSION"
  grep -Fq 'launch-child.sh' "$AUTO_SESSION"
  grep -Fq 'plan-parallel.sh' "$AUTO_SESSION"
  grep -Fq 'check-owned.sh' "$AUTO_SESSION"
  grep -Fq '親停止' "$AUTO_SESSION"
}

# peer_deny in auto-peer.rules is the single source of what a dedicated auto peer must not
# run. Both tools' settings are projections of it, and every check below reads it from there.
peer_deny() {
  python3 -I - "$PROJECT_ROOT/private_dot_config/codex/auto-peer.rules" "$@" <<'PY'
import ast, json, re, sys
from ast import literal_eval as parse_literal

src = open(sys.argv[1]).read()
records = next(
    parse_literal(n.value)
    for n in ast.parse(src).body
    if isinstance(n, ast.Assign) and n.targets[0].id == "peer_deny"
)
mode = sys.argv[2]
claude = [p for r in records for p in r["claude"]]
if mode == "projection":
    print(json.dumps({"permissions": {"deny": claude}}, indent=2))
elif mode == "codex-match":
    for r in records:
        for rule in r["codex"]:
            for cmd in rule["match"]:
                print(cmd)
elif mode == "claude-examples":
    bash_deny = [p for p in claude if p.startswith("Bash(")]

    def denied(command):
        return any(
            re.fullmatch(re.escape(p[5:-1]).replace(r"\*", ".*"), command, re.S)
            for p in bash_deny
        )

    bad = [c for r in records for c in r.get("claude_deny", []) if not denied(c)]
    bad += [c for r in records for c in r.get("claude_allow", []) if denied(c)]
    assert bad == [], bad
    assert all(p.startswith("Bash(") and p.endswith(")") for p in bash_deny)
PY
}

@test "Codex peer permission rules remain isolated and preserve the read-only credential path" {
  local rules="$PROJECT_ROOT/private_dot_config/codex/auto-peer.rules"
  local sync="$PROJECT_ROOT/private_dot_local/bin/executable_sync-codex-managed-config"
  [ -f "$rules" ]
  ! grep -Fq 'auto-peer.rules' "$sync"
  grep -Fq 'pattern = ["git", "push"]' "$PROJECT_ROOT/private_dot_config/codex/rules/default.rules"
  ! grep -Fq '"git", "push"' "$rules"
  grep -Fq 'GH_CONFIG_DIR=~/.codex-peer/gh' "$AUTO_SESSION"
  grep -Fq 'CODEX_HOME=~/.codex-peer' "$AUTO_SESSION"
  # --peer selects dotfiles-peer (tests/codex-reviewer.bats).
  grep -Fq 'codex-reviewer --peer --disable apps' "$AUTO_SESSION"
  grep -Fq '[apps.github]' "$PROJECT_ROOT/private_dot_config/codex/config.toml.tmpl"
}

@test "Codex peer rules forbid every peer_deny match; loading also validates each match and not_match" {
  local rules="$PROJECT_ROOT/private_dot_config/codex/auto-peer.rules" cmd
  local -a argv
  run peer_deny codex-match
  [ "$status" -eq 0 ]
  [ -n "$output" ]
  while IFS= read -r cmd; do
    read -r -a argv <<<"$cmd"
    run --separate-stderr codex execpolicy check --rules "$rules" -- "${argv[@]}"
    [ "$status" -eq 0 ]
    [ "$(jq -r .decision <<<"$output")" = forbidden ]
  done < <(peer_deny codex-match)
}

@test "Removing a record from peer_deny cannot silently drop the named peer prohibitions" {
  local rules="$PROJECT_ROOT/private_dot_config/codex/auto-peer.rules" cmd
  local -a argv
  for cmd in 'gh pr merge 1' 'gh -R o/r pr merge 1' 'gh --repo o/r pr merge 1' 'gh pr -R o/r merge 1' 'gh api graphql' 'git-push-reviewed'; do
    read -r -a argv <<<"$cmd"
    run --separate-stderr codex execpolicy check --rules "$rules" -- "${argv[@]}"
    [ "$(jq -r .decision <<<"$output")" = forbidden ]
  done
  # Independent of peer_deny: every command the Claude fragment denied before peer_deny existed.
  run python3 -I - "$PROJECT_ROOT/private_dot_claude/auto-peer-deny.json" <<'PY'
import json, re, sys

deny = json.load(open(sys.argv[1]))["permissions"]["deny"]
assert "AskUserQuestion" in deny, deny
patterns = [p[5:-1] for p in deny if p.startswith("Bash(")]
must_deny = [
    "gh pr merge 1",
    "gh pr merge --auto --squash 1",
    "gh -R o/r pr merge 1",
    "gh --repo o/r pr merge 1",
    "gh --repo=o/r pr merge 1",
    "gh pr -R o/r merge 1",
    "gh pr --repo o/r merge 1",
    "gh pr --repo=o/r merge 1",
    "sh -c 'gh pr merge 1'",
    "/usr/bin/gh pr merge 1",
    "xargs -n1 gh pr merge",
    "gh pr 'merge' 1",
    'gh pr "merge" 1',
    "gh api -X POST graphql -f query='mutation { mergePullRequest(input: {}) { clientMutationId } }'",
    "gh api graphql -f query='mutation { enablePullRequestAutoMerge(input: {}) { clientMutationId } }'",
    "gh api -X PUT repos/o/r/pulls/1/merge",
    "gh -R o/r api repos/o/r/pulls/1/merge",
    "gh api -X POST repos/o/r/merges",
]
bad = [
    c
    for c in must_deny
    if not any(re.fullmatch(re.escape(p).replace(r"\*", ".*"), c, re.S) for p in patterns)
]
assert not bad, bad
PY
  [ "$status" -eq 0 ]
}

@test "Claude deny fragment is the projection of peer_deny and only applies to dedicated auto sessions" {
  local fragment="$PROJECT_ROOT/private_dot_claude/auto-peer-deny.json"
  [ -f "$fragment" ]
  grep -Fq 'claude --permission-mode auto --settings ~/.claude/auto-peer-deny.json' "$AUTO_SESSION"
  [ "$(peer_deny projection)" = "$(cat "$fragment")" ]
  run peer_deny claude-examples
  [ "$status" -eq 0 ]
  run grep -Fq 'gh pr merge' "$PROJECT_ROOT/private_dot_claude/settings.json.tmpl"
  [ "$status" -eq 1 ]
  run grep -Fq 'AskUserQuestion' "$PROJECT_ROOT/private_dot_claude/settings.json.tmpl"
  [ "$status" -eq 1 ]
}

@test "dotfiles links to public peer references without copying skill behavior claims" {
  grep -Fq 'この固定 source にある規範文書を参照してください' "$CONTRACT"
  grep -Fq 'autonomous-peer-contract.md' "$PROJECT_ROOT/runtime/skill-harness.md"
  for detail in '依頼 ID／SHA' 'terminal の idle や送信成功だけでは完了にしない' 'Peer Decision'; do
    run grep -Fq "$detail" "$CONTRACT"
    [ "$status" -eq 1 ]
  done
}
