---
name: worktree-gc
description: 緊急時に repo-local worktree (.claude/worktrees / .worktrees / tmp/implement-issue/worktrees) を GC して fd/inotify 枯渇を解消する。"worktree cleanup" "fd 枯渇" "Too many open files" "worktree が溜まった" で起動。
---

# worktree-gc

## Steps

1. この skill に同梱の `scripts/worktree-gc.sh`（配備先例: `~/.agents/skills/worktree-gc/scripts/worktree-gc.sh`）を `bash <script path> --diagnose --repo "$(git rev-parse --show-toplevel)" --roots ".claude/worktrees,.worktrees,tmp/implement-issue/worktrees" --max-report 50` で実行し、まず `summary` だけを読む。
2. `candidates` と主要な keep 理由 (`out_of_root`, `keep_dirty`, `keep_detached`, `keep_unique`, `keep_open_pr`) をユーザーに示す。大量の明細は貼らず、必要な時だけ TSV を抜粋する。
3. AskUserQuestion で「適用するか / age 閾値を変えるか」を確認する。
4. 承認されたら `--diagnose` を外し、同じ `--repo` / `--roots` / age 設定に `--apply` を付けて実行する。緊急時は `--age-days 0 --locked-age-days 0` で即時回収も可 (ライブ agent を撃つ恐れを明示)。
5. 実行後 `git worktree list | wc -l` で残数を報告する。

## Notes

- dry-run が既定。`--apply` を付けない限り削除しない。
- `--diagnose` は削除しない。`--apply` と併用しても診断のみ。
- summary は `out_of_root` を scope バケット、`keep_*` を in-root/main 側の保護理由として読む。
- locked は age ゲート。`--locked-age-days` 未満の locked はライブ agent とみなし保護される。
- `removed=0` でも `git worktree list` が多い場合、roots 外 worktree や dirty / detached / unique commit / open PR で保護されている可能性が高い。
- 外部 worktree (`~/workspace` 等) は診断表示のみで、自動削除対象外。
- shell snippet は bash 前提にする。zsh では `path` 変数名が `PATH` と連動するため使わない。
