import copy
import json
import tempfile
import unittest
from pathlib import Path
from experiment import run_matrix, decode_model, verify, digest, REPO, validate
from evaluate import qualifies, validate_review


class ExperimentTests(unittest.TestCase):
    def test_matrix_is_balanced_and_reproducible(self):
        cases = [{'id': f't{i}', 'language': 'ts'} for i in range(3)] + [
                 {'id': f'r{i}', 'language': 'rust'} for i in range(4)]
        matrix = run_matrix(cases)
        self.assertEqual(matrix, run_matrix(cases))
        self.assertEqual(len(matrix), 75)
        self.assertEqual(len({r['id'] for r in matrix}), 75)
        for case in cases:
            rows = [r for r in matrix if r['case'] == case['id']]
            for condition in {r['condition'] for r in rows}:
                self.assertEqual(sorted(r['repeat'] for r in rows if r['condition'] == condition), [1, 2, 3])

    def test_freeze_rejects_changed_input(self):
        with tempfile.TemporaryDirectory(dir=REPO / 'tmp') as directory:
            file = Path(directory) / 'source.rs'
            file.write_text('fn first() {}')
            manifest = {'sha256': {str(file.relative_to(REPO)): digest(file)}}
            verify(manifest)
            file.write_text('fn second() {}')
            with self.assertRaisesRegex(RuntimeError, 'drift'):
                verify(manifest)

    def test_gate_does_not_hide_case_regression_in_average(self):
        baseline = {'critical': 0, 'false_mean': 2, 'failures': 0,
                    'by_case': {'a': {'fulfilled_mean': 6}, 'b': {'fulfilled_mean': 6}}}
        candidate = copy.deepcopy(baseline)
        candidate['false_mean'] = 1
        self.assertTrue(qualifies(candidate, baseline))
        candidate['by_case']['a']['fulfilled_mean'] = 5
        candidate['by_case']['b']['fulfilled_mean'] = 9
        self.assertFalse(qualifies(candidate, baseline))

    def test_gate_rejects_critical_failure_or_no_gain(self):
        baseline = {'critical': 0, 'false_mean': 1, 'failures': 0, 'by_case': {'a': {'fulfilled_mean': 6}}}
        self.assertFalse(qualifies(baseline, baseline))
        for field, value in [('critical', 1), ('failures', 1)]:
            candidate = copy.deepcopy(baseline)
            candidate.update(false_mean=0)
            candidate[field] = value
            self.assertFalse(qualifies(candidate, baseline))

    def test_blind_scores_must_cover_every_run_and_requirement(self):
        packet = {'case': 'x', 'models': [{'id': 'opaque'}], 'gold': {'requirements': [{'id': 'early-return'}]}}
        data = {'case': 'x', 'scores': [{'id': 'opaque', 'requirements': [
            {'id': 'early-return', 'fulfilled': True, 'reason': 'source supports edge', 'evidence': ['E1']}],
            'false_assertions': [], 'unknowns': []}]}
        validate_review(data, packet)
        data['scores'][0]['requirements'] = []
        with self.assertRaisesRegex(ValueError, 'requirement'):
            validate_review(data, packet)

    def test_decoder_does_not_accept_trailing_commentary(self):
        self.assertEqual(decode_model('```json\n{"nodes": []}\n```'), {'nodes': []})
        with self.assertRaises(json.JSONDecodeError):
            decode_model('{"nodes": []} this is correct')

    def test_renderer_and_scope_reject_wrong_source(self):
        with tempfile.TemporaryDirectory(dir=REPO / 'tmp') as directory:
            root = Path(directory)
            (root / 'main.rs').write_text('fn main() {}\nfn hidden() {}\n')
            model = {'title': 'Example', 'entry': 'main', 'summary': 'Example', 'start': 'A',
                'nodes': [{'id': 'A', 'label': 'A', 'summary': 'work', 'kind': 'work', 'lane': 'success',
                           'source': {'path': 'main.rs', 'start': 1}},
                          {'id': 'END', 'label': 'end', 'summary': 'return', 'kind': 'terminal', 'lane': 'success'}],
                'edges': [{'from': 'A', 'to': 'END'}], 'paths': [{'label': 'success', 'edges': [0]}], 'limitations': []}
            case = {'root': directory, 'files': ['main.rs'], 'ranges': {'main.rs': [[1, 1]]}}
            file = root / 'flow.json'
            file.write_text(json.dumps(model))
            self.assertIn('flowchart TB', validate(file, case))
            model['nodes'][0]['source']['start'] = 2
            file.write_text(json.dumps(model))
            with self.assertRaisesRegex(ValueError, 'permitted ranges'):
                validate(file, case)


if __name__ == '__main__':
    unittest.main()
