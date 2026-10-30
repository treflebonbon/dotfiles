#!/usr/bin/env bash
set -Eeuo pipefail

repo="$(git rev-parse --show-toplevel)"
cd "$repo"

for command in curl git playwright-cli python3; do
  if ! command -v "$command" >/dev/null 2>&1; then
    printf 'Required command is unavailable: %s\n' "$command" >&2
    exit 2
  fi
done

mkdir -p -- .tmp
run_dir="$(mktemp -d "$repo/.tmp/architecture-render-smoke.XXXXXX")"
web_root="$run_dir/web"
fixture_dir="$repo/tests/fixtures/architecture-render"
skills_root="$(cd "${TREFLEBONBON_SKILLS_LIB:?run this check in the pinned skills-plugin devShell}/../.." && pwd)"
checker="$skills_root/skills/herdr-peer-refactor/scripts/check-architecture-render.js"
tap="$run_dir/browser-smoke.tap"
console_log="$run_dir/browser-console.log"
session="architecture-render-smoke-$$"
server_pid=
mkdir -p -- "$web_root"
cp -R -- "$fixture_dir"/. "$web_root"/

printf 'TAP log: %s\n' "$tap"
printf 'Browser console log: %s\n' "$console_log"
if ! curl --fail --location --silent --show-error --max-time 30 \
  https://cdn.jsdelivr.net/npm/mermaid@11.17.2/dist/mermaid.min.js \
  --output "$web_root/mermaid.min.js"; then
  printf 'Could not fetch Mermaid 11.17.2 from jsDelivr.\n' >&2
  exit 2
fi

cleanup() {
  if [[ -n "$server_pid" ]]; then
    kill "$server_pid" 2>/dev/null || true
    wait "$server_pid" 2>/dev/null || true
  fi
  playwright-cli -s="$session" close >/dev/null 2>&1 || true
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

python3 "$repo/scripts/architecture-render-fixture-server.py" "$web_root" \
  >"$run_dir/server.log" 2>&1 &
server_pid=$!
port=
for _ in {1..100}; do
  port="$(sed -n 's/^READY //p' "$run_dir/server.log" | head -n 1)"
  if [[ -n "$port" ]] || ! kill -0 "$server_pid" 2>/dev/null; then
    break
  fi
  sleep 0.1
done
if [[ ! "$port" =~ ^[0-9]+$ ]]; then
  cat "$run_dir/server.log" >&2
  printf 'Loopback fixture server did not report its port.\n' >&2
  exit 2
fi
if ! playwright-cli -s="$session" open about:blank >"$run_dir/open.log" 2>&1; then
  cat "$run_dir/open.log" >&2
  printf 'Could not open the managed Playwright CLI session.\n' >&2
  exit 2
fi

printf 'TAP version 13\n1..7\n' >"$tap"
: >"$console_log"
failures=0
number=0
run_case() {
  local name="$1" file="$2" expected_count="$3" expectation="$4"
  local needle="$5" extra_needle="${6-}"
  number=$((number + 1))
  local url="http://127.0.0.1:$port/$file?__architecture_expected_mermaid=$expected_count"
  local goto_log="$run_dir/$number-goto.log" run_log="$run_dir/$number-run.log"
  local status=0

  playwright-cli -s="$session" goto "$url" >"$goto_log" 2>&1 || status=99
  if [[ "$status" -eq 0 ]]; then
    playwright-cli -s="$session" --raw run-code "$(sed '$s/;$//' "$checker")" >"$run_log" 2>&1 || status=$?
  fi
  {
    printf '\n## %s\n' "$name"
    cat "$goto_log"
    if [[ -f "$run_log" ]]; then cat "$run_log"; fi
    playwright-cli -s="$session" console error 2>&1 || true
  } >>"$console_log"

  if [[ -f "$run_log" ]] &&
    { [[ "$expectation" = pass && "$status" -eq 0 ]] ||
      [[ "$expectation" = fail && "$status" -ne 0 ]]; } &&
    grep -Fq -- "$needle" "$run_log" &&
    { [[ -z "$extra_needle" ]] || grep -Fq -- "$extra_needle" "$run_log"; }; then
    printf 'ok %d - %s\n' "$number" "$name" | tee -a "$tap"
    return
  fi
  printf 'not ok %d - %s (exit=%s, expected=%s, evidence=%s)\n' \
    "$number" "$name" "$status" "$expectation" "$run_log" | tee -a "$tap"
  failures=$((failures + 1))
}

run_case 'valid diagram renders once' valid.html 1 pass '"ok":true'
run_case 'original nested-markup error diagram is rejected' original-error.html 1 fail '"marker":"error-icon"' '"reloadStatus":200'
run_case 'invalid Mermaid syntax is rejected' invalid-syntax.html 1 fail '"reloadStatus":200' '"marker":"error-icon"'
run_case 'empty report with HTTP 200 passes' no-diagrams.html 0 pass '"reloadStatus":200'
run_case 'empty report with HTTP 404 fails' missing.html 0 fail '"reloadStatus":404'
run_case 'one container with two SVGs fails' two-svgs.html 1 fail '"diagramSvgCounts":[2]'
run_case 'non-favicon console error fails' console-error.html 1 fail 'fixture console error'

if [[ "$failures" -ne 0 ]]; then
  printf 'Browser smoke failed: %s of 7 cases. Evidence: %s\n' "$failures" "$run_dir" >&2
  exit 1
fi
printf 'Browser smoke passed: 7 cases. Evidence: %s\n' "$run_dir"
