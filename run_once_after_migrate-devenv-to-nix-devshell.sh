#!/usr/bin/env bash
# 旧配備先は独自設定との区別ができないため、保持して確認を案内する。
set -euo pipefail

OLD="$HOME/.config/devenv"

if [ -e "$OLD" ] || [ -L "$OLD" ]; then
  echo "migrate-devenv-to-nix-devshell: $OLD を保持しました。不要かどうか手動で確認してください" >&2
fi
