#!/usr/bin/env bats

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
        self.sock.connect(str(Path(sys.argv[2]) / 'service.sock'))
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
        client.request(method, path, json.dumps(payload), {'Content-Type': 'application/json'})
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
server=module['start_gateway'](Path(sys.argv[2]),'dependencies',domains=['cache.nixos.org','**.github.com'])
class Client(http.client.HTTPConnection):
    def connect(self):
        self.sock=socket.socket(socket.AF_UNIX)
        self.sock.connect(str(Path(sys.argv[2])/'service.sock'))
try:
    for payload,status in [({'host':'cache.nixos.org','type':1},200),({'host':'cache.nixos.org','type':28},200),
                           ({'host':'private.github.com','type':1},403),({'host':'127.0.0.1','type':1},403),
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
