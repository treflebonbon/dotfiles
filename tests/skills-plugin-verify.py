from __future__ import annotations

import importlib.util
import io
import json
import os
import shutil
import subprocess
import sys
import tempfile
import textwrap
import tomllib
import unittest
from contextlib import redirect_stdout
from pathlib import Path
from importlib.machinery import SourceFileLoader
from unittest.mock import call, patch


PROJECT_ROOT = Path(__file__).resolve().parents[1]
SCRIPT = PROJECT_ROOT / "private_dot_local/bin/executable_sync-skills-plugin"
LOADER = SourceFileLoader("sync_skills_plugin", str(SCRIPT))
SPEC = importlib.util.spec_from_loader("sync_skills_plugin", LOADER)
assert SPEC is not None and SPEC.loader is not None
sync_skills_plugin = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(sync_skills_plugin)


def git(root: Path, *args: str, input: bytes | None = None) -> str:
    return (
        subprocess.run(
            ["git", *args],
            cwd=root,
            input=input,
            check=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
        )
        .stdout.decode()
        .strip()
    )


class VerifyCheckoutTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary = tempfile.TemporaryDirectory()
        self.root = Path(self.temporary.name) / "checkout"
        self.root.mkdir()
        git(self.root, "init", "-q")
        git(self.root, "config", "user.name", "Fixture")
        git(self.root, "config", "user.email", "fixture@example.invalid")
        (self.root / "plugin.json").write_text(
            json.dumps({"name": "treflebonbon-skills", "version": "0.2.1"}) + "\n"
        )
        (self.root / "README.md").write_text("fixture\n")
        (self.root / "bin").mkdir()
        entrypoint = self.root / "bin/tool"
        entrypoint.write_text("#!/bin/sh\nexit 0\n")
        entrypoint.chmod(0o755)
        for name in sync_skills_plugin.GLOBAL_CLI_NAMES:
            public_entry = self.root / "bin" / name
            public_entry.write_text(f"#!/bin/sh\n# fixture for {name}\nexit 0\n")
            public_entry.chmod(0o755)
        for name in ("devshell-env", "codex-worktree"):
            public_entry = self.root / "bin" / name
            public_entry.write_text(f"#!/bin/sh\n# fixture for {name}\nexit 0\n")
            public_entry.chmod(0o755)
        public_module = self.root / "lib/python/treflebonbon_skills"
        public_module.mkdir(parents=True)
        (public_module / "codex_reviewer.py").write_text("# public fixture module\n")
        (public_module / "git_context.py").write_text("# shared fixture module\n")
        git(self.root, "add", "plugin.json", "README.md", "bin/tool")
        git(self.root, "add", "bin", "lib")
        git(self.root, "commit", "-qm", "fixture")
        self.pin = {
            "owner": "treflebonbon",
            "repo": "skills",
            "rev": git(self.root, "rev-parse", "HEAD"),
            "tree": git(self.root, "rev-parse", "HEAD^{tree}"),
            "version": "0.2.1",
            "nar_hash": "sha256-fixture",
            "file_count": len(sync_skills_plugin.tracked_tree(self.root)),
        }
        self.source = sync_skills_plugin.ensure_marketplace_source(
            self.root,
            self.pin,
            Path(self.temporary.name) / "marketplaces",
        )
        self.real_git = shutil.which("git")
        assert self.real_git is not None
        self.git_wrapper_dir = Path(self.temporary.name) / "bin"
        self.git_wrapper_dir.mkdir()
        wrapper = self.git_wrapper_dir / "git"
        wrapper.write_text(
            "#!/usr/bin/env python3\n"
            "import os, sys\n"
            "args = sys.argv[1:]\n"
            "if args[:3] == ['remote', 'add', 'origin']:\n"
            "    args[3] = os.environ['FIXTURE_GIT_REMOTE']\n"
            "os.execv(os.environ['REAL_GIT'], [os.environ['REAL_GIT'], *args])\n"
        )
        wrapper.chmod(0o755)
        self.checkout_parent = Path(self.temporary.name) / "checkouts"

    def tearDown(self) -> None:
        self.temporary.cleanup()

    def test_accepts_checkout_when_head_tree_content_and_modes_match(self) -> None:
        self.assertTrue(sync_skills_plugin.verify_checkout(self.root, self.pin))

    def test_pin_path_uses_the_deployed_chezmoi_config_from_local_bin(self) -> None:
        home = Path(self.temporary.name) / "deployed-home"
        executable = home / ".local/bin/sync-skills-plugin"
        executable.parent.mkdir(parents=True)
        executable.write_text("#!/usr/bin/env python3\n")
        pin_file = home / ".config/nix-devshell/skills-plugin.json"
        pin_file.parent.mkdir(parents=True)
        pin_file.write_text(json.dumps(self.pin) + "\n")

        with (
            patch.object(sync_skills_plugin, "__file__", str(executable)),
            patch.dict(os.environ, {"HOME": str(home)}),
        ):
            self.assertEqual(sync_skills_plugin.pin_path(), pin_file)
            self.assertEqual(sync_skills_plugin.load_pin()["rev"], self.pin["rev"])

    def test_marketplace_source_is_exact_immutable_snapshot_without_git_metadata(
        self,
    ) -> None:
        self.assertFalse((self.source / ".git").exists())
        self.assertTrue(
            sync_skills_plugin.verify_payload(
                self.source, sync_skills_plugin.tracked_tree(self.root), self.pin
            )
        )
        self.assertEqual(
            sync_skills_plugin.ensure_marketplace_source(
                self.root,
                self.pin,
                Path(self.temporary.name) / "marketplaces",
            ),
            self.source,
        )
        (self.source / "README.md").write_text("tampered\n")
        with self.assertRaisesRegex(sync_skills_plugin.PluginSyncError, "README.md"):
            sync_skills_plugin.ensure_marketplace_source(
                self.root,
                self.pin,
                Path(self.temporary.name) / "marketplaces",
            )
        self.assertEqual((self.source / "README.md").read_text(), "tampered\n")

    def test_rejects_unexpected_installed_payload_entries_and_version_drift(
        self,
    ) -> None:
        expected = sync_skills_plugin.tracked_tree(self.root)
        unexpected_file = self.source / "extra.txt"
        unexpected_file.write_text("extra\n")
        with self.assertRaisesRegex(sync_skills_plugin.PluginSyncError, "extra.txt"):
            sync_skills_plugin.verify_payload(self.source, expected, self.pin)
        unexpected_file.unlink()

        unexpected_directory = self.source / "empty-extra"
        unexpected_directory.mkdir()
        with self.assertRaisesRegex(sync_skills_plugin.PluginSyncError, "empty-extra"):
            sync_skills_plugin.verify_payload(self.source, expected, self.pin)
        unexpected_directory.rmdir()

        git_metadata = self.source / ".git"
        git_metadata.mkdir()
        with self.assertRaisesRegex(sync_skills_plugin.PluginSyncError, "Git metadata"):
            sync_skills_plugin.verify_payload(self.source, expected, self.pin)
        git_metadata.rmdir()

        unexpected_link = self.source / "linked"
        unexpected_link.symlink_to("README.md")
        with self.assertRaisesRegex(sync_skills_plugin.PluginSyncError, "symlink"):
            sync_skills_plugin.verify_payload(self.source, expected, self.pin)
        unexpected_link.unlink()

        wrong_version = dict(self.pin, version="9.9.9")
        with self.assertRaisesRegex(
            sync_skills_plugin.PluginSyncError, "version does not match pin"
        ):
            sync_skills_plugin.verify_payload(self.source, expected, wrong_version)

    def test_detects_content_change_hidden_by_assume_unchanged(self) -> None:
        (self.root / "README.md").write_text("tampered\n")
        git(self.root, "update-index", "--assume-unchanged", "README.md")

        with self.assertRaisesRegex(sync_skills_plugin.PluginSyncError, "README.md"):
            sync_skills_plugin.verify_checkout(self.root, self.pin)

    def test_detects_untracked_extra_file(self) -> None:
        (self.root / "extra.txt").write_text("extra\n")

        with self.assertRaisesRegex(sync_skills_plugin.PluginSyncError, "extra.txt"):
            sync_skills_plugin.verify_checkout(self.root, self.pin)

    def test_detects_untracked_empty_directory(self) -> None:
        (self.root / "empty-extra").mkdir()

        with self.assertRaisesRegex(sync_skills_plugin.PluginSyncError, "empty-extra"):
            sync_skills_plugin.verify_checkout(self.root, self.pin)

    def test_detects_executable_bit_change(self) -> None:
        (self.root / "bin/tool").chmod(0o644)

        with self.assertRaisesRegex(sync_skills_plugin.PluginSyncError, "bin/tool"):
            sync_skills_plugin.verify_checkout(self.root, self.pin)

    def test_rejects_sensitive_names_and_symlinks(self) -> None:
        secret_name = self.root / ".env.local"
        secret_name.write_text("fixture\n")
        with self.assertRaisesRegex(sync_skills_plugin.PluginSyncError, "sensitive"):
            sync_skills_plugin.verify_checkout(self.root, self.pin)
        secret_name.unlink()

        link = self.root / "linked"
        link.symlink_to("README.md")
        with self.assertRaisesRegex(sync_skills_plugin.PluginSyncError, "symlink"):
            sync_skills_plugin.verify_checkout(self.root, self.pin)

    def test_ensure_checkout_fetches_once_and_revalidates_existing_contents(
        self,
    ) -> None:
        with patch.dict(
            os.environ,
            {
                "PATH": f"{self.git_wrapper_dir}:{os.environ['PATH']}",
                "REAL_GIT": self.real_git,
                "FIXTURE_GIT_REMOTE": str(self.root),
            },
        ):
            checkout = sync_skills_plugin.ensure_checkout(
                self.pin, self.checkout_parent
            )
            self.assertEqual(checkout, self.checkout_parent / self.pin["rev"])
            self.assertTrue(sync_skills_plugin.verify_checkout(checkout, self.pin))
            original = (checkout / "README.md").read_text()
            (checkout / "README.md").write_text("tampered\n")
            git(checkout, "update-index", "--assume-unchanged", "README.md")

            with self.assertRaisesRegex(
                sync_skills_plugin.PluginSyncError, "README.md"
            ):
                sync_skills_plugin.ensure_checkout(self.pin, self.checkout_parent)
            self.assertEqual((checkout / "README.md").read_text(), "tampered\n")
            self.assertNotEqual((checkout / "README.md").read_text(), original)

    def test_keeps_both_pinned_snapshots_for_rollback_to_the_previous_sha(self) -> None:
        marketplace_parent = self.source.parent
        with patch.dict(
            os.environ,
            {
                "PATH": f"{self.git_wrapper_dir}:{os.environ['PATH']}",
                "REAL_GIT": self.real_git,
                "FIXTURE_GIT_REMOTE": str(self.root),
            },
        ):
            old_checkout = sync_skills_plugin.ensure_checkout(
                self.pin, self.checkout_parent
            )
            old_source = sync_skills_plugin.ensure_marketplace_source(
                old_checkout, self.pin, marketplace_parent
            )
            old_readme = (old_source / "README.md").read_bytes()

            (self.root / "plugin.json").write_text(
                json.dumps({"name": "treflebonbon-skills", "version": "0.2.2"}) + "\n"
            )
            (self.root / "README.md").write_text("updated fixture\n")
            git(self.root, "add", "plugin.json", "README.md")
            git(self.root, "commit", "-qm", "fixture update")
            new_pin = dict(
                self.pin,
                rev=git(self.root, "rev-parse", "HEAD"),
                tree=git(self.root, "rev-parse", "HEAD^{tree}"),
                version="0.2.2",
            )
            new_checkout = sync_skills_plugin.ensure_checkout(
                new_pin, self.checkout_parent
            )
            new_source = sync_skills_plugin.ensure_marketplace_source(
                new_checkout, new_pin, marketplace_parent
            )

            self.assertNotEqual(old_checkout, new_checkout)
            self.assertNotEqual(old_source, new_source)
            self.assertTrue(sync_skills_plugin.verify_checkout(old_checkout, self.pin))
            self.assertTrue(sync_skills_plugin.verify_checkout(new_checkout, new_pin))
            self.assertTrue(
                sync_skills_plugin.verify_payload(
                    old_source,
                    sync_skills_plugin.tracked_tree(old_checkout),
                    self.pin,
                )
            )
            self.assertTrue(
                sync_skills_plugin.verify_payload(
                    new_source,
                    sync_skills_plugin.tracked_tree(new_checkout),
                    new_pin,
                )
            )
            self.assertEqual((old_source / "README.md").read_bytes(), old_readme)
            self.assertEqual(
                (new_source / "README.md").read_text(), "updated fixture\n"
            )
            self.assertEqual(
                sync_skills_plugin.ensure_checkout(self.pin, self.checkout_parent),
                old_checkout,
            )
            self.assertEqual(
                sync_skills_plugin.ensure_marketplace_source(
                    old_checkout, self.pin, marketplace_parent
                ),
                old_source,
            )

    def make_mock_claude(self) -> Path:
        claude_bin = Path(self.temporary.name) / "claude-bin"
        claude_bin.mkdir()
        cli = claude_bin / "claude"
        cli.write_text(
            textwrap.dedent(
                """\
                #!/usr/bin/env python3
                import json, os, shutil, sys
                from pathlib import Path
                args = sys.argv[1:]
                config = Path(os.environ["CLAUDE_CONFIG_DIR"])
                state = config / "mock-marketplace-source"
                log = config.parent / "claude-commands.jsonl"
                plugin_id = "treflebonbon-skills@treflebonbon"
                install_root = config / "plugins/cache/treflebonbon/treflebonbon-skills"
                installed = config / "plugins/installed_plugins.json"
                if args == ["--version"]:
                    print("2.1.312 (Claude Code)")
                    sys.exit(0)
                with log.open("a") as stream:
                    stream.write(json.dumps(args) + "\\n")
                if args[:3] == ["plugin", "marketplace", "add"]:
                    state.write_text(args[3])
                    settings_path = config / "settings.json"
                    settings = json.loads(settings_path.read_text()) if settings_path.exists() else {}
                    settings.setdefault("extraKnownMarketplaces", {})["treflebonbon"] = {
                        "source": {"source": "directory", "path": args[3]}
                    }
                    settings_path.write_text(json.dumps(settings))
                    marketplaces = config / "plugins/known_marketplaces.json"
                    marketplaces.parent.mkdir(parents=True, exist_ok=True)
                    marketplaces.write_text(json.dumps({"treflebonbon": {
                        "source": {"source": "directory", "path": args[3]},
                        "installLocation": args[3]
                    }}))
                    print(json.dumps({"name": "treflebonbon"}))
                elif args[:2] in (["plugin", "install"], ["plugin", "update"]):
                    action = args[1]
                    if (config / f"mock-fail-{action}").exists():
                        sys.exit(74)
                    source = Path(state.read_text())
                    plugin_version = json.loads((source / "plugin.json").read_text())["version"]
                    install = install_root / plugin_version
                    if not install.exists():
                        install.parent.mkdir(parents=True, exist_ok=True)
                        shutil.copytree(source, install, ignore=shutil.ignore_patterns(".git"))
                    settings_path = config / "settings.json"
                    settings = json.loads(settings_path.read_text()) if settings_path.exists() else {}
                    settings.setdefault("enabledPlugins", {})[plugin_id] = True
                    settings_path.write_text(json.dumps(settings))
                    installed.parent.mkdir(parents=True, exist_ok=True)
                    installed.write_text(json.dumps({"version": 2, "plugins": {
                        plugin_id: [{
                            "scope": "user", "version": plugin_version, "installPath": str(install)
                        }]
                    }}))
                    print(json.dumps({action: True}))
                elif args[:3] == ["plugin", "list", "--json"]:
                    fault_path = config / "mock-inventory-fault"
                    if fault_path.exists():
                        fault = json.loads(fault_path.read_text())
                        fault["remaining"] -= 1
                        fault_path.write_text(json.dumps(fault))
                        if fault["remaining"] == 0:
                            if fault["mode"] == "exit":
                                sys.exit(75)
                            print(fault["mode"])
                            sys.exit(0)
                    if not installed.exists():
                        print("[]")
                    else:
                        registry = json.loads(installed.read_text())["plugins"][plugin_id][0]
                        tamper_after = config / "mock-tamper-after-list"
                        if tamper_after.exists():
                            remaining = int(tamper_after.read_text()) - 1
                            tamper_after.write_text(str(remaining))
                            if remaining == 0:
                                (Path(registry["installPath"]) / "README.md").write_text("tampered during inventory\\n")
                        source = state.read_text()
                        plugin_version = json.loads((Path(source) / "plugin.json").read_text())["version"]
                        print(json.dumps([{
                            "id": plugin_id, "version": registry["version"],
                            "scope": "user", "enabled": True,
                            "installPath": registry["installPath"],
                            "readFromFolder": source, "folderVersion": plugin_version
                        }]))
                else:
                    sys.exit(2)
                """
            )
        )
        cli.chmod(0o755)
        return cli

    def test_claude_official_install_is_verified_against_source_and_inventory(
        self,
    ) -> None:
        cli = self.make_mock_claude()
        config = Path(self.temporary.name) / "claude-config"
        config.mkdir()
        (config / "settings.json").write_text('{"env":{"PRESERVE":"yes"}}')
        log = Path(self.temporary.name) / "claude-commands.jsonl"
        with patch.dict(
            os.environ,
            {
                "PATH": f"{cli.parent}:{os.environ['PATH']}",
                "HOME": str(Path(self.temporary.name) / "home"),
                "CLAUDE_CONFIG_DIR": str(config),
            },
        ):
            self.assertEqual(
                sync_skills_plugin.sync_claude(self.root, self.source, self.pin)[
                    "version"
                ],
                "0.2.1",
            )
            calls = [json.loads(line) for line in log.read_text().splitlines()]
            self.assertEqual(calls[0], ["plugin", "list", "--json"])
            self.assertEqual(calls[1][:3], ["plugin", "marketplace", "add"])
            self.assertEqual(calls[1][3], str(self.source))
            self.assertEqual(
                calls[2],
                [
                    "plugin",
                    "install",
                    "treflebonbon-skills@treflebonbon",
                    "--scope",
                    "user",
                    "--json",
                ],
            )
            self.assertEqual(calls[3], ["plugin", "list", "--json"])
            self.assertEqual(
                sync_skills_plugin.sync_claude(self.root, self.source, self.pin)[
                    "version"
                ],
                "0.2.1",
            )
            calls = [json.loads(line) for line in log.read_text().splitlines()]
            self.assertEqual(
                calls,
                [
                    ["plugin", "list", "--json"],
                    [
                        "plugin",
                        "marketplace",
                        "add",
                        str(self.source),
                        "--scope",
                        "user",
                        "--json",
                    ],
                    [
                        "plugin",
                        "install",
                        "treflebonbon-skills@treflebonbon",
                        "--scope",
                        "user",
                        "--json",
                    ],
                    ["plugin", "list", "--json"],
                    ["plugin", "list", "--json"],
                    ["plugin", "list", "--json"],
                ],
            )
            settings = json.loads((config / "settings.json").read_text())
            self.assertEqual(settings["env"]["PRESERVE"], "yes")

            cache = config / "plugins/cache/treflebonbon/treflebonbon-skills/0.2.1"
            (cache / "README.md").write_text("tampered\n")
            with self.assertRaisesRegex(
                sync_skills_plugin.PluginSyncError, "README.md"
            ):
                sync_skills_plugin.sync_claude(self.root, self.source, self.pin)

    def test_unchanged_claude_sync_preserves_managed_settings_bytes(self) -> None:
        cli = self.make_mock_claude()
        home = Path(self.temporary.name) / "home"
        config = home / ".claude"
        config.mkdir(parents=True)
        with patch.dict(
            os.environ,
            {
                "PATH": f"{cli.parent}:{os.environ['PATH']}",
                "HOME": str(home),
                "CLAUDE_CONFIG_DIR": str(config),
            },
        ):
            checkout = sync_skills_plugin.cache_root() / self.pin["rev"]
            checkout.parent.mkdir(parents=True)
            shutil.copytree(self.root, checkout)
            source = sync_skills_plugin.ensure_marketplace_source(checkout, self.pin)
            initial = sync_skills_plugin.sync_claude(checkout, source, self.pin)
            receipt = {
                "schema_version": 1,
                "status": "verified",
                "pin": self.pin,
                "checkout": str(checkout),
                "source": str(source),
                "results": {"claude": initial},
            }
            settings = config / "settings.json"
            settings.write_text(
                json.dumps(json.loads(settings.read_text()), indent=2) + "\n"
            )
            managed_bytes = settings.read_bytes()

            for previous in (None, receipt):
                with self.subTest(previous_receipt=previous is not None):
                    result = sync_skills_plugin.sync_claude(
                        checkout, source, self.pin, previous_verified=previous
                    )

                    self.assertEqual(result["version"], self.pin["version"])
                    self.assertEqual(settings.read_bytes(), managed_bytes)

    def test_claude_sync_repairs_registration_with_current_payload(self) -> None:
        cli = self.make_mock_claude()
        home = Path(self.temporary.name) / "home"
        config = home / ".claude"
        config.mkdir(parents=True)
        with patch.dict(
            os.environ,
            {
                "PATH": f"{cli.parent}:{os.environ['PATH']}",
                "HOME": str(home),
                "CLAUDE_CONFIG_DIR": str(config),
            },
        ):
            sync_skills_plugin.sync_claude(self.root, self.source, self.pin)
            for path in (
                config / "settings.json",
                config / "plugins/known_marketplaces.json",
            ):
                with self.subTest(registration=path.name):
                    path.write_text("{}\n")

                    sync_skills_plugin.sync_claude(self.root, self.source, self.pin)

                    verified = sync_skills_plugin.verify_claude_installation(
                        self.root,
                        self.source,
                        self.pin,
                        sync_skills_plugin.tracked_tree(self.root),
                    )
                    self.assertEqual(verified["version"], self.pin["version"])

    def test_claude_sync_rejects_payload_changed_during_inventory_verification(
        self,
    ) -> None:
        cli = self.make_mock_claude()
        home = Path(self.temporary.name) / "home"
        config = home / ".claude"
        config.mkdir(parents=True)
        with patch.dict(
            os.environ,
            {
                "PATH": f"{cli.parent}:{os.environ['PATH']}",
                "HOME": str(home),
                "CLAUDE_CONFIG_DIR": str(config),
            },
        ):
            sync_skills_plugin.sync_claude(self.root, self.source, self.pin)
            log = home / "claude-commands.jsonl"
            before = len(log.read_text().splitlines())
            (config / "mock-tamper-after-list").write_text("2")

            with self.assertRaisesRegex(
                sync_skills_plugin.PluginSyncError, "README.md"
            ):
                sync_skills_plugin.sync_claude(self.root, self.source, self.pin)

            calls = [
                json.loads(line) for line in log.read_text().splitlines()[before:]
            ]
            self.assertEqual(calls, [["plugin", "list", "--json"]] * 2)
            install = config / "plugins/cache/treflebonbon/treflebonbon-skills/0.2.1"
            self.assertEqual(
                (install / "README.md").read_text(), "tampered during inventory\n"
            )

    def test_claude_inventory_verification_errors_do_not_start_repairs(self) -> None:
        cli = self.make_mock_claude()
        home = Path(self.temporary.name) / "home"
        config = home / ".claude"
        config.mkdir(parents=True)
        with patch.dict(
            os.environ,
            {
                "PATH": f"{cli.parent}:{os.environ['PATH']}",
                "HOME": str(home),
                "CLAUDE_CONFIG_DIR": str(config),
            },
        ):
            sync_skills_plugin.sync_claude(self.root, self.source, self.pin)
            settings = config / "settings.json"
            settings.write_text(
                json.dumps(json.loads(settings.read_text()), indent=2) + "\n"
            )
            managed_bytes = settings.read_bytes()
            log = home / "claude-commands.jsonl"
            for mode in ("exit", "{", "{}", "[]"):
                with self.subTest(inventory_failure=mode):
                    before = len(log.read_text().splitlines())
                    (config / "mock-inventory-fault").write_text(
                        json.dumps({"remaining": 2, "mode": mode})
                    )

                    with self.assertRaises(sync_skills_plugin.PluginSyncError):
                        sync_skills_plugin.sync_claude(self.root, self.source, self.pin)

                    calls = [
                        json.loads(line) for line in log.read_text().splitlines()[before:]
                    ]
                    self.assertEqual(calls, [["plugin", "list", "--json"]] * 2)
                    self.assertEqual(settings.read_bytes(), managed_bytes)

    def test_claude_install_failure_keeps_existing_local_skill(self) -> None:
        cli = self.make_mock_claude()
        home = Path(self.temporary.name) / "home"
        config = home / ".claude"
        legacy = config / "skills/local-skill/SKILL.md"
        legacy.parent.mkdir(parents=True)
        legacy.write_text("legacy\n")
        (config / "mock-fail-install").touch()
        with patch.dict(
            os.environ,
            {
                "PATH": f"{cli.parent}:{os.environ['PATH']}",
                "HOME": str(home),
                "CLAUDE_CONFIG_DIR": str(config),
            },
        ):
            with self.assertRaisesRegex(
                sync_skills_plugin.PluginSyncError, "Claude Code plugin install"
            ):
                sync_skills_plugin.sync_claude(self.root, self.source, self.pin)
            self.assertEqual(legacy.read_text(), "legacy\n")

    def run_native_acceptance(self, *, rewrite_settings: bool = False):
        cli = self.make_mock_claude()
        if rewrite_settings:
            text = cli.read_text()
            anchor = 'elif args[:3] == ["plugin", "list", "--json"]:\n'
            replacement = anchor + textwrap.indent(
                'settings = config / "settings.json"\n'
                "if settings.exists():\n"
                "    settings.write_text(json.dumps(json.loads(settings.read_text())))\n",
                "    ",
            )
            self.assertEqual(text.count(anchor), 1)
            cli.write_text(text.replace(anchor, replacement))
        base = Path(self.temporary.name) / "native-base"
        base.mkdir()
        git(base, "init", "-q")
        git(base, "config", "user.name", "Fixture")
        git(base, "config", "user.email", "fixture@example.invalid")
        for relative in (
            "private_dot_local/bin/executable_sync-skills-plugin",
            "private_dot_claude/settings.json.tmpl",
        ):
            target = base / relative
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(PROJECT_ROOT / relative, target)
        pin = base / "private_dot_config/nix-devshell/skills-plugin.json"
        pin.parent.mkdir(parents=True)
        pin.write_text(json.dumps(self.pin))
        git(base, "add", ".")
        git(base, "commit", "-qm", "native acceptance fixture")
        source = Path(self.temporary.name) / "native-source"
        git(base, "worktree", "add", "-b", "native", str(source))
        original = Path(self.temporary.name) / "original-home"
        original.mkdir()
        sentinel = original / "sentinel"
        sentinel.write_text("preserved")
        result = subprocess.run(
            [
                sys.executable,
                str(PROJECT_ROOT / "scripts/verify-claude-plugin-sync.py"),
                str(source),
                "--checkout",
                str(self.root),
            ],
            env={
                **os.environ,
                "HOME": str(original),
                "PATH": f"{cli.parent}:{os.environ['PATH']}",
            },
            capture_output=True,
            text=True,
        )
        self.assertEqual(sentinel.read_text(), "preserved")
        records = [
            line.removeprefix("検証ログ: ")
            for line in result.stdout.splitlines()
            if line.startswith("検証ログ: ")
        ]
        self.assertEqual(len(records), 1, result.stderr)
        record = Path(records[0])
        evidence = json.loads((record / "result.json").read_text())
        return result, evidence

    @unittest.skipUnless(
        sys.platform == "linux", "requires Linux/WSL2 write protection"
    )
    def test_native_acceptance_checks_two_repeats_with_managed_settings(self) -> None:
        result, evidence = self.run_native_acceptance()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(evidence["status"], "passed")
        self.assertEqual(len(evidence["repeated_syncs"]), 2)
        self.assertTrue(
            all(row["settings_bytes_preserved"] for row in evidence["repeated_syncs"])
        )
        self.assertEqual(evidence["pin"], self.pin)

    @unittest.skipUnless(
        sys.platform == "linux", "requires Linux/WSL2 write protection"
    )
    def test_native_acceptance_rejects_settings_rewritten_by_cli(self) -> None:
        result, evidence = self.run_native_acceptance(rewrite_settings=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(evidence["status"], "failed")
        self.assertFalse(evidence["repeated_syncs"][0]["settings_bytes_preserved"])

    def make_mock_codex(self) -> Path:
        codex_bin = Path(self.temporary.name) / "codex-bin"
        codex_bin.mkdir()
        cli = codex_bin / "codex"
        cli.write_text(
            textwrap.dedent(
                """\
                #!/usr/bin/env python3
                import json, os, shutil, sys
                from pathlib import Path
                args = sys.argv[1:]
                home = Path(os.environ["CODEX_HOME"])
                source_record = home / "mock-marketplace-source"
                installed = home / "mock-installed-plugin.json"
                log = home / "codex-commands.jsonl"
                if args == ["--version"]:
                    print("codex-cli 0.165.0")
                    sys.exit(0)
                with log.open("a") as stream:
                    stream.write(json.dumps(args) + "\\n")
                if args[:3] == ["plugin", "marketplace", "add"]:
                    source = Path(args[3])
                    config = home / "config.toml"
                    if config.exists():
                        current = config.read_text()
                        marker = 'source = "'
                        existing = next((line[len(marker):-1] for line in current.splitlines() if line.startswith(marker)), None)
                        if existing is not None and existing != str(source):
                            print("marketplace 'treflebonbon' is already added from a different source; remove it before adding this source", file=sys.stderr)
                            sys.exit(1)
                    fail_source = home / "mock-fail-marketplace-source"
                    if fail_source.exists() and fail_source.read_text() == str(source):
                        fail_source.unlink()
                        print("fixture marketplace add failure", file=sys.stderr)
                        sys.exit(74)
                    source_record.write_text(str(source))
                    config.parent.mkdir(parents=True, exist_ok=True)
                    plugin_config = '[plugins."treflebonbon-skills@treflebonbon"]\\nenabled = true\\n'
                    config.write_text('[marketplaces.treflebonbon]\\nsource_type = "local"\\nsource = "' + str(source) + '"\\n' + plugin_config)
                    print(json.dumps({"name": "treflebonbon"}))
                elif args[:3] == ["plugin", "marketplace", "remove"]:
                    config = home / "config.toml"
                    lines = config.read_text().splitlines(keepends=True) if config.exists() else []
                    kept = []
                    in_marketplace = False
                    for line in lines:
                        if line.startswith("["):
                            in_marketplace = line.strip() == "[marketplaces.treflebonbon]"
                        if not in_marketplace:
                            kept.append(line)
                    config.write_text("".join(kept))
                    source_record.unlink(missing_ok=True)
                    print(json.dumps({"removed": True}))
                elif args[:2] == ["plugin", "add"]:
                    source = Path(source_record.read_text())
                    version = json.loads((source / "plugin.json").read_text())["version"]
                    install = home / "plugins/cache/treflebonbon/treflebonbon-skills" / version
                    if not install.exists():
                        shutil.copytree(source, install, ignore=shutil.ignore_patterns(".git"))
                    installed.write_text(json.dumps({"version": version, "source": str(source), "install_path": str(install)}))
                    print(json.dumps({"installed": True}))
                elif args[:3] == ["plugin", "list", "--json"]:
                    if not installed.exists():
                        print(json.dumps({"installed": [], "available": []}))
                    else:
                        state = json.loads(installed.read_text())
                        source = Path(state["source"])
                        print(json.dumps({"installed": [{
                            "pluginId": "treflebonbon-skills@treflebonbon", "name": "treflebonbon-skills",
                            "marketplaceName": "treflebonbon", "version": state["version"], "installed": True,
                            "enabled": True, "source": {"source": "local", "path": str(source)},
                            "marketplaceSource": {"sourceType": "local", "source": str(source)}
                        }]}))
                else:
                    sys.exit(2)
                """
            )
        )
        cli.chmod(0o755)
        return cli

    def test_codex_official_install_checks_marketplace_inventory_and_payload(
        self,
    ) -> None:
        cli = self.make_mock_codex()
        home = Path(self.temporary.name) / "codex home"
        legacy = home / "skills/local-skill/SKILL.md"
        legacy.parent.mkdir(parents=True)
        legacy.write_text("legacy\n")
        log = home / "codex-commands.jsonl"
        with patch.dict(
            os.environ,
            {
                "PATH": f"{cli.parent}:{os.environ['PATH']}",
                "HOME": str(Path(self.temporary.name) / "home"),
                "CODEX_HOME": str(home),
            },
        ):
            result = sync_skills_plugin.sync_codex(
                self.root, self.source, self.pin, home
            )
            self.assertEqual(result["version"], "0.2.1")
            calls = [json.loads(line) for line in log.read_text().splitlines()]
            first_sync = [
                ["plugin", "marketplace", "add", str(self.source), "--json"],
                ["plugin", "add", "treflebonbon-skills@treflebonbon", "--json"],
                ["plugin", "list", "--json"],
            ]
            self.assertEqual(calls, first_sync)
            self.assertEqual(
                sync_skills_plugin.sync_codex(self.root, self.source, self.pin, home)[
                    "version"
                ],
                "0.2.1",
            )
            self.assertEqual(
                [json.loads(line) for line in log.read_text().splitlines()],
                first_sync * 2,
            )
            config = tomllib.loads((home / "config.toml").read_text())
            self.assertEqual(
                config["marketplaces"]["treflebonbon"]["source"], str(self.source)
            )
            self.assertEqual(legacy.read_text(), "legacy\n")

            cache = home / "plugins/cache/treflebonbon/treflebonbon-skills/0.2.1"
            (cache / "README.md").write_text("tampered\n")
            with self.assertRaisesRegex(
                sync_skills_plugin.PluginSyncError, "README.md"
            ):
                sync_skills_plugin.sync_codex(self.root, self.source, self.pin, home)

    def test_read_only_verification_matches_current_homes_and_leaves_receipt_unchanged(
        self,
    ) -> None:
        claude = self.make_mock_claude()
        cli = self.make_mock_codex()
        agy = self.make_mock_agy()
        home = Path(self.temporary.name) / "managed-home"
        claude_config = home / ".claude"
        claude_config.mkdir(parents=True)
        codex_app = home / ".codex-app"
        codex_app.mkdir(parents=True)
        explicit = Path(self.temporary.name) / "explicit-codex-home"
        homes = [home / ".codex", codex_app, explicit]
        receipt_file = Path(self.temporary.name) / "state/receipt.json"
        environment = {
            "PATH": f"{claude.parent}:{cli.parent}:{agy.parent}:{os.environ['PATH']}",
            "HOME": str(home),
            "CODEX_HOME": str(explicit),
            "CLAUDE_CONFIG_DIR": str(claude_config),
        }

        with patch.dict(os.environ, environment):
            sync_skills_plugin.sync_all(
                homes,
                pin=self.pin,
                checkout=self.root,
                source_root=self.source,
                receipt_file=receipt_file,
            )
            before = receipt_file.read_bytes()
            before_stat = receipt_file.stat()
            command_counts = {
                path: len((path / "codex-commands.jsonl").read_text().splitlines())
                for path in homes
            }
            claude_log = home / "claude-commands.jsonl"
            agy_log = home / "agy-commands.jsonl"
            claude_count = len(claude_log.read_text().splitlines())
            agy_count = len(agy_log.read_text().splitlines())
            managed_files = [
                claude_config / "settings.json",
                claude_config / "plugins/known_marketplaces.json",
                claude_config / "plugins/installed_plugins.json",
                home / ".gemini/config/import_manifest.json",
            ]
            managed_before = {path: path.read_bytes() for path in managed_files}
            cache_roots = [
                claude_config / "plugins/cache",
                home / ".gemini/config/plugins/treflebonbon-skills",
                *(path / "plugins/cache" for path in homes),
            ]
            cache_before = {
                root: sync_skills_plugin.filesystem_tree(root)[0]
                for root in cache_roots
            }

            result = sync_skills_plugin.verify_current_installation(
                sync_skills_plugin.current_codex_homes(),
                pin=self.pin,
                checkout=self.root,
                source_root=self.source,
                receipt_file=receipt_file,
            )
            cli_source = sync_skills_plugin.verify_cli_source(
                sync_skills_plugin.current_codex_homes(),
                pin=self.pin,
                checkout=self.root,
                source_root=self.source,
                receipt_file=receipt_file,
            )
            self.assertEqual(cli_source["source"], str(self.source.resolve()))
            for name in sync_skills_plugin.GLOBAL_CLI_NAMES:
                self.assertEqual(
                    sync_skills_plugin.public_cli_path(cli_source["source"], name),
                    self.source / "bin" / name,
                )

        self.assertEqual(result["source"], str(self.source.resolve()))
        self.assertEqual(result["codex_homes"], [str(path.resolve()) for path in homes])
        self.assertEqual(receipt_file.read_bytes(), before)
        self.assertEqual(receipt_file.stat().st_mtime_ns, before_stat.st_mtime_ns)
        self.assertEqual(
            {path: path.read_bytes() for path in managed_files}, managed_before
        )
        self.assertEqual(
            {root: sync_skills_plugin.filesystem_tree(root)[0] for root in cache_roots},
            cache_before,
        )
        for codex_home in homes:
            commands = [
                json.loads(line)
                for line in (codex_home / "codex-commands.jsonl")
                .read_text()
                .splitlines()
            ]
            self.assertEqual(
                commands[command_counts[codex_home] :],
                [["plugin", "list", "--json"]],
            )
        self.assertEqual(
            [json.loads(line) for line in claude_log.read_text().splitlines()][
                claude_count:
            ],
            [["plugin", "list", "--json"]],
        )
        self.assertEqual(
            [json.loads(line) for line in agy_log.read_text().splitlines()][agy_count:],
            [["plugin", "list", "--json"]],
        )
        module = self.source / "lib/python/treflebonbon_skills/codex_reviewer.py"
        module.write_text("tampered module\n")
        with patch.dict(os.environ, environment):
            with self.assertRaisesRegex(
                sync_skills_plugin.PluginSyncError,
                "installed plugin content does not match pin: lib/python/treflebonbon_skills/codex_reviewer.py",
            ):
                sync_skills_plugin.verify_cli_source(
                    homes,
                    pin=self.pin,
                    checkout=self.root,
                    source_root=self.source,
                    receipt_file=receipt_file,
                )

    def test_read_only_verification_rejects_duplicate_or_stale_codex_homes(
        self,
    ) -> None:
        cli = self.make_mock_codex()
        home = Path(self.temporary.name) / "managed-home"
        codex_home = home / ".codex"
        receipt_file = Path(self.temporary.name) / "state/receipt.json"
        with (
            patch.dict(
                os.environ,
                {
                    "PATH": f"{cli.parent}:{os.environ['PATH']}",
                    "HOME": str(home),
                },
            ),
            patch.object(
                sync_skills_plugin,
                "sync_claude",
                return_value={"runtime": "claude"},
            ),
            patch.object(
                sync_skills_plugin, "sync_agy", return_value={"runtime": "agy"}
            ),
        ):
            sync_skills_plugin.sync_all(
                [codex_home],
                pin=self.pin,
                checkout=self.root,
                source_root=self.source,
                receipt_file=receipt_file,
            )
            with self.assertRaisesRegex(
                sync_skills_plugin.PluginSyncError, "duplicate Codex home"
            ):
                sync_skills_plugin.verify_current_installation(
                    [codex_home, codex_home],
                    pin=self.pin,
                    checkout=self.root,
                    source_root=self.source,
                    receipt_file=receipt_file,
                )

            (home / ".codex-app").mkdir()
            with self.assertRaisesRegex(
                sync_skills_plugin.PluginSyncError, "current Codex homes"
            ):
                sync_skills_plugin.verify_current_installation(
                    sync_skills_plugin.current_codex_homes(),
                    pin=self.pin,
                    checkout=self.root,
                    source_root=self.source,
                    receipt_file=receipt_file,
                )

            receipt = json.loads(receipt_file.read_text())
            receipt["pin"]["rev"] = "0" * 40
            receipt_file.write_text(json.dumps(receipt) + "\n")
            with self.assertRaisesRegex(
                sync_skills_plugin.PluginSyncError, "receipt pin does not match"
            ):
                sync_skills_plugin.verify_current_installation(
                    [codex_home],
                    pin=self.pin,
                    checkout=self.root,
                    source_root=self.source,
                    receipt_file=receipt_file,
                )

    def test_verify_only_command_reports_the_read_only_result(self) -> None:
        result = {
            "status": "verified",
            "pin": self.pin,
            "checkout": str(self.root),
            "source": str(self.source),
            "codex_homes": ["/fixture/.codex"],
            "results": {"codex": []},
        }
        output = io.StringIO()
        with (
            patch.object(sys, "argv", [str(SCRIPT), "--verify-only"]),
            patch.object(
                sync_skills_plugin,
                "verify_current_installation",
                return_value=result,
            ) as verify,
            patch.object(sync_skills_plugin, "sync_all") as sync,
            redirect_stdout(output),
        ):
            status = sync_skills_plugin.main()

        self.assertEqual(status, 0)
        self.assertEqual(json.loads(output.getvalue()), result)
        verify.assert_called_once_with(None)
        sync.assert_not_called()

    def test_verify_source_only_command_does_not_require_receipt_or_runtime_state(
        self,
    ) -> None:
        result = sync_skills_plugin.verify_fixed_source(
            pin=self.pin, checkout=self.root, source_root=self.source
        )
        self.assertEqual(result["status"], "verified")
        self.assertEqual(result["checkout"], str(self.root))
        self.assertEqual(result["source"], str(self.source))

    def test_verify_source_only_cli_is_read_only(self) -> None:
        result = {
            "status": "verified",
            "pin": self.pin,
            "checkout": str(self.root),
            "source": str(self.source),
            "files": self.pin["file_count"],
        }
        output = io.StringIO()
        with (
            patch.object(sys, "argv", [str(SCRIPT), "--verify-source-only"]),
            patch.object(
                sync_skills_plugin, "verify_fixed_source", return_value=result
            ) as verify,
            patch.object(sync_skills_plugin, "sync_all") as sync,
            redirect_stdout(output),
        ):
            status = sync_skills_plugin.main()

        self.assertEqual(status, 0)
        self.assertEqual(json.loads(output.getvalue()), result)
        verify.assert_called_once_with()
        sync.assert_not_called()

    def test_run_raw_command_uses_only_the_verified_public_entry(self) -> None:
        entry = self.source / "bin/devshell-env"
        entry.parent.mkdir(parents=True, exist_ok=True)
        entry.write_text("#!/bin/sh\nexit 0\n")
        entry.chmod(0o755)
        with (
            patch.object(
                sync_skills_plugin,
                "verify_cli_source",
                return_value={"source": str(self.source)},
            ),
            patch.object(sync_skills_plugin.os, "execv") as execv,
        ):
            sync_skills_plugin.exec_raw_runtime(
                "admit", ["--git-head", "a" * 40, "--", "flake.nix", "task.sh"]
            )

        execv.assert_called_once_with(
            str(entry),
            [str(entry), "admit", "--git-head", "a" * 40, "--", "flake.nix", "task.sh"],
        )

    def test_codex_worktree_uses_the_public_entry_without_a_command_prefix(
        self,
    ) -> None:
        entry = self.source / "bin/codex-worktree"
        with (
            patch.object(
                sync_skills_plugin,
                "verify_cli_source",
                return_value={"source": str(self.source)},
            ),
            patch.object(sync_skills_plugin.os, "execv") as execv,
        ):
            sync_skills_plugin.exec_raw_runtime(
                "codex-worktree", ["--no-alt-screen", "task with spaces"]
            )

        execv.assert_called_once_with(
            str(entry), [str(entry), "--no-alt-screen", "task with spaces"]
        )

    def test_run_raw_command_stops_when_the_public_entry_is_missing(self) -> None:
        (self.source / "bin/devshell-env").unlink()
        with (
            patch.object(
                sync_skills_plugin,
                "verify_cli_source",
                return_value={"source": str(self.source)},
            ),
            patch.object(sync_skills_plugin.os, "execv") as execv,
        ):
            with self.assertRaisesRegex(
                sync_skills_plugin.PluginSyncError, "pinned raw runtime unavailable"
            ):
                sync_skills_plugin.exec_raw_runtime("codex", ["--probe"])

        execv.assert_not_called()

    def test_raw_codex_worktree_stops_when_its_public_entry_is_missing(self) -> None:
        (self.source / "bin/codex-worktree").unlink()
        with (
            patch.object(
                sync_skills_plugin,
                "verify_cli_source",
                return_value={"source": str(self.source)},
            ),
            patch.object(sync_skills_plugin.os, "execv") as execv,
        ):
            with self.assertRaisesRegex(
                sync_skills_plugin.PluginSyncError, "pinned raw runtime unavailable"
            ):
                sync_skills_plugin.exec_raw_runtime("codex-worktree", ["--probe"])

        execv.assert_not_called()

    def test_current_codex_home_detection_deduplicates_default_and_explicit_paths(
        self,
    ) -> None:
        home = Path(self.temporary.name) / "home"
        desktop = home / ".codex-app"
        desktop.mkdir(parents=True)
        with patch.dict(
            os.environ,
            {"HOME": str(home), "CODEX_HOME": str(home / ".codex")},
        ):
            self.assertEqual(
                sync_skills_plugin.current_codex_homes(),
                [home / ".codex", desktop],
            )

    def test_current_receipt_does_not_fall_back_to_previous_verified_receipt(
        self,
    ) -> None:
        receipt_file = Path(self.temporary.name) / "state/receipt.json"
        receipt_file.parent.mkdir()
        receipt_file.write_text(
            json.dumps(
                {
                    "schema_version": 1,
                    "status": "failed",
                    "previous_verified": {"schema_version": 1, "status": "verified"},
                }
            )
            + "\n"
        )
        receipt_file.chmod(0o600)
        with self.assertRaisesRegex(
            sync_skills_plugin.PluginSyncError,
            "current plugin sync receipt is not verified",
        ):
            sync_skills_plugin.read_verified_receipt(receipt_file)

    def test_global_cli_dispatch_preserves_the_reviewed_entry_name(self) -> None:
        selected = self.source / "bin/git-push-reviewed"
        with (
            patch.object(
                sync_skills_plugin,
                "verify_cli_source",
                return_value={"source": str(self.source)},
            ),
            patch.object(
                sync_skills_plugin.os, "execv", side_effect=RuntimeError("exec")
            ) as execv,
        ):
            with self.assertRaisesRegex(RuntimeError, "exec"):
                sync_skills_plugin.exec_global_cli("git-push-reviewed", ["--probe"])

        execv.assert_called_once_with(str(selected), [str(selected), "--probe"])

    def test_each_public_cli_start_failure_recovers_to_its_validated_backup(
        self,
    ) -> None:
        for name in sorted(sync_skills_plugin.GLOBAL_CLI_NAMES):
            backup = Path(self.temporary.name) / f"legacy/{name}"
            backup.parent.mkdir(parents=True, exist_ok=True)
            backup.write_text("#!/bin/sh\nexit 0\n")
            with (
                patch.object(
                    sync_skills_plugin,
                    "verify_cli_source",
                    return_value={"source": str(self.source)},
                ),
                patch.object(
                    sync_skills_plugin,
                    "verified_legacy_cli_backup",
                    return_value=backup,
                ),
                patch.object(
                    sync_skills_plugin.os,
                    "execv",
                    side_effect=[
                        OSError("fixture startup failure"),
                        RuntimeError("fallback exec"),
                    ],
                ) as execv,
            ):
                with self.assertRaisesRegex(RuntimeError, "fallback exec"):
                    sync_skills_plugin.exec_global_cli(name, ["--probe"])

            self.assertEqual(
                execv.call_args_list,
                [
                    call(
                        str(self.source / "bin" / name),
                        [str(self.source / "bin" / name), "--probe"],
                    ),
                    call(str(backup), [str(backup), "--probe"]),
                ],
            )

    def test_missing_public_cli_uses_only_the_validated_legacy_backup(self) -> None:
        backup = Path(self.temporary.name) / "legacy/orca-send"
        with (
            patch.object(
                sync_skills_plugin,
                "verify_cli_source",
                return_value={
                    "source": str(Path(self.temporary.name) / "missing-source")
                },
            ),
            patch.object(
                sync_skills_plugin,
                "verified_legacy_cli_backup",
                return_value=backup,
            ),
            patch.object(
                sync_skills_plugin.os, "execv", side_effect=RuntimeError("exec")
            ) as execv,
        ):
            with self.assertRaisesRegex(RuntimeError, "exec"):
                sync_skills_plugin.exec_global_cli("orca-send", ["--probe"])

        execv.assert_called_once_with(str(backup), [str(backup), "--probe"])

    def test_global_cli_dispatch_uses_only_a_validated_legacy_backup_on_stale_state(
        self,
    ) -> None:
        backup = Path(self.temporary.name) / "legacy/git-push-topic"
        backup.parent.mkdir(parents=True)
        backup.write_text("#!/bin/sh\nexit 0\n")
        with (
            patch.object(
                sync_skills_plugin,
                "verify_cli_source",
                side_effect=sync_skills_plugin.PluginSyncError("stale receipt"),
            ),
            patch.object(
                sync_skills_plugin,
                "verified_legacy_cli_backup",
                return_value=backup,
            ),
            patch.object(
                sync_skills_plugin.os, "execv", side_effect=RuntimeError("exec")
            ) as execv,
        ):
            with self.assertRaisesRegex(RuntimeError, "exec"):
                sync_skills_plugin.exec_global_cli("git-push-topic", ["--probe"])

        execv.assert_called_once_with(str(backup), [str(backup), "--probe"])

    def test_legacy_backup_manifest_and_payload_cannot_be_changed_together(
        self,
    ) -> None:
        backup_state = (
            Path(self.temporary.name)
            / ".local/state/treflebonbon-skills/plugin-sync/receipt.json"
        )
        legacy_root = (
            backup_state.parents[2]
            / "treflebonbon-skills/legacy"
            / sync_skills_plugin.LEGACY_CLI_REVISION
        )
        names = {f".local/bin/{name}" for name in sync_skills_plugin.GLOBAL_CLI_NAMES}
        names.add(".local/share/devshell-env/devshell_environment.py")
        cli_manifest = {}
        for relative in sorted(names):
            cli_manifest[relative] = {
                "sha256": sync_skills_plugin.hashlib.sha256(
                    relative.encode()
                ).hexdigest(),
                "mode": 0o755 if relative.startswith(".local/bin/") else 0o644,
            }
        trusted = {
            "revision": sync_skills_plugin.LEGACY_CLI_REVISION,
            "cli": cli_manifest,
        }
        with (
            patch.object(sync_skills_plugin, "state_path", return_value=backup_state),
            patch.object(
                sync_skills_plugin, "trusted_legacy_cli_manifest", return_value=trusted
            ),
        ):
            for relative, expected in cli_manifest.items():
                path = legacy_root / relative
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_bytes(relative.encode())
                path.chmod(expected["mode"])
            manifest_path = legacy_root / "baseline.json"
            manifest_path.write_text(
                json.dumps({**trusted, "skills": {}, "directories": {}}) + "\n"
            )
            manifest_path.chmod(0o600)

            selected = sync_skills_plugin.verified_legacy_cli_backup("git-push-topic")
            self.assertEqual(selected, legacy_root / ".local/bin/git-push-topic")

            changed = legacy_root / ".local/bin/git-push-topic"
            changed.write_text("altered payload\n")
            changed.chmod(0o755)
            changed_relative = ".local/bin/git-push-topic"
            altered_manifest = json.loads(manifest_path.read_text())
            altered_manifest["cli"][changed_relative]["sha256"] = (
                sync_skills_plugin.hashlib.sha256(changed.read_bytes()).hexdigest()
            )
            manifest_path.write_text(json.dumps(altered_manifest) + "\n")
            manifest_path.chmod(0o600)
            with self.assertRaisesRegex(
                sync_skills_plugin.PluginSyncError, "manifest is invalid"
            ):
                sync_skills_plugin.verified_legacy_cli_backup("git-push-topic")

    def test_read_only_verification_rejects_symlinked_source_before_resolving(
        self,
    ) -> None:
        source_alias = Path(self.temporary.name) / "source-alias"
        source_alias.symlink_to(self.source, target_is_directory=True)
        with self.assertRaisesRegex(
            sync_skills_plugin.PluginSyncError, "source snapshot root is a symlink"
        ):
            sync_skills_plugin.verify_pinned_source(
                [Path(self.temporary.name) / "home/.codex"],
                pin=self.pin,
                checkout=self.root,
                source_root=source_alias,
                receipt_file=Path(self.temporary.name) / "missing-receipt.json",
                require_existing_homes=False,
            )

    def test_failed_codex_source_update_restores_previous_verified_registration(
        self,
    ) -> None:
        cli = self.make_mock_codex()
        home = Path(self.temporary.name) / "home"
        codex_home = home / "codex"
        legacy = codex_home / "skills/local-skill/SKILL.md"
        legacy.parent.mkdir(parents=True)
        legacy.write_text("legacy\n")
        old_checkout = home / ".cache/treflebonbon-skills/checkouts" / self.pin["rev"]
        old_checkout.parent.mkdir(parents=True)
        shutil.copytree(self.root, old_checkout)
        old_source_parent = home / ".cache/treflebonbon-skills/marketplaces"
        old_source = sync_skills_plugin.ensure_marketplace_source(
            old_checkout, self.pin, old_source_parent
        )
        new_source = sync_skills_plugin.ensure_marketplace_source(
            self.root,
            self.pin,
            Path(self.temporary.name) / "new-marketplaces",
        )
        receipt_file = (
            home / ".local/state/treflebonbon-skills/plugin-sync/receipt.json"
        )
        with patch.dict(
            os.environ,
            {
                "PATH": f"{cli.parent}:{os.environ['PATH']}",
                "HOME": str(home),
                "CODEX_HOME": str(codex_home),
            },
        ):
            previous_codex = sync_skills_plugin.sync_codex(
                old_checkout, old_source, self.pin, codex_home
            )
            previous = {
                "schema_version": 1,
                "status": "verified",
                "pin": {
                    key: self.pin[key]
                    for key in (
                        "owner",
                        "repo",
                        "rev",
                        "tree",
                        "version",
                        "nar_hash",
                        "file_count",
                    )
                },
                "checkout": str(old_checkout),
                "source": str(old_source),
                "codex_homes": [str(codex_home)],
                "results": {
                    "claude": {"runtime": "claude"},
                    "codex": [previous_codex],
                    "agy": {"runtime": "agy"},
                },
            }
            sync_skills_plugin.write_receipt(receipt_file, previous)
            (codex_home / "mock-fail-marketplace-source").write_text(str(new_source))

            with patch.object(
                sync_skills_plugin, "sync_claude", return_value={"runtime": "claude"}
            ):
                with self.assertRaises(sync_skills_plugin.PluginSyncError):
                    sync_skills_plugin.sync_all(
                        [codex_home],
                        pin=self.pin,
                        checkout=self.root,
                        source_root=new_source,
                        receipt_file=receipt_file,
                    )

            failed = json.loads(receipt_file.read_text())
            self.assertEqual(failed["status"], "failed")
            self.assertEqual(failed["previous_verified"], previous)
            self.assertIn(
                "recovery",
                failed,
                json.dumps(
                    {
                        "failure": failed.get("failure"),
                        "calls": [
                            json.loads(line)
                            for line in (codex_home / "codex-commands.jsonl")
                            .read_text()
                            .splitlines()
                        ],
                    }
                ),
            )
            self.assertEqual(
                failed["recovery"],
                {
                    "runtime": "codex",
                    "codex_home": str(codex_home.resolve()),
                    "update_error_type": "PluginCliError",
                    "previous_source": str(old_source.resolve()),
                    "previous_version": self.pin["version"],
                    "previous_plugin_usable": True,
                },
            )
            self.assertTrue(
                failed["rollback"]["runtimes"][f"codex:{codex_home.resolve()}"][
                    "usable"
                ]
            )
            config = tomllib.loads((codex_home / "config.toml").read_text())
            self.assertEqual(
                config["marketplaces"]["treflebonbon"]["source"],
                str(old_source.resolve()),
            )
            self.assertEqual(legacy.read_text(), "legacy\n")
            install = (
                codex_home
                / "plugins/cache/treflebonbon/treflebonbon-skills"
                / self.pin["version"]
            )
            self.assertTrue(
                sync_skills_plugin.verify_payload(
                    install, sync_skills_plugin.tracked_tree(old_checkout), self.pin
                )
            )
            calls = [
                json.loads(line)
                for line in (codex_home / "codex-commands.jsonl")
                .read_text()
                .splitlines()
            ]
            self.assertEqual(
                calls[-5:],
                [
                    ["plugin", "marketplace", "add", str(new_source), "--json"],
                    ["plugin", "marketplace", "remove", "treflebonbon", "--json"],
                    ["plugin", "marketplace", "add", str(new_source), "--json"],
                    ["plugin", "marketplace", "add", str(old_source), "--json"],
                    ["plugin", "list", "--json"],
                ],
            )

            with (
                patch.object(
                    sync_skills_plugin,
                    "sync_claude",
                    return_value={"runtime": "claude"},
                ),
                patch.object(
                    sync_skills_plugin,
                    "sync_agy",
                    return_value={"runtime": "agy"},
                ),
            ):
                retried = sync_skills_plugin.sync_all(
                    [codex_home],
                    pin=self.pin,
                    checkout=self.root,
                    source_root=new_source,
                    receipt_file=receipt_file,
                )
            self.assertEqual(retried["status"], "verified")
            self.assertNotIn("previous_verified", retried)
            self.assertEqual(retried["source"], str(new_source.resolve()))
            config = tomllib.loads((codex_home / "config.toml").read_text())
            self.assertEqual(
                config["marketplaces"]["treflebonbon"]["source"],
                str(new_source.resolve()),
            )

    def make_mock_agy(self) -> Path:
        agy_bin = Path(self.temporary.name) / "agy-bin"
        agy_bin.mkdir()
        cli = agy_bin / "agy"
        cli.write_text(
            textwrap.dedent(
                """\
                #!/usr/bin/env python3
                import json, os, shutil, sys
                from pathlib import Path
                args = sys.argv[1:]
                home = Path(os.environ["HOME"])
                root = home / ".gemini/config/plugins/treflebonbon-skills"
                source_record = home / ".gemini/config/plugin-source"
                log = home / "agy-commands.jsonl"
                if args == ["--version"]:
                    print("1.4.8")
                    sys.exit(0)
                with log.open("a") as stream:
                    stream.write(json.dumps(args) + "\\n")
                if args[:2] == ["plugin", "install"]:
                    if (home / "mock-fail-install").exists():
                        sys.exit(74)
                    fail_source = home / "mock-fail-install-source"
                    if fail_source.exists() and fail_source.read_text() == args[2]:
                        fail_source.unlink()
                        print("fixture plugin install failure", file=sys.stderr)
                        sys.exit(74)
                    source_record.parent.mkdir(parents=True, exist_ok=True)
                    source_record.write_text(args[2])
                    source = Path(args[2])
                    target_version = json.loads((source / "plugin.json").read_text())["version"]
                    current_version = None
                    if root.exists() and (root / "plugin.json").exists():
                        current_version = json.loads((root / "plugin.json").read_text())["version"]
                    if root.exists() and current_version != target_version:
                        shutil.rmtree(root)
                    if not root.exists():
                        shutil.copytree(source, root, ignore=shutil.ignore_patterns(".git"))
                    manifest = home / ".gemini/config/import_manifest.json"
                    manifest.parent.mkdir(parents=True, exist_ok=True)
                    manifest.write_text(json.dumps({"imports": [{
                        "name": "treflebonbon-skills", "source": "antigravity", "components": ["skills"]
                    }]}))
                    print("installed")
                elif args[:3] == ["plugin", "list", "--json"]:
                    source = Path(source_record.read_text())
                    skills = sorted(path.parent.name for path in root.glob("skills/*/SKILL.md"))
                    version = json.loads((root / "plugin.json").read_text())["version"]
                    print(json.dumps([{
                        "name": "treflebonbon-skills", "enabled": True, "version": version,
                        "source": "antigravity", "path": str(root), "skills": skills
                    }]))
                else:
                    sys.exit(2)
                """
            )
        )
        cli.chmod(0o755)
        return cli

    def test_antigravity_official_install_checks_inventory_import_and_payload(
        self,
    ) -> None:
        cli = self.make_mock_agy()
        home = Path(self.temporary.name) / "agy home"
        legacy = home / ".gemini/skills/local-skill/SKILL.md"
        legacy.parent.mkdir(parents=True)
        legacy.write_text("legacy\n")
        log = home / "agy-commands.jsonl"
        with patch.dict(
            os.environ,
            {
                "PATH": f"{cli.parent}:{os.environ['PATH']}",
                "HOME": str(home),
            },
        ):
            result = sync_skills_plugin.sync_agy(self.root, self.source, self.pin)
            self.assertEqual(result["version"], "0.2.1")
            first_sync = [
                ["plugin", "install", str(self.source)],
                ["plugin", "list", "--json"],
            ]
            self.assertEqual(
                [json.loads(line) for line in log.read_text().splitlines()], first_sync
            )
            self.assertEqual(
                sync_skills_plugin.sync_agy(self.root, self.source, self.pin)[
                    "version"
                ],
                "0.2.1",
            )
            self.assertEqual(
                [json.loads(line) for line in log.read_text().splitlines()],
                first_sync * 2,
            )
            self.assertEqual(legacy.read_text(), "legacy\n")

            cache = home / ".gemini/config/plugins/treflebonbon-skills"
            (cache / "README.md").write_text("tampered\n")
            with self.assertRaisesRegex(
                sync_skills_plugin.PluginSyncError, "README.md"
            ):
                sync_skills_plugin.sync_agy(self.root, self.source, self.pin)

    def test_antigravity_install_failure_keeps_existing_local_skill(self) -> None:
        cli = self.make_mock_agy()
        home = Path(self.temporary.name) / "agy-home"
        legacy = home / ".gemini/skills/local-skill/SKILL.md"
        legacy.parent.mkdir(parents=True)
        legacy.write_text("legacy\n")
        (home / "mock-fail-install").touch()
        with patch.dict(
            os.environ,
            {
                "PATH": f"{cli.parent}:{os.environ['PATH']}",
                "HOME": str(home),
            },
        ):
            with self.assertRaisesRegex(
                sync_skills_plugin.PluginSyncError, "Antigravity plugin install"
            ):
                sync_skills_plugin.sync_agy(self.root, self.source, self.pin)
        self.assertEqual(legacy.read_text(), "legacy\n")

    def test_receipt_is_verified_only_after_all_runtime_checks_finish(self) -> None:
        receipt_file = Path(self.temporary.name) / "state/receipt.json"
        codex_homes = [
            Path(self.temporary.name) / "codex-one",
            Path(self.temporary.name) / "codex-two",
        ]
        with (
            patch.object(
                sync_skills_plugin, "sync_claude", return_value={"runtime": "claude"}
            ) as claude,
            patch.object(
                sync_skills_plugin,
                "sync_codex",
                side_effect=lambda checkout, source, pin, home, previous_verified=None: {
                    "home": str(home)
                },
            ) as codex,
            patch.object(
                sync_skills_plugin, "sync_agy", return_value={"runtime": "agy"}
            ) as agy,
        ):
            receipt = sync_skills_plugin.sync_all(
                codex_homes,
                pin=self.pin,
                checkout=self.root,
                source_root=self.source,
                receipt_file=receipt_file,
            )
        self.assertEqual(receipt["status"], "verified")
        self.assertEqual(json.loads(receipt_file.read_text())["status"], "verified")
        self.assertEqual(len(receipt["results"]["codex"]), 2)
        self.assertEqual(codex.call_count, 2)
        claude.assert_called_once()
        agy.assert_called_once()
        self.assertEqual(receipt_file.stat().st_mode & 0o777, 0o600)

    def test_partial_runtime_failure_restores_previous_native_plugin_everywhere(
        self,
    ) -> None:
        claude = self.make_mock_claude()
        codex = self.make_mock_codex()
        agy = self.make_mock_agy()
        home = Path(self.temporary.name) / "partial-update-home"
        codex_homes = [home / ".codex", home / ".codex-app"]
        (home / ".claude").mkdir(parents=True)
        checkout_root = home / ".cache/treflebonbon-skills/checkouts"
        marketplace_root = home / ".cache/treflebonbon-skills/marketplaces"
        receipt_file = (
            home / ".local/state/treflebonbon-skills/plugin-sync/receipt.json"
        )
        old_checkout = checkout_root / self.pin["rev"]
        old_checkout.parent.mkdir(parents=True)
        shutil.copytree(self.root, old_checkout)
        old_source = sync_skills_plugin.ensure_marketplace_source(
            old_checkout, self.pin, marketplace_root
        )

        with patch.dict(
            os.environ,
            {
                "PATH": f"{claude.parent}:{codex.parent}:{agy.parent}:{os.environ['PATH']}",
                "HOME": str(home),
                "CLAUDE_CONFIG_DIR": str(home / ".claude"),
                "CODEX_HOME": str(codex_homes[0]),
            },
        ):
            previous = sync_skills_plugin.sync_all(
                codex_homes,
                pin=self.pin,
                checkout=old_checkout,
                source_root=old_source,
                receipt_file=receipt_file,
            )
            self.assertEqual(previous["status"], "verified")
            self.assertEqual(len(previous["results"]["codex"]), 2)

            (self.root / "plugin.json").write_text(
                json.dumps({"name": "treflebonbon-skills", "version": "0.2.2"}) + "\n"
            )
            (self.root / "README.md").write_text("updated fixture\n")
            git(self.root, "add", "plugin.json", "README.md")
            git(self.root, "commit", "-qm", "fixture update")
            new_pin = dict(
                self.pin,
                rev=git(self.root, "rev-parse", "HEAD"),
                tree=git(self.root, "rev-parse", "HEAD^{tree}"),
                version="0.2.2",
            )
            new_checkout = checkout_root / new_pin["rev"]
            shutil.copytree(self.root, new_checkout)
            new_source = sync_skills_plugin.ensure_marketplace_source(
                new_checkout, new_pin, marketplace_root
            )
            (home / "mock-fail-install-source").write_text(str(new_source))

            with self.assertRaisesRegex(
                sync_skills_plugin.PluginCliError, "Antigravity plugin install"
            ):
                sync_skills_plugin.sync_all(
                    codex_homes,
                    pin=new_pin,
                    checkout=new_checkout,
                    source_root=new_source,
                    receipt_file=receipt_file,
                )

            failed = json.loads(receipt_file.read_text())
            self.assertEqual(failed["status"], "failed")
            self.assertEqual(failed["previous_verified"], previous)
            self.assertTrue(failed["rollback"]["all_usable"])
            self.assertEqual(failed["rollback"]["previous_version"], "0.2.1")
            self.assertEqual(
                set(failed["rollback"]["runtimes"]),
                {
                    "claude",
                    "agy",
                    *(f"codex:{codex_home.resolve()}" for codex_home in codex_homes),
                },
            )
            self.assertTrue(
                all(item["usable"] for item in failed["rollback"]["runtimes"].values())
            )

            claude_inventory = json.loads(
                subprocess.check_output(
                    ["claude", "plugin", "list", "--json"],
                    env=os.environ.copy(),
                )
            )
            self.assertEqual(
                [
                    entry["version"]
                    for entry in claude_inventory
                    if entry.get("id") == "treflebonbon-skills@treflebonbon"
                ],
                ["0.2.1"],
            )
            for codex_home in codex_homes:
                env = os.environ.copy()
                env["CODEX_HOME"] = str(codex_home)
                codex_inventory = json.loads(
                    subprocess.check_output(
                        ["codex", "plugin", "list", "--json"], env=env
                    )
                )
                self.assertEqual(
                    [
                        entry["version"]
                        for entry in codex_inventory["installed"]
                        if entry.get("pluginId") == "treflebonbon-skills@treflebonbon"
                    ],
                    ["0.2.1"],
                )
            agy_inventory = json.loads(
                subprocess.check_output(
                    ["agy", "plugin", "list", "--json"], env=os.environ.copy()
                )
            )
            self.assertEqual(
                [
                    entry["version"]
                    for entry in agy_inventory
                    if entry.get("name") == "treflebonbon-skills"
                ],
                ["0.2.1"],
            )

    def test_failed_retry_replaces_old_success_receipt_and_retains_legacy_skill(
        self,
    ) -> None:
        receipt_file = Path(self.temporary.name) / "state/receipt.json"
        receipt_file.parent.mkdir(parents=True)
        receipt_file.write_text('{"status":"verified","rev":"previous"}\n')
        legacy = Path(self.temporary.name) / "legacy/SKILL.md"
        legacy.parent.mkdir()
        legacy.write_text("legacy\n")
        with patch.object(
            sync_skills_plugin,
            "sync_claude",
            side_effect=sync_skills_plugin.PluginSyncError(
                "Claude Code plugin install failed"
            ),
        ):
            with self.assertRaisesRegex(
                sync_skills_plugin.PluginSyncError, "Claude Code plugin install"
            ):
                sync_skills_plugin.sync_all(
                    [Path(self.temporary.name) / "codex"],
                    pin=self.pin,
                    checkout=self.root,
                    source_root=self.source,
                    receipt_file=receipt_file,
                )
        receipt = json.loads(receipt_file.read_text())
        self.assertEqual(receipt["status"], "failed")
        self.assertNotEqual(receipt.get("rev"), "previous")
        self.assertEqual(receipt["failure"]["type"], "PluginSyncError")
        self.assertEqual(legacy.read_text(), "legacy\n")


if __name__ == "__main__":
    unittest.main()
