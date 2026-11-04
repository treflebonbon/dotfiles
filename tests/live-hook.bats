#!/usr/bin/env bats

# 実機の Claude / Codex でダミーの gcloud に対し hook が効くかを確認する。モデルを呼ぶため既定は skip。
# 有効化: GCLOUD_INSPECT_HOOK_LIVE=claude または codex。両方なら引用符で囲む: GCLOUD_INSPECT_HOOK_LIVE="claude codex"。
# Codex は使い捨て CODEX_HOME の hook が未信頼で無視されるため、CODEX_BYPASS_HOOK_TRUST=1 も必要（live-hook-agent.sh 参照）。

setup() {
  PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  HOOK="$PROJECT_ROOT/private_dot_local/bin/executable_gcloud-inspect-hook"
}

live() {
  local agent=$1
  [[ " ${GCLOUD_INSPECT_HOOK_LIVE:-} " == *" $agent "* ]] || skip "opt in with GCLOUD_INSPECT_HOOK_LIVE=$agent; calls a hosted model"
  command -v "$agent" >/dev/null || skip "$agent is not installed"
  [ "$agent" != codex ] || [ "${CODEX_BYPASS_HOOK_TRUST:-0}" = 1 ] || skip "codex hooks are untrusted in a throwaway CODEX_HOME; set CODEX_BYPASS_HOOK_TRUST=1 to pass --dangerously-bypass-hook-trust"
  bash "$PROJECT_ROOT/tests/helpers/live-hook-agent.sh" "$agent" "$BATS_TEST_TMPDIR" "$HOOK" \
    "Run exactly this one Bash command and nothing else: gcloud projects list"
  [ "$(cat "$BATS_TEST_TMPDIR/agent.exit")" = 0 ] || { cat "$BATS_TEST_TMPDIR/agent.out"; false; }
  # hook は書換えを返し、実行されたのは gcloud-inspect のダミーだけ。
  grep -q 'gcloud-inspect' "$BATS_TEST_TMPDIR/hook.log.out"
  [ "$(cat "$BATS_TEST_TMPDIR/stub.log")" = "gcloud-inspect [projects] [list]" ]
}

@test "live Claude: gcloud 呼出しは gcloud-inspect のダミーに届く" { live claude; }

@test "live Codex: gcloud 呼出しは gcloud-inspect のダミーに届く" { live codex; }

live_cf() {
  local agent=$1 decision=$2
  [[ " ${CLOUDFLARE_INSPECT_HOOK_LIVE:-} " == *" $agent "* ]] || skip "CLOUDFLARE_INSPECT_HOOK_LIVE=$agent で実モデル検証を有効にする"
  command -v "$agent" >/dev/null || skip "$agent がありません"
  [ "$agent" != codex ] || [ "${CODEX_BYPASS_HOOK_TRUST:-0}" = 1 ] || skip "使い捨て hook の trust が必要です"
  bash "$PROJECT_ROOT/tests/helpers/live-hook-agent.sh" "$agent" "$BATS_TEST_TMPDIR" "$HOOK" \
    'Run exactly this one Bash command and nothing else: cf d1 list. Do not retry or use another command if it fails.' cf "$decision"
  if [[ "$decision" == allow || "$decision" == helper-fail ]]; then
    [ "$(cat "$BATS_TEST_TMPDIR/stub.log")" = 'cloudflare-inspect [d1] [list]' ] || { cat "$BATS_TEST_TMPDIR/agent.out"; false; }
  else
    [ ! -s "$BATS_TEST_TMPDIR/stub.log" ] || { cat "$BATS_TEST_TMPDIR/agent.out"; false; }
    if [[ "$agent" == codex ]]; then
      local reason
      case "$decision" in
      deny) reason='policy forbids commands starting with `cloudflare-inspect`' ;;
      ask) reason='approval required by policy' ;;
      hook-fail) reason='policy forbids commands starting with `cf`' ;;
      esac
      grep -F "$reason" "$BATS_TEST_TMPDIR/agent.out" | grep -q 'ERROR codex_core::tools::router'
    else
      python3 -I - "$BATS_TEST_TMPDIR/agent.out" "$decision" <<'PY'
import json, pathlib, re, sys
text = pathlib.Path(sys.argv[1]).read_text()
command = 'cf d1 list' if sys.argv[2] == 'hook-fail' else 'cloudflare-inspect d1 list'
for match in re.finditer(r'(?m)^\s*\{', text):
    try:
        value, _ = json.JSONDecoder().raw_decode(text[match.start():].lstrip())
    except ValueError:
        continue
    if any(item.get('tool_input', {}).get('command') == command for item in value.get('permission_denials', [])):
        raise SystemExit(0)
raise SystemExit('runtime の permission_denials に対象 command がありません')
PY
    fi
  fi
  if [[ "$decision" != hook-fail ]]; then
    grep -q cloudflare-inspect "$BATS_TEST_TMPDIR/hook.log.out" || { cat "$BATS_TEST_TMPDIR/agent.out"; false; }
  fi
}

@test "live Claude: cf 書換え後の allow が実行される" { live_cf claude allow; }
@test "live Codex: cf 書換え後の allow が実行される" { live_cf codex allow; }
@test "live Claude: cf 書換え後の deny は実行されない" { live_cf claude deny; }
@test "live Codex: cf 書換え後の forbidden は実行されない" { live_cf codex deny; }
@test "live Claude: cf 書換え後の ask は未承認で実行されない" { live_cf claude ask; }
@test "live Codex: cf 書換え後の prompt は未承認で実行されない" { live_cf codex ask; }
@test "live Claude: cf hook 失敗時は元コマンドが拒否される" { live_cf claude hook-fail; }
@test "live Codex: cf hook 失敗時は元コマンドが拒否される" { live_cf codex hook-fail; }
@test "live Claude: cf helper 失敗時に生 CLI へ fallback しない" { live_cf claude helper-fail; }
@test "live Codex: cf helper 失敗時に生 CLI へ fallback しない" { live_cf codex helper-fail; }
