#!/usr/bin/env bats

setup() {
  PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  FIXTURE="$BATS_TEST_TMPDIR/retirement"
  RUNTIME="$FIXTURE/home"
  mkdir -p "$RUNTIME" "$FIXTURE/source"
  python3 - "$FIXTURE" <<'PY'
import hashlib, json, sys
from pathlib import Path
root = Path(sys.argv[1])
runtime = root / 'home'
content = b'---\nname: retired\ndescription: Retirement fixture\n---\n'
digest = 'sha256:' + hashlib.sha256(content).hexdigest()
files = []
hashes = {}
deployments = []
owner = 'fixture/skills/skills/retired'
for target, directory in [('claude', '.claude'), ('codex', '.agents')]:
    skill = f'{directory}/skills/retired'
    path = runtime / skill
    path.mkdir(parents=True)
    (path / 'SKILL.md').write_bytes(content)
    (path.parent / 'unmanaged').mkdir()
    (path.parent / 'unmanaged' / 'keep').write_bytes(b'Keep unknown bytes\n')
    for value, content_hash in [(skill, None), (skill + '/SKILL.md', digest)]:
        files.append(value)
        deployments.append(dict(kind='project-relative', target=target,
            value=value, runtime=None, scope='project', owners=[owner],
            active_owner=owner, content_hash=content_hash))
    hashes[skill + '/SKILL.md'] = digest
dependency = dict(repo_url='fixture/skills', name='retired', host='github.com',
    virtual_path='skills/retired', is_virtual=True, package_type='claude_skill',
    resolved_commit='a' * 40, deployed_files=files, deployed_file_hashes=hashes)
old = dict(lockfile_version='1', apm_version='0.35.0',
    dependencies=[dependency], deployments=deployments)
accepted = dict(old, dependencies=[], deployments=[])
(root / 'old-lock.yaml').write_text(json.dumps(old))
(runtime / 'apm.lock.yaml').write_text(json.dumps(old))
(root / 'source' / 'apm.lock.yaml').write_text(json.dumps(accepted))
(root / 'source' / 'apm.yml').write_text(
    'name: retirement-fixture\nversion: 1.0.0\ntargets: [claude, codex]\n'
    'dependencies:\n  apm: []\n')
PY
  APM="$(command -v apm)"
  CHEZMOI="$(command -v chezmoi)"
}

apply_accepted() {
  "$CHEZMOI" --source "$FIXTURE/source" --destination "$RUNTIME" \
    --config /dev/null --config-format toml --cache "$FIXTURE/cache" \
    --persistent-state "$FIXTURE/chezmoi-state" apply --force \
    "$RUNTIME/apm.yml" "$RUNTIME/apm.lock.yaml"
}

run_apm() {
  (cd "$RUNTIME" && HOME="$RUNTIME" XDG_CACHE_HOME="$RUNTIME/.cache" "$APM" "$@")
}

@test "APM invocation isolates HOME and cache while preserving caller and arguments" {
  local caller_home="$HOME" caller_cache="${XDG_CACHE_HOME-}" caller_pwd="$PWD"
  APM="$FIXTURE/apm-probe"
  cat >"$APM" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$HOME" "${XDG_CACHE_HOME-}" "$PWD" "$@"
SH
  chmod +x "$APM"

  run_apm prune --dry-run >"$FIXTURE/probe.output"

  [ "$HOME" = "$caller_home" ]
  [ "${XDG_CACHE_HOME-}" = "$caller_cache" ]
  [ "$PWD" = "$caller_pwd" ]
  run cat "$FIXTURE/probe.output"

  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "$RUNTIME" ]
  [ "${lines[1]}" = "$RUNTIME/.cache" ]
  [ "${lines[2]}" = "$RUNTIME" ]
  [ "${lines[3]}" = prune ]
  [ "${lines[4]}" = --dry-run ]
}

@test "APM old-ledger prune preserves a modified retired skill" {
  run apply_accepted
  [ "$status" -eq 0 ]
  printf 'User modification\n' >>"$RUNTIME/.agents/skills/retired/SKILL.md"
  cp "$RUNTIME/.agents/skills/retired/SKILL.md" "$FIXTURE/modified.md"
  cp "$FIXTURE/old-lock.yaml" "$RUNTIME/apm.lock.yaml"
  run run_apm prune
  [ "$status" -eq 0 ]

  cmp "$FIXTURE/modified.md" "$RUNTIME/.agents/skills/retired/SKILL.md"
  [ ! -e "$RUNTIME/.claude/skills/retired" ]
  [ "$(cat "$RUNTIME/.agents/skills/unmanaged/keep")" = 'Keep unknown bytes' ]
}

@test "APM new-lock install and prune leave previously owned skills on disk" {
  run apply_accepted
  [ "$status" -eq 0 ]
  run run_apm install --frozen --target claude,codex --https
  [ "$status" -eq 0 ]
  run run_apm prune
  [ "$status" -eq 0 ]

  for target in .agents .claude; do
    [ -f "$RUNTIME/$target/skills/retired/SKILL.md" ]
  done
  run bun "$PROJECT_ROOT/scripts/verify-apm-deployment.mjs" --live \
    "$FIXTURE/source/apm.lock.yaml" "$RUNTIME"
  [ "$status" -eq 0 ]
  [[ "$output" == *'管理外の配備先:'*'skills/retired'* ]]
}

@test "APM old-ledger prune retires both targets and preserves unknown skills" {
  run apply_accepted
  [ "$status" -eq 0 ]
  cp "$FIXTURE/old-lock.yaml" "$RUNTIME/apm.lock.yaml"
  run run_apm prune --dry-run
  [ "$status" -eq 0 ]
  for target in .agents .claude; do
    [ -f "$RUNTIME/$target/skills/retired/SKILL.md" ]
  done
  run run_apm prune
  [ "$status" -eq 0 ]
  run apply_accepted
  [ "$status" -eq 0 ]
  run run_apm install --frozen --target claude,codex --https
  [ "$status" -eq 0 ]

  for target in .agents .claude; do
    [ ! -e "$RUNTIME/$target/skills/retired" ]
    [ ! -L "$RUNTIME/$target/skills/retired" ]
    [ "$(cat "$RUNTIME/$target/skills/unmanaged/keep")" = 'Keep unknown bytes' ]
  done
  cmp "$FIXTURE/source/apm.lock.yaml" "$RUNTIME/apm.lock.yaml"
  run "$CHEZMOI" --source "$FIXTURE/source" --destination "$RUNTIME" \
    --config /dev/null --config-format toml --cache "$FIXTURE/cache" \
    --persistent-state "$FIXTURE/chezmoi-state" verify \
    "$RUNTIME/apm.yml" "$RUNTIME/apm.lock.yaml"
  [ "$status" -eq 0 ]
}
