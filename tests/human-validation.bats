#!/usr/bin/env bats

bats_require_minimum_version 1.5.0
load helpers/raw-codex

setup() { PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"; }
teardown() { raw_cleanup; }

@test "raw Codex edits and tests with public fixtures while a human runs a fixed revision outside its namespace" {
  raw_fixture
  # Explicit inputs also work in the human's normal Nix build sandbox.
  python3 - "$RAW_BASE/work/flake.nix" <<'PY'
from pathlib import Path
import shutil, sys
bash = Path(shutil.which('bash')).resolve().parents[1]
utils = Path(shutil.which('cat')).resolve().parents[1]
Path(sys.argv[1]).write_text('''{
  outputs = { self }: let
    tool = path: builtins.appendContext path { ${path} = { path = true; }; };
    bash = tool "%s"; utils = tool "%s";
  in { devShells.x86_64-linux.default = builtins.derivation {
    name = "human-validation"; system = "x86_64-linux";
    builder = "${bash}/bin/bash"; args = [ "-c" "exit 0" ]; outputs = [ "out" ];
    PATH = "${bash}/bin:${utils}/bin"; PUBLIC_VAR = "normal";
    shellHook = "export HOOK_VAR=ready";
  }; };
}''' % (bash, utils))
PY
  cp "$PROJECT_ROOT/tests/fixtures/secret-isolation/human-reviewed.py" "$RAW_BASE/work/reviewed.py"
  cp "$PROJECT_ROOT/tests/fixtures/secret-isolation/human-boundary.py" "$RAW_BASE/work/task.py"
  printf 'public fixture\n' > "$RAW_BASE/work/fixture.txt"
  printf 'touch envrc-executed; exit 89\n' > "$RAW_BASE/work/.envrc"
  raw_admit flake.nix reviewed.py task.py fixture.txt .envrc
  run python3 "$PROJECT_ROOT/tests/helpers/human-validation.py" "$RAW_BASE" "$PROJECT_ROOT"
  raw_assert_status 0
  [[ "$output" == *HUMAN_VALIDATION_SEPARATED* ]]
}
