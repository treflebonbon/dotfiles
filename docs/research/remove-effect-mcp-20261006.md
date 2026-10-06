# Effect MCP の撤去

ユーザーの依頼「effect mcp が v3 で古いため削除」に従い、Effect MCP の登録を撤去する。v3 対応が撤去理由であることはユーザーから提示された前提で、上流の対応版は独立に調査していない。

## 変更範囲

更新単位は Effect MCP の撤去のみ。`private_dot_mcp.json` の `effect-docs`（`effect-mcp@latest`）を削除し、`runtime/ai-runtimes.md` の MCP 一覧を更新する。管理ソース内の該当参照はこの2ファイルのみで、予定した変更はともに反映済み。

context7 と serena、Effect 用 skill・reference・fixture は維持する。代替導入、ツール版・APM lock の更新、PR 分割はない。別の変更先へ保留した作業もない。

## 適用規約と検証

[ADR-0057 の Decision](../adr/0057-retire-to-worktree-for-native-entry.md#decision) と [skill-harness の Worktree の開始と復旧](../../runtime/skill-harness.md#worktree-の開始と復旧) に従い、Codex native worktree を作成し、root・branch・HEAD・status・Git dir・common dir を確認した。[architecture の編集・配備ルール](../architecture.md) に従い、task worktree の source のみを変更し、live 配備は受入後に行う。

JSON の変更前後比較で Effect MCP だけが削除され、他の MCP 設定が保持されることを確認した。`chezmoi cat ~/.mcp.json` の task source 出力も既存の `.mcp.json` と一致する。型チェック（`bunx tsc --noEmit`）、oxfmt、`git diff --check`、commit hook は成功した。

`lefthook run test` の初回は744件中716成功・6失敗・22スキップ、終了コード1。lefthook が TTY 出力を捕捉したため、TAP ではなく最終進捗 `744/744` と集計を照合した。ログは `/tmp/dotfiles-remove-effect-mcp-tests.log`。

失敗6件は設定を変更せず単体で再確認した。`human-validation.bats` の1件は repo devShell の `with-env` がない環境前提の失敗で、`nix develop .#default --command bats --formatter tap tests/human-validation.bats` では成功。TTY 捕捉下で停止・タイムアウトしたシェル関連5件は、`bats --formatter tap tests/user-environment-startup.bats` の4件と、`bats --formatter tap --filter 'gcd は ghq list' tests/dot_zshrc.bats` の1件として直接再実行し、すべて成功した。初回に停止した zsh 1プロセスと bash 2プロセスは手動で終了し、失敗として記録した。

最終の全スイートは `nix develop .#default --command lefthook run --no-tty test` で再実行し、722成功・0失敗・22スキップ、終了コード0。TAP 計画 `1..744` と結果744行の連番を照合した。初回とは検証環境・TTY の扱いが異なるため別の試行として扱う。最終ログは `/tmp/dotfiles-remove-effect-mcp-tests-final.log`。

この記録は [conventions のツール・スキル更新の追跡とレビュー](../conventions.md#ツールスキル更新の追跡とレビュー) に基づく規約レビューの指摘を受けて補完した。撤去だけなので新しい更新候補や ADR の採用判断はない。変更は task branch にコミットし、merge と live 配備はまだ行っていない。
