#!/usr/bin/env bash
# treflebonbon/dotfiles install script
#
# Nix flake ベースの開発環境をセットアップする
# - chezmoi: dotfiles 管理
# - Nix: パッケージ基盤、flake devShell で開発ツールを提供
# - direnv: プロジェクト単位の環境切り替え（オプション）
#
# 環境変数:
#   DOTFILES_WORKSPACE_FOLDER - ワークスペースルート (デフォルト: /workspace)
#   DOTFILES_SKIP_DIRENV=1    - direnv インストールをスキップ

set -euo pipefail

# systemd 不在のコンテナで nix-installer SelfTest WARN により
# /etc/nix/nix.conf への flakes 設定が反映されないケースを救済する保険。
# 以下の nix-installer --extra-conf とあわせて二重防御。
export NIX_CONFIG="extra-experimental-features = nix-command flakes"

DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "Installing treflebonbon/dotfiles with chezmoi..."

# 前提条件チェック
for cmd in git curl; do
  if ! command -v "$cmd" &>/dev/null; then
    echo "Error: $cmd is required but not installed."
    echo "Please install it using your system's package manager."
    exit 1
  fi
done

# ~/.local/bin を PATH に追加（chezmoi のインストール先）
export PATH="$HOME/.local/bin:$PATH"

# gh (GitHub CLI) チェック — soft prerequisite
# PATH 拡張後に実行（~/.local/bin の gh を検出するため）
if ! command -v gh &>/dev/null; then
  echo "Warning: gh (GitHub CLI) is not installed."
  echo "  Git credential helper and GitHub integrations will not be configured."
  echo "  To install: https://cli.github.com/"
  echo "  DevPod/Dev Containers: Add 'ghcr.io/devcontainers/features/github-cli' feature."
fi

# chezmoi をインストール
# 段階 1: PATH に既存があればそのまま使う
# 段階 2: nix store に既存があれば PATH に prepend して再利用 (devpod dotfiles 経路で flake と二重化するのを防ぐ)
# 段階 3: どちらにも無ければ official installer で sideload
# NIX_STORE_PREFIX はテスト用フック (default /nix/store)
if ! command -v chezmoi &>/dev/null; then
  # bash の glob expansion で nix store を検索 (ls / head 等の外部コマンドに依存しない)
  shopt -s nullglob
  store_candidates=("${NIX_STORE_PREFIX:-/nix/store}"/*-chezmoi-*/bin/chezmoi)
  shopt -u nullglob
  if [ "${#store_candidates[@]}" -gt 0 ] && [ -x "${store_candidates[0]}" ]; then
    store_chezmoi_dir="$(dirname "${store_candidates[0]}")"
    export PATH="$store_chezmoi_dir:$PATH"
    hash -r # コマンドキャッシュを更新
  fi
fi

if ! command -v chezmoi &>/dev/null; then
  echo "chezmoi not found, installing via official installer..."
  curl -fsLS get.chezmoi.io | sh -s -- -b ~/.local/bin
  hash -r # コマンドキャッシュを更新
  if ! command -v chezmoi &>/dev/null; then
    echo "Error: chezmoi installation failed. Please install manually: https://chezmoi.io"
    exit 1
  fi
fi

# Nix をインストール (NixOS Experimental Installer)
if ! command -v nix &>/dev/null; then
  echo "Nix not found, installing via NixOS Installer..."
  # 上記 NIX_CONFIG と二重防御。/etc/nix/nix.conf へ persistent に書き込んで
  # install.sh 終了後の手動 nix CLI 利用も flakes が効くようにする。
  # linux プランナー + --init none: systemd が名目上存在する（systemctl はあるが
  # 機能しない）コンテナ環境で nix-installer が systemd-tmpfiles 呼び出しに失敗するのを
  # 防ぐ。init 統合は行わず、後続の手動 nix-daemon 起動ロジックに一本化する。
  # --init はトップレベル install 直下ではなく linux プランナーのサブコマンドオプション。
  curl -sSfL https://artifacts.nixos.org/nix-installer | sh -s -- install linux \
    --no-confirm \
    --init none \
    --extra-conf "extra-experimental-features = nix-command flakes" \
    --extra-conf "extra-substituters = https://cache.numtide.com https://nix-community.cachix.org" \
    --extra-conf "extra-trusted-substituters = https://cache.numtide.com https://nix-community.cachix.org" \
    --extra-conf "extra-trusted-public-keys = niks3.numtide.com-1:DTx8wZduET09hRmMtKdQDxNNthLQETkc/yaX7M4qK0g= nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
  # Nix 環境を読み込み
  if [ -e '/nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh' ]; then
    # shellcheck source=/dev/null
    . '/nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh'
  fi
  hash -r
  if ! command -v nix &>/dev/null; then
    echo "Error: Nix installation failed. Please install manually: https://github.com/NixOS/experimental-nix-installer"
    exit 1
  fi
fi

