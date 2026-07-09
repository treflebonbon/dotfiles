# treflebonbon/dotfiles

[chezmoi](https://www.chezmoi.io/) で管理された個人開発環境の dotfiles リポジトリ。
DevPod および VS Code Dev Containers で自動的にインストールされます。

**テーマ: [Dracula](https://draculatheme.com/)** - 全ツールで統一されたダークテーマ
**シェル: bash**

## 管理ツール

| ツール          | 説明                                  | テーマ                 |
| --------------- | ------------------------------------- | ---------------------- |
| **bash**        | シェル設定（履歴、補完、ツール init） | -                      |
| **git**         | バージョン管理設定                    | -                      |
| **gh**          | GitHub CLI 拡張・エイリアス           | -                      |
| **tmux**        | ターミナルマルチプレクサ              | Dracula カスタム       |
| **starship**    | クロスシェルプロンプト                | Dracula カラーパレット |
| **atuin**       | zsh 側のシェル履歴管理（`Ctrl-R`）    | -                      |
| **neovim**      | エディタ（lazy.nvim）                 | dracula.nvim           |
| **wezterm**     | GPU ターミナル                        | Dracula (Official)     |
| **Claude Code** | AI コーディングアシスタント設定       | -                      |

## ツール管理（Nix flake devShell）

ユーザー環境（`~/.config/nix-devshell/`）が WSL2 や devcontainer 外でも横断的に使えるツールを供給します。プロジェクト言語の toolchain は per-repo `flake.nix` が供給します。

| カテゴリ         | ツール                                                                                |
| ---------------- | ------------------------------------------------------------------------------------- |
| 汎用ランタイム   | node, python3, bun                                                                    |
| シェル環境       | flyline, starship, zoxide, atuin, eza, bat, fzf, direnv, bash-completion, zsh plugins |
| 検索             | ripgrep, fd, jq                                                                       |
| Linter/Formatter | shellcheck, shfmt, oxfmt, oxlint                                                      |
| エディタ         | neovim, tmux                                                                          |
| Git              | gh, lazygit, delta                                                                    |
| AI               | claude-code, codex, copilot-cli, antigravity, rtk, playwright-cli, apm                |

## セットアップ

### DevPod

```bash
devpod context set-options -o DOTFILES_URL=https://github.com/treflebonbon/dotfiles
```

### VS Code Dev Containers

User Settings (JSON) に追加:

```json
{
  "dotfiles.repository": "treflebonbon/dotfiles",
  "dotfiles.installCommand": "bash install.sh"
}
```

### WSL2

```bash
# 前提条件をインストール
sudo apt update && sudo apt install -y git curl

# dotfiles をインストール
git clone https://github.com/treflebonbon/dotfiles /tmp/dotfiles
bash /tmp/dotfiles/install.sh

# シェルを再起動
exec bash -l
```

### 手動インストール

```bash
# chezmoi がインストール済みの場合
chezmoi init --apply https://github.com/treflebonbon/dotfiles

# または install.sh を使用
git clone https://github.com/treflebonbon/dotfiles /tmp/dotfiles
bash /tmp/dotfiles/install.sh
```

## ツール別設定

### bash

sheldon などのプラグインマネージャは使わず、`.bashrc` で各ツールの init を直接読み込みます（軽量化）。

- **入力補助 / 履歴検索の所有者**: flyline。Linux/glibc 版 loadable builtin を `enable -f` し、bash の line editor と `Ctrl-R` 履歴検索を所有させる（[ADR-0021](docs/adr/0021-replace-blesh-with-flyline.md)）
- **hook 基盤**: bash-preexec（vendored）。starship 継続時の prompt hook 互換性のため維持
- **プロンプト**: starship を継続。flyline prompt は Git status など既存 starship 表示を置き換える条件を満たさないため使わない
- **ツール連携**: flyline, bash-preexec, fzf, zoxide, starship, eza, direnv
- **履歴**: bash は flyline、macOS zsh は atuin。履歴検索の所有者は shell 実装ごとに分ける
- **ghq + fzf**: `Ctrl-G` / `gcd` / `gclone` / `gedit` / `gweb` / `ginit`
- **Dracula**: fzf カラー
- **nix-devshell グローバル env**: `~/.config/nix-devshell` の devShell を home でも stale-while-revalidate キャッシュで有効化

### zsh（macOS）

macOS では [ADR-0020](docs/adr/0020-macos-keeps-zsh-login-shell.md) に従い zsh を維持します。主要機能セットは bash と同一実装に揃えず、zsh-native plugins で満たします。

- **履歴検索の所有者**: atuin（`Ctrl-R`）
- **入力補助**: zsh-autosuggestions / zsh-syntax-highlighting
- **プロンプト / fuzzy finder / smart cd**: starship, fzf, zoxide

### git

- **エディタ**: vim
- **改行**: `autocrlf=input`（CRLF → LF 変換）
- **マージ**: `merge.ff=false`、**プル**: `pull.ff=only` + `pull.autostash=true`
- **プッシュ**: `push.default=current`、**デフォルトブランチ**: `main`
- **認証**: HTTPS + `gh auth git-credential`（SSH は使用しない）

**ユーザー設定**: `GIT_AUTHOR_NAME`/`GIT_AUTHOR_EMAIL` 環境変数があればそれを使用し、なければ `chezmoi init` 時に対話的にプロンプトされます。

```bash
export GIT_AUTHOR_EMAIL="your@email.com"
export GIT_AUTHOR_NAME="Your Name"
```

### gh (GitHub CLI)

初回適用時に拡張機能（[gh-poi](https://github.com/seachicken/gh-poi)）とエイリアスを設定:

| エイリアス        | 説明                               | 使用例        |
| ----------------- | ---------------------------------- | ------------- |
| `gh feat <issue>` | Issue からフィーチャーブランチ作成 | `gh feat 123` |
| `gh fix <issue>`  | Issue から hotfix ブランチ作成     | `gh fix 456`  |
| `gh push-f`       | `--force-with-lease` でプッシュ    | `gh push-f`   |
| `gh merge-pr`     | マージ可能な PR を一括マージ       | `gh merge-pr` |

### tmux / starship / neovim / wezterm

- **tmux**: プレフィックス `Ctrl+a`、ペイン分割 `|`（水平）/ `-`（垂直）、Vim スタイル移動
- **starship**: OS → ユーザー → ディレクトリ → Git → 言語バージョン
- **neovim**: lazy.nvim。LSP は flake devShell で一元管理（gopls, ts_ls, lua_ls, rust_analyzer, ruff）。mason.nvim は DAP 等の補助用
- **wezterm**: JetBrains Mono + Nerd Font、透過 95%

### Claude Code

`~/.claude/settings.json` を dotfiles で完全管理し、個人差分は `~/.claude/settings.local.json` に置きます（`language: japanese`、`effortLevel: xhigh`、`teammateMode: auto`、`statusLine` に bash カスタムスクリプト）。

- **セキュリティ**: 機密ファイル読み取り禁止、破壊的コマンド禁止、クラウド操作禁止（deny ルール群）
- **設計→実装ワークフロー**: mattpocock skills（`setup-matt-pocock-skills` → `grill-with-docs` → `to-spec` → `to-tickets` → `implement` → `to-pr`、raw issue は `triage` on-ramp）。apm 経由で `~/.claude/skills/` へ展開
- **enabledPlugins**: security-guidance, LSP 群, codex, claude-code-setup
- **ブラウザ**: `playwright-cli`

各 product repo で `setup-matt-pocock-skills` を最初に実行し、issue tracker（GitHub / GitLab / local markdown 等）と triage label 語彙を構成します。triage label（`needs-triage` 等）は各 repo で `gh label create` するか skill のランタイム挙動に任せます。

### Codex

Codex 固有の設定は `private_dot_config/codex/`（config.toml / rules / AGENTS.md / hooks.json / environments）を編集し、`run_onchange_after_codex-*.sh.tmpl` が `~/.config/codex/` 経由で `~/.codex/`（`$CODEX_HOME`）へマージ配置します。宣言的設定のみ管理し、runtime/cache/auth/session/state と project trust は管理対象外です。

Windows Codex Desktop の WSL mode では `CODEX_INTERNAL_ORIGINATOR_OVERRIDE=Codex Desktop` を検出した login shell が `CODEX_HOME=$HOME/.codex-app` を設定し、保存先を WSL native filesystem に置きます。

## 環境変数

| 変数                        | デフォルト   | 説明                                                 |
| --------------------------- | ------------ | ---------------------------------------------------- |
| `DOTFILES_WORKSPACE_FOLDER` | `/workspace` | ワークスペースのルートパス                           |
| `WORKSPACE_FOLDER`          | `/workspace` | `DOTFILES_WORKSPACE_FOLDER` 未設定時のフォールバック |
| `GIT_AUTHOR_EMAIL`          | (未設定)     | Git ユーザーメールアドレス                           |
| `GIT_AUTHOR_NAME`           | (未設定)     | Git ユーザー名                                       |
| `DOTFILES_SKIP_DIRENV`      | (未設定)     | `1` で direnv インストールをスキップ                 |

## プロジェクト固有設定

プロジェクトごとの追加シェル設定は以下のいずれかに記述:

1. `${WORKSPACE_FOLDER}/.devcontainer/dotfiles/bash/.bashrc.local`
2. `${WORKSPACE_FOLDER}/.bashrc.local`

## chezmoi 操作

```bash
chezmoi diff              # 差分確認
chezmoi apply             # 変更適用
chezmoi edit ~/.bashrc    # ソース編集
chezmoi data              # テンプレート変数確認
chezmoi update            # リモートから更新
```

## ディレクトリ構造

- **Bootstrap**: `install.sh`（エントリーポイント）、`.chezmoi.toml.tmpl`
- **Dotfiles**（`dot_*` → `~/.*`）: `dot_bashrc.tmpl`, `dot_bash_profile.tmpl`, `dot_gitconfig.tmpl`, `dot_tmux.conf`
- **Scripts**（`run_*`）: `run_after_setup-gh.sh`, `run_onchange_after_codex-*.sh.tmpl`, `run_onchange_after_apm-install.sh.tmpl` など
- **Docs / Knowledge**: `CLAUDE.md` / `AGENTS.md`、`runtime/`（Open Knowledge Format で書かれた home-wide 知識バンドル）、`docs/`（repo ローカルな architecture/conventions/ADR）
- `private_dot_claude/` → `~/.claude/`: `settings.json.tmpl`
- `private_dot_config/` → `~/.config/`: `starship.toml`, `nvim/`, `wezterm/`, `codex/`, `nix-devshell/`（`flake.nix` / `modules/` / `packages/` / `lib/`）
- **APM**: `apm.yml` / `apm.lock.yaml`（外部 skill / plugin）
- **Templates**: `templates/<lang>/`（per-repo flake 雛形、home には非配備）

## 知識バンドル（runtime/）

home 配下のどの repo でも共通するシェル環境・skill 配備・AI ランタイムの知識は [Open Knowledge Format](https://cloud.google.com/blog/products/data-analytics/how-the-open-knowledge-format-can-improve-data-sharing) で書かれたバンドルとして `runtime/` に置き、chezmoi が `~/runtime/` へ配備します。agent は `runtime/index.md` を入口に markdown リンクで辿れます（OKF はここで使う markdown+frontmatter の _形式_ であり、ディレクトリ名には使いません）。

dotfiles repo 自身の構造・規約（`docs/architecture.md` / `docs/conventions.md`）と意思決定記録（`docs/adr/`）は repo ローカルで、home へは配備されません。他 repo で作業中の agent には価値が無いためです。

## Dracula カラーパレット

| 色           | Hex       | 用途       |
| ------------ | --------- | ---------- |
| Background   | `#282A36` | 背景       |
| Current Line | `#44475A` | 選択行     |
| Foreground   | `#F8F8F2` | テキスト   |
| Comment      | `#6272A4` | コメント   |
| Cyan         | `#8BE9FD` | 型、定数   |
| Green        | `#50FA7B` | 文字列     |
| Orange       | `#FFB86C` | 警告       |
| Pink         | `#FF79C6` | キーワード |
| Purple       | `#BD93F9` | 数値、関数 |
| Red          | `#FF5555` | エラー     |
| Yellow       | `#F1FA8C` | クラス名   |

## ライセンス

MIT
