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
      hash = "sha256-c27XhedK4jRNMDYSf2FN3eWrUgpSfYvIKokWEu9x9kg=";
    };
    aarch64-linux = {
      asset = "impeccable-linux-arm64";
      hash = "sha256-MXyxjWSw93FWgd1uV0rWSyrbWmyvjnobO1eWX4BUBL4=";
    };
    aarch64-darwin = {
      asset = "impeccable-darwin-arm64";
      hash = "sha256-VD7i9yA2rRhdyZkaw7qGt02R+Yjz1Jd3agiLi2XIqeE=";
    };
  };
  release = releases.${system} or (throw "impeccable is not packaged for ${system}");
in
stdenvNoCC.mkDerivation (finalAttrs: {
  pname = "impeccable";
  version = "0.1.18";

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
