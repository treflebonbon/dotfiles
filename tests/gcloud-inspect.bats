#!/usr/bin/env bats

bats_require_minimum_version 1.5.0

setup() {
	PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
	SCRIPT="$PROJECT_ROOT/private_dot_local/bin/executable_gcloud-inspect"
	export MOCK_GCLOUD_LOG="$BATS_TEST_TMPDIR/gcloud.jsonl"
	export MOCK_GCLOUD_RESPONSE="$BATS_TEST_TMPDIR/response.json"
	export HOME="$BATS_TEST_TMPDIR/home"
	mkdir -p "$BATS_TEST_TMPDIR/bin" "$HOME"
	export PATH="$BATS_TEST_TMPDIR/bin:$PATH"
	cat >"$BATS_TEST_TMPDIR/bin/gcloud" <<'PY'
#!/usr/bin/env python3
import json
import os
from pathlib import Path
import sys

if "--help" in sys.argv:
    if sys.argv[1:4] == ["compute", "disks", "describe"]:
        print("NAME\n    gcloud compute disks describe - describe a disk\n\nSYNOPSIS")
    elif sys.argv[1:4] == ["config", "configurations", "activate"]:
        print("NAME\n    gcloud config configurations activate - activate a configuration\n\nSYNOPSIS")
    else:
        raise SystemExit(2)
    raise SystemExit(0)

with open(os.environ["MOCK_GCLOUD_LOG"], "a") as log:
    log.write(json.dumps(sys.argv[1:]) + "\n")
if os.environ.get("MOCK_GCLOUD_FAIL"):
    print("diagnostic containing DUMMY_SECRET", file=sys.stderr)
    raise SystemExit(1)
if sys.argv[1:3] == ["auth", "print-access-token"]:
    print("DUMMY_ACCESS_TOKEN")
else:
    assert os.environ.get("CLOUDSDK_CORE_SHOULD_PROMPT_TO_ENABLE_API") == "false"
    print(Path(os.environ["MOCK_GCLOUD_RESPONSE"]).read_text())
PY
	chmod +x "$BATS_TEST_TMPDIR/bin/gcloud"
}

@test "gcloud-inspect reads filtered logs through the existing CLI" {
	printf '%s\n' '[{"severity":"ERROR","textPayload":"request failed"}]' >"$MOCK_GCLOUD_RESPONSE"
	run python3 -I "$SCRIPT" logging read 'severity>=ERROR' --project example-project --limit 20
	[ "$status" -eq 0 ]
	[ "$(jq -r '.[0].textPayload' <<<"$output")" = 'request failed' ]
	run jq -e '.[0:3] == ["logging", "read", "severity>=ERROR"] and index("--format=json") != null and index("--quiet") != null' "$MOCK_GCLOUD_LOG"
	[ "$status" -eq 0 ]
}

@test "gcloud-inspect preserves nonsecret configuration and removes known sensitive fields" {
	cat >"$MOCK_GCLOUD_RESPONSE" <<'JSON'
{"metadata":{"name":"example-service","annotations":{"token":"DUMMY_SECRET","kubectl.kubernetes.io/last-applied-configuration":"DUMMY_SECRET"}},"status":{"url":"https://service.example"},"spec":{"template":{"spec":{"containers":[{"image":"example/image","env":[{"name":"PASSWORD","value":"DUMMY_SECRET"}]}]}},"masterAuth":{"password":"DUMMY_SECRET"}},"nested":{"access_token":"DUMMY_SECRET","clientSecret":"DUMMY_SECRET"}}
JSON
	run python3 -I "$SCRIPT" run services describe example --project example-project --region asia-northeast1
	[ "$status" -eq 0 ]
	[[ "$output" != *DUMMY_SECRET* ]]
	[ "$(jq -r '.metadata.name' <<<"$output")" = 'example-service' ]
	[ "$(jq -r '.status.url' <<<"$output")" = 'https://service.example' ]
	[ "$(jq -r '.spec.template.spec.containers[0].image' <<<"$output")" = 'example/image' ]
}

@test "gcloud-inspect hides instance metadata values while retaining resource identity" {
	printf '%s\n' '{"name":"example-vm","metadata":{"kind":"compute#metadata","items":[{"key":"startup-script","value":"DUMMY_SECRET"}]},"status":"RUNNING"}' >"$MOCK_GCLOUD_RESPONSE"
	run python3 -I "$SCRIPT" compute instances describe example-vm --zone asia-northeast1-a
	[ "$status" -eq 0 ]
	[[ "$output" != *DUMMY_SECRET* ]]
	[ "$(jq -r '.metadata.kind' <<<"$output")" = 'compute#metadata' ]
	[ "$(jq -r '.status' <<<"$output")" = RUNNING ]
}

