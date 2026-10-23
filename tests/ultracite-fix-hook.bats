#!/usr/bin/env bats

setup() {
  PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  HOOK="$PROJECT_ROOT/private_dot_local/bin/executable_ultracite-fix-hook"
  export CLAUDE_PROJECT_DIR="$BATS_TEST_TMPDIR/project with spaces"
  export CALL_LOG="$BATS_TEST_TMPDIR/call.json"
  mkdir -p "$CLAUDE_PROJECT_DIR/node_modules/.bin" "$BATS_TEST_TMPDIR/other"
  git init -q "$CLAUDE_PROJECT_DIR"
  EDITED="$CLAUDE_PROJECT_DIR/edited file.js"
  printf 'unformatted\n' >"$EDITED"
  printf 'untouched\n' >"$CLAUDE_PROJECT_DIR/untouched.js"
  cat >"$CLAUDE_PROJECT_DIR/node_modules/.bin/ultracite" <<'PY'
#!/usr/bin/env -S python3 -I
import json, os, pathlib, sys
pathlib.Path(os.environ["CALL_LOG"]).write_text(json.dumps({"args": sys.argv[1:], "cwd": os.getcwd(), "stdin": sys.stdin.read()}))
assert len(sys.argv) == 3 and sys.argv[1] == "fix"
pathlib.Path(sys.argv[2]).write_text("formatted\n")
PY
  chmod +x "$CLAUDE_PROJECT_DIR/node_modules/.bin/ultracite"
  cd "$BATS_TEST_TMPDIR/other" || return
}

hook() {
  jq -nc --arg file "$1" --arg tool "${2:-Edit}" \
    '{hook_event_name:"PostToolUse",tool_name:$tool,tool_input:{file_path:$file}}' | "$HOOK"
}

@test "別の cwd からも project の編集ファイル1件だけを整形する" {
  run hook "$EDITED"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  [ "$(cat "$EDITED")" = formatted ]
  [ "$(cat "$CLAUDE_PROJECT_DIR/untouched.js")" = untouched ]
  jq -e --arg file "$EDITED" --arg project "$CLAUDE_PROJECT_DIR" \
    '.args == ["fix", $file] and .cwd == $project and .stdin == ""' "$CALL_LOG"
}

@test "解消途中のコンフリクト記号を含むファイルは整形しない" {
  local marker
  for marker in '<<<<<<< HEAD' '||||||| base' '=======' '>>>>>>> topic'; do
    printf '%s\n' "$marker" >"$EDITED"
    run hook "$EDITED"
    [ "$status" -eq 0 ]
    [ "$(cat "$EDITED")" = "$marker" ]
    [ ! -e "$CALL_LOG" ]
  done
}

@test "merge 中は競合記号のないファイルも整形しない" {
  touch "$CLAUDE_PROJECT_DIR/.git/MERGE_HEAD"
  run hook "$EDITED"
  [ "$status" -eq 0 ]
  [ "$(cat "$EDITED")" = unformatted ]
  [ ! -e "$CALL_LOG" ]
}

@test "rebase の両 backend は整形しない" {
  mkdir "$CLAUDE_PROJECT_DIR/.git/rebase-merge"
  run hook "$EDITED"
  [ "$status" -eq 0 ]
  [ ! -e "$CALL_LOG" ]
  mv "$CLAUDE_PROJECT_DIR/.git/rebase-merge" "$CLAUDE_PROJECT_DIR/.git/rebase-apply"
  run hook "$EDITED"
  [ "$status" -eq 0 ]
  [ "$(cat "$EDITED")" = unformatted ]
  [ ! -e "$CALL_LOG" ]
}

@test "linked worktree は自身の Git dir で merge 状態を判定する" {
  git -C "$CLAUDE_PROJECT_DIR" -c user.name=Test -c user.email=test@example.invalid commit -qm baseline --allow-empty
  local linked="$BATS_TEST_TMPDIR/linked worktree" git_dir edited event
  git -C "$CLAUDE_PROJECT_DIR" worktree add -q --detach "$linked" HEAD
  mkdir -p "$linked/node_modules/.bin"
  cp -p "$CLAUDE_PROJECT_DIR/node_modules/.bin/ultracite" "$linked/node_modules/.bin/ultracite"
  edited="$linked/edited.js"
  event=$(jq -nc --arg file "$edited" '{hook_event_name:"PostToolUse",tool_name:"Edit",tool_input:{file_path:$file}}')
  printf 'unformatted\n' >"$edited"
  touch "$CLAUDE_PROJECT_DIR/.git/MERGE_HEAD"
  run env CLAUDE_PROJECT_DIR="$linked" "$HOOK" <<<"$event"
  [ "$status" -eq 0 ]
  [ "$(cat "$edited")" = formatted ]
  mv "$CALL_LOG" "$BATS_TEST_TMPDIR/previous-call.json"
  printf 'unformatted\n' >"$edited"
  git_dir=$(git -C "$linked" rev-parse --absolute-git-dir)
  mkdir "$git_dir/rebase-merge"
  run env CLAUDE_PROJECT_DIR="$linked" "$HOOK" <<<"$event"
  [ "$status" -eq 0 ]
  [ "$(cat "$edited")" = unformatted ]
  [ ! -e "$CALL_LOG" ]
}

