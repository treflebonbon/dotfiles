#!/usr/bin/env bats

setup() {
  PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  SCRIPT="$PROJECT_ROOT/scripts/check-registry-locks.js"
  REGISTRY_REPO="$BATS_TEST_TMPDIR/registry-fixture"
}

write_registry_fixture() {
  mkdir -p "$REGISTRY_REPO/scripts" "$REGISTRY_REPO/tests/experiments/rop-analysis"
  cp "$SCRIPT" "$REGISTRY_REPO/scripts/check-registry-locks.js"
  cp "$PROJECT_ROOT/lefthook.yml" "$REGISTRY_REPO/lefthook.yml"
  cat >"$REGISTRY_REPO/tests/experiments/rop-analysis/.npmrc" <<'NPMRC'
registry=https://registry.npmjs.org/
NPMRC
  cat >"$REGISTRY_REPO/bunfig.toml" <<'TOML'
[install]
registry = "https://registry.npmjs.org"
TOML
  cat >"$REGISTRY_REPO/bun.lock" <<'JSON'
{
  "lockfileVersion": 1,
  "packages": {
    "fixture": ["fixture@1.0.0", "", {}, "sha512-fixture"]
  }
}
JSON
  cat >"$REGISTRY_REPO/package-lock.json" <<'JSON'
{
  "lockfileVersion": 3,
  "packages": {
    "": {"name": "fixture"},
    "node_modules/workspace": {"link": true},
    "node_modules/dependency": {
      "version": "1.0.0",
      "resolved": "https://registry.npmjs.org/dependency/-/dependency-1.0.0.tgz"
    }
  }
}
JSON
  git -C "$REGISTRY_REPO" init -q
  git -C "$REGISTRY_REPO" config user.name registry-test
  git -C "$REGISTRY_REPO" config user.email registry-test@example.invalid
  git -C "$REGISTRY_REPO" add bunfig.toml bun.lock package-lock.json scripts/check-registry-locks.js tests/experiments/rop-analysis/.npmrc
  git -C "$REGISTRY_REPO" add lefthook.yml
}

run_registry_checker() (
  cd "$REGISTRY_REPO"
  bun scripts/check-registry-locks.js "$@"
)

run_registry_hook() (
  cd "$REGISTRY_REPO"
  lefthook run pre-commit --job registry-locks --no-auto-install
)

run_full_registry_hook() (
  cd "$REGISTRY_REPO"
  lefthook run pre-commit --no-auto-install
)

@test "official Bun and npm registries pass with normal package-lock root and workspace entries" {
  write_registry_fixture
  run run_registry_checker --staged
  [ "$status" -eq 0 ]
  [[ "$output" == *"1 個の npm lockfile"* ]]
}

@test "npm registry values accept INI quotes and comments without hiding mirror URLs" {
  write_registry_fixture
  for value in \
    '"https://registry.npmjs.org/"' \
    "'https://registry.npmjs.org/'" \
    '"https:\/\/registry.npmjs.org\/"' \
    'https://registry.npmjs.org/ ; official registry'; do
    printf 'registry=%s\n' "$value" >"$REGISTRY_REPO/tests/experiments/rop-analysis/.npmrc"
    git -C "$REGISTRY_REPO" add tests/experiments/rop-analysis/.npmrc
    run run_registry_checker --staged
    [ "$status" -eq 0 ]
  done
  for value in \
    '"https://mirror.invalid/"' \
    "'https://mirror.invalid/'" \
    "'[\"https://registry.npmjs.org/\"]'" \
    '"https://registry.npmjs.org/#mirror"' \
    'https://registry.npmjs.org/\#mirror'; do
    printf 'registry=%s\n' "$value" >"$REGISTRY_REPO/tests/experiments/rop-analysis/.npmrc"
    git -C "$REGISTRY_REPO" add tests/experiments/rop-analysis/.npmrc
    run run_registry_checker --staged
    [ "$status" -ne 0 ]
  done
}

