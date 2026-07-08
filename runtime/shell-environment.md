---
type: concept
title: Shell environment
description: bash ベースのシェル環境 (starship / atuin / fzf / zoxide / ghq / direnv / eza) と nix-devshell グローバル env キャッシュ
tags: [bash, shell, starship, atuin, ghq]
---

# Shell environment

ログインシェルは **bash**（zsh は使わない → [ADR-0001](../docs/adr/0001-bash-over-zsh.md)）。

- `dot_bash_profile.tmpl` → `~/.bash_profile` — login shell。PATH / XDG_RUNTIME_DIR フォールバック / nix-daemon 読み込み / Codex Desktop 用 CODEX_HOME、末尾で `~/.bashrc` を source。
- `dot_bashrc.tmpl` → `~/.bashrc` — 対話 shell。ツール init と関数を定義。

## ツール

sheldon などのプラグインマネージャは使わず、`.bashrc` で各ツールの init を直接 `eval` する（軽量化）:

- **ble.sh**（`blesh` パッケージ） — 構文ハイライト・autosuggestion・リッチな Tab 補完メニュー。`--attach=none` で source しファイル末尾で `ble-attach`（[ADR-0018](../docs/adr/0018-add-blesh-to-bash.md)）。atuin/starship はロード順序に対して自己統合するため追加コード不要
- **bash-preexec** — precmd/preexec hook 基盤（`~/.config/bash/bash-preexec.sh` に vendored, rcaloras/bash-preexec 0.6.0）。atuin の履歴記録と starship のプロンプト描画は `precmd_functions`/`preexec_functions` 経由で動くため必須
- **starship** — プロンプト（Dracula カラーパレット）。ble.sh ロード時は `${BLE_VERSION-}` を検出し右プロンプト（RPS1）も有効化
- **atuin** — シェル履歴管理（`Ctrl-R`）。ble.sh の autosuggestion も atuin の履歴に基づく
- **fzf** — キーバインド + 補完。ble.sh ロード時は `ble-import -d integration/fzf-completion` / `fzf-key-bindings`、未ロード時は `fzf --bash` にフォールバック。Dracula カラー
- **zoxide** — スマート cd（`--cmd cd`）
- **eza** — `ls`/`ll`/`la`/`lt` エイリアス
- **direnv** — ディレクトリ単位の環境変数
- **bash-completion** — 補完。OS パッケージ優先、無ければ nix-devshell 供給の本体を `XDG_DATA_DIRS` から探索

**init 順序が重要**: ble.sh → bash-preexec → fzf(ble-import) → atuin → starship → ble-attach。Ctrl-R は後勝ちのため fzf の後に atuin を init して履歴検索を atuin に取らせる。

## nix-devshell グローバル env キャッシュ

`~/.config/nix-devshell` の devShell を home など direnv 管轄外でも有効化するため、`nix print-dev-env` の出力を `~/.cache/nix-devshell-global-env.bash` にキャッシュし stale-while-revalidate で更新する。実体は `~/.config/nix-devshell/lib/{ensure-env,refresh-cache}.sh`（bash 関数）。`.bashrc` は起動時に現行キャッシュを source し、背景で次回向けに再生成、`PROMPT_COMMAND` で mtime 変化時にリロード（`chezmoi apply` 連携）。出力は bash として直接 source 可能なため zcompile は不要。

## ghq + fzf リポジトリ管理

`.bashrc` の関数で提供:

| コマンド | 動作                                                                            |
| -------- | ------------------------------------------------------------------------------- |
| `Ctrl-G` | fzf でリポジトリ選択 → cd（`bind -x` で `gcd` を起動）                          |
| `gcd`    | リポジトリを選んで cd                                                           |
| `gclone` | 引数ありで `ghq get`、なしで `gh repo list`（ユーザー + 所属 Org）→ fzf → clone |
| `gedit`  | リポジトリを `$EDITOR` で開く                                                   |
| `gweb`   | リポジトリを `gh browse` で表示                                                 |
| `ginit`  | `owner/repo` 形式で ghq 管理下にローカルリポジトリを作成                        |

## その他

- **tmux** — `Ctrl+a` プレフィックス
- **neovim (lazy.nvim)** — LSP は flake devShell 管理のものを PATH 経由で利用
- **wezterm** — ターミナル（Dracula テーマ、WSL 対応）

関連: [architecture](../docs/architecture.md) / [ai-runtimes](ai-runtimes.md)
