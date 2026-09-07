---
type: concept
title: Shell environment
description: bash は flyline 中心、macOS zsh は atuin + zsh plugins 中心で構成するシェル環境と nix-devshell グローバル env キャッシュ
tags: [bash, zsh, shell, flyline, starship, atuin, ghq]
---

# Shell environment

Linux / Dev Container のログインシェルは **bash**（[ADR-0001](../docs/adr/0001-bash-over-zsh.md)）。macOS は zsh を維持する（[ADR-0020](../docs/adr/0020-macos-keeps-zsh-login-shell.md)）。

- `dot_bash_profile.tmpl` → `~/.bash_profile` — login shell。PATH / XDG_RUNTIME_DIR フォールバック / nix-daemon 読み込み / Codex Desktop 用 CODEX_HOME、末尾で `~/.bashrc` を source。
- `dot_bashrc.tmpl` → `~/.bashrc` — 対話 shell。ツール init と関数を定義。
- `dot_zshrc.tmpl` → `~/.zshrc` — macOS zsh 用の対話 shell。atuin と zsh-native plugins を初期化する。

## 所有権モデル

**履歴検索の所有者** は shell ごとに分ける。bash では flyline が `Ctrl-R` を所有し、zsh では atuin が `Ctrl-R` を所有する。

**主要機能セット** は同一実装ではなく、shell ごとの最適実装で満たす。bash は flyline、zsh は atuin + zsh-autosuggestions + zsh-syntax-highlighting を使い、starship / fzf / zoxide は両方で維持する（[ADR-0021](../docs/adr/0021-replace-blesh-with-flyline.md)）。

## bash ツール

sheldon などのプラグインマネージャは使わず、`.bashrc` で各ツールの init を直接 `eval` する（軽量化）:

- **flyline** — bash の line editor と履歴検索の所有者。Linux/glibc 版 loadable builtin を `enable -f` する。load 失敗時は1行警告を出して bash 標準入力編集へフォールバックする。mouse capture と AI agent integration は初期無効
- **bash-preexec** — precmd/preexec hook 基盤（`~/.config/bash/bash-preexec.sh` に vendored, rcaloras/bash-preexec 0.6.0）。starship 継続時の prompt hook 互換性のため維持
- **starship** — プロンプト（Dracula カラーパレット）。flyline prompt は directory / Git branch/status / time / command duration の既存表示を十分に置き換えないため、bash でも starship を維持する
- **fzf** — キーバインド + 補完。通常の `fzf --bash` を使う。Dracula カラー
- **zoxide** — スマート cd（`--cmd cd`）
- **eza** — `ls`/`ll`/`la`/`lt` エイリアス
- **direnv** — ディレクトリ単位の環境変数
- **bash-completion** — 補完。OS パッケージ優先、無ければ nix-devshell 供給の本体を `XDG_DATA_DIRS` から探索

## zsh ツール（macOS）

- **atuin** — zsh の履歴検索の所有者（`Ctrl-R`）。fzf より後に init し、zsh の後勝ち keybind で履歴検索を取る
- **zsh-autosuggestions / zsh-syntax-highlighting** — nixpkgs パッケージ由来の plugin file を直接 source する
- **starship / fzf / zoxide / direnv** — zsh native hook で初期化する

## nix-devshell グローバル env キャッシュ

`~/.config/nix-devshell` の devShell を home など direnv 管轄外でも有効化するため、`nix print-dev-env` の出力を `~/.cache/nix-devshell-global-env.bash` にキャッシュし stale-while-revalidate で更新する。実体は `~/.config/nix-devshell/lib/{ensure-env,refresh-cache}.sh`（bash 関数）。`.bashrc` は起動時に現行キャッシュを source し、背景で次回向けに再生成、`PROMPT_COMMAND` で mtime 変化時にリロード（`chezmoi apply` 連携）。出力は bash として直接 source 可能なため zcompile は不要。

通常の `chezmoi apply`、APM 配備、初回導入は `NIX_DEVSHELL_CACHE_REQUIRED=1` で更新し、必要な更新や前提の確認に失敗したら停止する。途中まで出力した Nix の非0終了、空・bash 構文不正の出力、キャッシュ置換の失敗は旧キャッシュを保持する。対話シェルの背景更新は引き続き起動を止めない。鮮度は devShell 配下のソースの内容・追加・削除と WSL／通常環境の選択で判定し、入力が同じなら再評価しない。ルートの `.git`／`.direnv` と Nix の `result`／`result-*` symlink は実行時状態として除外する。対応する入力情報をキャッシュ本体に含め、検査後に一緒に置換する。旧形式はそのまま読め、次の更新で再生成へ移行する。初回生成には初期 PATH の `sha256sum` または `shasum` と、ロック用の system `perl` を使う（[ADR-0050](../docs/adr/0050-user-environment-cache-freshness.md)）。

同じキャッシュの背景更新は競合時に待たず省略し、必須更新は先行更新を待って入力を再確認する。評価前後の照合で入力の変化を検出した場合は結果を採用せず1回だけ再試行し、再び検出すれば旧キャッシュを保持して必須更新を失敗させる。更新元の終了でロックは解放され、残った一時出力は次回の更新が回収する。`~/.cache/nix-devshell-global-env.bash.lock` は常設ファイルであり、存在自体は更新中の意味ではない。実行中のロックファイルを削除すると排他を壊すため、そのまま通常の更新を再実行する。

ソースの書込み側はこのロックに参加しない。最後の入力照合後、採用直前にソースが変わると、その更新は変更前の入力のキャッシュを採用して成功することがある。この変更は次回更新の入力照合で検出する。配備中の並行編集まで含めた採用時点の最新性は保証しないため、編集が重なった場合は入力を安定させて必須更新を再実行する。保証範囲と判断理由は [ADR-0050の鮮度保証の境界](../docs/adr/0050-user-environment-cache-freshness.md#鮮度保証の境界) に従う。

## ghq + fzf リポジトリ管理

`.bashrc` の関数で提供:

| コマンド | 動作                                                                               |
| -------- | ---------------------------------------------------------------------------------- |
| `Ctrl-G` | flyline 有効時は入力を破棄して `gcd` を実行し fzf 選択 → cd、fallback 時は直接起動 |
| `gcd`    | リポジトリを選んで cd                                                              |
| `gclone` | 引数ありで `ghq get`、なしで `gh repo list`（ユーザー + 所属 Org）→ fzf → clone    |
| `gedit`  | リポジトリを `$EDITOR` で開く                                                      |
| `gweb`   | リポジトリを `gh browse` で表示                                                    |
| `ginit`  | `owner/repo` 形式で ghq 管理下にローカルリポジトリを作成                           |

## その他

- **tmux** — `Ctrl+a` プレフィックス
- **neovim (lazy.nvim)** — LSP は flake devShell 管理のものを PATH 経由で利用
- **wezterm** — ターミナル（Dracula テーマ、WSL 対応）

関連: [architecture](../docs/architecture.md) / [ai-runtimes](ai-runtimes.md)
