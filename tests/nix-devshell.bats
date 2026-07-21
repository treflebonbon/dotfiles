#!/usr/bin/env bats

setup() {
  PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
}

@test "nix-devshell includes bubblewrap for Codex sandboxing on Linux only" {
  local module="$PROJECT_ROOT/private_dot_config/nix-devshell/modules/ai.nix"

  grep -q 'lib\.optionals pkgs\.stdenv\.isLinux \[ pkgs\.bubblewrap \]' "$module"
}

@test "user devShell retains four-system support on nixpkgs 26.05" {
  local flake="$PROJECT_ROOT/private_dot_config/nix-devshell/flake.nix"

  grep -q 'nixpkgs-26\.05-darwin' "$flake"
  grep -q '"x86_64-linux"' "$flake"
  grep -q '"aarch64-linux"' "$flake"
  grep -q '"aarch64-darwin"' "$flake"
  grep -q '"x86_64-darwin"' "$flake"
  grep -q 'llm-agents\.overlays\.shared-nixpkgs' "$flake"
}

@test "shell.nix includes zsh-autosuggestions and zsh-syntax-highlighting packages (issue #46)" {
  local module="$PROJECT_ROOT/private_dot_config/nix-devshell/modules/shell.nix"
  grep -q 'zsh-autosuggestions' "$module"
  grep -q 'zsh-syntax-highlighting' "$module"
}

@test "shell.nix includes zsh itself so bats tests/dot_zshrc.bats doesn't depend on host zsh (issue #46 review)" {
  local module="$PROJECT_ROOT/private_dot_config/nix-devshell/modules/shell.nix"
  grep -qE '^\s*zsh\s*$' "$module"
}

@test "shell.nix exposes ZSH_AUTOSUGGESTIONS_SHARE / ZSH_SYNTAX_HIGHLIGHTING_SHARE via env (issue #46)" {
  local module="$PROJECT_ROOT/private_dot_config/nix-devshell/modules/shell.nix"
  grep -q 'ZSH_AUTOSUGGESTIONS_SHARE' "$module"
  grep -q 'ZSH_SYNTAX_HIGHLIGHTING_SHARE' "$module"
  grep -q 'zsh-autosuggestions.zsh' "$module"
  grep -q 'zsh-syntax-highlighting.zsh' "$module"
}

@test "nix-devshell packages pinned Linux glibc flyline release (issue #53)" {
  local pkg="$PROJECT_ROOT/private_dot_config/nix-devshell/packages/flyline.nix"
  local flake="$PROJECT_ROOT/private_dot_config/nix-devshell/flake.nix"
  local module="$PROJECT_ROOT/private_dot_config/nix-devshell/modules/shell.nix"

  grep -q 'version = "1.3.0";' "$pkg"
  grep -q 'libflyline-v${version}-x86_64-unknown-linux-gnu.tar.gz' "$pkg"
  grep -q 'libflyline-v${version}-aarch64-unknown-linux-gnu.tar.gz' "$pkg"
  grep -q 'sha256-IbsKeg5BdJb/aO+DecrcBdNeQq7jV/xkrZqNlfaTIPg=' "$pkg"
  grep -q 'sha256-qIm8Fu4x5aa4Vyi5udnSPWfz8PuyG/DK5+J4kL1DxM0=' "$pkg"
  grep -q 'libflyline.so' "$pkg"
  grep -q 'license = lib.licenses.gpl3Only' "$pkg"
  grep -q 'flyline = pkgs.callPackage ./packages/flyline.nix' "$flake"
  grep -q 'FLYLINE_BASH_LOADABLE' "$module"
  grep -q 'lib.optionals pkgs.stdenv.isLinux' "$module"
  ! grep -q 'unknown-linux-musl' "$pkg"
}

@test "shell docs describe flyline bash ownership and zsh native ownership (issues #54 #55)" {
  local readme="$PROJECT_ROOT/README.md"
  local runtime="$PROJECT_ROOT/runtime/shell-environment.md"

  grep -q 'flyline' "$readme"
  grep -q '履歴検索の所有者' "$runtime"
  grep -q '主要機能セット' "$runtime"
  grep -q 'bash.*flyline' "$runtime"
  grep -q 'zsh.*atuin' "$runtime"
  grep -q 'ADR-0021' "$runtime"
  ! grep -q 'ble.sh.*リッチな Tab 補完' "$readme"
  ! grep -q 'ble.sh.*リッチな Tab 補完' "$runtime"
}

@test "repository flake includes Playwright runner dependencies" {
  local flake="$PROJECT_ROOT/flake.nix"

  grep -q 'nodejs_24' "$flake"
  grep -q 'playwright-driver' "$flake"
  grep -q 'PLAYWRIGHT_BROWSERS_PATH' "$flake"
  grep -q 'PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD' "$flake"
}

