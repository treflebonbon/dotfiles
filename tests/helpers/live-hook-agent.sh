#!/usr/bin/env bash
# 実機の Claude / Codex に1回だけ Bash を呼ばせ、hook とダミーの記録を残す。
# 使い方: live-hook-agent.sh claude|codex WORK_DIR HOOK PROMPT
# WORK_DIR に bin/（ダミー）、stub.log、hook.log.in/out、agent.out、agent.exit を作る。
# モデルを呼ぶので opt-in 専用。Codex は host の ~/.codex/auth.json を symlink で借りる。
#
# codex exec の落とし穴:
#   - stdin が端末のままだと入力待ちで止まる → </dev/null
#   - git 管理外の WORK_DIR では --skip-git-repo-check が要る
#   - 使い捨ての CODEX_HOME の hook は未信頼のため Codex に無視される。信頼の保存形式は未確認なので自動では回避しない。
#     自前のラッパーだけと承知の上で、呼出し限りの --dangerously-bypass-hook-trust を使う場合に限り CODEX_BYPASS_HOOK_TRUST=1 を設定する
#   - `| tail` は timeout の Terminated を隠し、終了コードも tail のものになる → ファイルへ出して終了コードを別に記録する
set -euo pipefail
agent=$1 work=$2 hook=$3 prompt=$4
here=$(cd "$(dirname "$0")" && pwd)
mkdir -p "$work/bin"
for name in gcloud gcloud-inspect; do
  cp "$here/live-hook-stub.sh" "$work/bin/$name"
  chmod +x "$work/bin/$name"
done
export STUB_LOG="$work/stub.log" HOOK_LOG="$work/hook.log" PATH="$work/bin:$PATH"
: >"$STUB_LOG"
wrapper="$here/live-hook-wrapper.sh"
command_line="bash $wrapper $hook"

case "$agent" in
claude)
  settings="$work/settings.json"
  jq -n --arg c "$command_line" '{hooks: {PreToolUse: [{matcher: "Bash", hooks: [{type: "command", command: $c}]}]}}' >"$settings"
  cmd=(claude -p "$prompt" --settings "$settings" --allowedTools Bash)
  ;;
codex)
  export CODEX_HOME="$work/codex-home"
  mkdir -p "$CODEX_HOME"
  ln -sf "$HOME/.codex/auth.json" "$CODEX_HOME/auth.json"
  printf '[features]\nhooks = true\n' >"$CODEX_HOME/config.toml"
  jq -n --arg c "$command_line" '{hooks: {PreToolUse: [{matcher: "Bash", hooks: [{type: "command", command: $c}]}]}}' >"$CODEX_HOME/hooks.json"
  cmd=(codex exec --skip-git-repo-check --sandbox workspace-write -C "$work" "$prompt")
  [ "${CODEX_BYPASS_HOOK_TRUST:-0}" = 1 ] && cmd+=(--dangerously-bypass-hook-trust)
  ;;
*)
  echo "agent は claude か codex" >&2
  exit 2
  ;;
esac

set +e
timeout 180 "${cmd[@]}" </dev/null >"$work/agent.out" 2>&1
printf '%s\n' "$?" >"$work/agent.exit"
