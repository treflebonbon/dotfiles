#!/usr/bin/env bats

setup() {
  PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  VERIFIER="$PROJECT_ROOT/scripts/verify-apm-deployment.mjs"
  FIXTURE="$BATS_TEST_TMPDIR/apm"
  mkdir -p "$FIXTURE"
  python3 - "$FIXTURE" <<'PY'
import hashlib, json, sys
from pathlib import Path
root=Path(sys.argv[1]); runtime=root/'runtime'
entries=[]
for name in ['alpha','beta']:
    files={}
    for target in ['.agents','.claude']:
        skill=f'{target}/skills/{name}'
        path=runtime/skill; path.mkdir(parents=True)
        content=f'---\nname: {name}\ndescription: Fixture skill\n---\n# Skill\n'
        (path/'SKILL.md').write_text(content)
        files[f'{skill}/SKILL.md']='sha256:'+hashlib.sha256(content.encode()).hexdigest()
    entries.append({'repo_url':'fixture/skills','virtual_path':f'skills/{name}',
        'content_hash':'sha256:baseline',
        'deployed_files':[p for file in files for p in [str(Path(file).parent),file]],
        'deployed_file_hashes':files})
base={'dependencies':entries}
(root/'base.yaml').write_text(json.dumps(base))
candidate=json.loads(json.dumps(base)); added=[]
for target in ['.agents','.claude']:
    file=f'{target}/skills/alpha/guide.md'; content='# Guide\n\n## Usage\nPlain Markdown.\n'
    (runtime/file).write_text(content);added.append(file)
    candidate['dependencies'][0]['deployed_files'].append(file)
    candidate['dependencies'][0]['deployed_file_hashes'][file]='sha256:'+hashlib.sha256(content.encode()).hexdigest()
candidate['dependencies'][0]['content_hash']='sha256:candidate'
(runtime/'apm.lock.yaml').write_text(json.dumps(candidate))
(root/'plan.json').write_text(json.dumps({'candidates':[{'repo_url':'fixture/skills',
    'virtual_path':'skills/alpha','added':added,'removed':[]}]}))
PY
}

mutate_fixture() {
  python3 - "$FIXTURE" "$1" <<'PY'
import hashlib, json, sys
from pathlib import Path
root=Path(sys.argv[1]); runtime=root/'runtime'; mutation=sys.argv[2]
lock_path=runtime/'apm.lock.yaml'; lock=json.loads(lock_path.read_text())
alpha,beta=lock['dependencies']; skill='.agents/skills/alpha/SKILL.md'
if mutation in ['unplanned-removal','untracked-skill']:
    alpha['deployed_files'].remove(skill)
    del alpha['deployed_file_hashes'][skill]
    if mutation=='untracked-skill':
        base_path=root/'base.yaml'; base=json.loads(base_path.read_text())
        base['dependencies'][0]['deployed_files'].remove(skill)
        del base['dependencies'][0]['deployed_file_hashes'][skill]
        base_path.write_text(json.dumps(base))
elif mutation=='noncandidate-hash':
    file='.agents/skills/beta/SKILL.md'; content=(runtime/file).read_text()+'Changed\n'
    (runtime/file).write_text(content)
    beta['deployed_file_hashes'][file]='sha256:'+hashlib.sha256(content.encode()).hexdigest()
elif mutation=='crlf':
    file=runtime/'.agents/skills/alpha/guide.md'; file.write_bytes(b'# Guide\r\n\r\n## Usage\r\nPlain Markdown.\r\n')
elif mutation=='tamper':
    (runtime/'.agents/skills/alpha/guide.md').write_text('Changed\n')
elif mutation=='frontmatter':
    content='# Missing frontmatter\n'; (runtime/skill).write_text(content)
    alpha['deployed_file_hashes'][skill]='sha256:'+hashlib.sha256(content.encode()).hexdigest()
elif mutation in ['traversal','symlink']:
    file='.agents/skills/alpha/../../escape' if mutation=='traversal' else '.agents/skills/alpha/escape'
    if mutation=='symlink':
        (root/'outside').write_text('Outside\n'); (runtime/file).symlink_to(root/'outside')
    alpha['deployed_files'].append(file)
    plan=json.loads((root/'plan.json').read_text()); plan['candidates'][0]['added'].append(file)
    (root/'plan.json').write_text(json.dumps(plan))
elif mutation=='floating-commit':
    beta['resolved_commit']='a'*40
elif mutation=='pin-commit':
    base_path=root/'base.yaml'; base=json.loads(base_path.read_text())
    base['dependencies'][1].update(resolved_ref='b'*40,resolved_commit='b'*40)
    base_path.write_text(json.dumps(base))
    beta.update(resolved_ref='b'*40,resolved_commit='a'*40)
elif mutation in ['resolved-ref','version']:
    beta['resolved_ref' if mutation=='resolved-ref' else 'version']='changed'
elif mutation in ['planned-removal','leftover-removal']:
    file='.agents/skills/alpha/obsolete.md'
    base_path=root/'base.yaml'; base=json.loads(base_path.read_text())
    base['dependencies'][0]['deployed_files'].append(file)
    base['dependencies'][0]['deployed_file_hashes'][file]='sha256:'+hashlib.sha256(b'Old\n').hexdigest()
    base_path.write_text(json.dumps(base))
    plan=json.loads((root/'plan.json').read_text()); plan['candidates'][0]['removed']=[file]
    (root/'plan.json').write_text(json.dumps(plan))
    if mutation=='leftover-removal': (runtime/file).write_text('Old\n')
elif mutation=='extra-skill':
    directory=runtime/'.agents/skills/untracked'; directory.mkdir()
    (directory/'SKILL.md').write_text('---\nname: untracked\ndescription: Extra\n---\n')
lock_path.write_text(json.dumps(lock))
PY
}