@test "nix-devshell requires Claude Code with isolated worktree fixes" {
  grep -q 'minClaudeCode = "2\.1\.216";' "$PROJECT_ROOT/private_dot_config/nix-devshell/modules/ai.nix"
}

@test "nix-devshell requires Codex with GPT 5.6 support" {
  local module="$PROJECT_ROOT/private_dot_config/nix-devshell/modules/ai.nix"

  grep -q 'minCodex = "0\.144\.6";' "$module"
  grep -q 'llm\.codex\.version' "$module"
  grep -q 'llm\.codex;' "$module"
  ! grep -q 'llm\.codex\.override' "$module"
}

@test "nix-devshell includes Google Antigravity CLI" {
  grep -q 'llm\.antigravity' "$PROJECT_ROOT/private_dot_config/nix-devshell/modules/ai.nix"
}

@test "nix-devshell installs Playwright CLI 0.1.17 and local skill symlinks" {
  local module="$PROJECT_ROOT/private_dot_config/nix-devshell/modules/ai.nix"
  local pkg="$PROJECT_ROOT/private_dot_config/nix-devshell/packages/playwright-cli.nix"
  local package_json="$PROJECT_ROOT/private_dot_config/nix-devshell/packages/playwright-cli-agent/package.json"

  grep -q 'playwright-cli = pkgs.callPackage ../packages/playwright-cli.nix' "$module"
  grep -q '^    playwright-cli$' "$module"
  grep -q 'share/playwright-cli/skills/playwright-cli' "$module"
  grep -q '\.agents/skills/playwright-cli' "$module"
  grep -q '\.claude/skills/playwright-cli' "$module"
  grep -q 'pname = "playwright-cli";' "$pkg"
  grep -q -- '--unset PLAYWRIGHT_BROWSERS_PATH' "$pkg"
  grep -q -- '--unset PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD' "$pkg"
  grep -q 'version = "0.1.17";' "$pkg"
  grep -q '"@playwright/cli": "0.1.17"' "$package_json"
}

@test "nix-devshell pins design.md 0.3.0 and document converters" {
  local flake="$PROJECT_ROOT/private_dot_config/nix-devshell/flake.nix"
  local module="$PROJECT_ROOT/private_dot_config/nix-devshell/modules/ai.nix"
  local pkg="$PROJECT_ROOT/private_dot_config/nix-devshell/packages/design-md-cli.nix"
  local package_json="$PROJECT_ROOT/private_dot_config/nix-devshell/packages/design-md-cli/package.json"

  grep -q 'version = "0.3.0";' "$pkg"
  grep -q '"@google/design.md": "0.3.0"' "$package_json"
  grep -q '421eebfd0ec7bccd4abe826ce62d7e6e83129493' "$flake"
  grep -q 'nixpkgs-ai-sources.*defuddle/package\.nix' "$module"
  grep -q 'markitdown/default\.nix' "$module"
}

@test "local skill deploy uses agents hub for Codex without native duplicate target" {
  local deploy="$PROJECT_ROOT/run_onchange_after_deploy-local-skills.sh.tmpl"
  local cleanup="$PROJECT_ROOT/run_onchange_before_remove-orphan-claude-skills.sh.tmpl"
  local runtime="$PROJECT_ROOT/runtime/skill-harness.md"

  grep -q '\.agents/skills/\$name' "$deploy"
  grep -q '\.claude/skills/\$name' "$deploy"
  ! grep -q 'codex_home/skills/\$name' "$deploy"
  grep -q 'remove_named_skill_entries "\${HOME}/\.codex/skills" "codex local duplicate"' "$cleanup"
  grep -q 'Codex native location.*へは配備しない' "$runtime"
}

@test "ui grill skill is available through local skill deployment" {
  local skill="$PROJECT_ROOT/local-skills/ui-grill-with-docs/SKILL.md"
  local deploy="$PROJECT_ROOT/run_onchange_after_deploy-local-skills.sh.tmpl"

  [ -f "$skill" ]
  sed -n '/^local_skills=(/,/^)/p' "$deploy" | grep -qx '  ui-grill-with-docs'
}

@test "ui grill skill contract keeps visual aids disposable" {
  local skill="$PROJECT_ROOT/local-skills/ui-grill-with-docs/SKILL.md"
  local runtime="$PROJECT_ROOT/runtime/skill-harness.md"

  grep -qx 'name: ui-grill-with-docs' "$skill"
  grep -qx 'disable-model-invocation: true' "$skill"
  grep -Fq 'tmp/wireframe-<screen>.html' "$skill"
  grep -Fq 'The question, recommendation, and' "$skill"
  grep -Fq 'mockups are never the source' "$skill"
  grep -Fq 'ask the user to confirm cleanup' "$skill"
  grep -Fq 'delete only the `tmp/wireframe-*.html` files' "$skill"
  grep -Fq '`ui-grill-with-docs`' "$runtime"
}

