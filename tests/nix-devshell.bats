#!/usr/bin/env bats

setup() {
  PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  export XDG_CACHE_HOME="$BATS_TEST_TMPDIR/xdg-cache"
}

@test "nix-devshell includes bubblewrap for Codex sandboxing on Linux only" {
  local module="$PROJECT_ROOT/private_dot_config/nix-devshell/modules/ai.nix"

  grep -q 'lib\.optionals pkgs\.stdenv\.isLinux \[ pkgs\.bubblewrap \]' "$module"
}

@test "flakes support Linux and Apple Silicon without Intel Darwin" {
  local flakes=(
    "$PROJECT_ROOT/flake.nix"
    "$PROJECT_ROOT/private_dot_config/nix-devshell/flake.nix"
    "$PROJECT_ROOT/templates/go/flake.nix"
    "$PROJECT_ROOT/templates/rust/flake.nix"
    "$PROJECT_ROOT/templates/elixir/flake.nix"
    "$PROJECT_ROOT/templates/perl/flake.nix"
    "$PROJECT_ROOT/templates/gleam/flake.nix"
    "$PROJECT_ROOT/templates/bun/flake.nix"
  )

  for flake in "${flakes[@]}"; do
    grep -q '"x86_64-linux"' "$flake"
    grep -q '"aarch64-linux"' "$flake"
    grep -q '"aarch64-darwin"' "$flake"
    run grep -q '"x86_64-darwin"' "$flake"
    [ "$status" -ne 0 ]
  done

  grep -q 'nixpkgs-26\.05-darwin' "$PROJECT_ROOT/private_dot_config/nix-devshell/flake.nix"
  grep -q 'llm-agents\.overlays\.shared-nixpkgs' "$PROJECT_ROOT/private_dot_config/nix-devshell/flake.nix"
}

@test "user devShell selects the approved installed AI toolset snapshot without moving shared nixpkgs" {
  local flake="$PROJECT_ROOT/private_dot_config/nix-devshell/flake.nix"
  local lock="$PROJECT_ROOT/private_dot_config/nix-devshell/flake.lock"

  grep -q 'github:numtide/llm-agents\.nix/3c16acbe5229040ee8f4d6f7b85de757e14b4bda' "$flake"
  jq -e '.nodes[.nodes.root.inputs["llm-agents"]].locked.rev == "3c16acbe5229040ee8f4d6f7b85de757e14b4bda"' "$lock"
  jq -e '.nodes[.nodes.root.inputs["llm-agents"]].original.rev == "3c16acbe5229040ee8f4d6f7b85de757e14b4bda"' "$lock"
  jq -e '.nodes[.nodes.root.inputs.nixpkgs].locked.rev == "fca2dbd4c00c3063235e56bb91758e24fc67b7b8"' "$lock"
}

