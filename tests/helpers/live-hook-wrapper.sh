#!/usr/bin/env bash
# 実際の hook を包み、入力（$HOOK_LOG.in）と出力（$HOOK_LOG.out）を記録する。引数: hook のパス。
set -euo pipefail
input=$(cat)
printf '%s\n' "$input" >>"${HOOK_LOG:?}.in"
output=$("$1" <<<"$input")
printf '%s\n' "$output" >>"$HOOK_LOG.out"
printf '%s' "$output"
