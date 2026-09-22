---
type: decision
title: llm-agents snapshot と worktree/trust boundary の quality floor を更新する
description: Claude Code の worktree 隔離・permission bypass 修正と Codex の WSL sandbox escape・Unix shutdown 修正を根拠に quality floor を引き上げ、通常 APM payload refresh を同じ回の別更新単位として採用する
tags: [adr, nix, llm-agents, apm, claude-code, codex, worktree, wsl]
timestamp: 2026-09-22
status: accepted
---

# llm-agents snapshot と worktree/trust boundary の quality floor を更新する

2026-09-22 の定期メンテナンスで見つかった更新候補のうち、同じ互換性ゲート・検証結果・rollback 境界を共有する変更だけを一つの更新単位として採用する（[ADR-0045](0045-separate-llm-agents-and-apm-update-units.md) の四更新単位の方針を継続）。

## Decision

- `llm-agents.nix` は `private_dot_config/nix-devshell/flake.nix` の immutable revision を `52aac5d0a0c206feaeb1889cbec62ad37dc8843e` から upstream default branch HEAD `9032892fd4d89bdad79c858a81aae1268ad2d191`（2026-09-21）へ更新する。共有 nixpkgs（`nixpkgs-26.05-darwin`）と x86_64-linux / aarch64-linux / aarch64-darwin の3-system境界は維持する。3 system の package metadata は claude-code 2.1.278、codex 0.155.1、copilot-cli 1.0.87、antigravity-cli(`agy`) 1.2.7、rtk 0.49.0（変化なし）、apm 0.31.0、herdr 0.9.1、code-review-graph 2.3.9 で一致する。
- Claude Code の quality floor を `2.1.261` から `2.1.277` へ引き上げる。根拠は 2.1.273–2.1.277 の公式 CHANGELOG から確認した次の修正: worktree 隔離済みセッションが certain nested shell expansion を含む Bash コマンドを受理してしまう不具合の修正（2.1.274、worktree 隔離破れ）、special な shell 変数を loop/assign するコマンドが permission check をすり抜けていた不具合の修正（2.1.274、permission bypass）、subagent/background agent が streamed reply に token usage や model id を欠く場合に結果配信されず failed 報告される不具合の修正（2.1.273、多 agent ワークフローの error 伝搬）、plugin の LSP server 終了時に background session (`claude --bg`) ごと終了してしまう不具合の修正（2.1.277、この repo が `enabledPlugins` に LSP を含むため直撃）、`--worktree` session でメイン repository の project skill が `.claude/skills` untracked のため読み込まれない不具合の修正（2.1.277、skill discovery）。pin 自体は 2.1.278 まで進むが、その内容（auto mode server-side classifier の billing 変更のみ）に床上げ根拠となる記述がないため床は 2.1.277 に留める。
- Codex の quality floor を `0.153.4` から `0.155.0` へ引き上げる。根拠は 0.155.0 の公式 release note から確認した次の修正: restricted WSL sandbox からの Windows-process escape 遮断と brokered shell snapshot の credential exposure 強化（`#44286`/`#43909`/`#44040`。この repo は WSL2 上で稼働するため直撃する）、Unix SIGTERM 受信時の app-server stdio shutdown の graceful 化（`#44523`、この repo の Codex floor 判断基準に明記された "Unix shutdown" に合致）。pin 自体は 0.155.1 まで進むが、その内容（TUI の reasoning summary 既定値 revert のみ）に床上げ根拠となる記述がないため床は 0.155.0 に留める。
- Copilot CLI 1.0.87、Antigravity CLI 1.2.7、RTK 0.49.0（変化なし）、Herdr 0.9.1、code-review-graph 2.3.9 は package metadata の追従のみ確認し、新設の quality floor は設けない。version 固有の公式 changelog は Herdr のみ確認（0.9.1、bugfix のみで設定変更不要）。Copilot CLI / Antigravity CLI の 1.0.83→1.0.87 / 1.2.3→1.2.7 は version 固有の changelog を確認していない。
- 通常 APM payload refresh を同じ回の別更新単位として採用する。APM binary は snapshot が供給する 0.31.0 を使う。実体差分は次の2件: `mizchi/skills` の upstream が `meta/` サブディレクトリを廃止しフラット構成へ移行したため、`apm.yml` の依存パスを `mizchi/skills/meta/empirical-prompt-tuning` から `mizchi/skills/empirical-prompt-tuning` へ追従した。この追従でパッケージ全体の `content_hash` は `sha256:20e7fba9...` から `sha256:26042612...` へ変化する（`README.md` の install 例3箇所が新パスへ書き換わったことによる差分で、実際のスキル本体である `SKILL.md`/`SKILL-ja.md` の hash（`sha256:0a38d8...` を含む）は不変）。`stablyai/orca` の floating `orchestration` / `computer-use` は selected content hash が変化し、それぞれの `SKILL.md` の routing 文言（Orca embedded browser・Playwright/CDP・programmatic path への誘導基準の明確化）が upstream で更新されていることを確認した。同じ floating dependency の `shadcn`・`find-skills` は resolved_commit のみ revision-only に前進し selected content hash は不変。`stablyai/orca` の `orca-cli` は exact pin `de0a91b9` のまま resolved_commit・content hash とも不変。他13依存（Impeccable skill・Matt Pocock full set・Effect-TS・modern-web-guidance・remotion-best-practices・herdr skill 等の exact pin 群）は不変のまま維持する。
- Impeccable skill pin（現行 `cb56ed6c19a07329a9fa0cd4e657bee040156593`）と Matt Pocock managed set（現行 `6654f6b60cd9d5be8b54c6fafe44346dabeb3b76`）は、upstream 双方が default branch HEAD を進めていることを確認済みだが（Impeccable `83c2c735...`、Matt Pocock `c55ee460...`）、それぞれ専用の互換性ゲート（Design Hook 契約差分、workflow migration 差分）の調停が本更新単位のスコープ外のため、今回は据え置く。
- 実装の正本は Nix flake / lock、`modules/ai.nix`、`apm.yml` / `apm.lock.yaml` とし、配備先を直接編集しない。

