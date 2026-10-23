#!/usr/bin/env bats

setup() {
  PLANNER="$BATS_TEST_DIRNAME/../scripts/plan-apm-deployment.mjs"
  python3 -I - "$BATS_TEST_TMPDIR" <<'PY'
import json, sys
from pathlib import Path
root = Path(sys.argv[1])
def dep(name, **extra):
    d = {'repo_url': f'fixture/{name}', 'virtual_path': f'skills/{name}',
         'resolved_commit': 'a' * 40, 'content_hash': 'sha256:one',
         'deployed_files': [f'.agents/skills/{name}/SKILL.md'],
         'deployed_file_hashes': {f'.agents/skills/{name}/SKILL.md': 'sha256:x'}}
    d.update(extra)
    return d
base = {'dependencies': [dep('added'), dep('hashonly'), dep('floating'),
                         dep('pinned', resolved_ref='b' * 40), dep('same')]}
cand = json.loads(json.dumps(base))
d = cand['dependencies']
d[0]['deployed_files'] += ['.agents/skills/added/guide.md']
d[0]['content_hash'] = 'sha256:two'
d[1]['content_hash'] = 'sha256:two'
d[2]['resolved_commit'] = 'c' * 40
d[3]['resolved_commit'] = 'd' * 40
(root / 'base.json').write_text(json.dumps(base))
(root / 'candidate.json').write_text(json.dumps(cand))
PY
}

@test "plan lists added files, hash-only changes, and pinned commit changes but not floating commit advances" {
  run bun "$PLANNER" "$BATS_TEST_TMPDIR/base.json" "$BATS_TEST_TMPDIR/candidate.json"

  [ "$status" -eq 0 ]
  jq -e '
    (.candidates | map(.virtual_path) | sort) == ["skills/added", "skills/hashonly", "skills/pinned"] and
    (.candidates[] | select(.virtual_path == "skills/added") | .added) == [".agents/skills/added/guide.md"] and
    all(.candidates[]; .removed == []) and
    (.candidates[] | select(.virtual_path == "skills/hashonly") | .added) == []
  ' <<<"$output"
}

@test "plan lists removed files" {
  run bun "$PLANNER" "$BATS_TEST_TMPDIR/candidate.json" "$BATS_TEST_TMPDIR/base.json"

  [ "$status" -eq 0 ]
  jq -e '(.candidates[] | select(.virtual_path == "skills/added") | .removed) == [".agents/skills/added/guide.md"]' <<<"$output"
}

@test "plan rejects a changed dependency set" {
  python3 -I - "$BATS_TEST_TMPDIR/candidate.json" <<'PY'
import json, sys
p = sys.argv[1]
lock = json.load(open(p))
lock['dependencies'].pop()
json.dump(lock, open(p, 'w'))
PY

  run bun "$PLANNER" "$BATS_TEST_TMPDIR/base.json" "$BATS_TEST_TMPDIR/candidate.json"

  [ "$status" -eq 1 ]
  [[ "$output" == *'構成が変わっています'* ]]
}

@test "plan rejects duplicate dependencies and malformed locks" {
  python3 -I - "$BATS_TEST_TMPDIR/candidate.json" <<'PY'
import json, sys
p = sys.argv[1]
lock = json.load(open(p))
lock['dependencies'].append(lock['dependencies'][0])
json.dump(lock, open(p, 'w'))
PY
  run bun "$PLANNER" "$BATS_TEST_TMPDIR/base.json" "$BATS_TEST_TMPDIR/candidate.json"
  [ "$status" -eq 1 ]
  [[ "$output" == *'dependency 重複'* ]]

  printf '{}' >"$BATS_TEST_TMPDIR/candidate.json"
  run bun "$PLANNER" "$BATS_TEST_TMPDIR/base.json" "$BATS_TEST_TMPDIR/candidate.json"
  [ "$status" -eq 1 ]
}

@test "plan requires exactly two lock arguments" {
  run bun "$PLANNER" "$BATS_TEST_TMPDIR/base.json"
  [ "$status" -eq 2 ]
}
