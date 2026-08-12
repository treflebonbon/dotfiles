---
type: decision
title: llm-agents snapshot を更新し Claude Code / Codex の trust boundary 修正を品質フロアにする
description: 共有 nixpkgs を固定したまま llm-agents と導入済み AI CLI を更新し、permission bypass・sandbox 迂回（Claude Code 2.1.223-2.1.225）と trust boundary・secret redaction（Codex 0.147.0）を新しい床として採用する
tags: [adr, nix, llm-agents, claude-code, codex]
timestamp: 2026-08-12
status: accepted
---

# llm-agents snapshot を更新し Claude Code / Codex の trust boundary 修正を品質フロアにする

## Context

`numtide/llm-agents.nix` の 2026-08-12 時点 main HEAD (`8651bf95690800f5361d53a9abda0fc3fbe0e2ec`) を確認したところ、claude-code / codex ともに複数版が進んでいた。

Claude Code の公式 CHANGELOG（2.1.223-2.1.228）には、タブ・不可視 Unicode でコマンドの一部を permission 承認ダイアログから隠す permission bypass、workflow script が動的 `import()` でサンドボックス外のコードを実行できる問題、agent 定義の `bypassPermissions` が org の bypass-permissions 無効化ポリシーを無視する権限ギャップ（2.1.223）、sandbox filesystem の deny エントリが末尾スラッシュ付きだと Linux/macOS で静かに迂回できる問題と sandbox violation 詳細が Bash tool result に表示されない問題（2.1.224）、auto mode が自身の safety-filter refusal を consecutive-block limit へ誤加算する不具合（2.1.225）が含まれる。2.1.226-2.1.228 は床上げの具体根拠を確認できなかった（2.1.228 の claude.ai 同期 skill hardening はこの repo が skill を apm / chezmoi / nix 経由でのみ取得するため対象外）。pin 自体は 2.1.223-2.1.225 の修正により 2.1.228 まで進むため、床もその version に揃える。

Codex 0.147.0 の release note には、不慣れな local project への明示的 trust 要求と managed authentication 制約の credential 使用前強制、Agent Plugin runtime の isolation 強化（policy 更新失敗時のネットワーク拒否含む）、表示コマンド・履歴再生からの secret / bearer token redaction 強化が含まれる。

いずれも worktree 隔離・auto mode・多 agent ワークフロー・外部 skill 実行という、この repo が主用する運用形態の permission/trust boundary に直結する。

同じ snapshot で他の消費パッケージも進む: copilot-cli 1.0.78 → 1.0.79、antigravity-cli 1.1.10 → 1.1.12、rtk 0.44.2 → 0.45.0。apm は 0.28.0 のまま変化なし。この4種には `modules/ai.nix` の quality-floor assert がなく、package metadata 追従のみを確認した。

## Decision

- `llm-agents.nix` を immutable snapshot `8651bf95690800f5361d53a9abda0fc3fbe0e2ec` に固定し、ユーザー devShell が共有する nixpkgs `fca2dbd4c00c3063235e56bb91758e24fc67b7b8` は据え置く（`flake.lock` の `nixpkgs_2` ノードで確認済み）。
- 導入 version を claude-code 2.1.228、codex 0.147.0、copilot-cli 1.0.79、antigravity-cli 1.1.12、rtk 0.45.0、apm 0.28.0 とする。
- `minClaudeCode` を `2.1.222` から `2.1.228` へ、`minCodex` を `0.146.1` から `0.147.0` へ引き上げる。根拠は上記 Context の permission bypass / sandbox 迂回（Claude Code 2.1.223-2.1.225）と trust boundary / secret redaction（Codex）の修正。Claude Code の床は 2.1.225 の修正が主根拠で、pin 自体が到達する 2.1.228 に合わせる。
- copilot-cli / antigravity-cli / rtk / apm は quality-floor assert の対象外のまま維持し、追加の dotfiles 設定変更は行わない。

## Verification

- `nix flake check --all-systems`（x86_64-linux / aarch64-linux / aarch64-darwin の3 system）が新 pin・新 floor で通過することを確認した。
- 3 system それぞれで `pkgs.llm-agents.<pkg>.version`（`modules/ai.nix` と同じ `shared-nixpkgs` overlay 適用後の経路）を評価し、上記6 package の version が3 system で一致することを確認した（ADR-0028 の教訓 — 浅い評価は platform 縮小を検出できない — を踏まえ、`devShells.<system>.default` を `.drv` まで forceする deep eval を実施）。
- Linux host からの評価境界は上記までで、aarch64-darwin の実機実行は確認していない。
- `tests/nix-devshell.bats` のうち snapshot/floor を検証する3 test（`--filter 'snapshot|Claude Code|Codex'`）は green で再実行した。同ファイルの `code-review-graph package meets its FastMCP floor on all supported systems` test（`tests/nix-devshell.bats:162`）は `nix develop` 経由で devShell 全体を source から build するため今回は再実行していない。`code-review-graph` の `version` は `pkgs.callPackage ./packages/code-review-graph.nix { inherit inputs; }` 経由で `2.3.7`（変化なし）であることを評価で確認済みで、同 test の評価半分は `nix flake check --all-systems` が cover する。

## Consequences

本 ADR は [ADR-0034](0034-update-ai-toolset-safety-baselines.md) のうち snapshot 固定値・`minClaudeCode`/`minCodex` の値だけを supersede する。x86_64-darwin サポート終了・3-system化の decision は ADR-0034 のまま有効で、本 ADR では再決定しない。

決定そのものの正本は本 ADR。`runtime/ai-runtimes.md` の「現在の」floor サマリー行（`baseline は ... 床固定する`）は本 ADR の `minClaudeCode`/`minCodex` 値と同期させる一方、同ファイルの日付付きエントリは pin 更新ごとに確認した release note・検証範囲を記録する append-only な運用履歴であり、本 ADR の記述と矛盾しない限り両方を保持する。将来の pin 更新では [ADR-0028](0028-claude-code-darwin-x64-local-override.md) / [ADR-0034](0034-update-ai-toolset-safety-baselines.md) に従い、pin 上の各 package version の変化をトリガーに再評価する。

関連: [ADR-0028](0028-claude-code-darwin-x64-local-override.md) / [ADR-0033](0033-update-llm-agents-snapshot-and-claude-baseline.md) / [ADR-0034](0034-update-ai-toolset-safety-baselines.md) / [ai-runtimes](../../runtime/ai-runtimes.md)
