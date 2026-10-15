# HOME を書込み可能な /tmp の外へ置き、実際の home と同じ権限境界で検証する。
setup_file() {
  export CODEX_TEST_HOME_ROOT
  CODEX_TEST_HOME_ROOT="$(mktemp -d /var/tmp/codex-homes.XXXXXX)"
}

teardown_file() {
  rm -rf -- "$CODEX_TEST_HOME_ROOT"
}
