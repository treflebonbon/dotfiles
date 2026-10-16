#!/usr/bin/env bats

setup() {
  PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  CONTRACT="$PROJECT_ROOT/runtime/autonomous-peer-contract.md"
  AUTO_SESSION="$PROJECT_ROOT/local-skills/herdr-peer-refactor/references/auto-session.md"
  ADR="$PROJECT_ROOT/docs/adr/0075-adopt-peer-refactor-skills.md"
}

@test "contract stays indexed and the instruction layers share one model-independent pointer" {
  [ -f "$CONTRACT" ]
  grep -Fq 'autonomous-peer-contract.md' "$PROJECT_ROOT/runtime/index.md"
  grep -Fq 'autonomous-peer-contract.md' "$PROJECT_ROOT/docs/conventions.md"
  grep -Fq 'autonomous-peer-contract.md' "$PROJECT_ROOT/runtime/skill-harness.md"
  local claude agents
  claude="$(grep -F 'autonomous-peer-contract.md' "$PROJECT_ROOT/CLAUDE.md")"
  agents="$(grep -F 'autonomous-peer-contract.md' "$PROJECT_ROOT/AGENTS.md")"
  [ -n "$claude" ]
  [ "$(printf '%s\n' "$claude" | wc -l)" -eq 1 ]
  [ "$claude" = "$agents" ]
  printf '%s\n' "$claude" | grep -Fq '不可逆・影響の広い判断'
  run grep -Fq '同一モデル' <<<"$claude"
  [ "$status" -eq 1 ]
}

@test "contract allows normal explicit collaboration and keeps external-write and merge boundaries" {
  local start scope
  start="$(sed -n '/^## 開始と承認/,/^## 元の候補/p' "$CONTRACT")"
  scope="$(sed -n '/^## 実装・レビュー・公開/,$p' "$CONTRACT")"
  printf '%s\n' "$start" | grep -Fq '明示依頼したら、通常 session でも進める'
  printf '%s\n' "$start" | grep -Fq 'deny 設定がないことは、この明示依頼を拒否する条件ではない'
  printf '%s\n' "$start" | grep -Fq '承認していない外部書込みは推測しない'
  printf '%s\n' "$start" | grep -Fq 'merge と issue の直接 close は実行しない'
  printf '%s\n' "$start" | grep -Fq 'issue 作成や報告 comment も依頼範囲にある場合だけ行う'
  printf '%s\n' "$scope" | grep -Fq 'issue は任意'
  printf '%s\n' "$scope" | grep -Fq 'issue がある場合だけ'
  printf '%s\n' "$scope" | grep -Fq 'Closes #N'
  printf '%s\n' "$scope" | grep -Fq 'topic push は `git-push-topic`'
  printf '%s\n' "$scope" | grep -Fq 'gh-once.sh'
  printf '%s\n' "$scope" | grep -Fq '再送しない'
  printf '%s\n' "$scope" | grep -Fq 'PR の state・head・draft を読み直し'
}

@test "contract preserves the source candidates and their acceptance scope" {
  local source
  source="$(sed -n '/^## 元の候補と受入条件/,/^## 担当と並行/p' "$CONTRACT")"
  printf '%s\n' "$source" | grep -Fq '元 artifact の内容'
  printf '%s\n' "$source" | grep -Fq '共通 Git dir による repo identity'
  printf '%s\n' "$source" | grep -Fq '提示時の source SHA'
  printf '%s\n' "$source" | grep -Fq 'ancestor'
  printf '%s\n' "$source" | grep -Fq '受入条件／非目標'
  printf '%s\n' "$source" | grep -Fq 'helper の共有やファイル分割'
  printf '%s\n' "$source" | grep -Fq '固定 record'
}

