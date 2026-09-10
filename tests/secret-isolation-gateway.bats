#!/usr/bin/env bats

@test "gateways serve independent long paths and release their socket resources" {
  [ "$(uname -s)" = Linux ] || skip "long-path raw isolation requires Linux/WSL2"
  run python3 - "$BATS_TEST_DIRNAME/../private_dot_local/share/codex-isolation/secret-isolation-gateway.py" "$BATS_TEST_TMPDIR" <<'PY'
import http.client, os, runpy, socket, stat, subprocess, sys
from pathlib import Path
module = runpy.run_path(sys.argv[1])
parent = Path(sys.argv[2]) / ('long-gateway-parent-' * 8)
parent.mkdir()
before = set(os.listdir('/proc/self/fd'))
servers = []
try:
    for name in ('first', 'second'):
        directory = parent / name
        assert len(os.fsencode(directory / 'service.sock')) > 107
        server = module['start_gateway'](directory, 'dependencies', domains=[])
        servers.append(server)
        assert stat.S_IMODE(directory.stat().st_mode) == 0o700
        assert (directory / 'service.sock').is_socket()
        # A separate client process must be able to use the published address.
        subprocess.run([sys.executable, '-c', '''
import http.client, socket, sys
client = http.client.HTTPConnection('gateway', timeout=3)
client.sock = socket.socket(socket.AF_UNIX)
client.sock.settimeout(3)
client.sock.connect(sys.argv[1])
client.request('GET', '/forbidden')
response = client.getresponse()
assert response.status == 403
assert response.read() == b''
client.close()
''', server.server_address], check=True)
    assert servers[0].server_address != servers[1].server_address
finally:
    for server in servers:
        server.shutdown()
        server.server_close()
        server.server_close()
assert set(os.listdir('/proc/self/fd')) == before
PY
  [ "$status" -eq 0 ] || printf '%s\n' "$output" >&3
  [ "$status" -eq 0 ]
}

@test "gateway setup failure releases socket resources" {
  [ "$(uname -s)" = Linux ] || skip "descriptor accounting requires Linux procfs"
  run python3 - "$BATS_TEST_DIRNAME/../private_dot_local/share/codex-isolation/secret-isolation-gateway.py" "$BATS_TEST_TMPDIR" <<'PY'
import os, runpy, sys
from pathlib import Path
module = runpy.run_path(sys.argv[1])
parent = Path(sys.argv[2]) / ('long-setup-parent-' * 8)
parent.mkdir()
before = set(os.listdir('/proc/self/fd'))
try:
    module['start_gateway'](parent / 'socket', 'model',
                            codex_home=Path(sys.argv[2]) / 'missing-login')
except FileNotFoundError:
    pass
else:
    raise AssertionError('missing login must reject gateway setup')
assert set(os.listdir('/proc/self/fd')) == before
PY
  [ "$status" -eq 0 ] || printf '%s\n' "$output" >&3
  [ "$status" -eq 0 ]
}

@test "the model socket rejects remote state, remote tools, malformed requests and other routes without upstream access" {
  local project_root
  project_root="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  mkdir -p "$BATS_TEST_TMPDIR/home/.codex"
  printf '{"tokens":{"access_token":"dummy-access","account_id":"dummy-account"}}\n' >"$BATS_TEST_TMPDIR/home/.codex/auth.json"
  run env HOME="$BATS_TEST_TMPDIR/home" CODEX_HOME="$BATS_TEST_TMPDIR/home/.codex" \
    python3 - "$project_root/private_dot_local/share/codex-isolation/secret-isolation-gateway.py" "$BATS_TEST_TMPDIR/socket" <<'PY'
import http.client, json, runpy, socket, sys
from pathlib import Path
module = runpy.run_path(sys.argv[1])
called = []
def unavailable_upstream(*args, **kwargs):
    called.append(True)
    raise OSError('the negative test must not contact a real service')
http.client.HTTPSConnection = unavailable_upstream
server = module['start_gateway'](Path(sys.argv[2]), 'model')
class Client(http.client.HTTPConnection):
    def connect(self):
        self.sock = socket.socket(socket.AF_UNIX)
        self.sock.settimeout(3)
        self.sock.connect(server.server_address)
cases = [
    ('POST', '/v1/responses', {'previous_response_id': 'old-private-response'}),
    ('POST', '/v1/responses', {'conversation': 'old-private-conversation'}),
    ('POST', '/v1/responses', {'tools': [{'type': 'file_search', 'vector_store_ids': ['private-store']}]}),
    ('POST', '/v1/responses', {'tools': [{'type': 'namespace', 'tools': [{'type': 'mcp'}]}]}),
    ('POST', '/v1/responses', {'input': [{'type': 'item_reference', 'id': 'private-item'}]}),
    ('POST', '/v1/responses', {'input': [{'type': 'additional_tools', 'tools': [{'type': 'file_search'}]}]}),
    ('POST', '/v1/responses', {'input': [{'type': 'message', 'content': [{'type': 'input_file', 'file_id': 'private-file'}]}]}),
    ('POST', '/v1/responses', []),
    ('POST', '/v1/responses', {'tools': [None]}),
    ('POST', '/v1/responses/../files', {}),
    ('GET', '/v1/responses', {}),
    ('CONNECT', 'chatgpt.com:443', {}),
]
try:
    for method, path, payload in cases:
        client = Client('model', timeout=3)
        try:
            client.request(method, path, json.dumps(payload), {'Content-Type': 'application/json'})
        except BrokenPipeError:
            # A forbidden route may receive its 403 before the body is sent.
            pass
        response = client.getresponse()
        assert response.status == 403, (method, path, payload, response.status)
        assert response.read() == b''
        client.close()
    assert not called, 'a forbidden request reached the authenticated upstream'
finally:
    server.shutdown()
    server.server_close()
PY
  [ "$status" -eq 0 ] || printf '%s\n' "$output" >&3
  [ "$status" -eq 0 ]
}

