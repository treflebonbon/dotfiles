#!/usr/bin/env bats
# local-skills/worktree-gc/scripts/worktree-gc-fanout.sh の
# home 幅広い fan-out ラッパー (ADR-0056) を検証する。

load 'test_helper'

readonly SRC="$BATS_TEST_DIRNAME/../local-skills/worktree-gc/scripts/worktree-gc-fanout.sh"

setup() {
  setup_test_env
}

extract_functions() {
  local file="$1"
  shift
  local name
  for name in "$@"; do
    extract_function "$file" "$name"
    echo
  done
}

# 純粋関数を隔離環境で呼び出す。is_dangling_worktree のような依存関係のある
# 関数は、呼び出し先の関数定義も一緒に extract する。
run_pure_function() {
  local fn="$1"
  shift
  local deps=("$fn")
  case "$fn" in
  is_dangling_worktree) deps+=(gitdir_target) ;;
  esac
  local quoted_args=() a
  for a in "$@"; do
    quoted_args+=("$(printf '%q' "$a")")
  done
  run /usr/bin/env -i \
    PATH="/usr/bin:/bin" \
    HOME="$BATS_TEST_TMPDIR/home" \
    /bin/bash -c "
      $(extract_functions "$SRC" "${deps[@]}")
      $fn ${quoted_args[*]}
    "
}

# stdin を読む純粋関数（skip_summary_and_header）用。呼び出し側が heredoc で
# stdin を渡す。
run_pure_function_stdin() {
  local fn="$1"
  run /usr/bin/env -i \
    PATH="/usr/bin:/bin" \
    HOME="$BATS_TEST_TMPDIR/home" \
    /bin/bash -c "
      $(extract_functions "$SRC" "$fn")
      $fn
    "
}

make_ghq_repo() {
  local repo="$1"
  mkdir -p "$repo"
  git -C "$repo" init -q -b main
  git -C "$repo" config user.email test@example.com
  git -C "$repo" config user.name test
  git -C "$repo" commit -q --allow-empty -m init
}

age_dir() {
  touch -d '2001-09-09' "$1"
}

# --- repo_roots_for -----------------------------------------------------

@test "repo_roots_for: 既定rootsに herdr/orca の basename パスを追加する" {
  run_pure_function repo_roots_for \
    "/home/u/ghq/github.com/o/myrepo" "/home/u/.herdr/worktrees" \
    "/home/u/orca/workspaces" ".claude/worktrees,.worktrees"
  assert_success
  assert_output ".claude/worktrees,.worktrees,/home/u/.herdr/worktrees/myrepo,/home/u/orca/workspaces/myrepo"
}

# --- remaining_budget -----------------------------------------------------

@test "remaining_budget: cap未満なら差分を返す" {
  run_pure_function remaining_budget 50 10
  assert_success
  assert_output "40"
}

@test "remaining_budget: usedがcapを超えても0未満にはしない" {
  run_pure_function remaining_budget 50 999
  assert_success
  assert_output "0"
}

# --- gitdir_target / is_dangling_worktree ----------------------------------

@test "gitdir_target: worktree pointer file から絶対パスをそのまま返す" {
  mkdir -p "$BATS_TEST_TMPDIR/wt"
  echo "gitdir: /somewhere/.git/worktrees/wt" >"$BATS_TEST_TMPDIR/wt/.git"
  run_pure_function gitdir_target "$BATS_TEST_TMPDIR/wt"
  assert_success
  assert_output "/somewhere/.git/worktrees/wt"
}

@test "gitdir_target: 相対パスは worktree dir 基準で解決する" {
  mkdir -p "$BATS_TEST_TMPDIR/wt"
  echo "gitdir: ../elsewhere" >"$BATS_TEST_TMPDIR/wt/.git"
  run_pure_function gitdir_target "$BATS_TEST_TMPDIR/wt"
  assert_success
  assert_output "$BATS_TEST_TMPDIR/wt/../elsewhere"
}

@test "gitdir_target: .git が実ディレクトリ(通常clone)なら失敗する" {
  mkdir -p "$BATS_TEST_TMPDIR/repo/.git"
  run_pure_function gitdir_target "$BATS_TEST_TMPDIR/repo"
  assert_failure
}