@test "gcloud-inspect refuses unknown operations and output or authentication overrides before invoking gcloud" {
	local args
	for args in \
		'run services delete example' \
		'secrets versions access latest --secret example' \
		'auth print-access-token' \
		'run services describe example --format yaml' \
		'run services describe example --flags-file /tmp/flags.yaml' \
		'run services describe example --impersonate-service-account example' \
		'run services describe example --access-token-file /tmp/token' \
		'run services describe example --log-http' \
		'logging read --limit 1001' \
		'logging read --limit -1'; do
		# These fixed cases contain no shell quoting or expansions.
		read -r -a arguments <<<"$args"
		run python3 -I "$SCRIPT" "${arguments[@]}"
		[ "$status" -ne 0 ]
		[ ! -e "$MOCK_GCLOUD_LOG" ]
	done
}

@test "gcloud-inspect fails without exposing failed CLI diagnostics or malformed output" {
	printf '%s\n' 'invalid JSON containing DUMMY_SECRET' >"$MOCK_GCLOUD_RESPONSE"
	run python3 -I "$SCRIPT" projects list
	[ "$status" -ne 0 ]
	[[ "$output" != *DUMMY_SECRET* ]]
	run env MOCK_GCLOUD_FAIL=1 python3 -I "$SCRIPT" projects list
	[ "$status" -ne 0 ]
	[[ "$output" != *DUMMY_SECRET* ]]
}

@test "gcloud-inspect reads Monitoring time series without exposing the internal token" {
	run python3 -I - "$SCRIPT" <<'PY'
import json
import runpy
import sys
from unittest.mock import patch
from urllib.parse import parse_qs, urlsplit

class Response:
    def __enter__(self):
        return self
    def __exit__(self, *args):
        return False
    def read(self):
        return b'{"timeSeries":[{"metric":{"type":"compute.googleapis.com/instance/cpu/utilization"},"points":[{"value":{"doubleValue":0.5}}]}]}'

def open_request(opener, request, **kwargs):
    assert request.get_method() == 'GET'
    assert request.get_header('Authorization') == 'Bearer DUMMY_ACCESS_TOKEN'
    url = urlsplit(request.full_url)
    assert url.scheme == 'https' and url.netloc == 'monitoring.googleapis.com'
    assert url.path == '/v3/projects/example-project/timeSeries'
    query = parse_qs(url.query)
    assert query['filter'] == ['metric.type="compute.googleapis.com/instance/cpu/utilization"']
    assert query['interval.startTime'] == ['2026-10-15T00:00:00+00:00']
    assert query['interval.endTime'] == ['2026-10-15T01:00:00+00:00']
    assert query['pageSize'] == ['10']
    assert query['pageToken'] == ['NEXT_PAGE']
    return Response()

sys.argv = [sys.argv[1], 'monitoring', 'time-series', 'list', '--project', 'example-project',
            '--filter', 'metric.type="compute.googleapis.com/instance/cpu/utilization"',
            '--start', '2026-10-15T00:00:00Z', '--end', '2026-10-15T01:00:00Z', '--limit', '10', '--page-token', 'NEXT_PAGE']
with patch('urllib.request.OpenerDirector.open', open_request):
    runpy.run_path(sys.argv[0], run_name='__main__')
PY
	[ "$status" -eq 0 ]
	[[ "$output" != *DUMMY_ACCESS_TOKEN* ]]
	[ "$(jq -r '.timeSeries[0].points[0].value.doubleValue' <<<"$output")" = '0.5' ]
}

@test "gcloud-inspect does not forward its token on Monitoring redirects" {
	run python3 -I - "$SCRIPT" <<'PY'
from io import BytesIO
from email.message import Message
import runpy
import sys
from unittest.mock import patch
from urllib.response import addinfourl

requests = []
def https_open(handler, request):
    requests.append(request.full_url)
    assert request.host == 'monitoring.googleapis.com'
    headers = Message()
    headers['Location'] = 'https://unexpected.example/receive'
    response = addinfourl(BytesIO(b'DUMMY_SECRET'), headers, request.full_url, 302)
    response.msg = 'Found'
    return response

sys.argv = [sys.argv[1], 'monitoring', 'time-series', 'list', '--project', 'example-project',
            '--filter', 'metric.type="example"', '--start', '2026-10-15T00:00:00Z', '--end', '2026-10-15T01:00:00Z']
with patch('urllib.request.HTTPSHandler.https_open', https_open):
    try:
        runpy.run_path(sys.argv[0], run_name='__main__')
    except SystemExit as error:
        assert error.code == 1
    else:
        raise AssertionError('redirect must fail')
assert len(requests) == 1
PY
	[ "$status" -eq 0 ]
	[[ "$output" == *'Monitoring API の参照に失敗'* ]]
	[[ "$output" != *DUMMY_ACCESS_TOKEN* ]]
	[[ "$output" != *DUMMY_SECRET* ]]
}

@test "gcloud-inspect validates Monitoring requests before retrieving a token" {
	for project in '../other-project' 'example-project?destination=other'; do
		run python3 -I "$SCRIPT" monitoring time-series list --project "$project" \
			--filter 'metric.type="example"' --start 2026-10-15T00:00:00Z --end 2026-10-15T01:00:00Z
		[ "$status" -ne 0 ]
		[ ! -e "$MOCK_GCLOUD_LOG" ]
	done
	run python3 -I "$SCRIPT" monitoring time-series list --project example-project \
		--filter 'metric.type="example"' --start 2026-10-15T02:00:00Z --end 2026-10-15T01:00:00Z
	[ "$status" -ne 0 ]
	[ ! -e "$MOCK_GCLOUD_LOG" ]
}

