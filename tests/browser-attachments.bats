#!/usr/bin/env bats

setup() {
  ATTACHMENTS="$BATS_TEST_DIRNAME/../private_dot_config/nix-devshell/packages/browser-attachments.mjs"
  export BROWSER_OWNERSHIP_DIR="$BATS_TEST_TMPDIR/ownership"
  export MANAGED_CHROME_OWNER="$BATS_TEST_TMPDIR/owner"
  export PWCLI_POWERSHELL="$BATS_TEST_TMPDIR/powershell"
  export PWCLI_WINDOWS_SCRIPT='C:\fixture.ps1'
  export BROWSER_ATTACHMENTS_PLAYWRIGHT="$BATS_TEST_TMPDIR/playwright.mjs"
  export OWNER_CALLS="$BATS_TEST_TMPDIR/owner-calls"
  export FIXTURE_MODE=headless
  cat >"$MANAGED_CHROME_OWNER" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$OWNER_CALLS"
if [[ "$1" == locate ]]; then
  printf 'attachment-fixture\tC:\\fixture-profile\thttp://127.0.0.1:29999\t30000\n'
else
  printf '{"phase":"active","mode":"%s","browserPid":4242,"token":"fixture"}\n' "$FIXTURE_MODE"
fi
SH
  cat >"$PWCLI_POWERSHELL" <<'SH'
#!/usr/bin/env bash
printf 'managed:headless:4242\n'
SH
  chmod +x "$MANAGED_CHROME_OWNER" "$PWCLI_POWERSHELL"
  printf 'export const chromium={connectOverCDP:async()=>{throw new Error("connection refused");}};\n' >"$BROWSER_ATTACHMENTS_PLAYWRIGHT"
  printf image >"$BATS_TEST_TMPDIR/image.png"
}

upload() {
  node "$ATTACHMENTS" upload --repo owner/repo --pr 42 --image "$BATS_TEST_TMPDIR/image.png" --placeholder PLACE --request-id test
}

@test "attachment mode conflict preserves the existing owner before attempting upload" {
  export FIXTURE_MODE=headed
  run upload
  [ "$status" -ne 0 ]
  [[ "$output" == *ownership-conflict:* ]]
  ! grep -Eq 'release|run|reserve' "$OWNER_CALLS"
  [ -z "$(find "$BROWSER_OWNERSHIP_DIR" -name '*.json' -print)" ]
}

@test "attachment CDP failure is distinguished and does not create an upload receipt" {
  run upload
  [ "$status" -ne 0 ]
  [[ "$output" == *cdp-unavailable:* ]]
  ! grep -Eq 'release|run|reserve' "$OWNER_CALLS"
  [ -z "$(find "$BROWSER_OWNERSHIP_DIR" -name '*.json' -print)" ]
}
