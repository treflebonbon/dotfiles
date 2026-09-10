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
import os, shutil, sys
bash = Path(shutil.which('bash')).resolve().parents[1]
utils = Path(shutil.which('cat')).resolve().parents[1]
python = Path(shutil.which('python3')).resolve().parents[1]
system = {'x86_64': 'x86_64-linux', 'aarch64': 'aarch64-linux'}[os.uname().machine]
Path(sys.argv[1]).write_text(r'''{
  outputs = { self }: let
    tool = path: builtins.appendContext path { ${path} = { path = true; }; };
    bash = tool "%s"; utils = tool "%s"; python = tool "%s";
  in { devShells.%s.default = builtins.derivation {
    name = "human-validation"; system = "%s";
    builder = "${bash}/bin/bash"; args = [ "-c" "exit 0" ]; outputs = [ "out" ];
    PATH = "${bash}/bin:${utils}/bin:${python}/bin"; PUBLIC_VAR = "normal";
    shellHook = "test -z \"$HUMAN_TOKEN$RAW_DUMMY_SECRET\" || return 71; export HOOK_VAR=ready";
  }; };
}''' % (bash, utils, python, system, system))
PY
  cp "$PROJECT_ROOT/tests/fixtures/secret-isolation/human-reviewed.py" "$RAW_BASE/work/reviewed.py"
  cp "$PROJECT_ROOT/tests/fixtures/secret-isolation/human-boundary.py" "$RAW_BASE/work/task.py"
  printf 'public fixture\n' > "$RAW_BASE/work/fixture.txt"
  printf 'touch envrc-executed; exit 89\n' > "$RAW_BASE/work/.envrc"
  raw_admit flake.nix reviewed.py task.py fixture.txt .envrc
  run python3 "$PROJECT_ROOT/tests/helpers/human-validation.py" "$RAW_BASE"
  raw_assert_status 0
  [[ "$output" == *HUMAN_VALIDATION_SEPARATED* ]]
}
