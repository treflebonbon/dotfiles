# ツール・スキル更新（2026-09-22）

## 要件と採用境界

ユーザーの `/implement ツールとスキルの更新` に基づき、既存 AI tool snapshot と APM 全19依存の更新候補を確認する。ADR-0045 に従い、tool snapshot（quality floor 込み）と通常 APM payload refresh の2更新単位を採用し、Impeccable skill pin と Matt Pocock managed set は upstream が進んでいることを確認した上で別更新単位として対象外にする。前回更新（2026-09-16、`52aac5d0`）から6日経過している。task worktree は main `bfc72f4` から作成した。

受入条件は exact snapshot と lock の整合、3 system の評価、Linux build・CLI起動、関連テスト・型チェック・full suite、二軸レビューとコミット。モデル・権限設定、配布経路、新規ツール追加、private skill 改稿は対象外。live apply・push・PR は行わない。

## Tool snapshot

実装入口で `git ls-remote https://github.com/numtide/llm-agents.nix HEAD` を確認し、default branch HEAD `9032892fd4d89bdad79c858a81aae1268ad2d191`（2026-09-21）に固定した。`private_dot_config/nix-devshell/flake.nix` の `llm-agents.url` は exact revision 文字列を直接埋め込む設計のため、`nix flake update llm-agents` だけでは進まず、URL 自体を書き換えてから再ロックする必要があった（この設計は `llm.claude-code` 等を通じて `modules/ai.nix` が参照する immutable snapshot の一部）。

| ツール            | 旧版    | 候補    |
| ----------------- | ------- | ------- |
| Claude Code       | 2.1.272 | 2.1.278 |
| Codex             | 0.154.0 | 0.155.1 |
| Copilot CLI       | 1.0.83  | 1.0.87  |
| Antigravity CLI   | 1.2.3   | 1.2.7   |
| RTK               | 0.49.0  | 0.49.0  |
| APM               | 0.30.0  | 0.31.0  |
| Herdr             | 0.9.0   | 0.9.1   |
| code-review-graph | 2.3.8   | 2.3.9   |

Claude Code の公式 CHANGELOG（v2.1.273–v2.1.278、`raw.githubusercontent.com/anthropics/claude-code/v2.1.278/CHANGELOG.md`）を確認した。この repo の quality floor 判断基準（多 agent ワークフロー・worktree 隔離・permission/trust boundary の信頼性）に合致する修正:

- **worktree 隔離破れ**: worktree 隔離済みセッションが certain nested shell expansion を含む Bash コマンドを受理してしまう不具合の修正（2.1.274）
- **permission bypass**: special な shell 変数を loop/assign するコマンドが permission check をすり抜けていた不具合の修正（2.1.274）
- **多 agent の error 伝搬**: subagent/background agent が streamed reply に token usage や model id を欠く場合に結果配信されず failed 報告される不具合の修正（2.1.273）
- **background daemon 安定化**: plugin の LSP server 終了時に background session (`claude --bg`) ごと終了してしまう不具合の修正（2.1.277。この repo は `enabledPlugins` に LSP を含むため直撃）
- **skill discovery**: `--worktree` session でメイン repository の project skill が `.claude/skills` untracked のため読み込まれない不具合の修正（2.1.277）

pin は 2.1.278 まで進むが、その内容（auto mode server-side classifier の billing 変更のみ）に床上げ根拠となる記述はない。よって `minClaudeCode` を `2.1.261` → `2.1.277` へ引き上げ、pin は `2.1.278` を採用する。

Codex の公式 release note（`gh api repos/openai/codex/releases`、rust-v0.155.0 / rust-v0.155.1）を確認した。この repo の Codex floor 判断基準（untrusted project instruction・managed deny-read・credential redaction・remote MCP・Unix shutdown）に合致する修正:

