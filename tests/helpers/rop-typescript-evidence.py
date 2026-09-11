"""Contract tests for syntax evidence and source-only fallback."""
import importlib.util
import json
import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

sys.dont_write_bytecode = True
script = Path(sys.argv.pop(1)).resolve()
spec = importlib.util.spec_from_file_location('rop_syntax', script)
syntax = importlib.util.module_from_spec(spec)
spec.loader.exec_module(syntax)


class SyntaxEvidence(unittest.TestCase):
    def setUp(self):
        directory = tempfile.TemporaryDirectory()
        self.addCleanup(directory.cleanup)
        self.root = Path(directory.name)
        (self.root / 'main.ts').write_text('const value = work();\n')

    def scan_with_response(self, response):
        with patch.object(syntax.shutil, 'which', return_value='/tool/ast-grep'), \
             patch.object(syntax.subprocess, 'run', return_value=response):
            return syntax.collect(self.root, ['main.ts'])

    def test_missing_tool_is_explicit_and_does_not_run_any_command(self):
        with patch.object(syntax.shutil, 'which', return_value=None), patch.object(syntax.subprocess, 'run') as run:
            result = syntax.collect(self.root, ['main.ts'])
        self.assertEqual(result['status'], 'unavailable')
        self.assertIn('PATH', result['reason'])
        self.assertEqual(result['nodes'], [])
        run.assert_not_called()

    def test_no_matches_is_success_not_failure(self):
        result = self.scan_with_response(subprocess.CompletedProcess([], 0, '[]', ''))
        self.assertEqual(result['status'], 'ok')
        self.assertEqual(result['nodes'], [])
        self.assertIsNone(result['reason'])
        self.assertEqual(len(result['files'][0]['sha256']), 64)

    def test_command_and_json_failures_are_recorded(self):
        for response in [subprocess.CompletedProcess([], 2, '', 'bad rules'),
                         subprocess.CompletedProcess([], 0, 'invalid JSON', ''),
                         subprocess.CompletedProcess([], 0, '{}', '')]:
            with self.subTest(response=response):
                result = self.scan_with_response(response)
                self.assertEqual(result['status'], 'failed')
                self.assertTrue(result['reason'])
                self.assertEqual(result['nodes'], [])

    def test_timeout_continues_with_explicit_failure(self):
        with patch.object(syntax.shutil, 'which', return_value='/tool/ast-grep'), \
             patch.object(syntax.subprocess, 'run', side_effect=subprocess.TimeoutExpired('ast-grep', 30)):
            result = syntax.collect(self.root, ['main.ts'])
        self.assertEqual(result['status'], 'failed')
        self.assertIn('TimeoutExpired', result['reason'])

    def test_mismatched_source_and_parser_error_are_rejected(self):
        for match in [{'ruleId': 'ERROR'}, {'ruleId': 'call_expression', 'text': 'other()',
                       'range': {'byteOffset': {'start': 14, 'end': 20}}},
                      {'ruleId': 'call_expression', 'text': 'work()',
                       'range': {'byteOffset': {'start': -1, 'end': 100}}}]:
            with self.subTest(match=match):
                result = self.scan_with_response(subprocess.CompletedProcess([], 0, json.dumps([match]), ''))
                self.assertEqual(result['status'], 'failed')
                self.assertEqual(result['nodes'], [])

    def test_directories_outside_root_and_other_languages_are_not_scanned(self):
        (self.root / 'other.rs').write_text('fn main() {}')
        for name in ['.', 'other.rs', '../outside.ts', 'missing.ts']:
            with self.subTest(name=name), patch.object(syntax.shutil, 'which', return_value='/tool/ast-grep'), \
                 patch.object(syntax.subprocess, 'run') as run:
                self.assertEqual(syntax.collect(self.root, [name])['status'], 'failed')
                run.assert_not_called()

    @unittest.skipUnless(shutil.which('ast-grep'), 'native ast-grep is not installed')
    def test_native_ts_tsx_unicode_and_source_containment(self):
        (self.root / 'main.ts').write_text('''class Label { catchTag() { return "plain"; } }
export const run = () => { const 日本語 = new Label().catchTag(); return Fx.catchTag(load(日本語), "Missing", () => backup()); };
''')
        (self.root / 'view.tsx').write_text('export const View = () => <p>{run()}</p>;\n')
        (self.root / 'unselected.ts').write_text('unexpected();')
        (self.root / 'sgconfig.yml').write_text('invalid: [')
        result = syntax.collect(self.root, ['main.ts', 'view.tsx'])
        self.assertEqual(result['status'], 'ok', result['reason'])
        self.assertEqual(result['capabilities'], 'syntax-only')
        self.assertEqual({n['path'] for n in result['nodes']}, {'main.ts', 'view.tsx'})
        self.assertTrue(any(n['text'] == 'run()' for n in result['nodes']))
        self.assertTrue(any(n['text'] == 'new Label().catchTag()' for n in result['nodes']))
        for node in result['nodes']:
            raw = (self.root / node['path']).read_bytes()
            self.assertEqual(raw[node['byte_start']:node['byte_end']].decode()[:180], node['text'])
            self.assertLessEqual(node['end'], len(raw.splitlines()))
            self.assertNotIn('type', node)
            if node['parent'] is not None:
                parent = result['nodes'][node['parent']]
                self.assertEqual(parent['path'], node['path'])
                self.assertLessEqual(parent['byte_start'], node['byte_start'])
                self.assertGreaterEqual(parent['byte_end'], node['byte_end'])

    @unittest.skipUnless(shutil.which('ast-grep'), 'native ast-grep is not installed')
    def test_native_parse_failure_discards_partial_batch(self):
        (self.root / 'broken.tsx').write_text('const x = <p>{broken(</p>')
        result = syntax.collect(self.root, ['main.ts', 'broken.tsx'])
        self.assertEqual(result['status'], 'failed')
        self.assertEqual(result['nodes'], [])

    @unittest.skipUnless(shutil.which('ast-grep'), 'native ast-grep is not installed')
    def test_cli_writes_evidence_artifact(self):
        output = self.root / 'report/evidence.json'
        proc = subprocess.run([sys.executable, str(script), '--repo-root', str(self.root),
                               '--output', str(output), 'main.ts'], capture_output=True, text=True)
        self.assertEqual(proc.returncode, 0, proc.stderr)
        result = json.loads(output.read_text())
        self.assertEqual(result['status'], 'ok', result['reason'])
        self.assertTrue(result['nodes'])


if __name__ == '__main__':
    unittest.main()
