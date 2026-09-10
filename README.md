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

環境キャッシュの更新では、初回を含めて毎回、排他に PATH 上の `perl`（native `flock` 対応）、鮮度判定に `sha256sum` または `shasum` を使います。生成済みのキャッシュがあってもこれらは必要です。`install.sh` は導入を始める前に、`git`・`curl`・`perl` の存在、Perl の native `flock` 対応、SHA-256 コマンドの存在を確認します。

### コンテナイメージの前提条件

DevPod と VS Code Dev Containers では、dotfiles の自動インストールが始まる前に、コンテナイメージ内へ依存を用意してください。Debian／Ubuntu ベースなら、既存の Dockerfile の root で実行する箇所（`USER` で一般ユーザーへ切り替える前）に追加します。`git` と `curl` は従来どおりイメージ側で提供します。

```dockerfile
RUN apt-get update && apt-get install -y --no-install-recommends perl coreutils
```

`coreutils` が `sha256sum` を提供します。ほかのディストリビューションでは、そのパッケージマネージャーで native `flock` 対応の Perl と SHA-256 コマンドを用意してください。イメージを再ビルドしてから、以下の自動インストール設定を利用します。

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
sudo apt update && sudo apt install -y git curl perl

# dotfiles をインストール
git clone https://github.com/treflebonbon/dotfiles /tmp/dotfiles
bash /tmp/dotfiles/install.sh

# シェルを再起動
exec bash -l
```

### 手動インストール

上記の依存は初回生成から以後のキャッシュ更新まで必要です。Linux／WSL は OS のパッケージとして用意し、macOS も配備前にこれらを利用できることを確認してください。

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

Codex 管理設定は `private_dot_config/codex/`（config.toml.tmpl / rules / AGENTS.md / hooks.json / environments）を編集し、`run_onchange_after_codex-managed-sync.sh.tmpl` が `~/.config/codex/` 経由で5種類をまとめて同期します。config.toml は既存設定へマージし、他4種類は管理ファイルで置換します。runtime/cache/auth/session/state と project trust は管理対象外です。配備先の追加・修復時は `sync-codex-managed-config` を引数なしで実行します（[同期と復旧の詳細](runtime/ai-runtimes.md#codex-管理設定の同期)）。

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

開発ツール・通常変数・非秘密の初期化はプロジェクトの `flake.nix` と `flake.lock` に集約します。bash／zsh の標準起動は direnv 自動 hook を登録しません。共通ツールは既存のユーザー環境キャッシュから利用できます。

```bash
nix develop .#default           # プロジェクト開発シェルへ入る
exit                            # 起動元の bash／zsh へ戻る
devshell-env trust               # repo と所属 worktree の AI 自動読込みを信頼登録
devshell-env status              # root・output・登録状態を確認
devshell-env untrust             # 次回の自動読込みから解除
```

dotfiles の WSL2 開発では `nix develop .#wsl` を使います。Claude は後続 Bash に非秘密環境を反映し、flake 編集後は `devshell-env reload`。raw Codex は linked worktree の `codex-worktree` から準備し、編集後は再起動します。Codex Desktop／Orca native Codex に自動環境読込みは追加しません。

Linux／WSL2 の raw Codex は、確認した公開ファイルと到達可能な Git 履歴を `devshell-env admit` で登録し、`codex-worktree` から秘密なしで起動します。準備済み環境では `with-env --prepared -- command` を使い、通常変数や無害な fixture で検証します。ホストの dotenv と任意の継承変数は渡しません。既存セッション・直接 Codex・Desktop・Orca／Herdr native 起動には、この隔離を遡及適用しません。

実値が必要な検証は、人間が確認した固定版のコードを Codex からアクセスできない別環境へ渡し、そこで `nix run .#with-env -- command` を実行します。人間向けの root `.env` 注入、起動元 → devShell → `.env` の優先順は維持します。コード・秘密・出力を分離し、人間が確認した必要な結果だけを共有します。[移行と人間の検証手順](runtime/human-validation.md)を参照してください。Claude の dotenv 注入は対象外です。正式入口の準備失敗を直接実行で迂回しません。

direnv 本体と既存 `.envrc` は残り、内容を確認したうえで `direnv allow .` / `direnv exec . command` を明示利用できます。[移行・更新・復旧の手順](runtime/shell-environment.md#既存-repo-の移行)と各言語テンプレートの `DEVELOPMENT.md` に、dev／test app への組込み例をまとめています。未 merge の source は実配備せず、受入後に live source で `chezmoi apply` して新しい端末を開きます。

シェル固有の表示や対話設定は以下のいずれかに記述:

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
- **Scripts**（`run_*`）: `run_after_setup-gh.sh`, `run_onchange_after_codex-managed-sync.sh.tmpl`, `run_onchange_after_apm-install.sh.tmpl` など
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
