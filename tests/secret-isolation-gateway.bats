#!/usr/bin/env bats

@test "the model socket rejects remote state, remote tools, malformed requests and other routes without upstream access" {
  local project_root
  project_root="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  mkdir -p "$BATS_TEST_TMPDIR/home/.codex"
  printf '{"tokens":{"access_token":"dummy-access","account_id":"dummy-account"}}\n' >"$BATS_TEST_TMPDIR/home/.codex/auth.json"
  run env HOME="$BATS_TEST_TMPDIR/home" CODEX_HOME="$BATS_TEST_TMPDIR/home/.codex" \
    python3 - "$project_root/scripts/secret-isolation-gateway.py" "$BATS_TEST_TMPDIR/socket" <<'PY'
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
