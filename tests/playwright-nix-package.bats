#!/usr/bin/env bats

setup() {
  PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
}

@test "Nix Playwright package uses the fixed public browser assets" {
  local module="$PROJECT_ROOT/private_dot_config/nix-devshell/modules/ai.nix"
  local package="$PROJECT_ROOT/private_dot_config/nix-devshell/packages/playwright-cli.nix"
  local assets="$PROJECT_ROOT/private_dot_config/nix-devshell/packages"

  grep -Fq 'skills-plugin.json' "$module"
  grep -Fq 'fetchFromGitHub' "$module"
  grep -Fq 'nodejs skillsPluginSource;' "$module"
  grep -Fq 'skillsPluginSource' "$package"
  grep -Fq 'packages/wsl2-browser' "$package"
  grep -Fq 'program_before_count' "$package"
  grep -Fq 'program_after_count' "$package"
  grep -Fq 'substituteInPlace "$program" --replace-fail' "$package"

  for asset in \
    browser-attachments.mjs \
    browser-lock.mjs \
    dogfood-chrome-windows.ps1 \
    managed-chrome-owner.mjs \
    playwright-cli-cdp-close.js \
    playwright-cli-sockets.cjs \
    playwright-cli-sockets.patch \
    playwright-cli-wrapper.sh \
    playwright-cli-windows.ps1 \
    playwright-cli-wsl-skill.md \
    playwright-runtime.mjs \
    pr-evidence.mjs; do
    [ ! -e "$assets/$asset" ]
  done
}

@test "Nix output wires the public helpers to its pinned Playwright runtime" {
  [[ -n "${TEST_PLAYWRIGHT_PACKAGE:-}" ]] || skip "Set TEST_PLAYWRIGHT_PACKAGE to the built Playwright package output"
  local package="$TEST_PLAYWRIGHT_PACKAGE"
  local core="$package/lib/node_modules/playwright-cli-agent/node_modules/playwright-core"

  [ -x "$package/bin/playwright-cli" ]
  [ -x "$package/bin/browser-attachments" ]
  [ -x "$package/bin/managed-chrome-owner" ]
  [ -f "$package/libexec/playwright-cli-wrapper.sh" ]
  [ -f "$package/libexec/playwright-cli-sockets.patch" ]
  [ -f "$package/share/playwright-cli/playwright-runtime.mjs" ]
  [ -f "$package/share/playwright-cli/browser-lock.mjs" ]
  [ -f "$package/share/playwright-cli/references/playwright-cli-wsl.md" ]
  [ -f "$package/share/licenses/playwright-cli/LICENSE" ]
  [ -f "$package/share/licenses/playwright-cli/THIRD_PARTY_NOTICES.md" ]
  [ -f "$package/libexec/browser-attachments.mjs" ]
  [ -f "$package/libexec/playwright-cli-cdp-close.js" ]
  [ -f "$core/lib/tools/cli-client/program.js" ]

  grep -Fq 'process.env.PWTEST_CLI_MANAGED_CHROME === "1" ? "tab-new" : "goto"' \
    "$core/lib/tools/cli-client/program.js"
  grep -Fq 'require("./playwright-cli-sockets.cjs").shortSocketPath(dir, name)' \
    "$core/lib/coreBundle.js"
  grep -Fq "$package/libexec/playwright-cli-upstream" "$package/bin/playwright-cli"
  grep -Fq "$package/libexec/playwright-cli-cdp-close" "$package/bin/playwright-cli"
  grep -Fq "$package/libexec/playwright-runtime" "$package/bin/playwright-cli"
  grep -Fq "$package/bin/managed-chrome-owner" "$package/bin/playwright-cli"
  grep -Fq "$package/libexec/browser-attachments-entrypoint" "$package/bin/browser-attachments"
  grep -Fq '$package_root/libexec/browser-attachments.mjs' "$package/libexec/browser-attachments-entrypoint"
  grep -Fq "$package/lib/node_modules/playwright-cli-agent/node_modules/@playwright/cli/../../playwright-core/index.mjs" \
    "$package/bin/browser-attachments"
  grep -Fq 'Managed Playwright Chrome' "$package/share/playwright-cli/skills/playwright-cli/SKILL.md"
  grep -Fq "package's own source is licensed under the repository's MIT license" \
    "$package/share/licenses/playwright-cli/THIRD_PARTY_NOTICES.md"
}

