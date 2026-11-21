#!/usr/bin/env bats

setup_file() {
  # 並列実行の別ファイルが先に作った場合も、次行で種類と所有者を確かめる。
  mkdir -m 700 /tmp/codex 2>/dev/null || :
  [ -d /tmp/codex ] && [ ! -L /tmp/codex ] && [ -O /tmp/codex ]
}

setup() {
  PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  SHARED_TMP="$(mktemp -d /tmp/codex/test.XXXXXX)"
  FIXTURE_HOME="$BATS_TEST_TMPDIR/home"
  STATE_HOME="$BATS_TEST_TMPDIR/state"
  WORKSPACE="$BATS_TEST_TMPDIR/workspace"
  SESSION_TMP="$BATS_TEST_TMPDIR/session-tmp"
  local plugin_rev legacy_rev
  plugin_rev="$(jq -r '.rev' "$PROJECT_ROOT/private_dot_config/nix-devshell/skills-plugin.json")"
  legacy_rev="$(jq -r '.revision' "$PROJECT_ROOT/.chezmoitemplates/local-skills-legacy.json")"
  mkdir -p "$FIXTURE_HOME/.codex" "$WORKSPACE" "$SESSION_TMP" \
    "$FIXTURE_HOME/.cache/treflebonbon-skills/marketplaces/$plugin_rev" \
    "$FIXTURE_HOME/.cache/treflebonbon-skills/checkouts/$plugin_rev" \
    "$FIXTURE_HOME/.config/nix-devshell" "$FIXTURE_HOME/.config/gh" \
    "$FIXTURE_HOME/.config/git" \
    "$FIXTURE_HOME/.local/bin" "$FIXTURE_HOME/runtime" \
    "$STATE_HOME/treflebonbon-skills/plugin-sync" \
    "$STATE_HOME/treflebonbon-skills/legacy/$legacy_rev"
  cp "$PROJECT_ROOT/private_dot_config/nix-devshell/skills-plugin.json" \
    "$FIXTURE_HOME/.config/nix-devshell/skills-plugin.json"
  printf '[user]\n\temail = fixture@example.invalid\n' >"$FIXTURE_HOME/.gitconfig"
  local mount_root
  for mount_root in \
    "$FIXTURE_HOME/.cache/treflebonbon-skills/marketplaces/$plugin_rev" \
    "$FIXTURE_HOME/.cache/treflebonbon-skills/checkouts/$plugin_rev" \
    "$FIXTURE_HOME/.config/gh" "$FIXTURE_HOME/.config/git" \
    "$FIXTURE_HOME/.local/bin" \
    "$STATE_HOME/treflebonbon-skills/plugin-sync" \
    "$STATE_HOME/treflebonbon-skills/legacy/$legacy_rev"; do
    : >"$mount_root/.env"
  done
  printf '{}\n' >"$STATE_HOME/treflebonbon-skills/plugin-sync/receipt.json"
  env HOME="$FIXTURE_HOME" XDG_STATE_HOME="$STATE_HOME" chezmoi --source "$PROJECT_ROOT" execute-template \
    -f "$PROJECT_ROOT/private_dot_config/codex/config.toml.tmpl" \
    >"$FIXTURE_HOME/.codex/config.toml"
}

teardown() {
  rm -rf -- "$SHARED_TMP" "${OUTSIDE_TMP:-$SHARED_TMP}" "${OTHER_SUITE:-$SHARED_TMP}"
}

codex_probe() {
  if [ "$(uname -s)" != Linux ]; then
    "$@"
    return
  fi
  # 他 suite の生成・撤去や unreadable fixture を Codex の glob scan に見せない。
  local -a namespace=(
    bwrap --unshare-user --die-with-parent --ro-bind / /
    --tmpfs /tmp --dir /tmp/codex --chmod 0700 /tmp/codex
    --bind "$BATS_TEST_TMPDIR" "$BATS_TEST_TMPDIR"
    --bind "$SHARED_TMP" "$SHARED_TMP"
    --dev /dev --proc /proc
  )
  if [[ -n "${OUTSIDE_TMP:-}" ]]; then
    namespace+=(--bind "$OUTSIDE_TMP" "$OUTSIDE_TMP")
  fi
  if [[ -n "${FIXTURE_MOUNT:-}" ]]; then
    namespace+=(--tmpfs /run --bind "$BATS_TEST_TMPDIR" "$FIXTURE_MOUNT")
  fi
  "${namespace[@]}" "$@"
}

