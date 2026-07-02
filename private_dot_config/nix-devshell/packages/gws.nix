{
  fetchurl,
  lib,
  stdenvNoCC,
}:

let
  inherit (stdenvNoCC.hostPlatform) system;

  releases = {
    x86_64-linux = {
      asset = "google-workspace-cli-x86_64-unknown-linux-gnu.tar.gz";
      hash = "sha256-3njs29LxqEzKAGOn7LxEAkD8FLbrzLsX9GRreSqMXB8=";
    };
    aarch64-linux = {
      asset = "google-workspace-cli-aarch64-unknown-linux-gnu.tar.gz";
      hash = "sha256-lEkCldlYDh6IV05xWgoWKZF0fRLWL4x7jcyCaLbBzqA=";
    };
    x86_64-darwin = {
      asset = "google-workspace-cli-x86_64-apple-darwin.tar.gz";
      hash = "sha256-Ufm9cxQE1LuibDbi4w3WjFbczR+DTAElLLCxTWplRLI=";
    };
    aarch64-darwin = {
      asset = "google-workspace-cli-aarch64-apple-darwin.tar.gz";
      hash = "sha256-HSqf/VvJssLEtIYw2vCC+tE9nlfXQZiKLCSO7VYvfaw=";
    };
  };

  release = releases.${system} or (throw "gws is not packaged for ${system}");
in
stdenvNoCC.mkDerivation (finalAttrs: {
  pname = "gws";
  version = "0.22.5";

  src = fetchurl {
    url = "https://github.com/googleworkspace/cli/releases/download/v${finalAttrs.version}/${release.asset}";
    inherit (release) hash;
  };

  sourceRoot = ".";

  installPhase = ''
    runHook preInstall

    bin=""
    for candidate in google-workspace-cli gws; do
      if [ -f "$candidate" ]; then
        bin="$candidate"
        break
      fi
    done
    install -Dm755 "$bin" "$out/bin/gws"

    runHook postInstall
  '';

  meta = {
    description = "One command-line tool for all Google Workspace APIs";
    homepage = "https://github.com/googleworkspace/cli";
    license = lib.licenses.asl20;
    mainProgram = "gws";
    platforms = builtins.attrNames releases;
  };
})
