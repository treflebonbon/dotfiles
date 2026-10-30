import importlib.util
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import threading
import unittest
from concurrent.futures import ThreadPoolExecutor
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "scripts"))
SPEC = importlib.util.spec_from_file_location(
    "publication", ROOT / "scripts/publish-topic.py"
)
publication = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(publication)
REAL_RUN = subprocess.run


class PublicationTests(unittest.TestCase):
    def setUp(self):
        self.root = publication.new_runtime("test-publication.")
        self.addCleanup(shutil.rmtree, self.root)
        self.base = self.root / "base"
        self.base.mkdir()
        self.git(self.base, "init", "-q", "--initial-branch=main")
        self.git(
            self.base,
            "-c",
            "user.name=Fixture",
            "-c",
            "user.email=fixture@example.invalid",
            "commit",
            "-qm",
            "fixture",
            "--allow-empty",
        )
        self.work = self.root / "work"
        self.git(self.base, "worktree", "add", "-qb", "topic", str(self.work))
        self.git(
            self.work, "remote", "add", "origin", "https://github.com/fixture/repo.git"
        )
        self.head = self.git(self.work, "rev-parse", "HEAD")
        self.record = self.root / "operation"
        self.record.mkdir(mode=0o700)
        self.pushes = 0
        self.answers = []
        self.push_status = 0
        self.push_error = None

    def git(self, root, *args):
        return REAL_RUN(
            ["git", *args], cwd=root, check=True, capture_output=True, text=True
        ).stdout.strip()

    def receipt(self):
        return json.loads((self.record / "publication.json").read_text())

    def observation(self, **changes):
        return {
            "headRefOid": self.head,
            "headRefName": "topic",
            "state": "OPEN",
            "url": "https://github.com/fixture/repo/pull/7",
            **changes,
        }

    def command(self, argv, **kwargs):
        if Path(argv[0]).name == "git-push-topic":
            self.pushes += 1
            self.assertEqual(self.receipt()["push"]["status"], "started")
            if self.push_error is not None:
                raise self.push_error
            return subprocess.CompletedProcess(argv, self.push_status)
        if Path(argv[0]).name == "gh":
            self.assertIn(
                self.receipt()["push"]["status"], ("started", "succeeded", "failed")
            )
            answer = self.answers.pop(0)
            if isinstance(answer, Exception):
                raise answer
            return subprocess.CompletedProcess(argv, 0, json.dumps(answer), "")
        return REAL_RUN(argv, **kwargs)

    def push(self):
        return publication.push(self.work, "fixture/repo", self.record)

    def verify(self, timeout=30):
        return publication.verify(self.record, 7, timeout)

    def test_delayed_observation_preserves_push_and_records_both_heads(self):
        self.answers = [self.observation(headRefOid="0" * 40), self.observation()]
        with (
            patch.object(publication.subprocess, "run", side_effect=self.command),
            patch.object(publication.time, "sleep"),
        ):
            self.assertEqual(self.push(), 0)
            self.assertEqual(self.verify(), 0)
        receipt = self.receipt()
        self.assertEqual(self.pushes, 1)
        self.assertEqual(receipt["push"]["status"], "succeeded")
        self.assertEqual(receipt["verification"]["status"], "confirmed")
        self.assertEqual(
            [r["headRefOid"] for r in receipt["verification"]["observations"]],
            ["0" * 40, self.head],
        )

    def test_timeout_and_read_only_resume_do_not_push_again(self):
        self.answers = [self.observation(headRefOid="0" * 40), self.observation()]
        with patch.object(publication.subprocess, "run", side_effect=self.command):
            self.assertEqual(self.push(), 0)
            self.assertNotEqual(self.verify(timeout=0), 0)
            self.assertEqual(self.receipt()["push"]["status"], "succeeded")
            self.assertEqual(self.receipt()["verification"]["status"], "pending")
            self.assertEqual(self.verify(), 0)
        self.assertEqual(self.pushes, 1)

    def test_api_error_does_not_reclassify_push_as_failed(self):
        self.answers = [subprocess.TimeoutExpired("gh", 1)]
        with patch.object(publication.subprocess, "run", side_effect=self.command):
            self.assertEqual(self.push(), 0)
            self.assertNotEqual(self.verify(), 0)
        self.assertEqual(self.receipt()["push"]["status"], "succeeded")
        self.assertEqual(self.receipt()["verification"]["status"], "api_error")

    def test_closed_pr_is_recorded_and_not_retried(self):
        self.answers = [self.observation(state="CLOSED")]
        with patch.object(publication.subprocess, "run", side_effect=self.command):
            self.assertEqual(self.push(), 0)
            self.assertNotEqual(self.verify(), 0)
        self.assertEqual(
            self.receipt()["verification"]["observations"][0]["state"], "CLOSED"
        )
        self.assertEqual(self.receipt()["verification"]["status"], "closed")
        self.assertEqual(self.pushes, 1)

    def test_push_failure_is_distinct_and_record_cannot_be_reused_for_push(self):
        self.push_status = 1
        with patch.object(publication.subprocess, "run", side_effect=self.command):
            self.assertNotEqual(self.push(), 0)
            with self.assertRaises(ValueError):
                self.push()
        self.assertEqual(self.receipt()["push"]["status"], "failed")
        self.assertEqual(self.pushes, 1)

    def test_uncommitted_changes_are_rejected_before_push(self):
        (self.work / "untracked").write_text("fixture")
        with patch.object(publication.subprocess, "run", side_effect=self.command):
            with self.assertRaises(ValueError):
                self.push()
        self.assertEqual(self.pushes, 0)

    def test_wrong_repository_is_rejected_before_push(self):
        with patch.object(publication.subprocess, "run", side_effect=self.command):
            with self.assertRaises(ValueError):
                publication.push(self.work, "different/repo", self.record)
        self.assertEqual(self.pushes, 0)

    def test_wrong_pr_branch_is_recorded_without_another_push(self):
        self.answers = [self.observation(headRefName="another-topic")]
        with patch.object(publication.subprocess, "run", side_effect=self.command):
            self.assertEqual(self.push(), 0)
            self.assertNotEqual(self.verify(), 0)
        self.assertEqual(self.receipt()["verification"]["status"], "mismatch")
        self.assertEqual(self.pushes, 1)

    def test_inherited_git_redirects_do_not_change_the_selected_worktree(self):
        with (
            patch.dict(
                os.environ,
                {"GIT_DIR": str(self.base / ".git"), "GIT_WORK_TREE": str(self.base)},
            ),
            patch.object(publication.subprocess, "run", side_effect=self.command),
        ):
            self.assertEqual(self.push(), 0)
        self.assertEqual(self.receipt()["branch"], "topic")

    def test_interrupted_push_can_be_verified_without_repeating_the_write(self):
        self.push_error = KeyboardInterrupt()
        self.answers = [self.observation()]
        with patch.object(publication.subprocess, "run", side_effect=self.command):
            with self.assertRaises(KeyboardInterrupt):
                self.push()
            self.assertEqual(self.receipt()["push"]["status"], "started")
            self.assertEqual(self.verify(), 0)
        self.assertEqual(self.pushes, 1)
        self.assertEqual(self.receipt()["push"]["status"], "started")

    def test_malformed_api_response_is_recorded_as_a_verification_error(self):
        self.answers = [{}, [], None, self.observation(headRefOid="invalid")]
        with patch.object(publication.subprocess, "run", side_effect=self.command):
            self.assertEqual(self.push(), 0)
            for _ in range(4):
                self.assertNotEqual(self.verify(), 0)
        self.assertEqual(self.receipt()["verification"]["status"], "api_error")
        self.assertEqual(self.receipt()["push"]["status"], "succeeded")

    def test_record_cannot_be_retargeted_to_another_pr(self):
        self.answers = [self.observation()]
        with patch.object(publication.subprocess, "run", side_effect=self.command):
            self.assertEqual(self.push(), 0)
            self.assertEqual(self.verify(), 0)
            with self.assertRaises(ValueError):
                publication.verify(self.record, 8, 0)

    def test_publication_record_rejects_symlinked_directories(self):
        alias = self.root / "alias"
        alias.symlink_to(self.record, target_is_directory=True)
        with self.assertRaises(ValueError):
            publication.record_path(alias)

    def test_publication_record_requires_private_permissions(self):
        self.record.chmod(0o777)
        with self.assertRaises(ValueError):
            publication.record_path(self.record)

    def test_push_preserves_unknown_files_in_the_record_directory(self):
        unknown = self.record / "push.stdout.log"
        unknown.write_text("preserved")
        with patch.object(publication.subprocess, "run", side_effect=self.command):
            with self.assertRaises(ValueError):
                self.push()
        self.assertEqual(self.pushes, 0)
        self.assertEqual(unknown.read_text(), "preserved")

    def test_concurrent_starts_claim_the_record_before_pushing(self):
        publication.dependencies()
        barrier = threading.Barrier(2)

        def command(argv, **kwargs):
            if Path(argv[0]).name == "git" and argv[-2:] == ["rev-parse", "HEAD"]:
                barrier.wait(timeout=30)
            return self.command(argv, **kwargs)

        def attempt():
            try:
                return self.push()
            except (FileExistsError, ValueError):
                return 1

        with (
            patch.object(publication.subprocess, "run", side_effect=command),
            ThreadPoolExecutor(max_workers=2) as pool,
        ):
            results = list(pool.map(lambda _: attempt(), range(2)))
        self.assertEqual(sorted(results), [0, 1])
        self.assertEqual(self.pushes, 1)


if __name__ == "__main__":
    unittest.main()