@test "staged npm configuration rejects registry keys that npm ignores" {
  write_registry_fixture
  for key in REGISTRY Registry; do
    printf '%s=https://registry.npmjs.org/\n' "$key" >"$REGISTRY_REPO/tests/experiments/rop-analysis/.npmrc"
    git -C "$REGISTRY_REPO" add tests/experiments/rop-analysis/.npmrc
    run run_registry_checker --staged
    [ "$status" -ne 0 ]
    [[ "$output" == *".npmrc: registry は公式 npm registry を一つだけ指定してください"* ]]
  done
}

@test "Bun and npm lockfiles reject mirror and lookalike registry hosts" {
  write_registry_fixture
  for url in \
    "https://mirror.invalid/fixture-1.0.0.tgz" \
    "https://registry.npmjs.org.evil.invalid/fixture-1.0.0.tgz"; do
    python3 - "$REGISTRY_REPO/bun.lock" "$url" <<'PY'
import json, sys
from pathlib import Path
path, url = sys.argv[1:]
data = json.loads(Path(path).read_text())
data["packages"]["fixture"][1] = url
Path(path).write_text(json.dumps(data))
PY
    git -C "$REGISTRY_REPO" add bun.lock
    run run_registry_checker --staged
    [ "$status" -ne 0 ]
  done

  cat >"$REGISTRY_REPO/bun.lock" <<'JSON'
{"lockfileVersion":1,"packages":{"fixture":["fixture@1.0.0","",{},"sha512-fixture"]}}
JSON
  git -C "$REGISTRY_REPO" add bun.lock
  python3 - "$REGISTRY_REPO/package-lock.json" <<'PY'
import json, sys
from pathlib import Path
path = Path(sys.argv[1])
data = json.loads(path.read_text())
data["packages"]["node_modules/dependency"]["resolved"] = "https://registry.npmjs.org.evil.invalid/dependency.tgz"
path.write_text(json.dumps(data))
PY
  git -C "$REGISTRY_REPO" add package-lock.json
  run run_registry_checker --staged
  [ "$status" -ne 0 ]
}

@test "staged mode reads the Git index and working-tree mode reads the checkout" {
  write_registry_fixture
  python3 - "$REGISTRY_REPO/bun.lock" <<'PY'
import json, sys
from pathlib import Path
path = Path(sys.argv[1])
data = json.loads(path.read_text())
data["packages"]["fixture"][1] = "https://mirror.invalid/fixture.tgz"
path.write_text(json.dumps(data))
PY
  run run_registry_checker --staged
  [ "$status" -eq 0 ]
  run run_registry_checker
  [ "$status" -ne 0 ]

  git -C "$REGISTRY_REPO" add bun.lock
  cat >"$REGISTRY_REPO/bun.lock" <<'JSON'
{"lockfileVersion":1,"packages":{"fixture":["fixture@1.0.0","",{},"sha512-fixture"]}}
JSON
  run run_registry_checker --staged
  [ "$status" -ne 0 ]
  run run_registry_checker
  [ "$status" -eq 0 ]
}

@test "registry checker rejects broken lock data and nonofficial Bun configuration" {
  write_registry_fixture
  printf '{broken json\n' >"$REGISTRY_REPO/bun.lock"
  git -C "$REGISTRY_REPO" add bun.lock
  run run_registry_checker --staged
  [ "$status" -ne 0 ]

  cat >"$REGISTRY_REPO/bun.lock" <<'JSON'
{"lockfileVersion":1,"packages":{"fixture":["fixture@1.0.0","",{},"sha512-fixture"]}}
JSON
  git -C "$REGISTRY_REPO" add bun.lock
  python3 - "$REGISTRY_REPO/package-lock.json" <<'PY'
import json, sys
from pathlib import Path
path = Path(sys.argv[1])
data = json.loads(path.read_text())
del data["packages"]["node_modules/dependency"]["resolved"]
path.write_text(json.dumps(data))
PY
  git -C "$REGISTRY_REPO" add package-lock.json
  run run_registry_checker --staged
  [ "$status" -ne 0 ]

  python3 - "$REGISTRY_REPO/package-lock.json" <<'PY'
import json, sys
from pathlib import Path
path = Path(sys.argv[1])
data = json.loads(path.read_text())
data["packages"]["node_modules/dependency"]["resolved"] = "https://registry.npmjs.org/dependency/-/dependency-1.0.0.tgz"
path.write_text(json.dumps(data))
PY
  git -C "$REGISTRY_REPO" add package-lock.json
  cat >"$REGISTRY_REPO/bunfig.toml" <<'TOML'
[install]
registry = "https://mirror.invalid"
TOML
  git -C "$REGISTRY_REPO" add bunfig.toml
  run run_registry_checker --staged
  [ "$status" -ne 0 ]

  cat >"$REGISTRY_REPO/bunfig.toml" <<'TOML'
[install]
registry = "https://registry.npmjs.org"
TOML
  git -C "$REGISTRY_REPO" add bun.lock bunfig.toml package-lock.json
  cat >"$REGISTRY_REPO/tests/experiments/rop-analysis/.npmrc" <<'NPMRC'
registry=https://mirror.invalid/
NPMRC
  git -C "$REGISTRY_REPO" add tests/experiments/rop-analysis/.npmrc
  run run_registry_checker --staged
  [ "$status" -ne 0 ]
}