@test "APM deployment verification accepts planned guides without requiring skill frontmatter" {
  local before
  before=$(sha256sum "$FIXTURE/runtime/apm.lock.yaml")

  run bun "$VERIFIER" "$FIXTURE/base.yaml" "$FIXTURE/runtime" "$FIXTURE/plan.json"

  [ "$status" -eq 0 ]
  [[ "$output" == *'追加2'* ]]
  [ "$(sha256sum "$FIXTURE/runtime/apm.lock.yaml")" = "$before" ]
}

@test "APM deployment verification rejects an undeclared candidate deletion" {
  mutate_fixture unplanned-removal
  run bun "$VERIFIER" "$FIXTURE/base.yaml" "$FIXTURE/runtime" "$FIXTURE/plan.json"
  [ "$status" -eq 1 ]
  [[ "$output" == *'予定外の削除'* ]]
}

@test "APM deployment verification rejects noncandidate hash drift even when bytes match the new hash" {
  mutate_fixture noncandidate-hash
  run bun "$VERIFIER" "$FIXTURE/base.yaml" "$FIXTURE/runtime" "$FIXTURE/plan.json"
  [ "$status" -eq 1 ]
  [[ "$output" == *'候補外の drift'* ]]
}

@test "APM deployment verification accepts CRLF bytes whose LF-normalized hash matches the native hash" {
  mutate_fixture crlf
  run bun "$VERIFIER" "$FIXTURE/base.yaml" "$FIXTURE/runtime" "$FIXTURE/plan.json"
  [ "$status" -eq 0 ]
}

