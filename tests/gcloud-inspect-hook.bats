#!/usr/bin/env bats

bats_require_minimum_version 1.5.0

setup() {
  PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  SCRIPT="$PROJECT_ROOT/private_dot_local/bin/executable_gcloud-inspect-hook"
}

# 指定した command を PreToolUse の入力として hook へ渡す。
hook() {
  HOOK_CMD="$1" python3 -I -c '
import json, os
print(json.dumps({"tool_name": "Bash", "tool_input": {"command": os.environ["HOOK_CMD"], "description": "d"}}))
' | "$SCRIPT"
}

# 引数文字列を bash が単語分割した結果を NUL 区切りで出す（展開後の引数列の独立した基準）。
bash_args() {
  bash -c "printf '%s\\0' $1" | python3 -I -c 'import sys; print(sys.stdin.buffer.read().split(b"\0"))'
}

# hook の JSON 出力から値を取り出す。引数は path（例: decision, command, reason）。
field() {
  python3 -I -c '
import json, sys
out = json.load(sys.stdin)["hookSpecificOutput"]
assert out["hookEventName"] == "PreToolUse"
path = sys.argv[1]
print({
    "decision": out["permissionDecision"],
    "reason": out.get("permissionDecisionReason", ""),
    "command": out.get("updatedInput", {}).get("command", ""),
    "description": out.get("updatedInput", {}).get("description", ""),
}[path])
' "$1"
}

@test "単独の gcloud 呼出しは gcloud-inspect へ書換える" {
  run -0 hook "gcloud logging read 'severity>=ERROR' --project p"
  [ "$(field decision <<<"$output")" = "allow" ]
  [ "$(field command <<<"$output")" = "gcloud-inspect logging read 'severity>=ERROR' --project p" ]
}

@test "書換え時に command 以外の tool_input を保つ" {
  run -0 hook "gcloud projects list"
  [ "$(field description <<<"$output")" = "d" ]
}

