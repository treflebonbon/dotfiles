#!/usr/bin/env bats

setup_file() {
  if [ ! -e /tmp/codex ] && [ ! -L /tmp/codex ]; then
    mkdir -m 700 /tmp/codex
  fi
  [ -d /tmp/codex ] && [ ! -L /tmp/codex ] && [ -O /tmp/codex ]
}

setup() {
  unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES GIT_COMMON_DIR GIT_PREFIX
  local project_root
  project_root="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  SCRIPT="$project_root/local-skills/herdr-peer-refactor/scripts/run-evidence.py"
  PIN="$project_root/local-skills/herdr-peer-refactor/scripts/candidate-record.py"
  EVIDENCE="$(mktemp -d /tmp/codex/peer-evidence-test.XXXXXX)"
  REPO="$BATS_TEST_TMPDIR/repo"
  mkdir -p "$REPO" "$EVIDENCE/peer"
  git init -q "$REPO"
  git -C "$REPO" -c user.name=Fixture -c user.email=fixture@example.invalid commit -qm initial --allow-empty
  SHA="$(git -C "$REPO" rev-parse HEAD)"
  COMMON="$(git -C "$REPO" rev-parse --path-format=absolute --git-common-dir)"
  RECORD="$EVIDENCE/record.json"
  CANDIDATES="$EVIDENCE/candidates.json"
  REPORT="$EVIDENCE/report.md"
  printf '# Gateway preparation\n' >"$REPORT"
  printf '%s\n' '[{"id":"C2","title":"Gateway preparation","acceptance":["ready"],"non_goals":[],"owned_files":["gateway.py"]}]' >"$CANDIDATES"
  FINGERPRINT="$(cd "$REPO" && python3 "$PIN" pin "$REPORT" "$COMMON" "$SHA" "$CANDIDATES" "$RECORD")"
  printf 'run-1\n' >"$EVIDENCE/peer/run-id"
  printf '271\n' >"$EVIDENCE/peer/waited-s"
  printf '2\n' >"$EVIDENCE/peer/round"
  printf 'missing\n' >"$EVIDENCE/peer/REQ-1.failures"
  printf 'mutation detected\n' >"$EVIDENCE/mutation.log"
}

teardown() {
  if [[ "${EVIDENCE:-}" == /tmp/codex/peer-evidence-test.* ]]; then
    rm -r -- "$EVIDENCE"
  fi
}

checkpoint() {
  (cd "$REPO" && python3 "$SCRIPT" checkpoint "$RECORD" "$CANDIDATES" "$FINGERPRINT" "$@")
}

save_checkpoint() {
  run checkpoint "$EVIDENCE/peer/run-id" "$EVIDENCE/peer/waited-s" "$EVIDENCE/peer/round" "$EVIDENCE/peer/REQ-1.failures" "$EVIDENCE/mutation.log"
  [ "$status" -eq 0 ]
  CHECKPOINT="$(python3 -c 'import json,sys; print(json.loads(sys.argv[1])["checkpoint"])' "$output")"
  ARCHIVE="$COMMON/peer-refactor-evidence/$FINGERPRINT/$CHECKPOINT.json"
  [ -f "$ARCHIVE" ]
}

restore() {
  (cd "$REPO" && python3 "$SCRIPT" restore "$FINGERPRINT" "$CHECKPOINT")
}

