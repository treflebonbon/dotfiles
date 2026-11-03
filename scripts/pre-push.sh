#!/usr/bin/env bash
# pre-push hook: 全 Bats の実行漏れを push 前に止める。
# 使い方: scripts/pre-push.sh        pre-push hook 本体（stdin は git が渡す ref の一覧）
#         scripts/pre-push.sh record  clean な tree を検証済みとして記録する
set -euo pipefail

repo_root=$(git rev-parse --show-toplevel)
cd "$repo_root"

zero=0000000000000000000000000000000000000000
# 検証済み tree の一覧。worktree ごとの git dir に置くので、追跡対象にも tmp/ の掃除にも巻き込まれない。
tested_trees=$(git rev-parse --git-path tested-trees)
head_tree=$(git rev-parse 'HEAD^{tree}')

check_hidden_paths() {
  local hidden
  if ! hidden="$(git ls-files -v -z | {
    local entry found=0
    while IFS= read -r -d '' entry; do
      case "${entry:0:1}" in
      S | [[:lower:]]) found=1 ;;
      esac
    done
    printf '%s' "$found"
  })"; then
    echo "Git のフラグ検査に失敗したため、検証済みとして扱えません" >&2
    return 1
  fi
  if [[ "$hidden" == 1 ]]; then
    echo "assume-unchanged または skip-worktree を解除してから、push する tree を検証してください" >&2
    return 1
  fi
}

record() {
  local working_status
  if ! working_status=$(git status --porcelain); then
    echo "Git status の検査に失敗したため、検証済みとして記録しません" >&2
    return 1
  fi
  # 未 commit・未追跡の内容は tree に反映されず、検証した内容と HEAD の tree が食い違うので記録しない。
  if [[ -n "$working_status" ]]; then
    echo "未 commit または未追跡の変更があるため、検証済みとして記録しない" >&2
    return 0
  fi
  check_hidden_paths || return 1
  echo "$head_tree" >>"$tested_trees"
}

if [[ ${1:-} == record ]]; then
  record
  exit 0
fi

# stdin の ref ごとに push 対象の tree を照合する。空入力（手動実行など）は削除と見なさず HEAD を対象にする。
needs_run=0
saw_ref=0
while read -r _ local_sha _; do
  saw_ref=1
  [[ $local_sha == "$zero" ]] && continue
  tree=$(git rev-parse "$local_sha^{tree}")
  if grep -qxF "$tree" "$tested_trees" 2>/dev/null; then
    continue
  elif [[ $tree == "$head_tree" ]]; then
    needs_run=1
  else
    # テストは作業ツリー（HEAD）に対して走るため、HEAD 以外の未検証 commit は検証できない。
    echo "検証済みでない commit $local_sha は HEAD ではないため push できない。checkout して lefthook run test を実行する" >&2
    exit 1
  fi
done
if ((saw_ref == 0)); then
  grep -qxF "$head_tree" "$tested_trees" 2>/dev/null || needs_run=1
fi
((needs_run)) || exit 0

# テストと文書判定は作業ツリーを見るため、未 commit・未追跡の変更があると push する tree とは別の内容を検証してしまう。
if ! working_status=$(git status --porcelain); then
  echo "Git status の検査に失敗したため、push する tree を検証できません" >&2
  exit 1
fi
if [[ -n "$working_status" ]]; then
  echo "未 commit または未追跡の変更があるため、push する tree を検証できない。commit または退避してから push する" >&2
  exit 1
fi
check_hidden_paths

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
