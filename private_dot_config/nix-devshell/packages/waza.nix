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
      hash = "sha256-Fo41Yt7qoZWNRDZrN9ljtIsJHDJcbJtbJhPlOZ/wd7k=";
    };
    aarch64-linux = {
      asset = "waza-linux-arm64";
      hash = "sha256-q11qPlAqD39aSBSeA0+geHWi/gKt3d7GubnboU87RoU=";
    };
    x86_64-darwin = {
      asset = "waza-darwin-amd64";
      hash = "sha256-8qDGlSq7ta11vxfidpw0xIAJPCaVdIOTaLgtQLPF3sk=";
    };
    aarch64-darwin = {
      asset = "waza-darwin-arm64";
      hash = "sha256-mapDZrGY8xkUXP/u9C1QDrn2F4I1oFN9NMGd2PL0b+w=";
    };
  };

  release = releases.${system} or (throw "waza is not packaged for ${system}");
in
stdenvNoCC.mkDerivation (finalAttrs: {
  pname = "waza";
  version = "0.38.3";

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