## Verification boundary

- Nix source gate: `nix flake check --no-build --all-systems` が3 system で成功。新しい quality floor の assert（`requireQualityFloor`）が3 system の deep eval を強制するため、shallow eval による偽陽性（ADR-0028 の教訓）は生じない。3 system の overlay 経由 `pkgs.llm-agents.<pkg>.version` 実測が claude-code 2.1.278 / codex 0.155.1 / copilot-cli 1.0.87 / antigravity-cli 1.2.7 / rtk 0.49.0 / apm 0.31.0 / code-review-graph 2.3.9 で一致することを確認した。x86_64-linux (host) では `nix develop` で実ビルドし、claude / codex / copilot / agy / rtk / apm / herdr / code-review-graph の8 CLI 実測 version が snapshot と一致することを確認した。
- APM gate: `apm.yml` を隔離ディレクトリへコピーし、隔離 `$HOME` で snapshot 供給の apm 0.31.0 により `apm install --https` を実行して lock を再生成した。同じ環境の `apm install --frozen --https` が SHA-256 一致で書き戻しなし、`apm audit --ci` が10/10 通過した。
- リポジトリ既存の bats full suite が通過。floor 引き上げに伴い `tests/ai-quality-floor.bats`（floor 値・診断メッセージの期待値）、`tests/herdr.bats`（Herdr 期待 version）、`tests/apm-runtime.bats`（apm_version・shadcn/orca 系 lock entry の期待値）を同じ更新単位で追従させた。
- aarch64-linux / aarch64-darwin の実機実行、2.1.273–2.1.277 と 0.155.0 の床上げ根拠そのもの（worktree isolation bypass、permission bypass、WSL sandbox escape 等）を実際の agent session で機能的に再現する smoke は未確認のまま。

## Deliberately separate

- Impeccable skill pin の前進（`cb56ed6c` → 候補 `83c2c735...`）は、[ADR-0029](0029-impeccable-pin-advance-with-stop-hook.md) / [ADR-0053](0053-separate-impeccable-skill-and-engine.md) が定める Design Hook 互換性ゲート（`IMPECCABLE_HOOK_RUNTIME` 経由の `tests/design-hook.bats` probe と per-edit tier / Stop contract / dedupe の差分切り分け）を未実施のため、この更新単位に含めない。
- Matt Pocock managed set の前進（`6654f6b6` → 候補 `c55ee460...`）は、[ADR-0042](0042-mattpocock-managed-set-update-gate.md) が定める ordered gate（frozen no-rewrite、audit 10/10、related contract test、full Bats、25-skill discovery、isolated chezmoi dry-run）を未実施のため、この更新単位に含めない。
- floating（unpinned）な APM dependency のうち `anthropics/skills`（pdf/skill-creator）・`Effect-TS/skills`・`vercel-labs/agent-skills` 4skill・`supabase/agent-skills` は、隔離 `apm install` に伴い resolved_commit が自然に現在の upstream HEAD へ再解決されたが、selected content hash は不変であり実体差分がないためこの ADR は個別に採否判断しない。

## Consequences

この境界により、worktree 隔離・permission bypass・WSL sandbox escape という trust boundary 直結の snapshot 更新と、通常 APM payload の実体差分（mizchi パス追従、orca routing 文言更新）を同じ verification / rollback 証跡で扱える。Impeccable と Matt Pocock は upstream が進んでいる状態のまま次回以降の専用更新単位に持ち越す。

関連: [調査ノート 2026-09-22](../research/llm-agents-and-apm-update-2026-09-22.md) / [ADR-0045](0045-separate-llm-agents-and-apm-update-units.md) / [ADR-0028](0028-claude-code-darwin-x64-local-override.md) / [ADR-0029](0029-impeccable-pin-advance-with-stop-hook.md) / [ADR-0042](0042-mattpocock-managed-set-update-gate.md) / [ADR-0053](0053-separate-impeccable-skill-and-engine.md) / [ai-runtimes](../../runtime/ai-runtimes.md)
