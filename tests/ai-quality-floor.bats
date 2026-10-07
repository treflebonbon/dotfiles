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
  [[ "$output" == *'2.1.289'* ]]
}

@test "quality floor rejects Codex with missing version metadata and identifies it as unknown" {
  evaluate_floor codex '{ }'
  [ "$status" -ne 0 ]
  [[ "$output" == *'codex 不明'* ]]
  [[ "$output" == *'0.159.1'* ]]
}

@test "quality floor accepts input packages at the approved floors" {
  evaluate_floor claude-code '{ version = "2.1.289"; }'
  [ "$status" -eq 0 ]
  jq -e '.version == "2.1.289" and .matchesSource' <<<"$output"

  evaluate_floor codex '{ version = "0.159.1"; }'
  [ "$status" -eq 0 ]
  jq -e '.version == "0.159.1" and .matchesSource' <<<"$output"
}

@test "quality floor accepts input packages above the approved floors" {
  evaluate_floor claude-code '{ version = "2.1.290"; }'
  [ "$status" -eq 0 ]
  jq -e '.version == "2.1.290" and .matchesSource' <<<"$output"

  evaluate_floor codex '{ version = "0.159.2"; }'
  [ "$status" -eq 0 ]
  jq -e '.version == "0.159.2" and .matchesSource' <<<"$output"
}

@test "quality floor rejects null versions as unknown for each tool" {
  for tool in claude-code codex; do
    evaluate_floor "$tool" '{ version = null; }'
    [ "$status" -ne 0 ]
    [[ "$output" == *"$tool 不明"* ]]
  done
}

@test "quality floor rejects versions below approved floors with concise actionable diagnostics" {
  local tool candidate minimum record diagnostic
  while read -r tool candidate minimum record; do
    evaluate_floor "$tool" "{ version = \"$candidate\"; }"
    [ "$status" -ne 0 ]
    diagnostic="${output##*error: }"
    [[ "$diagnostic" == *"$tool $candidate"* ]]
    [[ "$diagnostic" == *"$minimum"* ]]
    [[ "$diagnostic" == *'採用理由:'* ]]
    [[ "$diagnostic" == *"$record"* ]]
    [[ "$diagnostic" == *'修復手順:'* ]]
    [[ "$diagnostic" == *'private_dot_config/nix-devshell/flake.nix'* ]]
    [ "$(wc -l <<<"$diagnostic")" -le 12 ]
  done <<'CASES'
claude-code 2.1.288 2.1.289 docs/adr/0047-test-quality-floors-through-package-outputs.md
codex 0.158.0 0.159.1 docs/adr/0070-adopt-gpt-6-1-sol.md
CASES
}

@test "quality floor preserves each snapshot source and dependencies through local patches" {
  for tool in claude-code codex; do
    evaluate_floor "$tool" null
    [ "$status" -eq 0 ]
    jq -e '.matchesSource and (.version | type == "string")' <<<"$output"
  done
}

@test "Codex Rust build runs one job regardless of the Nix limit" {
  evaluate_floor codex null
  [ "$status" -eq 0 ]
  jq -r '.preBuild' <<<"$output" >"$BATS_TEST_TMPDIR/pre-build.sh"
  local cores
  for cores in 0 1 2 4 8 16; do
    run env NIX_BUILD_CORES="$cores" bash -eu -c '
      substituteInPlace() { :; }
      source "$1"
      test "$NIX_BUILD_CORES" -eq 1
    ' -- "$BATS_TEST_TMPDIR/pre-build.sh"
    [ "$status" -eq 0 ]
  done
}
