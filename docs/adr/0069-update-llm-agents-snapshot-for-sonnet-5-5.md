---
type: decision
title: llm-agents snapshot を更新し Sonnet 5.5 を利用可能にする
description: Anthropic の Claude Sonnet 5.5 (`claude-sonnet-5-5`) リリースと Claude Code 2.1.284 のデフォルト Sonnet モデル追加を根拠に quality floor を引き上げ、同じ pin に含まれる Codex の trust boundary 修正も併記する
tags: [adr, nix, llm-agents, claude-code, codex, sonnet, effort-level]
timestamp: 2026-09-29
status: accepted
---

# llm-agents snapshot を更新し Sonnet 5.5 を利用可能にする

ユーザーが `/ask-matt claude sonnet 5.5 に対応したバージョンに更新` に続けて `/implement` を実行した。2026-09-28 に Anthropic が Claude Sonnet 5.5 (`claude-sonnet-5-5`) をリリースし（Opus 5.5 に次ぐ Claude 5.5 ファミリー第2弾、Sonnet 5 と同一課金・1M context）、Claude Code 2.1.284 がこれをデフォルト Sonnet モデルとして追加したことを、公式 CHANGELOG（`anthropics/claude-code` の `CHANGELOG.md` を直接 curl して逐語確認、要約ではなく原文）で確認した。issue #112（Opus 5 対応）・[ADR-0064](0064-update-llm-agents-snapshot-for-opus-5-5.md)（Opus 5.5 対応）と同じ「モデル品質・metadata の正確性」を根拠区分として、[ADR-0045](0045-separate-llm-agents-and-apm-update-units.md) の更新単位方針に従いツール snapshot だけを一つの更新単位として採用する。通常 APM payload・Impeccable・Matt Pocock managed set は upstream の進捗を確認しておらず、この更新単位に含めない。

## Decision

- `llm-agents.nix` は `private_dot_config/nix-devshell/flake.nix` の immutable revision を `e28ea84e78517e5d05ae0c399da00e848e207261`（2026-09-28、PR #362）から upstream default branch HEAD `ee7041016e9b6de43f7ba4cce04272518f7cfaa9`（2026-09-28、62 commit 先行）へ更新する。共有 nixpkgs（`nixpkgs-26.05-darwin`）と x86_64-linux / aarch64-linux / aarch64-darwin の3-system境界は維持する。3 system の package metadata は claude-code 2.1.284、codex 0.158.0、copilot-cli 1.0.89、antigravity-cli(`agy`) 1.2.12 で一致し、rtk 0.50.0、apm 0.32.0、herdr 0.9.1、code-review-graph 2.3.9 は変化しない。
- Claude Code の quality floor を `2.1.283` から `2.1.284` へ引き上げる。根拠は 2.1.284 の公式 CHANGELOG から確認した "Added Claude Sonnet 5.5 (`claude-sonnet-5-5`), now the default Sonnet model on the Anthropic API"（今回の直接動機）。pin 自体も 2.1.284 が最新のため、床と pin を同じ 2.1.284 に揃える。
- Codex の quality floor を `0.157.0` から `0.158.0` へ引き上げる。根拠は 0.158.0 の公式 GitHub Release Notes（`rust-v0.158.0`）から確認した次の内容: "Terminal input approval is enabled by default for commands running with elevated permissions; runtime-only grants no longer cause unnecessary reviews."（昇格権限コマンドの承認フローのデフォルト強化）、"Secure direct exec-server WebSocket connections with bearer tokens, including connections configured through app-server."（exec-server の WebSocket 接続認証強化）。いずれも [ADR-0047](0047-test-quality-floors-through-package-outputs.md) の Codex floor 判断基準（sandbox・trust boundary の信頼性）に合致する。
- Copilot CLI は 1.0.88→1.0.89 で非公開 changelog のため package metadata の追従のみ確認し、quality floor の対象外とする。Antigravity CLI・RTK・APM・Herdr・code-review-graph は snapshot 内でも変化がない。
- Sonnet 5.5 の到達経路は `private_dot_claude/settings.json.tmpl` の `"model": "sonnet"` という generic alias を通す。model 名を直接指定する設定ではないため、今回の snapshot 更新だけで実行モデルが Sonnet 5.5 を使うようになる。`advisorModel: "opus"`（advisor tool）は対象外のまま変更しない。
- APM 経由で配布する skill 依存（`apm.yml` / `apm.lock.yaml`）は今回変更しない。upstream 側の変化を確認しておらず、ADR-0045 の更新単位方針によりツール snapshot と別更新単位のまま扱う。
- 実装の正本は Nix flake / lock、`modules/ai.nix` とし、配備先を直接編集しない。