@test "contract uses model-independent Peer Decision and Held Candidate rules with independent evidence" {
  local decisions
  decisions="$(sed -n '/^## 判断の分類/,/^## peer 相談と応答/p' "$CONTRACT")"
  printf '%s\n' "$decisions" | grep -Fq 'Peer Decision'
  printf '%s\n' "$decisions" | grep -Fq 'Held Candidate'
  printf '%s\n' "$decisions" | grep -Fq 'モデル同一性を判断の権限にしない'
  printf '%s\n' "$decisions" | grep -Fq '根拠が同意だけなら不一致扱い'
  printf '%s\n' "$decisions" | grep -Fq '無応答は同意にしない'
  printf '%s\n' "$decisions" | grep -Fq '新たな ADR・仕様・schema'
  printf '%s\n' "$decisions" | grep -Fq '提案と理由を報告し、実装しない'
  printf '%s\n' "$decisions" | grep -Fq '既に明示承認された同じ判断を再質問しない'
}

@test "peer responses require current evidence and keep the upstream human-wait contract unchanged" {
  local peer skill="$PROJECT_ROOT/local-skills/herdr-peer-refactor/SKILL.md"
  peer="$(sed -n '/^## peer 相談と応答/,/^## 実装・レビュー・公開/p' "$CONTRACT")"
  printf '%s\n' "$peer" | grep -Fq '新しい context'
  printf '%s\n' "$peer" | grep -Fq '依頼 ID と対象 SHA'
  printf '%s\n' "$peer" | grep -Fq '古い turn の完了は今回の完了ではない'
  printf '%s\n' "$peer" | grep -Fq '状態不明の agent に依頼を再送しない'
  grep -Fq 'を呼ばない別手順とし' "$CONTRACT"
  grep -Fq '各 round の人間の回答を待ち' "$PROJECT_ROOT/runtime/skill-harness.md"
  grep -Fq '未回答の decision を推測して先へ進まない' "$PROJECT_ROOT/runtime/skill-harness.md"
  grep -Fq 'grilling' "$skill"
}

@test "worktree ownership and holds protect other writers and preserve observed state" {
  local ownership response
  ownership="$(sed -n '/^## 担当と並行/,/^## 判断の分類/p' "$CONTRACT")"
  response="$(sed -n '/^## peer 相談と応答/,/^## 実装・レビュー・公開/p' "$CONTRACT")"
  printf '%s\n' "$ownership" | grep -Fq 'native worktree ごとに writer は一人'
  printf '%s\n' "$ownership" | grep -Fq 'peer は read-only'
  printf '%s\n' "$ownership" | grep -Fq '同じファイルでも別 hunk'
  printf '%s\n' "$ownership" | grep -Fq '意味的な競合は直列'
  printf '%s\n' "$ownership" | grep -Fq '他者の未 commit 変更を commit・stash・破棄しない'
  printf '%s\n' "$response" | grep -Fq 'pane・worktree・成果物を保持'
  printf '%s\n' "$response" | grep -Fq '同一の失敗は 2 回で保留'
  printf '%s\n' "$response" | grep -Fq '2 時間'
  printf '%s\n' "$response" | grep -Eq 'Review Round[[:space:]]*\|[[:space:]]*3 回'
}