@test "APM live 検証は管理外スキルを保持して報告し、CRLF を受け入れる" {
  mutate_fixture crlf
  cp "$FIXTURE/runtime/apm.lock.yaml" "$FIXTURE/base.yaml"
  mkdir -p "$FIXTURE/runtime/.agents/skills/legacy"
  printf 'unmanaged fixture\n' >"$FIXTURE/runtime/.agents/skills/legacy/SKILL.md"
  ln -s "$FIXTURE/unavailable" "$FIXTURE/runtime/.agents/skills/playwright-cli"
  local before
  before=$(sha256sum "$FIXTURE/runtime/apm.lock.yaml" "$FIXTURE/runtime/.agents/skills/legacy/SKILL.md")

  run bun "$VERIFIER" --live "$FIXTURE/base.yaml" "$FIXTURE/runtime"

  [ "$status" -eq 0 ]
  [[ "$output" == *'管理外の配備先:'*'.agents/skills/legacy'* ]]
  [[ "$output" == *'.agents/skills/playwright-cli'* ]]
  [[ "$output" == *'skill .agents=2 .claude=2'* ]]
  [ "$(sha256sum "$FIXTURE/runtime/apm.lock.yaml" "$FIXTURE/runtime/.agents/skills/legacy/SKILL.md")" = "$before" ]
  [ -L "$FIXTURE/runtime/.agents/skills/playwright-cli" ]
}

@test "APM live 検証は受入済み lock の所有権 ledger の drift を拒否する" {
  cp "$FIXTURE/runtime/apm.lock.yaml" "$FIXTURE/base.yaml"
  python3 - "$FIXTURE/runtime/apm.lock.yaml" <<'PY'
import json, sys
from pathlib import Path
p=Path(sys.argv[1]); lock=json.loads(p.read_text())
lock['deployments']=[{'owners':['unexpected-owner']}]
p.write_text(json.dumps(lock))
PY

  run bun "$VERIFIER" --live "$FIXTURE/base.yaml" "$FIXTURE/runtime"

  [ "$status" -eq 1 ]
  [[ "$output" == *'live lock が受入済み lock と一致しません'* ]]
}

@test "APM live 検証は HOME 内でも管理対象の symlink を拒否する" {
  cp "$FIXTURE/runtime/apm.lock.yaml" "$FIXTURE/base.yaml"
  mv "$FIXTURE/runtime/.agents/skills/alpha/SKILL.md" "$FIXTURE/runtime/unmanaged.md"
  ln -s "$FIXTURE/runtime/unmanaged.md" "$FIXTURE/runtime/.agents/skills/alpha/SKILL.md"

  run bun "$VERIFIER" --live "$FIXTURE/base.yaml" "$FIXTURE/runtime"

  [ "$status" -eq 1 ]
  [[ "$output" == *'live の管理対象に symlink'* ]]
}

@test "APM live 検証は管理対象の親 directory の symlink を拒否する" {
  cp "$FIXTURE/runtime/apm.lock.yaml" "$FIXTURE/base.yaml"
  mv "$FIXTURE/runtime/.agents" "$FIXTURE/runtime/other-agents"
  ln -s "$FIXTURE/runtime/other-agents" "$FIXTURE/runtime/.agents"

  run bun "$VERIFIER" --live "$FIXTURE/base.yaml" "$FIXTURE/runtime"

  [ "$status" -eq 1 ]
  [[ "$output" == *'live の管理対象に symlink'* ]]
}

@test "APM live 検証は管理対象ファイルの改変を拒否する" {
  cp "$FIXTURE/runtime/apm.lock.yaml" "$FIXTURE/base.yaml"
  mutate_fixture tamper

  run bun "$VERIFIER" --live "$FIXTURE/base.yaml" "$FIXTURE/runtime"

  [ "$status" -eq 1 ]
  [[ "$output" == *'file hash 不一致'* ]]
}

@test "APM live 検証は管理対象ファイルの欠落を拒否する" {
  cp "$FIXTURE/runtime/apm.lock.yaml" "$FIXTURE/base.yaml"
  mv "$FIXTURE/runtime/.agents/skills/alpha/guide.md" "$FIXTURE/guide.md"

  run bun "$VERIFIER" --live "$FIXTURE/base.yaml" "$FIXTURE/runtime"

  [ "$status" -eq 1 ]
  [[ "$output" == *'guide.md'* ]]
}

