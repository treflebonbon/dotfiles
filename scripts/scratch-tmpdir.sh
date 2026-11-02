# shellcheck shell=bash
# Bats の入口（scripts/test.sh、scripts/test-docs.sh）が source して使う。
# bats 本体は setup_suite より前に TMPDIR から一時領域を作る。検証用 bwrap が書込み可で残すのは scratch root（/tmp/codex）
# だけで、それ以外の TMPDIR では fixture が隠れるか書き込めない。Linux では bats の起動前に、既存の TMPDIR が解決先まで
# scratch root 配下ならそのまま、そうでなければ配下の新しい一時領域へ寄せる。どちらも scratch root を検査する。
# 新しい一時領域を作ったときは scratch_tmpdir にその path を入れる。呼出元が終了時に削除する。
use_scratch_tmpdir() {
  [[ "$(uname -s)" == Linux ]] || return 0
  local bats_tmpdir
  bats_tmpdir=$(
    python3 -B -I - "$(dirname "${BASH_SOURCE[0]}")" <<'PY'
import os
import sys
from pathlib import Path

sys.path.insert(0, sys.argv[1])
from verification_env import ensure_scratch_root, new_runtime

try:
    root = ensure_scratch_root()
    current = os.environ.get("TMPDIR")
    if current and Path(current).resolve().is_relative_to(root):
        print(current)
    else:
        print(new_runtime("bats-tmp."))
except (OSError, ValueError) as error:
    raise SystemExit(f"Bats の一時領域を用意できません: {error}") from None
PY
  )
  if [[ "$bats_tmpdir" != "${TMPDIR:-}" ]]; then
    # 呼出元が終了時の削除に使う。
    # shellcheck disable=SC2034
    scratch_tmpdir=$bats_tmpdir
  fi
  export TMPDIR=$bats_tmpdir
}
