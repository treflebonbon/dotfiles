#!/usr/bin/env bats

setup() {
  PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  SETTINGS_SOURCE="$PROJECT_ROOT/private_dot_claude/settings.json.tmpl"
  SETTINGS="$BATS_TEST_TMPDIR/settings.json"
  local config="$BATS_TEST_TMPDIR/chezmoi.yaml"
  mkdir -p "$BATS_TEST_TMPDIR/home"
  printf '{}\n' >"$config"
  env HOME="$BATS_TEST_TMPDIR/home" chezmoi --source "$PROJECT_ROOT" \
    --destination "$BATS_TEST_TMPDIR/home" --config "$config" \
    execute-template <"$SETTINGS_SOURCE" >"$SETTINGS"
}

@test "ponytail plugin is enabled" {
  run jq -r '.enabledPlugins["ponytail@ponytail"]' "$SETTINGS"
  [ "$status" -eq 0 ]
  [ "$output" = "true" ]
}

@test "ponytail marketplace source points at dietrichgebert/ponytail" {
  run jq -c '.extraKnownMarketplaces.ponytail.source' "$SETTINGS"
  [ "$status" -eq 0 ]
  [ "$output" = '{"source":"github","repo":"dietrichgebert/ponytail"}' ]
}

@test "validated skills plugin is enabled and uses the immutable pinned checkout" {
  local plugin_rev
  plugin_rev="$(jq -r '.rev' "$PROJECT_ROOT/private_dot_config/nix-devshell/skills-plugin.json")"

  run jq -r '.enabledPlugins["treflebonbon-skills@treflebonbon"]' "$SETTINGS"
  [ "$status" -eq 0 ]
  [ "$output" = "true" ]

  run jq -c '.extraKnownMarketplaces.treflebonbon.source' "$SETTINGS"
  [ "$status" -eq 0 ]
  [ "$output" = "{\"source\":\"directory\",\"path\":\"$BATS_TEST_TMPDIR/home/.cache/treflebonbon-skills/marketplaces/$plugin_rev\"}" ]
}
