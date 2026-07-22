{
  buildNpmPackage,
  lib,
  makeWrapper,
  nodejs,
  playwright-driver,
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

    makeWrapper ${nodejs}/bin/node "$out/bin/playwright-cli" \
      --set-default PWTEST_CLI_GLOBAL_CONFIG "$config_root" \
      --unset PLAYWRIGHT_BROWSERS_PATH \
      --unset PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD \
      --add-flags "$pkg/playwright-cli.js"

    mkdir -p "$out/share/playwright-cli/skills"
    cp -R "$pkg/skills/playwright-cli" "$out/share/playwright-cli/skills/playwright-cli"
  '';

  meta = {
    description = "Playwright Agent CLI with locally installable coding-agent skills";
    homepage = "https://playwright.dev/agent-cli/intro";
    license = lib.licenses.asl20;
    mainProgram = "playwright-cli";
    platforms = lib.platforms.unix;
  };
}