@test "the resolver admits only allowlisted public addresses and rejects local or unsupported queries" {
  local project_root
  project_root="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  run python3 - "$project_root/private_dot_local/share/codex-isolation/secret-isolation-gateway.py" "$BATS_TEST_TMPDIR/resolver" <<'PY'
import http.client,json,runpy,socket,sys
from pathlib import Path
module=runpy.run_path(sys.argv[1])
lookups=[]
def lookup(host,port,**kwargs):
    lookups.append(host)
    address='127.0.0.1' if host == 'private.github.com' else '8.8.8.8'
    return [(socket.AF_INET,socket.SOCK_STREAM,6,'',(address,port))]
socket.getaddrinfo=lookup
server=module['start_gateway'](Path(sys.argv[2]),'dependencies',domains=['cache.nixos.org','**.github.com'],denied_domains=['blocked.github.com'])
class Client(http.client.HTTPConnection):
    def connect(self):
        self.sock=socket.socket(socket.AF_UNIX)
        self.sock.connect(server.server_address)
try:
    for payload,status in [({'host':'cache.nixos.org','type':1},200),({'host':'cache.nixos.org','type':28},200),
                           ({'host':'private.github.com','type':1},403),({'host':'blocked.github.com','type':1},403),({'host':'127.0.0.1','type':1},403),
                           ({'host':'example.com','type':1},403),({'host':'cache.nixos.org','type':12},403)]:
        client=Client('resolver')
        client.request('POST','/resolve',json.dumps(payload))
        response=client.getresponse()
        assert response.status == status,(payload,response.status)
        answer=response.read()
        if status==200:
            assert json.loads(answer)==(['8.8.8.8'] if payload['type']==1 else [])
        else:
            assert answer==b''
        client.close()
    assert lookups==['cache.nixos.org','cache.nixos.org','private.github.com']
finally:
    server.shutdown()
    server.server_close()
PY
  [ "$status" -eq 0 ] || printf '%s\n' "$output" >&3
  [ "$status" -eq 0 ]
}

@test "the dependency proxy tries another validated public address when the first cannot connect" {
  local project_root
  project_root="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  run python3 - "$project_root/private_dot_local/share/codex-isolation/secret-isolation-gateway.py" "$BATS_TEST_TMPDIR/proxy" <<'PY'
import http.client, runpy, socket, socketserver, sys, threading
from pathlib import Path
module = runpy.run_path(sys.argv[1])
class Echo(socketserver.BaseRequestHandler):
    def handle(self):
        self.request.sendall(self.request.recv(4))
upstream = socketserver.ThreadingTCPServer(('127.0.0.1', 0), Echo)
threading.Thread(target=upstream.serve_forever, daemon=True).start()
server = module['start_gateway'](Path(sys.argv[2]), 'dependencies', domains=['cache.nixos.org'])
attempts = []
original_socket = socket.socket
class FixtureSocket(original_socket):
    def connect(self, address):
        if self.family == socket.AF_INET and address[1] == 443:
            attempts.append(address[0])
            if address[0] == '8.8.8.8':
                raise TimeoutError('first public address is unreachable')
            assert address[0] == '1.1.1.1'
            address = upstream.server_address
        return super().connect(address)
socket.socket = FixtureSocket
socket.getaddrinfo = lambda *a, **kw: [
    (socket.AF_INET, socket.SOCK_STREAM, 6, '', (address, 443))
    for address in ('8.8.8.8', '1.1.1.1')
]
class Client(http.client.HTTPConnection):
    def connect(self):
        self.sock = original_socket(socket.AF_UNIX)
        self.sock.settimeout(3)
        self.sock.connect(server.server_address)
try:
    client = Client('proxy')
    client.connect()
    tunnel = client.sock
    client.request('CONNECT', 'cache.nixos.org:443')
    response = client.getresponse()
    assert response.status == 200, response.status
    tunnel.sendall(b'ping')
    assert response.read(4) == b'ping'
    response.close()
    client.close()
    assert attempts == ['8.8.8.8', '1.1.1.1'], attempts
finally:
    server.shutdown()
    server.server_close()
    upstream.shutdown()
    upstream.server_close()
PY
  [ "$status" -eq 0 ] || printf '%s\n' "$output" >&3
  [ "$status" -eq 0 ]
}
