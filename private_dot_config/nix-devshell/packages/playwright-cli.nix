{
  buildNpmPackage,
  coreutils,
  curl,
  git,
  lib,
  makeWrapper,
  nodejs,
  playwright-driver ? null,
  skillsPluginSource,
  util-linux,
}:

let
  browserPackage = "${skillsPluginSource}/packages/wsl2-browser";
in
buildNpmPackage {
  pname = "playwright-cli";
  version = "0.1.22";

  src = ./playwright-cli-agent;

  npmDepsHash = "sha256-Jiy7hSv23PenWcQcX5rd6oyEiMV0nW7FatfhAxj5Sdw=";
  dontNpmBuild = true;
  PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD = "1";

  nativeBuildInputs = [ makeWrapper ];

  postInstall = ''
    public="${browserPackage}"
    pkg="$out/lib/node_modules/playwright-cli-agent/node_modules/@playwright/cli"
    core="$pkg/../../playwright-core"
    program="$core/lib/tools/cli-client/program.js"

    patch --directory="$core" -p1 < "$public/libexec/playwright-cli-sockets.patch"
    cp "$public/libexec/playwright-cli-sockets.cjs" "$core/lib/playwright-cli-sockets.cjs"
    program_before="$(awk '/^--- / || /^\+\+\+ / { next } /^-/ { print substr($0, 2); exit }' \
      "$public/libexec/playwright-cli-program.patch")"
    program_after="$(awk '/^--- / || /^\+\+\+ / { next } /^\+/ { print substr($0, 2); exit }' \
      "$public/libexec/playwright-cli-program.patch")"
    program_before_count="$(awk '/^--- / || /^\+\+\+ / { next } /^-/ { count++ } END { print count + 0 }' \
      "$public/libexec/playwright-cli-program.patch")"
    program_after_count="$(awk '/^--- / || /^\+\+\+ / { next } /^\+/ { count++ } END { print count + 0 }' \
      "$public/libexec/playwright-cli-program.patch")"
    if [[ "$program_before_count" != 1 || "$program_after_count" != 1 || \
      -z "$program_before" || -z "$program_after" ]]; then
      echo "Playwright program patch must contain one non-empty replacement." >&2
      exit 1
    fi
    substituteInPlace "$program" --replace-fail "$program_before" "$program_after"

    ${lib.optionalString (playwright-driver != null) ''
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
    ''}

    mkdir -p \
      "$out/bin" \
      "$out/libexec" \
      "$out/share/licenses/playwright-cli" \
      "$out/share/playwright-cli/references" \
      "$out/share/playwright-cli/skills"
    cp -R "$public/libexec/." "$out/libexec/"
    cp "$public/bin/playwright-cli" "$out/libexec/playwright-cli-entrypoint"
    cp "$public/bin/browser-attachments" "$out/libexec/browser-attachments-entrypoint"
    cp "$public/references/playwright-cli-wsl.md" \
      "$out/share/playwright-cli/references/playwright-cli-wsl.md"
    cp "${skillsPluginSource}/LICENSE" "$out/share/licenses/playwright-cli/LICENSE"
    cp "$public/THIRD_PARTY_NOTICES.md" \
      "$out/share/licenses/playwright-cli/THIRD_PARTY_NOTICES.md"
    for asset in "$public"/libexec/*; do
      asset_name="$(basename "$asset")"
      ln -s "../../libexec/$asset_name" "$out/share/playwright-cli/$asset_name"
    done
    ln -s ../../libexec/playwright-cli-cdp-close.js "$out/share/playwright-cli/cdp-close.js"

    makeWrapper ${nodejs}/bin/node "$out/libexec/playwright-cli-upstream" \
      ${
        lib.optionalString (
          playwright-driver != null
        ) ''--set-default PWTEST_CLI_GLOBAL_CONFIG "$config_root"''
      } \
      --unset PLAYWRIGHT_BROWSERS_PATH \
      --unset PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD \
      --add-flags "$pkg/playwright-cli.js"

    makeWrapper ${nodejs}/bin/node "$out/libexec/playwright-cli-cdp-close" \
      --add-flags "$out/libexec/playwright-cli-cdp-close.js"
    makeWrapper ${nodejs}/bin/node "$out/libexec/playwright-runtime" \
      --add-flags "$out/libexec/playwright-runtime.mjs"
    makeWrapper ${nodejs}/bin/node "$out/bin/managed-chrome-owner" \
      --set-default MANAGED_CHROME_FLOCK '${util-linux}/bin/flock' \
      --add-flags "$out/libexec/managed-chrome-owner.mjs"

    makeWrapper "$out/libexec/playwright-cli-entrypoint" "$out/bin/playwright-cli" \
      --set-default PWCLI_UPSTREAM "$out/libexec/playwright-cli-upstream" \
      --set-default PWCLI_CDP_CLOSE "$out/libexec/playwright-cli-cdp-close" \
      --set-default PWCLI_WINDOWS_SCRIPT "$out/libexec/playwright-cli-windows.ps1" \
      --set-default MANAGED_CHROME_OWNER "$out/bin/managed-chrome-owner" \
      --set-default PWCLI_RUNTIME_COMMAND "$out/libexec/playwright-runtime" \
      --set-default PWCLI_CURL '${curl}/bin/curl' \
      --set-default PWCLI_FLOCK '${util-linux}/bin/flock' \
      --prefix PATH : ${
        lib.makeBinPath [
          coreutils
          git
          nodejs
          util-linux
        ]
      }

    makeWrapper "$out/libexec/browser-attachments-entrypoint" "$out/bin/browser-attachments" \
      --set-default MANAGED_CHROME_OWNER "$out/bin/managed-chrome-owner" \
      --set-default PWCLI_WINDOWS_SCRIPT "$out/libexec/playwright-cli-windows.ps1" \
      --set-default DOGFOOD_WINDOWS_SCRIPT "$out/libexec/dogfood-chrome-windows.ps1" \
      --set-default MANAGED_CHROME_FLOCK '${util-linux}/bin/flock' \
      --set-default BROWSER_ATTACHMENTS_PLAYWRIGHT "$pkg/../../playwright-core/index.mjs" \
      --prefix PATH : ${
        lib.makeBinPath [
          coreutils
          curl
          git
          nodejs
          util-linux
        ]
      }

    cp -R "$pkg/skills/playwright-cli" "$out/share/playwright-cli/skills/playwright-cli"
    printf '\n' >>"$out/share/playwright-cli/skills/playwright-cli/SKILL.md"
    cat "$public/references/playwright-cli-wsl.md" \
      >>"$out/share/playwright-cli/skills/playwright-cli/SKILL.md"
  '';

  meta = {
    description = "Playwright Agent CLI with locally installable coding-agent skills";
    homepage = "https://playwright.dev/agent-cli/intro";
    license = [
      lib.licenses.asl20
      lib.licenses.mit
    ];
    mainProgram = "playwright-cli";
    platforms = lib.platforms.unix;
  };
}
