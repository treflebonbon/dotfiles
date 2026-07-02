#!/usr/bin/env bash
# statusline.sh - Claude Code status line script
# Reads JSON from stdin and outputs a 3-line formatted status line
# (ctx context window / 5h rate limit / 7d rate limit)

set -euo pipefail

input=$(cat)

if [ -z "$input" ]; then
  exit 0
fi

if ! command -v jq &>/dev/null; then
  printf '%s\n' "statusline: jq not found"
  exit 0
fi

NOW=$(date +%s)

# --- ANSI カラー ---
CYAN='\033[36m' YELLOW='\033[33m' RED='\033[31m'
GREEN='\033[32m' MAGENTA='\033[35m' DIM='\033[2m' RESET='\033[0m'

# --- ユーティリティ関数 ---

color_for_pct() {
  if [ "$1" -ge 80 ] 2>/dev/null; then
    printf '%b' "$RED"
  elif [ "$1" -ge 50 ] 2>/dev/null; then
    printf '%b' "$YELLOW"
  else printf '%b' "$GREEN"; fi
}

# `set -e` 互換: クランプを if 文で書き換え (記事の `[ ] && ...` パターンを差し替え)
progress_bar() {
  local f=$((($1 + 5) / 10))
  if [ "$f" -gt 10 ]; then f=10; fi
  if [ "$f" -lt 0 ]; then f=0; fi
  local bar="▰▰▰▰▰▰▰▰▰▰"
  local empty="▱▱▱▱▱▱▱▱▱▱"
  printf '%s%s' "${bar:0:$f}" "${empty:0:$((10 - f))}"
}

bar_line() {
  local label="$1" pct="$2" reset_str="${3:-}"
  if [ -n "$pct" ]; then
    printf '%b%-3s %s %3s%%%b%s' "$(color_for_pct "$pct")" "$label" "$(progress_bar "$pct")" "$pct" "$RESET" "$reset_str"
  else
    printf '%b%-3s ▱▱▱▱▱▱▱▱▱▱  --%%%b' "$DIM" "$label" "$RESET"
  fi
}

# `set -e` 互換: early-return を if 文に書き換え
format_reset() {
  local epoch="$1"
  if [ -z "$epoch" ] || [ "$epoch" = "0" ] || [ "$epoch" = "null" ]; then
    return
  fi
  local rem=$((epoch - NOW))
  if [ "$rem" -le 0 ]; then
    return
  fi
  local d=$((rem / 86400)) h=$((rem % 86400 / 3600)) m=$((rem % 3600 / 60))
  if [ "$d" -gt 0 ]; then
    printf ' %d日 %2d時間 %2d分でリセット' "$d" "$h" "$m"
  elif [ "$h" -gt 0 ]; then
    printf ' %d時間 %2d分でリセット' "$h" "$m"
  else
    printf ' %d分でリセット' "$m"
  fi
}

# 週次 (7d) 用: 固定カレンダー境界なので相対カウントダウンではなく絶対時刻で表示
# (/usage の "weekly Mon 18 May 09:00" 表記に倣う)。% リセットと resets_at は
# デカップルしているため、相対表示だと「未リセット」に見える混乱を避ける。
format_reset_abs() {
  local epoch="$1" formatted
  if [ -z "$epoch" ] || [ "$epoch" = "0" ] || [ "$epoch" = "null" ]; then
    return
  fi
  # GNU date (Linux) は `-d @epoch`、BSD/macOS date は `-r epoch`。
  # `%-m`/`%-d` のゼロ埋め抑制は GNU 拡張のため、BSD 分岐ではゼロ埋めを許容する。
  formatted=$(date -d "@$epoch" +'%-m/%-d %H:%M' 2>/dev/null) ||
    formatted=$(date -r "$epoch" +'%m/%d %H:%M' 2>/dev/null) ||
    formatted=""
  if [ -n "$formatted" ]; then
    printf ' %s リセット' "$formatted"
  fi
}

# --- stdin JSON パース ---
eval "$(echo "$input" | jq -r '
  "MODEL=" + (.model.display_name // "Unknown" | @sh),
  "CTX_SIZE=" + (.context_window.context_window_size // 200000 | tostring),
  "CTX_USED_PCT=" + (.context_window.used_percentage // 0 | tostring),
  "CTX_INPUT=" + ((.context_window.current_usage.input_tokens // 0) | tostring),
  "CTX_CACHE_CREATE=" + ((.context_window.current_usage.cache_creation_input_tokens // 0) | tostring),
  "CTX_CACHE_READ=" + ((.context_window.current_usage.cache_read_input_tokens // 0) | tostring),
  "CTX_HAS_USAGE=" + (if .context_window.current_usage then "1" else "0" end),
  "CWD=" + (.workspace.current_dir // "." | @sh),
  "LINES_ADD=" + (.cost.total_lines_added // 0 | tostring),
  "LINES_DEL=" + (.cost.total_lines_removed // 0 | tostring),
  "FIVE_PCT=" + (.rate_limits.five_hour.used_percentage // empty | floor | tostring),
  "FIVE_RESET_EPOCH=" + (.rate_limits.five_hour.resets_at // 0 | tostring),
  "SEVEN_PCT=" + (.rate_limits.seven_day.used_percentage // empty | floor | tostring),
  "SEVEN_RESET_EPOCH=" + (.rate_limits.seven_day.resets_at // 0 | tostring)
' 2>/dev/null)"

# jq の `// empty` で未定義になりうる変数のデフォルト (set -u 互換)
: "${FIVE_PCT:=}"
: "${SEVEN_PCT:=}"

if [ "$CTX_HAS_USAGE" = "1" ]; then
  CTX_PCT=$(((CTX_INPUT + CTX_CACHE_CREATE + CTX_CACHE_READ) * 100 / CTX_SIZE))
else
  CTX_PCT=${CTX_USED_PCT%%.*}
fi

# --- Git ブランチ ---
GIT_BRANCH=""
if git -C "$CWD" rev-parse --git-dir >/dev/null 2>&1; then
  BRANCH=$(git -C "$CWD" --no-optional-locks branch --show-current 2>/dev/null)
  if [ -n "$BRANCH" ]; then
    GIT_BRANCH=" | ${MAGENTA}${BRANCH}${RESET}"
  fi
fi

# --- レートリミット（stdin JSON から取得） ---
FIVE_RESET=$(format_reset "$FIVE_RESET_EPOCH")
SEVEN_RESET=$(format_reset_abs "$SEVEN_RESET_EPOCH")

# --- 出力 ---
LINE_STATS=""
if [ "$LINES_ADD" -gt 0 ] 2>/dev/null || [ "$LINES_DEL" -gt 0 ] 2>/dev/null; then
  LINE_STATS=" | ${GREEN}+${LINES_ADD}${RESET}/${RED}-${LINES_DEL}${RESET}"
fi

printf '%b\n' "$(bar_line "ctx" "$CTX_PCT") | ${CYAN}${MODEL}${RESET}${GIT_BRANCH}${LINE_STATS}"
printf '%b\n' "$(bar_line "5h" "$FIVE_PCT") |$FIVE_RESET"
printf '%b' "$(bar_line "7d" "$SEVEN_PCT") |$SEVEN_RESET"