@test "installed gcloud-inspect supports configuration and IAM reads across services" {
	install -m 755 "$SCRIPT" "$BATS_TEST_TMPDIR/bin/gcloud-inspect"
	printf '%s\n' '{"name":"example","status":"ACTIVE"}' >"$MOCK_GCLOUD_RESPONSE"
	local command
	for command in \
		'projects list' \
		'projects get-iam-policy example-project' \
		'monitoring policies list' \
		'container clusters describe example' \
		'iam service-accounts describe example' \
		'config list'; do
		read -r -a arguments <<<"$command"
		run gcloud-inspect "${arguments[@]}"
		[ "$status" -eq 0 ]
		[ "$(jq -r .name <<<"$output")" = example ]
	done
	run jq -se '.[-1] == ["config", "list", "--format=json", "--quiet"]' "$MOCK_GCLOUD_LOG"
	[ "$status" -eq 0 ]
}

@test "Codex automatically allows supported investigation commands and reviews raw CLI access" {
	local command
	for command in \
		'gcloud-inspect run services describe example' \
		'gh pr view 42' \
		'gh pr diff 42' \
		'gh pr checks 42' \
		'gh repo view owner/repo' \
		'gh search code example' \
		'gh run view 42 --log-failed' \
		'gh run list' \
		'gh workflow view build'; do
		read -r -a arguments <<<"$command"
		run --separate-stderr codex execpolicy check --rules "$PROJECT_ROOT/private_dot_config/codex/rules/default.rules" -- "${arguments[@]}"
		[ "$status" -eq 0 ]
		[ "$(jq -r .decision <<<"$output")" = allow ]
	done
	for command in 'gcloud-inspect --reviewed compute disks list' 'gh api repos/owner/repo' 'gh api graphql'; do
		read -r -a arguments <<<"$command"
		run --separate-stderr codex execpolicy check --rules "$PROJECT_ROOT/private_dot_config/codex/rules/default.rules" -- "${arguments[@]}"
		[ "$status" -eq 0 ]
		[ "$(jq -r .decision <<<"$output")" = prompt ]
	done
	for command in \
		'gcloud run services describe example' \
		'gcloud unknown read' \
		'gcloud secrets versions access latest' \
		'gcloud auth print-access-token' \
		'gcloud beta secrets versions access latest' \
		'gcloud --project=example-project secrets versions access latest' \
		'gcloud --configuration=example auth print-access-token'; do
		read -r -a arguments <<<"$command"
		run --separate-stderr codex execpolicy check --rules "$PROJECT_ROOT/private_dot_config/codex/rules/default.rules" -- "${arguments[@]}"
		[ "$status" -eq 0 ]
		[ "$(jq -r .decision <<<"$output")" = forbidden ]
	done
}

@test "Claude permits safe investigation and retains the raw gcloud boundary" {
	for settings in "$PROJECT_ROOT/private_dot_claude/settings.json.tmpl" "$PROJECT_ROOT/.claude/settings.json"; do
		run jq -e '
      (.permissions.allow | index("Bash(gcloud-inspect:*)") != null)
      and (.permissions.deny | index("Bash(gcloud:*)") != null)
      and (.permissions.ask | index("Bash(gcloud-inspect --reviewed:*)") != null)
      and (.permissions.ask | index("Bash(gh api:*)") != null)
    ' "$settings"
		[ "$status" -eq 0 ]
	done
}

@test "reviewed investigation supports additional read operations while still filtering configuration" {
	cat >"$MOCK_GCLOUD_RESPONSE" <<'JSON'
{"name":"data-disk","diskEncryptionKey":{"rawKey":"DUMMY_SECRET"}}
JSON
	run python3 -I "$SCRIPT" compute disks describe data-disk
	[ "$status" -eq 2 ]
	[ ! -e "$MOCK_GCLOUD_LOG" ]
	run python3 -I "$SCRIPT" --reviewed compute disks describe data-disk --project example-project --zone asia-northeast1-a
	[ "$status" -eq 0 ]
	[ "$(jq -r .name <<<"$output")" = data-disk ]
	[[ "$output" != *DUMMY_SECRET* ]]
}

@test "reviewed investigation rejects authentication, hidden global options, and mutations" {
	for command in \
		'auth print-access-token' \
		'beta secrets versions access latest' \
		'--project=example-project secrets versions access latest' \
		'compute disks delete data-disk' \
		'config configurations activate list' \
		'run services describe example --reviewed'; do
		read -r -a arguments <<<"$command"
		run python3 -I "$SCRIPT" --reviewed "${arguments[@]}"
		[ "$status" -ne 0 ]
		[ ! -e "$MOCK_GCLOUD_LOG" ]
	done
}
