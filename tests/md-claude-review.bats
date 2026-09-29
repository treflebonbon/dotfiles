#!/usr/bin/env bats
# md-claude-review が特定のモデル世代に固定されず、実在するパスだけを案内することを固定する。

setup() {
  PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  SKILL="$PROJECT_ROOT/local-skills/md-claude-review/SKILL.md"
  CRITERIA="$PROJECT_ROOT/local-skills/md-claude-review/references/criteria.md"
}

@test "criteria の Move-to 先 docs パスはこの repo に実在する" {
  local path
  for path in $(sed -n '/^## 6\./,/^## 7\./p' "$CRITERIA" | grep -o 'docs/[A-Za-z0-9_./-]*' | sort -u); do
    [ -e "$PROJECT_ROOT/${path%/}" ]
  done
}

@test "SKILL.md は特定のモデル世代を名指しせず、最新化手順を参照する" {
  ! grep -Eq 'Opus [0-9]|Sonnet [0-9]' "$SKILL"
  grep -Fq 'update procedure' "$SKILL"
  grep -Fq 'WebFetch(domain:code.claude.com)' "$SKILL"
}

@test "モデル固有の判定は prompt-audit に委譲し、同梱ファイルのパスを固定しない" {
  grep -Fq 'Skill(claude-api)' "$SKILL"
  grep -Fq 'argument `prompt-audit`' "$SKILL"
  grep -Fq '第一手段: prompt-audit に委譲する' "$CRITERIA"
  ! grep -Eq 'bundled-skills|shared/prompt-audit' "$SKILL"
}

@test "criteria §7 は最新化手順・世代別の由来・検証日を持つ" {
  grep -Fq '最新化手順' "$CRITERIA"
  grep -Fq 'https://code.claude.com/docs/en/best-practices' "$CRITERIA"
  grep -Fq '### 7b. 世代別の再テスト候補' "$CRITERIA"
  grep -Eq '^最終検証: [0-9]{4}-[0-9]{2}-[0-9]{2}' "$CRITERIA"
}
