# ツールとスキル更新（2026-09-24）

## 要件と採用境界

ユーザーの `/implement ツールとスキル更新` に基づき、既存 AI tool snapshot と APM 全19依存の更新候補を確認する。ADR-0045 に従い、tool snapshot と通常 APM payload の2更新単位を別々に採否する（Impeccable、Matt Pocock managed set は対象外）。task worktree は main `8ed3db4` から作成した。

受入条件は exact snapshot と lock の整合、3 system の評価、Linux build・CLI起動、関連テスト・型チェック・full suite、二軸レビューとコミット。品質 floor、モデル・権限、配布経路、新規ツール追加、private skill 改稿は対象外。live apply・push・PR は行わない。

## Tool snapshot

実装入口で `git ls-remote https://github.com/numtide/llm-agents.nix HEAD` を確認し、default branch HEAD `8bec0ce1cbb0a39f8f08dc97a7635af847779f99`（2026-09-24）に固定した。旧 pin `8011aaf2e65e9222b2121c2fbb622912d7469bd6`（2026-09-22）から約150 commit進んでいた。

| ツール            | 旧版    | 候補    |
| ----------------- | ------- | ------- |
| Claude Code       | 2.1.280 | 2.1.281 |
| Codex             | 0.155.1 | 0.156.1 |
| Copilot CLI       | 1.0.87  | 1.0.88  |
| Antigravity CLI   | 1.2.8   | 1.2.10  |
| RTK               | 0.49.0  | 0.49.0  |
| APM               | 0.31.0  | 0.31.0  |
| Herdr             | 0.9.1   | 0.9.1   |
| code-review-graph | 2.3.9   | 2.3.9   |

Claude Code の公式 CHANGELOG（v2.1.281）を確認した。この repo の quality floor 判断基準（多 agent ワークフロー・worktree 隔離・permission/trust boundary の信頼性）に合致する修正:

- **permission bypass**: auto mode / `--dangerously-skip-permissions` で、削除対象がコマンド置換結果のみの再帰 `rm`（例: `rm -rf "$(pwd)"`）が Bash allow ルールに関わらず無承認実行されていた不具合の修正（`CLAUDE_CODE_DISABLE_SUBSTITUTION_RM_PROMPT=1` でのみ従来挙動に戻せる）。この repo は `defaultMode: auto` を既定にしているため直撃。
- **permission rule の迂回**: NUL byte を含む permission rule がワイルドカード一致へ展開されていた不具合の修正（該当ルールは無害化されマッチしなくなる）。
- **sandbox 診断**: `sandbox.excludedCommands` が `git rev-parse --git-dir`、shell builtin と同名のプログラム、`[WIP]` や `#` 行を含む commit message に一致しなかった不具合の修正。

他は resumed session の履歴破損修正、tool call の overlong name 起因スタック、MCP・PDF・headless session まわりの修正など trust boundary に直結しない項目のため床上げ根拠から除外した。よって `minClaudeCode` を `2.1.280` → `2.1.281` へ引き上げ、pin も `2.1.281` を採用する（2.1.281 が最新）。

Codex は snapshot 内で `0.155.1` → `0.156.1` へ進んだ。前回（2026-09-23、ADR-0065）は 0.156.1 の release note（0.156.0→0.156.1 の hotfix 差分。GPT-6 モデルカタログ追加のみ）だけを確認して `minCodex` を `0.155.0` に据え置いたが、実際に snapshot が進んだ差分は `0.155.1`→`0.156.1` であり、その途中の `0.156.0` 自体の公式 release note を確認していなかった。今回 GitHub Releases（`rust-v0.156.0`）本文を確認したところ、次の記載があった:

