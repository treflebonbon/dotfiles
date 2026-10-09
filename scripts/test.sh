#!/usr/bin/env bash
set -euo pipefail

mkdir -p tmp
log_dir=$(mktemp -d tmp/test-run.XXXXXX)
trap 'printf "%s\n" "$?" >"$log_dir/exit-code"' EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
: >"$log_dir/tap.log"
printf 'テストログ: %s/tap.log\n' "$log_dir" >&2

if ! python3 -I - >"$log_dir/environment" 2>"$log_dir/setup.log" <<'PY'; then
import shutil
import sys
from pathlib import Path

with_env = shutil.which("with-env")
print(f"python3: {Path(sys.executable).resolve()}")
print(f"with-env: {Path(with_env).resolve() if with_env else '未検出'}")
try:
    import dotenv.parser
except ImportError as error:
    raise SystemExit(f"python3 -I: {error}") from None
if not with_env or not Path(with_env).resolve().is_relative_to("/nix/store"):
    raise SystemExit("with-env が Nix store の実行ファイルに解決されない")
PY
  cat "$log_dir/setup.log" >&2
  printf '%s\n' 'テスト環境が不完全です。docs/conventions.md の devShell 手順で再実行してください。' | tee -a "$log_dir/setup.log" >&2
  exit 1
fi

bun install --frozen-lockfile 2>&1 | tee -a "$log_dir/setup.log"
bats --tap --print-output-on-failure tests/ "$@" 2>&1 | tee "$log_dir/tap.log"
