"""Run blind source-grounded reviews and apply the predeclared adoption gate."""
import argparse
import concurrent.futures
import json
from aggregation import reaggregate
from experiment import WORK, HERE, verify, invoke, decode_model, save


def review(case, manifest):
    source = WORK / 'blind' / f"{case['id']}.json"
    dest = WORK / 'reviews' / case['id']
    if (dest / 'review.json').exists():
        return case['id'], 'recorded'
    if dest.exists():
        raise RuntimeError('Partial review exists: ' + str(dest))
    packet = json.loads(source.read_text())
    prompt = (HERE / 'evaluator.md').read_text() + '\nINPUT\n' + source.read_text()
    result = invoke(prompt, dest, manifest, timeout=1200)
    save(dest / 'result.json', result)
    if result['exit_code'] or result['tool_calls']:
        raise RuntimeError('Review failed: ' + case['id'])
    data = decode_model((dest / 'response.txt').read_text())
    validate_review(data, packet)
    save(dest / 'review.json', data)
    return case['id'], 'complete'


def validate_review(data, packet):
    if data.get('case') != packet['case']:
        raise ValueError('Wrong case')
    models = {m['id']: m for m in packet['models']}
    expected = set(models)
    actual = [s['id'] for s in data['scores']]
    if set(actual) != expected or len(actual) != len(expected):
        raise ValueError('Missing or duplicate run scores')
    requirements = {r['id'] for r in packet['gold']['requirements']}
    for score in data['scores']:
        actual = [r['id'] for r in score['requirements']]
        if set(actual) != requirements or len(actual) != len(requirements):
            raise ValueError('Missing or duplicate requirement scores')
        for req in score['requirements']:
            if type(req['fulfilled']) is not bool or not req.get('reason') or not isinstance(req.get('evidence'), list):
                raise ValueError('Incomplete requirement rationale')
        for claim in score['false_assertions']:
            if type(claim['critical']) is not bool or not claim.get('description') or not claim.get('evidence'):
                raise ValueError('Unsupported false assertion')
        if not isinstance(score['unknowns'], list):
            raise ValueError('Invalid unknowns')
        if models[score['id']]['model'] is None and (
                any(r['fulfilled'] for r in score['requirements'])
                or score['false_assertions'] or score['unknowns']):
            raise ValueError('Absent model has semantic review results')


def summarize(manifest):
    verify(manifest)
    scores = {}
    for case in manifest['cases']:
        packet = json.loads((WORK / 'blind' / f"{case['id']}.json").read_text())
        data = json.loads((WORK / 'reviews' / case['id'] / 'review.json').read_text())
        validate_review(data, packet)
        scores.update({s['id']: s for s in data['scores']})
    observations = []
    for run in manifest['runs']:
        s = scores[run['id']]
        status = json.loads((WORK / 'runs' / run['id'] / 'result.json').read_text())
        fulfilled = sum(r['fulfilled'] for r in s['requirements']) if status['valid'] else 0
        row = {**run, 'valid': status['valid'], 'fulfilled': fulfilled,
               'missing': len(s['requirements']) - fulfilled, 'false': len(s['false_assertions']),
               'critical': sum(f['critical'] for f in s['false_assertions']),
               'unknowns': len(s['unknowns']), 'duration_seconds': status['duration_seconds'],
               'usage': status['usage']}
        observations.append(row)
    result = reaggregate({'observations': observations,
                          'interpretation': 'Descriptive three-repeat comparison, not statistical superiority.'},
                         manifest['cases'])
    save(WORK / 'summary.json', result)
    print(json.dumps({'aggregate': result['aggregate'], 'decisions': result['decisions']}, ensure_ascii=False, indent=2))


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('action', choices=['review', 'summarize'])
    args = parser.parse_args()
    manifest = json.loads((WORK / 'manifest.json').read_text())
    verify(manifest)
    if args.action == 'review':
        with concurrent.futures.ThreadPoolExecutor(max_workers=3) as pool:
            for result in pool.map(lambda c: review(c, manifest), manifest['cases']):
                print(result, flush=True)
    else:
        summarize(manifest)