@test "Nix 所有権 CLI は既定 Windows 資産を解決し不確定な記録を保持する" {
  [[ -n "${TEST_PLAYWRIGHT_PACKAGE:-}" ]] || skip "ビルド済み package を TEST_PLAYWRIGHT_PACKAGE に指定する"
  local package="$TEST_PLAYWRIGHT_PACKAGE"
  local owner="$package/bin/managed-chrome-owner"
  export BROWSER_OWNERSHIP_DIR="$BATS_TEST_TMPDIR/ownership"
  export PWCLI_RUNTIME_DIR="$BATS_TEST_TMPDIR/runtime"
  export OWNER_PROBE_STATE="$BATS_TEST_TMPDIR/probe-state"
  export OWNER_PROBE_LOG="$BATS_TEST_TMPDIR/probe-log"
  unset PWCLI_WINDOWS_SCRIPT DOGFOOD_WINDOWS_SCRIPT DOGFOOD_BROWSER_OWNERSHIP_DIR
  export PWCLI_POWERSHELL="$BATS_TEST_TMPDIR/powershell.exe"
  export DOGFOOD_POWERSHELL="$PWCLI_POWERSHELL"
  export PWCLI_WSLPATH="$BATS_TEST_TMPDIR/wslpath"
  export DOGFOOD_WSLPATH="$PWCLI_WSLPATH"
  cat >"$PWCLI_POWERSHELL" <<'FIXTURE'
#!/usr/bin/env bash
set -euo pipefail
script=
while (($#)); do
  if [[ $1 == -File ]]; then
    script=$2
    break
  fi
  shift
done
if [[ -z $script || ! -f $script ]]; then
  printf '指定された PowerShell 資産が存在しません: %s\n' "$script" >&2
  exit 53
fi
printf '%s\n' "$script" >>"$OWNER_PROBE_LOG"
if [[ $(cat "$OWNER_PROBE_STATE") == query-error ]]; then
  printf 'fixture query failed\n' >&2
  exit 54
fi
cat "$OWNER_PROBE_STATE"
FIXTURE
  cat >"$PWCLI_WSLPATH" <<'FIXTURE'
#!/usr/bin/env bash
[[ $# == 2 && $1 == -w ]] || exit 2
printf '%s\n' "$2"
FIXTURE
  chmod +x "$PWCLI_POWERSHELL" "$PWCLI_WSLPATH"

  local role token script profile prefix before state expected
  for role in attachment playwright dogfood; do
    script=playwright-cli-windows.ps1
    [[ $role == dogfood ]] && script=dogfood-chrome-windows.ps1
    profile="$BATS_TEST_TMPDIR/profile-$role"
    mkdir "$profile"
    printf '%s\n' profile-marker >"$profile/marker"
    token="$("$owner" --identity "$role" reserve --role "$role" --id "$role" \
      --pid "$$" --mode headless --profile "$profile" --endpoint http://127.0.0.1:19222)"
    : >"$OWNER_PROBE_LOG"
    before="$("$owner" --identity "$role" status)"
    [ ! -s "$OWNER_PROBE_LOG" ]
    run "$owner" --identity "$role" activate "$token"
    [ "$status" -ne 0 ]
    [[ $output == *"Startup has not completed"* ]]
    run "$owner" --identity "$role" recover
    [ "$status" -ne 0 ]
    [[ $output == *"A live startup reservation exists"* ]]
    [ "$("$owner" --identity "$role" status)" = "$before" ]
    [ ! -s "$OWNER_PROBE_LOG" ]
    "$owner" --identity "$role" run "$token" -- true
    printf '%s\n' managed:headless:4242 >"$OWNER_PROBE_STATE"
    : >"$OWNER_PROBE_LOG"
    run "$owner" --identity "$role" activate "$token"
    printf '%s\n' "$output"
    [ "$status" -eq 0 ]
    [ "$(cat "$OWNER_PROBE_LOG")" = "$package/libexec/$script" ]

    : >"$OWNER_PROBE_LOG"
    before="$("$owner" --identity "$role" status)"
    [[ $before == *'"phase":"active"'* ]]
    [ ! -s "$OWNER_PROBE_LOG" ]
    for state in managed:headless:4242 unknown query-error; do
      printf '%s\n' "$state" >"$OWNER_PROBE_STATE"
      expected="Chrome state is unconfirmed"
      [[ $state == managed:* ]] && expected="Chrome is still running"
      [[ $state == query-error ]] && expected="fixture query failed"
      run "$owner" --identity "$role" recover
      [ "$status" -ne 0 ]
      [[ $output == *"$expected"* ]]
      [ "$("$owner" --identity "$role" status)" = "$before" ]
      [ "$(cat "$profile/marker")" = profile-marker ]
    done

    prefix=PWCLI
    [[ $role == dogfood ]] && prefix=DOGFOOD
    export "${prefix}_WINDOWS_SCRIPT=$BATS_TEST_TMPDIR/missing-$role.ps1"
    : >"$OWNER_PROBE_LOG"
    run "$owner" --identity "$role" recover
    [ "$status" -ne 0 ]
    [[ $output == *"Windows script unavailable ($BATS_TEST_TMPDIR/missing-$role.ps1)"* ]]
    [ "$("$owner" --identity "$role" status)" = "$before" ]
    [ ! -s "$OWNER_PROBE_LOG" ]

    cp "$package/libexec/$script" "$BATS_TEST_TMPDIR/override-$role.ps1"
    export "${prefix}_WINDOWS_SCRIPT=$BATS_TEST_TMPDIR/override-$role.ps1"
    printf '%s\n' managed:headless:4242 >"$OWNER_PROBE_STATE"
    run "$owner" --identity "$role" activate "$token"
    [ "$status" -eq 0 ]
    [ "$(cat "$OWNER_PROBE_LOG")" = "$BATS_TEST_TMPDIR/override-$role.ps1" ]
    unset PWCLI_WINDOWS_SCRIPT DOGFOOD_WINDOWS_SCRIPT

    printf '%s\n' absent >"$OWNER_PROBE_STATE"
    : >"$OWNER_PROBE_LOG"
    run "$owner" --identity "$role" recover
    printf '%s\n' "$output"
    [ "$status" -eq 0 ]
    [ "$(cat "$OWNER_PROBE_LOG")" = "$package/libexec/$script" ]
    run "$owner" --identity "$role" status
    [ "$output" = null ]
    [ "$(cat "$profile/marker")" = profile-marker ]
  done
}
