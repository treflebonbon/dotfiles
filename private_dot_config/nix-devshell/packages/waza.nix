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
      hash = "sha256-RMJgdeFZuNnnJTyeReR9JGjAn4GAuN6NUitPr3N2elw=";
    };
    aarch64-linux = {
      asset = "waza-linux-arm64";
      hash = "sha256-cZKcv8IPooQWHfCsllxJRmTHx4l+qFRg2vaNeLF4Qr8=";
    };
    aarch64-darwin = {
      asset = "waza-darwin-arm64";
      hash = "sha256-9hLrk3OLQs3r3w3cB9L+nzmmro4qR40Jt8lv7b97bSY=";
    };
  };

  release = releases.${system} or (throw "waza is not packaged for ${system}");
in
stdenvNoCC.mkDerivation (finalAttrs: {
  pname = "waza";
  version = "0.40.1";

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
