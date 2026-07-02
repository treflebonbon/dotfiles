{
  buildNpmPackage,
  lib,
  makeWrapper,
  nodejs,
}:

buildNpmPackage {
  pname = "playwright-cli";
  version = "0.1.14";

  src = ./playwright-cli-agent;

  npmDepsHash = "sha256-W3lCMwnJgXS4HZ3U4D8VuhTkLHYe0XKGk4nfSSZ1Brk=";
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