@test "checkpoint restores candidate bytes and all peer budgets after shared evidence disappears" {
  save_checkpoint
  local original
  original="$(sha256sum "$RECORD")"
  rm -- "$RECORD" "$CANDIDATES" "$REPORT" "$EVIDENCE/mutation.log" "$EVIDENCE/peer/"*
  git -C "$REPO" -c user.name=Fixture -c user.email=fixture@example.invalid commit -qm descendant --allow-empty
  git -C "$REPO" worktree add -qb task "$BATS_TEST_TMPDIR/linked"
  run bash -c 'cd "$1" && python3 "$2" restore "$3" "$4"' _ "$BATS_TEST_TMPDIR/linked" "$SCRIPT" "$FINGERPRINT" "$CHECKPOINT"
  [ "$status" -eq 0 ]
  [ "$(sha256sum "$RECORD")" = "$original" ]
  [ "$(cat "$EVIDENCE/peer/waited-s")" = 271 ]
  [ "$(cat "$EVIDENCE/peer/round")" = 2 ]
  [ "$(cat "$EVIDENCE/peer/run-id")" = run-1 ]
  [ "$(cat "$EVIDENCE/peer/REQ-1.failures")" = missing ]
  [ "$(cat "$EVIDENCE/mutation.log")" = 'mutation detected' ]
  run restore
  [ "$status" -eq 0 ]
  run checkpoint "$EVIDENCE/peer/run-id" "$EVIDENCE/peer/waited-s" "$EVIDENCE/peer/round" "$EVIDENCE/peer/REQ-1.failures" "$EVIDENCE/mutation.log"
  [ "$status" -eq 0 ]
  [[ "$output" == *"$CHECKPOINT"* ]]
}

@test "restore rejects altered checkpoint bytes before writing any evidence" {
  save_checkpoint
  printf ' ' >>"$ARCHIVE"
  rm -- "$REPORT"
  run restore
  [ "$status" -ne 0 ]
  [[ "$output" == *'hash が一致しません'* ]]
  [ ! -e "$REPORT" ]
}

@test "restore refuses newer local ledger values without partially restoring missing files" {
  save_checkpoint
  printf '400\n' >"$EVIDENCE/peer/waited-s"
  printf '3\n' >"$EVIDENCE/peer/round"
  rm -- "$REPORT"
  run restore
  [ "$status" -ne 0 ]
  [[ "$output" == *'上書きしません'* ]]
  [ "$(cat "$EVIDENCE/peer/waited-s")" = 400 ]
  [ "$(cat "$EVIDENCE/peer/round")" = 3 ]
  [ ! -e "$REPORT" ]
}

@test "checkpoint validates the original fingerprint and artifact before archiving" {
  local good="$FINGERPRINT"
  FINGERPRINT="$(printf '%064d' 0)"
  run checkpoint
  [ "$status" -ne 0 ]
  [[ "$output" == *'fingerprint が一致しません'* ]]
  FINGERPRINT="$good"
  printf 'changed\n' >>"$REPORT"
  run checkpoint
  [ "$status" -ne 0 ]
  [[ "$output" == *'変更または移動'* ]]
  [ ! -e "$COMMON/peer-refactor-evidence" ]
}

@test "checkpoint refuses sensitive names symlinks directories and paths outside shared evidence" {
  local path
  for path in .env private.key credentials.json auth.json secret.json secrets.json service-account-test.json .ENV .envrc token.json .aws/credentials .ssh/config .config/gh/hosts.yml .docker/config.json .azure/accessTokens.json .git-credentials .credentials.json id_rsa id_ed25519 id_ecdsa id_dsa; do
    mkdir -p "$(dirname "$EVIDENCE/$path")"
    printf 'synthetic\n' >"$EVIDENCE/$path"
    run checkpoint "$EVIDENCE/$path"
    [ "$status" -ne 0 ]
    [[ "$output" == *'機密ファイル名'* ]]
  done
  ln -s "$REPORT" "$EVIDENCE/link.md"
  run checkpoint "$EVIDENCE/link.md"
  [ "$status" -ne 0 ]
  [[ "$output" == *'symlink'* ]]
  run checkpoint "$EVIDENCE/peer"
  [ "$status" -ne 0 ]
  run checkpoint "$BATS_TEST_TMPDIR/outside.md"
  [ "$status" -ne 0 ]
  [[ "$output" == *'/tmp/codex'* ]]
  [ ! -e "$COMMON/peer-refactor-evidence" ]
}

