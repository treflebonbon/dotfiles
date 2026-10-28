#!/usr/bin/env bash
# 文書・指示 Markdown だけの変更で、PR 公開前の全 Bats を絞る入口。
# 使い方: scripts/test-docs.sh [--plan] [変更ファイル...]
# 変更ファイルを省略すると origin/main との差分（未 commit・未追跡を含む）を使う。
# 例外の対象外が 1 つでもあれば全 Bats（lefthook run test）が必要と報告して exit 2 する。
set -euo pipefail

plan_only=0
if [[ ${1:-} == --plan ]]; then
  plan_only=1
  shift
fi

if (($# > 0)); then
  changed=("$@")
else
  base=$(git merge-base origin/main HEAD)
  mapfile -t changed < <({
    git diff --name-only "$base"
    git ls-files --others --exclude-standard
  } | sort -u)
fi

if ((${#changed[@]} == 0)); then
  echo "変更がない" >&2
  exit 2
fi

# lefthook.yml の instruction-contract の glob から、Markdown の指示ファイルだけを残した集合。
# tests/*.bats・lefthook.yml・.chezmoiignore・*.tmpl・*.toml・実行ファイルは含めない。
is_docs() {
  case $1 in
  CLAUDE.md | AGENTS.md | GLOSSARY.md | private_dot_claude/CLAUDE.md | private_dot_config/codex/AGENTS.md | private_dot_gemini/AGENTS.md | docs/architecture.md | docs/conventions.md | local-skills/ui-grill-with-docs/SKILL.md) return 0 ;;
  runtime/*.md | docs/adr/*.md | local-skills/*-peer-refactor/*.md) return 0 ;;
  # triage が却下した依頼の記録。指示ファイルではないが、Markdown だけの変更として扱う。
  .out-of-scope/*.md) return 0 ;;
  esac
  return 1
}

for file in "${changed[@]}"; do
  if ! is_docs "$file"; then
    echo "例外の対象外: $file。全 Bats（lefthook run test）が必要" >&2
    exit 2
  fi
done

# 変更ファイルのパスまたは basename を含む Bats。直接参照だけを拾い、間接参照は拾えない。
mapfile -t related < <(
  for file in "${changed[@]}"; do
    grep -lF -e "$file" -e "$(basename "$file")" tests/*.bats || :
  done | sort -u
)
contract=(tests/workflow-contract.bats tests/autonomous-peer-contract.bats)
mapfile -t files < <(printf '%s\n' "${contract[@]}" "${related[@]}" | sort -u)

printf '対象 Bats:\n' >&2
printf '  %s\n' "${files[@]}" >&2
((plan_only)) && exit 0

# git hook 由来の GIT_DIR 等は Bats の fixture を実 repo へ向けるため外す（scripts/test.sh と同じ）。
while IFS= read -r git_var; do unset "$git_var"; done < <(git rev-parse --local-env-vars)
bats "${files[@]}"
bats --filter 'Review Round contract' tests/gh-review-thread.bats
