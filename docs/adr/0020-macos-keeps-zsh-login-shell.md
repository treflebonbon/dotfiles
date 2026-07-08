---
type: decision
title: macOS はログインシェルを zsh のまま維持し、chezmoi で zsh 向け設定を出し分ける
description: bash への統一（ADR-0001）は Linux/コンテナに限定し、macOS は既定の zsh を維持したまま chezmoi の OS 分岐で同等のツール統合を行う
tags: [adr, bash, zsh, macos, darwin, chezmoi]
timestamp: 2026-07-08
---

# macOS はログインシェルを zsh のまま維持し、chezmoi で zsh 向け設定を出し分ける

## Status

Accepted (2026-07-08)。ADR-0001（zsh → bash 移行）を上書きせず、適用範囲を Linux/コンテナに限定する形で補足する。

## Context

ADR-0001 の zsh → bash 移行は DevPod / VS Code Dev Containers（Linux、既定ログインシェルが元々 bash であることが多い）を前提にしていた。dotfiles を実際に macOS でも使う想定があり（issue #41 の triage で確認）、macOS の既定ログインシェルは zsh であるため、bash に統一しようとすると以下が必要になることが分かった:

- macOS のシステム bash（3.2、Apple が更新停止）は前提を満たさないため、nix 経由で新しい bash を供給する必要がある
- `chsh` によるログインシェル切替（`/etc/shells` への追記を含む）が必要になり、ADR-0001 が明示した「chsh は行わない」方針と衝突する

これらは実装可能だが、macOS のみのための特別な bash 供給・chsh 案内という複雑さに見合うほどの価値があるかを検討した結果、**macOS は zsh のままにし、chezmoi 側で zsh 用の設定を出し分ける**方が単純と判断した。

nixpkgs は `zsh-autosuggestions` / `zsh-syntax-highlighting` を、ADR-0001 が廃止した sheldon のようなプラグインマネージャ無しで直接 `source` 可能な形でパッケージ提供している（ble.sh を `blesh-share` 経由で直接 source するのと同型）。starship / atuin / fzf / zoxide / direnv はいずれも zsh ネイティブフックを持つため、ble.sh 相当の構文ハイライト/autosuggestion 以外はほぼそのまま移植できる。

## Decision

- `install.sh` は `uname` で OS を判定し、nix-installer のプランナーのみ macOS 向けに分岐する（`install macos --no-confirm ...`、Linux 側は現状の `install linux --init none ...` を維持）。ログインシェルの切替（chsh）は行わない
- macOS 向けに新規 `dot_zshrc.tmpl` を chezmoi の `.chezmoi.os == "darwin"` 分岐で出し分ける。starship/atuin/fzf/zoxide/direnv の zsh 向け init と、`pkgs.zsh-autosuggestions` / `pkgs.zsh-syntax-highlighting` の直接 source で構成する
- sheldon 等のプラグインマネージャは再導入しない（ADR-0001 の決定を維持）
- `dot_bashrc.tmpl` / ble.sh 統合（ADR-0018）は Linux/コンテナ専用のまま変更しない

## Consequences

- macOS では ble.sh（bash 専用）は使えないが、zsh-autosuggestions / zsh-syntax-highlighting により同等の機能をほぼ得られる
- bash と zsh の2種類の設定を chezmoi で保守することになる。ツール追加時は原則両方に反映する必要がある
- macOS 向けの nix 経由 bash 供給・chsh 案内は不要になり、install.sh の変更は nix-installer プランナー分岐のみに縮小した

関連: [ADR-0001](0001-bash-over-zsh.md)（適用範囲を Linux/コンテナに限定する形で補足）/ [ADR-0018](0018-add-blesh-to-bash.md)（bash 側の ble.sh 統合、変更なし）/ [issue #41](https://github.com/treflebonbon/dotfiles/issues/41)