@test "checkpoint preserves an existing pinned report outside the shared run directory" {
  local previous="$REPORT"
  REPORT="$BATS_TEST_TMPDIR/external.md"
  cp "$previous" "$REPORT"
  rm -- "$RECORD"
  FINGERPRINT="$(cd "$REPO" && python3 "$PIN" pin "$REPORT" "$COMMON" "$SHA" "$CANDIDATES" "$RECORD")"
  save_checkpoint
  rm -- "$REPORT"
  run restore
  [ "$status" -eq 0 ]
  cmp "$previous" "$REPORT"
}

@test "restore refuses symlink destinations and leaves their target unchanged" {
  save_checkpoint
  local target="$BATS_TEST_TMPDIR/target"
  printf 'unchanged\n' >"$target"
  rm -- "$REPORT"
  ln -s "$target" "$REPORT"
  run restore
  [ "$status" -ne 0 ]
  [[ "$output" == *'symlink'* ]]
  [ "$(cat "$target")" = unchanged ]
}

@test "restore checks all parent paths before writing any missing evidence" {
  save_checkpoint
  rm -- "$EVIDENCE/peer/"*
  rmdir "$EVIDENCE/peer"
  printf 'unchanged\n' >"$EVIDENCE/peer"
  rm -- "$REPORT"
  run restore
  [ "$status" -ne 0 ]
  [[ "$output" == *'親パス'* ]]
  [ "$(cat "$EVIDENCE/peer")" = unchanged ]
  [ ! -e "$REPORT" ]
}

@test "restore rejects the same checkpoint copied into another repository" {
  save_checkpoint
  local other="$BATS_TEST_TMPDIR/other"
  git clone -q "$REPO" "$other"
  mkdir -p "$other/.git/peer-refactor-evidence/$FINGERPRINT"
  cp "$ARCHIVE" "$other/.git/peer-refactor-evidence/$FINGERPRINT/"
  rm -- "$REPORT"
  run bash -c 'cd "$1" && python3 "$2" restore "$3" "$4"' _ "$other" "$SCRIPT" "$FINGERPRINT" "$CHECKPOINT"
  [ "$status" -ne 0 ]
  [[ "$output" == *'別の Git リポジトリ'* ]]
  [ ! -e "$REPORT" ]
}

@test "restore validates candidate provenance even for an internally consistent checkpoint" {
  save_checkpoint
  CHECKPOINT="$(
    python3 - "$ARCHIVE" <<'PY'
import base64, hashlib, json, sys
from pathlib import Path
p = Path(sys.argv[1])
data = json.loads(p.read_bytes())
record_path = data['record_path']
record = json.loads(base64.b64decode(data['files'][record_path]))
record['candidates'][0]['acceptance'] = ['changed intent']
data['files'][record_path] = base64.b64encode(json.dumps(record).encode()).decode()
raw = json.dumps(data).encode()
digest = hashlib.sha256(raw).hexdigest()
p.with_name(digest + '.json').write_bytes(raw)
print(digest)
PY
  )"
  rm -- "$REPORT"
  run restore
  [ "$status" -ne 0 ]
  [[ "$output" == *'fingerprint が一致しません'* ]]
  [ ! -e "$REPORT" ]
}

