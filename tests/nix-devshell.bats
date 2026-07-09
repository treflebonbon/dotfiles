#!/usr/bin/env bats

setup() {
  PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
}

@test "nix-devshell includes bubblewrap for Codex sandboxing" {
  grep -q 'pkgs\.bubblewrap' "$PROJECT_ROOT/private_dot_config/nix-devshell/modules/ai.nix"
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

@test "nix-devshell requires Claude Code with goal support" {
  grep -q 'minClaudeCode = "2\.1\.204";' "$PROJECT_ROOT/private_dot_config/nix-devshell/modules/ai.nix"
}

@test "nix-devshell includes Google Antigravity CLI" {
  grep -q 'llm\.antigravity' "$PROJECT_ROOT/private_dot_config/nix-devshell/modules/ai.nix"
}

@test "nix-devshell installs playwright-cli and local skill symlinks" {
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
  grep -q '"@playwright/cli": "0.1.14"' "$package_json"
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

@test "waza package uses pinned 0.33.0 release binaries" {
  local pkg="$PROJECT_ROOT/private_dot_config/nix-devshell/packages/waza.nix"
  local flake="$PROJECT_ROOT/private_dot_config/nix-devshell/flake.nix"
  local module="$PROJECT_ROOT/private_dot_config/nix-devshell/modules/ai.nix"
  local lock="$PROJECT_ROOT/private_dot_config/nix-devshell/flake.lock"

  grep -q 'version = "0.33.0";' "$pkg"
  grep -q 'waza-linux-amd64' "$pkg"
  grep -q 'waza-linux-arm64' "$pkg"
  grep -q 'waza-darwin-amd64' "$pkg"
  grep -q 'waza-darwin-arm64' "$pkg"
  grep -q 'sha256-waMaFdlZ0s1Tb+tBz3sg+UsENKjoaUnT3j0hweP7b/M=' "$pkg"
  ! grep -q 'unstable-2026-04-28' "$pkg"
  ! grep -q 'buildGoModule' "$pkg"
  ! grep -q 'waza-src' "$flake"
  ! grep -q 'waza-src' "$module"
  ! grep -q 'waza-src' "$lock"
}
