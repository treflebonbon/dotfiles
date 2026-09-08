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
      hash = "sha256-r8ekJOC9bGBre+THc8cOhyhK+9tB10jrmjT4pEeOV9o=";
    };
    aarch64-linux = {
      asset = "impeccable-linux-arm64";
      hash = "sha256-UjwKIjrAwVIkiXWan1bcywtFi0LWpcZudOb+IlWvYM4=";
    };
    aarch64-darwin = {
      asset = "impeccable-darwin-arm64";
      hash = "sha256-I4IRNdTGLxQo/RXduekdaVQCcn9DsTpus+nzH8AbQHI=";
    };
  };
  release = releases.${system} or (throw "impeccable is not packaged for ${system}");
in
stdenvNoCC.mkDerivation (finalAttrs: {
  pname = "impeccable";
  version = "0.1.3";

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