@test "standalone evidence tests prepare a private shared root and reject unsafe roots" {
  run python3 - "$BATS_TEST_DIRNAME/.." "$EVIDENCE" <<'PY'
import os, re, shlex, stat, subprocess, sys
from pathlib import Path

root = Path(sys.argv[1]).resolve()
evidence = Path(sys.argv[2])
source = (root / 'tests/run-evidence.bats').read_text()
assignment = '  project_root="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"'
assert source.splitlines().count(assignment) == 1
for kind in ['missing', 'owned', 'file', 'symlink', 'dangling']:
    shared = evidence / f'shared-{kind}'
    if kind == 'owned':
        shared.mkdir(mode=0o700)
        (shared / 'keep').write_text('unchanged')
    elif kind == 'file':
        shared.write_text('unchanged')
    elif kind == 'symlink':
        (evidence / 'link-target').mkdir(mode=0o700)
        (evidence / 'link-target' / 'keep').write_text('unchanged')
        shared.symlink_to(evidence / 'link-target')
    elif kind == 'dangling':
        shared.symlink_to(evidence / 'missing-target')
    fixture = evidence / f'{kind}.bats'
    fixture.write_text(source.replace('/tmp/codex', str(shared)).replace(assignment, '  project_root=' + shlex.quote(str(root)), 1))
    result = subprocess.run(['bats', '--tap', '--print-output-on-failure', '--filter', '^checkpoint validates the original fingerprint', str(fixture)], capture_output=True, text=True)
    if kind in ['missing', 'owned']:
        assert result.returncode == 0, result.stdout + result.stderr
        assert shared.is_dir() and not shared.is_symlink()
        assert shared.stat().st_uid == os.getuid()
        assert stat.S_IMODE(shared.stat().st_mode) == 0o700
        assert list(shared.iterdir()) == ([] if kind == 'missing' else [shared / 'keep'])
    else:
        assert result.returncode != 0, kind
        assert 'setup_file failed' in result.stdout, result.stdout
        if kind == 'file':
            assert shared.read_text() == 'unchanged'
        elif kind == 'symlink':
            assert shared.is_symlink()
            assert list((evidence / 'link-target').iterdir()) == [evidence / 'link-target' / 'keep']
        else:
            assert shared.is_symlink() and not (evidence / 'missing-target').exists()

setup_file = re.search(r'^setup_file\(\) \{\n.*?^\}', source, re.M | re.S).group()
if Path('/').stat().st_uid != os.getuid():
    rejected = subprocess.run(['bash', '-c', setup_file.replace('/tmp/codex', '/') + '\nsetup_file'], capture_output=True, text=True)
    assert rejected.returncode != 0
teardown = re.search(r'^teardown\(\) \{\n.*?^\}', source, re.M | re.S).group()
for state in ['unset EVIDENCE', "EVIDENCE=''"]:
    result = subprocess.run(['bash', '-c', 'set -u\n' + teardown + '\n' + state + '\nteardown'], capture_output=True, text=True)
    assert result.returncode == 0, result.stderr
PY
  [ "$status" -eq 0 ]
}

@test "restore cleans up failed writes but preserves a concurrently created destination" {
  save_checkpoint
  run python3 - "$SCRIPT" "$REPO" "$REPORT" "$FINGERPRINT" "$CHECKPOINT" <<'PY'
import os, runpy, sys
from pathlib import Path
from unittest.mock import patch

script, repo, report, fingerprint, checkpoint = sys.argv[1:]
os.chdir(repo)
restore = runpy.run_path(script)['restore']
report = Path(report)
original = report.read_bytes()
actual_open, actual_chmod = Path.open, os.fchmod

class FailingStream:
    def __init__(self, stream, fault):
        self.stream, self.fault = stream, fault
    def __enter__(self):
        self.stream.__enter__()
        return self
    def __exit__(self, *args):
        self.stream.__exit__(*args)
        if self.fault == 'close':
            raise OSError('injected close failure')
    def fileno(self):
        return self.stream.fileno()
    def write(self, content):
        if self.fault == 'write':
            self.stream.write(content[:3])
            self.stream.flush()
            raise OSError('injected write failure')
        return self.stream.write(content)

for fault in ['chmod', 'write', 'close', 'concurrent']:
    report.unlink()
    def faulty_open(path, mode='r', *args, **kwargs):
        if path != report or mode != 'xb':
            return actual_open(path, mode, *args, **kwargs)
        if fault == 'concurrent':
            with actual_open(path, 'xb') as stream:
                stream.write(b'newer evidence')
        stream = actual_open(path, mode, *args, **kwargs)
        return FailingStream(stream, fault)
    chmod = OSError('injected chmod failure') if fault == 'chmod' else actual_chmod
    with patch.object(Path, 'open', faulty_open), patch.object(os, 'fchmod', side_effect=chmod):
        try:
            restore(fingerprint, checkpoint)
        except OSError as error:
            if fault == 'concurrent':
                assert isinstance(error, FileExistsError), error
            else:
                assert str(error) == f'injected {fault} failure', error
        else:
            raise AssertionError(f'{fault}: expected restore failure')
    if fault == 'concurrent':
        assert report.read_bytes() == b'newer evidence'
        report.unlink()
    else:
        assert not report.exists(), f'{fault}: incomplete evidence remains'
    restore(fingerprint, checkpoint)
    assert report.read_bytes() == original
PY
  [ "$status" -eq 0 ]
}