@test "APM live 検証は管理スキル内部の台帳外ファイルを拒否する" {
  cp "$FIXTURE/runtime/apm.lock.yaml" "$FIXTURE/base.yaml"
  printf 'unlisted fixture\n' >"$FIXTURE/runtime/.agents/skills/alpha/extra.py"

  run bun "$VERIFIER" --live "$FIXTURE/base.yaml" "$FIXTURE/runtime"

  [ "$status" -eq 1 ]
  [[ "$output" == *'台帳外の配備file'*'extra.py'* ]]
}

@test "APM live 検証は配備済み lock の symlink を拒否する" {
  cp "$FIXTURE/runtime/apm.lock.yaml" "$FIXTURE/base.yaml"
  mv "$FIXTURE/runtime/apm.lock.yaml" "$FIXTURE/deployed.lock"
  ln -s "$FIXTURE/deployed.lock" "$FIXTURE/runtime/apm.lock.yaml"

  run bun "$VERIFIER" --live "$FIXTURE/base.yaml" "$FIXTURE/runtime"

  [ "$status" -eq 1 ]
  [[ "$output" == *'lock は通常 file'* ]]
}

@test "APM deployment verification rejects deployed bytes that disagree with the native hash" {
  mutate_fixture tamper
  run bun "$VERIFIER" "$FIXTURE/base.yaml" "$FIXTURE/runtime" "$FIXTURE/plan.json"
  [ "$status" -eq 1 ]
  [[ "$output" == *'file hash 不一致'* ]]
}

@test "APM deployment verification requires frontmatter on SKILL.md" {
  mutate_fixture frontmatter
  run bun "$VERIFIER" "$FIXTURE/base.yaml" "$FIXTURE/runtime" "$FIXTURE/plan.json"
  [ "$status" -eq 1 ]
  [[ "$output" == *'SKILL frontmatter'* ]]
}

@test "APM deployment verification rejects path traversal in a planned addition" {
  mutate_fixture traversal
  run bun "$VERIFIER" "$FIXTURE/base.yaml" "$FIXTURE/runtime" "$FIXTURE/plan.json"
  [ "$status" -eq 1 ]
  [[ "$output" == *'配備先不正'* ]]
}

@test "APM deployment verification rejects symlinks outside the isolated runtime" {
  mutate_fixture symlink
  run bun "$VERIFIER" "$FIXTURE/base.yaml" "$FIXTURE/runtime" "$FIXTURE/plan.json"
  [ "$status" -eq 1 ]
  [[ "$output" == *'runtime 外の配備先'* ]]
}

@test "APM deployment verification accepts floating commit changes with an unchanged payload" {
  mutate_fixture floating-commit
  run bun "$VERIFIER" "$FIXTURE/base.yaml" "$FIXTURE/runtime" "$FIXTURE/plan.json"
  [ "$status" -eq 0 ]
}

@test "APM deployment verification rejects an unexpected discovered skill" {
  mutate_fixture extra-skill
  run bun "$VERIFIER" "$FIXTURE/base.yaml" "$FIXTURE/runtime" "$FIXTURE/plan.json"
  [ "$status" -eq 1 ]
  [[ "$output" == *'discovery 不一致'* ]]
}

@test "APM deployment verification rejects an unlisted script inside a managed skill" {
  mkdir -p "$FIXTURE/runtime/.agents/skills/alpha/scripts"
  printf 'print("unlisted fixture")\n' >"$FIXTURE/runtime/.agents/skills/alpha/scripts/extra.py"

  run bun "$VERIFIER" "$FIXTURE/base.yaml" "$FIXTURE/runtime" "$FIXTURE/plan.json"

  [ "$status" -eq 1 ]
  [[ "$output" == *'台帳外の配備file'*'scripts/extra.py'* ]]
}

@test "APM deployment verification rejects a discovered SKILL.md omitted from the hash ledger" {
  mutate_fixture untracked-skill
  run bun "$VERIFIER" "$FIXTURE/base.yaml" "$FIXTURE/runtime" "$FIXTURE/plan.json"
  [ "$status" -eq 1 ]
  [[ "$output" == *'未検証の SKILL.md'* ]]
}

