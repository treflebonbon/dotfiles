---
type: decision
title: llm-agents と APM skill の更新を四つの更新単位に分ける
description: snapshot、通常の skill payload、Design Hook、Matt Pocock workflow を個別の互換性ゲートと rollback 境界で更新する
tags: [adr, nix, llm-agents, apm, skills, impeccable, matt-pocock]
timestamp: 2026-08-27
status: proposed
---

# llm-agents と APM skill の更新を四つの更新単位に分ける

2026-08-27 の更新では、導入済み AI ツールセットと導入済み Agent Skill セットの全 dependency を調査対象にする。ただし、互換性ゲートと rollback 境界が異なる変更を一括採用せず、次の四つの更新単位へ分ける。

## Decision

1. **llm-agents snapshot**: 実装 phase の入口で upstream stable/default branch HEAD を一度だけ再確認し、pre-release を除外した exact revision に固定する。特定 release の収録を待ち続けない。調査時点の候補は `4a9441120caf6c6aff273af68995267a35c20fcd` で、code-review-graph 2.3.8 に合わせて local package override も同じ単位で更新する。Claude Code の品質 floor は `2.1.247`、Codex の品質 floor は `0.150.0` へ引き上げる。
2. **通常の APM payload refresh**: 全 dependency の selected subtree を比較し、実体差分のある Modern Web Guidance と Remotion を候補にする。floating dependency は隔離 lock 生成時に再解決し、revision だけが進んで payload が同じ変更は個別の採用理由にしない。selected subtree が同一の exact pin は動かさない。
3. **Impeccable**: 4.1.2 payload を独立した検証済み Skill Pin の候補とし、Codex Stop protocol、finding cache、monorepo/symlink root、fail-soft の挙動を含む Design Hook 互換性ゲートが通った場合だけ採用する。候補は Codex Stop を top-level の `decision` / `reason` で返すため、旧 `hookSpecificOutput.additionalContext` adapter を除去して fail-open pass-through にする配線変更と、Stop characterization test / runtime docs の更新を同じ単位に含める。Claude Stop の出力契約は変更しない。
4. **Matt Pocock managed set**: 同じ initiative 内の独立した workflow migration として、25 skill の full set を exact revision へ進める。membership は変更せず、明示的な skill 呼出し、frontier question separator、setup 未済時の案内方法を取り込む。既存のローカル skill 上書きは維持し、先に確定した non-Matt lock を baseline として ADR-0042 の ordered gate が全て通った場合だけ採用する。

各更新単位は、候補の一部だけを採用しない。互換性ゲートに失敗した単位は旧 snapshot、旧 pin、または旧 manifest/lock pair を維持し、他の更新単位の採否とは分離する。

## Implementation status

Issue #184 の実装入口では、upstream stable/default branch HEAD を一度だけ再確認し、調査候補と同じ `4a9441120caf6c6aff273af68995267a35c20fcd` を採用 revision として固定した。source URL と lock の `original.rev` / `locked.rev` は同じ exact revision を指し、pre-release は導入していない。ユーザー devShell が共有する nixpkgs `fca2dbd4c00c3063235e56bb91758e24fc67b7b8`、対応3 system、Copilot CLI 1.0.80、APM 0.28.0 は変更していない。

採用した package metadata は3 systemで claude-code 2.1.247、codex 0.150.0、copilot-cli 1.0.80、antigravity-cli 1.1.21、rtk 0.46.0、apm 0.28.0、code-review-graph 2.3.8 に一致する。`minClaudeCode` は2.1.247、`minCodex` は0.150.0へ上げた。CRG 2.3.8 の package sourceは parser probe を `[sys.executable, "-c", code, grammar]` へ変更したため、local overrideもこの新しい probe形を固定Python環境へ差し替えるよう更新した。

`nix flake check --no-build --all-systems`、3 systemの7 package metadata eval、x86_64-linux hostのdevShell buildと7 CLI version/startup、CRGの一時repository graph build、read-only allowlistに限定したstdio MCP `list_graph_stats_tool`、full Bats suite 389/389（runtime mount条件の1件はskip）を通過した。scoped `chezmoi apply` 後のlive devShellでも7 CLI versionは一致した。aarch64-linux / aarch64-darwinの実機実行、Claude 2.1.247 / Codex 0.150.0の根拠機能をinteractive agent sessionで再現する機能的smoke、Antigravity CLI 1.1.21のversion固有changelogは未確認である。

これにより llm-agents snapshot 更新単位は採用できる。通常の APM payload、Impeccable、Matt Pocock managed set の3更新単位は後続issueの互換性ゲート待ちであるため、本ADR全体のstatusは `proposed` を維持する。

## Verification boundary

- llm-agents は対応3 systemの evaluation、x86_64-linux host build、導入 CLI の version/startup smoke、code-review-graph の build/CLI/MCP smoke を行う。
- APM lock は runtime layout を再現した隔離 HOME で `apm install --https` により生成し、同じ環境で frozen no-rewrite と audit を確認する。
- Impeccable は `turn_id` を持つ Codex Stop の top-level `decision` / `reason`、初回 deep-pass 後の silent Stop、Claude Stop の既存出力、managed fail-open を candidate runtime で確認する。既知の交互再報告を期待する旧 characterization は、4.1.2 で不具合が修正された契約へ更新する。
- Matt Pocock managed set は `tests/mattpocock-update-gate.sh` の全工程を通す。ADR-0043 に記録した4 testの既知例外は現行 main で再現しないため、今回の例外にはしない。
- repository の full test、`chezmoi apply`、live 環境の version/discovery smoke までを完了境界とする。

## Consequences

候補ごとの失敗を他の更新へ波及させず、snapshot packaging、通常の skill payload、hook runtime、workflow semantics をそれぞれの根拠で採否できる。一方、単一の一括更新より検証回数と順序制約は増える。

関連: [ADR-0029](0029-impeccable-pin-advance-with-stop-hook.md) / [ADR-0041](0041-adopt-mattpocock-v1-2-3-workflow-semantics.md) / [ADR-0042](0042-mattpocock-managed-set-update-gate.md) / [ADR-0043](0043-update-llm-agents-and-impeccable-update-unit.md) / [skill-harness](../../runtime/skill-harness.md)
