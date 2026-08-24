---
type: decision
title: llm-agents snapshot と Impeccable pin 前進を一つの更新単位として採用する
description: llm-agents の品質 floor 引き上げと Design Hook 互換性ゲートを通過した Impeccable payload を一つの atomic update unit として採用し、Remotion の version-only 更新と Matt Pocock workflow migration は別境界に保つ
tags: [adr, nix, llm-agents, apm, impeccable, claude-code, codex, antigravity]
timestamp: 2026-08-24
status: accepted
---

# llm-agents snapshot と Impeccable pin 前進を一つの更新単位として採用する

2026-08-24 の調査（[調査ノート](../research/llm-agents-and-apm-update-2026-08-24.md)）で見つかった更新候補のうち、同じ互換性ゲート・検証結果・配備境界・rollback 境界を共有する変更だけを一つの更新単位として採用する。

## Decision

- `llm-agents.nix` は exact snapshot `3c16acbe5229040ee8f4d6f7b85de757e14b4bda` を採用する。
- Claude Code の quality floor を `2.1.238` から `2.1.239` へ引き上げる。根拠は `extensions.worktreeConfig` が設定された repo で Linux sandbox が存在しない `.git/config.worktree` を unreadable と誤判定し sandbox 化された git コマンドを壊す不具合、working directory 削除後の hook が `posix_spawn ENOENT` で失敗する不具合、`ListAgents`/`SendMessage` の自己名解決と live teammate 一覧の不具合の修正。いずれも `teammateMode: auto` と worktree 隔離を主用するこの repo の信頼性に直結する。pin 自体は `2.1.241` まで追従するが、`2.1.240`/`2.1.241` は release note に床上げ根拠となる具体記述がないため単独の床上げ根拠にはしない。
- Codex は `0.149.0` を維持する（この snapshot 範囲で変更なし）。
- Antigravity CLI は package metadata の追従のみ（`1.1.17` → `1.1.19`）で、新設の quality floor は設けない。version 固有の公式 changelog は未確認のまま。
- APM は stable `0.28.0` を維持し、selected payload が変わる Impeccable だけを `5a149f3fdb1b5793f10567233b1dcab98fc305fd` から `c39b6425fa54a093749b9a236adcd003818167c1` へ進める。live-server の symlink 経由ワークスペース脱出修正、Claude hook installation / home-scoped agent freshness の修正を含むため、[ADR-0029](0029-impeccable-pin-advance-with-stop-hook.md) の Design Hook 互換性ゲートを通過させてから採用する。
- 対応 system は `x86_64-linux`、`aarch64-linux`、`aarch64-darwin` の3 systemを維持する。
- 実装の正本は Nix flake / lock、`modules/ai.nix`、`apm.yml` / `apm.lock.yaml` とし、配備先を直接編集しない。

## Verification boundary

- Nix source gate: `nix flake check --no-build --all-systems` が3 system で成功すること。x86_64-linux (host) では `nix develop` で実ビルドし、claude-code / codex / copilot-cli / antigravity-cli(`agy`) / rtk / apm の実測 version が snapshot の package metadata と一致すること。
- APM gate: `apm.yml` を隔離ディレクトリへコピーし、隔離 `$HOME` で `apm install --https` を実行して lock を再生成する。生成された `apm.lock.yaml` をそのまま repo へ戻し、同じ隔離環境で `apm install --frozen --https` が書き戻しなし（SHA-256 一致）で完了すること、`apm audit --ci` が全 check を通過すること。
- Design Hook gate: 隔離 materialize した候補 Impeccable の `scripts/hook.mjs` を `IMPECCABLE_HOOK_RUNTIME` に指定して `tests/design-hook.bats` を実行し、既存の quiet / immediate tier / Stop deep pass / dedupe / edit threshold / sensitive・generated path filter / Stop re-entry の契約を維持すること（9/9）。managed hook の fail-open は `tests/codex-config.bats` の該当テストで別途確認する。
- リポジトリ既存の bats full suite が通過すること。
- いずれかの gate が実際に失敗した場合、この更新単位は採用済みとみなさず、旧 source pin / 旧 Impeccable pin を fallback とする。nix devshell 側だけ、または Impeccable だけを部分採用しない。

## Deliberately separate

- Remotion の main 進行（`7fc6dea3` → `baf0b919`）は `version: 4.0.514` → `4.0.515` の version marker 更新のみで、`<HtmlInCanvas>` 等のガイダンス本文に変更はない。実体差分がないため、この更新単位には含めない。
- Matt Pocock workflow migration（`writing-for-agents` 系のリネーム、`grilling` round 区切りの変更等）は [ADR-0041](0041-adopt-mattpocock-v1-2-3-workflow-semantics.md) が調停済みの別 migration のままとし、この更新では pin を動かさない。
- floating（unpinned）な APM dependency（`anthropics/skills`、`Effect-TS/skills`、`shadcn-ui/ui`、`vercel-labs/*`、`supabase/agent-skills`、`mizchi/skills`、`stablyai/orca` の `computer-use`/`orchestration`）は、隔離 `apm install` の実行に伴い自然に現在の upstream HEAD へ再解決される。これは floating dependency の通常の挙動であり、この ADR が個別に採否判断する対象ではない。selected subtree の実体差分は確認できなかった（`pdf`/`skill-creator`/`shadcn`/`orca` 3skill/`vercel-labs` 4skill/`find-skills` いずれも既存 test の資産と整合）。

## Consequences

この境界により、snapshot の worktree/teammate messaging 修正と Impeccable の hook/agent installation 修正を同じ verification / rollback 証跡で扱える。一方、Remotion の version-only 更新は別途 payload の実体差分が出た回に改めて評価する必要がある。

`tests/apm-runtime.bats` の find-skills に関する古い否定アサーション（`resolved_commit` が 2026-08-20 時点の未採用候補 `435076e7...` と一致しないことを確認する行）は削除した。floating dependency である find-skills の upstream main が実際にこの commit へ到達したことを `git ls-remote` で確認済みであり、もはや「却下済み候補」を表さないため。

関連: [調査ノート 2026-08-24](../research/llm-agents-and-apm-update-2026-08-24.md) / [調査ノート 2026-08-21](../research/llm-agents-and-apm-update-2026-08-21.md) / [ADR-0029](0029-impeccable-pin-advance-with-stop-hook.md) / [ADR-0040](0040-update-llm-agents-and-remotion-update-unit.md) / [ai-runtimes](../../runtime/ai-runtimes.md) / [skill-harness](../../runtime/skill-harness.md)
