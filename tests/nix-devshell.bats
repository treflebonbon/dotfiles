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

@test "user devShell selects the approved installed AI toolset snapshot without moving shared nixpkgs" {
  local flake="$PROJECT_ROOT/private_dot_config/nix-devshell/flake.nix"
  local lock="$PROJECT_ROOT/private_dot_config/nix-devshell/flake.lock"

  grep -q 'github:numtide/llm-agents\.nix/efa77d0fc9553758c11ddd22274cb39018aabd48' "$flake"
  jq -e '.nodes[.nodes.root.inputs["llm-agents"]].locked.rev == "efa77d0fc9553758c11ddd22274cb39018aabd48"' "$lock"
  jq -e '.nodes[.nodes.root.inputs["llm-agents"]].original.rev == "efa77d0fc9553758c11ddd22274cb39018aabd48"' "$lock"
  jq -e '.nodes[.nodes.root.inputs.nixpkgs].locked.rev == "fca2dbd4c00c3063235e56bb91758e24fc67b7b8"' "$lock"
}

@test "project Codex launcher keeps supported auto-review escalation" {
  local package_json="$PROJECT_ROOT/package.json"

  jq -e '.scripts.codex == "codex --ask-for-approval on-request -c approvals_reviewer=auto_review"' "$package_json"
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

@test "nix-devshell requires Claude Code with current workflow and permission fixes (issue #112)" {
  grep -q 'minClaudeCode = "2\.1\.222";' "$PROJECT_ROOT/private_dot_config/nix-devshell/modules/ai.nix"
}

@test "nix-devshell restores x86_64-darwin claude-code locally after upstream dropped it (issue #112)" {
  local module="$PROJECT_ROOT/private_dot_config/nix-devshell/modules/ai.nix"
  local package="$PROJECT_ROOT/private_dot_config/nix-devshell/packages/claude-code-darwin-x64.nix"

  grep -q 'claudeCodeDarwinX64 = pkgs\.callPackage \.\./packages/claude-code-darwin-x64\.nix { };' "$module"
  grep -q 'selected =' "$module"
  grep -q 'if pkgs\.stdenv\.hostPlatform\.system == "x86_64-darwin" then claudeCodeDarwinX64 else llm\.claude-code;' "$module"
  test -f "$package"
  # この version は minClaudeCode ではなく flake pin 上の claude-code に追従する。
  # 床は根拠のある release でしか上げないため、床据え置きのまま pin だけ進む回があり、
  # そこで両者はずれる。床に合わせると x86_64-darwin だけ旧版で取り残されたまま
  # assert が通ってしまう（ADR-0028 の補足を参照）。
  grep -q 'version = "2\.1\.222";' "$package"
  grep -Fq 'sha256-Nr/GSColcw27HO5yWJ5SLGbEWk3J6/3Yp2qBE7AbYYg=' "$package"
}

@test "nix-devshell requires Codex with executor-provided skill support" {
  local module="$PROJECT_ROOT/private_dot_config/nix-devshell/modules/ai.nix"

  grep -q 'minCodex = "0\.146\.1";' "$module"
  grep -q 'llm\.codex\.version' "$module"
  grep -q 'llm\.codex;' "$module"
}

@test "nix-devshell restores x86_64-darwin codex/copilot-cli/antigravity-cli locally after the same llm-agents pin bump dropped them" {
  local module="$PROJECT_ROOT/private_dot_config/nix-devshell/modules/ai.nix"

  grep -q 'llm\.codex\.override' "$module"
  grep -q 'llm\.codex\.mkRustyV8Archive' "$module"
  grep -q 'copilotCli =' "$module"
  grep -q 'llm\.copilot-cli\.overrideAttrs' "$module"
  grep -q 'antigravityCli =' "$module"
  grep -q 'llm\.antigravity-cli\.overrideAttrs' "$module"
  grep -Fq 'sha256-C4sEKT69kDzgzbtyzSZwiiKoXxkpPzk/wcTOXaN2Eyk=' "$module"
  grep -Fq 'url = "https://storage.googleapis.com/antigravity-public/antigravity-cli/${old.version}-6423386432339968/darwin-x64/cli_mac_x64.tar.gz";' "$module"
  grep -Fq 'sha512-DtlRl+psUD5g/J9l0DUvznM7PW9bihba6XG/6Rf+mEzH2srI/rArpxq2rauln5nx/3QH+V67yvj+wwQH0+j7sA==' "$module"
  grep -q '^    copilotCli$' "$module"
  grep -q '^    antigravityCli$' "$module"
  ! grep -q '^    llm\.copilot-cli$' "$module"
  ! grep -q '^    llm\.antigravity-cli$' "$module"
}

@test "nix-devshell installs code-review-graph CLI without globally enabling it (issue #136)" {
  local module="$PROJECT_ROOT/private_dot_config/nix-devshell/modules/ai.nix"
  local codex_config="$PROJECT_ROOT/private_dot_config/codex/config.toml"
  local claude_mcp="$PROJECT_ROOT/private_dot_mcp.json"
  local runtime="$PROJECT_ROOT/runtime/ai-runtimes.md"

  grep -q 'codeReviewGraph = pkgs\.callPackage \.\./packages/code-review-graph\.nix' "$module"
  grep -q '^    codeReviewGraph$' "$module"
  ! grep -q '\[mcp_servers\.code-review-graph\]' "$codex_config"
  ! grep -q 'code-review-graph' "$claude_mcp"
  grep -q 'リポジトリ単位の code-review-graph opt-in' "$runtime"
  grep -q 'code-review-graph install.*実行しない' "$runtime"
}

@test "code-review-graph package meets its FastMCP floor on all supported systems (issue #136)" {
  local package="$PROJECT_ROOT/private_dot_config/nix-devshell/packages/code-review-graph.nix"
  local language_pack="$PROJECT_ROOT/private_dot_config/nix-devshell/packages/tree-sitter-language-pack-0_13.nix"
  local flake="$PROJECT_ROOT/private_dot_config/nix-devshell"

  grep -q 'minFastMcp = "3\.2\.4";' "$package"
  grep -q 'nixpkgs-ai-sources.*fastmcp/default\.nix' "$package"
  grep -q 'lib\.versionAtLeast python\.pkgs\.fastmcp\.version minFastMcp' "$package"
  grep -q 'tree-sitter-language-pack-0_13\.nix' "$package"
  grep -q 'version = "0\.13\.0";' "$language_pack"
  grep -Fq 'sha256-AyA0xeJ7H24AcwuefC28ggO0cA0MaB/QGdbe/PYRg+w=' "$language_pack"
  grep -q '"x86_64-linux"' "$package"
  grep -q '"aarch64-linux"' "$package"
  grep -q '"x86_64-darwin"' "$package"
  grep -q '"aarch64-darwin"' "$package"

  run nix flake check --no-build --all-systems "path:$flake"
  [ "$status" -eq 0 ]

  if [ "$(uname -s)" = "Linux" ]; then
    local probe="$BATS_TEST_TMPDIR/code-review-graph-probe"
    mkdir -p "$probe"
    git -C "$probe" init -q
    printf 'def answer():\n    return 42\n' >"$probe/sample.py"
    git -C "$probe" add sample.py

    run nix develop "path:$flake" --command code-review-graph --help
    [ "$status" -eq 0 ]

    run nix develop "path:$flake" --command bash -c 'cd "$1" && code-review-graph build' _ "$probe"
    [ "$status" -eq 0 ]
    [ -f "$probe/.code-review-graph/graph.db" ]
  fi
}

@test "nix-devshell installs Playwright CLI 0.1.17 with managed WSL2 Chrome and local skill symlinks" {
  local module="$PROJECT_ROOT/private_dot_config/nix-devshell/modules/ai.nix"
  local pkg="$PROJECT_ROOT/private_dot_config/nix-devshell/packages/playwright-cli.nix"
  local package_json="$PROJECT_ROOT/private_dot_config/nix-devshell/packages/playwright-cli-agent/package.json"
  local wrapper="$PROJECT_ROOT/private_dot_config/nix-devshell/packages/playwright-cli-wrapper.sh"
  local windows="$PROJECT_ROOT/private_dot_config/nix-devshell/packages/playwright-cli-windows.ps1"
  local skill="$PROJECT_ROOT/private_dot_config/nix-devshell/packages/playwright-cli-wsl-skill.md"

  grep -q 'playwright-cli = pkgs.callPackage ../packages/playwright-cli.nix' "$module"
  grep -q '^    playwright-cli$' "$module"
  grep -q 'share/playwright-cli/skills/playwright-cli' "$module"
  grep -q '\.agents/skills/playwright-cli' "$module"
  grep -q '\.claude/skills/playwright-cli' "$module"
  grep -q 'pname = "playwright-cli";' "$pkg"
  grep -q '^  playwright-driver,$' "$pkg"
  grep -q '^  util-linux,$' "$pkg"
  grep -Fq 'find -L ${playwright-driver.browsers}' "$pkg"
  grep -Fq 'Google Chrome for Testing.app/Contents/MacOS/Google Chrome for Testing' "$pkg"
  grep -q '"executablePath"' "$pkg"
  grep -q 'PWTEST_CLI_GLOBAL_CONFIG' "$pkg"
  grep -q -- '--unset PLAYWRIGHT_BROWSERS_PATH' "$pkg"
  grep -q -- '--unset PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD' "$pkg"
  grep -q 'playwright-cli-wrapper.sh' "$pkg"
  grep -q 'playwright-cli-windows.ps1' "$pkg"
  grep -q 'playwright-cli-cdp-close.js' "$pkg"
  grep -q 'PWTEST_CLI_MANAGED_CHROME' "$pkg"
  grep -q 'playwright-cli-wsl-skill.md' "$pkg"
  grep -Fq '127.0.0.1:9222' "$wrapper"
  grep -Fq '127.0.0.1:9323' "$wrapper"
  grep -Fq 'aiakos\playwright-cli\chrome-profile' "$windows"
  grep -Fq '$ProfileDir =' "$windows"
  ! grep -Fq '$Profile =' "$windows"
  grep -Fq 'PWTEST_CLI_GLOBAL_CONFIG' "$skill"
  ! grep -Eq 'chromium-[0-9]+' "$pkg"
  grep -q 'version = "0.1.17";' "$pkg"
  grep -q '"@playwright/cli": "0.1.17"' "$package_json"
}

@test "WSL2 Playwright skill documents managed headless and headed workflows" {
  local skill="$PROJECT_ROOT/private_dot_config/nix-devshell/packages/playwright-cli-wsl-skill.md"

  grep -Fq 'headless by default' "$skill"
  grep -Fq '`open --headed`' "$skill"
  grep -Fq '`PLAYWRIGHT_MCP_HEADLESS=true|1`' "$skill"
  grep -Fq '`PLAYWRIGHT_MCP_HEADLESS=false|0`' "$skill"
  grep -Fq '`show` and `show --annotate` require headed mode' "$skill"
  grep -Fq 'manual authentication' "$skill"
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

@test "waza package uses pinned 0.38.3 standalone release binaries" {
  local pkg="$PROJECT_ROOT/private_dot_config/nix-devshell/packages/waza.nix"
  local flake="$PROJECT_ROOT/private_dot_config/nix-devshell/flake.nix"
  local module="$PROJECT_ROOT/private_dot_config/nix-devshell/modules/ai.nix"
  local lock="$PROJECT_ROOT/private_dot_config/nix-devshell/flake.lock"

  grep -q 'version = "0.38.3";' "$pkg"
  grep -q 'waza-linux-amd64' "$pkg"
  grep -q 'waza-linux-arm64' "$pkg"
  grep -q 'waza-darwin-amd64' "$pkg"
  grep -q 'waza-darwin-arm64' "$pkg"
  grep -q 'sha256-8qDGlSq7ta11vxfidpw0xIAJPCaVdIOTaLgtQLPF3sk=' "$pkg"
  grep -q 'sha256-mapDZrGY8xkUXP/u9C1QDrn2F4I1oFN9NMGd2PL0b+w=' "$pkg"
  grep -q 'sha256-Fo41Yt7qoZWNRDZrN9ljtIsJHDJcbJtbJhPlOZ/wd7k=' "$pkg"
  grep -q 'sha256-q11qPlAqD39aSBSeA0+geHWi/gKt3d7GubnboU87RoU=' "$pkg"
  grep -q 'releases/download/v\${finalAttrs.version}' "$pkg"
  grep -q 'dontUnpack = true' "$pkg"
  ! grep -q 'unstable-2026-04-28' "$pkg"
  ! grep -q 'buildGoModule' "$pkg"
  ! grep -q 'waza-src' "$flake"
  ! grep -q 'waza-src' "$module"
  ! grep -q 'waza-src' "$lock"
}
