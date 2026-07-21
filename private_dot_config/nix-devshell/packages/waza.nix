{
  fetchurl,
  lib,
  stdenvNoCC,
  unzip,
}:

let
  inherit (stdenvNoCC.hostPlatform) system;

  releases = {
    x86_64-linux = {
      asset = "microsoft-azd-waza-linux-amd64.tar.gz";
      executable = "microsoft-azd-waza-linux-amd64";
      hash = "sha256-SQpv1e69ewDqHR/SGu6VEvBwkgGQI5B/JVl5eDNybBw=";
    };
    aarch64-linux = {
      asset = "microsoft-azd-waza-linux-arm64.tar.gz";
      executable = "microsoft-azd-waza-linux-arm64";
      hash = "sha256-mN77pOPChew0+9J12SvJLQEFFKM/OXZP/gMTJ1Rw5YM=";
    };
    x86_64-darwin = {
      asset = "microsoft-azd-waza-darwin-amd64.zip";
      executable = "microsoft-azd-waza-darwin-amd64";
      hash = "sha256-/Q3LRv6TLE2m3qmVxB+jiHAII3q7gN2/ghJuDQq6mTY=";
    };
    aarch64-darwin = {
      asset = "microsoft-azd-waza-darwin-arm64.zip";
      executable = "microsoft-azd-waza-darwin-arm64";
      hash = "sha256-0Qd/uLtwgahucqL5VXS8mG/FUzx0pMAz55TJXiV95bA=";
    };
  };

  release = releases.${system} or (throw "waza is not packaged for ${system}");
in
stdenvNoCC.mkDerivation (finalAttrs: {
  pname = "waza";
  version = "0.38.3";

  src = fetchurl {
    url = "https://github.com/microsoft/waza/releases/download/azd-ext-microsoft-azd-waza_${finalAttrs.version}/${release.asset}";
    inherit (release) hash;
  };

  nativeBuildInputs = lib.optional (lib.hasSuffix ".zip" release.asset) unzip;
  sourceRoot = ".";

  installPhase = ''
    runHook preInstall
    install -Dm755 "${release.executable}" "$out/bin/waza"
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
