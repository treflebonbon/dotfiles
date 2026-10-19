#!/usr/bin/env bats

# 実機の Claude / Codex でダミーの gcloud に対し hook が効くかを確認する。モデルを呼ぶため既定は skip。
# 有効化: GCLOUD_INSPECT_HOOK_LIVE=claude / codex（空白区切りで両方可）。
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