@test "staged invalid UTF-8 reports the tracked file path" {
  write_registry_fixture
  python3 - "$REGISTRY_REPO/package-lock.json" <<'PY'
from pathlib import Path
import sys
Path(sys.argv[1]).write_bytes(b"\xff")
PY
  git -C "$REGISTRY_REPO" add package-lock.json
  run run_registry_checker --staged
  [ "$status" -ne 0 ]
  [[ "$output" == *"package-lock.json: UTF-8として読み取れません"* ]]
}

@test "the pre-commit hook runs for a staged lockfile and checker change, using the index" {
  write_registry_fixture
  git -C "$REGISTRY_REPO" commit -qm fixture

  python3 - "$REGISTRY_REPO/bun.lock" <<'PY'
import json, sys
from pathlib import Path
path = Path(sys.argv[1])
data = json.loads(path.read_text())
data["packages"]["fixture"][1] = "https://mirror.invalid/fixture.tgz"
path.write_text(json.dumps(data))
PY
  git -C "$REGISTRY_REPO" add bun.lock
  cat >"$REGISTRY_REPO/bun.lock" <<'JSON'
{"lockfileVersion":1,"packages":{"fixture":["fixture@1.0.0","",{},"sha512-fixture"]}}
JSON
  run run_registry_hook
  [ "$status" -ne 0 ]
  [[ "$output" == *"bun.lock: fixture は公式 npm registry 以外を参照しています"* ]]

  git -C "$REGISTRY_REPO" add bun.lock
  printf '\n// staged checker change\n' >>"$REGISTRY_REPO/scripts/check-registry-locks.js"
  git -C "$REGISTRY_REPO" add scripts/check-registry-locks.js
  run run_registry_hook
  [ "$status" -eq 0 ]
  [[ "$output" == *"registry-locks: bun.lock と 1 個の npm lockfile"* ]]
}

@test "the full pre-commit hook preserves the staged registry and rejects a staged mirror" {
  write_registry_fixture
  git -C "$REGISTRY_REPO" commit -qm fixture
  ln -s "$PROJECT_ROOT/node_modules" "$REGISTRY_REPO/node_modules"
  printf '\n' >>"$REGISTRY_REPO/bunfig.toml"
  git -C "$REGISTRY_REPO" add bunfig.toml
  cat >"$REGISTRY_REPO/bunfig.toml" <<'TOML'
[install]
registry = "https://mirror.invalid"
TOML
  run run_full_registry_hook
  [ "$status" -eq 0 ]
  run git -C "$REGISTRY_REPO" show :bunfig.toml
  [[ "$output" == *"https://registry.npmjs.org"* ]]
  [[ "$output" != *"mirror.invalid"* ]]
  run cat "$REGISTRY_REPO/bunfig.toml"
  [[ "$output" == *"https://mirror.invalid"* ]]

  git -C "$REGISTRY_REPO" add bunfig.toml
  run run_full_registry_hook
  [ "$status" -ne 0 ]
  [[ "$output" == *"bunfig.toml: [install].registry は公式 npm registry を一つだけ指定してください"* ]]
}
