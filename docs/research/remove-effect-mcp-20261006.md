# Effect MCP の撤去

ユーザーの依頼「effect mcp が v3 で古いため削除」に従い、Effect MCP の登録を撤去する。v3 対応が撤去理由であることはユーザーから提示された前提で、上流の対応版は独立に調査していない。

## 変更範囲

更新単位は Effect MCP の撤去のみ。`private_dot_mcp.json` の `effect-docs`（`effect-mcp@latest`）を削除し、`runtime/ai-runtimes.md` の MCP 一覧を更新する。管理ソース内の該当参照はこの2ファイルのみで、予定した変更はともに反映済み。

context7 と serena、Effect 用 skill・reference・fixture は維持する。代替導入、ツール版・APM lock の更新、PR 分割はない。別の変更先へ保留した作業もない。

## 適用規約と検証

[ADR-0057 の Decision](../adr/0057-retire-to-worktree-for-native-entry.md#decision) と [skill-harness の Worktree の開始と復旧](../../runtime/skill-harness.md#worktree-の開始と復旧) に従い、Codex native worktree を作成し、root・branch・HEAD・status・Git dir・common dir を確認した。[architecture の編集・配備ルール](../architecture.md) に従い、task worktree の source のみを変更し、live 配備は受入後に行う。

JSON の変更前後比較で Effect MCP だけが削除され、他の MCP 設定が保持されることを確認した。`chezmoi cat ~/.mcp.json` の task source 出力も既存の `.mcp.json` と一致する。型チェック（`bunx tsc --noEmit`）、oxfmt、`git diff --check`、commit hook は成功した。

この記録は [conventions のツール・スキル更新の追跡とレビュー](../conventions.md#ツールスキル更新の追跡とレビュー) に基づく規約レビューの指摘を受けて補完した。撤去だけなので新しい更新候補や ADR の採用判断はない。変更は task branch にコミットし、merge と live 配備はまだ行っていない。