@test "gitdir_target: .git が存在しなければ失敗する" {
  mkdir -p "$BATS_TEST_TMPDIR/plain"
  run_pure_function gitdir_target "$BATS_TEST_TMPDIR/plain"
  assert_failure
}

@test "is_dangling_worktree: gitdir参照先が存在すれば dangling ではない" {
  mkdir -p "$BATS_TEST_TMPDIR/parent/.git/worktrees/wt" "$BATS_TEST_TMPDIR/wt"
  echo "gitdir: $BATS_TEST_TMPDIR/parent/.git/worktrees/wt" >"$BATS_TEST_TMPDIR/wt/.git"
  run_pure_function is_dangling_worktree "$BATS_TEST_TMPDIR/wt"
  assert_failure
}

@test "is_dangling_worktree: gitdir参照先が消えていれば dangling と判定する" {
  mkdir -p "$BATS_TEST_TMPDIR/wt"
  echo "gitdir: $BATS_TEST_TMPDIR/parent-gone/.git/worktrees/wt" >"$BATS_TEST_TMPDIR/wt/.git"
  run_pure_function is_dangling_worktree "$BATS_TEST_TMPDIR/wt"
  assert_success
}

@test "is_dangling_worktree: 通常clone(.gitが実ディレクトリ)は dangling 扱いしない" {
  mkdir -p "$BATS_TEST_TMPDIR/repo/.git"
  run_pure_function is_dangling_worktree "$BATS_TEST_TMPDIR/repo"
  assert_failure
}

# --- skip_summary_and_header ------------------------------------------------

@test "skip_summary_and_header: summary行とヘッダ行を取り除きデータ行だけ残す" {
  run_pure_function_stdin skip_summary_and_header <<'EOF'
summary total=2 in_root=1 out_of_root=1 candidates=1 keep_main=0 keep_self_session=0 keep_young=0 keep_dirty=0 keep_detached=0 keep_unique=0 keep_open_pr=0 keep_other=0 keep_dirty_stale=0
decision	reason	scope	branch	path
remove-candidate	clean-safe	in-root	feature-x	/repo/.worktrees/feature-x
keep	out-of-root	out-of-root	-	/other/place
EOF
  assert_success
  [ "${#lines[@]}" -eq 2 ]
  assert_line --index 0 "remove-candidate	clean-safe	in-root	feature-x	/repo/.worktrees/feature-x"
  assert_line --index 1 "keep	out-of-root	out-of-root	-	/other/place"
}

# --- is_busy_dir -----------------------------------------------------------

@test "is_busy_dir: cwdが対象ディレクトリ配下のプロセスがあれば検出する" {
  local dir="$BATS_TEST_TMPDIR/busy"
  mkdir -p "$dir"
  (
    cd "$dir" || exit 1
    exec sleep 30
  ) &
  local pid=$!
  for _ in $(seq 1 50); do
    if [ "$(readlink -f "/proc/$pid/cwd" 2>/dev/null)" = "$(readlink -f "$dir")" ]; then
      break
    fi
    sleep 0.05
  done
  run_pure_function is_busy_dir "$dir"
  kill "$pid" 2>/dev/null || true
  wait "$pid" 2>/dev/null || true
  assert_success
}

@test "is_busy_dir: cwdが対象外なら検出しない" {
  local dir="$BATS_TEST_TMPDIR/idle"
  mkdir -p "$dir"
  run_pure_function is_busy_dir "$dir"
  assert_failure
}

# --- find_ghq_repos / find_worktree_dirs ------------------------------------

@test "find_ghq_repos: 実clone(.gitが実ディレクトリ)だけを列挙する" {
  local root="$BATS_TEST_TMPDIR/ghq"
  mkdir -p "$root/host/org/real-repo/.git"
  mkdir -p "$root/host/org/a-worktree"
  echo "gitdir: /elsewhere" >"$root/host/org/a-worktree/.git"
  run_pure_function find_ghq_repos "$root"
  assert_success
  assert_line "$root/host/org/real-repo"
  refute_line "$root/host/org/a-worktree"
}

@test "find_ghq_repos: rootが存在しなければ何も出力しない" {
  run_pure_function find_ghq_repos "$BATS_TEST_TMPDIR/does-not-exist"
  assert_success
  assert_output ""
}

