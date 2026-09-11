"""Run blind source-grounded reviews and apply the predeclared adoption gate."""
import argparse
import concurrent.futures
import json
from collections import defaultdict
from statistics import mean
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
    expected = {m['id'] for m in packet['models']}
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


def qualifies(candidate, baseline):
    return (candidate['critical'] == 0 and candidate['false_mean'] < baseline['false_mean']
            and candidate['failures'] <= baseline['failures']
            and all(candidate['by_case'][key]['fulfilled_mean'] >= value['fulfilled_mean']
                    for key, value in baseline['by_case'].items()))


def summarize(manifest):
    verify(manifest)
    scores = {}
    for case in manifest['cases']:
        packet = json.loads((WORK / 'blind' / f"{case['id']}.json").read_text())
        data = json.loads((WORK / 'reviews' / case['id'] / 'review.json').read_text())
        validate_review(data, packet)
        scores.update({s['id']: s for s in data['scores']})
    groups = defaultdict(list)
    case_languages = {c['id']: c['language'] for c in manifest['cases']}
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
        groups[(case_languages[run['case']], run['condition'])].append(row)
    aggregate = {}
    for (language, condition), rows in groups.items():
        by_case = {}
        for case in sorted({r['case'] for r in rows}):
            subset = [r for r in rows if r['case'] == case]
            by_case[case] = {'fulfilled_mean': mean(r['fulfilled'] for r in subset),
                             'false_mean': mean(r['false'] for r in subset),
                             'failures': sum(not r['valid'] for r in subset)}
        aggregate.setdefault(language, {})[condition] = {
            'n': len(rows), 'false_mean': mean(r['false'] for r in rows),
            'fulfilled_mean': mean(r['fulfilled'] for r in rows),
            'critical': sum(r['critical'] for r in rows), 'failures': sum(not r['valid'] for r in rows),
            'by_case': by_case}
    decisions = {}
    burden = {'ast-grep': 0, 'ts-morph': 1, 'syn': 1, 'rust-analyzer': 2}
    for language, conditions in aggregate.items():
        candidates = [c for c in conditions if c != 'baseline' and qualifies(conditions[c], conditions['baseline'])]
        candidates.sort(key=lambda c: (conditions[c]['false_mean'], -conditions[c]['fulfilled_mean'], burden[c]))
        decisions[language] = {'qualifying': candidates, 'recommendation': candidates[0] if candidates else 'retain baseline'}
    result = {'observations': observations, 'aggregate': aggregate, 'decisions': decisions,
              'interpretation': 'Descriptive three-repeat comparison, not statistical superiority.'}
    save(WORK / 'summary.json', result)
    print(json.dumps({'aggregate': aggregate, 'decisions': decisions}, ensure_ascii=False, indent=2))


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
