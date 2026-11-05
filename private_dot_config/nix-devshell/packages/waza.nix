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
      hash = "sha256-0JEXo8Yx9EoApsNiRiyVGu2DyHdR6MJfOZFqd9EBOAI=";
    };
    aarch64-linux = {
      asset = "waza-linux-arm64";
      hash = "sha256-Om0OHqWA77An1agcKPE+WINb9qZPUnD8OZsBE9ZxdRE=";
    };
    aarch64-darwin = {
      asset = "waza-darwin-arm64";
      hash = "sha256-oMzvkU7UGhk5TnoBtgV4z9N9PM4O86p4VzWsOfqIcrw=";
    };
  };

  release = releases.${system} or (throw "waza is not packaged for ${system}");
in
stdenvNoCC.mkDerivation (finalAttrs: {
  pname = "waza";
  version = "0.40.0";

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
