---
type: decision
title: bash は flyline 中心、zsh は zsh-native plugin 中心の非対称構成にする
description: ble.sh/atuin 中心の bash 構成をやめ、bash は flyline を line editor と履歴検索の所有者にし、macOS zsh は atuin と zsh plugins を維持する
tags: [adr, bash, zsh, flyline, blesh, shell]
timestamp: 2026-07-09
---

# bash は flyline 中心、zsh は zsh-native plugin 中心の非対称構成にする

## Status

Accepted (2026-07-09)。[ADR-0018](0018-add-blesh-to-bash.md) を supersede する。

## Context

[ADR-0018](0018-add-blesh-to-bash.md) では、bash に ble.sh を導入して syntax highlight、autosuggestion、リッチな Tab 補完メニューを得る方針を採った。しかし実利用で入力遅延・描画乱れ・補完まわりの不安定さが問題になった。最初は ble.sh を syntax highlight と inline autosuggestion だけに薄型化する案も検討したが、bash 側だけで完結する modern line editor として flyline を採用し、zsh 側は zsh-native plugins を維持する非対称構成を再検討した。

flyline は readline replacement であり、`Ctrl-R` を atuin へフォールスルーさせる薄い補助レイヤーではない。そのため bash で flyline を採用する場合、履歴検索の所有者は atuin ではなく flyline に移す。一方、macOS zsh 側は [ADR-0020](0020-macos-keeps-zsh-login-shell.md) のとおり zsh を維持し、atuin と `zsh-autosuggestions` / `zsh-syntax-highlighting` で主要機能セットを満たす。

## Decision

- bash から ble.sh を削除する。`blesh` パッケージ、`blesh-share` source、`ble-import`、`ble-attach` は廃止する
- bash から atuin を削除する。bash の `Ctrl-R` 履歴検索は flyline が所有する
- bash に flyline を導入する。nixpkgs 未収録のため、Linux glibc 版 prebuilt `.so` を `fetchurl` + sha256 固定で取得する custom derivation として扱う
- flyline の load 失敗時は stderr に1行警告を出し、bash 標準 + bash-completion + fzf + zoxide + optional starship でシェル起動を継続する
- bash-completion、fzf、zoxide は bash/zsh の両方で維持する。fzf は `gcd` / `gclone` / `gedit` / `gweb` の repo picker でもあるため flyline で置き換えない
- bash-preexec は一旦維持する。atuin は削除するが、starship 継続時の prompt hook 互換性を実測するまで外さない
- bash の starship は条件付きで削除する。flyline だけで directory、Git branch/status、時刻、command duration を実用表示できる場合は bash から starship を外す。条件未達なら bash でも starship を残す
- flyline の AI agent integration は無効のままにする
- flyline の mouse capture は初期状態では無効にする
- macOS zsh は今回変更しない。`atuin + zsh-autosuggestions + zsh-syntax-highlighting + starship + fzf + zoxide` を維持する

## Consequences

- bash と zsh は同一実装ではなくなる。主要機能セットは、shell ごとの最適実装で満たす
- bash の履歴検索履歴は atuin 同期から外れる。zsh 側は引き続き atuin が履歴検索の所有者になる
- flyline は bash と同一プロセスに load されるネイティブ `.so` であり、ble.sh より ABI 依存が強い。失敗時にログインシェルを壊さないため warning-only fallback を必須にする
- flyline prompt が starship を置き換えられるかは実装時の実測で決める。置き換え条件を満たせない場合、prompt は従来どおり starship が所有する

関連: [issue #52](https://github.com/treflebonbon/dotfiles/issues/52) / [ADR-0001](0001-bash-over-zsh.md) / [ADR-0018](0018-add-blesh-to-bash.md) / [ADR-0020](0020-macos-keeps-zsh-login-shell.md)
