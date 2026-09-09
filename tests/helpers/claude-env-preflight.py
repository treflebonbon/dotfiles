"""Opt-in real Claude lifecycle; a loopback model stub supplies tool calls.

Run: python3 tests/helpers/claude-env-preflight.py [--real-nix]
No real credentials, API calls or user configuration are used. Evidence is left in /tmp.
"""

import argparse
import http.server
import json
import os
import shlex
import shutil
import subprocess
import threading
import tempfile
from pathlib import Path

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--real-nix", action="store_true")
parser.add_argument("--shell", choices=("bash", "zsh"), default="bash")
args = parser.parse_args()
source = Path(__file__).resolve().parents[2]
p = Path(tempfile.mkdtemp(prefix="claude-env-preflight-", dir="/tmp"))
project = p / "project"
home = p / "home"
bin_dir = home / ".local/bin"
bin_dir.mkdir(parents=True)
(bin_dir / "devshell-env").symlink_to(
    source / "private_dot_local/bin/executable_devshell-env"
)
state = p / "claude-state"
state.mkdir()
print(f"Evidence: {p}", flush=True)
env = {k: v for k, v in os.environ.items() if k in ("PATH", "SSL_CERT_FILE", "LANG")}
env.update(
    HOME=str(home),
    PATH=str(bin_dir) + os.pathsep + env["PATH"],
    CLAUDE_CONFIG_DIR=str(state / "config"),
    XDG_STATE_HOME=str(home / "state"),
    CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC="1",
    TMPDIR="/tmp",
    DUMMY_SECRET_256="sentinel-inherited-256",
    PROJECT_NAME="baseline",
    CLAUDE_CODE_SHELL=shutil.which(args.shell),
)


def run(command, cwd=None):
    return subprocess.run(
        command, cwd=cwd, env=env, capture_output=True, text=True, check=True
    ).stdout.strip()


if args.real_nix:
    nixpkgs = run(
        [
            "nix",
            "eval",
            "--offline",
            "--impure",
            "--raw",
            "--expr",
            f"(builtins.getFlake (toString {source})).inputs.nixpkgs.outPath",
        ]
    )
    system = run(
        ["nix", "eval", "--impure", "--raw", "--expr", "builtins.currentSystem"]
    )
else:
    (bin_dir / "nix").write_text('#!/bin/bash\ncat "$PWD/environment.sh"\n')
    (bin_dir / "nix").chmod(0o755)

for name in ("project", "second", "untrusted", "no-flake", "failure"):
    repo = p / name
    run(["git", "init", "-q", str(repo)])
    script = (
        f"export PROJECT_NAME={name}\n"
        'export DERIVED_SECRET="prefix-${DUMMY_SECRET_256-unset}"\n'
        f"printf 'init\\n' >> {shlex.quote(str(p / 'initializations'))}\n"
    )
    if name == "project":
        script += "export FIRST_ONLY=yes\n"
    if name == "failure":
        script += "exit 17\n"
    if args.real_nix:
        flake = f'''{{
  inputs.nixpkgs.url = "path:{nixpkgs}";
  outputs = {{ nixpkgs, ... }}: {{
    devShells.{system}.default = let pkgs = import nixpkgs {{ system = "{system}"; }}; in pkgs.mkShell {{
      packages = [ pkgs.hello ];
      shellHook = builtins.readFile ./environment.sh;
    }};
  }};
}}\n'''
    else:
        flake = "fixture\n"
    if name != "no-flake":
        (repo / "flake.nix").write_text(flake)
    (repo / "environment.sh").write_text(script)
    (repo / "observe.py").write_text(
        "import os,sys,subprocess\nfrom pathlib import Path\n"
        "label, expected, first, count = sys.argv[1:]\n"
        "assert os.environ.get('PROJECT_NAME') == expected, dict((k, os.environ.get(k)) for k in ('PROJECT_NAME','FIRST_ONLY','OTHER_HOOK'))\n"
        "assert os.environ.get('FIRST_ONLY', 'unset') == first\n"
        "assert os.environ.get('OTHER_HOOK') == 'kept'\n"
        "assert 'CLAUDE_ENV_FILE' not in os.environ\n"
        "assert os.environ['DUMMY_SECRET_256'] == 'sentinel-inherited-256'\n"
        f"assert len(Path({str(p / 'initializations')!r}).read_text().splitlines()) == int(count)\n"
        + (
            "if expected != 'baseline': subprocess.run(['hello'], stdout=subprocess.DEVNULL, check=True)\n"
            if args.real_nix
            else ""
        )
        + "print('PASS ' + label)\n"
    )
    run(["git", "add", "."], repo)
    run(
        [
            "git",
            "-c",
            "user.name=Test",
            "-c",
            "user.email=test@example.com",
            "commit",
            "-qm",
            "test: fixture",
        ],
        repo,
    )
    (repo / ".env").write_text("DUMMY_DOTENV=sentinel-dotenv-256\n")
    (repo / ".envrc").write_text("touch envrc-was-read\n")
    if name != "untrusted":
        run(["devshell-env", "trust", str(repo)])