@test "Orca receipt example validates before publishing and reuses saved worker receipts" {
  run python3 - "$BATS_TEST_DIRNAME/.." "$EVIDENCE" <<'PY'
import json, os, subprocess, sys
from pathlib import Path
from unittest.mock import patch

root, run = (Path(p).resolve() for p in sys.argv[1:])
receipt = run / 'worker-one'
receipt.mkdir()
(run / 'run-create.json').write_text(json.dumps({'ok': True, 'result': {'run': {'id': 'run-1', 'coordinator_handle': 'parent-1'}}}))
(receipt / 'worker-start.json').write_text(json.dumps({'result': {'dispatchId': 'dispatch-1', 'taskId': 'task-1', 'effects': [{'kind': 'terminal', 'role': 'agent', 'id': 'worker-1'}]}}))
doc = root / 'local-skills/orca-peer-refactor/references/orca.md'
source = doc.read_text().split("<<'PY'\n", 1)[1].split('\nPY\n```', 1)[0]
source = source.replace('<skill-dir>', str(root / 'local-skills/orca-peer-refactor'))
actual_run = subprocess.run
queries = []
worker_output = json.dumps({'ok': True, 'result': {'dispatch': {'id': 'dispatch-1', 'taskId': 'task-1', 'assigneeHandle': 'worker-1', 'status': 'dispatched'}}})
def fake_orca(argv, **kwargs):
    if argv[0] != 'orca-ide':
        return actual_run(argv, **kwargs)
    if 'worker-show' in argv:
        queries.append(argv)
        return subprocess.CompletedProcess(argv, 0, stdout=worker_output)
    return subprocess.CompletedProcess(argv, 0, stdout=json.dumps({'result': {'runId': 'run-1'}}))

valid_output = worker_output
for name, worker_output in [('malformed', '{"ok":'), ('rejected', '{"ok":false,"result":{}}'), ('mismatch', valid_output.replace('dispatch-1', 'dispatch-other'))]:
    failed_receipt = run / name
    failed_receipt.mkdir()
    (failed_receipt / 'worker-start.json').write_bytes((receipt / 'worker-start.json').read_bytes())
    with patch.object(sys, 'argv', ['example', str(run), str(failed_receipt)]), patch.dict(os.environ, {'ORCA_TERMINAL_HANDLE': 'parent-1'}), patch.object(subprocess, 'run', fake_orca):
        try:
            exec(compile(source, str(doc), 'exec'), {})
        except subprocess.CalledProcessError:
            pass
        else:
            raise AssertionError(f'{name}: invalid receipt was accepted')
        assert not (failed_receipt / 'worker-show.json').exists(), name
        pending = failed_receipt / 'worker-show.json.part'
        assert pending.read_text() == worker_output, name
        before_retry = len(queries)
        try:
            exec(compile(source, str(doc), 'exec'), {})
        except SystemExit:
            pass
        else:
            raise AssertionError(f'{name}: unfinished receipt was ignored')
        assert len(queries) == before_retry, name
        assert pending.read_text() == worker_output, name

worker_output = valid_output
queries.clear()

with patch.object(sys, 'argv', ['example', str(run), str(receipt)]), patch.dict(os.environ, {'ORCA_TERMINAL_HANDLE': 'parent-1'}), patch.object(subprocess, 'run', fake_orca):
    exec(compile(source, str(doc), 'exec'), {})
    original = (receipt / 'worker-show.json').read_bytes()
    exec(compile(source, str(doc), 'exec'), {})
assert len(queries) == 1, queries
assert (receipt / 'worker-show.json').read_bytes() == original
PY
  [ "$status" -eq 0 ]
}

