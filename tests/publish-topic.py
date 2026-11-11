import fcntl
import importlib.util
import io
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import threading
import unittest
from concurrent.futures import ThreadPoolExecutor
from contextlib import redirect_stdout
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "scripts"))
SPEC = importlib.util.spec_from_file_location(
    "publication", ROOT / "scripts/publish-topic.py"
)
publication = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(publication)
REAL_RUN = subprocess.run
REAL_FLOCK = fcntl.flock


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
            "number": 7,
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

    def inspect(self, answer, pr=None):
        """fixture の PR 応答で inspect を実行し、参照コマンドの引数を検証する。"""
        def command(argv, **kwargs):
            """git は fixture で実行し、gh には指定された応答を返す。"""
            if Path(argv[0]).name == "gh":
                self.assertEqual(
                    argv[:3], ["gh", "pr", "list" if pr is None else "view"]
                )
                self.assertEqual(kwargs["timeout"], 30)
                if pr is None:
                    self.assertEqual(argv[argv.index("--head") + 1], "topic")
                    self.assertEqual(argv[argv.index("--state") + 1], "all")
                else:
                    self.assertEqual(argv[3], str(pr))
                if isinstance(answer, Exception):
                    raise answer
                return subprocess.CompletedProcess(argv, 0, json.dumps(answer), "")
            self.assertEqual(Path(argv[0]).name, "git")
            return REAL_RUN(argv, **kwargs)

        with patch.object(publication.subprocess, "run", side_effect=command):
            return publication.inspect_topic(self.work, "fixture/repo", pr)

    def test_inspection_matches_explicit_pr_without_a_publication_record(self):
        (self.work / "untracked").write_text("ongoing work")
        result = self.inspect(self.observation(), pr=7)
        self.assertEqual(result["status"], "confirmed")
        self.assertEqual(result["head"], self.head)
        self.assertEqual(result["branch"], "topic")
        self.assertEqual(result["observations"], [self.observation()])
        self.assertEqual(list(self.record.iterdir()), [])
        self.assertEqual(self.git(self.work, "status", "--porcelain"), "?? untracked")

    def test_inspection_distinguishes_missing_ambiguous_and_mismatched_prs(self):
        """候補数と branch・HEAD の違いが期待する状態へ分類されることを確認する。"""
        cases = [
            ([], "not_created"),
            ([self.observation()], "confirmed"),
            ([self.observation(), self.observation(number=8)], "ambiguous"),
            ([self.observation(headRefName="other-topic")], "mismatch"),
            ([self.observation(headRefOid="0" * 40)], "mismatch"),
        ]
        for observations, expected in cases:
            with self.subTest(status=expected, observations=observations):
                result = self.inspect(observations)
                self.assertEqual(result["status"], expected)
                self.assertEqual(result["observations"], observations)

    def test_inspection_reports_api_errors_and_rejects_malformed_responses(self):
        """API 失敗と不正応答がエラーとして報告されることを確認する。"""
        error = subprocess.CalledProcessError(1, "gh")
        with self.assertRaises(ValueError):
            self.inspect(error)
        for answer in ({}, None, [None], [self.observation(headRefOid="invalid")]):
            with self.subTest(answer=answer), self.assertRaises(ValueError):
                self.inspect(answer)
        with self.assertRaises(ValueError):
            self.inspect(self.observation(number=8), pr=7)

    def test_inspection_records_safe_authentication_and_http_diagnostics(self):
        """固定診断が終了コード・認証要求・HTTP 状態を表し、認証値を保護する。"""
        cases = [
            (4, "Authorization: Bearer fixture-sensitive-value", "認証が必要"),
            (1, "HTTP 401: fixture-sensitive-value", "HTTP 401"),
            (17, "HTTP 403: fixture-sensitive-value", "HTTP 403"),
            (1, "HTTP 503: fixture-sensitive-value", "HTTP 503"),
            (1, "unexpected fixture-sensitive-value", "API コマンド失敗"),
        ]
        for code, stderr, expected in cases:
            error = subprocess.CalledProcessError(code, "gh", stderr=stderr)
            with self.subTest(code=code), self.assertRaises(ValueError) as raised:
                self.inspect(error)
            message = str(raised.exception)
            self.assertIn(expected, message)
            self.assertIn(f"exit {code}", message)
            self.assertNotIn("fixture-sensitive-value", message)

    def test_inspection_rejects_wrong_repo_and_ignores_inherited_git_redirects(self):
        with self.assertRaises(ValueError):
            publication.inspect_topic(self.work, "different/repo")
        with patch.dict(
            os.environ,
            {"GIT_DIR": str(self.base / ".git"), "GIT_WORK_TREE": str(self.base)},
        ):
            self.assertEqual(
                self.inspect(self.observation(), pr=7)["status"], "confirmed"
            )

    def test_inspection_cli_reports_json_and_a_nonzero_status_for_mismatches(self):
        """CLI の JSON 出力と、照合状態に応じた終了コードを確認する。"""
        for status in ("confirmed", "not_created", "mismatch", "ambiguous"):
            result = {"status": status}
            with (
                self.subTest(status=status),
                patch.object(
                    sys,
                    "argv",
                    ["publish-topic.py", "inspect", "--repo", "fixture/repo", "--pr", "7"],
                ),
                patch.object(
                    publication, "inspect_topic", return_value=result
                ) as inspect,
                redirect_stdout(io.StringIO()) as output,
            ):
                self.assertEqual(
                    publication.main(),
                    0 if status in ("confirmed", "not_created") else 1,
                )
                self.assertEqual(json.loads(output.getvalue()), result)
                inspect.assert_called_once_with(Path.cwd(), "fixture/repo", 7)

    @unittest.skipUnless(sys.platform == "linux", "verification_env requires Linux")
    def test_handoff_instructions_preserve_api_failure_logs(self):
        """実際の引継ぎ手順で、API 失敗の診断ログと終了コードが保存されることを確認する。"""
        instructions = (ROOT / "docs/conventions.md").read_text()
        block = next(
            block
            for block in re.findall(r"```bash\n(.*?)\n```", instructions, re.S)
            if "handoff_record=" in block
        )
        block = block.replace("treflebonbon/dotfiles", "fixture/repo")
        block += '\nprintf "%s" "$handoff_record" > "$HANDOFF_FIXTURE_RECEIPT"\n'
        (self.work / "scripts").symlink_to(ROOT / "scripts", target_is_directory=True)
        original_home = self.root / "home"
        original_home.mkdir()
        binary = self.root / "bin"
        binary.mkdir()
        gh = binary / "gh"
        gh.write_text(
            "#!/bin/sh\n"
            "printf 'HTTP 403: Authorization: Bearer fixture-sensitive-value\\n' >&2\n"
            "exit 17\n"
        )
        gh.chmod(0o700)
        receipt = self.root / "handoff-path"
        environment = os.environ.copy()
        environment.update(
            HOME=str(original_home),
            PATH=f"{binary}:{environment['PATH']}",
            HANDOFF_FIXTURE_RECEIPT=str(receipt),
        )
        result = REAL_RUN(
            ["bash", "-eu", "-c", block],
            cwd=self.work,
            env=environment,
            capture_output=True,
            text=True,
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        record = Path(receipt.read_text())
        self.addCleanup(shutil.rmtree, record)
        self.assertEqual((record / "exit-code").read_text(), "1\n")
        self.assertEqual((record / "identity.json").read_text(), "")
        diagnostic = (record / "stderr.log").read_text()
        self.assertIn("HTTP 403", diagnostic)
        self.assertIn("exit 17", diagnostic)
        self.assertNotIn("fixture-sensitive-value", diagnostic)

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

    def test_concurrent_verification_preserves_the_completed_push(self):
        push_started = threading.Event()
        finish_push = threading.Event()
        push_finished = threading.Event()
        verification_ready = threading.Event()
        verifier = None
        self.answers = [self.observation()]

        def command(argv, **kwargs):
            if Path(argv[0]).name == "git-push-topic":
                push_started.set()
                self.assertTrue(finish_push.wait(timeout=30))
            elif Path(argv[0]).name == "gh":
                verification_ready.set()
                self.assertTrue(push_finished.wait(timeout=30))
            return self.command(argv, **kwargs)

        def lock(descriptor, operation):
            if threading.get_ident() == verifier:
                verification_ready.set()
            return REAL_FLOCK(descriptor, operation)

        def pushing():
            try:
                return self.push()
            finally:
                push_finished.set()

        def verifying():
            nonlocal verifier
            verifier = threading.get_ident()
            return self.verify()

        with (
            patch.object(publication.subprocess, "run", side_effect=command),
            patch.object(fcntl, "flock", side_effect=lock),
            ThreadPoolExecutor(max_workers=2) as pool,
        ):
            pushed = pool.submit(pushing)
            try:
                self.assertTrue(push_started.wait(timeout=30))
                verified = pool.submit(verifying)
                self.assertTrue(verification_ready.wait(timeout=30))
            finally:
                finish_push.set()
            self.assertEqual(pushed.result(timeout=30), 0)
            self.assertEqual(verified.result(timeout=30), 0)
        receipt = self.receipt()
        self.assertEqual(receipt["push"], {"status": "succeeded", "exit_code": 0})
        self.assertEqual(receipt["verification"]["status"], "confirmed")
        self.assertEqual(self.pushes, 1)

    def test_api_error_does_not_reclassify_push_as_failed(self):
        errors = [
            subprocess.TimeoutExpired("gh", 1),
            FileNotFoundError("gh"),
            subprocess.CalledProcessError(1, "gh"),
        ]
        with patch.object(publication.subprocess, "run", side_effect=self.command):
            self.assertEqual(self.push(), 0)
            for error in errors:
                with self.subTest(error=type(error).__name__):
                    self.answers = [error]
                    self.assertNotEqual(self.verify(), 0)
                    self.assertEqual(self.receipt()["push"]["status"], "succeeded")
                    self.assertEqual(
                        self.receipt()["verification"]["status"], "api_error"
                    )

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

    def test_push_timeout_preserves_unknown_state_and_allows_verification(self):
        self.answers = [self.observation()]

        def command(argv, **kwargs):
            if Path(argv[0]).name == "git-push-topic":
                self.assertEqual(kwargs.get("timeout"), 1800)
                self.push_error = subprocess.TimeoutExpired(argv, kwargs["timeout"])
            return self.command(argv, **kwargs)

        with patch.object(publication.subprocess, "run", side_effect=command):
            with self.assertRaises(subprocess.TimeoutExpired):
                self.push()
            self.assertEqual(self.receipt()["push"], {"status": "started"})
            self.assertEqual(self.verify(), 0)
        self.assertEqual(self.receipt()["push"], {"status": "started"})
        self.assertEqual(self.receipt()["verification"]["status"], "confirmed")
        self.assertEqual(self.pushes, 1)

    def test_malformed_api_response_is_recorded_as_a_verification_error(self):
        self.answers = [{}, [], None, self.observation(headRefOid="invalid")]
        with patch.object(publication.subprocess, "run", side_effect=self.command):
            self.assertEqual(self.push(), 0)
            for _ in range(4):
                self.assertNotEqual(self.verify(), 0)
        self.assertEqual(self.receipt()["verification"]["status"], "api_error")
        self.assertEqual(self.receipt()["push"]["status"], "succeeded")

    def test_record_cannot_be_retargeted_to_another_pr(self):
        self.answers = [self.observation(headRefOid="0" * 40), self.observation()]
        with patch.object(publication.subprocess, "run", side_effect=self.command):
            self.assertEqual(self.push(), 0)
            for expected in (2, 0):
                self.assertEqual(self.verify(timeout=0), expected)
                with self.assertRaises(ValueError):
                    publication.verify(self.record, 8, 0)

    def test_pr_can_be_corrected_after_api_error_without_observations(self):
        self.answers = [
            subprocess.CalledProcessError(1, "gh"),
            self.observation(url="https://github.com/fixture/repo/pull/8"),
        ]
        with patch.object(publication.subprocess, "run", side_effect=self.command):
            self.assertEqual(self.push(), 0)
            self.assertEqual(self.verify(), 1)
            self.assertEqual(self.receipt()["verification"]["observations"], [])
            self.assertEqual(publication.verify(self.record, 8, 0), 0)
        self.assertEqual(self.receipt()["verification"]["pr"], 8)
        self.assertEqual(self.receipt()["verification"]["status"], "confirmed")
        self.assertEqual(len(self.receipt()["verification"]["observations"]), 1)
        self.assertEqual(self.receipt()["push"]["status"], "succeeded")
        self.assertEqual(self.pushes, 1)

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

        def attempt():
            barrier.wait(timeout=30)
            try:
                return self.push()
            except (FileExistsError, ValueError):
                return 1

        with (
            patch.object(publication.subprocess, "run", side_effect=self.command),
            ThreadPoolExecutor(max_workers=2) as pool,
        ):
            results = list(pool.map(lambda _: attempt(), range(2)))
        self.assertEqual(sorted(results), [0, 1])
        self.assertEqual(self.pushes, 1)


if __name__ == "__main__":
    unittest.main()
