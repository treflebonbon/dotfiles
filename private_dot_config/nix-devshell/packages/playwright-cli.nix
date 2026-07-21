{
  buildNpmPackage,
  lib,
  makeWrapper,
  nodejs,
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

    makeWrapper ${nodejs}/bin/node "$out/bin/playwright-cli" \
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
