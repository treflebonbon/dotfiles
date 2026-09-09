"""Opt-in real Claude hook/Bash fixture; a loopback model stub supplies commands.

Run: python3 tests/helpers/claude-env-preflight.py
No real credentials, API calls or user configuration are used. Evidence is left in /tmp.
"""

import http.server
import json
import os
import subprocess
import threading
import tempfile
from pathlib import Path

p = Path(tempfile.mkdtemp(prefix="claude-env-preflight-", dir="/tmp"))
project = p / "project"
project.mkdir()
(p / "home").mkdir()
state = p / "claude-state"
state.mkdir()
print(f"Evidence: {p}")
(state / "env.sh").write_text("export HOOK_255=initial\n")
(project / "reload-fixture").write_text(
    '#!/bin/bash\nprintf "export HOOK_255=reloaded\\n" > '
    + str(state / "env.sh")
    + "\n"
)
(project / "reload-fixture").chmod(0o755)
commands = [
    'printf "observed=%s envfile=%s\\n" "$HOOK_255" "${CLAUDE_ENV_FILE-unset}"',
    "./reload-fixture",
    'printf "observed=%s\\n" "$HOOK_255"',
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
                "name": "Bash",
                "input": {"command": commands[count]},
            }
            if count < len(commands)
            else {"type": "text", "text": "fixture complete"}
        )
        msg = {
            "id": f"msg_{count}",
            "type": "message",
            "role": "assistant",
            "model": "claude-sonnet-4-6",
            "content": [block],
            "stop_reason": "tool_use" if count < len(commands) else "end_turn",
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
hook = state / "hook.sh"
hook.write_text(
    "#!/bin/bash\nprintf 'source \"%s\"\\n' "
    + str(state / "env.sh")
    + ' >> "$CLAUDE_ENV_FILE"\nprintf "%s\\n" "$CLAUDE_ENV_FILE" > '
    + str(state / "env-path")
    + "\n"
)
hook.chmod(0o755)
settings = {
    "hooks": {"SessionStart": [{"hooks": [{"type": "command", "command": str(hook)}]}]}
}
(state / "settings.json").write_text(json.dumps(settings))
env = {k: v for k, v in os.environ.items() if k in ("PATH", "SSL_CERT_FILE", "LANG")}
env.update(
    HOME=str(p / "home"),
    CLAUDE_CONFIG_DIR=str(state / "config"),
    ANTHROPIC_BASE_URL=f"http://127.0.0.1:{server.server_port}",
    ANTHROPIC_API_KEY="fixture-dummy-key",
    CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC="1",
    TMPDIR="/tmp",
)
try:
    r = subprocess.run(
        [
            "claude",
            "-p",
            "Run fixture commands.",
            "--model",
            "claude-sonnet-4-6",
            "--setting-sources",
            "",
            "--settings",
            str(state / "settings.json"),
            "--tools",
            "Bash",
            "--allowedTools",
            "Bash",
            "--output-format",
            "stream-json",
            "--verbose",
            "--no-session-persistence",
        ],
        cwd=project,
        env=env,
        capture_output=True,
        text=True,
        timeout=50,
    )
    (state / "output.jsonl").write_text(r.stdout)
    (state / "stderr").write_text(r.stderr)
    print("Claude status:", r.returncode)
    observed = []
    for line in r.stdout.splitlines():
        try:
            item = json.loads(line)
            if item.get("type") == "user" and "tool_use_result" in item:
                observed.append(item["tool_use_result"]["stdout"])
        except ValueError:
            pass
    print(observed)
    assert r.returncode == 0 and observed == [
        "observed=initial envfile=unset",
        "",
        "observed=reloaded",
    ], r.stderr[-1200:]
    print("PASS: SessionStart -> Bash -> explicit reload -> subsequent Bash")
except subprocess.TimeoutExpired as error:
    raise RuntimeError("Claude lifecycle timed out") from error
finally:
    server.shutdown()