@test "Codex tmp probes do not observe another suite's shared scratch" {
  [ "$(uname -s)" = Linux ] || skip "Linux の namespace 分離を確認する"
  OTHER_SUITE="$(mktemp -d /tmp/codex/another-suite.XXXXXX)"
  printf 'other suite\n' >"$OTHER_SUITE/public.txt"
  run codex_probe env HOME="$FIXTURE_HOME" CODEX_HOME="$FIXTURE_HOME/.codex" XDG_STATE_HOME="$STATE_HOME" TMPDIR="$SESSION_TMP" \
    codex sandbox -P dotfiles-secure -C "$WORKSPACE" -- sh -c '
      if test -e "$1"; then printf "other suite is visible\n" >&2; exit 1; fi
    ' _ "$OTHER_SUITE/public.txt"
  [ "$status" -eq 0 ] || printf '%s\n' "$output" >&3
  [ "$status" -eq 0 ]
  [ "$(cat "$OTHER_SUITE/public.txt")" = 'other suite' ]
}

@test "Codex shares /tmp/codex outside its session TMPDIR and denies other /tmp files" {
  OUTSIDE_TMP="$(mktemp -d /tmp/codex-outside.XXXXXX)"
  printf 'outside-public\n' >"$OUTSIDE_TMP/public.txt"
  printf 'original\n' >"$SHARED_TMP/shared.txt"

  run codex_probe env HOME="$FIXTURE_HOME" CODEX_HOME="$FIXTURE_HOME/.codex" XDG_STATE_HOME="$STATE_HOME" TMPDIR="$SESSION_TMP" \
    codex sandbox -P dotfiles-secure -C "$WORKSPACE" -- sh -c '
      set -eu
      test "$(cat "$1/shared.txt")" = original
      if cat "$2/public.txt" 2>/dev/null; then exit 1; fi
      if (printf overwritten >"$2/public.txt") 2>/dev/null; then exit 1; fi
      printf "updated\n" >"$1/shared.txt"
      printf "created\n" >"$1/new.txt"
      test "$(cat "$1/new.txt")" = created
      rm "$1/new.txt"
      test ! -e "$1/new.txt"
    ' _ "$SHARED_TMP" "$OUTSIDE_TMP"

  [ "$status" -eq 0 ] || printf '%s\n' "$output" >&3
  [ "$status" -eq 0 ]
  [ "$(cat "$SHARED_TMP/shared.txt")" = updated ]
  [ ! -e "$SHARED_TMP/new.txt" ]
  [ "$(cat "$OUTSIDE_TMP/public.txt")" = outside-public ]
}

