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
      hash = "sha256-nHOX2NKBJ9fJnsatH6tzDL1DgXSjlgr7yCw6YNrMy3Q=";
    };
    aarch64-linux = {
      asset = "waza-linux-arm64";
      hash = "sha256-pkN/RofXDzs/1DhjnUs8dU3EeOaSdnq9Ome6qHNPBIc=";
    };
    aarch64-darwin = {
      asset = "waza-darwin-arm64";
      hash = "sha256-jqI49tU5wjphFs1ZcQB180H/swXFZ0w0y055mNNFmr0=";
    };
  };

  release = releases.${system} or (throw "waza is not packaged for ${system}");
in
stdenvNoCC.mkDerivation (finalAttrs: {
  pname = "waza";
  version = "0.41.0";

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
