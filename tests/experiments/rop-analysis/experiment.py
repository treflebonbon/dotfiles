"""Freeze, run, validate and blind a reproducible ROP evidence comparison."""
import argparse
import concurrent.futures
import hashlib
import importlib.util
import json
import random
import subprocess
import sys
import time
import tomllib
from pathlib import Path
from extract import HERE, REPO, WORK, extract, environment

sys.dont_write_bytecode = True

CONDITIONS = {'ts': ['baseline', 'ast-grep', 'ts-morph'],
              'rust': ['baseline', 'ast-grep', 'syn', 'rust-analyzer']}


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def save(path, value):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2))


def run_matrix(cases):
    runs = [{'case': c['id'], 'condition': condition, 'repeat': repeat}
            for c in cases for condition in CONDITIONS[c['language']] for repeat in range(1, 4)]
    random.Random(20260911).shuffle(runs)
    return [dict(run, id=f'run-{i:03}') for i, run in enumerate(runs, 1)]


def source_text(case):
    sections = []
    for file in case['files']:
        lines = (Path(case['root']) / file).read_text().splitlines()
        ranges = case.get('ranges', {}).get(file, [[1, len(lines)]])
        for lo, hi in ranges:
            sections.append(f'FILE {file} L{lo}-L{hi}\n' + '\n'.join(
                f'{i}: {lines[i - 1]}' for i in range(lo, hi + 1)))
    return '\n\n'.join(sections)


def freeze():
    if (WORK / 'manifest.json').exists():
        raise RuntimeError('Manifest already frozen; use verify, not freeze')
    cases = json.loads((WORK / 'cases.json').read_text())
    gold = json.loads((HERE / 'gold.json').read_text())
    assert len(cases) == 7 and len(run_matrix(cases)) == 75
    assert {c['id'] for c in cases} == {c['id'] for c in gold['cases']}
    config = tomllib.loads((Path.home() / '.codex/config.toml').read_text())
    files = set(p for p in HERE.rglob('*') if p.is_file() and
                'node_modules' not in p.parts and '__pycache__' not in p.parts)
    files.update([REPO / 'docs/research/rop-public-inputs.json',
                  WORK / 'preflight/tool-paths.txt',
                  REPO / 'local-skills/rop-visualizer/scripts/render.py',
                  REPO / 'local-skills/rop-visualizer/references/report-format.md'])
    for case in cases:
        root = Path(case['root'])
        files.update(root / file for file in case['files'])
        for name in [case['config'], 'Cargo.lock', 'package-lock.json', 'package.json']:
            if (root / name).exists():
                files.add(root / name)
        for condition in CONDITIONS[case['language']][1:]:
            print('extract', case['id'], condition, flush=True)
            start = time.monotonic()
            data = extract(case, condition)
            data['extraction_seconds'] = time.monotonic() - start
            dest = WORK / 'evidence' / case['id'] / f'{condition}.json'
            save(dest, data)
            files.add(dest)
    for lock in (WORK / 'public').glob('*/runtime/package-lock.json'):
        files.add(lock)
    manifest = {'schema_version': 1, 'seed': 20260911,
                'model': config['model'], 'reasoning_effort': config['model_reasoning_effort'],
                'codex_version': subprocess.check_output(['codex', '--version'], text=True).strip(),
                'tool_versions': {Path(p).name: subprocess.check_output([p, '--version'], text=True).strip()
                                  for p in (WORK / 'preflight/tool-paths.txt').read_text().splitlines()},
                'cases': cases, 'runs': run_matrix(cases),
                'sha256': {str(p.relative_to(REPO)): digest(p) for p in sorted(files)}}
    save(WORK / 'manifest.json', manifest)
    print('Frozen', len(manifest['sha256']), 'files and', len(manifest['runs']), 'runs')


def verify(manifest):
    changed = [file for file, expected in manifest['sha256'].items()
               if not (REPO / file).is_file() or digest(REPO / file) != expected]
    if changed:
        raise RuntimeError('Frozen input drift: ' + ', '.join(changed))


def decode_model(text):
    text = text.strip()
    if text.startswith('```') and text.endswith('```'):
        text = text.split('\n', 1)[1].rsplit('```', 1)[0]
    result = json.loads(text)
    if not isinstance(result, dict):
        raise ValueError('Model is not an object')
    return result


def validate(model_path, case):
    spec = importlib.util.spec_from_file_location('renderer', REPO / 'local-skills/rop-visualizer/scripts/render.py')
    renderer = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(renderer)
    model = renderer.load_model(model_path, Path(case['root']))
    for node in model['nodes']:
        if node.get('source'):
            src = node['source']
            if src['path'] not in case['files']:
                raise ValueError('Source outside permitted files')
            if case.get('ranges') and not any(lo <= src['start'] <= src.get('end', src['start']) <= hi
                    for lo, hi in case['ranges'].get(src['path'], [])):
                raise ValueError('Source outside permitted ranges')
    return renderer.diagram(model)