- restricted WSL sandbox からの Windows-process escape 遮断と brokered shell snapshot の credential exposure 強化（`#44286`/`#43909`/`#44040`。この repo は WSL2 上で稼働するため直撃する）
- Unix SIGTERM 受信時の app-server stdio shutdown の graceful 化（`#44523`）

0.155.1 は TUI の reasoning summary 既定値 revert のみで床上げ根拠にはならない。よって `minCodex` を `0.153.4` → `0.155.0` へ引き上げ、pin は `0.155.1` を採用する。

Copilot CLI・Antigravity CLI・RTK・code-review-graph は package metadata の追従のみ確認し、version 固有の公式 changelog は未確認（quality floor 対象外）。Herdr 0.9.1 は bugfix のみで dotfiles 側の設定変更は不要と判断した。

`nix flake lock --update-input llm-agents`（実際は `flake.nix` の URL 書き換え後に `nix flake update llm-agents`）で lock を更新し、`nix flake check --no-build --all-systems` は全6 devShell と formatter の評価に成功した。3 system の overlay 経由 `pkgs.llm-agents.<pkg>.version` 実測は claude-code 2.1.278 / codex 0.155.1 / copilot-cli 1.0.87 / antigravity-cli 1.2.7 / rtk 0.49.0 / apm 0.31.0 / herdr 0.9.1 / code-review-graph 2.3.9 で3 system一致した。x86_64-linux の実 `nix develop` build と8 CLI 起動（`claude` 2.1.278 / `codex-cli` 0.155.1 / `copilot` 1.0.87 / `agy` 1.2.7 / `rtk` 0.49.0 / `apm` 0.31.0 / `herdr` 0.9.1 / `code-review-graph` 2.3.9）も成功した。

## スキル候補の比較

全19依存の配布対象は不変のため manifest の構造（targets/依存数）は維持し、隔離 `apm install --https`（apm 0.31.0）で floating dependency を再解決し selected content hash を比較した。

| 依存 | 確認内容 | 採否 |
| --- | --- | --- |
| pdf / skill-creator / effect-ts / herdr / shadcn / react-view-transitions / web-design-guidelines / react-best-practices / composition-patterns / supabase-postgres-best-practices（floating、10件） | selected content hash 不変 | 配布差分なし・維持（shadcn・herdr skill を含む） |
| mattpocock/skills（exact pin `6654f6b6`） | upstream default branch HEAD が `c55ee46073ed923f86ce59a5eb3b6d895095d1b7` へ進行 | 別更新単位（ADR-0042 の ordered gate 未実施）・pin維持 |
| pbakaus/impeccable（exact pin `cb56ed6c`） | upstream HEAD が `83c2c735777c68e30ea536ab9cc97f7843456945` へ進行 | 別更新単位（Design Hook 互換性ゲート未実施）・pin維持 |
| stablyai/orca `orca-cli`（exact pin `de0a91b9`） | upstream 最新まで selected subtree の content hash 不変 | 配布差分なし・pin維持 |
| stablyai/orca `orchestration`（floating） | 旧 resolved `60d79395` → 新 default HEAD `059ee59a` で content hash 変化（`SKILL.md` の routing 文言更新: 「Playwright/CDP へ誘導」の一文を含む段落を簡素化） | 実体差分、revision-only 再解決を反映 |
| stablyai/orca `computer-use`（floating） | 同上の commit 範囲で content hash 変化（`SKILL.md` を全面改稿: accessibility tree 操作の説明、programmatic path 優先の明記、GUI 操作が必要な場合の限定を追加） | 実体差分、revision-only 再解決を反映 |
| vercel-labs/skills/find-skills（floating） | selected content hash 不変（resolved_commit のみ `d6b37f62` → `7407f389` に前進） | revision-only、floating解決を自然反映 |
| GoogleChrome/modern-web-guidance（exact pin `bfd8c8dd`）/ remotion-dev/skills/remotion-best-practices（exact pin `3b9e6561`）（2件） | 前回（2026-09-16）から upstream 未変化 | 配布差分なし・維持 |
| mizchi/skills/empirical-prompt-tuning（floating、パス変更） | upstream `mizchi/skills` が `meta/` サブディレクトリを廃止しフラット構成へ移行したため、旧パス `meta/empirical-prompt-tuning` を指定した `apm install` が `Subdirectory not found` で失敗 | `apm.yml` の依存パスを `mizchi/skills/empirical-prompt-tuning` へ追従（選択済みスキルの content_hash `sha256:0a38d8...` は不変） |

