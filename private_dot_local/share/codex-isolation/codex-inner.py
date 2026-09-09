"""Prepare the admitted project and start Codex inside the outer namespace."""

import json
import os
from pathlib import Path
import runpy
import sys
import tempfile


RUNTIME = Path("/nix/codex-isolation")
DEVENV = runpy.run_path(str(RUNTIME / "bin/devshell-env"))


def main():
    launch = json.loads((RUNTIME / "launch.json").read_text())
    arguments = sys.argv[1:]
    DEVENV["validate_codex_arguments"](arguments)
    repo = DEVENV["Repository"].discover(launch["root"], linked_only=True)
    if (
        str(repo.git_dir) != launch["git_dir"]
        or str(repo.common_dir) != launch["common_dir"]
    ):
        raise ValueError("isolated Git ownership does not match the selected worktree")
    identity = repo.identity()
    codex = DEVENV["executable"]("codex")
    if not codex:
        raise ValueError("the selected Codex is unavailable")
    environment = DEVENV["prepare_environment"](
        repo,
        dict(os.environ),
        require_trust=False,
        isolated=True,
    )
    if (
        DEVENV["Repository"].discover(repo.root, linked_only=True) != repo
        or repo.identity() != identity
    ):
        raise ValueError("Git metadata changed during initialization")
    # These values and arguments belong to the launcher, not shellHook output.
    environment["CODEX_HOME"] = "/home/agent/.codex"
    environment["TMPDIR"] = tempfile.mkdtemp(prefix="codex-worktree-", dir="/tmp")
    for key in list(environment):
        if key.startswith("LD_"):
            del environment[key]
    for key in (
        "HTTP_PROXY",
        "HTTPS_PROXY",
        "http_proxy",
        "https_proxy",
        "NO_PROXY",
        "no_proxy",
        "NIX_CONFIG",
        "NIX_REMOTE",
        "NIX_SSL_CERT_FILE",
        "SSL_CERT_FILE",
    ):
        if key in os.environ:
            environment[key] = os.environ[key]
    overrides = [
        'default_permissions="dotfiles-secure"',
        'model_provider="isolated"',
        'model_providers.isolated={name="Isolated model",base_url="http://127.0.0.1:8123/v1",wire_api="responses",requires_openai_auth=false,request_max_retries=0,stream_max_retries=0}',
        'web_search="disabled"',
        "features.shell_snapshot=false",
        "features.network_proxy=true",
    ]
    argv = [codex, "-C", str(repo.root)]
    for override in overrides:
        argv.extend(["-c", override])
    (Path("/result") / "codex-started").touch()
    os.chdir(repo.root)
    os.execve(codex, [*argv, *arguments], environment)


if __name__ == "__main__":
    try:
        main()
    except (
        OSError,
        ValueError,
        DEVENV["InvalidContext"],
        DEVENV["PreparationError"],
    ) as error:
        print(f"codex-worktree: {error}; initialization incomplete", file=sys.stderr)
        sys.exit(1)
