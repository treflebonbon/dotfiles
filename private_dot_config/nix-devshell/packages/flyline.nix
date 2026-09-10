{
  fetchurl,
  lib,
  stdenvNoCC,
}:

let
  inherit (stdenvNoCC.hostPlatform) system;

  releases = {
    x86_64-linux = {
      asset = "libflyline-v${version}-x86_64-unknown-linux-gnu.tar.gz";
      hash = "sha256-/xg03kdJriRUg4jrsFTP4tGFcJP5d2jsVWfVjuScJFs=";
    };
    aarch64-linux = {
      asset = "libflyline-v${version}-aarch64-unknown-linux-gnu.tar.gz";
      hash = "sha256-4HlW0PSS2maC81u1UJZi2b3VQIpXTFYLUghPq8BEmkY=";
    };
  };

  version = "1.8.0";
  release = releases.${system} or (throw "flyline is not packaged for ${system}");
in
stdenvNoCC.mkDerivation {
  pname = "flyline";
  inherit version;

  src = fetchurl {
    url = "https://github.com/HalFrgrd/flyline/releases/download/v${version}/${release.asset}";
    inherit (release) hash;
  };

  sourceRoot = ".";

  installPhase = ''
    runHook preInstall

    install -Dm755 "libflyline.so.${version}" "$out/lib/libflyline.so.${version}"
    ln -s "libflyline.so.${version}" "$out/lib/libflyline.so"

    runHook postInstall
  '';

  meta = {
    description = "Bash loadable line editor with syntax highlighting and fuzzy history";
    homepage = "https://github.com/HalFrgrd/flyline";
    license = lib.licenses.gpl3Only;
    platforms = builtins.attrNames releases;
  };
}