`apm.yml` のパス修正後、隔離 cwd（Git remote なし）へコピーして `apm install --https`（apm 0.31.0）を実行した。生成 lock の SHA-256 `baa97ced11b444fe9c51da7fbd3b5648f8eecd5aec46b66f6d9e10cf7c686300` は同一環境の `apm install --frozen --https` 前後で不変、`apm audit --ci` は10/10全通過した。生成 lock を diff すると、変更対象は mizchi のパス（`active_owner` 表記のみ、content 不変）、`orchestration` / `computer-use` の resolved_commit と content hash（実体差分）、`shadcn` / `orca-cli` / `find-skills` の revision-only な `resolved_commit` 更新のみで、他13依存の pin・content hash は無変化だった。両 target（`.agents/skills/` / `.claude/skills/`）で19依存の discovery を確認した。

## 検証

- `nix flake update llm-agents`（`flake.nix` の URL revision 書き換え後）、`nix flake check --no-build --all-systems`: 成功。
- 3 system の overlay 経由 `pkgs.llm-agents.<pkg>.version` 実測（8パッケージ）: 一致。
- x86_64-linux の実 `nix develop` build と8 CLI version 起動: 成功。
- `tests/ai-quality-floor.bats`: quality floor 値（`2.1.277` / `0.155.0`）と診断メッセージの固定値を更新し、7/7 成功。
- `tests/herdr.bats`: Herdr 期待 version を `0.9.1` へ更新し、1/1 成功。
- 隔離 cwd/HOME の APM install（非frozen→frozen）と `apm audit --ci` 10/10: 成功。
- `tests/apm-runtime.bats`: `apm_version`、`shadcn`/`computer-use`/`orchestration` の resolved_commit・content hash 固定値を更新し、5/5（変更対象テスト）を含む23/23 成功。`tests/apm-cache-refresh.bats` は変更なしで成功を維持。
- `bunx tsc --noEmit`: エラーなし。
- `bats tests/`（全スイート、741件）: `LC_ALL=C bats tests/*.bats` で741/741成功（exit 0）。`tests/nix-devshell.bats` の2 test（snapshot revision の固定値2箇所）は、この更新作業中に該当ファイルを編集しながら並行して走らせていた1回目のフル suite 実行でだけ一時的に failure を観測したが、これは編集途中の該当テストファイルを長時間実行中の bats プロセスが読んだ競合によるものと判明した。編集完了後に同テストを単体実行（28/28成功）、続けて全編集が完了し他の並行編集がない状態でフル suite を再実行した結果（本記録の値）は741/741成功であり、regression ではない。

## 二軸レビュー

`/code-review`（base: `main`）を実行した。Standards / Spec の両サブエージェントに hard violation の指摘はなかった。

## 最終結果

`nix flake update`・3 system 評価・x86_64-linux 実 build・8 CLI 起動・関連 bats・typecheck が成功し、full suite は741/741成功した。APM の mizchi パス追従と orca floating dependency 更新は隔離 lock 生成・frozen no-rewrite・audit 10/10・両target discoveryを通過した。live apply、push・PR は未実施。aarch64-linux / aarch64-darwin の実機実行、2.1.273–2.1.277 と 0.155.0 の床上げ根拠そのもの（worktree isolation bypass、permission bypass、WSL sandbox escape 等）を実際の agent session で機能的に再現する smoke、Copilot CLI / Antigravity CLI の version固有 changelog は未確認のまま。
