#!/usr/bin/env bats

bats_require_minimum_version 1.5.0

# 実 lefthook.yml を使い、hook と test ジョブが scripts/pre-push.sh へ正しく結線されていることだけを見る。
# 判定ロジックは tests/pre-push.bats が見る。

setup() {
  PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  REPO="$BATS_TEST_TMPDIR/repo"
  REMOTE="$BATS_TEST_TMPDIR/remote.git"
  CALLS="$BATS_TEST_TMPDIR/calls"
  BIN="$BATS_TEST_TMPDIR/bin"
  mkdir -p "$BIN"
  git init -q --bare "$REMOTE"
  git init -q "$REPO"
  cd "$REPO"
  mkdir scripts
  cp "$PROJECT_ROOT/lefthook.yml" lefthook.yml
  # 実処理は呼ばず、呼ばれた引数と stdin の ref だけを記録する。
  printf '#!/usr/bin/env bash\necho "pre-push ${1:-hook} $(cat)" >>"%s"\n' "$CALLS" >scripts/pre-push.sh
  printf '#!/usr/bin/env bash\necho "bun $*" >>"%s"\nexit "${BUN_STATUS:-0}"\n' "$CALLS" >"$BIN/bun"
  chmod +x scripts/pre-push.sh "$BIN/bun"
  git -c user.name=t -c user.email=t@example.com add -A
  git -c user.name=t -c user.email=t@example.com commit -q -m init
  git remote add origin "$REMOTE"
  : >"$CALLS"
}

@test "lefthook install creates a pre-push hook that passes the pushed refs to scripts/pre-push.sh" {
  run -0 lefthook install
  run -0 git push -q origin HEAD:refs/heads/topic
  [[ "$(cat "$CALLS")" == "pre-push hook HEAD $(git rev-parse HEAD) refs/heads/topic "* ]]
}

@test "the test job installs hooks, runs the Bats, then records the tested tree" {
  run -0 env PATH="$BIN:$PATH" lefthook run test --no-auto-install
  [ -f .git/hooks/pre-push ]
  [ "$(grep -c . "$CALLS")" -eq 2 ]
  [ "$(sed -n 1p "$CALLS")" = "bun run test" ]
  [ "$(sed -n 2p "$CALLS")" = "pre-push record " ]
}

@test "a failing test job does not record the tested tree" {
  BUN_STATUS=1 run -1 env PATH="$BIN:$PATH" lefthook run test --no-auto-install
  ! grep -q "pre-push record" "$CALLS"
}
