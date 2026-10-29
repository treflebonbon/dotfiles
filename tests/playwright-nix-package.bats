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