@test "引数列は空引数・空白・メタ文字を含めて保存する" {
  local -a cases=(
    "gcloud projects list '--filter=\$(printf PROBE)'"
    "gcloud projects list ''"
    "gcloud projects list 'a b'"
    "gcloud projects list \"a b\""
    "gcloud projects list a\\ b"
    "gcloud projects list 'it'\"'\"'s'"
    "gcloud projects list \"a\\\"b\""
    "gcloud projects list '--filter=a;b|c&d>e'"
    "gcloud projects list \"\\\$HOME\""
  )
  local c rewritten
  for c in "${cases[@]}"; do
    run -0 hook "$c"
    rewritten="$(field command <<<"$output")"
    [[ "$rewritten" == "gcloud-inspect "* ]]
    # 期待値は bash 自身の単語分割で作る（元の引数と書換え後の引数が一致すること）。
    [ "$(bash_args "${c#gcloud }")" = "$(bash_args "${rewritten#gcloud-inspect }")" ] || { echo "args differ: $c => $rewritten"; false; }
  done
}

@test "gcloud-inspect の入力に書換え後も展開が残らない" {
  run -0 hook "gcloud projects list '--filter=\$(printf PROBE)'"
  [ "$(field command <<<"$output")" = "gcloud-inspect projects list '--filter=\$(printf PROBE)'" ]
}

@test "複合 shell は分割の案内つきで deny する" {
  local -a cases=(
    "cd repo && gcloud projects list"
    "gcloud logging read x | jq ."
    "gcloud projects list; echo done"
    "gcloud projects list &"
    "echo \$(gcloud projects list)"
    "echo \`gcloud projects list\`"
    "(gcloud projects list)"
    "gcloud projects list || true"
    "x=\$(gcloud projects list)"
    "echo \"\$(gcloud projects list)\""
    $'echo a\ngcloud projects list'
    "echo \"\$(true && gcloud projects list)\""
    "echo \"\$(cd d; gcloud projects list)\""
    "echo \"\`true; gcloud projects list\`\""
    "time gcloud projects list"
    "if true; then gcloud projects list; fi"
    "{ gcloud projects list; }"
    "! gcloud projects list"
    $'echo ok # comment\ngcloud projects list'
    $'cat <<EOF\ntext\nEOF\ngcloud projects list'
    $'cat <<-EOF\n\ttext\n\tEOF\ngcloud projects list'
    $'cat <<\'EOF\'\ngcloud in body\nEOF\ngcloud projects list'
    $'cat <<EOF | tee x\ntext\nEOF\ngcloud projects list'
    "echo \"\$(time gcloud projects list)\""
    "echo \"\$(if true; then gcloud projects list; fi)\""
    "echo \"\$(! gcloud projects list)\""
    "echo \"\$(while true; do gcloud projects list; done)\""
    $'echo "$(cat <<\'EOF\'\nbody\nEOF\n)"; gcloud projects list'
    $'echo "$(cat <<\'EOF\'\nbody\nEOF\n)"\ngcloud projects list'
    $'echo "$(cat <<EOF\nsay \"hi\" and gcloud x\nEOF\n)" && gcloud projects list'
    $'echo "$(cat <<-EOF\n\tbody\n\tEOF\n)" | gcloud projects list'
  )
  local c
  for c in "${cases[@]}"; do
    run -0 hook "$c"
    [ "$(field decision <<<"$output")" = "deny" ] || { echo "not denied: $c"; false; }
    [[ "$(field reason <<<"$output")" == *"単独で1回"* ]] || { echo "wrong reason: $c"; false; }
  done
}

@test "展開・代入・リダイレクト・glob・コメントは案内つきで deny する" {
  local -a cases=(
    "gcloud projects list --filter=\"\$(something)\""
    "gcloud \$ARGS"
    "gcloud \"\$ARGS\""
    "gcloud projects list \$HOME"
    "gcloud projects list \"\${HOME}\""
    "gcloud projects list *"
    "gcloud projects list ~"
    "gcloud projects list name=~"
    "gcloud projects list a:~"
    "gcloud projects list {a,b}"
    "gcloud projects list ?"
    "gcloud projects list [a]"
    "NAME=value gcloud projects list"
    "NAME='value' gcloud projects list"
    "NAME=\"value\" gcloud projects list"
    "NAME=a\\ b gcloud projects list"
    "A=1 B='2' gcloud projects list"
    "gcloud projects list > out.json"
    "gcloud projects list 2>&1"
    "gcloud projects list < in"
    "gcloud projects list <<EOF"
    "gcloud projects list # comment"
    "gcloud projects list 'unterminated"
    "gcloud projects list \"unterminated"
    "gcloud projects list \\"
    $'gcloud projects list \'a\nb\''
  )
  local c
  for c in "${cases[@]}"; do
    run -0 hook "$c"
    [ "$(field decision <<<"$output")" = "deny" ] || { echo "not denied: $c"; false; }
    [[ "$(field reason <<<"$output")" == *"リテラルの引数だけ"* ]] || { echo "wrong reason: $c"; false; }
  done
}

@test "先頭の --reviewed は引用符を外した後でも deny する" {
  local -a cases=(
    "gcloud --reviewed compute disks describe d"
    "gcloud '--reviewed' compute disks describe d"
    "gcloud \"--reviewed\" compute disks describe d"
    "gcloud --revie\"wed\" compute disks describe d"
  )
  local c
  for c in "${cases[@]}"; do
    run -0 hook "$c"
    [ "$(field decision <<<"$output")" = "deny" ] || { echo "not denied: $c"; false; }
    [[ "$(field reason <<<"$output")" == *"gcloud-inspect --reviewed"* ]] || { echo "wrong reason: $c"; false; }
  done
}

@test "末尾の改行や空白は無視して書換える" {
  run -0 hook $'gcloud projects list \n'
  [ "$(field decision <<<"$output")" = "allow" ]
  [ "$(field command <<<"$output")" = "gcloud-inspect projects list" ]
}

@test "書換え後の command を実行すると helper には展開前の引数がそのまま届く" {
  mkdir -p "$BATS_TEST_TMPDIR/bin"
  export STUB_LOG="$BATS_TEST_TMPDIR/stub.log"
  for name in gcloud gcloud-inspect; do
    cat >"$BATS_TEST_TMPDIR/bin/$name" <<'SH'
#!/usr/bin/env bash
{ printf '%s' "${0##*/}"; printf ' [%s]' "$@"; printf '\n'; } >>"$STUB_LOG"
SH
    chmod +x "$BATS_TEST_TMPDIR/bin/$name"
  done
  run -0 hook "gcloud logging read 'severity>=ERROR AND textPayload:\"a b\"' --project p '' '--filter=\$(touch $BATS_TEST_TMPDIR/pwned)' 'it'\"'\"'s'"
  PATH="$BATS_TEST_TMPDIR/bin:$PATH" bash -c "$(field command <<<"$output")"
  # 元の gcloud は実行されず、helper には引数が1語ずつそのまま届く。展開は起きない。
  [ "$(cat "$STUB_LOG")" = "gcloud-inspect [logging] [read] [severity>=ERROR AND textPayload:\"a b\"] [--project] [p] [] [--filter=\$(touch $BATS_TEST_TMPDIR/pwned)] [it's]" ]
  [ ! -e "$BATS_TEST_TMPDIR/pwned" ]
}

@test "--reviewed が先頭以外にある場合は helper へ渡す" {
  run -0 hook "gcloud projects list --reviewed"
  [ "$(field decision <<<"$output")" = "allow" ]
  [ "$(field command <<<"$output")" = "gcloud-inspect projects list --reviewed" ]
}

@test "対象外の入力は何も出力しない" {
  local -a cases=(
    "gh pr view 42"
    "gh api repos/o/r"
    "gh pr create --title t --body 'gcloud を使う'"
    "cd repo && gh pr view 42"
    "echo gcloud"
    "echo \"use gcloud\""
    "grep gcloud file"
    "cd r && echo gcloud"
    "grep gcloud file | wc -l"
    "gcloud-inspect logging read x"
    "gcloud-inspect --reviewed compute disks describe d"
    "command gcloud projects list"
    "env gcloud projects list"
    "/usr/bin/gcloud projects list"
    "'gcloud' projects list"
    "gcl\"oud\" projects list"
    "sudo gcloud projects list"
    "echo \"\$Xgcloud\""
    "echo \"\$(echo hi; gcloud-inspect projects list)\""
    "echo \"\$(date)\"; echo gcloud"
    "echo ok # gcloud projects list"
    $'echo ok # note\necho done'
    $'cat <<EOF\ngcloud projects list\nEOF'
    $'cat <<EOF\ntext\nEOF\necho done'
    "\"NAME=v\" gcloud projects list"
    $'git commit -m "$(cat <<\'EOF\'\nfix: \"quoted\" gcloud x\nEOF\n)"'
    $'echo "$(cat <<\'EOF\'\nbody; gcloud projects list\nEOF\n)"; echo done'
    "gh pr create --body \"\$(cat body.md)\" --title \"fix (gcloud)\""
    "echo \"\$(date)\" \"; gcloud\""
    "echo \"\$(date)\" \"| gcloud\""
    "echo \"\$(date)\" \"then gcloud\""
    "echo \"\$(date)\" \"!gcloud\""
    "echo \"\\\`date\\\`\" \"(gcloud)\""
    "ls"
    ""
  )
  local c
  for c in "${cases[@]}"; do
    run -0 hook "$c"
    [ -z "$output" ] || { echo "unexpected output for: $c"; echo "$output"; false; }
  done
}

@test "heredoc を含む commit や PR 本文では gcloud の言及で deny しない" {
  run -0 hook $'git commit -m "$(cat <<\'EOF\'\nfeat: route gcloud\n\ngcloud projects list を gcloud-inspect へ\nEOF\n)"'
  [ -z "$output" ]
  run -0 hook $'python3 - <<\'PY\'\nprint("x")\ngcloud projects list\nPY'
  [ -z "$output" ]
}

@test "Bash 以外の tool と壊れた入力では何もしない" {
  run -0 bash -c 'printf %s "{\"tool_name\":\"Read\",\"tool_input\":{\"command\":\"gcloud projects list\"}}" | "$1"' _ "$SCRIPT"
  [ -z "$output" ]
  run -0 bash -c 'printf %s "not json" | "$1"' _ "$SCRIPT"
  [ -z "$output" ]
  run -0 bash -c 'printf %s "{\"tool_name\":\"Bash\",\"tool_input\":{}}" | "$1"' _ "$SCRIPT"
  [ -z "$output" ]
  run -0 bash -c 'printf %s "{\"tool_name\":\"Bash\",\"tool_input\":{\"command\":5}}" | "$1"' _ "$SCRIPT"
  [ -z "$output" ]
}