(project / "subdirectory").mkdir()


def observe(label, expected, first, count):
    path = "../observe.py" if label == "same-root" else "./observe.py"
    return f"python3 {path} {label} {expected} {first} {count}"


calls = [
    ("Bash", {"command": observe("startup", "project", "yes", 1)}),
    ("Bash", {"command": "cd subdirectory"}),
    ("Bash", {"command": observe("same-root", "project", "yes", 1)}),
    ("EnterWorktree", {"name": "fixture"}),
    ("Bash", {"command": observe("enter-worktree", "project", "yes", 2)}),
    ("ExitWorktree", {"action": "keep"}),
    ("Bash", {"command": f"cd {shlex.quote(str(p / 'second'))}"}),
    ("Bash", {"command": observe("second-repo", "second", "unset", 4)}),
    (
        "Bash",
        {
            "command": "printf 'export PROJECT_NAME=reloaded\\n' >> environment.sh; devshell-env reload"
        },
    ),
    ("Bash", {"command": observe("reload", "reloaded", "unset", 5)}),
    ("Bash", {"command": f"cd {shlex.quote(str(p / 'untrusted'))}"}),
    ("Bash", {"command": observe("untrusted", "baseline", "unset", 5)}),
    ("Bash", {"command": f"cd {shlex.quote(str(p / 'no-flake'))}"}),
    ("Bash", {"command": observe("no-flake", "baseline", "unset", 5)}),
    ("Bash", {"command": f"cd {shlex.quote(str(p / 'failure'))}"}),
    ("Bash", {"command": observe("failure", "baseline", "unset", 6)}),
]


class Server(http.server.BaseHTTPRequestHandler):
    def log_message(self, *args):
        pass

    def do_POST(self):
        data = json.loads(self.rfile.read(int(self.headers.get("Content-Length", 0))))
        if "count_tokens" in self.path:
            body = json.dumps({"input_tokens": 100}).encode()
            self.send_response(200)
            self.end_headers()
            self.wfile.write(body)
            return
        (state / "requests.jsonl").open("a").write(json.dumps(data) + "\n")
        count = sum(
            1
            for m in data.get("messages", [])
            if m["role"] == "assistant"
            and isinstance(m.get("content"), list)
            and any(b.get("type") == "tool_use" for b in m["content"])
        )
        block = (
            {
                "type": "tool_use",
                "id": f"toolu_{count}",
                "name": calls[count][0],
                "input": calls[count][1],
            }
            if count < len(calls)
            else {"type": "text", "text": "fixture complete"}
        )
        msg = {
            "id": f"msg_{count}",
            "type": "message",
            "role": "assistant",
            "model": "claude-sonnet-4-6",
            "content": [block],
            "stop_reason": "tool_use" if count < len(calls) else "end_turn",
            "stop_sequence": None,
            "usage": {"input_tokens": 100, "output_tokens": 20},
        }
        self.send_response(200)
        if not data.get("stream"):
            self.send_header("Content-Type", "application/json")
            self.end_headers()
            self.wfile.write(json.dumps(msg).encode())
            return
        self.send_header("Content-Type", "text/event-stream")
        self.end_headers()
        start = msg | {"content": [], "stop_reason": None}
        events = [
            ("message_start", {"type": "message_start", "message": start}),
            (
                "content_block_start",
                {
                    "type": "content_block_start",
                    "index": 0,
                    "content_block": block
                    | ({"input": {}} if block["type"] == "tool_use" else {"text": ""}),
                },
            ),
            (
                "content_block_delta",
                {
                    "type": "content_block_delta",
                    "index": 0,
                    "delta": {
                        "type": "input_json_delta",
                        "partial_json": json.dumps(block["input"]),
                    }
                    if block["type"] == "tool_use"
                    else {"type": "text_delta", "text": block["text"]},
                },
            ),
            ("content_block_stop", {"type": "content_block_stop", "index": 0}),
            (
                "message_delta",
                {
                    "type": "message_delta",
                    "delta": {"stop_reason": msg["stop_reason"], "stop_sequence": None},
                    "usage": {"output_tokens": 20},
                },
            ),
            ("message_stop", {"type": "message_stop"}),
        ]
        for event, value in events:
            self.wfile.write(f"event: {event}\ndata: {json.dumps(value)}\n\n".encode())
            self.wfile.flush()