@test "find_worktree_dirs: <repo>/<name> の2階層リーフを列挙する" {
  local root="$BATS_TEST_TMPDIR/herdr"
  mkdir -p "$root/dotfiles/worktree-a" "$root/dotfiles/worktree-b" "$root/other-repo/wt"
  run_pure_function find_worktree_dirs "$root"
  assert_success
  assert_line "$root/dotfiles/worktree-a"
  assert_line "$root/dotfiles/worktree-b"
  assert_line "$root/other-repo/wt"
}

@test "find_worktree_dirs: 空の1階層ディレクトリ(.orca-preparing相当)は何も出さない" {
  local root="$BATS_TEST_TMPDIR/orca"
  mkdir -p "$root/.orca-preparing"
  run_pure_function find_worktree_dirs "$root"
  assert_success
  assert_output ""
}

# --- 統合テスト（実際の git repo / worktree を使う） -----------------------

@test "統合: --diagnose は他repoのstale worktreeとdangling worktreeを両方、正しいsourceで報告する" {
  local ghq_root="$BATS_TEST_TMPDIR/ghq"
  local herdr="$BATS_TEST_TMPDIR/herdr"
  local orca="$BATS_TEST_TMPDIR/orca"
  local repo="$ghq_root/host/org/myrepo"
  make_ghq_repo "$repo"
  git -C "$repo" worktree add -q -b feature-x "$herdr/myrepo/feature-x"
  age_dir "$herdr/myrepo/feature-x"

  mkdir -p "$orca/otherproj/gone-parent"
  echo "gitdir: $BATS_TEST_TMPDIR/vanished/.git/worktrees/gone-parent" >"$orca/otherproj/gone-parent/.git"
  age_dir "$orca/otherproj/gone-parent"

  run env WORKTREE_GC_PROTECT_OPEN_PR=0 bash "$SRC" --diagnose \
    --ghq-root "$ghq_root" --herdr-root "$herdr" --orca-root "$orca" --age-days 7
  assert_success

  local repo_row dangling_row
  repo_row=$(printf '%s\n' "$output" | awk -F'\t' -v p="$herdr/myrepo/feature-x" '$5==p')
  dangling_row=$(printf '%s\n' "$output" | awk -F'\t' -v p="$orca/otherproj/gone-parent" '$5==p')
  [ -n "$repo_row" ]
  [ -n "$dangling_row" ]
  [ "${repo_row%%$'\t'*}" = "repo" ]
  [ "${dangling_row%%$'\t'*}" = "dangling" ]
}

@test "統合: --herdr-root がsymlink経由でも登録済みworktreeを孤児と誤認識しない(symlink正規化回帰テスト, PR#281レビュー)" {
  local ghq_root="$BATS_TEST_TMPDIR/ghq"
  local herdr_real="$BATS_TEST_TMPDIR/herdr_real"
  local herdr_link="$BATS_TEST_TMPDIR/herdr_link"
  local orca="$BATS_TEST_TMPDIR/orca"
  local repo="$ghq_root/host/org/myrepo"
  make_ghq_repo "$repo"
  mkdir -p "$herdr_real"
  ln -s "$herdr_real" "$herdr_link"
  git -C "$repo" worktree add -q -b feature-x "$herdr_link/myrepo/feature-x"
  age_dir "$herdr_real/myrepo/feature-x"
  # dirty にしておく: 誤って「孤児」判定された場合、orphan削除はage判定のみで
  # dirtyガードが効かないため実際に削除されてしまい、正規化の有無で結果が
  # 分かれる。
  echo dirty >"$herdr_real/myrepo/feature-x/untracked.txt"

  run env WORKTREE_GC_PROTECT_OPEN_PR=0 bash "$SRC" --apply \
    --ghq-root "$ghq_root" --herdr-root "$herdr_link" --orca-root "$orca" --age-days 7

  assert_success
  [ -d "$herdr_real/myrepo/feature-x" ]
}

