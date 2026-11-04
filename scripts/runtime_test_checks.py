"""変更対象に必要な実ランタイムを確認し、既存の回帰テストを実行する。"""

import argparse
import os
from pathlib import Path
import re
import subprocess
import sys


BASH_TESTS = (
    "Herdr event copies .env without inherited Git variables",
    "codex repo state works without inherited Git variables",
)
TREESITTER_TESTS = (
    "Treesitter の設定を読み込み、標準 API で選択を拡大・縮小できる",
    "固定版 Treesitter の実 API でも設定と選択が動く",
)
BASH_PATHS = {
    ".herdr/herdr-plugin.toml",
    "private_dot_local/bin/executable_codex-repo-state",
    "tests/herdr-copy-env.bats",
    "tests/codex-repo-state.bats",
    "scripts/runtime_test_checks.py",
}
TREESITTER_PATHS = {
    "private_dot_config/nvim/lua/plugins/lsp.lua",
    "tests/nvim-treesitter.bats",
    "tests/helpers/nvim-treesitter.lua",
    "scripts/runtime_test_checks.py",
}


def required_tests(source, environment):
    def git(*arguments):
        return subprocess.check_output(
            ["git", *arguments], cwd=source, env=environment, stderr=subprocess.PIPE
        )

    base = git("merge-base", "origin/main", "HEAD").decode().strip()
    changed = {
        os.fsdecode(path)
        for path in git("diff", "--no-renames", "--name-only", "-z", base, "HEAD").split(b"\0")
        if path
    }
    return (
        *(BASH_TESTS if changed & BASH_PATHS else ()),
        *(TREESITTER_TESTS if changed & TREESITTER_PATHS else ()),
    )


def runtime_paths(required, environment):
    paths = {}
    if any(name in required for name in BASH_TESTS):
        value = environment.get("TEST_COMPAT_BASH", "")
        bash = Path(value)
        if (
            not bash.is_absolute()
            or not bash.is_file()
            or not os.access(bash, os.X_OK)
        ):
            raise ValueError("TEST_COMPAT_BASH に検証用 Bash 3.2 の絶対パスが必要です")
        version = subprocess.check_output(
            [
                str(bash),
                "--noprofile",
                "--norc",
                "-c",
                'printf "%s.%s" "${BASH_VERSINFO[0]}" "${BASH_VERSINFO[1]}"',
            ],
            env=environment | {"BASH_ENV": "/dev/null"},
            text=True,
        )
        if version != "3.2":
            raise ValueError("TEST_COMPAT_BASH は Bash 3.2 を実行する必要があります")
        paths["compat_bash"] = str(bash)
    if any(name in required for name in TREESITTER_TESTS):
        value = environment.get("NVIM_TREESITTER_RUNTIME", "")
        plugin = Path(value)
        module = plugin / "lua/nvim-treesitter/init.lua"
        if not plugin.is_absolute() or not module.is_file():
            raise ValueError("NVIM_TREESITTER_RUNTIME に固定版 plugin の checkout が必要です")
        paths["treesitter_module"] = str(module)
    return paths


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--validate-only", action="store_true")
    arguments = parser.parse_args()
    environment = {
        key: value for key, value in os.environ.items() if not key.startswith("GIT_")
    }
    source = Path.cwd()
    try:
        required = required_tests(source, environment)
        runtime_paths(required, environment)
        if required and not arguments.validate_only:
            files = []
            if any(name in required for name in BASH_TESTS):
                files.extend(("tests/herdr-copy-env.bats", "tests/codex-repo-state.bats"))
            if any(name in required for name in TREESITTER_TESTS):
                files.append("tests/nvim-treesitter.bats")
            pattern = "^(" + "|".join(map(re.escape, required)) + ")$"
            result = subprocess.run(
                ["bats", "--tap", "--filter", pattern, *files],
                cwd=source,
                env=environment,
                stdout=subprocess.PIPE,
                text=True,
            )
            print(result.stdout, end="")
            result.check_returncode()
            for name in required:
                matches = re.findall(
                    r"^ok [0-9]+ " + re.escape(name) + r"$",
                    result.stdout,
                    re.MULTILINE,
                )
                if len(matches) != 1:
                    raise ValueError(f"必須fixtureが欠落・重複・失敗・skipしています: {name}")
    except (OSError, ValueError, subprocess.CalledProcessError) as error:
        print(f"実ランタイムの検証に失敗しました: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