@test "APM deployment verification accepts a declared guide removal" {
  mutate_fixture planned-removal
  run bun "$VERIFIER" "$FIXTURE/base.yaml" "$FIXTURE/runtime" "$FIXTURE/plan.json"
  [ "$status" -eq 0 ]
  [[ "$output" == *'削除1'* ]]
}

@test "APM deployment verification rejects removed files left in the runtime" {
  mutate_fixture leftover-removal
  run bun "$VERIFIER" "$FIXTURE/base.yaml" "$FIXTURE/runtime" "$FIXTURE/plan.json"
  [ "$status" -eq 1 ]
  [[ "$output" == *'削除fileが残存'* ]]
}

@test "APM deployment verification rejects an exact pin commit changing outside the candidate" {
  mutate_fixture pin-commit
  run bun "$VERIFIER" "$FIXTURE/base.yaml" "$FIXTURE/runtime" "$FIXTURE/plan.json"
  [ "$status" -eq 1 ]
  [[ "$output" == *'候補外の drift'*'resolved_commit'* ]]
}

@test "APM deployment verification rejects a reference changing outside the candidate" {
  mutate_fixture resolved-ref
  run bun "$VERIFIER" "$FIXTURE/base.yaml" "$FIXTURE/runtime" "$FIXTURE/plan.json"
  [ "$status" -eq 1 ]
  [[ "$output" == *'候補外の drift'*'resolved_ref'* ]]
}

@test "APM deployment verification rejects version metadata drift outside the candidate" {
  mutate_fixture version
  run bun "$VERIFIER" "$FIXTURE/base.yaml" "$FIXTURE/runtime" "$FIXTURE/plan.json"
  [ "$status" -eq 1 ]
  [[ "$output" == *'候補外の drift'*'version'* ]]
}

@test "APM deployment verification accepts an unchanged runtime with an empty candidate plan" {
  cp "$FIXTURE/runtime/apm.lock.yaml" "$FIXTURE/base.yaml"
  printf '{"candidates":[]}\n' >"$FIXTURE/plan.json"
  local before
  before=$(sha256sum "$FIXTURE/runtime/apm.lock.yaml")

  run bun "$VERIFIER" "$FIXTURE/base.yaml" "$FIXTURE/runtime" "$FIXTURE/plan.json"

  [ "$status" -eq 0 ]
  [[ "$output" == *'追加0・削除0'* ]]
  [ "$(sha256sum "$FIXTURE/runtime/apm.lock.yaml")" = "$before" ]
}

@test "APM deployment verification rejects a bare array instead of a candidate plan object" {
  printf '[]\n' >"$FIXTURE/plan.json"

  run bun "$VERIFIER" "$FIXTURE/base.yaml" "$FIXTURE/runtime" "$FIXTURE/plan.json"

  [ "$status" -eq 1 ]
  [[ "$output" == *'配列ではありません'* ]]
}

@test "APM deployment verification rejects unknown and duplicate candidates" {
  printf '{"candidates":[{"repo_url":"fixture/unknown","added":[],"removed":[]}]}\n' >"$FIXTURE/plan.json"
  run bun "$VERIFIER" "$FIXTURE/base.yaml" "$FIXTURE/runtime" "$FIXTURE/plan.json"
  [ "$status" -eq 1 ]
  [[ "$output" == *'計画に未知の dependency'* ]]

  python3 - "$FIXTURE/plan.json" <<'PY'
import json, sys
from pathlib import Path
candidate={'repo_url':'fixture/skills','virtual_path':'skills/alpha','added':[],'removed':[]}
Path(sys.argv[1]).write_text(json.dumps({'candidates':[candidate,candidate]}))
PY
  run bun "$VERIFIER" "$FIXTURE/base.yaml" "$FIXTURE/runtime" "$FIXTURE/plan.json"
  [ "$status" -eq 1 ]
  [[ "$output" == *'dependency 重複'* ]]
}
