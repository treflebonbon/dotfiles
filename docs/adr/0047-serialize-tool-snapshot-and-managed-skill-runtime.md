---
type: decision
title: Tool Snapshot と Managed Skill Runtime を直列に更新する
description: APM 0.29 を供給する immutable tool snapshot を先に採用し、managed payload refresh を更新済み main から始める
tags: [adr, nix, llm-agents, apm, skills, worktree]
timestamp: 2026-09-01
status: accepted
---

# Tool Snapshot と Managed Skill Runtime を直列に更新する

## Context

PR #202 で Worktree Entry Point は Orca native worktree と Agent Picker、非 Orca runtime の `/to-worktree` に整理された。一方、導入済み AI CLI と APM の snapshot、および通常の APM 管理 skill payload には upstream の更新がある。APM 0.29.0 を供給する tool snapshot と、その APM で生成する managed payload lock を同じ rollback 境界にすると、build/runtime failure と materialization failure を切り分けられない。

Issue #203 の実装入口で `numtide/llm-agents.nix` の default branch `main` を一度だけ再確認した。2026-09-01 01:19:47 UTC の HEAD は `ea1dc2132fb2669899dc8b3cbe6fe82ed10d23d6` であり、以後の実装と検証では moving branch ではなくこの immutable revision だけを使う。

## Decision

更新は二つの独立した単位として、stacked PR にせず直列に採用する。

1. **Tool Snapshot**: この PR では `llm-agents.nix` を `ea1dc2132fb2669899dc8b3cbe6fe82ed10d23d6` に固定し、共有 nixpkgs と3-system境界を動かさない。採用 snapshot は Claude Code 2.1.252、Codex 0.151.0、Copilot CLI 1.0.82、Antigravity CLI 1.1.22、APM 0.29.0、RTK 0.46.0 を含む。

   | Package         | 旧 version | 採用 version |
   | --------------- | ---------- | ------------ |
   | Claude Code     | 2.1.247    | 2.1.252      |
   | Codex           | 0.150.0    | 0.151.0      |
   | Copilot CLI     | 1.0.80     | 1.0.82       |
   | Antigravity CLI | 1.1.21     | 1.1.22       |
   | APM             | 0.28.0     | 0.29.0       |
   | RTK             | 0.46.0     | 0.46.0       |

   Claude Code は 2.1.251 の symlink swap / plugin path traversal / permission-before-read / deny rule / worktree・teammate 修正を含む stable pin の 2.1.252 へ、Codex は permission profile、sandbox path semantics、stale Guardian authorization を修正する 0.151.0 へ品質 floor を上げる。確認時点の immutable snapshot に Codex 0.152.0 stable は含まれないため polling せず 0.151.0 を採用する。

2. **Managed Skill Runtime**: Tool Snapshot PR が main にマージされた後、更新済み main から新しい Orca native worktree と agent session を開始する。そこで APM 0.29.0 を使い、通常の managed payload だけを一度の隔離 lock 生成で更新する。この PR では `apm.yml`、`apm.lock.yaml`、selected payload を変更しない。

Codex の `update_plan` は upstream default のままとし、repository config から強制有効化しない。OpenCode、新しい CLI/skill/plugin/runtime target は追加しない。PR #202 の Worktree Entry Point 所有関係も変更せず、既存 regression seam で維持を確認する。未マージ worktree から live HOME へ `chezmoi apply` しない。

## Verification boundary

- `nix flake check --no-build --all-systems` と3 systemの deep evaluationで snapshot、品質 floor、devShellを評価する。
- x86_64-linux hostで user devShellをbuild/startupし、Claude Code、Codex、Copilot CLI、Antigravity CLI、APM、RTKのversion/helpを確認する。
- `tests/nix-devshell.bats` と既存のfull Bats suiteで共有 nixpkgs、3-system境界、Worktree Entry Point、planning tool非依存を含む品質 floorを確認する。
- aarch64-linux / aarch64-darwin の実機実行、対話sessionでの各release-note修正の再現、live HOME applyはこのsource PRのacceptanceに含めない。

rollback は Tool Snapshot commitだけをrevertして旧 immutable revisionへ戻す。Managed Skill Runtimeの採否やrollbackとは分離する。

## Verification result

- `nix flake check --no-build --all-systems` とdeep evaluationは、x86_64-linux / aarch64-linux / aarch64-darwinのdefault / WSL devShell derivation、および全systemで同じ6 package versionを確認して成功した。
- x86_64-linuxではWSL devShellをsource buildし、隔離HOMEからClaude Code 2.1.252、Codex 0.151.0、Copilot CLI 1.0.82、Antigravity CLI 1.1.22、APM 0.29.0、RTK 0.46.0のversion/helpを確認した。
- `tests/nix-devshell.bats`は32/32、`tests/workflow-contract.bats`は14/14、full Bats suiteは404/404（agent runtime mount条件の1件はskip）、`bunx tsc --noEmit`は成功した。
- Codexのoverlay derivationはNumtide cacheのdirect packageとhashが異なり、release/LTO source buildを要した。direct packageはcacheから144.98秒で取得して同じ0.151.0を起動できたが、共有nixpkgs overlay契約の例外になるため、このPRではpackage routeを変更しない。今後短縮する場合はdirect package採用または共有binary cacheを別decisionとして扱う。
- aarch64-linux / aarch64-darwinの実機実行、release-note修正のinteractive再現、live HOME applyは未確認のままであり、このsource PRの成功として扱わない。

関連: [Issue #203](https://github.com/treflebonbon/dotfiles/issues/203) / [PR #202](https://github.com/treflebonbon/dotfiles/pull/202) / [ADR-0045](0045-separate-llm-agents-and-apm-update-units.md) / [ADR-0046](0046-separate-orca-native-worktree-entry.md) / [ai-runtimes](../../runtime/ai-runtimes.md)