# systemd がない環境向けに nix-daemon を起動
# Nix はマルチユーザー操作に daemon が必要。systemd がない環境（Docker, Cloud Workstations 等）
# では手動起動が必要
if ! pgrep -x nix-daemon >/dev/null 2>&1; then
  echo "nix-daemon not running, starting..."
  if [ -x /nix/var/nix/profiles/default/bin/nix-daemon ]; then
    # sudo -n: 非インタラクティブモード（パスワード要求時は即座に失敗）
    if sudo -n true 2>/dev/null; then
      sudo /nix/var/nix/profiles/default/bin/nix-daemon &
      disown
    else
      echo "Warning: sudo requires password. Run manually: sudo nix-daemon &"
    fi
  else
    echo "Warning: nix-daemon binary not found. Skipping daemon start."
  fi
fi

# ソケット準備完了を待つ（最大 30 秒）
if [ ! -S /nix/var/nix/daemon-socket/socket ]; then
  echo "Waiting for nix-daemon socket..."
  for _ in $(seq 1 30); do
    [ -S /nix/var/nix/daemon-socket/socket ] && break
    sleep 1
  done
  if [ ! -S /nix/var/nix/daemon-socket/socket ]; then
    echo "Warning: nix-daemon socket not ready after timeout."
  fi
fi

# direnv をインストール（オプション）
# プロジェクト単位の .envrc 自動読み込みに使用
# スキップ: DOTFILES_SKIP_DIRENV=1
if [[ "${DOTFILES_SKIP_DIRENV:-}" != "1" ]]; then
  if ! command -v direnv &>/dev/null; then
    echo "direnv not found, installing via nix profile..."
    nix profile add nixpkgs#direnv
    hash -r
  fi

  # nix-direnv: direnv の flake 評価結果をキャッシュして 2 回目以降のロードを高速化
  if command -v direnv &>/dev/null && ! nix profile list 2>/dev/null | grep -q nix-direnv; then
    echo "Installing nix-direnv for direnv flake caching..."
    nix profile add nixpkgs#nix-direnv
  fi
fi

# python3 をブートストラップ用にインストール
# run_onchange スクリプト（codex-config 等）は最初の chezmoi init --apply 実行時点
# （nix-devshell の devShell 評価より前）で python3 を必要とするため、先に用意する。
# 通常時の python3 は nix-devshell（ユーザー環境）が汎用ランタイムとして供給する。
if ! command -v python3 &>/dev/null; then
  echo "python3 not found, installing via nix profile (bootstrap for chezmoi run_onchange scripts)..."
  nix profile add nixpkgs#python3
  hash -r
fi

# chezmoi 設定用の環境変数をエクスポート
# chezmoi はこれらを .chezmoi.toml.tmpl で参照可能
export CHEZMOI_WORKSPACE_FOLDER="${DOTFILES_WORKSPACE_FOLDER:-${WORKSPACE_FOLDER:-/workspace}}"

echo "  WORKSPACE_FOLDER: $CHEZMOI_WORKSPACE_FOLDER"

# ローカルの dotfiles ディレクトリから chezmoi を初期化・適用
# マーカー "# Installed by treflebonbon/dotfiles" はテンプレートに含まれているため
# 外部 dotfiles の検出に使用可能
# --force: 既存ファイル（デフォルトの .bashrc 等）を上書き
chezmoi init --source="$DOTFILES_DIR" --apply --force

# ログインシェルは bash デフォルト前提のため chsh は行わない。

# flake devShell の初回評価（ユーザー環境）
echo "Setting up user devShell..."
if [ -d "$HOME/.config/nix-devshell" ] && [ -f "$HOME/.config/nix-devshell/flake.nix" ]; then
  # 初回評価で nix-store を warm up（次回 direnv 起動時のブロックを避ける）
  echo "Building user devShell (this may take a while on first run)..."
  (cd "$HOME/.config/nix-devshell" && nix develop --command true) ||
    echo "Warning: user devShell build failed, run 'cd ~/.config/nix-devshell && nix develop' manually"

  # devShell 由来ツール（gh, python3 等）を chezmoi テンプレートに反映
  # run_onchange スクリプト（codex-config 等）が python3 に依存するため、
  # devShell の PATH を継承したサブプロセスとして chezmoi apply を実行する
  # （`nix develop --command true` はサブシェル限りで親プロセスの PATH は変わらない）
  echo "Re-applying chezmoi templates..."
  (cd "$HOME/.config/nix-devshell" && nix develop --command chezmoi apply --source="$DOTFILES_DIR" --force)

  # 新規ターミナルでも AI CLI 等を即利用できるよう、bash 起動用キャッシュを self-heal + 再生成
  if [ -f "$HOME/.config/nix-devshell/lib/refresh-cache.sh" ]; then
    # shellcheck source=/dev/null
    . "$HOME/.config/nix-devshell/lib/refresh-cache.sh"
    refresh_nix_devshell_cache
  fi

  # direnv を許可
  if command -v direnv &>/dev/null; then
    echo "Allowing direnv for ~/.config/nix-devshell..."
    direnv allow "$HOME/.config/nix-devshell" 2>/dev/null || true
  fi
fi

echo "Dotfiles installed successfully!"
echo "Run 'exec bash -l' to apply changes."
