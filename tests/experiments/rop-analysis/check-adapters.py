"""Native smoke checks before freeze; never treat syntax-only output as type facts."""
import json
import subprocess
import tempfile
from pathlib import Path
from extract import WORK, extract, environment

cases = json.loads((WORK / 'cases.json').read_text())
for case in cases:
    if case['language'] == 'ts':
        evidence = extract(case, 'ts-morph')
        assert not evidence['diagnostics'], (case['id'], evidence['diagnostics'])
        if case['id'] == 'ts-symbols':
            fake = [n for n in evidence['nodes'] if n['kind'] == 'CallExpression' and n['text'].startswith('new Label')]
            assert fake and fake[0]['declarations'][0]['path'] == 'src/main.ts', fake
    else:
        command = ['cargo', 'check', '--locked']
        if case.get('cargoFeatures'):
            command += ['--features', ','.join(case['cargoFeatures'])]
        checked = subprocess.run(command, cwd=case['root'], env=environment(), capture_output=True, text=True)
        assert checked.returncode == 0, checked.stderr
        evidence = extract(case, 'syn')
        assert all(n['type'] is None for n in evidence['nodes'])
        if case['id'] == 'rust-symbols':
            nodes = evidence['nodes']
            assert any(n['kind'] == 'try' and n['scope'] is not None and
                       nodes[n['scope']]['kind'] == 'closure' for n in nodes)
    syntax = extract(case, 'ast-grep')
    assert syntax['nodes'] and all(n['type'] is None for n in syntax['nodes'])
    for node in syntax['nodes']:
        lines = (Path(case['root']) / node['path']).read_text().splitlines()
        assert 1 <= node['start'] <= node['end'] <= len(lines)
    print(case['id'], 'PASS', flush=True)

with tempfile.TemporaryDirectory(dir=WORK) as directory:
    file = Path(directory) / 'unicode.rs'
    file.write_text('fn f() { let café = 1; consume(café); }\n')
    proc = subprocess.run([str(WORK / 'build/debug/rop-syn-extractor'), 'unicode.rs'],
                          cwd=directory, env=environment(), capture_output=True, text=True, check=True)
    nodes = json.loads(proc.stdout)['nodes']
    call = next(n for n in nodes if n['kind'] == 'call')
    assert call['text'] == 'consume(café)', call
print('UTF-8 source spans PASS')