@test "統合: ghq外の生きた親を持つ同名basenameのworktreeがあれば外部rootを無効化し誤削除しない(PR#281レビュー)" {
  local ghq_root="$BATS_TEST_TMPDIR/ghq"
  local herdr="$BATS_TEST_TMPDIR/herdr"
  local orca="$BATS_TEST_TMPDIR/orca"
  local repo="$ghq_root/host/org/samename"
  local foreign_repo="$BATS_TEST_TMPDIR/foreign/samename"
  make_ghq_repo "$repo"
  make_ghq_repo "$foreign_repo"

  git -C "$repo" worktree add -q -b own-feature "$herdr/samename/own-feature"
  age_dir "$herdr/samename/own-feature"

  # basenameは同じ "samename" だが ghq 配下ではない別の生きたリポジトリが、
  # 同じ herdr ディレクトリ配下に自分の worktree を持っている(dirty)。
  git -C "$foreign_repo" worktree add -q -b foreign-feature "$herdr/samename/foreign-feature"
  age_dir "$herdr/samename/foreign-feature"
  echo dirty >"$herdr/samename/foreign-feature/untracked.txt"

  run env WORKTREE_GC_PROTECT_OPEN_PR=0 bash "$SRC" --apply \
    --ghq-root "$ghq_root" --herdr-root "$herdr" --orca-root "$orca" --age-days 7

  assert_success
  assert_output --partial "foreign worktree found under a same-named external root"
  # 外部root全体を無効化するため、ghq発見リポジトリ自身のstale worktreeも
  # このラウンドでは削除されない(安全側の道連れ保護)。
  [ -d "$herdr/samename/own-feature" ]
  [ -d "$herdr/samename/foreign-feature" ]
}

@test "統合: 稼働中プロセスが無ければ --apply は stale worktree と dangling worktree を削除する" {
  local ghq_root="$BATS_TEST_TMPDIR/ghq"
  local herdr="$BATS_TEST_TMPDIR/herdr"
  local orca="$BATS_TEST_TMPDIR/orca"
  local repo="$ghq_root/host/org/myrepo"
  make_ghq_repo "$repo"
  git -C "$repo" worktree add -q -b feature-x "$herdr/myrepo/feature-x"
  age_dir "$herdr/myrepo/feature-x"

  mkdir -p "$orca/otherproj/gone-parent"
  echo "gitdir: $BATS_TEST_TMPDIR/vanished/.git/worktrees/gone-parent" >"$orca/otherproj/gone-parent/.git"
  age_dir "$orca/otherproj/gone-parent"

  run env WORKTREE_GC_PROTECT_OPEN_PR=0 bash "$SRC" --apply \
    --ghq-root "$ghq_root" --herdr-root "$herdr" --orca-root "$orca" --age-days 7

  assert_success
  [ ! -d "$herdr/myrepo/feature-x" ]
  [ ! -d "$orca/otherproj/gone-parent" ]
  assert_output --partial "fanout done removed=2"
}

@test "統合: --max-removals 0 なら全体でも何も削除しない" {
  local ghq_root="$BATS_TEST_TMPDIR/ghq"
  local herdr="$BATS_TEST_TMPDIR/herdr"
  local orca="$BATS_TEST_TMPDIR/orca"
  local repo="$ghq_root/host/org/myrepo"
  make_ghq_repo "$repo"
  git -C "$repo" worktree add -q -b feature-x "$herdr/myrepo/feature-x"
  age_dir "$herdr/myrepo/feature-x"

  mkdir -p "$orca/otherproj/gone-parent"
  echo "gitdir: $BATS_TEST_TMPDIR/vanished/.git/worktrees/gone-parent" >"$orca/otherproj/gone-parent/.git"
  age_dir "$orca/otherproj/gone-parent"

  run env WORKTREE_GC_PROTECT_OPEN_PR=0 bash "$SRC" --apply --max-removals 0 \
    --ghq-root "$ghq_root" --herdr-root "$herdr" --orca-root "$orca" --age-days 7

  assert_success
  [ -d "$herdr/myrepo/feature-x" ]
  [ -d "$orca/otherproj/gone-parent" ]
  assert_output --partial "fanout done removed=0"
}

@test "is_older_than_days: GNU stat で古いパスを古いと判定する" {
  stub_real_cmd stat
  stub_real_cmd date
  local old_path="$BATS_TEST_TMPDIR/old-dir"
  mkdir -p "$old_path"
  touch -d '2001-09-09' "$old_path"
  run /usr/bin/env -i \
    PATH="$TEST_BIN_DIR:/usr/bin:/bin" \
    TEST_LOG="$TEST_LOG" \
    /bin/bash -c "
      $(extract_function "$SRC" is_older_than_days)
      is_older_than_days '$old_path' 7
    "
  assert_success
}