## Verification boundary

- Nix source gate: `nix flake lock`（`flake.nix` の URL revision 書き換え後）と `nix flake check --no-build --all-systems` が3 system で成功。3 system の `nix eval` 実測が claude-code 2.1.284 / codex 0.158.0 / copilot-cli 1.0.89 / antigravity-cli 1.2.12 / rtk 0.50.0 / apm 0.32.0 / herdr 0.9.1 で一致することを確認した。x86_64-linux (host) では `nix develop` で実ビルドし、claude / codex / copilot / agy / rtk / apm / herdr / code-review-graph の8 CLI 実測 version が snapshot と一致することを確認した。
- `tests/ai-quality-floor.bats`（floor 値・診断メッセージの期待値）、`tests/nix-devshell.bats`（snapshot revision の固定値、AI toolset snapshot contract の参照先 research doc）を同じ更新単位で追従させ、成功を確認した。
- `runtime/ai-runtimes.md` の Advisor tool 節が自ら課す再検証義務（pin 上の claude-code version が変わった回は kill switch → env var バイパス → `tengu_sage_compass2` フラグ → advisorModel rank check の構造を再確認する）に従い、pin `2.1.283→2.1.284` を機に `.claude-wrapped` バイナリを `strings` で再検証した。4トークン（`CLAUDE_CODE_DISABLE_ADVISOR_TOOL` 4件 / `CLAUDE_CODE_ENABLE_EXPERIMENTAL_ADVISOR_TOOL` 4件 / `tengu_sage_compass2` 2件 / `advisorModel` 39件）の存在と、kill switch → env var バイパス → `tengu_sage_compass2` 判定 → advisorModel 候補配列 `["fable","opus","sonnet"]` という構造が変化していないことをコード上で確認した。model catalog に `claude-sonnet-5-5`（`advisor_rank:3`）が追加され、`aliases.sonnet.default` が `claude-sonnet-5-5` へ変わったことも直接確認した。詳細は `runtime/ai-runtimes.md` の Advisor tool 節の 2026-09-29 エントリを参照。
- full bats suite、`bunx tsc --noEmit`、二軸レビューの結果は[調査ノート](../research/llm-agents-and-apm-update-2026-09-29.md)に記録する。
- aarch64-linux / aarch64-darwin の実機実行、Copilot CLI / Antigravity CLI の version固有 changelog、Sonnet 5.5 が実際のセッションで選択されることのランタイム smoke は未確認のまま。

## Deliberately separate

- APM payload（skill 依存の refresh）、Impeccable skill pin、Matt Pocock managed set は upstream の進捗有無を今回確認しておらず、この更新単位に含めない。
- `"advisorModel": "opus"` を Sonnet 系へ切り替える判断（advisor モデル自体を変える）は、この更新の動機（実行モデルの Sonnet 5.5 対応）とは無関係のスコープ外として対象外にする。ユーザーが advisor モデルの切替を意図している場合は別途依頼が必要。

## Consequences

この境界により、Sonnet 5.5 の利用可否という単一の動機と、それに付随する Codex の trust boundary 修正（terminal input approval のデフォルト強化、exec-server WebSocket 認証強化）の quality floor 引き上げを同じ verification / rollback 証跡で扱える。APM payload は次回以降の専用更新単位に持ち越す。

関連: [調査ノート 2026-09-29](../research/llm-agents-and-apm-update-2026-09-29.md) / [ADR-0068](0068-update-llm-agents-snapshot-and-apm-payload-20260926.md) / [ADR-0064](0064-update-llm-agents-snapshot-for-opus-5-5.md) / [ADR-0045](0045-separate-llm-agents-and-apm-update-units.md) / [ADR-0047](0047-test-quality-floors-through-package-outputs.md) / [ai-runtimes](../../runtime/ai-runtimes.md)
