"""PROTOTYPE: deterministic filesystem probe, not an LLM evaluator."""
import errno
import hashlib
import json
import os
from pathlib import Path
import sys

config = json.load(sys.stdin)
hashes = {str(p.relative_to('/inputs')): hashlib.sha256(p.read_bytes()).hexdigest()
          for p in Path('/inputs').rglob('*') if p.is_file()}
targets = dict(config['forbidden'])
os.symlink(targets['canary'], '/tmp/escape')
targets['symlink'] = '/tmp/escape'
targets['proc_root'] = '/proc/1/root' + targets['canary']
targets['traversal'] = '/inputs/..' + targets['canary']
reads = {}
for label, path in targets.items():
    try:
        with open(path, 'rb') as f:
            f.read(1)
        reads[label] = {'readable': True, 'errno': None}
    except OSError as e:
        reads[label] = {'readable': False, 'errno': e.errno}
try:
    with open('/inputs/SKILL.md', 'ab') as f:
        f.write(b'PROTOTYPE unexpected writable input')
    write_errno = None
except OSError as e:
    write_errno = e.errno
result = {
    'hashes': hashes, 'forbidden_reads': reads, 'input_write_errno': write_errno,
    'environment_sentinel_visible': 'PROTOTYPE_HOST_ONLY' in os.environ,
    'network_namespace': os.readlink('/proc/self/ns/net'),
    'root_entries': sorted(os.listdir('/')), 'cwd': os.getcwd(),
}
result['ok'] = (hashes == config['expected'] and
                all(not r['readable'] and r['errno'] in (errno.ENOENT, errno.EACCES)
                    for r in reads.values()) and write_errno == errno.EROFS and
                not result['environment_sentinel_visible'] and
                result['network_namespace'] != config['host_network_namespace'])
print(json.dumps(result))
sys.exit(0 if result['ok'] else 1)
