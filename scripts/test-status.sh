#!/usr/bin/env bash
# 最新の tmp/test-run.* の進捗を表示する。exit-code があれば完了、無ければ実行中。
# プロセスは見ない（pgrep は使わない）。TAP の結果行から成功・失敗・スキップ・計画件数を数える。
set -euo pipefail

# 開始時刻（scripts/test.sh が書く started、ナノ秒）が最も新しい実行を選ぶ。started の無い古い実行は更新時刻で比べる。
latest() {
  local d key best="" best_key=-1
  for d in tmp/test-run.*/; do
    [[ -d "$d" ]] || continue
    if [[ -f "$d/started" ]]; then
      key=$(<"$d/started")
    else
      key=$(($(stat -c %Y "$d") * 1000000000))
    fi
    if ((key > best_key)); then
      best_key=$key
      best=${d%/}
    fi
  done
  printf '%s' "$best"
}

dir=${1:-$(latest)}
[[ -n "$dir" && -d "$dir" ]] || {
  echo "tmp/test-run.* がありません" >&2
  exit 1
}
dir=${dir%/}

tap="$dir/tap.log"
plan=$(sed -n 's/^1\.\.\([0-9][0-9]*\).*/\1/p' "$tap" 2>/dev/null | head -n1 || true)
read -r pass fail skip < <(awk '
  /^not ok / { f++ }
  /^ok / { if ($0 ~ /# [Ss][Kk][Ii][Pp]/) s++; else p++ }
  END { print p + 0, f + 0, s + 0 }' "$tap" 2>/dev/null || echo "0 0 0")

if [[ -f "$dir/exit-code" ]]; then
  state="完了 (exit $(<"$dir/exit-code"))"
else
  state="実行中"
fi
printf '%s: %s\n成功 %s / 失敗 %s / スキップ %s / 計画 %s\n' "$dir" "$state" "$pass" "$fail" "$skip" "${plan:-未確定}"
