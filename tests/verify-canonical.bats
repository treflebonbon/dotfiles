#!/usr/bin/env bats

load 'test_helper'

setup() {
  setup_test_env
  local project_root
  project_root="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  local base="$BATS_TEST_TMPDIR/base"
  export SOURCE="$BATS_TEST_TMPDIR/worktree"
  mkdir -p "$base/scripts"
  cp "$project_root/scripts/test.sh" "$base/scripts/"
  if [[ -f "$project_root/scripts/verify-canonical.py" ]]; then
    cp "$project_root/scripts/verify-canonical.py" "$base/scripts/"
  fi
  printf 'tmp/\n' >"$base/.gitignore"
  printf 'initial\n' >"$base/tracked-file"
  ln -s tracked-file "$base/tracked-link"
  git init --quiet --initial-branch=main "$base"
  git -C "$base" add .
  git -C "$base" -c user.name=Fixture -c user.email=fixture@example.test commit --quiet -m fixture
  git -C "$base" worktree add --quiet -b task "$SOURCE"

  export IMPECCABLE_HOOK_RUNTIME="$BATS_TEST_TMPDIR/hook"
  export IMPECCABLE_BIN="$BATS_TEST_TMPDIR/impeccable"
  export TEST_PLAYWRIGHT_PACKAGE="$BATS_TEST_TMPDIR/playwright"
  mkdir -p "$TEST_PLAYWRIGHT_PACKAGE"/{bin,libexec,share/playwright-cli}
  local executable
  for executable in "$IMPECCABLE_HOOK_RUNTIME" "$IMPECCABLE_BIN" \
    "$TEST_PLAYWRIGHT_PACKAGE/bin/managed-chrome-owner" \
    "$TEST_PLAYWRIGHT_PACKAGE/libexec/playwright-runtime"; do
    printf '#!/bin/bash\nexit 0\n' >"$executable"
    chmod +x "$executable"
  done
  touch "$TEST_PLAYWRIGHT_PACKAGE/share/playwright-cli/"{browser-lock,playwright-runtime}.mjs

  export CANONICAL_FIXTURE_TAP="$BATS_TEST_TMPDIR/fixture.tap"
  cat >"$CANONICAL_FIXTURE_TAP" <<'TAP'
1..16
ok 1 materialized quiet Design Hook reports an immediate-tier finding on the edit
ok 2 materialized quiet Design Hook emits the full self-serve policy once per session
ok 3 materialized Design Hook self-serve ignore persists only a reasoned detector value
ok 4 materialized quiet Design Hook stays silent for clean, non-UI, sensitive, and generated files
ok 5 materialized quiet Design Hook defers non-immediate findings to the Stop deep pass and surfaces them once
ok 6 materialized quiet Design Hook emits native Codex Stop output for a turn-scoped deep-pass finding
ok 7 global materialized hooks check new projects without opt-in for both providers
ok 8 materialized Codex apply_patch checks a symlinked monorepo target and converges
ok 9 materialized hooks preserve project config and disposable cache ownership
ok 10 materialized quiet Design Hook Stop pass converges silently on a file with findings in both tiers
ok 11 materialized quiet Design Hook Stop pass stays silent for an untouched session and when re-entered
ok 12 materialized quiet Design Hook dedupes repeated findings and suppresses a new finding after the edit threshold
ok 13 Design Hook remains unwired for Antigravity, Cursor, and GitHub Copilot
ok 14 Playwright runtime keeps locks and fails closed across records and process failures
ok 15 distributed Playwright package protects the direct CLI and retains shared FDs
ok 16 optional # skip 未設定
TAP
  cat >"$TEST_BIN_DIR/lefthook" <<'SH'
#!/bin/bash
printf 'lefthook %s\n' "$*" >> "$TEST_LOG"
status=0
bash "$SOURCE/scripts/test.sh" || status=$?
if [[ ${CANONICAL_FIXTURE_MODE:-} == empty-runtime ]]; then
  directory=$(cat "$DOTFILES_TEST_RUN_RECEIPT")
  : > "$directory/environment"
elif [[ ${CANONICAL_FIXTURE_MODE:-} == foreign-receipt ]]; then
  directory="$SOURCE/tmp/test-run.foreign"
  mkdir -p "$directory"
  printf 'previous-receipt\n' > "$directory/canonical-receipt"
  printf '%s\n' "$directory" > "$DOTFILES_TEST_RUN_RECEIPT"
elif [[ ${CANONICAL_FIXTURE_MODE:-} == missing-receipt ]]; then
  mv "$DOTFILES_TEST_RUN_RECEIPT" "$DOTFILES_TEST_RUN_RECEIPT.saved"
elif [[ ${CANONICAL_FIXTURE_MODE:-} == exit-mismatch ]]; then
  exit 2
fi
exit "$status"
SH
  cat >"$TEST_BIN_DIR/bats" <<'SH'
#!/bin/bash
cat "$CANONICAL_FIXTURE_TAP"
case ${CANONICAL_FIXTURE_MODE:-} in
  source-change) printf 'changed\n' > "$SOURCE/tracked-file" ;;
  head-change) git -C "$SOURCE" -c user.name=Fixture -c user.email=fixture@example.test commit --quiet --allow-empty -m changed ;;
  runtime-change) printf '# changed\n' >> "$IMPECCABLE_BIN" ;;
  exit-mismatch) exit 1 ;;
