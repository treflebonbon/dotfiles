"""固定 plugin を実 Claude CLI で導入し、管理設定の反復同期を確認する。"""

import argparse
import hashlib
import importlib.util
from importlib.machinery import SourceFileLoader
import json
import os
from pathlib import Path
import subprocess
import sys

sys.dont_write_bytecode = True

from verification_env import create_environment, new_runtime, sandbox_prefix


WORKER = """
import importlib.util, sys
from pathlib import Path
sys.path.insert(0, str(Path(sys.argv[1]).parent))
spec = importlib.util.spec_from_file_location('native_check', sys.argv[1])
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)
raise SystemExit(module.probe(*map(Path, sys.argv[2:])))
"""


def probe(source: Path, checkout: Path, record: Path) -> int:
    result = {"status": "failed", "repeated_syncs": []}
    try:
        loader = SourceFileLoader(
            "sync_skills_plugin",
            str(source / "private_dot_local/bin/executable_sync-skills-plugin"),
        )
        spec = importlib.util.spec_from_loader(loader.name, loader)
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        pin = module.load_pin(
            source / "private_dot_config/nix-devshell/skills-plugin.json"
        )
        module.verify_checkout(checkout, pin)
        cached = module.cache_root() / pin["rev"]
        cached.parent.mkdir(parents=True)
        module.git(
            cached.parent,
            "clone",
            "--no-hardlinks",
            "--no-checkout",
            "--",
            str(checkout),
            str(cached),
        )
        module.git(cached, "checkout", "--detach", pin["rev"])
        module.verify_checkout(cached, pin)
        snapshot = module.ensure_marketplace_source(cached, pin)
        config = Path(os.environ["HOME"]) / ".claude"
        config.mkdir(mode=0o700)
        os.environ["CLAUDE_CONFIG_DIR"] = str(config)
        os.environ["CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC"] = "1"
        installed = module.sync_claude(cached, snapshot, pin)
        receipt = {
            "schema_version": 1,
            "status": "verified",
            "pin": pin,
            "checkout": str(cached),
            "source": str(snapshot),
            "results": {"claude": installed},
        }
        template_config = record / "chezmoi.yaml"
        template_config.write_text("{}\n")
        rendered = subprocess.check_output(
            [
                "chezmoi",
                "--source",
                str(source),
                "--destination",
                os.environ["HOME"],
                "--config",
                str(template_config),
                "execute-template",
            ],
            input=(source / "private_dot_claude/settings.json.tmpl").read_bytes(),
        )
        settings = config / "settings.json"
        settings.write_bytes(rendered)
        expected = module.tracked_tree(cached)
        for iteration in (1, 2):
            installed = module.sync_claude(
                cached, snapshot, pin, previous_verified=receipt
            )
            verified = module.verify_claude_installation(
                cached, snapshot, pin, expected
            )
            preserved = settings.read_bytes() == rendered
            result["repeated_syncs"].append(
                {
                    "iteration": iteration,
                    "settings_bytes_preserved": preserved,
                    "version": verified["version"],
                    "files": verified["files"],
                }
            )
            if not preserved:
                raise ValueError("再同期で管理 settings.json の bytes が変化しました")
            receipt["results"]["claude"] = installed
        result.update(
            status="passed",
            pin=pin,
            cli_path=installed["cli_path"],
            cli_version=installed["cli_version"],
            settings_bytes=len(rendered),
            settings_sha256=hashlib.sha256(rendered).hexdigest(),
        )
    except Exception as error:
        result["error"] = str(error)
    (record / "result.json").write_text(
        json.dumps(result, ensure_ascii=False, indent=2) + "\n"
    )
    return 0 if result["status"] == "passed" else 1


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("source", type=Path)
    parser.add_argument(
        "--checkout",
        type=Path,
        required=True,
        help="固定 pin に一致する公開 Git checkout",
    )
    args = parser.parse_args()
    record = new_runtime("claude-plugin-native.")
    print(f"検証ログ: {record}", flush=True)
    try:
        prefix = sandbox_prefix(args.source, record, Path(os.environ["HOME"]))
        environment = create_environment(record)
        command = [
            *prefix,
            sys.executable,
            "-I",
            "-B",
            "-c",
            WORKER,
            str(Path(__file__).resolve()),
            str(args.source.resolve()),
            str(args.checkout.absolute()),
            str(record),
        ]
        with (
            (record / "stdout.log").open("wb") as output,
            (record / "stderr.log").open("wb") as error,
        ):
            status = subprocess.run(
                command, env=environment, stdout=output, stderr=error
            ).returncode
    except (OSError, ValueError, subprocess.CalledProcessError) as error:
        print(f"検証環境の起動を拒否しました: {error}", file=sys.stderr)
        status = 1
    status = status if status >= 0 else 128 - status
    (record / "exit-code").write_text(f"{status}\n")
    if status:
        print(f"REJECT: Claude plugin の実 CLI 検証に失敗（{record}）", file=sys.stderr)
    else:
        print(
            "PASS: Claude plugin の2回の再同期で管理設定と固定 payload を確認しました"
        )
    return status


if __name__ == "__main__":
    raise SystemExit(main())