def producer_prompt(case, condition):
    prompt = (HERE / 'producer.md').read_text()
    prompt += '\nREPORT FORMAT\n' + (REPO / 'local-skills/rop-visualizer/references/report-format.md').read_text()
    prompt += f"\nENTRY: {case['entry']}\nSCOPE: {case['scope']}\nSOURCE\n{source_text(case)}"
    if condition != 'baseline':
        data = json.loads((WORK / 'evidence' / case['id'] / f'{condition}.json').read_text())
        data.pop('extraction_seconds', None)
        prompt += '\nSUPPLEMENTAL EVIDENCE\n' + json.dumps(data, ensure_ascii=False)
    return prompt


def invoke(prompt, destination, manifest, timeout=900):
    destination.mkdir(parents=True, exist_ok=True)
    (destination / 'prompt.txt').write_text(prompt)
    isolated = WORK / 'isolated'
    isolated.mkdir(exist_ok=True)
    command = ['codex', 'exec', '--ephemeral', '--sandbox', 'read-only', '--skip-git-repo-check',
               '--cd', str(isolated), '--json', '--color', 'never', '--model', manifest['model'],
               '-c', f'model_reasoning_effort="{manifest["reasoning_effort"]}"',
               '-o', str(destination / 'response.txt'), '-']
    start = time.monotonic()
    with (destination / 'events.jsonl').open('w') as out, (destination / 'stderr.txt').open('w') as err:
        try:
            proc = subprocess.run(command, input=prompt, text=True, stdout=out, stderr=err, timeout=timeout)
            code = proc.returncode
        except subprocess.TimeoutExpired:
            code = 124
    events = []
    for line in (destination / 'events.jsonl').read_text().splitlines():
        try:
            events.append(json.loads(line))
        except json.JSONDecodeError:
            pass
    usage = next((e.get('usage') for e in reversed(events) if e.get('type') == 'turn.completed'), None)
    tool_calls = [e for e in events if e.get('type') == 'item.completed' and
                  e.get('item', {}).get('type') in ('command_execution', 'mcp_tool_call', 'web_search', 'file_change')]
    return {'exit_code': code, 'duration_seconds': time.monotonic() - start,
            'usage': usage, 'tool_calls': len(tool_calls)}


def produce(run, manifest):
    case = next(c for c in manifest['cases'] if c['id'] == run['case'])
    dest = WORK / 'runs' / run['id']
    if (dest / 'result.json').exists():
        return run['id'], 'already recorded'
    if dest.exists():
        raise RuntimeError(f'Partial run {run["id"]}; inspect instead of rerunning')
    status = invoke(producer_prompt(case, run['condition']), dest, manifest)
    try:
        if status['exit_code'] or status['tool_calls']:
            raise ValueError('Generation failed or producer used prohibited tools')
        model = decode_model((dest / 'response.txt').read_text())
        save(dest / 'flow.json', model)
        mermaid = validate(dest / 'flow.json', case)
        (dest / 'flow.mmd').write_text(mermaid)
        status['valid'] = True
    except (ValueError, OSError, KeyError, TypeError, IndexError) as error:
        status.update(valid=False, error=str(error))
    save(dest / 'result.json', status)
    return run['id'], status['valid']


def generate(manifest, workers):
    verify(manifest)
    with concurrent.futures.ThreadPoolExecutor(max_workers=workers) as pool:
        futures = [pool.submit(produce, r, manifest) for r in manifest['runs']]
        for future in concurrent.futures.as_completed(futures):
            print(*future.result(), flush=True)
    verify(manifest)


def blind(manifest):
    verify(manifest)
    gold = {c['id']: c for c in json.loads((HERE / 'gold.json').read_text())['cases']}
    for case in manifest['cases']:
        models = []
        for run in manifest['runs']:
            if run['case'] != case['id']:
                continue
            dest = WORK / 'runs' / run['id']
            status = json.loads((dest / 'result.json').read_text())
            models.append({'id': run['id'], 'valid': status['valid'],
                           'model': json.loads((dest / 'flow.json').read_text()) if (dest / 'flow.json').exists() else None,
                           'validation_error': status.get('error')})
        save(WORK / 'blind' / f"{case['id']}.json", {'case': case['id'], 'entry': case['entry'],
            'scope': case['scope'], 'source': source_text(case), 'gold': gold[case['id']], 'models': models})


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('action', choices=['freeze', 'verify', 'generate', 'blind'])
    parser.add_argument('--workers', type=int, default=3)
    args = parser.parse_args()
    if args.action == 'freeze':
        freeze()
    else:
        manifest = json.loads((WORK / 'manifest.json').read_text())
        if args.action == 'verify': verify(manifest)
        elif args.action == 'generate': generate(manifest, args.workers)
        elif args.action == 'blind': blind(manifest)
