"""Synthetic peers for the real Nix/Codex/Git/gh binaries, inside bubblewrap only."""

from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import json
import os
from pathlib import Path
import subprocess
import socket
import sys
import threading
import time


def assert_host_isolation():
    host = Path(os.environ["HOST_FIXTURE"])
    for path in (host / ".env", host / "other-secret", host / "alias", host / "hardlink", host / "late-secret", Path("/work/.env")):
        try:
            path.read_bytes()
        except OSError:
            pass
        else:
            raise AssertionError(f"host file accessible: {path.name}")
    assert "PROBE_PARENT_SECRET" not in os.environ
    assert not Path("/nix/var/nix/daemon-socket/socket").exists()
    assert os.environ["HOME"] == "/home/agent"
    for name, host_namespace in json.loads(os.environ["HOST_NAMESPACES"]).items():
        assert os.readlink(f"/proc/self/ns/{name}") != host_namespace
    for family, address in ((socket.AF_UNIX, str(host / "provider.sock")), (socket.AF_INET, ("127.0.0.1", int(os.environ["HOST_TCP_PORT"])))):
        with socket.socket(family) as client:
            client.settimeout(1)
            try:
                client.connect(address)
            except OSError:
                pass
            else:
                raise AssertionError("host secret provider accessible")
    assert Path("/work/admitted.txt").read_text() == "public-fixture-input\n"


def shell_task():
    assert_host_isolation()
    assert os.environ["PROBE_HOOK"] == "ready"
    subprocess.run([sys.executable, "/fixture/runtime.py", "assert-boundary"], check=True)
    escape = Path("/work/link-to-host")
    escape.symlink_to(Path(os.environ["HOST_FIXTURE"]) / ".env")
    try:
        escape.read_bytes()
    except OSError:
        pass
    else:
        raise AssertionError("symlink escaped the private workspace")
    try:
        os.link(Path(os.environ["HOST_FIXTURE"]) / ".env", "/work/hardlink-to-host")
    except OSError:
        pass
    else:
        raise AssertionError("hardlink escaped the private workspace")
    Path("calculator.py").write_text("def add(a, b):\n    return a + b\n")
    subprocess.run([sys.executable, "-m", "py_compile", "calculator.py"], check=True)
    subprocess.run([sys.executable, "-c", "from calculator import add; assert add(2, 3) == 5"], check=True)
    subprocess.run(["git", "add", "calculator.py"], check=True)
    subprocess.run(["git", "-c", "user.name=Fixture", "-c", "user.email=fixture@example.invalid", "commit", "-qm", "test: fixture calculation"], check=True)
    metadata = subprocess.check_output(["git", "rev-parse", "--git-dir", "--git-common-dir"], text=True)
    assert metadata.splitlines() == ["/repo/.git/worktrees/work", "/repo/.git"]
    github = subprocess.check_output(
        ["gh", "api", os.environ["FIXTURE_API"] + "/repos/fixture/example", "--jq", ".full_name"],
        env={**os.environ, "GH_TOKEN": "synthetic-tool-auth", "GH_PROMPT_DISABLED": "1"}, text=True,
    )
    assert github.strip() == "fixture/example"
    print("SHELL_GIT_GH_OK", flush=True)


def mcp():
    for line in sys.stdin:
        message = json.loads(line)
        if "id" not in message:
            continue
        method = message["method"]
        if method == "initialize":
            result = {"protocolVersion": "2024-11-05", "capabilities": {"tools": {}}, "serverInfo": {"name": "boundary-fixture", "version": "1"}}
        elif method == "tools/list":
            result = {"tools": [{"name": "probe", "description": "Assert the synthetic secret boundary", "inputSchema": {"type": "object", "properties": {}, "additionalProperties": False}}]}
        elif method == "tools/call":
            assert_host_isolation()
            Path("/evidence/mcp-ok").write_text("MCP_OK\n")
            result = {"content": [{"type": "text", "text": "MCP_OK"}]}
        else:
            result = {}
        print(json.dumps({"jsonrpc": "2.0", "id": message["id"], "result": result}), flush=True)


def tool_name(tools, wanted, namespace=None):
    for tool in tools:
        if tool.get("type") == "namespace":
            found = tool_name(tool["tools"], wanted, tool["name"])
            if found:
                return found
        elif tool.get("name") == wanted:
            return {"name": wanted, **({"namespace": namespace} if namespace else {})}
    return None


