#!/usr/bin/env bats

bats_require_minimum_version 1.5.0
load helpers/raw-codex

setup() { PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"; }
teardown() { raw_cleanup; }

@test "human validation keeps reviewed code, dummy secrets and output outside a concurrently editing raw Codex" {
	raw_fixture
	run python3 "$PROJECT_ROOT/tests/helpers/human-validation.py" "$RAW_BASE"
	raw_assert_status 0
	[[ "$output" == *'HUMAN_VALIDATION_SEPARATED_OK'* ]]
}
