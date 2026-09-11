import copy
import json
import queue
import runpy
import subprocess
import tempfile
import time
import unittest
from pathlib import Path
from unittest.mock import Mock, patch
from evaluate import validate_review
from extract import Lsp


class ReviewFailureTests(unittest.TestCase):
    def test_absent_model_accepts_only_empty_semantic_scores(self):
        packet = {'case': 'x', 'models': [{'id': 'run', 'model': None}],
                  'gold': {'requirements': [{'id': 'r'}]}}
        data = {'case': 'x', 'scores': [{'id': 'run', 'requirements': [
            {'id': 'r', 'fulfilled': False, 'reason': '生成失敗', 'evidence': []}],
            'false_assertions': [], 'unknowns': []}]}
        validate_review(data, packet)
        for field in ('fulfilled', 'false_assertions', 'unknowns'):
            with self.subTest(field=field):
                changed = copy.deepcopy(data)
                score = changed['scores'][0]
                if field == 'fulfilled':
                    score['requirements'][0]['fulfilled'] = True
                elif field == 'false_assertions':
                    score[field] = [{'critical': True, 'description': 'invented', 'evidence': ['E1']}]
                else:
                    score[field] = ['invented boundary']
                with self.assertRaisesRegex(ValueError, 'Absent model'):
                    validate_review(changed, packet)
                # A present model may still be reviewed even if mechanically invalid.
                present = copy.deepcopy(packet)
                present['models'][0].update(model={}, valid=False)
                validate_review(changed, present)

    def test_empty_lsp_queue_reports_timeout(self):
        client = Lsp.__new__(Lsp)
        client.messages = queue.Queue()
        with self.assertRaisesRegex(TimeoutError, 'rust-analyzer did not finish loading'):
            client.receive(time.monotonic())

    def test_lsp_initialization_failures_release_process_and_streams(self):
        for error in (RuntimeError('initialize failed'), TimeoutError('loading failed'), KeyboardInterrupt()):
            with self.subTest(error=type(error).__name__), tempfile.TemporaryDirectory() as directory:
                root = Path(directory)
                (root / 'preflight').mkdir()
                process = Mock()
                with patch('extract.WORK', root), patch('extract.environment', return_value={}), \
                     patch('extract.subprocess.Popen', return_value=process) as popen, \
                     patch('extract.threading.Thread'), patch.object(Lsp, 'request', side_effect=error):
                    with self.assertRaises(type(error)):
                        Lsp(root, [])
                process.terminate.assert_called_once()
                process.wait.assert_called_once_with(timeout=5)
                process.stdin.close.assert_called_once()
                process.stdout.close.assert_called_once()
                self.assertTrue(popen.call_args.kwargs['stderr'].closed)

    def test_lsp_spawn_failure_closes_stderr(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / 'preflight').mkdir()
            with patch('extract.WORK', root), patch('extract.environment', return_value={}), \
                 patch('extract.subprocess.Popen', side_effect=FileNotFoundError('rust-analyzer')) as popen:
                with self.assertRaises(FileNotFoundError):
                    Lsp(root, [])
            self.assertTrue(popen.call_args.kwargs['stderr'].closed)

    def test_lsp_cleanup_kills_process_that_does_not_terminate(self):
        client = Lsp.__new__(Lsp)
        client.proc = Mock()
        client.stderr = Mock()
        client.proc.wait.side_effect = [subprocess.TimeoutExpired('rust-analyzer', 5), None]
        client.close()
        client.proc.kill.assert_called_once()
        self.assertEqual(client.proc.wait.call_count, 2)
        client.stderr.close.assert_called_once()

    def test_public_preparation_preserves_dangling_link_on_rerun(self):
        script = Path(__file__).with_name('prepare-public.py')
        with tempfile.TemporaryDirectory() as directory:
            repo = Path(directory)
            work = repo / 'tmp/experiment'
            work.mkdir(parents=True)
            (work / 'cases-local.json').write_text('[]')
            docs = repo / 'docs/research'
            docs.mkdir(parents=True)
            (docs / 'rop-public-inputs.json').write_text(json.dumps({'inputs': [
                {'id': 'effect-test', 'snapshot': {'archive': 'public/source.tar.gz'}}]}))
            root = repo / 'project'
            root.mkdir()
            target = repo / 'public/runtime/node_modules'
            modules = root / 'node_modules'
            modules.symlink_to(target, target_is_directory=True)
            inode = modules.lstat().st_ino
            with patch('prepare.REPO', repo), patch('prepare.WORK', work), \
                 patch('public_snapshot.prepare_snapshot', return_value=root), patch('subprocess.run'):
                runpy.run_path(str(script))
                self.assertFalse(modules.exists())
                self.assertEqual(modules.lstat().st_ino, inode)
                target.mkdir(parents=True)
                runpy.run_path(str(script))
            self.assertTrue(modules.is_dir())
            self.assertEqual(modules.lstat().st_ino, inode)
            self.assertEqual(len(json.loads((work / 'cases.json').read_text())), 1)


if __name__ == '__main__':
    unittest.main()
