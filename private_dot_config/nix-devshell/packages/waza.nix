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
      hash = "sha256-mGXOUQgNAF402zQ72i1jKA3oZKMPmpXWyYa/Amk1tA8=";
    };
    aarch64-linux = {
      asset = "waza-linux-arm64";
      hash = "sha256-x5kUSxbR2+uzzQZVAaMgUXoim/kPI6ks3hljNEhmZkc=";
    };
    aarch64-darwin = {
      asset = "waza-darwin-arm64";
      hash = "sha256-S/l6/xhnU7lFrBb3EBriK+eR5bTNBA2taaO4ghHBz+k=";
    };
  };

  release = releases.${system} or (throw "waza is not packaged for ${system}");
in
stdenvNoCC.mkDerivation (finalAttrs: {
  pname = "waza";
  version = "0.42.0";

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
