{
  fetchurl,
  lib,
  stdenvNoCC,
}:

let
  inherit (stdenvNoCC.hostPlatform) system;
  releases = {
    x86_64-linux = {
      asset = "impeccable-linux-x64";
      hash = "sha256-0xe9G+Bh/ckCxN7ef98e/R93RIgvtRGh+WL83E7tU4I=";
    };
    aarch64-linux = {
      asset = "impeccable-linux-arm64";
      hash = "sha256-NO9WOWbLlcGzbEUO5ibHJyZnY1efxelamu8oC3SHUIA=";
    };
    aarch64-darwin = {
      asset = "impeccable-darwin-arm64";
      hash = "sha256-9cw5I6yT/p7AoBRJ6zuPA4WdrgioGVnkQVMzwEK8L4A=";
    };
  };
  release = releases.${system} or (throw "impeccable is not packaged for ${system}");
in
stdenvNoCC.mkDerivation (finalAttrs: {
  pname = "impeccable";
  version = "0.1.24";

  src = fetchurl {
    url = "https://github.com/pbakaus/impeccable/releases/download/engine-v${finalAttrs.version}/${release.asset}";
    inherit (release) hash;
  };

  dontUnpack = true;
  installPhase = ''
    runHook preInstall
    install -Dm755 "$src" "$out/bin/impeccable"
    runHook postInstall
  '';

  meta = {
    description = "Impeccable design engine for the APM-managed skill and hooks";
    homepage = "https://github.com/pbakaus/impeccable";
    license = lib.licenses.asl20;
    mainProgram = "impeccable";
    platforms = builtins.attrNames releases;
  };
})
