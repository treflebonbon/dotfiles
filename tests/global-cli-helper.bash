render_global_cli() {
  local name="$1" destination="$2"
  local home="$BATS_TEST_TMPDIR/global-cli-home"
  local config="$BATS_TEST_TMPDIR/global-cli-chezmoi.yaml"
  mkdir -p "$home" "$(dirname "$destination")" "$BATS_TEST_TMPDIR/global-cli-state"
  printf '{}\n' >"$config"
  env HOME="$home" XDG_STATE_HOME="$BATS_TEST_TMPDIR/global-cli-state" \
    chezmoi --source "$PROJECT_ROOT" --destination "$home" --config "$config" \
    --persistent-state "$BATS_TEST_TMPDIR/global-cli-state.boltdb" \
    --cache "$BATS_TEST_TMPDIR/global-cli-cache" execute-template \
    --file "$PROJECT_ROOT/private_dot_local/bin/executable_${name}.tmpl" \
    >"$destination"
  chmod +x "$destination"
}
