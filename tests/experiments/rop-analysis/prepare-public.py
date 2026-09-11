"""Materialize locked public projects from the archives recorded by the research step."""
import json
import subprocess
from prepare import REPO, WORK, write
from public_snapshot import prepare_snapshot

metadata = json.loads((REPO / 'docs/research/rop-public-inputs.json').read_text())
cases = json.loads((WORK / 'cases-local.json').read_text())
for item in metadata['inputs']:
    archive = REPO / item['snapshot']['archive']
    root = prepare_snapshot(item, REPO)
    if item['id'].startswith('effect'):
        runtime = archive.parent / 'runtime'
        write(runtime / 'package.json', json.dumps({'private': True, 'dependencies': {
            'effect': '3.9.2', '@effect/schema': '0.75.4', 'find-my-way-ts': '0.1.5', 'multipasta': '0.2.5'}}))
        subprocess.run(['npm', 'install', '--ignore-scripts', '--no-audit', '--no-fund'], cwd=runtime, check=True)
        modules = root / 'node_modules'
        if not modules.exists() and not modules.is_symlink():
            modules.symlink_to((runtime / 'node_modules').resolve(), target_is_directory=True)
        write(root / 'tsconfig.experiment.json', json.dumps({'compilerOptions': {
            'target': 'ES2022', 'module': 'ESNext', 'moduleResolution': 'Bundler',
            'strict': True, 'skipLibCheck': True, 'noEmit': True,
            'paths': {'@effect/platform/*': ['./packages/platform/src/*']}},
            'include': ['packages/platform/src/internal/httpClient.ts']}))
        cases.append({'id': 'effect-public', 'language': 'ts', 'root': str(root),
            'entry': 'packages/platform/src/internal/httpClient.ts:retryTransient',
            'files': ['packages/platform/src/internal/httpClient.ts'],
            'ranges': {'packages/platform/src/internal/httpClient.ts': [[263, 278], [565, 599]]},
            'config': 'tsconfig.experiment.json',
            'scope': 'retryTransient and transformResponse only. Describe client construction separately from the response effect when executed. Original client, Effect.retry internals, and Schedule behavior are named boundaries; use the explicit predicate and public signatures without inventing retry counts or delays.'})
    else:
        cases.append({'id': 'rust-public', 'language': 'rust', 'root': str(root),
            'entry': 'crates/core/main.rs:main', 'files': ['crates/core/main.rs'],
            'ranges': {'crates/core/main.rs': [[44, 107]]}, 'config': 'Cargo.toml',
            'cargoFeatures': ['unstable-index'],
            'scope': 'main and run only, with unstable-index enabled on Linux. Called search/files/index/parser and logging implementations are named boundaries. Explain main exit outcomes, never turn the exit-code conversion into resuming run.'})
write(WORK / 'cases.json', json.dumps(cases, indent=2))
