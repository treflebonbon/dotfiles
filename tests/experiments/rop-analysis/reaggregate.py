"""Recompute historical result metrics without regenerating or rewriting frozen records."""
import hashlib
import json
from aggregation import reaggregate
from experiment import WORK, save


def verify_snapshot(manifest, snapshot):
    for name, expected in manifest['sha256'].items():
        path = snapshot / name
        if not path.is_file() or hashlib.sha256(path.read_bytes()).hexdigest() != expected:
            raise RuntimeError('Archived frozen input drift: ' + name)


def main():
    manifest = json.loads((WORK / 'manifest.json').read_text())
    verify_snapshot(manifest, WORK / 'frozen-source')
    for name in ('summary', 'sensitivity'):
        source = WORK / f'{name}.json'
        original = json.loads(source.read_text())
        result = reaggregate(original, manifest['cases'])
        if result['decisions'] != original['decisions']:
            raise RuntimeError('Reporting-only revision changed adoption decisions')
        result['aggregation_revision'] = {
            'reason': 'Code review: include all protocol means and share adoption selection.',
            'source': source.name,
            'source_sha256': hashlib.sha256(source.read_bytes()).hexdigest(),
            'frozen_manifest_sha256': hashlib.sha256((WORK / 'manifest.json').read_bytes()).hexdigest(),
            'verification': 'All original frozen files verified in frozen-source; current analysis code is a post-review revision.',
        }
        save(WORK / f'{name}-reviewed.json', result)
        print(name, len(result['observations']), 'observations; decisions unchanged')


if __name__ == '__main__':
    main()