@test "project Codex launcher keeps supported auto-review escalation" {
  local package_json="$PROJECT_ROOT/package.json"

  jq -e '.scripts.codex == "codex --approve-for-me"' "$package_json"
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

@test "Linux user devShell installs WSL-aware xdg-open and sets BROWSER only on WSL" {
  local module="$PROJECT_ROOT/private_dot_config/nix-devshell/modules/shell.nix"
  local flake="$PROJECT_ROOT/private_dot_config/nix-devshell/flake.nix"
  local package="$PROJECT_ROOT/private_dot_config/nix-devshell/packages/wsl-xdg-open.nix"
  local wrapper="$PROJECT_ROOT/private_dot_config/nix-devshell/packages/wsl-xdg-open.sh"
  local powershell="$PROJECT_ROOT/private_dot_config/nix-devshell/packages/wsl-open-url.ps1"

  grep -q 'wslXdgOpen = pkgs.callPackage ./packages/wsl-xdg-open.nix' "$flake"
  grep -q 'wslXdgOpen' "$module"
  grep -q 'lib.optionals pkgs.stdenv.isLinux' "$module"
  grep -q 'export BROWSER=xdg-open' "$module"
  grep -q 'WSL_DISTRO_NAME' "$module"
  grep -q 'xdg-utils' "$package"
  grep -q '\[Hh\]\[Tt\]\[Tt\]\[Pp\]' "$wrapper"
  grep -q 'powershell.exe' "$wrapper"
  grep -q 'Start-Process -FilePath' "$powershell"
}

@test "Managed Dogfood Chrome rejects a zero DebugPort before launch" {
  local package="$PROJECT_ROOT/private_dot_config/nix-devshell/packages/dogfood-chrome-windows.ps1"

  grep -Fq 'if ($DebugPort -le 0)' "$package"
  grep -Fq 'Start requires a positive -DebugPort.' "$package"
}

@test "Managed Dogfood Chrome quotes Windows paths only when they contain whitespace" {
  local package="$PROJECT_ROOT/private_dot_config/nix-devshell/packages/dogfood-chrome-windows.ps1"

  grep -Fq 'function Format-ChromePathArgument' "$package"
  grep -Fq 'if ($Value -match "\s")' "$package"
  grep -Fq "\$escapedValue = \$Value -replace '(\\\\+)$', '\$1\$1'" "$package"
  grep -Fq "return ('\"' + \$escapedValue + '\"')" "$package"
  grep -Fq 'return $Value' "$package"
  grep -Fq '$ProfileArgument = Format-ChromePathArgument $ProfileDir' "$package"
  grep -Fq '"--user-data-dir=$ProfileArgument"' "$package"
  grep -Fq '$ExtensionArgument = Format-ChromePathArgument $ExtensionPath' "$package"
  grep -Fq '"--disable-extensions-except=$ExtensionArgument"' "$package"
  grep -Fq '"--load-extension=$ExtensionArgument"' "$package"
}

@test "Managed Dogfood Chrome doubles trailing backslashes in quoted paths" {
  local package="$PROJECT_ROOT/private_dot_config/nix-devshell/packages/dogfood-chrome-windows.ps1"

  grep -Fq "\$escapedValue = \$Value -replace '(\\\\+)$', '\$1\$1'" "$package"
  if ! command -v powershell.exe >/dev/null 2>&1; then
    skip "powershell.exe unavailable"
  fi

  local script="$BATS_TEST_TMPDIR/format-chrome-path.ps1"
  cat >"$script" <<'PS'
$Value = 'C:\Temp\profile with spaces\'
$escapedValue = $Value -replace '(\\+)$', '$1$1'
if (('"' + $escapedValue + '"') -ne '"C:\Temp\profile with spaces\\"') {
    exit 1
}
PS

  run powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "$script"
  [ "$status" -eq 0 ]
}

@test "WSL2 ADR keeps the CDP evidence record video-free" {
  local adr="$PROJECT_ROOT/docs/adr/0038-keep-wsl2-browser-free.md"

  grep -Fq 'screenshot / traceを生成し' "$adr"
  grep -Fq 'video-free契約のため、video artifactはこの経路の検証対象外' "$adr"
  ! grep -Fq 'screenshot / trace / video' "$adr"
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

@test "repo and user flakes expose a browser-free WSL output" {
  local repo_flake="$PROJECT_ROOT/flake.nix"
  local user_flake="$PROJECT_ROOT/private_dot_config/nix-devshell/flake.nix"
  local testing="$PROJECT_ROOT/private_dot_config/nix-devshell/modules/testing.nix"
  local ai="$PROJECT_ROOT/private_dot_config/nix-devshell/modules/ai.nix"
  local package="$PROJECT_ROOT/private_dot_config/nix-devshell/packages/playwright-cli.nix"
  local direnvrc="$PROJECT_ROOT/private_dot_config/direnv/direnvrc"
  local global_envrc="$PROJECT_ROOT/private_dot_config/nix-devshell/dot_envrc"

  grep -q 'wsl = pkgs.mkShell' "$repo_flake"
  grep -q 'wsl = makeShell true' "$user_flake"
  grep -q 'browserless ? false' "$ai"
  grep -q 'playwright-driver = if browserless then null' "$ai"
  grep -q 'lib.optionals (!browserless)' "$testing"
  grep -q 'playwright-driver ? null' "$package"
  grep -q 'dogfood-chrome-windows.ps1' "$package"
  grep -q '_df_select_wsl_flake_output' "$direnvrc"
  grep -q 'use flake .#wsl' "$global_envrc"
  [ -f "$PROJECT_ROOT/.wsl-browser-free" ]
}

@test "nix-devshell requires Claude Code with current workflow and permission fixes (issue #112)" {
  grep -q 'minClaudeCode = "2\.1\.239";' "$PROJECT_ROOT/private_dot_config/nix-devshell/modules/ai.nix"
}

@test "accepted AI toolset snapshot and selected payload source contract is pinned" {
  local adr="$PROJECT_ROOT/docs/adr/0043-update-llm-agents-and-impeccable-update-unit.md"
  local flake="$PROJECT_ROOT/private_dot_config/nix-devshell/flake.nix"
  local manifest="$PROJECT_ROOT/apm.yml"

  grep -q '^status: accepted$' "$adr"
  grep -Fq '3c16acbe5229040ee8f4d6f7b85de757e14b4bda' "$flake"
  grep -Fq 'GoogleChrome/modern-web-guidance/skills/modern-web-guidance#460e5536b8e61034d83ff4af24bb0bf1112d2cb0' "$manifest"
}

@test "nix-devshell uses the pinned Claude Code package without an Intel Darwin override" {
  local module="$PROJECT_ROOT/private_dot_config/nix-devshell/modules/ai.nix"
  local package="$PROJECT_ROOT/private_dot_config/nix-devshell/packages/claude-code-darwin-x64.nix"

  grep -q 'v = llm\.claude-code\.version or null;' "$module"
  grep -q '^    llm\.claude-code;$' "$module"
  run grep -q 'claudeCodeDarwinX64' "$module"
  [ "$status" -ne 0 ]
  run test -e "$package"
  [ "$status" -ne 0 ]
}

@test "nix-devshell requires Codex with executor-provided skill support" {
  local module="$PROJECT_ROOT/private_dot_config/nix-devshell/modules/ai.nix"

  grep -q 'minCodex = "0\.149\.0";' "$module"
  grep -q 'llm\.codex\.version' "$module"
  grep -q 'llm\.codex;' "$module"
}

@test "nix-devshell uses pinned Codex, Copilot, and Antigravity packages without Intel Darwin overrides" {
  local module="$PROJECT_ROOT/private_dot_config/nix-devshell/modules/ai.nix"

  grep -q '^    llm\.codex;$' "$module"
  grep -q '^    llm\.copilot-cli$' "$module"
  grep -q '^    llm\.antigravity-cli$' "$module"
  run grep -q 'x86_64-darwin' "$module"
  [ "$status" -ne 0 ]
}

@test "nix-devshell installs code-review-graph CLI without globally enabling it (issue #136)" {
  local module="$PROJECT_ROOT/private_dot_config/nix-devshell/modules/ai.nix"
  local codex_config="$PROJECT_ROOT/private_dot_config/codex/config.toml.tmpl"
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
  grep -q '"aarch64-darwin"' "$package"
  run grep -q '"x86_64-darwin"' "$package"
  [ "$status" -ne 0 ]

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
  grep -q 'DOGFOOD_WINDOWS_SCRIPT' "$module"
  grep -q '\.agents/skills/playwright-cli' "$module"
  grep -q '\.claude/skills/playwright-cli' "$module"
  grep -q 'pname = "playwright-cli";' "$pkg"
  grep -q '^  playwright-driver ? null,$' "$pkg"
  grep -q '^  util-linux,$' "$pkg"
  grep -Fq 'find -L ${playwright-driver.browsers}' "$pkg"
  grep -Fq 'Google Chrome for Testing.app/Contents/MacOS/Google Chrome for Testing' "$pkg"
  grep -q '"executablePath"' "$pkg"
  grep -q 'PWTEST_CLI_GLOBAL_CONFIG' "$pkg"
  grep -q -- '--unset PLAYWRIGHT_BROWSERS_PATH' "$pkg"
  grep -q -- '--unset PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD' "$pkg"
  grep -q 'playwright-cli-wrapper.sh' "$pkg"
  grep -q 'playwright-cli-windows.ps1' "$pkg"
  grep -q 'dogfood-chrome-windows.ps1' "$pkg"
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

@test "browser-free Playwright wrapper keeps makeWrapper flags in one shell command" {
  local expr
  local drv
  local post_install

  expr='
      let
        flake = builtins.getFlake (toString ./private_dot_config/nix-devshell);
        pkgs = import flake.inputs.nixpkgs.outPath {
          system = "x86_64-linux";
          config.allowUnfree = true;
          overlays = [ flake.inputs.llm-agents.overlays.shared-nixpkgs ];
        };
      in (pkgs.callPackage (flake.outPath + "/packages/playwright-cli.nix") {
        playwright-driver = null;
      }).drvPath
    '

  export XDG_CACHE_HOME="$BATS_TEST_TMPDIR/nix-cache"
  mkdir -p "$XDG_CACHE_HOME"
  run bash -c 'cd "$1" && nix eval --raw --impure --option use-xdg-base-directories true --expr "$2"' \
    _ "$PROJECT_ROOT" "$expr"
  [ "$status" -eq 0 ]
  drv="$output"

  run nix derivation show "$drv"
  [ "$status" -eq 0 ]
  post_install="$(jq -r 'if has("derivations") then .derivations else . end | to_entries[0].value.env.postInstall' <<<"$output")"

  awk '
    /playwright-cli-upstream"/ { found = 1; next }
    found && /--unset PLAYWRIGHT_BROWSERS_PATH/ { seen = 1; exit }
    found && /^[[:space:]]*$/ { blank = 1 }
    END { exit !(found && seen && !blank) }
  ' <<<"$post_install"
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
  grep -q 'google-workspace-cli-aarch64-apple-darwin.tar.gz' "$pkg"
  grep -q 'sha256-3njs29LxqEzKAGOn7LxEAkD8FLbrzLsX9GRreSqMXB8=' "$pkg"
  grep -q 'sha256-lEkCldlYDh6IV05xWgoWKZF0fRLWL4x7jcyCaLbBzqA=' "$pkg"
  grep -q 'sha256-HSqf/VvJssLEtIYw2vCC+tE9nlfXQZiKLCSO7VYvfaw=' "$pkg"
  run grep -q 'x86_64-apple-darwin' "$pkg"
  [ "$status" -ne 0 ]
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
  grep -q 'waza-darwin-arm64' "$pkg"
  grep -q 'sha256-mapDZrGY8xkUXP/u9C1QDrn2F4I1oFN9NMGd2PL0b+w=' "$pkg"
  grep -q 'sha256-Fo41Yt7qoZWNRDZrN9ljtIsJHDJcbJtbJhPlOZ/wd7k=' "$pkg"
  grep -q 'sha256-q11qPlAqD39aSBSeA0+geHWi/gKt3d7GubnboU87RoU=' "$pkg"
  run grep -q 'waza-darwin-amd64' "$pkg"
  [ "$status" -ne 0 ]
  grep -q 'releases/download/v\${finalAttrs.version}' "$pkg"
  grep -q 'dontUnpack = true' "$pkg"
  ! grep -q 'unstable-2026-04-28' "$pkg"
  ! grep -q 'buildGoModule' "$pkg"
  ! grep -q 'waza-src' "$flake"
  ! grep -q 'waza-src' "$module"
  ! grep -q 'waza-src' "$lock"
}