@test "Orca shell receipt examples publish only complete successful output and preserve failed attempts" {
  run python3 - "$BATS_TEST_DIRNAME/.." "$EVIDENCE" <<'PY'
import json, os, re, subprocess, sys
from pathlib import Path

root, evidence = (Path(p).resolve() for p in sys.argv[1:])
doc = root / 'local-skills/orca-peer-refactor/references/orca.md'
examples = re.findall(r'\(set -C\b.*?\)', doc.read_text(), re.S)
assert len(examples) == 5, examples
binary = evidence / 'bin'
binary.mkdir()
fake = binary / 'ORCA'
fake.write_text('''#!/usr/bin/env python3
import os, signal, sys
with open(os.environ['RECEIPT_CALLS'], 'a') as stream:
    stream.write('called\\n')
sys.stdout.write(os.environ['RECEIPT_OUTPUT'])
sys.stdout.flush()
if os.environ['RECEIPT_MODE'] == 'interrupted':
    os.kill(os.getpid(), signal.SIGTERM)
sys.exit(1 if os.environ['RECEIPT_MODE'] == 'failed' else 0)
''')
fake.chmod(0o700)
complete = json.dumps({'ok': True, 'result': {'id': 'receipt-1'}})
for index, example in enumerate(examples):
    command = re.sub(r'<[^>]+>', 'fixture', example)
    operation = re.search(r'ORCA orchestration (run-create|worker-start|worker-show)', command).group(1)
    for mode, output in [('failed', complete), ('interrupted', '{"ok":'), ('empty', ''), ('malformed', '{"ok":'), ('success', complete), ('existing', complete)]:
        folder = evidence / f'{index}-{mode}'
        folder.mkdir()
        final = folder / f'{operation}.json'
        pending = folder / f'{operation}.json.part'
        calls = folder / 'calls'
        env = dict(os.environ, PATH=str(binary) + os.pathsep + os.environ['PATH'], RECEIPT_MODE=mode, RECEIPT_OUTPUT=output, RECEIPT_CALLS=str(calls))
        env.update({key: str(folder) for key in ['run_dir', 'receipt_dir', 'child_run_dir', 'child_receipt_dir']})
        if mode == 'existing':
            final.write_text('original receipt\n')
        result = subprocess.run(['bash', '-c', command], env=env, capture_output=True, text=True)
        if mode == 'success':
            assert result.returncode == 0, result.stderr
            assert final.read_text() == complete
        elif mode == 'existing':
            assert result.returncode != 0
            assert final.read_text() == 'original receipt\n'
            assert not calls.exists(), command
        else:
            assert result.returncode != 0, (mode, command)
            assert not final.exists(), (mode, command)
            assert pending.read_text() == output
            before_retry = calls.read_bytes()
            retried = subprocess.run(['bash', '-c', command], env=env, capture_output=True, text=True)
            assert retried.returncode != 0
            assert calls.read_bytes() == before_retry, command
            assert pending.read_text() == output

for index, heading in enumerate(['### coordinator\n', '### nested coordinator\n']):
    block = doc.read_text().split(heading, 1)[1].split('```text\n', 1)[1].split('\n```', 1)[0]
    block = block.replace('<skill-dir>', str(root / 'local-skills/orca-peer-refactor'))
    command = re.sub(r'<[^>]+>', 'fixture', block)
    for mode in ['failed', 'interrupted', 'malformed']:
        folder = evidence / f'sequence-{index}-{mode}'
        folder.mkdir()
        calls = folder / 'calls'
        env = dict(os.environ, PATH=str(binary) + os.pathsep + os.environ['PATH'], run_dir=str(folder), RECEIPT_MODE=mode, RECEIPT_OUTPUT='{"ok":', RECEIPT_CALLS=str(calls))
        result = subprocess.run(['bash', '-c', command], env=env, capture_output=True, text=True)
        assert result.returncode != 0, (heading, mode)
        assert calls.read_text().splitlines() == ['called'], (heading, mode, 'later operation ran')
PY
  [ "$status" -eq 0 ]
}
