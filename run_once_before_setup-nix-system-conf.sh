#!/usr/bin/env bash
# /etc/nix/nix.custom.conf を chezmoi が管理し、user の nix 設定を system-level で確実に効かせる
# untrusted user (devpod コンテナ等) でも extra-substituters / download-buffer-size 等が機能する
# run_once_before: chezmoi のデプロイ前に実行 (一度のみ、内容ハッシュ変更で再実行)
set -euo pipefail

# パスは env var で override 可能 (テスト用)
NIX_CONF="${NIX_CONF_PATH:-/etc/nix/nix.conf}"
CUSTOM_CONF="${NIX_CUSTOM_CONF_PATH:-/etc/nix/nix.custom.conf}"
SYSTEMD_RUNTIME_DIR="${SYSTEMD_RUNTIME_DIR:-/run/systemd/system}"

# Nix 未インストール環境はスキップ
[ -f "$NIX_CONF" ] || exit 0

# 非対話 sudo が使えない環境 (CI / sudo 未設定コンテナ / TTY 無しの apply) では、
# sudo を要する system conf 書き込みを graceful に degrade する。下部の
# restart_nix_daemon と同じ方針。TTY がある対話実行 (install.sh 等) では sudo が
# パスワードプロンプトを出せるため通常経路に進む — `sudo -n` 失敗だけで degrade
# すると対話環境の初回セットアップまで塞いでしまう。exit 0 で apply 全体は
# 止めない (run_once_before の失敗が chezmoi apply を abort させないため)。
if ! sudo -n true 2>/dev/null && [ ! -t 0 ]; then
  if [ -f "$CUSTOM_CONF" ] && grep -q '^!include nix\.custom\.conf$' "$NIX_CONF" 2>/dev/null; then
    echo "nix: 非対話 sudo 不可。$CUSTOM_CONF は既に整備済みのため system conf 更新をスキップ"
  else
    echo "nix: 非対話 sudo 不可かつ $CUSTOM_CONF 未整備。install.sh を対話実行するか手動で nix system conf を設定してください" >&2
  fi
  exit 0
fi

# nix.custom.conf を sudo touch で作成 (存在しない場合)
[ -f "$CUSTOM_CONF" ] || sudo touch "$CUSTOM_CONF"

# /etc/nix/nix.conf に !include nix.custom.conf を追加 (なければ)
if ! grep -q '^!include nix\.custom\.conf$' "$NIX_CONF"; then
  echo '!include nix.custom.conf' | sudo tee -a "$NIX_CONF" >/dev/null
fi

# nix.custom.conf を期待状態に rewrite (idempotent)
USER_NAME="$(whoami)"
sudo tee "$CUSTOM_CONF" >/dev/null <<EOF
# Managed by chezmoi: treflebonbon/dotfiles run_once_before_setup-nix-system-conf.sh
# DO NOT EDIT — changes here are overwritten on next chezmoi apply.

trusted-users = root $USER_NAME

# rust-overlay のバイナリキャッシュ
extra-substituters = https://nix-community.cachix.org
extra-trusted-public-keys = nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs=

# llm-agents (numtide)
extra-substituters = https://cache.numtide.com
extra-trusted-public-keys = niks3.numtide.com-1:DTx8wZduET09hRmMtKdQDxNNthLQETkc/yaX7M4qK0g=

# 高速回線向けダウンロードバッファ (デフォルト 1MB → 128MB)
download-buffer-size = 134217728

# flakes が /etc/nix/nix.conf に書き込まれていない環境 (systemd 不在コンテナで
# nix-installer SelfTest WARN が発火するなど) の救済。
# install.sh の NIX_CONFIG / --extra-conf と二重防御。
extra-experimental-features = nix-command flakes
EOF
echo "nix: $CUSTOM_CONF を更新しました ($USER_NAME を trusted-users に追加 + binary caches + download-buffer-size)"

# nix-daemon を再起動して新設定 (extra-substituters / trusted-users 等) を反映
restart_nix_daemon() {
  # systemd が実際に稼働している環境 (DevPod の systemctl shim は /run/systemd/system が無いため弾ける)
  if [ -d "$SYSTEMD_RUNTIME_DIR" ] && command -v systemctl >/dev/null 2>&1 &&
    systemctl is-active nix-daemon >/dev/null 2>&1; then
    sudo systemctl restart nix-daemon
    echo "nix-daemon を再起動しました (systemd)"
    return 0
  fi

  # systemd 不在環境 (DevPod / dev container 等): pkill + spawn で本当に再起動する
  if ! pgrep -x nix-daemon >/dev/null 2>&1; then
    echo "nix: nix-daemon は未起動。新設定は次回起動時に反映されます"
    return 0
  fi

  if ! sudo -n true 2>/dev/null; then
    echo "nix: sudo を非対話で取得できないため nix-daemon の再起動をスキップ (手動再起動が必要)"
    return 0
  fi

  local nix_daemon_bin=/nix/var/nix/profiles/default/bin/nix-daemon
  if [ ! -x "$nix_daemon_bin" ]; then
    echo "nix: $nix_daemon_bin が見つからないため再起動スキップ"
    return 0
  fi

  echo "nix: systemd 不在のため pkill + spawn で nix-daemon を再起動します"
  sudo pkill -x nix-daemon || true
  # 旧プロセスの teardown を待つ (socket は新 daemon が再生成する)
  sleep 1

  # stdin/stdout/stderr を端末から切り離す。リダイレクトしないと nix-daemon の
  # 接続ログ (accepted connection from pid ..., user ... (trusted)) が spawn 元の
  # 対話端末を fd 継承したまま流れ続ける (disown はジョブ管理から外すだけで fd は切らない)。
  # 出力先は /dev/null: 共有 /tmp 等のログファイルが他 user 所有で書き込み不可だと、
  # 直前の pkill 後にリダイレクトが失敗し set -e で daemon 未起動のまま abort する。
  # 常に書き込み可能な /dev/null なら起動が失敗せず、ログ肥大化も起きない。
  # SC2024: リダイレクトは呼び出し元ユーザーのシェルで行うのが正しい (root 権限の出力先化は不要)。
  # shellcheck disable=SC2024
  sudo "$nix_daemon_bin" </dev/null >/dev/null 2>&1 &
  disown

  # ソケット ready まで最大 30s 待つ (install.sh と同じ手法)
  for _ in $(seq 1 30); do
    [ -S /nix/var/nix/daemon-socket/socket ] && break
    sleep 1
  done
  if [ ! -S /nix/var/nix/daemon-socket/socket ]; then
    echo "nix: 警告: nix-daemon socket が 30s 経っても準備できませんでした"
    return 0
  fi

  echo "nix-daemon を再起動しました (pkill + spawn)"
}

restart_nix_daemon

# 旧 user-level ~/.config/nix/nix.conf 残骸を削除 (chezmoi unmanage 化したファイル)
USER_NIX_CONF="$HOME/.config/nix/nix.conf"
if [ -f "$USER_NIX_CONF" ]; then
  rm -f "$USER_NIX_CONF"
  echo "nix: $USER_NIX_CONF を削除しました (system-level に格上げ済み)"
fi
