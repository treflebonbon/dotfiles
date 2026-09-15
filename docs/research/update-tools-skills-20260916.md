# ツール・スキル更新（2026-09-16）

## 要件と採用境界

ユーザーの `/implement ツールとスキルの更新` に基づき、既存 AI tool snapshot と APM 全19依存の更新候補を確認する。ADR-0045 に従い、tool snapshot と通常スキルの2更新単位を別々に採否する（Impeccable、Matt Pocock managed set は対象外）。前回更新（PR #320、2026-09-15）から24時間しか経っていないため、まず upstream HEAD の再確認と selected subtree の content hash 比較を先に行い、実差分がある場合のみ検証コストの大きい nix build / APM lock 生成に進む方針とした。task worktree は main `7c4ab3d` から作成した。

受入条件は exact snapshot と lock の整合、3 system の評価、Linux build・CLI起動、関連テスト・型チェック・full suite、二軸レビューとコミット。品質 floor、モデル・権限、配布経路、新規ツール追加、private skill 改稿は対象外。live apply・push・PR は行わない。

## Tool snapshot

入口で確認した [llm-agents default branch snapshot](https://github.com/numtide/llm-agents.nix/tree/52aac5d0a0c206feaeb1889cbec62ad37dc8843e) `52aac5d0a0c206feaeb1889cbec62ad37dc8843e` に固定した。旧 snapshot `1dedf84794052aa7569df5b8335de60aee97af35` から50 commit進んでおり、GitHub Compare のファイル一覧では `packages/claude-code/hashes.json` と `packages/antigravity-cli/hashes.json` のみが変更対象だった（Codex、Copilot CLI、RTK、Herdr、APM の該当ファイルは差分に含まれない）。

| ツール          | 旧版    | 候補    |
| --------------- | ------- | ------- |
| Claude Code     | 2.1.270 | 2.1.272 |
| Antigravity CLI | 1.2.2   | 1.2.3   |
| RTK             | 0.49.0  | 0.49.0  |
| Codex           | 0.154.0 | 0.154.0 |
| Copilot CLI     | 1.0.83  | 1.0.83  |
| Herdr           | 0.9.0   | 0.9.0   |
| APM             | 0.30.0  | 0.30.0  |

Claude Code の公式リリースノート（v2.1.271、v2.1.272）を確認した。v2.1.272 は "Bug fixes and reliability improvements" の一行のみ。v2.1.271 には `permissions.blockReadsOutsideWorkingDirectories` 下でのプロンプト回避の修正が含まれるが、[ADR-0055](../adr/0055-disable-block-reads-outside-working-directories.md) によりこの repo は同 fence を無効化済みのため、品質 floor（`minClaudeCode = "2.1.261"`）を引き上げる根拠にはしない。他の変更点（fast mode、`allowed_domains`、VSCode/Web/Tag 関連）も trust boundary に直結する記述はなかった。Antigravity CLI は非公開の changelog のため version 固有の変更内容は未確認のまま。`minCodex` 含め既存の品質 floor は据え置く。

`nix flake lock --update-input llm-agents` で lock を更新し、`nix flake check --no-build --all-systems` は全6 devShell と formatter の評価に成功した。3 system の `nix build --dry-run` はいずれも Claude Code 2.1.272、Antigravity CLI 1.2.3、Codex 0.154.0、Copilot CLI 1.0.83、RTK 0.49.0、Herdr 0.9.0、APM 0.30.0 で一致した。x86_64-linux の実 `nix build .#devShells.x86_64-linux.wsl` は新規2 derivation（Claude Code、Antigravity CLI）のビルドで完了し、隔離 HOME での7 CLI version 起動（`claude` 2.1.272 / `agy` 1.2.3 / `codex-cli` 0.154.0 / `copilot` 1.0.83 / `rtk` 0.49.0 / `herdr` 0.9.0 / `apm` 0.30.0）も成功した。

## スキル候補の比較

全19依存の配布対象は不変のため manifest は維持し、`apm outdated` と selected subtree の content hash 比較で採否した。

| 依存 | 確認内容 | 採否 |
| --- | --- | --- |
| pdf / skill-creator / effect-ts / herdr / empirical-prompt-tuning / shadcn / react-view-transitions / web-design-guidelines / react-best-practices / composition-patterns / supabase-postgres-best-practices（floating、11件） | `apm outdated` で up-to-date | 配布差分なし・維持 |
| mattpocock/skills | `apm outdated` は `v1.2.3`(`6acc160e`) を latest と表示するが、pin `6654f6b6` は同revisionのtag専用比較に対して `ahead_by: 39, behind_by: 0`（`gh api .../compare` で実測）。既知の false positive | 配布差分なし・維持 |
| stablyai/orca `computer-use` / `orchestration`（floating） | 旧 resolved `5e70014d` → 新 default HEAD `60d79395` まで selected subtree (`skills/computer-use/SKILL.md` 等) の blob SHA 不変 | revision-only、floating解決を自然反映 |
| stablyai/orca `orca-cli`（exact pin `de0a91b9`） | upstream 最新 `776e424e`（`v1.4.203`）まで selected subtree の blob SHA 不変 | 配布差分なし・pin維持 |
| vercel-labs/skills/find-skills（floating） | 旧 resolved `d667282` → 新 default HEAD `d6b37f62` まで selected subtree の blob SHA 不変 | revision-only、floating解決を自然反映 |
| GoogleChrome/modern-web-guidance（exact pin `bfd8c8dd`） | upstream HEAD は前回確認時点（`16ed22b43f`）から不変 | 配布差分なし・維持 |
| pbakaus/impeccable（exact pin `cb56ed6c`） | upstream HEAD が `2149fcce39` → `0a4e72a2` へ進行を確認したが、Impeccable は ADR-0045 で Design Hook 互換性ゲートを要する別更新単位のため本回では評価・採用しない | 対象外（別更新単位） |
| remotion-dev/skills/remotion-best-practices（exact pin `bd566b65`） | upstream HEAD `3b9e6561dababf40a485772a7cd641268bb7c365` で selected subtree の content hash が変化（version marker `4.0.524`→`4.0.525` のみ、機能差分なし） | payload変更、exact pin採用 |

Remotion の exact pin を `3b9e6561dababf40a485772a7cd641268bb7c365` へ更新し、`apm.yml` を隔離 cwd（Git remote なし）へコピーして `apm install --target claude,codex --https` を実行した。生成 lock の SHA-256 `671535602fbb158abdd29f751dc7eee0e3fe7fbeee62694bb5ebdea673e860e6` は同一環境の `apm install --frozen --target claude,codex --https` 前後で不変、`apm audit --ci` は10/10全通過した。生成 lock を diff すると、変更対象は remotion-best-practices の content hash と deployed file hash 群、および `computer-use` / `orchestration` / `find-skills` の revision-only な `resolved_commit` 更新のみで、他13依存の pin・content hash は無変化だった。両 target（`.agents/skills/` / `.claude/skills/`）に `version: 4.0.525` の payload を確認した。

## 検証

- `nix flake lock --update-input llm-agents`、`nix flake check --no-build --all-systems`: 成功。
- 3 system の `nix build --dry-run`: 7パッケージの版が一致。
- x86_64-linux の実 `nix build .#devShells.x86_64-linux.wsl` と隔離 HOME での7 CLI version 起動: 成功。
- `tests/nix-devshell.bats`: snapshot revision の固定値2箇所（旧値参照）を今回の revision と本記録パスへ更新し、28/28 成功。
- 隔離 cwd/HOME の APM install（非frozen→frozen）と `apm audit --ci` 10/10、両 target の remotion payload discovery: 成功。
- `tests/apm-runtime.bats`: remotion pin/content hash と `computer-use` / `orchestration` の revision-only な resolved_commit（`5e70014d`→`60d79395`）の固定値を更新し、15/15 成功。`tests/apm-cache-refresh.bats` 8/8 成功。
- `bunx tsc --noEmit`: エラーなし。
- `bats tests/`（732件）: 716 PASS、16 FAILで `bun run test` は exit 1。失敗16件は (a) `tests/mattpocock-update-gate.bats` の6件、(b) `tests/dogfood.bats` の8件、(c) `tests/local-skills.bats` の1件。(a)はこのセッションの `LANG=en_US.UTF-8` に起因する GNU `sort` 収集順序差（2026-09-02 follow-up で確認済みの既知原因と一致）で、`LC_ALL=C bats tests/mattpocock-update-gate.bats` は13/13全通過した。(b)(c)は本更新の差分（flake.nix/flake.lock、apm.yml/apm.lock.yaml、tests/nix-devshell.bats、tests/apm-runtime.bats）と無関係なファイルへの依存で、変更前の `main`（`7c4ab3d`）で同じ3ファイルを実行しても同一の16件がまったく同じテスト名で失敗することを実測し、本更新による regression ではないことを確認した。原因調査そのものは本更新のスコープ外とする。

## 二軸レビュー

Standards / Spec 各1件（`code-review` 実行）。指摘内容は次を参照。

## 最終結果

`nix flake lock`・3 system 評価・x86_64-linux 実 build・7 CLI 起動・関連 bats・typecheck が成功し、full suite は既知原因を確認済みの16件を除き716/732成功した。APM の remotion pin 更新は隔離 lock 生成・frozen no-rewrite・audit 10/10・両target discoveryを通過した。live apply、push・PR は未実施。aarch64-linux / aarch64-darwin の実機実行、Antigravity CLI 1.2.3 の version固有 changelog は未確認のまま。
