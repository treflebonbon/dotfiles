#!/usr/bin/env bash
# pre-push hook: 全 Bats の実行漏れを push 前に止める。
# 使い方: scripts/pre-push.sh        pre-push hook 本体（stdin は git が渡す ref の一覧）
#         scripts/pre-push.sh record  clean な tree を検証済みとして記録する
set -euo pipefail

zero=0000000000000000000000000000000000000000
# 検証済み tree の一覧。worktree ごとの git dir に置くので、追跡対象にも tmp/ の掃除にも巻き込まれない。
stamp=$(git rev-parse --git-path tested-trees)
# ponytail: push 対象は HEAD とみなす（git-push-topic は HEAD を push する）。別 ref を push する運用は照合を ref 単位にする。
tree=$(git rev-parse 'HEAD^{tree}')

record() {
  # 未 commit・未追跡の内容は tree に反映されず、検証した内容と HEAD の tree が食い違うので記録しない。
  if [[ -n $(git status --porcelain) ]]; then
    echo "未 commit または未追跡の変更があるため、検証済みとして記録しない" >&2
    return 0
  fi
  echo "$tree" >>"$stamp"
}

pushes_only_deletions() {
  local local_sha
  while read -r _ local_sha _; do
    [[ $local_sha == "$zero" ]] || return 1
  done
}

if [[ ${1:-} == record ]]; then
  record
  exit 0
fi

if pushes_only_deletions; then
  exit 0
fi

if grep -qxF "$tree" "$stamp" 2>/dev/null; then
  exit 0
fi

docs_cmd=${DOTFILES_PRE_PUSH_DOCS_CMD:-scripts/test-docs.sh}
full_cmd=${DOTFILES_PRE_PUSH_FULL_CMD:-bun run test}

# test-docs.sh は文書だけの変更なら関連 Bats で 0、対象外の変更を含めば 2、テスト失敗はそれ以外を返す。
status=0
"$docs_cmd" || status=$?
if ((status == 2)); then
  $full_cmd
elif ((status != 0)); then
  exit "$status"
fi
record
