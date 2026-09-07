#!/usr/bin/env bats

setup() {
  PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  export XDG_CACHE_HOME="$BATS_TEST_TMPDIR/nix-cache"
}

evaluate_floor() {
  run nix eval --json --impure --no-write-lock-file \
    --option use-xdg-base-directories true \
    --file "$PROJECT_ROOT/tests/helpers/ai-quality-floor.nix" \
    --apply "floor: floor { tool = \"$1\"; metadata = $2; }"
}

@test "quality floor rejects Claude Code with missing version metadata and identifies it as unknown" {
  evaluate_floor claude-code '{ }'
  [ "$status" -ne 0 ]
  [[ "$output" == *'claude-code 不明'* ]]
  [[ "$output" == *'2.1.261'* ]]
}

@test "quality floor rejects Codex with missing version metadata and identifies it as unknown" {
  evaluate_floor codex '{ }'
  [ "$status" -ne 0 ]
  [[ "$output" == *'codex 不明'* ]]
  [[ "$output" == *'0.153.4'* ]]
}

@test "quality floor accepts the exact input packages at the approved floors" {
  evaluate_floor claude-code '{ version = "2.1.261"; }'
  [ "$status" -eq 0 ]
  jq -e '.version == "2.1.261" and .matchesInput' <<<"$output"

  evaluate_floor codex '{ version = "0.153.4"; }'
  [ "$status" -eq 0 ]
  jq -e '.version == "0.153.4" and .matchesInput' <<<"$output"
}

@test "quality floor accepts the exact input packages above the approved floors" {
  evaluate_floor claude-code '{ version = "2.1.262"; }'
  [ "$status" -eq 0 ]
  jq -e '.version == "2.1.262" and .matchesInput' <<<"$output"

  evaluate_floor codex '{ version = "0.153.5"; }'
  [ "$status" -eq 0 ]
  jq -e '.version == "0.153.5" and .matchesInput' <<<"$output"
}

@test "quality floor rejects null versions as unknown for each tool" {
  for tool in claude-code codex; do
    evaluate_floor "$tool" '{ version = null; }'
    [ "$status" -ne 0 ]
    [[ "$output" == *"$tool 不明"* ]]
  done
}

@test "quality floor rejects versions below approved floors with concise actionable diagnostics" {
  local tool candidate minimum diagnostic
  while read -r tool candidate minimum; do
    evaluate_floor "$tool" "{ version = \"$candidate\"; }"
    [ "$status" -ne 0 ]
    diagnostic="${output##*error: }"
    [[ "$diagnostic" == *"$tool $candidate"* ]]
    [[ "$diagnostic" == *"$minimum"* ]]
    [[ "$diagnostic" == *'採用理由:'* ]]
    [[ "$diagnostic" == *'docs/adr/'* ]]
    [[ "$diagnostic" == *'修復手順:'* ]]
    [[ "$diagnostic" == *'private_dot_config/nix-devshell/flake.nix'* ]]
    [ "$(wc -l <<<"$diagnostic")" -le 12 ]
  done <<'CASES'
claude-code 2.1.260 2.1.261
codex 0.153.3 0.153.4
CASES
}

@test "quality floor preserves each package selected from the actual snapshot" {
  for tool in claude-code codex; do
    evaluate_floor "$tool" null
    [ "$status" -eq 0 ]
    jq -e '.matchesInput and (.version | type == "string")' <<<"$output"
  done
}