@test "is_older_than_days: 作成直後のパスは古いと判定しない" {
  local fresh_path="$BATS_TEST_TMPDIR/fresh-dir"
  mkdir -p "$fresh_path"
  run_pure_function is_older_than_days "$fresh_path" 7
  assert_failure
}

@test "is_busy_dir: 候補パスがsymlink経由でも、実体のcwdを検出する(fail-open回帰テスト)" {
  mkdir -p "$BATS_TEST_TMPDIR/real/wt"
  ln -s "$BATS_TEST_TMPDIR/real" "$BATS_TEST_TMPDIR/link"
  (
    cd "$BATS_TEST_TMPDIR/real/wt" || exit 1
    exec sleep 30
  ) &
  local pid=$!
  for _ in $(seq 1 50); do
    if [ "$(readlink -f "/proc/$pid/cwd" 2>/dev/null)" = "$(readlink -f "$BATS_TEST_TMPDIR/real/wt")" ]; then
      break
    fi
    sleep 0.05
  done
  # symlink 経由の(未解決の)パスを渡しても検出できなければならない。
  run_pure_function is_busy_dir "$BATS_TEST_TMPDIR/link/wt"
  kill "$pid" 2>/dev/null || true
  wait "$pid" 2>/dev/null || true
  assert_success
}

@test "統合: basenameが衝突する2repoは herdr 外部rootの付与を無効化し警告する" {
  local ghq_root="$BATS_TEST_TMPDIR/ghq"
  local herdr="$BATS_TEST_TMPDIR/herdr"
  local orca="$BATS_TEST_TMPDIR/orca"
  local repo_a="$ghq_root/host/org-a/myrepo"
  local repo_b="$ghq_root/host/org-b/myrepo"
  make_ghq_repo "$repo_a"
  make_ghq_repo "$repo_b"
  git -C "$repo_a" worktree add -q -b feature-a "$herdr/myrepo/from-a"
  age_dir "$herdr/myrepo/from-a"

  run env WORKTREE_GC_PROTECT_OPEN_PR=0 bash "$SRC" --diagnose \
    --ghq-root "$ghq_root" --herdr-root "$herdr" --orca-root "$orca" --age-days 7
  assert_success
  assert_output --partial "basename collision, external roots disabled for 'myrepo'"
  refute_output --partial "$herdr/myrepo/from-a"
}

@test "統合: --max-report を絞ってもプロセス検出ガードは全候補を見て保護する" {
  local ghq_root="$BATS_TEST_TMPDIR/ghq"
  local herdr="$BATS_TEST_TMPDIR/herdr"
  local orca="$BATS_TEST_TMPDIR/orca"
  local repo="$ghq_root/host/org/myrepo"
  make_ghq_repo "$repo"
  git -C "$repo" worktree add -q -b feature-x "$herdr/myrepo/feature-x"
  git -C "$repo" worktree add -q -b feature-y "$herdr/myrepo/feature-y"
  age_dir "$herdr/myrepo/feature-x"
  age_dir "$herdr/myrepo/feature-y"

  # feature-y (2件目に作成) を稼働中にする。--max-report 1 で先頭1件しか
  # 見えない実装であれば、feature-y のビジー状態を見逃して削除してしまう。
  (
    cd "$herdr/myrepo/feature-y" || exit 1
    exec sleep 30
  ) &
  local pid=$!
  for _ in $(seq 1 50); do
    if [ "$(readlink -f "/proc/$pid/cwd" 2>/dev/null)" = "$(readlink -f "$herdr/myrepo/feature-y")" ]; then
      break
    fi
    sleep 0.05
  done

  run env WORKTREE_GC_PROTECT_OPEN_PR=0 bash "$SRC" --apply --max-report 1 \
    --ghq-root "$ghq_root" --herdr-root "$herdr" --orca-root "$orca" --age-days 7

  kill "$pid" 2>/dev/null || true
  wait "$pid" 2>/dev/null || true

  assert_success
  [ -d "$herdr/myrepo/feature-x" ]
  [ -d "$herdr/myrepo/feature-y" ]
}

