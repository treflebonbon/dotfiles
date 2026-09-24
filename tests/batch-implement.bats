#!/usr/bin/env bats
# local-skills/batch-implement/scripts/compute-chains.sh の compute_chains が
# 「Blocked by」で連結した ticket 群を Ticket Chain (CONTEXT.md) へ正しく
# グルーピングし、blocker を先に並べる順序 (Kahn's algorithm) で出力するかを
# 検証する。

load 'test_helper'

readonly SRC="$BATS_TEST_DIRNAME/../local-skills/batch-implement/scripts/compute-chains.sh"

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

run_compute_chains() {
  run /usr/bin/env -i \
    PATH="/usr/bin:/bin" \
    HOME="$BATS_TEST_TMPDIR/home" \
    /bin/bash -c "
      set -euo pipefail
      $(extract_functions "$SRC" compute_chains find_root union ensure_node split_tsv_line)
      compute_chains
    "
}

@test "依存の無いticketはそれぞれ要素数1のchainになる" {
  run_compute_chains <<'EOF'
10
20
30
EOF
  assert_success
  assert_output --partial $'1\t1\t10'
  assert_output --partial $'2\t1\t20'
  assert_output --partial $'3\t1\t30'
}

@test "線形chainはblockerを先頭に並べる" {
  run_compute_chains <<'EOF'
A	B
B	C
C
EOF
  assert_success
  assert_output $'1\t1\tC\n1\t2\tB\n1\t3\tA'
}

@test "ひし形依存も両方のblockerの後に依存先が来る" {
  run_compute_chains <<'EOF'
D	B,C
B	A
C	A
A
EOF
  assert_success
  # A は必ず先頭、D は必ず末尾。B/C の前後関係はどちらでもよい。
  [[ "${lines[0]}" == $'1\t1\tA' ]]
  [[ "${lines[3]}" == $'1\t4\tD' ]]
  [[ "${lines[1]}" == $'1\t2\tB' || "${lines[1]}" == $'1\t2\tC' ]]
}

@test "バッチ外のblockerは既に解決済みとして無視される" {
  run_compute_chains <<'EOF'
40	999
EOF
  assert_success
  assert_output $'1\t1\t40'
}

@test "無関係な2つのchainは別のchain_idになる" {
  run_compute_chains <<'EOF'
A	B
B
X	Y
Y
EOF
  assert_success
  [[ "${lines[0]}" == $'1\t1\tB' ]]
  [[ "${lines[1]}" == $'1\t2\tA' ]]
  [[ "${lines[2]}" == $'2\t1\tY' ]]
  [[ "${lines[3]}" == $'2\t2\tX' ]]
}

@test "循環依存はエラーを報告して非0で終了する" {
  run_compute_chains <<'EOF'
1	2
2	1
EOF
  assert_failure
  assert_output --partial "cycle detected"
}

@test "openな外部blockerを持つticketはSKIPとして報告される" {
  run_compute_chains <<'EOF'
40		999
EOF
  assert_success
  assert_output $'SKIP\t40\texternal-open-blocker:999'
}

@test "openな外部blockerに依存するticketは連鎖的にSKIPされる" {
  run_compute_chains <<'EOF'
A
B	A
C		999
D	C
EOF
  assert_success
  assert_output --partial $'1\t1\tA'
  assert_output --partial $'1\t2\tB'
  assert_output --partial $'SKIP\tC\texternal-open-blocker:999'
  assert_output --partial $'SKIP\tD\tblocked-by-excluded:C'
}

@test "3列目が空でも従来どおり2列形式として解釈される" {
  run_compute_chains <<'EOF'
10
20	10
EOF
  assert_success
  assert_output $'1\t1\t10\n1\t2\t20'
}
