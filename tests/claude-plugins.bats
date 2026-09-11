#!/usr/bin/env bats

setup() {
  PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  SETTINGS="$PROJECT_ROOT/private_dot_claude/settings.json.tmpl"
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