@test "統合: --diagnose は --max-report で表示を絞っても total_candidates で真の件数を報告する" {
  local ghq_root="$BATS_TEST_TMPDIR/ghq"
  local herdr="$BATS_TEST_TMPDIR/herdr"
  local orca="$BATS_TEST_TMPDIR/orca"
  local repo="$ghq_root/host/org/myrepo"
  make_ghq_repo "$repo"
  git -C "$repo" worktree add -q -b feature-x "$herdr/myrepo/feature-x"
  git -C "$repo" worktree add -q -b feature-y "$herdr/myrepo/feature-y"
  age_dir "$herdr/myrepo/feature-x"
  age_dir "$herdr/myrepo/feature-y"

  run env WORKTREE_GC_PROTECT_OPEN_PR=0 bash "$SRC" --diagnose --max-report 1 \
    --ghq-root "$ghq_root" --herdr-root "$herdr" --orca-root "$orca" --age-days 7
  assert_success
  assert_output --partial "total_candidates=2 shown=1"
  # ヘッダ行 + 1データ行だけが標準出力に乗る。
  local data_lines
  data_lines=$(printf '%s\n' "$output" | grep -c '^repo	')
  [ "$data_lines" -eq 1 ]
}

@test "統合: --max-removals は複数repoを跨いで累計され、上限で打ち切る" {
  local ghq_root="$BATS_TEST_TMPDIR/ghq"
  local herdr="$BATS_TEST_TMPDIR/herdr"
  local orca="$BATS_TEST_TMPDIR/orca"
  local repo1="$ghq_root/host/org/repo1"
  local repo2="$ghq_root/host/org/repo2"
  make_ghq_repo "$repo1"
  make_ghq_repo "$repo2"
  git -C "$repo1" worktree add -q -b feature-a "$herdr/repo1/feature-a"
  git -C "$repo2" worktree add -q -b feature-b "$herdr/repo2/feature-b"
  age_dir "$herdr/repo1/feature-a"
  age_dir "$herdr/repo2/feature-b"

  run env WORKTREE_GC_PROTECT_OPEN_PR=0 bash "$SRC" --apply --max-removals 1 \
    --ghq-root "$ghq_root" --herdr-root "$herdr" --orca-root "$orca" --age-days 7

  assert_success
  assert_output --partial "fanout done removed=1"
  local remaining=0
  [ -d "$herdr/repo1/feature-a" ] && remaining=$((remaining + 1))
  [ -d "$herdr/repo2/feature-b" ] && remaining=$((remaining + 1))
  [ "$remaining" -eq 1 ]
}

@test "統合: 稼働中プロセスがある候補を含むrepoは丸ごと保護し削除しない" {
  local ghq_root="$BATS_TEST_TMPDIR/ghq"
  local herdr="$BATS_TEST_TMPDIR/herdr"
  local orca="$BATS_TEST_TMPDIR/orca"
  local repo="$ghq_root/host/org/myrepo"
  make_ghq_repo "$repo"
  git -C "$repo" worktree add -q -b feature-x "$herdr/myrepo/feature-x"
  git -C "$repo" worktree add -q -b feature-y "$herdr/myrepo/feature-y"
  age_dir "$herdr/myrepo/feature-x"
  age_dir "$herdr/myrepo/feature-y"

  (
    cd "$herdr/myrepo/feature-y" || exit 1
    exec sleep 30
  ) &
  local pid=$!
  for _ in $(seq 1 50); do
    if [ "$(readlink -f "/proc/$pid/cwd" 2>/dev/null)" = "$(readlink -f "$herdr/myrepo/feature-y")" ]; then
      break
    fi
    sleep 0.05
  done

  run env WORKTREE_GC_PROTECT_OPEN_PR=0 bash "$SRC" --apply \
    --ghq-root "$ghq_root" --herdr-root "$herdr" --orca-root "$orca" --age-days 7

  kill "$pid" 2>/dev/null || true
  wait "$pid" 2>/dev/null || true

  assert_success
  [ -d "$herdr/myrepo/feature-x" ]
  [ -d "$herdr/myrepo/feature-y" ]
}
