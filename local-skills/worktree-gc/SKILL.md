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

## Home-wide fan-out (明示オプトイン, ADR-0056)

上記の既定フローは現在の repo 1つだけが対象。`~/ghq/` 配下の全リポジトリ + `~/.herdr/worktrees/` + `~/orca/workspaces/` を横断して GC したい場合だけ、ユーザーが明示的に要求したとき（例:「home 全体を掃除して」「ghq 全部まとめて worktree-gc して」）に限り、同梱の `scripts/worktree-gc-fanout.sh` を使う。デフォルトの単一repo緊急GCの動作・トリガーフレーズはこの節と無関係で変更されない。

1. `bash <script path>/worktree-gc-fanout.sh --diagnose --age-days 7` を実行する（`--ghq-root` / `--herdr-root` / `--orca-root` は既定でそれぞれ `~/ghq`・`~/.herdr/worktrees`・`~/orca/workspaces`。別パスなら明示指定）。出力は `source(repo|dangling)\treason\tscope\tbranch\tpath\trepo` の TSV で、全repo分 + dangling worktree 分を1つに集約した一覧。
2. 集約された候補一覧をユーザーに示し、AskUserQuestion で「まとめて適用するか」を1回だけ確認する（repoごとに個別承認しない）。
3. 承認されたら同じオプションに `--apply` を付けて実行する。
4. 実行後、`--herdr-root` / `--orca-root` 配下の残数や `fanout done removed=N` の行で結果を報告する。

- `worktree-gc.sh` 本体は無改修。`~/.herdr/worktrees/<repo>` と `~/orca/workspaces/<repo>` を、各 ghq リポジトリ呼び出しの `--roots` に追加するだけで実削除対象にしている（信頼できる外部ルートの許可リスト、[CONTEXT.md](../../CONTEXT.md)）。
- dangling worktree（親リポジトリ自体が消滅した worktree、[CONTEXT.md](../../CONTEXT.md)）も `--age-days` 閾値ゲート付きで検出・削除する。
- 実削除前に稼働中プロセス（`/proc/*/cwd`）を検出し、該当する repo 呼び出し・dangling候補を丸ごと保護する（repo単位の粒度。同じ呼び出しに含まれる他の候補も道連れで保護される）。
- `--max-removals`（既定50）は **実行全体** の上限。repo単位の上限ではない点が `worktree-gc.sh` 単体と異なる。
- `~/ghq/` は削除対象ではなく列挙起点。実際に削除され得るのは各リポジトリの repo-local roots・`~/.herdr/worktrees/<repo>`・`~/orca/workspaces/<repo>`・dangling worktree のみ。
- `--max-report`（既定50）は表示行数の上限に過ぎない。プロセス検出ガードや実削除対象の判定には常に全候補を使うため、`--max-report` を絞っても見落としは起きない。標準エラーの `total_candidates=N shown=M` 行で、表示件数とは別に真の候補総数を確認できる。
- 2つの異なる ghq リポジトリが同じ basename を共有する場合、事故防止のため両方とも herdr/orca 外部rootの付与を無効化し（repo-local roots のみで継続）、標準エラーに `basename collision, external roots disabled for '<name>'` と警告する。
- ghq 配下では発見されない、別の生きたリポジトリが同じ basename の herdr/orca ディレクトリに worktree を持っている場合も同様に検出し（`git worktree list` との照合による所有権検証）、標準エラーに `foreign worktree found under a same-named external root, disabling it for '<name>' (...)` と警告して外部rootの付与を無効化する。
- `--ghq-root`/`--herdr-root`/`--orca-root` は取得直後に正規化(`readlink -f`)する。symlink を含むパスを渡しても `git worktree list` の正規化済みパスと一致するため、登録済みworktreeを孤児と誤認識しない。