@test "pre-commit applies OXC to local skills without rewriting run-code examples" {
  local config="$PROJECT_ROOT/lefthook.yml"
  local skill="$PROJECT_ROOT/local-skills/to-pr/SKILL.md"
  local fixture="$PROJECT_ROOT/local-skills/dogfood-to-issues/references/fixtures/mv3-min"

  ! sed -n '/name: oxfmt/,/stage_fixed: true/p' "$config" | grep -Fq 'local-skills/**'
  ! sed -n '/name: oxlint/,/stage_fixed: true/p' "$config" | grep -Fq 'local-skills/**'
  sed -n '/name: oxfmt/,/stage_fixed: true/p' "$config" | grep -Fq '"**/*.mjs"'
  sed -n '/name: oxlint/,/stage_fixed: true/p' "$config" | grep -Fq '"**/*.mjs"'
  [ "$(grep -Fc '<!-- prettier-ignore -->' "$skill")" -eq 2 ]
  [ -f "$fixture/service-worker.js" ]
  [ ! -e "$fixture/service_worker.js" ]
  grep -Fq '"service_worker": "service-worker.js"' "$fixture/manifest.json"
}

@test "gws package uses pinned 0.22.5 release binaries" {
  local pkg="$PROJECT_ROOT/private_dot_config/nix-devshell/packages/gws.nix"
  local flake="$PROJECT_ROOT/private_dot_config/nix-devshell/flake.nix"
  local lock="$PROJECT_ROOT/private_dot_config/nix-devshell/flake.lock"

  grep -q 'version = "0.22.5";' "$pkg"
  grep -q 'google-workspace-cli-x86_64-unknown-linux-gnu.tar.gz' "$pkg"
  grep -q 'google-workspace-cli-aarch64-unknown-linux-gnu.tar.gz' "$pkg"
  grep -q 'google-workspace-cli-x86_64-apple-darwin.tar.gz' "$pkg"
  grep -q 'google-workspace-cli-aarch64-apple-darwin.tar.gz' "$pkg"
  grep -q 'sha256-3njs29LxqEzKAGOn7LxEAkD8FLbrzLsX9GRreSqMXB8=' "$pkg"
  grep -q 'sha256-lEkCldlYDh6IV05xWgoWKZF0fRLWL4x7jcyCaLbBzqA=' "$pkg"
  grep -q 'sha256-Ufm9cxQE1LuibDbi4w3WjFbczR+DTAElLLCxTWplRLI=' "$pkg"
  grep -q 'sha256-HSqf/VvJssLEtIYw2vCC+tE9nlfXQZiKLCSO7VYvfaw=' "$pkg"
  grep -q 'sourceRoot = "\.";' "$pkg"
  grep -q './packages/gws.nix' "$flake"
  ! grep -q 'github:googleworkspace/cli' "$flake"
  ! grep -q 'inputs\.gws-cli' "$flake"
  ! grep -q '"gws-cli"' "$lock"
}

@test "waza package uses pinned 0.38.3 release archives" {
  local pkg="$PROJECT_ROOT/private_dot_config/nix-devshell/packages/waza.nix"
  local flake="$PROJECT_ROOT/private_dot_config/nix-devshell/flake.nix"
  local module="$PROJECT_ROOT/private_dot_config/nix-devshell/modules/ai.nix"
  local lock="$PROJECT_ROOT/private_dot_config/nix-devshell/flake.lock"

  grep -q 'version = "0.38.3";' "$pkg"
  grep -q 'microsoft-azd-waza-linux-amd64.tar.gz' "$pkg"
  grep -q 'microsoft-azd-waza-linux-arm64.tar.gz' "$pkg"
  grep -q 'microsoft-azd-waza-darwin-amd64.zip' "$pkg"
  grep -q 'microsoft-azd-waza-darwin-arm64.zip' "$pkg"
  grep -q 'sha256-SQpv1e69ewDqHR/SGu6VEvBwkgGQI5B/JVl5eDNybBw=' "$pkg"
  grep -q 'sha256-mN77pOPChew0+9J12SvJLQEFFKM/OXZP/gMTJ1Rw5YM=' "$pkg"
  grep -q 'sha256-/Q3LRv6TLE2m3qmVxB+jiHAII3q7gN2/ghJuDQq6mTY=' "$pkg"
  grep -q 'sha256-0Qd/uLtwgahucqL5VXS8mG/FUzx0pMAz55TJXiV95bA=' "$pkg"
  ! grep -q 'unstable-2026-04-28' "$pkg"
  ! grep -q 'buildGoModule' "$pkg"
  ! grep -q 'waza-src' "$flake"
  ! grep -q 'waza-src' "$module"
  ! grep -q 'waza-src' "$lock"
}