@test "contract requires final-SHA Standards and Spec review and safe publication" {
  local scope skill="$PROJECT_ROOT/local-skills/herdr-peer-refactor/SKILL.md"
  scope="$(sed -n '/^## 実装・レビュー・公開/,$p' "$CONTRACT")"
  printf '%s\n' "$scope" | grep -Fq '最終 SHA に Standards と Spec の独立レビュー'
  printf '%s\n' "$scope" | grep -Fq '新しい head に古い SHA のレビュー結果を流用しない'
  printf '%s\n' "$scope" | grep -Fq '権限拡大はしない'
  printf '%s\n' "$scope" | grep -Fq 'topic push は `git-push-topic`'
  grep -Fq 'gh pr view --json state,headRefOid,isDraft' "$skill"
  grep -Fq '元候補 → PR' "$skill"
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

@test "Codex peer permission rules remain isolated and preserve the read-only credential path" {
  local rules="$PROJECT_ROOT/private_dot_config/codex/auto-peer.rules"
  local sync="$PROJECT_ROOT/private_dot_local/bin/executable_sync-codex-managed-config"
  [ -f "$rules" ]
  ! grep -Fq 'auto-peer.rules' "$sync"
  grep -Fq 'pattern = ["gh", "pr", "merge"]' "$rules"
  grep -Fq 'pattern = ["gh", "api"]' "$rules"
  grep -Fq 'pattern = ["git-push-reviewed"]' "$rules"
  grep -Fq 'pattern = ["git", "push"]' "$PROJECT_ROOT/private_dot_config/codex/rules/default.rules"
  ! grep -Fq '"git", "push"' "$rules"
  grep -Fq 'default_permissions="dotfiles-peer"' "$AUTO_SESSION"
  grep -Fq 'GH_CONFIG_DIR=~/.codex-peer/gh' "$AUTO_SESSION"
  grep -Fq 'CODEX_HOME=~/.codex-peer' "$AUTO_SESSION"
  grep -Fq 'codex --disable apps -c' "$AUTO_SESSION"
  grep -Fq '[apps.github]' "$PROJECT_ROOT/private_dot_config/codex/config.toml.tmpl"
}

@test "Claude deny fragment is standard permission configuration and only applies to dedicated auto sessions" {
  local fragment="$PROJECT_ROOT/private_dot_claude/auto-peer-deny.json"
  [ -f "$fragment" ]
  grep -Fq 'claude --permission-mode auto --settings ~/.claude/auto-peer-deny.json' "$AUTO_SESSION"
  run python3 - "$fragment" <<'PY'
import json, re, sys

doc = json.load(open(sys.argv[1]))
assert list(doc) == ["permissions"], list(doc)
assert list(doc["permissions"]) == ["deny"], list(doc["permissions"])
deny = doc["permissions"]["deny"]
assert "AskUserQuestion" in deny, deny
bash_deny = [p for p in deny if p != "AskUserQuestion"]
assert bash_deny and all(p.startswith("Bash(") and p.endswith(")") for p in bash_deny), deny

def denied(command):
    for pattern in bash_deny:
        rx = re.escape(pattern[len("Bash("):-1]).replace(r"\*", ".*")
        if re.fullmatch(rx, command, re.S):
            return True
    return False

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
must_allow = [
    "gh pr view 1 --json state,mergeStateStatus",
    "gh pr list --state merged --limit 1",
    "gh pr create --title 'feat: add merge deny' --body-file b.md",
    "gh pr close 1",
    "gh pr reopen 1",
    "gh pr ready 1",
    "gh api graphql -f query='query { viewer { login } }'",
    "git-push-topic",
]
bad = [command for command in must_deny if not denied(command)] + [command for command in must_allow if denied(command)]
assert not bad, bad
PY
  [ "$status" -eq 0 ]
  run grep -Fq 'gh pr merge' "$PROJECT_ROOT/private_dot_claude/settings.json.tmpl"
  [ "$status" -eq 1 ]
  run grep -Fq 'AskUserQuestion' "$PROJECT_ROOT/private_dot_claude/settings.json.tmpl"
  [ "$status" -eq 1 ]
}

@test "the ADR and the runtime contract pointer remain readable" {
  grep -Fq 'status: accepted' "$ADR"
  grep -Fq 'runtime/autonomous-peer-contract.md' "$ADR"
}

# The Orca reference keeps the two rules the contract states for every peer request: a
# completion is matched to the request ID and SHA, and a worker in an unknown state is
# kept rather than stopped, released or sent the request again. An earlier Orca procedure
# contradicted both while no test covered it. The per-peer deny
# check is not asserted here: the contract no longer requires it for an explicit request.
orca_reference() {
  cat "$PROJECT_ROOT/local-skills/orca-peer-refactor/references/orca.md"
}

@test "Orca completion needs the request ID and SHA, never an idle terminal or a successful send" {
  orca_reference | grep -Fq '依頼 ID／SHA'
  orca_reference | grep -Fq 'terminal の idle や送信成功だけでは完了にしない'
  grep -Fq '各依頼に依頼 ID と対象 SHA を付け' "$CONTRACT"
}

@test "Orca keeps a worker in an unknown state instead of stopping, releasing or resending to it" {
  orca_reference | grep -Fq '保留・状態不明の process を停止・release せず保持する'
  orca_reference | grep -Fq '接続喪失を process 終了と扱わない'
  grep -Fq '状態不明の agent に依頼を再送しない' "$CONTRACT"
}
