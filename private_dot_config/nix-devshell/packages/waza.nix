{
  fetchurl,
  lib,
  stdenvNoCC,
}:

let
  inherit (stdenvNoCC.hostPlatform) system;

  releases = {
    x86_64-linux = {
      asset = "waza-linux-amd64";
      hash = "sha256-4ifNiEFz3nlrwoxssYKEmPJQKX4OYGpORQTRRGX/h58=";
    };
    aarch64-linux = {
      asset = "waza-linux-arm64";
      hash = "sha256-FC6oNrvIMkFU9S0yeMt8mp+k4b50gLRNOEEwm1b3sDk=";
    };
    aarch64-darwin = {
      asset = "waza-darwin-arm64";
      hash = "sha256-gqT0TH2VsT5UYHqwu52mGLsTTFHJSmS+c77b97zU53g=";
    };
  };

  release = releases.${system} or (throw "waza is not packaged for ${system}");
in
stdenvNoCC.mkDerivation (finalAttrs: {
  pname = "waza";
  version = "0.38.7";

  src = fetchurl {
    url = "https://github.com/microsoft/waza/releases/download/v${finalAttrs.version}/${release.asset}";
    inherit (release) hash;
  };

  dontUnpack = true;

  installPhase = ''
    runHook preInstall
    install -Dm755 "$src" "$out/bin/waza"
    runHook postInstall
  '';

  meta = {
    description = "AI agent skills evaluation framework";
    homepage = "https://github.com/microsoft/waza";
    license = lib.licenses.mit;
    mainProgram = "waza";
    platforms = builtins.attrNames releases;
  };
})