class Provider(BaseHTTPRequestHandler):
    requests = []
    errors = []
    github_calls = 0

    def log_message(self, *args):
        pass

    def do_GET(self):
        if self.path == "/repos/fixture/example":
            type(self).github_calls += 1
            data = json.dumps({"full_name": "fixture/example"}).encode()
            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(data)))
            self.end_headers()
            self.wfile.write(data)
        else:
            self.send_error(404)

    def do_POST(self):
        try:
            payload = json.loads(self.rfile.read(int(self.headers["Content-Length"])))
            index = len(self.requests)
            self.requests.append(payload)
            if index == 0:
                tool = tool_name(payload["tools"], "exec_command")
                assert tool, "real Codex did not advertise exec_command"
                item = {"type": "function_call", "call_id": "shell-call", **tool,
                        "arguments": json.dumps({"cmd": f"{sys.executable} /fixture/runtime.py shell", "workdir": "/work", "yield_time_ms": 10000})}
            elif index == 1:
                assert "SHELL_GIT_GH_OK" in json.dumps(payload["input"]), "Codex command did not succeed"
                tool = tool_name(payload["tools"], "probe") or tool_name(payload["tools"], "mcp__fixture__probe")
                assert tool, "real Codex did not advertise fixture MCP tool"
                item = {"type": "function_call", "call_id": "mcp-call", **tool, "arguments": "{}"}
            elif index == 2:
                assert "MCP_OK" in json.dumps(payload["input"]), "Codex MCP call did not succeed"
                item = {"type": "message", "role": "assistant", "id": "final", "content": [{"type": "output_text", "text": "FIXTURE_COMPLETE"}]}
            else:
                raise AssertionError("unexpected extra inference request")
            events = [
                {"type": "response.created", "response": {"id": f"fixture-{index}"}},
                {"type": "response.output_item.done", "output_index": 0, "item": item},
                {"type": "response.completed", "response": {"id": f"fixture-{index}", "output": [], "usage": {"input_tokens": 0, "output_tokens": 0, "total_tokens": 0}}},
            ]
            data = "".join(f"event: {event['type']}\ndata: {json.dumps(event)}\n\n" for event in events).encode()
            self.send_response(200)
            self.send_header("Content-Type", "text/event-stream")
            self.send_header("Content-Length", str(len(data)))
            self.end_headers()
            self.wfile.write(data)
        except Exception as error:
            self.errors.append(str(error))
            self.send_error(500, "fixture assertion failed")


def main():
    assert_host_isolation()
    Path("/evidence/mutate.ready").touch()
    deadline = time.monotonic() + 10
    while not Path("/evidence/mutate.done").exists():
        assert time.monotonic() < deadline, "host mutation handshake timed out"
        time.sleep(0.01)
    assert_host_isolation()
    server = ThreadingHTTPServer(("127.0.0.1", 0), Provider)
    assert server.server_port != int(os.environ["HOST_TCP_PORT"]), "fixture port collision; rerun"
    threading.Thread(target=server.serve_forever, daemon=True).start()
    endpoint = f"http://127.0.0.1:{server.server_port}"
    os.environ["FIXTURE_API"] = endpoint
    home = Path(os.environ["CODEX_HOME"])
    home.mkdir()
    (home / "config.toml").write_text(f'''
model_provider = "fixture"
model = "fixture-model"
approval_policy = "never"
default_permissions = "fixture"
[features]
shell_snapshot = false
[permissions.fixture]
extends = ":workspace"
[permissions.fixture.filesystem]
"/repo/.git" = "write"
"/evidence" = "write"
[permissions.fixture.network]
enabled = true
[model_providers.fixture]
name = "Synthetic Responses API"
base_url = "{endpoint}/v1"
wire_api = "responses"
requires_openai_auth = false
request_max_retries = 0
stream_max_retries = 0
[mcp_servers.fixture]
command = "{sys.executable}"
args = ["/fixture/runtime.py", "mcp"]
cwd = "/work"
env_vars = ["HOST_FIXTURE", "HOST_TCP_PORT", "HOST_NAMESPACES"]
enabled_tools = ["probe"]
[mcp_servers.fixture.tools.probe]
approval_mode = "approve"
''')
    Path("/evidence/codex-started").touch()
    with subprocess.Popen(["codex", "exec", "--strict-config", "--ephemeral", "--json", "Run the synthetic fixture command and MCP probe."], text=True, stdin=subprocess.DEVNULL, stdout=subprocess.PIPE, stderr=subprocess.PIPE) as process:
        for name in ("mnt", "pid", "net", "user"):
            assert os.readlink(f"/proc/{process.pid}/ns/{name}") == os.readlink(f"/proc/self/ns/{name}")
        assert b"PROBE_PARENT_SECRET=" not in Path(f"/proc/{process.pid}/environ").read_bytes()
        try:
            stdout, stderr = process.communicate(timeout=90)
        except subprocess.TimeoutExpired:
            process.kill()
            process.communicate()
            raise
    Path("/evidence/codex.jsonl").write_text(stdout)
    Path("/evidence/codex.stderr").write_text(stderr)
    Path("/evidence/provider.json").write_text(json.dumps(Provider.requests, indent=2))
    assert not Provider.errors, Provider.errors
    assert process.returncode == 0, stderr
    assert "FIXTURE_COMPLETE" in stdout, stdout
    assert Path("/evidence/mcp-ok").read_text() == "MCP_OK\n"
    assert Provider.github_calls == 1
    print("PASS codex-shell-git\nPASS codex-mcp\nPASS codex-github-fixture", flush=True)
    server.shutdown()


if __name__ == "__main__":
    {"run": main, "shell": shell_task, "mcp": mcp, "assert-boundary": assert_host_isolation}[sys.argv[1]]()