> Close sandbox isolation gaps involving inbound Windows connections, privileged Linux/macOS sockets, and writes through read-only macOS file handles. (#44639, #45984, #46500)

これはこの repo の Codex floor 判断基準（[ADR-0047](../adr/0047-test-quality-floors-through-package-outputs.md) の sandbox・trust boundary の信頼性）に合致する。よって `minCodex` を `0.155.0` → `0.156.0` へ引き上げる（前回サイクルの見落としを本更新で訂正する）。0.156.1 自体は GPT-6 モデルカタログ追加のみで追加の床上げ根拠はない。

Copilot CLI 1.0.87→1.0.88、Antigravity CLI 1.2.8→1.2.10 は非公開 changelog のため package metadata の追従のみ確認し、quality floor 対象外とした（前例踏襲）。RTK・APM・Herdr（バイナリ）・code-review-graph は snapshot 内でも変化なし。

`nix flake update llm-agents`（`flake.nix` の URL 書き換え後）で lock を更新し、`nix flake check --no-build --all-systems` は全6 devShell と formatter の評価に成功した。3 system の overlay 経由 `pkgs.llm-agents.<pkg>.version` 実測は claude-code 2.1.281 / codex 0.156.1 / copilot-cli 1.0.88 / antigravity-cli 1.2.10 / rtk 0.49.0 / apm 0.31.0 / herdr 0.9.1 / code-review-graph 2.3.9 で3 system一致した。Codex は3 system とも direct package（`inputs.llm-agents.packages.${system}.codex`）の dry-run で fetch 対象（cache hit）であり、build 対象（rustc OOM を伴う LTO source build のリスク）に含まれないことを確認した。x86_64-linux の実 `nix develop` build と、隔離 HOME での8 CLI 起動（claude 2.1.281 / codex-cli 0.156.1 / copilot 1.0.88 / agy 1.2.10 / rtk 0.49.0 / apm 0.31.0 / herdr 0.9.1 / code-review-graph 2.3.9）も成功した。

## APM payload

`apm outdated`（隔離 cwd/HOME）が示した6件の outdated 依存を起点に、floating `(default)` 依存は selected subtree の content hash 比較、exact pin 依存は実際の upstream diff を確認して個別に採否した。

- **herdrdev/herdr/skills/herdr**: 同梱 Herdr バイナリが 0.9.1 になって以降 pin が 0.9.0 相当の `b99002ac99b09e00b4ca692436cb15a6b0d676f1` のまま据え置かれていた。`git diff` で実差分（`--machine` 経由のリモート SSH machine 操作手順の追加、`pane split` の暗黙ターゲット規則の明確化、alternate-screen scrollback 回復の説明変更）を確認し、pin を `065ef9d6a531c49fb8bee7e818ef837065b21ee9`（release v0.9.1）へ進めた。apm.yml のコメントも「Herdr 0.9.1 同梱」へ追従した。
- **stablyai/orca/skills/orca-cli**: discovery 文言の簡素化という実差分（`git diff` で確認）を確認した。`git rev-parse v1.4.210` は `0afcacccb238bbb288acd7a0e412d3979c635ec8` を指すが、この commit を候補にして `apm install` すると、lock は別の commit `4a5afd70a3db16f1cd546458e070681a4eb0da18` へ resolve された。`git diff 0afcaccc.. 4a5afd70..` は空（tree 内容は同一）だったため、`apm audit --ci` の `ref-consistency` check（manifest 記載commitとlockfile resolved_commitの一致を要求）を満たすよう、`apm` 自身が解決した `4a5afd70` を最終的な pin として採用した。
- **remotion-dev/skills/skills/remotion-best-practices**: `4.0.525`→`4.0.528` で connected-compositions パターンの新設、multi-scene 構成の全面改稿、`Audio`/`Video` の `from` prop 移行、`render --frames` の追加という実差分を確認し、pin を `41b22eec767aa77eb31df62ccb3bacf52ed771fb` へ進めた。
- **GoogleChrome/modern-web-guidance/skills/modern-web-guidance**: Anchor positioning・Grid lanes（masonry）の Baseline 状況更新を含む browser-support 記述の広範な更新という実差分を確認し、pin を `22ab18dfb50a5d7e3bdcf471c14076a5534eae4e`（release v0.0.190）へ進めた。
- **stablyai/orca の floating `(default)` 依存 `orchestration` / `computer-use`**: 前回サイクル（2026-09-22）と異なり resolved_commit が `059ee59a48272854a2317cc267bdd03f23ec9aa6`→`122b8c25d7c16f76e395bf9a65887d7c4bc5003b` へ進み、selected content hash も変化した（floating のため apm.yml は変更せず、lock 再生成による自然反映のみ）。
- **mattpocock/skills**: pin `6654f6b60cd9d5be8b54c6fafe44346dabeb3b76` について `apm outdated` は最新 tag `v1.2.3`（`6acc160e`）を示すが、`gh api repos/mattpocock/skills/compare/6acc160e...6654f6b6` で実測すると pin の方が39 commit 先行しており（0 behind）、既知の tag 専用比較に起因する false positive（2026-09-03 と同型）と確認したため pin を維持した。
- **supabase/agent-skills/skills/supabase-postgres-best-practices**: floating `(default)` 依存で resolved_commit `551274ed2fe97c8fea1325f7ceb05803a542f8df` へ前進した（lock 再生成による自然反映のみ、apm.yml は変更なし）。
- Impeccable、Matt Pocock managed set、Effect-TS、shadcn、anthropics `pdf`/`skill-creator`、vercel-labs 各 skill は `apm outdated` で up-to-date、または別更新単位のため今回の候補にしていない。

隔離 cwd/HOME での `apm install --target claude,codex --https`（non-frozen）でlockを再生成し、同一隔離環境の `apm install --frozen --target claude,codex --https` で SHA-256 が不変（`e4e54c68...`）であることを確認した。`apm audit --ci` は10チェック全て成功（`lockfile-exists` / `ref-consistency` / `deployment-ledger-owners` / `deployed-files-present` / `no-orphaned-packages` / `skill-subset-consistency` / `config-consistency` / `content-integrity` / `includes-consent` / `drift`）。lock は oxfmt で再整形していない。

## 検証

- `nix flake update llm-agents`（`flake.nix` の URL revision 書き換え後）、`nix flake check --no-build --all-systems`: 成功。
- 3 system の overlay 経由 `pkgs.llm-agents.<pkg>.version` 実測（8パッケージ）: 一致。Codex は3 system とも direct package の dry-run で fetch 対象（build 対象外）を確認。
- x86_64-linux の実 `nix develop` build と8 CLI version 起動（隔離 HOME）: 成功。
- `tests/ai-quality-floor.bats`: floor 値（`2.1.281` / `0.156.0`）と診断メッセージの固定値を更新し、7/7 成功。
- `tests/nix-devshell.bats`: snapshot revision の固定値、AI toolset snapshot contract の参照先 research doc（本ファイル）を追従させ、28/28 成功。
- `tests/apm-runtime.bats`: 4 exact pin（herdr / modern-web-guidance / remotion-best-practices / orca-cli）と floating orca 2件（orchestration / computer-use）の resolved_commit・content_hash 断定を追従・新設し、15/15 成功。herdr は従来 `assert_lock_entry` 断定を持たなかったため、この更新単位で新設した。
- `bunx tsc --noEmit`: エラーなし。
- `bats tests/*.bats`（全スイート）: `LC_ALL=C bats tests/*.bats` で740/742成功。失敗2件は次の通り、いずれも regression ではない:
  - `tests/codex-config.bats` の「Codex config migration keeps dotenv denied and public examples readable without a raw read grant」（`codex sandbox` を起動する統合テスト）。別 worktree で main（`8ed3db4`、Codex 0.155.1）をベースラインとして同じテストを単体実行し、同じく失敗することを確認した（この diff とは無関係な既存の環境依存フレーク）。
  - このファイル自体を参照する `tests/nix-devshell.bats` の「AI toolset snapshot and selected payload source contract is documented」は、本ファイル作成前の中間実行で一時的に失敗した後、本ファイル作成後は成功した。

## 二軸レビュー

`/code-review`（base: `main`）を実行した。結果は後述。

## 最終結果

`nix flake update`・3 system 評価・x86_64-linux 実 build・APM 隔離 install/audit・関連 bats が成功した。live apply、push・PR は未実施。aarch64-linux / aarch64-darwin の実機実行、2.1.281 の各修正・0.156.0 の sandbox isolation 修正を実際の agent session で機能的に再現する smoke、Copilot CLI / Antigravity CLI の version固有 changelog は未確認のまま。
