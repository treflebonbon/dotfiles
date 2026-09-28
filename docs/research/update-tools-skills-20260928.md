# ツールとスキル更新（2026-09-28）

`/implement ツールとスキル更新` に基づき、main `2826975` から task worktree を作成し、導入済み AI ツールと APM 20依存を確認した。[ADR-0045](../adr/0045-separate-llm-agents-and-apm-update-units.md) の境界に従い、llm-agents snapshot と通常の skill payload を個別に採否した。Impeccable と Matt Pocock managed set は専用ゲートが必要なため今回の採用対象から外した。品質 floor、モデル・権限設定、配布経路は維持する。

## ツール

[llm-agents.nix の比較](https://github.com/numtide/llm-agents.nix/compare/bbb0f9a24c3a5ce918f3d8103397ce08b20300e1...e28ea84e78517e5d05ae0c399da00e848e207261)で、既存 snapshot から default branch HEAD `e28ea84e78517e5d05ae0c399da00e848e207261` まで120 commit進み、導入済みツールの package file の差分は `packages/antigravity-cli/hashes.json` のみと確認した。Antigravity CLI は 1.2.11→1.2.12。Claude Code 2.1.283、Codex 0.157.1、Copilot CLI 1.0.88、RTK 0.50.0、Herdr 0.9.1、APM 0.32.0、code-review-graph 2.3.9 は不変。version固有の公式 changelog が確認できないため Antigravity CLI の機能変更は断定しない。既存の `minClaudeCode = "2.1.283"` と `minCodex = "0.157.0"` を維持する。

`private_dot_config/nix-devshell/flake.nix` と lock の `original.rev` / `locked.rev` を同じ revision に更新し、共有 nixpkgs は維持した。lock に含まれる llm-agents 自身の nixpkgs input は上流 pin に従い更新された。

## スキル

`apm outdated` は7依存を outdated と表示した。選択済み subtree の Git tree / blob SHA と実差分で判断した。

| 対象 | 確認結果 | 採否 |
| --- | --- | --- |
| `stablyai/orca/skills/orca-cli` | exact pin `4a5afd70` と default HEAD `aedb9305` の `SKILL.md` に実差分。`runtime_access_denied` 時の案内を追加 | `aedb9305cd1b3de859b5eafc1ee0d77fa0df8963` に更新 |
| `mizchi/skills/empirical-prompt-tuning`、`shadcn-ui/ui/skills/shadcn`、`stablyai/orca` の `computer-use` / `orchestration`、`supabase/agent-skills` | default HEAD へ進んだが selected subtree の内容は不変 | floating revision のみ lock に反映 |
| `remotion-dev/skills`、`GoogleChrome/modern-web-guidance`、`cloudflare/security-audit-skill` | exact pin と default HEAD が同一 | 維持 |
| その他の floating 依存 | `apm outdated` で up-to-date | 維持 |
| `mattpocock/skills`、`pbakaus/impeccable` | 専用の互換性ゲートを持つ別更新単位 | 維持 |

`orca-cli` の追加文は、接続が `runtime_access_denied` で失敗したときの権限要求と、Orca の再起動を避ける手順を示す。実行時は各環境の上位権限ポリシーが優先する。現セッションの権限設定では権限昇格を実行できないため、実 Orca セッションでの分岐動作は未確認。

空の隔離 cwd/HOME で APM 0.32.0 の `apm install --target claude,codex --https` を実行し、20依存すべての `deployed_file_hashes` を持つ lock を生成した。同じ環境の frozen install 前後で SHA-256 は `c7497cfcebac0f5f23ac468893492ff392036f00a5ca945cb62d634c1158e41d` のまま。`apm audit --ci` は10/10成功した。隔離 cwd に Git remote がないため organization policy enforcement は warning 付き skip となった。配布先 `.agents/skills/orca-cli/SKILL.md` と `.claude/skills/orca-cli/SKILL.md` は新しい案内文を含む。

## 検証

Nix の `nix flake check --no-build --all-systems` は6 devShell と3 formatterの評価に成功した。3 system の `nix build --dry-run` も成功し、Antigravity CLI 1.2.12 を確認した。x86_64-linux の `nix develop .#wsl` 実 build と隔離 HOME での8 CLI起動も成功し、`agy --version` は 1.2.12 を返した。aarch64-linux / aarch64-darwin の実機起動は未確認。

関連 Bats は `tests/nix-devshell.bats` 28/28、`tests/apm-runtime.bats` 15/15、`tests/apm-cache-refresh.bats` 8/8、`tests/ai-quality-floor.bats` 7/7。`bunx tsc --noEmit` も成功した。

`LC_ALL=C FORCE_COLOR=0 bun run test` は752件中750件成功、2件失敗（exit 1）。失敗した `Codex config migration keeps dotenv denied and public examples readable without a raw read grant` は sandbox 内で公開 `.envrc` / `.env.example` を読む fixture が終了0にならず、`raw Codex edits and tests with public fixtures while a human runs a fixed revision outside its namespace` は `with-env` の実体が `/nix/store` 内にあるという assertion に失敗した。変更前の main `2826975` で両テストを個別実行して同じ失敗を再現したため、今回の更新による回帰ではない。

二軸レビューの結果は完了後に追記する。