server = http.server.ThreadingHTTPServer(("127.0.0.1", 0), Server)
threading.Thread(target=server.serve_forever, daemon=True).start()
managed = json.loads((source / "private_dot_claude/settings.json.tmpl").read_text())
audit = state / "audit.py"
audit.write_text(
    "import json,subprocess,sys\n"
    "from pathlib import Path\n"
    "payload = sys.stdin.read()\n"
    f"with Path({str(state / 'events.jsonl')!r}).open('a') as output: output.write(payload + '\\n')\n"
    f"sys.exit(subprocess.run({[str(bin_dir / 'devshell-env'), 'claude-hook']!r}, input=payload, text=True).returncode)\n"
)
settings = {
    "hooks": {
        event: managed["hooks"][event][:1]
        for event in ("SessionStart", "CwdChanged", "PreToolUse")
    }
}
for groups in settings["hooks"].values():
    groups[0]["hooks"][0]["command"] = f"python3 {shlex.quote(str(audit))}"
settings["hooks"]["SessionStart"].append(
    {
        "hooks": [
            {
                "type": "command",
                "command": "printf 'export OTHER_HOOK=kept\\n' >> \"$CLAUDE_ENV_FILE\"",
            }
        ]
    }
)
(state / "settings.json").write_text(json.dumps(settings))
env.update(
    ANTHROPIC_BASE_URL=f"http://127.0.0.1:{server.server_port}",
    ANTHROPIC_API_KEY="fixture-dummy-key",
)
try:
    r = subprocess.run(
        [
            "claude",
            "-p",
            "Run the fixture, including EnterWorktree and the directory switches.",
            "--model",
            "claude-sonnet-4-6",
            "--setting-sources",
            "",
            "--add-dir",
            str(p),
            "--settings",
            str(state / "settings.json"),
            "--tools",
            "Bash,EnterWorktree,ExitWorktree",
            "--allowedTools",
            "Bash,EnterWorktree,ExitWorktree",
            "--output-format",
            "stream-json",
            "--verbose",
            "--no-session-persistence",
        ],
        cwd=project,
        env=env,
        capture_output=True,
        text=True,
        timeout=180,
    )
    (state / "output.jsonl").write_text(r.stdout)
    (state / "stderr").write_text(r.stderr)
    print("Claude status:", r.returncode)
    observed = []
    for line in r.stdout.splitlines():
        try:
            item = json.loads(line)
            if item.get("type") == "user" and "tool_use_result" in item:
                observed.append(item["tool_use_result"])
        except ValueError:
            pass
    print(json.dumps(observed, indent=2))
    assert r.returncode == 0, r.stderr[-1200:]
    for label in (
        "startup",
        "same-root",
        "enter-worktree",
        "second-repo",
        "reload",
        "untrusted",
        "no-flake",
        "failure",
    ):
        assert any(
            isinstance(item, dict) and item.get("stdout", "") == f"PASS {label}"
            for item in observed
        ), label
    for directory in (
        state / "config/session-env",
        state / "config/projects/.devshell-env",
        home / ".cache",
    ):
        for path in directory.rglob("*"):
            if path.is_file():
                assert b"sentinel-inherited-256" not in path.read_bytes(), path
                assert b"sentinel-dotenv-256" not in path.read_bytes(), path
    assert not list(p.rglob("envrc-was-read"))
    print(
        "PASS: real Claude lifecycle and environment files; Nix="
        + ("real" if args.real_nix else "fixture")
    )
except subprocess.TimeoutExpired as error:
    raise RuntimeError("Claude lifecycle timed out") from error
finally:
    server.shutdown()
