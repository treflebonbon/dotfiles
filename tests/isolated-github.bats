#!/usr/bin/env bats

@test "GitHub socket permits only selected repository metadata and rejects secret and administrative routes" {
  local root
  root="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  mkdir "$BATS_TEST_TMPDIR/bin"
  cat > "$BATS_TEST_TMPDIR/bin/gh" <<'SH'
#!/bin/sh
case "$*" in
  'api repos/example/public --method GET') printf '{"full_name":"example/public","private":false,"default_branch":"main"}\n' ;;
  *) exit 70 ;;
esac
SH
  chmod +x "$BATS_TEST_TMPDIR/bin/gh"
  run env PATH="$BATS_TEST_TMPDIR/bin:$PATH" python3 - "$root/private_dot_local/share/codex-isolation/secret-isolation-gateway.py" "$BATS_TEST_TMPDIR/socket" <<'PY'
import http.client, json, runpy, socket, sys
from pathlib import Path
module = runpy.run_path(sys.argv[1])
policy = {'repository': 'example/public', 'branch': 'task', 'default_branch': 'main',
          'reviewed_commit': 'a' * 40, 'automation': 'no-project-secrets', 'review': 'dummy reviewed fixture'}
server = module['start_gateway'](Path(sys.argv[2]), 'github', github_policy=policy)
class Client(http.client.HTTPConnection):
    def connect(self):
        self.sock = socket.socket(socket.AF_UNIX)
        self.sock.connect(str(Path(sys.argv[2]) / 'service.sock'))
try:
    for method, path, expected in [
        ('GET', '/repos/example/public', 200),
        ('GET', '/repos/other/private', 403),
        ('GET', '/repos/example/public/actions/secrets', 403),
        ('GET', '/repos/example/public/actions/runs/1/logs', 403),
        ('GET', '/repos/example/public/contents/.env', 403),
        ('POST', '/graphql', 403),
        ('POST', '/repos/example/public/actions/workflows/a/dispatches', 403),
        ('PUT', '/repos/example/public/pulls/1/merge', 403),
        ('PATCH', '/repos/example/public/pulls/1', 403),
        ('CONNECT', 'api.github.com:443', 403),
    ]:
        client = Client('api.github.com')
        client.request(method, path, headers={'Authorization': 'Bearer dummy-not-forwarded'})
        response = client.getresponse()
        body = response.read()
        assert response.status == expected, (method, path, response.status)
        assert b'dummy-not-forwarded' not in body
        client.close()
finally:
    server.shutdown()
    server.server_close()
PY
  [ "$status" -eq 0 ] || printf '%s\n' "$output" >&3
  [ "$status" -eq 0 ]
}

@test "topic publication validates real Git history and rejects unreviewed automation before invoking the publisher" {
  local root
  root="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  mkdir "$BATS_TEST_TMPDIR/bin"
  cat > "$BATS_TEST_TMPDIR/bin/gh" <<'SH'
#!/bin/sh
case "$*" in
  'api repos/example/public --method GET') printf '{"full_name":"example/public","private":false,"default_branch":"main"}\n' ;;
  'api repos/example/public/git/trees/'*' --method GET') printf '{"tree":[]}\n' ;;
  *) exit 70 ;;
esac
SH
  chmod +x "$BATS_TEST_TMPDIR/bin/gh"
  run env DUMMY_HOST_SECRET=dummy-host-secret PATH="$BATS_TEST_TMPDIR/bin:$PATH" \
    python3 "$root/tests/fixtures/secret-isolation/github-push.py" "$root" "$BATS_TEST_TMPDIR"
  [ "$status" -eq 0 ] || printf '%s\n' "$output" >&3
  [ "$status" -eq 0 ]
}

@test "GitHub PR writes are restricted to the selected topic and reject state changes and extra fields" {
  local root
  root="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  mkdir "$BATS_TEST_TMPDIR/bin"
  cat > "$BATS_TEST_TMPDIR/bin/gh" <<'SH'
#!/bin/sh
case "$*" in
  'api repos/example/public --method GET') printf '{"full_name":"example/public","private":false,"default_branch":"main"}\n' ;;
  'api repos/example/public/git/trees/'*' --method GET') printf '{"tree":[]}\n' ;;
  'api repos/example/public/pulls --method POST --input -')
    cat >/dev/null
    printf '{"number":7,"html_url":"https://github.com/example/public/pull/7","head":{"ref":"task","repo":{"full_name":"example/public"}},"base":{"ref":"main"}}\n' ;;
  *) exit 70 ;;
esac
SH
  chmod +x "$BATS_TEST_TMPDIR/bin/gh"
  run env PATH="$BATS_TEST_TMPDIR/bin:$PATH" python3 - "$root/private_dot_local/share/codex-isolation/secret-isolation-gateway.py" "$BATS_TEST_TMPDIR/socket" <<'PY'
import http.client, json, runpy, socket, sys
from pathlib import Path
module = runpy.run_path(sys.argv[1])
policy = {'repository':'example/public','branch':'task','default_branch':'main',
          'reviewed_commit':'a'*40,'automation':'no-project-secrets','review':'dummy CI review'}
server = module['start_gateway'](Path(sys.argv[2]), 'github', github_policy=policy)
class Client(http.client.HTTPConnection):
    def connect(self):
        self.sock = socket.socket(socket.AF_UNIX)
        self.sock.connect(str(Path(sys.argv[2]) / 'service.sock'))
try:
    good = {'title':'feat: isolated change','body':'Dummy public body','head':'task','base':'main','draft':True}
    for payload, expected in [(good,200),(good|{'head':'other'},403),(good|{'base':'release'},403),
                              (good|{'maintainer_can_modify':True},403),(good|{'state':'closed'},403)]:
        client = Client('api.github.com')
        client.request('POST','/repos/example/public/pulls',json.dumps(payload))
        response = client.getresponse()
        assert response.status == expected, response.status
        response.read()
        client.close()
finally:
    server.shutdown()
    server.server_close()
PY
  [ "$status" -eq 0 ] || printf '%s\n' "$output" >&3
  [ "$status" -eq 0 ]
}
