"""Shared descriptive metrics and the unchanged language-specific adoption gate."""
from collections import defaultdict
from statistics import mean


def metrics(rows):
    return {
        'n': len(rows),
        **{f'{field}_mean': mean(r[field] for r in rows)
           for field in ('false', 'fulfilled', 'missing', 'unknowns', 'critical')},
        'failure_mean': mean(not r['valid'] for r in rows),
        'critical_total': sum(r['critical'] for r in rows),
        'failures_total': sum(not r['valid'] for r in rows),
    }


def aggregate_observations(observations, cases):
    languages = {c['id']: c['language'] for c in cases}
    groups = defaultdict(list)
    for row in observations:
        groups[(languages[row['case']], row['condition'])].append(row)
    aggregate = {}
    for (language, condition), rows in groups.items():
        aggregate.setdefault(language, {})[condition] = {
            **metrics(rows),
            'by_case': {case: metrics([r for r in rows if r['case'] == case])
                        for case in sorted({r['case'] for r in rows})},
        }
    return aggregate


def qualifies(candidate, baseline):
    return (candidate['critical_total'] == 0 and candidate['false_mean'] < baseline['false_mean']
            and candidate['failures_total'] <= baseline['failures_total']
            and all(candidate['by_case'][key]['fulfilled_mean'] >= value['fulfilled_mean']
                    for key, value in baseline['by_case'].items()))


def decide(aggregate):
    decisions = {}
    burden = {'ast-grep': 0, 'ts-morph': 1, 'syn': 1, 'rust-analyzer': 2}
    for language, conditions in aggregate.items():
        candidates = [c for c in conditions if c != 'baseline' and qualifies(conditions[c], conditions['baseline'])]
        candidates.sort(key=lambda c: (conditions[c]['false_mean'], -conditions[c]['fulfilled_mean'], burden[c]))
        decisions[language] = {'qualifying': candidates, 'recommendation': candidates[0] if candidates else 'retain baseline'}
    return decisions


def reaggregate(result, cases):
    """Replace derived fields only; preserve observations and audit metadata."""
    aggregate = aggregate_observations(result['observations'], cases)
    return {**result, 'aggregate': aggregate, 'decisions': decide(aggregate)}
