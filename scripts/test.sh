#!/usr/bin/env bash
set -euo pipefail

if ! environment=$(
  python3 -I - <<'PY'
import shutil
import sys
from pathlib import Path

try:
    import dotenv.parser
except ImportError as error:
    raise SystemExit(f"python3 -I: {error}") from None
with_env = shutil.which("with-env")
if not with_env or not Path(with_env).resolve().is_relative_to("/nix/store"):
    raise SystemExit("with-env が Nix store の実行ファイルに解決されない")
print(f"python3: {Path(sys.executable).resolve()}")
print(f"with-env: {Path(with_env).resolve()}")
PY
); then
  printf '%s\n' 'テスト環境が不完全です。docs/conventions.md の devShell 手順で再実行してください。' >&2
  exit 1
fi

bun install --frozen-lockfile
mkdir -p tmp
log_dir=$(mktemp -d tmp/test-run.XXXXXX)
printf '%s\n' "$environment" >"$log_dir/environment"
trap 'printf "%s\n" "$?" >"$log_dir/exit-code"' EXIT
printf 'テストログ: %s/tap.log\n' "$log_dir" >&2
bats --tap --print-output-on-failure tests/ "$@" 2>&1 | tee "$log_dir/tap.log"
