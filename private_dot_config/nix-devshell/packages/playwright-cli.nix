{
  buildNpmPackage,
  curl,
  lib,
  makeWrapper,
  nodejs,
  playwright-driver,
  util-linux,
}:

buildNpmPackage {
  pname = "playwright-cli";
  version = "0.1.17";

  src = ./playwright-cli-agent;

  npmDepsHash = "sha256-btb24zLalfK6HII90+mH8TfiIo0c+OJZTwHUMl03Dv4=";
  dontNpmBuild = true;
  PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD = "1";

  nativeBuildInputs = [ makeWrapper ];

  postInstall = ''
    pkg="$out/lib/node_modules/playwright-cli-agent/node_modules/@playwright/cli"
    program="$pkg/../../playwright-core/lib/tools/cli-client/program.js"

    substituteInPlace "$program" \
      --replace-fail \
        'const toolText = await runInSessionOrStop(newEntry, clientInfo, { _: ["goto", ...params.length ? params : ["about:blank"]] }, output);' \
        'const toolText = await runInSessionOrStop(newEntry, clientInfo, { _: [process.env.PWTEST_CLI_MANAGED_CHROME === "1" ? "tab-new" : "goto", ...params.length ? params : ["about:blank"]] }, output);'

    chromium_executable="$(
      find -L ${playwright-driver.browsers} -type f \
        \( -path '*/chrome-linux*/chrome' \
        -o -path '*/Google Chrome for Testing.app/Contents/MacOS/Google Chrome for Testing' \
        -o -path '*/Chromium.app/Contents/MacOS/Chromium' \) \
        -print | head -n 1
    )"
    if [ -z "$chromium_executable" ]; then
      echo "Playwright Chromium executable not found in ${playwright-driver.browsers}" >&2
      exit 1
    fi

    config_root="$out/share/playwright-cli/config"
    mkdir -p "$config_root/.playwright"
    cat >"$config_root/.playwright/cli.config.json" <<EOF
    {
      "browser": {
        "browserName": "chromium",
        "launchOptions": {
          "executablePath": "$chromium_executable"
        }
      }
    }
    EOF

    mkdir -p "$out/bin" "$out/libexec" "$out/share/playwright-cli"

    makeWrapper ${nodejs}/bin/node "$out/libexec/playwright-cli-upstream" \
      --set-default PWTEST_CLI_GLOBAL_CONFIG "$config_root" \
      --unset PLAYWRIGHT_BROWSERS_PATH \
      --unset PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD \
      --add-flags "$pkg/playwright-cli.js"

    cp ${./playwright-cli-cdp-close.js} "$out/share/playwright-cli/cdp-close.js"
    makeWrapper ${nodejs}/bin/node "$out/libexec/playwright-cli-cdp-close" \
      --add-flags "$out/share/playwright-cli/cdp-close.js"

    cp ${./playwright-cli-windows.ps1} "$out/share/playwright-cli/windows.ps1"
    cp ${./playwright-cli-wrapper.sh} "$out/bin/playwright-cli"
    substituteInPlace "$out/bin/playwright-cli" \
      --replace-fail '@playwrightCliUpstream@' "$out/libexec/playwright-cli-upstream" \
      --replace-fail '@curl@' '${curl}' \
      --replace-fail '@cdpClose@' "$out/libexec/playwright-cli-cdp-close" \
      --replace-fail '@windowsScript@' "$out/share/playwright-cli/windows.ps1" \
      --replace-fail '@flock@' '${util-linux}/bin/flock'
    chmod +x "$out/bin/playwright-cli"

    mkdir -p "$out/share/playwright-cli/skills"
    cp -R "$pkg/skills/playwright-cli" "$out/share/playwright-cli/skills/playwright-cli"
    printf '\n' >>"$out/share/playwright-cli/skills/playwright-cli/SKILL.md"
    cat ${./playwright-cli-wsl-skill.md} \
      >>"$out/share/playwright-cli/skills/playwright-cli/SKILL.md"
  '';

  meta = {
    description = "Playwright Agent CLI with locally installable coding-agent skills";
    homepage = "https://playwright.dev/agent-cli/intro";
    license = lib.licenses.asl20;
    mainProgram = "playwright-cli";
    platforms = lib.platforms.unix;
  };
}