esac
SH
  chmod +x "$TEST_BIN_DIR/lefthook" "$TEST_BIN_DIR/bats"
  stub_cmd bun
}

run_canonical() {
  run env PATH="$TEST_BIN_DIR:$PATH" python3 "$SOURCE/scripts/verify-canonical.py"
}

@test "canonical検証のhelpは全suiteを開始しない" {
  run env PATH="$TEST_BIN_DIR:$PATH" python3 "$SOURCE/scripts/verify-canonical.py" --help
  assert_success
  [ ! -s "$TEST_LOG" ]
}

@test "canonical検証は一度の全suiteの証拠を結び付け必須fixtureと既定skipを区別する" {
  run_canonical

  assert_success
  [ "$(grep -c '^lefthook run test$' "$TEST_LOG")" -eq 1 ]
  python3 -I - "$SOURCE" <<'PY'
import json, sys
from pathlib import Path

source = Path(sys.argv[1])
attempts = list((source / "tmp").glob("canonical-run.*"))
assert len(attempts) == 1
attempt = attempts[0]
result = json.loads((attempt / "result.json").read_text())
assert result["command_exit"] == result["exit_code"] == 0
assert result["tap"]["plan"] == 16
assert result["tap"]["pass"] == 15
assert result["tap"]["skip"] == 1
assert result["tap"]["fail"] == 0
assert len(result["tap"]["required"]) == 15
assert result["elapsed_seconds"] >= 0
assert result["errors"] == []
before = json.loads((attempt / "before.json").read_text())
after = json.loads((attempt / "after.json").read_text())
assert before == after
assert before["source"]["files"]["tracked-link"]["kind"] == "symlink"
runner = Path((attempt / "runner-path").read_text().removesuffix("\n"))
assert (runner / "tap.log").is_file()
assert (runner / "canonical-receipt").read_text() == str(attempt / "runner-path") + "\n"
assert "python3:" in result["runner_environment"]
PY
}

@test "canonical検証はrunnerの実行runtime記録が欠けた成功を拒否する" {
  export CANONICAL_FIXTURE_MODE=empty-runtime

  run_canonical

  assert_failure 1
  assert_output --partial "実行runtime"
}

@test "canonical検証は異なる失敗終了コードを証拠の不一致として記録する" {
  export CANONICAL_FIXTURE_MODE=exit-mismatch

  run_canonical

  assert_failure 2
  assert_output --partial "終了コードが不一致"
  python3 -I - "$SOURCE" <<'PY'
import json, sys
from pathlib import Path
attempt = next((Path(sys.argv[1]) / "tmp").glob("canonical-run.*"))
result = json.loads((attempt / "result.json").read_text())
assert result["runner_exit"] == 1 and result["command_exit"] == 2
assert result["exit_code"] == 2
assert result["errors"]
PY
}

@test "canonical検証は名前で必須fixtureの欠落・重複・skipを拒否する" {
  local original mode
  original=$(cat "$CANONICAL_FIXTURE_TAP")
  for mode in missing duplicate skip; do
    printf '%s\n' "$original" >"$CANONICAL_FIXTURE_TAP"
    python3 -I - "$CANONICAL_FIXTURE_TAP" "$mode" <<'PY'
import sys
from pathlib import Path

path, mode = Path(sys.argv[1]), sys.argv[2]
lines = path.read_text().splitlines()
if mode == "missing":
    lines[1] = "ok 1 unrelated fixture"
elif mode == "duplicate":
    lines[2] = "ok 2 materialized quiet Design Hook reports an immediate-tier finding on the edit"
else:
    lines[1] += " # skip 未準備"
path.write_text("\n".join(lines) + "\n")
PY
    run_canonical
    assert_failure 1
    assert_output --partial "必須fixture"
  done
  [ "$(grep -c '^lefthook run test$' "$TEST_LOG")" -eq 3 ]
}