@test "Codex daily sandbox reads linked Git metadata and protects secrets and temporary files" {
  [ "$(uname -s)" = Linux ] || skip "Git metadata と一時領域を別 mount で検査する"
  FIXTURE_MOUNT=/run/codex-daily-fixture
  OUTSIDE_TMP="$(mktemp -d /tmp/codex-outside.XXXXXX)"
  printf 'outside\n' >"$OUTSIDE_TMP/public.txt"

  run codex_probe bash -c '
    set -eu
    export HOME="$1/home" CODEX_HOME="$1/home/.codex" TMPDIR="$1/session-tmp"
    export GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=/dev/null
    repo="$HOME/ghq/github.com/example/repo"
    orca_workspace="$HOME/orca/workspaces/example/nested"
    workspace="$1/workspace"
    unreadable="$repo/tmp/generated/data/private"
    mkdir -p "$unreadable" "$orca_workspace" "$HOME/.codex-app"
    chmod 000 "$unreadable"
    trap "chmod 700 \"$unreadable\"" EXIT
    git init -q "$repo"
    git -C "$repo" -c user.name=Fixture -c user.email=fixture@example.invalid \
      commit -q --allow-empty -m fixture
    git -C "$repo" worktree add -qd "$workspace"
    expected_head="$(git -C "$repo" rev-parse HEAD)"
    for dir in "$repo" "$orca_workspace" "$workspace" "$2"; do
      printf "public\n" >"$dir/.env.example"
      printf "dummy-secret\n" >"$dir/.env"
    done
    printf "dummy-secret\n" >"$HOME/.config/gh/hosts.yml"
    printf "dummy-secret\n" >"$HOME/.codex-app/auth.json"

    profile="$(python3 -c "import sys,tomllib; print(tomllib.load(sys.stdin.buffer)[\"default_permissions\"])" \
      <"$CODEX_HOME/config.toml")"
    codex sandbox -P "$profile" -C "$workspace" -- bash -c "$4" _ \
      "$repo" "$orca_workspace" "$2" "$3" "$expected_head"
  ' _ "$FIXTURE_MOUNT" "$SHARED_TMP" "$OUTSIDE_TMP/public.txt" '
    set -eu
    git --no-optional-locks status --short --branch
    test "$(git rev-parse HEAD)" = "$5"
    if git branch unexpected-write >/dev/null 2>&1; then
      printf "Git metadata is writable\n" >&2
      exit 1
    fi
    for dir in "$1" "$2" "$PWD" "$3"; do
      test "$(cat "$dir/.env.example")" = public
      test "$(cat "$dir/.env" 2>/dev/null || true)" != dummy-secret
    done
    for path in "$HOME/.config/gh/hosts.yml" "$HOME/.codex-app/auth.json"; do
      test "$(cat "$path" 2>/dev/null || true)" != dummy-secret
    done
    test "$(cat "$4" 2>/dev/null || true)" != outside
    printf "shared\n" >"$3/round-trip"
    printf "session\n" >"$TMPDIR/round-trip"
    test "$(cat "$3/round-trip")" = shared
    test "$(cat "$TMPDIR/round-trip")" = session
  '
  [ "$status" -eq 0 ] || printf '%s\n' "$output" >&3
  [ "$status" -eq 0 ]
  [ "$(cat "$SHARED_TMP/round-trip")" = shared ]
  [ "$(cat "$SESSION_TMP/round-trip")" = session ]
}

@test "Codex protects sensitive /tmp/codex filenames while public examples remain usable" {
  mkdir "$SHARED_TMP/nested"
  local path
  local paths=(
    .env .env.local .envrc.local .env.example.local .environment
    nested/.env private.key certificate.pem credentials.json secrets.json
  )
  for path in "${paths[@]}"; do
    printf 'dummy-secret\n' >"$SHARED_TMP/$path"
  done

  for path in "${paths[@]}"; do
    run codex_probe env HOME="$FIXTURE_HOME" CODEX_HOME="$FIXTURE_HOME/.codex" XDG_STATE_HOME="$STATE_HOME" TMPDIR="$SESSION_TMP" \
      codex sandbox -P dotfiles-secure -C "$WORKSPACE" -- cat "$SHARED_TMP/$path"
    [ "$status" -ne 0 ]
    [[ "$output" != *dummy-secret* ]]

    run codex_probe env HOME="$FIXTURE_HOME" CODEX_HOME="$FIXTURE_HOME/.codex" XDG_STATE_HOME="$STATE_HOME" TMPDIR="$SESSION_TMP" \
      codex sandbox -P dotfiles-secure -C "$WORKSPACE" -- \
      sh -c 'printf overwritten >"$1"' _ "$SHARED_TMP/$path"
    [ "$status" -ne 0 ]
    [ "$(cat "$SHARED_TMP/$path")" = dummy-secret ]
  done

  for path in .envrc .env.example; do
    printf 'public\n' >"$SHARED_TMP/$path"
    run codex_probe env HOME="$FIXTURE_HOME" CODEX_HOME="$FIXTURE_HOME/.codex" XDG_STATE_HOME="$STATE_HOME" TMPDIR="$SESSION_TMP" \
      codex sandbox -P dotfiles-secure -C "$WORKSPACE" -- \
      sh -c 'set -eu; test "$(cat "$1")" = public; printf updated >"$1"' _ "$SHARED_TMP/$path"
    [ "$status" -eq 0 ] || printf '%s\n' "$output" >&3
    [ "$status" -eq 0 ]
    [ "$(cat "$SHARED_TMP/$path")" = updated ]
  done
}

session_start_command() {
  python3 - "$PROJECT_ROOT/private_dot_config/codex/hooks.json" "$1" <<'PYHOOK'
import json
import sys
from pathlib import Path
hooks = json.loads(Path(sys.argv[1]).read_text())
command = hooks["hooks"]["SessionStart"][0]["hooks"][0]["command"]
print(command.replace("/tmp/codex", sys.argv[2]))
PYHOOK
}

@test "Codex SessionStart creates a private shared directory and preserves existing files" {
  local shared="$BATS_TEST_TMPDIR/shared"
  local command
  command="$(session_start_command "$shared")"
  run sh -c "$command"
  [ "$status" -eq 0 ]
  [ -d "$shared" ]
  [ -z "$output" ]
  python3 - "$shared" <<'PYMODE'
import stat
import sys
from pathlib import Path
assert stat.S_IMODE(Path(sys.argv[1]).stat().st_mode) == 0o700
PYMODE
  printf kept >"$shared/public.txt"
  run sh -c "$command"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  [ "$(cat "$shared/public.txt")" = kept ]
}

@test "Codex SessionStart stops for a symlink or file at the shared directory path" {
  local target="$BATS_TEST_TMPDIR/target"
  local shared="$BATS_TEST_TMPDIR/shared"
  local command
  mkdir "$target"
  chmod 755 "$target"
  ln -s "$target" "$shared"
  command="$(session_start_command "$shared")"
  run sh -c "$command"
  [ "$status" -eq 0 ]
  [[ "$output" == *'"continue":false'* ]]
  [ -L "$shared" ]
  python3 - "$target" <<'PYMODE'
import stat
import sys
from pathlib import Path
assert stat.S_IMODE(Path(sys.argv[1]).stat().st_mode) == 0o755
PYMODE
  shared="$BATS_TEST_TMPDIR/file"
  printf kept >"$shared"
  command="$(session_start_command "$shared")"
  run sh -c "$command"
  [ "$status" -eq 0 ]
  [[ "$output" == *'"continue":false'* ]]
  [ "$(cat "$shared")" = kept ]
}

@test "Codex SessionStart rejects a raced symlink without changing its target" {
  local shared="$BATS_TEST_TMPDIR/shared"
  local target="$BATS_TEST_TMPDIR/target"
  local bin="$BATS_TEST_TMPDIR/bin"
  local command
  mkdir "$target" "$bin"
  chmod 755 "$target"
  printf '#!%s\n' "$(command -v python3)" >"$bin/mkdir"
  cat >>"$bin/mkdir" <<'PYRACE'
import os
from pathlib import Path
import sys

def inject_symlink():
    os.symlink(os.environ["RACE_TARGET"], os.environ["RACE_SHARED"])
    Path(os.environ["RACE_HIT"]).touch()

if Path(sys.argv[0]).name == "mkdir":
    inject_symlink()
    os.execv(os.environ["REAL_MKDIR"], ["mkdir", *sys.argv[1:]])
else:
    original_mkdir = os.mkdir
    def raced_mkdir(path, *args, **kwargs):
        inject_symlink()
        return original_mkdir(path, *args, **kwargs)
    os.mkdir = raced_mkdir
    exec(sys.argv[-1])
PYRACE
  chmod +x "$bin/mkdir"
  cp "$bin/mkdir" "$bin/python3"
  command="$(session_start_command "$shared")"
  run env PATH="$bin:$PATH" RACE_SHARED="$shared" RACE_TARGET="$target" \
    RACE_HIT="$BATS_TEST_TMPDIR/race-hit" REAL_MKDIR="$(command -v mkdir)" sh -c "$command"

  [ "$status" -eq 0 ]
  [ -f "$BATS_TEST_TMPDIR/race-hit" ]
  [[ "$output" == *'"continue":false'* ]]
  python3 - "$target" <<'PYMODE'
import stat
import sys
from pathlib import Path
assert stat.S_IMODE(Path(sys.argv[1]).stat().st_mode) == 0o755
PYMODE
}