@test "project 範囲外・同じ接頭辞の隣接 directory・外向き symlink は整形しない" {
  local outside="$BATS_TEST_TMPDIR/other/scratch.js" path
  printf 'outside\n' >"$outside"
  mkdir "$CLAUDE_PROJECT_DIR-extra"
  printf 'outside\n' >"$CLAUDE_PROJECT_DIR-extra/sibling.js"
  ln -s "$outside" "$CLAUDE_PROJECT_DIR/link.js"
  for path in "$outside" "$CLAUDE_PROJECT_DIR-extra/sibling.js" "$CLAUDE_PROJECT_DIR/link.js"; do
    run hook "$path"
    [ "$status" -eq 0 ]
    [ ! -e "$CALL_LOG" ]
  done
  [ "$(cat "$outside")" = outside ]
  [ "$(cat "$CLAUDE_PROJECT_DIR-extra/sibling.js")" = outside ]
}

@test "不正入力・対象なし・相対パス・別イベントは全体整形へ fallback しない" {
  local event path
  for event in '' 'not json' '[]' 'null' '{}' \
    '{"hook_event_name":"PostToolUse","tool_name":"Edit","tool_input":null}' \
    '{"hook_event_name":"PostToolUse","tool_name":"Edit","tool_input":{"file_path":123}}'; do
    run "$HOOK" <<<"$event"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
    [ ! -e "$CALL_LOG" ]
  done
  for path in '' 'edited.js' "$CLAUDE_PROJECT_DIR/missing.js" "$CLAUDE_PROJECT_DIR"; do
    run hook "$path"
    [ "$status" -eq 0 ]
    [ ! -e "$CALL_LOG" ]
  done
  run hook "$EDITED" Read
  [ "$status" -eq 0 ]
  [ ! -e "$CALL_LOG" ]
  run "$HOOK" <<<"$(jq -nc --arg file "$EDITED" '{hook_event_name:"PreToolUse",tool_name:"Edit",tool_input:{file_path:$file}}')"
  [ "$status" -eq 0 ]
  [ ! -e "$CALL_LOG" ]
  run env -u CLAUDE_PROJECT_DIR "$HOOK" <<<"$(jq -nc --arg file "$EDITED" '{hook_event_name:"PostToolUse",tool_name:"Edit",tool_input:{file_path:$file}}')"
  [ "$status" -eq 0 ]
  [ ! -e "$CALL_LOG" ]
}

@test "Write の空白・メタ文字入りファイル名は単一引数として渡す" {
  local file="$CLAUDE_PROJECT_DIR/-edited \$(touch injected).js"
  mv "$EDITED" "$file"
  run hook "$file" Write
  [ "$status" -eq 0 ]
  [ "$(cat "$file")" = formatted ]
  jq -e --arg file "$file" '.args == ["fix", $file]' "$CALL_LOG"
  [ ! -e "$CLAUDE_PROJECT_DIR/injected" ]
}

@test "local CLI がなければ取得せず、整形失敗も編集を止めない" {
  mv "$CLAUDE_PROJECT_DIR/node_modules/.bin/ultracite" "$CLAUDE_PROJECT_DIR/node_modules/.bin/ultracite.saved"
  run hook "$EDITED"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  [ "$(cat "$EDITED")" = unformatted ]
  printf '#!/bin/sh\nprintf "formatter failed\\n" >&2\nexit 17\n' >"$CLAUDE_PROJECT_DIR/node_modules/.bin/ultracite"
  chmod +x "$CLAUDE_PROJECT_DIR/node_modules/.bin/ultracite"
  run hook "$EDITED"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  [ "$(cat "$EDITED")" = unformatted ]
}

@test "Git 状態を検査できない場合は整形しない" {
  printf '#!/bin/sh\nexit 1\n' >"$CLAUDE_PROJECT_DIR/node_modules/.bin/git"
  chmod +x "$CLAUDE_PROJECT_DIR/node_modules/.bin/git"
  export PATH="$CLAUDE_PROJECT_DIR/node_modules/.bin:$PATH"
  run hook "$EDITED"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  [ "$(cat "$EDITED")" = unformatted ]
  [ ! -e "$CALL_LOG" ]
  cat >"$CLAUDE_PROJECT_DIR/node_modules/.bin/git" <<'SH'
#!/bin/sh
printf '%s\n' "$CALL_LOG"
SH
  printf 'not a directory\n' >"$CALL_LOG"
  run hook "$EDITED"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  [ "$(cat "$EDITED")" = unformatted ]
  [ "$(cat "$CALL_LOG")" = 'not a directory' ]
}