@test "canonical検証はsourceの変更を検出して成功したBatsの証拠も保持する" {
  export CANONICAL_FIXTURE_MODE=source-change
  run_canonical
  assert_failure 1
  assert_output --partial "source/HEAD"
  python3 -I - "$SOURCE" <<'PY'
import json, sys
from pathlib import Path
attempt = next((Path(sys.argv[1]) / "tmp").glob("canonical-run.*"))
result = json.loads((attempt / "result.json").read_text())
assert result["command_exit"] == 0 and result["exit_code"] == 1
assert result["tap"]["pass"] == 15
assert (attempt / "before.json").read_bytes() != (attempt / "after.json").read_bytes()
PY
}

@test "canonical検証は内容が同じでも実行中のHEAD変更を拒否する" {
  export CANONICAL_FIXTURE_MODE=head-change
  run_canonical
  assert_failure 1
  assert_output --partial "source/HEAD"
}

@test "canonical検証はsource外にあるruntimeの変更も検出する" {
  export CANONICAL_FIXTURE_MODE=runtime-change
  run_canonical
  assert_failure 1
  assert_output --partial "runtimeの前後"
}

@test "canonical検証はdirtyなsourceと未準備runtimeでBatsを開始しない" {
  printf 'dirty\n' >"$SOURCE/tracked-file"
  run_canonical
  assert_failure 1
  assert_output --partial "clean"
  [ ! -s "$TEST_LOG" ]
  printf 'initial\n' >"$SOURCE/tracked-file"
  unset IMPECCABLE_BIN
  run_canonical
  assert_failure 1
  assert_output --partial "IMPECCABLE_BIN"
  [ ! -s "$TEST_LOG" ]
}

@test "canonical検証はprimary checkoutでBatsを開始しない" {
  run env PATH="$TEST_BIN_DIR:$PATH" python3 "$BATS_TEST_TMPDIR/base/scripts/verify-canonical.py"
  assert_failure 1
  assert_output --partial "linked task worktree"
  [ ! -s "$TEST_LOG" ]
}

@test "canonical検証は異なる実行のログ参照と受渡し欠落を拒否する" {
  local mode
  for mode in foreign-receipt missing-receipt; do
    export CANONICAL_FIXTURE_MODE="$mode"
    run_canonical
    assert_failure 1
  done
  [ "$(grep -c '^lefthook run test$' "$TEST_LOG")" -eq 2 ]
}

@test "canonical検証は中断を子へ伝え元ログと非0の結果を保存する" {
  export CANONICAL_SIGNAL_READY="$BATS_TEST_TMPDIR/command.pid"
  export CANONICAL_SIGNAL_HANDLED="$BATS_TEST_TMPDIR/command-stopped"
  cat >"$TEST_BIN_DIR/lefthook" <<'SH'
#!/bin/bash
trap 'touch "$CANONICAL_SIGNAL_HANDLED"; exit 0' TERM
printf '%s\n' "$$" > "$CANONICAL_SIGNAL_READY"
printf 'command-started\n'
while :; do sleep 0.05; done
SH
  run env PATH="$TEST_BIN_DIR:$PATH" python3 -I - "$SOURCE" <<'PY'
import json, os, signal, subprocess, sys, time
from pathlib import Path

source = Path(sys.argv[1])
ready = Path(os.environ["CANONICAL_SIGNAL_READY"])
handled = Path(os.environ["CANONICAL_SIGNAL_HANDLED"])
with (source.parent / "interrupted-output.log").open("wb") as output:
    entry = subprocess.Popen([sys.executable, str(source / "scripts/verify-canonical.py")],
        stdout=output, stderr=subprocess.STDOUT, start_new_session=True)
    forwarded = False
    try:
        deadline = time.monotonic() + 5
        while not ready.exists() and entry.poll() is None and time.monotonic() < deadline:
            time.sleep(0.01)
        assert ready.is_file(), "中断fixtureが開始しませんでした"
        entry.send_signal(signal.SIGTERM)
        status = entry.wait(timeout=5)
        forwarded = handled.is_file()
    finally:
        if entry.poll() is None:
            entry.kill()
            entry.wait()
        if ready.exists() and not handled.exists():
            try:
                os.kill(int(ready.read_text()), signal.SIGTERM)
            except ProcessLookupError:
                pass
    assert status == 143, status
    assert forwarded, "中断が子へ伝わりませんでした"
attempt = next((source / "tmp").glob("canonical-run.*"))
result = json.loads((attempt / "result.json").read_text())
assert result["command_exit"] == 0 and result["exit_code"] == 143
assert result["signal"] == 15
assert result["tap"] is None and result["errors"]
assert "command-started" in (attempt / "command.log").read_text()
PY
  assert_success
}
