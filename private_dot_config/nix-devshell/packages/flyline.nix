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
      hash = "sha256-QLMMiKq8i68j5Uevn/0ziMv6SwRN8atT8rqZema/Q2o=";
    };
    aarch64-linux = {
      asset = "libflyline-v${version}-aarch64-unknown-linux-gnu.tar.gz";
      hash = "sha256-S9SYgFdNerVwD+5Xm3Ex/Hyq5GjTbTkeKYbLNw0aeBY=";
    };
  };

  version = "1.11.0";
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
