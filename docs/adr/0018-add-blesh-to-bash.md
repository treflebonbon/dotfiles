---
type: decision
title: ble.sh を bash に導入し既存ツールと統合する
description: 構文ハイライト・autosuggestion・リッチな Tab 補完メニューを bash に追加し、atuin/fzf/starship/zoxide/ghq+fzf と共存させる。プラグインマネージャは導入しない
tags: [adr, bash, blesh, shell]
timestamp: 2026-07-08
---

# ble.sh を bash に導入し既存ツールと統合する

## Status

Superseded by [ADR-0021](0021-replace-blesh-with-flyline.md) (2026-07-09)。ADR-0001 の「autosuggestions / syntax-highlighting は失う」という consequence を部分的に見直したが、実利用で入力遅延・描画乱れ・補完まわりの不安定さが問題になったため、bash 側は flyline 中心の構成へ移行する。

## Context

ADR-0001（zsh → bash 移行）は、autosuggestions / syntax-highlighting の喪失を「atuin の履歴補完と fzf で実用上カバーする」として受け入れた。実際に日々使う中でこの前提を見直したいという要望があり（issue #33）、bash-native な [ble.sh](https://github.com/akinomyoga/ble.sh) を導入することで、sheldon 等のプラグインマネージャを新設せずに構文ハイライト・autosuggestion・リッチな Tab 補完を得られることが分かった。

nixpkgs の `blesh` パッケージは `blesh-share` コマンドを提供し、`"$(blesh-share)/ble.sh"` として ble.sh 本体の絶対パスを nix store パスをハードコードせずに得られる。

atuin と starship はいずれも ble.sh のロードに自己統合する仕組みを持つ:

- atuin: `BLE_ONLOAD` フック経由でロード順序に依存せず自己統合し、履歴ベースの自動補完候補を出す
- starship: `${BLE_VERSION-}` を検出して右プロンプト（RPS1）を自動的に有効化する

このため、ble.sh を正しい順序で source すれば、atuin/starship 側に追加コードは不要となる。

## Decision

- `private_dot_config/nix-devshell/modules/shell.nix` の Shell tools グループに nixpkgs の `blesh` パッケージを追加する
- `dot_bashrc.tmpl` で、vendored `bash-preexec.sh` の source 直前に `"$(blesh-share)/ble.sh"` を `--attach=none` で source する。この位置は nix-devshell グローバル env 読み込み後・starship init（ファイル後半）より前であり、atuin/starship のネイティブ ble.sh 統合を有効化する
- 既存の `eval "$(fzf --bash)"` は、ble.sh ロード時（`${BLE_VERSION-}` が設定されている場合）に限り `ble-import -d integration/fzf-completion` / `ble-import -d integration/fzf-key-bindings` に置き換え、fzf のネイティブ bash 統合との二重キーバインドを避ける。`blesh-share` が無い環境では ble.sh 統合そのものが skip されるため、既存の `eval "$(fzf --bash)"` にフォールバックする。`FZF_DEFAULT_OPTS`（Dracula カラー）は維持する
- `.bashrc` ファイル末尾（project-specific config 読み込みの後）で `ble-attach` する
- vendored `bash-preexec.sh` は削除せず残す。atuin は bash-preexec 前提で書かれており自前の DEBUG trap フォールバックを持たないため、履歴記録を ble.sh 単独の起動成否に懸けない
- ble.sh の contrib integration は fzf 関連のみを取り込む。`integration/bash-completion` / `integration/zoxide` / `integration/fzf-git` は今回のスコープに含めない
- sheldon / Oh My Bash / bash-it は導入しない
- キルスイッチ（環境変数トグル等）は作らない。問題が発生した場合は該当コミットを `git revert` して対応する

## Consequences

- ADR-0001 の「autosuggestions / syntax-highlighting は失う」という consequence が解消される。atuin（履歴）・fzf（キーバインド/補完の一部）・starship（プロンプト）・zoxide（スマート cd）・ghq+fzf（Ctrl-G）は退行なく共存する
- `blesh-share` が存在しない環境（nix-devshell 未導入等）では ble.sh 統合は自動的に skip され、fzf は従来通り `eval "$(fzf --bash)"` にフォールバックする
- ble.sh 関連の自動テスト基盤は新設しない。検証は `shellcheck` と手動の対話セッション確認が中心になる

関連: [issue #33](https://github.com/treflebonbon/dotfiles/issues/33) / [issue #34](https://github.com/treflebonbon/dotfiles/issues/34) / [ADR-0001](0001-bash-over-zsh.md)（consequence を部分的に見直し）
